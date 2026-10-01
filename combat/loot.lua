--[[
	x_mob_core - Loot Drop Subsystem
	Dispatches physical item drops with parabolic pop arcs, radial dispersion,
	and sparkling visual feedback upon mob defeat.
]]

---@class DropEntryDef
---@field name string Technical item name (e.g. "everness:quartz_crystal")
---@field min? integer Minimum count to drop (default: 1)
---@field max? integer Maximum count to drop (default: 1)
---@field chance? number Probability to drop between 0.0 and 1.0 (default: 1.0)


---@class DropOptions
---@field up_vel_min? number Minimum upward launch velocity (default: 4.6)
---@field up_vel_max? number Maximum upward launch velocity (default: 5.8)
---@field spread_min? number Minimum horizontal spread velocity (default: 1.0)
---@field spread_max? number Maximum horizontal spread velocity (default: 1.6)
---@field particles? boolean Enable sparkle/burst particles (default: true)
---@field trails? boolean Enable sparkling trail attached to flying items (default: true)
---@field particle_color? string Hex color for sparkle particles
---@field sound? string Sound identifier to play on drop
---@field killer? ObjectRef Killer object/player if applicable

---@class LootSubsystem
local loot = {}

local utils = dofile(core.get_modpath("x_mob_core") .. "/core/utils.lua")

local LOOT_SHINE_COLORS = { "#FFFFFF", "#FFF275", "#FFD700", "#C77DFF", "#70D6FF" }

--- Strips leading '#' from hex color strings
---@param color? string Hex color string
---@return string hex 6-character hex code
local function clean_hex(color)
	if not color or color == "" then return "FFFFFF" end
	return color:gsub("#", "")
end

--- Validates whether an item technical name is registered in the engine
---@param item_name string
---@return boolean is_registered
local function is_item_valid(item_name)
	if not item_name or item_name == "" or item_name == "air" or item_name == "ignore" then
		return false
	end
	return core.registered_items[item_name] ~= nil
		or core.registered_nodes[item_name] ~= nil
		or core.registered_craftitems[item_name] ~= nil
		or core.registered_tools[item_name] ~= nil
end

--- Spawns sparkling burst particles at the loot release location
---@param pos Vector Origin point
---@param count integer Number of particles
---@param custom_color? string Optional dominant hex color
local function spawn_loot_particles(pos, count, custom_color)
	local texpool = {}
	local colors = custom_color and { custom_color, "#FFFFFF", "#FFF275", "#FFD700" } or LOOT_SHINE_COLORS
	for i = 1, #colors do
		local hex = clean_hex(colors[i])
		local base_tex = (i % 2 == 1) and "x_mob_core_sparkle.png" or "x_mob_core_star.png"
		texpool[#texpool + 1] = {
			name = string.format("%s^[multiply:#%s", base_tex, hex),
			blend = "add",
			scale_tween = { { x = 1.8, y = 1.8 }, { x = 0.4, y = 0.4 } },
			alpha_tween = { 1.0, 0.0 },
		}
	end

	local primary_hex = clean_hex(colors[1])
	core.add_particlespawner({
		amount = math.min(32, math.max(16, count * 5)),
		time = 0.30,
		pos = {
			min = { x = pos.x - 0.25, y = pos.y - 0.05, z = pos.z - 0.25 },
			max = { x = pos.x + 0.25, y = pos.y + 0.35, z = pos.z + 0.25 },
		},
		vel = {
			min = { x = -1.8, y = 2.4, z = -1.8 },
			max = { x = 1.8, y = 4.2, z = 1.8 },
		},
		acc = {
			min = { x = 0, y = -7.0, z = 0 },
			max = { x = 0, y = -10.0, z = 0 },
		},
		jitter = {
			min = { x = -0.4, y = -0.2, z = -0.4 },
			max = { x = 0.4, y = 0.2, z = 0.4 },
		},
		drag = { x = 0.8, y = 0.4, z = 0.8 },
		bounce = 0.30,
		size = { min = 1.8, max = 3.2 },
		exptime = { min = 0.40, max = 0.75 },
		collisiondetection = true,
		collision_removal = false,
		glow = 14,
		texpool = texpool,

		-- Backward-compatible fallback fields
		minpos = { x = pos.x - 0.25, y = pos.y - 0.05, z = pos.z - 0.25 },
		maxpos = { x = pos.x + 0.25, y = pos.y + 0.35, z = pos.z + 0.25 },
		minvel = { x = -1.8, y = 2.4, z = -1.8 },
		maxvel = { x = 1.8, y = 4.2, z = 1.8 },
		minacc = { x = 0, y = -7.0, z = 0 },
		maxacc = { x = 0, y = -10.0, z = 0 },
		minexptime = 0.40,
		maxexptime = 0.75,
		minsize = 1.8,
		maxsize = 3.2,
		texture = string.format("x_mob_core_sparkle.png^[multiply:#%s", primary_hex),
	})
