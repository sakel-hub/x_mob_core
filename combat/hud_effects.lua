--[[
	x_mob_core - Centralized HUD Status Screen Vignette Subsystem
	Responsive fullscreen viewport overlay rendering, multi-effect texture
	compositing, and 3rd-party extensible vignette registry.

	Conforms to S.O.L.I.D. architecture:
	- Single Responsibility: Handles exclusively client-side HUD vignette lifecycle & scaling
	- Open/Closed: Extensible via register_vignette and set_default_vignette without core changes
	- Dependency Inversion: status_effects delegates to hud_effects abstraction

	Author: SaKeL
	License: MIT
]]

---@class VignetteConfig
---@field texture? string Custom texture or procedural texture modifier
---@field color? string Hex color string (e.g. "#8A2BE240" or "#FF450050")
---@field opacity? integer Opacity value 0-255
---@field z_index? integer Optional z-index override (default: -10)

---@class HudEffectsSubsystem
local hud_effects = {}

local DEFAULT_BASE_TEXTURE = "x_mob_core_vignette.png"

--- Global settings cache
local vignettes_enabled = core.settings:get_bool("x_mob_core_enable_hud_vignettes", true)
local raw_multiplier = core.settings.get and core.settings:get("x_mob_core_hud_vignette_opacity_multiplier")
local vignette_multiplier = tonumber(raw_multiplier) or 1.0

--- 3rd-party custom vignette preset registry
--- Key: effect_id string -> VignetteConfig
--- Pre-populated with balanced filmic defaults for all canonical status effects.
--- Calibrated for prominent visibility and rich contrast even against bright daylight.
---@type table<string, VignetteConfig>
local registered_vignettes = {
	venom = { color = "#1b8822d0" },
	web = { color = "#ffffffb8" },
	frost = { color = "#55ccffc0" },
	nature_roots = { color = "#2e5a1ec0" },
	ignite = { color = "#ff4500c8" },
	crystallize = { color = "#88ffffc4" },
	earth_anchor = { color = "#4a3219cc" },
	void_miasma = { color = "#2d004dc8" },
	bone_shackles = { color = "#ddddddcc" },
	waterlogged = { color = "#003366c8" },
	concussion = { color = "#ffffffa8" },
	spores = { color = "#8a2be2b8" },
	pheromone_mark = { color = "#88ff00b8" },
}

--- Per-player active vignette tracking
--- Key: player_name string -> { hud_id: integer, effects: table<string, string> }
--- `effects` maps effect_id -> resolved texture modifier string
---@type table<string, { hud_id: integer, effects: table<string, string> }>
local active_player_vignettes = {}

-- ============================================================================
-- 1. INTERNAL HELPERS & TEXTURE COMPOSITING
-- ============================================================================

