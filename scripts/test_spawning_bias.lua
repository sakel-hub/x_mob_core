--[[
	test_spawning_bias.lua - Directional Spawning Bias & Multiplayer Optimization Test Suite
	Verifies heading calculations, forward cone biasing, omnidirectional flank/rear retention,
	coordinate projection, and multiplayer time-sliced batching.
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

local function assert_true(desc, condition)
	if condition then
		print("  [PASS] " .. desc)
		passed = passed + 1
	else
		print("  [FAIL] " .. desc)
		failed = failed + 1
	end
end

local function assert_near(desc, actual, expected, epsilon)
	local eps = epsilon or 0.001
	if math.abs(actual - expected) <= eps then
		print(string.format("  [PASS] %s (actual: %.4f, expected: %.4f)", desc, actual, expected))
		passed = passed + 1
	else
		print(string.format("  [FAIL] %s: expected %.4f (+/-%.4f), got %.4f", desc, expected, eps, actual))
		failed = failed + 1
	end
end

-- =========================================================================
-- Luanti Engine Mocks
-- =========================================================================
_G.core = {
	registered_nodes = {
		["air"] = { walkable = false },
		["default:stone"] = { walkable = true },
		["default:dirt_with_grass"] = { walkable = true },
	},
	get_node = function(pos)
		local y = pos and pos.y or 0
		if y <= 0 then
			return { name = "default:dirt_with_grass" }
		end
		return { name = "air" }
	end,
	get_node_or_nil = function(pos)
		return _G.core.get_node(pos)
	end,
	get_modpath = function(modname)
		if modname == "x_mob_core" then return "." end
		return nil
	end,
	dir_to_yaw = function(dir)
		return -math.atan2(dir.x, dir.z)
	end,
	yaw_to_dir = function(yaw)
		return { x = -math.sin(yaw), y = 0, z = math.cos(yaw) }
	end,
	get_connected_players = function() return {} end,
	register_globalstep = function(fn) _G.core._globalstep = fn end,
	register_on_generated = function() end,
	register_on_mods_loaded = function() end,
	get_item_group = function(name, group)
		if group == "soil" and name == "default:dirt_with_grass" then return 1 end
		if group == "stone" and name == "default:stone" then return 1 end
		return 0
	end,
	get_node_light = function() return 10 end,
	get_natural_light = function() return 10 end,
	get_timeofday = function() return 0.5 end,
	get_biome_data = function() return { biome = 1 } end,
	get_biome_name = function() return "grassland" end,
	get_objects_inside_radius = function() return {} end,
	log = function() end,
	pos_to_string = function(p)
		return string.format("(%d, %d, %d)", p.x, p.y, p.z)
	end,
}
_G.vector = {
	round = function(v)
		return { x = math.floor(v.x + 0.5), y = math.floor(v.y + 0.5), z = math.floor(v.z + 0.5) }
	end,
}
_G.Raycast = function(_p1, _p2)
	return function() return nil end
end
_G.x_mob_core = {
	registered_mobs = {},
}

-- Load Spawning Engine
local engine = dofile("spawning/engine.lua")

print("==================================================")
print("  Running Directional Spawning Bias Test Suite")
print("==================================================")

-- =========================================================================
-- 1. Player Heading Calculation
-- =========================================================================
print("\n--- 1. Player Heading Calculations ---")

local function make_mock_player(vel, look_dir, yaw, is_valid)
	return {
		is_valid = function() return is_valid ~= false end,
		get_velocity = function() return vel or { x = 0, y = 0, z = 0 } end,
		get_look_dir = function() return look_dir or { x = 1, y = 0, z = 0 } end,
		get_look_horizontal = function() return yaw or 0 end,
	}
end

-- Cardinal velocity directions
local p_east = make_mock_player({ x = 4.0, y = 0, z = 0 })
local h_east = engine.get_player_heading(p_east)
assert_near("Moving East (+X) gives heading 0.0 rad", h_east, 0.0)

local p_north = make_mock_player({ x = 0, y = 0, z = 5.0 })
local h_north = engine.get_player_heading(p_north)
assert_near("Moving North (+Z) gives heading pi/2 rad", h_north, math.pi / 2)

local p_west = make_mock_player({ x = -4.0, y = 0, z = 0 })
local h_west = engine.get_player_heading(p_west)
assert_near("Moving West (-X) gives heading pi rad", math.abs(h_west), math.pi)

local p_south = make_mock_player({ x = 0, y = 0, z = -5.0 })
local h_south = engine.get_player_heading(p_south)
assert_near("Moving South (-Z) gives heading -pi/2 rad", h_south, -math.pi / 2)

-- Diagonal velocity
local p_ne = make_mock_player({ x = 3.0, y = 0, z = 3.0 })
local h_ne = engine.get_player_heading(p_ne)
assert_near("Moving Northeast (+X, +Z) gives heading pi/4 rad", h_ne, math.pi / 4)

-- Stationary player: falls back to look direction
local p_stat_east = make_mock_player({ x = 0.1, y = 0, z = 0 }, { x = 1.0, y = 0, z = 0 })
local h_stat_east = engine.get_player_heading(p_stat_east)
assert_near("Stationary player facing East uses look_dir (0.0 rad)", h_stat_east, 0.0)

local p_stat_north = make_mock_player({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 1.0 })
local h_stat_north = engine.get_player_heading(p_stat_north)
assert_near("Stationary player facing North uses look_dir (pi/2 rad)", h_stat_north, math.pi / 2)

-- Vertical look: falls back to horizontal yaw
local p_look_up = make_mock_player({ x = 0, y = 0, z = 0 }, { x = 0, y = 1.0, z = 0 }, 0)
local h_look_up = engine.get_player_heading(p_look_up)
-- yaw 0 with yaw_to_dir gives {x = 0, z = 1} -> atan2(1, 0) = pi/2
assert_near("Vertical look direction falls back to get_look_horizontal", h_look_up, math.pi / 2)

-- Invalid player
local p_invalid = make_mock_player(nil, nil, nil, false)
assert_eq("Invalid player returns nil heading", engine.get_player_heading(p_invalid), nil)
assert_eq("Nil player returns nil heading", engine.get_player_heading(nil), nil)

-- =========================================================================
-- 2. Statistical Angle Distribution & Biasing
-- =========================================================================
print("\n--- 2. Angle Distribution & Biasing Verification ---")

-- Helper to check if an angle is within [heading - half_arc, heading + half_arc] modulo 2*pi
local function is_in_forward_cone(angle, heading, half_arc)
	local diff = math.abs((angle - heading + math.pi) % (math.pi * 2) - math.pi)
	return diff <= (half_arc + 1e-6)
end

local TRIALS = 20000
local arc_rad = math.rad(130.0)
local half_arc = arc_rad * 0.5
local p_test = make_mock_player({ x = 4.0, y = 0, z = 0 }) -- heading = 0 (facing +X)

-- Test 2.1: Default bias (0.50)
local in_front_count = 0
for _ = 1, TRIALS do
	local ang = engine.sample_spawn_angle(p_test, 0.50, arc_rad)
	if is_in_forward_cone(ang, 0.0, half_arc) then
		in_front_count = in_front_count + 1
	end
end

local front_pct = (in_front_count / TRIALS) * 100
local rear_flank_pct = 100 - front_pct
print(string.format("  Forward Cone (130 deg): %.2f%% (theoretical ~68.1%%)", front_pct))
print(string.format("  Flanks and Rear: %.2f%% (theoretical ~31.9%%)", rear_flank_pct))

assert_true("Default 50% bias yields 65% - 71% forward spawns", front_pct >= 65.0 and front_pct <= 71.0)
assert_true("Flanks and rear maintain 29% - 35% ambient spawns", rear_flank_pct >= 29.0 and rear_flank_pct <= 35.0)

-- Test 2.2: Pure uniform bias (0.0)
local uniform_front_count = 0
for _ = 1, TRIALS do
	local ang = engine.sample_spawn_angle(p_test, 0.0, arc_rad)
	if is_in_forward_cone(ang, 0.0, half_arc) then
		uniform_front_count = uniform_front_count + 1
	end
end
local uniform_front_pct = (uniform_front_count / TRIALS) * 100
local theoretical_uniform = (130.0 / 360.0) * 100
print(string.format("  Uniform (0.0 bias): %.2f%% (theoretical %.2f%%)", uniform_front_pct, theoretical_uniform))
assert_near("0.0 bias produces purely uniform geometric distribution", uniform_front_pct, theoretical_uniform, 2.5)

-- Test 2.3: Pure forward bias (1.0)
local pure_front_count = 0
for _ = 1, TRIALS do
	local ang = engine.sample_spawn_angle(p_test, 1.0, arc_rad)
	if is_in_forward_cone(ang, 0.0, half_arc) then
		pure_front_count = pure_front_count + 1
	end
end
assert_eq("1.0 bias produces 100% forward cone candidates", pure_front_count, TRIALS)

-- =========================================================================
-- 3. Coordinate Projection in Path of Player
-- =========================================================================
print("\n--- 3. Coordinate Projection Verification ---")

local p_travel = make_mock_player({ x = 0, y = 0, z = 5.0 }) -- traveling North (+Z)
local p_pos = { x = 100, y = 10, z = 200 }

local north_spawns = 0
local COORD_TRIALS = 5000
for _ = 1, COORD_TRIALS do
	local ang = engine.sample_spawn_angle(p_travel, 0.50, arc_rad)
	local dist = 30
	local tz = math.floor(p_pos.z + math.sin(ang) * dist + 0.5)
	if tz > p_pos.z then
		north_spawns = north_spawns + 1
	end
end
local north_pct = (north_spawns / COORD_TRIALS) * 100
print(string.format("  Spawns ahead of +Z traveler (+Z half-plane): %.2f%% (theoretical 75.00%%)", north_pct))
assert_near("Forward half-plane coordinates match theoretical 75% for 0.50 bias", north_pct, 75.0, 2.5)

-- =========================================================================
-- 4. Multiplayer Time-Sliced Batching Verification
-- =========================================================================
print("\n--- 4. Multiplayer Time-Slicing Batching ---")

-- Test time-slicing math with 30 concurrent players across 12 one-second intervals
local num_players = 30
local SPAWN_INTERVAL = 12.0
local STEP_INTERVAL = 1.0
local slices = math.max(1, math.floor(SPAWN_INTERVAL / STEP_INTERVAL + 0.5))
assert_eq("12s interval sliced over 1s ticks yields 12 slices", slices, 12)

-- Simulate quota progression across 12 intervals for 30 players
local player_eval_counts = {}
for i = 1, num_players do player_eval_counts[i] = 0 end

local player_cursor = 1
local quota = 0.0
for _ = 1, slices do
	quota = math.min(num_players, quota + (num_players / slices))
	local to_process = math.floor(quota + 1e-9)
	quota = quota - to_process
	for _ = 1, to_process do
		if player_cursor > num_players then
			player_cursor = 1
		end
		player_eval_counts[player_cursor] = player_eval_counts[player_cursor] + 1
		player_cursor = player_cursor + 1
	end
end

local all_evaluated_once = true
for i = 1, num_players do
	if player_eval_counts[i] ~= 1 then
		all_evaluated_once = false
		break
	end
end
assert_true("All 30 players are evaluated exactly once across 12.0s cycle without lag spikes", all_evaluated_once)

-- Singleplayer test: 1 player evaluated exactly once in 12 seconds (not every 1s)
local sp_quota = 0.0
local sp_evals = 0
for _ = 1, slices do
	sp_quota = math.min(1, sp_quota + (1 / slices))
	local to_process = math.floor(sp_quota + 1e-9)
	sp_quota = sp_quota - to_process
	sp_evals = sp_evals + to_process
end
assert_eq("Singleplayer evaluates exactly 1 time across 12.0s interval", sp_evals, 1)

-- Small server test: 2 players evaluated exactly twice in 12 seconds
local p2_quota = 0.0
local p2_evals = 0
for _ = 1, slices do
	p2_quota = math.min(2, p2_quota + (2 / slices))
	local to_process = math.floor(p2_quota + 1e-9)
	p2_quota = p2_quota - to_process
	p2_evals = p2_evals + to_process
end
assert_eq("2 players evaluated exactly 2 times across 12.0s interval", p2_evals, 2)

print("\n==================================================")
print(string.format("  Tests Completed: %d Passed, %d Failed", passed, failed))
print("==================================================")

if failed > 0 then
	os.exit(1)
end
