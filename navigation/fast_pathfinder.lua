--[[
	fast_pathfinder.lua - Zero-Overhead VoxelManip A* Pathfinding Engine
	- Direct 1D Stride Hashing (Zero core.hash_node_position or C-bridge overhead)
	- Pre-allocated Generational Stamped Arrays (Zero table allocations per search)
	- Time-Sliced Coroutine Execution with strict 1.5ms per-tick CPU budget
	- Full Contextual Traversal: Door opening, Ladder climbing, Swimming (pursuit-gated)
	- Optimized for LuaJIT Trace Compilation
]]

local MinHeap = dofile(core.get_modpath("x_mob_core") .. "/navigation/min_heap.lua")
local path_cache = dofile(core.get_modpath("x_mob_core") .. "/navigation/path_cache.lua")

---@class FastPathfinder
local fast_pathfinder = {}

-- -------------------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
-- -------------------------------------------------------------------------
local MAX_TICK_BUDGET_US = 1500 -- 1.5 milliseconds per server step
local BATCH_EXPANSIONS = 64      -- Number of node expansions before checking time budget
local MAX_SEARCH_RADIUS = 42     -- Maximum horizontal bounding radius (supports large caverns)
local MAX_VERTICAL_PAD = 24      -- Maximum vertical bounding padding (Supports high cavern ceilings)
local DEFAULT_MOB_HEIGHT = 2     -- Vertical clearance in nodes

-- -------------------------------------------------------------------------
-- PRE-ALLOCATED REUSABLE BUFFERS & STAMPED ARRAYS
-- -------------------------------------------------------------------------
local shared_vm_buffer = {}
local g_scores = {}
local came_from = {}
local came_from_stamp = {}
local visited_stamp = {}
local closed_stamp = {}
local current_stamp = 0

-- Central MinHeap instance
local open_set = MinHeap.new(1024)

-- Active coroutine search queue and sequential worker
local active_searches = {}
local search_queue_head = 1
local search_queue_tail = 0
local current_active_co = nil

--- Fast Octile Heuristic with vertical cost
---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@return number
local function calculate_heuristic(x1, y1, z1, x2, y2, z2)
	local dx = math.abs(x1 - x2)
	local dy = math.abs(y1 - y2)
	local dz = math.abs(z1 - z2)

	local h_min = (dx < dz) and dx or dz
	local h_max = (dx > dz) and dx or dz

	-- 1.414 diagonal factor, 1.0 straight, 1.2 vertical weight
	return (h_max - h_min) + 1.4142 * h_min + dy * 1.2
end

--- 3D Octile Heuristic for Surface and 3D Traversal
---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@return number
local function calculate_heuristic_3d(x1, y1, z1, x2, y2, z2)
	local dx = math.abs(x1 - x2)
	local dy = math.abs(y1 - y2)
	local dz = math.abs(z1 - z2)

	local dmin = math.min(dx, math.min(dy, dz))
	local dmax = math.max(dx, math.max(dy, dz))
	local dmid = dx + dy + dz - dmin - dmax

	-- 1.0 straight, 1.4142 planar diagonal, 1.732 3D corner
	return (dmax - dmid) + 1.4142 * (dmid - dmin) + 1.73205 * dmin
end

--- Unpacks a 1D VoxelArea index into 3D world coordinates
---@param idx integer
---@param emin Vector
---@param ystride integer
---@param zstride integer
---@return integer x, integer y, integer z
local function unpack_index(idx, emin, ystride, zstride)
	local rem = idx - 1
	local z = math.floor(rem / zstride)
	rem = rem - z * zstride
	local y = math.floor(rem / ystride)
	local x = rem - y * ystride

	return x + emin.x, y + emin.y, z + emin.z
end

