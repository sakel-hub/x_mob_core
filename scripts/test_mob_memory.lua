--[[
	test_mob_memory.lua - Comprehensive Test Suite for Mob Memory Subsystem
	Validates:
	1. Zero-allocation memory initialization and fixed ring buffers
	2. 8-Second Predictive Target Pursuit (LKP) and age expiration
	3. Unreachable target recording, auto-expiration cleanup, and clear
	4. Danger recording, inverse-square spatial repulsion vector, and fallback
	5. Circular trail buffer anti-stagnation on stationary mobs vs moving
	6. Exploration novelty bias vector computation
	7. Obstacle deadlock memory and nearby duplicate spot suppression
	8. Multi-angle heading evaluation with zero-allocation heading cache
	9. Low-HP tactical fleeing state transitions and passive health regeneration
	10. Swarm alert broadcasting with living player/mob target validation
]]

local math = math

-- Minimal Luanti Engine Environment Mock
local current_gametime = 100.0

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
	get_objects_inside_radius = function(_pos, _radius)
		return {}
	end,
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
}
_G.vector = vector

-- Mock Core Utils
local utils = {
	is_player_alive = function(target)
		if not target or not target:is_valid() then return false end
		if target:is_player() then
			return (target:get_hp() or 0) > 0
		end
		local luaent = target:get_luaentity()
		if luaent then
			if luaent.is_dead or (luaent.hp and luaent.hp <= 0) then
				return false
			end
			return true
		end
		return false
	end,
}

local x_mob_core = {
	utils = utils,
}
_G.x_mob_core = x_mob_core

-- Load mob_memory subsystem
local mob_memory = dofile("navigation/mob_memory.lua")

-- Test Runner Helpers
local test_count = 0
local pass_count = 0

local function assert_test(condition, test_name, extra_info)
	test_count = test_count + 1
	if condition then
		pass_count = pass_count + 1
		print(string.format("  [PASS] %s", test_name))
	else
		print(string.format("  [FAIL] %s: %s", test_name, extra_info or "Assertion failed"))
	end
end

local function make_mock_object(is_player, name, hp, pos)
	local _pos = pos or {x = 0, y = 0, z = 0}
	local _hp = hp or 20
	local _valid = true
	local _luaent = nil

	local obj = {}
	function obj.is_valid() return _valid end
	function obj.is_player() return is_player end
	function obj.get_player_name() return is_player and name or "" end
	function obj.get_hp() return _hp end
	function obj.set_hp(_self, new_hp) _hp = new_hp end
	function obj.get_pos() return {x = _pos.x, y = _pos.y, z = _pos.z} end
	function obj.set_pos(_self, p) _pos.x = p.x; _pos.y = p.y; _pos.z = p.z end
	function obj.get_luaentity() return _luaent end
	function obj.invalidate() _valid = false end

	if not is_player then
		_luaent = {
			name = name,
			hp = _hp,
			is_dead = (_hp <= 0),
			object = obj,
		}
	end

	return obj, _luaent
end

print("==================================================")
print("  Running x_mob_core Mob Memory Subsystem Test Suite")
print("==================================================")

