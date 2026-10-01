--[[
	x_mob_core - Swarm Intelligence & Flocking Subsystem
	Multi-agent 3D Boids separation, dynamic peer succession,
	ground-tethered orbital flocking, and coordinated aerial combat.
]]

---@class SwarmSubsystem
local swarm = {}

local modpath = core.get_modpath("x_mob_core")
local utils = dofile(modpath .. "/core/utils.lua")
local animator = dofile(modpath .. "/animation/animator.lua")
local sound = dofile(modpath .. "/audio/sound.lua")
local squad = dofile(modpath .. "/pack/squad.lua")
local coordination = dofile(modpath .. "/pack/coordination.lua")

--- Safeguards floating/swarm entity from sinking when touching liquid
---@param pos Vector Entity position
---@param vy number Current vertical velocity
---@return number vy Adjusted vertical velocity
local function apply_liquid_safeguard(pos, vy)
	local node_here = core.get_node_or_nil(pos)
	local ndef = node_here and core.registered_nodes[node_here.name]
	if ndef and ndef.liquidtype and ndef.liquidtype ~= "none" then
		return math.max(vy, 2.5)
	end
	return vy
end

--- Initializes an entity's swarm role, index, and state on activation
---@param self table Mob instance
---@param def table Mob definition table
---@param data table Deserialized static data table
function swarm.init_entity(self, def, data)
	local cfg = def.swarm
	if not cfg then return end

	self.saved_data = data or {}

	if self.saved_data.is_follower then
		self.pack_role = "member"
		self.pack_id = self.saved_data.pack_id
		self.follower_index = self.saved_data.follower_index or 1
	else
		self.pack_role = "leader"
		self.pack_id = self.saved_data.pack_id or utils.generate_uuid()
		self.saved_data.pack_id = self.pack_id
		self.follower_index = 0
		self.pack_followers = {}
		if not self.saved_data.cluster_spawned then
			self.saved_data.cluster_spawned = true
			self._needs_cluster_spawning = true
		end
	end

	self.saved_data.follower_index = self.follower_index

	-- Stagger initial attack cooldown across swarm members so they don't dive in unison
	if cfg.stagger_attacks ~= false then
		local stagger = (self.follower_index or 0) * 0.7
		self.attack_cooldown = 1.0 + stagger + math.random() * 0.4
	end
end



--- Calculates 3D Boids spatial repulsion with anti-stacking horizontal bias
---@param self table Mob instance
---@param pos Vector World position


--- Initializes organic multi-octave jitter and micro-dart parameters on an entity
---@param self table Mob instance
---@param idx integer Follower index
local function ensure_flock_params(self, idx)
	if self._flock_init then return end
	self._flock_init = true

	self._bob_freq = 1.4 + math.random() * 1.6
	self._bob_amp = 0.15 + math.random() * 0.20
	self._bob_phase = math.random() * math.pi * 2
	self._jitter_seed = math.random() * 100.0
	self._jitter_timer = 0
	self._freq_x1 = 3.2 + math.random() * 2.5
	self._freq_x2 = 8.0 + math.random() * 4.0
	self._freq_y1 = 3.5 + math.random() * 2.5
	self._freq_y2 = 9.0 + math.random() * 4.0
	self._freq_z1 = 3.2 + math.random() * 2.5
	self._freq_z2 = 8.0 + math.random() * 4.0
	self._flock_angle_offset = (idx / 6) * math.pi * 2
	self._flock_radius = 1.6 + (idx % 3) * 0.5
	self._dart_timer = 1.0 + math.random() * 2.0
	self._dart_vx = 0
	self._dart_vy = 0
	self._dart_vz = 0
end

