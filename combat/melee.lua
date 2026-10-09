--[[
	x_mob_core - Universal Melee Combat Subsystem
	Declarative close-quarters combat handler for terrestrial, custom, and hybrid mobs.
]]

---Universal Melee Combat Subsystem.
---@class MeleeSubsystem
local melee = {}

local modpath = core.get_modpath("x_mob_core") or "."
local utils = dofile(modpath .. "/core/utils.lua")
local animator = dofile(modpath .. "/animation/animator.lua")
local sound = dofile(modpath .. "/audio/sound.lua")
local factions = dofile(modpath .. "/combat/factions.lua")

---Checks whether a target is valid for a melee strike
---@param self table Mob entity instance
---@param target ObjectRef Target object to test
---@return boolean is_valid
function melee.is_valid_target(self, target)
	if not target or not target:is_valid() then return false end
	if self.object and target == self.object then return false end
	if target:is_player() then
		if not utils.is_player_alive(target) then return false end
		if not self.friendly_fire and factions.are_allies(self.object, target) then
			return false
		end
		return true
	end
	local ent = target:get_luaentity()
	if not ent then return false end
	if ent.name == "__builtin:item" or ent.name == "__builtin:falling_node" or ent.name:find("^__builtin:") then
		return false
	end
	if ent.name == "x_mob_core:health_bar" or ent._is_health_bar then
		return false
	end
	if not self.friendly_fire and factions.are_allies(self.object, target) then
		return false
	end
	return true
end

---Executes an instantaneous melee strike on target
---@param self table Mob entity instance
---@param target ObjectRef Target entity
---@param dir Vector Strike impulse direction
---@param def table Mob definition table
---@param m_cfg table Melee configuration table
function melee.perform_attack(self, target, dir, def, m_cfg)
	if def.perform_attack then
		def.perform_attack(self, target, dir)
	elseif m_cfg and m_cfg.perform_attack then
		m_cfg.perform_attack(self, target, dir)
	else
		local dmg = (m_cfg and m_cfg.damage) or def.damage or 4
		local atk_mult = self.object and x_mob_core.get_attack_multiplier(self.object) or 1.0
		if atk_mult and atk_mult > 0 and atk_mult ~= 1.0 then
			dmg = math.max(1, math.floor(dmg * atk_mult + 0.5))
		end
		target:punch(self.object, 1.0, {
			full_punch_interval = 1.0,
			damage_groups = { fleshy = dmg },
		}, dir)
	end

	if m_cfg and m_cfg.on_strike then
		m_cfg.on_strike(self, target, dir)
	end
end

