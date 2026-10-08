--[[
	x_mob_core - Centralized Status Effect & Player Physics Subsystem
	Manages player and entity status effects, compound physics overrides,
	multi-mod physics adapters (player_monoids, pova, playerphysics, vanilla),
	damage-over-time (DoT) tickers, and visual envelop synergy.

	Author: SaKeL
	License: MIT
]]

---@class StatusEffectDef
---@field type? "slow"|"root"|"dot"|"debuff"|"custom" Effect archetype ("root" halts movement and jump)
---@field chance? number Optional success chance (fraction 0.0-1.0 or percentage 1-100; defaults to 100% when nil)
---@field duration number Duration in seconds
---@field speed_factor? number Movement speed fractional multiplier (e.g. 0.5 for 50% slow)
---@field jump_factor? number Jump fractional multiplier (e.g. 0.0 to prevent jump)
---@field gravity_factor? number Gravity fractional multiplier
---@field fov_factor? number Camera FOV multiplier (e.g. 0.85 for shockwave / tunnel vision)
---@field fov_duration? number Optional sub-duration for FOV effect in seconds (defaults to effect duration)
---@field fov_transition? number FOV transition smoothing time in seconds (default 0.2)
---@field damage? number Damage per interval tick for DoT
---@field interval? number Interval between DoT ticks in seconds (default 1.0)
---@field damage_type? string Damage group name for DoT (default "fleshy")
---@field caster? ObjectRef Attacking entity or player source
---@field penetrate_armor? boolean Whether DoT bypasses armor damage reduction (default true)
---@field particle_spawner? table|fun(target: ObjectRef):table Particle spawner definition for DoT ticks
---@field envelop? table<{ texture: string }> Visual envelop configuration
---@field envelop_texture? string Visual envelop sleeve texture asset
---@field hud_vignette? string|table Fullscreen responsive screen vignette configuration
---@field cleanse_in_water? boolean Whether immersion in water immediately cleanses the effect
---@field drain_hunger? number Hunger or stamina units drained per tick via hunger_adapter
---@field anti_heal? boolean Whether health regeneration is suppressed during effect
---@field damage_multiplier? number Incoming damage multiplier while afflicted (e.g. 1.35 for brittle)
---@field on_apply? fun(target: ObjectRef) Callback when effect is first applied
---@field on_step? fun(dtime: number, target: ObjectRef) Callback on step tick (forwarded to envelop)
---@field on_tick? fun(target: ObjectRef) Callback on periodic DoT tick (e.g. particle spawner)
---@field on_remove? fun(target: ObjectRef) Callback when effect is removed or expires

---@class ActiveEffectRecord : StatusEffectDef
---@field timer number Remaining duration in seconds
---@field token string|integer Cancellation and refresh token
---@field has_envelop boolean Whether an envelop entity was attached
---@field target ObjectRef Target entity or player

---@class StatusEffectsSubsystem
local status_effects = {}

local modpath = core.get_modpath("x_mob_core")
local utils = dofile(modpath .. "/core/utils.lua")

--- Per-target active status effects registry
--- Key: player_name string or mob LuaEntity table / identifier
---@type table<string|table, table<string, ActiveEffectRecord>>
local active_effects = {}

--- Per-player baseline physics override cache for vanilla fallback
--- Key: player_name string
---@type table<string, {speed: number, jump: number, gravity: number}>
local player_base_physics = {}

--- Per-player active physics modifiers for compound calculation
--- Key: player_name string -> effect_id string -> {speed_factor?: number, jump_factor?: number}
---@type table<string, table<string, table<string, number>>>
local player_physics_modifiers = {}

--- Per-player baseline FOV override cache
--- Key: player_name string
---@type table<string, {fov: number, is_multiplier: boolean}>
local player_base_fov = {}

--- Per-player active FOV modifiers for compound calculation
--- Key: player_name string -> effect_id string -> {fov_factor: number, transition_time: number}
---@type table<string, table<string, {fov_factor: number, transition_time: number}>>
local player_fov_modifiers = {}

--- Set of currently rooted players for zero-velocity enforcement
--- Key: player_name string -> boolean
local rooted_players = {}

-- ============================================================================
-- 1. TARGET KEY RESOLUTION
-- ============================================================================

--- Resolves a consistent tracking key for any target ObjectRef
---@param target ObjectRef Target player or mob entity
---@return string|table? key Registry key
local function get_target_key(target)
	if not target then return nil end
	local is_player = target.is_player and target:is_player()
	if is_player then
		local name = target:get_player_name()
		if name and name ~= "" then
			return name
		end
		return tostring(target)
	end
	local ent = target:get_luaentity()
	return ent or tostring(target)
end

-- ============================================================================
-- 2. PHYSICS ADAPTER LAYER
-- Integrates player_monoids, pova, playerphysics, and vanilla fallback
-- ============================================================================

