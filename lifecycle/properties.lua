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
	-- Set generous engine HP capacity so internal C++ health never reaches zero
	props.hp_max = math.max(hp_max, 1000)

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

	-- Floating locomotion configuration
	if def.is_floating == nil then def.is_floating = false end
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

	def.attack_range = def.attack_range or 2.0
	def.aggro_radius = def.aggro_radius or 16.0
	if def.flee_hp_threshold == nil then
		def.flee_hp_threshold = math.floor(hp_max * 0.25)
	end
	if def.return_hp_threshold == nil then
		def.return_hp_threshold = math.floor(hp_max * 0.60)
	end
end

return properties
