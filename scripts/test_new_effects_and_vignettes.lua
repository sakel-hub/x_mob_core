--[[
	x_mob_core - Unit & Integration Test Suite for Extended Status Effects & HUD Vignettes
	Validates:
	1. Hunger & stamina compatibility adapter (stamina, hbhunger, hunger_ng, healing suppression)
	2. HUD Screen Vignette subsystem (fullscreen scale, composite multi-texture compilation, registry override)
	3. Extended status effects:
	   - Ignite: 1 HP DoT, water immersion cleanse
	   - Spores: periodic hunger/stamina drain
	   - Crystallize: +35% incoming damage, pickaxe cracky shatter synergy
	   - Earth Anchor: heavy downward gravity (2.4x), jump suppression
	   - Void Miasma: 1 HP DoT, low-gravity float, caster lifesteal
	   - Pheromone Mark: swarm attractor tracking
	   - Bone Shackles: full root and anti-heal healing suppression
	   - Waterlogged: liquid drag and downward sinking
	   - Concussion: speed and jump suppression
	4. Visual sleeve envelop attachments across all effects

	Author: SaKeL
	License: MIT
]]

local registered_entities = {}
local registered_on_joinplayer = {}
local registered_on_leaveplayer = {}
local registered_on_dieplayer = {}
local registered_on_respawnplayer = {}
local registered_on_punchplayer = {}
local registered_on_hpchange = {}
local registered_on_shutdown = {}
local registered_globalsteps = {}
local scheduled_timers = {}
local registered_players_by_name = {}
local mock_current_time = 100.0

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
	get_us_time = function() return math.floor(mock_current_time * 1000000) end,
	get_translator = function() return function(s) return s end end,
	registered_nodes = {
		["air"] = { walkable = false, drawtype = "airlike", buildable_to = true },
		["default:water_source"] = { walkable = false, liquidtype = "source" },
	},
	registered_entities = registered_entities,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	register_on_joinplayer = function(fn) table.insert(registered_on_joinplayer, fn) end,
	register_on_leaveplayer = function(fn) table.insert(registered_on_leaveplayer, fn) end,
	register_on_dieplayer = function(fn) table.insert(registered_on_dieplayer, fn) end,
	register_on_respawnplayer = function(fn) table.insert(registered_on_respawnplayer, fn) end,
	register_on_punchplayer = function(fn) table.insert(registered_on_punchplayer, fn) end,
	register_on_player_hpchange = function(fn, modifier)
		table.insert(registered_on_hpchange, {fn = fn, modifier = modifier})
	end,
	register_on_shutdown = function(fn) table.insert(registered_on_shutdown, fn) end,
	register_on_mods_loaded = function() end,
	register_on_generated = function() end,
	register_globalstep = function(fn) table.insert(registered_globalsteps, fn) end,
	register_chatcommand = function() end,
	get_connected_players = function() return {} end,
	get_player_by_name = function(name) return registered_players_by_name[name] end,
	line_of_sight = function(_pos1, _pos2) return true end,
	log = function() end,
	sound_play = function() return 1 end,
	is_creative_enabled = function() return false end,
	after = function(delay, fn)
		table.insert(scheduled_timers, { delay = delay, fn = fn })
	end,
	serialize = function(t)
		local parts = {}
		for k, v in pairs(t) do
			if type(v) == "table" then
				local inner = {}
				for ik, iv in pairs(v) do
					table.insert(inner, string.format("[%q]=%s", ik, tostring(iv)))
				end
				table.insert(parts, string.format("[%q]={%s}", k, table.concat(inner, ",")))
			else
				table.insert(parts, string.format("[%q]=%s", k, tostring(v)))
			end
		end
		return "return {" .. table.concat(parts, ",") .. "}"
	end,
	deserialize = function(str)
		if not str or str == "" then return nil end
		local f = (loadstring or load)(str)
		if f then return f() end
		return nil
	end,
	settings = {
		get = function(_self, _key, default) return default end,
		get_bool = function(_self, _key, default)
			if default ~= nil then return default end
			return false
		end,
	},
	_mock_nodes = {},
	hash_node_position = function(pos)
		return (pos.z * 65536) + (pos.y * 256) + pos.x
	end,
	get_node_or_nil = function(pos)
		local k = string.format("%d,%d,%d", math.floor(pos.x), math.floor(pos.y), math.floor(pos.z))
		return _G.core._mock_nodes[k] or {name = "air"}
	end,
	get_node = function(pos)
		local k = string.format("%d,%d,%d", math.floor(pos.x), math.floor(pos.y), math.floor(pos.z))
		return _G.core._mock_nodes[k] or {name = "air"}
	end,
	get_item_group = function(name, group)
		if group == "water" and (name == "default:water_source" or name == "default:water_flowing") then
			return 3
		end
		return 0
	end,
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
		if t.delay <= 0.0001 then
			table.insert(to_run, t.fn)
		else
			table.insert(remaining, t)
		end
	end
	scheduled_timers = remaining
	for _, fn in ipairs(to_run) do
		fn()
	end
	for _, gs in ipairs(registered_globalsteps) do
		gs(dt)
	end
	mock_current_time = mock_current_time + dt