--- Recalculates and applies net physics override across all active modifiers for a player
---@param player ObjectRef Target player
local function recalculate_vanilla_physics(player)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	local mods = player_physics_modifiers[pname]
	local base = player_base_physics[pname]

	-- If no active modifiers remain, restore base physics cleanly
	if not mods or not next(mods) then
		if base then
			player:set_physics_override({
				speed = base.speed,
				jump = base.jump,
				gravity = base.gravity,
			})
			player_base_physics[pname] = nil
		end
		player_physics_modifiers[pname] = nil
		return
	end

	-- Compute compound factors
	local base_speed = base and base.speed or 1.0
	local base_jump = base and base.jump or 1.0
	local base_gravity = base and base.gravity or 1.0

	local speed_mult = 1.0
	local min_jump_factor = 1.0
	local has_jump_modifier = false
	local gravity_mult = 1.0
	local has_root = false

	for _, mod in pairs(mods) do
		if mod.speed_factor ~= nil then
			if mod.speed_factor <= 0 then
				has_root = true
			else
				speed_mult = speed_mult * mod.speed_factor
			end
		end
		if mod.jump_factor ~= nil then
			has_jump_modifier = true
			if mod.jump_factor <= 0 then
				min_jump_factor = 0.0
			else
				min_jump_factor = math.min(min_jump_factor, mod.jump_factor)
			end
		end
		if mod.gravity_factor ~= nil then
			gravity_mult = gravity_mult * mod.gravity_factor
		end
	end

	local net_speed = has_root and 0.0 or (base_speed * speed_mult)
	local net_jump
	if has_root or (has_jump_modifier and min_jump_factor <= 0) then
		net_jump = 0.0
	elseif has_jump_modifier then
		net_jump = base_jump * min_jump_factor
	else
		net_jump = base_jump
	end
	local net_gravity = base_gravity * gravity_mult

	player:set_physics_override({
		speed = net_speed,
		jump = net_jump,
		gravity = net_gravity,
	})
end

--- Applies or updates a physics modifier for a target player
---@param player ObjectRef Target player
---@param effect_id string Unique effect ID
---@param speed_factor? number Speed multiplier
---@param jump_factor? number Jump multiplier
---@param gravity_factor? number Gravity multiplier
local function apply_physics_modifier(player, effect_id, speed_factor, jump_factor, gravity_factor)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	local player_monoids = rawget(_G, "player_monoids")
	local pova = rawget(_G, "pova")
	local playerphysics = rawget(_G, "playerphysics")

	-- 1. player_monoids adapter
	if player_monoids and player_monoids.speed then
		if speed_factor ~= nil then
			player_monoids.speed:add_change(player, speed_factor, "x_mob_core:" .. effect_id)
		end
		if jump_factor ~= nil and player_monoids.jump then
			player_monoids.jump:add_change(player, jump_factor, "x_mob_core:" .. effect_id)
		end
		if gravity_factor ~= nil and player_monoids.gravity then
			player_monoids.gravity:add_change(player, gravity_factor, "x_mob_core:" .. effect_id)
		end
		return
	end

	-- 2. pova adapter
	if pova then
		local ovr = {}
		if speed_factor ~= nil then ovr.speed = speed_factor end
		if jump_factor ~= nil then
			ovr.jump = (jump_factor == 0) and -100 or jump_factor
		end
		if gravity_factor ~= nil then ovr.gravity = gravity_factor end
		pova.add_override(pname, "x_mob_core:" .. effect_id, ovr)
		pova.do_override(player)
		return
	end

	-- 3. playerphysics adapter
	if playerphysics then
		if speed_factor ~= nil then
			playerphysics.add_physics_factor(player, "speed", "x_mob_core:" .. effect_id, speed_factor)
		end
		if jump_factor ~= nil then
			playerphysics.add_physics_factor(player, "jump", "x_mob_core:" .. effect_id, jump_factor)
		end
		if gravity_factor ~= nil then
			playerphysics.add_physics_factor(player, "gravity", "x_mob_core:" .. effect_id, gravity_factor)
		end
		return
	end

	-- 4. Vanilla fallback with compound modifier stack
	if not player_physics_modifiers[pname] then
		player_physics_modifiers[pname] = {}
		local cur = player:get_physics_override() or {}
		player_base_physics[pname] = {
			speed = cur.speed or 1.0,
			jump = cur.jump or 1.0,
			gravity = cur.gravity or 1.0,
		}
	end

	player_physics_modifiers[pname][effect_id] = {
		speed_factor = speed_factor,
		jump_factor = jump_factor,
		gravity_factor = gravity_factor,
	}

	recalculate_vanilla_physics(player)
end

--- Removes a physics modifier for a target player
---@param player ObjectRef Target player
---@param effect_id string Unique effect ID
local function remove_physics_modifier(player, effect_id)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	local player_monoids = rawget(_G, "player_monoids")
	local pova = rawget(_G, "pova")
	local playerphysics = rawget(_G, "playerphysics")

	-- 1. player_monoids adapter
	if player_monoids and player_monoids.speed then
		player_monoids.speed:del_change(player, "x_mob_core:" .. effect_id)
		if player_monoids.jump then
			player_monoids.jump:del_change(player, "x_mob_core:" .. effect_id)
		end
		if player_monoids.gravity then
			player_monoids.gravity:del_change(player, "x_mob_core:" .. effect_id)
		end
		return
	end

	-- 2. pova adapter
	if pova then
		pova.del_override(pname, "x_mob_core:" .. effect_id)
		pova.do_override(player)
		return
	end

	-- 3. playerphysics adapter
	if playerphysics then
		playerphysics.remove_physics_factor(player, "speed", "x_mob_core:" .. effect_id)
		playerphysics.remove_physics_factor(player, "jump", "x_mob_core:" .. effect_id)
		playerphysics.remove_physics_factor(player, "gravity", "x_mob_core:" .. effect_id)
		return
	end

	-- 4. Vanilla fallback
	if player_physics_modifiers[pname] then
		player_physics_modifiers[pname][effect_id] = nil
		recalculate_vanilla_physics(player)
	end
end