--- Advances micro-dart impulse vectors and calculates harmonic velocity jitter
---@param self table Mob instance
---@param dtime number Step delta time
---@param cfg table Swarm configuration
---@return number jx
---@return number jy
---@return number jz
local function update_jitter_and_darts(self, dtime, cfg)
	self._jitter_timer = (self._jitter_timer or 0) + dtime

	if cfg.micro_darts ~= false then
		self._dart_timer = (self._dart_timer or 1.0) - dtime
		if self._dart_timer <= 0 then
			self._dart_timer = 1.5 + math.random() * 2.5
			self._dart_vx = (math.random() - 0.5) * 1.8
			self._dart_vy = (math.random() - 0.5) * 1.0
			self._dart_vz = (math.random() - 0.5) * 1.8
		else
			local decay = math.max(0, 1.0 - dtime * 3.5)
			self._dart_vx = (self._dart_vx or 0) * decay
			self._dart_vy = (self._dart_vy or 0) * decay
			self._dart_vz = (self._dart_vz or 0) * decay
		end
	else
		self._dart_vx = 0
		self._dart_vy = 0
		self._dart_vz = 0
	end

	local jx, jy, jz = 0, 0, 0
	if cfg.organic_jitter ~= false then
		local jt = self._jitter_timer
		local js = self._jitter_seed or 0
		jx = math.sin(jt * (self._freq_x1 or 4.0) + js) * 0.35 + math.sin(jt * (self._freq_x2 or 9.0) + js * 1.2) * 0.20
		jy = math.cos(jt * (self._freq_y1 or 4.0) + js) * 0.25 + math.sin(jt * (self._freq_y2 or 9.0) + js * 1.5) * 0.15
		jz = math.cos(jt * (self._freq_z1 or 4.0) + js) * 0.35 + math.cos(jt * (self._freq_z2 or 9.0) + js * 1.1) * 0.20
	end

	return jx, jy, jz
end

