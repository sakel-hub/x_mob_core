--[[
	x_mob_core - Per-Step Node Cache Subsystem
	Caches get_node and get_node_or_nil lookups per server tick
	to eliminate redundant engine C++ map lookups during pathfinding and steering.
]]

---@class NodeCacheSubsystem
local node_cache = {}

local global_node_cache = _G._x_mob_core_node_cache or {}
local global_node_or_nil_cache = _G._x_mob_core_node_or_nil_cache or {}
_G._x_mob_core_node_cache = global_node_cache
_G._x_mob_core_node_or_nil_cache = global_node_or_nil_cache

--- Clears the per-step node caches
function node_cache.clear()
	for k in pairs(global_node_cache) do
		global_node_cache[k] = nil
	end
	for k in pairs(global_node_or_nil_cache) do
		global_node_or_nil_cache[k] = nil
	end
end

core.register_globalstep(function()
	node_cache.clear()
end)

--- Retrieves node table from per-step cache or queries engine
---@param pos Vector Node world position
---@return table node Node definition table {name: string, param1: number, param2: number}
function node_cache.get_node(pos)
	local hash = core.hash_node_position(pos)
	local n = global_node_cache[hash]
	if not n then
		n = core.get_node(pos)
		global_node_cache[hash] = n
	end
	return n
end

--- Retrieves node table or nil from per-step cache or queries engine
---@param pos Vector Node world position
---@return table|nil node Node definition table {name: string, param1: number, param2: number} or nil
function node_cache.get_node_or_nil(pos)
	local hash = core.hash_node_position(pos)
	local n = global_node_or_nil_cache[hash]
	if n == false then return nil end
	if not n then
		n = core.get_node_or_nil(pos)
		global_node_or_nil_cache[hash] = n or false
	end
	return n
end

return node_cache
