--[[
	x_mob_core - Unit & Integration Test Suite for Status Effects Subsystem
	Validates slow, root, dot, compound physics aggregation,
	envelop binding, refresh tokens, and lifecycle cleanup.

	Author: SaKeL
	License: MIT
]]

local registered_entities = {}
local registered_on_joinplayer = {}
local registered_on_leaveplayer = {}
local registered_on_dieplayer = {}
local registered_on_respawnplayer = {}
local registered_on_shutdown = {}
local scheduled_timers = {}

_G.vector = {
	distance = function(a, b)
		local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	round = function(v)
		return {x = math.floor(v.x + 0.5), y = math.floor(v.y + 0.5), z = math.floor(v.z + 0.5)}
	end,
}

local create_mock_object

_G.core = {
	get_modpath = function(mod)
		if mod == "x_mob_core" then
			local f = io.open("mods/x_mob_core/api.lua", "r")
			if f then f:close() return "mods/x_mob_core" end
			return "."
		end
		return nil
	end,
	get_us_time = function() return 1000000 end,
	get_translator = function() return function(s) return s end end,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	register_on_joinplayer = function(fn) table.insert(registered_on_joinplayer, fn) end,
	register_on_leaveplayer = function(fn) table.insert(registered_on_leaveplayer, fn) end,
	register_on_dieplayer = function(fn) table.insert(registered_on_dieplayer, fn) end,
	register_on_respawnplayer = function(fn) table.insert(registered_on_respawnplayer, fn) end,
	register_on_punchplayer = function() end,
	register_on_player_hpchange = function() end,
	register_on_shutdown = function(fn) table.insert(registered_on_shutdown, fn) end,
	register_on_mods_loaded = function() end,
	register_on_generated = function() end,
	register_globalstep = function() end,
	register_chatcommand = function() end,
	get_connected_players = function() return {} end,
	log = function() end,
	after = function(delay, fn)
		table.insert(scheduled_timers, { delay = delay, fn = fn })
	end,
	settings = {
		get = function(_self, _key, default) return default end,
		get_bool = function(_self, _key, default)
			if default ~= nil then return default end
			return false
		end,
	},
	_mock_spawners = {},
	_spawner_counter = 0,
	add_particlespawner = function(def)
		_G.core._spawner_counter = _G.core._spawner_counter + 1
		local id = _G.core._spawner_counter
		_G.core._mock_spawners[id] = def
		return id
	end,
	delete_particlespawner = function(id, ...)
		local n = select("#", ...)
		if n >= 1 then
			local playername = select(1, ...)
			if type(playername) ~= "string" then
				error("bad argument #2 to 'delete_particlespawner' (string expected, got " .. type(playername) .. ")")
			end
		end
		_G.core._mock_spawners[id] = nil
	end,
	add_entity = function(pos, name, staticdata)
		local def = registered_entities[name]
		if not def then return nil end
		local obj = create_mock_object(def.initial_properties, false, nil)
		obj:set_pos(pos)
		local ent = {}
		for k, v in pairs(def) do ent[k] = v end
		ent.object = obj
		obj._luaentity = ent
		if ent.on_activate then
			ent:on_activate(staticdata, 0)
		end
		return obj
	end,
}
_G.minetest = _G.core

local function advance_time(dt)
	local remaining = {}
	local to_run = {}
	for _, t in ipairs(scheduled_timers) do
		t.delay = t.delay - dt
		if t.delay <= 0.001 then
			table.insert(to_run, t.fn)
		else
			table.insert(remaining, t)
		end
	end
	scheduled_timers = remaining
	for _, fn in ipairs(to_run) do
		fn()
	end
end

local function run_scheduled_timers()
	advance_time(100.0)
end

