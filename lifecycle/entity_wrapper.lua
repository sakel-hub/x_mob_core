--[[
	x_mob_core - Entity Registration Wrapper
	Standardizes entity definition, validates physics, provides smart defaults,
	and wires up pack, state machine, memory, combat, and persistence hooks.
]]

---@class EntityWrapperSubsystem
---@field registered_mobs table<string, MobRegistrationDef>
local entity_wrapper = {
	registered_mobs = {},
}

local modpath = core.get_modpath("x_mob_core")
local squad = dofile(modpath .. "/pack/squad.lua")
local state_machine = dofile(modpath .. "/lifecycle/state_machine.lua")
local detachment = dofile(modpath .. "/combat/detachment.lua")
local mob_memory = dofile(modpath .. "/navigation/mob_memory.lua")
local animator = dofile(modpath .. "/animation/animator.lua")
local utils = dofile(modpath .. "/core/utils.lua")
local effects = dofile(modpath .. "/combat/effects.lua")
local coordination = dofile(modpath .. "/pack/coordination.lua")
local safety = dofile(modpath .. "/motor/safety.lua")
local locomotion = dofile(modpath .. "/motor/locomotion.lua")
local mob_ai = dofile(modpath .. "/motor/mob_ai.lua")
local sound = dofile(modpath .. "/audio/sound.lua")
local loot = dofile(modpath .. "/combat/loot.lua")
local shooter = dofile(modpath .. "/combat/shooter.lua")
local factions = dofile(modpath .. "/combat/factions.lua")
local swarm = dofile(modpath .. "/pack/swarm.lua")
local shoal = dofile(modpath .. "/pack/shoal.lua")

-- Focused lifecycle submodules (Single Responsibility Principle)
local pipeline = dofile(modpath .. "/lifecycle/pipeline.lua")
local culling = dofile(modpath .. "/lifecycle/culling.lua")
local combat_handler = dofile(modpath .. "/lifecycle/combat_handler.lua")
local properties = dofile(modpath .. "/lifecycle/properties.lua")
local environment = dofile(modpath .. "/lifecycle/environment.lua")
local health_bar = dofile(modpath .. "/combat/health_bar.lua")

entity_wrapper.pipeline = pipeline
entity_wrapper.culling = culling
entity_wrapper.combat_handler = combat_handler
entity_wrapper.properties = properties
entity_wrapper.environment = environment
entity_wrapper.set_texture = properties.set_texture
entity_wrapper.normalize_texture_variations = properties.normalize_texture_variations
entity_wrapper.set_armor_groups = properties.set_armor_groups
entity_wrapper.handle_punch = combat_handler.handle_punch

-- Register core step pipeline hooks (Open/Closed Principle)
-- Priority 20: Shooter Auto-Combat
pipeline.register_step_hook("shooter", 20, function(self, dtime, def)
	if def.shooter and self.target and self.state ~= "flinching" then
		return shooter.step(self, dtime, def)
	end
	return false
end)

-- Priority 25: Environmental Hazards & Node Damage (Lava, Fire, Drowning, Suffocation)
pipeline.register_step_hook("environment", 25, function(self, dtime, def)
	return environment.step(self, dtime, def, combat_handler)
end)

-- Priority 30: Pack Cluster Spawning (Shoals, Swarms, Squads)
pipeline.register_step_hook("pack_cluster", 30, function(self, _, def)
	if self._needs_cluster_spawning then
		self._needs_cluster_spawning = false
		squad.spawn_cluster(self, def)
	end
	return false
end)

-- Swarm Intelligence Navigation
pipeline.register_step_hook("swarm_nav", 40, function(self, dtime, def)
	if def.swarm and def.swarm.enabled ~= false and not self.is_dead and self.state ~= "flinching" then
		if not def._has_custom_step then
			return swarm.step(self, dtime, def)
		end
	end
	return false
end)

-- Shoal Intelligence Navigation & Anchor Steering
pipeline.register_step_hook("shoal_nav", 42, function(self, dtime, def)
	if def.shoal and def.shoal.enabled ~= false and not self.is_dead and self.state ~= "flinching" then
		if not def._has_custom_step then
			return shoal.step(self, dtime, def)
		end
	end
	return false
end)

