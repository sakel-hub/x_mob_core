local shooter = {}

local modpath = core.get_modpath("x_mob_core") or "."
local utils = dofile(modpath .. "/core/utils.lua")
local animator = dofile(modpath .. "/animation/animator.lua")
local sound = dofile(modpath .. "/audio/sound.lua")
local factions = dofile(modpath .. "/combat/factions.lua")

--- Predicts target intercept position and direction based on target velocity and projectile speed
---@param origin Vector Projectile launch origin
---@param tgt_center Vector Target center position
---@param tgt_vel? Vector Target velocity vector
---@param proj_speed number Projectile travel speed
---@return Vector predicted_pos Predicted intercept position
---@return Vector dir Normalized direction vector towards predicted position
function shooter.predict_aim(origin, tgt_center, tgt_vel, proj_speed)
	local dir = vector.direction(origin, tgt_center)
	if not tgt_vel or (tgt_vel.x == 0 and tgt_vel.y == 0 and tgt_vel.z == 0) or not proj_speed or proj_speed <= 0 then
		return tgt_center, dir
	end
	local dist = vector.distance(origin, tgt_center)
	local t = math.min(dist / proj_speed, 1.2)
	local predicted = {
		x = tgt_center.x + tgt_vel.x * t,
		y = tgt_center.y + (math.abs(tgt_vel.y) > 2.0 and (tgt_vel.y * t * 0.5) or (tgt_vel.y * t)),
		z = tgt_center.z + tgt_vel.z * t,
	}
	local p_dir = vector.direction(origin, predicted)
	if p_dir.x == 0 and p_dir.y == 0 and p_dir.z == 0 then
		return tgt_center, dir
	end
	return predicted, p_dir
end

---Agnostically determines if a LuaEntity represents an active projectile, arrow, or ballistic entity.
---Polymorphically evaluates standard duck-typed projectile interfaces.
---@param ent table LuaEntity table
---@return boolean is_projectile
function shooter.is_projectile(ent)
	if not ent then return false end
	return ent._is_projectile == true
		or ent.is_projectile == true
		or ent._is_arrow == true
		or ent.is_arrow == true
		or ent._is_bullet == true
		or ent.is_bullet == true
		or ent._shooter ~= nil
		or ent.shooter ~= nil
end

--- Validates whether an object is a targetable enemy for a projectile or shooter mob.
--- Agnostically filters out dropped items (__builtin:item), falling nodes, utility health bars,
--- shooter self-hits, and faction allies.
---@param source_or_proj ObjectRef|table Projectile entity instance, shooter mob, or ObjectRef
---@param obj ObjectRef Target object to test
---@param options? ProjectileTargetOptions Optional configuration table
---@return boolean is_valid True if target is attackable, false if ignored
function shooter.is_valid_target(source_or_proj, obj, options)
	if not obj or not obj:is_valid() then return false end

	local self_obj = nil
	local shooter_obj = nil
	if type(source_or_proj) == "table" then
		self_obj = source_or_proj.object
		shooter_obj = source_or_proj._shooter or self_obj
	elseif type(source_or_proj) == "userdata" then
		self_obj = source_or_proj
		local ent = source_or_proj.get_luaentity and source_or_proj:get_luaentity()
		shooter_obj = (ent and ent._shooter) or self_obj
	end

	-- Exclude self and shooter
	if self_obj and obj == self_obj then return false end
	if shooter_obj and shooter_obj:is_valid() and obj == shooter_obj then return false end

	local opts = options or {}

	-- Player handling
	if obj:is_player() then
		if opts.allow_players == false then return false end
		local allow_allies = opts.allow_allies == true
		if not allow_allies and shooter_obj and shooter_obj:is_valid() then
			if factions.are_allies(shooter_obj, obj) then
				return false
			end
		end
		return true
	end

	-- Entity handling
	local ent = obj:get_luaentity()
	if not ent then return false end

	local name = ent.name
	-- Ignore dropped items, falling nodes, and all engine built-in non-mob entities
	if not name or name == "__builtin:item" or name == "__builtin:falling_node" or name:find("^__builtin:") then
		return false
	end

	-- Ignore utility health bars
	if name == "x_mob_core:health_bar" or ent._is_health_bar then
		return false
	end

	-- Resolve projectile entity name
	local proj_name = nil
	if type(source_or_proj) == "table" then
		proj_name = source_or_proj.name
		if not proj_name and source_or_proj.object and source_or_proj.object.get_luaentity then
			local l_ent = source_or_proj.object:get_luaentity()
			proj_name = l_ent and l_ent.name
		end
	end
	if not proj_name and (type(source_or_proj) == "userdata" or type(source_or_proj) == "table")
			and source_or_proj.get_luaentity then
		local l_ent = source_or_proj:get_luaentity()
		proj_name = l_ent and l_ent.name
	end

	-- Ignore projectile's own entity type or active projectiles to prevent mid-air projectile collisions
	if (proj_name and name == proj_name) or shooter.is_projectile(ent) then
		return false
	end

	-- Check explicit ignored entity list
	local ignored = opts.ignore_entities
	if ignored then
		if ignored[name] then return false end
		for i = 1, #ignored do
			if ignored[i] == name then return false end
		end
	end

	-- Check faction allegiance / friendly fire
	local allow_allies = opts.allow_allies == true
	if not allow_allies then
		local src = (shooter_obj and shooter_obj:is_valid()) and shooter_obj or self_obj
		if src and factions.are_allies(src, obj) then
			return false
		end
	end

	return true
