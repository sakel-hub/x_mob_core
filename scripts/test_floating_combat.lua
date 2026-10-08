--[[
	test_floating_combat.lua - Unit tests for floating mob combat behavior
	Verifies combat standoff positioning in front of the player,
	combat hover elevation slightly above the ground, and velocity halting.
]]

local modpath = "."
local registered_entities = {}
local registered_nodes = {
	["default:dirt_with_grass"] = {walkable = true, liquidtype = "none"},
	["air"] = {walkable = false, liquidtype = "none"},
}

local settings_store = {
	x_mob_damage_particles = "mob_default",
	x_mob_damage_particle_multiplier = "1.0",
	x_mob_core_enable_health_bars = "true",
	x_mob_core_health_bar_timeout = "4.0",
	x_mob_core_health_bar_auto_remove = "true",
}

_G.core = {
	registered_nodes = registered_nodes,
	registered_entities = registered_entities,
	hash_node_position = function(pos)
		return (pos.x or 0) .. ":" .. (pos.y or 0) .. ":" .. (pos.z or 0)
	end,
	get_node = function(pos)
		local y = math.floor(pos.y + 0.5)
		if y <= 0 then
			return {name = "default:dirt_with_grass"}
		end
		return {name = "air"}
	end,
	get_node_or_nil = function(pos)
		return _G.core.get_node(pos)
	end,
	get_modpath = function(modname)
		if modname == "x_mob_core" then
			return modpath
		end
		return nil
	end,
	dir_to_yaw = function(dir)
		local atan = math.atan2 or math.atan
		return -atan(dir.x, dir.z)
	end,
	yaw_to_dir = function(yaw)
		return {x = -math.sin(yaw), y = 0, z = math.cos(yaw)}
	end,
	settings = {
		get = function(_self, key)
			return settings_store[key]
		end,
		get_bool = function(_self, key, default)
			if settings_store[key] == nil then return default end
			return settings_store[key] == "true" or settings_store[key] == true
		end,
	},
	get_gametime = function() return 100.0 end,
	get_us_time = function() return 1000000 end,
	register_globalstep = function() end,
	register_on_mods_loaded = function() end,
	get_objects_inside_radius = function() return {} end,
	line_of_sight = function(_p1, _p2)
		return true, nil
	end,
}
_G.minetest = _G.core

local vector = {
	distance = function(a, b)
		local dx = b.x - a.x
		local dy = b.y - a.y
		local dz = b.z - a.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	direction = function(a, b)
		local dx = b.x - a.x
		local dy = b.y - a.y
		local dz = b.z - a.z
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		if len < 0.0001 then return {x = 0, y = 0, z = 0} end
		return {x = dx / len, y = dy / len, z = dz / len}
	end,
	length = function(v)
		return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
	end,
	multiply = function(v, s)
		return {x = v.x * s, y = v.y * s, z = v.z * s}
	end,
	add = function(a, b)
		return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
	end,
	subtract = function(a, b)
		return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
	end,
}
_G.vector = vector

_G.x_mob_core = {
	fast_pathfinder = dofile(modpath .. "/navigation/fast_pathfinder.lua"),
	mob_memory = dofile(modpath .. "/navigation/mob_memory.lua"),
	animator = {
		play = function() end,
	},
}

local mob_ai = dofile(modpath .. "/motor/mob_ai.lua")
local locomotion = dofile(modpath .. "/motor/locomotion.lua")
local properties = dofile(modpath .. "/lifecycle/properties.lua")

local test_count = 0
local pass_count = 0
local function assert_test(desc, condition, err_msg)
	test_count = test_count + 1
	if condition then
		pass_count = pass_count + 1
		print(string.format("  [PASS] %s", desc))
	else
		print(string.format("  [FAIL] %s - %s", desc, err_msg or "assertion failed"))
		error("Test failed: " .. desc)
	end
end

print("==================================================")
print("  Running Floating Mob Combat Subsystem Tests")
print("==================================================")

-- Test 1: Property normalization assigns combat_hover_offset and combat_standoff
local test_def = {
	is_floating = true,
	hover_offset = 1.4,
	attack_range = 2.4,
}
properties.resolve_mob_properties(test_def)
assert_test("Default combat_hover_offset clamps to <= 0.4 when hover_offset is 1.4",
	test_def.combat_hover_offset == 0.4, "Got: " .. tostring(test_def.combat_hover_offset))