--- Normalizes Luanti texture modifier strings to ensure the engine preserves
--- the underlying image alpha gradient.
--- Luanti's C++ [colorize modifier interpolates alpha unless ratio is "alpha" with 0xFF alpha.
--- This converts [colorize:#RRGGBBAA to [colorize:#RRGGBB:alpha^[opacity:A
---@param s string Texture modifier string
---@return string normalized_string Clean modifier preserving alpha gradient
local function normalize_colorize_vignette(s)
	if not s or s == "" then return s end
	-- Convert #RRGGBBAA with hex alpha to #RRGGBB:alpha^[opacity:A
	s = s:gsub("%[colorize:#(%x%x%x%x%x%x)(%x%x)", function(rgb, alpha_hex)
		local op = tonumber(alpha_hex, 16) or 255
		if vignette_multiplier and vignette_multiplier ~= 1.0 then
			op = math.max(0, math.min(255, math.floor(op * vignette_multiplier + 0.5)))
		end
		return string.format("[colorize:#%s:alpha^[opacity:%d", rgb, op)
	end)
	-- Convert bare #RRGGBB without ratio to #RRGGBB:alpha
	s = s:gsub("%[colorize:#(%x%x%x%x%x%x)([^:%x])", "[colorize:#%1:alpha%2")
	s = s:gsub("%[colorize:#(%x%x%x%x%x%x)$", "[colorize:#%1:alpha")
	return s
end

--- Resolves full texture string with colorize or opacity modifiers
---@param effect_id string Unique effect identifier
---@param config? VignetteConfig|string Configuration or texture string
---@return string texture_string Formatted Luanti texture modifier
local function resolve_vignette_texture(effect_id, config)
	local conf = registered_vignettes[effect_id]

	if type(config) == "string" then
		-- Check if config is a preset reference or matches effect_id or lacks texture file extension
		if registered_vignettes[config] then
			conf = registered_vignettes[config]
		elseif config == effect_id
				or not (config:find("%.png") or config:find("%.jpg") or config:find("%[") or config:find("%^")) then
			conf = conf or registered_vignettes[effect_id]
		else
			return normalize_colorize_vignette(config)
		end
	elseif type(config) == "table" then
		conf = config
	end

	conf = conf or {}
	local base = conf.texture or DEFAULT_BASE_TEXTURE

	-- If texture is already a composite or specific modifier, use it directly
	if base:find("%^") or base:find("%[") then
		return normalize_colorize_vignette(base)
	end

	if conf.color and conf.color ~= "" then
		local clean_color = conf.color:gsub("^#", "")
		if #clean_color == 8 then
			local rgb = clean_color:sub(1, 6)
			local op = tonumber(clean_color:sub(7, 8), 16) or 255
			if vignette_multiplier and vignette_multiplier ~= 1.0 then
				op = math.max(0, math.min(255, math.floor(op * vignette_multiplier + 0.5)))
			end
			return string.format("%s^[colorize:#%s:alpha^[opacity:%d", base, rgb, op)
		elseif conf.opacity then
			local op = math.max(0, math.min(255, conf.opacity))
			if vignette_multiplier and vignette_multiplier ~= 1.0 then
				op = math.max(0, math.min(255, math.floor(op * vignette_multiplier + 0.5)))
			end
			return string.format("%s^[colorize:#%s:alpha^[opacity:%d", base, clean_color, op)
		else
			return string.format("%s^[colorize:#%s:alpha", base, clean_color)
		end
	elseif conf.opacity then
		local op = math.max(0, math.min(255, conf.opacity))
		if vignette_multiplier and vignette_multiplier ~= 1.0 then
			op = math.max(0, math.min(255, math.floor(op * vignette_multiplier + 0.5)))
		end
		return string.format("%s^[opacity:%d", base, op)
	end

	return base
end

--- Compiles a composite texture string from all active vignettes for a player
---@param effect_map table<string, string> Map of effect_id -> texture string
---@return string composite_texture Combined texture string with "^" modifiers
local function build_composite_texture(effect_map)
	local list = {}
	for _, tex in pairs(effect_map) do
		if tex and tex ~= "" then
			list[#list + 1] = tex
		end
	end
	table.sort(list)
	if #list == 0 then
		return "blank.png"
	end
	return table.concat(list, "^")
end

-- ============================================================================
-- 2. PUBLIC API & EXTENSIBILITY
-- ============================================================================

--- Registers or overrides a vignette style for a specific effect ID (3rd-party extensible)
---@param effect_id string Unique effect identifier
---@param config VignetteConfig|string Configuration table or texture string
function hud_effects.register_vignette(effect_id, config)
	if not effect_id then return end
	if type(config) == "string" then
		registered_vignettes[effect_id] = { texture = config }
	elseif type(config) == "table" then
		registered_vignettes[effect_id] = config
	end
end

--- Checks if a default or custom vignette preset is registered for the effect ID
---@param effect_id string Unique effect identifier
---@return boolean has_preset
function hud_effects.has_preset(effect_id)
	return registered_vignettes[effect_id] ~= nil
end

--- Retrieves the active HUD element ID for a player if one exists
---@param player ObjectRef Target player
---@return integer? hud_id
function hud_effects.get_hud_id(player)
	if not player or not player:is_player() then return nil end
	local pname = player:get_player_name()
	local session = active_player_vignettes[pname]
	return session and session.hud_id
end

--- Sets default base radial vignette texture used across all effects
---@param texture_name string Texture asset filename
function hud_effects.set_default_vignette(texture_name)
	if texture_name and texture_name ~= "" then
		DEFAULT_BASE_TEXTURE = texture_name
	end
end

--- Sets the global vignette prominence / opacity scaling multiplier (e.g. 1.0 = standard, 1.5 = high contrast)
---@param mult number Prominence multiplier in range [0.1, 3.0]
function hud_effects.set_prominence_multiplier(mult)
	if type(mult) == "number" and mult > 0 then
		vignette_multiplier = math.max(0.1, math.min(3.0, mult))
	end
end

--- Gets the current global vignette prominence / opacity scaling multiplier
---@return number mult
function hud_effects.get_prominence_multiplier()
	return vignette_multiplier
end

--- Applies or updates a fullscreen responsive screen vignette on a target player
---@param player ObjectRef Target player
---@param effect_id string Unique status effect identifier
---@param config? VignetteConfig|string Vignette configuration table or texture modifier
---@return integer? hud_id Numerical HUD element ID or nil
function hud_effects.apply(player, effect_id, config)
	if not vignettes_enabled then return nil end
	if not player or not player:is_player() or not effect_id then return nil end

	local pname = player:get_player_name()
	if not pname or pname == "" then return nil end

	local tex = resolve_vignette_texture(effect_id, config)
	if not tex or tex == "" then return nil end

	local session = active_player_vignettes[pname]

	if not session then
		-- First vignette for player: register single responsive fullscreen HUD element
		local comp_tex = tex
		local hud_id = player:hud_add({
			hud_elem_type = "image",
			position = { x = 0.5, y = 0.5 },
			alignment = { x = 0, y = 0 },
			-- Negative values tell Luanti engine to scale to 100% of viewport width and height
			scale = { x = -100, y = -100 },
			text = comp_tex,
			z_index = -10,
		})

		if hud_id then
			active_player_vignettes[pname] = {
				hud_id = hud_id,
				effects = { [effect_id] = tex },
			}
			return hud_id
		end
		return nil
	end

	-- Existing session: update composite texture stack
	session.effects[effect_id] = tex
	local comp_tex = build_composite_texture(session.effects)
	player:hud_change(session.hud_id, "text", comp_tex)

	return session.hud_id
end

--- Removes an active vignette for a specific status effect from a player
---@param player ObjectRef Target player
---@param effect_id string Unique status effect identifier
---@return boolean removed True if vignette was present and removed
function hud_effects.remove(player, effect_id)
	if not player or not player:is_player() or not effect_id then return false end

	local pname = player:get_player_name()
	if not pname or pname == "" then return false end

	local session = active_player_vignettes[pname]
	if not session or not session.effects[effect_id] then return false end

	session.effects[effect_id] = nil

	-- If no active vignettes remain, cleanly remove the HUD element
	if not next(session.effects) then
		if player:is_valid() then
			player:hud_remove(session.hud_id)
		end
		active_player_vignettes[pname] = nil
		return true
	end

	-- Update composite texture with remaining active effects
	if player:is_valid() then
		local comp_tex = build_composite_texture(session.effects)
		player:hud_change(session.hud_id, "text", comp_tex)
	end

	return true
end

--- Clears all active vignettes and removes the HUD element for a player
---@param player ObjectRef Target player
function hud_effects.clear(player)
	if not player then return end
	local pname = player:is_player() and player:get_player_name()
	if not pname or pname == "" then return end

	local session = active_player_vignettes[pname]
	if not session then return end

	active_player_vignettes[pname] = nil
	if player:is_valid() and session.hud_id then
		player:hud_remove(session.hud_id)
	end
end

--- Checks if a player currently has an active vignette for a given effect ID
---@param player ObjectRef Target player
---@param effect_id? string Optional specific effect ID
---@return boolean has_vignette True if active
function hud_effects.has_vignette(player, effect_id)
	if not player or not player:is_player() then return false end
	local pname = player:get_player_name()
	local session = active_player_vignettes[pname]
	if not session then return false end
	if not effect_id then return true end
	return session.effects[effect_id] ~= nil
end

-- ============================================================================
-- 3. LIFECYCLE LISTENERS
-- ============================================================================

core.register_on_joinplayer(function(player)
	hud_effects.clear(player)
end)

core.register_on_leaveplayer(function(player)
	hud_effects.clear(player)
end)

core.register_on_dieplayer(function(player)
	hud_effects.clear(player)
end)

core.register_on_respawnplayer(function(player)
	hud_effects.clear(player)
end)

core.register_on_shutdown(function()
	for _, player in ipairs(core.get_connected_players()) do
		hud_effects.clear(player)
	end
end)

x_mob_core.hud_effects = hud_effects

return hud_effects
