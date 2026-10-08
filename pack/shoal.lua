--[[
	x_mob_core - Fish Schooling & Shoaling Subsystem
	Leader-Follower Anchor Steering architecture for coordinated aquatic formations,
	3D water-bound obstacle/boundary avoidance, zero-allocation steering loops,
	client-side velocity interpolation, and democratic leader succession.
]]

---@class ShoalSubsystem
local shoal = {}

local modpath = core.get_modpath("x_mob_core")
local utils = dofile(modpath .. "/core/utils.lua")
local animator = dofile(modpath .. "/animation/animator.lua")
local sound = dofile(modpath .. "/audio/sound.lua")
local squad = dofile(modpath .. "/pack/squad.lua")
local coordination = dofile(modpath .. "/pack/coordination.lua")

-- Pre-allocated module-level scratch tables for zero-allocation inner loops
local scratch_vel = {x = 0, y = 0, z = 0}
local scratch_rot = {x = 0, y = 0, z = 0}
local scratch_probe = {x = 0, y = 0, z = 0}

--- Smoothly interpolates an angle towards a target angle with maximum angular step
---@param current number Current angle in radians
---@param target number Target angle in radians
---@param max_step number Maximum angular delta in radians
---@return number next_angle
local function approach_angle(current, target, max_step)
	local diff = (target - current) % (math.pi * 2)
	if diff > math.pi then
		diff = diff - (math.pi * 2)
	end
	if diff > max_step then
		return current + max_step
	elseif diff < -max_step then
		return current - max_step
	else
		return target
	end
end

local is_water_node = utils.is_water_node
local is_navigable_water = utils.is_water_node

-- Pre-allocated horizontal probe directions for strict 2-node boundary buffer (zero allocation)
local BOUNDARY_PROBES = {
	{x = 2.2, z = 0.0, nx = 1.0, nz = 0.0},
	{x = -2.2, z = 0.0, nx = -1.0, nz = 0.0},
	{x = 0.0, z = 2.2, nx = 0.0, nz = 1.0},
	{x = 0.0, z = -2.2, nx = 0.0, nz = -1.0},
	{x = 1.55, z = 1.55, nx = 0.7071, nz = 0.7071},
	{x = 1.55, z = -1.55, nx = 0.7071, nz = -0.7071},
	{x = -1.55, z = 1.55, nx = -0.7071, nz = 0.7071},
	{x = -1.55, z = -1.55, nx = -0.7071, nz = -0.7071},
}

-- Pre-allocated horizontal probe offsets for seeking deep water when shallow
local DEEP_SEEK_PROBES = {
	{x = 4.0, z = 0.0},
	{x = -4.0, z = 0.0},
	{x = 0.0, z = 4.0},
	{x = 0.0, z = -4.0},
}


--- Checks if coordinates represent safe deep water respecting the strict 2-node buffer
--- from surface air, dry land walkable nodes, and seabed
---@param x number X coordinate
---@param y number Y coordinate
---@param z number Z coordinate
---@return boolean is_safe
local function is_safe_deep_water(x, y, z)
	-- Must be water at body level
	if not is_water_node(x, y, z) then return false end
	-- Submerged vertical clearance for body height
	if not is_water_node(x, y + 0.8, z) then return false end
	if not is_water_node(x, y - 0.8, z) then return false end
	-- Lateral clearance from shore / dry land in cardinal directions
	if not is_water_node(x + 1.2, y, z) then return false end
	if not is_water_node(x - 1.2, y, z) then return false end
	if not is_water_node(x, y, z + 1.2) then return false end
	if not is_water_node(x, y, z - 1.2) then return false end
	return true
end
local get_water_column_bounds = utils.get_water_column_bounds

--- Calculates critically damped vertical velocity toward the safe water column depth
---@param pos Vector Entity world position
---@param pad? table Collision padding table
---@return number vy
---@return boolean is_shallow
local function get_vertical_containment(pos, pad)
	local min_y, max_y, is_shallow = get_water_column_bounds(pos, pad)
	if pos.y > max_y then
		-- Above safe envelope (within 2 nodes of air): strongly descend into deep water
		return math.max(-3.5, (max_y - pos.y) * 4.0), is_shallow
	elseif pos.y < min_y then
		-- Below safe envelope: ascend away from seabed
		return math.min(2.5, (min_y - pos.y) * 3.0), is_shallow
	else
		-- In safe submerged depth: zero vertical correction force
		return 0.0, is_shallow
	end
end

