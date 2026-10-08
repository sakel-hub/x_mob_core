--[[
	x_mob_core - Lifecycle Properties & Schema Subsystem
	Resolves standardized entity properties, speeds, bounding boxes,
	texture phenotypes, and engine armor groups (Single Responsibility Principle).
]]

local properties = {}

local ENGINE_OBJECT_PROPERTIES = {
	"hp_max",
	"physical",
	"collide_with_objects",
	"weight",
	"collisionbox",
	"selectionbox",
	"pointable",
	"visual",
	"visual_size",
	"mesh",
	"textures",
	"colors",
	"spritediv",
	"initial_sprite_basepos",
	"is_visible",
	"makes_footstep_sound",
	"automatic_rotate",
	"stepheight",
	"automatic_face_movement_dir",
	"automatic_face_movement_max_rotation_per_sec",
	"backface_culling",
	"glow",
	"nametag",
	"nametag_color",
	"nametag_bgcolor",
	"infotext",
	"static_save",
	"shaded",
	"show_on_minimap",
	"eye_height",
	"zoom_fov",
	"use_texture_alpha",
	"damage_texture_modifier",
}

---Normalizes texture variation definitions into a list of texture tables.
---@param raw string|string[]|(string[])[]|nil
---@return table[]|nil variations List of texture tables e.g. { {"tex1.png"}, {"tex2.png"} }
function properties.normalize_texture_variations(raw)
	if not raw then return nil end
	if type(raw) == "string" then
		return { { raw } }
	end
	if type(raw) == "table" then
		local count = #raw
		if count == 0 then return nil end
		local variations = {}
		for i = 1, count do
			local entry = raw[i]
			if type(entry) == "table" then
				variations[i] = entry
			elseif type(entry) == "string" then
				variations[i] = { entry }
			else
				return nil
			end
		end
		return variations
	end
	return nil
end

---Changes or sets the mob's active texture variation by index.
---@param self table|ObjectRef Mob entity instance or ObjectRef
---@param id integer Texture variation index
---@param variations? table[] Optional explicit variations list
---@return string[]|nil applied The applied textures array
function properties.set_texture(self, id, variations)
	local obj = (type(self) == "table" and self.object) or self
	if not obj or not obj:is_valid() then return nil end
	local ent = type(self) == "table" and self or obj:get_luaentity()
	local vars = variations or (ent and ent.texture_variations)
	if not vars or not vars[id] then return nil end
	local applied = vars[id]
	if ent then
		ent.texture_no = id
		ent._chosen_textures = applied
		ent.base_texture = applied
	end
	obj:set_properties({ textures = applied })
	return applied
end

---Updates armor groups on a mob while guaranteeing engine immortal protection.
---@param self table|ObjectRef Mob entity instance or ObjectRef
---@param groups table<string, number> Armor groups (e.g. { fleshy = 80 })
function properties.set_armor_groups(self, groups)
	local obj = (type(self) == "table" and self.object) or self
	if not obj or not obj:is_valid() then return end
	local resolved = {}
	if groups then
		for group, rating in pairs(groups) do
			resolved[group] = rating
		end
	end
	if not resolved.fleshy then
		resolved.fleshy = 100
	end
	if resolved.immortal == nil then
		resolved.immortal = 1
	end
	obj:set_armor_groups(resolved)
end

---Resolves armor groups ensuring standard fleshy and engine immortal protection.
---@param def table Entity definition table
---@return table resolved_armor_groups
function properties.resolve_armor_groups(def)
	local resolved = {}
	local source = def.armor_groups or (def.initial_properties and def.initial_properties.armor_groups)
	if source then
		for group, rating in pairs(source) do
			resolved[group] = rating
		end
	end
	if not resolved.fleshy then
		resolved.fleshy = 100
	end
	if resolved.immortal == nil then
		resolved.immortal = 1
	end
	return resolved
end

