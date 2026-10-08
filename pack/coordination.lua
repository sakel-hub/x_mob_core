--[[
	x_mob_core - Multi-Agent Pack Coordination
	Spatial leash tethering, regroup vectors, and shared threat broadcasting
]]

---@class CoordinationSubsystem
local coordination = {}

local utils = dofile(core.get_modpath("x_mob_core") .. "/core/utils.lua")

--- Rallies all pack followers to attack a shared target
---@param leader_self table Leader mob instance
---@param target ObjectRef Target entity
function coordination.rally_followers(leader_self, target)
	local followers = leader_self.pack_followers
	if not followers or not target then return end
	for i = 1, #followers do
		local obj = followers[i]
		if utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent and ent.state ~= "fleeing" and ent.state ~= "dying" then
				ent.target = target
				if ent.state == "idle" or ent.state == "walk" or ent.state == "regrouping" then
					ent.state = "combat"
				end
			end
		end
	end
end

--- Broadcasts alert to nearby pack members or allies when taking damage or spotting an enemy.
--- Directly assigns `ent.target = target` and transitions idle/roaming allies into `"combat"`.
--- Note: This is an imperative function requiring an active `ObjectRef`. Unlike declarative
--- `swarm_alert`, it does not write coordinate memory for obscured allies, nor does it
--- trigger automatically on death.
---@param self table Mob instance
---@param target ObjectRef Threat target
---@param radius? number Alert radius in nodes (default: 16.0)
---@param max_allies? integer Max allies to alert (default: 4)
function coordination.broadcast_threat(self, target, radius, max_allies)
	if not self.object or not self.object:is_valid() or not target then return end
	local pos = self.object:get_pos()
	if not pos then return end

	local rad = radius or 16.0
	local max_cnt = max_allies or 4
	local objs = core.get_objects_inside_radius(pos, rad)
	local alerted = 0

	for i = 1, #objs do
		if alerted >= max_cnt then break end
		local obj = objs[i]
		if obj ~= self.object and not obj:is_player() and utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent then
				-- Alert if matching pack_id, same mob family, or allied faction
				local is_pack_mate = self.pack_id and ent.pack_id and (self.pack_id == ent.pack_id)
				local is_same_kind = ent.name == self.name
				local is_allied = x_mob_core.are_allies(self, ent)

				if is_pack_mate or is_same_kind or is_allied then
					if not ent.target or not ent.target:is_valid() then
						ent.target = target
						if ent.state == "idle" or ent.state == "walk" or ent.state == "regrouping" then
							ent.state = "combat"
						end
						if ent.path_state then
							ent.path_state.timer = 99.0
						end
						alerted = alerted + 1
					end
				end
			end
		end
	end
end

--- Checks if a follower has exceeded its leash distance from its leader
---@param follower_self table Follower mob instance
---@return boolean is_leashed True if within leash limit, false if leashed/separated
---@return Vector|nil leader_pos Position of leader if valid
---@return number dist Distance to leader
function coordination.check_leash(follower_self)
	local l_obj = follower_self.leader_obj
	if not l_obj or not l_obj:is_valid() then
		return true, nil, 0
	end

	local m_pos = follower_self.object and follower_self.object:get_pos()
	local l_pos = l_obj:get_pos()
	if not m_pos or not l_pos then
		return true, nil, 0
	end

	local dist = vector.distance(m_pos, l_pos)
	local max_dist = follower_self.pack_leash_distance or 18.0
	return (dist <= max_dist), l_pos, dist
end