end

--- Attaches a sparkling particle trail to a flying item entity,
--- creating a shimmering wake that follows its parabolic launch arc.
---@param item_obj ObjectRef Spawned item entity
---@param custom_color? string Optional dominant hex color
---@param custom_texture? string Optional custom base particle texture
local function attach_sparkle_trail(item_obj, custom_color, custom_texture)
	if not item_obj or not item_obj:is_valid() then return end

	local colors = custom_color and { custom_color, "#FFFFFF", "#FFF275", "#FFD700" } or LOOT_SHINE_COLORS
	local texpool = {}
	for i = 1, #colors do
		local hex = clean_hex(colors[i])
		local base_tex = custom_texture or ((i % 2 == 1) and "x_mob_core_sparkle.png" or "x_mob_core_star.png")
		texpool[#texpool + 1] = {
			name = string.format("%s^[multiply:#%s", base_tex, hex),
			blend = "add",
			scale_tween = { { x = 1.6, y = 1.6 }, { x = 0.3, y = 0.3 } },
			alpha_tween = { 1.0, 0.0 },
		}
	end

	local primary_hex = clean_hex(colors[1])
	local primary_tex = custom_texture or "x_mob_core_sparkle.png"

	core.add_particlespawner({
		amount = 32,
		time = 1.15,
		pos = {
			min = { x = -0.05, y = -0.05, z = -0.05 },
			max = { x = 0.05, y = 0.05, z = 0.05 },
		},
		vel = {
			min = { x = -0.20, y = -0.15, z = -0.20 },
			max = { x = 0.20, y = 0.15, z = 0.20 },
		},
		acc = {
			min = { x = -0.10, y = -1.2, z = -0.10 },
			max = { x = 0.10, y = -2.2, z = 0.10 },
		},
		jitter = {
			min = { x = -0.2, y = -0.1, z = -0.2 },
			max = { x = 0.2, y = 0.1, z = 0.2 },
		},
		drag = { x = 1.0, y = 0.5, z = 1.0 },
		size = { min = 1.6, max = 2.8 },
		exptime = { min = 0.30, max = 0.55 },
		collisiondetection = false,
		attached = item_obj,
		glow = 14,
		texpool = texpool,

		-- Backward-compatible fallback fields
		minpos = { x = -0.05, y = -0.05, z = -0.05 },
		maxpos = { x = 0.05, y = 0.05, z = 0.05 },
		minvel = { x = -0.20, y = -0.15, z = -0.20 },
		maxvel = { x = 0.20, y = 0.15, z = 0.20 },
		minacc = { x = -0.10, y = -1.2, z = -0.10 },
		maxacc = { x = 0.10, y = -2.2, z = 0.10 },
		minexptime = 0.30,
		maxexptime = 0.55,
		minsize = 1.6,
		maxsize = 2.8,
		texture = string.format("%s^[multiply:#%s", primary_tex, primary_hex),
	})
end

--- Spawns a single item with a physical parabolic launch arc
---@param origin Vector World coordinate of spawn origin
---@param itemstack ItemStack|string Item or ItemStack to drop
---@param angle? number Launch azimuth in radians
---@param options? DropOptions Physics and effect overrides
---@return ObjectRef|nil item_obj Spawned item entity or nil
function loot.drop_item(origin, itemstack, angle, options)
	if not origin then return nil end
	local stack = ItemStack(itemstack)
	if stack:is_empty() then return nil end

	local item_name = stack:get_name()
	if not is_item_valid(item_name) then return nil end

	options = options or {}
	local up_min = options.up_vel_min or 4.6
	local up_max = options.up_vel_max or 5.8
	local sp_min = options.spread_min or 1.0
	local sp_max = options.spread_max or 1.6

	local theta = angle or (math.random() * math.pi * 2.0)
	local speed = sp_min + math.random() * (sp_max - sp_min)
	local up_speed = up_min + math.random() * (up_max - up_min)

	local vx = math.cos(theta) * speed
	local vy = up_speed
	local vz = math.sin(theta) * speed

	local item_obj = core.add_item(origin, stack)
	if item_obj and item_obj:is_valid() then
		item_obj:set_velocity({
			x = vx,
			y = vy,
			z = vz,
		})
		item_obj:set_acceleration({ x = 0, y = -9.81, z = 0 })

		if options.particles ~= false and options.trails ~= false then
			attach_sparkle_trail(item_obj, options.particle_color, options.particle_texture)
		end

		-- Settle any residual velocity after full parabolic arc completes
		core.after(1.25, function(obj)
			if obj and obj:is_valid() then
				local v = obj:get_velocity()
				if v and math.abs(v.y) < 0.5 then
					obj:set_velocity({ x = 0, y = v.y, z = 0 })
				end
			end
		end, item_obj)
	end

	return item_obj
