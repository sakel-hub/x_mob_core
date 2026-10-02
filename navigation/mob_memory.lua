--[[
	mob_memory.lua - High-Performance Short-Term Independent Mob Memory
	- Zero GC pressure: Pre-allocated fixed-size ring buffers updated in-place
	- 8-Second Predictive Target Pursuit (Last Known Position - LKP)
	- Danger & Pain Source Spatial Repulsion Vector Fields
	- Low-HP Tactical Fleeing with Passive Health Regeneration & Return
	- Anti-Oscillation Trail Buffer & Exploration Novelty Bias
	- Configurable Swarm Alert Broadcast (Pack Communication)
]]

---@class MobMemorySubsystem
local mob_memory = {}

local modpath = core.get_modpath("x_mob_core") or "."
local utils = dofile(modpath .. "/core/utils.lua")

local DANGER_SLOTS = 3
local TRAIL_SLOTS = 6
local BLOCKED_SLOTS = 2
local TRAIL_SAMPLE_INTERVAL = 1.0

--- Initializes a zero-allocation working memory buffer on an entity instance
---@param self table Entity instance
function mob_memory.init_memory(self)
	if self.memory then return self.memory end

	local mem = {
		-- Target memory (Single fixed record)
		target = {
			name = "",
			lkp = {x = 0, y = 0, z = 0},
			last_seen = 0.0,
			has_record = false,
		},

		-- Danger memory (Pre-allocated ring buffer)
		dangers = {},
		danger_idx = 1,

		-- Traversal history / trail (Pre-allocated circular buffer)
		trail = {},
		trail_idx = 1,
		last_trail_sample = 0.0,

		-- Obstruction / Deadlock memory
		blocked_spots = {},
		blocked_idx = 1,

		-- Health regeneration & fleeing state
		regen_timer = 0.0,
		flee_state = false,

		-- Fight / combat location memory (decoupled from 8s LKP for tactical return)
		fight = {
			x = 0.0,
			y = 0.0,
			z = 0.0,
			expire = 0.0,
			active = false,
		},

		-- Unreachable targets cache (e.g. across impassable water)
		unreachable_targets = {},

		-- Pre-allocated reusable query vectors (zero GC pressure)
		vec_danger_repulse = {x = 0.0, y = 0.0, z = 0.0},
		vec_exploration_bias = {x = 0.0, y = 0.0, z = 0.0},
		vec_fight_return = {x = 0.0, y = 0.0, z = 0.0},

		-- Pre-allocated heading evaluation cache (zero GC across multi-angle candidate scoring)
		_heading_cache = {
			pos_x = 0.0,
			pos_y = 0.0,
			pos_z = 0.0,
			time = -1.0,
			novelty_x = 0.0,
			novelty_y = 0.0,
			novelty_z = 0.0,
			danger_count = 0,
			dangers = {},
			blocked_count = 0,
			blocked = {},
		},
	}

	for i = 1, DANGER_SLOTS do
		mem.dangers[i] = {x = 0, y = 0, z = 0, threat = 0.0, expire = 0.0, active = false}
		mem._heading_cache.dangers[i] = {
			ux = 0.0, uy = 0.0, uz = 0.0,
			threat_towards = 0.0, threat_away = 0.0,
		}
	end

	for i = 1, TRAIL_SLOTS do
		mem.trail[i] = {x = 0, y = 0, z = 0, time = 0.0, active = false}
	end

	for i = 1, BLOCKED_SLOTS do
		mem.blocked_spots[i] = {x = 0, y = 0, z = 0, expire = 0.0, active = false}
		mem._heading_cache.blocked[i] = {
			ux = 0.0, uy = 0.0, uz = 0.0,
			weight = 0.0,
		}
	end

	self.memory = mem
	return mem
end

--- Helper to safely extract a target identifier string
---@param target_obj ObjectRef|nil Target player or entity
---@return string name Identifier name or fallback string
local function get_target_identifier(target_obj)
	if not target_obj or not target_obj:is_valid() then
		return "target"
	end
	if target_obj:is_player() then
		local pname = target_obj:get_player_name()
		if pname and pname ~= "" then return pname end
	else
		local le = target_obj:get_luaentity()
		if le and le.name and le.name ~= "" then return le.name end
	end
	return tostring(target_obj)
