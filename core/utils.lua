--[[
	x_mob_core - Utilities Subsystem
	UUID generation, table helpers, and spatial vector routines
]]

---@class UtilsSubsystem
local utils = {}

--- Generates an RFC 4122 Version 4 compliant UUID.
--- Uses Luanti's OS-backed SecureRandom for guaranteed uniqueness,
--- with an automatic RFC 4122 template math.random fallback.
---@return string uuid
function utils.generate_uuid()
	local sec_fn = rawget(_G, "SecureRandom")
	if type(sec_fn) == "function" then
		local sec_rnd = sec_fn()
		if sec_rnd and sec_rnd.next_bytes then
			local raw = sec_rnd:next_bytes(16)
			if raw and #raw == 16 then
				local b = { string.byte(raw, 1, 16) }
				b[7] = math.floor(b[7] % 16) + 64
				b[9] = math.floor(b[9] % 64) + 128
				return string.format("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
					b[1], b[2], b[3], b[4],
					b[5], b[6],
					b[7], b[8],
					b[9], b[10],
					b[11], b[12], b[13], b[14], b[15], b[16])
			end
		end
	end

	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)
end

--- Shallow copies a table
---@generic T : table
---@param tbl T
---@return T
function utils.shallow_copy(tbl)
	if type(tbl) ~= "table" then return tbl end
	local copy = {}
	for k, v in pairs(tbl) do
		copy[k] = v
	end
	return copy
end

--- Line of sight check between two points using native engine C++ ray traversal with liquid penetration support
---@param p1 Vector
---@param p2 Vector
---@return boolean is_clear
function utils.line_of_sight(p1, p2)
	local clear, blocked_pos = core.line_of_sight(p1, p2)
	if clear then return true end

	-- core.line_of_sight treats any non-air node (including liquids/water) as an obstruction.
	-- If blocked by a non-walkable liquid node, verify true physical occlusion with a liquid-ignoring raycast.
	if blocked_pos then
		local node = core.get_node_or_nil(blocked_pos)
		local ndef = node and core.registered_nodes[node.name]
		if ndef and not ndef.walkable then
			local ray = core.raycast(p1, p2, false, false)
			for pt in ray do
				if pt.type == "node" then
					local bnode = core.get_node_or_nil(pt.under)
					local bdef = bnode and core.registered_nodes[bnode.name]
					if bdef and bdef.walkable then
						return false
					end
				end
			end
			return true
		end
	end

	return false
end

--- Checks if an ObjectRef is a valid living player or entity
---@param player ObjectRef Target entity
---@return boolean is_alive True if player reference is valid and alive
function utils.is_player_alive(player)
	if not player or not player:is_valid() then return false end
	if player:is_player() then
		return (player:get_hp() or 0) > 0
	end
	local luaent = player:get_luaentity()
	if luaent then
		if luaent.is_dead or (luaent.hp and luaent.hp <= 0) then
			return false
		end
		return true
	end
	return false
end

--- Finds the topmost solid ground surface near a given coordinate
---@param pos Vector Position to check
---@param max_down? number Maximum distance to search downwards (default: 8)
---@param max_up? number Maximum distance to search upwards (default: 3)
---@param walkable_only? boolean If true, requires walkable non-liquid node with headroom (default: true)
---@return number|nil ground_y Top surface height of highest ground node, or nil
function utils.get_ground_y(pos, max_down, max_up, walkable_only)
	local nx = math.floor(pos.x + 0.5)
	local ny = math.floor(pos.y + 0.5)
	local nz = math.floor(pos.z + 0.5)
	local top_y = ny + (max_up or 3)
	local btm_y = ny - (max_down or 8)

	for cy = top_y, btm_y, -1 do
		local node = core.get_node_or_nil({x = nx, y = cy, z = nz})
		if node and node.name ~= "air" and node.name ~= "ignore" then
			local def = core.registered_nodes[node.name]
			if def then
				if walkable_only ~= false then
					if def.walkable and (not def.liquidtype or def.liquidtype == "none") then
						local above = core.get_node_or_nil({x = nx, y = cy + 1, z = nz})
						local above_def = above and core.registered_nodes[above.name]
						if not above_def or not above_def.walkable then
							return cy + 0.5
						end
					end
				else
					return cy + 0.5
				end
			end
		end
	end
	return nil