---Universal step handler for melee attacks
---@param self table Mob entity instance
---@param _dtime number Step delta time
---@param def table Entity definition table
---@return boolean handled True if the melee logic handled or intercepted combat
function melee.step(self, _dtime, def)
	if not self.target or not melee.is_valid_target(self, self.target) then
		return false
	end

	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	local tpos = self.target:get_pos()
	if not pos or not tpos then return false end

	local m_cfg = type(def.melee) == "table" and def.melee or {}
	local reach = m_cfg.range or def.attack_range or 2.0
	local max_h_diff = m_cfg.max_height_diff or 2.0

	local dist = vector.distance(pos, tpos)
	local dx = pos.x - tpos.x
	local dz = pos.z - tpos.z
	local hdist = math.sqrt(dx * dx + dz * dz)
	local vdist = math.abs(pos.y - tpos.y)

	local in_reach = (dist <= reach) or (hdist <= reach and vdist <= max_h_diff)
	if not in_reach then return false end

	local eye_pos = { x = pos.x, y = pos.y + (self.eye_offset or 1.5), z = pos.z }
	local target_eye = { x = tpos.x, y = tpos.y + 1.2, z = tpos.z }
	local los = utils.line_of_sight(eye_pos, target_eye)
	if not los then return false end

	-- Target is in reach and in sight: halt horizontal velocity and face target
	x_mob_core.halt_horizontal_velocity(self)
	local to_target = vector.direction(pos, tpos)
	to_target.y = 0
	local len = math.sqrt(to_target.x * to_target.x + to_target.z * to_target.z)
	if len > 0.01 then
		to_target = { x = to_target.x / len, y = 0, z = to_target.z / len }
	else
		to_target = { x = 0, y = 0, z = 1 }
	end
	local face_yaw = core.dir_to_yaw(to_target)
	self.object:set_yaw(face_yaw)
	self._cur_rot = { x = 0, y = face_yaw, z = 0 }

	-- Attack execution
	if (self.attack_cooldown or 0) <= 0 then
		local active_attack = m_cfg
		if m_cfg.attacks and #m_cfg.attacks > 0 then
			local total_weight = 0
			for i = 1, #m_cfg.attacks do
				total_weight = total_weight + (m_cfg.attacks[i].weight or 1)
			end
			local roll = math.random() * total_weight
			local current = 0
			for i = 1, #m_cfg.attacks do
				local atk = m_cfg.attacks[i]
				current = current + (atk.weight or 1)
				if roll <= current then
					active_attack = atk
					break
				end
			end
		end

		local duration = active_attack.duration or m_cfg.duration or 0.5
		local cooldown = active_attack.cooldown or m_cfg.cooldown or def.attack_interval or 1.2
		local delay = active_attack.delay or m_cfg.delay or 0.25
		local anim = active_attack.animation or m_cfg.animation or "attack"
		local anim_speed = active_attack.anim_speed or m_cfg.anim_speed or 1.2
		local attack_sound = active_attack.sound or m_cfg.sound or "attack"

		self.state = "attacking"
		self.action_timer = duration
		self.attack_cooldown = cooldown

		animator.play(self.object, anim, { speed = anim_speed, loop = false, force = true })
		if attack_sound then
			sound.play(self, attack_sound)
		end

		local on_start_cb = active_attack.on_start or active_attack.on_charge or m_cfg.on_start or m_cfg.on_charge
		if on_start_cb then
			on_start_cb(self, self.target)
		end

		x_mob_core.schedule(self, delay, "melee_strike", function()
			local cp = self.object and self.object:is_valid() and self.object:get_pos()
			if not cp then return end

			if active_attack.aoe and active_attack.perform_attack then
				local strike_dir = { x = 0, y = 0, z = 1 }
				if self.target and self.target:is_valid() then
					local tp = self.target:get_pos()
					if tp then
						strike_dir = vector.direction(cp, tp)
					end
				end
				melee.perform_attack(self, self.target, strike_dir, def, active_attack)
				return
			end

			if not self.target or not melee.is_valid_target(self, self.target) then
				return
			end
			local tp = self.target:get_pos()
			if not tp then return end

			local tol = active_attack.reach_tolerance or m_cfg.reach_tolerance or 0.6
			local cur_dist = vector.distance(cp, tp)
			local c_dx = cp.x - tp.x
			local c_dz = cp.z - tp.z
			local cur_hdist = math.sqrt(c_dx * c_dx + c_dz * c_dz)
			local cur_vdist = math.abs(cp.y - tp.y)

			local max_r = reach + tol
			if cur_dist <= max_r or (cur_hdist <= max_r and cur_vdist <= (max_h_diff + 0.5)) then
				local c_eye = { x = cp.x, y = cp.y + (self.eye_offset or 1.5), z = cp.z }
				local t_eye = { x = tp.x, y = tp.y + 1.2, z = tp.z }
				if utils.line_of_sight(c_eye, t_eye) then
					local strike_dir = vector.direction(cp, tp)
					if strike_dir.x == 0 and strike_dir.y == 0 and strike_dir.z == 0 then
						strike_dir = { x = 0, y = 1, z = 0 }
					end
					melee.perform_attack(self, self.target, strike_dir, def, active_attack)
				end
			end
		end)
		return true
	end

	-- On attack cooldown: hold idle pose facing target
	if self.state ~= "attacking" and self.state ~= "idle" then
		self.state = "idle"
		animator.play(self.object, "idle", { speed = 1.0, loop = true })
	end

	return true
end

return melee
