--[[
	mob_ai.lua - Pursuit-Gated Mob Motor Controller & Navigation Coordinator
	Modular coordinator delegating to doors, surface, safety, and locomotion submodules.
	- Tier 1: Fast-Path Line-of-Sight check bypassing A* graph search
	- Pursuit-Gated Traversal: Doors, Ladders, and Swimming unlocked ONLY during active pursuit
	- Non-locking Door Opening with Area Protection validation (leaves doors open)
	- Manual Ladder climbing physics counteracting gravity
	- Multiplayer Distance LOD: Refresh intervals scaled by player proximity
	- Production-ready entity integration and steering controller facade
]]

local modpath = core.get_modpath("x_mob_core") or "."
local utils = dofile(modpath .. "/core/utils.lua")
local node_cache = dofile(modpath .. "/motor/node_cache.lua")
local doors = dofile(modpath .. "/motor/doors.lua")
local surface = dofile(modpath .. "/motor/surface.lua")
local safety = dofile(modpath .. "/motor/safety.lua")
local locomotion = dofile(modpath .. "/motor/locomotion.lua")
local fast_pathfinder = x_mob_core.fast_pathfinder
local mob_memory = x_mob_core.mob_memory

---@class MobAISubsystem
local mob_ai = {}

local flank_slot_counter = 0
local airborne_vel_scratch = {x = 0, y = 0, z = 0}
local airborne_accel_scratch = {x = 0, y = -9.81, z = 0}

-- Localized subsystem delegations for high-frequency inner loops
local is_valid_living_player = utils.is_player_alive
local check_line_of_sight = utils.line_of_sight
local get_pursuit_state = locomotion.get_pursuit_state
local safe_get_yaw = locomotion.safe_get_yaw
local safe_set_yaw = locomotion.safe_set_yaw
local safe_set_acceleration = locomotion.safe_set_acceleration
local safe_set_rotation = locomotion.safe_set_rotation
local calculate_liquid_vertical_velocity = locomotion.calculate_liquid_vertical_velocity
local calculate_separation_force = locomotion.calculate_separation_force
local has_wall_collision = locomotion.has_wall_collision
local handle_mob_movement = locomotion.handle_mob_movement
local handle_mob_wandering = locomotion.handle_mob_wandering
local handle_mob_fleeing = locomotion.handle_mob_fleeing

local is_openable_door = doors.is_openable_door
local try_open_door_at_pos = doors.try_open_door_at_pos
local check_and_open_forward_doors = doors.check_and_open_forward_doors

local find_adjacent_surface = surface.find_adjacent_surface
local dir_to_surface_rotation = surface.dir_to_surface_rotation
local interpolate_rotation = surface.interpolate_rotation

local is_aquatic_mob = safety.is_aquatic_mob
local check_in_liquid = safety.check_in_liquid
local is_step_safe = safety.is_step_safe
local is_valid_stand_pos = safety.is_valid_stand_pos
local check_corridor_line_of_sight = safety.check_corridor_line_of_sight
local check_ground_line_of_sight = safety.check_ground_line_of_sight

--- Calculates Multiplayer Level of Detail (LOD) path recalculation interval
---@param dist number Distance in nodes to nearest target
---@return number|nil interval Refresh interval in seconds, or nil if A* is paused
local function get_lod_refresh_interval(dist)
	if dist < 12.0 then
		return 1.0 -- Close range: high frequency update
	elseif dist <= 32.0 then
		return 3.0 -- Medium range: relaxed update
	else
		return nil -- Long range: pause A*, switch to local wandering
	end
end

--- Calculates target vertical velocity for floating mobs during combat pursuit
--- Anchors hovering elevation slightly above ground or target footing
---@param self table Mob entity instance
---@param current_pos Vector Current mob world position
---@param target_pos Vector Target world position
---@return number y_vel Vertical velocity
local function calculate_floating_combat_elevation(self, current_pos, target_pos)
	local combat_hover = self.combat_hover_offset or math.min(self.hover_offset or 0.35, 0.4)
	local ground_y = utils.get_ground_y(current_pos, 8, 3, true, true)
	local desired_y = ground_y and (ground_y + combat_hover) or (target_pos.y + combat_hover)
	local h_dy = desired_y - current_pos.y
	if math.abs(h_dy) < 0.04 then
		return 0
	end
	return math.min(math.max(h_dy * 2.5, -5.0), 4.5)
end