--- Purges all x_mob_core status effect modifiers from active physics adapters and resets player physics cleanly
---@param player ObjectRef Target player
local function clear_all_player_physics(player)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	local player_monoids = rawget(_G, "player_monoids")
	local pova = rawget(_G, "pova")
	local playerphysics = rawget(_G, "playerphysics")

	-- 1. player_monoids adapter
	if player_monoids then
		if player_monoids.speed and player_monoids.speed.changes then
			local ch = player_monoids.speed.changes[player]
			if ch then
				for id in pairs(ch) do
					if type(id) == "string" and id:find("^x_mob_core:") then
						player_monoids.speed:del_change(player, id)
					end
				end
			end
		end
		if player_monoids.jump and player_monoids.jump.changes then
			local ch = player_monoids.jump.changes[player]
			if ch then
				for id in pairs(ch) do
					if type(id) == "string" and id:find("^x_mob_core:") then
						player_monoids.jump:del_change(player, id)
					end
				end
			end
		end
		if player_monoids.gravity and player_monoids.gravity.changes then
			local ch = player_monoids.gravity.changes[player]
			if ch then
				for id in pairs(ch) do
					if type(id) == "string" and id:find("^x_mob_core:") then
						player_monoids.gravity:del_change(player, id)
					end
				end
			end
		end
	end

	-- 2. pova adapter
	if pova and pova.get_modifiers then
		local ovrs = pova.get_modifiers(pname)
		if ovrs then
			for id in pairs(ovrs) do
				if type(id) == "string" and id:find("^x_mob_core:") then
					pova.del_override(pname, id)
				end
			end
			pova.do_override(player)
		end
	end

	-- 3. playerphysics adapter (clears all x_mob_core:* factors from persistent metadata)
	if playerphysics then
		local meta = player:get_meta()
		local raw_meta = meta:get_string("playerphysics:physics")
		if raw_meta and raw_meta ~= "" then
			local data = core.deserialize(raw_meta)
			if type(data) == "table" then
				local dirty = false
				for _, attr in ipairs({ "speed", "jump", "gravity" }) do
					if type(data[attr]) == "table" then
						for factor_id in pairs(data[attr]) do
							if type(factor_id) == "string" and factor_id:find("^x_mob_core:") then
								data[attr][factor_id] = nil
								dirty = true
							end
						end
					end
				end
				if dirty then
					meta:set_string("playerphysics:physics", core.serialize(data))
				end
				for _, attr in ipairs({ "speed", "jump", "gravity" }) do
					local product = 1.0
					if type(data[attr]) == "table" then
						for _, factor in pairs(data[attr]) do
							if type(factor) == "number" then
								product = product * factor
							end
						end
					end
					player:set_physics_override({ [attr] = product })
				end
			end
		else
			player:set_physics_override({ speed = 1.0, jump = 1.0, gravity = 1.0 })
		end
	end

	-- 4. Vanilla fallback cleanup
	player_physics_modifiers[pname] = nil
	local base = player_base_physics[pname]
	player_base_physics[pname] = nil

	local default_speed = 1.0
	local default_jump = 1.0
	local default_gravity = 1.0

	if base then
		if base.speed and base.speed >= 0.2 and base.speed <= 3.0 then
			default_speed = base.speed
		end
		if base.jump and base.jump >= 0.2 and base.jump <= 3.0 then
			default_jump = base.jump
		end
		if base.gravity and base.gravity >= 0.2 and base.gravity <= 3.0 then
			default_gravity = base.gravity
		end
	end

	if not player_monoids and not pova and not playerphysics then
		player:set_physics_override({
			speed = default_speed,
			jump = default_jump,
			gravity = default_gravity,
		})
	end
end

-- ============================================================================
-- 2.5 CAMERA FOV MODIFIER LAYER
-- Manages compound FOV adjustments and baseline capture/restoration
-- ============================================================================

--- Recalculates and applies net camera FOV override across all active status effect modifiers
---@param player ObjectRef Target player
---@param transition_time? number FOV transition smoothing time in seconds
local function recalculate_player_fov(player, transition_time)
	if not player or not player:is_player() then return end
	if not player.set_fov or not player.get_fov then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	local mods = player_fov_modifiers[pname]
	local base = player_base_fov[pname]

	-- If no active FOV modifiers remain, restore base FOV cleanly
	if not mods or not next(mods) then
		if base then
			player:set_fov(base.fov, base.is_multiplier, transition_time or 0.5)
			player_base_fov[pname] = nil
		else
			player:set_fov(0, false, transition_time or 0.5)
		end
		player_fov_modifiers[pname] = nil
		return
	end

	-- Compute compound FOV factor across all active status effect modifiers
	local compound_factor = 1.0
	local trans_time = transition_time or 0.2
	for _, mod in pairs(mods) do
		if mod.fov_factor and mod.fov_factor > 0 then
			compound_factor = compound_factor * mod.fov_factor
		end
		if mod.transition_time then
			trans_time = math.min(trans_time, mod.transition_time)
		end
	end

	-- Apply compounded factor on top of existing base override without clobbering it
	if not base or base.fov == 0 then
		player:set_fov(compound_factor, true, trans_time)
	elseif base.is_multiplier then
		player:set_fov(base.fov * compound_factor, true, trans_time)
	else
		player:set_fov(base.fov * compound_factor, false, trans_time)
	end
end

