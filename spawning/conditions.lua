--[[
	x_mob_core - Spawning Conditions Validator
	Validates elevation, light levels, dynamic node/group ground, and active entity density
]]

---@class SpawningConditions
local conditions = {}

local SPAWN_MAX_DIST = 45
conditions.MAX_TOTAL_RADIUS_MOBS = 8

--- Checks whether an entity represents a living mob rather than a dropped item or non-mob entity
---@param ent table LuaEntity table
---@return boolean
local function is_mob_entity(ent)
	if not ent or not ent.name then return false end
	if ent.name == "__builtin:item" or ent.name == "__builtin:falling_node" then
		return false
	end
	if ent._is_x_mob or x_mob_core.registered_mobs[ent.name] then
		return true
	end
	if ent.hp or ent.health or ent.hp_max or ent._cmi_is_mob then
		return true
	end
	return false
end
conditions.is_mob_entity = is_mob_entity

--- Counts living mob entities and specific mob occurrences in a radius
---@param pos Vector Center position
---@param radius number Search radius
---@param mob_name? string Specific mob technical name to count
---@return integer count Count of specific mob_name (or total if mob_name is nil)
---@return integer total Count of all living mobs in radius
local function count_mobs_in_radius(pos, radius, mob_name)
	local objs = core.get_objects_inside_radius(pos, radius)
	local specific_count = 0
	local total = 0
	for i = 1, #objs do
		local obj = objs[i]
		if obj and obj:is_valid() and not obj:is_player() then
			local ent = obj:get_luaentity()
			if ent and is_mob_entity(ent) then
				total = total + 1
				if mob_name and ent.name == mob_name then
					specific_count = specific_count + 1
				end
			end
		end
	end
	return specific_count, total
end
conditions.count_mobs_in_radius = count_mobs_in_radius

--- Checks if a position satisfies all conditions for a spawn definition
---@param pos Vector Proposed spawn world position
---@param def SpawnDefinition|SpawnConfig Spawn definition table
---@param is_mapgen? boolean Whether check is performed during mapgen chunk generation
---@return boolean is_valid
function conditions.check(pos, def, is_mapgen)
	-- Verify time of day limits (ultra-fast scalar check before spatial queries)
	if not is_mapgen then
		local tod = core.get_timeofday()
		if tod then
			if def.day_only and (tod < 0.20 or tod > 0.80) then
				return false
			end
			if def.night_only and (tod >= 0.20 and tod <= 0.80) then
				return false
			end
			if def.min_time and def.max_time then
				if def.min_time <= def.max_time then
					if tod < def.min_time or tod > def.max_time then
						return false
					end
				else
					-- Wrap-around range across midnight (e.g. min_time = 0.8, max_time = 0.2)
					if tod < def.min_time and tod > def.max_time then
						return false
					end
				end
			end
		end
	end

	-- Verify world elevation limits
	local min_elev = def.min_elevation or -31000
	local max_elev = def.max_elevation or 31000
	if pos.y < min_elev or pos.y > max_elev then
		return false
	end

	-- Verify biome limits if specified
	if def._parsed_biomes and next(def._parsed_biomes) then
		local bdata = core.get_biome_data(pos)
		local bname = bdata and core.get_biome_name(bdata.biome)
		if not bname or not def._parsed_biomes[bname] then
			return false
		end
	end

	-- Verify lighting limits
	local min_light = def.min_light or 0
	local max_light = def.max_light or 15
	local light = core.get_node_light(pos)
	if not light or light < min_light or light > max_light then
		return false
	end

	-- Validate surface ground node or group filter using pre-parsed O(1) sets
	local node_below = core.get_node({x = pos.x, y = pos.y - 1, z = pos.z})
	local node_at = core.get_node(pos)

	-- Check explicit node exclusions
	if def._parsed_exclude_nodes and next(def._parsed_exclude_nodes) then
		if def._parsed_exclude_nodes[node_below.name] or def._parsed_exclude_nodes[node_at.name] then
			return false
		end
	end

	-- Check explicit group exclusions
	if def._parsed_exclude_groups and next(def._parsed_exclude_groups) then
		for grp in pairs(def._parsed_exclude_groups) do
			if core.get_item_group(node_below.name, grp) > 0 or core.get_item_group(node_at.name, grp) > 0 then
				return false
			end
		end
	end

	local valid_node = false
	if def._parsed_nodes and (next(def._parsed_nodes) or next(def._parsed_groups)) then
		if def._parsed_nodes[node_below.name] then
			valid_node = true
		else
			for group_name in pairs(def._parsed_groups) do
				if core.get_item_group(node_below.name, group_name) > 0 then
					valid_node = true
					break
				end
			end
		end
	elseif def.nodes and #def.nodes > 0 then
		for _, target in ipairs(def.nodes) do
			if target:sub(1, 6) == "group:" then
				local group_name = target:sub(7)
				if core.get_item_group(node_below.name, group_name) > 0 then
					valid_node = true
					break
				end
			elseif node_below.name == target then
				valid_node = true
				break
			end
		end
	else
		-- If no node restriction specified, ensure ground is solid/walkable
		local node_def = core.registered_nodes[node_below.name]
		valid_node = node_def and node_def.walkable == true
	end

	if not valid_node then
		return false
	end

	-- Enforce active entity density limits around proposed position:
	-- 1. Specific mob active_object_count limit
	-- 2. Total combined living mob density cap within radius
	local max_count = def.active_object_count or 1
	local max_total = def.max_total_in_radius or conditions.MAX_TOTAL_RADIUS_MOBS
	local count, total_mobs = count_mobs_in_radius(pos, SPAWN_MAX_DIST, def.mob_name)
	if total_mobs >= max_total or count >= max_count then
		return false
	end

	return true
end

return conditions