end

--- Records or updates target sighting and Last Known Position
---@param self table Entity instance
---@param target_obj ObjectRef Target player or entity
---@param target_pos Vector Target position
---@param current_time? number Optional current time or timestamp
function mob_memory.record_target_sighting(self, target_obj, target_pos, current_time)
	if not self.memory then mob_memory.init_memory(self) end
	if not target_pos then return end

	local tm = self.memory.target
	local now = current_time or core.get_gametime()

	tm.has_record = true
	tm.name = get_target_identifier(target_obj)
	tm.lkp.x = target_pos.x
	tm.lkp.y = target_pos.y
	tm.lkp.z = target_pos.z
	tm.last_seen = now
end

--- Retrieves active Last Known Position if within the 8.0s pursuit window
---@param self table Entity instance
---@param max_age? number Maximum age in seconds (default: 8.0)
---@param current_time? number Current timestamp
---@return Vector|nil lkp Last known position or nil if expired
function mob_memory.get_lkp_target(self, max_age, current_time)
	if not self.memory or not self.memory.target.has_record then return nil end

	local tm = self.memory.target
	local now = current_time or core.get_gametime()
	local age_limit = max_age or 8.0

	if (now - tm.last_seen) <= age_limit then
		return tm.lkp
	else
		tm.has_record = false
		return nil
	end
end

--- Clears target memory explicitly
---@param self table Entity instance
function mob_memory.clear_target_memory(self)
	if self.memory and self.memory.target then
		self.memory.target.has_record = false
	end
end

--- Records a target as temporarily unreachable (e.g. across impassable water or chasm)
---@param self table Entity instance
---@param target_obj ObjectRef Target player or entity
---@param duration? number Duration in seconds before re-evaluating (default: 12.0)
---@param current_time? number Current timestamp
function mob_memory.record_unreachable_target(self, target_obj, duration, current_time)
	if not self.memory then mob_memory.init_memory(self) end
	local name = get_target_identifier(target_obj)
	local now = current_time or core.get_gametime()

	-- Periodic cleanup of expired unreachable targets to prevent unbounded table growth
	for k, exp in pairs(self.memory.unreachable_targets) do
		if now >= exp then
			self.memory.unreachable_targets[k] = nil
		end
	end

	self.memory.unreachable_targets[name] = now + (duration or 12.0)
end

--- Checks if a target is currently marked as unreachable
---@param self table Entity instance
---@param target_obj ObjectRef Target player or entity
---@param current_time? number Current timestamp
---@return boolean is_unreachable True if target is unreachable and on cooldown
function mob_memory.is_target_unreachable(self, target_obj, current_time)
	if not self.memory or not self.memory.unreachable_targets then return false end
	local name = get_target_identifier(target_obj)
	local expiry = self.memory.unreachable_targets[name]
	if not expiry then return false end
	local now = current_time or core.get_gametime()
	if now < expiry then
		return true
	end
	self.memory.unreachable_targets[name] = nil
	return false
end

--- Clears unreachable status for a target (e.g. when punched by that target)
---@param self table Entity instance
---@param target_obj ObjectRef Target player or entity
function mob_memory.clear_unreachable_target(self, target_obj)
	if not self.memory or not self.memory.unreachable_targets then return end
	local name = get_target_identifier(target_obj)
	self.memory.unreachable_targets[name] = nil
end

--- Records a danger source (damage taken, enemy position, hazard)
---@param self table Entity instance
---@param danger_pos Vector World coordinates of the threat
---@param threat_level number Magnitude of the threat (e.g. damage amount)
---@param duration? number Duration in seconds before expiration (default: 12.0)
---@param current_time? number Current timestamp
function mob_memory.record_danger(self, danger_pos, threat_level, duration, current_time)
	if not self.memory then mob_memory.init_memory(self) end
	if not danger_pos then return end

	local mem = self.memory
	local slot = mem.dangers[mem.danger_idx]
	local now = current_time or core.get_gametime()
	local dur = duration or 12.0

	slot.x = danger_pos.x
	slot.y = danger_pos.y
	slot.z = danger_pos.z
	slot.threat = threat_level or 1.0
	slot.expire = now + dur
	slot.active = true

	mem.danger_idx = (mem.danger_idx % DANGER_SLOTS) + 1
