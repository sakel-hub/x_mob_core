--[[
	x_mob_core - Lifecycle Combat Handler Subsystem
	Encapsulates punch intake, damage resolution, knockback impulse,
	flinch transitions, and lethal state dispatching (Single Responsibility Principle).
]]

local combat_handler = {}

local modpath = core.get_modpath("x_mob_core")
local damage_calculator = dofile(modpath .. "/combat/damage.lua")
local effects = dofile(modpath .. "/combat/effects.lua")
local factions = dofile(modpath .. "/combat/factions.lua")
local sound = dofile(modpath .. "/audio/sound.lua")
local detachment = dofile(modpath .. "/combat/detachment.lua")
local animator = dofile(modpath .. "/animation/animator.lua")
local mob_memory = dofile(modpath .. "/navigation/mob_memory.lua")
local squad = dofile(modpath .. "/pack/squad.lua")
local coordination = dofile(modpath .. "/pack/coordination.lua")
local utils = dofile(modpath .. "/core/utils.lua")

---Applies death settling physics, anchoring the dying entity to walkable ground without vibration.
---@param self table Entity instance
function combat_handler.apply_death_settling_physics(self)
	if not self.object or not self.object:is_valid() then return end
	local on_ground = self._moveresult and self._moveresult.touching_ground
	if not on_ground then
		local p = self.object:get_pos()
		if p then
			local bnode = core.get_node_or_nil({x = p.x, y = p.y - 0.05, z = p.z})
			local bdef = bnode and core.registered_nodes[bnode.name]
			if bdef and bdef.walkable then
				on_ground = true
			end
		end
	end
	local y_acc = on_ground and 0 or -9.81
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local y_vel = on_ground and 0 or math.min(0, vel.y)
	self.object:set_velocity({x = 0, y = y_vel, z = 0})
	self.object:set_acceleration({x = 0, y = y_acc, z = 0})
end

---Dispatches the lethal death transition on a mob.
---@param self table Mob entity instance
---@param puncher? ObjectRef Killer object reference
---@param dir? Vector Strike direction
---@param dmg number Final damage dealt
---@param def table Entity definition table
function combat_handler.handle_lethal_death(self, puncher, dir, dmg, def)
	self.is_dead = true
	self.state = "dying"
	if self.target then
		self.target = nil
		if x_mob_core and x_mob_core.emit then
			x_mob_core.emit("on_mob_target", self, nil, self.target)
		end
	end
	self.action_timer = def.death_duration or 1.5
	effects.clear_damage(self.object)
	effects.spawn_damage_particles(self.object, puncher, dir, dmg, def)

	detachment.detach_attached_children(self.object)
	if self.object then
		self.object:set_properties({
			pointable = false,
			collide_with_objects = false,
		})
		-- Lock in immortal buffer so engine never deletes entity prematurely
		self.object:set_armor_groups({ immortal = 1, fleshy = 0 })
		self.object:set_hp(1000)
		combat_handler.apply_death_settling_physics(self)
	end

	animator.play(self.object, "die", {speed = 1.0, loop = false, force = true, priority = 10})
	sound.play(self, "death")

	-- Store killer reference so followers can inherit target and drops spawn after death
	self._killer = puncher

	if def.pack and def.pack.role == "leader" then
		squad.handle_leader_death(self)
	elseif self.leader_obj and self.leader_obj:is_valid() then
		local leader_ent = self.leader_obj:get_luaentity()
		if leader_ent then
			squad.remove_follower(leader_ent, self.object)
		end
	end

	local is_pack_threat = (def.swarm and def.swarm.enabled ~= false) or (def.shoal and def.shoal.enabled ~= false)
	if is_pack_threat and puncher and utils.is_player_alive(puncher) then
		coordination.broadcast_threat(self, puncher, 24.0, 8)
	end

	if def.on_death then
		def.on_death(self, puncher)
	end
	if x_mob_core and x_mob_core.emit then
		x_mob_core.emit("on_mob_death", self, puncher)
	end
end