end

--- Evaluates a declarative drop table and launches all dropped items in a radial fountain
---@param origin Vector World coordinate of spawn origin
---@param drops (DropEntryDef|string)[] List of drop table entries
---@param options? DropOptions Physics, particle, and sound overrides
---@return ObjectRef[] spawned_objects List of successfully spawned item ObjectRefs
function loot.drop_items(origin, drops, options)
	if not origin or not drops or #drops == 0 then return {} end
	options = options or {}

	-- Resolve total items to launch
	local items_to_spawn = {}
	for i = 1, #drops do
		local entry = drops[i]
		if type(entry) == "string" then
			local stack = ItemStack(entry)
			if not stack:is_empty() and is_item_valid(stack:get_name()) then
				items_to_spawn[#items_to_spawn + 1] = stack
			end
		elseif type(entry) == "table" and entry.name then
			local chance = entry.chance or 1.0
			if chance >= 1.0 or math.random() <= chance then
				local item_name = entry.name
				if is_item_valid(item_name) then
					local min_cnt = entry.min or 1
					local max_cnt = entry.max or min_cnt
					local count = (min_cnt == max_cnt) and min_cnt or math.random(min_cnt, max_cnt)
					if count > 0 then
						items_to_spawn[#items_to_spawn + 1] = ItemStack(item_name .. " " .. count)
					end
				end
			end
		end
	end

	local total = #items_to_spawn
	if total == 0 then return {} end

	-- Visual feedback
	if options.particles ~= false then
		spawn_loot_particles(origin, total, options.particle_color)
	end

	-- Sound feedback (silent by default, played only if explicitly requested)
	if options.sound and options.sound ~= "" then
		core.sound_play(options.sound, {
			pos = origin,
			gain = 0.8,
			max_hear_distance = 18.0,
		}, true)
	end

	-- Launch items radially in a distributed circular fountain
	local spawned = {}
	local base_angle = math.random() * math.pi * 2.0
	for idx = 1, total do
		local stack = items_to_spawn[idx]
		local angle = base_angle + ((2.0 * math.pi / total) * (idx - 1)) + (math.random() - 0.5) * 0.35
		local item_obj = loot.drop_item(origin, stack, angle, options)
		if item_obj then
			spawned[#spawned + 1] = item_obj
		end
	end

	return spawned
end

--- Convenience method to drop items from a dying mob instance
---@param self table Mob entity instance
---@param killer? ObjectRef Killer entity or player
---@param drops (DropEntryDef|string)[] Mob drop definitions
---@param options? DropOptions Runtime drop overrides
---@return ObjectRef[] spawned_objects List of spawned item ObjectRefs
function loot.spawn_mob_drops(self, killer, drops, options)
	local obj = self.object
	if not obj or not obj:is_valid() then return {} end
	local pos = obj:get_pos()
	if not pos then return {} end

	local cbox = self.initial_properties and self.initial_properties.collisionbox
	local torso_y = (cbox and cbox[5] and cbox[5] > 0) and math.min(0.5, math.max(0.2, cbox[5] * 0.35)) or 0.35
	local spawn_origin = {
		x = pos.x,
		y = pos.y + torso_y,
		z = pos.z,
	}

	-- Ensure spawn point is not inside a solid walkable node to prevent engine force-out
	local snode = core.get_node_or_nil(spawn_origin)
	if snode and snode.name ~= "air" and snode.name ~= "ignore" then
		local sdef = core.registered_nodes[snode.name]
		if sdef and sdef.walkable then
			spawn_origin.y = math.floor(spawn_origin.y) + 1.05
		end
	end

	local opts = utils.shallow_copy(options) or {}
	if not opts.particle_color and self.damage_effect and self.damage_effect.color then
		opts.particle_color = self.damage_effect.color
	end
	opts.killer = killer

	return loot.drop_items(spawn_origin, drops, opts)
end

return loot
