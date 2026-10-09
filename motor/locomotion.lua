--[[
	x_mob_core - Locomotion & Steering Subsystem
	Physical movement, velocity integration, autonomous wandering,
	fleeing/standoff state machines, kiting retreat, and collision avoidance.
]]

---@class LocomotionSubsystem
local locomotion = {}

local modpath = core.get_modpath("x_mob_core") or "."
local utils = dofile(modpath .. "/core/utils.lua")
local node_cache = dofile(modpath .. "/motor/node_cache.lua")
local doors = dofile(modpath .. "/motor/doors.lua")
local surface = dofile(modpath .. "/motor/surface.lua")
local safety = dofile(modpath .. "/motor/safety.lua")
local mob_memory = dofile(modpath .. "/navigation/mob_memory.lua")
local animator = dofile(modpath .. "/animation/animator.lua")
local melee = dofile(modpath .. "/combat/melee.lua")
local shooter = dofile(modpath .. "/combat/shooter.lua")

--- Checks whether the given target is a connected, valid, living player or entity
local is_valid_living_player = utils.is_player_alive

--- Determines if mob is in active pursuit of a living target
---@param self table Entity instance
---@return boolean is_pursuing
function locomotion.get_pursuit_state(self)
	if self.is_pursuing ~= nil then
		return self.is_pursuing == true
	end
	return is_valid_living_player(self.target)
end

--- Safely gets object yaw in radians
---@param obj ObjectRef|nil
---@return number yaw
function locomotion.safe_get_yaw(obj)
	if obj and obj:is_valid() then
		if obj.get_yaw then
			return obj:get_yaw() or 0
		elseif obj.get_look_horizontal then
			return obj:get_look_horizontal() or 0
		elseif obj.get_look_yaw then
			return obj:get_look_yaw() or 0
		end
	end
	return 0
end

--- Safely sets object yaw in radians
---@param obj ObjectRef|nil
---@param yaw number
function locomotion.safe_set_yaw(obj, yaw)
	if obj and obj:is_valid() then
		obj:set_yaw(yaw)
	end
end

--- Safely sets object acceleration
---@param obj ObjectRef|nil
---@param acc Vector
function locomotion.safe_set_acceleration(obj, acc)
	if obj and obj:is_valid() then
		obj:set_acceleration(acc)
	end
end

--- Sets object rotation (Euler radians)
---@param obj ObjectRef|nil
---@param rot Vector
function locomotion.safe_set_rotation(obj, rot)
	if obj and obj:is_valid() then
		obj:set_rotation(rot)
	end
end

--- Calculates vertical velocity and applies buoyancy acceleration when navigating liquids
---@param self table Mob entity instance
---@param current_y number Current mob vertical position
---@param target_y number Desired waypoint/target vertical position
---@param is_subm boolean True if submerged
---@param target_vy number Target floating velocity from check_in_liquid
---@return number y_vel Vertical velocity to assign
function locomotion.calculate_liquid_vertical_velocity(self, current_y, target_y, is_subm, target_vy)
	local dy = target_y - current_y
	if dy > 0.4 then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
		return 2.0
	elseif dy < -0.6 and is_subm then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = -1.5, z = 0})
		return -1.2
	else
		local acc_y = is_subm and 0.5 or 0.0
		locomotion.safe_set_acceleration(self.object, {x = 0, y = acc_y, z = 0})
		return target_vy or 0
	end
end

--- Applies active water buoyancy and partial submersion floating physics for swimming mobs
---@param self table Entity instance
---@param dtime number Step delta time
---@return boolean in_liquid True if mob is currently inside a liquid node
---@return boolean is_submerged True if mob is submerged below target swimming waterline
---@return number target_vy Vertical velocity to maintain or reach swimming depth
function locomotion.apply_liquid_buoyancy(self, dtime)
	if not self.object or not self.object:is_valid() then
		return false, false, 0
	end

	local pos = self.object:get_pos()
	if not pos then
		return false, false, 0
	end

	local in_liquid, is_submerged, _, target_vy = safety.check_in_liquid(
		pos, self.abilities or self._inherent_abilities, self.mob_height or 1.5
	)

	if not in_liquid then
		if self._in_liquid then
			local exit_acc = self.is_floating and {x = 0, y = 0, z = 0} or {x = 0, y = -9.81, z = 0}
			locomotion.safe_set_acceleration(self.object, exit_acc)
			self._in_liquid = false
			self._is_submerged = false
			self._liquid_vy = nil
		end
		return false, false, 0
	end

	if self.is_floating then
		-- Airborne flying mobs in liquid accelerate upward to breach surface into air
		locomotion.safe_set_acceleration(self.object, {x = 0, y = 4.0, z = 0})
		local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		local vy = math.max(vel.y, 3.2)
		self.object:set_velocity({x = vel.x, y = vy, z = vel.z})
		self._in_liquid = true
		self._is_submerged = true
		self._liquid_vy = 3.2
		return true, true, 3.2
	end

	self._in_liquid = true
	self._is_submerged = is_submerged
	self._liquid_vy = target_vy

	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local dt = dtime or 0.05
	local vx = vel.x
	local vz = vel.z
	if math.abs(vx) > 1.8 or math.abs(vz) > 1.8 then
		local drag = math.max(0.0, 1.0 - 5.0 * dt)
		vx = vx * drag
		vz = vz * drag
	end

	local vy = vel.y
	if vy > 1.5 then
		vy = vy * math.max(0.0, 1.0 - 6.0 * dt)
	else
		vy = vy + (target_vy - vy) * math.min(1.0, dt * 6.0)
	end

	self.object:set_velocity({x = vx, y = vy, z = vz})

	if is_submerged then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
	else
		locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
	end

	return true, is_submerged, target_vy
end

--- Halts horizontal velocity while preserving vertical motion/gravity and liquid buoyancy
---@param self table Mob entity instance
function locomotion.halt_horizontal_velocity(self)
	if not self or not self.object or not self.object:is_valid() then return end
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local y_vel = self.in_water and (self.water_vy or self._liquid_vy or 0) or (self.is_floating and 0 or vel.y)
	self.object:set_velocity({x = 0, y = y_vel, z = 0})
	if not self.in_water and not self.is_floating then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
	end
end

--- Computes effective movement speed for a mob incorporating status effects (buffs/slows)
---@param self table Mob entity instance
---@param base_speed number Base locomotion speed
---@return number effective_speed Multiplied speed
function locomotion.get_effective_speed(self, base_speed)
	if not base_speed or base_speed <= 0 then return 0 end
	local mult = (self.object and x_mob_core.get_speed_multiplier and x_mob_core.get_speed_multiplier(self.object)) or 1.0
	return base_speed * mult
end

--- Sets horizontal velocity of a mob entity along a given yaw while preserving vertical motion/gravity
---@param self table Mob entity instance
---@param speed number Horizontal movement speed
---@param yaw number Orientation angle in radians
function locomotion.set_horizontal_velocity(self, speed, yaw)
	if not self or not self.object or not self.object:is_valid() then return end
	local eff_speed = locomotion.get_effective_speed(self, speed)
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local y_vel = self.in_water and (self.water_vy or self._liquid_vy or 0) or (self.is_floating and 0 or vel.y)
	local dir = core.yaw_to_dir(yaw)
	self.object:set_velocity({x = dir.x * eff_speed, y = y_vel, z = dir.z * eff_speed})
	if not self.in_water and not self.is_floating then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
	end
end



--- Detects if entity has collided with a wall/solid obstacle or is physically stagnant against one
---@param self table Mob entity instance
---@param current_pos Vector Current world position
---@param dtime number Delta time
---@return boolean is_colliding Whether the mob is colliding with a wall
---@return Vector|nil wall_normal Estimated normal pointing away from the wall
---@return Vector|nil node_pos Position of collided node if known
function locomotion.has_wall_collision(self, current_pos, dtime)
	local mr = self._moveresult or self.moveresult
	if mr and mr.collides and mr.collisions then
		for i = 1, #mr.collisions do
			local c = mr.collisions[i]
			if c.type == "node" and (c.axis == "x" or c.axis == "z") then
				if c.node_pos then
					doors.try_open_door_at_pos(c.node_pos, self.abilities, self.object)
				end
				local norm = {x = 0, y = 0, z = 0}
				if c.axis == "x" then
					norm.x = (c.old_velocity and c.old_velocity.x > 0) and -1 or 1
				elseif c.axis == "z" then
					norm.z = (c.old_velocity and c.old_velocity.z > 0) and -1 or 1
				end
				return true, norm, c.node_pos
			end
		end
	end

	if not self._last_nav_pos then
		self._last_nav_pos = {x = current_pos.x, y = current_pos.y, z = current_pos.z}
		self._wall_stuck_timer = 0.0
	else
		local dx = current_pos.x - self._last_nav_pos.x
		local dz = current_pos.z - self._last_nav_pos.z
		local dist_sq = dx * dx + dz * dz

		local vel = self.object and self.object:get_velocity()
		local commanded_horizontal = vel and (math.abs(vel.x) > 0.3 or math.abs(vel.z) > 0.3)

		if commanded_horizontal and dist_sq < 0.015 then
			self._wall_stuck_timer = (self._wall_stuck_timer or 0) + dtime
			if self._wall_stuck_timer > 0.3 then
				local norm = nil
				if vel and (math.abs(vel.x) > 0.1 or math.abs(vel.z) > 0.1) then
					norm = {x = (vel.x > 0) and -1 or 1, y = 0, z = (vel.z > 0) and -1 or 1}
				end
				return true, norm, nil
			end
		else
			if dist_sq >= 0.04 then
				self._wall_stuck_timer = 0.0
			end
			self._last_nav_pos.x = current_pos.x
			self._last_nav_pos.y = current_pos.y
			self._last_nav_pos.z = current_pos.z
		end
	end

	return false, nil, nil
