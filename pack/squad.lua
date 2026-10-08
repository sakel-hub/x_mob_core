--[[
	x_mob_core - Generic Pack & Squad Subsystem
	Manages multi-agent group identities, leader-follower rosters, and orphan adoption
]]

---@class SquadSubsystem
local squad = {}

local utils = dofile(core.get_modpath("x_mob_core") .. "/core/utils.lua")

-- Pre-allocated module-level scratch tables for zero-allocation cluster spawning
local scratch_pos = {x = 0, y = 0, z = 0}

local is_water_node = utils.is_water_node
local is_walkable_node = utils.is_walkable_node
local get_water_column_bounds = utils.get_water_column_bounds

--- Registers an entity as a pack leader
---@param self table Mob instance
---@param config MobPackDef Pack options
function squad.init_leader(self, config)
	if not self.pack_id then
		self.pack_id = config.pack_id or utils.generate_uuid()
	end
	self.pack_role = "leader"
	self.pack_followers = {}
	self.pack_max_followers = config.max_followers or 3
	self.pack_follower_type = config.follower_type
end

--- Registers an entity as a pack follower/member
---@param self table Mob instance
---@param config MobPackDef Pack options
function squad.init_member(self, config)
	self.pack_role = "member"
	self.pack_leader_type = config.leader_type
	self.pack_leash_distance = config.leash_distance or 18.0
	self.pack_regroup_distance = config.regroup_distance or 4.0
	self.pack_on_leader_lost = config.on_leader_lost
end

--- Cleans invalid/dead follower objects from a leader's roster in-place without table allocations
---@param self table Leader mob instance
---@return integer count
---@return table alive_followers
function squad.clean_followers(self)
	local followers = self.pack_followers
	if not followers then
		followers = {}
		self.pack_followers = followers
		return 0, followers
	end

	local write_idx = 1
	for read_idx = 1, #followers do
		local obj = followers[read_idx]
		local keep = false
		if utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent and (not self.pack_id or not ent.pack_id or ent.pack_id == self.pack_id)
				and (not ent.leader_obj or ent.leader_obj == self.object) then
				keep = true
			end
		end

		if keep then
			if write_idx ~= read_idx then
				followers[write_idx] = obj
			end
			write_idx = write_idx + 1
		end
	end

	for i = #followers, write_idx, -1 do
		followers[i] = nil
	end

	self.pack_followers = followers
	return #followers, followers
end

--- Registers a follower under a leader
---@param self table Leader mob instance
---@param follower_obj ObjectRef Follower entity object
---@param force? boolean If true, bypasses max_followers capacity limit (default: false)
---@return boolean added True if follower was newly registered or reconfirmed, false if full or invalid
function squad.add_follower(self, follower_obj, force)
	if not follower_obj or not follower_obj:is_valid() then return false end
	if not self.pack_followers then
		self.pack_followers = {}
	end

	-- Check if already registered: refresh leader pointers idempotently
	for i = 1, #self.pack_followers do
		if self.pack_followers[i] == follower_obj then
			local ent = follower_obj:get_luaentity()
			if ent then
				ent.leader_obj = self.object
				if self.pack_id then
					ent.pack_id = self.pack_id
					if ent.saved_data then
						ent.saved_data.pack_id = self.pack_id
					end
				end
			end
			return true
		end
	end

	local max_fol = self.pack_max_followers
	if not force and max_fol then
		squad.clean_followers(self)
		if #self.pack_followers >= max_fol then
			return false
		end
	end

	local ent = follower_obj:get_luaentity()
	if ent then
		ent.leader_obj = self.object
		if self.pack_id then
			ent.pack_id = self.pack_id
			if ent.saved_data then
				ent.saved_data.pack_id = self.pack_id
			end
		end
	end

	table.insert(self.pack_followers, follower_obj)
	return true
end

--- Removes a follower object from a leader's roster
---@param self table Leader mob instance
---@param follower_obj ObjectRef Follower entity object
function squad.remove_follower(self, follower_obj)
	local followers = self.pack_followers
	if not followers or not follower_obj then return end
	for i = #followers, 1, -1 do
		if followers[i] == follower_obj then
			table.remove(followers, i)
			break
		end
	end
end

local function matches_follower_type(expected, name)
	if not expected then return true end
	if type(expected) == "table" then
		for i = 1, #expected do
			if expected[i] == name then return true end
		end
		return false
	end
	return expected == name
end