end

--- Picks a ground-anchored wander waypoint near current position over solid walkable nodes
---@param current_pos Vector Current mob world position
---@param origin? Vector Center origin of wander boundary (default: current_pos)
---@param radius? number Maximum wander radius from origin (default: 10.0)
---@param min_dist? number Minimum step distance from current position (default: 3.0)
---@param max_dist? number Maximum step distance from current position (default: 7.5)
---@param hover_offset? number Vertical offset above detected ground (default: 1.4)
---@return Vector|nil waypoint Ground-anchored target position or nil
function utils.pick_ground_waypoint(current_pos, origin, radius, min_dist, max_dist, hover_offset)
	local center = origin or current_pos
	local max_rad = radius or 10.0
	local rad_sq = max_rad * max_rad
	local min_step = min_dist or 3.0
	local step_range = (max_dist or 7.5) - min_step
	local hover = hover_offset or 1.4

	for _ = 1, 8 do
		local angle = math.random() * math.pi * 2
		local dist = min_step + math.random() * step_range
		local cand_x = current_pos.x + math.cos(angle) * dist
		local cand_z = current_pos.z + math.sin(angle) * dist

		local odx = cand_x - center.x
		local odz = cand_z - center.z
		if (odx * odx + odz * odz) <= rad_sq then
			local ground_y = utils.get_ground_y({x = cand_x, y = current_pos.y, z = cand_z}, 4, 3, true)
			if ground_y then
				return {x = cand_x, y = ground_y + hover, z = cand_z}
			end
		end
	end

	local orig_gy = utils.get_ground_y(center, 6, 4, true)
	if orig_gy then
		return {x = center.x, y = orig_gy + hover, z = center.z}
	end
	return nil
end

local headroom_probe = {x = 0, y = 0, z = 0}
local avoid_probe = {x = 0, y = 0, z = 0}

--- Scans vertically upwards from origin to check distance to the first solid ceiling node.
---@param origin Vector Base position (e.g. foot or center coordinate)
---@param max_check? number Maximum nodes to scan upward (default: 4.0)
---@return number headroom Distance to first walkable ceiling node, or max_check if open sky
function utils.get_headroom(origin, max_check)
	local max_h = max_check or 4.0
	headroom_probe.x = math.floor(origin.x + 0.5)
	headroom_probe.z = math.floor(origin.z + 0.5)
	local base_y = math.floor(origin.y + 0.5)
	for dy = 1, math.floor(max_h + 0.5) do
		headroom_probe.y = base_y + dy
		local n = core.get_node_or_nil(headroom_probe)
		local def = n and core.registered_nodes[n.name]
		if def and def.walkable then
			return dy - 0.2
		end
	end
	return max_h
end