--- Probes surrounding environment and calculates 3D repulsion away from air surface and dry land
--- Strictly enforces a minimum 2-node buffer from any air or non-water obstacle
---@param pos Vector Entity world position
---@param pad? table Collision padding table
---@param opt_min_y? number Optional precomputed lowest safe Y
---@param opt_max_y? number Optional precomputed highest safe Y
---@param opt_is_shallow? boolean Optional precomputed shallow flag
---@param opt_surface_y? number Optional precomputed surface water block Y
---@param opt_floor_y? number Optional precomputed seabed water block Y
---@return number push_x
---@return number push_y
---@return number push_z
---@return boolean near_boundary
local function get_boundary_repulsion(pos, pad, opt_min_y, opt_max_y, opt_is_shallow, opt_surface_y, opt_floor_y)
	local push_x, push_z = 0.0, 0.0
	local near_boundary = false

	-- 1. Strict 2-node vertical containment below air surface
	local min_y, max_y, is_shallow, surface_y, floor_y
	if opt_min_y and opt_max_y then
		min_y = opt_min_y
		max_y = opt_max_y
		is_shallow = opt_is_shallow or false
		surface_y = opt_surface_y or math.floor(max_y + 2.0)
		floor_y = opt_floor_y or math.floor(min_y - 0.5)
	else
		min_y, max_y, is_shallow, surface_y, floor_y = get_water_column_bounds(pos, pad)
	end

	local push_y = 0.0
	if pos.y > max_y then
		push_y = math.max(-3.5, (max_y - pos.y) * 4.0)
		near_boundary = true
	elseif pos.y < min_y then
		push_y = math.min(2.5, (min_y - pos.y) * 3.0)
		near_boundary = true
	end

	-- 2. Strict 2-node horizontal clearance from shore and dry land walkable nodes
	local probe_y = math.min(max_y, math.max(min_y, pos.y))

	-- Check 8 directions at radius 2.2 nodes across 3 vertical sampling layers
	for i = 1, #BOUNDARY_PROBES do
		local p = BOUNDARY_PROBES[i]
		-- Check at body level, 1 node above (surface bank/air), and 0.8 node below (seabed bank)
		local blocked = not is_water_node(pos.x + p.x, probe_y, pos.z + p.z)
			or not is_water_node(pos.x + p.x, probe_y + 1.0, pos.z + p.z)
			or not is_water_node(pos.x + p.x, probe_y - 0.8, pos.z + p.z)
		if blocked then
			-- Non-water detected within 2 nodes: repel strongly inward towards open water
			push_x = push_x - p.nx * 3.5
			push_z = push_z - p.nz * 3.5
			near_boundary = true
		end
	end

	-- Inner 1.2-node emergency shore barrier
	if not is_water_node(pos.x + 1.2, probe_y, pos.z) then
		push_x = push_x - 6.0
		near_boundary = true
	end
	if not is_water_node(pos.x - 1.2, probe_y, pos.z) then
		push_x = push_x + 6.0
		near_boundary = true
	end
	if not is_water_node(pos.x, probe_y, pos.z + 1.2) then
		push_z = push_z - 6.0
		near_boundary = true
	end
	if not is_water_node(pos.x, probe_y, pos.z - 1.2) then
		push_z = push_z + 6.0
		near_boundary = true
	end

	-- 3. If water column is shallow (< 3.5 nodes deep), repel outward towards deep open water
	if is_shallow then
		near_boundary = true
		local best_depth = surface_y - floor_y
		local deep_dx, deep_dz = 0.0, 0.0
		for c = 1, #DEEP_SEEK_PROBES do
			local cd = DEEP_SEEK_PROBES[c]
			scratch_probe.x = pos.x + cd.x
			scratch_probe.y = pos.y
			scratch_probe.z = pos.z + cd.z
			local _, _, _, c_surf, c_flr = get_water_column_bounds(scratch_probe, pad)
			local d = c_surf - c_flr
			if d > best_depth then
				best_depth = d
				deep_dx = cd.x
				deep_dz = cd.z
			end
		end
		if deep_dx ~= 0.0 or deep_dz ~= 0.0 then
			push_x = push_x + deep_dx
			push_z = push_z + deep_dz
		end
	end

	return push_x, push_y, push_z, near_boundary
end

shoal.is_water_node = is_water_node
shoal.is_navigable_water = is_navigable_water
shoal.is_safe_deep_water = is_safe_deep_water
shoal.get_boundary_repulsion = get_boundary_repulsion
shoal.get_vertical_containment = get_vertical_containment
shoal.get_water_column_bounds = get_water_column_bounds

--- Derives horizontal collision radius, diameter, height, and safe distance padding from entity collisionbox
---@param self table Mob instance
---@param def table Mob definition table
---@return table pad Collision padding parameters
function shoal.get_collision_padding(self, def)
	if self._shoal_pad then
		return self._shoal_pad
	end

	local cbox = self.collisionbox
		or (self.initial_properties and self.initial_properties.collisionbox)
		or (def and def.initial_properties and def.initial_properties.collisionbox)
		or {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5}

	local rx = math.max(math.abs(cbox[1] or -0.5), math.abs(cbox[4] or 0.5))
	local rz = math.max(math.abs(cbox[3] or -0.5), math.abs(cbox[6] or 0.5))
	local radius_h = math.max(rx, rz)
	local diameter_h = radius_h * 2
	local height = math.abs((cbox[5] or 0.5) - (cbox[2] or -0.5))

	local cfg = def and def.shoal or {}
	local extra_padding = cfg.separation_padding or 0.5
	local repulsion_radius = cfg.repulsion_radius or (diameter_h + extra_padding)

	local pad = {
		radius_h = radius_h,
		diameter_h = diameter_h,
		height = height,
		repulsion_radius = repulsion_radius,
		extra_padding = extra_padding,
	}
	self._shoal_pad = pad
	return pad
end

--- Initializes an entity's shoal role, index, and state on activation
---@param self table Mob instance
---@param def table Mob definition table
---@param data table Deserialized static data table
function shoal.init_entity(self, def, data)
	local cfg = def.shoal
	if not cfg then return end

	self.saved_data = data or {}

	if self.saved_data.is_follower then
		self.pack_role = "member"
		self.pack_id = self.saved_data.pack_id
		self.follower_index = self.saved_data.follower_index or 1
	else
		self.pack_role = "leader"
		self.pack_id = self.saved_data.pack_id or utils.generate_uuid()
		self.follower_index = 0
		self.pack_followers = {}
		self.pack_max_followers = (cfg.size or 6) - 1
		if not self.saved_data.cluster_spawned then
			self.saved_data.cluster_spawned = true
			self._needs_cluster_spawning = true
		end
	end

	self.saved_data.follower_index = self.follower_index

	-- Stagger initial attack cooldowns across school members
	local stagger = (self.follower_index or 0) * 0.6
	self.attack_cooldown = 1.0 + stagger + math.random() * 0.4

	-- Internal timer registers
	self._shoal_timer = math.random() * 10.0
	self._wander_mode = "swim"
	self._wander_wait = 6.0 + math.random() * 6.0
	self._wander_heading_y = 0.0
	self._wander_target_yaw = self.object and self.object:get_yaw() or 0.0

	-- Initialize neutral aquatic buoyancy (zero gravity acceleration inside water)
	if self.object and self.object:is_valid() then
		self.object:set_acceleration({x = 0, y = 0, z = 0})
		self._has_zero_accel = true
	end