assert_test("Default combat_standoff computes from attack_range * 0.7",
	math.abs(test_def.combat_standoff - (2.4 * 0.7)) < 0.001, "Got: " .. tostring(test_def.combat_standoff))

-- Test 2: Custom combat_hover_offset and combat_standoff preserved
local custom_def = {
	is_floating = true,
	hover_offset = 1.4,
	combat_hover_offset = 0.35,
	combat_standoff = 1.7,
	attack_range = 2.4,
}
properties.resolve_mob_properties(custom_def)
assert_test("Explicit combat_hover_offset preserved",
	custom_def.combat_hover_offset == 0.35)
assert_test("Explicit combat_standoff preserved",
	custom_def.combat_standoff == 1.7)

-- Test 3: halt_horizontal_velocity zeroes vertical velocity on floating mobs
local float_halt_mob = {
	is_floating = true,
	in_water = false,
	object = {
		is_valid = function() return true end,
		vel = {x = 2.5, y = 1.8, z = -1.2},
		acc = {x = 0, y = 0, z = 0},
		get_velocity = function(self) return self.vel end,
		set_velocity = function(self, v) self.vel = v end,
		set_acceleration = function(self, a) self.acc = a end,
	},
}
locomotion.halt_horizontal_velocity(float_halt_mob)
assert_test("halt_horizontal_velocity zeroes horizontal x/z velocity on floating mob",
	float_halt_mob.object.vel.x == 0 and float_halt_mob.object.vel.z == 0)
assert_test("halt_horizontal_velocity zeroes vertical drift on floating mob",
	float_halt_mob.object.vel.y == 0, "Got: " .. tostring(float_halt_mob.object.vel.y))

-- Test 3b: set_horizontal_velocity sets directed horizontal velocity and zeroes vertical drift on floating mobs
local float_set_mob = {
	is_floating = true,
	in_water = false,
	object = {
		is_valid = function() return true end,
		vel = {x = 0, y = 1.8, z = 0},
		acc = {x = 0, y = 0, z = 0},
		get_velocity = function(self) return self.vel end,
		set_velocity = function(self, v) self.vel = v end,
		set_acceleration = function(self, a) self.acc = a end,
	},
}
locomotion.set_horizontal_velocity(float_set_mob, 4.0, 0) -- yaw 0 points +Z ({x=0, y=0, z=1})
assert_test("set_horizontal_velocity sets expected horizontal velocity",
	math.abs(float_set_mob.object.vel.z - 4.0) < 0.001 and math.abs(float_set_mob.object.vel.x) < 0.001)
assert_test("set_horizontal_velocity zeroes vertical drift on floating mob",
	float_set_mob.object.vel.y == 0, "Got: " .. tostring(float_set_mob.object.vel.y))


-- Helper to create mock player and floating mob
local function create_floating_mob(mob_pos, player_pos)
	local p_ref = {
		is_valid = function() return true end,
		is_player = function() return true end,
		get_player_name = function() return "test_player" end,
		get_pos = function() return {x = player_pos.x, y = player_pos.y, z = player_pos.z} end,
		get_hp = function() return 20 end,
		get_yaw = function() return 0 end,
	}

	local m_obj = {
		pos = {x = mob_pos.x, y = mob_pos.y, z = mob_pos.z},
		vel = {x = 0, y = 0, z = 0},
		acc = {x = 0, y = 0, z = 0},
		yaw = 0,
		rot = {x = 0, y = 0, z = 0},
		is_valid = function() return true end,
		get_pos = function(self) return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end,
		get_velocity = function(self) return self.vel end,
		set_velocity = function(self, v) self.vel = v end,
		set_acceleration = function(self, a) self.acc = a end,
		get_yaw = function(self) return self.yaw end,
		set_yaw = function(self, y) self.yaw = y end,
		set_rotation = function(self, r) self.rot = r end,
		set_properties = function() end,
	}

	local mob = {
		object = m_obj,
		is_floating = true,
		hover_offset = 1.4,
		combat_hover_offset = 0.35,
		combat_standoff = 1.7,
		attack_range = 2.4,
		pursuit_speed = 4.0,
		path_state = {timer = 0},
		abilities = {is_floating = true},
		target = p_ref,
	}
	return mob, p_ref
