--[[
	x_mob_core - Combat & Damage Subsystem
	Calculates damage from tool capabilities and mob armor groups, and applies tool wear
]]

---@class DamageSubsystem
local damage = {}

--- Calculates damage from tool capabilities and mob armor groups, and adds tool wear
---@param self table Mob entity instance
---@param puncher? ObjectRef Punching entity
---@param time_from_last_punch? number Time since last punch
---@param tool_capabilities? table Wielded tool capabilities
---@param _dir? Vector Punch direction
---@param damage_override? number Direct damage override
---@return number dmg Calculated damage integer
function damage.calculate_punch_damage(self, puncher, time_from_last_punch, tool_capabilities, _dir, damage_override)
	local dmg = 0
	local armor = (self.object and self.object:is_valid() and self.object:get_armor_groups()) or {}

	local tflp = time_from_last_punch or 1.0
	local fpi = (tool_capabilities and tool_capabilities.full_punch_interval) or 1.4
	local mult = math.min(1.0, math.max(0.0, tflp / fpi))

	if tool_capabilities and tool_capabilities.damage_groups then
		for group, val in pairs(tool_capabilities.damage_groups) do
			local armor_val = armor[group] or 0
			dmg = dmg + val * mult * (armor_val / 100.0)
		end
	end

	-- Material-specific weak points (e.g. pickaxes with groupcaps.cracky against cracky armor)
	-- In Luanti, tools define mining capability in groupcaps and typically only specify fleshy in damage_groups.
	-- When striking an entity with a corresponding material armor vulnerability (e.g. crystal/stone golems),
	-- calculate heightened damage using the tool's mining tier against that armor group.
	if tool_capabilities and tool_capabilities.groupcaps and armor then
		for group, gcap in pairs(tool_capabilities.groupcaps) do
			local armor_val = armor[group] or 0
			if armor_val > 0 and (not tool_capabilities.damage_groups or not tool_capabilities.damage_groups[group]) then
				local maxlevel = (type(gcap) == "table" and gcap.maxlevel) or 1
				local base_val = (tool_capabilities.damage_groups and tool_capabilities.damage_groups.fleshy) or 4
				-- Mining tool force: base tool impact + mining tier bonus
				local effective_val = base_val + (maxlevel * 2.5)
				local group_dmg = effective_val * mult * (armor_val / 100.0)
				if group_dmg > dmg then
					dmg = group_dmg
				end
			end
		end
	end

	if damage_override and damage_override > dmg then
		dmg = damage_override
	end

	dmg = math.floor(dmg + 0.5)
	if dmg <= 0 then
		dmg = 1
	end

	-- Apply wear to attacker's weapon like vanilla Luanti
	if puncher and puncher:is_valid() and puncher:is_player() then
		local tool = puncher:get_wielded_item()
		if tool and not tool:is_empty() and not core.is_creative_enabled(puncher:get_player_name()) then
			local wear = math.floor((fpi / 75) * 9000)
			tool:add_wear(wear)
			puncher:set_wielded_item(tool)
		end
	end

	-- Dampen excessive engine knockback when struck inside water
	if x_mob_core and x_mob_core.dampen_water_knockback then
		x_mob_core.dampen_water_knockback(self)
	end

	return dmg
end

return damage