--- Advances ambient swarm idle locomotion: dynamic flocking, leader patrol, and ground contour tethering
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean is_handled
function swarm.step_flock(self, dtime, def)
	self.target = nil
	self.combat_mode = "orbit"
	self._dive_timer = 0

	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return false end

	local cfg = def.swarm or {}
	local idx = self.follower_index or 0
	ensure_flock_params(self, idx)

	local jx, jy, jz = update_jitter_and_darts(self, dtime, cfg)
	local sep_x, sep_y, sep_z = coordination.calculate_repulsion(
		self, pos, cfg.repulsion_radius or 2.2, cfg.repulsion_strength or 2.8, false, nil, 0.4, true
	)

	local hover_elev = cfg.hover_elevation or def.hover_offset or 1.4
	local cur_ground_y = utils.get_ground_y(pos, 8, 3, true)
	local cur_surface_y = utils.get_ground_y(pos, 8, 3, false)
	local jt = self._jitter_timer or 0

	-- Leader wander navigation: guides the swarm over walkable terrain
	if self.pack_role == "leader" then
		if not self.wander_origin then
			self.wander_origin = {x = pos.x, y = pos.y, z = pos.z}
		end

		self._wander_wait = (self._wander_wait or 0) - dtime
		if not self._wander_target or self._wander_wait <= 0 then
			if self._is_wandering then
				self._is_wandering = false
				self._wander_wait = 1.8 + math.random() * 2.5
				self._wander_target = nil
			else
				local wpt = utils.pick_ground_waypoint(
					pos, self.wander_origin, self.wander_radius or 10.0, 3.0, 7.5, hover_elev
				)
				if wpt then
					self._wander_target = wpt
					self._is_wandering = true
					self._wander_wait = 4.0 + math.random() * 3.0
				else
					self._wander_wait = 2.0
				end
			end
		end

		local vx, vz = 0, 0
		local vy
		if self._is_wandering and self._wander_target then
			local hdx = self._wander_target.x - pos.x
			local hdz = self._wander_target.z - pos.z
			local hdist = math.sqrt(hdx * hdx + hdz * hdz)

			if hdist > 0.6 then
				local wdir = {x = hdx / hdist, y = 0, z = hdz / hdist}
				local wyaw = core.dir_to_yaw(wdir)
				self.object:set_yaw(wyaw)
				self._cur_rot = {x = 0, y = wyaw, z = 0}

				local wspeed = self.wander_speed or 2.0
				vx = wdir.x * wspeed
				vz = wdir.z * wspeed
			else
				self._is_wandering = false
				self._wander_target = nil
				self._wander_wait = 1.8 + math.random() * 2.0
			end
		elseif not cur_ground_y and self.wander_origin then
			-- If out over deep water or void with no walkable ground, steer back toward wander origin
			local odx = self.wander_origin.x - pos.x
			local odz = self.wander_origin.z - pos.z
			local odist = math.sqrt(odx * odx + odz * odz)
			if odist > 0.5 then
				local rdir = {x = odx / odist, y = 0, z = odz / odist}
				local ryaw = core.dir_to_yaw(rdir)
				self.object:set_yaw(ryaw)
				self._cur_rot = {x = 0, y = ryaw, z = 0}
				local rspeed = self.wander_speed or 2.0
				vx = rdir.x * rspeed
				vz = rdir.z * rspeed
			end
		end

		local effective_ground_y = cur_ground_y or cur_surface_y
		local bob = math.sin(jt * (self._bob_freq or 1.5) + (self._bob_phase or 0)) * (self._bob_amp or 0.15)
		if effective_ground_y then
			local desired_y = effective_ground_y + hover_elev + bob
			vy = math.min(math.max((desired_y - pos.y) * 2.5, -2.5), 2.2)
		else
			-- Over a high drop/cliff void: maintain safe altitude relative to wander origin
			local safe_y = (self.wander_origin and self.wander_origin.y or pos.y) + hover_elev + bob
			vy = math.min(math.max((safe_y - pos.y) * 2.0, -0.8), 2.0)
		end

		-- Water contact safeguard: prevent sinking if touching liquid
		vy = apply_liquid_safeguard(pos, vy)

		self.object:set_velocity({
			x = vx + jx + (self._dart_vx or 0) + sep_x,
			y = vy + jy + (self._dart_vy or 0) + sep_y,
			z = vz + jz + (self._dart_vz or 0) + sep_z,
		})

		if self._is_wandering then
			self.state = "walk"
			animator.play(self.object, "walk", {speed = 1.0, loop = true})
		else
			self.state = "idle"
			animator.play(self.object, "idle", {speed = 1.0, loop = true})
		end
		return true
	end

	-- Follower flocking: flocks tightly in dynamic orbit around the pack leader
	local leader = self.leader_obj
	if leader and leader:is_valid() then
		local lpos = leader:get_pos()
		local lent = leader:get_luaentity()
		if lpos and lent and not lent.is_dead then
			local angle = (self._flock_angle_offset or 0) + jt * 0.45
			local slot_dist = self._flock_radius or (cfg.flock_radius or 2.0)
			local slot_x = lpos.x + math.cos(angle) * slot_dist
			local slot_z = lpos.z + math.sin(angle) * slot_dist

			local fdx = slot_x - pos.x
			local fdz = slot_z - pos.z
			local fdist = math.sqrt(fdx * fdx + fdz * fdz)

			local d_to_leader = vector.distance(pos, lpos)
			local fspeed = (d_to_leader > 4.5) and (self.pursuit_speed or 4.8) or (self.walk_speed or 2.6)

			local vx, vz = 0, 0
			if fdist > 0.2 then
				vx = (fdx / fdist) * math.min(fdist * 1.8, fspeed)
				vz = (fdz / fdist) * math.min(fdist * 1.8, fspeed)
				local fyaw = core.dir_to_yaw({x = vx, y = 0, z = vz})
				self.object:set_yaw(fyaw)
				self._cur_rot = {x = 0, y = fyaw, z = 0}
			end

			local gy = cur_ground_y or cur_surface_y or (lpos.y - hover_elev)
			local bob = math.sin(jt * (self._bob_freq or 1.5) + (self._bob_phase or 0)) * (self._bob_amp or 0.15)
			local desired_y = gy + hover_elev - 0.2 + ((idx % 3) * 0.35) + bob
			local vy = math.min(math.max((desired_y - pos.y) * 2.8, -2.5), 2.2)

			-- Follower liquid safeguard
			vy = apply_liquid_safeguard(pos, vy)

			self.object:set_velocity({
				x = vx + jx + (self._dart_vx or 0) + sep_x,
				y = vy + jy + (self._dart_vy or 0) + sep_y,
				z = vz + jz + (self._dart_vz or 0) + sep_z,
			})

			if fdist > 0.4 then
				self.state = "walk"
				animator.play(self.object, "walk", {speed = 1.1, loop = true})
			else
				self.state = "idle"
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
			end
			return true
		end
	end

	-- Fallback: if leader is missing, try to link with another surviving leader nearby
	squad.relink_follower(self, 24.0)

	-- If still orphaned, hover safely over solid ground
	local vy
	local effective_ground_y = cur_ground_y or cur_surface_y
	if effective_ground_y then
		local desired_y = effective_ground_y + hover_elev
		vy = math.min(math.max((desired_y - pos.y) * 2.0, -2.0), 2.0)
	else
		local safe_y = (self.wander_origin and self.wander_origin.y or pos.y) + hover_elev
		vy = math.min(math.max((safe_y - pos.y) * 2.0, -0.8), 2.0)
	end

	vy = apply_liquid_safeguard(pos, vy)

	self.object:set_velocity({
		x = jx + sep_x,
		y = vy + jy,
		z = jz + sep_z,
	})
	self.state = "idle"
	animator.play(self.object, "idle", {speed = 1.0, loop = true})
	return true