end

-- Test 4: Approaching target from 3.5m away moves towards standoff (1.7m), not target center
local mob1 = create_floating_mob({x = 0, y = 0.85, z = 3.5}, {x = 0, y = 0.5, z = 0})
mob_ai.update_navigation(mob1, 0.1)
assert_test("Mob at 3.5m has negative Z velocity moving forward toward 1.7m standoff",
	mob1.object.vel.z < -0.5, "Got vel.z: " .. tostring(mob1.object.vel.z))
assert_test("Mob at 3.5m keeps zero X velocity in direct line",
	math.abs(mob1.object.vel.x) < 0.01)

-- Test 5: Mob already at ideal combat standoff (1.7m) decelerates to zero speed
local mob2 = create_floating_mob({x = 0, y = 0.85, z = 1.7}, {x = 0, y = 0.5, z = 0})
mob_ai.update_navigation(mob2, 0.1)
assert_test("Mob at exact 1.7m standoff has 0 horizontal velocity (holding position)",
	math.abs(mob2.object.vel.x) < 0.01 and math.abs(mob2.object.vel.z) < 0.01,
	"Got vel: " .. mob2.object.vel.x .. ", " .. mob2.object.vel.z)

-- Test 6: Player walks forward into mob (mob is now 1.2m away); mob glides backward
local mob3 = create_floating_mob({x = 0, y = 0.85, z = 1.2}, {x = 0, y = 0.5, z = 0})
mob_ai.update_navigation(mob3, 0.1)
assert_test("Mob inside standoff (1.2m) has positive Z velocity backpedaling away from player",
	mob3.object.vel.z > 0.2, "Got vel.z: " .. tostring(mob3.object.vel.z))

-- Test 7: Combat elevation anchors slightly above ground (player feet y=0.5 -> desired y=0.85)
-- Mob starting too high (y = 1.9, previous bug where it hovered at player_feet + 1.4)
local mob4 = create_floating_mob({x = 0, y = 1.9, z = 2.0}, {x = 0, y = 0.5, z = 0})
mob_ai.update_navigation(mob4, 0.1)
assert_test("Mob starting too high (y=1.9) descends toward combat hover y=0.85 (negative y_vel)",
	mob4.object.vel.y < -1.0, "Got vel.y: " .. tostring(mob4.object.vel.y))

-- Test 8: Mob starting too low (y = 0.5) ascends toward combat hover y=0.85 (positive y_vel)
local mob5 = create_floating_mob({x = 0, y = 0.5, z = 2.0}, {x = 0, y = 0.5, z = 0})
mob_ai.update_navigation(mob5, 0.1)
assert_test("Mob starting at foot level (y=0.5) ascends toward combat hover y=0.85 (positive y_vel)",
	mob5.object.vel.y > 0.5, "Got vel.y: " .. tostring(mob5.object.vel.y))

-- Test 9: Mob at desired combat hover (y = 0.85) maintains vertical stability (y_vel = 0)
local mob6 = create_floating_mob({x = 0, y = 0.85, z = 2.0}, {x = 0, y = 0.5, z = 0})
mob_ai.update_navigation(mob6, 0.1)
assert_test("Mob at desired combat hover (y=0.85) has 0 vertical velocity",
	mob6.object.vel.y == 0, "Got vel.y: " .. tostring(mob6.object.vel.y))

-- Test 10: Facing yaw is locked directly onto target player
local mob7 = create_floating_mob({x = 2.0, y = 0.85, z = 0}, {x = 0, y = 0.5, z = 0})
for _ = 1, 5 do
	mob_ai.update_navigation(mob7, 0.1)
end
local expected_yaw = core.dir_to_yaw(vector.direction(mob7.object:get_pos(), {x = 0, y = 0.5, z = 0}))
assert_test("Mob facing rotation matches direction to player after angular interpolation",
	math.abs(mob7.object.rot.y - expected_yaw) < 0.05,
	"Got rot.y: " .. tostring(mob7.object.rot.y) .. " expected: " .. tostring(expected_yaw))

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count / test_count) * 100))
print("==================================================")
print("All floating mob combat subsystem tests passed successfully!")
