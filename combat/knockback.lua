--[[
	x_mob_core - Knockback Physics Subsystem
	Liquid knockback dampening and velocity clamping
]]

---@class KnockbackSubsystem
local knockback = {}

--- Dampens punch knockback when an entity is struck inside water
---@param self table Mob entity instance
function knockback.dampen_water_knockback(self)
	if not self or not self.object or not self.object:is_valid() then return end
	local pos = self.object:get_pos()
	if not pos then return end
	local in_liquid = x_mob_core.motor.safety.check_in_liquid(
		pos, self.abilities or {can_swim = true}, self.mob_height or 1.5
	)
	if in_liquid then
		core.after(0, function()
			if self.object and self.object:is_valid() and not self.is_dead and self.state ~= "dying" then
				local v = self.object:get_velocity()
				if v then
					local max_h = 2.0
					local vx = math.max(-max_h, math.min(max_h, v.x * 0.35))
					local vz = math.max(-max_h, math.min(max_h, v.z * 0.35))
					local vy = math.max(-0.6, math.min(0.6, v.y * 0.15))
					self.object:set_velocity({x = vx, y = vy, z = vz})
				end
			end
		end)
	end
end

--- Returns the effective knockback multiplier for an entity or ObjectRef
---@param obj ObjectRef|table Target object or mob entity
---@return number multiplier (1.0 for players, mob-defined knockback_mult, or 1.0 default)
function knockback.get_multiplier(obj)
	if not obj then return 1.0 end
	local base_mult = 1.0
	local target_obj = nil
	if type(obj) == "table" then
		if obj.knockback_mult ~= nil then
			base_mult = obj.knockback_mult
		end
		if obj.object and type(obj.object) == "userdata" and obj.object.is_valid and obj.object:is_valid() then
			target_obj = obj.object
		else
			return base_mult
		end
	elseif type(obj) == "userdata" then
		target_obj = obj
		if not (obj.is_player and obj:is_player()) then
			local ent = obj.get_luaentity and obj:get_luaentity()
			if ent then
				if ent.knockback_mult ~= nil then
					base_mult = ent.knockback_mult
				elseif ent._def and ent._def.knockback_mult ~= nil then
					base_mult = ent._def.knockback_mult
				end
			end
		end
	end

	if target_obj and target_obj:is_valid() then
		local res = x_mob_core.get_knockback_resilience(target_obj)
		if res and res > 0 then
			base_mult = base_mult * math.max(0.0, 1.0 - res)
		end
	end

	return base_mult
end

return knockback