end

--- Records a combat / fight location
---@param self table Entity instance
---@param fight_pos Vector World coordinates of the fight
---@param duration? number Duration in seconds before expiration (default: 45.0)
---@param current_time? number Current timestamp
function mob_memory.record_fight_pos(self, fight_pos, duration, current_time)
	if not self.memory then mob_memory.init_memory(self) end
	if not fight_pos then return end

	local f = self.memory.fight
	local now = current_time or core.get_gametime()
	f.x = fight_pos.x
	f.y = fight_pos.y
	f.z = fight_pos.z
	f.expire = now + (duration or 45.0)
	f.active = true
end

--- Retrieves active fight location if not expired
---@param self table Entity instance
---@param current_time? number Current timestamp
---@return Vector|nil fight_pos Coordinates of the fight or nil
function mob_memory.get_fight_pos(self, current_time)
	if not self.memory or not self.memory.fight or not self.memory.fight.active then
		return nil
	end

	local f = self.memory.fight
	local now = current_time or core.get_gametime()
	if now < f.expire then
		local out = self.memory.vec_fight_return or {x = 0.0, y = 0.0, z = 0.0}
		self.memory.vec_fight_return = out
		out.x = f.x
		out.y = f.y
		out.z = f.z
		return out
	else
		f.active = false
		return nil
	end
end

--- Clears fight memory explicitly
---@param self table Entity instance
function mob_memory.clear_fight_pos(self)
	if self.memory and self.memory.fight then
		self.memory.fight.active = false
	end
end

--- Calculates a spatial repulsion vector away from all active danger spots
--- Uses inverse-square distance weighting
---@param self table Entity instance
---@param current_pos Vector Current mob position
---@param current_time? number Current timestamp
---@return Vector repulsion Normalized 3D repulsive vector or {x=0, y=0, z=0}
function mob_memory.get_danger_repulsion_vector(self, current_pos, current_time)
	if not self.memory then return {x = 0, y = 0, z = 0} end

	local mem = self.memory
	local now = current_time or core.get_gametime()
	local rx, ry, rz = 0.0, 0.0, 0.0
	local total_weight = 0.0
	local closest_slot = nil
	local closest_dist_sq = 1e9

	for i = 1, DANGER_SLOTS do
		local slot = mem.dangers[i]
		if slot.active then
			if slot.expire > now then
				local dx = current_pos.x - slot.x
				local dy = current_pos.y - slot.y
				local dz = current_pos.z - slot.z
				local dist_sq = dx * dx + dy * dy + dz * dz

				if dist_sq < 0.04 then dist_sq = 0.04 end
				-- Inverse-square weight scaled by threat level
				local w = (slot.threat or 1.0) / dist_sq
				local dist = math.sqrt(dist_sq)

				rx = rx + (dx / dist) * w
				ry = ry + (dy / dist) * w
				rz = rz + (dz / dist) * w
				total_weight = total_weight + w

				if dist_sq < closest_dist_sq then
					closest_dist_sq = dist_sq
					closest_slot = slot
				end
			else
				slot.active = false
			end
		end
	end

	local out = mem.vec_danger_repulse or {x = 0.0, y = 0.0, z = 0.0}
	mem.vec_danger_repulse = out

	if total_weight > 0.0001 then
		local len = math.sqrt(rx * rx + ry * ry + rz * rz)
		-- If opposing dangers cancel out (|R| / total_weight < 0.2),
		-- flee directly away from the closest active danger
		if (len / total_weight) < 0.2 and closest_slot then
			local c_dx = current_pos.x - closest_slot.x
			local c_dz = current_pos.z - closest_slot.z
			local c_len = math.sqrt(c_dx * c_dx + c_dz * c_dz)
			if c_len > 0.01 then
				out.x = c_dx / c_len
				out.y = 0.0
				out.z = c_dz / c_len
				return out
			end
		end

		if len > 0.001 then
			out.x = rx / len
			out.y = ry / len
			out.z = rz / len
			return out
		end
	end

	out.x = 0.0; out.y = 0.0; out.z = 0.0
	return out
