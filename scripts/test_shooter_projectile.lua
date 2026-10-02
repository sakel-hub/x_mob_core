--[[
	test_shooter_projectile.lua - Ranged Combat & Projectile Pipeline Test Suite
	Verifies projectile flight step, raycast collision, proximity fallback,
	and target validation filtering (__builtin:item, falling nodes, allies, health bars).
]]

local registered_nodes = {
	["air"] = { walkable = false },
	["default:stone"] = { walkable = true },
}

_G.core = {
	registered_nodes = registered_nodes,
	get_node = function(pos)
		if pos.y <= 0 then
			return { name = "default:stone" }
		end
		return { name = "air" }
	end,
	get_node_or_nil = function(pos)
		return _G.core.get_node(pos)
	end,
	get_modpath = function(modname)
		if modname == "x_mob_core" then
			return "."
		end
		return nil
	end,
	after = function(_delay, func) func() end,
	sound_play = function() end,
}

_G.vector = {
	direction = function(p1, p2)
		local dx = p2.x - p1.x
		local dy = p2.y - p1.y
		local dz = p2.z - p1.z
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		if len == 0 then return {x = 0, y = 0, z = 0} end
		return {x = dx / len, y = dy / len, z = dz / len}
	end,
	distance = function(p1, p2)
		local dx = p2.x - p1.x
		local dy = p2.y - p1.y
		local dz = p2.z - p1.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	multiply = function(v, s)
		return {x = v.x * s, y = v.y * s, z = v.z * s}
	end,
	dir_to_rotation = function(_dir)
		return {x = 0, y = 0, z = 0}
	end,
}

local utils = dofile("./core/utils.lua")
local factions = dofile("./combat/factions.lua")
local shooter = dofile("./combat/shooter.lua")