--- Applies or updates a camera FOV modifier for a target player
---@param player ObjectRef Target player
---@param effect_id string Unique effect ID
---@param fov_factor number Camera FOV multiplier (e.g. 0.85)
---@param transition_time? number Smoothing transition time in seconds
local function apply_fov_modifier(player, effect_id, fov_factor, transition_time)
	if not player or not player:is_player() then return end
	if not player.set_fov or not player.get_fov then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	if not player_fov_modifiers[pname] then
		player_fov_modifiers[pname] = {}
		local cur_fov, cur_is_mult = player:get_fov()
		player_base_fov[pname] = {
			fov = cur_fov or 0,
			is_multiplier = (cur_is_mult == true),
		}
	end

	player_fov_modifiers[pname][effect_id] = {
		fov_factor = fov_factor,
		transition_time = transition_time or 0.2,
	}

	recalculate_player_fov(player, transition_time or 0.2)
end

--- Removes a camera FOV modifier for a target player
---@param player ObjectRef Target player
---@param effect_id string Unique effect ID
---@param transition_time? number Smoothing transition time in seconds
local function remove_fov_modifier(player, effect_id, transition_time)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	if not pname or pname == "" then return end

	if player_fov_modifiers[pname] then
		player_fov_modifiers[pname][effect_id] = nil
		recalculate_player_fov(player, transition_time or 0.5)
	end
end

-- ============================================================================
-- 3. STATUS EFFECT CORE API
-- ============================================================================

--- Normalizes status effect parameters based on archetype defaults
---@param def StatusEffectDef Input effect definition
---@return StatusEffectDef normalized Clean normalized definition
local function normalize_effect_def(def)
	local envelop_texture = def.envelop_texture
	if not envelop_texture and type(def.envelop) == "table" then
		envelop_texture = def.envelop.texture
	end

	local effect_type = def.type or "custom"
	local particles_def = def.particles or def.particle_spawner
	local norm = {
		id = def.id or def.name,
		type = effect_type,
		chance = def.chance,
		duration = def.duration or 3.0,
		speed_factor = def.speed_factor,
		jump_factor = def.jump_factor or def.jump_modifier,
		gravity_factor = def.gravity_factor,
		fov_factor = def.fov_factor,
		fov_duration = def.fov_duration,
		fov_transition = def.fov_transition or 0.2,
		damage = def.damage,
		interval = def.interval,
		damage_type = def.damage_type,
		caster = def.caster,
		penetrate_armor = (def.penetrate_armor ~= nil) and def.penetrate_armor or (effect_type == "dot"),
		particles = particles_def,
		playername = def.playername,
		on_tick_particles = def.on_tick_particles,
		envelop_texture = envelop_texture,
		hud_vignette = def.hud_vignette or def.vignette,
		cleanse_in_water = def.cleanse_in_water,
		drain_hunger = def.drain_hunger,
		anti_heal = def.anti_heal,
		damage_multiplier = def.damage_multiplier,
		on_apply = def.on_apply,
		on_step = def.on_step,
		on_tick = def.on_tick,
		on_remove = def.on_remove,
	}

	if norm.type == "slow" then
		if norm.speed_factor == nil then norm.speed_factor = 0.5 end
	elseif norm.type == "root" then
		norm.speed_factor = 0.0
		norm.jump_factor = 0.0
	elseif norm.type == "dot" then
		if norm.damage == nil then norm.damage = 1 end
		if norm.interval == nil then norm.interval = 1.0 end
		if norm.damage_type == nil then norm.damage_type = "fleshy" end
	elseif norm.type == "debuff" then
		if norm.drain_hunger and norm.interval == nil then
			norm.interval = 1.0
		end
	end

	-- Ensure any effect providing periodic actions defaults to 1.0s interval
	if (norm.drain_hunger or norm.on_tick or norm.on_tick_particles) and norm.interval == nil then
		norm.interval = 1.0
	end

	return norm
end


