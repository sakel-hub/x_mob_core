--[[
	test_swarm_alert.lua - Test Suite for Threat Alerting & Faction Rallying
	Validates:
	1. Faction alliance checking between undead/skeleton mobs
	2. coordination.broadcast_threat rallying same-faction allies into combat
	3. Non-allied mobs are ignored by broadcast_threat
	4. Already engaged allies are not interrupted
	5. Immediate path evaluation via path_state.timer reset
	6. combat_handler.handle_punch triggers threat broadcast when swarm_alert is configured
	7. combat_handler.handle_punch triggers threat broadcast when pack.swarm_alert is true
	8. combat_handler.handle_lethal_death alerts allies on instant kill
]]

local math = math

local core = {
	get_modpath = function(modname)
		if modname == "x_mob_core" then
			return "."
		end
		return nil
	end,
	registered_entities = {},
	registered_nodes = {},
	get_objects_inside_radius = function(_pos, _radius)
		return {}
	end,
	log = function() end,
	serialize = function() return "{}" end,
	deserialize = function() return {} end,
	settings = {
		get = function(_self, _key) return nil end,
		get_bool = function(_self, _key, default) return default end,
	},
	register_entity = function() end,
	sound_play = function() end,
	add_particlespawner = function() end,
	add_entity = function() return nil end,
	after = function(_t, fn) fn() end,
	get_gametime = function() return 100 end,
	get_us_time = function() return 1000000 end,
	dir_to_yaw = function() return 0 end,
	get_node_or_nil = function() return {name = "air"} end,
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
}
_G.vector = vector

local factions = dofile("combat/factions.lua")

-- Mock global x_mob_core for coordination and combat_handler
_G.x_mob_core = {
	are_allies = factions.are_allies,
	are_enemies = factions.are_enemies,
	registered_mobs = {},
	emit = function() end,
	events = {
		listen = function() end,
	},
	motor = {
		safety = {
			check_in_liquid = function() return false end,
		},
	},
	get_damage_multiplier = function() return 1.0 end,
}

local coordination = dofile("pack/coordination.lua")
local combat_handler = dofile("lifecycle/combat_handler.lua")

local passed = 0
local total = 0

local function test(desc, fn)
	total = total + 1
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print("  [PASS] " .. desc)
	else
		print("  [FAIL] " .. desc .. ": " .. tostring(err))
	end
end

local function make_mock_player(name, pos)
	local hp = 20
	local player = {
		_is_player = true,
		_name = name or "singleplayer",
		_pos = pos or {x = 0, y = 0, z = 0},
	}
	player.is_player = function() return true end
	player.is_valid = function() return true end
	player.get_player_name = function(self) return self._name end
	player.get_pos = function(self) return {x = self._pos.x, y = self._pos.y, z = self._pos.z} end
	player.get_hp = function() return hp end
	player.set_hp = function(_, h) hp = h end
	player.get_wielded_item = function()
		return {
			is_empty = function() return true end,
			get_name = function() return "" end,
		}
	end
	return player
end

local function make_mock_mob(name, faction_list, pos)
	local mob_ent = {
		name = name,
		factions = faction_list,
		state = "idle",
		target = nil,
		hp = 20,
		hp_max = 20,
		is_dead = false,
		path_state = { timer = 0 },
	}
	local obj = {
		_is_player = false,
		_pos = pos or {x = 0, y = 0, z = 0},
	}
	obj.is_player = function() return false end
	obj.is_valid = function() return true end
	obj.get_pos = function(self) return {x = self._pos.x, y = self._pos.y, z = self._pos.z} end
	obj.get_luaentity = function() return mob_ent end
	obj.get_velocity = function() return {x = 0, y = 0, z = 0} end
	obj.set_velocity = function() end
	obj.get_armor_groups = function() return {fleshy = 100} end
	obj.set_armor_groups = function() end
	obj.set_properties = function() end
	obj.get_properties = function()
		return { textures = {"test.png"}, collisionbox = {-0.3, 0, -0.3, 0.3, 1.8, 0.3} }
	end
	obj.get_texture_mod = function() return "" end
	obj.set_texture_mod = function() end
	obj.set_hp = function(_, h) mob_ent.hp = h end
	obj.add_velocity = function() end
	obj.set_acceleration = function() end
	obj.get_children = function() return {} end
	obj.get_animations = function() return {} end
	obj.set_animation = function() end
	obj.play_animation = function() end
	obj.set_animation_frame_speed = function() end
	mob_ent.object = obj
	return mob_ent, obj
