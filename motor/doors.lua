--[[
	x_mob_core - Doors Subsystem
	Door and trapdoor traversal, area protection validation,
	smart door opening, and forward door scanning for pathfinding mobs.
]]

---@class DoorsSubsystem
local doors = {}

local modpath = core.get_modpath("x_mob_core") or "."
local node_cache = dofile(modpath .. "/motor/node_cache.lua")

--- Checks if a door or trapdoor is currently already open
---@param pos Vector World position of door node
---@param node? table Node table {name, param1, param2}
---@param def? table Registered node definition
---@return boolean is_open True if door is already open
function doors.is_door_open(pos, node, def)
	local check_pos = pos
	local check_node = node
	local check_def = def
	if check_node and check_node.name == "doors:hidden" then
		check_pos = {x = pos.x, y = pos.y - 1, z = pos.z}
		check_node = node_cache.get_node(check_pos)
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
---@param abilities? table Mob capabilities table
---@return boolean is_openable True if node is an openable door and mob can open doors
function doors.is_openable_door(name, abilities)
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
---@param node? table Node table {name, param1, param2}
---@param def? table Registered node definition
---@param _user? ObjectRef Entity attempting the interaction
---@return boolean success True if door is open or was successfully opened
function doors.try_open_door(pos, node, def, _user)
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
		door_node = node_cache.get_node(door_pos)
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
	if doors.is_door_open(door_pos, door_node, door_def) then
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
		if not doors.is_door_open(door_pos, door_node, door_def) then
			doors_mod.door_toggle(door_pos, door_node, nil)
			if doors.is_door_open(door_pos, door_node, door_def) then
				return true
			end
		end
	end

	-- Fallback to on_rightclick ONLY if still closed
	if door_def and door_def.on_rightclick then
		if not doors.is_door_open(door_pos, door_node, door_def) then
			door_def.on_rightclick(door_pos, door_node, nil)
			if doors.is_door_open(door_pos, door_node, door_def) then
				return true
			end
		end
	end

	return doors.is_door_open(door_pos, door_node, door_def)
end

--- Checks and opens an openable door node at a specific position
---@param pos Vector World position
---@param abilities? table Ability flags table
---@param object? ObjectRef User/mob object
---@return boolean opened
function doors.try_open_door_at_pos(pos, abilities, object)
	if not (abilities and abilities.can_open_doors) or not pos then return false end
	local node = node_cache.get_node(pos)
	if doors.is_openable_door(node.name, abilities) then
		local def = core.registered_nodes[node.name] or {}
		if not doors.is_door_open(pos, node, def) then
			return doors.try_open_door(pos, node, def, object)
		end
	end
	return false
end

--- Checks and proactively opens any closed doors directly ahead in movement direction
---@param pos Vector Current entity position
---@param dir? Vector Direction of movement
---@param abilities? table Mob capabilities table
---@param object? ObjectRef Entity ObjectRef
function doors.check_and_open_forward_doors(pos, dir, abilities, object)
	if not (abilities and abilities.can_open_doors) or not dir then return end
	if math.abs(dir.x) <= 0.01 and math.abs(dir.z) <= 0.01 then return end
	local fwd_x = math.floor(pos.x + dir.x * 1.1 + 0.5)
	local fwd_z = math.floor(pos.z + dir.z * 1.1 + 0.5)
	local fwd_y = math.floor(pos.y + 0.5)
	for dy = 0, 1 do
		doors.try_open_door_at_pos({x = fwd_x, y = fwd_y + dy, z = fwd_z}, abilities, object)
	end
end

return doors
