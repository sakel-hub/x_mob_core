--[[
	test_spider_spawning_and_crawling.lua
	Regression Test Suite for Spider Spawning, Underground Pocket Rejection,
	Crawler Floor-vs-Wall Surface Detection, Collisionbox Depenetration,
	and Buried Entity Suffocation/Recovery.
]]

local passed = 0
local failed = 0

local function assert_eq(desc, actual, expected)
	if actual == expected then
		print("  [PASS] " .. desc)
		passed = passed + 1
	else
		print(string.format("  [FAIL] %s: expected %s, got %s", desc, tostring(expected), tostring(actual)))
		failed = failed + 1
	end
end

local function assert_true(desc, cond)
	if cond then
		print("  [PASS] " .. desc)
		passed = passed + 1
	else
		print("  [FAIL] " .. desc)
		failed = failed + 1
	end
end

-- =========================================================================
-- Mock Luanti Environment
-- =========================================================================
local world_nodes = {}
local default_node_fn = nil

local function key(x, y, z)
	return string.format("%d,%d,%d", x, y, z)
end

local function set_node(x, y, z, name)
	world_nodes[key(x, y, z)] = name
end

local function reset_world(fn)
	world_nodes = {}
	default_node_fn = fn
end

_G.core = {
	registered_nodes = {
		["air"] = { walkable = false },
		["ignore"] = { walkable = false },
		["default:stone"] = { walkable = true, drawtype = "normal" },
		["default:dirt_with_grass"] = { walkable = true, drawtype = "normal" },
		["default:grass_1"] = { walkable = false, drawtype = "plantlike" },
		["default:water_source"] = { walkable = false, liquidtype = "source" },
	},
	registered_entities = {},
	get_node = function(pos)
		local x = math.floor(pos.x + 0.5)
		local y = math.floor(pos.y + 0.5)
		local z = math.floor(pos.z + 0.5)
		local n = world_nodes[key(x, y, z)]
		if n then
			return { name = n }
		end
		if default_node_fn then
			return { name = default_node_fn(x, y, z) }
		end
		return { name = (y <= 0) and "default:stone" or "air" }
	end,
	get_node_or_nil = function(pos)
		local n = _G.core.get_node(pos)
		if n and n.name == "ignore" then
			return n
		end
		return n
	end,
	get_modpath = function(modname)
		if modname == "x_mob_core" then return "." end
		return nil
	end,
	get_item_group = function(name, group)
		if group == "stone" and name == "default:stone" then return 1 end
		if group == "soil" and name == "default:dirt_with_grass" then return 1 end
		if group == "water" and name == "default:water_source" then return 1 end
		return 0
	end,
	get_node_light = function() return 5 end,
	get_natural_light = function() return 5 end,
	get_timeofday = function() return 0.5 end,
	get_biome_data = function() return { biome = 1 } end,
	get_biome_name = function() return "underground" end,
	get_objects_inside_radius = function() return {} end,
	get_connected_players = function() return {} end,
	get_us_time = function() return 0 end,
	hash_node_position = function(pos)
		return string.format("%d,%d,%d", pos.x, pos.y, pos.z)
	end,
	register_globalstep = function() end,
	register_on_generated = function() end,
	register_on_mods_loaded = function() end,
	dir_to_yaw = function(dir)
		return -math.atan2(dir.x or 0, dir.z or 0)
	end,
	yaw_to_dir = function(yaw)
		return { x = -math.sin(yaw), y = 0, z = math.cos(yaw) }
	end,
	line_of_sight = function() return true end,
	is_protected = function() return false end,
	setting_get_pos = function() return nil end,
	settings = { get = function() return nil end },
	log = function() end,
	pos_to_string = function(p)
		return string.format("(%0.2f, %0.2f, %0.2f)", p.x, p.y, p.z)
	end,
	add_entity = function(pos, name)
		return {
			pos = { x = pos.x, y = pos.y, z = pos.z },
			name = name,
			is_valid = function() return true end,
		}
	end,
}
_G.minetest = _G.core

_G.vector = {
	round = function(v)
		return { x = math.floor(v.x + 0.5), y = math.floor(v.y + 0.5), z = math.floor(v.z + 0.5) }
	end,
	distance = function(a, b)
		local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	direction = function(a, b)
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		if len < 1e-6 then return { x = 0, y = 0, z = 0 } end
		return { x = dx / len, y = dy / len, z = dz / len }
	end,
}

_G.Raycast = function(_p1, _p2)
	return function() return nil end
end