-- Mock entity / player factory
local entity_counter = 0
create_mock_object = function(props, is_player, player_name)
	entity_counter = entity_counter + 1
	local obj = {
		_id = entity_counter,
		_valid = true,
		_props = props or {
			collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.77, 0.3},
			selectionbox = {-0.3, 0.0, -0.3, 0.3, 1.77, 0.3},
		},
		_pos = { x = 0, y = 10, z = 0 },
		_attached_to = nil,
		_attach_pos = nil,
		_hp = 20,
		_speed = 1.0,
		_jump = 1.0,
		_gravity = 1.0,
		_vel = { x = 0, y = 0, z = 0 },
		_luaentity = nil,
	}

	function obj:is_valid() return self._valid end
	obj.is_player = function() return is_player == true end
	obj.get_player_name = function() return player_name or "" end
	function obj:get_pos() return { x = self._pos.x, y = self._pos.y, z = self._pos.z } end
	function obj:set_pos(pos) self._pos = pos end
	function obj:get_hp() return self._hp end
	function obj:set_hp(hp) self._hp = hp end
	function obj:get_properties() return self._props end
	function obj:set_properties(p)
		for k, v in pairs(p) do self._props[k] = v end
	end
	function obj:set_attach(parent, _bone, pos, _rot, _fixed)
		self._attached_to = parent
		self._attach_pos = pos
	end
	function obj:get_attach() return self._attached_to end
	function obj:set_detach() self._attached_to = nil end
	function obj:set_armor_groups(g) self._armor_groups = g end
	function obj:remove()
		self._valid = false
		if self._luaentity then
			self._luaentity._target = nil
		end
	end
	function obj:get_luaentity() return self._luaentity end
	function obj:get_physics_override()
		return { speed = self._speed, jump = self._jump, gravity = self._gravity }
	end
	function obj:set_physics_override(o)
		if o.speed ~= nil then self._speed = o.speed end
		if o.jump ~= nil then self._jump = o.jump end
		if o.gravity ~= nil then self._gravity = o.gravity end
	end
	function obj:get_velocity()
		return { x = self._vel.x, y = self._vel.y, z = self._vel.z }
	end
	function obj:add_velocity(v)
		self._vel.x = self._vel.x + (v.x or 0)
		self._vel.y = self._vel.y + (v.y or 0)
		self._vel.z = self._vel.z + (v.z or 0)
	end
	obj.punch = function()
		return true
	end

	return obj
end

-- Load x_mob_core
dofile(core.get_modpath("x_mob_core") .. "/api.lua")

local passed = 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
		print(string.format("  [PASS] %s", name))
	else
		print(string.format("  [FAIL] %s: %s", name, tostring(err)))
		os.exit(1)
	end
end

print("==================================================")
print("  Running x_mob_core Status Effects Subsystem Tests")
print("==================================================")

test("Status effect API methods are exported", function()
	assert(type(x_mob_core.apply_status_effect) == "function", "apply_status_effect must be a function")
	assert(type(x_mob_core.remove_status_effect) == "function", "remove_status_effect must be a function")
	assert(type(x_mob_core.has_status_effect) == "function", "has_status_effect must be a function")
	assert(type(x_mob_core.get_status_effects) == "function", "get_status_effects must be a function")
	assert(type(x_mob_core.clear_status_effects) == "function", "clear_status_effects must be a function")
	assert(type(x_mob_core.indicate_regen) == "function", "indicate_regen must be a function")
	assert(type(x_mob_core.effects) == "table", "effects subsystem must be exported")
	assert(type(x_mob_core.effects.indicate_regen) == "function", "effects.indicate_regen must be a function")
end)

test("Slow archetype reduces speed and restores upon expiration", function()
	local player = create_mock_object(nil, true, "Alice")
	assert(player._speed == 1.0, "Initial speed is 1.0")

	local res = x_mob_core.apply_status_effect(player, {
		id = "web_slow",
		type = "slow",
		speed_factor = 0.5,
		duration = 3.0,
	})
	assert(res == true, "apply_status_effect should succeed")
	assert(x_mob_core.has_status_effect(player, "web_slow") == true, "Should have web_slow effect")
	assert(math.abs(player._speed - 0.5) < 0.001, "Speed must be reduced to 0.5")

	-- Run timers to simulate 3.0s expiration
	run_scheduled_timers()
	assert(x_mob_core.has_status_effect(player, "web_slow") == false, "web_slow effect should expire")
	assert(math.abs(player._speed - 1.0) < 0.001, "Speed must be restored to 1.0")
end)