--- Handles movement for a follower returning to assemble with its pack leader
---@param self table Follower mob instance
---@param dtime number Step delta time
---@param move_anim? string Movement animation (default: "walk")
---@param speed_mult? number Speed multiplier (default: 1.25)
---@return boolean is_regrouping True if still actively regrouping, false if reached leader or leader lost
function coordination.step_regroup(self, dtime, move_anim, speed_mult)
	local dt = dtime or 0.05
	local leader = self.leader_obj
	if not leader or not leader:is_valid() then
		if not self.pack_id then
			self.leader_obj = nil
		end
		self.state = "idle"
		return false
	end

	local l_pos = leader:get_pos()
	local my_pos = self.object and self.object:get_pos()
	if not l_pos or not my_pos then
		self.state = "idle"
		return false
	end

	local d_leader = vector.distance(my_pos, l_pos)
	local regroup_dist = self.pack_regroup_distance or 4.0
	local s_ent = leader:get_luaentity()

	-- If reached regroup distance, transition to idle or acquire leader's target
	if d_leader <= regroup_dist then
		self.state = "idle"
		if self.path_state then
			self.path_state.waypoints = nil
			self.path_state.index = 1
		end
		if s_ent and s_ent.target and utils.is_player_alive(s_ent.target) then
			self.target = s_ent.target
		end
		return false
	end

	-- If within 6 nodes and leader has active target, switch to combat
	if s_ent and s_ent.target and utils.is_player_alive(s_ent.target) and d_leader <= (regroup_dist + 2.0) then
		self.state = "idle"
		if self.path_state then
			self.path_state.waypoints = nil
			self.path_state.index = 1
		end
		self.target = s_ent.target
		return false
	end

	-- Initialize path state and abilities if needed
	if not self.abilities or not self.path_state then
		x_mob_core.motor.safety.init_abilities(self)
	end

	local r_speed = (self.walk_speed or 3.0) * (speed_mult or 1.25)
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local y_v = self.in_water and (self.water_vy or 0.4) or vel.y
	if not self.in_water then
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
	end

	-- Check if following active waypoints
	local wpts = self.path_state.waypoints
	local w_idx = self.path_state.index
	if wpts and w_idx <= #wpts then
		x_mob_core.motor.locomotion.handle_mob_movement(self, dt, my_pos, wpts[w_idx])
	else
		if wpts and w_idx > #wpts then
			self.path_state.waypoints = nil
			self.path_state.index = 1
		end

		local to_leader = vector.direction(my_pos, l_pos)
		local motor = x_mob_core.motor
		local fast_pathfinder = x_mob_core.fast_pathfinder
		local is_aquatic = (self.shoal ~= nil) or (self.is_aquatic == true) or
			(self.type == "aquatic") or (self.factions and (self.factions.aquatic or self.factions.fish))
		local leader_in_water = false
		local ln = core.get_node_or_nil(l_pos)
		local ld = ln and core.registered_nodes[ln.name]
		if ld and ld.liquidtype and ld.liquidtype ~= "none" then
			leader_in_water = true
		end

		local my_in_water = self.in_water == true
		local allow_water = is_aquatic or leader_in_water or my_in_water

		local abilities = utils.shallow_copy(self.abilities or {})
		abilities.can_swim = allow_water
		abilities.disallow_water = not allow_water
		if abilities.can_open_doors == nil then
			abilities.can_open_doors = (self.can_open_doors == true)
		end
		if abilities.can_climb == nil then
			abilities.can_climb = (self.can_climb == true)
		end
		if abilities.can_crawl == nil then
			abilities.can_crawl = (self.can_crawl == true)
		end

		local is_wall_hit, wall_norm = motor.locomotion.has_wall_collision(self, my_pos, dt)
		motor.doors.check_and_open_forward_doors(my_pos, to_leader, abilities, self.object)
		local step_ok = motor.safety.is_step_safe(my_pos, to_leader, abilities)
		local glos_ok = motor.safety.check_ground_line_of_sight(my_pos, l_pos, abilities)

		if step_ok and glos_ok and not is_wall_hit then
			-- Unobstructed direct line of sight to leader
			self.object:set_velocity({
				x = to_leader.x * r_speed,
				y = y_v,
				z = to_leader.z * r_speed,
			})
			local yaw = core.dir_to_yaw(to_leader)
			self.object:set_yaw(yaw)
			self._cur_rot = {x = 0, y = yaw, z = 0}
		else
			-- Path to leader is blocked by wall or obstacle: request A* path
			self.path_state.timer = (self.path_state.timer or 0) + dt
			if not self.path_state.is_calculating and (self.path_state.timer >= 1.0) then
				self.path_state.is_calculating = true
				self.path_state.timer = 0.0
				fast_pathfinder.find_path(my_pos, l_pos, abilities, function(res_wpts)
					if not self.object or not self.object:is_valid() then return end
					self.path_state.is_calculating = false
					if res_wpts and #res_wpts > 0 then
						self.path_state.waypoints = res_wpts
						self.path_state.index = 1
					else
						self.path_state.waypoints = nil
					end
				end, self.mob_height or 1.2)
			end

			-- Deflect laterally along wall instead of pushing directly into it
			local cand_dirs
			if wall_norm and (wall_norm.x ~= 0 or wall_norm.z ~= 0) then
				cand_dirs = {
					{x = -wall_norm.z, y = 0, z = wall_norm.x},
					{x = wall_norm.z, y = 0, z = -wall_norm.x},
					{x = wall_norm.x, y = 0, z = wall_norm.z},
				}
			else
				cand_dirs = {
					{x = -to_leader.z, y = 0, z = to_leader.x},
					{x = to_leader.z, y = 0, z = -to_leader.x},
					{x = -to_leader.x, y = 0, z = -to_leader.z},
				}
			end

			local deflected = false
			for c_idx = 1, #cand_dirs do
				local cand = cand_dirs[c_idx]
				if motor.safety.is_step_safe(my_pos, cand, abilities) then
					self.object:set_velocity({
						x = cand.x * (r_speed * 0.75),
						y = y_v,
						z = cand.z * (r_speed * 0.75),
					})
					local yaw = core.dir_to_yaw(cand)
					self.object:set_yaw(yaw)
					self._cur_rot = {x = 0, y = yaw, z = 0}
					deflected = true
					break
				end
			end

			if not deflected then
				self.object:set_velocity({x = 0, y = y_v, z = 0})
			end
		end
	end

	local anim = move_anim or "walk"
	x_mob_core.animator.play(self.object, anim, {speed = 1.2, loop = true})

	return true