end

--- Executes standard dive attack strike with animation, sound, and horizontal recoil
---@param self table Mob instance
---@param target ObjectRef Target entity
---@param dir Vector Strike direction
---@param def table Mob definition table
function swarm.perform_attack(self, target, dir, def)
	self.state = "attacking"
	self.combat_mode = "orbit"
	self._dive_timer = 0
	self.action_timer = 0.4

	local swarm_cfg = def.swarm or {}
	self.attack_cooldown = (swarm_cfg.attack_cooldown_min or 2.5) + math.random() * (swarm_cfg.attack_cooldown_rand or 2.5)

	animator.play(self.object, "attack", {speed = 1.6, loop = false})
	sound.play(self, "attack")

	local attack_dir = dir or {x = 0, y = 0, z = 1}
	self.object:set_velocity({
		x = attack_dir.x * 5.0,
		y = attack_dir.y * 3.0,
		z = attack_dir.z * 5.0,
	})

	local atk_range = self.attack_range or 1.6
	local atk_dmg = self.damage or 2
	local recoil_force = (swarm_cfg.combat and swarm_cfg.combat.recoil) or 4.5

	x_mob_core.schedule(self, 0.18, "scheduled_action", function()
		if target and target:is_valid() then
			local cp = self.object and self.object:is_valid() and self.object:get_pos()
			local tp = target:get_pos()
			if cp and tp and vector.distance(cp, tp) <= atk_range + 1.0 then
				target:punch(self.object, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = { fleshy = atk_dmg },
				}, attack_dir)

				local rdx = cp.x - tp.x
				local rdz = cp.z - tp.z
				local rdist = math.sqrt(rdx * rdx + rdz * rdz)
				local rx, rz
				if rdist > 0.1 then
					rx = rdx / rdist
					rz = rdz / rdist
				else
					local ang = math.random() * math.pi * 2
					rx = math.cos(ang)
					rz = math.sin(ang)
				end
				self.object:set_velocity({
					x = rx * recoil_force,
					y = -0.4,
					z = rz * recoil_force,
				})
			end
		end
	end)
end

--- Initializes combat holding pattern parameters
---@param self table Mob instance
---@param c_cfg table Combat configuration
local function ensure_combat_params(self, c_cfg)
	if self._swarm_init then return end
	self._swarm_init = true

	local idx = self.follower_index
	if c_cfg.two_way_orbit ~= false then
		if idx then
			self._orbit_sign = (idx % 2 == 0) and 1 or -1
		else
			self._orbit_sign = (math.random() > 0.5) and 1 or -1
		end
	else
		self._orbit_sign = 1
	end

	local shells = c_cfg.orbit_shells or 3
	local shell = (idx or math.random(0, 5)) % shells
	local base_rad = c_cfg.orbit_radius or 2.6
	self._orbit_dist = base_rad + shell * 0.7 + math.random() * 0.4
	self._orbit_speed = 3.2 + math.random() * 1.8
	self._speed_variance = (math.random() - 0.5) * 1.0

	local h_off = c_cfg.height_offset or 0.7
	self._eye_y_offset = h_off + shell * 0.3 + (math.random() - 0.5) * 0.15

	self._bob_freq = 1.5 + math.random() * 1.8
	self._bob_amp = 0.12 + math.random() * 0.15
	self._bob_phase = math.random() * math.pi * 2

	self._freq_x1 = 3.5 + math.random() * 3.0
	self._freq_x2 = 8.5 + math.random() * 5.0
	self._freq_y1 = 4.0 + math.random() * 3.0
	self._freq_y2 = 10.0 + math.random() * 5.0
	self._freq_z1 = 3.5 + math.random() * 3.0
	self._freq_z2 = 8.5 + math.random() * 5.0
	self._jitter_seed = math.random() * 100.0
	self._jitter_amp = 0.75 + math.random() * 0.4

	self._dart_timer = 0.5 + math.random() * 1.5
	self._dart_vx = 0
	self._dart_vy = 0
	self._dart_vz = 0
