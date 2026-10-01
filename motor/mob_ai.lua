--[[
	mob_ai.lua - Pursuit-Gated Mob Motor Controller & Navigation Logic
	- Tier 1: Fast-Path Line-of-Sight check bypassing A* graph search
	- Pursuit-Gated Traversal: Doors, Ladders, and Swimming unlocked ONLY during active pursuit
	- Non-locking Door Opening with Area Protection validation (leaves doors open)
	- Manual Ladder climbing physics counteracting gravity
	- Multiplayer Distance LOD: Refresh intervals scaled by player proximity
	- Production-ready entity integration and steering controller
]]

local utils = (x_mob_core and x_mob_core.utils) or
	dofile(core.get_modpath("x_mob_core") .. "/core/utils.lua")
local fast_pathfinder = (x_mob_core and x_mob_core.fast_pathfinder) or
	dofile(core.get_modpath("x_mob_core") .. "/navigation/fast_pathfinder.lua")
local mob_memory = (x_mob_core and x_mob_core.mob_memory) or
	dofile(core.get_modpath("x_mob_core") .. "/navigation/mob_memory.lua")

---@class MobAISubsystem
local mob_ai = {}
local flank_slot_counter = 0

-- -------------------------------------------------------------------------
-- TIER 0: NODE CACHING
-- -------------------------------------------------------------------------
local global_node_cache = {}
local global_node_or_nil_cache = {}

core.register_globalstep(function()
	global_node_cache = {}
	global_node_or_nil_cache = {}
end)

function mob_ai.get_node(pos)
	local hash = core.hash_node_position(pos)
	local n = global_node_cache[hash]
	if not n then
		n = core.get_node(pos)
		global_node_cache[hash] = n
	end
	return n
end

function mob_ai.get_node_or_nil(pos)
	local hash = core.hash_node_position(pos)
	local n = global_node_or_nil_cache[hash]
	if n == false then return nil end
	if not n then
		n = core.get_node_or_nil(pos)
		global_node_or_nil_cache[hash] = n or false
	end
	return n
end


-- -------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- -------------------------------------------------------------------------

local check_line_of_sight = utils.line_of_sight

--- Volumetric multi-ray corridor check to determine if a direct straight-line path is clear.
--- Checks eye-level, torso-level, and left/right lateral extents.
--- If any obstacle blocks the corridor, direct path is obstructed and A* is required.
---@param pos Vector Mob base world position
---@param target_pos Vector Target world position
---@param eye_offset number|nil Eye height offset above base pos
---@param half_width number|nil Mob collision half-width (default 0.4)
---@return boolean is_clear True if entire corridor has unobstructed line of sight
local function check_corridor_line_of_sight(pos, target_pos, eye_offset, half_width)
	-- Headroom clearance ray verifying upper space along corridor
	local head_h = math.max(1.15, (eye_offset or 1.5))
	local m_head = {x = pos.x, y = pos.y + head_h, z = pos.z}
	local t_head = {x = target_pos.x, y = target_pos.y + 1.5, z = target_pos.z}
	if not check_line_of_sight(m_head, t_head) then
		return false
	end
	local t_head_lvl = {x = target_pos.x, y = target_pos.y + head_h, z = target_pos.z}
	if not check_line_of_sight(m_head, t_head_lvl) then
		return false
	end

	-- Eye-level ray verifying line of sight
	local m_eye = {x = pos.x, y = pos.y + (eye_offset or 1.5), z = pos.z}
	local t_eye = {x = target_pos.x, y = target_pos.y + 1.5, z = target_pos.z}
	if not check_line_of_sight(m_eye, t_eye) then
		return false
	end

	-- Torso-level ray for low walls, fences, slabs, and corners
	local m_torso = {x = pos.x, y = pos.y + 0.6, z = pos.z}
	local t_torso = {x = target_pos.x, y = target_pos.y + 0.6, z = target_pos.z}
	if not check_line_of_sight(m_torso, t_torso) then
		return false
	end

	-- Lateral shoulder clearance rays for wide entities
	local hw = half_width or 0.4
	if hw >= 0.3 then
		local dx = target_pos.x - pos.x
		local dz = target_pos.z - pos.z
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist > 1.5 then
			-- Perpendicular unit vector on XZ plane
			local perp_x = -dz / dist * (hw * 0.75)
			local perp_z = dx / dist * (hw * 0.75)

			local left_start = {x = pos.x + perp_x, y = pos.y + 0.8, z = pos.z + perp_z}
			local left_end = {x = target_pos.x + perp_x, y = target_pos.y + 0.8, z = target_pos.z + perp_z}
			if not check_line_of_sight(left_start, left_end) then
				return false
			end

			local right_start = {x = pos.x - perp_x, y = pos.y + 0.8, z = pos.z - perp_z}
			local right_end = {x = target_pos.x - perp_x, y = target_pos.y + 0.8, z = target_pos.z - perp_z}
			if not check_line_of_sight(right_start, right_end) then
				return false
			end
		end
	end

	return true
end

--- Checks if a door or trapdoor is currently already open
---@param pos Vector World position of door node
---@param node table Node table {name, param1, param2}
---@param def table Registered node definition
---@return boolean is_open True if door is already open
local function is_door_open(pos, node, def)
	local check_pos = pos
	local check_node = node
	local check_def = def
	if check_node and check_node.name == "doors:hidden" then
		check_pos = {x = pos.x, y = pos.y - 1, z = pos.z}
		check_node = mob_ai.get_node(check_pos)
		check_def = core.registered_nodes[check_node.name] or {}
	end

	-- Check global doors mod API via door:state()
	local doors_mod = rawget(_G, "doors")
	if doors_mod and doors_mod.get then
		local door = doors_mod.get(check_pos)
		if door and door.state then
			local ok, s = pcall(door.state, door)
			if ok and s == true then
				return true
			end
		end
	end

	-- Non-walkable door nodes are considered open
	if check_def and check_def.walkable == false then
		return true
	end

	-- Engine door metadata state inspection
	local meta = core.get_meta(check_pos)
	if meta then
		local state_str = meta:get_string("state")
		if state_str ~= "" then
			local s = tonumber(state_str)
			if s and s % 2 == 1 then
				return true
			end
		end
	end

	-- Node naming convention checks for open doors and trapdoors
	local name = (check_node and check_node.name) or ""
	if name:sub(-2) == "_c" or name:sub(-2) == "_d" or name:sub(-5) == "_open" then
		return true
	end

	return false
end

--- Checks if a node represents an unlocked, openable door
---@param name string Node technical name
---@param abilities table|nil Mob capabilities table
---@return boolean is_openable True if node is an openable door and mob can open doors
local function is_openable_door(name, abilities)
	if not (abilities and abilities.can_open_doors) then
		return false
	end
	if not name or name == "" or name == "air" or name == "ignore" then
		return false
	end
	local is_door = (core.get_item_group(name, "door") or 0) > 0 or (name == "doors:hidden")
	if not is_door then
		return false
	end
	local is_locked = (name:find("steel") ~= nil) or
		(name:find("iron") ~= nil) or
		(name:find("locked") ~= nil)
	return not is_locked
end

--- Opens a door node if closed, ensuring already open doors are not toggled or touched
---@param pos Vector World position of door node
---@param node table Node table {name, param1, param2}
---@param def table Registered node definition
---@param _user ObjectRef|nil Entity attempting the interaction
---@return boolean success True if door is open or was successfully opened
local function try_open_door(pos, node, def, _user)
	-- Verify area protection
	if core.is_protected(pos, "") then
		return false
	end

	-- Handle hidden top segment of two-node doors
	local door_pos = pos
	local door_node = node
	local door_def = def
	if door_node and door_node.name == "doors:hidden" then
		door_pos = {x = pos.x, y = pos.y - 1, z = pos.z}
		door_node = mob_ai.get_node(door_pos)
		door_def = core.registered_nodes[door_node.name] or {}
	end

	if core.is_protected(door_pos, "") then
		return false
	end

	local node_name = (door_node and door_node.name) or ""
	-- Do not open locked or steel/iron doors
	if node_name:find("steel") or node_name:find("iron") or node_name:find("locked") then
		return false
	end

	-- If the door is already open, DO NOT touch or toggle it!
	if is_door_open(door_pos, door_node, door_def) then
		return true
	end

	-- Door is confirmed closed: open it via doors API without player clicker
	local doors_mod = rawget(_G, "doors")
	if doors_mod and doors_mod.get then
		local door = doors_mod.get(door_pos)
		if door and door.open then
			local ok = door:open(nil)
			if ok ~= false then
				return true
			end
		end
	end

	-- Fallback to door_toggle ONLY if the door is still verified closed
	if doors_mod and doors_mod.door_toggle then
		if not is_door_open(door_pos, door_node, door_def) then
			doors_mod.door_toggle(door_pos, door_node, nil)
			if is_door_open(door_pos, door_node, door_def) then
				return true
			end
		end
	end

	-- Fallback to on_rightclick ONLY if still closed
	if door_def and door_def.on_rightclick then
		if not is_door_open(door_pos, door_node, door_def) then
			door_def.on_rightclick(door_pos, door_node, nil)
			if is_door_open(door_pos, door_node, door_def) then
				return true
			end
		end
	end

	return is_door_open(door_pos, door_node, door_def)
end

--- Checks and opens an openable door node at a specific position
---@param pos Vector World position
---@param abilities table Ability flags table
---@param object ObjectRef User/mob object
---@return boolean opened
local function try_open_door_at_pos(pos, abilities, object)
	if not (abilities and abilities.can_open_doors) or not pos then return false end
	local node = mob_ai.get_node(pos)
	if is_openable_door(node.name, abilities) then
		local def = core.registered_nodes[node.name] or {}
		if not is_door_open(pos, node, def) then
			return try_open_door(pos, node, def, object)
		end
	end
	return false
end
mob_ai.try_open_door_at_pos = try_open_door_at_pos

--- Checks and proactively opens any closed doors directly ahead in movement direction
---@param pos Vector Current entity position
---@param dir Vector Direction of movement
---@param abilities table|nil Mob capabilities table
---@param object ObjectRef Entity ObjectRef
local function check_and_open_forward_doors(pos, dir, abilities, object)
	if not (abilities and abilities.can_open_doors) or not dir then return end
	if math.abs(dir.x) <= 0.01 and math.abs(dir.z) <= 0.01 then return end
	local fwd_x = math.floor(pos.x + dir.x * 1.1 + 0.5)
	local fwd_z = math.floor(pos.z + dir.z * 1.1 + 0.5)
	local fwd_y = math.floor(pos.y + 0.5)
	for dy = 0, 1 do
		try_open_door_at_pos({x = fwd_x, y = fwd_y + dy, z = fwd_z}, abilities, object)
	end
end
mob_ai.check_and_open_forward_doors = check_and_open_forward_doors