end

create_mock_object = function(props, is_player, playername)
	local obj = {
		_valid = true,
		_is_player = is_player or false,
		_playername = playername or (is_player and "test_hero" or nil),
		_pos = {x = 0, y = 0, z = 0},
		_hp = (props and props.hp_max) or (is_player and 20 or 50),
		_armor = {fleshy = 100},
		_physics = {speed = 1.0, jump = 1.0, gravity = 1.0},
		_props = props or {},
		_hud_elements = {},
		_hud_id_counter = 100,
		_attach_parent = nil,
		_punch_log = {},
		_breath = 11,
		_fov = 0,
		_fov_is_mult = false,
		_fov_transition = 0,
	}

	function obj:is_valid() return self._valid end
	function obj:is_player() return self._is_player end
	function obj:get_player_name() return self._playername or "" end
	function obj:get_pos() return {x = self._pos.x, y = self._pos.y, z = self._pos.z} end
	function obj:set_pos(p) self._pos = {x = p.x, y = p.y, z = p.z} end
	function obj:get_hp() return self._hp end
	function obj:set_hp(hp) self._hp = math.max(0, hp) end
	function obj:get_breath() return self._breath end
	function obj:set_breath(b) self._breath = b end
	function obj:set_fov(fov, is_multiplier, transition_time)
		self._fov = fov
		self._fov_is_mult = (is_multiplier == true)
		self._fov_transition = transition_time or 0
	end
	function obj:get_fov()
		return self._fov, self._fov_is_mult
	end
	function obj:get_armor_groups() return self._armor end
	function obj:set_armor_groups(g) self._armor = g end
	function obj:get_physics_override() return self._physics end
	function obj:set_physics_override(p)
		for k, v in pairs(p) do self._physics[k] = v end
	end
	function obj:get_luaentity() return self._luaentity end
	function obj:get_properties() return self._props end
	function obj:set_properties(p)
		for k, v in pairs(p) do self._props[k] = v end
	end
	function obj:set_attach(parent, _bone, pos, _rot)
		self._attach_parent = parent
		self._attach_pos = pos
	end
	function obj:get_attach() return self._attach_parent end
	function obj:set_detach() self._attach_parent = nil end
	function obj:get_texture_mod() return self._texture_mod or "" end
	function obj:set_texture_mod(m) self._texture_mod = m end
	function obj:remove() self._valid = false end
	function obj:punch(puncher, time_from_last_punch, tool_capabilities, dir)
		table.insert(self._punch_log, {
			puncher = puncher,
			time = time_from_last_punch,
			caps = tool_capabilities,
			dir = dir,
		})
		local dmg = 0
		if tool_capabilities and tool_capabilities.damage_groups then
			dmg = tool_capabilities.damage_groups.fleshy or 0
		end
		self._hp = math.max(0, self._hp - dmg)
		return dmg
	end

	-- HUD Mock methods for player
	if is_player then
		function obj:hud_add(def)
			self._hud_id_counter = self._hud_id_counter + 1
			local id = self._hud_id_counter
			self._hud_elements[id] = {}
			for k, v in pairs(def) do self._hud_elements[id][k] = v end
			return id
		end
		function obj:hud_change(id, stat, value)
			if self._hud_elements[id] then
				self._hud_elements[id][stat] = value
			end
		end
		function obj:hud_remove(id)
			self._hud_elements[id] = nil
		end
		function obj:hud_get(id)
			return self._hud_elements[id]
		end
		if playername then
			registered_players_by_name[playername] = obj
		end
	end

	return obj
end

-- Load x_mob_core
local api_file = "mods/x_mob_core/api.lua"
local f = io.open(api_file, "r")
if f then
	f:close()
else
	api_file = "api.lua"
end
dofile(api_file)

print("=== Starting Extended Status Effects & HUD Vignettes Test Suite ===")

local total_tests = 0
local passed_tests = 0

local function assert_eq(actual, expected, desc)
	total_tests = total_tests + 1
	if actual == expected then
		passed_tests = passed_tests + 1
		print(string.format("  [PASS] %s", desc))
	else
		print(string.format("  [FAIL] %s: expected %s, got %s", desc, tostring(expected), tostring(actual)))
	end
end

local function assert_true(val, desc)
	assert_eq(not not val, true, desc)
end

local function assert_false(val, desc)
	assert_eq(not val, true, desc)
