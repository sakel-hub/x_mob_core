--[[
	x_mob_core - Terrain Safety & Hazard Detection Subsystem
	Step safety validation, cliff avoidance, liquid hazard testing,
	volumetric corridor line-of-sight, and shoreline searching.
]]

---@class SafetySubsystem
local safety = {}

local modpath = core.get_modpath("x_mob_core") or "."
local utils = dofile(modpath .. "/core/utils.lua")
local node_cache = dofile(modpath .. "/motor/node_cache.lua")
local doors = dofile(modpath .. "/motor/doors.lua")

--- Checks if a mob is strictly aquatic (shoal fish, shark, aquatic faction)
---@param self table Entity instance or mob definition table
---@return boolean is_aquatic
function safety.is_aquatic_mob(self)
	local def = (self and self._def) or self
	if not def then return false end
	if (def.shoal ~= nil) or (self.shoal ~= nil) or
		(def.shoal_member == true) or (self.shoal_member == true) or
		(def.is_aquatic == true) or (self.is_aquatic == true) or
		(def.aquatic == true) or (self.aquatic == true) or
		(def.type == "aquatic") or (self.type == "aquatic") or
		(def.mob_type == "aquatic") or (self.mob_type == "aquatic") or
		(def.can_breathe == false and def.can_fly_in_water == true) or
		(self.can_breathe == false and self.can_fly_in_water == true) then
		return true
	end
	local facts = self.factions or def.factions
	if type(facts) == "table" then
		if facts.aquatic or facts.fish or facts.shoal then
			return true
		end
		for i = 1, #facts do
			local f = facts[i]
			if f == "aquatic" or f == "fish" or f == "shoal" then
				return true
			end
		end
	end
	local name = def.name or self.name
	if type(name) == "string" and (name:find("fish") or name:find("shark")) then
		return true
	end
	return false
end

--- Scans for the nearest dry, walkable shoreline position from a liquid location
--- Uses expanding concentric box rings with early exit for maximum performance
---@param pos Vector Current world position in liquid
---@param max_radius? number Maximum search radius in nodes (default: 16)
---@return Vector|nil shore_pos Nearest dry walkable shore position or nil
function safety.find_nearest_shore_pos(pos, max_radius)
	local px = math.floor(pos.x + 0.5)
	local py = math.floor(pos.y + 0.5)
	local pz = math.floor(pos.z + 0.5)

	-- If pos is submerged in liquid, anchor vertical search around the liquid surface
	for sy = py, py + 24 do
		local snode = node_cache.get_node_or_nil({x = px, y = sy, z = pz})
		local sdef = snode and core.registered_nodes[snode.name]
		if not sdef or not sdef.liquidtype or sdef.liquidtype == "none" then
			if sy > py then
				py = sy - 1
			end
			break
		end
	end

	local max_r = max_radius or 16
	local max_r_sq = max_r * max_r

	local best_d_sq = 999999
	local best_shore = nil

	for r = 1, max_r do
		if best_shore and (r * r) > best_d_sq then
			break
		end

		for dx = -r, r do
			local abs_dx = math.abs(dx)
			local min_z = (abs_dx == r) and -r or -r
			local max_z = (abs_dx == r) and r or r
			local step_z = (abs_dx == r) and 1 or (2 * r)

			for dz = min_z, max_z, step_z do
				local d_sq = dx * dx + dz * dz
				if d_sq <= max_r_sq and d_sq < best_d_sq then
					local nx = px + dx
					local nz = pz + dz
					for dy = -1, 3 do
						local ny = py + dy
						local ng = node_cache.get_node_or_nil({x = nx, y = ny - 1, z = nz})
						local dg = ng and core.registered_nodes[ng.name]
						if dg and dg.walkable and (not dg.liquidtype or dg.liquidtype == "none") then
							local nf = node_cache.get_node_or_nil({x = nx, y = ny, z = nz})
							local df = nf and core.registered_nodes[nf.name]
							if df and (not df.walkable) and (not df.liquidtype or df.liquidtype == "none") then
								best_d_sq = d_sq
								best_shore = {x = nx, y = ny, z = nz}
								break
							end
						end
					end
				end
			end
		end
	end

	return best_shore
end

