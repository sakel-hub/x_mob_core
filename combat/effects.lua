--[[
	x_mob_core - Combat Feedback Effects
	Visual damage feedback and red flash coloring
]]

---@class EffectsSubsystem
local effects = {}

local FLASH_MODIFIER = "^[colorize:#FF000060"
local cached_global_mode = core.settings:get("x_mob_damage_particles") or "mob_default"
local cached_mult = tonumber(core.settings:get("x_mob_damage_particle_multiplier")) or 1.0
if cached_mult <= 0 then cached_mult = 0 end
if cached_mult > 3.0 then cached_mult = 3.0 end

--- Strips transient damage flash colorize modifiers from a texture modifier string
---@param mod? string Original texture modifier string
---@return string clean_mod Texture modifier without damage colorize
function effects.strip_damage_mod(mod)
	if not mod or mod == "" then return "" end
	local res = mod:gsub("%^%[[cC][oO][lL][oO][rR][iI][zZ][eE]:#[fF][fF]0000[^%^]*", "")
	return (res:gsub("%^%[[cC][oO][lL][oO][rR][iI][zZ][eE]:[rR][eE][dD][^%^]*", ""))
end

--- Clears any active damage flash on an entity, restoring its clean base texture modifier
---@param obj ObjectRef Entity object
function effects.clear_damage(obj)
	if not obj or not obj:is_valid() then return end
	local ent = obj:get_luaentity()
	local base_mod = ent and ent._damage_flash_base
	if ent then
		ent._damage_flash_timer = nil
		ent._damage_flash_base = nil
	end
	local cur_mod = obj:get_texture_mod() or ""
	local clean_mod = base_mod or effects.strip_damage_mod(cur_mod)
	if cur_mod ~= clean_mod then
		obj:set_texture_mod(clean_mod)
	end
end

--- Flashes the entity red briefly upon taking damage for visual feedback.
--- Prevents duplicate stacking and race condition persistence under rapid hits.
---@param obj ObjectRef Entity object
function effects.indicate_damage(obj)
	if not obj or not obj:is_valid() then return end
	local ent = obj:get_luaentity()

	if ent then
		-- Only capture the base modifier if not already actively flashing
		if not ent._damage_flash_timer or ent._damage_flash_timer <= 0 then
			ent._damage_flash_base = effects.strip_damage_mod(obj:get_texture_mod() or "")
		end
		ent._damage_flash_timer = 0.2
		obj:set_texture_mod((ent._damage_flash_base or "") .. FLASH_MODIFIER)

		-- Backup safety timer in case on_step is skipped or entity is deactivated
		core.after(0.25, function()
			if obj and obj:is_valid() then
				local e = obj:get_luaentity()
				if e and e._damage_flash_timer and e._damage_flash_timer <= 0.05 then
					effects.clear_damage(obj)
				end
			end
		end)
	else
		-- Non-LuaEntity fallback
		local clean_mod = effects.strip_damage_mod(obj:get_texture_mod() or "")
		obj:set_texture_mod(clean_mod .. FLASH_MODIFIER)
		core.after(0.2, function()
			if obj and obj:is_valid() then
				obj:set_texture_mod(clean_mod)
			end
		end)
	end
end