end

-- ============================================================================
-- TEST 1: Hunger & Stamina Compatibility Adapter
-- ============================================================================
print("\n--- Test Suite 1: Hunger Adapter ---")
local player1 = create_mock_object(nil, true, "hunter_steve")

-- Test 1.1: Vanilla fallback (no external hunger mod active)
local drained_vanilla = x_mob_core.hunger_adapter.drain(player1, 2)
assert_eq(drained_vanilla, false, "Vanilla drain fallback reports false when no hunger mod")

-- Test 1.2: Mock Stamina Mod
_G.stamina = {
	exhaust_player = function(p, points, cause)
		p._stamina_exhausted = (p._stamina_exhausted or 0) + points
		p._last_cause = cause
		return true
	end
}
x_mob_core.hunger_adapter.drain(player1, 3, "x_mob_core:spores")
assert_eq(player1._stamina_exhausted, 60, "stamina.exhaust_player received 60 exhaustion points (3 * 20)")
assert_eq(player1._last_cause, "x_mob_core:spores", "stamina.exhaust_player received correct cause")
_G.stamina = nil

-- Test 1.3: Mock hbhunger Mod
_G.hbhunger = {
	hunger = { ["hunter_steve"] = 20 },
}
x_mob_core.hunger_adapter.drain(player1, 4, "x_mob_core:spores")
assert_eq(_G.hbhunger.hunger["hunter_steve"], 16, "hbhunger raw hunger reduced by 4 points")
_G.hbhunger = nil

-- Test 1.4: Healing Suppression (Anti-Heal) & on_player_hpchange modifier
assert_eq(x_mob_core.hunger_adapter.is_healing_suppressed(player1), false, "Initial healing is not suppressed")
x_mob_core.hunger_adapter.suppress_healing(player1, 2.0)
assert_eq(x_mob_core.hunger_adapter.is_healing_suppressed(player1), true, "Healing is suppressed after call")

-- Verify on_player_hpchange modifier cancels healing during suppression
local hp_mod = registered_on_hpchange[1]
assert_true(hp_mod ~= nil, "on_player_hpchange modifier must be registered")
local blocked_change, stop_chain = hp_mod.fn(player1, 5, {type = "set_hp"})
assert_eq(blocked_change, 0, "Healing (+5 HP) must be negated to 0 when suppressed")
assert_true(stop_chain, "Modifier returns true to halt subsequent healing callbacks")
local dmg_change = hp_mod.fn(player1, -4, {type = "punch"})
assert_eq(dmg_change, -4, "Damage (-4 HP) passes through unchanged")

advance_time(2.5)
assert_eq(x_mob_core.hunger_adapter.is_healing_suppressed(player1), false, "Healing suppression expires after timer")
local restored_change = hp_mod.fn(player1, 5, {type = "set_hp"})
assert_eq(restored_change, 5, "Healing (+5 HP) is allowed once suppression expires")

-- ============================================================================
-- TEST 2: HUD Screen Vignette Subsystem (SOLID Architecture)
-- ============================================================================
print("\n--- Test Suite 2: HUD Screen Vignette Subsystem ---")
local player2 = create_mock_object(nil, true, "vignette_tester")

-- Test 2.1: Add single vignette
local hid = x_mob_core.hud_effects.apply(player2, "spores", "x_mob_core_vignette.png^[colorize:#88cc0066")
assert_true(hid ~= nil, "HUD element created for player")
local elem = player2:hud_get(hid)
assert_eq(elem.scale.x, -100, "HUD scale.x is -100 (100% viewport width)")
assert_eq(elem.scale.y, -100, "HUD scale.y is -100 (100% viewport height)")
assert_eq(elem.text, "x_mob_core_vignette.png^[colorize:#88cc00:alpha^[opacity:102",
	"Texture modifier applied accurately with alpha preservation")

-- Test 2.2: Add second vignette (composite compilation via ^)
x_mob_core.hud_effects.apply(player2, "ignite", "x_mob_core_vignette.png^[colorize:#ff440088")
local elem2 = player2:hud_get(hid)
local has_composite = string.find(elem2.text, "%^") ~= nil
assert_true(has_composite, "Multiple vignettes composited via ^ separator")

-- Test 2.3: 3rd Party Custom Registry Override
x_mob_core.register_vignette("custom_curse", "custom_dark_edges.png")
x_mob_core.hud_effects.apply(player2, "custom_curse")
local elem3 = player2:hud_get(hid)
local has_custom = string.find(elem3.text, "custom_dark_edges.png") ~= nil
assert_true(has_custom, "3rd-party custom vignette registered and applied")