end

--- Calculates a soft repulsive separation vector away from other nearby mobs
--- to prevent clipping and merging into each other.
--- Respects surface orientation (tangent projection on walls/ceilings).
--- Throttled to 100ms per entity to ensure zero performance overhead on multiplayer servers.
---@param self table Mob entity state
---@param current_pos Vector Mob position
---@param dtime number Server step delta time
---@param on_surface boolean True if mob is on wall or ceiling
---@param normal Vector Surface normal vector (or {x=0, y=1, z=0} for floor)
---@return Vector sep_force Tangent/horizontal separation velocity offset
function locomotion.calculate_separation_force(self, current_pos, dtime, on_surface, normal)
	self._sep_timer = (self._sep_timer or 0) + dtime
	if self._sep_timer < 0.1 then
		return self._cached_sep_force or {x = 0, y = 0, z = 0}
	end
	self._sep_timer = 0

	local cbox = self.collisionbox or (self.initial_properties and self.initial_properties.collisionbox)
	local self_r = 0.55
	if cbox then
		local rx = math.max(math.abs(cbox[1] or 0.55), math.abs(cbox[4] or 0.55))
		local rz = math.max(math.abs(cbox[3] or 0.55), math.abs(cbox[6] or 0.55))
		self_r = math.max(rx, rz)
	end

	local scan_radius = self_r * 2.5
	local nearby = core.get_objects_inside_radius(current_pos, scan_radius)
	local fx, fy, fz = 0, 0, 0
	local self_obj = self.object

	for i = 1, #nearby do
		local obj = nearby[i]
		if obj and obj ~= self_obj and not obj:is_player() then
			local le = obj:get_luaentity()
			if le and le ~= self then
				local opos = obj:get_pos()
				if opos then
					local dx = current_pos.x - opos.x
					local dy = current_pos.y - opos.y
					local dz = current_pos.z - opos.z
					local dist_sq = dx * dx + dy * dy + dz * dz
					local min_dist = self_r * 2.2
					if dist_sq < (min_dist * min_dist) and dist_sq > 0.0001 then
						local dist = math.sqrt(dist_sq)
						local strength = (1.0 - (dist / min_dist)) * 3.0
						local nx, ny, nz = dx / dist, dy / dist, dz / dist
						fx = fx + nx * strength
						fy = fy + ny * strength
						fz = fz + nz * strength
					end
				end
			end
		end
	end

	local sep_force = {x = fx, y = fy, z = fz}

	if on_surface and normal then
		local dot = sep_force.x * normal.x + sep_force.y * normal.y + sep_force.z * normal.z
		sep_force.x = sep_force.x - dot * normal.x
		sep_force.y = sep_force.y - dot * normal.y
		sep_force.z = sep_force.z - dot * normal.z
	else
		sep_force.y = 0
	end

	local f_len = math.sqrt(sep_force.x * sep_force.x + sep_force.y * sep_force.y + sep_force.z * sep_force.z)
	if f_len > 3.0 then
		sep_force.x = (sep_force.x / f_len) * 3.0
		sep_force.y = (sep_force.y / f_len) * 3.0
		sep_force.z = (sep_force.z / f_len) * 3.0
	end

	self._cached_sep_force = sep_force
	return sep_force
end