--- Core A* Search Generator (Executed inside a coroutine)
---@param start_pos Vector
---@param target_pos Vector
---@param abilities table
---@param mob_height integer
---@return table|nil waypoints
local function astar_search(start_pos, target_pos, abilities, mob_height)
	if not path_cache.initialized then
		path_cache.init()
	end

	local s_x = math.floor(start_pos.x + 0.5)
	local s_y = math.floor(start_pos.y + 0.5)
	local s_z = math.floor(start_pos.z + 0.5)

	local t_x = math.floor(target_pos.x + 0.5)
	local t_y = math.floor(target_pos.y + 0.5)
	local t_z = math.floor(target_pos.z + 0.5)

	-- Direct reach check
	if s_x == t_x and s_y == t_y and s_z == t_z then
		return { {x = t_x, y = t_y, z = t_z, normal = {x = 0, y = 1, z = 0}, surface_type = "floor"} }
	end

	-- Compute Bounding Box with Padding
	local can_crawl = abilities.can_crawl == true
	local is_floating = abilities.is_floating == true
	local pad_h = 18
	local pad_v = (can_crawl or is_floating) and 12 or 8
	local min_x = math.min(s_x, t_x) - pad_h
	local max_x = math.max(s_x, t_x) + pad_h
	local min_y = math.min(s_y, t_y) - pad_v
	local max_y = math.max(s_y, t_y) + pad_v
	local min_z = math.min(s_z, t_z) - pad_h
	local max_z = math.max(s_z, t_z) + pad_h

	-- Enforce maximum search limits with boundary clamping
	if (max_x - min_x) > (MAX_SEARCH_RADIUS * 2) then
		local mid_x = math.floor((s_x + t_x) * 0.5)
		min_x = mid_x - MAX_SEARCH_RADIUS
		max_x = mid_x + MAX_SEARCH_RADIUS
	end
	if (max_z - min_z) > (MAX_SEARCH_RADIUS * 2) then
		local mid_z = math.floor((s_z + t_z) * 0.5)
		min_z = mid_z - MAX_SEARCH_RADIUS
		max_z = mid_z + MAX_SEARCH_RADIUS
	end
	if (max_y - min_y) > (MAX_VERTICAL_PAD * 2) then
		local mid_y = math.floor((s_y + t_y) * 0.5)
		min_y = mid_y - MAX_VERTICAL_PAD
		max_y = mid_y + MAX_VERTICAL_PAD
	end

	local min_edge = {x = min_x, y = min_y, z = min_z}
	local max_edge = {x = max_x, y = max_y, z = max_z}

	-- Read map block into VoxelManip buffer
	local vm = core.get_voxel_manip(min_edge, max_edge)
	local emin, emax = vm:read_from_map(min_edge, max_edge)
	local data = vm:get_data(shared_vm_buffer)

	local x_size = emax.x - emin.x + 1
	local y_size = emax.y - emin.y + 1
	local ystride = x_size
	local zstride = x_size * y_size

	-- Helper closure to compute 1D index
	local function get_idx(x, y, z)
		return (z - emin.z) * zstride + (y - emin.y) * ystride + (x - emin.x) + 1
	end

	local start_idx = get_idx(s_x, s_y, s_z)
	local target_idx = get_idx(t_x, t_y, t_z)

	-- Precompute Neighbor Strides
	local stride_e = 1
	local stride_w = -1
	local stride_n = zstride
	local stride_s = -zstride
	local stride_u = ystride
	local stride_d = -ystride

	local c_walkable = path_cache.walkable
	local c_climbable = path_cache.climbable
	local c_swimable = path_cache.swimable
	local c_openable = path_cache.openable
	local c_cost = path_cache.base_cost
	local c_hazard = path_cache.is_hazard
	local c_tall = path_cache.tall_obstacle

	local can_climb = abilities.can_climb == true
	local can_swim = (abilities.can_swim == true) and not (abilities and abilities.disallow_water == true)
	local can_open_doors = abilities.can_open_doors == true
	local height = math.max(1, math.ceil(mob_height or DEFAULT_MOB_HEIGHT))

	-- If target node itself is solid stone, lacks headroom, or is water for non-swimmers:
	-- snap to adjacent passable node with adequate headroom
	local target_blocked = c_walkable[data[target_idx]] or (not can_swim and c_swimable[data[target_idx]])
	if not target_blocked and not can_crawl then
		for h = 1, height - 1 do
			if (t_y + h) <= emax.y and c_walkable[data[target_idx + h * stride_u]] then
				target_blocked = true
				break
			end
		end
	end

	if target_blocked then
		local card_dirs = {
			{0, -1, 0, stride_d}, {0, 1, 0, stride_u},
			{1, 0, 0, stride_e}, {-1, 0, 0, stride_w},
			{0, 0, 1, stride_n}, {0, 0, -1, stride_s}
		}
		for i = 1, #card_dirs do
			local cd = card_dirs[i]
			local ax, ay, az = t_x + cd[1], t_y + cd[2], t_z + cd[3]
			if ax >= emin.x and ax <= emax.x and ay >= emin.y and ay <= emax.y and az >= emin.z and az <= emax.z then
				local a_idx = target_idx + cd[4]
				if not c_walkable[data[a_idx]] and not c_hazard[data[a_idx]] and
				   not (not can_swim and c_swimable[data[a_idx]]) then
					local a_head_clear = true
					if not can_crawl then
						for h = 1, height - 1 do
							if (ay + h) <= emax.y and c_walkable[data[a_idx + h * stride_u]] then
								a_head_clear = false
								break
							end
						end
					end
					if a_head_clear then
						t_x, t_y, t_z = ax, ay, az
						target_idx = a_idx
						break
					end
				end
			end
		end
	end

	-- Start Node Snapping: If starting inside a solid block (clipped corner, embedded on spawn):
	if c_walkable[data[start_idx]] then
		local card_dirs = {
			{0, 1, 0, stride_u}, {1, 0, 0, stride_e}, {-1, 0, 0, stride_w},
			{0, 0, 1, stride_n}, {0, 0, -1, stride_s}, {0, -1, 0, stride_d}
		}
		for i = 1, #card_dirs do
			local cd = card_dirs[i]
			local ax, ay, az = s_x + cd[1], s_y + cd[2], s_z + cd[3]
			if ax >= emin.x and ax <= emax.x and ay >= emin.y and ay <= emax.y and az >= emin.z and az <= emax.z then
				local a_idx = start_idx + cd[4]
				if not c_walkable[data[a_idx]] then
					s_x, s_y, s_z = ax, ay, az
					start_idx = a_idx
					break
				end
			end
		end
	end

	-- Start & Target Surface Snapping for Wall/Ceiling Crawlers:
	if can_crawl then

		local has_start_surface = (s_y - 1 >= emin.y and c_walkable[data[start_idx + stride_d]]) or
		                          (s_y + 1 <= emax.y and c_walkable[data[start_idx + stride_u]]) or
		                          (s_x + 1 <= emax.x and c_walkable[data[start_idx + stride_e]]) or
		                          (s_x - 1 >= emin.x and c_walkable[data[start_idx + stride_w]]) or
		                          (s_z + 1 <= emax.z and c_walkable[data[start_idx + stride_n]]) or
		                          (s_z - 1 >= emin.z and c_walkable[data[start_idx + stride_s]])

		if not has_start_surface then
			local best_snap_x, best_snap_y, best_snap_z = nil, nil, nil
			local best_snap_dist = 999.0

			-- Check below for floor (up to 4 blocks down)
			for dy = 1, 4 do
				local cy = s_y - dy
				if cy >= emin.y then
					local c_idx = get_idx(s_x, cy, s_z)
					if c_walkable[data[c_idx]] then
						local snap_y = cy + 1
						if snap_y <= emax.y and not c_walkable[data[get_idx(s_x, snap_y, s_z)]] then
							best_snap_x = s_x
							best_snap_y = snap_y
							best_snap_z = s_z
							best_snap_dist = dy
							break
						end
					end
				end
			end

			-- Check cardinal horizontals for walls (up to 3 blocks)
			local card_dirs = {
				{1, 0, stride_e}, {-1, 0, stride_w}, {0, 1, stride_n}, {0, -1, stride_s}
			}
			for i = 1, #card_dirs do
				local cd = card_dirs[i]
				for step = 1, 3 do
					if step < best_snap_dist then
						local cx = s_x + cd[1] * step
						local cz = s_z + cd[2] * step
						if cx >= emin.x and cx <= emax.x and cz >= emin.z and cz <= emax.z then
							local c_idx = get_idx(cx, s_y, cz)
							if c_walkable[data[c_idx]] then
								local snap_x = cx - cd[1]
								local snap_z = cz - cd[2]
								if not c_walkable[data[get_idx(snap_x, s_y, snap_z)]] then
									best_snap_x = snap_x
									best_snap_y = s_y
									best_snap_z = snap_z
									best_snap_dist = step
									break
								end
							end
						end
					end
				end
			end

			if best_snap_x and best_snap_y and best_snap_z then
				s_x = best_snap_x
				s_y = best_snap_y
				s_z = best_snap_z
				start_idx = get_idx(s_x, s_y, s_z)
			end
		end

		-- Target surface snapping: if player is suspended in mid-air, snap target to nearest surface node
		local has_target_surface = (t_y - 1 >= emin.y and c_walkable[data[target_idx + stride_d]]) or
		                           (t_y + 1 <= emax.y and c_walkable[data[target_idx + stride_u]]) or
		                           (t_x + 1 <= emax.x and c_walkable[data[target_idx + stride_e]]) or
		                           (t_x - 1 >= emin.x and c_walkable[data[target_idx + stride_w]]) or
		                           (t_z + 1 <= emax.z and c_walkable[data[target_idx + stride_n]]) or
		                           (t_z - 1 >= emin.z and c_walkable[data[target_idx + stride_s]])

		if not has_target_surface then
			local best_snap_x, best_snap_y, best_snap_z = nil, nil, nil
			local best_snap_dist = 999.0

			-- Check above for ceiling (up to 4 blocks)
			for dy = 1, 4 do
				local cy = t_y + dy
				if cy <= emax.y then
					local c_idx = get_idx(t_x, cy, t_z)
					if c_walkable[data[c_idx]] then
						local snap_y = cy - 1
						if snap_y >= emin.y and not c_walkable[data[get_idx(t_x, snap_y, t_z)]] then
							best_snap_x = t_x
							best_snap_y = snap_y
							best_snap_z = t_z
							best_snap_dist = dy
							break
						end
					end
				end
			end

			-- Check below for floor/ledge (up to 3 blocks) if closer than ceiling
			for dy = 1, 3 do
				local cy = t_y - dy
				if cy >= emin.y and dy < best_snap_dist then
					local c_idx = get_idx(t_x, cy, t_z)
					if c_walkable[data[c_idx]] then
						local snap_y = cy + 1
						if snap_y <= emax.y and not c_walkable[data[get_idx(t_x, snap_y, t_z)]] then
							best_snap_x = t_x
							best_snap_y = snap_y
							best_snap_z = t_z
							best_snap_dist = dy
							break
						end
					end
				end
			end

			-- Check cardinal horizontals for walls (up to 3 blocks)
			local card_dirs = {
				{1, 0, stride_e}, {-1, 0, stride_w}, {0, 1, stride_n}, {0, -1, stride_s}
			}
			for i = 1, #card_dirs do
				local cd = card_dirs[i]
				for step = 1, 3 do
					if step < best_snap_dist then
						local cx = t_x + cd[1] * step
						local cz = t_z + cd[2] * step
						if cx >= emin.x and cx <= emax.x and cz >= emin.z and cz <= emax.z then
							local c_idx = get_idx(cx, t_y, cz)
							if c_walkable[data[c_idx]] then
								local snap_x = cx - cd[1]
								local snap_z = cz - cd[2]
								if not c_walkable[data[get_idx(snap_x, t_y, snap_z)]] then
									best_snap_x = snap_x
									best_snap_y = t_y
									best_snap_z = snap_z
									best_snap_dist = step
									break
								end
							end
						end
					end
				end
			end

			if best_snap_x and best_snap_y and best_snap_z then
				t_x = best_snap_x
				t_y = best_snap_y
				t_z = best_snap_z
				target_idx = get_idx(t_x, t_y, t_z)
			end
		end
	end

	-- Increment generational stamp for O(1) array reset
	current_stamp = current_stamp + 1
	local stamp = current_stamp

	open_set:clear()

	g_scores[start_idx] = 0.0
	visited_stamp[start_idx] = stamp
	came_from[start_idx] = 0
	came_from_stamp[start_idx] = stamp

	local base_heuristic = (can_crawl or is_floating) and calculate_heuristic_3d or calculate_heuristic
	local path_seed = (abilities and abilities.path_seed) or 0
	local flank_slot = (abilities and abilities.flank_slot) or 1

	-- Flank geometry precomputation (zero allocation per node expansion)
	local fdx = t_x - s_x
	local fdz = t_z - s_z
	local fdist = math.sqrt(fdx * fdx + fdz * fdz)
	local u_fwd_x = 0.0
	local u_fwd_z = 0.0
	local u_left_x = 0.0
	local u_left_z = 0.0
	if fdist > 1.0 then
		u_fwd_x = fdx / fdist
		u_fwd_z = fdz / fdist
		u_left_x = -u_fwd_z
		u_left_z = u_fwd_x
	end

	local function heuristic_fn(x1, y1, z1, x2, y2, z2)
		local h = base_heuristic(x1, y1, z1, x2, y2, z2)

		if fdist > 1.5 and flank_slot > 1 then
			local rx = x1 - s_x
			local rz = z1 - s_z
			local proj_fwd = rx * u_fwd_x + rz * u_fwd_z
			if proj_fwd > 0.0 and proj_fwd < fdist then
				local progress = proj_fwd / fdist
				local envelope = math.sin(math.pi * progress)
				local lateral_left = rx * u_left_x + rz * u_left_z

				if flank_slot == 2 then
					-- Left Flank: reward leftward deviation (+lateral_left), penalize rightward
					h = h - lateral_left * 0.25 * envelope
				elseif flank_slot == 3 then
					-- Right Flank: reward rightward deviation (-lateral_left), penalize leftward
					h = h + lateral_left * 0.25 * envelope
				elseif flank_slot == 4 then
					if can_crawl or is_floating then
						-- Vertical Ceiling/High Wall/Air Flank: reward upward elevation gain
						local ascent = y1 - s_y
						h = h - ascent * 0.35 * envelope
					else
						-- Wide Flank for ground mobs
						local wide_sign = (path_seed % 2 == 0) and 1.0 or -1.0
						h = h + wide_sign * lateral_left * 0.4 * envelope
					end
				end
			end
		end

		if path_seed ~= 0 then
			local perturb = math.sin(x1 * 0.41 + y1 * 0.29 + z1 * 0.53 + path_seed * 1.618) * 0.03
			h = h + perturb
		end

		if h < 0.0 then h = 0.0 end
		return h
	end

	local h_start = heuristic_fn(s_x, s_y, s_z, t_x, t_y, t_z)
	open_set:push(start_idx, h_start)

	-- Pre-allocated neighbor offsets (zero allocation inside loop)
	local ground_neighbor_offsets = {
		{ 1, 0,  0, stride_e, false, 1.0},
		{-1, 0,  0, stride_w, false, 1.0},
		{ 0, 0,  1, stride_n, false, 1.0},
		{ 0, 0, -1, stride_s, false, 1.0},
		{ 1, 0,  1, stride_e + stride_n, true, 1.4142},
		{-1, 0,  1, stride_w + stride_n, true, 1.4142},
		{ 1, 0, -1, stride_e + stride_s, true, 1.4142},
		{-1, 0, -1, stride_w + stride_s, true, 1.4142},
	}

	local ladder_swim_neighbor_offsets = {
		{ 1, 0,  0, stride_e, false, 1.0},
		{-1, 0,  0, stride_w, false, 1.0},
		{ 0, 0,  1, stride_n, false, 1.0},
		{ 0, 0, -1, stride_s, false, 1.0},
		{ 1, 0,  1, stride_e + stride_n, true, 1.4142},
		{-1, 0,  1, stride_w + stride_n, true, 1.4142},
		{ 1, 0, -1, stride_e + stride_s, true, 1.4142},
		{-1, 0, -1, stride_w + stride_s, true, 1.4142},
		{ 0,  1, 0, stride_u, false, 1.0},
		{ 0, -1, 0, stride_d, false, 1.0},
	}

	local crawl_neighbor_offsets = {
		-- 6 Orthogonal steps
		{ 1,  0,  0, stride_e, false, 1.0},
		{-1,  0,  0, stride_w, false, 1.0},
		{ 0,  0,  1, stride_n, false, 1.0},
		{ 0,  0, -1, stride_s, false, 1.0},
		{ 0,  1,  0, stride_u, false, 1.05},
		{ 0, -1,  0, stride_d, false, 1.0},
		-- 4 Horizontal planar diagonals
		{ 1,  0,  1, stride_e + stride_n, true, 1.4142},
		{-1,  0,  1, stride_w + stride_n, true, 1.4142},
		{ 1,  0, -1, stride_e + stride_s, true, 1.4142},
		{-1,  0, -1, stride_w + stride_s, true, 1.4142},
		-- 4 Vertical X-Y planar diagonals
		{ 1,  1,  0, stride_e + stride_u, true, 1.4142},
		{-1,  1,  0, stride_w + stride_u, true, 1.4142},
		{ 1, -1,  0, stride_e + stride_d, true, 1.4142},
		{-1, -1,  0, stride_w + stride_d, true, 1.4142},
		-- 4 Vertical Y-Z planar diagonals
		{ 0,  1,  1, stride_u + stride_n, true, 1.4142},
		{ 0,  1, -1, stride_u + stride_s, true, 1.4142},
		{ 0, -1,  1, stride_d + stride_n, true, 1.4142},
		{ 0, -1, -1, stride_d + stride_s, true, 1.4142},
		-- 8 3D Corner diagonals for uneven surfaces and stalactites
		{ 1,  1,  1, stride_e + stride_u + stride_n, true, 1.732},
		{-1,  1,  1, stride_w + stride_u + stride_n, true, 1.732},
		{ 1, -1,  1, stride_e + stride_d + stride_n, true, 1.732},
		{-1, -1,  1, stride_w + stride_d + stride_n, true, 1.732},
		{ 1,  1, -1, stride_e + stride_u + stride_s, true, 1.732},
		{-1,  1, -1, stride_w + stride_u + stride_s, true, 1.732},
		{ 1, -1, -1, stride_e + stride_d + stride_s, true, 1.732},
		{-1, -1, -1, stride_w + stride_d + stride_s, true, 1.732},
	}

	local expansions = 0
	local found = false
	local best_fallback_idx = start_idx
	local best_fallback_h = h_start

	-- ---------------------------------------------------------------------
	-- MAIN A* EXPANSION LOOP
	-- ---------------------------------------------------------------------
	while not open_set:is_empty() do
		expansions = expansions + 1
		if (expansions % BATCH_EXPANSIONS) == 0 then
			-- Time-slice yield back to scheduler
			coroutine.yield("slice")
		end

		local curr_idx, _ = open_set:pop()
		if not curr_idx then break end

		if closed_stamp[curr_idx] ~= stamp then
			closed_stamp[curr_idx] = stamp

			local cx, cy, cz = unpack_index(curr_idx, emin, ystride, zstride)

			-- Goal condition: exact target reached
			if curr_idx == target_idx then
				found = true
				break
			end

			local curr_g = g_scores[curr_idx]
			local curr_cid = data[curr_idx]
			local is_on_ladder = can_climb and (c_climbable[curr_cid] == true)
			local is_in_water = can_swim and (c_swimable[curr_cid] == true)

			local neighbor_offsets = (can_crawl or is_floating) and crawl_neighbor_offsets or
				((is_on_ladder or is_in_water) and ladder_swim_neighbor_offsets or ground_neighbor_offsets)

			for i = 1, #neighbor_offsets do
				local off = neighbor_offsets[i]
				local nx = cx + off[1]
				local ny = cy + off[2]
				local nz = cz + off[3]

				-- Verify within VoxelManip active bounds
				if nx >= emin.x and nx <= emax.x and
				   ny >= emin.y and ny <= emax.y and
				   nz >= emin.z and nz <= emax.z then

					local n_idx = curr_idx + off[4]
					local n_cid = data[n_idx]

					local valid_step = false
					local final_ny = ny
					local final_n_idx = n_idx

					if can_crawl then
						-- Surface Crawling Traversal (Spider, Wall Climber):
						-- Candidate node must be passable, non-hazardous, and not water for non-swimmers
						if (not c_walkable[n_cid] or (can_open_doors and c_openable[n_cid])) and
						   not c_hazard[n_cid] and not (not can_swim and c_swimable[n_cid]) then
							local corner_clear = true
							if off[5] then -- is_diagonal
								local dx, dy, dz = off[1], off[2], off[3]
								if dx ~= 0 and dy ~= 0 and dz ~= 0 then
									local b1 = data[curr_idx + (dx > 0 and stride_e or stride_w)]
									local b2 = data[curr_idx + (dy > 0 and stride_u or stride_d)]
									local b3 = data[curr_idx + (dz > 0 and stride_n or stride_s)]
									if c_walkable[b1] and c_walkable[b2] and c_walkable[b3] then
										corner_clear = false
									end
								elseif dx ~= 0 and dz ~= 0 then
									local b1 = data[curr_idx + (dx > 0 and stride_e or stride_w)]
									local b2 = data[curr_idx + (dz > 0 and stride_n or stride_s)]
									if c_walkable[b1] and c_walkable[b2] then
										corner_clear = false
									end
								elseif dx ~= 0 and dy ~= 0 then
									local b1 = data[curr_idx + (dx > 0 and stride_e or stride_w)]
									local b2 = data[curr_idx + (dy > 0 and stride_u or stride_d)]
									if c_walkable[b1] and c_walkable[b2] then
										corner_clear = false
									end
								elseif dy ~= 0 and dz ~= 0 then
									local b1 = data[curr_idx + (dy > 0 and stride_u or stride_d)]
									local b2 = data[curr_idx + (dz > 0 and stride_n or stride_s)]
									if c_walkable[b1] and c_walkable[b2] then
										corner_clear = false
									end
								end
							end

							if corner_clear then
								-- Verify surface adherence: supported by solid block on cardinal face
								local has_surface = (ny - 1 >= emin.y and c_walkable[data[n_idx + stride_d]]) or
								                    (ny + 1 <= emax.y and c_walkable[data[n_idx + stride_u]]) or
								                    (nx + 1 <= emax.x and c_walkable[data[n_idx + stride_e]]) or
								                    (nx - 1 >= emin.x and c_walkable[data[n_idx + stride_w]]) or
								                    (nz + 1 <= emax.z and c_walkable[data[n_idx + stride_n]]) or
								                    (nz - 1 >= emin.z and c_walkable[data[n_idx + stride_s]])

								-- Leniency for uneven terrain: check planar diagonals within 1 node
								if not has_surface then
									has_surface = (nx + 1 <= emax.x and ny + 1 <= emax.y and c_walkable[data[n_idx + stride_e + stride_u]]) or
									              (nx - 1 >= emin.x and ny + 1 <= emax.y and c_walkable[data[n_idx + stride_w + stride_u]]) or
									              (nx + 1 <= emax.x and ny - 1 >= emin.y and c_walkable[data[n_idx + stride_e + stride_d]]) or
									              (nx - 1 >= emin.x and ny - 1 >= emin.y and c_walkable[data[n_idx + stride_w + stride_d]]) or
									              (nz + 1 <= emax.z and ny + 1 <= emax.y and c_walkable[data[n_idx + stride_n + stride_u]]) or
									              (nz - 1 >= emin.z and ny + 1 <= emax.y and c_walkable[data[n_idx + stride_s + stride_u]]) or
									              (nz + 1 <= emax.z and ny - 1 >= emin.y and c_walkable[data[n_idx + stride_n + stride_d]]) or
									              (nz - 1 >= emin.z and ny - 1 >= emin.y and c_walkable[data[n_idx + stride_s + stride_d]]) or
									              (nx + 1 <= emax.x and nz + 1 <= emax.z and c_walkable[data[n_idx + stride_e + stride_n]]) or
									              (nx - 1 >= emin.x and nz + 1 <= emax.z and c_walkable[data[n_idx + stride_w + stride_n]]) or
									              (nx + 1 <= emax.x and nz - 1 >= emin.z and c_walkable[data[n_idx + stride_e + stride_s]]) or
									              (nx - 1 >= emin.x and nz - 1 >= emin.z and c_walkable[data[n_idx + stride_w + stride_s]])
								end

								if has_surface then
									valid_step = true
									final_ny = ny
									final_n_idx = n_idx
								end
							end
						end
					elseif is_floating then
						-- 3D Aerial Flight Traversal (Floating/Hovering mob, flyers):
						-- Candidate node must be passable, non-hazardous, and not liquid for non-swimmers
						if (not c_walkable[n_cid] or (can_open_doors and c_openable[n_cid])) and
						   not c_hazard[n_cid] and not (not can_swim and c_swimable[n_cid]) then
							local corner_clear = true
							if off[5] then -- is_diagonal
								local dx, dy, dz = off[1], off[2], off[3]
								if dx ~= 0 and dy ~= 0 and dz ~= 0 then
									local b1 = data[curr_idx + (dx > 0 and stride_e or stride_w)]
									local b2 = data[curr_idx + (dy > 0 and stride_u or stride_d)]
									local b3 = data[curr_idx + (dz > 0 and stride_n or stride_s)]
									if c_walkable[b1] and c_walkable[b2] and c_walkable[b3] then
										corner_clear = false
									end
								elseif dx ~= 0 and dz ~= 0 then
									local b1 = data[curr_idx + (dx > 0 and stride_e or stride_w)]
									local b2 = data[curr_idx + (dz > 0 and stride_n or stride_s)]
									if c_walkable[b1] and c_walkable[b2] then
										corner_clear = false
									end
								elseif dx ~= 0 and dy ~= 0 then
									local b1 = data[curr_idx + (dx > 0 and stride_e or stride_w)]
									local b2 = data[curr_idx + (dy > 0 and stride_u or stride_d)]
									if c_walkable[b1] and c_walkable[b2] then
										corner_clear = false
									end
								elseif dy ~= 0 and dz ~= 0 then
									local b1 = data[curr_idx + (dy > 0 and stride_u or stride_d)]
									local b2 = data[curr_idx + (dz > 0 and stride_n or stride_s)]
									if c_walkable[b1] and c_walkable[b2] then
										corner_clear = false
									end
								end
							end

							if corner_clear then
								valid_step = true
								final_ny = ny
								final_n_idx = n_idx
							end
						end
					elseif is_on_ladder then
						-- Ladder traversal: vertical climb or step off onto floor/ladder
						local is_vertical = (off[1] == 0 and off[3] == 0)
						local n_below_cid = data[n_idx + stride_d]
						if is_vertical then
							if c_climbable[n_cid] or (off[2] < 0 and c_walkable[n_cid]) then
								valid_step = true
							end
						else
							-- Horizontal step off ladder: requires passability and footing/ladder
							if (not c_walkable[n_cid] or (can_open_doors and c_openable[n_cid])) and
							   (c_climbable[n_cid] or c_walkable[n_below_cid] or (can_climb and c_climbable[n_below_cid])) then
								valid_step = true
							end
						end
					elseif is_in_water then
						-- Direct 3D traversal in liquid
						if not c_walkable[n_cid] or (can_open_doors and c_openable[n_cid]) then
							valid_step = true
						end
					else
						-- Standard Ground Movement: test direct foot, step-up, and step-down
						-- Diagonal corner-cutting prevention for ground mobs:
						-- Prevent diagonal traversal if either adjacent orthogonal node is solid wall
						local diagonal_corner_blocked = false
						if off[5] then
							local dx, dz = off[1], off[3]
							if dx ~= 0 and dz ~= 0 then
								local b1_idx = curr_idx + (dx > 0 and stride_e or stride_w)
								local b2_idx = curr_idx + (dz > 0 and stride_n or stride_s)
								local b1 = data[b1_idx]
								local b2 = data[b2_idx]
								if c_walkable[b1] or c_walkable[b2] then
									diagonal_corner_blocked = true
								else
									local b1_h = data[b1_idx + stride_u]
									local b2_h = data[b2_idx + stride_u]
									if c_walkable[b1_h] or c_walkable[b2_h] then
										diagonal_corner_blocked = true
									end
								end
							end
						end

						if not diagonal_corner_blocked then
							local under_cid = data[n_idx + stride_d]

							if c_walkable[n_cid] and not (can_open_doors and c_openable[n_cid]) then
								-- Blocked at foot level: attempt 1-node step-up (disallowed for tall obstacles like fences/walls/bars)
								if not (c_tall and c_tall[n_cid]) then
									local step_up_idx = n_idx + stride_u
									local step_up_cid = data[step_up_idx]
									local head_clear_idx = step_up_idx + stride_u
									local head_clear_cid = data[head_clear_idx]

									if ny + 1 <= emax.y and
									   (not c_walkable[step_up_cid] or (can_open_doors and c_openable[step_up_cid])) and
									   (not c_walkable[head_clear_cid]) and
									   not c_hazard[step_up_cid] and
									   not (not can_swim and (c_swimable[step_up_cid] or c_swimable[head_clear_cid])) then
										valid_step = true
										final_ny = ny + 1
										final_n_idx = step_up_idx
									end
								end
							else
								-- Foot node is open (air, openable door, or ladder)
								if not can_swim and c_swimable[n_cid] then
									-- Candidate foot node is water, mob cannot swim
									valid_step = false
								elseif c_walkable[under_cid] or (can_climb and (c_climbable[under_cid] or c_climbable[n_cid])) or
								   (can_swim and c_swimable[under_cid]) then
									-- Solid ground or ladder underneath
									if not can_swim and c_swimable[under_cid] then
										valid_step = false
									else
										valid_step = true
									end
								else
									-- Air underneath: test drop-down (up to 2 nodes)
									for drop = 1, 2 do
										local drop_foot_idx = n_idx - drop * stride_u
										local drop_ground_idx = drop_foot_idx - stride_u
										if (ny - drop - 1) >= emin.y then
											local df_cid = data[drop_foot_idx]
											local dg_cid = data[drop_ground_idx]
											if not c_walkable[df_cid] and c_walkable[dg_cid] and not c_hazard[df_cid] and
											   not (not can_swim and (c_swimable[df_cid] or c_swimable[dg_cid])) then
												valid_step = true
												final_ny = ny - drop
												final_n_idx = drop_foot_idx
												break
											end
										end
									end
								end
							end
						end
					end

					-- Height clearance check
					if valid_step and not can_crawl then
						for h = 1, height - 1 do
							local head_idx = final_n_idx + h * stride_u
							if (final_ny + h) <= emax.y then
								local head_cid = data[head_idx]
								if (c_walkable[head_cid] and not (can_open_doors and c_openable[head_cid])) or
								   c_hazard[head_cid] or (not can_swim and c_swimable[head_cid]) then
									valid_step = false
									break
								end
							else
								valid_step = false
								break
							end
						end
					end

					-- Hazard avoidance
					local final_cid = data[final_n_idx]
					if c_hazard[final_cid] then
						valid_step = false
					end

					if valid_step and closed_stamp[final_n_idx] ~= stamp then
						-- Calculate traversal cost
						local move_dist = off[6] or (off[5] and 1.4142 or 1.0)
						local node_cost = c_cost[final_cid] or 1.0

						-- Door penalty
						if c_openable[final_cid] and can_open_doors then
							node_cost = node_cost + 2.0
						end

						-- Swim penalty
						if c_swimable[final_cid] and can_swim then
							node_cost = node_cost + 1.5
						end

						local tentative_g = curr_g + (move_dist * node_cost)

						if visited_stamp[final_n_idx] ~= stamp or tentative_g < g_scores[final_n_idx] then
							visited_stamp[final_n_idx] = stamp
							g_scores[final_n_idx] = tentative_g
							came_from[final_n_idx] = curr_idx
							came_from_stamp[final_n_idx] = stamp

							local h = heuristic_fn(nx, final_ny, nz, t_x, t_y, t_z)
							open_set:push(final_n_idx, tentative_g + h)

							if h < best_fallback_h then
								best_fallback_h = h
								best_fallback_idx = final_n_idx
							end
						end
					end
				end
			end
		end
	end

	-- Reconstruct Waypoint Path
	local end_trace_idx = found and target_idx or best_fallback_idx
	if end_trace_idx == start_idx then
		return nil
	end

	local raw_path = {}
	local trace = end_trace_idx
	local visited_trace = {}
	local safety = 0

	while trace and trace ~= start_idx and trace > 0 and safety < 1000 do
		safety = safety + 1
		if visited_trace[trace] or came_from_stamp[trace] ~= stamp then
			-- Stale node or cycle detected; terminate path reconstruction safely
			break
		end
		visited_trace[trace] = true
		local px, py, pz = unpack_index(trace, emin, ystride, zstride)
		local normal = {x = 0, y = 1, z = 0}
		local surface_type = "floor"
		local diag_n = 0.7071067811865475

		if can_crawl then
			if py - 1 >= emin.y and c_walkable[data[trace + stride_d]] then
				normal = {x = 0, y = 1, z = 0}
				surface_type = "floor"
			elseif py + 1 <= emax.y and c_walkable[data[trace + stride_u]] then
				normal = {x = 0, y = -1, z = 0}
				surface_type = "ceiling"
			elseif pz + 1 <= emax.z and c_walkable[data[trace + stride_n]] then
				normal = {x = 0, y = 0, z = -1}
				surface_type = "wall"
			elseif pz - 1 >= emin.z and c_walkable[data[trace + stride_s]] then
				normal = {x = 0, y = 0, z = 1}
				surface_type = "wall"
			elseif px + 1 <= emax.x and c_walkable[data[trace + stride_e]] then
				normal = {x = -1, y = 0, z = 0}
				surface_type = "wall"
			elseif px - 1 >= emin.x and c_walkable[data[trace + stride_w]] then
				normal = {x = 1, y = 0, z = 0}
				surface_type = "wall"
			-- Diagonal normal resolution for uneven terrain corners and stalactites
			elseif py + 1 <= emax.y and px + 1 <= emax.x and c_walkable[data[trace + stride_u + stride_e]] then
				normal = {x = -diag_n, y = -diag_n, z = 0}
				surface_type = "ceiling"
			elseif py + 1 <= emax.y and px - 1 >= emin.x and c_walkable[data[trace + stride_u + stride_w]] then
				normal = {x = diag_n, y = -diag_n, z = 0}
				surface_type = "ceiling"
			elseif py + 1 <= emax.y and pz + 1 <= emax.z and c_walkable[data[trace + stride_u + stride_n]] then
				normal = {x = 0, y = -diag_n, z = -diag_n}
				surface_type = "ceiling"
			elseif py + 1 <= emax.y and pz - 1 >= emin.z and c_walkable[data[trace + stride_u + stride_s]] then
				normal = {x = 0, y = -diag_n, z = diag_n}
				surface_type = "ceiling"
			elseif py - 1 >= emin.y and px + 1 <= emax.x and c_walkable[data[trace + stride_d + stride_e]] then
				normal = {x = -diag_n, y = diag_n, z = 0}
				surface_type = "wall"
			elseif py - 1 >= emin.y and px - 1 >= emin.x and c_walkable[data[trace + stride_d + stride_w]] then
				normal = {x = diag_n, y = diag_n, z = 0}
				surface_type = "wall"
			elseif py - 1 >= emin.y and pz + 1 <= emax.z and c_walkable[data[trace + stride_d + stride_n]] then
				normal = {x = 0, y = diag_n, z = -diag_n}
				surface_type = "wall"
			elseif py - 1 >= emin.y and pz - 1 >= emin.z and c_walkable[data[trace + stride_d + stride_s]] then
				normal = {x = 0, y = diag_n, z = diag_n}
				surface_type = "wall"
			end
		end

		local n_len = math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
		if n_len > 1e-4 and math.abs(n_len - 1.0) > 1e-5 then
			normal = {x = normal.x / n_len, y = normal.y / n_len, z = normal.z / n_len}
		end

		table.insert(raw_path, {
			x = px,
			y = py,
			z = pz,
			normal = normal,
			surface_type = is_floating and "air" or surface_type,
		})
		trace = came_from[trace]
	end

	-- Reverse path into start-to-goal order
	local waypoints = {}
	local count = #raw_path
	for i = 1, count do
		waypoints[i] = raw_path[count - i + 1]
	end

	return waypoints