---Universal combat punch intake handler.
---@param self table Mob entity instance
---@param puncher ObjectRef Attacking entity
---@param time_from_last_punch number Elapsed time
---@param tool_capabilities table Weapon capabilities
---@param dir Vector Punch impulse direction
---@param damage number Base damage
---@param def table Entity definition table
---@return boolean handled
function combat_handler.handle_punch(self, puncher, time_from_last_punch, tool_capabilities, dir, damage, def)
	def = def or self._def or (self.name and core.registered_entities[self.name]) or {}
	if self.is_dead or self.state == "dying" then return true end

	-- Friendly fire prevention
	local allow_ff = self.friendly_fire
	if allow_ff == nil then
		allow_ff = (def.friendly_fire == true)
	end
	if not allow_ff and puncher and factions.are_allies(self, puncher) then
		return true
	end

	local dmg = damage_calculator.calculate_punch_damage(
		self, puncher, time_from_last_punch, tool_capabilities, dir, damage
	)
	local hp_max = self.hp_max or def._hp_max or 20
	self.hp = (self.hp or hp_max) - dmg
	if self.hp < 0 then self.hp = 0 end

	-- Target assignment & threat recording for living player puncher
	if puncher and utils.is_player_alive(puncher) then
		if self.target ~= puncher then
			local old_target = self.target
			self.target = puncher
			if x_mob_core and x_mob_core.emit then
				x_mob_core.emit("on_mob_target", self, puncher, old_target)
			end
		end
		self.lost_sight_timer = 0
		if self.path_state then
			self.path_state.timer = 99.0
		end
		local ppos = puncher:get_pos()
		if ppos then
			mob_memory.record_danger(self, ppos, dmg, 12.0)
			mob_memory.record_target_sighting(self, puncher, ppos)
			if def.pack and def.pack.role == "leader" then
				coordination.broadcast_threat(self, puncher, 16.0, 4)
				coordination.rally_followers(self, puncher)
			elseif def.pack and def.pack.role == "member" then
				local leader = self.leader_obj or self.shaman_obj
				if leader and leader:is_valid() then
					local s_ent = leader:get_luaentity()
					if s_ent and not s_ent.is_dead and not s_ent.target then
						s_ent.target = puncher
					end
				end
			elseif (def.swarm and def.swarm.enabled ~= false) or (def.shoal and def.shoal.enabled ~= false) then
				coordination.broadcast_threat(self, puncher, 24.0, 8)
			elseif self.swarm_alert and self.swarm_alert.enabled then
				mob_memory.broadcast_alert(self, ppos, dmg, self.swarm_alert.radius, self.swarm_alert.max_allies)
			end
		end
	end

	-- Check for lethal damage
	if self.hp <= 0 then
		combat_handler.handle_lethal_death(self, puncher, dir, dmg, def)
		return true
	end

	-- Non-lethal feedback
	effects.indicate_damage(self.object)
	effects.spawn_damage_particles(self.object, puncher, dir, dmg, def)
	sound.play(self, "hurt")
	local kb = self.knockback_mult
	if kb == nil then
		kb = (def.knockback_mult ~= nil and def.knockback_mult) or 1.5
	end
	if kb > 0 and dir and self.object then
		self.object:add_velocity({x = dir.x * kb, y = 0.6 * kb, z = dir.z * kb})
	end

	-- Flinch hurt animation (unless in uninterruptible state or overridden)
	local can_flinch = (self.state ~= "flinching" and self.state ~= "attacking")
	if def.can_flinch ~= nil then
		if type(def.can_flinch) == "function" then
			can_flinch = def.can_flinch(self)
		else
			can_flinch = (def.can_flinch == true)
		end
	end
	if can_flinch then
		self.state = "flinching"
		self.action_timer = 0.4
		animator.play(self.object, "hurt", {speed = 1.2, loop = false, force = true})
	end

	if def.on_hurt then
		def.on_hurt(self, puncher, dmg)
	end
	if x_mob_core and x_mob_core.emit then
		x_mob_core.emit("on_mob_hurt", self, puncher, dmg)
	end

	return true
end

---Applies environmental damage (lava, fire, drowning, suffocation) to a mob.
---@param self table Mob entity instance
---@param dmg number Damage amount
---@param damage_type string Type of damage ("lava", "fire", "drowning", "suffocation", etc.)
---@param def table Entity definition table
---@return boolean lethal True if mob died from the damage
function combat_handler.apply_environmental_damage(self, dmg, damage_type, def)
	def = def or self._def or (self.name and core.registered_entities[self.name]) or {}
	if self.is_dead or self.state == "dying" then return false end

	local hp_max = self.hp_max or def._hp_max or 20
	self.hp = (self.hp or hp_max) - dmg
	if self.hp < 0 then self.hp = 0 end

	if self.hp <= 0 then
		combat_handler.handle_lethal_death(self, nil, nil, dmg, def)
		return true
	end

	-- Non-lethal visual and sound feedback
	effects.indicate_damage(self.object)
	effects.spawn_damage_particles(self.object, nil, nil, dmg, def)
	sound.play(self, "hurt")

	if def.on_hurt then
		def.on_hurt(self, nil, dmg)
	end
	if x_mob_core and x_mob_core.emit then
		x_mob_core.emit("on_mob_environmental_damage", self, damage_type, dmg)
		x_mob_core.emit("on_mob_hurt", self, nil, dmg)
	end

	return false
end

return combat_handler