--- Handles physical movement and steering toward the next path waypoint
---@param self table Entity instance
---@param dtime number Step delta time
---@param current_pos Vector Current mob world position
---@param next_waypoint Vector Target node world position
function locomotion.handle_mob_movement(self, dtime, current_pos, next_waypoint)
	if not self.abilities or not self._inherent_abilities then
		safety.init_abilities(self)
	end
	local is_pursuing = locomotion.get_pursuit_state(self)

	local node_at_target = node_cache.get_node(next_waypoint)
	local def_target = core.registered_nodes[node_at_target.name] or {}
	local current_node = node_cache.get_node({
		x = math.floor(current_pos.x + 0.5),
		y = math.floor(current_pos.y + 0.5),
		z = math.floor(current_pos.z + 0.5),
	})
	local def_current = core.registered_nodes[current_node.name] or {}

	-- Liquid Avoidance (Path Invalidation if Waypoint Flooded)
	if def_target.liquidtype and def_target.liquidtype ~= "none" and not (self.abilities and self.abilities.can_swim) then
		self.path_state.waypoints = nil
		self.path_state.index = 1
		return
	end

	-- Door Opening (Pursuit, Fleeing, Regrouping)
	if self.abilities and self.abilities.can_open_doors then
		if doors.is_openable_door(node_at_target.name, self.abilities) and
		   not doors.is_door_open(next_waypoint, node_at_target, def_target) then
			local opened = doors.try_open_door(next_waypoint, node_at_target, def_target, self.object)
			if not opened then
				self.path_state.waypoints = nil
				self.path_state.index = 1
				return
			end
		end

		local to_wpt = vector.direction(current_pos, next_waypoint)
		doors.check_and_open_forward_doors(current_pos, to_wpt, self.abilities, self.object)
	end

	-- Surface Crawling Physics (Walls, Ceilings, Ledges & 3D Crawling)
	local is_crawler = self.abilities and self.abilities.can_crawl == true
	local normal = next_waypoint.normal or {x = 0, y = 1, z = 0}
	local surface_type = next_waypoint.surface_type or
		(normal.y < -0.5 and "ceiling" or (normal.y > 0.5 and "floor" or "wall"))

	if is_crawler then
		local on_surface = (surface_type == "wall" or surface_type == "ceiling")
		self.on_wall_or_ceiling = on_surface
		if on_surface then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		else
			locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end

		local SPIDER_SELBOX = {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85}
		if self.object and self.object:is_valid() then
			local selbox = self.selectionbox
				or (self.initial_properties and self.initial_properties.selectionbox)
				or SPIDER_SELBOX
			if on_surface and not self._has_wall_cbox then
				self._has_wall_cbox = true
				self.object:set_properties({
					collisionbox = {-0.20, -0.20, -0.20, 0.20, 0.20, 0.20},
					selectionbox = selbox,
				})
			elseif not on_surface and self._has_wall_cbox then
				self._has_wall_cbox = false
				local ground_cbox = self.collisionbox
					or (self.initial_properties and self.initial_properties.collisionbox)
					or {-0.35, 0.0, -0.35, 0.35, 0.45, 0.35}
				self.object:set_properties({
					collisionbox = ground_cbox,
					selectionbox = selbox,
				})
			end
		end

		local target_wpt = {
			x = next_waypoint.x - (normal.x * 0.30),
			y = next_waypoint.y - (normal.y * 0.30),
			z = next_waypoint.z - (normal.z * 0.30),
		}

		local move_vec = vector.direction(current_pos, target_wpt)
		local raw_speed = is_pursuing and (self.pursuit_speed or 4.0) or (self.walk_speed or 1.5)
		local speed = locomotion.get_effective_speed(self, raw_speed)


		local dist_to_target = vector.distance(current_pos, target_wpt)
		local move_heading
		if dist_to_target > 0.30 then
			move_heading = move_vec
			self._last_move_dir = move_heading
		else
			move_heading = self._last_move_dir or move_vec
		end

		self._cur_normal = self._cur_normal or normal
		self._cur_normal = surface.interpolate_vector(self._cur_normal, normal, math.min(1.0, dtime * 8.0))
		local active_normal = self._cur_normal

		local adhere_bias = on_surface and 0.22 or 0.0
		local sep = locomotion.calculate_separation_force(self, current_pos, dtime, on_surface, active_normal)
		local vx = move_vec.x * speed - active_normal.x * adhere_bias + sep.x
		local vy = move_vec.y * speed - active_normal.y * adhere_bias + sep.y
		local vz = move_vec.z * speed - active_normal.z * adhere_bias + sep.z

		self.object:set_velocity({x = vx, y = vy, z = vz})

		local target_rot = surface.dir_to_surface_rotation(move_heading, active_normal)
		local cur_rot = self._cur_rot or {x = 0, y = locomotion.safe_get_yaw(self.object), z = 0}
		local max_rot_step = (self.max_angular_speed or 4.0) * dtime
		local smoothed_rot = surface.interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 6.5), max_rot_step)
		self._cur_rot = smoothed_rot
		locomotion.safe_set_rotation(self.object, smoothed_rot)

		local dist_3d = vector.distance(current_pos, next_waypoint)
		local arrived = (dist_3d < 0.80)

		if not arrived and self.path_state then
			if (self.path_state.last_wpt_idx or 0) == self.path_state.index then
				self.path_state.wpt_stuck_time = (self.path_state.wpt_stuck_time or 0) + dtime
				if self.path_state.wpt_stuck_time > 0.5 and dist_3d < 2.0 then
					arrived = true
					self.path_state.wpt_stuck_time = 0
				end
			else
				self.path_state.last_wpt_idx = self.path_state.index
				self.path_state.wpt_stuck_time = 0
			end
		end

		if arrived then
			self.path_state.index = self.path_state.index + 1
			if self.path_state then
				self.path_state.wpt_stuck_time = 0
			end
		end
		return
	end

	-- Swimming Physics
	local can_swim = self.abilities and (self.abilities.can_swim == true)
	local in_liq, is_subm, _, target_vy = safety.check_in_liquid(current_pos, self.abilities or {}, self.mob_height)
	local in_liquid = can_swim and (
		(def_current.liquidtype and def_current.liquidtype ~= "none") or
		(def_target.liquidtype and def_target.liquidtype ~= "none") or
		in_liq
	)

	-- Ladder & Climbing Physics (Pursuit Only)
	local can_climb = self.abilities and (self.abilities.can_climb == true)
	local in_ladder = is_pursuing and can_climb and
		(def_current and def_current.climbable == true)
	local approaching_ladder = is_pursuing and can_climb and
		not in_ladder and (def_target and def_target.climbable == true)

	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local move_vec = vector.direction(current_pos, next_waypoint)
	local raw_speed = is_pursuing and (self.pursuit_speed or 4.0) or (self.walk_speed or 1.5)
	local speed = locomotion.get_effective_speed(self, raw_speed)
	local y_vel = vel.y

	if in_ladder then
		local dy = next_waypoint.y - current_pos.y
		locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		if math.abs(dy) > 0.15 then
			y_vel = (dy > 0) and 2.2 or -2.2
		else
			y_vel = 0
		end
		self._was_in_ladder = true
	elseif in_liquid then
		y_vel = locomotion.calculate_liquid_vertical_velocity(self, current_pos.y, next_waypoint.y, is_subm, target_vy)
		speed = speed * 0.75
	elseif self.is_floating then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		local hover_h = (self.target or self.state == "fleeing" or self.state == "combat")
			and (self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4))
			or (self.hover_offset or 0.0)
		local desired_y = next_waypoint.y + hover_h
		local dy = desired_y - current_pos.y
		y_vel = math.min(math.max(dy * 2.5, -5.0), 4.5)
	else
		locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		if self._was_in_ladder then
			self._was_in_ladder = false
			if y_vel > 0 then
				y_vel = 0
			end
		end
	end

	local sep = locomotion.calculate_separation_force(self, current_pos, dtime, false, {x = 0, y = 1, z = 0})
	self.object:set_velocity({
		x = move_vec.x * speed + sep.x,
		y = y_vel,
		z = move_vec.z * speed + sep.z,
	})

	if math.abs(move_vec.x) > 0.01 or math.abs(move_vec.z) > 0.01 then
		local yaw = core.dir_to_yaw(move_vec)
		local cur_rot = self._cur_rot or {x = 0, y = locomotion.safe_get_yaw(self.object) or 0, z = 0}
		local target_rot = {x = 0, y = yaw, z = 0}
		local max_rot_step = (self.max_angular_speed or 4.0) * dtime
		local smoothed_rot = surface.interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 6.5), max_rot_step)
		self._cur_rot = smoothed_rot
		if math.abs(smoothed_rot.x) + math.abs(smoothed_rot.z) > 0.05 then
			locomotion.safe_set_rotation(self.object, smoothed_rot)
		else
			locomotion.safe_set_yaw(self.object, smoothed_rot.y)
		end
	end

	local flat_dist = vector.distance(
		{x = current_pos.x, y = 0, z = current_pos.z},
		{x = next_waypoint.x, y = 0, z = next_waypoint.z}
	)
	local y_diff = math.abs(current_pos.y - next_waypoint.y)
	local arrival_thresh = math.max(0.85, (self.half_width or 0.4) * 1.25)
	local y_thresh = (in_ladder or approaching_ladder) and 0.5 or (self.is_floating and 1.8 or 1.35)
	local arrived = (flat_dist < arrival_thresh) and (y_diff < y_thresh)

	if not arrived and self.path_state then
		if (self.path_state.last_wpt_idx or 0) == self.path_state.index then
			self.path_state.wpt_stuck_time = (self.path_state.wpt_stuck_time or 0) + dtime
			if self.path_state.wpt_stuck_time > 0.4 and flat_dist < 2.0 and y_diff < 2.5 then
				arrived = true
				self.path_state.wpt_stuck_time = 0
			elseif self.path_state.wpt_stuck_time > 0.8 then
				self.path_state.waypoints = nil
				self.path_state.index = 1
				self.path_state.timer = 999.0
				self.path_state.wpt_stuck_time = 0
				mob_memory.record_blocked_spot(self, current_pos, 4.0)
			end
		else
			self.path_state.last_wpt_idx = self.path_state.index
			self.path_state.wpt_stuck_time = 0
		end
	end

	if arrived then
		self.path_state.index = self.path_state.index + 1
		if self.path_state then
			self.path_state.wpt_stuck_time = 0
		end
	end

	mob_memory.record_trail_step(self, current_pos, dtime)
end