end

-- -------------------------------------------------------------------------
-- CENTRAL TIME-SLICED SCHEDULER (MAX 1.5ms PER TICK)
-- -------------------------------------------------------------------------

--- Queues an asynchronous pathfinding task
---@param start_pos Vector Starting world position
---@param target_pos Vector Target world position
---@param abilities table Mob movement capabilities
---@param callback fun(path: table|nil) Callback invoked upon path completion
---@param mob_height integer|nil Mob height clearance in nodes
function fast_pathfinder.find_path(start_pos, target_pos, abilities, callback, mob_height)
	local height = math.max(1, math.ceil(mob_height or DEFAULT_MOB_HEIGHT))
	local co = coroutine.create(function()
		local path = astar_search(start_pos, target_pos, abilities or {}, height)
		callback(path)
	end)

	search_queue_tail = search_queue_tail + 1
	active_searches[search_queue_tail] = co
end

--- Synchronous path request (for fallback or immediate test verification)
---@param start_pos Vector
---@param target_pos Vector
---@param abilities table
---@param mob_height integer|nil
---@return table|nil
function fast_pathfinder.find_path_sync(start_pos, target_pos, abilities, mob_height)
	local height = math.max(1, math.ceil(mob_height or DEFAULT_MOB_HEIGHT))
	local result = nil
	local co = coroutine.create(function()
		result = astar_search(start_pos, target_pos, abilities or {}, height)
	end)

	while coroutine.status(co) ~= "dead" do
		local ok, err = coroutine.resume(co)
		if not ok then
			core.log("error", "[x_pathfinding] A* search error: " .. tostring(err))
			return nil
		end
	end

	return result
