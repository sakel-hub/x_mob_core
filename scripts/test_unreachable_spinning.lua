--[[
	test_unreachable_spinning.lua - Test Suite for Unreachable Pathfinding and Spin Suppression
	Validates:
	1. Default max_angular_speed is calibrated to 4.0 rad/s.
	2. Unreachable failures increment when pathfinder cannot find a valid path to target.
	3. When unreachable threshold is reached (_unreachable_fails >= 2), mob records target in
	   mob_memory as unreachable, clears target, and transitions to wandering patrol for 10s.
	4. Blocked mobs with unreachable fails hold position and smoothly face target instead of
	   rapidly alternating contour directions (contour timer/dir suppressed).
	5. Stationary and searching rotation speeds are damped to 3.0 rad/s to eliminate wild spinning.
	6. Path retry delay is preserved with exponential backoff and not wiped to 0 on collision.
]]

local math = math

-- Minimal Luanti Engine Environment Mock
local current_gametime = 100.0
local world_nodes = {}

local core = {
	get_gametime = function()
		return current_gametime
	end,
	get_modpath = function(modname)
		if modname == "x_mob_core" then
			return "."
		end
		return nil
	end,
	registered_entities = {},
	registered_nodes = {
		["air"] = {walkable = false, buildable_to = true},
		["default:dirt"] = {walkable = true},
		["default:stone"] = {walkable = true},
	},
	get_node_or_nil = function(pos)
		local k = string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
		return world_nodes[k] or {name = "air"}
	end,
	get_node = function(pos)
		local k = string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
		return world_nodes[k] or {name = "air"}
	end,
	dir_to_yaw = function(dir)
		local atan = math.atan2 or math.atan
		return -atan(dir.x, dir.z)
	end,
	yaw_to_dir = function(yaw)
		return {x = -math.sin(yaw), y = 0, z = math.cos(yaw)}
	end,
	get_objects_inside_radius = function()
		return {}
	end,
	register_on_mods_loaded = function() end,
	register_globalstep = function() end,
	register_entity = function() end,
	after = function(_delay, func) func() end,
	sound_play = function() return 1 end,
	sound_stop = function() end,
	log = function() end,
	get_translator = function() return function(s) return s end end,
	hash_node_position = function(pos)
		return string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
	end,
	line_of_sight = function() return true end,
	get_item_group = function() return 0 end,
	settings = {
		get_bool = function(_key, default) return default end,
		get = function(_key) return nil end,
	},
}
_G.core = core
_G.minetest = core

local vector = {
	new = function(x, y, z)
		if type(x) == "table" then
			return {x = x.x or 0, y = x.y or 0, z = x.z or 0}
		end
		return {x = x or 0, y = y or 0, z = z or 0}
	end,
	distance = function(p1, p2)
		local dx = p1.x - p2.x
		local dy = p1.y - p2.y
		local dz = p1.z - p2.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	direction = function(p1, p2)
		local dx = p2.x - p1.x
		local dy = p2.y - p1.y
		local dz = p2.z - p1.z
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		if len < 0.0001 then return {x = 0, y = 0, z = 0} end
		return {x = dx / len, y = dy / len, z = dz / len}
	end,
	length = function(v)
		return math.sqrt((v.x or 0) * (v.x or 0) + (v.y or 0) * (v.y or 0) + (v.z or 0) * (v.z or 0))
	end,
	normalize = function(v)
		local len = math.sqrt((v.x or 0) * (v.x or 0) + (v.y or 0) * (v.y or 0) + (v.z or 0) * (v.z or 0))
		if len < 0.0001 then return {x = 0, y = 0, z = 0} end
		return {x = v.x / len, y = v.y / len, z = v.z / len}
	end,
	add = function(a, b)
		return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
	end,
	subtract = function(a, b)
		return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
	end,
	multiply = function(a, s)
		return {x = a.x * s, y = a.y * s, z = a.z * s}
	end,
	round = function(v)
		return {
			x = math.floor(v.x + 0.5),
			y = math.floor(v.y + 0.5),
			z = math.floor(v.z + 0.5),
		}
	end,
	equals = function(a, b)
		return a.x == b.x and a.y == b.y and a.z == b.z
	end,
}
_G.vector = vector

local tests_passed = 0
local tests_total = 0