--- Checks whether a world position is a valid, standing location (not inside a wall, has ground support)
---@param pos Vector
---@return boolean is_valid True if pos is clear of walkable blocks and supported by ground
local function is_valid_stand_pos(pos)
	if not pos then return false end
	local nx = math.floor(pos.x + 0.5)
	local ny = math.floor(pos.y + 0.5)
	local nz = math.floor(pos.z + 0.5)
	local foot = mob_ai.get_node_or_nil({x = nx, y = ny, z = nz})
	local head = mob_ai.get_node_or_nil({x = nx, y = ny + 1, z = nz})
	local ground = mob_ai.get_node_or_nil({x = nx, y = ny - 1, z = nz})
	local def_f = foot and core.registered_nodes[foot.name]
	local def_h = head and core.registered_nodes[head.name]
	local def_g = ground and core.registered_nodes[ground.name]
	if (def_f and def_f.walkable) or (def_h and def_h.walkable) then
		return false
	end
	if not (def_g and def_g.walkable) then
		return false
	end
	return true
end

--- Detects if entity has collided with a wall/solid obstacle or is physically stagnant against one
---@param self table Mob entity instance
---@param current_pos Vector Current world position
---@param dtime number Delta time
---@return boolean is_colliding Whether the mob is colliding with a wall
---@return Vector|nil wall_normal Estimated normal pointing away from the wall
---@return Vector|nil node_pos Position of collided node if known
local function has_wall_collision(self, current_pos, dtime)
	-- Check engine moveresult collisions on horizontal axes
	local mr = self._moveresult or self.moveresult
	if mr and mr.collides and mr.collisions then
		for i = 1, #mr.collisions do
			local c = mr.collisions[i]
			if c.type == "node" and (c.axis == "x" or c.axis == "z") then
				if c.node_pos then
					try_open_door_at_pos(c.node_pos, self.abilities, self.object)
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

	-- Physical displacement watchdog detecting movement stagnation
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

--- Checks whether the given target is a connected, valid, living player or entity
--- Reuses canonical player vitality check from core utils
local is_valid_living_player = utils.is_player_alive

--- Determines if mob is in active pursuit of a living target
---@param self table Entity instance
---@return boolean is_pursuing
local function get_pursuit_state(self)
	return is_valid_living_player(self.target)
end

--- Safely gets object yaw in radians
---@param obj ObjectRef|nil
---@return number yaw
local function safe_get_yaw(obj)
	if obj and obj:is_valid() then
		return obj:get_yaw() or 0
	end
	return 0
end

--- Safely sets object yaw in radians
---@param obj ObjectRef|nil
---@param yaw number
local function safe_set_yaw(obj, yaw)
	if obj and obj:is_valid() then
		obj:set_yaw(yaw)
	end
end

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



--- Safely sets object acceleration
---@param obj ObjectRef|nil
---@param acc Vector
local function safe_set_acceleration(obj, acc)
	if obj and obj:is_valid() then
		obj:set_acceleration(acc)
	end
end

--- Sets object rotation (Euler radians)
---@param obj ObjectRef|nil
---@param rot Vector
local function safe_set_rotation(obj, rot)
	if obj and obj:is_valid() then
		obj:set_rotation(rot)
	end
end

--- Checks if entity is in liquid and calculates water surface and immersion level
---@param pos Vector World position
---@param abilities table|nil Mob abilities table
---@param mob_height number|nil Height of mob (default 1.5)
---@return boolean in_liquid True if in liquid and submerged or at waterline
---@return boolean is_submerged True if mob is submerged below target swimming waterline
---@return number|nil surface_y Y elevation of topmost water surface in node column
---@return number target_vy Recommended vertical velocity to reach/maintain swimming depth
local function check_in_liquid(pos, abilities, mob_height)
	if not (abilities and abilities.can_swim) or not pos then
		return false, false, nil, 0
	end

	local px = math.floor(pos.x + 0.5)
	local pz = math.floor(pos.z + 0.5)
	local py = math.floor(pos.y + 0.5)

	-- Search for highest water block in vertical column near entity
	local surface_y = nil
	for iy = py + 4, py - 2, -1 do
		local node = mob_ai.get_node_or_nil({x = px, y = iy, z = pz})
		local def = node and core.registered_nodes[node.name]
		if def and def.liquidtype and def.liquidtype ~= "none" then
			surface_y = iy + 0.5
			break
		end
	end

	if not surface_y then
		return false, false, nil, 0
	end

	-- Target swimming waterline: partially submerge mob (~48% of height in water)
	local h = mob_height or 1.5
	local target_depth = h * 0.48
	local target_y = surface_y - target_depth

	-- If feet are completely above water surface, entity is in air above water!
	if pos.y >= surface_y then
		return false, false, surface_y, 0
	end

	local in_liquid = true
	local diff = target_y - pos.y
	local is_submerged = (diff > 0.6)

	local target_vy
	if diff > 0.08 then
		-- Submerged below waterline: actively swim upwards to reach partial submersion
		target_vy = math.min(1.8, math.max(0.4, diff * 2.2))
	elseif diff < -0.08 then
		-- Above waterline but in water: settle down to target depth
		target_vy = math.max(-1.2, diff * 2.5)
	else
		-- At waterline: gentle restorative floating velocity
		target_vy = diff * 2.0
	end

	return in_liquid, is_submerged, surface_y, target_vy
end

--- Calculates vertical velocity and applies buoyancy acceleration when navigating liquids
---@param self table Mob entity instance
---@param current_y number Current mob vertical position
---@param target_y number Desired waypoint/target vertical position
---@param is_subm boolean True if submerged
---@param target_vy number Target floating velocity from check_in_liquid
---@return number y_vel Vertical velocity to assign
local function calculate_liquid_vertical_velocity(self, current_y, target_y, is_subm, target_vy)
	local dy = target_y - current_y
	if dy > 0.4 then
		safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
		return 2.0
	elseif dy < -0.6 and is_subm then
		safe_set_acceleration(self.object, {x = 0, y = -1.5, z = 0})
		return -1.2
	else
		local acc_y = is_subm and 0.5 or 0.0
		safe_set_acceleration(self.object, {x = 0, y = acc_y, z = 0})
		return target_vy or 0
	end
end

--- Applies active water buoyancy and partial submersion floating physics for swimming mobs
---@param self table Entity instance
---@param dtime number Step delta time
---@return boolean in_liquid True if mob is currently inside a liquid node
---@return boolean is_submerged True if mob is submerged below target swimming waterline
---@return number target_vy Vertical velocity to maintain or reach swimming depth
local function apply_liquid_buoyancy(self, dtime)
	if not self.object or not self.object:is_valid() then
		return false, false, 0
	end
	if self.can_swim ~= true and not (self.abilities and self.abilities.can_swim) then
		return false, false, 0
	end

	local pos = self.object:get_pos()
	if not pos then
		return false, false, 0
	end

	local in_liquid, is_submerged, _, target_vy = check_in_liquid(
		pos, self.abilities or {can_swim = true}, self.mob_height or 1.5
	)

	if not in_liquid then
		if self._in_liquid then
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
			self._in_liquid = false
			self._is_submerged = false
			self._liquid_vy = nil
		end
		return false, false, 0
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
		safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
	else
		safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
	end

	return true, is_submerged, target_vy
end

--- Halts horizontal velocity while preserving vertical motion/gravity and liquid buoyancy
---@param self table Mob entity instance
local function halt_horizontal_velocity(self)
	if not self or not self.object or not self.object:is_valid() then return end
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local y_vel = self.in_water and (self.water_vy or self._liquid_vy or 0) or math.min(0, vel.y)
	self.object:set_velocity({x = 0, y = y_vel, z = 0})
	if not self.in_water and not self.is_floating then
		safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
	end
end

--- Computes 3D Euler angles (pitch, yaw, roll in radians) matching Luanti extrinsic Z-X-Y order
---@param dir Vector Movement direction
---@param up Vector Surface normal
---@return Vector Euler rotation in radians {x = pitch, y = yaw, z = roll}
local function dir_to_surface_rotation(dir, up)
	local up_len = math.sqrt((up.x or 0) * (up.x or 0) + (up.y or 0) * (up.y or 0) + (up.z or 0) * (up.z or 0))
	local norm_up
	if up_len > 1e-4 then
		norm_up = {x = (up.x or 0) / up_len, y = (up.y or 0) / up_len, z = (up.z or 0) / up_len}
	else
		norm_up = {x = 0, y = 1, z = 0}
	end

	local pitch, yaw, roll

	if norm_up.y < -0.7 then
		-- Inverted ceiling: roll = pi
		pitch = 0.0
		yaw = (dir.x ~= 0 or dir.z ~= 0) and -core.dir_to_yaw(dir) or 0
		roll = math.pi
	elseif norm_up.y > 0.7 then
		-- Horizontal floor: pitch = 0, roll = 0
		pitch = 0.0
		yaw = (dir.x ~= 0 or dir.z ~= 0) and core.dir_to_yaw(dir) or 0
		roll = 0.0
	else
		-- Vertical wall (normal is primarily horizontal)
		local hn_len = math.sqrt(norm_up.x * norm_up.x + norm_up.z * norm_up.z)
		local nx = (hn_len > 1e-4) and (norm_up.x / hn_len) or 1
		local nz = (hn_len > 1e-4) and (norm_up.z / hn_len) or 0
		local wall_yaw = core.dir_to_yaw({x = -nx, y = 0, z = -nz})

		local vy = dir.y or 0
		if vy > 0.30 then
			-- Climbing straight UP the wall
			pitch = math.pi / 2
			yaw = wall_yaw
			roll = 0.0
		elseif vy < -0.30 then
			-- Crawling straight DOWN the wall
			pitch = -math.pi / 2
			yaw = wall_yaw
			roll = 0.0
		else
			-- Crawling horizontally along the wall
			pitch = 0.0
			yaw = (dir.x ~= 0 or dir.z ~= 0) and core.dir_to_yaw(dir) or wall_yaw
			roll = (nx * (dir.z or 0) - nz * (dir.x or 0) > 0) and (math.pi / 2) or (-math.pi / 2)
		end
	end

	return {x = pitch, y = yaw, z = roll}
end

--- Smoothly interpolates Euler angles handling modulo wrap with optional angular rate limiting
---@param cur_rot Vector Current rotation
---@param target_rot Vector Target rotation
---@param factor number Interpolation factor [0, 1]
---@param max_delta number|nil Maximum angular delta allowed per step (radians)
---@return Vector
local function interpolate_rotation(cur_rot, target_rot, factor, max_delta)
	local function smooth_angle(a, b)
		local diff = (b - a) % (2 * math.pi)
		if diff > math.pi then
			diff = diff - 2 * math.pi
		end
		local step = diff * factor
		if max_delta and max_delta > 0 then
			step = math.max(-max_delta, math.min(max_delta, step))
		end
		return a + step
	end

	return {
		x = smooth_angle(cur_rot.x or 0, target_rot.x or 0),
		y = smooth_angle(cur_rot.y or 0, target_rot.y or 0),
		z = smooth_angle(cur_rot.z or 0, target_rot.z or 0),
	}
end