--- Volumetric multi-ray corridor check to determine if a direct straight-line path is clear.
--- Checks eye-level, torso-level, and left/right lateral extents.
--- If any obstacle blocks the corridor, direct path is obstructed and A* is required.
---@param pos Vector Mob base world position
---@param target_pos Vector Target world position
---@param eye_offset? number Eye height offset above base pos
---@param half_width? number Mob collision half-width (default 0.4)
---@return boolean is_clear True if entire corridor has unobstructed line of sight
function safety.check_corridor_line_of_sight(pos, target_pos, eye_offset, half_width)
	-- Headroom clearance ray verifying upper space along corridor
	local head_h = math.max(1.15, (eye_offset or 1.5))
	local m_head = {x = pos.x, y = pos.y + head_h, z = pos.z}
	local t_head = {x = target_pos.x, y = target_pos.y + 1.5, z = target_pos.z}
	if not utils.line_of_sight(m_head, t_head) then
		return false
	end
	local t_head_lvl = {x = target_pos.x, y = target_pos.y + head_h, z = target_pos.z}
	if not utils.line_of_sight(m_head, t_head_lvl) then
		return false
	end

	-- Eye-level ray verifying line of sight
	local m_eye = {x = pos.x, y = pos.y + (eye_offset or 1.5), z = pos.z}
	local t_eye = {x = target_pos.x, y = target_pos.y + 1.5, z = target_pos.z}
	if not utils.line_of_sight(m_eye, t_eye) then
		return false
	end

	-- Torso-level ray for low walls, fences, slabs, and corners
	local m_torso = {x = pos.x, y = pos.y + 0.6, z = pos.z}
	local t_torso = {x = target_pos.x, y = target_pos.y + 0.6, z = target_pos.z}
	if not utils.line_of_sight(m_torso, t_torso) then
		return false
	end

	-- Lateral shoulder clearance rays for wide entities
	local hw = half_width or 0.4
	if hw >= 0.3 then
		local dx = target_pos.x - pos.x
		local dz = target_pos.z - pos.z
		local dist = math.sqrt(dx * dx + dz * dz)
		if dist > 1.5 then
			local perp_x = -dz / dist * (hw * 0.75)
			local perp_z = dx / dist * (hw * 0.75)

			local left_start = {x = pos.x + perp_x, y = pos.y + 0.8, z = pos.z + perp_z}
			local left_end = {x = target_pos.x + perp_x, y = target_pos.y + 0.8, z = target_pos.z + perp_z}
			if not utils.line_of_sight(left_start, left_end) then
				return false
			end

			local right_start = {x = pos.x - perp_x, y = pos.y + 0.8, z = pos.z - perp_z}
			local right_end = {x = target_pos.x - perp_x, y = target_pos.y + 0.8, z = target_pos.z - perp_z}
			if not utils.line_of_sight(right_start, right_end) then
				return false
			end
		end
	end

	return true
end

--- Checks whether a world position is a valid, standing location (not inside a wall, has ground support)
---@param pos Vector
---@return boolean is_valid True if pos is clear of walkable blocks and supported by ground
function safety.is_valid_stand_pos(pos)
	if not pos then return false end
	local nx = math.floor(pos.x + 0.5)
	local ny = math.floor(pos.y + 0.5)
	local nz = math.floor(pos.z + 0.5)
	local foot = node_cache.get_node_or_nil({x = nx, y = ny, z = nz})
	local head = node_cache.get_node_or_nil({x = nx, y = ny + 1, z = nz})
	local ground = node_cache.get_node_or_nil({x = nx, y = ny - 1, z = nz})
	local def_f = foot and core.registered_nodes[foot.name]
	local def_h = head and core.registered_nodes[head.name]
	local def_g = ground and core.registered_nodes[ground.name]
	if (def_f and def_f.walkable) or (def_h and def_h.walkable) then
		return false
	end
	if not (def_g and def_g.walkable) then
		return false
	end
	return true
end