--- Leader searches nearby area to adopt orphans or re-link separated followers
---@param self table Leader mob instance
---@param search_radius? number Radius to search (default: 32.0)
function squad.adopt_nearby_orphans(self, search_radius)
	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return end

	local count = squad.clean_followers(self)
	local max_fol = self.pack_max_followers or 3
	if count >= max_fol then return end

	local radius = search_radius or 32.0
	local nearby = core.get_objects_inside_radius(pos, radius)

	-- Pass 1: Re-adopt matching pack_id
	for i = 1, #nearby do
		if count >= max_fol then break end
		local obj = nearby[i]
		if obj ~= self.object and utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent and matches_follower_type(self.pack_follower_type, ent.name) then
				if ent.pack_id and self.pack_id and ent.pack_id == self.pack_id then
					if squad.add_follower(self, obj) then
						count = count + 1
					end
				end
			end
		end
	end

	-- Pass 2: Adopt unassigned orphans (only if quota not satisfied in pass 1)
	if count < max_fol then
		for i = 1, #nearby do
			if count >= max_fol then break end
			local obj = nearby[i]
			if obj ~= self.object and utils.is_player_alive(obj) then
				local ent = obj:get_luaentity()
				if ent and matches_follower_type(self.pack_follower_type, ent.name) then
					local has_valid_leader = ent.leader_obj and ent.leader_obj:is_valid()
					if not has_valid_leader and (not ent.pack_id or ent.pack_id ~= self.pack_id) then
						if squad.add_follower(self, obj) then
							count = count + 1
						end
					end
				end
			end
		end
	end
end

--- Disbands the pack and notifies all followers when the leader dies
---@param self table Leader mob instance
function squad.handle_leader_death(self)
	local followers = self.pack_followers
	if not followers then return end
	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	for i = 1, #followers do
		local obj = followers[i]
		if obj and obj:is_valid() then
			local ent = obj:get_luaentity()
			if ent and not ent.is_dead then
				ent.leader_obj = nil
				ent.pack_id = nil
				if ent.saved_data then
					ent.saved_data.pack_id = nil
				end
				local on_lost = ent.pack_on_leader_lost or (ent.pack and ent.pack.on_leader_lost)
				if type(on_lost) == "function" then
					on_lost(ent, self)
				elseif on_lost == "fight" then
					ent.state = "idle"
					ent.panic_timer = 0
					if ent.memory then
						ent.memory.flee_state = nil
						ent.memory.danger = {}
					end
					-- Retain target or inherit leader's killer/target
					if not ent.target or not x_mob_core.is_player_alive(ent.target) then
						local threat = self._killer or self.target
						if threat and threat:is_valid() then
							ent.target = threat
						end
					end
				else
					ent.state = "fleeing"
					ent.panic_timer = 5.0
					if ent.memory then
						ent.memory.flee_state = true
						if pos then
							x_mob_core.mob_memory.record_danger(ent, pos, 15, 20.0)
						end
					end
				end
			end
		end
	end
	self.pack_followers = {}
end

