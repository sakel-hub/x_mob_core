--[[
	x_mob_core - 3D Surface Kinematics & Orientation Subsystem
	Surface adherence, climbing rotations, wall/ceiling normal estimation,
	Euler angle interpolations matching Luanti extrinsic Z-X-Y conventions.
]]

---@class SurfaceSubsystem
local surface = {}

local modpath = core.get_modpath("x_mob_core") or "."
local node_cache = dofile(modpath .. "/motor/node_cache.lua")

--- Computes 3D Euler angles (pitch, yaw, roll in radians) matching Luanti extrinsic Z-X-Y order
---@param dir Vector Movement direction
---@param up Vector Surface normal
---@return Vector Euler rotation in radians {x = pitch, y = yaw, z = roll}
function surface.dir_to_surface_rotation(dir, up)
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
---@param max_delta? number Maximum angular delta allowed per step (radians)
---@return Vector
function surface.interpolate_rotation(cur_rot, target_rot, factor, max_delta)
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
function surface.interpolate_vector(v1, v2, factor)
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
---@param preferred_normal? Vector Previous surface normal for geometric hysteresis
---@return table|nil surface_info {has_surface = boolean, normal = Vector, surface_type = string}
function surface.find_adjacent_surface(pos, preferred_normal)
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
			local node = node_cache.get_node(check_npos)
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
		local node = node_cache.get_node(npos)
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
		{-0.75, 0, -0.75, {x = -diag_n, y = 0, z = diag_n}, "wall"},
	}

	for i = 1, #diag_checks do
		local dc = diag_checks[i]
		local npos = {
			x = math.floor(cx + dc[1] + 0.5),
			y = math.floor(cy + dc[2] + 0.5),
			z = math.floor(cz + dc[3] + 0.5),
		}
		local node = node_cache.get_node(npos)
		local def = core.registered_nodes[node.name]
		if def and def.walkable then
			return {has_surface = true, normal = dc[4], surface_type = dc[5]}
		end
	end

	return nil
end

return surface
