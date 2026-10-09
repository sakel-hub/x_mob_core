--[[
	x_mob_core - Unit & Integration Test Suite for Buffs & Positive Effects Subsystem
	Validates preset registration, positive effect multipliers, cleanse/dispel,
	thorns, knockback resilience, damage scaling, pack buffs, and declarative pipeline integration.

	Author: SaKeL
	License: MIT
]]

local registered_entities = {}
local registered_on_joinplayer = {}
local registered_on_leaveplayer = {}
local registered_on_dieplayer = {}
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
	direction = function(from, to)
		local d = {x = to.x - from.x, y = to.y - from.y, z = to.z - from.z}
		local len = math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
		if len == 0 then return {x = 0, y = 0, z = 0} end
		return {x = d.x / len, y = d.y / len, z = d.z / len}
	end,
	multiply = function(v, s)
		return {x = v.x * s, y = v.y * s, z = v.z * s}
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
	registered_entities = registered_entities,
	register_on_joinplayer = function(fn) table.insert(registered_on_joinplayer, fn) end,
	register_on_leaveplayer = function(fn) table.insert(registered_on_leaveplayer, fn) end,
	register_on_dieplayer = function(fn) table.insert(registered_on_dieplayer, fn) end,
	register_on_respawnplayer = function() end,
	register_on_punchplayer = function() end,
	register_on_player_hpchange = function() end,
	register_on_shutdown = function(fn) table.insert(registered_on_shutdown, fn) end,
	register_on_mods_loaded = function() end,
	register_on_generated = function() end,
	register_globalstep = function() end,
	register_chatcommand = function() end,
	get_connected_players = function() return {} end,
	get_objects_inside_radius = function() return {} end,
	log = function() end,
	sound_play = function() return 1 end,
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
	delete_particlespawner = function(id)
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

create_mock_object = function(props, is_player, name)
	local obj = {
		_props = props or {},
		_is_player = is_player,
		_name = name or (is_player and "TestPlayer" or "mock:entity"),
		_pos = {x = 0, y = 10, z = 0},
		_vel = {x = 0, y = 0, z = 0},
		_hp = 20,
		_physics = {speed = 1.0, jump = 1.0, gravity = 1.0},
		_meta = {},
		_valid = true,
		_punches = {},
		_children = {},
		_parent = nil,
	}
	if not is_player then
		obj._luaentity = {
			object = obj,
			name = obj._name,
			hp = 20,
		}
	end

	function obj:is_player() return self._is_player end
	function obj:is_valid() return self._valid end
	function obj:get_player_name() return self._is_player and self._name or "" end
	function obj:get_pos() return {x = self._pos.x, y = self._pos.y, z = self._pos.z} end
	function obj:set_pos(p) self._pos = {x = p.x, y = p.y, z = p.z} end
	function obj:get_velocity() return {x = self._vel.x, y = self._vel.y, z = self._vel.z} end
	function obj:set_velocity(v) self._vel = {x = v.x, y = v.y, z = v.z} end
	function obj:add_velocity(v) self._vel = {x = self._vel.x + v.x, y = self._vel.y + v.y, z = self._vel.z + v.z} end
	function obj:get_hp() return self._hp end
	function obj:set_hp(hp) self._hp = hp end
	function obj:get_physics_override() return self._physics end
	function obj:set_physics_override(po)
		for k, v in pairs(po) do self._physics[k] = v end
	end
	function obj:get_luaentity() return self._luaentity end
	function obj:get_properties() return self._props end
	function obj:set_properties(p)
		for k, v in pairs(p) do self._props[k] = v end
	end
	function obj:set_armor_groups(g)
		self._armor_groups = g
	end
	function obj:get_armor_groups()
		return self._armor_groups or {}
	end
	function obj.get_texture_mod(_self)
		return ""
	end
	function obj.set_texture_mod(_self, _m)
	end
	function obj.play_animation(_self, _track, _params)
	end
	function obj:set_attach(parent)
		self._parent = parent
		table.insert(parent._children, self)
	end
	function obj:set_detach()
		self._parent = nil
	end
	function obj:get_attach()
		return self._parent
	end
	function obj:get_children()
		return self._children
	end
	function obj:punch(puncher, time_from_last_punch, tool_capabilities, dir)
		table.insert(self._punches, {
			puncher = puncher,
			tflp = time_from_last_punch,
			caps = tool_capabilities,
			dir = dir,
		})
		local dmg = 0
		if tool_capabilities and tool_capabilities.damage_groups then
			dmg = tool_capabilities.damage_groups.fleshy or tool_capabilities.damage_groups.generic or 0
		end
		self._hp = math.max(0, self._hp - dmg)
	end
	function obj:remove()
		self._valid = false
	end
	function obj.get_meta(_self)
		return {
			get_string = function(_s, k) return obj._meta[k] or "" end,
			set_string = function(_s, k, v) obj._meta[k] = v end,
		}
	end
	return obj
end