--- Schedules a recursive DoT ticker for an active DoT status effect
---@param target ObjectRef Target victim
---@param effect_id string Unique effect ID
---@param token string|integer Token to validate against refresh/cancellation
---@param interval number Tick interval in seconds
---@param damage number Damage per tick
---@param damage_type string Damage group
---@param caster? ObjectRef Punch source
---@param penetrate_armor? boolean Armor bypass
---@param on_tick? fun(target: ObjectRef) Periodic callback
---@param particle_spawner? table|fun(target: ObjectRef):table Particle spawner
local function schedule_dot_tick(
	target,
	effect_id,
	token,
	interval,
	damage,
	damage_type,
	caster,
	penetrate_armor,
	on_tick,
	particle_spawner
)
	core.after(interval, function()
		if not target or not target:is_valid() then return end
		local key = get_target_key(target)
		if not key or not active_effects[key] then return end

		local record = active_effects[key][effect_id]
		if not record or record.token ~= token then return end

		-- Check if target is already dead
		if (target.is_player and target:is_player() and target:get_hp() <= 0) or
		   (target.get_hp and target:get_hp() <= 0) then
			status_effects.remove_effect(target, effect_id)
			return
		end

		-- Check water immersion cleansing (e.g. for ignite/burning)
		if record.cleanse_in_water and target:is_valid() then
			local pos = target:get_pos()
			if pos then
				local node = core.get_node(pos)
				local node_below = core.get_node({x = pos.x, y = pos.y - 0.5, z = pos.z})
				if (node and core.get_item_group(node.name, "water") > 0) or
				   (node_below and core.get_item_group(node_below.name, "water") > 0) then
					core.sound_play("default_cool_lava", {pos = pos, gain = 0.5, max_hear_distance = 16}, true)
					core.add_particlespawner({
						amount = 8,
						time = 0.2,
						pos = {
							min = {x = pos.x - 0.3, y = pos.y, z = pos.z - 0.3},
							max = {x = pos.x + 0.3, y = pos.y + 0.8, z = pos.z + 0.3}
						},
						vel = {min = {x = -0.2, y = 0.5, z = -0.2}, max = {x = 0.2, y = 1.2, z = 0.2}},
						texture = "smoke_puff.png^[opacity:160",
					})
					status_effects.remove_effect(target, effect_id)
					return
				end
			end
		end

		-- Drain hunger / stamina on tick if configured
		if record.drain_hunger and target:is_player() then
			x_mob_core.hunger_adapter.drain(target, record.drain_hunger, "x_mob_core:" .. effect_id)
		end

		-- Run particle spawner if provided
		if particle_spawner then
			local ps_def = type(particle_spawner) == "function" and particle_spawner(target) or particle_spawner
			if type(ps_def) == "table" then
				core.add_particlespawner(ps_def)
			end
		end

		-- Run on_tick callback if provided
		if on_tick then
			local ok, err = pcall(on_tick, target, caster)
			if not ok then
				core.log("error", string.format(
					"[x_mob_core] Status effect '%s' on_tick callback failed: %s",
					tostring(effect_id), tostring(err)))
			end
		end

		-- Deal DoT damage if configured
		if damage and damage > 0 then
			local punch_source = (caster and caster:is_valid()) and caster or target
			local old_groups = (target.get_armor_groups and target:get_armor_groups()) or {}
			local is_immortal = (old_groups.immortal and old_groups.immortal > 0)
			local modified_armor = false

			if not is_immortal then
				if penetrate_armor and old_groups[damage_type] ~= 100 then
					local temp_groups = utils.shallow_copy(old_groups)
					temp_groups[damage_type] = 100
					target:set_armor_groups(temp_groups)
					modified_armor = true
				end

				target:punch(punch_source, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = { [damage_type] = damage },
				}, { x = 0, y = 0, z = 0 })

				if modified_armor and target:is_valid() then
					target:set_armor_groups(old_groups)
				end
			end

			-- Check if target died from punch
			if not target:is_valid() or
			   (target.is_player and target:is_player() and target:get_hp() <= 0) or
			   (target.get_hp and target:get_hp() <= 0) then
				status_effects.remove_effect(target, effect_id)
				return
			end
		end

		-- Schedule next tick or natural expiration
		local remaining = record.timer - interval
		if remaining >= interval - 0.001 then
			record.timer = remaining
			schedule_dot_tick(
				target,
				effect_id,
				token,
				interval,
				damage,
				damage_type,
				caster,
				penetrate_armor,
				on_tick,
				particle_spawner
			)
		elseif remaining > 0.001 then
			core.after(remaining, function()
				if not target or not target:is_valid() then return end
				local k = get_target_key(target)
				if not k or not active_effects[k] then return end
				local rec = active_effects[k][effect_id]
				if rec and rec.token == token then
					status_effects.remove_effect(target, effect_id)
				end
			end)
		else
			status_effects.remove_effect(target, effect_id)
		end
	end)
end

