--[[
	x_mob_core - Pre-Cached Content ID Registry for Zero-Overhead Pathfinding
	- Maps Luanti node definitions to integer Content IDs (0..65535)
	- Zero string table lookups inside A* search loops
	- Flat primitive arrays for cache locality and LuaJIT JIT compilation
	- Precomputes walkability, swimability, climbability, door openability, and costs
]]

---@class PathCache
---@field walkable table<integer, boolean>
---@field swimable table<integer, boolean>
---@field climbable table<integer, boolean>
---@field openable table<integer, boolean>
---@field tall_obstacle table<integer, boolean>
---@field base_cost table<integer, number>
---@field is_hazard table<integer, boolean>
---@field node_names table<integer, string>
---@field cid_air integer
---@field cid_ignore integer
---@field initialized boolean
local path_cache = {
	walkable = {},
	swimable = {},
	climbable = {},
	openable = {},
	tall_obstacle = {},
	base_cost = {},
	is_hazard = {},
	node_names = {},

	cid_air = 0,
	cid_ignore = 0,
	initialized = false,
}

--- Scans and caches all registered Luanti node definitions into flat integer arrays
function path_cache.init()
	local registered_nodes = core.registered_nodes

	path_cache.cid_air = core.get_content_id("air")
	path_cache.cid_ignore = core.get_content_id("ignore")

	for name, def in pairs(registered_nodes) do
		local cid = core.get_content_id(name)
		if cid and cid >= 0 then
			path_cache.node_names[cid] = name

			-- Walkability
			local is_walkable = def.walkable ~= false
			if name == "air" or name == "ignore" then
				is_walkable = false
			end
			path_cache.walkable[cid] = is_walkable

			-- Swimability (Liquids: water, river water, etc.)
			local is_liquid = (def.liquidtype and def.liquidtype ~= "none") or false
			path_cache.swimable[cid] = is_liquid

			-- Climbability (Ladders, vines, ropes)
			local is_climbable = (def.climbable == true)
			path_cache.climbable[cid] = is_climbable

			-- Openable Doors (group:door > 0 or doors:hidden, excluding steel/iron/locked variants)
			local door_group = core.get_item_group(name, "door") or 0
			local is_door = door_group > 0 or (name == "doors:hidden")
			local is_locked = (name:find("steel") ~= nil) or
				(name:find("iron") ~= nil) or
				(name:find("locked") ~= nil)
			local is_openable = is_door and not is_locked
			path_cache.openable[cid] = is_openable

			-- Environmental Hazards (Lava, fire, damage nodes)
			local dps = def.damage_per_second or 0
			local is_lava = (core.get_item_group(name, "lava") or 0) > 0
			local is_igniter = (core.get_item_group(name, "igniter") or 0) > 0
			local is_danger = (dps > 0) or is_lava or is_igniter
			path_cache.is_hazard[cid] = is_danger

			-- Tall obstacles (Fences, walls, iron bars > 1.0 node high that ground mobs cannot step over)
			local is_fence = (core.get_item_group(name, "fence") or 0) > 0 or
				(core.get_item_group(name, "wall") or 0) > 0 or
				(core.get_item_group(name, "pane") or 0) > 0 or
				(core.get_item_group(name, "iron_bars") or 0) > 0 or
				(name:find("fence") ~= nil) or
				(name:find("wall") ~= nil) or
				(name:find("bars") ~= nil)
			path_cache.tall_obstacle[cid] = is_fence

			-- Base Traversal Cost Precomputation
			if is_danger then
				path_cache.base_cost[cid] = math.huge
			elseif is_openable then
				path_cache.base_cost[cid] = 2.0 -- Interaction and obstruction penalty
			elseif is_liquid then
				path_cache.base_cost[cid] = 2.5 -- Viscosity drag penalty
			else
				path_cache.base_cost[cid] = 1.0 -- Standard traversal cost
			end
		end
	end

	-- Default entries for air and ignore
	if path_cache.cid_air then
		path_cache.walkable[path_cache.cid_air] = false
		path_cache.swimable[path_cache.cid_air] = false
		path_cache.climbable[path_cache.cid_air] = false
		path_cache.openable[path_cache.cid_air] = false
		path_cache.is_hazard[path_cache.cid_air] = false
		path_cache.tall_obstacle[path_cache.cid_air] = false
		path_cache.base_cost[path_cache.cid_air] = 1.0
	end

	if path_cache.cid_ignore then
		path_cache.walkable[path_cache.cid_ignore] = true -- Treat unloaded boundaries as solid
		path_cache.swimable[path_cache.cid_ignore] = false
		path_cache.climbable[path_cache.cid_ignore] = false
		path_cache.openable[path_cache.cid_ignore] = false
		path_cache.is_hazard[path_cache.cid_ignore] = true
		path_cache.tall_obstacle[path_cache.cid_ignore] = true
		path_cache.base_cost[path_cache.cid_ignore] = math.huge
	end

	path_cache.initialized = true
	core.log("action", "[x_mob_core] Pre-cached Content ID registry initialized with zero string lookups")
end

-- Automatically register on mods loaded callback
core.register_on_mods_loaded(path_cache.init)

return path_cache
