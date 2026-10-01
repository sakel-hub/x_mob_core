--[[
	x_mob_core - Spawn Rule Registry
	Collects spawn definitions and dynamically aggregates surface nodes with zero hardcoding
]]

---@class SpawningRegistry
---@field spawns SpawnDefinition[]
---@field surface_nodes table<string, boolean>
---@field registered_groups table<string, boolean>
---@field surface_nodes_dirty boolean
---@field cached_surface_node_list string[]|nil
local registry = {
	spawns = {},
	surface_nodes = {},
	registered_groups = {},
	surface_nodes_dirty = true,
	cached_surface_node_list = nil,
}

--- Registers a mob for natural spawning
---@param mob_name string Registered entity technical name
---@param def SpawnConfig|SpawnDefinition Spawn parameters
function registry.register_spawn(mob_name, def)
	def.mob_name = mob_name
	def.chance = def.chance or 1000
	def.active_object_count = def.active_object_count or 1
	def.group_min = def.group_min or 1
	def.group_max = def.group_max or def.group_min
	def.min_light = def.min_light or 0
	def.max_light = def.max_light or 15
	def.min_elevation = def.min_elevation or -31000
	def.max_elevation = def.max_elevation or 31000

	-- Pre-parse nodes, groups, and biomes into fast O(1) lookup sets
	def._parsed_nodes = {}
	def._parsed_groups = {}
	def._parsed_biomes = {}
	def._parsed_exclude_nodes = {}
	def._parsed_exclude_groups = {}

	table.insert(registry.spawns, def)

	-- Dynamically collect specific node names and groups for mapgen area searches
	if def.nodes then
		for _, n in ipairs(def.nodes) do
			if n:sub(1, 6) == "group:" then
				local grp = n:sub(7)
				def._parsed_groups[grp] = true
				registry.registered_groups[grp] = true
				if grp == "sand" then
					-- Everness compatibility: everness sands define everness_sand and material_sand
					def._parsed_groups["everness_sand"] = true
					def._parsed_groups["material_sand"] = true
					registry.registered_groups["everness_sand"] = true
					registry.registered_groups["material_sand"] = true
				elseif grp == "sandstone" then
					def._parsed_groups["everness_sandstone"] = true
					registry.registered_groups["everness_sandstone"] = true
				end
			else
				def._parsed_nodes[n] = true
				registry.surface_nodes[n] = true
				registry.surface_nodes_dirty = true
			end
		end
	end

	-- Pre-parse exclusion filters (nodes or groups to explicitly bypass)
	if def.exclude_nodes then
		for _, n in ipairs(def.exclude_nodes) do
			if n:sub(1, 6) == "group:" then
				def._parsed_exclude_groups[n:sub(7)] = true
			else
				def._parsed_exclude_nodes[n] = true
			end
		end
	end
	if def.exclude_groups then
		for _, g in ipairs(def.exclude_groups) do
			local grp = (g:sub(1, 6) == "group:") and g:sub(7) or g
			def._parsed_exclude_groups[grp] = true
		end
	end

	if def.biomes then
		for _, b in ipairs(def.biomes) do
			def._parsed_biomes[b] = true
		end
	end
end

--- Returns all registered spawn definitions
---@return SpawnDefinition[]
function registry.get_spawns()
	return registry.spawns
end

--- Expands registered spawn groups into matching walkable surface or aquatic source nodes
core.register_on_mods_loaded(function()
	if not next(registry.registered_groups) then return end
	for group_name in pairs(registry.registered_groups) do
		for name, node_def in pairs(core.registered_nodes) do
			local is_valid_surface = node_def.walkable or (group_name == "water" and node_def.liquidtype == "source")
			if is_valid_surface and name ~= "air" and name ~= "ignore" then
				if core.get_item_group(name, group_name) > 0 then
					registry.surface_nodes[name] = true
					registry.surface_nodes_dirty = true
				end
			end
		end
	end
end)

--- Returns flat list of all unique surface nodes registered across all mobs
---@return string[]
function registry.get_surface_nodes()
	if not registry.surface_nodes_dirty and registry.cached_surface_node_list then
		return registry.cached_surface_node_list
	end

	local list = {}
	for name in pairs(registry.surface_nodes) do
		table.insert(list, name)
	end

	-- Fallback if no specific nodes were provided: query common walkable terrain groups
	if #list == 0 then
		for name, def in pairs(core.registered_nodes) do
			if def.walkable and name ~= "air" and name ~= "ignore" then
				local is_ground = (core.get_item_group(name, "soil") > 0) or
					(core.get_item_group(name, "stone") > 0) or
					(core.get_item_group(name, "sand") > 0) or
					(core.get_item_group(name, "everness_sand") > 0) or
					(core.get_item_group(name, "material_sand") > 0) or
					(core.get_item_group(name, "everness_sandstone") > 0)
				if is_ground then
					table.insert(list, name)
				end
			end
		end
	end

	registry.cached_surface_node_list = list
	registry.surface_nodes_dirty = false
	return list
end

return registry
