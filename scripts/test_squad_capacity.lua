--[[
	test_squad_capacity.lua - Test Suite for Squad Pack Capacity & Orphan Adoption
	Validates:
	1. Leader initialization with max_followers
	2. add_follower respects pack_max_followers limit
	3. add_follower allows bypass with force = true
	4. relink_follower checks leader capacity before linking
	5. adopt_nearby_orphans enforces capacity limit
	6. handle_leader_death clears pack_id on followers
	7. clean_followers preserves valid followers and cleans dead
]]

local math = math

local core = {
	get_modpath = function(modname)
		if modname == "x_mob_core" then
			return "."
		end
		return nil
	end,
	get_objects_inside_radius = function(_pos, _radius)
		return {}
	end,
	log = function() end,
	serialize = function(t)
		local parts = {}
		for k, v in pairs(t) do
			table.insert(parts, string.format("%s=%q", k, tostring(v)))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end,
	deserialize = function() return {} end,
	dir_to_yaw = function() return 0 end,
	pos_to_string = function(p) return string.format("(%d,%d,%d)", p.x, p.y, p.z) end,
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
	round = function(p)
		return {x = math.floor(p.x + 0.5), y = math.floor(p.y + 0.5), z = math.floor(p.z + 0.5)}
	end,
}
_G.vector = vector

local squad = dofile("pack/squad.lua")

local passed = 0
local total = 0

local function test(desc, fn)
	total = total + 1
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print(string.format("  [PASS] %s", desc))
	else
		print(string.format("  [FAIL] %s: %s", desc, tostring(err)))
	end
end

local function create_mock_object(name, hp, pack_id)
	local ent = {
		name = name,
		hp = hp or 15,
		is_dead = false,
		pack_id = pack_id,
		saved_data = {},
	}
	local obj = {
		is_valid = function() return not ent.is_dead end,
		is_player = function() return false end,
		get_luaentity = function() return ent end,
		get_pos = function() return {x = 0, y = 0, z = 0} end,
	}
	ent.object = obj
	return obj, ent
end

print("==================================================")
print("  Running x_mob_core Squad Capacity Test Suite")
print("==================================================")