-- Test 2.4: Remove effects and cleanup
x_mob_core.hud_effects.remove(player2, "custom_curse")
x_mob_core.hud_effects.remove(player2, "spores")
x_mob_core.hud_effects.remove(player2, "ignite")
assert_eq(x_mob_core.hud_effects.get_hud_id(player2), nil, "HUD element destroyed when all vignettes removed")
assert_eq(player2:hud_get(hid), nil, "HUD element removed from player")

-- Test 2.5: Canonical Preset Resolution without explicit config
local hid_preset = x_mob_core.hud_effects.apply(player2, "ignite")
local elem_preset = player2:hud_get(hid_preset)
assert_eq(elem_preset.text, "x_mob_core_vignette.png^[colorize:#ff4500:alpha^[opacity:200",
	"Ignite canonical preset resolved to valid modifier string")

-- Test 2.6: Canonical Preset Resolution when preset name string is passed as config
local hid_preset2 = x_mob_core.hud_effects.apply(player2, "frost", "frost")
local elem_preset2 = player2:hud_get(hid_preset2)
assert_true(string.find(elem_preset2.text, "x_mob_core_vignette%.png%^%[colorize:#55ccff:alpha") ~= nil,
	"Preset name string resolved to valid texture string instead of literal name")
x_mob_core.hud_effects.remove(player2, "ignite")
x_mob_core.hud_effects.remove(player2, "frost")
assert_eq(x_mob_core.hud_effects.get_hud_id(player2), nil, "Cleaned up preset tests")

-- Test 2.7: Vignette Prominence Multiplier Scaling
assert_eq(x_mob_core.get_vignette_prominence_multiplier(), 1.0, "Baseline prominence multiplier is 1.0")
x_mob_core.set_vignette_prominence_multiplier(1.2)
assert_eq(x_mob_core.get_vignette_prominence_multiplier(), 1.2, "Prominence multiplier updated to 1.2")
local hid_prom = x_mob_core.hud_effects.apply(player2, "custom_scaled", "x_mob_core_vignette.png^[colorize:#88cc0066")
local elem_prom = player2:hud_get(hid_prom)
-- 102 (0x66) * 1.2 = 122.4 -> 122
assert_eq(elem_prom.text, "x_mob_core_vignette.png^[colorize:#88cc00:alpha^[opacity:122",
	"Vignette opacity accurately scaled by prominence multiplier")
x_mob_core.hud_effects.remove(player2, "custom_scaled")
x_mob_core.set_vignette_prominence_multiplier(1.0)
assert_eq(x_mob_core.get_vignette_prominence_multiplier(), 1.0, "Prominence multiplier reset to baseline 1.0")

-- ============================================================================
-- TEST 3: Ignite Status Effect (1 HP DoT & Water Cleanse)
-- ============================================================================
print("\n--- Test Suite 3: Ignite & Water Cleansing ---")
local player3 = create_mock_object(nil, true, "burning_player")
player3:set_hp(20)

x_mob_core.apply_status_effect(player3, {
	name = "ignite",
	type = "dot",
	damage = 1,
	interval = 1.0,
	duration = 5.0,
	cleanse_in_water = true,
	envelop_texture = "x_mobs_fire_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#ff440088",
})

assert_true(x_mob_core.has_status_effect(player3, "ignite"), "Ignite effect is active")
assert_true(x_mob_core.has_envelop(player3), "Visual fire sleeve envelop attached")

-- Advance 1 tick: exactly 1 HP damage taken
advance_time(1.0)
assert_eq(player3:get_hp(), 19, "Ignite deals exactly 1 HP DoT per tick")

-- Submerge in water and advance to next tick
_G.core._mock_nodes["0,0,0"] = {name = "default:water_source"}
advance_time(1.0)
assert_eq(x_mob_core.has_status_effect(player3, "ignite"), false, "Ignite cleansed upon water immersion")
assert_eq(x_mob_core.has_envelop(player3), false, "Visual fire sleeve envelop detached on cleanse")
assert_eq(x_mob_core.hud_effects.get_hud_id(player3), nil, "Vignette removed upon effect cleanse")
_G.core._mock_nodes["0,0,0"] = nil

-- Test 3b: Automatic preset vignette removal (no hud_vignette specified in def)
x_mob_core.apply_status_effect(player3, {
	id = "ignite",
	duration = 2.0,
})
assert_true(x_mob_core.hud_effects.get_hud_id(player3) ~= nil, "Preset vignette applied automatically")
x_mob_core.remove_status_effect(player3, "ignite")
assert_eq(x_mob_core.hud_effects.get_hud_id(player3), nil,
	"Preset vignette removed cleanly on remove_status_effect")

-- ============================================================================
-- TEST 4: Crystallize & Pickaxe Shattering Synergy
-- ============================================================================
print("\n--- Test Suite 4: Crystallize (+35% Damage & Pickaxe Shatter) ---")
local mob_target = create_mock_object({hp_max = 100}, false, nil)
mob_target:set_hp(100)