---Sets the current target and fires on_mob_target event if target changed.
---@param self table Mob entity instance
---@param target ObjectRef|nil Target entity or player
---@return boolean changed True if target changed
function entity_wrapper.set_target(self, target)
	local old_target = self.target
	if old_target == target then return false end
	self.target = target
	x_mob_core.emit("on_mob_target", self, target, old_target)
	return true
end

---Universal step lifecycle handler.
---Manages death countdown, buoyancy, target validation, timers, action completions, and idle navigation.
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param def table Entity definition table
---@return boolean handled True if step was fully handled (e.g. dying or action-locked)
function entity_wrapper.handle_core_step(self, dtime, def)
	-- Damage flash recovery timer
	if self._damage_flash_timer then
		self._damage_flash_timer = self._damage_flash_timer - dtime
		if self._damage_flash_timer <= 0 then
			effects.clear_damage(self.object)
		end
	end

	-- Regeneration flash recovery timer
	if self._regen_flash_timer then
		self._regen_flash_timer = self._regen_flash_timer - dtime
		if self._regen_flash_timer <= 0 then
			effects.clear_regen(self.object)
		end
	end

	-- Health bar auto-hide countdown timer
	if self._health_bar_timer and self._health_bar_timer > 0 then
		self._health_bar_timer = self._health_bar_timer - dtime
		if self._health_bar_timer <= 0 then
			health_bar.on_timeout(self, def)
		end
	end

	-- Knockback flight timer countdown
	if self._knockback_timer then
		self._knockback_timer = self._knockback_timer - dtime
		if self._knockback_timer <= 0 or (self._moveresult and self._moveresult.touching_ground) then
			self._knockback_timer = nil
		end
	end

	-- Distance, daylight, and diurnal cycle culling (SRP delegated)
	if culling.step_culling(self, dtime, def) then
		return true
	end

	-- Death despawn countdown
	if self.is_dead or self.state == "dying" then
		if self._damage_flash_timer then
			effects.clear_damage(self.object)
		end
		if self._regen_flash_timer then
			effects.clear_regen(self.object)
		end
		if self._health_bar_obj then
			health_bar.remove(self)
		end
		combat_handler.apply_death_settling_physics(self)
		self.action_timer = (self.action_timer or 1.5) - dtime
		if self.action_timer <= 0 then
			-- Spawn drops now that the death animation is done
			if def.drops and not self._drops_spawned then
				self._drops_spawned = true
				loot.spawn_mob_drops(self, self._killer, def.drops, def.drop_options)
			end

			culling.remove_mob(self, def, "death_completed")
			detachment.detach_attached_children(self.object)
			return true
		end
		return true
	end

	-- Liquid buoyancy update (bypassed for shoal mobs with self-contained 3D aquatic locomotion)
	local is_shoal_mob = (def and def.shoal and def.shoal.enabled ~= false) or (self.shoal ~= nil)
	if not is_shoal_mob then
		local in_water, _, water_vy = locomotion.apply_liquid_buoyancy(self, dtime)
		self.in_water = in_water
		self.water_vy = water_vy
	else
		self.in_water = true
		self.water_vy = 0
	end

	-- Invalidate dead or disconnected targets
	local is_target_alive = utils.is_player_alive(self.target)
	if self.target and not is_target_alive then
		entity_wrapper.set_target(self, nil)
		mob_memory.clear_target_memory(self)
		if self.path_state then
			self.path_state.waypoints = nil
			self.path_state.index = 1
		end
		local is_fleeing = (self.state == "fleeing") or (self.panic_timer and self.panic_timer > 0)
		if not is_fleeing and self.state ~= "idle" then
			self.state = "idle"
			animator.play(self.object, "idle", {speed = 1.0, loop = true})
		end
	end

	-- Animation initialization safeguard
	if not self._anim_initialized then
		self._anim_initialized = true
		if not self._current_track and self.state ~= "fleeing" then
			animator.play(self.object, "idle", {speed = 1.0, loop = true, force = true})
		end
	end

	-- Decrement timers and cooldowns (LuaJIT trace-optimized: avoid pairs() on idle mobs)
	self.scan_timer = (self.scan_timer or 0) + dtime
	if self.attack_cooldown then
		self.attack_cooldown = math.max(0, self.attack_cooldown - dtime)
	end
	if self.panic_timer and self.panic_timer > 0 then
		self.panic_timer = math.max(0, self.panic_timer - dtime)
	end
	if self.cooldowns then
		for k, v in pairs(self.cooldowns) do
			if v > 0 then
				local nv = v - dtime
				self.cooldowns[k] = (nv > 0) and nv or 0
			end
		end
	end

	-- Scheduled actions (with abort on flinch)
	if self._scheduled_actions then
		if self.state == "flinching" then
			self._scheduled_actions = {}
		else
			for i = #self._scheduled_actions, 1, -1 do
				local action = self._scheduled_actions[i]
				action.timer = action.timer - dtime
				if action.timer <= 0 then
					table.remove(self._scheduled_actions, i)
					if not self.is_dead and self.object and self.object:is_valid() then
						action.callback(self)
					end
				end
			end
		end
	end

	-- Declarative state transitions
	if def.transitions then
		for _, trans in ipairs(def.transitions) do
			if self.state == trans.from or trans.from == "*" then
				if trans.condition(self) then
					self.state = trans.to
					if trans.on_transition then
						trans.on_transition(self)
					end
					break
				end
			end
		end
	end

	-- Action timer completion
	if self.action_timer and self.action_timer > 0 then
		self.action_timer = self.action_timer - dtime
		if not self.is_floating and not self.in_water and not self.on_wall_or_ceiling and self.object then
			self.object:set_acceleration({x = 0, y = -9.81, z = 0})
			local on_ground = (self._moveresult and self._moveresult.touching_ground) == true
			if not on_ground then
				local cur_v = self.object:get_velocity()
				if cur_v and (cur_v.x ~= 0 or cur_v.z ~= 0) then
					local drag = math.max(0.0, 1.0 - 1.2 * dtime)
					self.object:set_velocity({x = cur_v.x * drag, y = cur_v.y, z = cur_v.z * drag})
				end
			end
		end
		if self.action_timer <= 0 then
			local prev_state = self.state
			if self.on_action_end then
				self:on_action_end()
			elseif def.swarm and def.swarm.enabled ~= false and self.state == "attacking" then
				swarm.on_action_end(self, def)
			elseif def.shoal and def.shoal.enabled ~= false and self.state == "attacking" then
				shoal.on_action_end(self, def)
			end
			local is_fleeing = (self.state == "fleeing") or (self.panic_timer and self.panic_timer > 0)
			if not is_fleeing and self.state ~= "idle" and self.state == prev_state then
				self.state = "idle"
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
			end
		end
		return true
	end

	-- Health regeneration via memory buffer
	mob_memory.update_health_regen(self, dtime)

	-- Periodic target scanning and pack follower relinking
	local scan_int = def.scan_interval or 0.4
	if self.scan_timer >= scan_int then
		self.scan_timer = 0
		if not self.target and def.auto_scan ~= false then
			local nearest = mob_ai.scan_for_player(self, self.aggro_radius, self.eye_offset)
			if nearest then
				entity_wrapper.set_target(self, nearest)
				sound.play(self, "alert")
				if def.pack and def.pack.role == "leader" then
					coordination.rally_followers(self, nearest)
				elseif (def.swarm and def.swarm.enabled ~= false) or (def.shoal and def.shoal.enabled ~= false) then
					coordination.broadcast_threat(self, nearest, 24.0, 8)
				end
			end
		end

		if def.pack and def.pack.role == "member" and (not self.leader_obj or not self.leader_obj:is_valid()) then
			squad.relink_follower(self, 32.0)
		end
	end

	-- Pack follower regrouping towards leader
	if def.pack and def.pack.role == "member" and self.state == "regrouping" then
		if coordination.step_regroup(self, dtime, "walk") then
			return true
		end
	end

	-- Ambient sound updates
	sound.update(self, dtime)

	return false