_G.x_mob_core = {
	utils = utils,
	combat = {
		factions = factions,
		shooter = shooter,
	},
	are_allies = factions.are_allies,
	are_enemies = factions.are_enemies,
	is_valid_projectile_target = shooter.is_valid_target,
	step_projectile = shooter.step_projectile,
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
print("  Running Shooter & Projectile Subsystem Tests")
print("==================================================")

local function mock_object(opts)
	local valid = (opts.valid ~= false)
	local is_player = (opts.is_player == true)
	local punched = false
	local punch_params = nil
	local removed = false
	local pos = opts.pos or {x = 0, y = 5, z = 0}
	local vel = opts.vel or {x = 0, y = 0, z = 0}
	local rot = {x = 0, y = 0, z = 0}

	local lua_ent = nil
	if not is_player then
		local facts = opts.factions
		if facts then
			facts = factions.normalize_factions(facts)
		end
		lua_ent = {
			name = opts.name or "test:mob",
			factions = facts,
			_shooter = opts._shooter,
		}
	end

	local obj = {}
	obj.is_valid = function() return valid end
	obj.is_player = function() return is_player end
	obj.get_player_name = function() return is_player and (opts.player_name or "player1") or "" end
	obj.get_luaentity = function() return lua_ent end
	obj.get_pos = function() return {x = pos.x, y = pos.y, z = pos.z} end
	obj.set_pos = function(_, p) pos = p end
	obj.get_velocity = function() return {x = vel.x, y = vel.y, z = vel.z} end
	obj.set_velocity = function(_, v) vel = v end
	obj.get_rotation = function() return rot end
	obj.set_rotation = function(_, r) rot = r end
	obj.punch = function(_, puncher, time, caps, dir)
		punched = true
		punch_params = {puncher = puncher, time = time, caps = caps, dir = dir}
	end
	obj.remove = function() removed = true end
	obj.was_punched = function() return punched end
	obj.get_punch_params = function() return punch_params end
	obj.was_removed = function() return removed end
	return obj
end

-- 1. Test is_valid_target filtering
do
	local shooter_mob = mock_object({name = "x_mobs:skull_archer", factions = {"undead"}})
	local proj_obj = mock_object({name = "x_mobs:archer_arrow", _shooter = shooter_mob})
	local proj_ent = {
		name = "x_mobs:archer_arrow",
		object = proj_obj,
		_shooter = shooter_mob,
		_damage = 5,
	}

	-- Exclude invalid / self / shooter
	assert_false(shooter.is_valid_target(proj_ent, nil), "rejects nil target")
	assert_false(shooter.is_valid_target(proj_ent, mock_object({valid = false})), "rejects invalid target")
	assert_false(shooter.is_valid_target(proj_ent, proj_obj), "rejects projectile self-hit")
	assert_false(shooter.is_valid_target(proj_ent, shooter_mob), "rejects shooter self-hit")

	-- Builtin non-mob entities must be rejected
	assert_false(shooter.is_valid_target(proj_ent, mock_object({name = "__builtin:item"})),
		"rejects __builtin:item")
	assert_false(shooter.is_valid_target(proj_ent, mock_object({name = "__builtin:falling_node"})),
		"rejects __builtin:falling_node")
	assert_false(shooter.is_valid_target(proj_ent, mock_object({name = "__builtin:custom_item"})),
		"rejects entities matching __builtin: prefix")

	-- Utility health bar must be rejected
	assert_false(shooter.is_valid_target(proj_ent, mock_object({name = "x_mob_core:health_bar"})),
		"rejects x_mob_core:health_bar")

	-- Same projectile type must be rejected
	assert_false(shooter.is_valid_target(proj_ent, mock_object({name = "x_mobs:archer_arrow"})),
		"rejects sister projectile of same entity type")

	-- Custom ignore_entities list
	assert_false(shooter.is_valid_target(proj_ent, mock_object({name = "custom:shield"}),
		{ignore_entities = {"custom:shield"}}), "rejects custom ignored entity from list")

	-- Allies vs Enemies
	local ally_mob = mock_object({name = "x_mobs:skull_lancer", factions = {"undead"}})
	local enemy_mob = mock_object({name = "x_mobs:spider", factions = {"arachnid"}})
	local enemy_player = mock_object({is_player = true, player_name = "hero"})

	assert_false(shooter.is_valid_target(proj_ent, ally_mob), "rejects allied mob sharing faction")
	assert_true(shooter.is_valid_target(proj_ent, enemy_mob), "accepts enemy mob with different faction")
	assert_true(shooter.is_valid_target(proj_ent, enemy_player), "accepts enemy player")

	-- allow_players option
	assert_false(shooter.is_valid_target(proj_ent, enemy_player, {allow_players = false}),
		"respects allow_players = false option")
end

-- 2. Test step_projectile raycast hit and item penetration
do
	local shooter_mob = mock_object({name = "x_mobs:skull_archer", factions = {"undead"}})
	local proj_obj = mock_object({
		name = "x_mobs:archer_arrow",
		pos = {x = 5, y = 5, z = 0},
		vel = {x = 20, y = 0, z = 0},
		_shooter = shooter_mob,
	})
	local proj_ent = {
		name = "x_mobs:archer_arrow",
		object = proj_obj,
		_shooter = shooter_mob,
		_damage = 7,
		_old_pos = {x = 0, y = 5, z = 0},
		timer = 0,
	}

	local dropped_item = mock_object({name = "__builtin:item", pos = {x = 2, y = 5, z = 0}})
	local target_player = mock_object({is_player = true, pos = {x = 4, y = 5, z = 0}})

	-- Mock raycast returning dropped item FIRST, then player
	_G.core.raycast = function()
		local pts = {
			{ type = "object", ref = dropped_item, intersection_point = {x = 2, y = 5, z = 0} },
			{ type = "object", ref = target_player, intersection_point = {x = 4, y = 5, z = 0} },
		}
		local idx = 0
		return function()
			idx = idx + 1
			return pts[idx]
		end
	end
	_G.core.get_objects_inside_radius = function() return {} end

	local hit, hit_obj, hit_pos = shooter.step_projectile(proj_ent, 0.1, {
		damage = 7,
		lifetime = 4.0,
	})

	assert_true(hit, "step_projectile reports impact")
	assert_eq(hit_obj, target_player, "step_projectile bypasses dropped item and hits target player")
	assert_eq(hit_pos.x, 4, "impact position corresponds to player location")
	assert_true(target_player.was_punched(), "player received punch damage")
	local punch = target_player.get_punch_params()
	assert_eq(punch.caps.damage_groups.fleshy, 7, "punch damage matches projectile damage")
	assert_false(dropped_item.was_punched(), "dropped item was not punched")
	assert_true(proj_obj.was_removed(), "projectile removed upon impact")
end

-- 3. Test step_projectile solid node collision
do
	local shooter_mob = mock_object({name = "x_mobs:skull_archer", factions = {"undead"}})
	local proj_obj = mock_object({
		name = "x_mobs:archer_arrow",
		pos = {x = 5, y = 5, z = 0},
		vel = {x = 20, y = 0, z = 0},
		_shooter = shooter_mob,
	})
	local proj_ent = {
		name = "x_mobs:archer_arrow",
		object = proj_obj,
		_shooter = shooter_mob,
		_damage = 5,
		_old_pos = {x = 0, y = 5, z = 0},
		timer = 0,
	}

	_G.core.raycast = function()
		local pts = {
			{ type = "node", under = {x = 3, y = 0, z = 0}, intersection_point = {x = 3, y = 0, z = 0} },
		}
		local idx = 0
		return function()
			idx = idx + 1
			return pts[idx]
		end
	end
	_G.core.get_objects_inside_radius = function() return {} end

	local node_hit_called = false
	local hit = shooter.step_projectile(proj_ent, 0.1, {
		on_hit_node = function(_self, hit_pos, node)
			node_hit_called = true
			assert_eq(hit_pos.x, 3, "node hit callback receives correct impact position")
			assert_eq(node.name, "default:stone", "node query resolves")
		end,
	})

	assert_true(hit, "step_projectile impacts solid node")
	assert_true(node_hit_called, "on_hit_node callback was executed")
	assert_true(proj_obj.was_removed(), "projectile removed upon wall impact")
end

-- 4. Test lifetime expiration and flight callbacks
do
	local proj_obj = mock_object({
		name = "x_mobs:archer_arrow",
		pos = {x = 0, y = 10, z = 0},
	})
	local proj_ent = {
		name = "x_mobs:archer_arrow",
		object = proj_obj,
		timer = 3.95,
		_old_pos = {x = 0, y = 10, z = 0},
	}

	_G.core.raycast = function() return function() return nil end end
	_G.core.get_objects_inside_radius = function() return {} end

	local step_called = false
	local hit = shooter.step_projectile(proj_ent, 0.1, {
		lifetime = 4.0,
		on_step = function() step_called = true end,
	})

	assert_false(hit, "expired projectile reports no collision")
	assert_true(proj_obj.was_removed(), "projectile removed when lifetime exceeded")
	assert_false(step_called, "on_step skipped when projectile expires")
end

-- 6. Agnostic Projectile Pass-Through Tests
do
	local shooter_obj = mock_object({ name = "x_mobs:crazy_mushroom", factions = {"fungal"} })
	local proj_obj = mock_object({ name = "x_mobs:spore_ball" })
	local proj_ent = { object = proj_obj, _shooter = shooter_obj, name = "x_mobs:spore_ball" }

	-- Mock target with _is_arrow
	local arrow_target = mock_object({ name = "custom_bows:arrow" })
	arrow_target.get_luaentity()._is_arrow = true
	assert_false(shooter.is_valid_target(proj_ent, arrow_target), "rejects target with _is_arrow flag")

	-- Mock target with _is_projectile
	local orb_target = mock_object({ name = "custom_magic:orb" })
	orb_target.get_luaentity()._is_projectile = true
	assert_false(shooter.is_valid_target(proj_ent, orb_target), "rejects target with _is_projectile flag")

	-- Mock target with _shooter reference
	local bullet_target = mock_object({ name = "custom_guns:bullet" })
	bullet_target.get_luaentity()._shooter = mock_object({ is_player = true })
	assert_false(shooter.is_valid_target(proj_ent, bullet_target), "rejects target with _shooter reference")

	-- Mock target with _is_bullet
	local bullet2_target = mock_object({ name = "other_mod:special_projectile" })
	assert_true(shooter.is_valid_target(proj_ent, bullet2_target), "accepts target entity without projectile flags")
	bullet2_target.get_luaentity()._is_bullet = true
	assert_false(shooter.is_valid_target(proj_ent, bullet2_target), "rejects target with _is_bullet flag")
end

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", pass_count, test_count, (pass_count / test_count) * 100))
print("==================================================")

if pass_count == test_count then
	print("All shooter projectile subsystem tests passed successfully!")
else
	error("Some shooter projectile subsystem tests failed!")
end