--- Updates autonomous local wandering and idling when mob is not pursuing a target
---@param self table Entity instance
---@param dtime number Step delta time
---@param current_pos Vector Current mob world position
---@param on_wall_or_ceiling boolean Whether mob is adhering to wall/ceiling
---@return table status Locomotion status {moving = boolean, speed = number, has_los = boolean}
function locomotion.handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
	if not self.abilities or not self._inherent_abilities then
		safety.init_abilities(self)
	end
	if type(current_pos) ~= "table" and self.object and self.object:is_valid() then
		current_pos = self.object:get_pos()
	end
	local is_aquatic = safety.is_aquatic_mob(self)
	local in_liquid, is_subm, _, target_vy = safety.check_in_liquid(
		current_pos, self.abilities or self._inherent_abilities, self.mob_height
	)

	if self.can_wander == false then
		local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		if in_liquid then
			vel.y = target_vy or 0
			if is_subm then
				locomotion.safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
			else
				locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			end
		elseif not self.is_floating and not on_wall_or_ceiling then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end
		self.object:set_velocity({x = 0, y = vel.y, z = 0})
		return {moving = false, speed = 0, has_los = false}
	end

	if not self.wander_state then
		self.wander_state = {
			is_moving = false,
			timer = 1.5 + math.random() * 2.0,
			dir = {x = 0, y = 0, z = 0},
			yaw = locomotion.safe_get_yaw(self.object),
			origin = {x = current_pos.x, y = current_pos.y, z = current_pos.z},
		}
	end

	local ws = self.wander_state
	ws.timer = ws.timer - dtime

	if in_liquid then
		if is_subm then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
		else
			locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		end
	elseif not self.is_floating and not on_wall_or_ceiling then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
	elseif self.is_floating or on_wall_or_ceiling then
		locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
	end

	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local y_vel = vel.y

	if in_liquid then
		y_vel = target_vy or 0
	elseif self.is_floating then
		local ground_y = utils.get_ground_y(current_pos, 24, 4, true, true)
		local hover_h = (self.target or self.state == "fleeing" or self.state == "combat")
			and (self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4))
			or (self.hover_offset or 0.5)
		if ground_y then
			local desired_y = ground_y + hover_h
			local dy = desired_y - current_pos.y
			if dy < -0.2 then
				y_vel = math.max(dy * 2.0, -3.5)
			elseif dy > 0.2 then
				y_vel = math.min(dy * 2.0, 1.8)
			else
				y_vel = 0
			end
		else
			y_vel = -2.5
		end
	end

	local wander_abilities = self.abilities
	if not is_aquatic and not in_liquid then
		wander_abilities = utils.shallow_copy(self.abilities or {})
		wander_abilities.can_swim = false
		wander_abilities.disallow_water = true
	end

	if not in_liquid and not is_aquatic and not self.is_floating then
		self._last_ground_pos = {x = current_pos.x, y = current_pos.y, z = current_pos.z}
	end

	local raw_speed = self.wander_speed or (self.walk_speed and self.walk_speed * 0.6) or 1.8
	local speed = locomotion.get_effective_speed(self, raw_speed)
	if in_liquid then
		speed = speed * 0.75
	end

	if not ws.is_moving then
		self.object:set_velocity({x = 0, y = y_vel, z = 0})

		if ws.timer <= 0 then
			local chosen_yaw = nil

			if in_liquid and not is_aquatic then
				local shore_pos = safety.find_nearest_shore_pos(current_pos, 24)
				if not shore_pos and self._last_ground_pos then
					shore_pos = self._last_ground_pos
				end
				if not shore_pos and ws.origin then
					local og_node = node_cache.get_node_or_nil(ws.origin)
					local og_def = og_node and core.registered_nodes[og_node.name]
					if not (og_def and og_def.liquidtype and og_def.liquidtype ~= "none") then
						shore_pos = ws.origin
					end
				end

				if shore_pos then
					local to_shore = vector.direction(current_pos, shore_pos)
					chosen_yaw = core.dir_to_yaw(to_shore)
					ws.is_moving = true
					ws.timer = 2.0 + math.random() * 1.0
					ws.yaw = chosen_yaw
					ws.dir = {x = -math.sin(chosen_yaw), y = 0, z = math.cos(chosen_yaw)}
					locomotion.safe_set_yaw(self.object, chosen_yaw)
					self._cur_rot = {x = 0, y = chosen_yaw, z = 0}

					local d_sq = (current_pos.x - shore_pos.x)^2 + (current_pos.z - shore_pos.z)^2
					local shore_y_vel = y_vel
					if d_sq < 6.25 then
						shore_y_vel = math.max(shore_y_vel or 0, 4.5)
					end

					self.object:set_velocity({
						x = ws.dir.x * speed,
						y = shore_y_vel,
						z = ws.dir.z * speed,
					})
					return {moving = true, speed = speed, has_los = false}
				else
					ws.timer = 1.0
					self.object:set_velocity({x = 0, y = y_vel, z = 0})
					return {moving = false, speed = 0, has_los = false}
				end
			end

			if not chosen_yaw then
				local wander_radius = self.wander_radius or 12.0
				local dist_from_origin = vector.distance(
					{x = current_pos.x, y = 0, z = current_pos.z},
					{x = ws.origin.x, y = 0, z = ws.origin.z}
				)

				if dist_from_origin > wander_radius then
					local to_origin = vector.direction(current_pos, ws.origin)
					chosen_yaw = core.dir_to_yaw(to_origin) + (math.random() - 0.5) * 0.8
				else
					local best_score = -9999.0
					local best_yaw = math.random() * math.pi * 2
					for _ = 1, 6 do
						local test_yaw = math.random() * math.pi * 2
						local t_dir = {x = -math.sin(test_yaw), y = 0, z = math.cos(test_yaw)}
						local score = mob_memory.evaluate_heading_bias(self, t_dir, current_pos)
						if not self.is_floating and not on_wall_or_ceiling then
							if not safety.is_step_safe(current_pos, t_dir, wander_abilities) then
								score = score - 100.0
							else
								local test_look = {
									x = current_pos.x + t_dir.x * 1.25,
									y = current_pos.y,
									z = current_pos.z + t_dir.z * 1.25,
								}
								local look_ok, l_reason = safety.is_step_safe(test_look, t_dir, wander_abilities)
								if not look_ok and (l_reason == "water" or l_reason == "cliff" or l_reason == "hazard") then
									score = score - 80.0
								end
							end
						end
						if score > best_score then
							best_score = score
							best_yaw = test_yaw
						end
					end
					chosen_yaw = best_yaw
				end
			end

			local dir_x = -math.sin(chosen_yaw)
			local dir_z = math.cos(chosen_yaw)

			local safe = true
			if not self.is_floating and not on_wall_or_ceiling then
				safe = safety.is_step_safe(current_pos, {x = dir_x, y = 0, z = dir_z}, wander_abilities)
				if safe then
					local look_pos = {
						x = current_pos.x + dir_x * 1.25,
						y = current_pos.y,
						z = current_pos.z + dir_z * 1.25,
					}
					local look_safe, look_reason = safety.is_step_safe(look_pos, {x = dir_x, y = 0, z = dir_z}, wander_abilities)
					if not look_safe and (look_reason == "water" or look_reason == "cliff" or look_reason == "hazard") then
						safe = false
					end
				end
			end

			if safe then
				ws.is_moving = true
				ws.timer = 2.0 + math.random() * 2.5
				ws.yaw = chosen_yaw
				ws.dir = {x = dir_x, y = 0, z = dir_z}
				locomotion.safe_set_yaw(self.object, chosen_yaw)
			else
				ws.timer = 0.5 + math.random() * 0.8
				return {moving = false, speed = 0, has_los = false}
			end
		else
			return {moving = false, speed = 0, has_los = false}
		end
	end

	if not self.is_floating and not on_wall_or_ceiling and not in_liquid then
		local is_wall_colliding, wall_norm = locomotion.has_wall_collision(self, current_pos, dtime)
		local unsafe_step = not safety.is_step_safe(current_pos, ws.dir, wander_abilities)
		if not unsafe_step then
			local look_pos = {
				x = current_pos.x + ws.dir.x * 1.25,
				y = current_pos.y,
				z = current_pos.z + ws.dir.z * 1.25,
			}
			local look_safe, look_reason = safety.is_step_safe(look_pos, ws.dir, wander_abilities)
			if not look_safe and (look_reason == "water" or look_reason == "cliff" or look_reason == "hazard") then
				unsafe_step = true
			end
		end

		if unsafe_step or is_wall_colliding then
			local cand_dirs
			if wall_norm and (wall_norm.x ~= 0 or wall_norm.z ~= 0) then
				cand_dirs = {
					{x = -wall_norm.z, y = 0, z = wall_norm.x},
					{x = wall_norm.z, y = 0, z = -wall_norm.x},
					{x = wall_norm.x, y = 0, z = wall_norm.z},
				}
			else
				cand_dirs = {
					{x = -ws.dir.z, y = 0, z = ws.dir.x},
					{x = ws.dir.z, y = 0, z = -ws.dir.x},
					{x = -ws.dir.x, y = 0, z = -ws.dir.z},
				}
			end

			local deflected = false
			for c_idx = 1, #cand_dirs do
				local cand = cand_dirs[c_idx]
				if safety.is_step_safe(current_pos, cand, wander_abilities) then
					local cand_look = {
						x = current_pos.x + cand.x * 1.25,
						y = current_pos.y,
						z = current_pos.z + cand.z * 1.25,
					}
					local c_look_safe, c_reason = safety.is_step_safe(cand_look, cand, wander_abilities)
					if c_look_safe or (c_reason ~= "water" and c_reason ~= "hazard") then
						ws.dir = cand
						ws.yaw = core.dir_to_yaw(cand)
						ws.timer = 2.0 + math.random() * 1.5
						ws.is_moving = true
						locomotion.safe_set_yaw(self.object, ws.yaw)
						self._cur_rot = {x = 0, y = ws.yaw, z = 0}
						self.object:set_velocity({
							x = cand.x * speed,
							y = y_vel,
							z = cand.z * speed,
						})
						deflected = true
						break
					end
				end
			end

			if not deflected then
				ws.is_moving = false
				ws.timer = 0.6 + math.random() * 0.6
				self.object:set_velocity({x = 0, y = y_vel, z = 0})
				return {moving = false, speed = 0, has_los = false}
			end
		end
	end

	if on_wall_or_ceiling then
		local adj = surface.find_adjacent_surface(current_pos, self._cur_normal)
		if adj and adj.normal then
			local n = adj.normal
			local dot = ws.dir.x * n.x + ws.dir.y * n.y + ws.dir.z * n.z
			local wx = ws.dir.x - dot * n.x
			local wy = ws.dir.y - dot * n.y
			local wz = ws.dir.z - dot * n.z
			local wlen = math.sqrt(wx * wx + wy * wy + wz * wz)
			if wlen > 0.01 then
				self.object:set_velocity({
					x = (wx / wlen) * speed - n.x * 0.15,
					y = (wy / wlen) * speed - n.y * 0.15,
					z = (wz / wlen) * speed - n.z * 0.15,
				})
			else
				self.object:set_velocity({x = -n.x * 0.1, y = -n.y * 0.1, z = -n.z * 0.1})
			end
		else
			self.object:set_velocity({x = 0, y = 0, z = 0})
		end
		if self._cur_rot then
			locomotion.safe_set_rotation(self.object, self._cur_rot)
		end
	else
		local move_y_vel = y_vel
		if in_liquid and not is_aquatic then
			local fwd_x = math.floor(current_pos.x + ws.dir.x * 1.0 + 0.5)
			local fwd_z = math.floor(current_pos.z + ws.dir.z * 1.0 + 0.5)
			local fwd_y = math.floor(current_pos.y + 0.5)
			local fwd_node = node_cache.get_node({x = fwd_x, y = fwd_y, z = fwd_z})
			local fwd_def = core.registered_nodes[fwd_node.name]
			if fwd_def and fwd_def.walkable and (not fwd_def.liquidtype or fwd_def.liquidtype == "none") then
				move_y_vel = math.max(move_y_vel, 4.5)
			end
		end
		self.object:set_velocity({
			x = ws.dir.x * speed,
			y = move_y_vel,
			z = ws.dir.z * speed,
		})
		locomotion.safe_set_yaw(self.object, ws.yaw)
	end

	mob_memory.record_trail_step(self, current_pos, dtime)

	if ws.timer <= 0 then
		ws.is_moving = false
		ws.timer = 2.0 + math.random() * 3.0
		self.object:set_velocity({x = 0, y = y_vel, z = 0})
		return {moving = false, speed = 0, has_los = false}
	end

	return {moving = true, speed = speed, has_los = false}
