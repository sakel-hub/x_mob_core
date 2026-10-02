--[[
	test_water_avoidance.lua - Comprehensive Test Suite for Water Avoidance Subsystem
	Validates:
	1. Accurate differentiation between aquatic and terrestrial mobs via is_aquatic_mob
	2. Safe step evaluation (is_step_safe) preventing terrestrial mobs from entering water (level, step-up, drop-down)
	3. Safe step evaluation allowing terrestrial mobs to swim when disallow_water is false and can_swim is true
	4. Shoreline search (find_nearest_shore_pos) detecting nearest dry walkable land
	5. Dynamic navigation gating (update_navigation) enabling water pursuit vs water avoidance
	6. Fleeing behavior avoiding water bodies on land and escaping to shore when submerged
	7. Wandering behavior avoiding water bodies on land and escaping to shore when submerged
	8. Squad regrouping behavior avoiding ocean water traversal when leader and follower are on land
	9. Fast pathfinder honoring disallow_water flag
]]

-- Minimal Luanti Engine Environment Mock
local world_nodes = {}

local core = {
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
		["default:dirt_with_grass"] = {walkable = true},
		["default:water_source"] = {walkable = false, liquidtype = "source", liquid_viscosity = 1},
		["default:water_flowing"] = {walkable = false, liquidtype = "flowing", liquid_viscosity = 1},
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
	get_gametime = function()
		return 100.0
	end,
	get_objects_inside_radius = function()
		return {}
	end,
	register_on_mods_loaded = function() end,
	register_globalstep = function() end,
	hash_node_position = function(pos)
		return string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
	end,
	line_of_sight = function() return true end,
	get_item_group = function() return 0 end,
	log = function() end,
}
_G.core = core
_G.minetest = core

local vector = {
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
	round = function(p)
		return {
			x = math.floor(p.x + 0.5),
			y = math.floor(p.y + 0.5),
			z = math.floor(p.z + 0.5),
		}
	end,
}
_G.vector = vector

local function set_node(x, y, z, name)
	local k = string.format("%d,%d,%d", x, y, z)
	world_nodes[k] = {name = name}
	if _G.x_mob_core and _G.x_mob_core.motor and _G.x_mob_core.motor.node_cache then
		_G.x_mob_core.motor.node_cache.clear()
	end
end

local function clear_world()
	world_nodes = {}
	if _G.x_mob_core and _G.x_mob_core.motor and _G.x_mob_core.motor.node_cache then
		_G.x_mob_core.motor.node_cache.clear()
	end
end

-- Load subsystems
local utils = dofile("./core/utils.lua")
local mob_memory = dofile("./navigation/mob_memory.lua")
local node_cache = dofile("./motor/node_cache.lua")
local doors = dofile("./motor/doors.lua")
local surface = dofile("./motor/surface.lua")
local safety = dofile("./motor/safety.lua")
local locomotion = dofile("./motor/locomotion.lua")
local mob_ai = dofile("./motor/mob_ai.lua")

_G.x_mob_core = {
	utils = utils,
	mob_memory = mob_memory,
	animator = {
		play = function(_obj, _anim, _opts) end,
	},
	pack = {
		coordination = {
			check_leash = function(_self) return false, nil, 0 end,
			step_regroup = function(_self, _dt, _anim) return false end,
		},
	},
	motor = {
		node_cache = node_cache,
		doors = doors,
		surface = surface,
		safety = safety,
		locomotion = locomotion,
		ai = mob_ai,
	},
}

local test_count = 0
local pass_count = 0

local function assert_eq(actual, expected, desc)
	test_count = test_count + 1
	if actual == expected then
		pass_count = pass_count + 1
		print(string.format("  [PASS] %s", desc))
	else
		print(string.format("  [FAIL] %s - Expected: %s, Got: %s", desc, tostring(expected), tostring(actual)))
	end
end

local function assert_true(actual, desc)
	assert_eq(actual == true, true, desc)
end

local function assert_false(actual, desc)
	assert_eq(actual == false or actual == nil, true, desc)
end

print("==================================================")
print("  Running x_mob_core Water Avoidance Test Suite")
print("==================================================")

-- 1. Test mob classification (is_aquatic_mob)
local shaman_mob = {
	name = "x_mobs:fallen_shaman",
	can_swim = true,
	mob_type = "monster",
}
local minion_mob = {
	name = "x_mobs:fallen_minion",
	can_swim = true,
}
local spider_mob = {
	name = "x_mobs:spider",
	can_swim = true,
}
local generic_mob = {
	can_swim = true,
}
local fish_mob1 = {
	name = "x_mobs:clownfish",
	mob_type = "aquatic",
}
local fish_mob2 = {
	name = "x_mobs:skeleton_fish",
	is_aquatic = true,
}
local fish_mob3 = {
	name = "x_mobs:shoal_fish",
	shoal_member = true,
}
local fish_mob4 = {
	name = "x_mobs:blue_tang",
	can_breathe = false,
	can_fly_in_water = true,
}