end

--- Standard projectile flight step handler: ballistics rotation, lifetime expiry,
--- continuous raycasting, proximity detection, and impact resolution.
---@param self table Projectile LuaEntity instance
---@param dtime number Step delta time
---@param options? ProjectileStepOptions Projectile configuration options
---@return boolean hit True if projectile collided with target or solid node
---@return ObjectRef|nil hit_obj Target object collided with
---@return Vector|nil hit_pos Impact location in world coordinates
function shooter.step_projectile(self, dtime, options)
	local obj = self.object
	if not obj or not obj:is_valid() then return false end

	local pos = obj:get_pos()
	if not pos then return false end

	local opts = options or {}

	-- Update rotation to match trajectory velocity
	if opts.rotate ~= false then
		local vel = obj:get_velocity()
		if vel and (vel.x ~= 0 or vel.y ~= 0 or vel.z ~= 0) then
			obj:set_rotation(vector.dir_to_rotation(vel))
		end
	end

	-- Lifetime expiration
	local dt = dtime or 0.05
	self.timer = (self.timer or 0) + dt
	local max_life = opts.lifetime or 4.0
	if self.timer > max_life then
		obj:remove()
		return false
	end

	local old_pos = self._old_pos or pos
	self._old_pos = pos

	local hit = false
	local hit_obj = nil
	local hit_pos = pos

	-- 1. Continuous Raycast check (avoids tunneling through obstacles or targets)
	local ray = core.raycast(old_pos, pos, true, false)
	for pt in ray do
		if pt.type == "object" then
			local cand = pt.ref
			if shooter.is_valid_target(self, cand, opts) then
				hit = true
				hit_obj = cand
				hit_pos = pt.intersection_point or pos
				break
			end
		elseif pt.type == "node" then
			local node = core.get_node(pt.under)
			local node_def = core.registered_nodes[node.name]
			if node_def and node_def.walkable then
				hit = true
				hit_pos = pt.intersection_point or pos
				break
			end
		end
	end

	-- 2. Proximity fallback (catches sub-block launch positions or stationary targets)
	if not hit then
		local radius = opts.radius or 1.5
		local nearby = core.get_objects_inside_radius(pos, radius)
		for i = 1, #nearby do
			local cand = nearby[i]
			if shooter.is_valid_target(self, cand, opts) then
				hit = true
				hit_obj = cand
				hit_pos = pos
				break
			end
		end
	end

	-- 3. Embedded node fallback (in case projectile spawned inside or penetrated block boundary)
	if not hit then
		local node = core.get_node(pos)
		local node_def = core.registered_nodes[node.name]
		if node_def and node_def.walkable then
			hit = true
			hit_pos = pos
		end
	end

	if hit then
		local shooter_ref = (self._shooter and self._shooter:is_valid()) and self._shooter or obj

		if hit_obj and hit_obj:is_valid() then
			if opts.on_hit_object then
				local opos = hit_obj:get_pos()
				local dir = opos and vector.direction(pos, opos) or {x = 0, y = 1, z = 0}
				opts.on_hit_object(self, hit_obj, hit_pos, dir)
			else
				local dmg = self._damage or opts.damage or 5
				local opos = hit_obj:get_pos()
				local dir = opos and vector.direction(pos, opos) or {x = 0, y = 1, z = 0}
				if dir.x == 0 and dir.y == 0 and dir.z == 0 then
					dir = {x = 0, y = 1, z = 0}
				end
				hit_obj:punch(shooter_ref, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = {fleshy = dmg},
				}, dir)
			end
		else
			local n_pos = {
				x = math.floor(hit_pos.x + 0.5),
				y = math.floor(hit_pos.y + 0.5),
				z = math.floor(hit_pos.z + 0.5),
			}
			local node = core.get_node(n_pos)
			if opts.on_hit_node then
				opts.on_hit_node(self, hit_pos, node)
			end
		end

		if opts.on_hit then
			opts.on_hit(self, hit_obj, hit_pos)
		end

		if opts.remove_on_hit ~= false then
			obj:remove()
		end

		return true, hit_obj, hit_pos
	end

	-- Unobstructed flight step callback (e.g. particle trails, acoustic sound fx)
	if opts.on_step then
		opts.on_step(self, dt, pos)
	end

	return false
end