end

--- Advances coordinated combat locomotion: vortex holding pattern and dive-bomb attack runs
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean is_handled
function swarm.step_combat(self, dtime, def)
	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	local tpos = self.target and self.target:is_valid() and self.target:get_pos()
	if not pos or not tpos then
		self.target = nil
		return false
	end

	local cfg = def.swarm or {}
	local c_cfg = cfg.combat or {}

	local dist = vector.distance(pos, tpos)
	local dir = vector.direction(pos, tpos)
	local target_yaw = core.dir_to_yaw(dir)

	local eye_offset = self.eye_offset or 0.38
	local eye_pos = {x = pos.x, y = pos.y + eye_offset, z = pos.z}
	local player_eye = {x = tpos.x, y = tpos.y + 1.5, z = tpos.z}
	local attack_los = utils.line_of_sight(eye_pos, player_eye)

	self.object:set_yaw(target_yaw)
	self._cur_rot = {x = 0, y = target_yaw, z = 0}

	-- Swarm threat broadcast: call nearby pack mates to attack target
	self._rally_timer = (self._rally_timer or 0) - dtime
	if self._rally_timer <= 0 then
		self._rally_timer = 0.8
		coordination.broadcast_threat(self, self.target, 24.0)
	end

	local dive_thresh = c_cfg.dive_range or 9.0
	if (self.attack_cooldown or 0) <= 0 and dist <= dive_thresh and attack_los then
		self.combat_mode = "dive"
	end

	-- Dive-bomb attack run toward target face/chest
	if self.combat_mode == "dive" then
		self._dive_timer = (self._dive_timer or 0) + dtime

		local atk_reach = self.attack_range or 1.6
		if dist <= atk_reach then
			if def.perform_attack then
				def.perform_attack(self, self.target, dir)
			else
				swarm.perform_attack(self, self.target, dir, def)
			end
			return true
		end

		local aim_h = c_cfg.height_offset or 1.2
		local aim_pos = {x = tpos.x, y = tpos.y + aim_h, z = tpos.z}
		local dive_dir = vector.direction(pos, aim_pos)
		local dive_yaw = core.dir_to_yaw(dive_dir)
		self.object:set_yaw(dive_yaw)
		self._cur_rot = {x = 0, y = dive_yaw, z = 0}

		local dive_speed = (c_cfg.dive_speed or 6.4) + (self._speed_variance or 0)
		self.object:set_velocity({
			x = dive_dir.x * dive_speed,
			y = dive_dir.y * dive_speed,
			z = dive_dir.z * dive_speed,
		})

		if self.state ~= "dive" then
			self.state = "dive"
			animator.play(self.object, "walk", {speed = 1.8, loop = true})
		end

		if self._dive_timer > 1.4 or not attack_los then
			self.combat_mode = "orbit"
			self._dive_timer = 0
			self.attack_cooldown = 1.5 + math.random() * 1.5
		end
		return true
	end

	-- Swarm orbital holding pattern around the target (concentric vortex)
	if dist <= dive_thresh then
		self._dive_timer = 0
		ensure_combat_params(self, c_cfg)

		self._jitter_timer = (self._jitter_timer or 0) + dtime

		if cfg.micro_darts ~= false then
			self._dart_timer = (self._dart_timer or 1.0) - dtime
			if self._dart_timer <= 0 then
				self._dart_timer = 1.2 + math.random() * 2.0
				self._dart_vx = (math.random() - 0.5) * 2.8
				self._dart_vy = (math.random() - 0.5) * 0.8
				self._dart_vz = (math.random() - 0.5) * 2.8
			else
				local decay = math.max(0, 1.0 - dtime * 4.0)
				self._dart_vx = (self._dart_vx or 0) * decay
				self._dart_vy = (self._dart_vy or 0) * decay
				self._dart_vz = (self._dart_vz or 0) * decay
			end
		end

		local hdx = pos.x - tpos.x
		local hdz = pos.z - tpos.z
		local h_dist = math.sqrt(hdx * hdx + hdz * hdz)

		local rx, rz
		if h_dist > 0.15 then
			rx = hdx / h_dist
			rz = hdz / h_dist
		else
			local escape_ang = (self.follower_index or 1) * (math.pi / 3) + (self._jitter_timer or 0)
			rx = math.cos(escape_ang)
			rz = math.sin(escape_ang)
			h_dist = 0.15
		end

		local tx = -rz * (self._orbit_sign or 1)
		local tz = rx * (self._orbit_sign or 1)

		local radial_adjust = ((self._orbit_dist or 3.2) - h_dist) * 2.2
		local min_player_radius = c_cfg.exclusion_radius or 2.4
		if h_dist < min_player_radius then
			local repulsion = (min_player_radius - h_dist) * 5.5
			radial_adjust = radial_adjust + repulsion
		end

		local o_spd = self._orbit_speed or 3.2
		local vx = tx * o_spd + rx * radial_adjust
		local vz = tz * o_spd + rz * radial_adjust

		local bob = math.sin((self._jitter_timer or 0) * (self._bob_freq or 1.5)
			+ (self._bob_phase or 0)) * (self._bob_amp or 0.12)
		local target_y = tpos.y + (self._eye_y_offset or 1.0) + bob
		local vy = math.min(math.max((target_y - pos.y) * 2.8, -2.5), 2.0)

		if c_cfg.clamp_ceiling ~= false and pos.y > tpos.y + 1.55 then
			vy = -3.2
		end

		local jt = self._jitter_timer or 0
		local js = self._jitter_seed or 0
		local ja = self._jitter_amp or 0.75
		local jx = (math.sin(jt * (self._freq_x1 or 4.0) + js) * 0.55
			+ math.sin(jt * (self._freq_x2 or 9.0) + js * 1.3) * 0.35) * ja
		local jy = (math.cos(jt * (self._freq_y1 or 4.0) + js) * 0.30
			+ math.sin(jt * (self._freq_y2 or 9.0) + js * 1.7) * 0.15) * ja
		local jz = (math.cos(jt * (self._freq_z1 or 4.0) + js) * 0.55
			+ math.cos(jt * (self._freq_z2 or 9.0) + js * 1.1) * 0.35) * ja

		local sep_x, sep_y, sep_z = coordination.calculate_repulsion(
			self, pos, cfg.repulsion_radius or 2.4, (cfg.repulsion_strength or 2.8) * 1.2, false, nil, 0.4, true
		)

		self.object:set_velocity({
			x = vx + jx + (self._dart_vx or 0) + sep_x,
			y = vy + jy + (self._dart_vy or 0) + sep_y,
			z = vz + jz + (self._dart_vz or 0) + sep_z,
		})

		if self.state ~= "circling" then
			self.state = "circling"
			animator.play(self.object, "walk", {speed = 1.3, loop = true})
		end
		return true
	end

	-- Long-range pursuit locomotion when target retreats beyond swarm radius
	local chase_dir = vector.direction(pos, player_eye)
	local chase_yaw = core.dir_to_yaw(chase_dir)
	self.object:set_yaw(chase_yaw)
	self._cur_rot = {x = 0, y = chase_yaw, z = 0}
	local chase_speed = self.pursuit_speed or 5.2
	self.object:set_velocity(vector.multiply(chase_dir, chase_speed))
	animator.play(self.object, "walk", {speed = 1.5, loop = true})
	return true
end

--- Master step dispatcher for swarming entities
---@param self table Mob instance
---@param dtime number Step delta time
---@param def table Mob definition table
---@return boolean is_handled
function swarm.step(self, dtime, def)
	if self._needs_cluster_spawning then
		self._needs_cluster_spawning = false
		squad.spawn_cluster(self, def)
	end

	self.attack_cooldown = math.max(0, (self.attack_cooldown or 0) - dtime)

	if self.state == "attacking" then
		return true
	end

	if not utils.is_player_alive(self.target) then
		return swarm.step_flock(self, dtime, def)
	end

	return swarm.step_combat(self, dtime, def)
end

--- Action end hook to transition attacking mobs back to combat walk
---@param self table Mob instance
---@param _def table Mob definition table
function swarm.on_action_end(self, _def)
	if self.state == "attacking" then
		self.state = "combat"
		if self.object and self.object:is_valid() and not self.is_dead then
			animator.play(self.object, "walk", {speed = 1.3, loop = true})
		end
	end
end

return swarm