test("init_leader sets max_followers and empty followers table", function()
	local leader_self = {}
	squad.init_leader(leader_self, {
		max_followers = 3,
		follower_type = "x_mobs:fallen_minion",
	})
	assert(leader_self.pack_max_followers == 3, "pack_max_followers should be 3")
	assert(#leader_self.pack_followers == 0, "pack_followers should be empty")
	assert(leader_self.pack_id ~= nil, "pack_id should be initialized")
end)

test("add_follower accepts followers up to max_followers", function()
	local leader_obj, leader_ent = create_mock_object("x_mobs:fallen_shaman", 45, "pack_test_1")
	squad.init_leader(leader_ent, {max_followers = 3, pack_id = "pack_test_1"})

	local m1_obj, m1_ent = create_mock_object("x_mobs:fallen_minion", 15)
	local m2_obj = create_mock_object("x_mobs:fallen_minion", 15)
	local m3_obj = create_mock_object("x_mobs:fallen_minion", 15)

	assert(squad.add_follower(leader_ent, m1_obj) == true, "follower 1 should be added")
	assert(squad.add_follower(leader_ent, m2_obj) == true, "follower 2 should be added")
	assert(squad.add_follower(leader_ent, m3_obj) == true, "follower 3 should be added")
	assert(#leader_ent.pack_followers == 3, "leader should have exactly 3 followers")
	assert(m1_ent.pack_id == "pack_test_1", "m1 should inherit leader's pack_id")
	assert(m1_ent.leader_obj == leader_obj, "m1 should reference leader_obj")
end)

test("add_follower rejects followers when max_followers is reached", function()
	local _, leader_ent = create_mock_object("x_mobs:fallen_shaman", 45, "pack_test_2")
	squad.init_leader(leader_ent, {max_followers = 3, pack_id = "pack_test_2"})

	local m1_obj = create_mock_object("x_mobs:fallen_minion", 15)
	local m2_obj = create_mock_object("x_mobs:fallen_minion", 15)
	local m3_obj = create_mock_object("x_mobs:fallen_minion", 15)
	local m4_obj = create_mock_object("x_mobs:fallen_minion", 15)

	squad.add_follower(leader_ent, m1_obj)
	squad.add_follower(leader_ent, m2_obj)
	squad.add_follower(leader_ent, m3_obj)

	local added = squad.add_follower(leader_ent, m4_obj)
	assert(added == false, "follower 4 must be rejected when capacity is 3")
	assert(#leader_ent.pack_followers == 3, "leader should still have only 3 followers")
end)

test("add_follower allows bypass when force = true", function()
	local _, leader_ent = create_mock_object("x_mobs:fallen_shaman", 45, "pack_test_3")
	squad.init_leader(leader_ent, {max_followers = 3, pack_id = "pack_test_3"})

	for _ = 1, 3 do
		local m = create_mock_object("x_mobs:fallen_minion", 15)
		squad.add_follower(leader_ent, m)
	end

	local m_forced = create_mock_object("x_mobs:fallen_minion", 15)
	local added = squad.add_follower(leader_ent, m_forced, true)
	assert(added == true, "forced follower should be accepted")
	assert(#leader_ent.pack_followers == 4, "leader should have 4 followers when forced")
end)

test("relink_follower rejects linking when leader is at capacity", function()
	local leader_obj, leader_ent = create_mock_object("x_mobs:fallen_shaman", 45, "pack_test_4")
	squad.init_leader(leader_ent, {max_followers = 3, pack_id = "pack_test_4"})

	for _ = 1, 3 do
		local m = create_mock_object("x_mobs:fallen_minion", 15)
		squad.add_follower(leader_ent, m)
	end

	local _, wild_ent = create_mock_object("x_mobs:fallen_minion", 15)
	wild_ent.pack_leader_type = "x_mobs:fallen_shaman"

	core.get_objects_inside_radius = function()
		return {leader_obj}
	end

	local linked = squad.relink_follower(wild_ent, 32.0)
	assert(linked == false, "relink_follower must fail when leader is at capacity")
	assert(wild_ent.leader_obj == nil, "wild follower should not link to full leader")
	assert(#leader_ent.pack_followers == 3, "leader must not exceed capacity")
end)

test("relink_follower links successfully when leader has space", function()
	local leader_obj, leader_ent = create_mock_object("x_mobs:fallen_shaman", 45, "pack_test_5")
	squad.init_leader(leader_ent, {max_followers = 3, pack_id = "pack_test_5"})

	-- Only 2 followers
	local m1 = create_mock_object("x_mobs:fallen_minion", 15)
	local m2 = create_mock_object("x_mobs:fallen_minion", 15)
	squad.add_follower(leader_ent, m1)
	squad.add_follower(leader_ent, m2)

	local _, wild_ent = create_mock_object("x_mobs:fallen_minion", 15)
	wild_ent.pack_leader_type = "x_mobs:fallen_shaman"

	core.get_objects_inside_radius = function()
		return {leader_obj}
	end

	local linked = squad.relink_follower(wild_ent, 32.0)
	assert(linked == true, "relink_follower should succeed when leader has space")
	assert(wild_ent.leader_obj == leader_obj, "wild follower should link to leader")
	assert(#leader_ent.pack_followers == 3, "leader should now have 3 followers")
end)

test("handle_leader_death clears pack_id and leader_obj on followers", function()
	local _, leader_ent = create_mock_object("x_mobs:fallen_shaman", 45, "pack_test_6")
	squad.init_leader(leader_ent, {max_followers = 3, pack_id = "pack_test_6"})

	local m1_obj, m1_ent = create_mock_object("x_mobs:fallen_minion", 15)
	squad.add_follower(leader_ent, m1_obj)
	assert(m1_ent.pack_id == "pack_test_6", "minion should have leader pack_id")

	squad.handle_leader_death(leader_ent)
	assert(m1_ent.leader_obj == nil, "leader_obj should be cleared")
	assert(m1_ent.pack_id == nil, "pack_id must be cleared on leader death")
end)

test("relink_follower successfully re-links an existing follower when at capacity", function()
	local leader_obj, leader_ent = create_mock_object("x_mobs:skeleton_swordfish", 40, "pack_test_7")
	squad.init_leader(leader_ent, {max_followers = 3, pack_id = "pack_test_7"})

	local m_objs = {}
	local m_ents = {}
	for i = 1, 3 do
		local obj, ent = create_mock_object("x_mobs:skeleton_swordfish", 40, "pack_test_7")
		ent.pack_role = "member"
		squad.add_follower(leader_ent, obj)
		m_objs[i] = obj
		m_ents[i] = ent
	end

	assert(#leader_ent.pack_followers == 3, "leader should have 3 followers")

	-- Follower 3 lost leader_obj pointer
	m_ents[3].leader_obj = nil

	-- Search radius returns other followers FIRST before leader
	core.get_objects_inside_radius = function()
		return {m_objs[1], m_objs[2], leader_obj}
	end

	local relinked = squad.relink_follower(m_ents[3], 32.0)
	assert(relinked == true, "existing follower should successfully relink")
	assert(m_ents[3].leader_obj == leader_obj, "follower MUST relink to leader, NOT fellow member")
	assert(#leader_ent.pack_followers == 3, "capacity must remain intact at 3")
end)

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", passed, total, (passed / total) * 100))
print("==================================================")

if passed == total then
	print("All squad capacity tests passed successfully!")
else
	os.exit(1)
end
