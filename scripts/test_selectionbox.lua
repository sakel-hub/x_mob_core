--[[
	test_selectionbox.lua - Test Suite for Mob Bounding Box & Selection Box Invariants
	Validates:
	1. Auto-generated selectionbox is derived from collisionbox without forcing rotate = true.
	2. Top-level def.selectionbox is migrated to initial_properties without forcing rotate = true.
	3. initial_properties.selectionbox preserves explicit coordinates.
	4. Explicit rotate = false is preserved.
	5. Explicit rotate = true is preserved if explicitly set by author.
	6. Activated mob entity instance initializes self.collisionbox and self.selectionbox.
	7. mob_ai.register_pathfinding_mob preserves selectionbox without forcing rotate = true.
]]
-- luacheck: globals core minetest x_mob_core

-- Minimal Luanti Engine Mock
local registered_entities = {}
local settings_store = {}

core = {
	settings = {
		get = function(_self, key) return settings_store[key] end,
		get_bool = function(_self, key, default)
			if settings_store[key] == nil then return default end
			return settings_store[key] == "true" or settings_store[key] == true
		end,
	},
	get_modpath = function(modname)
		if modname == "x_mob_core" then return "." end
		return nil
	end,
	registered_entities = registered_entities,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	deserialize = function() return nil end,
	after = function() end,
	log = function() end,
	register_on_mods_loaded = function() end,
	register_globalstep = function() end,
	get_us_time = function() return 1000000 end,
	get_node_or_nil = function() return {name = "air"} end,
	get_node = function() return {name = "air"} end,
	registered_nodes = { air = {walkable = false} },
	get_objects_inside_radius = function() return {} end,
	get_connected_players = function() return {} end,
}
minetest = core

-- Mock x_mob_core global for subsystem dependencies
x_mob_core = {
	emit = function() end,
	listen = function() end,
	events = {
		emit = function() end,
		listen = function() end,
	},
	pack = {
		coordination = {
			unregister_member = function() end,
			handle_member_step = function() end,
		},
		squad = {
			handle_leader_death = function() end,
			step_followers = function() end,
		},
		swarm = {
			step = function() end,
		},
		shoal = {
			step = function() end,
		},
	},
	combat = {
		health_bar = {
			remove = function() end,
		},
	},
	animator = {
		play = function() end,
	},
}
_G.x_mob_core = x_mob_core

local properties = dofile("lifecycle/properties.lua")
local entity_wrapper = dofile("lifecycle/entity_wrapper.lua")
local mob_ai = dofile("motor/mob_ai.lua")

local total_tests = 0
local passed_tests = 0

local function run_test(name, fn)
	total_tests = total_tests + 1
	local ok, err = pcall(fn)
	if ok then
		passed_tests = passed_tests + 1
		print("  [PASS] " .. name)
	else
		print("  [FAIL] " .. name .. ": " .. tostring(err))
	end
end

print("==================================================")
print("  Running x_mob_core Bounding Box Test Suite")
print("==================================================")

-- 1. Unconfigured selectionbox auto-generation derives from collisionbox
run_test("Auto-generated selectionbox derives from collisionbox without forcing rotate", function()
	local def = {
		collisionbox = {-0.4, 0.0, -0.4, 0.4, 1.8, 0.4},
	}
	properties.resolve_mob_properties(def)
	local sbox = def.initial_properties.selectionbox
	assert(sbox ~= nil, "selectionbox must be generated")
	assert(sbox.rotate ~= true, "selectionbox must not enforce rotate = true")
	assert(sbox[1] == -0.45 and sbox[2] == 0.0 and sbox[3] == -0.45, "sbox min bounds match")
	assert(sbox[4] == 0.45 and sbox[5] == 1.85 and sbox[6] == 0.45, "sbox max bounds match")
end)

-- 2. Top-level def.selectionbox migrated without forcing rotate
run_test("Top-level def.selectionbox preserved without forcing rotate = true", function()
	local def = {
		selectionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
	}
	properties.resolve_mob_properties(def)
	local sbox = def.initial_properties.selectionbox
	assert(sbox ~= nil, "selectionbox must be migrated to initial_properties")
	assert(sbox.rotate ~= true, "selectionbox.rotate must not be forced")
	assert(sbox[1] == -0.5 and sbox[6] == 0.5, "selectionbox coordinates intact")
end)

