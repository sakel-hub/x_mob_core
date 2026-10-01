local shooter = {}

local utils = dofile(core.get_modpath("x_mob_core") .. "/core/utils.lua")
local animator = dofile(core.get_modpath("x_mob_core") .. "/animation/animator.lua")
local sound = dofile(core.get_modpath("x_mob_core") .. "/audio/sound.lua")

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