--- Updates entity navigation, scanning, line-of-sight, and path execution
---@param self table Entity instance
---@param dtime number Step delta time
---@return table status Locomotion status {moving = boolean, speed = number, has_los = boolean}
function mob_ai.update_navigation(self, dtime)
	-- Initialize navigation state tables and abilities if missing
	safety.init_abilities(self)

	self.path_state.timer = (self.path_state.timer or 0) + dtime
	local current_pos = self.object:get_pos()
	if not current_pos then return {moving = false, speed = 0, has_los = false} end

	-- Drop invalid or dead target
	if self.target and not is_valid_living_player(self.target) then
		self.target = nil
		self.path_state.waypoints = nil
		self.path_state.index = 1
	end

	local is_pursuing = get_pursuit_state(self) == true
	local is_active = is_pursuing or (self.target ~= nil) or
		(self.state == "fleeing") or (self.state == "regrouping") or
		(self.panic_timer and self.panic_timer > 0)

	local inh = self._inherent_abilities
	self.abilities.can_open_doors = (inh.can_open_doors and is_active) == true
	self.abilities.can_climb = (inh.can_climb and is_active) == true
	self.abilities.can_crawl = inh.can_crawl == true
	self.abilities.is_floating = inh.is_floating == true

	local in_liq = check_in_liquid(current_pos, self.abilities, self.mob_height)
	self.in_water = in_liq
	local is_aquatic = is_aquatic_mob(self)
	local is_airborne = (inh.is_floating == true) or (self.is_floating == true)

	if is_aquatic then
		self.abilities.can_swim = inh.can_swim == true
		self.abilities.disallow_water = false
		self.abilities.in_liquid = in_liq
		self.abilities.allow_water_escape = false
	elseif is_airborne then
		self.abilities.can_swim = false
		self.abilities.disallow_water = false
		self.abilities.in_liquid = in_liq
		self.abilities.allow_water_escape = in_liq
	else
		-- Terrestrial mob: swimming through water is permitted during active pursuit or emergency shore escape
		if (is_pursuing and inh.can_swim) or in_liq then
			self.abilities.can_swim = true
			self.abilities.disallow_water = false
			self.abilities.in_liquid = in_liq
			self.abilities.allow_water_escape = in_liq
		else
			self.abilities.can_swim = false
			self.abilities.disallow_water = true
			self.abilities.in_liquid = false
			self.abilities.allow_water_escape = false
		end
	end

	-- Track last known solid dry ground position for terrestrial mobs
	if not self.is_floating and not is_aquatic then
		if not in_liq then
			local cur_floor = node_cache.get_node({
				x = math.floor(current_pos.x + 0.5),
				y = math.floor(current_pos.y - 0.4),
				z = math.floor(current_pos.z + 0.5),
			})
			local fdef = core.registered_nodes[cur_floor.name]
			if fdef and fdef.walkable and (not fdef.liquidtype or fdef.liquidtype == "none") then
				self._last_ground_pos = {x = current_pos.x, y = current_pos.y, z = current_pos.z}
			end
		end
	end

	local on_wall_or_ceiling = self._cur_rot and (math.abs(self._cur_rot.x) > 0.4 or math.abs(self._cur_rot.z) > 0.4)
	local is_crawler = self.abilities and self.abilities.can_crawl == true
	local adj_surf = nil

	if is_crawler then
		local ceiling_norm = (self._cur_rot and math.abs(self._cur_rot.z) > 2.0) and {x = 0, y = -1, z = 0} or nil
		local pref_norm = self._cur_normal or ceiling_norm
		adj_surf = find_adjacent_surface(current_pos, pref_norm)

		local following_wall_wpt = self.path_state and self.path_state.waypoints and
			self.path_state.index <= #self.path_state.waypoints and
			self.path_state.waypoints[self.path_state.index].surface_type == "wall"

		local surface_selbox = self.selectionbox
			or (self.initial_properties and self.initial_properties.selectionbox)
			or {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85}

		local ground_cbox = self.collisionbox
			or (self.initial_properties and self.initial_properties.collisionbox)
			or {-0.35, 0.0, -0.35, 0.35, 0.45, 0.35}

		if on_wall_or_ceiling and not adj_surf then
			-- PHYSICAL ADJACENCY WATCHDOG: Detach immediately and fall under gravity
			on_wall_or_ceiling = false
			self.on_wall_or_ceiling = false
			self._has_wall_cbox = false
			self._cur_normal = nil
			self._cur_rot = {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
			safe_set_rotation(self.object, self._cur_rot)
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
			self.object:set_properties({
				collisionbox = ground_cbox,
				selectionbox = surface_selbox,
			})
			if self.path_state then
				self.path_state.waypoints = nil
				self.path_state.index = 1
			end
		elseif on_wall_or_ceiling and adj_surf and adj_surf.surface_type == "floor" and not following_wall_wpt then
			-- Transitioning back onto floor gracefully without clearing waypoints
			on_wall_or_ceiling = false
			self.on_wall_or_ceiling = false
			self._has_wall_cbox = false
			self._cur_normal = {x = 0, y = 1, z = 0}
			self._cur_rot = {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
			safe_set_rotation(self.object, self._cur_rot)
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
			self.object:set_properties({
				collisionbox = ground_cbox,
				selectionbox = surface_selbox,
			})
		elseif adj_surf and (adj_surf.surface_type == "wall" or adj_surf.surface_type == "ceiling") then
			on_wall_or_ceiling = true
			self.on_wall_or_ceiling = true
			self._cur_normal = adj_surf.normal
			safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			if self.object and not self._has_wall_cbox then
				self._has_wall_cbox = true
				self.object:set_properties({
					collisionbox = {-0.20, -0.20, -0.20, 0.20, 0.20, 0.20},
					selectionbox = surface_selbox,
				})
			end
		end
	end

	-- Terrestrial mob airborne ballistic handling (knockback, falls, projectile launches)
	if not self.is_floating and not is_aquatic and not on_wall_or_ceiling and not self.in_water then
		local on_ground = (self._moveresult and self._moveresult.touching_ground) == true
		if not on_ground and not self._moveresult then
			local bnode = node_cache.get_node({
				x = math.floor(current_pos.x + 0.5),
				y = math.floor(current_pos.y - 0.2),
				z = math.floor(current_pos.z + 0.5),
			})
			local bdef = core.registered_nodes[bnode.name]
			if bdef and bdef.walkable then
				on_ground = true
			end
		end

		if on_ground then
			self._knockback_timer = nil
		else
			local cur_vel = self.object:get_velocity() or airborne_vel_scratch
			local cur_vy = (cur_vel and cur_vel.y) or 0
			local is_kb = (self._knockback_timer and self._knockback_timer > 0)
			if is_kb or math.abs(cur_vy) > 0.6 then
				safe_set_acceleration(self.object, airborne_accel_scratch)
				local drag = math.max(0.0, 1.0 - 1.2 * dtime)
				local new_vx = (cur_vel.x or 0) * drag
				local new_vz = (cur_vel.z or 0) * drag
				airborne_vel_scratch.x = new_vx
				airborne_vel_scratch.y = cur_vy
				airborne_vel_scratch.z = new_vz
				self.object:set_velocity(airborne_vel_scratch)

				local h_sq = new_vx * new_vx + new_vz * new_vz
				if h_sq > 0.04 then
					local flight_yaw = core.dir_to_yaw(airborne_vel_scratch)
					if flight_yaw then
						safe_set_yaw(self.object, flight_yaw)
						self._cur_rot = self._cur_rot or {x = 0, y = 0, z = 0}
						self._cur_rot.x = 0
						self._cur_rot.y = flight_yaw
						self._cur_rot.z = 0
					end
				end

				if not self._nav_result then
					self._nav_result = {moving = false, speed = 0, has_los = false}
				end
				self._nav_result.moving = (h_sq > 0.01)
				self._nav_result.speed = math.sqrt(h_sq)
				self._nav_result.has_los = true
				return self._nav_result
			end
		end
	end

	-- Fleeing state check (low HP retreat away from danger)
	if self.state == "fleeing" or self.state == "flee" then
		return handle_mob_fleeing(self, dtime, current_pos, on_wall_or_ceiling)
	end

	local target_pos
	if not is_pursuing then
		if self.nav_target_pos then
			target_pos = self.nav_target_pos
		else
			-- Check for swarm alert investigation when mob is idle/wandering
			local tm = self.memory and self.memory.target
			if tm and tm.has_record and tm.name == "swarm_alert" then
				local lkp = mob_memory.get_lkp_target(self, 8.0)
				if lkp then
					local lkp_dist = vector.distance(current_pos, lkp)
					if lkp_dist > 1.4 then
						target_pos = lkp
					else
						mob_memory.clear_target_memory(self)
						return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
					end
				else
					return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
				end
			else
				return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
			end
		end
	else
		target_pos = self.target and self.target.get_pos and self.target:get_pos()
		if not target_pos then
			if self.nav_target_pos then
				target_pos = self.nav_target_pos
			else
				return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
			end
		end
	end

	if self.wander_state and self.wander_state.is_moving then
		self.wander_state.is_moving = false
	end

	mob_memory.record_trail_step(self, current_pos, dtime)

	-- Anti-stuck watchdog: detect if mob is physically stagnant while attempting to move
	if not self._stuck_pos then
		self._stuck_pos = {x = current_pos.x, y = current_pos.y, z = current_pos.z}
		self._stuck_timer = 0.0
	else
		local stuck_dx = current_pos.x - self._stuck_pos.x
		local stuck_dy = current_pos.y - self._stuck_pos.y
		local stuck_dz = current_pos.z - self._stuck_pos.z
		local stuck_dist_sq = stuck_dx * stuck_dx + stuck_dy * stuck_dy + stuck_dz * stuck_dz
		if stuck_dist_sq > 1.44 then
			self._stuck_pos.x = current_pos.x
			self._stuck_pos.y = current_pos.y
			self._stuck_pos.z = current_pos.z
			self._stuck_timer = 0.0
		else
			self._stuck_timer = self._stuck_timer + dtime
			if self._stuck_timer > 1.0 then
				local target_dist = vector.distance(current_pos, target_pos)
				if target_dist > 3.0 then
					mob_memory.record_blocked_spot(self, current_pos, 4.0)
				end
				if self.path_state then
					self.path_state.waypoints = nil
					self.path_state.index = 1
					if not self.path_state.retry_delay or self.path_state.retry_delay <= 0 then
						self.path_state.timer = 999.0
					end
				end
				self._stuck_timer = 0.0
			end
		end
	end

	local dist = vector.distance(current_pos, target_pos)

	-- Assign deterministic tactical flanking slot & unique path seed to each mob
	if not self._flank_slot then
		flank_slot_counter = (flank_slot_counter % 4) + 1
		self._flank_slot = flank_slot_counter
		self._flank_dist = 2.0 + (self._flank_slot * 0.4)
		self.abilities.path_seed = math.random(1, 1000)
	end
	self.abilities.flank_slot = self._flank_slot

	-- Compute mob-specific tactical destination offset around target
	local nav_target_pos = target_pos
	if dist > 4.5 then
		local flank_angles = {0.0, 1.1, -1.1, 2.8}
		local f_angle = flank_angles[self._flank_slot] or 0.0
		if f_angle ~= 0.0 then
			local p_yaw = safe_get_yaw(self.target) or 0
			local angle = p_yaw + f_angle
			local f_dist = math.max(3.5, self._flank_dist or 3.5)
			local test_pos = {
				x = target_pos.x - math.sin(angle) * f_dist,
				y = target_pos.y,
				z = target_pos.z + math.cos(angle) * f_dist,
			}
			if is_valid_stand_pos(test_pos) then
				nav_target_pos = test_pos
			end
		end
	end

	-- Proactive door opening ahead of target line-of-sight check
	if dist <= 6.0 then
		local to_t = vector.direction(current_pos, target_pos)
		check_and_open_forward_doors(current_pos, to_t, self.abilities, self.object)
	end

	-- ---------------------------------------------------------------------
	-- TIER 1: FAST-PATH LINE-OF-SIGHT CHECK
	-- ---------------------------------------------------------------------
	local eye_offset = self.eye_offset or 1.5
	local mob_eye = {x = current_pos.x, y = current_pos.y + eye_offset, z = current_pos.z}
	local target_eye = {x = target_pos.x, y = target_pos.y + 1.5, z = target_pos.z}

	local has_los = check_line_of_sight(mob_eye, target_eye)
	local dy = math.abs(current_pos.y - target_pos.y)

	self.path_state._corridor_timer = (self.path_state._corridor_timer or 0) + dtime
	local corridor_clear = false
	local has_ground_los = false
	local glos_reason = self.path_state._glos_reason_cached

	if has_los then
		self.lost_sight_timer = 0
		mob_memory.record_target_sighting(self, self.target, target_pos)
		if self.path_state._corridor_cached ~= nil and self.path_state._corridor_timer < 0.2 then
			corridor_clear = self.path_state._corridor_cached
			has_ground_los = self.path_state._ground_los_cached
		else
			self.path_state._corridor_timer = 0
			local glos_ok, reason = check_ground_line_of_sight(current_pos, target_pos, self.abilities)
			glos_reason = reason
			has_ground_los = self.is_floating or glos_ok
			corridor_clear = has_ground_los and check_corridor_line_of_sight(
				current_pos, target_pos, eye_offset, self.half_width
			)
			self.path_state._corridor_cached = corridor_clear
			self.path_state._ground_los_cached = has_ground_los
			self.path_state._glos_reason_cached = glos_reason
		end
	else
		self.lost_sight_timer = (self.lost_sight_timer or 0) + dtime
		self.path_state._corridor_cached = false
		self.path_state._ground_los_cached = false
		self.path_state._glos_reason_cached = nil
		if is_pursuing and self.lost_sight_timer > 8.0 then
			self.target = nil
			mob_memory.clear_target_memory(self)
			self.lost_sight_timer = 0
			if self.path_state then
				self.path_state.waypoints = nil
				self.path_state.index = 1
			end
			self.state = "wandering"
			return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
		end
	end

	if has_los and corridor_clear and has_ground_los and not on_wall_or_ceiling and (self.is_floating or dy <= 3.5) then
		local steer_dest = (dist > 4.5) and nav_target_pos or target_pos
		local attack_rng = self.attack_range or 2.0
		local standoff_dist = self.combat_standoff or math.max(1.3, attack_rng * 0.7)
		local h_dx = current_pos.x - target_pos.x
		local h_dz = current_pos.z - target_pos.z
		local h_dist = math.sqrt(h_dx * h_dx + h_dz * h_dz)

		if self.is_floating and dist <= 4.5 then
			if h_dist > 0.05 then
				local h_dir_x = h_dx / h_dist
				local h_dir_z = h_dz / h_dist
				steer_dest = {
					x = target_pos.x + h_dir_x * standoff_dist,
					y = target_pos.y,
					z = target_pos.z + h_dir_z * standoff_dist,
				}
			end
		end

		local move_vec = vector.direction(current_pos, steer_dest)

		check_and_open_forward_doors(current_pos, move_vec, self.abilities, self.object)

		local step_ok = is_step_safe(current_pos, move_vec, self.abilities)
		if step_ok then
			self.path_state.waypoints = nil
			self.path_state.index = 1

			local speed = self.pursuit_speed or 4.0
			local in_melee_contact = (dist <= attack_rng * 0.75)

			if self.is_floating then
				in_melee_contact = (h_dist <= attack_rng * 0.85)
				if dist <= 4.5 then
					local gap = h_dist - standoff_dist
					if gap > 0.08 then
						speed = math.min(speed, math.max(0.0, gap * 2.5))
					elseif gap < -0.25 and h_dist > 0.05 then
						-- Player stepped into mob's personal space; back up to maintain standoff
						local h_dir_x = h_dx / h_dist
						local h_dir_z = h_dz / h_dist
						move_vec = {x = h_dir_x, y = 0, z = h_dir_z}
						speed = math.min(1.8, (-gap) * 2.0)
					else
						-- Holding ideal standoff line
						speed = 0.0
						move_vec = {x = 0, y = 0, z = 0}
					end
				end
			elseif in_melee_contact then
				speed = math.max(0.0, (dist - 1.1) * 2.5)
			end
			local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
			local y_vel = vel.y
			local in_liquid, is_subm, _, target_vy = check_in_liquid(
				current_pos, self.abilities, self.mob_height
			)

			local cur_n = node_cache.get_node({
				x = math.floor(current_pos.x + 0.5),
				y = math.floor(current_pos.y + 0.5),
				z = math.floor(current_pos.z + 0.5),
			})
			local cur_def = core.registered_nodes[cur_n.name] or {}
			local on_ladder = is_pursuing and self.abilities.can_climb and (cur_def.climbable == true)

			if on_ladder then
				safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
				local dy_target = steer_dest.y - current_pos.y
				if math.abs(dy_target) > 0.15 then
					y_vel = (dy_target > 0) and 2.2 or -2.2
				else
					y_vel = 0
				end
				self._was_in_ladder = true
			elseif in_liquid then
				y_vel = calculate_liquid_vertical_velocity(self, current_pos.y, steer_dest.y, is_subm, target_vy)
				speed = speed * 0.75
			elseif self.is_floating then
				safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
				y_vel = calculate_floating_combat_elevation(self, current_pos, target_pos)
			else
				safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
				if self._was_in_ladder then
					self._was_in_ladder = false
					if y_vel > 0 then
						y_vel = 0
					end
				end
			end

			local sep = calculate_separation_force(self, current_pos, dtime, false, {x = 0, y = 1, z = 0})
			local sep_x = sep.x
			local sep_z = sep.z
			if in_melee_contact then
				sep_x = sep_x * 0.2
				sep_z = sep_z * 0.2
			end
			self.object:set_velocity({
				x = move_vec.x * speed + sep_x,
				y = y_vel,
				z = move_vec.z * speed + sep_z,
			})

			local face_vec = (self.is_floating or in_melee_contact) and vector.direction(current_pos, target_pos) or move_vec
			if math.abs(face_vec.x) > 0.01 or math.abs(face_vec.z) > 0.01 then
				local target_yaw = core.dir_to_yaw(face_vec)
				local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
				local target_rot = {x = 0, y = target_yaw, z = 0}
				local max_rot_step = (self.max_angular_speed or 4.0) * dtime
				local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 6.5), max_rot_step)
				self._cur_rot = smoothed_rot
				safe_set_rotation(self.object, smoothed_rot)
			end
			return {moving = true, speed = speed, has_los = true}
		else
			self.path_state._corridor_cached = false
		end
	end

	-- ---------------------------------------------------------------------
	-- TIER 2: MULTIPLAYER DISTANCE LOD & ASYNC A* PATH REQUEST
	-- ---------------------------------------------------------------------
	local refresh_interval = get_lod_refresh_interval(dist)
	local is_crawler_active = (self.abilities and self.abilities.can_crawl == true)
	local is_elevated_or_wall = is_crawler_active and (on_wall_or_ceiling or math.abs(target_pos.y - current_pos.y) > 1.5)
	local astar_target = (is_elevated_or_wall or not is_valid_stand_pos(nav_target_pos)) and target_pos or nav_target_pos

	local can_query = refresh_interval and (not self.path_state.waypoints or self.path_state.timer >= refresh_interval)
	if self.path_state.retry_delay and self.path_state.retry_delay > 0 then
		self.path_state.retry_delay = self.path_state.retry_delay - dtime
		can_query = false
	end

	if can_query then
		if not self.path_state.is_calculating then
			self.path_state.is_calculating = true
			self.path_state.timer = 0.0

			fast_pathfinder.find_path(current_pos, astar_target, self.abilities, function(waypoints)
				if not self.object or not self.object:is_valid() then return end
				self.path_state.is_calculating = false
				if waypoints and #waypoints > 0 then
					self.path_state.waypoints = waypoints
					self.path_state.index = 1
					self.path_state.retry_delay = 0
					self._water_blocked_timer = 0
					self._unreachable_fails = 0
				else
					self.path_state.waypoints = nil
					self.path_state.retry_delay = 1.0 + (self._unreachable_fails or 0) * 0.5
					self._unreachable_fails = (self._unreachable_fails or 0) + 1
				end
			end, self.mob_height)
		end
	end

	-- ---------------------------------------------------------------------
	-- TIER 3: EXECUTE WAYPOINT PATH MOTOR CONTROL
	-- ---------------------------------------------------------------------
	local waypoints = self.path_state.waypoints
	local idx = self.path_state.index

	if waypoints and idx <= #waypoints then
		local next_waypoint = waypoints[idx]
		handle_mob_movement(self, dtime, current_pos, next_waypoint)
		return {moving = true, speed = self.pursuit_speed or 4.0, has_los = false}
	else
		if waypoints and idx > #waypoints then
			self.path_state.waypoints = nil
			self.path_state.index = 1
			self.path_state.timer = refresh_interval or 0.5
		end

		local is_water_blocking = (glos_reason == "water")
		if not is_water_blocking and not (self.abilities and self.abilities.can_swim) then
			local _, s_reason = is_step_safe(current_pos, vector.direction(current_pos, target_pos), self.abilities)
			if s_reason == "water" then
				is_water_blocking = true
			end
		end
		local is_unreachable = (self._unreachable_fails or 0) >= 2
		local water_blocked = not has_ground_los and is_water_blocking and
			not self.is_floating and not (self.abilities and self.abilities.can_swim)
		if water_blocked then
			self._water_blocked_timer = (self._water_blocked_timer or 0) + dtime
		else
			self._water_blocked_timer = 0
		end

		if (water_blocked and (self._water_blocked_timer >= 2.0 or is_unreachable)) or is_unreachable then
			if self.target then
				mob_memory.record_unreachable_target(self, self.target, 10.0)
				mob_memory.record_blocked_spot(self, current_pos, 8.0)
			end
			self.target = nil
			self.state = "wandering"
			self._water_blocked_timer = 0
			self._unreachable_fails = 0
			if self.path_state then
				self.path_state.waypoints = nil
				self.path_state.index = 1
				self.path_state.retry_delay = 0
			end
			self._contour_timer = nil
			self._contour_dir = nil

			local away_x = current_pos.x - target_pos.x
			local away_z = current_pos.z - target_pos.z
			local away_dist = math.sqrt(away_x * away_x + away_z * away_z)
			local away_dir
			if away_dist > 0.01 then
				away_dir = {x = away_x / away_dist, y = 0, z = away_z / away_dist}
			else
				away_dir = {x = 1, y = 0, z = 0}
			end
			local away_yaw = core.dir_to_yaw(away_dir)
			safe_set_yaw(self.object, away_yaw)
			self._cur_rot = {x = 0, y = away_yaw, z = 0}
			safe_set_rotation(self.object, self._cur_rot)

			self.wander_state = {
				is_moving = true,
				timer = 3.5 + math.random() * 2.5,
				dir = away_dir,
				yaw = away_yaw,
				origin = {x = current_pos.x, y = current_pos.y, z = current_pos.z},
			}
			local w_speed = self.wander_speed or (self.walk_speed and self.walk_speed * 0.6) or 1.8
			local cur_vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
			self.object:set_velocity({
				x = away_dir.x * w_speed,
				y = cur_vel.y,
				z = away_dir.z * w_speed,
			})
			x_mob_core.animator.play(self.object, "walk", {speed = 1.0, loop = true})
			return {moving = true, speed = w_speed, has_los = false}
		end

		local lkp = (not has_los and not on_wall_or_ceiling) and
			mob_memory.get_lkp_target(self, 8.0) or nil
		if self.path_state.is_calculating or has_los or lkp or on_wall_or_ceiling then
			local h_dx = current_pos.x - target_pos.x
			local h_dz = current_pos.z - target_pos.z
			local h_dist = math.sqrt(h_dx * h_dx + h_dz * h_dz)
			local pursuit_dest = target_pos
			if not has_los and not on_wall_or_ceiling and lkp then
				pursuit_dest = lkp
				local lkp_dist = vector.distance(current_pos, lkp)
				if lkp_dist <= 1.5 then
					mob_memory.clear_target_memory(self)
				end
			elseif self.is_floating and dist <= 4.5 and h_dist > 0.05 then
				local attack_rng = self.attack_range or 2.0
				local standoff_dist = self.combat_standoff or math.max(1.3, attack_rng * 0.7)
				local h_dir_x = h_dx / h_dist
				local h_dir_z = h_dz / h_dist
				pursuit_dest = {
					x = target_pos.x + h_dir_x * standoff_dist,
					y = target_pos.y,
					z = target_pos.z + h_dir_z * standoff_dist,
				}
			end
			local move_vec = vector.direction(current_pos, pursuit_dest)
			local speed = (self.pursuit_speed or 4.0) * 0.75
			local target_above = (target_pos.y - current_pos.y) > 2.5
			local flat_dist = h_dist

			if not on_wall_or_ceiling and not self.is_floating and target_above then
				if is_crawler then
					if flat_dist > 2.5 then
						local steer_target = nav_target_pos or target_pos
						local steer_dx = steer_target.x - current_pos.x
						local steer_dz = steer_target.z - current_pos.z
						local steer_len = math.sqrt(steer_dx * steer_dx + steer_dz * steer_dz)
						if steer_len > 0.1 then
							move_vec = {x = steer_dx / steer_len, y = 0, z = steer_dz / steer_len}
						else
							move_vec = {
								x = (target_pos.x - current_pos.x) / (flat_dist > 0.01 and flat_dist or 1),
								y = 0,
								z = (target_pos.z - current_pos.z) / (flat_dist > 0.01 and flat_dist or 1),
							}
						end
					else
						local f_dist = flat_dist > 0.01 and flat_dist or 1
						move_vec = {
							x = (target_pos.x - current_pos.x) / f_dist,
							y = 0,
							z = (target_pos.z - current_pos.z) / f_dist,
						}
					end
				else
					local standoff_dist = self._flank_dist or 3.2
					if flat_dist > standoff_dist + 0.6 then
						if nav_target_pos and flat_dist > 2.0 then
							move_vec = vector.direction(current_pos, nav_target_pos)
						else
							move_vec = {
								x = (target_pos.x - current_pos.x) / (flat_dist > 0.01 and flat_dist or 1),
								y = 0,
								z = (target_pos.z - current_pos.z) / (flat_dist > 0.01 and flat_dist or 1),
							}
						end
					elseif flat_dist < standoff_dist - 0.6 then
						if flat_dist > 0.1 then
							move_vec = {
								x = (current_pos.x - target_pos.x) / flat_dist,
								y = 0,
								z = (current_pos.z - target_pos.z) / flat_dist,
							}
						else
							move_vec = {x = 0, y = 0, z = 0}
						end
					else
						speed = 0.0
						move_vec = {
							x = (target_pos.x - current_pos.x) / (flat_dist > 0.01 and flat_dist or 1),
							y = 0,
							z = (target_pos.z - current_pos.z) / (flat_dist > 0.01 and flat_dist or 1),
						}
					end
				end
			end

			if is_crawler and not on_wall_or_ceiling and not self.is_floating then
				local check_pos = {
					x = math.floor(current_pos.x + move_vec.x * 0.95 + 0.5),
					y = math.floor(current_pos.y + 0.5),
					z = math.floor(current_pos.z + move_vec.z * 0.95 + 0.5),
				}
				local c_node = node_cache.get_node(check_pos)
				local c_def = core.registered_nodes[c_node.name]
				if c_def and c_def.walkable then
					self.on_wall_or_ceiling = true
					safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})

					local wn = {
						x = (current_pos.x > check_pos.x) and 1 or ((current_pos.x < check_pos.x) and -1 or 0),
						y = 0,
						z = (current_pos.z > check_pos.z) and 1 or ((current_pos.z < check_pos.z) and -1 or 0),
					}
					if wn.x == 0 and wn.z == 0 then wn.x = -move_vec.x end
					self._cur_normal = wn

					if self.object and not self._has_wall_cbox then
						self._has_wall_cbox = true
						local climb_selbox = self.selectionbox
							or (self.initial_properties and self.initial_properties.selectionbox)
							or {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85}
						self.object:set_properties({
							collisionbox = {-0.20, -0.20, -0.20, 0.20, 0.20, 0.20},
							selectionbox = climb_selbox,
						})
					end

					local climb_speed = speed * 0.85
					self.object:set_velocity({
						x = -wn.x * 0.25,
						y = climb_speed,
						z = -wn.z * 0.25,
					})

					local up_rot = dir_to_surface_rotation({x = 0, y = 1, z = 0}, wn)
					local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
					local max_rot_step = (self.max_angular_speed or 4.0) * dtime
					local smoothed_rot = interpolate_rotation(cur_rot, up_rot, math.min(1.0, dtime * 6.5), max_rot_step)
					self._cur_rot = smoothed_rot
					safe_set_rotation(self.object, smoothed_rot)
					return {moving = true, speed = speed, has_los = has_los}
				end
			end

			local facing_wall = false
			if not is_crawler and not on_wall_or_ceiling and (not has_los or not corridor_clear) then
				local check_x = math.floor(current_pos.x + move_vec.x * 0.85 + 0.5)
				local check_z = math.floor(current_pos.z + move_vec.z * 0.85 + 0.5)
				local foot_y = math.floor(current_pos.y + 0.5)
				local c_node = node_cache.get_node({x = check_x, y = foot_y, z = check_z})
				local c_def = core.registered_nodes[c_node.name]
				local h_node = node_cache.get_node({x = check_x, y = foot_y + 1, z = check_z})
				local h_def = core.registered_nodes[h_node.name]
				local c_openable = is_openable_door(c_node.name, self.abilities)
				local h_openable = is_openable_door(h_node.name, self.abilities)
				if c_openable then
					try_open_door_at_pos({x = check_x, y = foot_y, z = check_z}, self.abilities, self.object)
				end
				if h_openable then
					try_open_door_at_pos({x = check_x, y = foot_y + 1, z = check_z}, self.abilities, self.object)
				end
				local c_blocked = c_def and c_def.walkable and not c_openable
				local h_blocked = h_def and h_def.walkable and not h_openable
				if c_blocked or h_blocked then
					facing_wall = true
					if self.path_state and (not self.path_state.retry_delay or self.path_state.retry_delay <= 0) then
						self.path_state.timer = 999.0
					end
				end
			end

			local surf_norm = (adj_surf and adj_surf.normal) or
				((self._cur_rot and math.abs(self._cur_rot.z) > 2.0) and {x = 0, y = -1, z = 0} or {x = 0, y = 0, z = -1})
			local sep_norm = on_wall_or_ceiling and surf_norm or {x = 0, y = 1, z = 0}
			local sep = calculate_separation_force(self, current_pos, dtime, on_wall_or_ceiling, sep_norm)

			if on_wall_or_ceiling then
				local dot = move_vec.x * surf_norm.x + move_vec.y * surf_norm.y + move_vec.z * surf_norm.z
				local tan_x = move_vec.x - dot * surf_norm.x
				local tan_y = move_vec.y - dot * surf_norm.y
				local tan_z = move_vec.z - dot * surf_norm.z
				local tan_len = math.sqrt(tan_x * tan_x + tan_y * tan_y + tan_z * tan_z)
				if tan_len > 0.05 then
					tan_x = (tan_x / tan_len) * speed
					tan_y = (tan_y / tan_len) * speed
					tan_z = (tan_z / tan_len) * speed
				else
					tan_x, tan_y, tan_z = 0, 0, 0
				end

				self.object:set_velocity({
					x = tan_x - surf_norm.x * 0.22 + sep.x,
					y = tan_y - surf_norm.y * 0.22 + sep.y,
					z = tan_z - surf_norm.z * 0.22 + sep.z,
				})

				if tan_len > 0.05 then
					local move_dir = {x = tan_x, y = tan_y, z = tan_z}
					local target_rot = dir_to_surface_rotation(move_dir, surf_norm)
					local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
					local max_rot_step = (self.max_angular_speed or 4.0) * dtime
					local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 6.5), max_rot_step)
					self._cur_rot = smoothed_rot
					safe_set_rotation(self.object, smoothed_rot)
				end
			elseif self.is_floating then
				safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
				local y_vel = calculate_floating_combat_elevation(self, current_pos, target_pos)
				self.object:set_velocity({
					x = move_vec.x * speed + sep.x,
					y = y_vel,
					z = move_vec.z * speed + sep.z,
				})
			else
				local in_liquid, is_subm, _, target_vy = check_in_liquid(
					current_pos, self.abilities, self.mob_height
				)
				local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
				local y_vel = vel.y

				if in_liquid then
					y_vel = calculate_liquid_vertical_velocity(self, current_pos.y, target_pos.y, is_subm, target_vy)
					speed = speed * 0.75
				else
					safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
				end

				if speed <= 0.01 then
					self.object:set_velocity({x = sep.x, y = y_vel, z = sep.z})
					local face_dir = (has_los) and
						{x = target_pos.x - current_pos.x, y = 0, z = target_pos.z - current_pos.z} or move_vec
					if math.abs(face_dir.x) > 0.01 or math.abs(face_dir.z) > 0.01 then
						local target_yaw = core.dir_to_yaw(face_dir)
						local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
						local target_rot = {x = 0, y = target_yaw, z = 0}
						local max_rot_step = (math.min(self.max_angular_speed or 4.0, 3.0)) * dtime
						local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 5.0), max_rot_step)
						self._cur_rot = smoothed_rot
						safe_set_rotation(self.object, smoothed_rot)
					end
					return {moving = false, speed = 0, has_los = has_los}
				end

				local is_wall_hit, p_wall_norm = has_wall_collision(self, current_pos, dtime)
				local can_step_fwd = not facing_wall and not is_wall_hit and is_step_safe(current_pos, move_vec, self.abilities)

				if self._contour_timer and self._contour_timer > 0 and self._contour_dir and
				   is_step_safe(current_pos, self._contour_dir, self.abilities) then
					self._contour_timer = self._contour_timer - dtime
					self.object:set_velocity({
						x = self._contour_dir.x * (speed * 0.8) + sep.x,
						y = y_vel,
						z = self._contour_dir.z * (speed * 0.8) + sep.z,
					})
					move_vec = self._contour_dir
				elseif can_step_fwd then
					self._contour_timer = nil
					self._contour_dir = nil
					self.object:set_velocity({
						x = move_vec.x * speed + sep.x,
						y = y_vel,
						z = move_vec.z * speed + sep.z,
					})
				elseif (self._unreachable_fails or 0) > 0 then
					-- Pathfinder already reported no path:
					-- Hold position and calmly face target instead of spinning sideways/backwards
					self._contour_timer = nil
					self._contour_dir = nil
					self.object:set_velocity({x = sep.x, y = y_vel, z = sep.z})
					local to_target = (has_los) and
						{x = target_pos.x - current_pos.x, y = 0, z = target_pos.z - current_pos.z} or move_vec
					if math.abs(to_target.x) > 0.01 or math.abs(to_target.z) > 0.01 then
						local target_yaw = core.dir_to_yaw(to_target)
						local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
						local target_rot = {x = 0, y = target_yaw, z = 0}
						local max_rot_step = math.min(self.max_angular_speed or 4.0, 3.0) * dtime
						local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 5.0), max_rot_step)
						self._cur_rot = smoothed_rot
						safe_set_rotation(self.object, smoothed_rot)
					end
					return {moving = false, speed = 0, has_los = has_los}
				else
					if self.path_state and (not self.path_state.retry_delay or self.path_state.retry_delay <= 0) then
						self.path_state.timer = 999.0
					end

					local cand_dirs
					if p_wall_norm and (p_wall_norm.x ~= 0 or p_wall_norm.z ~= 0) then
						cand_dirs = {
							{x = -p_wall_norm.z, y = 0, z = p_wall_norm.x},
							{x = p_wall_norm.z, y = 0, z = -p_wall_norm.x},
						}
					else
						local left_dir = {x = -move_vec.z, y = 0, z = move_vec.x}
						local right_dir = {x = move_vec.z, y = 0, z = -move_vec.x}

						local left_score = mob_memory.evaluate_heading_bias(self, left_dir, current_pos)
						local right_score = mob_memory.evaluate_heading_bias(self, right_dir, current_pos)

						if self._flank_slot == 2 then
							left_score = left_score + 1.2
						elseif self._flank_slot == 3 then
							right_score = right_score + 1.2
						end

						cand_dirs = (left_score >= right_score) and {left_dir, right_dir} or {right_dir, left_dir}
					end

					local chosen_lateral = nil
					for c_i = 1, #cand_dirs do
						local cd = cand_dirs[c_i]
						if is_step_safe(current_pos, cd, self.abilities) then
							chosen_lateral = cd
							break
						end
					end

					if chosen_lateral then
						self._contour_dir = chosen_lateral
						self._contour_timer = 0.8
						self.object:set_velocity({
							x = chosen_lateral.x * (speed * 0.75) + sep.x,
							y = y_vel,
							z = chosen_lateral.z * (speed * 0.75) + sep.z,
						})
						move_vec = chosen_lateral
					else
						local back_dir = {x = -move_vec.x, y = 0, z = -move_vec.z}
						if is_step_safe(current_pos, back_dir, self.abilities) then
							self._contour_dir = back_dir
							self._contour_timer = 0.5
							self.object:set_velocity({
								x = back_dir.x * (speed * 0.6) + sep.x,
								y = y_vel,
								z = back_dir.z * (speed * 0.6) + sep.z,
							})
							move_vec = back_dir
						else
							mob_memory.record_blocked_spot(self, current_pos, 8.0)
							self.object:set_velocity({x = 0, y = y_vel, z = 0})
							return {moving = false, speed = 0, has_los = false}
						end
					end
				end
			end

			if not on_wall_or_ceiling then
				local face_dir = move_vec
				local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
				local horiz_speed_sq = vel.x * vel.x + vel.z * vel.z
				-- When stationary or backing up, maintain gaze on the target
				if has_los and (horiz_speed_sq < 0.04 or speed <= 0.01) then
					local to_target = {x = target_pos.x - current_pos.x, y = 0, z = target_pos.z - current_pos.z}
					if math.abs(to_target.x) > 0.01 or math.abs(to_target.z) > 0.01 then
						face_dir = to_target
					end
				end

				if math.abs(face_dir.x) > 0.01 or math.abs(face_dir.z) > 0.01 then
					local target_yaw = core.dir_to_yaw(face_dir)
					local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
					local target_rot = {x = 0, y = target_yaw, z = 0}
					local max_angular = self.max_angular_speed or 4.0
					if horiz_speed_sq < 0.04 or speed <= 0.01 or (self._unreachable_fails or 0) > 0 then
						max_angular = math.min(max_angular, 3.0)
					end
					local max_rot_step = max_angular * dtime
					local lerp_factor = math.min(1.0, dtime * ((horiz_speed_sq < 0.04) and 5.0 or 6.5))
					local smoothed_rot = interpolate_rotation(cur_rot, target_rot, lerp_factor, max_rot_step)
					self._cur_rot = smoothed_rot
					safe_set_rotation(self.object, smoothed_rot)
				end
			end
			return {moving = true, speed = speed, has_los = has_los}
		end

		local in_liquid, is_subm, _, target_vy = check_in_liquid(
			current_pos, self.abilities, self.mob_height
		)
		if in_liquid then
			if is_subm then
				safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
			else
				safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			end
			self.object:set_velocity({x = 0, y = target_vy or 0, z = 0})
		elseif not self.is_floating and not on_wall_or_ceiling then
			local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
			self.object:set_velocity({x = 0, y = vel.y or 0, z = 0})
		else
			safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			self.object:set_velocity({x = 0, y = 0, z = 0})
		end
		return {moving = false, speed = 0, has_los = false}
	end