local utils = dofile("core/utils.lua")
local node_cache = dofile("motor/node_cache.lua")
local surface = dofile("motor/surface.lua")
local safety = dofile("motor/safety.lua")

_G.x_mob_core = {
	utils = utils,
	registered_mobs = {
		["x_mobs:spider"] = {
			name = "x_mobs:spider",
			collisionbox = { -0.22, 0.0, -0.22, 0.22, 0.28, 0.22 },
			selectionbox = { -0.30, 0.0, -0.30, 0.30, 0.35, 0.30 },
			can_crawl = true,
		},
		["x_mobs:chasm_weaver"] = {
			name = "x_mobs:chasm_weaver",
			collisionbox = { -0.45, 0.0, -0.45, 0.45, 0.45, 0.45 },
			selectionbox = { -0.60, 0.0, -0.60, 0.60, 0.55, 0.60 },
			can_crawl = true,
		},
		["x_mobs:wide_brute"] = {
			name = "x_mobs:wide_brute",
			collisionbox = { -0.65, 0.0, -0.65, 0.65, 1.9, 0.65 },
		},
		["x_mobs:crystal_guardian"] = {
			name = "x_mobs:crystal_guardian",
			collisionbox = { -0.45, -0.7, -0.45, 0.45, 1.1, 0.45 },
		},
	},
	motor = {
		node_cache = node_cache,
		surface = surface,
		safety = safety,
	},
	combat = {
		health_bar = { on_hp_change = function() end },
	},
	indicate_regen = function() end,
}

local mob_memory = dofile("navigation/mob_memory.lua")
_G.x_mob_core.mob_memory = mob_memory
local engine = dofile("spawning/engine.lua")
local conditions = engine.conditions
local environment = dofile("lifecycle/environment.lua")

print("============================================================")
print("  Running Spider Spawning & Crawler Surface Regression Tests")
print("============================================================")

-- =========================================================================
-- 1. Crawler Surface Detection & Floor-Boundary Stability
-- =========================================================================
print("\n--- 1. Crawler Surface Detection & Floor-Boundary Stability ---")
reset_world(function(_x, y, _z)
	return (y <= 0) and "default:stone" or "air"
end)
node_cache.clear()

-- Spider standing on flat stone floor at y = 0 (top face at y = 0.5)
-- Gravity settlement frequently places cy at 0.4999 or 0.49
local surf_exact = surface.find_adjacent_surface({ x = 0, y = 0.5, z = 0 }, nil)
assert_true("Surface detected at y = 0.5 on flat floor", surf_exact ~= nil)
assert_eq("Flat floor at y = 0.5 is classified as 'floor' (not 'wall')",
	surf_exact and surf_exact.surface_type, "floor")

local surf_settled = surface.find_adjacent_surface({ x = 0, y = 0.495, z = 0 }, nil)
assert_true("Surface detected at settled y = 0.495 on flat floor", surf_settled ~= nil)
assert_eq("Flat floor at settled y = 0.495 is classified as 'floor' (not 'wall')",
	surf_settled and surf_settled.surface_type, "floor")
assert_eq("Floor normal Y is +1", surf_settled and surf_settled.normal.y, 1)

-- Even if previous normal was a horizontal wall, hysteresis must NOT mistake the floor at y=0 for a wall
local surf_hyst = surface.find_adjacent_surface({ x = 0, y = 0.495, z = 0 }, { x = -1, y = 0, z = 0 })
assert_eq("Hysteresis on flat floor at y = 0.495 does not misclassify floor neighbor as 'wall'",
	surf_hyst and surf_hyst.surface_type, "floor")

-- Actual wall at x = 1, y = 1 must still be detected as 'wall'
set_node(1, 1, 0, "default:stone")
node_cache.clear()
local surf_wall = surface.find_adjacent_surface({ x = 0.25, y = 0.5, z = 0 }, nil)
assert_eq("Actual vertical wall at (1, 1, 0) is detected as 'wall'", surf_wall and surf_wall.surface_type, "wall")
assert_eq("Wall normal points -X away from wall", surf_wall and surf_wall.normal.x, -1)