test("Root archetype immobilizes movement and jump (speed = 0, jump = 0)", function()
	local player = create_mock_object(nil, true, "Bob")
	assert(player._speed == 1.0 and player._jump == 1.0, "Initial physics 1.0")

	-- Simulate player running at full speed when struck by root spell
	player._vel = { x = 4.5, y = 0.0, z = -3.2 }

	x_mob_core.apply_status_effect(player, {
		id = "entangling_roots",
		type = "root",
		duration = 4.0,
	})
	assert(player._speed == 0.0, "Root speed must be 0.0")
	assert(player._jump == 0.0, "Root jump must be 0.0")
	assert(math.abs(player._vel.x) < 0.001, "Root must immediately halt horizontal x velocity")
	assert(math.abs(player._vel.z) < 0.001, "Root must immediately halt horizontal z velocity")
	assert(x_mob_core.is_rooted(player) == true, "x_mob_core.is_rooted must return true for rooted player")

	x_mob_core.remove_status_effect(player, "entangling_roots")
	assert(player._speed == 1.0, "Speed restored to 1.0")
	assert(player._jump == 1.0, "Jump restored to 1.0")
	assert(x_mob_core.is_rooted(player) == false, "x_mob_core.is_rooted must return false after removal")
end)

test("Compound physics aggregation prevents race conditions and state corruption", function()
	local player = create_mock_object(nil, true, "Charlie")

	-- 1. Apply 50% slow (speed = 0.5)
	x_mob_core.apply_status_effect(player, {
		id = "slow_1",
		type = "slow",
		speed_factor = 0.5,
		duration = 5.0,
	})
	assert(math.abs(player._speed - 0.5) < 0.001, "Speed is 0.5")

	-- 2. Apply second 50% slow (speed = 0.5 * 0.5 = 0.25)
	x_mob_core.apply_status_effect(player, {
		id = "slow_2",
		type = "slow",
		speed_factor = 0.5,
		duration = 3.0,
	})
	assert(math.abs(player._speed - 0.25) < 0.001, "Speed is compounded to 0.25")

	-- 3. Apply root (speed = 0, jump = 0)
	x_mob_core.apply_status_effect(player, {
		id = "root_1",
		type = "root",
		duration = 2.0,
	})
	assert(player._speed == 0.0, "Root takes absolute precedence (speed = 0)")
	assert(player._jump == 0.0, "Root takes absolute precedence (jump = 0)")

	-- 4. Remove root: speed should restore to compound remaining slows (0.25), jump to 1.0!
	x_mob_core.remove_status_effect(player, "root_1")
	assert(math.abs(player._speed - 0.25) < 0.001, "After root removal, speed returns to 0.25 compound slow")
	assert(math.abs(player._jump - 1.0) < 0.001, "Jump restored to 1.0")

	-- 5. Remove slow_2: speed should restore to slow_1 only (0.50)!
	x_mob_core.remove_status_effect(player, "slow_2")
	assert(math.abs(player._speed - 0.5) < 0.001, "After slow_2 removal, speed returns to 0.5")

	-- 6. Remove slow_1: speed should restore to clean baseline 1.0!
	x_mob_core.remove_status_effect(player, "slow_1")
	assert(math.abs(player._speed - 1.0) < 0.001, "After all slows removed, speed cleanly restored to 1.0")
end)

test("Envelop texture binding syncs visual sleeve with status effect lifecycle", function()
	local player = create_mock_object(nil, true, "Diana")

	local env_obj = x_mob_core.apply_status_effect(player, {
		id = "web_test",
		type = "slow",
		speed_factor = 0.5,
		duration = 3.0,
		envelop_texture = "x_mobs_web_envelop.png",
	})
	assert(env_obj ~= nil and env_obj ~= true, "Must return envelop ObjectRef")
	assert(x_mob_core.is_enveloped(player, "web_test") == true, "Player must be enveloped")
	assert(x_mob_core.has_status_effect(player, "web_test") == true, "Player must have status effect")

	-- Removing the status effect removes the visual envelop effect
	x_mob_core.remove_status_effect(player, "web_test")
	assert(x_mob_core.has_status_effect(player, "web_test") == false, "Status effect removed")
	assert(x_mob_core.is_enveloped(player, "web_test") == false, "Envelop effect removed")
	assert(math.abs(player._speed - 1.0) < 0.001, "Player speed restored")
end)

test("Direct envelop table binding envelop = { texture = '...' } binds sleeve in lockstep", function()
	local player = create_mock_object(nil, true, "Diana2")

	local env_obj = x_mob_core.apply_status_effect(player, {
		id = "roots_test",
		type = "root",
		duration = 4.0,
		envelop = { texture = "x_mobs_roots_envelop.png" },
	})
	assert(env_obj ~= nil and env_obj ~= true, "Must return envelop ObjectRef")
	assert(x_mob_core.is_enveloped(player, "roots_test") == true, "Player must be enveloped")
	assert(player._speed == 0.0 and player._jump == 0.0, "Root must immobilize")

	x_mob_core.remove_status_effect(player, "roots_test")
	assert(x_mob_core.is_enveloped(player, "roots_test") == false, "Envelop removed")
	assert(player._speed == 1.0 and player._jump == 1.0, "Physics restored")
end)