---Resolves standardized physics, dimensions, speeds, and defaults.
---@param def table Entity definition table
function properties.resolve_mob_properties(def)
	def.initial_properties = def.initial_properties or {}
	local props = def.initial_properties

	-- Resolve texture variations configuration
	local raw_textures = def.textures or props.textures
	local variations = properties.normalize_texture_variations(raw_textures)
	def._texture_variations = variations
	if variations and #variations > 0 then
		props.textures = variations[1]
	elseif raw_textures then
		props.textures = raw_textures
	end

	-- Derive combat thresholds and range from hp_max if omitted
	local hp_max = (props and props.hp_max) or def.hp_max or 20
	def._hp_max = hp_max
	-- True engine HP capacity matching mob definition (min 1 per Luanti engine requirements)
	props.hp_max = math.max(1, math.floor(hp_max))

	if props.physical == nil then props.physical = true end
	if props.collide_with_objects == nil then
		if (def.shoal and def.shoal.enabled ~= false) or (def.swarm and def.swarm.enabled ~= false) then
			props.collide_with_objects = false
		else
			props.collide_with_objects = true
		end
	end
	if props.static_save == nil then props.static_save = true end
	if props.stepheight == nil then props.stepheight = 1.1 end
	if props.use_texture_alpha == nil and def.use_texture_alpha ~= nil then
		props.use_texture_alpha = def.use_texture_alpha
	end
	if props.use_texture_alpha ~= nil then
		if type(props.use_texture_alpha) == "string" then
			props.use_texture_alpha = (props.use_texture_alpha ~= "opaque" and props.use_texture_alpha ~= "false")
		else
			props.use_texture_alpha = not not props.use_texture_alpha
		end
	end
	if props.visual == nil then
		props.visual = (props.mesh or def.mesh) and "mesh" or "cube"
	end

	-- Floating & aquatic locomotion configuration
	if def.is_floating == nil then
		def.is_floating = (def.fly == true) or (def.type == "flying") or false
	end
	def.fly = nil
	if def.is_aquatic == nil then
		def.is_aquatic = (def.aquatic == true) or (def.shoal ~= nil) or
			(def.type == "aquatic") or (def.mob_type == "aquatic") or false
	end
	def.aquatic = nil
	if props.makes_footstep_sound == nil then
		props.makes_footstep_sound = not def.is_floating
	end

	-- Resolve collisionbox and selectionbox
	local cbox = props.collisionbox or def.collisionbox or {-0.4, 0.0, -0.4, 0.4, 1.8, 0.4}
	props.collisionbox = cbox
	if not props.selectionbox and not def.selectionbox then
		props.selectionbox = {
			cbox[1] - 0.05, cbox[2], cbox[3] - 0.05,
			cbox[4] + 0.05, cbox[5] + 0.05, cbox[6] + 0.05
		}
	end

	-- Migrate and strip all standard engine ObjectProperties from top-level def into initial_properties
	for i = 1, #ENGINE_OBJECT_PROPERTIES do
		local prop = ENGINE_OBJECT_PROPERTIES[i]
		if def[prop] ~= nil then
			if props[prop] == nil then
				props[prop] = def[prop]
			end
			def[prop] = nil
		end
	end

	-- Derive dimensions from collisionbox if omitted
	local height = cbox[5] - cbox[2]
	def.mob_height = def.mob_height or height
	def.eye_offset = def.eye_offset or (cbox[5] * 0.85)
	def.half_width = def.half_width or math.max(math.abs(cbox[1]), math.abs(cbox[4]))

	-- Derive locomotion & speeds from walk_speed if omitted
	local walk_sp = def.walk_speed or 2.5
	def.walk_speed = walk_sp
	def.pursuit_speed = def.pursuit_speed or (walk_sp * 1.4)
	def.wander_speed = def.wander_speed or (walk_sp * 0.6)
	def.flee_speed = def.flee_speed or (walk_sp * 1.6)

	if def.can_wander == nil then def.can_wander = true end
	def.wander_radius = def.wander_radius or 10.0
	if def.can_swim == nil then def.can_swim = true end
	if def.can_climb == nil then def.can_climb = false end
	if def.can_open_doors == nil then def.can_open_doors = false end
	if def.can_crawl == nil then def.can_crawl = false end
	def.hover_offset = def.hover_offset or 0.4
	def.combat_hover_offset = def.combat_hover_offset or math.min(def.hover_offset or 0.35, 0.4)
	if def.flight_elevation == nil and def.is_floating then
		def.flight_elevation = def.hover_offset
	end

	def.attack_range = def.attack_range or 2.0
	def.combat_standoff = def.combat_standoff or math.max(1.3, def.attack_range * 0.7)
	def.aggro_radius = def.aggro_radius or 16.0

	-- Environmental hazard immunities table (Single Source of Truth)
	local raw_im = def.immunities or def.immune_to
	local im_table = (type(raw_im) == "table") and raw_im or {}
	def.immunities = {
		environment = (im_table.environment == true),
		damage_per_second = (im_table.damage_per_second == true),
		lava = (im_table.lava == true) or (def.immune_to_lava == true),
		fire = (im_table.fire == true) or (def.immune_to_fire == true),
		drown = (im_table.drown == true) or (im_table.water == true),
		suffocation = (im_table.suffocation == true) or (im_table.block_suffocation == true),
	}
	def.immune_to = nil
	def.immune_to_lava = nil
	def.immune_to_fire = nil

	-- Health regeneration & tactical fleeing: canonical def.health_regen configuration
	local raw_hr = def.health_regen
	local hr_table = (type(raw_hr) == "table") and raw_hr or {}

	local enabled = true
	if raw_hr == false or raw_hr == 0 or hr_table.enabled == false then
		enabled = false
	end

	local rate
	if not enabled then
		rate = 0
	elseif type(raw_hr) == "number" then
		rate = raw_hr
	else
		rate = hr_table.rate or 0.5
	end

	local passive = (hr_table.passive == true)
	local overlay = (hr_table.overlay ~= false)
	local overlay_color = hr_table.overlay_color or "^[colorize:#FFFFFF60"

	local flee_threshold
	if hr_table.can_flee == false then
		flee_threshold = 0
	elseif hr_table.flee_threshold ~= nil then
		flee_threshold = hr_table.flee_threshold
	elseif hr_table.flee_ratio ~= nil then
		flee_threshold = math.floor(hp_max * hr_table.flee_ratio)
	else
		flee_threshold = math.floor(hp_max * 0.25)
	end

	local return_threshold
	if hr_table.return_threshold ~= nil then
		return_threshold = hr_table.return_threshold
	elseif hr_table.return_ratio ~= nil then
		return_threshold = math.floor(hp_max * hr_table.return_ratio)
	else
		return_threshold = math.floor(hp_max * 0.60)
	end

	local unlimited_flee = (hr_table.unlimited_flee == true)
	local burst_duration = tonumber(hr_table.burst_duration) or 3.5
	local channel_duration = tonumber(hr_table.channel_duration) or 3.0
	local safe_distance = tonumber(hr_table.safe_distance) or 10.0
	local heal_amount = tonumber(hr_table.heal_amount) or math.max(1, return_threshold - flee_threshold)
	local flee_speed = tonumber(hr_table.flee_speed) or tonumber(def.flee_speed)
	local max_flee_dist = tonumber(hr_table.max_flee_distance) or tonumber(def.max_flee_distance) or 15.0

	-- Canonical single source of truth table
	def.health_regen = {
		enabled = enabled,
		rate = rate,
		passive = passive,
		overlay = overlay,
		overlay_color = overlay_color,
		flee_threshold = flee_threshold,
		return_threshold = return_threshold,
		unlimited_flee = unlimited_flee,
		burst_duration = burst_duration,
		channel_duration = channel_duration,
		safe_distance = safe_distance,
		heal_amount = heal_amount,
		flee_speed = flee_speed,
		max_flee_distance = max_flee_dist,
	}
end

return properties