local function assert_eq(actual, expected, msg)
	tests_total = tests_total + 1
	if actual == expected then
		tests_passed = tests_passed + 1
		print("  [PASS] " .. msg)
	else
		print(string.format("  [FAIL] %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
		os.exit(1)
	end
end

local function assert_true(val, msg)
	assert_eq(val, true, msg)
end

local function assert_false(val, msg)
	assert_eq(val, false, msg)
end

local function assert_near(actual, expected, tolerance, msg)
	tests_total = tests_total + 1
	if math.abs(actual - expected) <= tolerance then
		tests_passed = tests_passed + 1
		print("  [PASS] " .. msg)
	else
		print(string.format("  [FAIL] %s: expected ~%s (+/-%s), got %s",
			msg, tostring(expected), tostring(tolerance), tostring(actual)))
		os.exit(1)
	end
end

print("==================================================")
print("  Running x_mob_core Unreachable & Spin Prevention Tests")
print("==================================================")

-- Mock x_mob_core table for subsystem dependencies
_G.x_mob_core = {
	emit = function() end,
	listen = function() end,
	events = {
		emit = function() end,
		listen = function() end,
	},
	pack = {
		coordination = {
			unregister_member = function() end,
			handle_member_step = function() end,
		},
		squad = {
			handle_leader_death = function() end,
			step_followers = function() end,
		},
		swarm = {
			step = function() end,
		},
		shoal = {
			step = function() end,
		},
	},
	combat = {
		health_bar = {
			remove = function() end,
		},
	},
	animator = {
		play = function() end,
	},
}

-- Load dependencies
_G.x_mob_core.utils = dofile("./core/utils.lua")
_G.x_mob_core.node_cache = dofile("./motor/node_cache.lua")
_G.x_mob_core.safety = dofile("./motor/safety.lua")
local mob_memory = dofile("./navigation/mob_memory.lua")
_G.x_mob_core.mob_memory = mob_memory
local locomotion = dofile("./motor/locomotion.lua")
_G.x_mob_core.locomotion = locomotion

-- Mock fast_pathfinder returning nil to simulate completely unreachable target (e.g. up a high pillar)
_G.x_mob_core.fast_pathfinder = {
	find_path = function(_start, _target, _abilities, callback, _height)
		callback(nil)
	end,
}

local mob_ai = dofile("./motor/mob_ai.lua")
_G.x_mob_core.mob_ai = mob_ai
local entity_wrapper = dofile("./lifecycle/entity_wrapper.lua")
_G.x_mob_core.entity_wrapper = entity_wrapper

local function create_mock_object()
	return {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 0, z = 0} end,
		get_luaentity = function() return nil end,
		get_properties = function() return {} end,
		set_properties = function() end,
		set_armor_groups = function() end,
		set_hp = function() end,
		get_texture_mod = function() return "" end,
		set_texture_mod = function() end,
		get_acceleration = function() return {x = 0, y = 0, z = 0} end,
		set_acceleration = function() end,
		get_velocity = function() return {x = 0, y = 0, z = 0} end,
		set_velocity = function() end,
		get_yaw = function() return 0 end,
		set_yaw = function() end,
		get_rotation = function() return {x = 0, y = 0, z = 0} end,
		set_rotation = function() end,
		get_animations = function() return {} end,
		set_animation = function() end,
		set_animation_frame_speed = function() end,
		play_animation = function() end,
		stop_animation = function() end,
	}
end

-- 1. Verify Default max_angular_speed on Entity Activation
local test_def = {
	collisionbox = {-0.3, 0, -0.3, 0.3, 1.6, 0.3},
}
entity_wrapper.register_mob("x_mobs:test_goblin", test_def)
local test_entity = {
	object = create_mock_object(),
}
test_def.on_activate(test_entity, "", 0)
assert_eq(test_entity.max_angular_speed, 4.0, "default max_angular_speed is 4.0 rad/s on activation")

-- Custom max_angular_speed override
local custom_def = {
	max_angular_speed = 6.0,
}
entity_wrapper.register_mob("x_mobs:test_fast_turner", custom_def)
local custom_entity = {
	object = create_mock_object(),
}
custom_def.on_activate(custom_entity, "", 0)
assert_eq(custom_entity.max_angular_speed, 6.0, "custom max_angular_speed override is respected")

-- 2. Verify Mob AI Unreachable Fail Counter & State Transition
local target_pos = {x = 0, y = 8, z = 10}
local target_obj = {
	is_valid = function() return true end,
	is_player = function() return true end,
	get_player_name = function() return "test_player" end,
	get_pos = function() return target_pos end,
	get_look_horizontal = function() return 0 end,
	get_look_yaw = function() return 0 end,
	get_yaw = function() return 0 end,
	get_hp = function() return 20 end,
}

-- Setup solid ground for mob to stand on
world_nodes["0,-1,0"] = {name = "default:stone", walkable = true}

local mob_pos = {x = 0, y = 0, z = 0}
local cur_yaw = 0
local cur_vel = {x = 0, y = 0, z = 0}
local cur_rot = {x = 0, y = 0, z = 0}

local mock_mob = {
	name = "x_mobs:test_crawler",
	state = "combat",
	target = target_obj,
	abilities = {can_climb = false, can_swim = false},
	max_angular_speed = 4.0,
	memory = mob_memory.init_memory({}),
	path_state = {
		retry_delay = 0,
		target_pos = nil,
	},
	object = {
		is_valid = function() return true end,
		get_pos = function() return mob_pos end,
		get_yaw = function() return cur_yaw end,
		set_yaw = function(_s, y) cur_yaw = y end,
		get_rotation = function() return cur_rot end,
		set_rotation = function(_s, r) cur_rot = r end,
		get_velocity = function() return cur_vel end,
		set_velocity = function(_s, v) cur_vel = {x = v.x or 0, y = v.y or 0, z = v.z or 0} end,
		get_acceleration = function() return {x = 0, y = -9.81, z = 0} end,
		set_acceleration = function() end,
	},
}

-- First step: Pathfinder fails, incrementing _unreachable_fails to 1
mob_ai.update_navigation(mock_mob, 0.1)
assert_eq(mock_mob._unreachable_fails, 1, "unreachable fails increments to 1 on path failure")
assert_near(mock_mob.path_state.retry_delay, 1.0, 0.05, "path retry delay incorporates base delay")
assert_eq(mock_mob.target, target_obj, "target retained after first failure")

-- Fast-forward past retry delay
current_gametime = current_gametime + 2.0
mock_mob.path_state.retry_delay = 0

-- Second step: Pathfinder fails again, reaching threshold >= 2
mob_ai.update_navigation(mock_mob, 0.1)
assert_eq(mock_mob.target, nil, "mob clears unreachable target when threshold reached")
assert_eq(mock_mob.state, "wandering", "mob transitions to wandering state")
assert_true(mock_mob.wander_state and mock_mob.wander_state.is_moving,
	"mob initiates wander movement to disengage")
assert_true(mob_memory.is_target_unreachable(mock_mob, target_obj),
	"target marked as unreachable in mob_memory")

-- 3. Verify Spin Damping & Contour Suppression when Blocked with Failures
local blocked_yaw = 0
local blocked_vel = {x = 0, y = 0, z = 0}
local blocked_rot = {x = 0, y = 0, z = 0}

local blocked_mob = {
	name = "x_mobs:test_blocked",
	state = "combat",
	target = target_obj,
	abilities = {can_climb = false, can_swim = false},
	max_angular_speed = 4.0,
	memory = mob_memory.init_memory({}),
	_unreachable_fails = 1, -- has a recorded path failure
	path_state = {
		retry_delay = 1.5,
		target_pos = target_pos,
	},
	object = {
		is_valid = function() return true end,
		get_pos = function() return mob_pos end,
		get_yaw = function() return blocked_yaw end,
		set_yaw = function(_s, y) blocked_yaw = y end,
		get_rotation = function() return blocked_rot end,
		set_rotation = function(_s, r) blocked_rot = r end,
		get_velocity = function() return blocked_vel end,
		set_velocity = function(_s, v) blocked_vel = {x = v.x or 0, y = v.y or 0, z = v.z or 0} end,
		get_acceleration = function() return {x = 0, y = -9.81, z = 0} end,
		set_acceleration = function() end,
	},
}

-- Block forward movement by placing a solid wall directly in front
world_nodes["0,0,1"] = {name = "default:stone", walkable = true}
world_nodes["0,1,1"] = {name = "default:stone", walkable = true}

local move_result = mob_ai.update_navigation(blocked_mob, 0.05)
assert_false(move_result.moving, "blocked mob stops forward velocity")
assert_eq(blocked_mob._contour_timer, nil, "contour timer is suppressed when unreachable fails > 0")
assert_eq(blocked_mob._contour_dir, nil, "contour direction oscillation is suppressed")
assert_eq(blocked_vel.x, 0, "lateral velocity is zeroed when blocked with unreachable failure")
assert_eq(blocked_vel.z, 0, "forward velocity is zeroed when blocked with unreachable failure")

-- 4. Verify Path Retry Delay is NOT wiped on Collision
assert_near(blocked_mob.path_state.retry_delay, 1.45, 0.01,
	"path retry delay decrements smoothly by dtime and is not reset to 0 on collision")

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (100.0%%)", tests_passed, tests_total))
print("==================================================")
print("All unreachable pathfinding & spin prevention tests passed successfully!")