-- Transitioning from floor cbox (ymin = 0.0) to wall cbox (ymin = -0.20) must depenetrate upward above floor
local mock_pos = { x = 0.25, y = 0.50, z = 0 }
local mock_cbox = { -0.22, 0.0, -0.22, 0.22, 0.28, 0.22 }
local mock_spider = {
	collisionbox = mock_cbox,
	selectionbox = { -0.30, 0.0, -0.30, 0.30, 0.35, 0.30 },
	object = {
		is_valid = function() return true end,
		get_pos = function() return mock_pos end,
		set_pos = function(_self, p) mock_pos = { x = p.x, y = p.y, z = p.z } end,
		set_acceleration = function() end,
		set_properties = function(_self, props)
			if props.collisionbox then mock_cbox = props.collisionbox end
		end,
	},
}
surface.set_crawler_state(mock_spider, true, { x = -1, y = 0, z = 0 }, mock_pos)
assert_true("Wall cbox applied on wall attachment", mock_spider._has_wall_cbox == true)
assert_true("Spider pos.y depenetrated to >= 0.72 so wall cbox (ymin=-0.20) stays above floor top (0.50)",
	mock_pos.y >= 0.72 and (mock_pos.y + mock_cbox[2]) > 0.50)

-- =========================================================================
-- 2. Spawning Conditions: Sealed Pockets, Headroom & Wide Footprint
-- =========================================================================
print("\n--- 2. Spawning Conditions & Sealed Pocket Rejection ---")
local spider_spawn_def = {
	mob_name = "x_mobs:spider",
	nodes = { "group:stone" },
	min_light = 0,
	max_light = 15,
	active_object_count = 4,
}

-- Case 2.1: Valid open underground cavern (floor y <= 0, air y = 1..4)
reset_world(function(_x, y, _z)
	return (y <= 0) and "default:stone" or "air"
end)
assert_true("Spider spawns on valid open stone cavern floor",
	conditions.check({ x = 0, y = 1, z = 0 }, spider_spawn_def, false))

-- Case 2.2: Unloaded 'ignore' node at spawn pos or below
set_node(0, 1, 0, "ignore")
assert_true("Conditions reject unloaded 'ignore' node at spawn pos",
	not conditions.check({ x = 0, y = 1, z = 0 }, spider_spawn_def, false))
set_node(0, 1, 0, "air")
set_node(0, 0, 0, "ignore")
assert_true("Conditions reject unloaded 'ignore' node below spawn pos",
	not conditions.check({ x = 0, y = 1, z = 0 }, spider_spawn_def, false))

-- Case 2.3: 1x1x1 sealed pocket inside solid stone
reset_world(function(_x, _y, _z)
	return "default:stone"
end)
set_node(0, 1, 0, "air") -- isolated 1x1x1 air pocket inside solid stone
assert_true("Conditions reject 1x1x1 sealed air pocket inside solid stone",
	not conditions.check({ x = 0, y = 1, z = 0 }, spider_spawn_def, true))

-- Case 2.4: 1x2x1 vertical shaft enclosed on all 4 horizontal sides
set_node(0, 2, 0, "air")
assert_true("Conditions reject 1x2x1 vertical shaft enclosed by 4 stone walls",
	not conditions.check({ x = 0, y = 1, z = 0 }, spider_spawn_def, true))

-- Case 2.5: 1-node-high horizontal crack (roof at y = 2 is solid stone)
reset_world(function(_x, y, _z)
	if y <= 0 or y >= 2 then return "default:stone" end
	return "air"
end)
assert_true("Conditions reject 1-node-high horizontal seam with solid stone ceiling at y=2",
	not conditions.check({ x = 0, y = 1, z = 0 }, spider_spawn_def, true))

-- Case 2.6: Wide mob next to a wall (half_width = 0.65 > 0.48)
reset_world(function(_x, y, _z)
	return (y <= 0) and "default:stone" or "air"
end)
set_node(1, 1, 0, "default:stone") -- adjacent wall within wide mob's 0.65 half-width
local brute_spawn_def = {
	mob_name = "x_mobs:wide_brute",
	nodes = { "group:stone" },
	min_light = 0,
	max_light = 15,
	active_object_count = 4,
}
assert_true("Wide mob (half_width=0.65) rejected when adjacent wall would intersect AABB",
	not conditions.check({ x = 0, y = 1, z = 0 }, brute_spawn_def, false))

-- =========================================================================
-- 3. Trickle Spawner Vertical Search & Group Companion Scatter
-- =========================================================================
print("\n--- 3. Trickle Spawner Vertical Search & Group Scatter ---")

-- Case 3.1: Cave ceiling strata (y = 5..20 is solid stone, y = 1..4 is cave air, y <= 0 is stone floor)
reset_world(function(_x, y, _z)
	if y <= 0 or y >= 5 then return "default:stone" end
	return "air"
end)
local found_gy = engine.find_spawn_ground_y(0, 2, 0, 15)
assert_eq("find_spawn_ground_y skips solid cave ceiling (y=5..17) and finds cave floor (y=0)",
	found_gy, 0)