local PRESET_DEFAULTS = {
	blood = {
		color = "#B80A0A",
		colors = {"#D41010", "#A00606", "#6E0000"},
		count = 16,
		size_min = 1.4,
		size_max = 2.8,
		exptime_min = 0.55,
		exptime_max = 1.10,
		acc_y = -8.5,
		vel_fwd = 2.8,
		vel_y_min = 1.2,
		vel_y_max = 3.6,
		spread = 1.5,
		drag = {x = 0.8, y = 0.15, z = 0.8},
		jitter = {min = {x = -0.3, y = -0.15, z = -0.3}, max = {x = 0.3, y = 0.15, z = 0.3}},
		bounce = 0.2,
		collision = true,
		collision_removal = false,
		blend = "alpha",
	},
	smoke = {
		color = "#555555",
		colors = {"#777777", "#555555", "#333333"},
		count = 12,
		size_min = 1.6,
		size_max = 3.0,
		exptime_min = 0.45,
		exptime_max = 0.95,
		acc_y = 0.8,
		vel_fwd = 1.0,
		vel_y_min = 0.6,
		vel_y_max = 2.2,
		spread = 1.2,
		drag = {x = 1.0, y = 0.25, z = 1.0},
		jitter = {min = {x = -0.5, y = -0.1, z = -0.5}, max = {x = 0.5, y = 0.3, z = 0.5}},
		bounce = 0.0,
		collision = true,
		collision_removal = false,
		blend = "alpha",
	},
	ichor = {
		color = "#3DB810",
		colors = {"#5CE018", "#33AA11", "#1B6E06"},
		count = 16,
		size_min = 1.4,
		size_max = 2.8,
		exptime_min = 0.55,
		exptime_max = 1.10,
		acc_y = -8.0,
		vel_fwd = 2.6,
		vel_y_min = 1.0,
		vel_y_max = 3.4,
		spread = 1.5,
		drag = {x = 0.8, y = 0.15, z = 0.8},
		jitter = {min = {x = -0.35, y = -0.15, z = -0.35}, max = {x = 0.35, y = 0.15, z = 0.35}},
		bounce = 0.25,
		collision = true,
		collision_removal = false,
		blend = "alpha",
	},
	spectral = {
		color = "#7B1FA2",
		colors = {"#9C27B0", "#7B1FA2", "#4A148C"},
		count = 14,
		size_min = 1.4,
		size_max = 2.8,
		exptime_min = 0.50,
		exptime_max = 1.00,
		acc_y = 0.3,
		vel_fwd = 1.8,
		vel_y_min = 0.8,
		vel_y_max = 2.8,
		spread = 1.4,
		drag = {x = 0.8, y = 0.2, z = 0.8},
		jitter = {min = {x = -0.6, y = -0.2, z = -0.6}, max = {x = 0.6, y = 0.4, z = 0.6}},
		bounce = 0.0,
		collision = true,
		collision_removal = false,
		blend = "add",
		glow = 13,
	},
	sparks = {
		color = "#FFAA00",
		colors = {"#FFFF55", "#FFAA00", "#FF5500"},
		count = 16,
		size_min = 0.9,
		size_max = 2.0,
		exptime_min = 0.25,
		exptime_max = 0.60,
		acc_y = -11.0,
		vel_fwd = -2.8,
		vel_y_min = 1.6,
		vel_y_max = 4.2,
		spread = 1.8,
		drag = {x = 0.6, y = 0.15, z = 0.6},
		jitter = {min = {x = -0.8, y = -0.4, z = -0.8}, max = {x = 0.8, y = 0.4, z = 0.8}},
		bounce = 0.55,
		collision = true,
		collision_removal = true,
		blend = "add",
		glow = 14,
	},
}