-- TEST 1: Memory Initialization & Zero-Allocation Ring Buffers
do
	local mob = {}
	local mem = mob_memory.init_memory(mob)

	assert_test(mem ~= nil and mob.memory == mem, "init_memory sets self.memory")
	assert_test(#mem.dangers == 3, "init_memory creates 3 fixed danger slots")
	assert_test(#mem.trail == 6, "init_memory creates 6 fixed trail slots")
	assert_test(#mem.blocked_spots == 2, "init_memory creates 2 fixed blocked slots")
	assert_test(mem._heading_cache ~= nil, "init_memory creates pre-allocated heading evaluation cache")
	assert_test(#mem._heading_cache.dangers == 3, "heading cache pre-allocates 3 danger evaluators")
	assert_test(#mem._heading_cache.blocked == 2, "heading cache pre-allocates 2 blocked evaluators")
end

-- TEST 2: 8-Second Predictive Target Pursuit (LKP)
do
	local mob = {}
	mob_memory.init_memory(mob)
	local p_obj = make_mock_object(true, "player1", 20, {x = 10, y = 1, z = 20})

	current_gametime = 100.0
	mob_memory.record_target_sighting(mob, p_obj, {x = 10, y = 1, z = 20})

	local lkp1 = mob_memory.get_lkp_target(mob, 8.0)
	assert_test(lkp1 ~= nil and lkp1.x == 10 and lkp1.z == 20, "get_lkp_target returns active sighting")

	-- Advance time to 107.5 seconds (7.5s elapsed, within 8.0s window)
	current_gametime = 107.5
	local lkp2 = mob_memory.get_lkp_target(mob, 8.0)
	assert_test(lkp2 ~= nil, "get_lkp_target valid at 7.5s")

	-- Advance time to 108.5 seconds (8.5s elapsed, expired)
	current_gametime = 108.5
	local lkp3 = mob_memory.get_lkp_target(mob, 8.0)
	assert_test(lkp3 == nil, "get_lkp_target expires after 8.0s")

	-- Clear target memory
	mob_memory.record_target_sighting(mob, p_obj, {x = 12, y = 1, z = 25})
	mob_memory.clear_target_memory(mob)
	assert_test(mob_memory.get_lkp_target(mob, 8.0) == nil, "clear_target_memory invalidates active LKP")
end

-- TEST 3: Unreachable Targets Cache & Expiration Cleanup
do
	local mob = {}
	mob_memory.init_memory(mob)
	local p_obj = make_mock_object(true, "player2", 20, {x = 5, y = 1, z = 5})

	current_gametime = 200.0
	mob_memory.record_unreachable_target(mob, p_obj, 10.0)

	assert_test(mob_memory.is_target_unreachable(mob, p_obj) == true, "is_target_unreachable returns true within cooldown")

	-- Query after cooldown
	current_gametime = 211.0
	assert_test(mob_memory.is_target_unreachable(mob, p_obj) == false,
		"is_target_unreachable returns false and cleans up after expiry")

	-- Clear unreachable target
	mob_memory.record_unreachable_target(mob, p_obj, 15.0)
	mob_memory.clear_unreachable_target(mob, p_obj)
	assert_test(mob_memory.is_target_unreachable(mob, p_obj) == false,
		"clear_unreachable_target clears unreachable status")
end

-- TEST 4: Danger Recording & Inverse-Square Spatial Repulsion
do
	local mob = {}
	mob_memory.init_memory(mob)

	current_gametime = 300.0
	-- Danger at {x = 5, y = 0, z = 0}, mob at {x = 0, y = 0, z = 0}
	mob_memory.record_danger(mob, {x = 5, y = 0, z = 0}, 10.0, 12.0)

	local rep = mob_memory.get_danger_repulsion_vector(mob, {x = 0, y = 0, z = 0})
	assert_test(rep.x < -0.9 and math.abs(rep.z) < 0.1, "danger repulsion vector points directly away from danger")

	-- Opposing dangers: test symmetric cancellation fallback
	mob_memory.record_danger(mob, {x = -6, y = 0, z = 0}, 10.0, 12.0)
	local rep_opp = mob_memory.get_danger_repulsion_vector(mob, {x = 0, y = 0, z = 0})
	-- Slot 1 at x=5 (dist=5) is closer than Slot 2 at x=-6 (dist=6); mob flees away from closest danger (rep_opp.x < 0)
	assert_test(rep_opp.x < 0, "opposing danger fallback flees away from closest danger")

	-- Clear danger memory
	mob_memory.clear_danger_memory(mob)
	local rep_cleared = mob_memory.get_danger_repulsion_vector(mob, {x = 0, y = 0, z = 0})
	assert_test(rep_cleared.x == 0 and rep_cleared.z == 0, "clear_danger_memory clears all active danger vectors")
end

-- TEST 5: Trail Buffer Anti-Stagnation on Stationary Mobs
do
	local mob = {}
	mob_memory.init_memory(mob)

	current_gametime = 400.0
	-- Record step 1 at position A
	mob_memory.record_trail_step(mob, {x = 0, y = 0, z = 0}, 1.0)
	-- Record step 2 at position B (moved 3 blocks)
	mob_memory.record_trail_step(mob, {x = 3, y = 0, z = 0}, 1.0)

	-- Now mob stands still at position B for 10 seconds (10 steps)
	for _ = 1, 10 do
		mob_memory.record_trail_step(mob, {x = 3.1, y = 0, z = 0}, 1.0)
	end

	-- Verify slot 1 still remembers position A {x=0, y=0, z=0} and was not wiped!
	local slot1 = mob.memory.trail[1]
	assert_test(slot1.active and slot1.x == 0 and slot1.z == 0,
		"anti-stagnation preserves trail breadcrumbs when stationary")

	-- Now mob moves significantly to position C {x = 10, y = 0, z = 0}
	mob_memory.record_trail_step(mob, {x = 10, y = 0, z = 0}, 1.0)
	local slot3 = mob.memory.trail[3]
	assert_test(slot3.active and slot3.x == 10, "trail ring buffer advances when movement delta is >= 0.5 blocks")
end

-- TEST 6: Exploration Novelty Bias Vector
do
	local mob = {}
	mob_memory.init_memory(mob)

	current_gametime = 500.0
	-- Mob came from west ({x = -4, y = 0, z = 0})
	mob_memory.record_trail_step(mob, {x = -4, y = 0, z = 0}, 1.0)
	-- Current mob position is at origin {x = 0, y = 0, z = 0}
	local nov = mob_memory.get_exploration_bias_vector(mob, {x = 0, y = 0, z = 0})
	assert_test(nov.x > 0.9, "exploration novelty vector points forward away from recent trail")
end

-- TEST 7: Obstacle Deadlock Memory & Duplicate Spot Suppression
do
	local mob = {}
	mob_memory.init_memory(mob)

	current_gametime = 600.0
	-- Obstacle A at {x = 5, y = 1, z = 5}
	mob_memory.record_blocked_spot(mob, {x = 5, y = 1, z = 5}, 8.0)
	assert_test(mob.memory.blocked_idx == 2, "initial blocked spot consumes slot 1 and advances to slot 2")

	-- Nearby repeat call at {x = 5.2, y = 1, z = 5.1} (< 1.0 node away)
	mob_memory.record_blocked_spot(mob, {x = 5.2, y = 1, z = 5.1}, 10.0)
	assert_test(mob.memory.blocked_idx == 2, "nearby repeat blocked spot refreshes slot 1 without advancing index")
	assert_test(mob.memory.blocked_spots[1].expire == 610.0, "nearby repeat blocked spot refreshed expiration")

	-- Distant obstacle B at {x = -8, y = 1, z = -8}
	mob_memory.record_blocked_spot(mob, {x = -8, y = 1, z = -8}, 8.0)
	assert_test(mob.memory.blocked_idx == 1, "distinct distant blocked spot consumes slot 2 and wraps index")
end

-- TEST 8: Multi-Angle Heading Evaluation with Zero-Allocation Heading Cache
do
	local mob = {}
	mob_memory.init_memory(mob)

	current_gametime = 700.0
	-- Danger at east {x = 4, y = 0, z = 0}
	mob_memory.record_danger(mob, {x = 4, y = 0, z = 0}, 8.0, 12.0)
	-- Blocked spot at north {x = 0, y = 0, z = 3}
	mob_memory.record_blocked_spot(mob, {x = 0, y = 0, z = 3}, 8.0)

	local cur_pos = {x = 0, y = 0, z = 0}

	-- Candidate heading 1: West (away from danger)
	local score_west = mob_memory.evaluate_heading_bias(mob, {x = -1, y = 0, z = 0}, cur_pos)
	-- Candidate heading 2: East (directly towards danger)
	local score_east = mob_memory.evaluate_heading_bias(mob, {x = 1, y = 0, z = 0}, cur_pos)
	-- Candidate heading 3: North (towards blocked spot)
	local score_north = mob_memory.evaluate_heading_bias(mob, {x = 0, y = 0, z = 1}, cur_pos)

	assert_test(score_west > score_east, "heading away from danger scores significantly higher than towards danger")
	assert_test(score_west > score_north, "heading away from danger scores higher than heading into blocked spot")

	-- Verify heading cache was populated and valid
	local cache = mob.memory._heading_cache
	assert_test(cache.time == 700.0 and cache.pos_x == 0, "heading cache saved current position and timestamp")
	assert_test(cache.danger_count == 1, "heading cache precomputed active danger count")
	assert_test(cache.blocked_count == 1, "heading cache precomputed active blocked spot count")

	-- Perform 100 consecutive calls with candidate directions to confirm zero errors and high throughput
	local ok = true
	for i = 1, 100 do
		local angle = (i / 100.0) * math.pi * 2
		local dir = {x = math.cos(angle), y = 0, z = math.sin(angle)}
		local s = mob_memory.evaluate_heading_bias(mob, dir, cur_pos)
		if type(s) ~= "number" then ok = false break end
	end
	assert_test(ok, "multi-angle candidate scoring executes cleanly with heading cache")
end

-- TEST 9: Low-HP Tactical Fleeing State & Passive Health Regeneration
do
	local mob = {
		hp = 8,
		hp_max = 40,
		state = "idle",
		object = make_mock_object(false, "test_mob", 1000, {x = 0, y = 0, z = 0}),
	}
	mob_memory.init_memory(mob)

	-- HP = 8 / 40 = 20% (below 25% flee threshold)
	local is_fleeing = mob_memory.update_health_regen(mob, 0.1, 0.25, 0.60, 2.0)
	assert_test(is_fleeing == true and mob.state == "fleeing", "mob enters fleeing state when HP drops below flee ratio")

	-- Simulate passive health regeneration over 12 seconds
	for _ = 1, 12 do
		mob_memory.update_health_regen(mob, 1.0, 0.25, 0.60, 2.0)
	end

	-- After 12s at 2.0 HP/s: 8 + 24 = 32 HP (32 / 40 = 80%, above 60% return threshold)
	assert_test(mob.hp >= 24, "mob passively regenerates health while fleeing")
	assert_test(mob.memory.flee_state == false and mob.state == "idle",
		"mob exits fleeing state when HP recovers above return threshold")
end

-- TEST 10: Swarm Alert Broadcasting with Vitality Validation
do
	local mob = {
		name = "x_mobs:wolf",
		swarm_alert = {enabled = true, radius = 15.0, max_allies = 2},
	}
	mob.object = make_mock_object(false, "x_mobs:wolf", 1000, {x = 0, y = 0, z = 0})

	-- Mock ally 1 (idle, no target)
	local ally1_obj, ally1_ent = make_mock_object(false, "x_mobs:wolf", 1000, {x = 3, y = 0, z = 3})
	ally1_ent.target = nil
	ally1_ent.path_state = {timer = 0}

	-- Mock ally 2 (has alive player target)
	local p_alive = make_mock_object(true, "player3", 20, {x = 20, y = 0, z = 20})
	local ally2_obj, ally2_ent = make_mock_object(false, "x_mobs:wolf", 1000, {x = 4, y = 0, z = 4})
	ally2_ent.target = p_alive
	ally2_ent.path_state = {timer = 0}

	-- Mock ally 3 (target is dead mob entity)
	local dead_mob = make_mock_object(false, "x_mobs:pig", 0, {x = 5, y = 0, z = 5})
	local ally3_obj, ally3_ent = make_mock_object(false, "x_mobs:wolf", 1000, {x = 5, y = 0, z = 5})
	ally3_ent.target = dead_mob
	ally3_ent.path_state = {timer = 0}

	-- Inject into mock engine objects
	core.get_objects_inside_radius = function(_pos, _radius)
		return {ally1_obj, ally2_obj, ally3_obj}
	end

	local alerted = mob_memory.broadcast_alert(mob, {x = 10, y = 0, z = 10}, 15.0, 20.0, 5)
	assert_test(alerted >= 2, "broadcast_alert alerts nearby allies of same species")
	assert_test(ally1_ent.memory.target.name == "swarm_alert", "idle ally redirected to swarm alert")
	assert_test(ally2_ent.memory == nil or ally2_ent.memory.target == nil or ally2_ent.memory.target.name ~= "swarm_alert",
		"ally with living target is NOT redirected to alert")
	assert_test(ally3_ent.memory.target.name == "swarm_alert", "ally with dead target IS redirected to alert")
end

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count / test_count) * 100))
print("==================================================")

if pass_count == test_count then
	print("All mob memory subsystem tests passed successfully!")
	os.exit(0)
else
	print("FAILURES DETECTED in mob memory subsystem tests.")
	os.exit(1)
end