-- Case 3.2: Non-walkable flora at y = 1 above solid ground at y = 0
reset_world(function(_x, y, _z)
	if y <= 0 then return "default:dirt_with_grass" end
	if y == 1 then return "default:grass_1" end
	return "air"
end)
local flora_gy = engine.find_spawn_ground_y(0, 2, 0, 15)
assert_eq("find_spawn_ground_y skips non-walkable flora at y=1 and finds solid ground at y=0",
	flora_gy, 0)

-- Case 3.3: Negative collisionbox ymin offset on spawn (crystal_guardian ymin = -0.7)
reset_world(function(_x, y, _z)
	return (y <= 0) and "default:stone" or "air"
end)
local spawned_entities = {}
_G.core.add_entity = function(pos, name)
	local obj = { pos = { x = pos.x, y = pos.y, z = pos.z }, name = name, is_valid = function() return true end }
	table.insert(spawned_entities, obj)
	return obj
end
engine.spawn_mob_group({ x = 0, y = 1, z = 0 }, {
	mob_name = "x_mobs:crystal_guardian",
	nodes = { "group:stone" },
	group_min = 1,
	group_max = 1,
	active_object_count = 4,
}, "Test")
assert_eq("Crystal guardian spawned once", #spawned_entities, 1)
assert_true("Crystal guardian (ymin=-0.7) spawned with upward Y offset so bottom (-0.7) is above floor top (0.5)",
	spawned_entities[1] and (spawned_entities[1].pos.y - 0.7) > 0.5)

-- =========================================================================
-- 4. Suffocation Detection, Automatic Depenetration & Regen Guard
-- =========================================================================
print("\n--- 4. Suffocation Detection, Depenetration & Regen Guard ---")

-- Case 4.1: Low-profile spider embedded in floor block at y = 0 (pos.y = 0.30, head_y = 0.48, torso_y = 0.44)
-- With open air at y = 1, environment.step should automatically depenetrate the spider upward onto the floor!
reset_world(function(_x, y, _z)
	return (y <= 0) and "default:stone" or "air"
end)
local buried_pos = { x = 0, y = 0.30, z = 0 }
local buried_spider = {
	hp = 20,
	hp_max = 20,
	collisionbox = { -0.22, 0.0, -0.22, 0.22, 0.28, 0.22 },
	on_wall_or_ceiling = true,
	_has_wall_cbox = true,
	object = {
		is_valid = function() return true end,
		get_pos = function() return buried_pos end,
		set_pos = function(_self, p) buried_pos = { x = p.x, y = p.y, z = p.z } end,
		set_acceleration = function() end,
		set_properties = function() end,
	},
}
local dmg_taken = 0
local mock_combat_handler = {
	apply_environmental_damage = function(_self, dmg)
		dmg_taken = dmg_taken + dmg
		return false
	end,
}
environment.step(buried_spider, 0.6, _G.x_mob_core.registered_mobs["x_mobs:spider"], mock_combat_handler)
assert_true("Spider embedded in floor with air above is automatically depenetrated to y >= 0.52",
	buried_pos.y >= 0.52)
assert_eq("Depenetrated spider takes 0 suffocation damage", dmg_taken, 0)
assert_eq("Depenetrated spider resets false wall adherence", buried_spider.on_wall_or_ceiling, false)

-- Case 4.2: Spider completely entombed in solid stone (no adjacent air) takes suffocation damage & cannot regen
reset_world(function(_x, _y, _z)
	return "default:stone"
end)
buried_pos = { x = 0, y = 0.30, z = 0 }
buried_spider.hp = 4
buried_spider.hp_max = 20
buried_spider._def = { health_regen = { enabled = true, rate = 2.0, flee_threshold = 0.5 } }
environment.step(buried_spider, 0.6, _G.x_mob_core.registered_mobs["x_mobs:spider"], mock_combat_handler)
assert_true("Completely entombed spider is flagged _is_suffocating = true", buried_spider._is_suffocating == true)
assert_true("Completely entombed spider takes suffocation damage even with low profile (cbox[5]=0.28)", dmg_taken > 0)

mob_memory.update_health_regen(buried_spider, 1.5)
assert_eq("Suffocating spider does not regenerate health while buried in solid stone", buried_spider.hp, 4)

print("\n============================================================")
print(string.format("  Results: %d Passed, %d Failed", passed, failed))
print("============================================================")
if failed > 0 then
	os.exit(1)
end