end

print("==================================================")
print("  Running x_mob_core Alert Allies Test Suite")
print("==================================================")

-- 1. Faction alliance checking
test("Undead and Skeleton factions recognize each other as allies", function()
	local archer, _ = make_mock_mob("x_mobs:skull_archer", {"undead", "skeleton"})
	local lancer, _ = make_mock_mob("x_mobs:skull_lancer", {"undead", "skeleton"})
	local king, _ = make_mock_mob("x_mobs:skull_king", {"undead", "skeleton", "boss"})
	local golem, _ = make_mock_mob("x_mobs:golem", {"stone", "golem", "boss"})

	assert(factions.are_allies(archer, lancer) == true, "archer and lancer should be allies")
	assert(factions.are_allies(archer, king) == true, "archer and king should be allies")
	assert(factions.are_allies(lancer, king) == true, "lancer and king should be allies")
	assert(factions.are_allies(archer, golem) == false, "archer and golem should NOT be allies")
end)

-- 2. Threat broadcast alerts nearby same-faction allies
test("coordination.broadcast_threat rallies idle faction allies", function()
	local victim_ent, victim_obj = make_mock_mob("x_mobs:skull_archer", {"undead", "skeleton"}, {x = 0, y = 0, z = 0})
	local ally_ent, ally_obj = make_mock_mob("x_mobs:skull_lancer", {"undead", "skeleton"}, {x = 5, y = 0, z = 0})
	local player = make_mock_player("Hero", {x = 1, y = 0, z = 0})

	core.get_objects_inside_radius = function(p, rad)
		if vector.distance(p, victim_obj:get_pos()) <= rad then
			return {victim_obj, ally_obj}
		end
		return {}
	end

	coordination.broadcast_threat(victim_ent, player, 16.0, 4)

	assert(ally_ent.target == player, "allied lancer should target the player")
	assert(ally_ent.state == "combat", "allied lancer state should be combat")
	assert(ally_ent.path_state.timer == 99.0, "allied lancer path_state timer should trigger immediate evaluation")
end)

-- 3. Non-allied mobs are ignored by broadcast_threat
test("coordination.broadcast_threat ignores non-allied mobs", function()
	local victim_ent, victim_obj = make_mock_mob("x_mobs:skull_archer", {"undead", "skeleton"}, {x = 0, y = 0, z = 0})
	local stranger_ent, stranger_obj = make_mock_mob("x_mobs:spider", {"insectoid", "spider"}, {x = 5, y = 0, z = 0})
	local player = make_mock_player("Hero", {x = 1, y = 0, z = 0})

	core.get_objects_inside_radius = function(_p, _rad)
		return {victim_obj, stranger_obj}
	end

	coordination.broadcast_threat(victim_ent, player, 16.0, 4)

	assert(stranger_ent.target == nil, "spider should NOT target the player")
	assert(stranger_ent.state == "idle", "spider should remain idle")
end)

-- 4. Already engaged allies are not interrupted
test("coordination.broadcast_threat does not switch targets on already engaged allies", function()
	local victim_ent, victim_obj = make_mock_mob("x_mobs:skull_archer", {"undead", "skeleton"}, {x = 0, y = 0, z = 0})
	local ally_ent, ally_obj = make_mock_mob("x_mobs:skull_lancer", {"undead", "skeleton"}, {x = 5, y = 0, z = 0})
	local existing_target = make_mock_player("FirstPlayer", {x = 10, y = 0, z = 10})
	ally_ent.target = existing_target
	ally_ent.state = "combat"

	local new_attacker = make_mock_player("SecondPlayer", {x = 1, y = 0, z = 0})

	core.get_objects_inside_radius = function(_p, _rad)
		return {victim_obj, ally_obj}
	end

	coordination.broadcast_threat(victim_ent, new_attacker, 16.0, 4)

	assert(ally_ent.target == existing_target, "engaged ally should keep its current target")
end)