x_mob_core.apply_status_effect(mob_target, {
	name = "crystallize",
	type = "custom",
	duration = 4.0,
	speed_factor = 0.15,
	jump_factor = 0.0,
	damage_multiplier = 1.35,
	envelop_texture = "x_mobs_crystal_envelop.png",
})

assert_true(x_mob_core.has_status_effect(mob_target, "crystallize"), "Crystallize applied")
assert_eq(x_mob_core.get_damage_multiplier(mob_target), 1.35, "Damage multiplier is 1.35x (+35%)")

-- Calculate incoming damage with damage.lua multiplier
local mob_ctx = { object = mob_target }
local punch_caps = { full_punch_interval = 1.0, damage_groups = { fleshy = 20 } }
local final_dmg = x_mob_core.combat.damage.calculate_punch_damage(mob_ctx, nil, 1.0, punch_caps)
assert_eq(final_dmg, 27, "Base 20 damage multiplied by 1.35x yields 27 damage")

-- Player with pickaxe hits player with crystallize
local player_victim = create_mock_object(nil, true, "frozen_miner")
x_mob_core.apply_status_effect(player_victim, {
	name = "crystallize",
	type = "custom",
	duration = 4.0,
	damage_multiplier = 1.35,
	envelop_texture = "x_mobs_crystal_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#88ffff99",
})
assert_true(x_mob_core.has_status_effect(player_victim, "crystallize"), "Player crystallized")

-- Simulate pickaxe punch via registered_on_punchplayer hook
local puncher = create_mock_object(nil, true, "pickaxe_user")
function puncher.get_wielded_item(_self)
	return {
		is_empty = function() return false end,
		get_name = function() return "default:pick_diamond" end,
	}
end
_G.core.registered_items = {
	["default:pick_diamond"] = {
		tool_capabilities = {
			groupcaps = { cracky = { times = { 2.0, 1.0, 0.5 } } }
		}
	}
}

for _, fn in ipairs(registered_on_punchplayer) do
	fn(player_victim, puncher, 1.0, {damage_groups = {fleshy = 10}}, {x = 0, y = 0, z = 1}, 10)
end
assert_eq(x_mob_core.has_status_effect(player_victim, "crystallize"), false,
	"Pickaxe shatter cleansed crystallize early")

-- ============================================================================
-- TEST 5: Earth Anchor (Heavy Gravity & Jump Suppression)
-- ============================================================================
print("\n--- Test Suite 5: Earth Anchor ---")
local player5 = create_mock_object(nil, true, "heavy_player")
x_mob_core.apply_status_effect(player5, {
	name = "earth_anchor",
	type = "custom",
	duration = 4.0,
	gravity_factor = 2.4,
	jump_factor = 0.0,
	speed_factor = 0.55,
	envelop_texture = "x_mobs_mud_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#4a3219aa",
})
local phys5 = player5:get_physics_override()
assert_eq(phys5.gravity, 2.4, "Gravity increased to 2.4x")
assert_eq(phys5.jump, 0.0, "Jump suppressed to 0.0")
assert_eq(phys5.speed, 0.55, "Speed reduced to 0.55x")
assert_true(x_mob_core.has_envelop(player5), "Mud sleeve envelop attached")

-- ============================================================================
-- TEST 6: Void Miasma (1 HP DoT & Caster Lifesteal)
-- ============================================================================
print("\n--- Test Suite 6: Void Miasma & Caster Lifesteal ---")
local caster_spectrum = create_mock_object({hp_max = 60}, false, nil)
caster_spectrum:set_hp(40)
local victim6 = create_mock_object(nil, true, "void_victim")
victim6:set_hp(20)

x_mob_core.apply_status_effect(victim6, {
	name = "void_miasma",
	type = "custom",
	damage = 1,
	interval = 1.5,
	duration = 6.0,
	gravity_factor = 0.3,
	speed_factor = 0.7,
	caster = caster_spectrum,
	envelop_texture = "x_mobs_void_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#11002290",
	on_tick = function(_t, c)
		if c and c:is_valid() then
			local cur_hp = c:get_hp()
			c:set_hp(math.min(60, cur_hp + 1))
			x_mob_core.indicate_regen(c)
			x_mob_core.effects.indicate_regen(c)
		end
	end,
})

assert_true(type(x_mob_core.effects) == "table", "x_mob_core.effects subsystem exported")
assert_true(type(x_mob_core.effects.indicate_regen) == "function", "x_mob_core.effects.indicate_regen is callable")
assert_true(x_mob_core.has_status_effect(victim6, "void_miasma"), "Void miasma active")
local phys6 = victim6:get_physics_override()
assert_eq(phys6.gravity, 0.3, "Low-gravity float (0.3x) applied to victim")