--- Applies or updates a status effect on target (player or mob entity)
---@param target ObjectRef Target player or entity
---@param effect_def StatusEffectDef Status effect definition table
---@return ObjectRef|boolean result Envelop object if envelop attached, or true on success
function status_effects.apply_effect(target, effect_def)
	if not target or not target:is_valid() then return false end
	local eff_id = effect_def and (effect_def.id or effect_def.name)
	if not eff_id or eff_id == "" then return false end

	local norm = normalize_effect_def(effect_def)
	if norm.chance ~= nil then
		local prob = (norm.chance > 1.0) and (norm.chance / 100.0) or norm.chance
		if prob < 1.0 and (prob <= 0.0 or math.random() > prob) then
			return false
		end
	end

	local key = get_target_key(target)
	if not key then return false end

	if not active_effects[key] then
		active_effects[key] = {}
	end

	local token = x_mob_core.generate_uuid()
	local is_player = target:is_player()

	-- Do not apply status effects to attached accessories (wield items, armor meshes, proxies)
	if not is_player then
		if target.get_attach and target:get_attach() ~= nil then
			return false
		end
		local ent = target.get_luaentity and target:get_luaentity()
		if ent then
			if ent._is_wielditem or ent._is_visual_proxy or ent._is_envelop or ent._is_health_bar then
				return false
			end
			local name = ent.name or ""
			if name:find("wield") or name:find("^x_player_api:visual") or name:find("^__builtin:") then
				return false
			end
		end
	end

	-- Clean up previous spawner if refreshing an existing effect
	local existing = active_effects[key][norm.id]
	if existing and existing.spawner_id then
		x_mob_core.particles.delete(target, existing.spawner_id, existing.spawner_playername)
	end

	-- Attach continuous particle spawner if specified
	local spawner_id = nil
	if norm.particles then
		local p_def = type(norm.particles) == "function" and norm.particles(target) or norm.particles
		if type(p_def) == "table" then
			spawner_id = x_mob_core.particles.attach(target, p_def, norm.playername or p_def.playername)
		end
	end

	local record = {
		id = norm.id,
		type = norm.type,
		duration = norm.duration,
		timer = norm.duration,
		token = token,
		speed_factor = norm.speed_factor,
		jump_factor = norm.jump_factor,
		gravity_factor = norm.gravity_factor,
		fov_factor = norm.fov_factor,
		fov_duration = norm.fov_duration,
		fov_transition = norm.fov_transition,
		damage = norm.damage,
		interval = norm.interval,
		damage_type = norm.damage_type,
		caster = norm.caster,
		penetrate_armor = norm.penetrate_armor,
		particles = norm.particles,
		spawner_id = spawner_id,
		spawner_playername = norm.playername,
		on_tick_particles = norm.on_tick_particles,
		envelop_texture = norm.envelop_texture,
		has_envelop = norm.envelop_texture ~= nil,
		hud_vignette = norm.hud_vignette,
		cleanse_in_water = norm.cleanse_in_water,
		drain_hunger = norm.drain_hunger,
		anti_heal = norm.anti_heal,
		damage_multiplier = norm.damage_multiplier,
		on_apply = norm.on_apply,
		on_step = norm.on_step,
		on_tick = norm.on_tick,
		on_remove = norm.on_remove,
		target = target,
	}

	active_effects[key][norm.id] = record

	-- Apply physics modifier for players if requested
	if is_player and (norm.speed_factor ~= nil or norm.jump_factor ~= nil or norm.gravity_factor ~= nil) then
		apply_physics_modifier(target, norm.id, norm.speed_factor, norm.jump_factor, norm.gravity_factor)
	end

	-- Apply camera FOV modifier for players if requested
	if is_player and norm.fov_factor ~= nil then
		apply_fov_modifier(target, norm.id, norm.fov_factor, norm.fov_transition)

		if norm.fov_duration and norm.fov_duration > 0 and norm.fov_duration < norm.duration then
			core.after(norm.fov_duration, function()
				if not target or not target:is_valid() then return end
				local tkey = get_target_key(target)
				if not tkey or not active_effects[tkey] then return end
				local act = active_effects[tkey][norm.id]
				if act and act.token == token then
					remove_fov_modifier(target, norm.id, norm.fov_transition or 0.5)
				end
			end)
		end
	end

	-- If rooted or immobilized (speed_factor <= 0), halt momentum immediately and lock movement
	if is_player and (norm.type == "root" or (norm.speed_factor and norm.speed_factor <= 0.0)) then
		local cur_v = target.get_velocity and target:get_velocity()
		if cur_v and (cur_v.x ~= 0 or cur_v.z ~= 0 or cur_v.y > 0) and target.add_velocity then
			local add_y = cur_v.y > 0 and -cur_v.y or 0
			target:add_velocity({ x = -cur_v.x, y = add_y, z = -cur_v.z })
		end
		local pname = target:get_player_name()
		if pname and pname ~= "" then
			rooted_players[pname] = true
		end
		local x_player_api = rawget(_G, "x_player_api")
		local player_api = rawget(_G, "player_api")
		if x_player_api and x_player_api.set_animation then
			x_player_api.set_animation(target, "stand", nil, true, true)
		elseif player_api and player_api.set_animation then
			player_api.set_animation(target, "stand")
		end
	elseif not is_player and (norm.type == "root" or (norm.speed_factor and norm.speed_factor <= 0.0)) then
		local ent = target.get_luaentity and target:get_luaentity()
		if ent and ent._is_mob then
			x_mob_core.halt_horizontal_velocity(ent)
		elseif target.set_velocity then
			target:set_velocity({ x = 0, y = 0, z = 0 })
		end
	end

	-- Apply responsive HUD screen vignette for players if specified or preset registered
	if is_player then
		local vig = norm.hud_vignette
		if vig and vig ~= true then
			x_mob_core.hud_effects.apply(target, norm.id, vig)
		elseif vig == true or x_mob_core.hud_effects.has_preset(norm.id) then
			x_mob_core.hud_effects.apply(target, norm.id)
		end
	end

	-- Suppress healing for players if anti_heal specified
	if is_player and norm.anti_heal then
		x_mob_core.hunger_adapter.suppress_healing(target, norm.duration)
	end

	-- Bind to visual envelop subsystem if texture is specified
	local envelop_obj = nil
	if norm.envelop_texture then
		envelop_obj = x_mob_core.apply_envelop(target, {
			id = norm.id,
			duration = norm.duration,
			texture = norm.envelop_texture,
			on_step = norm.on_step,
			on_remove = function(t)
				status_effects.remove_effect(t, norm.id, true)
			end,
		})
	end

	-- Invoke on_apply callback if provided
	if norm.on_apply then
		norm.on_apply(target)
	end

	-- Schedule periodic ticker if applicable (DoT damage, hunger/stamina drain, on_tick callback)
	local has_ticker = (norm.interval and norm.interval > 0) and
		((norm.damage and norm.damage > 0) or
		 (norm.drain_hunger and norm.drain_hunger > 0) or
		 norm.on_tick ~= nil or
		 norm.on_tick_particles ~= nil)

	-- Always schedule an authoritative failsafe expiration timer via core.after.
	-- For ticking effects, an extra 0.1s grace period allows the final periodic tick to resolve.
	-- This guarantees that regardless of periodic ticker errors, pauses, or desyncs,
	-- the status effect and all associated physics/visual modifiers are strictly expired.
	local failsafe_duration = has_ticker and (norm.duration + 0.1) or norm.duration
	core.after(failsafe_duration, function()
		if not target or not target:is_valid() then return end
		local k = get_target_key(target)
		if not k or not active_effects[k] then return end
		local rec = active_effects[k][norm.id]
		if rec and rec.token == token then
			status_effects.remove_effect(target, norm.id)
		end
	end)

	if has_ticker then
		schedule_dot_tick(
			target,
			norm.id,
			token,
			norm.interval,
			norm.damage,
			norm.damage_type or "fleshy",
			norm.caster,
			norm.penetrate_armor,
			norm.on_tick,
			norm.on_tick_particles
		)
	end

	return envelop_obj or true