end

--- Globalstep processor executing search coroutines under the hard tick budget
--- Uses strict sequential execution so concurrent mob searches never interleave or corrupt shared memory buffers
---@param _dtime number Server step delta time
function fast_pathfinder.step(_dtime)
	if not current_active_co and search_queue_head > search_queue_tail then
		return
	end

	local tick_start = core.get_us_time()

	while true do
		local elapsed_us = core.get_us_time() - tick_start
		if elapsed_us >= MAX_TICK_BUDGET_US then
			break -- Budget reached, yield until next server tick
		end

		if not current_active_co or coroutine.status(current_active_co) == "dead" then
			if search_queue_head > search_queue_tail then
				-- Queue drained
				search_queue_head = 1
				search_queue_tail = 0
				current_active_co = nil
				break
			end
			current_active_co = active_searches[search_queue_head]
			active_searches[search_queue_head] = nil
			search_queue_head = search_queue_head + 1
		end

		if current_active_co and coroutine.status(current_active_co) ~= "dead" then
			local ok, err = coroutine.resume(current_active_co)
			if not ok then
				core.log("error", "[x_pathfinding] Coroutine execution error: " .. tostring(err))
				current_active_co = nil
			elseif coroutine.status(current_active_co) == "dead" then
				current_active_co = nil
			end
		else
			current_active_co = nil
		end
	end
end

-- Automatically register engine globalstep processor
core.register_globalstep(fast_pathfinder.step)

return fast_pathfinder