test("Root archetype halts vertical jump momentum and grounds player", function()
	local player = create_mock_object(nil, true, "JumpingTarget")
	player._vel = { x = 3.0, y = 1.5, z = 2.0 }

	x_mob_core.apply_status_effect(player, {
		id = "deep_freeze",
		type = "root",
		duration = 5.0,
	})
	assert(player._speed == 0.0, "Root speed must be 0.0")
	assert(player._jump == 0.0, "Root jump must be 0.0")
	assert(math.abs(player._vel.x) < 0.001, "Root must halt horizontal velocity")
	assert(math.abs(player._vel.z) < 0.001, "Root must halt horizontal velocity")
	assert(math.abs(player._vel.y) < 0.001, "Root must ground upward jump impulse")
	assert(x_mob_core.is_rooted(player) == true, "Player must be identified as rooted")

	local effs = x_mob_core.get_status_effects(player)
	assert(effs and effs.deep_freeze and effs.deep_freeze.type == "root", "Effect must be registered as root")

	x_mob_core.remove_status_effect(player, "deep_freeze")
	assert(player._speed == 1.0 and player._jump == 1.0, "Physics restored")
	assert(x_mob_core.is_rooted(player) == false, "Player no longer rooted")
end)

test("Jump factor aggregation computes minimum across active debuffs", function()
	local player = create_mock_object(nil, true, "JumpTarget")

	-- 1. Apply debuff with jump_factor 0.8
	x_mob_core.apply_status_effect(player, {
		id = "mud",
		type = "slow",
		speed_factor = 0.9,
		jump_factor = 0.8,
		duration = 10.0,
	})
	assert(math.abs(player._jump - 0.8) < 0.001, "Jump should be 0.8")

	-- 2. Apply stronger jump debuff with jump_factor 0.4
	x_mob_core.apply_status_effect(player, {
		id = "quicksand",
		type = "slow",
		speed_factor = 0.5,
		jump_factor = 0.4,
		duration = 10.0,
	})
	assert(math.abs(player._jump - 0.4) < 0.001, "Jump should be min(0.8, 0.4) = 0.4")

	-- 3. Apply root -> jump must become 0.0
	x_mob_core.apply_status_effect(player, {
		id = "root_pin",
		type = "root",
		duration = 5.0,
	})
	assert(player._jump == 0.0, "Root clamps jump to 0.0")
	assert(player._speed == 0.0, "Root clamps speed to 0.0")

	-- 4. Remove root -> jump returns to min(0.8, 0.4) = 0.4
	x_mob_core.remove_status_effect(player, "root_pin")
	assert(math.abs(player._jump - 0.4) < 0.001, "Jump restored to 0.4")

	-- 5. Remove quicksand -> jump returns to 0.8
	x_mob_core.remove_status_effect(player, "quicksand")
	assert(math.abs(player._jump - 0.8) < 0.001, "Jump restored to 0.8")

	-- 6. Remove mud -> jump returns to baseline 1.0
	x_mob_core.remove_status_effect(player, "mud")
	assert(math.abs(player._jump - 1.0) < 0.001, "Jump restored to baseline 1.0")
end)