end

--- Removes an active status effect from target
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID
---@param from_envelop? boolean Internal flag to prevent recursive envelop removal calls
---@return boolean success True if effect was active and removed
function status_effects.remove_effect(target, effect_id, from_envelop)
	if not target then return false end
	local key = get_target_key(target)
	if not key or not active_effects[key] then return false end

	local record = active_effects[key][effect_id]
	if not record then return false end

	active_effects[key][effect_id] = nil
	if not next(active_effects[key]) then
		active_effects[key] = nil
	end

	-- Delete attached particle spawner if present
	if record.spawner_id then
		x_mob_core.particles.delete(target, record.spawner_id, record.spawner_playername)
		record.spawner_id = nil
	end

	-- Remove physics modifier if player
	if target:is_player() then
		remove_physics_modifier(target, effect_id)
		local pname = target:get_player_name()
		if pname and pname ~= "" and not status_effects.is_rooted(target) then
			rooted_players[pname] = nil
		end
	end

	-- Revert camera FOV modifier if player
	if target:is_player() and record.fov_factor ~= nil then
		remove_fov_modifier(target, effect_id, record.fov_transition or 0.5)
	end

	-- Clean up visual envelop effect if attached and not called from envelop callback
	if record.has_envelop and not from_envelop then
		x_mob_core.remove_envelop_effect(target, effect_id)
	end

	-- Remove HUD screen vignette if present
	if target:is_player() then
		x_mob_core.hud_effects.remove(target, effect_id)
	end

	-- Invoke on_remove callback if provided
	if record.on_remove then
		record.on_remove(target)
	end

	return true
end

--- Checks if target currently has a specific active status effect
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID
---@return boolean has_effect True if effect is active
function status_effects.has_effect(target, effect_id)
	if not target then return false end
	local key = get_target_key(target)
	if not key or not active_effects[key] then return false end
	return active_effects[key][effect_id] ~= nil
end

--- Checks if target (player or mob entity) is currently rooted / immobilized
---@param target ObjectRef Target player or entity
---@return boolean is_rooted True if target has an active root status effect or speed_factor <= 0
function status_effects.is_rooted(target)
	if not target then return false end
	local key = get_target_key(target)
	if not key or not active_effects[key] then return false end
	for _, rec in pairs(active_effects[key]) do
		if rec.type == "root" or (rec.speed_factor and rec.speed_factor <= 0.0) then
			return true
		end
	end
	return false
end

--- Retrieves all active status effects for a target
---@param target ObjectRef Target player or entity
---@return table<string, ActiveEffectRecord>? effects Map of active effects
function status_effects.get_effects(target)
	if not target then return nil end
	local key = get_target_key(target)
	if not key then return nil end
	return active_effects[key]
end

--- Computes compound damage multiplier across all active status effects for a target
---@param target ObjectRef Target player or entity
---@return number multiplier Net damage multiplier (defaults to 1.0)
function status_effects.get_damage_multiplier(target)
	if not target then return 1.0 end
	local key = get_target_key(target)
	if not key or not active_effects[key] then return 1.0 end
	local mult = 1.0
	for _, rec in pairs(active_effects[key]) do
		if rec.damage_multiplier and rec.damage_multiplier > 0 then
			mult = mult * rec.damage_multiplier
		end
	end
	return mult
end

--- Clears all active status effects and restores clean physics on target
---@param target ObjectRef Target player or entity
function status_effects.clear_effects(target)
	if not target then return end
	local key = get_target_key(target)
	if key and active_effects[key] then
		local list = {}
		for id, rec in pairs(active_effects[key]) do
			table.insert(list, { id = id, rec = rec })
		end

		for _, item in ipairs(list) do
			status_effects.remove_effect(target, item.id)
		end

		active_effects[key] = nil
	end

	x_mob_core.particles.clear_target(target)

	if target:is_player() then
		x_mob_core.hud_effects.clear(target)
		x_mob_core.hunger_adapter.clear_suppression(target)
		local pname = target:get_player_name()
		if pname and pname ~= "" then
			rooted_players[pname] = nil
			clear_all_player_physics(target)

			if player_fov_modifiers[pname] then
				local base_fov = player_base_fov[pname]
				if target.set_fov then
					if base_fov then
						target:set_fov(base_fov.fov, base_fov.is_multiplier, 0.2)
					else
						target:set_fov(0, false, 0.2)
					end
				end
				player_base_fov[pname] = nil
				player_fov_modifiers[pname] = nil
			end
		end
	end
end

-- ============================================================================
-- 4. LIFECYCLE & COMBAT INTERACTION LISTENERS
-- ============================================================================