end





--- Advances ambient swimming locomotion and lookahead boundary avoidance for the school leader
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@param pos Vector Current world position
---@return boolean is_handled
function shoal.step_leader(self, dtime, def, pos)
	local current_yaw = self.object:get_yaw() or 0.0

	-- Periodically prune dead/unloaded followers from leader roster
	self._clean_timer = (self._clean_timer or 0) - dtime
	if self._clean_timer <= 0 then
		self._clean_timer = 1.0
		squad.clean_followers(self)
	end

	-- Ambient wandering locomotion: continuous cruising (no standing idle)
	self._wander_wait = (self._wander_wait or 2.0) - dtime
	if self._wander_wait <= 0 then
		self._wander_mode = "swim"
		self._wander_wait = 8.0 + math.random() * 8.0
		self._wander_target_yaw = current_yaw + (math.random() - 0.5) * 1.0
		self._wander_heading_y = (math.random() - 0.5) * 0.10
	end

	-- Forward lookahead feeler (3.5 nodes ahead at submerged body level)
	local fwd_x = -math.sin(current_yaw)
	local fwd_z = math.cos(current_yaw)
	local probe_dist = 3.5
	local ahead_x = pos.x + fwd_x * probe_dist
	local ahead_z = pos.z + fwd_z * probe_dist

	-- Apply strict 2-node boundary containment (air surface and dry land barrier)
	local pad = shoal.get_collision_padding(self, def)
	local min_y, max_y, is_shallow, surface_y, floor_y = get_water_column_bounds(pos, pad)
	local b_x, b_y, b_z, near_bound = get_boundary_repulsion(pos, pad, min_y, max_y, is_shallow, surface_y, floor_y)
	local vy = self._wander_heading_y or 0.0

	local probe_y = math.min(max_y, math.max(min_y, pos.y))
	local ahead_is_safe = is_safe_deep_water(ahead_x, probe_y, ahead_z)

	if pos.y >= max_y and vy > 0 then
		vy = 0.0
		self._wander_heading_y = -0.10
	elseif pos.y <= min_y and vy < 0 then
		vy = 0.0
		self._wander_heading_y = 0.10
	end

	if near_bound then
		if b_x ~= 0 or b_z ~= 0 then
			scratch_probe.x = b_x
			scratch_probe.y = 0.0
			scratch_probe.z = b_z
			self._wander_target_yaw = core.dir_to_yaw(scratch_probe)
			self._wander_wait = 4.0
		end
		if b_y < 0 then
			vy = math.min(vy, b_y)
			self._wander_heading_y = -0.15
		elseif b_y > 0 then
			vy = math.max(vy, b_y)
			self._wander_heading_y = 0.15
		end
	end

	-- Lateral avoidance if ahead is blocked by shore, shallow water, or surface air
	if not ahead_is_safe then
		local right_yaw = current_yaw + (math.pi * 0.40)
		local left_yaw = current_yaw - (math.pi * 0.40)

		local right_clear = is_safe_deep_water(
			pos.x - math.sin(right_yaw) * 3.5, probe_y, pos.z + math.cos(right_yaw) * 3.5
		)
		local left_clear = is_safe_deep_water(
			pos.x - math.sin(left_yaw) * 3.5, probe_y, pos.z + math.cos(left_yaw) * 3.5
		)

		if right_clear and not left_clear then
			self._wander_target_yaw = right_yaw
		elseif left_clear and not right_clear then
			self._wander_target_yaw = left_yaw
		elseif right_clear and left_clear then
			self._wander_target_yaw = (math.random() > 0.5) and right_yaw or left_yaw
		else
			-- Both sides blocked: reverse 180 degrees
			self._wander_target_yaw = current_yaw + math.pi
		end
		self._wander_wait = 4.0
	end

	-- Cruising swimming locomotion: smooth yaw navigation
	local angular_speed = 2.4 * dtime
	local next_yaw = approach_angle(current_yaw, self._wander_target_yaw, angular_speed)
	self.object:set_yaw(next_yaw)

	-- Pacing regulation: check if any follower is trailing too far behind
	local speed = self.wander_speed or 2.6
	if self.pack_followers and #self.pack_followers > 0 then
		local max_fol_dist = 0
		for f = 1, #self.pack_followers do
			local f_obj = self.pack_followers[f]
			if f_obj and f_obj:is_valid() then
				local fent = f_obj:get_luaentity()
				if fent and (not fent.leader_obj or fent.leader_obj == self.object) then
					local fp = f_obj:get_pos()
					if fp then
						local fd = vector.distance(pos, fp)
						if fd <= 28.0 and fd > max_fol_dist then
							max_fol_dist = fd
						end
					end
				end
			end
		end
		if max_fol_dist > 18.0 then
			speed = speed * 0.40 -- allow trailing followers to catch up without complete paralysis
		elseif max_fol_dist > 12.0 then
			speed = speed * 0.60
		elseif max_fol_dist > 8.0 then
			speed = speed * 0.80
		end
	end

	local move_x = -math.sin(next_yaw) * speed
	local move_z = math.cos(next_yaw) * speed

	-- Keep pitch strictly level (0.0) for natural aquatic presentation
	scratch_rot.x = 0.0
	scratch_rot.y = next_yaw
	scratch_rot.z = 0.0
	self.object:set_rotation(scratch_rot)
	self._cur_rot = scratch_rot

	-- Separation from peers (ignoring followers trailing behind leader)
	local cfg = def and def.shoal or {}
	local rep_rad = cfg.repulsion_radius or pad.repulsion_radius or 1.8
	local rep_str = cfg.repulsion_strength or 2.0
	local rep_min = cfg.min_sep or 1.2
	local sep_x, sep_y, sep_z = coordination.calculate_repulsion(
		self, pos, rep_rad, rep_str, true, rep_min, 0.05, false
	)

	scratch_vel.x = move_x + sep_x + b_x
	scratch_vel.y = vy + sep_y + b_y
	scratch_vel.z = move_z + sep_z + b_z

	-- Hard boundary safety clamp against entering non-water nodes
	if not is_water_node(pos.x + scratch_vel.x * 0.4, probe_y, pos.z + scratch_vel.z * 0.4) then
		if b_x ~= 0 or b_z ~= 0 then
			scratch_vel.x = b_x
			scratch_vel.z = b_z
		else
			local old_vx = scratch_vel.x
			scratch_vel.x = -scratch_vel.z * 0.7
			scratch_vel.z = old_vx * 0.7
		end
		self._wander_target_yaw = (self._wander_target_yaw or current_yaw) + 1.2
	end
	if pos.y > max_y then
		scratch_vel.y = math.min(-1.5, b_y)
	elseif pos.y < min_y then
		scratch_vel.y = math.max(1.0, b_y)
	elseif pos.y + scratch_vel.y * 0.35 > max_y and scratch_vel.y > 0 then
		scratch_vel.y = math.max(-0.8, b_y)
	elseif pos.y + scratch_vel.y * 0.35 < min_y and scratch_vel.y < 0 then
		scratch_vel.y = math.min(0.8, b_y)
	end

	self.object:set_velocity(scratch_vel)

	-- Publish active cruise velocity and yaw for school followers to inherit in lockstep
	self._cruise_vx = scratch_vel.x
	self._cruise_vy = scratch_vel.y
	self._cruise_vz = scratch_vel.z
	self._cruise_yaw = next_yaw

	self.state = "walk"
	animator.play(self.object, "walk", {speed = 1.0, loop = true})
	return true
