--[[
	x_mob_core - Hybrid Spawning Engine
	Provides player-centric trickle spawning and mapgen chunk population without ABMs
]]

---@class SpawningEngine
local engine = {}

local registry = dofile(core.get_modpath("x_mob_core") .. "/spawning/registry.lua")
local conditions = dofile(core.get_modpath("x_mob_core") .. "/spawning/conditions.lua")

local math_random = math.random
local math_floor = math.floor
local math_cos = math.cos
local math_sin = math.sin
local math_pi = math.pi
local math_rad = math.rad
local math_max = math.max
local math_min = math.min
local atan2 = math.atan2 or math.atan

local SPAWN_INTERVAL = 12.0
local STEP_INTERVAL = 1.0
local SPAWN_MIN_DIST = 24
local SPAWN_MAX_DIST = 48
local CHUNK_SPAWN_CHANCE = 4 -- 1 in 4 chunks attempts wild mob generation
local CANDIDATE_ATTEMPTS = 4
local FRONT_BIAS = 0.50
local FRONT_ARC_DEG = 130.0
local FRONT_ARC_RAD = math_rad(FRONT_ARC_DEG)

-- Scratch vectors recycled during candidate checks to prevent per-attempt table GC churn
local scratch_top_pos = {x = 0, y = 0, z = 0}
local scratch_bot_pos = {x = 0, y = 0, z = 0}
local scratch_spawn_pos = {x = 0, y = 0, z = 0}

--- Spawns a cohesive group of mobs scattered safely around a center point
---@param spawn_pos Vector World center position
---@param def SpawnDefinition Spawn definition
---@param source? string Spawner mechanism source identifier (default: "Spawning")
---@return integer count Number of mobs spawned
local function spawn_mob_group(spawn_pos, def, source)
	local min_g = def.group_min or 1
	local max_g = def.group_max or min_g
	local group_size = (max_g > min_g) and math.random(min_g, max_g) or min_g

	-- Check how many can spawn without exceeding active_object_count or total density cap
	local max_allowed = def.active_object_count or 1
	local max_total = def.max_total_in_radius or conditions.MAX_TOTAL_RADIUS_MOBS or 8
	local existing_count, existing_total = conditions.count_mobs_in_radius(spawn_pos, SPAWN_MAX_DIST, def.mob_name)

	local remaining_quota = max_allowed - existing_count
	local remaining_total = max_total - existing_total
	if remaining_quota <= 0 or remaining_total <= 0 then
		return 0
	end

	local to_spawn = math.min(group_size, remaining_quota, remaining_total)
	local spawned = 0

	local mdef = x_mob_core.registered_mobs[def.mob_name]
	local is_aquatic = def.is_aquatic or (mdef and (mdef.shoal or mdef.is_aquatic))
	local base_spawn_pos = spawn_pos
	if is_aquatic then
		local under_node = core.get_node({x = spawn_pos.x, y = spawn_pos.y - 1, z = spawn_pos.z})
		if core.get_item_group(under_node.name, "water") > 0 then
			base_spawn_pos = {x = spawn_pos.x, y = spawn_pos.y - 1, z = spawn_pos.z}
		end
	end

	for i = 1, to_spawn do
		local target_pos = base_spawn_pos
		if i > 1 then
			if is_aquatic then
				local ox = math.random(-2, 2)
				local oz = math.random(-2, 2)
				local oy = math.random(-1, 0)
				local check_pos = {x = base_spawn_pos.x + ox, y = base_spawn_pos.y + oy, z = base_spawn_pos.z + oz}
				local n_cur = core.get_node(check_pos)
				if core.get_item_group(n_cur.name, "water") > 0 then
					target_pos = check_pos
				end
			else
				-- Scatter companions in a 2-3 block horizontal radius
				local ox = math.random(-2, 2)
				local oz = math.random(-2, 2)
				local candidate_ground = nil

				for oy = 1, -2, -1 do
					local check_pos = {x = spawn_pos.x + ox, y = spawn_pos.y + oy, z = spawn_pos.z + oz}
					local check_under = {x = spawn_pos.x + ox, y = spawn_pos.y + oy - 1, z = spawn_pos.z + oz}
					local n_cur = core.get_node(check_pos)
					local n_und = core.get_node(check_under)
					if n_cur.name == "air" and n_und.name ~= "air" and n_und.name ~= "ignore" then
						local ndef = core.registered_nodes[n_und.name]
						if ndef and ndef.walkable and not (ndef.liquidtype and ndef.liquidtype ~= "none")
							and not (def._parsed_exclude_nodes and def._parsed_exclude_nodes[n_und.name]) then
							candidate_ground = check_pos
							break
						end
					end
				end

				if candidate_ground then
					target_pos = candidate_ground
				end
			end
		end

		local obj = core.add_entity(target_pos, def.mob_name)
		if obj then
			spawned = spawned + 1
		end
	end

	if spawned > 0 then
		local source_tag = source or "Spawning"
		core.log("action", string.format("[x_mob_core] [%s] Spawned %d %s at %s",
			source_tag, spawned, def.mob_name, core.pos_to_string(vector.round(base_spawn_pos))))
	end

	return spawned
