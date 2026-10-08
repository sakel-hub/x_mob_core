--[[
	test_health_regen.lua - Comprehensive Test Suite for Mob Health Regeneration
	Validates:
	1. Low-HP tactical fleeing state transitions with default thresholds (25% flee, 60% return)
	2. Passive health regeneration rate while fleeing
	3. Health regeneration triggered while running away from panic (panic_timer > 0)
	4. Suppression of health regeneration when idle or in combat without passive_regen
	5. Passive regeneration flag enabling continuous recovery without running away
	6. Developer configuration overrides via def.health_regen (number, boolean, table)
	7. Complete disabling of regeneration (health_regen = false / rate = 0)
	8. Complete disabling of fleeing (flee_threshold = 0 / can_flee = false)
	10. Visual white texture overlay feedback (indicate_regen with ^[colorize:#FFFFFF60)
	11. Custom texture overlay color configuration
	12. Disabling texture overlay while retaining HP recovery (regen_overlay = false)
	13. Red damage flash priority over white regeneration flash
	14. Active damage flash blocking new regeneration flashes
	15. Suppression of regeneration flash when dying or dead
	16. Dynamic overhead health bar synchronization on regeneration ticks
	17. Execution of on_regen_step and on_return_to_fight developer callbacks
]]

-- Minimal Luanti Engine Mock
local mock_entities = {}
local registered_entities = {}
local settings_store = {
	x_mob_damage_particles = "mob_default",
	x_mob_damage_particle_multiplier = "1.0",
	x_mob_core_enable_health_bars = "true",
	x_mob_core_health_bar_timeout = "4.0",
	x_mob_core_health_bar_auto_remove = "true",
}

local after_callbacks = {}

local core = {
	settings = {
		get = function(_self, key)
			return settings_store[key]
		end,
		get_bool = function(_self, key, default)
			if settings_store[key] == nil then return default end
			return settings_store[key] == "true" or settings_store[key] == true
		end,
	},
	get_modpath = function(modname)
		if modname == "x_mob_core" then
			return "."
		end
		return nil
	end,
	registered_entities = registered_entities,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	after = function(delay, func)
		after_callbacks[#after_callbacks + 1] = { timer = delay, func = func }
	end,
	add_entity = function(pos, name)
		local def = registered_entities[name]
		if not def then return nil end

		local obj = {
			_pos = { x = pos.x, y = pos.y, z = pos.z },
			_properties = {},
			_attached_to = nil,
			_texture_mod = "",
			_hp = 20,
			_valid = true,
			_luaentity = nil,
		}

		function obj:is_valid()
			return self._valid
		end

		function obj:get_pos()
			return { x = self._pos.x, y = self._pos.y, z = self._pos.z }
		end

		function obj:set_properties(props)
			for k, v in pairs(props) do
				self._properties[k] = v
			end
		end

		function obj:get_properties()
			return self._properties
		end

		function obj:get_hp()
			return self._hp
		end

		function obj:set_hp(hp)
			self._hp = hp
		end

		function obj:get_texture_mod()
			return self._texture_mod
		end

		function obj:set_texture_mod(mod)
			self._texture_mod = mod or ""
		end

		function obj:get_luaentity()
			return self._luaentity
		end

		function obj:set_attach(parent, _bone, attach_p, _rot, _force)
			self._attached_to = parent
			self._attach_pos = attach_p
		end

		function obj:set_detach()
			self._attached_to = nil
		end

		function obj:remove()
			self._valid = false
		end

		local ent = {}
		if def.initial_properties then
			for k, v in pairs(def.initial_properties) do
				obj._properties[k] = v
			end
		end
		for k, v in pairs(def) do
			if type(v) == "function" then
				ent[k] = v
			end
		end
		ent.object = obj
		obj._luaentity = ent
		mock_entities[#mock_entities + 1] = obj
		return obj
	end,
}

_G.core = core
_G.minetest = core

local function make_mock_object(hp, max_hp, texture_mod)
	local obj = {
		_hp = hp or 40,
		_max_hp = max_hp or 40,
		_texture_mod = texture_mod or "",
		_valid = true,
		_properties = {
			collisionbox = {-0.4, 0, -0.4, 0.4, 1.6, 0.4},
			selectionbox = {-0.4, 0, -0.4, 0.4, 1.6, 0.4},
			hp_max = max_hp or 40,
		},
		_luaentity = nil,
	}

	function obj:is_valid()
		return self._valid
	end

	function obj.get_pos()
		return { x = 0, y = 10, z = 0 }
	end

	function obj:get_properties()
		return self._properties
	end

	function obj:set_properties(props)
		for k, v in pairs(props) do
			self._properties[k] = v
		end
	end

	function obj:get_hp()
		return self._hp
	end

	function obj:set_hp(new_hp)
		self._hp = new_hp
	end

	function obj:get_texture_mod()
		return self._texture_mod
	end

	function obj:set_texture_mod(mod)
		self._texture_mod = mod or ""
	end

	function obj:get_luaentity()
		return self._luaentity
	end

	return obj
end

-- Load subsystems
local effects = dofile("combat/effects.lua")
local mob_memory = dofile("navigation/mob_memory.lua")
local properties = dofile("lifecycle/properties.lua")
local health_bar = dofile("combat/health_bar.lua")

-- Create global x_mob_core for delegation
_G.x_mob_core = {
	combat = {
		effects = effects,
		health_bar = health_bar,
	},
	indicate_regen = function(obj, color, dur)
		return effects.indicate_regen(obj, color, dur)
	end,
	clear_regen = function(obj)
		return effects.clear_regen(obj)
	end,
	indicate_damage = function(obj)
		return effects.indicate_damage(obj)
	end,
	clear_damage = function(obj)
		return effects.clear_damage(obj)
	end,
}

local total_tests = 0
local passed_tests = 0

local function assert_test(cond, msg)
	total_tests = total_tests + 1
	if cond then
		passed_tests = passed_tests + 1
		print(string.format("  [PASS] %s", msg))
	else
		print(string.format("  [FAIL] %s", msg))
		error("Assertion failed: " .. msg, 2)
	end
end

print("==================================================")
print("  Running x_mob_core Health Regeneration Test Suite")
print("==================================================")

-- TEST 1: Default Fleeing Thresholds and Passive Health Regeneration while Fleeing
do
	local mock_obj = make_mock_object(8, 40)
	local mob = {
		hp = 8,
		hp_max = 40,
		state = "idle",
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)

	-- 8 / 40 = 20% (below default 25% threshold)
	local is_fleeing = mob_memory.update_health_regen(mob, 0.1)
	assert_test(is_fleeing == true and mob.state == "fleeing",
		"Mob enters fleeing state when HP drops below default 25% flee ratio")

	-- Advance 2.0 seconds at default 0.5 HP/s -> +1 HP
	mob_memory.update_health_regen(mob, 2.0)
	assert_test(mob.hp == 9, "Mob recovers 1 HP after 2.0s at default 0.5 HP/s")
	assert_test(mock_obj:get_texture_mod():find("%[colorize:#FFFFFF60") ~= nil,
		"White texture overlay is applied on regeneration tick")

	-- Advance 30 seconds at 0.5 HP/s -> reaches 24 HP (60% return threshold)
	for _ = 1, 15 do
		mob_memory.update_health_regen(mob, 2.0)
	end
	assert_test(mob.hp >= 24, "Mob regenerates to return threshold (>= 24 HP)")
	assert_test(mob.state == "idle" and mob.memory.flee_state == false,
		"Mob exits fleeing state when HP recovers to 60% threshold")
end

-- TEST 2: Running Away Detection (Panic Timer & Custom Fleeing State)
do
	local mock_obj = make_mock_object(35, 40)
	local mob = {
		hp = 35,
		hp_max = 40,
		state = "idle",
		panic_timer = 5.0,
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)

	-- HP is high (35/40 = 87.5%), but mob is panicking (running away)
	mob_memory.update_health_regen(mob, 2.0)
	assert_test(mob.hp == 36, "Mob regenerates HP while running away from panic (panic_timer > 0)")
	assert_test(mock_obj:get_texture_mod():find("%[colorize:#FFFFFF60") ~= nil,
		"White texture overlay flashes during panic regeneration")

	-- Reset panic timer and state to idle
	mob.panic_timer = 0
	mob.state = "idle"
	mock_obj:set_texture_mod("")
	mob_memory.update_health_regen(mob, 2.0)
	assert_test(mob.hp == 36, "Idle mob does NOT regenerate HP without passive_regen")
end

-- TEST 3: Developer Override - Custom Regen Rate and Overlay Color
do
	local mock_obj = make_mock_object(5, 50)
	local regen_step_called = 0
	local added_amount = 0
	local mob = {
		hp = 5,
		hp_max = 50,
		state = "fleeing",
		health_regen = {
			rate = 3.0, -- 3 HP per second
			overlay_color = "^[colorize:#FFE06680", -- Custom gold overlay
		},
		on_regen_step = function(_self, amt)
			regen_step_called = regen_step_called + 1
			added_amount = amt
		end,
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)
	mob.memory.flee_state = true

	mob_memory.update_health_regen(mob, 1.0)
	assert_test(mob.hp == 8, "Custom regen_rate (3.0 HP/s) regenerates 3 HP in 1.0 second")
	assert_test(regen_step_called == 1 and added_amount == 3,
		"on_regen_step callback is executed with correct hp_added")
	assert_test(mock_obj:get_texture_mod():find("%[colorize:#FFE06680") ~= nil,
		"Custom regen_overlay_color is applied to object")
end

-- TEST 4: Developer Override - Disabling Overlay (regen_overlay = false)
do
	local mock_obj = make_mock_object(5, 40)
	local mob = {
		hp = 5,
		hp_max = 40,
		state = "fleeing",
		health_regen = {
			rate = 2.0,
			overlay = false,
		},
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)
	mob.memory.flee_state = true

	mock_obj:set_texture_mod("")
	mob_memory.update_health_regen(mob, 1.0)
	assert_test(mob.hp == 7, "Mob still regenerates HP when regen_overlay = false")
	assert_test(mock_obj:get_texture_mod() == "",
		"No texture overlay modifier is applied when regen_overlay = false")
end

-- TEST 5: Developer Override - Disabling Health Regeneration (health_regen = false / regen_rate = 0)
do
	local mock_obj = make_mock_object(5, 40)
	local mob = {
		hp = 5,
		hp_max = 40,
		state = "fleeing",
		health_regen = {
			rate = 0,
		},
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)
	mob.memory.flee_state = true

	mob_memory.update_health_regen(mob, 5.0)
	assert_test(mob.hp == 5, "Mob with regen_rate = 0 does not regenerate any HP")
end

-- TEST 6: Developer Override - Disabling Fleeing (flee_hp_threshold = 0)
do
	local mock_obj = make_mock_object(2, 40)
	local mob = {
		hp = 2,
		hp_max = 40,
		state = "idle",
		health_regen = {
			flee_threshold = 0, -- Never flees
		},
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)

	local is_fleeing = mob_memory.update_health_regen(mob, 1.0)
	assert_test(is_fleeing == false and mob.state == "idle",
		"Mob with flee_hp_threshold = 0 never enters fleeing state")
	assert_test(mob.hp == 2, "Mob does not regenerate health when standing ground")
end

-- TEST 7: Passive Regeneration Flag (passive_regen = true)
do
	local mock_obj = make_mock_object(10, 40)
	local mob = {
		hp = 10,
		hp_max = 40,
		state = "idle",
		health_regen = {
			flee_threshold = 0,
			passive = true,
			rate = 1.0,
		},
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)

	mob_memory.update_health_regen(mob, 1.0)
	assert_test(mob.hp == 11, "Mob with passive_regen = true regenerates health while idle")
end

-- TEST 8: Conflict Priority - Damage Flash Takes Precedence Over Regen Flash
do
	local mock_obj = make_mock_object(10, 40, "base_texture.png")
	local ent = {
		object = mock_obj,
		is_dead = false,
		state = "fleeing",
	}
	mock_obj._luaentity = ent

	-- Trigger white regen flash
	effects.indicate_regen(mock_obj)
	assert_test(mock_obj:get_texture_mod():find("%[colorize:#FFFFFF60") ~= nil,
		"Regen flash is initially visible")

	-- Entity takes damage: red flash must immediately cancel and overwrite white regen flash
	effects.indicate_damage(mock_obj)
	assert_test(mock_obj:get_texture_mod():find("%[colorize:#FF000060") ~= nil,
		"Damage flash immediately replaces white regen flash")
	assert_test(ent._regen_flash_timer == nil,
		"Regen flash timer is cleared when damage flash occurs")

	-- Attempting to trigger regen flash while damage flash is active must be blocked
	effects.indicate_regen(mock_obj)
	assert_test(mock_obj:get_texture_mod():find("%[colorize:#FF000060") ~= nil,
		"Active damage flash blocks regen flash from interrupting")

	-- Clearing damage restores clean base texture
	effects.clear_damage(mock_obj)
	assert_test(mock_obj:get_texture_mod() == "base_texture.png",
		"Base texture is cleanly restored after damage flash completes")
end

-- TEST 9: Dying State Suppresses Regeneration Visuals
do
	local mock_obj = make_mock_object(0, 40, "mob.png")
	local ent = {
		object = mock_obj,
		is_dead = true,
		state = "dying",
	}
	mock_obj._luaentity = ent

	effects.indicate_regen(mock_obj)
	assert_test(mock_obj:get_texture_mod() == "mob.png",
		"Regen flash is suppressed when entity is dead or dying")
end

-- TEST 10: Property Normalization - Table and Shorthand Configuration
do
	local def_table = {
		initial_properties = { hp_max = 50 },
		health_regen = {
			rate = 2.5,
			overlay = false,
			overlay_color = "^[colorize:#00FF0060",
			passive = true,
			flee_threshold = 15,
			return_threshold = 35,
		},
	}
	properties.resolve_mob_properties(def_table)
	assert_test(type(def_table.health_regen) == "table", "Structured config produces canonical health_regen table")
	assert_test(def_table.health_regen.rate == 2.5, "Canonical health_regen.rate is 2.5")
	assert_test(def_table.health_regen.overlay == false, "Canonical health_regen.overlay is false")
	assert_test(def_table.health_regen.overlay_color == "^[colorize:#00FF0060",
		"Canonical health_regen.overlay_color matches")
	assert_test(def_table.health_regen.passive == true, "Canonical health_regen.passive is true")
	assert_test(def_table.health_regen.flee_threshold == 15,
		"Canonical health_regen.flee_threshold resolves correctly")
	assert_test(def_table.health_regen.return_threshold == 35,
		"Canonical health_regen.return_threshold resolves correctly")
	assert_test(def_table.regen_rate == nil, "No redundant flat regen_rate alias on def")
	assert_test(def_table.flee_hp_threshold == nil, "No redundant flat flee_hp_threshold alias on def")
	assert_test(def_table.return_hp_threshold == nil, "No redundant flat return_hp_threshold alias on def")
	assert_test(def_table.health_regen.color == nil, "No redundant color alias in health_regen")
	assert_test(def_table.health_regen.unlimited == nil, "No redundant unlimited alias in health_regen")

	local def_disabled = {
		initial_properties = { hp_max = 30 },
		health_regen = false,
	}
	properties.resolve_mob_properties(def_disabled)
	assert_test(def_disabled.health_regen.enabled == false and def_disabled.health_regen.rate == 0,
		"health_regen = false normalizes to disabled in canonical table")
	assert_test(def_disabled.health_regen_enabled == nil, "No redundant flat health_regen_enabled alias on def")

	local def_numeric = {
		initial_properties = { hp_max = 40 },
		health_regen = 1.8,
	}
	properties.resolve_mob_properties(def_numeric)
	assert_test(def_numeric.health_regen.rate == 1.8, "Numeric health_regen normalizes to canonical table rate")
	assert_test(def_numeric.health_regen.overlay == true, "Default regen overlay is true")
	assert_test(def_numeric.health_regen.overlay_color == "^[colorize:#FFFFFF60",
		"Default regen overlay_color is white ^[colorize:#FFFFFF60")

	local def_default = {
		initial_properties = { hp_max = 60 },
	}
	properties.resolve_mob_properties(def_default)
	assert_test(type(def_default.health_regen) == "table", "Unconfigured mob creates canonical table")
	assert_test(def_default.health_regen.rate == 0.5, "Canonical default rate is 0.5")
	assert_test(def_default.health_regen.flee_threshold == 15,
		"Unconfigured mob receives default flee threshold = 25%")
	assert_test(def_default.health_regen.return_threshold == 36,
		"Unconfigured mob receives default return threshold = 60%")
	assert_test(def_default.health_regen.overlay == true, "Unconfigured mob receives default regen overlay = true")
end

-- TEST 11: on_return_to_fight Callback
do
	local mock_obj = make_mock_object(9, 40)
	local returned = false
	local mob = {
		hp = 9,
		hp_max = 40,
		state = "idle",
		on_return_to_fight = function(_self)
			returned = true
		end,
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)

	-- Enter fleeing
	mob_memory.update_health_regen(mob, 0.1, 0.25, 0.60, 10.0)
	assert_test(mob.state == "fleeing", "Mob enters fleeing state")

	-- Regenerate past 24 HP return threshold
	mob_memory.update_health_regen(mob, 2.0, 0.25, 0.60, 10.0)
	assert_test(returned == true, "on_return_to_fight callback is executed on return threshold recovery")
end

-- TEST 12: Overhead Health Bar Synchronization
do
	local mock_obj = make_mock_object(10, 40)
	local mob = {
		hp = 10,
		hp_max = 40,
		state = "fleeing",
		health_regen = {
			rate = 2.0,
		},
		object = mock_obj,
	}
	mock_obj._luaentity = mob
	mob_memory.init_memory(mob)
	mob.memory.flee_state = true

	mob_memory.update_health_regen(mob, 1.0)
	assert_test(mob._health_bar_obj ~= nil and mob._health_bar_obj:is_valid(),
		"Health bar entity is attached and updated upon health regeneration")
end

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)",
	passed_tests, total_tests, (passed_tests / total_tests) * 100))
print("==================================================")
assert_test(passed_tests == total_tests, "All health regeneration tests passed!")