--- Checks if entity is in liquid and calculates water surface and immersion level
---@param pos Vector World position
---@param abilities? table Mob abilities table
---@param mob_height? number Height of mob (default 1.5)
---@return boolean in_liquid True if in liquid and submerged or at waterline
---@return boolean is_submerged True if mob is submerged below target swimming waterline
---@return number|nil surface_y Y elevation of topmost water surface in node column
---@return number target_vy Recommended vertical velocity to reach/maintain swimming depth
function safety.check_in_liquid(pos, abilities, mob_height)
	if not pos or type(pos) ~= "table" then
		return false, false, nil, 0
	end

	local px = math.floor(pos.x + 0.5)
	local pz = math.floor(pos.z + 0.5)
	local py = math.floor(pos.y + 0.5)

	local surface_y = nil
	for iy = py + 16, py - 2, -1 do
		local node = node_cache.get_node_or_nil({x = px, y = iy, z = pz})
		local def = node and core.registered_nodes[node.name]
		if def and def.liquidtype and def.liquidtype ~= "none" then
			surface_y = iy + 0.5
			break
		end
	end

	if not surface_y then
		return false, false, nil, 0
	end

	local h = mob_height or 1.5
	local target_depth = h * 0.48
	local target_y = surface_y - target_depth

	if pos.y >= surface_y then
		return false, false, surface_y, 0
	end

	local in_liquid = true
	local diff = target_y - pos.y
	local is_submerged = (diff > 0.6)

	local target_vy
	if abilities and abilities.is_floating then
		is_submerged = true
		target_vy = 3.2
	elseif diff > 0.08 then
		target_vy = math.min(1.8, math.max(0.4, diff * 2.2))
	elseif diff < -0.08 then
		target_vy = math.max(-1.2, diff * 2.5)
	else
		target_vy = diff * 2.0
	end

	return in_liquid, is_submerged, surface_y, target_vy
end