advance_time(1.5)
assert_eq(victim6:get_hp(), 19, "Victim took exactly 1 HP DoT damage")
assert_eq(caster_spectrum:get_hp(), 41, "Caster regenerated 1 HP via lifesteal")

-- ============================================================================
-- TEST 7: Bone Shackles (Root & Anti-Heal)
-- ============================================================================
print("\n--- Test Suite 7: Bone Shackles ---")
local player7 = create_mock_object(nil, true, "shackled_player")
x_mob_core.apply_status_effect(player7, {
	name = "bone_shackles",
	type = "debuff",
	duration = 3.0,
	speed_factor = 0.0,
	jump_factor = 0.0,
	anti_heal = true,
	envelop_texture = "x_mobs_bone_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#ddddddbb",
})
local phys7 = player7:get_physics_override()
assert_eq(phys7.speed, 0.0, "Speed completely rooted (0.0)")
assert_eq(phys7.jump, 0.0, "Jump completely disabled (0.0)")
assert_true(x_mob_core.hunger_adapter.is_healing_suppressed(player7), "Healing is suppressed")

-- ============================================================================
-- TEST 8: Waterlogged & Concussion
-- ============================================================================
print("\n--- Test Suite 8: Waterlogged & Concussion ---")
local player8 = create_mock_object(nil, true, "swimming_player")
player8._breath = 11
x_mob_core.apply_status_effect(player8, {
	name = "waterlogged",
	type = "custom",
	duration = 4.0,
	speed_factor = 0.4,
	gravity_factor = 1.6,
	interval = 1.0,
	envelop_texture = "x_mobs_brine_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#00336690",
	on_apply = function(victim)
		if victim:is_player() then
			local b = victim:get_breath()
			if b and b > 0 then
				victim:set_breath(math.max(0, b - 2))
			end
		end
	end,
	on_tick = function(victim)
		if victim:is_player() then
			local b = victim:get_breath()
			if b and b > 0 then
				victim:set_breath(math.max(0, b - 2))
			end
		end
	end,
})
local phys8 = player8:get_physics_override()
assert_eq(phys8.speed, 0.4, "Waterlogged swim speed reduced to 0.4x")
assert_eq(phys8.gravity, 1.6, "Waterlogged sinking gravity increased to 1.6x")
assert_eq(player8:get_breath(), 9, "Waterlogged on_apply immediately drained 2 breath points (11 -> 9)")
advance_time(1.0)
assert_eq(player8:get_breath(), 7, "Waterlogged on_tick drained another 2 breath points (9 -> 7)")

local player9 = create_mock_object(nil, true, "concussed_player")
local concussion_applied = false
x_mob_core.apply_status_effect(player9, {
	name = "concussion",
	type = "custom",
	duration = 3.5,
	speed_factor = 0.45,
	jump_factor = 0.5,
	fov_factor = 0.85,
	fov_duration = 0.8,
	fov_transition = 0.2,
	envelop_texture = "x_mobs_smoke_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#ffffff77",
	on_apply = function(_target)
		concussion_applied = true
	end,
})
local phys9 = player9:get_physics_override()
assert_eq(phys9.speed, 0.45, "Concussion speed reduced to 0.45x")
assert_eq(phys9.jump, 0.5, "Concussion jump reduced to 0.5x")
assert_true(concussion_applied, "Concussion on_apply hook triggered")
assert_eq(player9._fov, 0.85, "Concussion applied declarative FOV factor 0.85")
assert_true(player9._fov_is_mult, "Concussion FOV override uses is_multiplier=true")

-- Test baseline preservation with prior item zoom (e.g. charged bow at 0.9x)
local player10 = create_mock_object(nil, true, "bow_zoomed_player")
player10:set_fov(0.9, true, 0.4)
x_mob_core.apply_status_effect(player10, {
	name = "concussion",
	type = "custom",
	duration = 3.5,
	fov_factor = 0.85,
	fov_duration = 0.8,
	fov_transition = 0.2,
})
-- Compound FOV: 0.9 * 0.85 = 0.765
local compound_diff = math.abs(player10._fov - 0.765)
assert_true(compound_diff < 0.0001, "Compound FOV with prior bow zoom (0.9 * 0.85 = 0.765)")
assert_true(player10._fov_is_mult, "Compound FOV maintains is_multiplier=true")

-- Test baseline absolute degrees preservation (e.g. spyglass at 20 degrees)
local player11 = create_mock_object(nil, true, "spyglass_player")
player11:set_fov(20, false, 0.1)
x_mob_core.apply_status_effect(player11, {
	name = "concussion",
	type = "custom",
	duration = 3.5,
	fov_factor = 0.85,
	fov_duration = 0.8,
	fov_transition = 0.2,
})
-- Compound absolute FOV: 20 * 0.85 = 17
local spyglass_diff = math.abs(player11._fov - 17)
assert_true(spyglass_diff < 0.0001, "Compound FOV with prior spyglass zoom (20 * 0.85 = 17)")
assert_false(player11._fov_is_mult, "Compound FOV maintains is_multiplier=false for absolute degrees")

