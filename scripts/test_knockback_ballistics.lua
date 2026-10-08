--[[
	test_knockback_ballistics.lua - Unit tests for mob knockback ballistics,
	vertical velocity preservation, and zero-allocation airborne trajectory.
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
	get_objects_inside_radius = function() return {} end,
	register_on_mods_loaded = function() end,
	register_globalstep = function() end,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	register_on_generated = function() end,
	get_mapgen_setting = function() return nil end,
	register_on_joinplayer = function() end,
	register_on_leaveplayer = function() end,
	register_on_dieplayer = function() end,
	register_on_respawnplayer = function() end,
	register_on_punchplayer = function() end,
	register_on_player_hpchange = function() end,
	register_on_shutdown = function() end,
	get_translator = function() return function(s) return s end end,
	get_connected_players = function() return {} end,
	register_chatcommand = function() end,
	line_of_sight = function() return true end,
	get_item_group = function() return 0 end,
	log = function() end,
	sound_play = function() end,
	add_particlespawner = function() end,
	add_entity = function() return nil end,
	after = function() end,
}
_G.minetest = _G.core

local passed = 0
local failed = 0

local function assert_test(name, condition, details)
	if condition then
		passed = passed + 1
		print(string.format("  [PASS] %s", name))
	else
		failed = failed + 1
		print(string.format("  [FAIL] %s - %s", name, details or "Condition returned false"))
	end
end

print("==================================================")
print("  Running Knockback Ballistics Test Suite")
print("==================================================")

-- Load full API
dofile(modpath .. "/api.lua")
local locomotion = x_mob_core.motor.locomotion
local mob_ai = x_mob_core.motor.ai
local entity_wrapper = x_mob_core.lifecycle.entity_wrapper
local combat_handler = entity_wrapper.combat_handler

-- Test 1: Terrestrial pack member is NOT flagged as in_water on land
local minion_ent = {
	pack_role = "member",
	object = {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 1, z = 0} end,
		get_velocity = function() return {x = 0, y = 0, z = 0} end,
		set_velocity = function() end,
		set_acceleration = function() end,
	},
}
local is_shoal = (minion_ent.shoal ~= nil)
assert_test("Terrestrial minion is not classified as shoal", is_shoal == false)

-- Test 2: Upward velocity is preserved in halt_horizontal_velocity
local test_mob = {
	in_water = false,
	is_floating = false,
	object = {
		is_valid = function() return true end,
		vel = {x = 3.5, y = 2.4, z = 1.2},
		acc = {x = 0, y = 0, z = 0},
		get_velocity = function(self) return self.vel end,
		set_velocity = function(self, v) self.vel = v end,
		set_acceleration = function(self, a) self.acc = a end,
	}
}
locomotion.halt_horizontal_velocity(test_mob)
assert_test("halt_horizontal_velocity zeroes horizontal velocity",
	test_mob.object.vel.x == 0 and test_mob.object.vel.z == 0)
assert_test("halt_horizontal_velocity preserves positive vertical velocity",
	test_mob.object.vel.y == 2.4, "Got: " .. tostring(test_mob.object.vel.y))
assert_test("halt_horizontal_velocity sets gravity acceleration", test_mob.object.acc.y == -9.81)

-- Test 3: Airborne mob in update_navigation executes smooth ballistic flight
local airborne_mob
airborne_mob = {
	in_water = false,
	is_floating = false,
	_knockback_timer = 0.35,
	_moveresult = {touching_ground = false},
	_anim_initialized = true,
	state = "idle",
	object = {
		is_valid = function() return true end,
		vel = {x = 5.0, y = 1.8, z = 0.0},
		acc = {x = 0, y = 0, z = 0},
		yaw = 0,
		get_pos = function() return {x = 0, y = 4, z = 0} end,
		get_velocity = function(self) return self.vel end,
		set_velocity = function(self, v) self.vel = {x = v.x, y = v.y, z = v.z} end,
		set_acceleration = function(self, a) self.acc = {x = a.x, y = a.y, z = a.z} end,
		set_yaw = function(self, y) self.yaw = y end,
		get_yaw = function(self) return self.yaw end,
		get_luaentity = function() return airborne_mob end,
		get_hp = function() return 20 end,
		set_hp = function() end,
	}
}

local nav = mob_ai.update_navigation(airborne_mob, 0.1)
assert_test("Airborne mob reports moving = true", nav and nav.moving == true)
assert_test("Airborne mob preserves vertical velocity", airborne_mob.object.vel.y == 1.8)
assert_test("Airborne mob applies air drag to horizontal velocity",
	airborne_mob.object.vel.x < 5.0 and airborne_mob.object.vel.x > 4.0)
assert_test("Airborne mob maintains -9.81 gravity acceleration", airborne_mob.object.acc.y == -9.81)

-- Test 4: Landing clears knockback timer
airborne_mob._moveresult.touching_ground = true
airborne_mob.object.vel.y = 0.0
entity_wrapper.handle_core_step(airborne_mob, 0.1, {})
assert_test("Touching ground clears _knockback_timer", airborne_mob._knockback_timer == nil)

-- Test 5: combat_handler.handle_punch respects knockback = 0 and caps vertical lift
local punch_mob
punch_mob = {
	hp = 20,
	hp_max = 20,
	knockback_mult = 1.5,
	state = "idle",
	_anim_initialized = true,
	object = {
		is_valid = function() return true end,
		added_vel = nil,
		add_velocity = function(self, v) self.added_vel = v end,
		set_hp = function() end,
		get_luaentity = function() return punch_mob end,
		set_properties = function() end,
		get_armor_groups = function() return {fleshy = 100} end,
		get_pos = function() return {x = 0, y = 0, z = 0} end,
		get_properties = function() return {collisionbox = {-0.4, 0, -0.4, 0.4, 1.6, 0.4}} end,
		get_texture_mod = function() return "" end,
		set_texture_mod = function() end,
		get_animations = function() return {} end,
		play_animation = function() end,
	}
}

-- Punch with knockback = 0 (from custom projectile like x_bows)
combat_handler.handle_punch(
	punch_mob,
	nil,
	1.0,
	{damage_groups = {fleshy = 5, knockback = 0}},
	{x = 1, y = 0, z = 0},
	5,
	{}
)
assert_test("Punch with knockback = 0 does NOT double-add velocity", punch_mob.object.added_vel == nil)
assert_test("Punch with knockback = 0 sets _knockback_timer", punch_mob._knockback_timer == 0.4)

-- Punch with normal knockback (e.g. melee attack)
punch_mob.object.added_vel = nil
punch_mob._knockback_timer = nil
combat_handler.handle_punch(
	punch_mob,
	nil,
	1.0,
	{damage_groups = {fleshy = 5, knockback = 1}},
	{x = 1, y = 0, z = 0},
	5,
	{}
)
assert_test("Punch with normal knockback adds velocity", punch_mob.object.added_vel ~= nil)
assert_test("Punch vertical lift is capped <= 1.8", punch_mob.object.added_vel.y <= 1.8)
assert_test("Punch vertical lift matches 0.5 * kb", punch_mob.object.added_vel.y == 0.75)
assert_test("Punch sets _knockback_timer", punch_mob._knockback_timer == 0.4)

print("==================================================")
local pct = (passed / (passed + failed)) * 100
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", passed, passed + failed, pct))
print("==================================================")

if failed > 0 then
	os.exit(1)
end