--- Checks whether a step in the given horizontal direction is safe for a ground mob:
--- - Detects cliffs (drops >= 3 blocks)
--- - Detects un-swimmable liquid (water, river water)
--- - Detects damaging hazard nodes (lava, fire)
--- - Verifies 1-node step-up or direct ground footstep
---@param pos Vector Mob position
---@param move_dir Vector Horizontal direction vector {x, y, z}
---@param abilities? table Mob abilities (can_swim, can_climb, can_crawl)
---@param max_drop? number Maximum safe drop height (default 2)
---@return boolean is_safe True if the step is physically safe to take
---@return string? reason Rejection reason if not safe ("wall", "cliff", "hazard", "water", "headroom")
function safety.is_step_safe(pos, move_dir, abilities, max_drop)
	local dlen = math.sqrt((move_dir.x or 0) * (move_dir.x or 0) + (move_dir.z or 0) * (move_dir.z or 0))
	if dlen < 1e-4 then
		return true
	end

	local dx = (move_dir.x or 0) / dlen
	local dz = (move_dir.z or 0) / dlen
	local step_dist = 1.15
	local max_d = max_drop or ((abilities and abilities.can_crawl) and 3 or 2)

	local target_x = math.floor(pos.x + dx * step_dist + 0.5)
	local target_z = math.floor(pos.z + dz * step_dist + 0.5)

	local foot_y = math.floor(pos.y + 0.5)

	if abilities and abilities.is_floating then
		local f_node = node_cache.get_node({x = target_x, y = foot_y, z = target_z})
		local f_def = core.registered_nodes[f_node.name]
		if f_def and f_def.walkable then
			return false, "wall"
		end
		if f_def and f_def.damage_per_second and f_def.damage_per_second > 0 then
			return false, "hazard"
		end
		if f_def and f_def.liquidtype and f_def.liquidtype ~= "none" and
		   (not abilities.can_swim or (abilities and abilities.disallow_water)) then
			if not (abilities and (abilities.allow_water_escape or abilities.in_liquid)) then
				return false, "water"
			end
		end

		local h_node = node_cache.get_node({x = target_x, y = foot_y + 1, z = target_z})
		local h_def = core.registered_nodes[h_node.name]
		if h_def and h_def.walkable then
			return false, "wall"
		end
		if h_def and h_def.damage_per_second and h_def.damage_per_second > 0 then
			return false, "hazard"
		end

		-- Check sub-surface nodes underneath the floating entity (hover offset clearance)
		-- Floating mobs hover above ground or water. If they disallow water or cannot swim,
		-- inspect downwards to detect water surfaces and hazards under their flight path.
		for dy = 1, 3 do
			local sub_node = node_cache.get_node({x = target_x, y = foot_y - dy, z = target_z})
			local sub_def = core.registered_nodes[sub_node.name]
			if sub_def then
				if sub_def.damage_per_second and sub_def.damage_per_second > 0 then
					return false, "hazard"
				end
				if sub_def.liquidtype and sub_def.liquidtype ~= "none" and
				   (abilities and abilities.disallow_water) then
					return false, "water"
				end
				if sub_def.walkable then
					break
				end
			end
		end

		return true
	end

	local current_ground_y = foot_y - 1

	local node_under = node_cache.get_node({
		x = math.floor(pos.x + 0.5),
		y = current_ground_y,
		z = math.floor(pos.z + 0.5),
	})
	local def_under = core.registered_nodes[node_under.name]
	if not (def_under and def_under.walkable) then
		local node_under2 = node_cache.get_node({
			x = math.floor(pos.x + 0.5),
			y = current_ground_y - 1,
			z = math.floor(pos.z + 0.5),
		})
		local def_under2 = core.registered_nodes[node_under2.name]
		if def_under2 and def_under2.walkable then
			current_ground_y = current_ground_y - 1
			foot_y = foot_y - 1
		end
	end

	-- Check 1: Step-Up (+1 block)
	local node_step_up_ground = node_cache.get_node({x = target_x, y = foot_y, z = target_z})
	local def_sug = core.registered_nodes[node_step_up_ground.name]
	local sug_openable = doors.is_openable_door(node_step_up_ground.name, abilities)
	if def_sug and def_sug.walkable and not sug_openable then
		local is_tall = (core.get_item_group(node_step_up_ground.name, "fence") or 0) > 0 or
			(core.get_item_group(node_step_up_ground.name, "wall") or 0) > 0 or
			(core.get_item_group(node_step_up_ground.name, "pane") or 0) > 0 or
			(core.get_item_group(node_step_up_ground.name, "iron_bars") or 0) > 0 or
			(node_step_up_ground.name:find("fence") ~= nil) or
			(node_step_up_ground.name:find("wall") ~= nil) or
			(node_step_up_ground.name:find("bars") ~= nil)
		if is_tall and not (abilities and abilities.can_crawl) then
			return false, "wall"
		end

		local node_head1 = node_cache.get_node({x = target_x, y = foot_y + 1, z = target_z})
		local def_h1 = core.registered_nodes[node_head1.name]
		local node_head2 = node_cache.get_node({x = target_x, y = foot_y + 2, z = target_z})
		local def_h2 = core.registered_nodes[node_head2.name]

		if def_h1 and def_h1.walkable and not doors.is_openable_door(node_head1.name, abilities) then
			if abilities and abilities.can_crawl then
				return true
			end
			return false, "wall"
		end
		if def_h2 and def_h2.walkable and not (abilities and abilities.can_crawl) and
		   not doors.is_openable_door(node_head2.name, abilities) then
			return false, "headroom"
		end
		if (def_h1 and def_h1.damage_per_second and def_h1.damage_per_second > 0) then
			return false, "hazard"
		end
		if (def_h1 and def_h1.liquidtype and def_h1.liquidtype ~= "none" and
		   (not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water))) then
			return false, "water"
		end
		return true
	end

	-- Check 2: Level Walk
	local node_foot = node_cache.get_node({x = target_x, y = foot_y, z = target_z})
	local def_foot = core.registered_nodes[node_foot.name]

	if def_foot and def_foot.walkable then
		if abilities and abilities.can_crawl then
			local node_head1 = node_cache.get_node({x = target_x, y = foot_y + 1, z = target_z})
			local def_h1 = core.registered_nodes[node_head1.name]
			if def_h1 and def_h1.liquidtype and def_h1.liquidtype ~= "none" and
			   (not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water)) then
				return false, "water"
			end
			return true
		end
	end

	if def_foot and def_foot.damage_per_second and def_foot.damage_per_second > 0 then
		return false, "hazard"
	end

	if def_foot and def_foot.liquidtype and def_foot.liquidtype ~= "none" then
		if not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water) then
			if not (abilities and (abilities.allow_water_escape or abilities.in_liquid)) then
				return false, "water"
			end
		end
	end

	if abilities and abilities.can_climb then
		if def_foot and def_foot.climbable then return true end
	end

	local node_ground = node_cache.get_node({x = target_x, y = current_ground_y, z = target_z})
	local def_ground = core.registered_nodes[node_ground.name]

	if abilities and abilities.can_climb then
		if def_ground and def_ground.climbable then return true end
	end

	if def_ground and def_ground.liquidtype and def_ground.liquidtype ~= "none" then
		if not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water) then
			if not (abilities and (abilities.allow_water_escape or abilities.in_liquid)) then
				return false, "water"
			end
		end
	end

	if def_ground and def_ground.damage_per_second and def_ground.damage_per_second > 0 then
		return false, "hazard"
	end

	local is_solid_walkable = def_ground and def_ground.walkable and
		not (def_ground.liquidtype and def_ground.liquidtype ~= "none")
	local is_swimmable_water = ((abilities and abilities.can_swim and not (abilities and abilities.disallow_water)) or
		(abilities and (abilities.allow_water_escape or abilities.in_liquid))) and (
		(def_ground and def_ground.liquidtype and def_ground.liquidtype ~= "none") or
		(def_foot and def_foot.liquidtype and def_foot.liquidtype ~= "none")
	)
	local can_traverse_ground = is_solid_walkable or is_swimmable_water
	if can_traverse_ground then
		local node_head = node_cache.get_node({x = target_x, y = foot_y + 1, z = target_z})
		local def_head = core.registered_nodes[node_head.name]
		if def_head and def_head.walkable and not (abilities and abilities.can_crawl) and
		   not doors.is_openable_door(node_head.name, abilities) then
			return false, "headroom"
		end
		return true
	end

	-- Check 3: Drop-Down
	for drop = 1, max_d do
		local drop_ground_y = current_ground_y - drop
		local drop_foot_y = drop_ground_y + 1

		local n_dg = node_cache.get_node({x = target_x, y = drop_ground_y, z = target_z})
		local def_dg = core.registered_nodes[n_dg.name]
		local n_df = node_cache.get_node({x = target_x, y = drop_foot_y, z = target_z})
		local def_df = core.registered_nodes[n_df.name]

		if (def_df and def_df.damage_per_second and def_df.damage_per_second > 0) or
		   (def_dg and def_dg.damage_per_second and def_dg.damage_per_second > 0) then
			return false, "hazard"
		end

		if ((def_df and def_df.liquidtype and def_df.liquidtype ~= "none") or
		    (def_dg and def_dg.liquidtype and def_dg.liquidtype ~= "none")) and
		   (not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water)) then
			return false, "water"
		end

		local can_drop_onto = (def_dg and def_dg.walkable and not (def_dg.liquidtype and def_dg.liquidtype ~= "none")) or
			(abilities and abilities.can_swim and not (abilities and abilities.disallow_water) and (
				(def_dg and def_dg.liquidtype and def_dg.liquidtype ~= "none") or
				(def_df and def_df.liquidtype and def_df.liquidtype ~= "none")
			))
		if can_drop_onto then
			return true
		end
	end

	return false, "cliff"