--- Spawns contextual, directional damage particles when an entity is damaged.
--- Configurable globally via `x_mob_damage_particles` and `x_mob_damage_particle_multiplier`,
--- or per-mob via `def.damage_effect`. Can be disabled by setting `damage_effect = false`,
--- `damage_effect = "none"`, or `{ enabled = false }` / `{ type = "none" }`.
---@param obj ObjectRef Entity object receiving damage
---@param puncher? ObjectRef Attacking entity or player
---@param dir? Vector Strike/knockback direction vector
---@param damage? number Damage points dealt
---@param def? table Mob definition table
function effects.spawn_damage_particles(obj, puncher, dir, damage, def)
	if not obj or not obj:is_valid() then return end
	local pos = obj:get_pos()
	if not pos then return end

	-- Check mob definition first for explicit disabling
	local ent = obj:get_luaentity()
	local raw_conf = nil
	if def and def.damage_effect ~= nil then
		raw_conf = def.damage_effect
	elseif ent and ent.damage_effect ~= nil then
		raw_conf = ent.damage_effect
	end

	-- Allow disabling core damage effect completely per mob
	-- Supports: damage_effect = false, "none", {enabled = false}, or {type = "none"}
	if raw_conf == false or raw_conf == "none" then
		return
	end
	if type(raw_conf) == "table" and (raw_conf.enabled == false or raw_conf.type == "none") then
		return
	end

	-- Global configuration lookup
	local global_mode = cached_global_mode
	if global_mode == "none" then return end

	local mult = cached_mult
	if mult <= 0 then return end

	-- Mob definition configuration
	local mob_conf = (type(raw_conf) == "table") and raw_conf or ((type(raw_conf) == "string") and {type = raw_conf} or {})
	local effect_type = (global_mode ~= "mob_default") and global_mode or (mob_conf.type or "blood")
	if effect_type == "none" then return end

	-- Look up preset in core defaults
	local preset = PRESET_DEFAULTS[effect_type]
	if not preset then
		-- If mob specified a custom effect type not recognized by core, do not force blood;
		-- let the mob's own VFX or event handlers handle it.
		if mob_conf.type and mob_conf.type ~= "blood" then
			return
		end
		preset = PRESET_DEFAULTS.blood
	end

	-- Calculate origin elevation
	local cbox = def and def.initial_properties and def.initial_properties.collisionbox
	local torso_y = (cbox and cbox[5] and cbox[5] > 0) and (cbox[5] * 0.55) or 0.8
	local spawn_pos = {x = pos.x, y = pos.y + torso_y, z = pos.z}

	-- Calculate hit impact vector
	local hit_dir = {x = 0, y = 0, z = 0}
	if dir and (dir.x ~= 0 or dir.z ~= 0) then
		local dlen = math.sqrt(dir.x * dir.x + dir.z * dir.z)
		if dlen > 0.01 then
			hit_dir = {x = dir.x / dlen, y = (dir.y or 0) / dlen, z = dir.z / dlen}
		end
	elseif puncher and puncher:is_valid() then
		local ppos = puncher:get_pos()
		if ppos then
			local dx = pos.x - ppos.x
			local dz = pos.z - ppos.z
			local plen = math.sqrt(dx * dx + dz * dz)
			if plen > 0.01 then
				hit_dir = {x = dx / plen, y = 0, z = dz / plen}
			end
		end
	end

	-- Scale count by damage amount and multiplier
	local dmg = damage or 1
	local base_count = mob_conf.count or preset.count or 16
	local dmg_scale = (dmg <= 3) and 0.75 or ((dmg <= 8) and 1.0 or 1.35)
	local final_amount = math.max(1, math.min(36, math.floor(base_count * dmg_scale * mult)))

	-- Color and texture resolution
	local color = (global_mode == "mob_default" and mob_conf.color) or preset.color
	local is_spark = (effect_type == "sparks")
	local fallback_base = is_spark and "x_mob_core_sparkle.png" or "x_mob_core_particle.png"
	local tex = mob_conf.texture or string.format("%s^[multiply:#%s", fallback_base, color:gsub("#", ""))
	local blend = preset.blend or "alpha"
	local scale_mult = mob_conf.scale or 1.0
	local size_min = preset.size_min * scale_mult
	local size_max = preset.size_max * scale_mult

	-- Directional spray boundaries
	local fwd = preset.vel_fwd or 2.8
	local spread = preset.spread or 1.5
	local minvel = {
		x = hit_dir.x * fwd - spread,
		y = preset.vel_y_min or 1.2,
		z = hit_dir.z * fwd - spread,
	}
	local maxvel = {
		x = hit_dir.x * fwd + spread,
		y = preset.vel_y_max or 3.6,
		z = hit_dir.z * fwd + spread,
	}
	local acc = {x = 0, y = preset.acc_y or -8.5, z = 0}

	-- Multi-shade texpool generation for visual depth
	local s_start = scale_mult * 1.25
	local s_end = scale_mult * 0.65
	local tween_scale = { { x = s_start, y = s_start }, { x = s_end, y = s_end } }
	local tween_alpha = { 1.0, 0.0 }

	local texpool = {}
	if mob_conf.texture then
		texpool[1] = {
			name = mob_conf.texture,
			blend = blend,
			scale_tween = tween_scale,
			alpha_tween = tween_alpha,
		}
	elseif mob_conf.colors and #mob_conf.colors > 0 then
		for i = 1, #mob_conf.colors do
			texpool[i] = {
				name = string.format("%s^[multiply:#%s", fallback_base, mob_conf.colors[i]:gsub("#", "")),
				blend = blend,
				scale_tween = tween_scale,
				alpha_tween = tween_alpha,
			}
		end
	elseif mob_conf.color then
		texpool[1] = {
			name = string.format("%s^[multiply:#%s", fallback_base, mob_conf.color:gsub("#", "")),
			blend = blend,
			scale_tween = tween_scale,
			alpha_tween = tween_alpha,
		}
	elseif preset.colors and #preset.colors > 0 then
		for i = 1, #preset.colors do
			texpool[i] = {
				name = string.format("%s^[multiply:#%s", fallback_base, preset.colors[i]:gsub("#", "")),
				blend = blend,
				scale_tween = tween_scale,
				alpha_tween = tween_alpha,
			}
		end
	else
		texpool[1] = {
			name = tex,
			blend = blend,
			scale_tween = tween_scale,
			alpha_tween = tween_alpha,
		}
	end

	core.add_particlespawner({
		amount = final_amount,
		time = 0.08,
		pos = {
			min = {x = spawn_pos.x - 0.25, y = spawn_pos.y - 0.2, z = spawn_pos.z - 0.25},
			max = {x = spawn_pos.x + 0.25, y = spawn_pos.y + 0.2, z = spawn_pos.z + 0.25},
		},
		vel = {
			min = minvel,
			max = maxvel,
		},
		acc = {
			min = acc,
			max = acc,
		},
		drag = preset.drag,
		jitter = preset.jitter,
		bounce = preset.bounce,
		size = {min = size_min, max = size_max},
		exptime = {min = preset.exptime_min, max = preset.exptime_max},
		collisiondetection = preset.collision or false,
		collision_removal = preset.collision_removal or false,
		glow = preset.glow or 0,
		texpool = texpool,

		-- Backward-compatible fallback fields
		minpos = {x = spawn_pos.x - 0.25, y = spawn_pos.y - 0.2, z = spawn_pos.z - 0.25},
		maxpos = {x = spawn_pos.x + 0.25, y = spawn_pos.y + 0.2, z = spawn_pos.z + 0.25},
		minvel = minvel,
		maxvel = maxvel,
		minacc = acc,
		maxacc = acc,
		minexptime = preset.exptime_min,
		maxexptime = preset.exptime_max,
		minsize = size_min,
		maxsize = size_max,
		texture = tex,
	})
end

return effects