--- Linearly interpolates and normalizes two 3D vectors
---@param v1 Vector Start vector
---@param v2 Vector Target vector
---@param factor number Interpolation factor [0, 1]
---@return Vector
local function interpolate_vector(v1, v2, factor)
	local f = math.max(0.0, math.min(1.0, factor))
	local inv = 1.0 - f
	local x = (v1.x or 0) * inv + (v2.x or 0) * f
	local y = (v1.y or 0) * inv + (v2.y or 0) * f
	local z = (v1.z or 0) * inv + (v2.z or 0) * f
	local len = math.sqrt(x * x + y * y + z * z)
	if len > 1e-4 then
		return {x = x / len, y = y / len, z = z / len}
	end
	return v2
end

--- Checks whether an entity is physically adjacent to a solid walkable surface
--- (floor, wall, ceiling, or uneven corner) within reach (~1.15m).
--- Retains preferred_normal if the existing surface is still in contact (hysteresis).
--- Returns surface info table or nil if entity is floating in mid-air.
---@param pos Vector World position
---@param preferred_normal Vector|nil Previous surface normal for geometric hysteresis
---@return table|nil surface_info {has_surface = boolean, normal = Vector, surface_type = string}
local function find_adjacent_surface(pos, preferred_normal)
	local cx = pos.x
	local cy = pos.y
	local cz = pos.z

	-- Hysteresis check verifying whether current surface normal is still valid
	if preferred_normal then
		local pn_len = math.sqrt(
			(preferred_normal.x or 0) * (preferred_normal.x or 0) +
			(preferred_normal.y or 0) * (preferred_normal.y or 0) +
			(preferred_normal.z or 0) * (preferred_normal.z or 0)
		)
		if pn_len > 0.5 then
			local un_x = (preferred_normal.x or 0) / pn_len
			local un_y = (preferred_normal.y or 0) / pn_len
			local un_z = (preferred_normal.z or 0) / pn_len

			-- Solid node is located in the direction opposite to the surface normal
			local check_npos = {
				x = math.floor(cx - un_x * 0.95 + 0.5),
				y = math.floor(cy - un_y * 0.95 + 0.5),
				z = math.floor(cz - un_z * 0.95 + 0.5),
			}
			local node = mob_ai.get_node(check_npos)
			local def = core.registered_nodes[node.name]
			if def and def.walkable then
				local stype = (un_y > 0.5 and "floor") or (un_y < -0.5 and "ceiling") or "wall"
				return {has_surface = true, normal = preferred_normal, surface_type = stype}
			end
		end
	end

	-- Primary cardinal surface checks
	-- Walls and ceiling are checked first so crawlers near floor-wall transitions detect the wall!
	local checks = {
		{0.85, 0, 0, {x = -1, y = 0, z = 0}, "wall"},
		{-0.85, 0, 0, {x = 1, y = 0, z = 0}, "wall"},
		{0, 0, 0.85, {x = 0, y = 0, z = -1}, "wall"},
		{0, 0, -0.85, {x = 0, y = 0, z = 1}, "wall"},
		{0, 0.85, 0, {x = 0, y = -1, z = 0}, "ceiling"},
		{0, -0.85, 0, {x = 0, y = 1, z = 0}, "floor"},
	}

	for i = 1, #checks do
		local c = checks[i]
		local npos = {
			x = math.floor(cx + c[1] + 0.5),
			y = math.floor(cy + c[2] + 0.5),
			z = math.floor(cz + c[3] + 0.5),
		}
		local node = mob_ai.get_node(npos)
		local def = core.registered_nodes[node.name]
		if def and def.walkable then
			return {has_surface = true, normal = c[4], surface_type = c[5]}
		end
	end

	-- Secondary diagonal checks for uneven cavern terrain
	local diag_n = 0.7071
	local diag_checks = {
		{0.75, 0.75, 0, {x = -diag_n, y = -diag_n, z = 0}, "ceiling"},
		{-0.75, 0.75, 0, {x = diag_n, y = -diag_n, z = 0}, "ceiling"},
		{0, 0.75, 0.75, {x = 0, y = -diag_n, z = -diag_n}, "ceiling"},
		{0, 0.75, -0.75, {x = 0, y = -diag_n, z = diag_n}, "ceiling"},
		{0.75, -0.75, 0, {x = -diag_n, y = diag_n, z = 0}, "wall"},
		{-0.75, -0.75, 0, {x = diag_n, y = diag_n, z = 0}, "wall"},
		{0, -0.75, 0.75, {x = 0, y = diag_n, z = -diag_n}, "wall"},
		{0, -0.75, -0.75, {x = 0, y = diag_n, z = diag_n}, "wall"},
		{0.75, 0, 0.75, {x = -diag_n, y = 0, z = -diag_n}, "wall"},
		{-0.75, 0, 0.75, {x = diag_n, y = 0, z = -diag_n}, "wall"},
		{0.75, 0, -0.75, {x = -diag_n, y = 0, z = diag_n}, "wall"},
		{-0.75, 0, -0.75, {x = diag_n, y = 0, z = diag_n}, "wall"},
	}

	for i = 1, #diag_checks do
		local dc = diag_checks[i]
		local npos = {
			x = math.floor(cx + dc[1] + 0.5),
			y = math.floor(cy + dc[2] + 0.5),
			z = math.floor(cz + dc[3] + 0.5),
		}
		local node = mob_ai.get_node(npos)
		local def = core.registered_nodes[node.name]
		if def and def.walkable then
			return {has_surface = true, normal = dc[4], surface_type = dc[5]}
		end
	end

	return nil
end

--- Checks whether a step in the given horizontal direction is safe for a ground mob:
--- - Detects cliffs (drops >= 3 blocks)
--- - Detects un-swimmable liquid (water, river water)
--- - Detects damaging hazard nodes (lava, fire)
--- - Verifies 1-node step-up or direct ground footstep
---@param pos Vector Mob position
---@param move_dir Vector Horizontal direction vector {x, y, z}
---@param abilities table Mob abilities (can_swim, can_climb, can_crawl)
---@param max_drop number|nil Maximum safe drop height (default 2)
---@return boolean is_safe True if the step is physically safe to take
local function is_step_safe(pos, move_dir, abilities, max_drop)
	local dlen = math.sqrt((move_dir.x or 0) * (move_dir.x or 0) + (move_dir.z or 0) * (move_dir.z or 0))
	if dlen < 1e-4 then
		return true
	end

	local dx = (move_dir.x or 0) / dlen
	local dz = (move_dir.z or 0) / dlen
	local step_dist = 1.15
	local max_d = max_drop or ((abilities and abilities.can_crawl) and 3 or 2)

	local target_x = math.floor(pos.x + dx * step_dist + 0.5)
	local target_z = math.floor(pos.z + dz * step_dist + 0.5)

	-- Current ground reference height
	local foot_y = math.floor(pos.y + 0.5)

	if abilities and abilities.is_floating then
		-- Floating aerial step check: target space at foot and head must be passable
		local f_node = mob_ai.get_node({x = target_x, y = foot_y, z = target_z})
		local f_def = core.registered_nodes[f_node.name]
		if f_def and f_def.walkable then
			return false, "wall"
		end
		if f_def and f_def.damage_per_second and f_def.damage_per_second > 0 then
			return false, "hazard"
		end
		if f_def and f_def.liquidtype and f_def.liquidtype ~= "none" and not abilities.can_swim then
			return false, "water"
		end

		local h_node = mob_ai.get_node({x = target_x, y = foot_y + 1, z = target_z})
		local h_def = core.registered_nodes[h_node.name]
		if h_def and h_def.walkable then
			return false, "wall"
		end
		if h_def and h_def.damage_per_second and h_def.damage_per_second > 0 then
			return false, "hazard"
		end

		return true
	end

	local current_ground_y = foot_y - 1

	-- If the mob's foot node is inside a solid block or floating, find the actual ground underneath:
	local node_under = mob_ai.get_node({x = math.floor(pos.x + 0.5), y = current_ground_y, z = math.floor(pos.z + 0.5)})
	local def_under = core.registered_nodes[node_under.name]
	if not (def_under and def_under.walkable) then
		local node_under2 = mob_ai.get_node({
			x = math.floor(pos.x + 0.5),
			y = current_ground_y - 1,
			z = math.floor(pos.z + 0.5),
		})
		local def_under2 = core.registered_nodes[node_under2.name]
		if def_under2 and def_under2.walkable then
			current_ground_y = current_ground_y - 1
			foot_y = foot_y - 1
		end
	end

	-- Check 1: Step-Up (+1 block)
	local node_step_up_ground = mob_ai.get_node({x = target_x, y = foot_y, z = target_z})
	local def_sug = core.registered_nodes[node_step_up_ground.name]
	local sug_openable = is_openable_door(node_step_up_ground.name, abilities)
	if def_sug and def_sug.walkable and not sug_openable then
		-- Tall obstacles (fences, walls, bars) are 1.5 blocks tall; non-crawlers cannot step over them
		local is_tall = (core.get_item_group(node_step_up_ground.name, "fence") or 0) > 0 or
			(core.get_item_group(node_step_up_ground.name, "wall") or 0) > 0 or
			(core.get_item_group(node_step_up_ground.name, "pane") or 0) > 0 or
			(core.get_item_group(node_step_up_ground.name, "iron_bars") or 0) > 0 or
			(node_step_up_ground.name:find("fence") ~= nil) or
			(node_step_up_ground.name:find("wall") ~= nil) or
			(node_step_up_ground.name:find("bars") ~= nil)
		if is_tall and not (abilities and abilities.can_crawl) then
			return false, "wall"
		end

		local node_head1 = mob_ai.get_node({x = target_x, y = foot_y + 1, z = target_z})
		local def_h1 = core.registered_nodes[node_head1.name]
		local node_head2 = mob_ai.get_node({x = target_x, y = foot_y + 2, z = target_z})
		local def_h2 = core.registered_nodes[node_head2.name]

		if def_h1 and def_h1.walkable and not is_openable_door(node_head1.name, abilities) then
			if abilities and abilities.can_crawl then
				return true -- Crawlers climb vertical solid walls
			end
			return false, "wall" -- Blocked by a 2+ high wall
		end
		if def_h2 and def_h2.walkable and not (abilities and abilities.can_crawl) and
		   not is_openable_door(node_head2.name, abilities) then
			return false, "headroom" -- Not enough headroom for 2-block tall mob
		end
		if (def_h1 and def_h1.damage_per_second and def_h1.damage_per_second > 0) then
			return false, "hazard"
		end
		if (def_h1 and def_h1.liquidtype and def_h1.liquidtype ~= "none" and not (abilities and abilities.can_swim)) then
			return false, "water"
		end
		return true -- Safe 1-node step-up!
	end

	-- Check 2: Level Walk (ground at current_ground_y, foot at foot_y)
	local node_foot = mob_ai.get_node({x = target_x, y = foot_y, z = target_z})
	local def_foot = core.registered_nodes[node_foot.name]

	-- If foot node is solid rock: crawlers can climb onto it!
	if def_foot and def_foot.walkable then
		if abilities and abilities.can_crawl then
			local node_head1 = mob_ai.get_node({x = target_x, y = foot_y + 1, z = target_z})
			local def_h1 = core.registered_nodes[node_head1.name]
			if def_h1 and def_h1.liquidtype and def_h1.liquidtype ~= "none" and not (abilities and abilities.can_swim) then
				return false, "water"
			end
			return true
		end
	end

	-- If foot is in damaging hazard (lava, fire):
	if def_foot and def_foot.damage_per_second and def_foot.damage_per_second > 0 then
		return false, "hazard"
	end

	-- If foot is in liquid (water) and mob cannot swim or water is disallowed:
	if def_foot and def_foot.liquidtype and def_foot.liquidtype ~= "none" then
		if not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water) then
			return false, "water"
		end
	end

	-- Check ladder / climbing support:
	if abilities and abilities.can_climb then
		if def_foot and def_foot.climbable then return true end
	end

	-- Check ground below foot node:
	local node_ground = mob_ai.get_node({x = target_x, y = current_ground_y, z = target_z})
	local def_ground = core.registered_nodes[node_ground.name]

	-- Climbing ladder ground support:
	if abilities and abilities.can_climb then
		if def_ground and def_ground.climbable then return true end
	end

	-- Liquid ground check:
	if def_ground and def_ground.liquidtype and def_ground.liquidtype ~= "none" then
		if not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water) then
			return false, "water"
		end
	end

	-- Hazard ground check:
	if def_ground and def_ground.damage_per_second and def_ground.damage_per_second > 0 then
		return false, "hazard"
	end

	-- If solid ground or swimmable water exists at current level:
	local is_solid_walkable = def_ground and def_ground.walkable and
		not (def_ground.liquidtype and def_ground.liquidtype ~= "none")
	local is_swimmable_water = abilities and abilities.can_swim and not (abilities and abilities.disallow_water) and (
		(def_ground and def_ground.liquidtype and def_ground.liquidtype ~= "none") or
		(def_foot and def_foot.liquidtype and def_foot.liquidtype ~= "none")
	)
	local can_traverse_ground = is_solid_walkable or is_swimmable_water
	if can_traverse_ground then
		local node_head = mob_ai.get_node({x = target_x, y = foot_y + 1, z = target_z})
		local def_head = core.registered_nodes[node_head.name]
		if def_head and def_head.walkable and not (abilities and abilities.can_crawl) and
		   not is_openable_door(node_head.name, abilities) then
			return false, "headroom" -- Headroom blocked
		end
		return true -- Safe level step!
	end

	-- Check 3: Drop-Down (Step down 1 to max_d blocks)
	for drop = 1, max_d do
		local drop_ground_y = current_ground_y - drop
		local drop_foot_y = drop_ground_y + 1

		local n_dg = mob_ai.get_node({x = target_x, y = drop_ground_y, z = target_z})
		local def_dg = core.registered_nodes[n_dg.name]
		local n_df = mob_ai.get_node({x = target_x, y = drop_foot_y, z = target_z})
		local def_df = core.registered_nodes[n_df.name]

		-- Hazard check on the drop node:
		if (def_df and def_df.damage_per_second and def_df.damage_per_second > 0) or
		   (def_dg and def_dg.damage_per_second and def_dg.damage_per_second > 0) then
			return false, "hazard"
		end

		-- Liquid check on the drop node:
		if ((def_df and def_df.liquidtype and def_df.liquidtype ~= "none") or
		    (def_dg and def_dg.liquidtype and def_dg.liquidtype ~= "none")) and
		   (not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water)) then
			return false, "water"
		end

		local can_drop_onto = (def_dg and def_dg.walkable and not (def_dg.liquidtype and def_dg.liquidtype ~= "none")) or
			(abilities and abilities.can_swim and not (abilities and abilities.disallow_water) and (
				(def_dg and def_dg.liquidtype and def_dg.liquidtype ~= "none") or
				(def_df and def_df.liquidtype and def_df.liquidtype ~= "none")
			))
		if can_drop_onto then
			return true -- Found solid landing ground or water within safe drop height!
		end
	end

	-- IT IS A CLIFF / CANYON! (Drop exceeds safe height or falls into open void)
	return false, "cliff"
