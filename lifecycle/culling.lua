--[[
	x_mob_core - Lifecycle Culling & Despawn Subsystem
	Handles distance-based simulation culling, daylight exposure despawns,
	and area congestion safeguards (Single Responsibility Principle).
]]

local culling = {}

---Evaluates daylight and scheduled time-of-day despawn conditions for a mob.
---@param self table Mob entity instance
---@param def table Mob definition table
---@param pos Vector World position
---@return boolean should_despawn
---@return string|nil reason
function culling.check_daylight_or_time(_self, def, pos)
	if def.despawn_in_daylight or (def.despawn_conditions and def.despawn_conditions.daylight) then
		local tod = core.get_timeofday() or 0
		local min_tod = (def.despawn_conditions and def.despawn_conditions.min_time) or 0.22
		local max_tod = (def.despawn_conditions and def.despawn_conditions.max_time) or 0.78
		if tod >= min_tod and tod <= max_tod then
			local nat_light = core.get_natural_light(pos)
			local cond_min = def.despawn_conditions and def.despawn_conditions.min_natural_light
			local req_light = def.despawn_natural_light or cond_min or 11
			if nat_light and nat_light >= req_light then
				return true, "daylight"
			end
		end
	elseif def.despawn_conditions and def.despawn_conditions.time_range then
		local tr = def.despawn_conditions.time_range
		local tod = core.get_timeofday() or 0
		local in_range = (tr.min <= tr.max) and (tod >= tr.min and tod <= tr.max) or (tod >= tr.min or tod <= tr.max)
		if in_range then
			if def.despawn_conditions.require_natural_light then
				local nat_light = core.get_natural_light(pos)
				local req_light = def.despawn_conditions.min_natural_light or 11
				if nat_light and nat_light >= req_light then
					return true, "time_of_day"
				end
			else
				return true, "time_of_day"
			end
		end
	end
	return false, nil
end

---Periodic distance and daylight culling evaluation for non-persistent mobs.
---Throttled to run every 4.0 seconds per mob with staggered offsets.
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean despawned True if mob was removed
function culling.step_culling(self, dtime, def)
	if self.is_dead or self.state == "dying" or self._persistent then
		return false
	end
	if def.despawn == false then
		return false
	end

	self._despawn_check_timer = (self._despawn_check_timer or (math.random() * 4.0)) + dtime
	if self._despawn_check_timer < 4.0 then
		return false
	end
	self._despawn_check_timer = 0

	local pos = self.object and self.object:get_pos()
	if not pos then return false end

	-- Check daylight or diurnal cycle despawn
	local should_despawn, despawn_reason = culling.check_daylight_or_time(self, def, pos)
	if should_despawn then
		culling.remove_mob(self, def, despawn_reason)
		return true
	end

	-- Distance-based culling relative to connected players
	local players = core.get_connected_players()
	if #players == 0 then return false end

	local min_pdist_sq = 999999999
	for p = 1, #players do
		local pobj = players[p]
		if pobj and pobj:is_valid() then
			local ppos = pobj:get_pos()
			if ppos then
				local dx = pos.x - ppos.x
				local dy = pos.y - ppos.y
				local dz = pos.z - ppos.z
				local d_sq = dx * dx + dy * dy + dz * dz
				if d_sq < min_pdist_sq then
					min_pdist_sq = d_sq
				end
			end
		end
	end

	-- Timer-based graceful despawn when distant from players (> 64 blocks unengaged).
	-- Never despawns immediately: requires sustained absence over a countdown timer.
	-- If a player returns within range (or mob engages in combat), the countdown resets.
	local despawn_time = def.despawn_timer or 45.0
	if min_pdist_sq > 4096 and not self.target then
		self._far_timer = (self._far_timer or 0) + 4.0
		if self._far_timer >= despawn_time then
			culling.remove_mob(self, def, "distance_timeout")
			return true
		end
	else
		self._far_timer = 0
	end

	return false
end

---Culls excess mobs of the same type in congested areas to prevent server lag.
---@param self table Mob entity instance
---@param max_density? integer Maximum allowed same-type entities in radius (default: 16)
---@param radius? number Search radius (default: 16)
---@return boolean culled True if this mob was culled
function culling.check_congestion(self, max_density, radius)
	local pos = self.object and self.object:get_pos()
	if not pos then return false end
	local rad = radius or 16
	local limit = max_density or 16

	local nearby = core.get_objects_inside_radius(pos, rad)
	local count = 0
	for i = 1, #nearby do
		local nobj = nearby[i]
		if nobj and nobj:is_valid() and not nobj:is_player() then
			local nent = nobj:get_luaentity()
			if nent and nent.name == self.name then
				count = count + 1
				if count > limit then
					self.object:remove()
					return true
				end
			end
		end
	end
	return false
end

---Safely removes a mob, notifying definition callbacks and event listeners.
---@param self table Mob entity instance
---@param def table Mob definition table
---@param reason? string Reason code for despawn
function culling.remove_mob(self, def, reason)
	if self._is_removing then return end
	self._is_removing = true
	if def.on_despawn and not self._despawn_handled then
		self._despawn_handled = true
		def.on_despawn(self, reason)
	end
	if x_mob_core and x_mob_core.emit and not self._despawn_emitted then
		self._despawn_emitted = true
		x_mob_core.emit("on_mob_despawn", self, reason)
	end
	if self.object and self.object:is_valid() then
		self.object:remove()
	end
end

return culling