end

--- Advances formation slot anchor steering and client velocity interpolation for school followers
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@param pos Vector Current world position
---@return boolean is_handled
function shoal.step_follower(self, dtime, def, pos)
	local leader = self.leader_obj

	-- Validate active leader
	if not leader or not leader:is_valid() then
		if not squad.relink_follower(self, 64.0) then
			-- Orphaned fallback: gently cruise while seeking a school with boundary containment and peer dispersion
			local current_yaw = self.object:get_yaw() or 0.0
			local smooth_yaw = approach_angle(current_yaw, current_yaw + 0.02, 1.2 * dtime)
			scratch_rot.x = 0.0
			scratch_rot.y = smooth_yaw
			scratch_rot.z = 0.0
			self.object:set_rotation(scratch_rot)
			self._cur_rot = scratch_rot

			local pad = shoal.get_collision_padding(self, def)
			local min_y, max_y, is_shallow, surface_y, floor_y = get_water_column_bounds(pos, pad)
			local b_x, b_y, b_z = get_boundary_repulsion(pos, pad, min_y, max_y, is_shallow, surface_y, floor_y)
			local sep_x, sep_y, sep_z = coordination.calculate_repulsion(
				self, pos, 3.0, 2.5, false, 1.5, 0.05, false
			)

			local ovx = -math.sin(smooth_yaw) * 1.5 + b_x + sep_x
			local ovy = b_y + sep_y
			local ovz = math.cos(smooth_yaw) * 1.5 + b_z + sep_z

			if pos.y > max_y then
				ovy = math.min(-1.5, b_y)
			elseif pos.y < min_y then
				ovy = math.max(1.0, b_y)
			end

			scratch_vel.x = ovx
			scratch_vel.y = ovy
			scratch_vel.z = ovz
			self.object:set_velocity(scratch_vel)

			self.state = "walk"
			animator.play(self.object, "walk", {speed = 0.8, loop = true})
			return true
		end
		leader = self.leader_obj
	end

	local lpos = leader:get_pos()
	local lent = leader:get_luaentity()
	if not lpos or not lent or lent.is_dead then
		self.leader_obj = nil
		return true
	end

	local leader_yaw = lent._cruise_yaw or leader:get_yaw() or 0.0
	local current_yaw = self.object:get_yaw() or leader_yaw
	local idx = self.follower_index or 1

	local pad = shoal.get_collision_padding(self, def)
	local min_y, max_y, is_shallow, surface_y, floor_y = get_water_column_bounds(pos, pad)

	-- Hydrodynamic V-Wedge Formation with Breathing Space around leader
	-- Follower slots dynamically scale with cfg.spacing_x and cfg.spacing_z
	local cfg = def and def.shoal or {}
	local sx = cfg.spacing_x or 2.2
	local sz = cfg.spacing_z or 1.8
	local sy = cfg.spacing_y or 0.6

	local ox, oz
	if idx == 1 then
		ox = -sx
		oz = -sz
	elseif idx == 2 then
		ox = sx
		oz = -sz
	elseif idx == 3 then
		ox = -sx * 1.625
		oz = -sz * 2.0833
	elseif idx == 4 then
		ox = sx * 1.625
		oz = -sz * 2.0833
	elseif idx == 5 then
		ox = 0.0
		oz = -sz * 2.5
	else
		local side = (idx % 2 == 1) and -1 or 1
		local row = math.ceil(idx / 2)
		ox = side * (sx * (1.0 + (row - 1) * 0.625))
		oz = - (sz * (1.0 + (row - 1) * 1.0833))
	end

	-- Subtle organic swimming sway in horizontal plane only (zero vertical oscillation)
	local sway = math.sin((self._shoal_timer or 0) * 1.5 + idx * 1.2) * 0.10
	ox = ox + sway

	-- Gentle micro-bobbing in vertical slot (max 4cm) + subtle depth tiering
	local vertical_tier = (idx % 2 == 1 and 0.06 or -0.06) * math.min(1.0, sy / 0.5)
	local oy = math.sin((self._shoal_timer or 0) * 1.2 + idx * 0.8) * 0.04 + vertical_tier

	-- Project local slot into world space rotated by leader yaw:
	local cos_yaw = math.cos(leader_yaw)
	local sin_yaw = math.sin(leader_yaw)
	local target_x = lpos.x + (ox * cos_yaw - oz * sin_yaw)
	local target_z = lpos.z + (ox * sin_yaw + oz * cos_yaw)
	local target_y = math.max(min_y, math.min(max_y, lpos.y + oy))

	-- Proportional anchor steering vector to assigned slot
	local dx = target_x - pos.x
	local dy = target_y - pos.y
	local dz = target_z - pos.z
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

	local l_vx = lent._cruise_vx or (-math.sin(leader_yaw) * (self.wander_speed or 2.6))
	local l_vy = lent._cruise_vy or 0.0
	local l_vz = lent._cruise_vz or (math.cos(leader_yaw) * (self.wander_speed or 2.6))

	local vx, vy, vz

	local catchup_thresh = math.max(6.0, sz * 3.2)
	if dist > catchup_thresh then
		-- Far from designated slot: sprint directly toward assigned slot (catch-up mode)
		local boost = math.min(2.2, 1.0 + (dist - catchup_thresh) * 0.25)
		local catchup_speed = (self.pursuit_speed or 5.6) * boost
		vx = (dx / dist) * catchup_speed
		vy = math.min(2.5, math.max(-2.5, (dy / dist) * catchup_speed))
		vz = (dz / dist) * catchup_speed
	else
		-- Cruising with school: inherit leader cruise velocity + proportional spring correction to slot
		-- Followers NEVER zero their velocity when close to slot; they swim in lockstep!
		local corr_speed = math.min(dist * 1.6, 2.4)
		local corr_x = (dist > 0.05) and (dx / dist) * corr_speed or 0.0
		local corr_y = (dist > 0.05) and (dy / dist) * corr_speed or 0.0
		local corr_z = (dist > 0.05) and (dz / dist) * corr_speed or 0.0

		vx = l_vx + corr_x
		vy = l_vy + corr_y
		vz = l_vz + corr_z
	end

	-- Apply 2-node boundary containment (air surface and dry land barrier)
	local b_x, b_y, b_z = get_boundary_repulsion(pos, pad, min_y, max_y, is_shallow, surface_y, floor_y)
	local probe_y = math.min(max_y, math.max(min_y, pos.y))
	vx = vx + b_x
	vy = vy + b_y
	vz = vz + b_z

	-- Hard boundary safety clamp against entering non-water nodes
	if not is_water_node(pos.x + vx * 0.4, probe_y, pos.z + vz * 0.4) then
		if b_x ~= 0 or b_z ~= 0 then
			vx = b_x
			vz = b_z
		else
			local old_vx = vx
			vx = -vz * 0.7
			vz = old_vx * 0.7
		end
	end
	if pos.y > max_y then
		vy = math.min(-1.5, b_y)
	elseif pos.y < min_y then
		vy = math.max(1.0, b_y)
	elseif pos.y + vy * 0.35 > max_y and vy > 0 then
		vy = math.max(-0.8, b_y)
	elseif pos.y + vy * 0.35 < min_y and vy < 0 then
		vy = math.min(0.8, b_y)
	end

	-- Peer separation (radius 1.8m, min_sep 1.2m so slots never fight repulsion)
	local rep_rad = cfg.repulsion_radius or pad.repulsion_radius or 1.8
	local rep_str = cfg.repulsion_strength or 2.0
	local rep_min = cfg.min_sep or 1.2
	local sep_x, sep_y, sep_z = coordination.calculate_repulsion(
		self, pos, rep_rad, rep_str, false, rep_min, 0.05, false
	)

	scratch_vel.x = vx + sep_x
	scratch_vel.y = vy + sep_y
	scratch_vel.z = vz + sep_z
	self.object:set_velocity(scratch_vel)

	-- Smooth rotation & slight yaw movements aligned with movement vector
	local h_vel = math.sqrt(scratch_vel.x * scratch_vel.x + scratch_vel.z * scratch_vel.z)
	local smooth_yaw
	if h_vel > 0.2 then
		scratch_probe.x = scratch_vel.x
		scratch_probe.y = 0.0
		scratch_probe.z = scratch_vel.z
		local f_yaw = core.dir_to_yaw(scratch_probe)
		smooth_yaw = approach_angle(current_yaw, f_yaw, 3.2 * dtime)
	else
		smooth_yaw = approach_angle(current_yaw, leader_yaw, 2.0 * dtime)
	end

	-- Keep pitch level (0.0) for natural fish appearance
	scratch_rot.x = 0.0
	scratch_rot.y = smooth_yaw
	scratch_rot.z = 0.0
	self.object:set_rotation(scratch_rot)
	self._cur_rot = scratch_rot

	-- Continuous swimming animation: followers swim fluidly alongside leader
	self.state = "walk"
	animator.play(self.object, "walk", {speed = 1.0, loop = true})

	return true