-- Intercept player punches to apply brittle damage amplification and pickaxe shatter
core.register_on_punchplayer(function(player, hitter, _time_from_last_punch, _tool_capabilities, _dir, damage)
	if not player or not player:is_valid() then return end

	-- Check pickaxe shatter synergy for crystallize
	if status_effects.has_effect(player, "crystallize") then
		local is_pickaxe = false
		if hitter and hitter:is_valid() and hitter:is_player() then
			local wielded = hitter:get_wielded_item()
			if wielded and not wielded:is_empty() then
				local iname = wielded:get_name()
				local idef = core.registered_items[iname]
				local caps = idef and idef.tool_capabilities
				if (caps and caps.groupcaps and caps.groupcaps.cracky)
						or (core.get_item_group(iname, "pickaxe") > 0) then
					is_pickaxe = true
				end
			end
		end
		if is_pickaxe then
			status_effects.remove_effect(player, "crystallize")
			local pos = player:get_pos()
			if pos then
				core.sound_play("x_mobs_crystal_guardian_hurt", {
					pos = pos,
					gain = 1.0,
					pitch = 1.4,
					max_hear_distance = 24.0,
				}, true)
				core.add_particlespawner({
					amount = 24,
					time = 0.1,
					pos = {
						min = {x = pos.x - 0.4, y = pos.y, z = pos.z - 0.4},
						max = {x = pos.x + 0.4, y = pos.y + 1.2, z = pos.z + 0.4}
					},
					vel = {min = {x = -3, y = 1, z = -3}, max = {x = 3, y = 4, z = 3}},
					texture = "x_mob_core_sparkle.png^[multiply:#55FFFF",
					glow = 12,
				})
			end
		end
	end

	-- Apply incoming status effect damage multiplier (e.g. brittle / crystallize)
	local mult = status_effects.get_damage_multiplier(player)
	if mult and mult > 1.0 and damage and damage > 0 then
		local extra_dmg = math.floor(damage * (mult - 1.0) + 0.5)
		if extra_dmg > 0 then
			local cur_hp = player:get_hp()
			if cur_hp > extra_dmg then
				player:set_hp(cur_hp - extra_dmg)
			else
				player:punch(hitter or player, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = { fleshy = extra_dmg },
				}, { x = 0, y = 0, z = 0 })
			end
		end
	end
end)


core.register_on_joinplayer(function(player)
	status_effects.clear_effects(player)
end)

core.register_on_dieplayer(function(player)
	status_effects.clear_effects(player)
end)

core.register_on_respawnplayer(function(player)
	status_effects.clear_effects(player)
end)

core.register_on_leaveplayer(function(player)
	status_effects.clear_effects(player)
end)

core.register_on_shutdown(function()
	for _, player in ipairs(core.get_connected_players()) do
		status_effects.clear_effects(player)
	end
end)

-- Enforce continuous zero-velocity clamping on rooted players to eliminate physics drift
local root_step_timer = 0
core.register_globalstep(function(dtime)
	if not next(rooted_players) then return end
	root_step_timer = root_step_timer + dtime
	if root_step_timer < 0.1 then return end
	root_step_timer = 0

	for pname in pairs(rooted_players) do
		local p = core.get_player_by_name(pname)
		if p and p:is_valid() then
			local v = p.get_velocity and p:get_velocity()
			if v and (math.abs(v.x) > 0.05 or math.abs(v.z) > 0.05 or v.y > 0.1) and p.add_velocity then
				local cancel_y = v.y > 0.1 and -v.y or 0
				p:add_velocity({ x = -v.x, y = cancel_y, z = -v.z })
			end
		else
			rooted_players[pname] = nil
		end
	end
end)

-- Register high-priority locomotion evaluator with x_player_api to force stand posture when rooted
local function register_root_locomotion_evaluator()
	local x_player_api = rawget(_G, "x_player_api")
	if x_player_api and x_player_api.register_locomotion_evaluator then
		x_player_api.register_locomotion_evaluator(100, function(player, _ctx)
			if status_effects.is_rooted(player) then
				return "stand"
			end
		end)
	end
end

core.register_on_mods_loaded(register_root_locomotion_evaluator)

-- ============================================================================
-- 5. PUBLIC API EXPORTS
-- ============================================================================

---Applies or refreshes a status effect on target (player or mob entity).
---@param target ObjectRef Target player or entity
---@param effect_def StatusEffectDef Status effect definition table
---@return ObjectRef|boolean result Envelop object if envelop attached, or true on success
function x_mob_core.apply_status_effect(target, effect_def)
	return status_effects.apply_effect(target, effect_def)
end

---Removes an active status effect from target.
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID to remove
---@return boolean success True if effect was removed
function x_mob_core.remove_status_effect(target, effect_id)
	return status_effects.remove_effect(target, effect_id)
end

---Checks if target currently has an active status effect.
---@param target ObjectRef Target player or entity
---@param effect_id string Unique effect ID
---@return boolean has_effect True if effect is active
function x_mob_core.has_status_effect(target, effect_id)
	return status_effects.has_effect(target, effect_id)
end

---Checks if target is currently rooted / immobilized.
---@param target ObjectRef Target player or entity
---@return boolean is_rooted True if target has an active root status effect or speed_factor <= 0
function x_mob_core.is_rooted(target)
	return status_effects.is_rooted(target)
end

---Retrieves all active status effects for a target.
---@param target ObjectRef Target player or entity
---@return table? effects Active status effects map
function x_mob_core.get_status_effects(target)
	return status_effects.get_effects(target)
end

---Clears all active status effects and restores baseline physics on target.
---@param target ObjectRef Target player or entity
function x_mob_core.clear_status_effects(target)
	return status_effects.clear_effects(target)
end

---Retrieves compound damage multiplier across all active status effects on target.
---@param target ObjectRef Target player or entity
---@return number multiplier Compound damage multiplier
function x_mob_core.get_damage_multiplier(target)
	return status_effects.get_damage_multiplier(target)
end

return status_effects