-- Advance time by fov_duration (0.8s) to verify clean restoration
advance_time(0.8)
assert_eq(player9._fov, 0, "Unzoomed player FOV restored to 0 after fov_duration")
assert_false(player9._fov_is_mult, "Unzoomed player FOV is_multiplier restored to false")
assert_eq(player10._fov, 0.9, "Bow-zoomed player FOV restored to baseline 0.9x")
assert_true(player10._fov_is_mult, "Bow-zoomed player FOV is_multiplier preserved as true")
assert_eq(player11._fov, 20, "Spyglass player FOV restored to baseline 20 degrees")
assert_false(player11._fov_is_mult, "Spyglass player FOV is_multiplier preserved as false")

-- Test refresh with token handling (subsequent hit refreshes fov_duration)
local player12 = create_mock_object(nil, true, "refresh_player")
x_mob_core.apply_status_effect(player12, {
	name = "concussion",
	type = "custom",
	duration = 3.5,
	fov_factor = 0.85,
	fov_duration = 0.8,
	fov_transition = 0.2,
})
advance_time(0.5) -- 0.5s elapsed, 0.3s remaining on first hit
-- Second hit refreshes effect
x_mob_core.apply_status_effect(player12, {
	name = "concussion",
	type = "custom",
	duration = 3.5,
	fov_factor = 0.85,
	fov_duration = 0.8,
	fov_transition = 0.2,
})
advance_time(0.4) -- 0.9s from first hit, but 0.4s into second hit
assert_eq(player12._fov, 0.85, "Refreshed effect token prevented stale timer from reverting FOV prematurely")
advance_time(0.5) -- Now second fov_duration has expired (0.4 + 0.5 = 0.9 >= 0.8)
assert_eq(player12._fov, 0, "FOV cleanly restored after refreshed fov_duration expired")

-- Test clear_effects restores baseline immediately
local player13 = create_mock_object(nil, true, "cleared_player")
player13:set_fov(0.75, true, 0.3)
x_mob_core.apply_status_effect(player13, {
	name = "concussion",
	type = "custom",
	duration = 3.5,
	fov_factor = 0.85,
	fov_duration = 0.8,
	fov_transition = 0.2,
})
assert_true(math.abs(player13._fov - (0.75 * 0.85)) < 0.0001, "FOV compounded before clear")
x_mob_core.clear_status_effects(player13)
assert_eq(player13._fov, 0.75, "clear_status_effects restored baseline FOV immediately")
assert_true(player13._fov_is_mult, "clear_status_effects preserved baseline is_multiplier")

-- ============================================================================
-- TEST 9: Pheromone Mark (Custom Alert & Widened Aggro Range)
-- ============================================================================
print("\n--- Test Suite 9: Pheromone Mark ---")
local marked_player = create_mock_object(nil, true, "marked_target")
marked_player:set_pos({x = 0, y = 0, z = 25})
local unmarked_player = create_mock_object(nil, true, "normal_target")
unmarked_player:set_pos({x = 0, y = 0, z = 25})

local alerted_swarm = false
x_mob_core.apply_status_effect(marked_player, {
	id = "pheromone_mark",
	type = "custom",
	duration = 8.0,
	envelop_texture = "x_mobs_swarm_envelop.png",
	hud_vignette = "x_mob_core_vignette.png^[colorize:#88ff0077",
	on_apply = function(_victim)
		alerted_swarm = true
	end,
})
assert_true(x_mob_core.has_status_effect(marked_player, "pheromone_mark"), "Pheromone mark active on player")
assert_true(alerted_swarm, "Pheromone mark alerted nearby swarm on apply")

local mob_scanner = {
	object = create_mock_object(nil, false, nil),
	aggro_radius = 16.0,
	eye_offset = 1.5,
}
mob_scanner.object:set_pos({x = 0, y = 0, z = 0})

_G.core.get_connected_players = function() return { unmarked_player } end
local found_unmarked = x_mob_core.motor.ai.scan_for_player(mob_scanner, 16.0)
assert_eq(found_unmarked, nil, "Unmarked player 25 nodes away is out of base aggro range (16.0)")

_G.core.get_connected_players = function() return { marked_player } end
local found_marked, dist_marked = x_mob_core.motor.ai.scan_for_player(mob_scanner, 16.0)
assert_true(found_marked == marked_player, "Marked player detected across widened aggro range (25 nodes)")
assert_eq(dist_marked, 25, "Measured distance matches exactly (25 nodes)")