end

local cached_entity_wrapper

--- Entity Registration Helper
--- Wraps standard mob definition with optimized pathfinding motor controller
---@param name string Entity technical name (e.g. "x_mobs:smart_zombie")
---@param def MobRegistrationDef Entity definition table
function mob_ai.register_pathfinding_mob(name, def)
	if not cached_entity_wrapper then
		cached_entity_wrapper = dofile(modpath .. "/lifecycle/entity_wrapper.lua")
	end
	return cached_entity_wrapper.register_mob(name, def)
end

--- Scans for the nearest valid living player within range and direct line of sight
---@param self table Mob instance
---@param scan_radius? number Max search radius (default: self.aggro_radius or 16.0)
---@param eye_height? number Mob eye height offset (default: self.eye_offset or 1.5)
---@return ObjectRef|nil nearest_player
---@return number|nil nearest_dist
function mob_ai.scan_for_player(self, scan_radius, eye_height)
	local pos = self.object and self.object:get_pos()
	if not pos then return nil end

	local eye_pos = {x = pos.x, y = pos.y + (eye_height or self.eye_offset or 1.5), z = pos.z}
	local max_dist = scan_radius or self.aggro_radius or 16.0
	local nearest_dist = math.huge
	local nearest_player = nil

	local players = core.get_connected_players()
	for i = 1, #players do
		local p = players[i]
		if is_valid_living_player(p) then
			local unreachable = self.memory and mob_memory.is_target_unreachable(self, p)
			if not unreachable then
				local ppos = p:get_pos()
				if ppos then
					local dist = vector.distance(pos, ppos)
					local effective_max = max_dist
					if x_mob_core.has_status_effect(p, "pheromone_mark") then
						effective_max = max_dist * 2.5
					end
					if dist <= effective_max and dist < nearest_dist then
						local player_eye = {x = ppos.x, y = ppos.y + 1.5, z = ppos.z}
						if check_line_of_sight(eye_pos, player_eye) then
							nearest_dist = dist
							nearest_player = p
						end
					end
				end
			end
		end
	end

	return nearest_player, (nearest_player and nearest_dist or nil)