end

--- Clears all active danger memories (used on combat re-engagement or panic exit)
---@param self table Entity instance
function mob_memory.clear_danger_memory(self)
	if not self.memory then return end
	for i = 1, DANGER_SLOTS do
		self.memory.dangers[i].active = false
	end
end


--- Records a visited world position into the circular trail buffer
--- Throttled to 1.0s intervals to minimize samples
---@param self table Entity instance
---@param current_pos Vector Current mob position
---@param dtime number Step delta time
---@param current_time? number Current timestamp
function mob_memory.record_trail_step(self, current_pos, dtime, current_time)
	if not self.memory then mob_memory.init_memory(self) end
	if not current_pos then return end

	local mem = self.memory
	mem.last_trail_sample = mem.last_trail_sample + dtime

	if mem.last_trail_sample >= TRAIL_SAMPLE_INTERVAL then
		mem.last_trail_sample = 0.0
		local now = current_time or core.get_gametime()

		-- Check if mob has actually moved from previous recorded position
		-- (prevents stationary mobs from flushing their entire trail history)
		local prev_idx = ((mem.trail_idx - 2) % TRAIL_SLOTS) + 1
		local prev_slot = mem.trail[prev_idx]
		if prev_slot and prev_slot.active then
			local dx = current_pos.x - prev_slot.x
			local dy = current_pos.y - prev_slot.y
			local dz = current_pos.z - prev_slot.z
			if (dx * dx + dy * dy + dz * dz) < 0.25 then
				prev_slot.time = now
				return
			end
		end

		local slot = mem.trail[mem.trail_idx]
		slot.x = current_pos.x
		slot.y = current_pos.y
		slot.z = current_pos.z
		slot.time = now
		slot.active = true

		mem.trail_idx = (mem.trail_idx % TRAIL_SLOTS) + 1
	end
end

--- Calculates an exploration novelty vector pointing away from recently visited positions
--- Prevents ping-pong oscillations in corridors and dead ends
---@param self table Entity instance
---@param current_pos Vector Current mob position
---@return Vector novelty Normalized 3D exploration vector or {x=0, y=0, z=0}
function mob_memory.get_exploration_bias_vector(self, current_pos)
	if not self.memory then return {x = 0, y = 0, z = 0} end

	local mem = self.memory
	local nx, ny, nz = 0.0, 0.0, 0.0
	local count = 0

	for i = 1, TRAIL_SLOTS do
		local slot = mem.trail[i]
		if slot.active then
			local dx = current_pos.x - slot.x
			local dy = current_pos.y - slot.y
			local dz = current_pos.z - slot.z
			local dist_sq = dx * dx + dy * dy + dz * dz

			-- Only consider trail points within 10 blocks
			if dist_sq > 0.01 and dist_sq < 100.0 then
				local dist = math.sqrt(dist_sq)
				-- Weight inversely proportional to distance (repel nearby visited spots more)
				local w = 1.0 / dist
				nx = nx + (dx / dist) * w
				ny = ny + (dy / dist) * w
				nz = nz + (dz / dist) * w
				count = count + 1
			end
		end
	end

	local out = mem.vec_exploration_bias or {x = 0.0, y = 0.0, z = 0.0}
	mem.vec_exploration_bias = out

	if count > 0 then
		local len = math.sqrt(nx * nx + ny * ny + nz * nz)
		if len > 0.001 then
			out.x = nx / len
			out.y = ny / len
			out.z = nz / len
			return out
		end
	end

	out.x = 0.0; out.y = 0.0; out.z = 0.0
	return out
end