end

---Registers a mob definition with standardized physical properties and lifecycle integration.
---@param name string Entity name (e.g. "x_mobs:spider")
---@param def table Entity definition table
function entity_wrapper.register_mob(name, def)
	def.name = name
	properties.resolve_mob_properties(def)
	local resolved_armor_groups = properties.resolve_armor_groups(def)
	def._resolved_armor_groups = resolved_armor_groups
	def._has_custom_step = (def.on_step ~= nil)

	-- Intercept on_activate to wire up core state, physics, pack, memory, and persistence
	local original_on_activate = def.on_activate
	def.on_activate = function(self, staticdata, dtime_s)
		-- Deserialize staticdata from previous session
		local data = {}
		if type(staticdata) == "table" then
			data = staticdata
		elseif type(staticdata) == "string" and staticdata ~= "" then
			local res = core.deserialize(staticdata)
			if type(res) == "table" then
				data = res
			elseif tonumber(staticdata) then
				data = { hp = tonumber(staticdata) }
			end
		end

		-- Initialize core entity attributes and timers
		local hp_max = def._hp_max or (def.initial_properties and def.initial_properties.hp_max) or 20
		self.hp_max = hp_max
		self._hp_max = hp_max
		self.hp = data.hp or hp_max
		if self.hp <= 0 then self.hp = hp_max end

		if def.initial_properties then
			if def.initial_properties.collisionbox then
				self.collisionbox = def.initial_properties.collisionbox
			end
			if def.initial_properties.selectionbox then
				self.selectionbox = def.initial_properties.selectionbox
			end
		end

		-- Apply standardized armor groups to ObjectRef, sync engine HP, and clear lingering damage overlays
		if self.object then
			self.object:set_armor_groups(resolved_armor_groups)
			self.object:set_hp(math.max(1, math.ceil(self.hp)))
			effects.clear_damage(self.object)
		end

		self.set_armor_groups = function(s, groups)
			properties.set_armor_groups(s, groups)
		end

		self.halt_horizontal_velocity = function(s)
			locomotion.halt_horizontal_velocity(s)
		end

		self.set_texture = function(s, id, vars)
			return properties.set_texture(s, id, vars)
		end

		-- Resolve texture variations & select variation
		local variations = def._texture_variations
			or properties.normalize_texture_variations(def.initial_properties and def.initial_properties.textures)
		if variations and #variations > 0 then
			self.texture_variations = variations
			local var_count = #variations
			local chosen_idx = data.texture_no or data.phenotype_idx
			if not chosen_idx or not variations[chosen_idx] then
				chosen_idx = math.random(var_count)
			end
			self.texture_no = chosen_idx
			local applied = variations[chosen_idx]
			self._chosen_textures = applied
			self.base_texture = applied
			if self.object then
				local update_props = { textures = applied }
				local init_props = def.initial_properties
				if init_props then
					if init_props.mesh then update_props.mesh = init_props.mesh end
					if init_props.visual_size then update_props.visual_size = init_props.visual_size end
					if init_props.collisionbox then update_props.collisionbox = init_props.collisionbox end
					if init_props.selectionbox then update_props.selectionbox = init_props.selectionbox end
					if init_props.collide_with_objects ~= nil then
						update_props.collide_with_objects = init_props.collide_with_objects
					end
					if init_props.backface_culling ~= nil then
						update_props.backface_culling = init_props.backface_culling
					end
				end
				local raw_alpha = (init_props and init_props.use_texture_alpha)
				if raw_alpha == nil then raw_alpha = def.use_texture_alpha end
				if raw_alpha ~= nil then
					local alpha
					if type(raw_alpha) == "string" then
						alpha = (raw_alpha ~= "opaque" and raw_alpha ~= "false")
					else
						alpha = not not raw_alpha
					end
					update_props.use_texture_alpha = alpha
				end
				-- Single network property update (removed redundant core.after(0) duplicate packet)
				self.object:set_properties(update_props)
			end
		end

		-- Overcrowding safeguard: cull excess mobs in congested areas to protect tick rate
		if not data.persistent and not self._persistent then
			if culling.check_congestion(self, 16, 16) then
				return
			end
		end

		self.state = "idle"
		self.target = nil
		self.is_dead = false
		self.scan_timer = 0
		self.action_timer = 0
		self.attack_cooldown = 0
		self.panic_timer = 0
		self.lost_sight_timer = 0
		self.cooldowns = {}
		if def.cooldowns then
			for k, v in pairs(def.cooldowns) do
				self.cooldowns[k] = v
			end
		end
		self.set_cooldown = function(s, k, v)
			if s.cooldowns then
				s.cooldowns[k] = math.max(0, v)
			end
		end

		-- Copy navigation & locomotion properties onto entity instance
		self.mob_height = def.mob_height
		self.eye_offset = def.eye_offset
		self.half_width = def.half_width
		self.walk_speed = def.walk_speed
		self.pursuit_speed = def.pursuit_speed
		self.wander_speed = def.wander_speed
		self.flee_speed = def.flee_speed
		self.can_wander = def.can_wander
		self.wander_radius = def.wander_radius
		self.can_swim = def.can_swim
		self.can_climb = def.can_climb
		self.can_open_doors = def.can_open_doors
		self.can_crawl = def.can_crawl
		self.is_floating = def.is_floating
		self.hover_offset = def.hover_offset
		-- Health regeneration
		self.health_regen = def.health_regen
		self.on_regen_step = def.on_regen_step
		self.on_return_to_fight = def.on_return_to_fight
		self.attack_range = def.attack_range
		self.aggro_radius = def.aggro_radius
		self.damage = def.damage
		self.damage_effect = def.damage_effect
		self.knockback_mult = (def.knockback_mult ~= nil and def.knockback_mult) or 1.5
		self._def = def

		-- Normalize factions & friendly fire configuration
		local f_input = data.factions or def.factions or def.faction
		local f_set, f_list = factions.normalize_factions(f_input)
		self.factions = f_set
		self.faction_list = f_list
		self.friendly_fire = (def.friendly_fire == true)

		-- Copy sound configuration and stagger ambient timer
		if not self.sounds and def.sounds then
			self.sounds = def.sounds
		end
		if not self.sounds then
			self._has_sounds = false
		end
		local snd = self.sounds
		local rcfg = snd and ((type(snd) == "string" and snd) or (type(snd) == "table" and (snd.random or snd.base)))
		if rcfg then
			local min_int = (type(rcfg) == "table" and rcfg.min_interval) or 8.0
			local max_int = (type(rcfg) == "table" and rcfg.max_interval) or 22.0
			self._sound_timer = min_int * 0.5 + math.random() * math.max(0.5, max_int - min_int)
		end

		-- Apply physics and gravity
		if not self.is_floating and self.object then
			self.object:set_acceleration({x = 0, y = -9.81, z = 0})
		end

		-- Initialize short-term memory buffer
		mob_memory.init_memory(self)

		-- Pathfinding state, abilities & orientation
		safety.init_abilities(self, def)
		self._cur_rot = {x = 0, y = 0, z = 0}
		self.swarm_alert = def.swarm_alert or {enabled = false}

		-- Initialize pack identity and hierarchy
		self.pack_id = data.pack_id
		if def.pack then
			if def.pack.role == "leader" then
				self.pack_id = self.pack_id or utils.generate_uuid()
				local pack_cfg = {}
				for k, v in pairs(def.pack) do pack_cfg[k] = v end
				pack_cfg.pack_id = self.pack_id
				squad.init_leader(self, pack_cfg)
				if def.pack.spawn_on_init then
					self.spawned_followers = data.spawned_followers or false
					if not self.spawned_followers then
						squad.spawn_initial_followers(self, def.pack.follower_type, def.pack.max_followers)
					else
						squad.adopt_nearby_orphans(self, 32.0)
					end
				end
			elseif def.pack.role == "member" then
				squad.init_member(self, def.pack)
			end
		end

		-- Initialize swarm intelligence
		if def.swarm and def.swarm.enabled ~= false then
			swarm.init_entity(self, def, data)
		end

		-- Initialize shoal schooling
		if def.shoal and def.shoal.enabled ~= false then
			shoal.init_entity(self, def, data)
		end

		-- Trigger initial idle animation
		if self.object then
			animator.play(self.object, "idle", {speed = 1.0, loop = true, force = true})
		end

		-- Invoke custom mob activation callback
		if original_on_activate then
			original_on_activate(self, data, dtime_s, staticdata)
		end

		-- Emit on_mob_spawn for external lifecycle listeners
		local is_fresh = (data.hp == nil and not data.saved_data)
		x_mob_core.emit("on_mob_spawn", self, is_fresh)
	end

	-- Standardized serializer preserving core attributes, hierarchy, and texture phenotypes
	local original_get_staticdata = def.get_staticdata
	def.get_staticdata = function(self)
		local save = {}
		if original_get_staticdata then
			local raw = original_get_staticdata(self)
			if type(raw) == "table" then
				save = raw
			elseif type(raw) == "string" and raw ~= "" then
				local res = core.deserialize(raw)
				if type(res) == "table" then
					save = res
				end
			end
		end
		if save.hp == nil then save.hp = self.hp end
		if save.pack_id == nil then save.pack_id = self.pack_id end
		if save.spawned_followers == nil then save.spawned_followers = self.spawned_followers end
		if save.texture_no == nil then save.texture_no = self.texture_no end
		if save.factions == nil and self.faction_list then save.factions = self.faction_list end
		if self.saved_data then
			for k, v in pairs(self.saved_data) do
				if save[k] == nil then save[k] = v end
			end
		end
		return core.serialize(save)
	end

	-- Intercept on_punch to provide standard combat handling
	local original_on_punch = def.on_punch
	def.on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		if original_on_punch then
			return original_on_punch(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		end
		return combat_handler.handle_punch(
			self, puncher, time_from_last_punch, tool_capabilities, dir, damage, def
		)
	end

	-- Intercept on_step to support lifecycle, custom state machine, and custom step
	local original_on_step = def.on_step
	def.on_step = function(self, dtime, moveresult)
		self._moveresult = moveresult

		-- Process core lifecycle step (death countdown, buoyancy, timers, target validity)
		local handled = entity_wrapper.handle_core_step(self, dtime, def)
		if handled then return end

		-- Process custom state machine tick
		if self.custom_states then
			if state_machine.update(self, dtime) then
				return
			end
		end

		-- Process step pipeline middleware hooks (Open/Closed Principle)
		if pipeline.execute(self, dtime, def, moveresult) then
			return
		end

		-- Execute custom mob step logic or fallback idle wandering / pursuit
		if original_on_step then
			original_on_step(self, dtime, moveresult)
		elseif not self.target then
			mob_ai.step_wander_or_idle(self, dtime)
		else
			mob_ai.step_move_or_idle(self, dtime)
		end
	end

	-- Intercept on_death to guarantee child/arrow detachment and leader death handling
	local original_on_death = def.on_death
	def.on_death = function(self, killer)
		health_bar.remove(self)
		detachment.detach_attached_children(self.object)

		self._killer = killer or self._killer

		if self.pack_role == "leader" then
			squad.handle_leader_death(self)
		elseif self.leader_obj and self.leader_obj:is_valid() then
			local leader_ent = self.leader_obj:get_luaentity()
			if leader_ent then
				squad.remove_follower(leader_ent, self.object)
			end
		end

		local auto_succ = (def.swarm and def.swarm.auto_succession ~= false) or
			(def.shoal and def.shoal.auto_succession ~= false) or
			(def.pack and def.pack.auto_succession == true)
		if auto_succ then
			squad.elect_successor(self, 24.0)
		end

		if not self.is_dead then
			combat_handler.handle_lethal_death(self, killer, nil, 0, def)
		end

		-- Fallback drop if death duration is 0 or unhandled by core step
		if (not self.action_timer or self.action_timer <= 0) and def.drops and not self._drops_spawned then
			self._drops_spawned = true
			loot.spawn_mob_drops(self, self._killer, def.drops, def.drop_options)
		end

		if original_on_death then
			original_on_death(self, killer)
		end
	end

	-- Intercept on_rightclick to provide decoupled interaction event
	local original_on_rightclick = def.on_rightclick
	def.on_rightclick = function(self, clicker)
		local itemstack = clicker and clicker:is_valid() and clicker:get_wielded_item()
		x_mob_core.emit("on_mob_rightclick", self, clicker, itemstack)
		if original_on_rightclick then
			return original_on_rightclick(self, clicker)
		end
	end

	-- Intercept on_deactivate to guarantee clean resource and HUD release
	local original_on_deactivate = def.on_deactivate
	def.on_deactivate = function(self, removal)
		local reason = removal and "removed" or "unloaded"
		if def.on_despawn and not self._despawn_handled then
			self._despawn_handled = true
			def.on_despawn(self, reason)
		end
		if not self._despawn_emitted then
			self._despawn_emitted = true
			x_mob_core.emit("on_mob_despawn", self, reason)
		end
		if original_on_deactivate then
			return original_on_deactivate(self, removal)
		end
	end

	def._is_x_mob = true
	entity_wrapper.registered_mobs[name] = def
	core.register_entity(name, def)
end

return entity_wrapper