end

--- Updates navigation movement and dispatches walk/run or idle animation
---@param self table Mob instance
---@param dtime number Step delta time
---@param move_anim? string Movement animation (default: "walk")
---@param anim_speed? number Animation speed (default: 1.0)
---@param idle_anim? string Idle animation (default: "idle")
---@return table|nil nav Navigation state
function mob_ai.step_move_or_idle(self, dtime, move_anim, anim_speed, idle_anim)
	local nav = mob_ai.update_navigation(self, dtime)
	local m_anim = move_anim or "walk"
	local i_anim = idle_anim or "idle"
	local speed = anim_speed or 1.0

	if nav and nav.moving then
		if self.state ~= "fleeing" and self.state ~= "regrouping" then
			self.state = m_anim
		end
		x_mob_core.animator.play(self.object, m_anim, {speed = speed, loop = true})
	else
		local is_fleeing = (self.state == "fleeing") or (self.panic_timer and self.panic_timer > 0)
		if not is_fleeing and self.state ~= "regrouping" then
			self.state = i_anim
		end
		if is_fleeing and m_anim == "flee" and (not nav or nav.moving ~= false) then
			x_mob_core.animator.play(self.object, m_anim, {speed = speed, loop = true})
		else
			x_mob_core.animator.play(self.object, i_anim, {speed = 1.0, loop = true})
		end
	end
	return nav
end

--- Executes wander navigation or idle holding when no active target is present
---@param self table Mob instance
---@param dtime number Step delta time
---@param walk_anim? string Custom walk animation name (default: "walk")
---@param idle_anim? string Custom idle animation name (default: "idle")
function mob_ai.step_wander_or_idle(self, dtime, walk_anim, idle_anim)
	-- Pack follower leash check: if separated from leader, tether wander origin or trigger regroup
	if self.pack_role == "member" or (self.pack and self.pack.role == "member") then
		local coordination = x_mob_core.pack.coordination
		local _, s_pos, s_dist = coordination.check_leash(self)
		if s_pos then
			if s_dist > 8.0 then
				self.state = "regrouping"
				if coordination.step_regroup(self, dtime, walk_anim) then
					return
				end
			elseif self.wander_state then
				self.wander_state.origin = {x = s_pos.x, y = s_pos.y, z = s_pos.z}
			end
		end
	end

	return mob_ai.step_move_or_idle(self, dtime, walk_anim or "walk", 1.0, idle_anim or "idle")
end

return mob_ai
