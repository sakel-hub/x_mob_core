--[[
	x_mob_core - Reusable Envelop & Status Visual FX Subsystem
	Provides an open rectangular sleeve visual envelop wrapping the bottom
	half of targets (players and mob entities) with smooth top-fading alpha.
	Supports dynamic multi-effect stacking, independent sub-effect lifecycles,
	and extensible callbacks conforming to SOLID architecture.

	Author: SaKeL
	License: MIT
]]

local S = core.get_translator("x_mob_core")

--- Active enveloped targets tracking
--- Key: player_name string or mob LuaEntity table
---@type table<string|table, EnvelopTargetRecord>
local active_envelops = {}

-- ============================================================================
-- 1. DIMENSION & ATTACHMENT CALCULATION
-- Calculates open rectangular sleeve wrap around target bottom half
-- ============================================================================

--- Computes proportional rectangular sleeve visual_size and attachment offset
---@param target ObjectRef Target entity or player
---@return Vector visual_size Calculated child visual_size
---@return Vector attach_pos Attachment translation in engine units
local function calculate_envelop_transform(target)
	local is_player = target:is_player()
	local props = target:get_properties() or {}

	local cbox = props.collisionbox or {-0.3, 0.0, -0.3, 0.3, 1.77, 0.3}
	local sbox = props.selectionbox

	-- Horizontal footprint
	local min_x = cbox[1] or -0.3
	local max_x = cbox[4] or 0.3
	local min_z = cbox[3] or -0.3
	local max_z = cbox[6] or 0.3

	if sbox and sbox[1] and sbox[4] then
		min_x = math.min(min_x, sbox[1])
		max_x = math.max(max_x, sbox[4])
	end
	if sbox and sbox[3] and sbox[6] then
		min_z = math.min(min_z, sbox[3])
		max_z = math.max(max_z, sbox[6])
	end

	local span_x = math.abs(max_x - min_x)
	local span_z = math.abs(max_z - min_z)
	local center_x = (min_x + max_x) * 0.5
	local center_z = (min_z + max_z) * 0.5

	-- Snug 1.15x margin around target bounding box, minimum 0.3 for tiny mobs
	local env_width = math.max(0.3, span_x * 1.15)
	local env_depth = math.max(0.3, span_z * 1.15)

	-- Ground/feet level is anchored by physical collisionbox contact level
	local feet_y = cbox[2] or (sbox and sbox[2]) or 0.0
	local top_y = math.max(cbox[5] or 1.0, (sbox and sbox[5]) or 1.0)
	local total_height = math.max(0.2, top_y - feet_y)
	local env_height = math.max(0.25, total_height * 0.55)

	-- Normalize for parent visual_size in scene graph (Irrlicht scales child by parent visual_size)
	local vs_x, vs_y, vs_z = 1.0, 1.0, 1.0
	if not is_player then
		local pvs = props.visual_size
		if type(pvs) == "table" then
			vs_x = (pvs.x and pvs.x > 0) and pvs.x or 1.0
			-- 2D visual_size {x, y} applies x scale to both X and Z in Luanti/Irrlicht
			vs_y = (pvs.y and pvs.y > 0) and pvs.y or vs_x
			vs_z = (pvs.z and pvs.z > 0) and pvs.z or vs_x
		elseif type(pvs) == "number" and pvs > 0 then
			vs_x, vs_y, vs_z = pvs, pvs, pvs
		end
	end

	local child_visual_size = {
		x = env_width / vs_x,
		y = env_height / vs_y,
		z = env_depth / vs_z,
	}

	-- Position base at feet level (tenths of a node) centered over horizontal span
	local attach_pos = {
		x = (center_x * 10) / vs_x,
		y = (feet_y * 10) / vs_y,
		z = (center_z * 10) / vs_z,
	}

	return child_visual_size, attach_pos
end

--- Generates robust unique tracking key for target
---@param target ObjectRef Target player or entity
---@return string|table key Player name string or LuaEntity table
local function get_target_key(target)
	if target:is_player() then
		return target:get_player_name()
	end
	return target:get_luaentity() or target
end

-- ============================================================================
-- 2. ENVELOP ENTITY REGISTRATION
-- Open 4-walled rectangular prism (x_mob_core_envelop_box.glb), no top/bottom caps
-- ============================================================================