-- 3. initial_properties.selectionbox preserved without forcing rotate
run_test("initial_properties.selectionbox preserved without forcing rotate = true", function()
	local def = {
		initial_properties = {
			selectionbox = {-0.6, -0.2, -0.6, 0.6, 0.8, 0.6},
		},
	}
	properties.resolve_mob_properties(def)
	local sbox = def.initial_properties.selectionbox
	assert(sbox ~= nil, "selectionbox exists")
	assert(sbox.rotate ~= true, "selectionbox.rotate must not be forced")
	assert(sbox[1] == -0.6 and sbox[4] == 0.6, "selectionbox coordinates intact")
end)

-- 4. Explicit rotate = false is preserved
run_test("Explicit rotate = false is preserved and never overridden", function()
	local def = {
		selectionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, rotate = false},
	}
	properties.resolve_mob_properties(def)
	local sbox = def.initial_properties.selectionbox
	assert(sbox ~= nil, "selectionbox exists")
	assert(sbox.rotate == false, "selectionbox.rotate must remain false")
end)

-- 5. Explicit rotate = true is preserved
run_test("Explicit rotate = true is preserved", function()
	local def = {
		selectionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5, rotate = true},
	}
	properties.resolve_mob_properties(def)
	local sbox = def.initial_properties.selectionbox
	assert(sbox ~= nil, "selectionbox exists")
	assert(sbox.rotate == true, "selectionbox.rotate must remain true")
end)

-- 6. Entity instance initialization assigns self.collisionbox and self.selectionbox
run_test("Activated mob entity assigns self.collisionbox and self.selectionbox", function()
	local def = {
		collisionbox = {-0.25, 0.0, -0.25, 0.25, 0.35, 0.25},
		selectionbox = {-0.54, -0.41, -0.54, 0.54, 0.41, 0.54},
	}
	entity_wrapper.register_mob("test:mob", def)
	assert(registered_entities["test:mob"] ~= nil, "entity must be registered")

	local instance = {
		play_animation = function() end,
		set_animation = function() end,
	}
	local obj = {
		is_valid = function() return true end,
		get_pos = function() return {x = 0, y = 0, z = 0} end,
		set_armor_groups = function() end,
		set_hp = function() end,
		set_properties = function() end,
		set_acceleration = function() end,
		set_velocity = function() end,
		get_animations = function() return {} end,
		set_animation = function() end,
		play_animation = function() end,
		stop_animation = function() end,
		get_luaentity = function() return instance end,
		get_properties = function() return {} end,
		get_texture_mod = function() return "" end,
		set_texture_mod = function() end,
	}
	instance.object = obj
	registered_entities["test:mob"].on_activate(instance, "")
	assert(instance.collisionbox ~= nil, "instance.collisionbox must be assigned on activate")
	assert(instance.collisionbox[1] == -0.25 and instance.collisionbox[5] == 0.35, "collisionbox bounds match")
	assert(instance.selectionbox ~= nil, "instance.selectionbox must be assigned on activate")
	assert(instance.selectionbox.rotate ~= true, "instance.selectionbox.rotate must not be forced to true")
	assert(instance.selectionbox[1] == -0.54 and instance.selectionbox[4] == 0.54, "coords intact")
end)

-- 7. mob_ai.register_pathfinding_mob preserves selectionbox without forcing rotate
run_test("mob_ai.register_pathfinding_mob preserves selectionbox without forcing rotate", function()
	local def = {
		selectionbox = {-0.3, 0.0, -0.3, 0.3, 1.5, 0.3},
	}
	mob_ai.register_pathfinding_mob("test:pathfinding_mob", def)
	local reg = registered_entities["test:pathfinding_mob"]
	assert(reg ~= nil, "pathfinding mob registered")
	assert(reg.initial_properties.selectionbox ~= nil, "selectionbox migrated")
	assert(reg.initial_properties.selectionbox.rotate ~= true, "selectionbox.rotate must not be forced")
end)

print("==================================================")
local pct = (passed_tests / total_tests) * 100
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", passed_tests, total_tests, pct))
print("==================================================")

if passed_tests == total_tests then
	print("All bounding box tests passed successfully!")
else
	error("Some tests failed!")
end
