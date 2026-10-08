--[[
	x_mob_core - Hybrid Spawning Engine
	Provides player-centric trickle spawning and mapgen chunk population without ABMs
]]

---@class SpawningEngine
local engine = {}

local registry = dofile(core.get_modpath("x_mob_core") .. "/spawning/registry.lua")
local conditions = dofile(core.get_modpath("x_mob_core") .. "/spawning/conditions.lua")

local SPAWN_INTERVAL = 6.0
local SPAWN_MIN_DIST = 24
local SPAWN_MAX_DIST = 48
local CHUNK_SPAWN_CHANCE = 4 -- 1 in 4 chunks attempts wild mob generation

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
						if ndef and ndef.walkable and not (def._parsed_exclude_nodes and def._parsed_exclude_nodes[n_und.name]) then
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

-- =========================================================================
-- PASS 2: PLAYER-CENTRIC TRICKLE SPAWNER
-- Responsive globalstep repopulating active player areas during exploration
-- =========================================================================
local timer = 0.0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < SPAWN_INTERVAL then return end
	timer = 0.0

	local players = core.get_connected_players()
	if #players == 0 then return end

	local spawns = registry.get_spawns()
	if #spawns == 0 then return end

	for p = 1, #players do
		local player = players[p]
		local p_pos = player and player:is_valid() and player:get_pos()
		if p_pos then
			-- Try up to 3 candidate directions to find suitable terrain around player
			for _ = 1, 3 do
				local angle = math.random() * math.pi * 2
				local dist = math.random(SPAWN_MIN_DIST, SPAWN_MAX_DIST)
				local tx = math.floor(p_pos.x + math.cos(angle) * dist + 0.5)
				local tz = math.floor(p_pos.z + math.sin(angle) * dist + 0.5)

				local min_y = math.max(-31000, math.floor(p_pos.y - 15 + 0.5))
				local max_y = math.min(31000, math.floor(p_pos.y + 15 + 0.5))

				local top_pos = {x = tx, y = max_y, z = tz}
				local bot_pos = {x = tx, y = min_y, z = tz}
				local node_top = core.get_node_or_nil(top_pos)
				if node_top then
					local ground_y = nil
					local ray = Raycast(top_pos, bot_pos, false, false)
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
						local spawn_pos = {x = tx, y = ground_y + 1, z = tz}
						local def = spawns[math.random(1, #spawns)]
						-- Calibrated probability scaling: P(attempt) = 75 / def.chance
						local scaled_chance = math.max(1, math.floor((def.chance or 1000) / 75))

						if math.random(1, scaled_chance) == 1 then
							if conditions.check(spawn_pos, def, false) then
								spawn_mob_group(spawn_pos, def, "Trickle Spawning")
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
return engine