end

--- Verifies that there is a continuous, safe ground path along the straight line
--- between pos and target_pos (no chasms, deep cliffs, or un-swimmable water).
--- If continuous ground does not exist, Tier 1 direct steering is invalidated,
--- forcing Tier 2 A* pathfinding to find a safe way around.
---@param pos Vector Mob position
---@param target_pos Vector Target position
---@param abilities table Mob abilities
---@return boolean has_ground True if continuous safe ground exists
---@return string|nil reason Failure reason if not safe ("water", "cliff", "hazard", etc.)
local function check_ground_line_of_sight(pos, target_pos, abilities)
	local dx = target_pos.x - pos.x
	local dz = target_pos.z - pos.z
	local flat_dist = math.sqrt(dx * dx + dz * dz)

	-- If very close (within 1.5 blocks), rely on immediate step check
	if flat_dist <= 1.5 then
		return is_step_safe(pos, {x = dx, y = 0, z = dz}, abilities)
	end

	local dir_x = dx / flat_dist
	local dir_z = dz / flat_dist

	-- Sample ground elevation at 1.8m intervals along the line
	local step_size = 1.8
	local num_steps = math.min(12, math.floor(flat_dist / step_size))

	local prev_ground_y = math.floor(pos.y + 0.5) - 1
	for i = 1, num_steps do
		local sample_dist = i * step_size
		local sx = math.floor(pos.x + dir_x * sample_dist + 0.5)
		local sz = math.floor(pos.z + dir_z * sample_dist + 0.5)

		-- Linear interpolation of expected terrain elevation
		local t = sample_dist / flat_dist
		local interp_y = math.floor(pos.y + (target_pos.y - pos.y) * t + 0.2)

		-- Scan downward from interp_y + 1 to interp_y - 2 to find walkable ground
		local found_ground = false
		local ground_y = nil
		for cy = interp_y + 1, interp_y - 2, -1 do
			local node = mob_ai.get_node({x = sx, y = cy, z = sz})
			local def = core.registered_nodes[node.name]
			if def then
				if def.damage_per_second and def.damage_per_second > 0 then
					return false, "hazard" -- Lava / fire hazard cuts across path
				end
				if def.liquidtype and def.liquidtype ~= "none" then
					if not (abilities and abilities.can_swim) then
						return false, "water" -- Water / river cuts across path
					end
				end
				local is_door_node = is_openable_door(node.name, abilities)
				local is_valid_medium = (def.walkable and not is_door_node) or
					(def.climbable and abilities and abilities.can_climb) or
					(abilities and abilities.can_swim and def.liquidtype and def.liquidtype ~= "none")
				if is_valid_medium then
					found_ground = true
					ground_y = cy
					break
				end
			end
		end

		if not found_ground then
			-- Chasm or cliff detected (> 2 blocks drop) along the straight line!
			return false, "cliff"
		end

		-- Elevation continuity check for non-crawlers and non-floaters:
		-- A ground mob cannot step up a vertical rise > 1.25 nodes per sample!
		if not (abilities and (abilities.can_crawl or abilities.is_floating)) then
			local cur_node = ground_y and mob_ai.get_node({x = sx, y = ground_y, z = sz})
			local cur_def = cur_node and core.registered_nodes[cur_node.name]
			local is_climbing_step = abilities and abilities.can_climb and cur_def and cur_def.climbable
			if not is_climbing_step and ground_y and prev_ground_y and (ground_y - prev_ground_y) > 1.25 then
				return false, "wall"
			end

			-- Headroom and torso clearance check: 2-node clearance above ground for non-crawlers
			if ground_y then
				local torso_node = mob_ai.get_node({x = sx, y = ground_y + 1, z = sz})
				local torso_def = core.registered_nodes[torso_node.name]
				if torso_def and torso_def.walkable and not is_openable_door(torso_node.name, abilities) then
					return false, "wall"
				end

				local head_node = mob_ai.get_node({x = sx, y = ground_y + 2, z = sz})
				local head_def = core.registered_nodes[head_node.name]
				if head_def and head_def.walkable and not is_openable_door(head_node.name, abilities) then
					return false, "headroom"
				end
			end
		end
		if ground_y then
			prev_ground_y = ground_y
		end
	end

	return true
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
local function calculate_separation_force(self, current_pos, dtime, on_surface, normal)
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
						-- Repulsion magnitude: inversely proportional to distance
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
		-- Surface Tangent Projection: prevent separation from pushing mob into or off the wall
		local dot = sep_force.x * normal.x + sep_force.y * normal.y + sep_force.z * normal.z
		sep_force.x = sep_force.x - dot * normal.x
		sep_force.y = sep_force.y - dot * normal.y
		sep_force.z = sep_force.z - dot * normal.z
	else
		-- On ground: keep horizontal, let gravity handle vertical
		sep_force.y = 0
	end

	-- Cap maximum separation velocity
	local f_len = math.sqrt(sep_force.x * sep_force.x + sep_force.y * sep_force.y + sep_force.z * sep_force.z)
	if f_len > 3.0 then
		sep_force.x = (sep_force.x / f_len) * 3.0
		sep_force.y = (sep_force.y / f_len) * 3.0
		sep_force.z = (sep_force.z / f_len) * 3.0
	end

	self._cached_sep_force = sep_force
	return sep_force
end

-- -------------------------------------------------------------------------
-- CORE MOTOR CONTROLLER & MOVEMENT HANDLER
-- -------------------------------------------------------------------------