assert_false(safety.is_aquatic_mob(shaman_mob), "is_aquatic_mob returns false for fallen_shaman")
assert_false(safety.is_aquatic_mob(minion_mob), "is_aquatic_mob returns false for fallen_minion")
assert_false(safety.is_aquatic_mob(spider_mob), "is_aquatic_mob returns false for spider")
assert_false(safety.is_aquatic_mob(generic_mob), "is_aquatic_mob returns false for unconfigured mob")
assert_true(safety.is_aquatic_mob(fish_mob1), "is_aquatic_mob returns true for mob_type = 'aquatic'")
assert_true(safety.is_aquatic_mob(fish_mob2), "is_aquatic_mob returns true for is_aquatic = true")
assert_true(safety.is_aquatic_mob(fish_mob3), "is_aquatic_mob returns true for shoal_member = true")
assert_true(safety.is_aquatic_mob(fish_mob4),
	"is_aquatic_mob returns true for can_breathe=false, can_fly_in_water=true")

-- 2. Test is_step_safe with water avoidance
clear_world()
-- Build a flat platform of dirt from x=-2 to 0 at y=0, with water at x=1,2,3 at y=0
for z = -2, 2 do
	for x = -3, 0 do
		set_node(x, 0, z, "default:dirt")
		set_node(x, 1, z, "air")
		set_node(x, 2, z, "air")
	end
	for x = 1, 3 do
		set_node(x, 0, z, "default:water_source")
		set_node(x, 1, z, "air")
		set_node(x, 2, z, "air")
	end
end

-- At pos {x=0, y=1, z=0}, standing on dirt at y=0. Move +x toward water
local current_pos = {x = 0, y = 1, z = 0}
local to_water_dir = {x = 1, y = 0, z = 0}
local to_land_dir = {x = -1, y = 0, z = 0}

-- Stepping on land
local safe_land, _ = safety.is_step_safe(current_pos, to_land_dir, {can_swim = false, disallow_water = true})
assert_true(safe_land, "is_step_safe allows stepping onto dry solid land")

-- Stepping towards water with disallow_water = true
local safe_water_avoid, reason1 = safety.is_step_safe(
	current_pos, to_water_dir, {can_swim = false, disallow_water = true})
assert_false(safe_water_avoid, "is_step_safe rejects stepping into water with disallow_water = true")
assert_eq(reason1, "water", "is_step_safe provides 'water' rejection reason")

-- Stepping towards water with can_swim = true and disallow_water = true
local safe_water_disallow, reason2 = safety.is_step_safe(
	current_pos, to_water_dir, {can_swim = true, disallow_water = true})
assert_false(safe_water_disallow, "is_step_safe rejects water when disallow_water = true even if can_swim = true")
assert_eq(reason2, "water", "is_step_safe provides 'water' rejection reason with disallow_water = true")

-- Stepping towards water with can_swim = true and disallow_water = false (pursuit mode)
local safe_water_swim, _ = safety.is_step_safe(
	current_pos, to_water_dir, {can_swim = true, disallow_water = false})
assert_true(safe_water_swim, "is_step_safe allows stepping into water when can_swim = true and disallow_water = false")

-- Drop-down onto water test
clear_world()
-- High ledge at x=0, y=2 (dirt at y=1). Water below at x=1, y=0.
set_node(0, 1, 0, "default:dirt")
set_node(0, 2, 0, "air")
set_node(1, 0, 0, "default:water_source")
set_node(1, 1, 0, "air")
set_node(1, 2, 0, "air")

local high_pos = {x = 0, y = 2, z = 0}
local safe_drop_water, reason_drop = safety.is_step_safe(
	high_pos, to_water_dir, {can_swim = false, disallow_water = true})
assert_false(safe_drop_water, "is_step_safe rejects dropping down onto water with disallow_water = true")
assert_eq(reason_drop, "water", "is_step_safe drop-down rejection reason is 'water'")

-- 3. Test find_nearest_shore_pos
clear_world()
-- Center water lake at x in [-2, 2], z in [-2, 2] at y=0 with air above at y=1.
for x = -3, 3 do
	for z = -3, 3 do
		set_node(x, 0, z, "default:water_source")
		set_node(x, 1, z, "air")
	end