end

-- =========================================================================
-- PASS 1: MAPGEN NATIVE POPULATION
-- Conservatively populates newly generated chunks with at most 1 pack/group per eligible chunk
-- =========================================================================
core.register_on_generated(function(minp, maxp, _blockseed)
	local spawns = registry.get_spawns()
	if #spawns == 0 then return end

	-- 1 in 4 chance for a chunk to spawn wild mobs
	if math.random(1, CHUNK_SPAWN_CHANCE) ~= 1 then return end

	local surface_targets = registry.get_surface_nodes()
	if #surface_targets == 0 then return end

	local surface_nodes = core.find_nodes_in_area_under_air(minp, maxp, surface_targets)
	if not surface_nodes or #surface_nodes == 0 then return end

	-- Attempt sample locations to place up to 2 groups per eligible chunk
	local groups_to_spawn = math.random(1, 2)
	local attempts = math.min(16, #surface_nodes)
	local spawned_groups = 0

	for _ = 1, attempts do
		local rand_idx = math.random(1, #surface_nodes)
		local pos = surface_nodes[rand_idx]
		local spawn_pos = {x = pos.x, y = pos.y + 1, z = pos.z}

		-- Pick a random mob spawn definition (avoids favoring first registered mob)
		local def = spawns[math.random(1, #spawns)]
		-- Mapgen rarity weighting: scale by def.chance so rare mobs do not flood newly generated terrain
		local mapgen_chance = math.max(1, math.floor((def.chance or 1000) / 1500))
		if math.random(1, mapgen_chance) == 1 then
			if conditions.check(spawn_pos, def, true) then
				if spawn_mob_group(spawn_pos, def, "Mapgen Spawning") > 0 then
					spawned_groups = spawned_groups + 1
					if spawned_groups >= groups_to_spawn then
						break
					end
				end
			end
		end
	end
end)

--- Determines player's primary horizontal movement or facing heading angle in radians.
--- Uses velocity when traveling, falling back to look direction or horizontal yaw.
---@param player ObjectRef Player object
---@return number|nil heading_angle Angle in radians (-pi to pi), or nil if indeterminate
local function get_player_heading(player)
	if not player or not player:is_valid() then
		return nil
	end

	-- 1. Velocity vector if moving horizontally (travel trajectory)
	local vel = player:get_velocity()
	if vel then
		local spd_sq = vel.x * vel.x + vel.z * vel.z
		if spd_sq > 0.25 then -- speed > 0.5 nodes/s (walking/sprinting/riding)
			return atan2(vel.z, vel.x)
		end
	end

	-- 2. Horizontal look direction vector
	local dir = player:get_look_dir()
	if dir then
		local dir_sq = dir.x * dir.x + dir.z * dir.z
		if dir_sq > 0.001 then
			return atan2(dir.z, dir.x)
		end
	end

	-- 3. Horizontal yaw fallback (handles looking straight up/down)
	local yaw = player:get_look_horizontal()
	if yaw then
		local fwd = core.yaw_to_dir(yaw)
		if fwd then
			return atan2(fwd.z, fwd.x)
		end
	end

	return nil
end

--- Computes a candidate spawn angle around the player, biased towards their path of travel.
---@param player ObjectRef Player object
---@param front_bias? number Probability (0.0 to 1.0) of choosing a forward cone angle
---@param front_arc_rad? number Total width of forward cone in radians
---@return number angle Angle in radians (0 to 2*pi)
local function sample_spawn_angle(player, front_bias, front_arc_rad)
	local bias = front_bias or FRONT_BIAS
	local arc = front_arc_rad or FRONT_ARC_RAD

	local heading = (bias > 0) and get_player_heading(player)
	if heading and math_random() < bias then
		local half_arc = arc * 0.5
		local offset = (math_random() * 2 - 1) * half_arc
		local angle = heading + offset
		return (angle % (math_pi * 2))
	end

	return math_random() * math_pi * 2
end

-- =========================================================================
-- PASS 2: PLAYER-CENTRIC TRICKLE SPAWNER
-- Responsive time-sliced globalstep repopulating active player areas during exploration
-- Distributes player checks across 1.0s ticks to eliminate multiplayer lag spikes
-- =========================================================================
local step_timer = 0.0
local player_cursor = 1
local player_quota = 0.0

core.register_globalstep(function(dtime)
	step_timer = step_timer + dtime
	if step_timer < STEP_INTERVAL then return end
	step_timer = 0.0

	local players = core.get_connected_players()
	local num_players = #players
	if num_players == 0 then
		player_quota = 0.0
		return
	end

	local spawns = registry.get_spawns()
	local num_spawns = #spawns
	if num_spawns == 0 then return end

	-- Time-sliced batch sizing: evenly spread player workload over SPAWN_INTERVAL seconds
	local slices = math_max(1, math_floor(SPAWN_INTERVAL / STEP_INTERVAL + 0.5))
	player_quota = math_min(num_players, player_quota + (num_players / slices))
	local players_to_process = math_floor(player_quota + 1e-9)
	if players_to_process <= 0 then return end
	player_quota = player_quota - players_to_process

	for _ = 1, players_to_process do
		if player_cursor > num_players then
			player_cursor = 1
		end
		local player = players[player_cursor]
		player_cursor = player_cursor + 1

		local p_pos = player and player:is_valid() and player:get_pos()
		if p_pos then
			-- Try up to CANDIDATE_ATTEMPTS candidate directions to find suitable terrain
			for _ = 1, CANDIDATE_ATTEMPTS do
				local angle = sample_spawn_angle(player, FRONT_BIAS, FRONT_ARC_RAD)
				local dist = math_random(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
				local tx = math_floor(p_pos.x + math_cos(angle) * dist + 0.5)
				local tz = math_floor(p_pos.z + math_sin(angle) * dist + 0.5)

				local min_y = math_max(-31000, math_floor(p_pos.y - 15 + 0.5))
				local max_y = math_min(31000, math_floor(p_pos.y + 15 + 0.5))

				scratch_top_pos.x = tx
				scratch_top_pos.y = max_y
				scratch_top_pos.z = tz

				scratch_bot_pos.x = tx
				scratch_bot_pos.y = min_y
				scratch_bot_pos.z = tz

				local node_top = core.get_node_or_nil(scratch_top_pos)
				if node_top then
					local ground_y = nil
					local ray = Raycast(scratch_top_pos, scratch_bot_pos, false, true)
					for pt in ray do
						if pt.type == "node" then
							local n = core.get_node(pt.under)
							if n.name ~= "air" and n.name ~= "ignore" then
								ground_y = pt.under.y
								break
							end
						end
					end

					if ground_y then
						scratch_spawn_pos.x = tx
						scratch_spawn_pos.y = ground_y + 1
						scratch_spawn_pos.z = tz

						local def = spawns[math_random(1, num_spawns)]
						-- Calibrated probability scaling: P(attempt) = 75 / def.chance
						local scaled_chance = math_max(1, math_floor((def.chance or 1000) / 75))

						if math_random(1, scaled_chance) == 1 then
							if conditions.check(scratch_spawn_pos, def, false) then
								spawn_mob_group({
									x = scratch_spawn_pos.x,
									y = scratch_spawn_pos.y,
									z = scratch_spawn_pos.z,
								}, def, "Trickle Spawning")
								break -- Succeeded for this player this cycle
							end
						end
					end
				end
			end
		end
	end
end)

engine.registry = registry
engine.conditions = conditions
engine.spawn_mob_group = spawn_mob_group
engine.get_player_heading = get_player_heading
engine.sample_spawn_angle = sample_spawn_angle
return engine