--- Handles physical movement and steering toward the next path waypoint
---@param self table Entity instance
---@param dtime number Step delta time
---@param current_pos Vector Current mob world position
---@param next_waypoint Vector Target node world position
local function handle_mob_movement(self, dtime, current_pos, next_waypoint)
	local is_pursuing = get_pursuit_state(self)

	local node_at_target = mob_ai.get_node(next_waypoint)
	local def_target = core.registered_nodes[node_at_target.name] or {}
	local current_node = mob_ai.get_node({
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
		if is_openable_door(node_at_target.name, self.abilities) and
		   not is_door_open(next_waypoint, node_at_target, def_target) then
			local opened = try_open_door(next_waypoint, node_at_target, def_target, self.object)
			if not opened then
				-- Invalidate path if door is locked, protected, or blocked
				self.path_state.waypoints = nil
				self.path_state.index = 1
				return
			end
		end

		-- Also check immediate forward node in direction of waypoint
		local to_wpt = vector.direction(current_pos, next_waypoint)
		check_and_open_forward_doors(current_pos, to_wpt, self.abilities, self.object)
	end

	-- Surface Crawling Physics (Walls, Ceilings, Ledges & 3D Crawling)
	local is_crawler = self.abilities and self.abilities.can_crawl == true
	local normal = next_waypoint.normal or {x = 0, y = 1, z = 0}
	local surface_type = next_waypoint.surface_type or
		(normal.y < -0.5 and "ceiling" or (normal.y > 0.5 and "floor" or "wall"))

	if is_crawler then
		-- Maintain kinematic surface adhesion on walls/ceilings, standard gravity on floor
		local on_surface = (surface_type == "wall" or surface_type == "ceiling")
		self.on_wall_or_ceiling = on_surface
		if on_surface then
			safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		else
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end

		-- Dynamic collisionbox: compact 0.40m box on walls/ceilings to prevent snagging and allow close surface adherence
		-- Always preserve the full 3D selectionbox so player crosshair punches always register
		local SPIDER_SELBOX = {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85}
		if self.object and self.object:is_valid() then
			if on_surface and not self._has_wall_cbox then
				self._has_wall_cbox = true
				self.object:set_properties({
					collisionbox = {-0.20, -0.20, -0.20, 0.20, 0.20, 0.20},
					selectionbox = SPIDER_SELBOX,
				})
			elseif not on_surface and self._has_wall_cbox then
				self._has_wall_cbox = false
				self.object:set_properties({
					collisionbox = {-0.35, 0.0, -0.35, 0.35, 0.45, 0.35},
					selectionbox = SPIDER_SELBOX,
				})
			end
		end

		-- Target waypoint placed right against the surface plane (~0.20m from rock)
		-- next_waypoint is the air block center (0.5m from rock face along normal).
		-- Subtraction brings the spider in from the air node center toward the rock face:
		-- Target waypoint placed right against the surface plane (~0.20m from rock)
		-- next_waypoint is the air block center (0.5m from rock face along normal).
		-- Subtraction brings the spider in from the air node center toward the rock face:
		-- (next_waypoint - normal * 0.5) + normal * 0.20 = next_waypoint - normal * 0.30.
		local target_wpt = {
			x = next_waypoint.x - (normal.x * 0.30),
			y = next_waypoint.y - (normal.y * 0.30),
			z = next_waypoint.z - (normal.z * 0.30),
		}

		local move_vec = vector.direction(current_pos, target_wpt)
		local speed = is_pursuing and (self.pursuit_speed or 4.0) or (self.walk_speed or 1.5)

		-- Heading Deadband: prevent 180-degree vector flips when within 0.30m of waypoint
		local dist_to_target = vector.distance(current_pos, target_wpt)
		local move_heading
		if dist_to_target > 0.30 then
			move_heading = move_vec
			self._last_move_dir = move_heading
		else
			move_heading = self._last_move_dir or move_vec
		end

		-- Surface Normal Interpolation: smooth out corner/edge 90-degree transitions
		self._cur_normal = self._cur_normal or normal
		self._cur_normal = interpolate_vector(self._cur_normal, normal, math.min(1.0, dtime * 8.0))
		local active_normal = self._cur_normal

		-- Combine forward tangent speed with gentle inward adherence velocity and soft separation
		local adhere_bias = on_surface and 0.22 or 0.0
		local sep = calculate_separation_force(self, current_pos, dtime, on_surface, active_normal)
		local vx = move_vec.x * speed - active_normal.x * adhere_bias + sep.x
		local vy = move_vec.y * speed - active_normal.y * adhere_bias + sep.y
		local vz = move_vec.z * speed - active_normal.z * adhere_bias + sep.z

		self.object:set_velocity({x = vx, y = vy, z = vz})

		-- Smooth 3D surface rotation with angular rate limiting
		local target_rot = dir_to_surface_rotation(move_heading, active_normal)
		local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object), z = 0}
		local max_rot_step = (self.max_angular_speed or 7.5) * dtime
		local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 10.0), max_rot_step)
		self._cur_rot = smoothed_rot
		safe_set_rotation(self.object, smoothed_rot)

		-- 3D Waypoint Arrival detection: tighter threshold (0.80 nodes) ensures spider hugs corners
		-- and physically traverses surface transitions without cutting corners through mid-air!
		local dist_3d = vector.distance(current_pos, next_waypoint)
		local arrived = (dist_3d < 0.80)

		-- Anti-snag watchdog for uneven rocky terrain: if close to waypoint for >0.5s, auto-advance
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
	local in_liq, is_subm, _, target_vy = check_in_liquid(current_pos, self.abilities, self.mob_height)
	local in_liquid = self.abilities.can_swim and (
		(def_current.liquidtype and def_current.liquidtype ~= "none") or
		(def_target.liquidtype and def_target.liquidtype ~= "none") or
		in_liq
	)

	-- Ladder & Climbing Physics (Pursuit Only)
	local in_ladder = is_pursuing and self.abilities.can_climb and
		(def_current and def_current.climbable == true)
	local approaching_ladder = is_pursuing and self.abilities.can_climb and
		not in_ladder and (def_target and def_target.climbable == true)

	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local move_vec = vector.direction(current_pos, next_waypoint)
	local speed = is_pursuing and (self.pursuit_speed or 4.0) or (self.walk_speed or 1.5)
	local y_vel = vel.y

	if in_ladder then
		local dy = next_waypoint.y - current_pos.y
		safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		if math.abs(dy) > 0.15 then
			y_vel = (dy > 0) and 2.2 or -2.2
		else
			y_vel = 0
		end
		self._was_in_ladder = true
	elseif in_liquid then
		y_vel = calculate_liquid_vertical_velocity(self, current_pos.y, next_waypoint.y, is_subm, target_vy)
		speed = speed * 0.75
	elseif self.is_floating then
		safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		local desired_y = next_waypoint.y + (self.hover_offset or 0.0)
		local dy = desired_y - current_pos.y
		y_vel = math.min(math.max(dy * 2.5, -5.0), 4.5)
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
	self.object:set_velocity({
		x = move_vec.x * speed + sep.x,
		y = y_vel,
		z = move_vec.z * speed + sep.z,
	})

	if math.abs(move_vec.x) > 0.01 or math.abs(move_vec.z) > 0.01 then
		local yaw = core.dir_to_yaw(move_vec)
		local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
		local target_rot = {x = 0, y = yaw, z = 0}
		local max_rot_step = (self.max_angular_speed or 7.5) * dtime
		local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 10.0), max_rot_step)
		self._cur_rot = smoothed_rot
		if math.abs(smoothed_rot.x) + math.abs(smoothed_rot.z) > 0.05 then
			safe_set_rotation(self.object, smoothed_rot)
		else
			safe_set_yaw(self.object, smoothed_rot.y)
		end
	end

	-- Advance to next waypoint when reaching proximity
	local flat_dist = vector.distance(
		{x = current_pos.x, y = 0, z = current_pos.z},
		{x = next_waypoint.x, y = 0, z = next_waypoint.z}
	)
	local y_diff = math.abs(current_pos.y - next_waypoint.y)
	local arrival_thresh = math.max(0.85, (self.half_width or 0.4) * 1.25)
	local y_thresh = (in_ladder or approaching_ladder) and 0.5 or (self.is_floating and 1.8 or 1.35)
	local arrived = (flat_dist < arrival_thresh) and (y_diff < y_thresh)

	-- Anti-snag watchdog for ground & floating mobs: if stuck near waypoint for >0.4s, auto-advance
	if not arrived and self.path_state then
		if (self.path_state.last_wpt_idx or 0) == self.path_state.index then
			self.path_state.wpt_stuck_time = (self.path_state.wpt_stuck_time or 0) + dtime
			if self.path_state.wpt_stuck_time > 0.4 and flat_dist < 2.0 and y_diff < 2.5 then
				arrived = true
				self.path_state.wpt_stuck_time = 0
			elseif self.path_state.wpt_stuck_time > 0.8 then
				-- Snagged further from waypoint: invalidate path to force immediate re-search around obstacle
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

-- -------------------------------------------------------------------------
-- HIERARCHICAL NAVIGATION DISPATCHER (ON_STEP)
-- -------------------------------------------------------------------------