-- Load x_mob_core
dofile(core.get_modpath("x_mob_core") .. "/api.lua")

local tests_run = 0
local tests_passed = 0

local function assert_eq(actual, expected, msg)
	tests_run = tests_run + 1
	if actual == expected then
		tests_passed = tests_passed + 1
		print(string.format("  [PASS] %s", msg))
	else
		print(string.format("  [FAIL] %s: expected '%s', got '%s'", msg, tostring(expected), tostring(actual)))
	end
end

local function assert_near(actual, expected, tol, msg)
	tests_run = tests_run + 1
	tol = tol or 0.001
	if math.abs(actual - expected) <= tol then
		tests_passed = tests_passed + 1
		print(string.format("  [PASS] %s", msg))
	else
		print(string.format("  [FAIL] %s: expected ~%s, got %s", msg, tostring(expected), tostring(actual)))
	end
end

local function assert_true(val, msg)
	tests_run = tests_run + 1
	if val then
		tests_passed = tests_passed + 1
		print(string.format("  [PASS] %s", msg))
	else
		print(string.format("  [FAIL] %s: expected true, got %s", msg, tostring(val)))
	end
end

print("==================================================")
print("  Running x_mob_core Buffs Subsystem Tests")
print("==================================================")

-- Test 1: Presets Registry
local frenzy_preset = x_mob_core.get_status_effect_preset("frenzy")
assert_true(frenzy_preset ~= nil, "Preset 'frenzy' is registered")
assert_eq(frenzy_preset.category, "buff", "Frenzy category is 'buff'")
assert_near(frenzy_preset.attack_multiplier, 1.35, 0.01, "Frenzy attack multiplier is 1.35x")
assert_near(frenzy_preset.speed_factor, 1.25, 0.01, "Frenzy speed factor is 1.25x")

local ironhide_preset = x_mob_core.get_status_effect_preset("ironhide")
assert_true(ironhide_preset ~= nil, "Preset 'ironhide' is registered")
assert_near(ironhide_preset.damage_multiplier, 0.60, 0.01, "Ironhide damage multiplier is 0.60x (-40% damage taken)")
assert_near(ironhide_preset.knockback_resilience, 0.50, 0.01, "Ironhide knockback resilience is 50%")

-- Test 2: Custom Preset Registration
x_mob_core.register_status_effect_preset("custom_war_cry", {
	category = "buff",
	duration = 8.0,
	attack_multiplier = 1.25,
	speed_factor = 1.15,
})
local c_preset = x_mob_core.get_status_effect_preset("custom_war_cry")
assert_true(c_preset ~= nil, "Custom preset registered successfully")
assert_near(c_preset.attack_multiplier, 1.25, 0.01, "Custom preset attack multiplier preserved")

-- Test 3: Applying Buff to Mob Entity & Checking Multipliers
local mob_obj = create_mock_object({hp_max = 50}, false, "test:orc")
mob_obj._luaentity = {
	object = mob_obj,
	name = "test:orc",
	walk_speed = 3.0,
}

x_mob_core.apply_buff(mob_obj, "frenzy")
assert_true(x_mob_core.has_status_effect(mob_obj, "frenzy"), "Mob has active frenzy buff")
assert_near(x_mob_core.get_attack_multiplier(mob_obj), 1.35, 0.01, "Mob attack multiplier is 1.35x")
assert_near(x_mob_core.get_speed_multiplier(mob_obj), 1.25, 0.01, "Mob speed multiplier is 1.25x")

-- Test 4: Damage Group Scaling
local base_damage_groups = {fleshy = 10, fire = 5}
local scaled = x_mob_core.scale_damage_groups(base_damage_groups, x_mob_core.get_attack_multiplier(mob_obj))
assert_eq(scaled.fleshy, 14, "Scaled fleshy damage is 14 (10 * 1.35)")
assert_eq(scaled.fire, 7, "Scaled fire damage is 7 (5 * 1.35)")

-- Test 5: Knockback Resilience & Defensive Damage Reduction
x_mob_core.clear_status_effects(mob_obj)
x_mob_core.apply_buff(mob_obj, "ironhide")
assert_near(x_mob_core.get_damage_multiplier(mob_obj), 0.60, 0.01, "Mob damage multiplier is 0.60x")
assert_near(x_mob_core.get_knockback_resilience(mob_obj), 0.50, 0.01, "Mob knockback resilience is 50%")

-- Test 6: Cleanse Debuffs vs Dispel Buffs
-- Apply a debuff to mob alongside active buffs
x_mob_core.apply_buff(mob_obj, "frenzy")
x_mob_core.apply_status_effect(mob_obj, {
	id = "frost_slow",
	type = "slow",
	speed_factor = 0.50,
	duration = 5.0,
})
assert_true(x_mob_core.has_status_effect(mob_obj, "frost_slow"), "Mob has frost_slow debuff")
assert_true(x_mob_core.has_status_effect(mob_obj, "frenzy"), "Mob has frenzy buff")
assert_true(x_mob_core.has_status_effect(mob_obj, "ironhide"), "Mob has ironhide buff")