--- Adopts nearby orphans and spawns missing followers radially around the leader
---@param self table Leader mob instance
---@param follower_type? string|table Entity technical name (default: self.pack_follower_type)
---@param max_count? integer Target follower count (default: self.pack_max_followers or 3)
---@param spawn_radius? number Radial spawn distance (default: 1.5)
function squad.spawn_initial_followers(self, follower_type, max_count, spawn_radius)
	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return end

	squad.adopt_nearby_orphans(self, 32.0)
	local count = squad.clean_followers(self)

	local target_type = follower_type or self.pack_follower_type
	if not target_type then return end

	local max_fol = max_count or self.pack_max_followers or 3
	if count < max_fol then
		local needed = max_fol - count
		local rad = spawn_radius or 1.5
		local spawned_count = 0
		local last_spawn_type = nil
		for i = 1, needed do
			local angle = (i / needed) * math.pi * 2
			scratch_pos.x = pos.x + math.cos(angle) * rad
			scratch_pos.y = pos.y
			scratch_pos.z = pos.z + math.sin(angle) * rad
			local static = core.serialize({ pack_id = self.pack_id })

			local spawn_type
			if type(target_type) == "table" then
				local counts = {}
				for _, t in ipairs(target_type) do counts[t] = 0 end
				for _, f in ipairs(self.pack_followers) do
					if f and f:is_valid() then
						local ent = f:get_luaentity()
						if ent and counts[ent.name] ~= nil then
							counts[ent.name] = counts[ent.name] + 1
						end
					end
				end
				local lowest = math.huge
				local choices = {}
				for t, c in pairs(counts) do
					if c < lowest then
						lowest = c
						choices = {t}
					elseif c == lowest then
						table.insert(choices, t)
					end
				end
				spawn_type = choices[math.random(#choices)]
			else
				spawn_type = target_type
			end
			last_spawn_type = spawn_type

			local m_obj = core.add_entity(scratch_pos, spawn_type, static)
			if m_obj and m_obj:is_valid() then
				squad.add_follower(self, m_obj)
				spawned_count = spawned_count + 1
			end
		end

		if spawned_count > 0 then
			local mob_type_str = (type(target_type) == "string" and target_type) or last_spawn_type or "follower"
			core.log("action", string.format("[x_mob_core] [Squad Spawning] Spawned %d %s at %s",
				spawned_count, mob_type_str, core.pos_to_string(vector.round(pos))))
		end
	end
	self.spawned_followers = true
end

--- Spawns missing follower peers/members radially around the cluster leader
--- Single unified engine method supporting aquatic shoals, airborne swarms, and ground squads
---@param self table Leader mob instance
---@param def table Mob definition table
function squad.spawn_cluster(self, def)
	local cfg = def.shoal or def.swarm or def.pack or {}
	local total_size = cfg.size or (def.pack and def.pack.max_followers and (def.pack.max_followers + 1)) or 5
	local follower_count = total_size - 1
	if follower_count <= 0 then return end

	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return end

	-- Ensure leader has an active pack_id before spawning followers
	if not self.pack_id then
		self.pack_id = (self.saved_data and self.saved_data.pack_id) or utils.generate_uuid()
		if self.saved_data then
			self.saved_data.pack_id = self.pack_id
		end
	end

	local entity_name = cfg.member_type or (def.pack and def.pack.follower_type) or self.name
	if type(entity_name) == "table" then
		entity_name = entity_name[1]
	end

	local num_vars = def._texture_variations and #def._texture_variations or 0
	local leader_tex = self.texture_no or (num_vars > 0 and math.random(num_vars)) or 1

	local cbox = def.collisionbox or {-0.4, -0.4, -0.4, 0.4, 0.4, 0.4}
	local radius_h = math.max(math.abs(cbox[1]), math.abs(cbox[4]), math.abs(cbox[3]), math.abs(cbox[6]))
	local diameter_h = radius_h * 2

	local is_aquatic = (def.is_aquatic == true) or (def.shoal ~= nil) or (def.type == "aquatic")
	local is_airborne = not is_aquatic and (
		(def.swarm ~= nil and def.is_floating) or def.is_floating or (def.type == "flying")
	)

	local min_y, max_y
	local spawn_radius_base
	if is_aquatic then
		min_y, max_y = get_water_column_bounds(pos)
		spawn_radius_base = diameter_h + (cfg.spacing_x or 2.2)
	elseif is_airborne then
		spawn_radius_base = cfg.flock_radius or (diameter_h + 1.6)
	else
		spawn_radius_base = cfg.flock_radius or cfg.spacing_x or (diameter_h + 1.2)
	end

	local spawned_count = 0
	for i = 1, follower_count do
		local angle = (i / follower_count) * math.pi * 2
		local radius = spawn_radius_base + (i % 2) * (radius_h * 0.8)
		local candidate_x = pos.x + math.cos(angle) * radius
		local candidate_y = pos.y
		local candidate_z = pos.z + math.sin(angle) * radius

		if is_aquatic then
			candidate_y = math.max(min_y, math.min(max_y, pos.y))
			if not is_water_node(candidate_x, candidate_y, candidate_z) then
				candidate_x = pos.x - math.cos(angle) * (diameter_h * 0.7)
				candidate_z = pos.z - math.sin(angle) * (diameter_h * 0.7)
				if not is_water_node(candidate_x, candidate_y, candidate_z) then
					candidate_x = pos.x + 0.15 * i
					candidate_z = pos.z + 0.15 * i
				end
			end
		elseif is_airborne then
			candidate_y = pos.y + (math.random() - 0.5) * 0.6
			local is_obstructed = is_walkable_node(candidate_x, candidate_y, candidate_z)
				or is_water_node(candidate_x, candidate_y, candidate_z)
			if is_obstructed then
				candidate_x = pos.x + math.cos(angle) * (radius_h + 0.3)
				candidate_y = pos.y
				candidate_z = pos.z + math.sin(angle) * (radius_h + 0.3)
				if is_walkable_node(candidate_x, candidate_y, candidate_z) then
					candidate_x = pos.x
					candidate_z = pos.z
				end
			end
		else
			if is_walkable_node(candidate_x, candidate_y, candidate_z) then
				candidate_x = pos.x + math.cos(angle) * (radius_h + 0.3)
				candidate_y = pos.y
				candidate_z = pos.z + math.sin(angle) * (radius_h + 0.3)
				if is_walkable_node(candidate_x, candidate_y, candidate_z) then
					candidate_x = pos.x
					candidate_z = pos.z
				end
			end
		end

		local follower_tex = nil
		if num_vars > 1 then
			follower_tex = ((leader_tex + i - 2) % num_vars) + 1
		end

		local static = core.serialize({
			pack_id = self.pack_id,
			is_follower = true,
			cluster_spawned = true,
			follower_index = i,
			texture_no = follower_tex,
		})

		scratch_pos.x = candidate_x
		scratch_pos.y = candidate_y
		scratch_pos.z = candidate_z

		local follower_obj = core.add_entity(scratch_pos, entity_name, static)
		if follower_obj and follower_obj:is_valid() then
			squad.add_follower(self, follower_obj)
			local fol_ent = follower_obj:get_luaentity()
			if fol_ent then
				fol_ent.leader_obj = self.object
				fol_ent.pack_id = self.pack_id
				fol_ent.follower_index = i
			end
			spawned_count = spawned_count + 1
		end
	end

	if spawned_count > 0 then
		local mode_tag = (def.shoal and "Shoal Spawning")
			or (def.swarm and "Swarm Spawning")
			or "Cluster Spawning"
		core.log("action", string.format("[x_mob_core] [%s] Spawned %d %s at %s",
			mode_tag, spawned_count, entity_name, core.pos_to_string(vector.round(pos))))
	end
end

--- Follower searches nearby area to re-link with its pack leader if separated
---@param self table Follower mob instance
---@param search_radius? number Radius to search (default: 32.0)
---@return boolean linked True if successfully re-linked
function squad.relink_follower(self, search_radius)
	if self.leader_obj and self.leader_obj:is_valid() then return true end
	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return false end

	local radius = search_radius or 32.0
	local nearby = core.get_objects_inside_radius(pos, radius)
	for i = 1, #nearby do
		local obj = nearby[i]
		if obj ~= self.object and not obj:is_player() and utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent and (not self.pack_id or not ent.pack_id or ent.pack_id == self.pack_id) then
				local is_leader = (ent.pack_role == "leader") or
					(ent.pack_role ~= "member" and (
						(self.pack_leader_type and ent.name == self.pack_leader_type) or
						(not self.pack_leader_type and ent.name == self.name and ent.pack_role == "leader")
					))
				if is_leader then
					local leader_max = ent.pack_max_followers
					local has_space = true
					if leader_max then
						local cur_count = squad.clean_followers(ent)
						local is_already_member = false
						if ent.pack_followers then
							for f_idx = 1, #ent.pack_followers do
								if ent.pack_followers[f_idx] == self.object then
									is_already_member = true
									break
								end
							end
						end
						if not is_already_member and cur_count >= leader_max then
							has_space = false
						end
					end
					if has_space and squad.add_follower(ent, self.object) then
						self.leader_obj = obj
						if ent.pack_id then
							self.pack_id = ent.pack_id
							if self.saved_data then
								self.saved_data.pack_id = ent.pack_id
							end
						end
						return true
					end
				end
			end
		end
	end
	return false
end

--- Democratic leader election: promotes the first surviving follower in-place
---@param self table Mob instance (dying leader or surviving follower)
---@param search_radius? number Radius to search for surviving members (default: 24.0)
---@return boolean success True if a new leader was established
function squad.elect_successor(self, search_radius)
	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return false end

	local radius = search_radius or 24.0
	local nearby = core.get_objects_inside_radius(pos, radius)
	local survivors = {}

	for i = 1, #nearby do
		local obj = nearby[i]
		if obj ~= self.object and not obj:is_player() and utils.is_player_alive(obj) then
			local ent = obj:get_luaentity()
			if ent and ent.name == self.name and not ent.is_dead then
				if not self.pack_id or not ent.pack_id or ent.pack_id == self.pack_id then
					survivors[#survivors + 1] = obj
				end
			end
		end
	end

	if #survivors > 0 then
		local new_leader_obj = survivors[1]
		local new_leader_ent = new_leader_obj:get_luaentity()
		if new_leader_ent then
			new_leader_ent.pack_role = "leader"
			new_leader_ent.follower_index = 0
			new_leader_ent.leader_obj = nil
			new_leader_ent.pack_followers = {}
			new_leader_ent.pack_max_followers = self.pack_max_followers
			if new_leader_ent.saved_data then
				new_leader_ent.saved_data.is_follower = false
				new_leader_ent.saved_data.follower_index = 0
				new_leader_ent.saved_data.pack_id = self.pack_id
			end

			for i = 2, #survivors do
				local fol_obj = survivors[i]
				squad.add_follower(new_leader_ent, fol_obj)
				local fol_ent = fol_obj:get_luaentity()
				if fol_ent then
					fol_ent.pack_role = "member"
					fol_ent.follower_index = i - 1
					fol_ent.leader_obj = new_leader_obj
					if fol_ent.saved_data then
						fol_ent.saved_data.is_follower = true
						fol_ent.saved_data.follower_index = i - 1
						fol_ent.saved_data.pack_id = self.pack_id
					end
				end
			end
			return true
		end
	end

	return false
end

return squad