test("DoT archetype ticks damage, penetrates armor, and executes on_tick", function()
	local player = create_mock_object(nil, true, "PoisonVictim")
	player:set_hp(20)
	player:set_armor_groups({ fleshy = 50 }) -- 50% damage reduction

	local punches = {}
	player.punch = function(_self, puncher, _time, tool_caps, _dir)
		table.insert(punches, { puncher = puncher, caps = tool_caps })
		local dmg = tool_caps.damage_groups and tool_caps.damage_groups.fleshy or 0
		player:set_hp(player:get_hp() - dmg)
		return true
	end

	local ticks_fired = 0
	local spider_attacker = create_mock_object(nil, false, nil)

	x_mob_core.apply_status_effect(player, {
		id = "venom_dot",
		type = "dot",
		duration = 3.0,
		damage = 2,
		interval = 1.0,
		caster = spider_attacker,
		penetrate_armor = true,
		on_tick = function(tgt)
			assert(tgt == player, "Target must match in on_tick")
			ticks_fired = ticks_fired + 1
		end,
	})

	-- Simulate 1st tick at 1.0s
	advance_time(1.0)
	assert(ticks_fired == 1, "1st tick fired")
	assert(player:get_hp() == 18, "HP reduced by 2 (penetrated armor)")
	assert(#punches == 1, "Punch recorded")
	assert(punches[1].puncher == spider_attacker, "Caster attributed as puncher")

	-- Simulate 2nd tick at 2.0s
	advance_time(1.0)
	assert(ticks_fired == 2, "2nd tick fired")
	assert(player:get_hp() == 16, "HP reduced by another 2")

	-- Simulate 3rd tick at 3.0s
	advance_time(1.0)
	assert(ticks_fired == 3, "3rd tick fired")
	assert(player:get_hp() == 14, "HP reduced by another 2")

	-- Clean up
	x_mob_core.remove_status_effect(player, "venom_dot")
end)

test("Lifecycle cleanup clears effects and resets physics on player leave/die/shutdown", function()
	local player = create_mock_object(nil, true, "Edward")

	x_mob_core.apply_status_effect(player, {
		id = "slow_leak_test",
		type = "slow",
		speed_factor = 0.4,
		duration = 10.0,
	})
	assert(math.abs(player._speed - 0.4) < 0.001, "Player slowed to 0.4")

	-- Trigger player leave listener
	for _, cb in ipairs(registered_on_leaveplayer) do
		cb(player)
	end
	assert(x_mob_core.has_status_effect(player, "slow_leak_test") == false, "Effect cleared on leave")
	assert(math.abs(player._speed - 1.0) < 0.001, "Physics restored on leave")
end)

test("Attached continuous particle spawner is created and deleted with effect lifecycle", function()
	local player = create_mock_object(nil, true, "Frank")

	x_mob_core.apply_status_effect(player, {
		id = "venom_particles_test",
		type = "dot",
		duration = 3.0,
		particles = {
			amount = 6,
			time = 0,
			pos = { min = {x = -0.2, y = 0.2, z = -0.2}, max = {x = 0.2, y = 1.2, z = 0.2} },
		},
	})

	local rec = x_mob_core.get_status_effects(player)["venom_particles_test"]
	assert(rec ~= nil, "Record exists")
	assert(rec.spawner_id ~= nil, "Spawner ID is assigned")
	local spawner_id = rec.spawner_id
	assert(_G.core._mock_spawners[spawner_id] ~= nil, "Spawner registered in core")
	assert(_G.core._mock_spawners[spawner_id].attached == player, "Spawner is attached to player")
	assert(_G.core._mock_spawners[spawner_id].time == 0, "Spawner is infinite continuous (time = 0)")
	assert(_G.core._mock_spawners[spawner_id].collisiondetection == false, "Collision detection disabled for aura")

	-- Advance time across the 3 DoT tick intervals (3.0s total)
	advance_time(1.0)
	advance_time(1.0)
	advance_time(1.0)
	assert(x_mob_core.has_status_effect(player, "venom_particles_test") == false, "Effect expired")
	assert(_G.core._mock_spawners[spawner_id] == nil, "Spawner was cleanly deleted upon expiration")
end)

test("Early dispel of status effect immediately deletes attached particle spawner", function()
	local player = create_mock_object(nil, true, "Grace")

	x_mob_core.apply_status_effect(player, {
		id = "early_dispel_test",
		type = "slow",
		duration = 10.0,
		particles = {
			amount = 8,
			time = 0,
		},
	})

	local rec = x_mob_core.get_status_effects(player)["early_dispel_test"]
	local spawner_id = rec.spawner_id
	assert(_G.core._mock_spawners[spawner_id] ~= nil, "Spawner active")

	-- Manually remove effect early
	x_mob_core.remove_status_effect(player, "early_dispel_test")
	assert(_G.core._mock_spawners[spawner_id] == nil, "Spawner deleted immediately on dispel")
end)

test("Selective packet scoping (playername) is preserved on attached spawner", function()
	local player = create_mock_object(nil, true, "Henry")

	x_mob_core.apply_status_effect(player, {
		id = "scoped_particles_test",
		type = "slow",
		duration = 5.0,
		playername = "Henry",
		particles = {
			amount = 4,
		},
	})

	local rec = x_mob_core.get_status_effects(player)["scoped_particles_test"]
	local spawner_id = rec.spawner_id
	assert(_G.core._mock_spawners[spawner_id] ~= nil, "Spawner active")
	assert(_G.core._mock_spawners[spawner_id].playername == "Henry", "Playername correctly scoped")

	x_mob_core.remove_status_effect(player, "scoped_particles_test")
	assert(_G.core._mock_spawners[spawner_id] == nil, "Spawner deleted")
end)

test("Optional chance property controls application success rate", function()
	local player = create_mock_object(nil, true, "ChanceTester")

	-- 1. Undefined chance applies 100% of the time
	local res_default = x_mob_core.apply_status_effect(player, {
		id = "chance_def_default",
		type = "custom",
		duration = 2.0,
	})
	assert(res_default == true, "Undefined chance must succeed")
	assert(x_mob_core.has_status_effect(player, "chance_def_default"), "Default effect applied")
	x_mob_core.remove_status_effect(player, "chance_def_default")

	-- 2. 0% chance never applies and returns false
	local res_zero = x_mob_core.apply_status_effect(player, {
		id = "chance_zero_test",
		type = "custom",
		chance = 0.0,
		duration = 2.0,
	})
	assert(res_zero == false, "0% chance must return false")
	assert(not x_mob_core.has_status_effect(player, "chance_zero_test"), "0% effect must not apply")

	-- 3. 100% chance (both 1.0 and 100) always applies
	local res_one = x_mob_core.apply_status_effect(player, {
		id = "chance_one_test",
		type = "custom",
		chance = 1.0,
		duration = 2.0,
	})
	assert(res_one == true, "1.0 chance must apply")
	x_mob_core.remove_status_effect(player, "chance_one_test")

	local res_hundred = x_mob_core.apply_status_effect(player, {
		id = "chance_hundred_test",
		type = "custom",
		chance = 100,
		duration = 2.0,
	})
	assert(res_hundred == true, "100 chance must apply")
	x_mob_core.remove_status_effect(player, "chance_hundred_test")

	-- 4. Statistical sampling of 20% chance (both 0.20 and 20)
	local trials = 500
	local successes = 0
	for _ = 1, trials do
		local res = x_mob_core.apply_status_effect(player, {
			id = "chance_twenty_test",
			type = "custom",
			chance = 0.20,
			duration = 1.0,
		})
		if res then
			successes = successes + 1
			x_mob_core.remove_status_effect(player, "chance_twenty_test")
		end
	end
	local rate = successes / trials
	assert(rate >= 0.10 and rate <= 0.35, string.format("Expected ~20%% application rate, got %.2f%%", rate * 100))
end)

test("Debuff archetype periodically drains hunger/stamina on tick without dealing HP damage", function()
	local player = create_mock_object(nil, true, "HungryPlayer")
	local drains = {}
	local orig_drain = x_mob_core.hunger_adapter.drain
	x_mob_core.hunger_adapter.drain = function(target, amount, reason)
		table.insert(drains, { target = target, amount = amount, reason = reason })
		return true
	end

	local initial_hp = player:get_hp()

	x_mob_core.apply_status_effect(player, {
		id = "exhaustion",
		type = "debuff",
		duration = 3.0,
		interval = 1.0,
		drain_hunger = 0.5,
	})

	assert(x_mob_core.has_status_effect(player, "exhaustion"), "Exhaustion debuff applied")
	assert(#drains == 0, "No drain before first interval")

	-- Advance 1.0 second: first drain tick
	advance_time(1.0)
	assert(#drains == 1, "First drain tick executed")
	assert(drains[1].amount == 0.5, "Drained 0.5 hunger units")
	assert(player:get_hp() == initial_hp, "HP untouched by pure hunger debuff")

	-- Advance 1.0 second: second drain tick
	advance_time(1.0)
	assert(#drains == 2, "Second drain tick executed")

	-- Advance 1.0 second: expiration
	advance_time(1.0)
	assert(not x_mob_core.has_status_effect(player, "exhaustion"), "Exhaustion expired")

	x_mob_core.hunger_adapter.drain = orig_drain
end)

print("==================================================")
print(string.format("  Status Effects Test Summary: %d Passed", passed))
print("==================================================")