local cleansed = x_mob_core.cleanse_debuffs(mob_obj)
assert_eq(cleansed, 1, "Exactly 1 debuff was cleansed")
assert_true(not x_mob_core.has_status_effect(mob_obj, "frost_slow"), "frost_slow was removed by cleanse")
assert_true(x_mob_core.has_status_effect(mob_obj, "frenzy"), "frenzy buff was preserved by cleanse")
assert_true(x_mob_core.has_status_effect(mob_obj, "ironhide"), "ironhide buff was preserved by cleanse")

local dispelled = x_mob_core.dispel_buffs(mob_obj)
assert_eq(dispelled, 2, "Dispelled both active buffs (frenzy and ironhide)")
assert_true(not x_mob_core.has_status_effect(mob_obj, "frenzy"), "frenzy buff was removed by dispel")
assert_true(not x_mob_core.has_status_effect(mob_obj, "ironhide"), "ironhide buff was removed by dispel")
assert_near(x_mob_core.get_attack_multiplier(mob_obj), 1.0, 0.01, "Attack multiplier reset to 1.0")

-- Test 7: Thorns Reflection
x_mob_core.apply_buff(mob_obj, "carapace")
local thorns = x_mob_core.combat.status_effects.get_thorns(mob_obj)
assert_true(thorns ~= nil, "Carapace grants thorns")
assert_eq(thorns.damage, 3, "Thorns reflects 3 damage")

-- Test 8: HoT (Healing over Time / Rejuvenation)
mob_obj:set_hp(10)
x_mob_core.apply_buff(mob_obj, "rejuvenation", {duration = 2.0, heal = 3, interval = 1.0})
assert_true(x_mob_core.has_status_effect(mob_obj, "rejuvenation"), "Rejuvenation active")
-- Advance 1.0 second to trigger the HoT tick (interval = 1.0)
advance_time(1.0)
assert_true(mob_obj:get_hp() > 10, "HoT tick restored mob health")

-- Test 9: Pack Coordination - apply_pack_buff
local leader_obj = create_mock_object({hp_max = 100}, false, "test:chieftain")
local follower_1 = create_mock_object({hp_max = 30}, false, "test:grunt1")
local follower_2 = create_mock_object({hp_max = 30}, false, "test:grunt2")

local leader_ent = {
	object = leader_obj,
	name = "test:chieftain",
	followers = {follower_1, follower_2},
}
leader_obj._luaentity = leader_ent

local buffed_count = x_mob_core.pack.coordination.apply_pack_buff(leader_ent, "haste", {include_leader = true})
assert_eq(buffed_count, 3, "apply_pack_buff buffed 2 followers + 1 leader = 3")
assert_true(x_mob_core.has_status_effect(follower_1, "haste"), "Follower 1 received haste")
assert_true(x_mob_core.has_status_effect(follower_2, "haste"), "Follower 2 received haste")
assert_true(x_mob_core.has_status_effect(leader_obj, "haste"), "Leader received haste")

-- Test 10: Envelop Texture Fallback to x_mob_core_envelop_default.png
local default_env_obj = create_mock_object({hp_max = 50}, false, "test:fallback_mob")
default_env_obj._luaentity = { object = default_env_obj, name = "test:fallback_mob" }

x_mob_core.apply_status_effect(default_env_obj, {
	id = "test_fallback_buff",
	duration = 5.0,
	envelop = true,
})
local active_effects = x_mob_core.get_status_effects(default_env_obj)
assert_true(active_effects ~= nil and active_effects["test_fallback_buff"] ~= nil, "Fallback buff applied")
assert_eq(
	active_effects["test_fallback_buff"].envelop_texture,
	"x_mob_core_envelop_default.png",
	"Fallback buff uses x_mob_core_envelop_default.png"
)

-- Test 11: 3rd-Party Preset Merging & Texture Binding
x_mob_core.register_status_effect_preset("frenzy", { envelop_texture = "x_mobs_frenzy_envelop.png" })
local updated_frenzy = x_mob_core.get_status_effect_preset("frenzy")
assert_near(updated_frenzy.attack_multiplier, 1.35, 0.01, "Preset merge preserved attack_multiplier")
assert_near(updated_frenzy.speed_factor, 1.25, 0.01, "Preset merge preserved speed_factor")
assert_eq(
	updated_frenzy.envelop_texture,
	"x_mobs_frenzy_envelop.png",
	"Preset merge updated envelop_texture to 3rd-party texture"
)

print("==================================================")
print(string.format("  Buffs Test Summary: %d / %d Passed", tests_passed, tests_run))
print("==================================================")

if tests_passed == tests_run then
	print("ALL BUFF SYSTEM TESTS PASSED SUCCESSFULLY!")
	os.exit(0)
else
	print("SOME TESTS FAILED!")
	os.exit(1)
end