end

--- Verifies that there is a continuous, safe ground path along the straight line
--- between pos and target_pos (no chasms, deep cliffs, or un-swimmable water).
---@param pos Vector Mob position
---@param target_pos Vector Target position
---@param abilities? table Mob abilities
---@return boolean has_ground True if continuous safe ground exists
---@return string? reason Failure reason if not safe ("water", "cliff", "hazard", etc.)
function safety.check_ground_line_of_sight(pos, target_pos, abilities)
	local dx = target_pos.x - pos.x
	local dz = target_pos.z - pos.z
	local flat_dist = math.sqrt(dx * dx + dz * dz)

	if flat_dist <= 1.5 then
		return safety.is_step_safe(pos, {x = dx, y = 0, z = dz}, abilities)
	end

	local dir_x = dx / flat_dist
	local dir_z = dz / flat_dist

	local step_size = 1.8
	local num_steps = math.min(12, math.floor(flat_dist / step_size))

	local prev_ground_y = math.floor(pos.y + 0.5) - 1
	for i = 1, num_steps do
		local sample_dist = i * step_size
		local sx = math.floor(pos.x + dir_x * sample_dist + 0.5)
		local sz = math.floor(pos.z + dir_z * sample_dist + 0.5)

		local t = sample_dist / flat_dist
		local interp_y = math.floor(pos.y + (target_pos.y - pos.y) * t + 0.2)

		local found_ground = false
		local ground_y = nil
		for cy = interp_y + 1, interp_y - 2, -1 do
			local node = node_cache.get_node({x = sx, y = cy, z = sz})
			local def = core.registered_nodes[node.name]
			if def then
				if def.damage_per_second and def.damage_per_second > 0 then
					return false, "hazard"
				end
				if def.liquidtype and def.liquidtype ~= "none" then
					if not (abilities and abilities.can_swim) or (abilities and abilities.disallow_water) then
						return false, "water"
					end
				end
				local is_door_node = doors.is_openable_door(node.name, abilities)
				local is_valid_medium = (def.walkable and not is_door_node) or
					(def.climbable and abilities and abilities.can_climb) or
					(abilities and abilities.can_swim and not (abilities and abilities.disallow_water) and
					 def.liquidtype and def.liquidtype ~= "none")
				if is_valid_medium then
					found_ground = true
					ground_y = cy
					break
				end
			end
		end

		if not found_ground then
			return false, "cliff"
		end

		if not (abilities and (abilities.can_crawl or abilities.is_floating)) then
			local cur_node = ground_y and node_cache.get_node({x = sx, y = ground_y, z = sz})
			local cur_def = cur_node and core.registered_nodes[cur_node.name]
			local is_climbing_step = abilities and abilities.can_climb and cur_def and cur_def.climbable
			if not is_climbing_step and ground_y and prev_ground_y and (ground_y - prev_ground_y) > 1.25 then
				return false, "wall"
			end

			if ground_y then
				local torso_node = node_cache.get_node({x = sx, y = ground_y + 1, z = sz})
				local torso_def = core.registered_nodes[torso_node.name]
				if torso_def and torso_def.walkable and not doors.is_openable_door(torso_node.name, abilities) then
					return false, "wall"
				end

				local head_node = node_cache.get_node({x = sx, y = ground_y + 2, z = sz})
				local head_def = core.registered_nodes[head_node.name]
				if head_def and head_def.walkable and not doors.is_openable_door(head_node.name, abilities) then
					return false, "headroom"
				end
			end
		end
		if ground_y then
			prev_ground_y = ground_y
		end
	end

	return true