core.register_entity("x_mob_core:envelop", {
	initial_properties = {
		hp_max = 1,
		physical = false,
		collide_with_objects = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
		selectionbox = {0, 0, 0, 0, 0, 0},
		pointable = false, -- Attacks pass through to target underneath
		visual = "mesh",
		mesh = "x_mob_core_envelop_box.glb",
		textures = {"blank.png"},
		use_texture_alpha = true,
		backface_culling = false,
		visual_size = {x = 1.0, y = 1.0, z = 1.0},
		glow = 8,
		static_save = false, -- Never stored in block database; self-cleans on restart
		infotext = S("Envelop"),
	},

	armor_groups = { immortal = 1 },
	_is_envelop = true,

	on_activate = function(self, _staticdata, _dtime_s)
		self.effects = {}
		self.object:set_armor_groups({ immortal = 1 })
		self.object:set_properties({
			pointable = false,
			selectionbox = {0, 0, 0, 0, 0, 0},
			collisionbox = {0, 0, 0, 0, 0, 0},
			collide_with_objects = false,
		})
		self.object:play_animation("pulse", { speed = 1.0, loop = true })

		-- Self-clean if spawned without target
		if not self.target then
			core.after(0.05, function()
				if not self.target or not self.target:is_valid() then
					if self.object and self.object:is_valid() then
						self.object:remove()
					end
				end
			end)
		end
	end,

	--- Assembles composite texture string from all currently active effects
	---@return string composite_texture Composite texture with "^" modifiers
	get_composite_texture = function(self)
		local tex_list = {}
		for _, eff in pairs(self.effects) do
			if eff.texture and eff.texture ~= "" then
				tex_list[#tex_list + 1] = eff.texture
			end
		end
		table.sort(tex_list)
		if #tex_list == 0 then
			return "blank.png"
		end
		return table.concat(tex_list, "^")
	end,

	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		if puncher and self.target and puncher == self.target then
			return true
		end
		if self.target and self.target:is_valid() then
			self.target:punch(puncher, time_from_last_punch, tool_capabilities, dir)
		end
		return true
	end,

	on_rightclick = function(_self, _clicker)
	end,

	on_step = function(self, dtime)
		local target = self.target
		if not target or not target:is_valid() then
			self.object:remove()
			return
		end

		if target:is_player() and target:get_hp() <= 0 then
			x_mob_core.remove_envelop(target)
			return
		end

		local tex_dirty = false
		local expired_ids = {}

		for id, eff in pairs(self.effects) do
			eff.timer = eff.timer - dtime
			if eff.on_step then
				eff.on_step(dtime, target)
			end
			if eff.timer <= 0 then
				expired_ids[#expired_ids + 1] = id
			end
		end

		for i = 1, #expired_ids do
			local id = expired_ids[i]
			local eff = self.effects[id]
			if eff then
				if eff.on_remove then
					eff.on_remove(target)
				end
				self.effects[id] = nil
				tex_dirty = true
			end
		end

		if not self.object or not self.object:is_valid() then
			return
		end

		if tex_dirty then
			local count = 0
			for _ in pairs(self.effects) do
				count = count + 1
			end
			if count == 0 then
				x_mob_core.remove_envelop(target)
				return
			end
			local new_tex = self:get_composite_texture()
			self.object:set_properties({ textures = { new_tex } })
		end
	end,
})

-- ============================================================================
-- 3. PUBLIC ENVELOP API
-- ============================================================================

--- Checks if target currently has an active envelop or a specific active effect
---@param target ObjectRef Target player or entity
---@param effect_id? string Optional specific effect ID to query
---@return boolean is_enveloped True if active envelop/effect exists
function x_mob_core.is_enveloped(target, effect_id)
	if not target or not target:is_valid() then return false end
	local key = get_target_key(target)
	local data = active_envelops[key]
	if not data or not data.envelop or not data.envelop:is_valid() then
		return false
	end
	if not effect_id then
		return true
	end
	local ent = data.envelop:get_luaentity()
	return ent ~= nil and ent.effects ~= nil and ent.effects[effect_id] ~= nil
end

--- Returns active envelop data record for target if present
---@param target ObjectRef Target player or entity
---@return EnvelopTargetRecord? data Active envelop metadata
function x_mob_core.get_envelop_data(target)
	if not target or not target:is_valid() then return nil end
	local key = get_target_key(target)
	return active_envelops[key]
end

--- Removes a specific active effect from target's envelop, preserving remaining effects
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID to remove
function x_mob_core.remove_envelop_effect(target, effect_id)
	if not target or not target:is_valid() or not effect_id then return end
	local key = get_target_key(target)
	local data = active_envelops[key]
	if not data or not data.envelop or not data.envelop:is_valid() then return end

	local ent = data.envelop:get_luaentity()
	if not ent or not ent.effects then return end

	local eff = ent.effects[effect_id]
	if eff then
		if eff.on_remove then
			eff.on_remove(target)
		end
		ent.effects[effect_id] = nil

		local count = 0
		for _ in pairs(ent.effects) do
			count = count + 1
		end
		if count == 0 then
			x_mob_core.remove_envelop(target)
		else
			local new_tex = ent:get_composite_texture()
			ent.object:set_properties({ textures = { new_tex } })
		end
	end
end

--- Removes all active effects and detaches/removes envelop entity from target
---@param target ObjectRef Target player or entity
function x_mob_core.remove_envelop(target)
	if not target or not target:is_valid() then return end
	local key = get_target_key(target)
	local data = active_envelops[key]
	if not data then return end
	active_envelops[key] = nil

	if data.envelop and data.envelop:is_valid() then
		local ent = data.envelop:get_luaentity()
		if ent and ent.effects then
			for _, eff in pairs(ent.effects) do
				if eff.on_remove then
					eff.on_remove(target)
				end
			end
			ent.effects = {}
		end
		data.envelop:remove()
	end
end

--- Applies or updates a visual sleeve envelop and status effect on target
---@param target ObjectRef Target player or entity to envelop
---@param effect_def table Configuration: { id: string, duration: number, texture: string }
---@return ObjectRef? Envelop entity object
function x_mob_core.apply_envelop(target, effect_def)
	if not target or not target:is_valid() or not effect_def or not effect_def.id then
		return nil
	end

	-- Do not envelop attached child entities (wielditems, armor meshes, visual proxies)
	if not target:is_player() then
		if target.get_attach and target:get_attach() ~= nil then
			return nil
		end
		local ent = target.get_luaentity and target:get_luaentity()
		if ent then
			if ent._is_wielditem or ent._is_visual_proxy or ent._is_envelop or ent._is_health_bar then
				return nil
			end
			local name = ent.name or ""
			if name:find("wield") or name:find("^x_player_api:visual") or name:find("^__builtin:") then
				return nil
			end
		end
	end

	local tpos = target:get_pos()
	if not tpos then return nil end

	local key = get_target_key(target)
	local duration = effect_def.duration or 3.0
	local texture = effect_def.texture
	if not texture or texture == "" or texture == "default" then
		texture = "x_mob_core_envelop_default.png"
	end

	-- If target is already enveloped, add or refresh the effect on existing entity
	local existing = active_envelops[key]
	if existing and existing.envelop and existing.envelop:is_valid() then
		local ent = existing.envelop:get_luaentity()
		if ent then
			ent.effects[effect_def.id] = {
				id = effect_def.id,
				duration = duration,
				timer = duration,
				texture = texture,
				on_step = effect_def.on_step,
				on_remove = effect_def.on_remove,
			}
			local comp_tex = ent:get_composite_texture()
			existing.envelop:set_properties({ textures = { comp_tex } })
		end
		return existing.envelop
	end

	-- Calculate proportional open sleeve visual dimensions and foot offset
	local v_size, attach_pos = calculate_envelop_transform(target)

	local envelop_obj = core.add_entity(tpos, "x_mob_core:envelop")
	if not envelop_obj or not envelop_obj:is_valid() then return nil end

	local envelop_ent = envelop_obj:get_luaentity()
	if envelop_ent then
		envelop_ent.target = target
		envelop_ent.effects = {
			[effect_def.id] = {
				id = effect_def.id,
				duration = duration,
				timer = duration,
				texture = texture,
				on_step = effect_def.on_step,
				on_remove = effect_def.on_remove,
			},
		}
	end

	local comp_tex = envelop_ent and envelop_ent:get_composite_texture() or texture

	envelop_obj:set_properties({
		mesh = "x_mob_core_envelop_box.glb",
		visual_size = v_size,
		textures = { comp_tex },
		use_texture_alpha = true,
		pointable = false,
		selectionbox = {0, 0, 0, 0, 0, 0},
		collisionbox = {0, 0, 0, 0, 0, 0},
		collide_with_objects = false,
		backface_culling = false,
		glow = 8,
	})

	envelop_obj:play_animation("pulse", { speed = 1.0, loop = true })
	envelop_obj:set_attach(target, "", attach_pos, {x = 0, y = 0, z = 0}, true)

	active_envelops[key] = {
		envelop = envelop_obj,
		target = target,
	}

	return envelop_obj
end

-- ============================================================================
-- 4. LIFECYCLE LISTENERS
-- ============================================================================

core.register_on_joinplayer(function(player)
	x_mob_core.remove_envelop(player)
end)

core.register_on_dieplayer(function(player)
	x_mob_core.remove_envelop(player)
end)

core.register_on_respawnplayer(function(player)
	x_mob_core.remove_envelop(player)
end)

core.register_on_leaveplayer(function(player)
	x_mob_core.remove_envelop(player)
end)

core.register_on_shutdown(function()
	for _, player in ipairs(core.get_connected_players()) do
		x_mob_core.remove_envelop(player)
	end
end)

---Visual Envelop and Status FX Subsystem.
---@class EnvelopSubsystem
local envelop = {
	apply_envelop = x_mob_core.apply_envelop,
	remove_envelop = x_mob_core.remove_envelop,
	remove_envelop_effect = x_mob_core.remove_envelop_effect,
	is_enveloped = x_mob_core.is_enveloped,
	get_envelop_data = x_mob_core.get_envelop_data,
}

return envelop