--- Verifies if a target coordinate is safely in passable air; if blocked, returns an adjusted clear position.
--- Probes lower elevations and ray-traces back towards safe_origin to prevent entities clipping into solid geometry.
---@param target_pos Vector Desired 3D coordinate
---@param safe_origin Vector Known safe origin or anchor (e.g. player or mob origin)
---@param look_dir? Vector Optional directional vector to tuck behind if in tight enclosure
---@return Vector clear_pos Adjusted safe 3D coordinate
function utils.avoid_solid_nodes(target_pos, safe_origin, look_dir)
	avoid_probe.x = math.floor(target_pos.x + 0.5)
	avoid_probe.y = math.floor(target_pos.y + 0.5)
	avoid_probe.z = math.floor(target_pos.z + 0.5)
	local node = core.get_node_or_nil(avoid_probe)
	local def = node and core.registered_nodes[node.name]
	if def and def.walkable then
		local hr = utils.get_headroom(safe_origin, 3.5)
		local safe_y

		if math.abs(target_pos.y - safe_origin.y) > 0.5 then
			-- Floating or elevated entity: adapt cruising height to available headroom
			safe_y = (hr < 2.3) and (safe_origin.y + 1.05) or target_pos.y

			-- Check lower elevations in case cave roof or ceiling forced entity into block
			if target_pos.y > safe_origin.y then
				avoid_probe.x = math.floor(target_pos.x + 0.5)
				avoid_probe.z = math.floor(target_pos.z + 0.5)
				for dy = -0.4, -1.8, -0.4 do
					avoid_probe.y = math.floor(target_pos.y + dy + 0.5)
					local l_node = core.get_node_or_nil(avoid_probe)
					local l_def = l_node and core.registered_nodes[l_node.name]
					if l_def and not l_def.walkable and (not l_def.liquidtype or l_def.liquidtype == "none") then
						return {x = target_pos.x, y = target_pos.y + dy, z = target_pos.z}
					end
				end
			end
		else
			-- Ground-level mob or spawner: check 1-node step-up onto ledge/stair first
			avoid_probe.y = math.floor(target_pos.y + 1.5)
			local step_up_node = core.get_node_or_nil(avoid_probe)
			local step_up_def = step_up_node and core.registered_nodes[step_up_node.name]
			if step_up_def and not step_up_def.walkable and (not step_up_def.liquidtype or step_up_def.liquidtype == "none")
				and hr >= 2.0 then
				return {x = target_pos.x, y = target_pos.y + 1.0, z = target_pos.z}
			end
			safe_y = safe_origin.y
		end

		-- Trace back towards safe_origin horizontally to stay in clear space
		avoid_probe.y = math.floor(safe_y + 0.5)
		for frac = 0.7, 0.2, -0.15 do
			local ix = safe_origin.x + (target_pos.x - safe_origin.x) * frac
			local iz = safe_origin.z + (target_pos.z - safe_origin.z) * frac
			avoid_probe.x = math.floor(ix + 0.5)
			avoid_probe.z = math.floor(iz + 0.5)
			local i_node = core.get_node_or_nil(avoid_probe)
			local i_def = i_node and core.registered_nodes[i_node.name]
			if i_def and not i_def.walkable and (not i_def.liquidtype or i_def.liquidtype == "none") then
				return {x = ix, y = safe_y, z = iz}
			end
		end

		-- Fallback for tight enclosed spaces: tuck behind look_dir
		if look_dir then
			local lhx = look_dir.x
			local lhz = look_dir.z
			local hlen = math.sqrt(lhx * lhx + lhz * lhz)
			if hlen > 0.05 then
				lhx = lhx / hlen
				lhz = lhz / hlen
				local tx = safe_origin.x - lhx * 1.0
				local tz = safe_origin.z - lhz * 1.0
				avoid_probe.x = math.floor(tx + 0.5)
				avoid_probe.z = math.floor(tz + 0.5)
				local t_node = core.get_node_or_nil(avoid_probe)
				local t_def = t_node and core.registered_nodes[t_node.name]
				if t_def and not t_def.walkable and (not t_def.liquidtype or t_def.liquidtype == "none") then
					return {x = tx, y = safe_y, z = tz}
				end
			end
		end

		return {x = safe_origin.x, y = safe_y, z = safe_origin.z}
	end
	return target_pos
end

--- Finds the top surface Y coordinate of the solid walkable ground below a given 3D position
---@param x number X world coordinate
---@param start_y number Y world coordinate
---@param z number Z world coordinate
---@param max_down? number Maximum distance to search downwards (default: 36)
---@return number|nil ground_y Top surface Y of solid node, or nil if none found
function utils.find_ground_level(x, start_y, z, max_down)
	return utils.get_ground_y({x = x, y = start_y, z = z}, max_down or 36, 3, true)
end

return utils