--- Universal ranged combat handler for shooter mobs
---@param self table Mob entity instance
---@param _dtime number Step delta time
---@param def table Entity definition table
---@return boolean handled True if the shooter logic intercepted movement/combat
function shooter.step(self, dtime, def)
	if not self.target then return false end
	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	local tpos = self.target:is_valid() and self.target:get_pos()
	if not pos or not tpos then return false end

	local cfg = type(def.shooter) == "table" and def.shooter or {}
	local range = cfg.range or def.attack_range or 15.0
	local min_range = cfg.min_range or 0.0
	local dist = vector.distance(pos, tpos)

	-- If out of max range, let standard locomotion AI handle pursuit
	if dist > range then return false end

	local eye_pos = {x = pos.x, y = pos.y + (self.eye_offset or 1.5), z = pos.z}
	local target_eye = {x = tpos.x, y = tpos.y + 1.5, z = tpos.z}
	local los = utils.line_of_sight(eye_pos, target_eye)

	-- If blocked by walls, let standard locomotion AI navigate around
	if not los then return false end

	-- Face target
	local yaw = core.dir_to_yaw(vector.direction(pos, tpos))
	self.object:set_yaw(yaw)
	self._cur_rot = {x = 0, y = yaw, z = 0}

	-- Active retreat if target gets too close (kiting)
	local is_retreating = false
	if dist < min_range then
		is_retreating = x_mob_core.retreat_from(self, tpos, cfg.retreat_speed or 1.0)
	end

	-- Handle mobile shooting animation timer
	if self._shoot_anim_timer and self._shoot_anim_timer > 0 then
		self._shoot_anim_timer = self._shoot_anim_timer - (dtime or 0.05)
		if not is_retreating then
			x_mob_core.halt_horizontal_velocity(self)
		end
		if self._shoot_anim_timer <= 0 then
			self._shoot_anim_timer = nil
			if self.state == "attacking" then
				if is_retreating then
					self.state = "retreating"
					animator.play(self.object, "walk", {speed = 1.2, loop = true})
				else
					self.state = "idle"
					animator.play(self.object, "idle", {speed = 1.0, loop = true})
				end
			end
		end
	end

	-- Ready to fire!
	if (self.attack_cooldown or 0) <= 0 then
		local can_shoot_while_retreating = (cfg.shoot_while_retreating ~= false) and is_retreating

		if not can_shoot_while_retreating then
			-- Stop horizontal movement to fire cleanly when stationary
			x_mob_core.halt_horizontal_velocity(self)

			self.state = "attacking"
			self.action_timer = cfg.fire_duration or 1.0
		else
			-- Shoot on the move while maintaining retreat velocity
			self.state = "attacking"
			self._shoot_anim_timer = cfg.fire_duration or 0.8
		end

		self.attack_cooldown = cfg.cooldown or 2.0

		local anim = cfg.animation or "attack"
		animator.play(self.object, anim, {speed = 1.0, loop = false, force = true})

		local shoot_sound = cfg.sound or "shoot"
		sound.play(self, shoot_sound)

		local delay = cfg.fire_delay or 0.4
		x_mob_core.schedule(self, delay, "shoot_projectile", function()
			if self.target and utils.is_player_alive(self.target) then
					local cp = self.object:get_pos()
					local tp = self.target:get_pos()
					if cp and tp then
						local proj = cfg.projectile or "x_mobs:archer_arrow"
						local origin = {x = cp.x, y = cp.y + (self.eye_offset or 1.5), z = cp.z}
						local tgt_center = {x = tp.x, y = tp.y + 1.0, z = tp.z}
						local p_vel = cfg.velocity or 18.0

						local dir
						if cfg.predict_aim then
							local t_vel = self.target:get_velocity()
							dir = select(2, shooter.predict_aim(origin, tgt_center, t_vel, p_vel))
						else
							dir = vector.direction(origin, tgt_center)
						end

						local p_obj = core.add_entity(origin, proj)
						if p_obj and p_obj:is_valid() then
							p_obj:set_velocity(vector.multiply(dir, p_vel))
							p_obj:set_rotation(vector.dir_to_rotation(dir))
							-- Standardize projectile metadata
							local p_ent = p_obj:get_luaentity()
							if p_ent then
								p_ent._shooter = self.object
								p_ent._damage = cfg.damage or 3
							end
						end
					end
				end
			end)
		return true
	end

	-- On cooldown: if retreating, play walk animation; if standing ground, play idle
	if self.state ~= "attacking" then
		if is_retreating then
			if self.state ~= "retreating" then
				self.state = "retreating"
				animator.play(self.object, "walk", {speed = 1.2, loop = true})
			end
		else
			-- Not retreating: stand ground and aim
			x_mob_core.halt_horizontal_velocity(self)

			if self.state ~= "idle" then
				self.state = "idle"
				animator.play(self.object, "idle", {speed = 1.0, loop = true})
			end
		end
	end

	return true
end

return shooter