end

--- Executes predatory school strike with animation, rostrum damage, and recoil
---@param self table Mob instance
---@param target ObjectRef Target entity
---@param dir Vector Strike direction
---@param _def table Mob definition table
function shoal.perform_attack(self, target, dir, def)
	self.state = "attacking"
	self.action_timer = 0.45
	self.attack_cooldown = 2.2 + math.random() * 1.5

	animator.play(self.object, "attack", {speed = 1.5, loop = false})
	sound.play(self, "attack")

	local atk_dir = dir or {x = 0, y = 0, z = 1}
	local lunge_speed = (self.pursuit_speed or 5.2) * 1.2

	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if pos then
		local _, max_y = get_water_column_bounds(pos)
		local probe_y = math.min(max_y, pos.y)

		-- Prevent lunging upward into the 2-node air boundary envelope
		if (pos.y + atk_dir.y * 1.5 > max_y or not is_water_node(pos.x, pos.y + 2.0, pos.z)) and atk_dir.y > 0 then
			atk_dir.y = 0.0
		end
		-- Prevent lunging horizontally onto dry land / shore
		local lunge_check_x = pos.x + atk_dir.x * 2.2
		local lunge_check_z = pos.z + atk_dir.z * 2.2
		if not is_safe_deep_water(lunge_check_x, probe_y, lunge_check_z) then
			lunge_speed = 0.0
		end
	end

	scratch_vel.x = atk_dir.x * lunge_speed
	scratch_vel.y = atk_dir.y * lunge_speed
	scratch_vel.z = atk_dir.z * lunge_speed
	self.object:set_velocity(scratch_vel)

	local atk_range = self.attack_range or 2.2
	local atk_dmg = self.damage or 4
	local recoil_vx = -atk_dir.x * 2.0
	local recoil_vz = -atk_dir.z * 2.0

	x_mob_core.schedule(self, 0.22, "scheduled_action", function()
		if target and target:is_valid() then
			local cp = self.object and self.object:is_valid() and self.object:get_pos()
			local tp = target:get_pos()
			if cp and tp and vector.distance(cp, tp) <= atk_range + 0.8 then
				target:punch(self.object, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = { fleshy = atk_dmg },
				}, atk_dir)

				if def and def.shoal and def.shoal.on_strike then
					def.shoal.on_strike(self, target, atk_dir)
				elseif def and def.on_strike then
					def.on_strike(self, target, atk_dir)
				end

				-- Recoil after slash (never pop upward into surface air)
				local recoil_y = 0.0
				local _, cur_max_y = get_water_column_bounds(cp)
				if cp.y >= cur_max_y then
					recoil_y = -0.8
				end
				scratch_vel.x = recoil_vx
				scratch_vel.y = recoil_y
				scratch_vel.z = recoil_vz
				self.object:set_velocity(scratch_vel)
			end
		end
	end)