--- Records a blocked position or cliff deadlock
---@param self table Entity instance
---@param blocked_pos Vector Position that could not be traversed
---@param duration? number Duration in seconds (default: 8.0)
---@param current_time? number Current timestamp
function mob_memory.record_blocked_spot(self, blocked_pos, duration, current_time)
	if not self.memory then mob_memory.init_memory(self) end
	if not blocked_pos then return end

	local mem = self.memory
	local now = current_time or core.get_gametime()
	local dur = duration or 8.0

	-- If a nearby blocked spot (< 1.0 node) is already active, refresh its expiration
	-- instead of consuming another ring buffer slot and overwriting other obstacles
	for i = 1, BLOCKED_SLOTS do
		local slot = mem.blocked_spots[i]
		if slot.active and slot.expire > now then
			local dx = blocked_pos.x - slot.x
			local dy = blocked_pos.y - slot.y
			local dz = blocked_pos.z - slot.z
			if (dx * dx + dy * dy + dz * dz) < 1.0 then
				slot.expire = math.max(slot.expire, now + dur)
				return
			end
		end
	end

	local slot = mem.blocked_spots[mem.blocked_idx]
	slot.x = blocked_pos.x
	slot.y = blocked_pos.y
	slot.z = blocked_pos.z
	slot.expire = now + dur
	slot.active = true

	mem.blocked_idx = (mem.blocked_idx % BLOCKED_SLOTS) + 1
end

--- Evaluates a candidate movement direction against danger, novelty, and blocked memory
--- Returns a scalar fitness score (higher is better)
--- Utilizes a zero-allocation heading evaluation cache to avoid duplicate vector and sqrt computations
---@param self table Entity instance
---@param candidate_dir Vector Candidate heading direction (normalized)
---@param current_pos Vector Current mob position
---@param current_time? number Current timestamp
---@return number score Fitness score
function mob_memory.evaluate_heading_bias(self, candidate_dir, current_pos, current_time)
	if not self.memory then return 0.0 end

	local mem = self.memory
	local cache = mem._heading_cache
	local now = current_time or core.get_gametime()

	-- Check if cache is valid for current position and timestamp
	if not cache or cache.time ~= now or
			cache.pos_x ~= current_pos.x or
			cache.pos_y ~= current_pos.y or
			cache.pos_z ~= current_pos.z then
		if not cache then
			cache = {
				pos_x = 0.0, pos_y = 0.0, pos_z = 0.0, time = -1.0,
				novelty_x = 0.0, novelty_y = 0.0, novelty_z = 0.0,
				danger_count = 0, dangers = {},
				blocked_count = 0, blocked = {},
			}
			for i = 1, DANGER_SLOTS do
				cache.dangers[i] = {
					ux = 0.0, uy = 0.0, uz = 0.0,
					threat_towards = 0.0, threat_away = 0.0,
				}
			end
			for i = 1, BLOCKED_SLOTS do
				cache.blocked[i] = {ux = 0.0, uy = 0.0, uz = 0.0, weight = 0.0}
			end
			mem._heading_cache = cache
		end

		cache.pos_x = current_pos.x
		cache.pos_y = current_pos.y
		cache.pos_z = current_pos.z
		cache.time = now

		-- 1. Precompute danger directions & distance weights
		local d_count = 0
		for i = 1, DANGER_SLOTS do
			local slot = mem.dangers[i]
			if slot.active and slot.expire > now then
				local to_danger_x = slot.x - current_pos.x
				local to_danger_y = slot.y - current_pos.y
				local to_danger_z = slot.z - current_pos.z
				local dist = math.sqrt(to_danger_x * to_danger_x + to_danger_y * to_danger_y + to_danger_z * to_danger_z)
				if dist > 0.05 and dist < 16.0 then
					d_count = d_count + 1
					local c_d = cache.dangers[d_count]
					c_d.ux = to_danger_x / dist
					c_d.uy = to_danger_y / dist
					c_d.uz = to_danger_z / dist
					local base_weight = (slot.threat or 1.0) * (1.0 - dist / 16.0)
					c_d.threat_towards = base_weight * 1.5
					c_d.threat_away = base_weight * 0.8
				end
			end
		end
		cache.danger_count = d_count

		-- 2. Precompute exploration novelty vector
		local nov = mob_memory.get_exploration_bias_vector(self, current_pos)
		cache.novelty_x = nov.x
		cache.novelty_y = nov.y
		cache.novelty_z = nov.z

		-- 3. Precompute blocked spot directions & weights
		local b_count = 0
		for i = 1, BLOCKED_SLOTS do
			local b_slot = mem.blocked_spots[i]
			if b_slot.active and b_slot.expire > now then
				local to_bx = b_slot.x - current_pos.x
				local to_by = b_slot.y - current_pos.y
				local to_bz = b_slot.z - current_pos.z
				local dist = math.sqrt(to_bx * to_bx + to_by * to_by + to_bz * to_bz)
				if dist > 0.05 and dist < 6.0 then
					b_count = b_count + 1
					local c_b = cache.blocked[b_count]
					c_b.ux = to_bx / dist
					c_b.uy = to_by / dist
					c_b.uz = to_bz / dist
					c_b.weight = 3.0 * (1.0 - dist / 6.0)
				end
			end
		end
		cache.blocked_count = b_count
	end

	-- Score candidate direction using precomputed unit vectors & weights
	local score = 0.0

	-- Danger aversion
	for i = 1, cache.danger_count do
		local c_d = cache.dangers[i]
		local dot = candidate_dir.x * c_d.ux + candidate_dir.y * c_d.uy + candidate_dir.z * c_d.uz
		if dot > 0.0 then
			score = score - dot * c_d.threat_towards
		else
			score = score - dot * c_d.threat_away
		end
	end

	-- Exploration novelty
	local nov_dot = candidate_dir.x * cache.novelty_x +
		candidate_dir.y * cache.novelty_y + candidate_dir.z * cache.novelty_z
	score = score + nov_dot * 1.2

	-- Blocked spot penalty
	for i = 1, cache.blocked_count do
		local c_b = cache.blocked[i]
		local dot = candidate_dir.x * c_b.ux + candidate_dir.y * c_b.uy + candidate_dir.z * c_b.uz
		if dot > 0.2 then
			score = score - dot * c_b.weight
		end
	end

	return score