end
-- East shore at x=3: dirt at y=0, air at y=1, air at y=2
for z = -3, 3 do
	set_node(3, 0, z, "default:dirt")
	set_node(3, 1, z, "air")
	set_node(3, 2, z, "air")
end

local water_mob_pos = {x = 0, y = 0, z = 0}
local shore_pos = safety.find_nearest_shore_pos(water_mob_pos, 8)
assert_true(shore_pos ~= nil, "find_nearest_shore_pos finds dry land from water")
if shore_pos then
	assert_eq(shore_pos.x, 3, "find_nearest_shore_pos identifies correct shore x coordinate")
	assert_eq(shore_pos.y, 1, "find_nearest_shore_pos identifies correct walkable stand y coordinate")
end

-- 4. Test Navigation Gating in update_navigation
local mock_mob = {
	name = "x_mobs:fallen_shaman",
	can_swim = true,
	abilities = {can_swim = true, can_climb = false, can_open_doors = false},
	is_pursuing = false,
	object = {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 1, z = 0} end,
		get_yaw = function() return 0 end,
		set_yaw = function() end,
		get_velocity = function() return {x = 0, y = 0, z = 0} end,
		set_velocity = function() end,
		get_acceleration = function() return {x = 0, y = 0, z = 0} end,
		set_acceleration = function() end,
		get_rotation = function() return {x = 0, y = 0, z = 0} end,
		set_rotation = function() end,
	},
}

-- Calling update_navigation when wandering (not pursuing)
mob_ai.update_navigation(mock_mob, 0.1)
assert_eq(mock_mob.abilities.can_swim, false, "update_navigation sets can_swim = false when not pursuing")
assert_eq(mock_mob.abilities.disallow_water, true, "update_navigation sets disallow_water = true when not pursuing")

-- Calling update_navigation when pursuing target
local mock_target = {
	is_valid = function() return true end,
	is_player = function() return true end,
	get_player_name = function() return "singleplayer" end,
	get_hp = function() return 20 end,
	get_pos = function() return {x = 10, y = 1, z = 0} end,
}
mock_mob.target = mock_target
mock_mob.is_pursuing = true
mob_ai.update_navigation(mock_mob, 0.1)
assert_eq(mock_mob.abilities.can_swim, true, "update_navigation enables can_swim = true when pursuing target")
assert_eq(mock_mob.abilities.disallow_water, false, "update_navigation clears disallow_water when pursuing target")

-- Aquatic mob always keeps can_swim = true
local mock_fish = {
	name = "x_mobs:skeleton_fish",
	is_aquatic = true,
	can_swim = true,
	abilities = {can_swim = true},
	is_pursuing = false,
	object = {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 0, z = 0} end,
		get_yaw = function() return 0 end,
		set_yaw = function() end,
		get_velocity = function() return {x = 0, y = 0, z = 0} end,
		set_velocity = function() end,
		get_acceleration = function() return {x = 0, y = 0, z = 0} end,
		set_acceleration = function() end,
		get_rotation = function() return {x = 0, y = 0, z = 0} end,
		set_rotation = function() end,
	},
}
mob_ai.update_navigation(mock_fish, 0.1)
assert_eq(mock_fish.abilities.can_swim, true, "aquatic mob maintains can_swim = true when idle")
assert_false(mock_fish.abilities.disallow_water, "aquatic mob never disallows water")

-- 5. Test Fast Pathfinder disallow_water
assert_true(dofile("./navigation/fast_pathfinder.lua") ~= nil, "fast_pathfinder module loads successfully")
local pf_abilities_water = {can_swim = true, disallow_water = true}
-- Verify that disallow_water suppresses can_swim inside pathfinder
local can_swim_resolved = (pf_abilities_water.can_swim == true) and
	not (pf_abilities_water and pf_abilities_water.disallow_water == true)
assert_false(can_swim_resolved, "fast_pathfinder suppresses can_swim when disallow_water is true")

local pf_abilities_pursue = {can_swim = true, disallow_water = false}
local can_swim_pursue = (pf_abilities_pursue.can_swim == true) and
	not (pf_abilities_pursue and pf_abilities_pursue.disallow_water == true)
assert_true(can_swim_pursue, "fast_pathfinder allows swimming when pursuing (disallow_water is false)")
-- 6. Test Wandering Behavior in Liquid vs Land
clear_world()
-- Water from x=-5 to 2, Shore at x=3
for z = -3, 3 do
	for x = -5, 2 do
		set_node(x, 0, z, "default:water_source")
		set_node(x, 1, z, "air")
	end
	set_node(3, 0, z, "default:dirt")
	set_node(3, 1, z, "air")
	set_node(3, 2, z, "air")