end

--- Disengages an entire school or member from combat back to peaceful swimming
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@param pos Vector Current world position
---@return boolean is_handled
local function disengage_shoal(self, dtime, def, pos)
	self.target = nil
	self.state = "walk"
	if self.pack_role == "leader" then
		local followers = self.pack_followers
		if followers then
			for i = 1, #followers do
				local f_obj = followers[i]
				if f_obj and f_obj:is_valid() then
					local f_ent = f_obj:get_luaentity()
					if f_ent and not f_ent.is_dead then
						f_ent.target = nil
						f_ent.state = "walk"
					end
				end
			end
		end
		return shoal.step_leader(self, dtime, def, pos)
	else
		return shoal.step_follower(self, dtime, def, pos)
	end
end

--- Advances coordinated combat locomotion when school has engaged a threat
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@param pos Vector Current world position
---@return boolean is_handled
function shoal.step_combat(self, dtime, def, pos)
	local target = self.target
	if not target or not target:is_valid() or not utils.is_player_alive(target) then
		return disengage_shoal(self, dtime, def, pos)
	end

	local tpos = target:get_pos()
	if not tpos then
		return disengage_shoal(self, dtime, def, pos)
	end

	local dist = vector.distance(pos, tpos)
	local max_chase_dist = (self.aggro_radius or def.aggro_radius or 16.0) * 1.5
	if dist > max_chase_dist then
		-- Keep target only if member's leader is actively engaged within chase distance
		if self.pack_role == "member" and self.leader_obj and self.leader_obj:is_valid() then
			local lent = self.leader_obj:get_luaentity()
			if not (lent and lent.target and utils.is_player_alive(lent.target)) then
				return disengage_shoal(self, dtime, def, pos)
			end
		else
			return disengage_shoal(self, dtime, def, pos)
		end
	end

	-- Check if target is in water or standing on dry land / air
	local target_in_water = is_water_node(tpos.x, tpos.y, tpos.z)
		or is_water_node(tpos.x, tpos.y - 0.5, tpos.z)

	local pad = shoal.get_collision_padding(self, def)
	local min_y, max_y, is_shallow, surface_y, floor_y = get_water_column_bounds(pos, pad)
	local atk_range = self.attack_range or 2.2

	local lead_obj = self.leader_obj
	local lead_pos = (lead_obj and lead_obj:is_valid() and lead_obj:get_pos()) or pos
	scratch_probe.x = tpos.x - lead_pos.x
	scratch_probe.y = tpos.y - lead_pos.y
	scratch_probe.z = tpos.z - lead_pos.z
	local attack_yaw = core.dir_to_yaw(scratch_probe)

	local dir_x, dir_y, dir_z
	local pursuit_speed = self.pursuit_speed or 5.2
	local is_striking = (self.pack_role == "leader")
		or ((self.attack_cooldown or 0) <= 0)
		or (dist <= atk_range)

	if is_striking then
		-- Active strike charge directly towards target (clamped strictly to safe water column)
		local strike_y = math.max(min_y, math.min(max_y, tpos.y))
		local ddx = tpos.x - pos.x
		local ddy = strike_y - pos.y
		local ddz = tpos.z - pos.z
		local dlen = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
		if dlen > 0.0001 then
			dir_x = ddx / dlen
			dir_y = ddy / dlen
			dir_z = ddz / dlen
		else
			dir_x, dir_y, dir_z = 0.0, 0.0, 1.0
		end
		if self.pack_role == "member" and dist > atk_range then
			pursuit_speed = pursuit_speed * 1.15
		end
	else
		-- Followers hold dynamic tactical encirclement slots to prevent clustering in a ball
		local idx = self.follower_index or 1
		local flank_angle
		local flank_radius = pad.diameter_h + 1.5 -- ~3.2m
		if idx == 1 then
			flank_angle = attack_yaw - 0.75
		elseif idx == 2 then
			flank_angle = attack_yaw + 0.75
		elseif idx == 3 then
			flank_angle = attack_yaw - 1.50
			flank_radius = flank_radius + 0.8
		elseif idx == 4 then
			flank_angle = attack_yaw + 1.50
			flank_radius = flank_radius + 0.8
		else
			flank_angle = attack_yaw + math.pi
			flank_radius = flank_radius + 1.2
		end

		local slot_x = tpos.x - math.sin(flank_angle) * flank_radius
		local slot_z = tpos.z + math.cos(flank_angle) * flank_radius
		local slot_y = math.max(min_y, math.min(max_y, tpos.y))

		local ddx = slot_x - pos.x
		local ddy = slot_y - pos.y
		local ddz = slot_z - pos.z
		local dist_to_slot = math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
		if dist_to_slot > 0.0001 then
			dir_x = ddx / dist_to_slot
			dir_y = ddy / dist_to_slot
			dir_z = ddz / dist_to_slot
		else
			dir_x, dir_y, dir_z = 0.0, 0.0, 1.0
		end
		if dist_to_slot < 0.4 then
			pursuit_speed = 0.5 -- hover in flanking stance
		end
	end

	-- Check 2-node boundary containment (air surface and dry land barrier)
	local b_x, b_y, b_z, near_bound = get_boundary_repulsion(pos, pad, min_y, max_y, is_shallow, surface_y, floor_y)

	-- Follower catch-up acceleration during combat pursuit to prevent falling behind
	if self.pack_role == "member" and self.leader_obj and self.leader_obj:is_valid() then
		local lp = self.leader_obj:get_pos()
		if lp then
			local dist_lead = vector.distance(pos, lp)
			if dist_lead > 4.5 then
				-- Blend pursuit vector toward leader with speed boost
				local ldx = lp.x - pos.x
				local ldy = lp.y - pos.y
				local ldz = lp.z - pos.z
				local ld_len = math.sqrt(ldx * ldx + ldy * ldy + ldz * ldz)
				if ld_len > 0.0001 then
					local to_lead_x = ldx / ld_len
					local to_lead_y = ldy / ld_len
					local to_lead_z = ldz / ld_len
					local blend = math.min(0.60, (dist_lead - 4.5) * 0.15)
					local inv_blend = 1.0 - blend
					dir_x = dir_x * inv_blend + to_lead_x * blend
					dir_y = dir_y * inv_blend + to_lead_y * blend
					dir_z = dir_z * inv_blend + to_lead_z * blend
					local boost = math.min(2.0, 1.0 + (dist_lead - 4.5) * 0.25)
					pursuit_speed = pursuit_speed * boost
				end
			end
		end
	end

	scratch_probe.x = dir_x
	scratch_probe.y = 0.0
	scratch_probe.z = dir_z
	local target_yaw = core.dir_to_yaw(scratch_probe)
	self.object:set_yaw(target_yaw)

	local horiz_dist = math.sqrt(dir_x * dir_x + dir_z * dir_z)
	local raw_pitch = (horiz_dist > 0.05) and -math.atan2(dir_y, horiz_dist) or 0.0
	local pitch = math.max(-0.35, math.min(0.35, raw_pitch))
	-- Prevent upward pitch if at or above water containment boundary
	if pos.y >= max_y and pitch < 0 then
		pitch = 0.0
	end
	scratch_rot.x = pitch
	scratch_rot.y = target_yaw
	scratch_rot.z = 0
	self.object:set_rotation(scratch_rot)
	self._cur_rot = scratch_rot

	-- Broadcast threat across pack mates periodically
	self._rally_timer = (self._rally_timer or 0) - dtime
	if self._rally_timer <= 0 then
		self._rally_timer = 0.8
		coordination.broadcast_threat(self, target, 24.0, 12)
	end

	if (self.attack_cooldown or 0) <= 0 and dist <= atk_range then
		shoal.perform_attack(self, target, {x = dir_x, y = dir_y, z = dir_z}, def)
		return true
	end

	local vx = dir_x * pursuit_speed
	local vy = dir_y * pursuit_speed
	local vz = dir_z * pursuit_speed

	-- If target is on dry land / air:
	-- Never swim up toward land, and patrol parallel to shore edge in deep water
	if not target_in_water then
		vy = math.min(0, vy)
		if near_bound then
			vx = -b_z * 0.7
			vz = b_x * 0.7
			vy = math.max(min_y - pos.y, math.min(0, max_y - pos.y))
		end
	end

	-- Apply boundary containment forces
	vx = vx + b_x
	vy = vy + b_y
	vz = vz + b_z

	-- Hard boundary safety clamp against entering non-water nodes
	local probe_y = math.min(max_y, math.max(min_y, pos.y))
	if not is_water_node(pos.x + vx * 0.4, probe_y, pos.z + vz * 0.4) then
		if b_x ~= 0 or b_z ~= 0 then
			vx = b_x
			vz = b_z
		else
			local old_vx = vx
			vx = -vz * 0.7
			vz = old_vx * 0.7
		end
	end
	if pos.y > max_y then
		vy = math.min(-1.5, b_y)
	elseif pos.y < min_y then
		vy = math.max(1.0, b_y)
	elseif pos.y + vy * 0.35 > max_y and vy > 0 then
		vy = math.max(-0.8, b_y)
	elseif pos.y + vy * 0.35 < min_y and vy < 0 then
		vy = math.min(0.8, b_y)
	end

	local cfg = def and def.shoal or {}
	local rep_rad = cfg.repulsion_radius or pad.repulsion_radius or 1.8
	local rep_str = cfg.repulsion_strength or 2.0
	local rep_min = cfg.min_sep or 1.2
	local sep_x, sep_y, sep_z = coordination.calculate_repulsion(
		self, pos, rep_rad, rep_str, false, rep_min, 0.05, false
	)
	scratch_vel.x = vx + sep_x
	scratch_vel.y = (pos.y > max_y) and math.min(-1.5, vy + sep_y) or (vy + sep_y)
	scratch_vel.z = vz + sep_z
	self.object:set_velocity(scratch_vel)

	self.state = "combat"
	animator.play(self.object, "run", {speed = 1.2, loop = true})
	return true