end

--- Updates low-HP tactical fleeing and passive health regeneration
--- When HP recovers to return threshold, exits fleeing state
---@param self table Entity instance
---@param dtime number Step delta time
---@param flee_ratio? number HP ratio to enter fleeing (default: 0.25)
---@param return_ratio? number HP ratio to exit fleeing (default: 0.60)
---@param regen_rate? number HP regenerated per second while fleeing (default: 0.5)
---@return boolean is_fleeing Whether the mob is currently in fleeing state
function mob_memory.update_health_regen(self, dtime, flee_ratio, return_ratio, regen_rate)
	if not self.memory then mob_memory.init_memory(self) end

	local mem = self.memory
	local max_hp = self.hp_max or (self.initial_properties and self.initial_properties.hp_max) or 40
	local cur_hp = self.hp or (self.object and self.object:is_valid() and self.object:get_hp()) or max_hp

	-- Read canonical health_regen source of truth table
	local hr = self.health_regen or (self._def and self._def.health_regen)
	local flee_thresh = (hr and hr.flee_threshold) or math.floor(max_hp * 0.25)
	local return_thresh = (hr and hr.return_threshold) or math.floor(max_hp * 0.60)
	local rate = (hr and hr.rate) or 0.5
	local passive = hr and (hr.passive == true)
	local overlay = not hr or (hr.overlay ~= false)
	local overlay_color = (hr and hr.overlay_color) or "^[colorize:#FFFFFF60"

	-- Caller-provided argument overrides
	if flee_ratio ~= nil then flee_thresh = max_hp * flee_ratio end
	if return_ratio ~= nil then return_thresh = max_hp * return_ratio end
	if regen_rate ~= nil then rate = regen_rate end

	-- Enter fleeing if HP drops below threshold
	if flee_thresh > 0 and not mem.flee_state and cur_hp <= flee_thresh and cur_hp > 0 then
		mem.flee_state = true
		self.state = "fleeing"
	end

	-- While fleeing, panicking, or when passive regeneration is enabled, regenerate health
	local is_running_away = mem.flee_state or (self.state == "fleeing" or self.state == "flee") or
		(self.panic_timer and self.panic_timer > 0)
	local should_regen = (rate > 0) and (is_running_away or passive)
	if should_regen and cur_hp < max_hp and cur_hp > 0 then
		mem.regen_timer = mem.regen_timer + dtime
		if mem.regen_timer >= 1.0 then
			local hp_to_add = math.floor(mem.regen_timer * rate)
			if hp_to_add >= 1 then
				mem.regen_timer = mem.regen_timer - (hp_to_add / rate)
				local old_hp = cur_hp
				local new_hp = math.min(max_hp, cur_hp + hp_to_add)
				self.hp = new_hp
				if self.object and self.object:is_valid() then
					self.object:set_hp(math.max(1, math.min(max_hp, math.ceil(new_hp))))
				end
				cur_hp = new_hp

				-- Trigger visual white texture overlay feedback (same mechanism as hurt flash, but white)
				if overlay and self.object and self.object:is_valid() then
					x_mob_core.indicate_regen(self.object, overlay_color)
				end

				-- Update dynamic health bar if present
				x_mob_core.combat.health_bar.on_hp_change(self, old_hp, new_hp, self._def)

				if self.on_regen_step then
					self:on_regen_step(hp_to_add)
				end
			end
		end
	end

	if mem.flee_state then
		-- Once HP recovers above return threshold and mob is not panicking, exit fleeing
		local is_panicking = (self.panic_timer and self.panic_timer > 0)
		if cur_hp >= return_thresh and not is_panicking then
			mem.flee_state = false
			if self.state == "fleeing" then
				self.state = "idle"
			end
			-- Clear old danger memories so mob doesn't keep running away
			for i = 1, DANGER_SLOTS do
				mem.dangers[i].active = false
			end
			if self.on_return_to_fight then
				self:on_return_to_fight()
			elseif self.target and (self.pack_role == "leader" or (self.pack and self.pack.role == "leader")) then
				x_mob_core.rally_followers(self, self.target)
			elseif not self.target and mem.fight and mem.fight.active then
				self.state = "returning"
				self.nav_target_pos = mob_memory.get_fight_pos(self)
			end
		end
	end

	return mem.flee_state