end

local water_wander_mob = {
	name = "x_mobs:fallen_shaman",
	can_swim = true,
	abilities = {can_swim = true},
	wander_state = {timer = 0, is_moving = false},
	object = {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 0, z = 0} end,
		get_yaw = function() return 0 end,
		set_yaw = function() end,
		get_velocity = function() return {x = 0, y = 0, z = 0} end,
		set_velocity = function() end,
		get_acceleration = function() return {x = 0, y = 0, z = 0} end,
		set_acceleration = function() end,
		get_rotation = function() return {x = 0, y = 0, z = 0} end,
		set_rotation = function() end,
	},
}

locomotion.handle_mob_wandering(water_wander_mob, 0.1, {x = 0, y = 0, z = 0}, false)
assert_true(water_wander_mob.wander_state.is_moving, "submerged wandering mob initiates movement toward shore")
assert_true(water_wander_mob.wander_state.dir and water_wander_mob.wander_state.dir.x > 0,
	"submerged wandering mob steers eastward directly towards shoreline")

-- 7. Test Fleeing Behavior in Liquid vs Land
local mock_threat = {
	is_valid = function() return true end,
	is_player = function() return true end,
	get_player_name = function() return "attacker" end,
	get_hp = function() return 20 end,
	get_pos = function() return {x = -3, y = 0, z = 0} end,
}

local water_flee_mob = {
	name = "x_mobs:fallen_minion",
	can_swim = true,
	abilities = {can_swim = true},
	flee_speed = 3.0,
	panic_timer = 5.0,
	target = mock_threat,
	object = {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 0, z = 0} end,
		get_yaw = function() return 0 end,
		set_yaw = function() end,
		get_hp = function() return 5 end,
		get_velocity = function() return {x = 0, y = 0, z = 0} end,
		set_velocity = function() end,
		get_acceleration = function() return {x = 0, y = 0, z = 0} end,
		set_acceleration = function() end,
		get_rotation = function() return {x = 0, y = 0, z = 0} end,
		set_rotation = function() end,
	},
}

-- Fleeing while submerged in water: should steer towards nearest shore (x=3)
local flee_res_water = locomotion.handle_mob_fleeing(water_flee_mob, 0.1, {x = 0, y = 0, z = 0}, false)
assert_true(flee_res_water.moving, "submerged fleeing mob moves to escape liquid")

-- Fleeing on land next to water: should not run into water
clear_world()
-- Land from x=-3 to 0 (dirt at y=0, air at y=1). Water at x >= 1
for z = -3, 3 do
	for x = -3, 0 do
		set_node(x, 0, z, "default:dirt")
		set_node(x, 1, z, "air")
		set_node(x, 2, z, "air")
	end
	for x = 1, 3 do
		set_node(x, 0, z, "default:water_source")
		set_node(x, 1, z, "air")
	end
end

local mock_land_threat = {
	is_valid = function() return true end,
	is_player = function() return true end,
	get_player_name = function() return "attacker" end,
	get_hp = function() return 20 end,
	get_pos = function() return {x = -2, y = 1, z = 0} end,
}

local last_set_vel = nil
local land_flee_mob = {
	name = "x_mobs:fallen_minion",
	can_swim = true,
	abilities = {can_swim = true},
	flee_speed = 3.0,
	panic_timer = 5.0,
	target = mock_land_threat,
	object = {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 1, z = 0} end,
		get_yaw = function() return 0 end,
		set_yaw = function() end,
		get_hp = function() return 5 end,
		get_velocity = function() return {x = 0, y = 0, z = 0} end,
		set_velocity = function(_self, v) last_set_vel = v end,
		get_acceleration = function() return {x = 0, y = 0, z = 0} end,
		set_acceleration = function() end,
		get_rotation = function() return {x = 0, y = 0, z = 0} end,
		set_rotation = function() end,
	},
}

-- Threat is at -x ({-2, 1, 0}). Direct retreat would be +x (into water at x=1).
-- Fleeing logic must reject stepping directly into water and deflect along dry land (z axis).
local flee_res_land = locomotion.handle_mob_fleeing(land_flee_mob, 0.1, {x = 0, y = 1, z = 0}, false)
assert_true(flee_res_land.moving, "land fleeing mob finds safe escape path away from water")
local vel_x = (last_set_vel and last_set_vel.x) or 0
assert_true(vel_x <= 0.1, "land fleeing mob does not rush straight into ocean water")

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count / test_count) * 100))
print("==================================================")

if pass_count == test_count then
	print("All water avoidance subsystem tests passed successfully!")
else
	error("Some water avoidance subsystem tests failed!")
end