--- Updates autonomous local wandering and idling when mob is not pursuing a target
---@param self table Entity instance
---@param dtime number Step delta time
---@param current_pos Vector Current mob world position
---@param on_wall_or_ceiling boolean Whether mob is adhering to wall/ceiling
---@return table status Locomotion status {moving = boolean, speed = number, has_los = boolean}
local function handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
	local in_liquid, is_subm, _, target_vy = check_in_liquid(current_pos, self.abilities, self.mob_height)

	if self.can_wander == false then
		local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		if in_liquid then
			vel.y = target_vy or 0
			if is_subm then
				safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
			else
				safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			end
		elseif not self.is_floating and not on_wall_or_ceiling then
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end
		self.object:set_velocity({x = 0, y = vel.y, z = 0})
		return {moving = false, speed = 0, has_los = false}
	end

	if not self.wander_state then
		self.wander_state = {
			is_moving = false,
			timer = 1.5 + math.random() * 2.0,
			dir = {x = 0, y = 0, z = 0},
			yaw = safe_get_yaw(self.object),
			origin = {x = current_pos.x, y = current_pos.y, z = current_pos.z},
		}
	end

	local ws = self.wander_state
	ws.timer = ws.timer - dtime

	if in_liquid then
		if is_subm then
			safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
		else
			safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
		end
	elseif not self.is_floating and not on_wall_or_ceiling then
		safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
	elseif self.is_floating or on_wall_or_ceiling then
		safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
	end

	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local y_vel = vel.y

	if in_liquid then
		y_vel = target_vy or 0
	elseif self.is_floating then
		local ground_y = utils.get_ground_y(current_pos, 16, 0, true)
		if ground_y then
			local desired_y = ground_y + (self.hover_offset or 1.8)
			local dy = desired_y - current_pos.y
			if dy < -0.2 then
				y_vel = math.max(dy * 2.0, -3.5)
			elseif dy > 0.2 then
				y_vel = math.min(dy * 2.0, 1.8)
			else
				y_vel = 0
			end
		else
			y_vel = 0
		end
	end

	local wander_abilities = self.abilities
	if not in_liquid and self.abilities and self.abilities.can_swim then
		wander_abilities = utils.shallow_copy(self.abilities)
		wander_abilities.can_swim = false
		wander_abilities.disallow_water = true
	end

	if not ws.is_moving then
		self.object:set_velocity({x = 0, y = y_vel, z = 0})

		if ws.timer <= 0 then
			local chosen_yaw

			-- If mob is stuck in liquid while wandering, actively steer towards nearest dry walkable shoreline
			if in_liquid and self.abilities and self.abilities.can_swim then
				local px, py, pz = math.floor(current_pos.x + 0.5), math.floor(current_pos.y + 0.5), math.floor(current_pos.z + 0.5)
				local best_d, shore_pos = 9999, nil
				for dx = -8, 8 do
					for dz = -8, 8 do
						local d = dx * dx + dz * dz
						if d <= 64 and d < best_d then
							for dy = -1, 2 do
								local ng = mob_ai.get_node_or_nil({x = px + dx, y = py + dy - 1, z = pz + dz})
								local dg = ng and core.registered_nodes[ng.name]
								local nf = mob_ai.get_node_or_nil({x = px + dx, y = py + dy, z = pz + dz})
								local df = nf and core.registered_nodes[nf.name]
								if dg and dg.walkable and (not dg.liquidtype or dg.liquidtype == "none") and
								   df and (not df.walkable) and (not df.liquidtype or df.liquidtype == "none") then
									best_d = d
									shore_pos = {x = px + dx, y = py + dy, z = pz + dz}
									break
								end
							end
						end
					end
				end
				if shore_pos then
					local to_shore = vector.direction(current_pos, shore_pos)
					chosen_yaw = core.dir_to_yaw(to_shore)
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
					-- Multi-sample candidate angles and score with mob memory
					-- (Danger repulsion + exploration novelty bias + anti-cliff deadlock)
					local best_score = -9999.0
					local best_yaw = math.random() * math.pi * 2
					for _ = 1, 6 do
						local test_yaw = math.random() * math.pi * 2
						local t_dir = {x = -math.sin(test_yaw), y = 0, z = math.cos(test_yaw)}
						local score = mob_memory.evaluate_heading_bias(self, t_dir, current_pos)
						if not self.is_floating and not on_wall_or_ceiling then
							if not is_step_safe(current_pos, t_dir, wander_abilities) then
								score = score - 100.0
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
				safe = is_step_safe(current_pos, {x = dir_x, y = 0, z = dir_z}, wander_abilities)
			end

			if safe then
				ws.is_moving = true
				ws.timer = 2.0 + math.random() * 2.5
				ws.yaw = chosen_yaw
				ws.dir = {x = dir_x, y = 0, z = dir_z}
				safe_set_yaw(self.object, chosen_yaw)
			else
				ws.timer = 0.5 + math.random() * 0.8
				return {moving = false, speed = 0, has_los = false}
			end
		else
			return {moving = false, speed = 0, has_los = false}
		end
	end

	local speed = self.wander_speed or (self.walk_speed and self.walk_speed * 0.6) or 1.8
	if in_liquid then
		speed = speed * 0.75
	end

	if not self.is_floating and not on_wall_or_ceiling then
		local is_wall_colliding, wall_norm = has_wall_collision(self, current_pos, dtime)
		local unsafe_step = not is_step_safe(current_pos, ws.dir, wander_abilities)

		if unsafe_step or is_wall_colliding then
			-- Mob reached a wall, obstacle, or drop-off while wandering:
			-- Deflect into safe tangent/perpendicular directions instead of stopping dead
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
				if is_step_safe(current_pos, cand, wander_abilities) then
					ws.dir = cand
					ws.yaw = core.dir_to_yaw(cand)
					ws.timer = 2.0 + math.random() * 1.5
					ws.is_moving = true
					safe_set_yaw(self.object, ws.yaw)
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

			if not deflected then
				ws.is_moving = false
				ws.timer = 0.6 + math.random() * 0.6
				self.object:set_velocity({x = 0, y = y_vel, z = 0})
				return {moving = false, speed = 0, has_los = false}
			end
		end
	end

	if on_wall_or_ceiling then
		local adj = find_adjacent_surface(current_pos, self._cur_normal)
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
			safe_set_rotation(self.object, self._cur_rot)
		end
	else
		self.object:set_velocity({
			x = ws.dir.x * speed,
			y = y_vel,
			z = ws.dir.z * speed,
		})
		safe_set_yaw(self.object, ws.yaw)
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
local function handle_mob_fleeing(self, dtime, current_pos, on_wall_or_ceiling)
	local return_thresh = self.return_hp_threshold or 24
	local cur_hp = self.hp or (self.object and self.object:is_valid() and self.object:get_hp()) or 40
	local is_panicking = (self.panic_timer and self.panic_timer > 0)
	if not is_panicking and ((self.memory and not self.memory.flee_state) or cur_hp >= return_thresh) then
		self.state = "idle"
		if self.memory then self.memory.flee_state = false end
		self._flee_dir = nil
		self._flee_timer = nil
		self._flee_last_pos = nil
		self._flee_stagnant_timer = nil
		return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
	end

	-- Determine true threat repulsion vector (away from danger)
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
		return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
	end

	-- Directional commitment and deflection state management
	self._flee_timer = (self._flee_timer or 0) - dtime
	if not self._flee_dir then
		self._flee_dir = threat_repulse
		self._flee_timer = 0.6
		self._flee_deflecting = false
	elseif self._flee_deflecting then
		-- When committed to an obstacle deflection, check if commitment timer expired
		if self._flee_timer <= 0 then
			self._flee_deflecting = false
			-- Smoothly resume pure fleeing away from threat if reasonably aligned
			local dot = self._flee_dir.x * threat_repulse.x + self._flee_dir.z * threat_repulse.z
			if dot > 0.2 then
				self._flee_dir = threat_repulse
			end
		end
	else
		-- In open space, smoothly track threat repulsion
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

	local speed = self.flee_speed or ((self.pursuit_speed or 4.0) * 1.25)
	local is_crawler = self.abilities and self.abilities.can_crawl

	-- If crawler on ground is fleeing, prioritize acquiring walls to climb to safety
	if is_crawler and not on_wall_or_ceiling then
		local c_dir = self._flee_dir or threat_repulse
		local check_pos = {
			x = math.floor(current_pos.x + c_dir.x * 0.95 + 0.5),
			y = math.floor(current_pos.y + 0.5),
			z = math.floor(current_pos.z + c_dir.z * 0.95 + 0.5),
		}
		local c_node = mob_ai.get_node(check_pos)
		local c_def = core.registered_nodes[c_node.name]
		if c_def and c_def.walkable then
			self.on_wall_or_ceiling = true
			safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
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

	local in_liquid, is_subm, _, target_vy = check_in_liquid(current_pos, self.abilities, self.mob_height)
	local move_vec = self._flee_dir
	if not on_wall_or_ceiling and not self.is_floating then
		local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
		local y_vel = vel.y
		if in_liquid then
			y_vel = target_vy or 0
			if is_subm then
				safe_set_acceleration(self.object, {x = 0, y = 0.5, z = 0})
			else
				safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			end
			speed = speed * 0.75
		else
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end

		-- Displacement watchdog per frame to detect true physical stagnation
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

		-- Proactive door opening in flee direction
		check_and_open_forward_doors(current_pos, self._flee_dir, self.abilities, self.object)

		local is_wall_hit, f_wall_norm = has_wall_collision(self, current_pos, dtime)
		local is_stagnant = ((self._flee_stagnant_timer or 0) > 0.3) or is_wall_hit
		local step_direct = is_step_safe(current_pos, self._flee_dir, self.abilities)

		if step_direct and speed > 3.0 then
			-- Proactive canyon / cliff lookahead for high-speed fleeing
			local look_pos = {
				x = current_pos.x + self._flee_dir.x * 1.25,
				y = current_pos.y,
				z = current_pos.z + self._flee_dir.z * 1.25,
			}
			local look_safe, look_reason = is_step_safe(look_pos, self._flee_dir, self.abilities)
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
			-- Obstructed by wall, cliff, or obstacle: find an evasion corridor
			-- All candidates are evaluated relative to threat_repulse to prevent spiraling
			local tx = threat_repulse.x
			local tz = threat_repulse.z
			local px = tz
			local pz = -tx
			local inv_s2 = 0.70710678

			local cands = {}
			-- Wall tangents using available collision normal
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

			-- Angular escape radials relative to threat_repulse
			-- Determine lateral bias from current heading to maintain momentum
			local cur_bias = self._flee_dir.x * px + self._flee_dir.z * pz
			if cur_bias >= 0 then
				cands[#cands + 1] = {x = (tx + px) * inv_s2, y = 0, z = (tz + pz) * inv_s2} -- 45 deg right
				cands[#cands + 1] = {x = (tx - px) * inv_s2, y = 0, z = (tz - pz) * inv_s2} -- 45 deg left
				cands[#cands + 1] = {x = px, y = 0, z = pz}                                 -- 90 deg right
				cands[#cands + 1] = {x = -px, y = 0, z = -pz}                               -- 90 deg left
				cands[#cands + 1] = {x = (-tx + px) * inv_s2, y = 0, z = (-tz + pz) * inv_s2} -- 135 deg right
				cands[#cands + 1] = {x = (-tx - px) * inv_s2, y = 0, z = (-tz - pz) * inv_s2} -- 135 deg left
			else
				cands[#cands + 1] = {x = (tx - px) * inv_s2, y = 0, z = (tz - pz) * inv_s2} -- 45 deg left
				cands[#cands + 1] = {x = (tx + px) * inv_s2, y = 0, z = (tz + pz) * inv_s2} -- 45 deg right
				cands[#cands + 1] = {x = -px, y = 0, z = -pz}                               -- 90 deg left
				cands[#cands + 1] = {x = px, y = 0, z = pz}                                 -- 90 deg right
				cands[#cands + 1] = {x = (-tx - px) * inv_s2, y = 0, z = (-tz - pz) * inv_s2} -- 135 deg left
				cands[#cands + 1] = {x = (-tx + px) * inv_s2, y = 0, z = (-tz + pz) * inv_s2} -- 135 deg right
			end
			cands[#cands + 1] = {x = -tx, y = 0, z = -tz} -- 180 deg reverse (escape dead end)

			local best_cand = nil
			local best_score = -99999.0

			for i = 1, #cands do
				local cand = cands[i]
				if is_step_safe(current_pos, cand, self.abilities) then
					local dot_threat = cand.x * tx + cand.z * tz
					local dot_cur = cand.x * self._flee_dir.x + cand.z * self._flee_dir.z
					local score = dot_threat * 3.0 + dot_cur * 0.8

					-- Proactive candidate lookahead: prioritize corridors that stay safe beyond immediate step
					local cand_look = {
						x = current_pos.x + cand.x * 1.25,
						y = current_pos.y,
						z = current_pos.z + cand.z * 1.25,
					}
					local cand_look_safe = is_step_safe(cand_look, cand, self.abilities)
					if cand_look_safe then
						score = score + 2.5
					else
						score = score - 15.0
					end

					if cand.is_tangent then
						score = score + 4.0
					end

					if has_norm then
						local dot_wall = cand.x * nx + cand.z * nz
						if dot_wall < -0.1 then
							score = score - 30.0 -- Avoid pushing into collided wall
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
				return {moving = false, speed = 0, has_los = false}
			end
		end

		local target_yaw = core.dir_to_yaw(move_vec)
		local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
		local target_rot = {x = 0, y = target_yaw, z = 0}
		local max_rot_step = (self.max_angular_speed or 7.5) * dtime
		local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 10.0), max_rot_step)
		self._cur_rot = smoothed_rot
		safe_set_rotation(self.object, smoothed_rot)
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

			-- Check if surface continues along crawl tangent: prevent crawling off the edge into empty air/canyon
			local next_surf_pos = {
				x = current_pos.x + ux * 0.85,
				y = current_pos.y + uy * 0.85,
				z = current_pos.z + uz * 0.85,
			}
			local ahead_surf = find_adjacent_surface(next_surf_pos, surf_norm)
			if ahead_surf then
				self.object:set_velocity({
					x = ux * speed - surf_norm.x * 0.2,
					y = uy * speed - surf_norm.y * 0.2,
					z = uz * speed - surf_norm.z * 0.2,
				})
			else
				-- Surface terminates ahead: stay pinned to current surface rather than falling into void/canyon
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

--- Updates entity navigation, scanning, line-of-sight, and path execution
---@param self table Entity instance
---@param dtime number Step delta time
---@return table status Locomotion status {moving = boolean, speed = number, has_los = boolean}
function mob_ai.update_navigation(self, dtime)
	-- Initialize navigation state tables if missing
	if not self.path_state then
		self.path_state = {
			waypoints = nil,
			index = 1,
			timer = 0.0,
			is_calculating = false,
		}
	end

	if not self._inherent_abilities then
		local doors_val = false
		if self.can_open_doors ~= nil then
			doors_val = (self.can_open_doors == true)
		elseif self.abilities and self.abilities.can_open_doors ~= nil then
			doors_val = (self.abilities.can_open_doors == true)
		end

		local climb_val = false
		if self.can_climb ~= nil then
			climb_val = (self.can_climb == true)
		elseif self.abilities and self.abilities.can_climb ~= nil then
			climb_val = (self.abilities.can_climb == true)
		end

		local swim_val = (self.can_swim == true) or (self.is_floating == true)
		if self.can_swim == false then
			swim_val = false
		elseif self.can_swim == nil and self.abilities and self.abilities.can_swim == true then
			swim_val = true
		end

		local crawl_val = (self.can_crawl == true) or (self.abilities and self.abilities.can_crawl == true)

		self._inherent_abilities = {
			can_open_doors = doors_val == true,
			can_climb = climb_val == true,
			can_swim = swim_val == true,
			can_crawl = crawl_val == true,
			is_floating = self.is_floating == true,
		}
	end

	if not self.abilities then
		self.abilities = {
			can_open_doors = false,
			can_climb = false,
			can_swim = false,
			can_crawl = false,
			is_floating = self.is_floating == true,
		}
	end
	self.half_width = self.half_width or 0.4

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
	self.abilities.can_swim = inh.can_swim == true
	self.abilities.can_crawl = inh.can_crawl == true
	self.abilities.is_floating = inh.is_floating == true

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

		if on_wall_or_ceiling and not adj_surf then
			-- PHYSICAL ADJACENCY WATCHDOG:
			-- Entity is floating in mid-air with NO solid surface within reach!
			-- Detach immediately and fall under gravity!
			on_wall_or_ceiling = false
			self.on_wall_or_ceiling = false
			self._has_wall_cbox = false
			self._cur_normal = nil
			self._cur_rot = {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
			safe_set_rotation(self.object, self._cur_rot)
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
			self.object:set_properties({
				collisionbox = {-0.35, 0.0, -0.35, 0.35, 0.45, 0.35},
				selectionbox = {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85},
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
				collisionbox = {-0.35, 0.0, -0.35, 0.35, 0.45, 0.35},
				selectionbox = {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85},
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
					selectionbox = {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85},
				})
			end
		end
	end

	-- Fleeing state check (low HP retreat away from danger)
	if self.state == "fleeing" or self.state == "flee" then
		return handle_mob_fleeing(self, dtime, current_pos, on_wall_or_ceiling)
	end

	local target_pos
	if not is_pursuing then
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
	else
		target_pos = self.target:get_pos()
		if not target_pos then
			return handle_mob_wandering(self, dtime, current_pos, on_wall_or_ceiling)
		end
	end

	if self.wander_state and self.wander_state.is_moving then
		self.wander_state.is_moving = false
	end

	-- Record short-term trail history during combat/pursuit (zero-allocation ring buffer)
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
					self.path_state.timer = 999.0
					self.path_state.retry_delay = 0
				end
				self._stuck_timer = 0.0
			end
		end
	end

	local dist = vector.distance(current_pos, target_pos)

	-- Assign deterministic tactical flanking slot & unique path seed to each mob
	if not self._flank_slot then
		-- Slot 1: Direct frontal approach
		-- Slot 2: Left flank (+1.1 rad)
		-- Slot 3: Right flank (-1.1 rad)
		-- Slot 4: Rear / Overhead ceiling approach (+2.8 rad)
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

	-- Throttled volumetric corridor & ground check (0.2s cache interval during open pursuit)
	self.path_state._corridor_timer = (self.path_state._corridor_timer or 0) + dtime
	local corridor_clear = false
	local has_ground_los = false
	local glos_reason = self.path_state._glos_reason_cached

	if has_los then
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
		self.path_state._corridor_cached = false
		self.path_state._ground_los_cached = false
		self.path_state._glos_reason_cached = nil
	end

	if has_los and corridor_clear and has_ground_los and not on_wall_or_ceiling and (self.is_floating or dy <= 3.5) then
		local steer_dest = (dist > 4.5) and nav_target_pos or target_pos
		local move_vec = vector.direction(current_pos, steer_dest)

		-- Proactive door opening in direction of movement
		check_and_open_forward_doors(current_pos, move_vec, self.abilities, self.object)

		-- Verify immediate step ahead is physically safe (wall, cliff & water guard)
		local step_ok = is_step_safe(current_pos, move_vec, self.abilities)
		if step_ok then
			self.path_state.waypoints = nil
			self.path_state.index = 1

			local speed = self.pursuit_speed or 4.0
			local attack_rng = self.attack_range or 2.0
			local in_melee_contact = (dist <= attack_rng * 0.75)
			if in_melee_contact then
				-- Close contact with target: ease speed down to avoid collision penetration bounce
				speed = math.max(0.0, (dist - 1.1) * 2.5)
			end
			local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
			local y_vel = vel.y
			local in_liquid, is_subm, _, target_vy = check_in_liquid(
				current_pos, self.abilities, self.mob_height
			)

			local cur_n = mob_ai.get_node({
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
				local desired_y = target_pos.y + (self.hover_offset or 0.6)
				local h_dy = desired_y - current_pos.y
				y_vel = math.min(math.max(h_dy * 2.5, -5.0), 4.5)
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

			local face_vec = in_melee_contact and vector.direction(current_pos, target_pos) or move_vec
			if math.abs(face_vec.x) > 0.01 or math.abs(face_vec.z) > 0.01 then
				local target_yaw = core.dir_to_yaw(face_vec)
				local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
				local target_rot = {x = 0, y = target_yaw, z = 0}
				local max_rot_step = (self.max_angular_speed or 7.5) * dtime
				local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 10.0), max_rot_step)
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
					-- Backoff delay on path calculation failure (prevents spamming queue every tick)
					self.path_state.retry_delay = 0.8
					if not has_ground_los then
						self._unreachable_fails = (self._unreachable_fails or 0) + 1
					end
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
		-- Waypoints finished: clear old path and allow immediate re-evaluation
		if waypoints and idx > #waypoints then
			self.path_state.waypoints = nil
			self.path_state.index = 1
			self.path_state.timer = refresh_interval or 0.5
		end

		-- If target is across impassable water with no valid path: disengage, turn around, and wander!
		local is_water_blocking = (glos_reason == "water")
		if not is_water_blocking and not (self.abilities and self.abilities.can_swim) then
			local _, s_reason = is_step_safe(current_pos, vector.direction(current_pos, target_pos), self.abilities)
			if s_reason == "water" then
				is_water_blocking = true
			end
		end
		local water_blocked = not has_ground_los and is_water_blocking and
			not self.is_floating and not (self.abilities and self.abilities.can_swim)
		if water_blocked then
			self._water_blocked_timer = (self._water_blocked_timer or 0) + dtime
			if (self._water_blocked_timer >= 2.0) or ((self._unreachable_fails or 0) >= 2) then
				if self.target and x_mob_core.mob_memory then
					x_mob_core.mob_memory.record_unreachable_target(self, self.target, 12.0)
					x_mob_core.mob_memory.record_blocked_spot(self, current_pos, 10.0)
				end
				self.target = nil
				self.state = "wandering"
				self._water_blocked_timer = 0
				self._unreachable_fails = 0
				if self.path_state then
					self.path_state.waypoints = nil
					self.path_state.index = 1
				end

				-- Compute turnaround vector away from target/water
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
					timer = 4.0 + math.random() * 3.0,
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
				x_mob_core.play_animation(self.object, "walk", {speed = 1.0, loop = true})
				return {moving = true, speed = w_speed, has_los = false}
			end
		else
			self._water_blocked_timer = 0
		end

		-- Active pursuit locomotion while calculating, closing in with LOS, or navigating surfaces:
		if self.path_state.is_calculating or has_los or on_wall_or_ceiling then
			local pursuit_dest = target_pos
			if not has_los and not on_wall_or_ceiling then
				local lkp = mob_memory.get_lkp_target and mob_memory.get_lkp_target(self, 8.0)
				if lkp then
					pursuit_dest = lkp
				end
			end
			local move_vec = vector.direction(current_pos, pursuit_dest)
			local speed = (self.pursuit_speed or 4.0) * 0.75
			local target_above = (target_pos.y - current_pos.y) > 2.5
			local flat_dist = math.sqrt((target_pos.x - current_pos.x)^2 + (target_pos.z - current_pos.z)^2)

			-- If target is high above on ceiling/wall/platform and mob is on the floor:
			if not on_wall_or_ceiling and not self.is_floating and target_above then
				if is_crawler then
					-- Crawlers (Spiders) seeking climbing walls to reach elevated prey:
					if flat_dist > 2.5 then
						-- Approach target's sector from assigned flank angle
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
						-- Underneath or within perimeter: steer outward along flank radial vector to reach perimeter walls
						local flank_angles = {0.0, 1.1, -1.1, 2.8}
						local f_angle = flank_angles[self._flank_slot] or 0.0
						local p_yaw = safe_get_yaw(self.target) or 0
						local angle = p_yaw + f_angle
						move_vec = {x = -math.sin(angle), y = 0, z = math.cos(angle)}
					end
				else
					-- Non-crawlers (ground mobs, flyers) targeting elevated prey:
					-- Maintain tactical standoff perimeter surrounding the base instead of circling!
					local standoff_dist = self._flank_dist or 3.2
					if flat_dist > standoff_dist + 0.6 then
						-- Approach standoff ring
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
						-- Too close to base: back up to standoff perimeter
						if flat_dist > 0.1 then
							move_vec = {
								x = (current_pos.x - target_pos.x) / flat_dist,
								y = 0,
								z = (current_pos.z - target_pos.z) / flat_dist,
							}
						else
							-- Directly centered underneath: back up along flank sector
							local flank_angles = {0.0, 1.1, -1.1, 2.8}
							local f_angle = flank_angles[self._flank_slot] or 0.0
							local p_yaw = safe_get_yaw(self.target) or 0
							local angle = p_yaw + f_angle
							move_vec = {x = -math.sin(angle), y = 0, z = math.cos(angle)}
						end
					else
						-- Position established: hold standoff ground and face target
						speed = 0.0
						move_vec = {
							x = (target_pos.x - current_pos.x) / (flat_dist > 0.01 and flat_dist or 1),
							y = 0,
							z = (target_pos.z - current_pos.z) / (flat_dist > 0.01 and flat_dist or 1),
						}
					end
				end
			end

			-- Fallback Wall Acquisition: if crawler on floor contacts a solid wall block in front, immediately engage climbing!
			if is_crawler and not on_wall_or_ceiling and not self.is_floating then
				local check_pos = {
					x = math.floor(current_pos.x + move_vec.x * 0.95 + 0.5),
					y = math.floor(current_pos.y + 0.5),
					z = math.floor(current_pos.z + move_vec.z * 0.95 + 0.5),
				}
				local c_node = mob_ai.get_node(check_pos)
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
						self.object:set_properties({
							collisionbox = {-0.20, -0.20, -0.20, 0.20, 0.20, 0.20},
							selectionbox = {-0.85, -0.65, -0.85, 0.85, 0.65, 0.85},
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
					local max_rot_step = (self.max_angular_speed or 7.5) * dtime
					local smoothed_rot = interpolate_rotation(cur_rot, up_rot, math.min(1.0, dtime * 10.0), max_rot_step)
					self._cur_rot = smoothed_rot
					safe_set_rotation(self.object, smoothed_rot)
					return {moving = true, speed = speed, has_los = has_los}
				end
			end

			-- Obstacle collision guard: if non-crawler lacks direct LOS or corridor clearance
			-- and faces a solid wall/ceiling obstruction immediately ahead, flag facing_wall
			-- and trigger A* path search around obstacle
			local facing_wall = false
			if not is_crawler and not on_wall_or_ceiling and (not has_los or not corridor_clear) then
				local check_x = math.floor(current_pos.x + move_vec.x * 0.85 + 0.5)
				local check_z = math.floor(current_pos.z + move_vec.z * 0.85 + 0.5)
				local foot_y = math.floor(current_pos.y + 0.5)
				local c_node = mob_ai.get_node({x = check_x, y = foot_y, z = check_z})
				local c_def = core.registered_nodes[c_node.name]
				local h_node = mob_ai.get_node({x = check_x, y = foot_y + 1, z = check_z})
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
					if self.path_state then
						self.path_state.timer = 999.0
						self.path_state.retry_delay = 0
					end
				end
			end

			local surf_norm = (adj_surf and adj_surf.normal) or
				((self._cur_rot and math.abs(self._cur_rot.z) > 2.0) and {x = 0, y = -1, z = 0} or {x = 0, y = 0, z = -1})
			local sep_norm = on_wall_or_ceiling and surf_norm or {x = 0, y = 1, z = 0}
			local sep = calculate_separation_force(self, current_pos, dtime, on_wall_or_ceiling, sep_norm)

			if on_wall_or_ceiling then
				-- Surface Tangent Projection: strictly prevent 3D velocity into open air!
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

				-- Maintain firm grip against rock face with gentle inward adherence bias (-surf_norm * 0.22)
				self.object:set_velocity({
					x = tan_x - surf_norm.x * 0.22 + sep.x,
					y = tan_y - surf_norm.y * 0.22 + sep.y,
					z = tan_z - surf_norm.z * 0.22 + sep.z,
				})

				if tan_len > 0.05 then
					local move_dir = {x = tan_x, y = tan_y, z = tan_z}
					local target_rot = dir_to_surface_rotation(move_dir, surf_norm)
					local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
					local max_rot_step = (self.max_angular_speed or 7.5) * dtime
					local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 10.0), max_rot_step)
					self._cur_rot = smoothed_rot
					safe_set_rotation(self.object, smoothed_rot)
				end
			elseif self.is_floating then
				safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
				local desired_y = target_pos.y + (self.hover_offset or 0.6)
				local h_dy = desired_y - current_pos.y
				local y_vel = math.min(math.max(h_dy * 2.5, -5.0), 4.5)
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
					if math.abs(move_vec.x) > 0.01 or math.abs(move_vec.z) > 0.01 then
						local target_yaw = core.dir_to_yaw(move_vec)
						local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
						local target_rot = {x = 0, y = target_yaw, z = 0}
						local max_rot_step = (self.max_angular_speed or 7.5) * dtime
						local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 10.0), max_rot_step)
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
				else
					-- Forward step is unsafe (cliff, wall or obstacle ahead)!
					-- Invalidate Tier 1 ground line of sight and force immediate A* path search around hazard!
					if self.path_state then
						self.path_state.timer = 999.0
						self.path_state.retry_delay = 0
					end

					-- Probe lateral directions (+90 deg, -90 deg)
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

						-- Flank bias: Slot 2 prefers left, Slot 3 prefers right
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
						-- No lateral contour possible: turn around and retreat from the edge!
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
							-- Completely blocked in all directions: halt completely and record deadlock
							mob_memory.record_blocked_spot(self, current_pos, 8.0)
							self.object:set_velocity({x = 0, y = y_vel, z = 0})
							return {moving = false, speed = 0, has_los = false}
						end
					end
				end
			end

			if not on_wall_or_ceiling then
				if math.abs(move_vec.x) > 0.01 or math.abs(move_vec.z) > 0.01 then
					local target_yaw = core.dir_to_yaw(move_vec)
					local cur_rot = self._cur_rot or {x = 0, y = safe_get_yaw(self.object) or 0, z = 0}
					local target_rot = {x = 0, y = target_yaw, z = 0}
					local max_rot_step = (self.max_angular_speed or 7.5) * dtime
					local smoothed_rot = interpolate_rotation(cur_rot, target_rot, math.min(1.0, dtime * 10.0), max_rot_step)
					self._cur_rot = smoothed_rot
					safe_set_rotation(self.object, smoothed_rot)
				end
			end
			return {moving = true, speed = speed, has_los = has_los}
		end

		-- End of path reached with no line of sight or target direction
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
			self.object:set_velocity({x = 0, y = vel.y, z = 0})
		else
			safe_set_acceleration(self.object, {x = 0, y = 0, z = 0})
			self.object:set_velocity({x = 0, y = 0, z = 0})
		end
		return {moving = false, speed = 0, has_los = false}
	end
end

--- Entity Registration Helper
--- Wraps standard mob definition with optimized pathfinding motor controller
---@param name string Entity technical name (e.g. "x_mobs:smart_zombie")
---@param def table Entity definition table
function mob_ai.register_pathfinding_mob(name, def)
	def.initial_properties = def.initial_properties or {}
	local props = def.initial_properties
	local engine_props = {
		"hp_max", "physical", "collide_with_objects", "weight", "collisionbox",
		"selectionbox", "pointable", "visual", "visual_size", "mesh", "textures",
		"colors", "spritediv", "initial_sprite_basepos", "is_visible",
		"makes_footstep_sound", "automatic_rotate", "stepheight", "backface_culling",
		"glow", "nametag", "nametag_color", "nametag_bgcolor", "infotext",
		"static_save", "shaded", "show_on_minimap", "eye_height", "zoom_fov",
		"use_texture_alpha", "damage_texture_modifier"
	}
	for i = 1, #engine_props do
		local prop = engine_props[i]
		if def[prop] ~= nil then
			if props[prop] == nil then
				props[prop] = def[prop]
			end
			def[prop] = nil
		end
	end

	local old_on_step = def.on_step

	def.on_step = function(self, dtime, moveresult)
		-- Execute movement and steering
		mob_ai.update_navigation(self, dtime)

		-- Execute custom mob logic
		if old_on_step then
			old_on_step(self, dtime, moveresult)
		end
	end

	core.register_entity(name, def)
end

--- Executes a safe kiting retreat away from a target position with cliff/obstacle guard
---@param self table Mob instance
---@param target_pos Vector Threat / target world position
---@param speed? number Movement speed (default: self.pursuit_speed or self.walk_speed or 3.0)
---@return boolean success True if a safe retreat direction was found and applied
function mob_ai.retreat_from(self, target_pos, speed)
	local pos = self.object and self.object:get_pos()
	if not pos or not target_pos then return false end

	local away = vector.direction(target_pos, pos)
	away.y = 0
	local a_len = math.sqrt(away.x * away.x + away.z * away.z)
	if a_len <= 0.01 then return false end

	away = {x = away.x / a_len, y = 0, z = away.z / a_len}
	local vel = self.object:get_velocity() or {x = 0, y = 0, z = 0}
	local k_speed = speed or self.pursuit_speed or self.walk_speed or 3.0

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
		{can_swim = true, can_crawl = false, disallow_water = false} or
		{can_swim = false, can_crawl = false, disallow_water = true}

	local chosen_dir = nil
	for i = 1, #candidates do
		local cand = candidates[i]
		if is_step_safe(pos, cand, abilities, 1) then
			local pos2 = {x = pos.x + cand.x * 1.2, y = pos.y, z = pos.z + cand.z * 1.2}
			if is_step_safe(pos2, cand, abilities, 1) then
				chosen_dir = cand
				break
			elseif not chosen_dir then
				chosen_dir = cand
			end
		end
	end

	if chosen_dir then
		local y_vel = in_water and water_vy or math.min(0, vel.y)
		if not in_water and not self.is_floating then
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end
		self.object:set_velocity({
			x = chosen_dir.x * k_speed,
			y = y_vel,
			z = chosen_dir.z * k_speed,
		})
		self.object:set_yaw(core.dir_to_yaw(vector.direction(pos, target_pos)))
		return true
	else
		local y_vel = in_water and water_vy or math.min(0, vel.y)
		if not in_water and not self.is_floating then
			safe_set_acceleration(self.object, {x = 0, y = -9.81, z = 0})
		end
		self.object:set_velocity({x = 0, y = y_vel, z = 0})
		self.object:set_yaw(core.dir_to_yaw(vector.direction(pos, target_pos)))
		return false
	end
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
	local nearest_dist = max_dist
	local nearest_player = nil

	local players = core.get_connected_players()
	for i = 1, #players do
		local p = players[i]
		if utils.is_player_alive(p) then
			local unreachable = self.memory and mob_memory and
				mob_memory.is_target_unreachable(self, p)
			if not unreachable then
				local ppos = p:get_pos()
				if ppos then
					local dist = vector.distance(pos, ppos)
					if dist < nearest_dist then
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
		if x_mob_core and x_mob_core.animator then
			x_mob_core.animator.play(self.object, m_anim, {speed = speed, loop = true})
		end
	else
		local is_fleeing = (self.state == "fleeing") or (self.panic_timer and self.panic_timer > 0)
		if not is_fleeing and self.state ~= "regrouping" then
			self.state = i_anim
		end
		if x_mob_core and x_mob_core.animator then
			if is_fleeing and m_anim == "flee" then
				x_mob_core.animator.play(self.object, m_anim, {speed = speed, loop = true})
			else
				x_mob_core.animator.play(self.object, i_anim, {speed = 1.0, loop = true})
			end
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
		local coordination = x_mob_core and x_mob_core.pack and x_mob_core.pack.coordination
		if coordination then
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
	end

	return mob_ai.step_move_or_idle(self, dtime, walk_anim or "walk", 1.0, idle_anim or "idle")
end

mob_ai.handle_mob_movement = handle_mob_movement
mob_ai.find_adjacent_surface = find_adjacent_surface
mob_ai.is_step_safe = is_step_safe
mob_ai.check_ground_line_of_sight = check_ground_line_of_sight
mob_ai.check_corridor_line_of_sight = check_corridor_line_of_sight
mob_ai.interpolate_rotation = interpolate_rotation
mob_ai.dir_to_surface_rotation = dir_to_surface_rotation
mob_ai.handle_mob_fleeing = handle_mob_fleeing
mob_ai.apply_liquid_buoyancy = apply_liquid_buoyancy
mob_ai.check_in_liquid = check_in_liquid
mob_ai.is_door_open = is_door_open
mob_ai.is_openable_door = is_openable_door
mob_ai.try_open_door = try_open_door
mob_ai.mob_memory = mob_memory
mob_ai.has_wall_collision = has_wall_collision
mob_ai.is_valid_stand_pos = is_valid_stand_pos
mob_ai.halt_horizontal_velocity = halt_horizontal_velocity

return mob_ai