end

--- Broadcasts a swarm alert to nearby allies of the same species
--- Configurable via self.swarm_alert = {enabled = true, radius = 10.0, max_allies = 3}
---@param self table Entity instance sending the alert
---@param alert_pos Vector Position of the threat
---@param threat? number Threat magnitude (default: 5.0)
---@param radius? number Alert radius in nodes (default: 10.0)
---@param max_allies? number Maximum allies to alert (default: 3)
---@return integer alerted_count Number of allies alerted
function mob_memory.broadcast_alert(self, alert_pos, threat, radius, max_allies)
	local cfg = self.swarm_alert
	if not cfg or cfg.enabled == false then return 0 end

	local pos = (self.object and self.object:is_valid() and self.object:get_pos()) or alert_pos
	if not pos or not alert_pos then return 0 end

	local search_rad = radius or cfg.radius or 10.0
	local limit = max_allies or cfg.max_allies or 3
	local mob_name = self.name
		or (self.object and self.object:is_valid() and self.object:get_luaentity() and self.object:get_luaentity().name)

	local count = 0
	local nearby = core.get_objects_inside_radius(pos, search_rad)

	for i = 1, #nearby do
		local obj = nearby[i]
		if obj and obj:is_valid() and obj ~= self.object and not obj:is_player() then
			local le = obj:get_luaentity()
			if le and le ~= self and (not mob_name or le.name == mob_name) then
				-- Alert ally mob
				if not le.memory then mob_memory.init_memory(le) end
				mob_memory.record_danger(le, alert_pos, threat or 5.0, 10.0)

				-- If ally is idle or roaming without a current target, orient it towards the alert
				local target_alive = le.target and utils.is_player_alive(le.target)
				if not target_alive then
					le.memory.target.has_record = true
					le.memory.target.name = "swarm_alert"
					le.memory.target.lkp.x = alert_pos.x
					le.memory.target.lkp.y = alert_pos.y
					le.memory.target.lkp.z = alert_pos.z
					le.memory.target.last_seen = core.get_gametime()
					if le.path_state then
						le.path_state.timer = 99.0 -- Trigger path evaluation
					end
				end

				count = count + 1
				if count >= limit then break end
			end
		end
	end

	return count
end

return mob_memory
