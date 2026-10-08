--[[
	x_mob_core - Environmental Damage & Hazard Subsystem
	Evaluates throttled node hazard damage (lava, fire, spikes), drowning,
	beaching suffocation for aquatic mobs, and solid block asphyxiation.
]]

---@class EnvironmentSubsystem
local environment = {}

local modpath = core.get_modpath("x_mob_core") or "."
local utils = dofile(modpath .. "/core/utils.lua")

local scratch_probe = {x = 0, y = 0, z = 0}

--- Throttled step processor evaluating environmental hazards
---@param self table Mob entity instance
---@param dtime number Step delta time
---@param def table Entity definition table
---@param combat_handler table Combat handler subsystem
---@return boolean handled True if mob died from environmental damage
function environment.step(self, dtime, def, combat_handler)
	if self.is_dead or self.state == "dying" then return false end

	-- Throttled accumulation (evaluate twice per second: interval = 0.5s)
	self._env_timer = (self._env_timer or 0) + dtime
	if self._env_timer < 0.5 then return false end
	local elapsed = self._env_timer
	self._env_timer = 0

	local pos = self.object and self.object:is_valid() and self.object:get_pos()
	if not pos then return false end

	local immunities = def.immunities or {}
	local cbox = self.collisionbox or def.collisionbox or {-0.4, -0.4, -0.4, 0.4, 0.4, 0.4}
	local foot_y = pos.y + cbox[2] + 0.1
	local torso_y = pos.y + (cbox[2] + cbox[5]) * 0.5
	local head_y = pos.y + cbox[5] - 0.1

	local total_dmg = 0
	local hazard_type = nil

	-- 1. Node hazard DPS (lava, fire, cactus, spikes)
	local nodes_to_check = { foot_y, torso_y }
	local max_dps = 0
	local found_lava = false
	local found_fire = false

	for i = 1, #nodes_to_check do
		scratch_probe.x = math.floor(pos.x + 0.5)
		scratch_probe.y = math.floor(nodes_to_check[i] + 0.5)
		scratch_probe.z = math.floor(pos.z + 0.5)
		local node = core.get_node(scratch_probe)
		local ndef = core.registered_nodes[node.name]

		if ndef then
			local dps = ndef.damage_per_second or 0
			if core.get_item_group(node.name, "lava") > 0 then
				found_lava = true
				if dps == 0 then dps = 8 end
			elseif core.get_item_group(node.name, "fire") > 0 or core.get_item_group(node.name, "igniter") > 0 then
				found_fire = true
				if dps == 0 then dps = 3 end
			end

			if dps > max_dps then
				max_dps = dps
			end
		end
	end

	-- Check immunities against node hazard
	if max_dps > 0 then
		local immune = immunities.environment or immunities.damage_per_second
		local is_fire_faction = self.factions and (self.factions.fire or self.factions.fire_elemental)
		local is_nether_faction = self.factions and (self.factions.lava or self.factions.nether)

		if found_lava and (immunities.lava or immunities.fire or
			is_fire_faction or is_nether_faction) then
			immune = true
		elseif found_fire and (immunities.fire or is_fire_faction) then
			immune = true
		end

		if not immune then
			local d = math.max(1, math.floor(max_dps * elapsed + 0.5))
			total_dmg = total_dmg + d
			hazard_type = found_lava and "lava" or (found_fire and "fire" or "hazard")
		end
	end

	-- 2. Aquatic vs Terrestrial Inversion (Beaching vs Drowning)
	local is_aquatic = (def.is_aquatic == true) or (def.shoal ~= nil) or (def.type == "aquatic")
	if is_aquatic then
		-- Aquatic mob (fish): suffocates when beached out of water
		scratch_probe.x = pos.x
		scratch_probe.y = torso_y
		scratch_probe.z = pos.z
		local in_water = utils.is_water_node(scratch_probe)
		if not in_water then
			self._air_timer = (self._air_timer or 0) + elapsed
			local grace = def.air_grace_period or 5.0
			if self._air_timer > grace then
				local suffocation_rate = def.suffocation_dps or 4
				total_dmg = total_dmg + math.max(1, math.floor(suffocation_rate * elapsed + 0.5))
				hazard_type = hazard_type or "suffocation"
			end
		else
			self._air_timer = 0
		end
	else
		-- Terrestrial mob: check for head submersion in water (drowning)
		scratch_probe.x = pos.x
		scratch_probe.y = head_y
		scratch_probe.z = pos.z
		local head_in_water = utils.is_water_node(scratch_probe)
		local can_drown = not (
			immunities.drown or def.can_breathe_water or def.amphibious or
			(self.factions and (self.factions.undead or self.factions.aquatic or self.factions.golem))
		)

		if head_in_water and can_drown then
			local breath_max = def.breath_max or 15.0
			self.breath = (self.breath or breath_max) - elapsed
			if self.breath <= 0 then
				self.breath = 0
				local drown_rate = def.drowning_dps or 2
				total_dmg = total_dmg + math.max(1, math.floor(drown_rate * elapsed + 0.5))
				hazard_type = hazard_type or "drowning"
			end
		else
			local breath_max = def.breath_max or 15.0
			if self.breath and self.breath < breath_max then
				self.breath = math.min(breath_max, self.breath + elapsed * 3)
			end
		end
	end

	-- 3. Suffocation in solid walkable blocks (buried alive in stone/sand/gravel)
	scratch_probe.x = math.floor(pos.x + 0.5)
	scratch_probe.y = math.floor(head_y + 0.5)
	scratch_probe.z = math.floor(pos.z + 0.5)
	local head_node = core.get_node(scratch_probe)
	local head_def = core.registered_nodes[head_node.name]
	if head_def and head_def.walkable and head_def.drawtype == "normal" and
		not immunities.suffocation then
		local suffocation_rate = def.block_suffocation_dps or 2
		total_dmg = total_dmg + math.max(1, math.floor(suffocation_rate * elapsed + 0.5))
		hazard_type = hazard_type or "suffocation"
	end

	-- Apply accumulated environmental damage
	if total_dmg > 0 then
		return combat_handler.apply_environmental_damage(self, total_dmg, hazard_type, def)
	end

	return false
end

return environment