end

--- Updates tactical fleeing behavior away from danger/threat sources
---@param self table Entity instance
---@param dtime number Step delta time
---@param current_pos Vector Current mob world position
---@param on_wall_or_ceiling boolean Whether mob is adhering to wall/ceiling
---@return table status Locomotion status {moving = boolean, speed = number, has_los = boolean}
function locomotion.handle_mob_fleeing(self, dtime, current_pos, on_wall_or_ceiling)
	if not self.abilities or not self._inherent_abilities then
		safety.init_abilities(self)
	end
	local max_hp = self.hp_max or (self.initial_properties and self.initial_properties.hp_max) or 40
	local hr = (self._def and self._def.health_regen) or self.health_regen
	local return_thresh = (hr and hr.return_threshold)
		or self.return_hp_threshold or (max_hp * (self.return_ratio or 0.60))
	local cur_hp = self.hp or (self.object and self.object:is_valid() and self.object:get_hp()) or max_hp
	local is_panicking = (self.panic_timer and self.panic_timer > 0)
	if not is_panicking and ((self.memory and not self.memory.flee_state) or cur_hp >= return_thresh) then
		self.state = "idle"
		if self.memory then self.memory.flee_state = false end
		self._flee_dir = nil
		self._flee_timer = nil
		self._flee_last_pos = nil
		self._flee_stagnant_timer = nil
		self._flee_standoff = nil
		return locomotion.handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
	end

	local threat_repulse = nil
	if self.target and is_valid_living_player(self.target) then
		local tpos = self.target:get_pos()
		if tpos then
			local dx = current_pos.x - tpos.x
			local dz = current_pos.z - tpos.z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist > 0.001 then
				threat_repulse = {x = dx / dist, y = 0, z = dz / dist}
			end
		end
	end

	if not threat_repulse then
		local repulse = mob_memory.get_danger_repulsion_vector(self, current_pos)
		local r_len = math.sqrt(repulse.x * repulse.x + repulse.z * repulse.z)
		if r_len > 0.001 then
			threat_repulse = {x = repulse.x / r_len, y = 0, z = repulse.z / r_len}
		end
	end

	if not threat_repulse then
		self._flee_dir = nil
		self._flee_timer = nil
		self._flee_deflecting = false
		self._flee_last_pos = nil
		self._flee_stagnant_timer = nil
		return locomotion.handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
	end

	local fpos = mob_memory.get_fight_pos(self)
	local ref_pos = (self.target and is_valid_living_player(self.target) and self.target:get_pos()) or fpos
	if not is_panicking and ref_pos then
		local max_flee = (hr and hr.max_flee_distance)
			or (self._def and self._def.max_flee_distance) or self.max_flee_distance or 15.0
		local rdx = current_pos.x - ref_pos.x
		local rdz = current_pos.z - ref_pos.z
		local dist_sq = rdx * rdx + rdz * rdz
		local resume_dist = math.max(4.0, max_flee - 3.5)
		local at_standoff = self._flee_standoff and (dist_sq >= (resume_dist * resume_dist))
			or (dist_sq >= (max_flee * max_flee))

		if at_standoff then
			self._flee_standoff = true
			locomotion.halt_horizontal_velocity(self)
			if not on_wall_or_ceiling and not self.is_floating then
				locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
			elseif self.is_floating then
				locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
				local combat_hover = self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4)
				local ground_y = utils.get_ground_y(current_pos, 8, 3, true, true)
				if ground_y then
					local desired_y = ground_y + combat_hover
					local h_dy = desired_y - current_pos.y
					if math.abs(h_dy) > 0.05 then
						local flt_vy = math.min(math.max(h_dy * 2.5, -4.0), 3.0)
						self.object:set_velocity({x = 0, y = flt_vy, z = 0})
					end
				end
			end
			self._flee_dir = nil
			self._flee_stagnant_timer = 0.0

			local rlen = math.sqrt(dist_sq)
			if rlen > 0.01 then
				local face_yaw = core.dir_to_yaw({x = -rdx / rlen, y = 0, z = -rdz / rlen})
				local cur_rot = self._cur_rot or {x = 0, y = locomotion.safe_get_yaw(self.object) or 0, z = 0}
				local target_rot = {x = 0, y = face_yaw, z = 0}
				local max_rot_step = (self.max_angular_speed or 4.0) * dtime
				local smoothed_rot = surface.interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 6.5), max_rot_step)
				self._cur_rot = smoothed_rot
				locomotion.safe_set_rotation(self.object, smoothed_rot)
			end
			if self.state ~= "idle" then
				self.state = "idle"
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
			end
			return {moving = false, speed = 0, has_los = false}
		else
			self._flee_standoff = nil
		end
	else
		self._flee_standoff = nil
	end

	self._flee_timer = (self._flee_timer or 0) - dtime
	if not self._flee_dir then
		self._flee_dir = threat_repulse
		self._flee_timer = 0.6
		self._flee_deflecting = false
	elseif self._flee_deflecting then
		if self._flee_timer <= 0 then
			self._flee_deflecting = false
			local dot = self._flee_dir.x * threat_repulse.x + self._flee_dir.z * threat_repulse.z
			if dot > 0.2 then
				self._flee_dir = threat_repulse
			end
		end
	else
		local blend = math.min(1.0, dtime * 6.0)
		local bx = self._flee_dir.x * (1.0 - blend) + threat_repulse.x * blend
		local bz = self._flee_dir.z * (1.0 - blend) + threat_repulse.z * blend
		local blen = math.sqrt(bx * bx + bz * bz)
		if blen > 0.001 then
			self._flee_dir = {x = bx / blen, y = 0, z = bz / blen}
		else
			self._flee_dir = threat_repulse
		end
	end

	local raw_speed = (hr and hr.flee_speed) or self.flee_speed or math.min((self.pursuit_speed or 4.0) * 1.05, 4.2)
	local speed = locomotion.get_effective_speed(self, raw_speed)
	local is_crawler = self.abilities and self.abilities.can_crawl

	if is_crawler and not on_wall_or_ceiling then
		local c_dir = self._flee_dir or threat_repulse
		local check_pos = {
			x = math.floor(current_pos.x + c_dir.x * 0.95 + 0.5),
			y = math.floor(current_pos.y + 0.5),
			z = math.floor(current_pos.z + c_dir.z * 0.95 + 0.5),
		}
		local c_node = node_cache.get_node(check_pos)
		local c_def = core.registered_nodes[c_node.name]
		if c_def and c_def.walkable then
			self.on_wall_or_ceiling = true
			locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			local wn = {
				x = (current_pos.x > check_pos.x) and 1 or ((current_pos.x < check_pos.x) and -1 or 0),
				y = 0,
				z = (current_pos.z > check_pos.z) and 1 or ((current_pos.z < check_pos.z) and -1 or 0),
			}
			if wn.x == 0 and wn.z == 0 then wn.x = -c_dir.x end
			self._cur_normal = wn
			local climb_speed = speed * 0.9
			self.object:set_velocity({
				x = -wn.x * 0.25,
				y = climb_speed,
				z = -wn.z * 0.25,
			})
			return {moving = true, speed = speed, has_los = false}
		end
	end

	local in_liquid, is_subm, _, target_vy = safety.check_in_liquid(
		current_pos, self._inherent_abilities or {can_swim = true}, self.mob_height
	)

	local is_aquatic = safety.is_aquatic_mob(self)
	local flee_abilities = self.abilities
	if not is_aquatic and not in_liquid then
		flee_abilities = utils.shallow_copy(self.abilities or {})
		flee_abilities.can_swim = false
		flee_abilities.disallow_water = true
	end

	if in_liquid and not is_aquatic then
		local shore_pos = safety.find_nearest_shore_pos(current_pos, 20) or self._last_ground_pos
		if shore_pos then
			local to_shore = vector.direction(current_pos, shore_pos)
			local flee_x = to_shore.x * 2.0 + threat_repulse.x * 0.8
			local flee_z = to_shore.z * 2.0 + threat_repulse.z * 0.8
			local flen = math.sqrt(flee_x * flee_x + flee_z * flee_z)
			if flen > 0.001 then
				self._flee_dir = {x = flee_x / flen, y = 0, z = flee_z / flen}
			else
				self._flee_dir = to_shore
			end
		end
	end

	local move_vec = self._flee_dir
	if not on_wall_or_ceiling then
		local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		local y_vel = vel.y
		if in_liquid then
			y_vel = target_vy or 0
			if is_subm then
				locomotion.safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
			else
				locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			end
			speed = speed * 0.75
		elseif self.is_floating then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			local combat_hover = self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4)
			local ground_y = utils.get_ground_y(current_pos, 24, 4, true, true)
			if ground_y then
				local desired_y = ground_y + combat_hover
				local h_dy = desired_y - current_pos.y
				y_vel = math.min(math.max(h_dy * 2.5, -5.0), 3.5)
			else
				y_vel = -3.5
			end
		else
			locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end

		if not self._flee_last_pos then
			self._flee_last_pos = {x = current_pos.x, y = current_pos.y, z = current_pos.z}
			self._flee_stagnant_timer = 0.0
		end
		local step_dx = current_pos.x - self._flee_last_pos.x
		local step_dz = current_pos.z - self._flee_last_pos.z
		local step_dist_sq = step_dx * step_dx + step_dz * step_dz
		self._flee_last_pos.x = current_pos.x
		self._flee_last_pos.y = current_pos.y
		self._flee_last_pos.z = current_pos.z

		if step_dist_sq < 0.002 then
			self._flee_stagnant_timer = (self._flee_stagnant_timer or 0) + dtime
		else
			self._flee_stagnant_timer = 0.0
		end

		doors.check_and_open_forward_doors(current_pos, self._flee_dir, self.abilities, self.object)

		local is_wall_hit, f_wall_norm = locomotion.has_wall_collision(self, current_pos, dtime)
		local is_stagnant = ((self._flee_stagnant_timer or 0) > 0.3) or is_wall_hit
		local step_direct = safety.is_step_safe(current_pos, self._flee_dir, flee_abilities)

		if step_direct then
			local look_pos = {
				x = current_pos.x + self._flee_dir.x * 1.25,
				y = current_pos.y,
				z = current_pos.z + self._flee_dir.z * 1.25,
			}
			local look_safe, look_reason = safety.is_step_safe(look_pos, self._flee_dir, flee_abilities)
			if not look_safe and (look_reason == "cliff" or look_reason == "water" or look_reason == "hazard") then
				step_direct = false
			end
		end

		if step_direct and not is_stagnant then
			self.object:set_velocity({
				x = self._flee_dir.x * speed,
				y = y_vel,
				z = self._flee_dir.z * speed,
			})
			move_vec = self._flee_dir
		else
			local tx = threat_repulse.x
			local tz = threat_repulse.z
			local px = tz
			local pz = -tx
			local inv_s2 = 0.70710678

			local cands = {}
			local has_norm = f_wall_norm and (f_wall_norm.x ~= 0 or f_wall_norm.z ~= 0)
			local nx, nz = 0, 0
			if has_norm then
				local nlen = math.sqrt(f_wall_norm.x * f_wall_norm.x + f_wall_norm.z * f_wall_norm.z)
				if nlen > 0.001 then
					nx = f_wall_norm.x / nlen
					nz = f_wall_norm.z / nlen
					cands[#cands + 1] = {x = -nz, y = 0, z = nx, is_tangent = true}
					cands[#cands + 1] = {x = nz, y = 0, z = -nx, is_tangent = true}
				end
			end

			local cur_bias = self._flee_dir.x * px + self._flee_dir.z * pz
			if cur_bias >= 0 then
				cands[#cands + 1] = {x = (tx + px) * inv_s2, y = 0, z = (tz + pz) * inv_s2}
				cands[#cands + 1] = {x = (tx - px) * inv_s2, y = 0, z = (tz - pz) * inv_s2}
				cands[#cands + 1] = {x = px, y = 0, z = pz}
				cands[#cands + 1] = {x = -px, y = 0, z = -pz}
				cands[#cands + 1] = {x = (-tx + px) * inv_s2, y = 0, z = (-tz + pz) * inv_s2}
				cands[#cands + 1] = {x = (-tx - px) * inv_s2, y = 0, z = (-tz - pz) * inv_s2}
			else
				cands[#cands + 1] = {x = (tx - px) * inv_s2, y = 0, z = (tz - pz) * inv_s2}
				cands[#cands + 1] = {x = (tx + px) * inv_s2, y = 0, z = (tz + pz) * inv_s2}
				cands[#cands + 1] = {x = -px, y = 0, z = -pz}
				cands[#cands + 1] = {x = px, y = 0, z = pz}
				cands[#cands + 1] = {x = (-tx - px) * inv_s2, y = 0, z = (-tz - pz) * inv_s2}
				cands[#cands + 1] = {x = (-tx + px) * inv_s2, y = 0, z = (-tz + pz) * inv_s2}
			end
			cands[#cands + 1] = {x = -tx, y = 0, z = -tz}

			local best_cand = nil
			local best_score = -99999.0

			for i = 1, #cands do
				local cand = cands[i]
				if safety.is_step_safe(current_pos, cand, flee_abilities) then
					local dot_threat = cand.x * tx + cand.z * tz
					local dot_cur = cand.x * self._flee_dir.x + cand.z * self._flee_dir.z
					local score = dot_threat * 3.0 + dot_cur * 0.8

					local cand_look = {
						x = current_pos.x + cand.x * 1.25,
						y = current_pos.y,
						z = current_pos.z + cand.z * 1.25,
					}
					local cand_look_safe, c_reason = safety.is_step_safe(cand_look, cand, flee_abilities)
					if cand_look_safe then
						score = score + 2.5
					elseif c_reason == "water" or c_reason == "hazard" or c_reason == "cliff" then
						score = score - 35.0
					else
						score = score - 15.0
					end

					if cand.is_tangent then
						score = score + 4.0
					end

					if has_norm then
						local dot_wall = cand.x * nx + cand.z * nz
						if dot_wall < -0.1 then
							score = score - 30.0
						elseif dot_wall >= 0 then
							score = score + 1.5
						end
					end

					if score > best_score then
						best_score = score
						best_cand = cand
					end
				end
			end

			if best_cand then
				self._flee_dir = {x = best_cand.x, y = 0, z = best_cand.z}
				self._flee_timer = 0.8
				self._flee_deflecting = true
				self._flee_stagnant_timer = 0.0
				self.object:set_velocity({
					x = best_cand.x * speed * 0.9,
					y = y_vel,
					z = best_cand.z * speed * 0.9,
				})
				move_vec = self._flee_dir
			else
				self.object:set_velocity({x = 0, y = y_vel, z = 0})
				if self.state ~= "idle" then
					self.state = "idle"
					animator.play(self.object, "idle", {speed = 1.0, loop = true})
				end
				return {moving = false, speed = 0, has_los = false}
			end
		end

		local target_yaw = core.dir_to_yaw(move_vec)
		local cur_rot = self._cur_rot or {x = 0, y = locomotion.safe_get_yaw(self.object) or 0, z = 0}
		local target_rot = {x = 0, y = target_yaw, z = 0}
		local max_rot_step = (self.max_angular_speed or 4.0) * dtime
		local smoothed_rot = surface.interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 6.5), max_rot_step)
		self._cur_rot = smoothed_rot
		locomotion.safe_set_rotation(self.object, smoothed_rot)
	else
		local surf_norm = self._cur_normal or {x = 0, y = 1, z = 0}
		local dot = move_vec.x * surf_norm.x + move_vec.y * surf_norm.y + move_vec.z * surf_norm.z
		local tan_x = move_vec.x - dot * surf_norm.x
		local tan_y = move_vec.y - dot * surf_norm.y
		local tan_z = move_vec.z - dot * surf_norm.z
		local tan_len = math.sqrt(tan_x * tan_x + tan_y * tan_y + tan_z * tan_z)
		if tan_len > 0.05 then
			local ux = tan_x / tan_len
			local uy = tan_y / tan_len
			local uz = tan_z / tan_len

			local next_surf_pos = {
				x = current_pos.x + ux * 0.85,
				y = current_pos.y + uy * 0.85,
				z = current_pos.z + uz * 0.85,
			}
			local ahead_surf = surface.find_adjacent_surface(next_surf_pos, surf_norm)
			if ahead_surf then
				self.object:set_velocity({
					x = ux * speed - surf_norm.x * 0.2,
					y = uy * speed - surf_norm.y * 0.2,
					z = uz * speed - surf_norm.z * 0.2,
				})
			else
				self.object:set_velocity({
					x = -surf_norm.x * 0.2,
					y = -surf_norm.y * 0.2,
					z = -surf_norm.z * 0.2,
				})
			end
		end
	end

	mob_memory.record_trail_step(self, current_pos, dtime)
	return {moving = true, speed = speed, has_los = false}
end

--- Executes a safe kiting retreat away from a target position with cliff/obstacle guard
---@param self table Mob instance
---@param target_pos Vector Threat / target world position
---@param speed? number Movement speed (default: self.pursuit_speed or self.walk_speed or 3.0)
---@param face_away? boolean If true, sets facing yaw towards chosen retreat escape direction instead of facing target
---@return boolean success True if a safe retreat direction was found and applied
function locomotion.retreat_from(self, target_pos, speed, face_away)
	local pos = self.object and self.object:get_pos()
	if not pos or not target_pos then return false end

	local away = vector.direction(target_pos, pos)
	away.y = 0
	local a_len = math.sqrt(away.x * away.x + away.z * away.z)
	if a_len <= 0.01 then return false end

	away = {x = away.x / a_len, y = 0, z = away.z / a_len}
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local raw_speed = speed or self.pursuit_speed or self.walk_speed or 3.0
	local k_speed = locomotion.get_effective_speed(self, raw_speed)

	local cos45, sin45 = 0.7071, 0.7071
	local candidates = {
		away,
		{x = away.x * cos45 - away.z * sin45, y = 0, z = away.x * sin45 + away.z * cos45},
		{x = away.x * cos45 + away.z * sin45, y = 0, z = -away.x * sin45 + away.z * cos45},
		{x = -away.z, y = 0, z = away.x},
		{x = away.z, y = 0, z = -away.x},
		{x = -away.x * cos45 - away.z * sin45, y = 0, z = -away.x * sin45 + away.z * cos45},
		{x = -away.x * cos45 + away.z * sin45, y = 0, z = away.x * sin45 - away.z * cos45},
	}

	local in_water = self.in_water or false
	local water_vy = self.water_vy or 0
	local abilities = in_water and
		{can_swim = true, can_crawl = false, disallow_water = false, is_floating = self.is_floating} or
		{can_swim = false, can_crawl = false, disallow_water = true, is_floating = self.is_floating}

	local chosen_dir = nil
	for i = 1, #candidates do
		local cand = candidates[i]
		if safety.is_step_safe(pos, cand, abilities, 1) then
			local pos2 = {x = pos.x + cand.x * 1.2, y = pos.y, z = pos.z + cand.z * 1.2}
			if safety.is_step_safe(pos2, cand, abilities, 1) then
				chosen_dir = cand
				break
			elseif not chosen_dir then
				chosen_dir = cand
			end
		end
	end

	if chosen_dir then
		local y_vel = in_water and water_vy or vel.y
		if not in_water and not self.is_floating then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		elseif self.is_floating then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			local combat_hover = self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4)
			local ground_y = utils.get_ground_y(pos, 24, 4, true, true)
			if ground_y then
				local desired_y = ground_y + combat_hover
				local h_dy = desired_y - pos.y
				y_vel = math.min(math.max(h_dy * 2.5, -5.0), 3.5)
			else
				y_vel = -3.5
			end
		end
		self.object:set_velocity({
			x = chosen_dir.x * k_speed,
			y = y_vel,
			z = chosen_dir.z * k_speed,
		})
		local yaw = face_away and core.dir_to_yaw(chosen_dir) or core.dir_to_yaw(vector.direction(pos, target_pos))
		self.object:set_yaw(yaw)
		self._cur_rot = {x = 0, y = yaw, z = 0}
		return true
	else
		local y_vel = in_water and water_vy or vel.y
		if not in_water and not self.is_floating then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		elseif self.is_floating then
			locomotion.safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			local combat_hover = self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4)
			local ground_y = utils.get_ground_y(pos, 24, 4, true, true)
			if ground_y then
				local desired_y = ground_y + combat_hover
				local h_dy = desired_y - pos.y
				y_vel = math.min(math.max(h_dy * 2.5, -5.0), 3.5)
			else
				y_vel = -3.5
			end
		end
		self.object:set_velocity({x = 0, y = y_vel, z = 0})
		local yaw = core.dir_to_yaw(vector.direction(pos, target_pos))
		self.object:set_yaw(yaw)
		self._cur_rot = {x = 0, y = yaw, z = 0}
		return false
	end
end

--- Advances tactical retreat, standoff kiting, and close-quarters retaliation for fleeing mobs.
--- Unifies forward-sprint escape locomotion, 180° standoff projectile kiting, and close-quarters
--- melee retaliation when cornered or caught.
---@param self table Entity instance
---@param dtime number Step delta time
---@param def? table Entity definition table
---@param _moveresult? table Engine move result
---@return boolean handled True if tactical retreat handled this step
function locomotion.step_tactical_retreat(self, dtime, def, _moveresult)
	if not self or not self.object or not self.object:is_valid() then
		return false
	end

	def = def or self._def or {}

	-- Check pack follower leash: prevent minion from fleeing beyond leash distance from leader
	if self.pack_role == "member" or (def.pack and def.pack.role == "member") then
		local within_leash, s_pos = x_mob_core.pack.coordination.check_leash(self)
		if not within_leash and s_pos then
			self.panic_timer = nil
			if self.memory then
				self.memory.flee_state = false
				self.memory.flee_hp_lock = nil
				mob_memory.clear_danger_memory(self)
			end
			if self.on_return_to_fight then
				self:on_return_to_fight()
			else
				self.state = "regrouping"
			end
			return true
		end
	end

	if def then
		self._def = def
	end

	local pos = self.object:get_pos()
	if not pos then return false end

	local target = self.target
	local has_living_target = target and utils.is_player_alive(target)

	-- If no living target, retreat away from environmental danger/threat memory
	if not has_living_target then
		local flee_anim = (def.animations and def.animations.flee and "flee")
			or (def.animations and def.animations.run and "run") or "walk"
		animator.play(self.object, flee_anim, {speed = 1.25, loop = true})
		local res = locomotion.handle_mob_fleeing(self, dtime, pos, self.on_wall_or_ceiling)
		if res and res.moving == false then
			if self.state ~= "idle" then
				self.state = "idle"
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
			end
		end
		return true
	end

	local tpos = target:get_pos()
	if not tpos then return false end

	local dist = vector.distance(pos, tpos)
	local to_target = vector.direction(pos, tpos)
	to_target.y = 0
	local t_len = math.sqrt(to_target.x * to_target.x + to_target.z * to_target.z)
	if t_len > 0.001 then
		to_target = {x = to_target.x / t_len, y = 0, z = to_target.z / t_len}
	else
		to_target = {x = 0, y = 0, z = 1}
	end
	local face_yaw = core.dir_to_yaw(to_target)

	-- 1. Close-Quarters Retaliation: if caught or cornered in melee reach, turn and fight back
	local m_cfg = type(def.melee) == "table" and def.melee or {}
	local is_melee_capable = (def.melee ~= false) and
		(def.melee ~= nil or def.damage or def.attack_range or def.perform_attack)
	local reach = m_cfg.range or (not def.shooter and def.attack_range) or 2.0
	local max_h_diff = m_cfg.max_height_diff or 2.0
	local dx = pos.x - tpos.x
	local dz = pos.z - tpos.z
	local hdist = math.sqrt(dx * dx + dz * dz)
	local vdist = math.abs(pos.y - tpos.y)
	local in_reach = (dist <= reach) or (hdist <= reach and vdist <= max_h_diff)

	if is_melee_capable and in_reach then
		local eye_pos = {x = pos.x, y = pos.y + (self.eye_offset or 1.5), z = pos.z}
		local target_eye = {x = tpos.x, y = tpos.y + 1.2, z = tpos.z}
		if utils.line_of_sight(eye_pos, target_eye) then
			-- If caught in melee reach while channeling heal, channel is interrupted!
			if self.state == "channeling" then
				self._flee_channel_timer = nil
				self._flee_burst_timer = 0
				self._flee_used = true
				if self.memory then self.memory.flee_state = false end
				self.state = "combat"
			end
			locomotion.halt_horizontal_velocity(self)
			locomotion.safe_set_yaw(self.object, face_yaw)
			self._cur_rot = {x = 0, y = face_yaw, z = 0}

			if (self.attack_cooldown or 0) <= 0 then
				melee.step(self, dtime, def)
				return true
			else
				if self.state ~= "attacking" and self.state ~= "idle" then
					self.state = "idle"
					animator.play(self.object, "idle", {speed = 1.0, loop = true})
				end
				return true
			end
		end
	end

	-- 2. Tactical Shooter Standoff Kiting: turn and sprint forward, turn 180° around to shoot
	-- Note: Mobs fleeing to recover health or panicking execute a full escape retreat (Section 3)
	local hr = def.health_regen or (self._def and self._def.health_regen) or self.health_regen
	local is_healing_flee = hr and (hr.flee_threshold or 0) > 0 and (
		(self.memory and self.memory.flee_state) or
		((self.hp or 0) <= (hr.flee_threshold or 0))
	)
	local is_panicking = (self.panic_timer and self.panic_timer > 0)
	local s_cfg = type(def.shooter) == "table" and def.shooter or {}
	local can_shoot_in_retreat = def.shooter and (s_cfg.shoot_while_retreating == true or
		(not is_healing_flee and not is_panicking))

	if can_shoot_in_retreat then
		local standoff_min = s_cfg.min_range or 6.0
		local standoff_max = s_cfg.range or def.attack_range or 15.0
		local max_flee = (hr and hr.max_flee_distance) or def.max_flee_distance or self.max_flee_distance or 14.0

		if dist < standoff_min then
			-- Inside standoff: sprint forward away from threat (no moonwalking!)
			local flee_anim = (def.animations and def.animations.flee and "flee")
				or (def.animations and def.animations.run and "run") or "run"
			animator.play(self.object, flee_anim, {speed = 1.25, loop = true})
			local res = locomotion.handle_mob_fleeing(self, dtime, pos, self.on_wall_or_ceiling)
			if res and res.moving == false then
				if self.state ~= "idle" then
					self.state = "idle"
					animator.play(self.object, "idle", {speed = 1.0, loop = true})
				end
			end
			return true
		elseif dist <= standoff_max then
			-- In optimal standoff bracket: check line of sight to fire
			local eye_pos = {x = pos.x, y = pos.y + (self.eye_offset or 1.5), z = pos.z}
			local target_eye = {x = tpos.x, y = tpos.y + 1.2, z = tpos.z}
			local los = utils.line_of_sight(eye_pos, target_eye)

			local shoot_ready = (self.attack_cooldown or 0) <= 0 and
				(not self.cooldowns or (self.cooldowns.shoot or 0) <= 0)

			if los and shoot_ready then
				locomotion.halt_horizontal_velocity(self)
				locomotion.safe_set_yaw(self.object, face_yaw)
				self._cur_rot = {x = 0, y = face_yaw, z = 0}
				shooter.step(self, dtime, def)
				return true
			elseif s_cfg.shoot_while_retreating == true and dist < max_flee then
				-- Shoot is on cooldown: continue running away until max_flee_distance is reached
				local flee_anim = (def.animations and def.animations.flee and "flee")
					or (def.animations and def.animations.run and "run") or "run"
				animator.play(self.object, flee_anim, {speed = 1.25, loop = true})
				local res = locomotion.handle_mob_fleeing(self, dtime, pos, self.on_wall_or_ceiling)
				if res and res.moving == false then
					if self.state ~= "idle" then
						self.state = "idle"
						animator.play(self.object, "idle", {speed = 1.0, loop = true})
					end
				end
				return true
			else
				locomotion.halt_horizontal_velocity(self)
				locomotion.safe_set_yaw(self.object, face_yaw)
				self._cur_rot = {x = 0, y = face_yaw, z = 0}
				if self.state ~= "attacking" and self.state ~= "shooting" and self.state ~= "idle" then
					self.state = "idle"
					animator.play(self.object, "idle", {speed = 1.0, loop = true})
				end
				return true
			end
		else
			-- Beyond maximum standoff distance: safe distance reached, halt, face threat and recover
			locomotion.halt_horizontal_velocity(self)
			locomotion.safe_set_yaw(self.object, face_yaw)
			self._cur_rot = {x = 0, y = face_yaw, z = 0}
			if self.state ~= "idle" then
				self.state = "idle"
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
			end
			return true
		end
	end

	-- Escape Retreat: Tactical Disengage & Channel vs Unlimited Flee
	local is_unlimited = hr and (hr.unlimited_flee == true)

	if is_unlimited then
		-- Unlimited continuous fleeing (e.g. Fallen Minion)
		local max_flee = (hr and hr.max_flee_distance) or def.max_flee_distance or self.max_flee_distance or 15.0
		local resume_dist = math.max(4.0, max_flee - 3.5)
		local at_standoff = self._flee_standoff and (dist >= resume_dist) or (dist >= max_flee)

		if at_standoff then
			self._flee_standoff = true
			locomotion.halt_horizontal_velocity(self)
			locomotion.safe_set_yaw(self.object, face_yaw)
			self._cur_rot = {x = 0, y = face_yaw, z = 0}
			if self.is_floating then
				local ground_y = utils.get_ground_y(pos, 24, 4, true, true)
				if ground_y then
					local combat_hover = self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4)
					local desired_y = ground_y + combat_hover
					local h_dy = desired_y - pos.y
					if math.abs(h_dy) > 0.05 then
						local flt_vy = math.min(math.max(h_dy * 2.5, -4.0), 3.0)
						self.object:set_velocity({x = 0, y = flt_vy, z = 0})
					end
				else
					self.object:set_velocity({x = 0, y = -3.5, z = 0})
				end
			end
			if self.state ~= "idle" then
				self.state = "idle"
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
			end
			return true
		else
			self._flee_standoff = nil
			local flee_anim = (def.animations and def.animations.flee and "flee")
				or (def.animations and def.animations.run and "run") or "walk"
			animator.play(self.object, flee_anim, {speed = 1.25, loop = true})
			local res = locomotion.handle_mob_fleeing(self, dtime, pos, self.on_wall_or_ceiling)
			if res and res.moving == false then
				if def.shooter then
					locomotion.safe_set_yaw(self.object, face_yaw)
					self._cur_rot = {x = 0, y = face_yaw, z = 0}
				end
				if self.state ~= "idle" then
					self.state = "idle"
					animator.play(self.object, "idle", {speed = 1.0, loop = true})
				end
			end
			return true
		end
	else
		-- Tactical Disengage: Single disengage burst -> stationary vulnerable healing channel
		if self._flee_used then
			-- Mob already executed its single tactical retreat this combat. Stand and fight!
			if self.memory then self.memory.flee_state = false end
			if self.state == "fleeing" or self.state == "channeling" then
				self.state = "combat"
			end
			return false
		end

		if self.state == "channeling" then
			locomotion.halt_horizontal_velocity(self)
			locomotion.safe_set_yaw(self.object, face_yaw)
			self._cur_rot = {x = 0, y = face_yaw, z = 0}
			if self.is_floating then
				local ground_y = utils.get_ground_y(pos, 24, 4, true, true)
				if ground_y then
					local combat_hover = self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4)
					local desired_y = ground_y + combat_hover
					local h_dy = desired_y - pos.y
					if math.abs(h_dy) > 0.05 then
						local flt_vy = math.min(math.max(h_dy * 2.5, -4.0), 3.0)
						self.object:set_velocity({x = 0, y = flt_vy, z = 0})
					end
				else
					self.object:set_velocity({x = 0, y = -3.5, z = 0})
				end
			end
			animator.play(self.object, "idle", {speed = 1.0, loop = true})

			self._channel_vfx_timer = (self._channel_vfx_timer or 0) + dtime
			if self._channel_vfx_timer >= 0.6 then
				self._channel_vfx_timer = 0
				if not hr or hr.overlay ~= false then
					x_mob_core.indicate_regen(self.object, hr and hr.overlay_color or "^[colorize:#FFFFFF60")
				end
			end

			self._flee_channel_timer = (self._flee_channel_timer or (hr and hr.channel_duration) or 3.0) - dtime
			if self._flee_channel_timer <= 0 then
				-- Channel completed uninterrupted! Restore health and re-engage combat!
				local max_hp = self.hp_max or (self.initial_properties and self.initial_properties.hp_max) or 20
				local restore = (hr and hr.heal_amount) or
					math.max(1, ((hr and hr.return_threshold) or math.floor(max_hp * 0.6)) - (self.hp or max_hp))
				local old_hp = self.hp or max_hp
				local new_hp = math.min(max_hp, old_hp + restore)
				self.hp = new_hp
				if self.object and self.object:is_valid() then
					self.object:set_hp(new_hp)
				end
				if not hr or hr.overlay ~= false then
					x_mob_core.indicate_regen(self.object, hr and hr.overlay_color or "^[colorize:#FFFFFF60")
				end
				x_mob_core.combat.health_bar.on_hp_change(self, old_hp, new_hp, def)

				self._flee_channel_timer = nil
				self._flee_burst_timer = nil
				self._flee_used = true
				if self.memory then
					self.memory.flee_state = false
					self.memory.flee_hp_lock = nil
				end
				self.state = "walk"
				if self.on_return_to_fight then
					self:on_return_to_fight()
				end
			end
			return true
		else
			-- Initial Disengage Burst Sprint (counts down to 0 or until safe distance reached)
			if not self._flee_burst_timer then
				self._flee_burst_timer = (hr and hr.burst_duration) or 3.5
			end
			self._flee_burst_timer = self._flee_burst_timer - dtime
			local safe_dist = (hr and hr.safe_distance) or 10.0

			if dist >= safe_dist or self._flee_burst_timer <= 0 then
				-- Reached safe distance or burst expired: halt and begin vulnerable healing channel!
				self._flee_burst_timer = 0
				self._flee_channel_timer = (hr and hr.channel_duration) or 3.0
				self.state = "channeling"
				locomotion.halt_horizontal_velocity(self)
				locomotion.safe_set_yaw(self.object, face_yaw)
				self._cur_rot = {x = 0, y = face_yaw, z = 0}
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
				if not hr or hr.overlay ~= false then
					x_mob_core.indicate_regen(self.object, hr and hr.overlay_color or "^[colorize:#FFFFFF60")
				end
				return true
			else
				-- Sprint away during burst
				local flee_anim = (def.animations and def.animations.flee and "flee")
					or (def.animations and def.animations.run and "run") or "walk"
				animator.play(self.object, flee_anim, {speed = 1.25, loop = true})
				local res = locomotion.handle_mob_fleeing(self, dtime, pos, self.on_wall_or_ceiling)
				if res and res.moving == false then
					if def.shooter then
						locomotion.safe_set_yaw(self.object, face_yaw)
						self._cur_rot = {x = 0, y = face_yaw, z = 0}
					end
					if self.state ~= "idle" then
						self.state = "idle"
						animator.play(self.object, "idle", {speed = 1.0, loop = true})
					end
				end
				return true
			end
		end
	end
end

return locomotion