-- 5. combat_handler.handle_punch triggers threat broadcast when swarm_alert is configured
test("combat_handler.handle_punch alerts faction allies when swarm_alert is set", function()
	local victim_ent, victim_obj = make_mock_mob("x_mobs:skull_archer", {"undead", "skeleton"}, {x = 0, y = 0, z = 0})
	local ally_ent, ally_obj = make_mock_mob("x_mobs:skull_king", {"undead", "skeleton", "boss"}, {x = 8, y = 0, z = 0})
	local puncher = make_mock_player("Attacker", {x = 2, y = 0, z = 0})

	core.get_objects_inside_radius = function(_p, _rad)
		return {victim_obj, ally_obj}
	end

	local def = {
		swarm_alert = {
			radius = 20.0,
			max_allies = 6,
		},
		damage = 4,
	}

	combat_handler.handle_punch(victim_ent, puncher, 1.0, {}, {x = 1, y = 0, z = 0}, 4, def)

	assert(victim_ent.target == puncher, "victim should target puncher")
	assert(ally_ent.target == puncher, "allied skull king should be alerted to target puncher")
	assert(ally_ent.state == "combat", "allied skull king should enter combat state")
end)

-- 6. combat_handler.handle_punch triggers threat broadcast when pack.swarm_alert is true
test("combat_handler.handle_punch alerts faction allies when pack.swarm_alert is true", function()
	local victim_ent, victim_obj = make_mock_mob("x_mobs:skull_lancer", {"undead", "skeleton"}, {x = 0, y = 0, z = 0})
	local ally_ent, ally_obj = make_mock_mob("x_mobs:skull_archer", {"undead", "skeleton"}, {x = 6, y = 0, z = 0})
	local puncher = make_mock_player("Attacker", {x = 1, y = 0, z = 0})

	core.get_objects_inside_radius = function(_p, _rad)
		return {victim_obj, ally_obj}
	end

	local def = {
		pack = {
			role = "member",
			leader_type = "x_mobs:skull_king",
			swarm_alert = true,
		},
	}

	combat_handler.handle_punch(victim_ent, puncher, 1.0, {}, {x = 1, y = 0, z = 0}, 3, def)

	assert(victim_ent.target == puncher, "victim should target puncher")
	assert(ally_ent.target == puncher, "allied skull archer should be alerted via pack.swarm_alert")
	assert(ally_ent.state == "combat", "allied skull archer should enter combat state")
end)

-- 7. combat_handler.handle_lethal_death alerts allies on instant kill
test("combat_handler.handle_lethal_death alerts faction allies even on lethal strike", function()
	local victim_ent, victim_obj = make_mock_mob("x_mobs:skull_archer", {"undead", "skeleton"}, {x = 0, y = 0, z = 0})
	local ally_ent, ally_obj = make_mock_mob("x_mobs:skull_lancer", {"undead", "skeleton"}, {x = 4, y = 0, z = 0})
	local killer = make_mock_player("Slayer", {x = 1, y = 0, z = 0})

	core.get_objects_inside_radius = function(_p, _rad)
		return {victim_obj, ally_obj}
	end

	local def = {
		swarm_alert = {
			radius = 24.0,
			max_allies = 8,
		},
	}

	-- 100 damage exceeds victim max HP (20)
	combat_handler.handle_punch(victim_ent, killer, 1.0, {}, {x = 1, y = 0, z = 0}, 100, def)

	assert(victim_ent.is_dead == true, "victim should be dead")
	assert(victim_ent.state == "dying", "victim state should be dying")
	assert(ally_ent.target == killer, "allied skull lancer should be alerted even on lethal blow")
	assert(ally_ent.state == "combat", "allied skull lancer should enter combat state")
end)

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", passed, total, (passed / total) * 100))
print("==================================================")
if passed < total then
	os.exit(1)
end