end

--- Synchronizes threat targets across the entire school to maintain cohesion
---@param self table Mob instance
function shoal.sync_school_threat(self)
	if self.pack_role == "leader" then
		if utils.is_player_alive(self.target) then
			-- Propagate leader target to all followers
			local followers = self.pack_followers
			if followers then
				for i = 1, #followers do
					local f_obj = followers[i]
					if f_obj and f_obj:is_valid() then
						local f_ent = f_obj:get_luaentity()
						if f_ent and not f_ent.is_dead then
							f_ent.target = self.target
						end
					end
				end
			end
		end
	elseif self.pack_role == "member" then
		if self.leader_obj and self.leader_obj:is_valid() then
			local lent = self.leader_obj:get_luaentity()
			if lent and utils.is_player_alive(lent.target) then
				self.target = lent.target
			elseif lent and not lent.target then
				-- Leader disengaged: follower must disengage in unison
				self.target = nil
				if self.state == "combat" then
					self.state = "walk"
				end
			end
		end
	end
end

--- Master step dispatcher for schooling entities
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean is_handled
function shoal.step(self, dtime, def)
	if self._needs_cluster_spawning then
		self._needs_cluster_spawning = false
		squad.spawn_cluster(self, def)
	end

	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return false end

	-- Gravity & aquatic buoyancy physics
	local in_water = is_water_node(pos.x, pos.y, pos.z)
	if not in_water then
		self._has_zero_accel = false
		self.object:set_acceleration({x = 0, y = -9.81, z = 0})
		if is_water_node(pos.x, pos.y - 1.0, pos.z) or is_water_node(pos.x, pos.y - 2.0, pos.z) then
			local v = self.object:get_velocity() or {x = 0, y = 0, z = 0}
			self.object:set_velocity({x = v.x * 0.5, y = math.min(-1.5, v.y), z = v.z * 0.5})
		end
	else
		if not self._has_zero_accel then
			self.object:set_acceleration({x = 0, y = 0, z = 0})
			self._has_zero_accel = true
		end
	end

	-- Active player proximity culling (hibernates school when distant)
	local cfg = def.shoal or {}
	self._cull_timer = (self._cull_timer or 0) - dtime
	if self._cull_timer <= 0 then
		self._cull_timer = 0.6
		local cull_dist_sq = (cfg.cull_distance or 64.0) ^ 2
		local players = core.get_connected_players()
		local player_near = false
		for p = 1, #players do
			local pobj = players[p]
			if pobj and pobj:is_valid() then
				local pp = pobj:get_pos()
				if pp then
					local pdx = pp.x - pos.x
					local pdy = pp.y - pos.y
					local pdz = pp.z - pos.z
					if (pdx * pdx + pdy * pdy + pdz * pdz) <= cull_dist_sq then
						player_near = true
						break
					end
				end
			end
		end
		self._is_culled = not player_near
	end

	if self._is_culled then
		if not self._culled_stopped then
			scratch_vel.x = 0
			scratch_vel.y = 0
			scratch_vel.z = 0
			self.object:set_velocity(scratch_vel)
			self._culled_stopped = true
		end
		return true
	end
	self._culled_stopped = false

	self._shoal_timer = (self._shoal_timer or 0) + dtime
	self.attack_cooldown = math.max(0, (self.attack_cooldown or 0) - dtime)

	if self.state == "attacking" then
		return true
	end

	-- Synchronize threat across school members
	shoal.sync_school_threat(self)

	-- Combat handling for predatory schools
	if cfg.predator ~= false and utils.is_player_alive(self.target) then
		return shoal.step_combat(self, dtime, def, pos)
	end

	-- Ambient schooling locomotion
	if self.pack_role == "leader" then
		return shoal.step_leader(self, dtime, def, pos)
	end

	return shoal.step_follower(self, dtime, def, pos)
end

--- Action end hook to transition attacking mobs back to swimming
---@param self table Mob instance
---@param _def table Mob definition table
function shoal.on_action_end(self, _def)
	if self.state == "attacking" then
		self.state = "walk"
		if self.object and self.object:is_valid() and not self.is_dead then
			animator.play(self.object, "walk", {speed = 1.0, loop = true})
		end
	end
end

return shoal