end

--- Triggers cowardice panic in nearby fellow mobs when a pack member dies
---@param death_pos Vector Position of the deceased mob
---@param mob_name string Name of the entity to match (e.g. "x_mobs:fallen_minion")
---@param radius? number Search radius (default: 12.0)
---@param panic_duration? number Duration in seconds for flee state (default: 4.0)
---@param danger_dmg? number Perceived damage recorded in memory (default: 10)
function coordination.trigger_cowardice_panic(death_pos, mob_name, radius, panic_duration, danger_dmg)
	if not death_pos or not mob_name then return end
	local rad = radius or 12.0
	local dur = panic_duration or 4.0
	local dmg = danger_dmg or 10
	local nearby = core.get_objects_inside_radius(death_pos, rad)
	for i = 1, #nearby do
		local obj = nearby[i]
		if obj and not obj:is_player() and utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent and ent.name == mob_name then
				ent.panic_timer = dur
				ent.state = "fleeing"
				if ent.memory then
					ent.memory.flee_state = true
					x_mob_core.mob_memory.record_danger(ent, death_pos, dmg, rad + 4.0)
					x_mob_core.mob_memory.record_fight_pos(ent, death_pos, 45.0)
				end
			end
		end
	end
end

-- Automatic pack cowardice panic listener
x_mob_core.events.listen("on_mob_death", function(mob)
	if mob and mob.pack_cowardice and mob.object and mob.object:is_valid() then
		local pos = mob.object:get_pos()
		if pos then
			local cfg = mob.pack_cowardice
			local rad = (type(cfg) == "table" and cfg.radius) or 12.0
			local dur = (type(cfg) == "table" and cfg.duration) or 4.0
			coordination.trigger_cowardice_panic(pos, mob.name, rad, dur)
		end
	end
end)

--- Calculates 3D multi-agent Boids spatial repulsion with anti-stacking and soft/hard buffers
---@param self table Mob instance
---@param pos Vector Current world position
---@param radius? number Repulsion radius (default: 2.0)
---@param strength? number Push force multiplier (default: 2.4)
---@param ignore_behind? boolean If true, ignores entities trailing behind self.object
---@param min_sep? number Minimum hard penetration separation (default: radius * 0.6)
---@param vertical_factor? number Vertical attenuation factor (default: 0.1)
---@param horizontal_bias? boolean If true, applies horizontal anti-stacking bias (default: true)
---@return number sep_x
---@return number sep_y
---@return number sep_z
function coordination.calculate_repulsion(self, pos, radius, strength, ignore_behind,
	min_sep, vertical_factor, horizontal_bias)
	local rad = radius or 2.0
	local rad_sq = rad * rad
	local p_force = strength or 2.4
	local min_s = min_sep or (rad * 0.6)
	local v_factor = vertical_factor or 0.1
	local h_bias = horizontal_bias ~= false

	local sep_x, sep_y, sep_z = 0, 0, 0
	local nearby = core.get_objects_inside_radius(pos, rad)

	local fwd_x, fwd_z = 0, 0
	if ignore_behind and self.object and self.object:is_valid() then
		local cyaw = self.object:get_yaw() or 0.0
		fwd_x = -math.sin(cyaw)
		fwd_z = math.cos(cyaw)
	end

	for i = 1, #nearby do
		local obj = nearby[i]
		if obj ~= self.object and not obj:is_player() and utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent and (ent.name == self.name or (self.pack_id and ent.pack_id == self.pack_id)) then
				local op = obj:get_pos()
				if op then
					local odx = pos.x - op.x
					local ody = pos.y - op.y
					local odz = pos.z - op.z

					local is_behind = ignore_behind and (odx * fwd_x + odz * fwd_z > 0)
					if not is_behind then
						local d2 = odx * odx + ody * ody + odz * odz
						if d2 > 0.001 and d2 < rad_sq then
							local d = math.sqrt(d2)
							local push
							if d < min_s then
								local pen = (min_s - d) / min_s
								push = p_force * (1.2 + pen * 2.5)
							else
								push = ((rad - d) / math.max(0.1, rad - min_s)) * p_force
							end

							local h_d2 = odx * odx + odz * odz
							if h_bias and h_d2 < 0.64 then
								local h_d = math.sqrt(h_d2)
								local h_force = p_force * 1.15
								if h_d > 0.05 then
									sep_x = sep_x + (odx / h_d) * h_force
									sep_z = sep_z + (odz / h_d) * h_force
								else
									local jt = self._jitter_timer or 0
									local ang = (self.follower_index or 1) * (math.pi / 3) + jt
									sep_x = sep_x + math.cos(ang) * h_force
									sep_z = sep_z + math.sin(ang) * h_force
								end
							else
								sep_x = sep_x + (odx / d) * push
								sep_z = sep_z + (odz / d) * push
							end

							sep_y = sep_y + (ody / d) * push * v_factor
						end
					end
				end
			end
		end
	end

	return sep_x, sep_y, sep_z
end

return coordination
