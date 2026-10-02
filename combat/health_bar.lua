--[[
	x_mob_core - Combat Health Bar Subsystem
	Procedural [combine: texture-based overhead health bars with
	granular color tiers, proportional bounding box scaling,
	and efficient timeout reset mechanics (Single Responsibility Principle).
]]

---@class HealthBarSubsystem
local health_bar = {}

---@type table<string, string> Cache of generated [combine: texture modifier strings
local texture_cache = {}

---Global engine settings cache
local global_enabled = core.settings:get_bool("x_mob_core_enable_health_bars", true)
local global_timeout = tonumber(core.settings:get("x_mob_core_health_bar_timeout")) or 4.0
local global_auto_remove = core.settings:get_bool("x_mob_core_health_bar_auto_remove", true)

---Default 5-tier color thresholds and health bar configuration
local DEFAULT_CONFIG = {
	enabled = true,
	width = 64,
	height = 8,
	border = 1,
	border_color = "#111111",
	empty_color = "#330000",
	colors = {
		{ threshold = 0.80, color = "#00FF00" }, -- Emerald Green
		{ threshold = 0.60, color = "#7CFC00" }, -- Lime
		{ threshold = 0.40, color = "#FFD700" }, -- Gold
		{ threshold = 0.20, color = "#FF8C00" }, -- Dark Orange
		{ threshold = 0.00, color = "#FF2200" }, -- Crimson Red
	},
	auto_scale = true,
	visual_size = nil,
	spacing = 0.35,
	offset_y = nil,
	timeout = 4.0,
	auto_remove = true,
	glow = 5,
}

---Registers the visual child entity used for displaying health bars in 3D world space.
core.register_entity("x_mob_core:health_bar", {
	initial_properties = {
		visual = "sprite",
		visual_size = {x = 1.0, y = 0.12},
		textures = {"[combine:1x1^[noalpha^[colorize:#000000:0"},
		physical = false,
		collide_with_objects = false,
		pointable = false,
		static_save = false,
		glow = 5,
		use_texture_alpha = true,
		backface_culling = false,
		is_visible = true,
	},

	_is_visual = true,

	on_activate = function(self)
		if self.object and self.object:is_valid() then
			self.object:set_armor_groups({ immortal = 1 })
		end
	end,

	on_step = function(self)
		-- Safety cleanup: remove orphan health bar if parent was destroyed or detached
		if not self.object or not self.object:is_valid() then return end
		local parent = self.object:get_attach()
		if not parent or not parent:is_valid() then
			self.object:remove()
		end
	end,
})

---Resolves effective health bar configuration for a mob.
---@param def? table Entity definition table
---@return table cfg Merged configuration
function health_bar.get_config(def)
	local mcfg = def and def.health_bar
	if mcfg == false then
		return { enabled = false }
	end

	local cfg = {}
	for k, v in pairs(DEFAULT_CONFIG) do
		cfg[k] = v
	end

	-- Apply global setting defaults
	if not global_enabled then
		cfg.enabled = false
	end
	if global_timeout then
		cfg.timeout = global_timeout
	end
	if global_auto_remove ~= nil then
		cfg.auto_remove = global_auto_remove
	end

	-- Apply mob definition overrides
	if type(mcfg) == "table" then
		for k, v in pairs(mcfg) do
			cfg[k] = v
		end
	end

	return cfg
end

---Resolves the bar fill color according to current health ratio and color tiers.
---@param ratio number Current health ratio (0.0 to 1.0)
---@param color_list table[] List of {threshold: number, color: string}
---@return string color Hex color string
function health_bar.resolve_color(ratio, color_list)
	local list = color_list or DEFAULT_CONFIG.colors
	local count = #list
	for i = 1, count do
		local entry = list[i]
		if ratio >= entry.threshold then
			return entry.color
		end
	end
	return (count > 0 and list[count].color) or "#FF0000"
end

---Generates or retrieves a memoized [combine: texture modifier string for the health bar.
---@param width integer Total texture width in px
---@param height integer Total texture height in px
---@param border integer Border thickness in px
---@param fill_w integer Width of the filled health bar in px
---@param bar_color string Fill color hex string (e.g. "#00FF00")
---@param border_color string Border color hex string (e.g. "#111111")
---@param empty_color string Background depleted track hex string (e.g. "#330000")
---@return string texture_modifier Compiled texture modifier string
function health_bar.get_texture(width, height, border, fill_w, bar_color, border_color, empty_color)
	local cache_key = width .. ":" .. height .. ":" .. border .. ":" .. fill_w .. ":" ..
		bar_color .. ":" .. border_color .. ":" .. empty_color

	local cached = texture_cache[cache_key]
	if cached then
		return cached
	end

	local inner_w = math.max(0, width - (border * 2))
	local inner_h = math.max(0, height - (border * 2))
	local clamped_fill = math.max(0, math.min(inner_w, fill_w))

	-- Construct composited texture modifier:
	-- Base outer border -> inner depleted track -> inner active fill
	-- Per Luanti documentation (doc/lua_api.md):
	-- Sub-textures inside [combine: must escape ^, :, and \ with backslashes.
	-- Parentheses are NOT allowed inside [combine: parameter arguments.
	local parts = {
		"[combine:", width, "x", height,
		":0,0=[combine\\:", width, "x", height, "\\^[noalpha\\^[colorize\\:", border_color, "\\:255",
	}

	if inner_w > 0 and inner_h > 0 then
		parts[#parts + 1] = ":"
		parts[#parts + 1] = border
		parts[#parts + 1] = ","
		parts[#parts + 1] = border
		parts[#parts + 1] = "=[combine\\:"
		parts[#parts + 1] = inner_w
		parts[#parts + 1] = "x"
		parts[#parts + 1] = inner_h
		parts[#parts + 1] = "\\^[noalpha\\^[colorize\\:"
		parts[#parts + 1] = empty_color
		parts[#parts + 1] = "\\:255"
	end

	if clamped_fill > 0 and inner_h > 0 then
		parts[#parts + 1] = ":"
		parts[#parts + 1] = border
		parts[#parts + 1] = ","
		parts[#parts + 1] = border
		parts[#parts + 1] = "=[combine\\:"
		parts[#parts + 1] = clamped_fill
		parts[#parts + 1] = "x"
		parts[#parts + 1] = inner_h
		parts[#parts + 1] = "\\^[noalpha\\^[colorize\\:"
		parts[#parts + 1] = bar_color
		parts[#parts + 1] = "\\:255"
	end

	local result = table.concat(parts)
	texture_cache[cache_key] = result
	return result
end

---Calculates proportional visual size and attachment position based on mob bounding box and nametag.
---@param self table Mob entity instance
---@param def? table Entity definition table
---@param cfg? table Health bar configuration
---@return Vector2d visual_size Sprite dimensions in world units
---@return Vector attach_pos Local attachment offset in engine units (tenths of a node)
function health_bar.calculate_dimensions(self, def, cfg)
	cfg = cfg or health_bar.get_config(def)

	local cbox = (self.object and self.object:is_valid() and self.object:get_properties().collisionbox) or
		self.collisionbox or
		(def and def.initial_properties and def.initial_properties.collisionbox) or
		{-0.4, 0, -0.4, 0.4, 1.6, 0.4}

	local sbox = (self.object and self.object:is_valid() and self.object:get_properties().selectionbox) or
		self.selectionbox or
		(def and def.initial_properties and def.initial_properties.selectionbox)

	-- Calculate horizontal footprint for proportional scaling
	local span_x = math.abs((cbox[4] or 0.4) - (cbox[1] or -0.4))
	local span_z = math.abs((cbox[6] or 0.4) - (cbox[3] or -0.4))
	if sbox and sbox[4] and sbox[1] then
		span_x = math.max(span_x, math.abs(sbox[4] - sbox[1]))
	end
	if sbox and sbox[6] and sbox[3] then
		span_z = math.max(span_z, math.abs(sbox[6] - sbox[3]))
	end
	local box_w = math.max(0.4, span_x, span_z)

	local world_w
	local world_h
	local aspect_ratio = (cfg.height and cfg.width and cfg.width > 0) and (cfg.height / cfg.width) or (8 / 64)
	if cfg.visual_size then
		world_w = cfg.visual_size.x
		world_h = cfg.visual_size.y
	elseif cfg.auto_scale ~= false then
		world_w = math.max(0.6, math.min(2.4, box_w * 1.15))
		world_h = math.max(0.07, math.min(0.28, world_w * aspect_ratio))
	else
		world_w = 1.0
		world_h = 1.0 * aspect_ratio
	end

	-- Extract parent entity visual_size to normalize attachment translation in Irrlicht scene graph.
	-- In Luanti, child entities attached to root bone ("") are parented to parent's animated_meshnode,
	-- which has scale = parent.visual_size.
	-- Irrlicht multiplies child attachment translation by parent.visual_size.y.
	-- Therefore, attach_y must be divided by vs_y so that the resulting world-space
	-- position is precisely (top_y + spacing) nodes above origin.
	local parent_props = (self.object and self.object:is_valid() and self.object:get_properties()) or {}
	local parent_vs = parent_props.visual_size or
		self.visual_size or
		(def and def.initial_properties and def.initial_properties.visual_size) or
		{ x = 1, y = 1 }

	local vs_y = 1
	if type(parent_vs) == "table" then
		vs_y = (parent_vs.y and parent_vs.y > 0 and parent_vs.y) or 1
	elseif type(parent_vs) == "number" and parent_vs > 0 then
		vs_y = parent_vs
	end

	-- IMPORTANT (Luanti glTF / Irrlicht CBillboardSceneNode Invariant):
	-- In Irrlicht, CBillboardSceneNode::render() sets video::ETS_WORLD to IdentityMatrix
	-- and calculates quad vertices directly from Size.Width and Size.Height (visual_size * BS).
	-- The billboard's quad geometry is NEVER multiplied by the parent node's scale matrix!
	-- Therefore, child visual_size must be the EXACT desired world dimensions (world_w, world_h)
	-- in nodes and MUST NOT be divided by parent visual_size.
	local v_size = {
		x = world_w,
		y = world_h,
	}

	-- Calculate vertical clearance above bounding box top relative to origin
	local top_y = cbox[5] or 1.2
	if sbox and sbox[5] and sbox[5] > top_y then
		top_y = sbox[5]
	end
	local base_y = math.min(0, cbox[2] or 0)
	local mob_h = self.mob_height or (def and def.mob_height)
	if mob_h and (base_y + mob_h) > top_y then
		top_y = base_y + mob_h
	end
	local eye_y = self.eye_offset or (def and def.eye_offset)
	if eye_y and type(eye_y) == "number" and (eye_y + 0.15) > top_y then
		top_y = eye_y + 0.15
	end

	local spacing = cfg.spacing or 0.35

	-- Add extra clearance if mob has an active nametag to prevent overlap
	local has_nametag = (self.nametag and self.nametag ~= "") or
		(self._nametag and self._nametag ~= "") or
		(def and def.nametag and def.nametag ~= "")
	if has_nametag then
		spacing = spacing + 0.15
	end

	if cfg.offset_y then
		spacing = cfg.offset_y
	end

	local attach_y = ((top_y + spacing) * 10) / vs_y
	local attach_pos = { x = 0, y = attach_y, z = 0 }

	return v_size, attach_pos
end

---Shows or updates the overhead health bar on a mob entity, resetting the timeout window.
---@param self table Mob entity instance
---@param cur_hp number Current health value
---@param max_hp number Maximum health value
---@param def? table Entity definition table
---@return boolean shown True if health bar is shown or updated
function health_bar.show(self, cur_hp, max_hp, def)
	def = def or self._def or (self.name and core.registered_entities[self.name]) or {}
	local cfg = health_bar.get_config(def)
	if not cfg.enabled then return false end
	if self.is_dead or self.state == "dying" then return false end
	if not self.object or not self.object:is_valid() then return false end

	max_hp = math.max(1, max_hp or self.hp_max or def._hp_max or 20)
	cur_hp = math.max(0, math.min(max_hp, cur_hp or self.hp or max_hp))
	local ratio = cur_hp / max_hp

	-- Calculate fill dimensions and texture
	local inner_w = math.max(0, cfg.width - (cfg.border * 2))
	local fill_w = math.floor(ratio * inner_w)
	local color = health_bar.resolve_color(ratio, cfg.colors)
	local tex = health_bar.get_texture(
		cfg.width, cfg.height, cfg.border, fill_w, color, cfg.border_color, cfg.empty_color
	)

	local v_size, attach_pos = health_bar.calculate_dimensions(self, def, cfg)

	local child = self._health_bar_obj
	if child and child:is_valid() then
		-- Update existing child entity texture, size, and ensure visibility
		child:set_properties({
			textures = { tex },
			visual_size = v_size,
			glow = cfg.glow or 5,
			is_visible = true,
		})
		child:set_attach(self.object, "", attach_pos, {x = 0, y = 0, z = 0}, true)
	else
		-- Spawn new child entity and attach above mob
		local pos = self.object:get_pos()
		if not pos then return false end
		local new_child = core.add_entity(pos, "x_mob_core:health_bar")
		if not new_child or not new_child:is_valid() then
			return false
		end

		new_child:set_properties({
			textures = { tex },
			visual_size = v_size,
			glow = cfg.glow or 5,
			is_visible = true,
		})
		new_child:set_attach(self.object, "", attach_pos, {x = 0, y = 0, z = 0}, true)
		self._health_bar_obj = new_child
	end

	-- Reset timeout countdown window
	self._health_bar_timer = cfg.timeout or 4.0
	return true
end

---Handles health bar auto-hiding when the countdown timer expires.
---@param self table Mob entity instance
---@param def? table Entity definition table
function health_bar.on_timeout(self, def)
	self._health_bar_timer = 0
	local cfg = health_bar.get_config(def)
	if cfg.auto_remove ~= false then
		health_bar.remove(self)
	else
		health_bar.hide(self)
	end
end

---Hides the health bar entity by setting is_visible = false (soft hide).
---@param self table Mob entity instance
function health_bar.hide(self)
	self._health_bar_timer = nil
	local child = self._health_bar_obj
	if child and child:is_valid() then
		child:set_properties({ is_visible = false })
	end
end

---Removes and destroys the health bar child entity completely.
---@param self table Mob entity instance
function health_bar.remove(self)
	self._health_bar_timer = nil
	local child = self._health_bar_obj
	if child and child:is_valid() then
		child:set_detach()
		child:remove()
	end
	self._health_bar_obj = nil
end

---Dispatches an HP change event to update the health bar.
---@param self table Mob entity instance
---@param _old_hp number Previous health value
---@param new_hp number Updated health value
---@param def? table Entity definition table
function health_bar.on_hp_change(self, _old_hp, new_hp, def)
	def = def or self._def or (self.name and core.registered_entities[self.name]) or {}
	local max_hp = self.hp_max or (def and (def.hp_max or def._hp_max)) or 20
	health_bar.show(self, new_hp, max_hp, def)
end

return health_bar