-- ============================================================================
-- Test Suite 10: Failsafe Expiration, Playerphysics Recovery & Envelop Punch Safety
-- ============================================================================
print("\n--- Test Suite 10: Failsafe Expiration, Playerphysics Recovery & Envelop Punch Safety ---")

local bugged_player = create_mock_object(nil, true, "bugged_player")
x_mob_core.apply_status_effect(bugged_player, {
	id = "error_tick_effect",
	type = "custom",
	duration = 3.0,
	interval = 1.0,
	speed_factor = 0.6,
	gravity_factor = 0.5,
	on_tick = function()
		error("Simulated unhandled runtime error in third-party on_tick callback")
	end,
})

local bugged_phys = bugged_player:get_physics_override()
assert_eq(bugged_phys.speed, 0.6, "Player slowed to 0.6x initially")
assert_eq(bugged_phys.gravity, 0.5, "Player gravity reduced to 0.5x initially")

-- Advance time across the ticks and through the 3.0s duration + 0.1s failsafe
advance_time(3.1)
assert_false(x_mob_core.has_status_effect(bugged_player, "error_tick_effect"),
	"Status effect expired despite on_tick error")
local restored_phys = bugged_player:get_physics_override()
assert_eq(restored_phys.speed, 1.0, "Player speed restored to 1.0x baseline via failsafe expiration")
assert_eq(restored_phys.gravity, 1.0, "Player gravity restored to 1.0x baseline via failsafe expiration")

-- Test playerphysics metadata recovery and cleanup
local meta_player = create_mock_object(nil, true, "meta_player")
local meta_store = {
	["playerphysics:physics"] =
		'return {["speed"]={["x_mob_core:void_miasma"]=0.7},["gravity"]={["x_mob_core:void_miasma"]=0.3}}',
}
meta_player.get_meta = function()
	return {
		get_string = function(_self, k) return meta_store[k] or "" end,
		set_string = function(_self, k, v) meta_store[k] = v end,
	}
end

_G.playerphysics = {
	add_physics_factor = function(p, attr, id, val)
		local data = _G.core.deserialize(p:get_meta():get_string("playerphysics:physics")) or {}
		data[attr] = data[attr] or {}
		data[attr][id] = val
		p:get_meta():set_string("playerphysics:physics", _G.core.serialize(data))
	end,
	remove_physics_factor = function(p, attr, id)
		local data = _G.core.deserialize(p:get_meta():get_string("playerphysics:physics")) or {}
		if data[attr] then data[attr][id] = nil end
		p:get_meta():set_string("playerphysics:physics", _G.core.serialize(data))
	end,
}

x_mob_core.clear_status_effects(meta_player)
local cleaned_meta = _G.core.deserialize(meta_store["playerphysics:physics"])
assert_true(cleaned_meta ~= nil, "playerphysics metadata exists")
assert_true(cleaned_meta.speed["x_mob_core:void_miasma"] == nil,
	"Speed factor x_mob_core:void_miasma purged from metadata")
assert_true(cleaned_meta.gravity["x_mob_core:void_miasma"] == nil,
	"Gravity factor x_mob_core:void_miasma purged from metadata")
local meta_phys = meta_player:get_physics_override()
assert_eq(meta_phys.speed, 1.0, "Player speed recalculated to 1.0 after metadata purge")
assert_eq(meta_phys.gravity, 1.0, "Player gravity recalculated to 1.0 after metadata purge")
_G.playerphysics = nil

-- Test Envelop self-punch guard
local envelop_entity = core.registered_entities["x_mob_core:envelop"]
if envelop_entity and envelop_entity.on_punch then
	local mock_envelop = {
		target = meta_player,
		object = create_mock_object(nil, false, nil),
	}
	local punched_target = false
	meta_player.punch = function() punched_target = true end
	-- Self-punch attempt: puncher is meta_player
	envelop_entity.on_punch(mock_envelop, meta_player, 1.0, {}, {x = 0, y = 0, z = 0})
	assert_false(punched_target, "Self punch blocked by envelop entity")
	-- Other puncher: puncher is different object
	local attacker = create_mock_object(nil, false, nil)
	envelop_entity.on_punch(mock_envelop, attacker, 1.0, {}, {x = 0, y = 0, z = 0})
	assert_true(punched_target, "Legitimate punch from third party forwarded to target")
end

print(string.format("\n========================================================"))
print(string.format("RESULTS: %d / %d tests passed.", passed_tests, total_tests))
print(string.format("========================================================"))

if passed_tests == total_tests then
	print("ALL EXTENDED STATUS EFFECT TESTS PASSED SUCCESSFULLY!")
	os.exit(0)
else
	print("SOME TESTS FAILED.")
	os.exit(1)
end