end

--- Initializes an entity's inherent abilities and active dynamic abilities table
---@param self table Entity instance
---@param def? table Entity definition table
function safety.init_abilities(self, def)
	def = def or self._def or (self.name and core.registered_entities[self.name]) or {}
	if not self.path_state then
		self.path_state = {
			waypoints = nil,
			index = 1,
			timer = 0.0,
			is_calculating = false,
		}
	end

	if not self._inherent_abilities then
		local doors_val = false
		if self.can_open_doors ~= nil then
			doors_val = (self.can_open_doors == true)
		elseif def.can_open_doors ~= nil then
			doors_val = (def.can_open_doors == true)
		elseif self.abilities and self.abilities.can_open_doors ~= nil then
			doors_val = (self.abilities.can_open_doors == true)
		end

		local climb_val = false
		if self.can_climb ~= nil then
			climb_val = (self.can_climb == true)
		elseif def.can_climb ~= nil then
			climb_val = (def.can_climb == true)
		elseif self.abilities and self.abilities.can_climb ~= nil then
			climb_val = (self.abilities.can_climb == true)
		end

		local is_flt = (self.is_floating == true) or (def.is_floating == true)
		local swim_val = (self.can_swim == true) or (def.can_swim == true) or is_flt
		if self.can_swim == false or def.can_swim == false then
			swim_val = false
		elseif self.can_swim == nil and def.can_swim == nil and self.abilities and self.abilities.can_swim ~= nil then
			swim_val = (self.abilities.can_swim == true)
		end

		local crawl_val = (self.can_crawl == true) or (def.can_crawl == true) or
			(self.abilities and self.abilities.can_crawl == true)

		self._inherent_abilities = {
			can_open_doors = doors_val == true,
			can_climb = climb_val == true,
			can_swim = swim_val == true,
			can_crawl = crawl_val == true,
			is_floating = is_flt == true,
		}
	end

	if not self.abilities then
		local is_aquatic = safety.is_aquatic_mob(self)
		local is_airborne = self._inherent_abilities and self._inherent_abilities.is_floating == true
		self.abilities = {
			can_open_doors = false,
			can_climb = false,
			can_swim = is_aquatic and (self._inherent_abilities.can_swim == true) or false,
			can_crawl = self._inherent_abilities.can_crawl == true,
			is_floating = self._inherent_abilities.is_floating == true,
			disallow_water = not is_aquatic and not is_airborne,
		}
	end
	self.half_width = self.half_width or def.half_width or 0.4
end

return safety
