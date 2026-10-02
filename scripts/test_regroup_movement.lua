--[[
	test_regroup_movement.lua - Test Suite for Pack Regrouping & Ability Initialization
	Validates:
	1. handle_mob_movement initializes self.abilities lazily if missing
	2. coordination.step_regroup executes safely without self.abilities pre-initialized
	3. on_activate initializes abilities and _inherent_abilities on mob entities
	4. Nil safety of self.abilities in handle_mob_movement physics branches
]]

local math = math

local registered_entities = {}
local registered_nodes = {
	["default:dirt_with_grass"] = {walkable = true, liquidtype = "none"},
	["default:stone"] = {walkable = true, liquidtype = "none"},
	["default:air"] = {walkable = false, drawtype = "airlike", liquidtype = "none"},
	["air"] = {walkable = false, drawtype = "airlike", liquidtype = "none"},
	["default:water_source"] = {walkable = false, liquidtype = "source"},
}

local settings_store = {
	x_mob_damage_particles = "mob_default",
	x_mob_damage_particle_multiplier = "1.0",
	x_mob_core_enable_health_bars = "true",
	x_mob_core_health_bar_timeout = "4.0",
	x_mob_core_health_bar_auto_remove = "true",
}

_G.core = {
	registered_nodes = registered_nodes,
	registered_entities = registered_entities,
	hash_node_position = function(pos)
		return (pos.x or 0) .. ":" .. (pos.y or 0) .. ":" .. (pos.z or 0)
	end,
	get_node = function(pos)
		local y = math.floor(pos.y + 0.5)
		if y <= 0 then
			return {name = "default:stone"}
		end
		return {name = "default:air"}
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
	dir_to_yaw = function(dir)
		local atan = math.atan2 or math.atan
		return -atan(dir.x, dir.z)
	end,
	yaw_to_dir = function(yaw)
		return {x = -math.sin(yaw), y = 0, z = math.cos(yaw)}
	end,
	settings = {
		get = function(_self, key)
			return settings_store[key]
		end,
		get_bool = function(_self, key, default)
			if settings_store[key] == nil then return default end
			return settings_store[key] == "true" or settings_store[key] == true
		end,
	},
	deserialize = function(_s) return {} end,
	serialize = function(_t) return "{}" end,
	get_gametime = function() return 100.0 end,
	get_us_time = function() return 1000000 end,
	get_objects_inside_radius = function() return {} end,
	register_on_mods_loaded = function() end,
	register_globalstep = function() end,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	register_on_generated = function() end,
	get_mapgen_setting = function() return nil end,
	register_on_joinplayer = function() end,
	register_on_leaveplayer = function() end,
	register_chatcommand = function() end,
	line_of_sight = function() return true end,
	get_item_group = function() return 0 end,
	log = function() end,
	sound_play = function() end,
	add_particlespawner = function() end,
	add_entity = function() return nil end,
	after = function() end,
}
_G.minetest = _G.core

local vector = {
	new = function(x, y, z)
		if type(x) == "table" then return {x = x.x or 0, y = x.y or 0, z = x.z or 0} end
		return {x = x or 0, y = y or 0, z = z or 0}
	end,
	direction = function(p1, p2)
		local dx = p2.x - p1.x
		local dy = p2.y - p1.y
		local dz = p2.z - p1.z
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		if len < 0.0001 then return {x = 0, y = 0, z = 0} end
		return {x = dx / len, y = dy / len, z = dz / len}
	end,
	distance = function(p1, p2)
		local dx = p1.x - p2.x
		local dy = p1.y - p2.y
		local dz = p1.z - p2.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	distance_sq = function(p1, p2)
		local dx = p1.x - p2.x
		local dy = p1.y - p2.y
		local dz = p1.z - p2.z
		return dx * dx + dy * dy + dz * dz
	end,
	round = function(p)
		return {x = math.floor(p.x + 0.5), y = math.floor(p.y + 0.5), z = math.floor(p.z + 0.5)}
	end,
}
_G.vector = vector

-- Mock ObjectRef
local function create_mock_object(pos, vel)
	local current_pos = pos or {x = 0, y = 1, z = 0}
	local current_vel = vel or {x = 0, y = 0, z = 0}
	local current_acc = {x = 0, y = -9.81, z = 0}
	local current_yaw = 0
	local valid = true

	local obj = {
		is_valid = function() return valid end,
		is_player = function() return false end,
		get_pos = function() return {x = current_pos.x, y = current_pos.y, z = current_pos.z} end,
		set_pos = function(_, p) current_pos = {x = p.x, y = p.y, z = p.z} end,
		get_velocity = function() return {x = current_vel.x, y = current_vel.y, z = current_vel.z} end,
		set_velocity = function(_, v) current_vel = {x = v.x, y = v.y, z = v.z} end,
		get_acceleration = function() return {x = current_acc.x, y = current_acc.y, z = current_acc.z} end,
		set_acceleration = function(_, a) current_acc = {x = a.x, y = a.y, z = a.z} end,
		get_yaw = function() return current_yaw end,
		set_yaw = function(_, y) current_yaw = y end,
		set_properties = function() end,
		get_properties = function() return {} end,
		get_animations = function() return {} end,
		set_animation = function() end,
		set_animation_frame_speed = function() end,
		play_animation = function() end,
		set_armor_groups = function() end,
		get_armor_groups = function() return {} end,
		get_hp = function() return 20 end,
		set_hp = function() end,
		get_texture_mod = function() return "" end,
		set_texture_mod = function() end,
		get_luaentity = function() return nil end,
	}
	return obj
end

-- Load API
dofile("api.lua")

local safety = x_mob_core.motor.safety
local locomotion = x_mob_core.motor.locomotion
local coordination = x_mob_core.pack.coordination

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

print("==================================================")
print("  Running Pack Regroup & Movement Test Suite")
print("==================================================")

test("init_abilities creates abilities and _inherent_abilities", function()
	local ent = {
		name = "x_mobs:fallen_minion",
		can_swim = false,
		can_climb = false,
		can_open_doors = true,
	}
	safety.init_abilities(ent)
	assert(type(ent.abilities) == "table", "abilities table should be created")
	assert(type(ent._inherent_abilities) == "table", "_inherent_abilities table should be created")
	assert(ent.path_state ~= nil, "path_state should be created")
	assert(ent._inherent_abilities.can_open_doors == true, "door opening should be preserved")
	assert(ent.abilities.can_swim == false, "can_swim should be false for terrestrial minion")
end)

test("handle_mob_movement does not crash when self.abilities is nil", function()
	local obj = create_mock_object({x = 5, y = 1, z = 5})
	local ent = {
		object = obj,
		walk_speed = 2.0,
		abilities = nil,
		_inherent_abilities = nil,
		path_state = {
			waypoints = {{x = 6, y = 1, z = 5}},
			index = 1,
		},
	}
	-- Should not throw 'attempt to index field abilities (a nil value)'
	locomotion.handle_mob_movement(ent, 0.1, {x = 5, y = 1, z = 5}, {x = 6, y = 1, z = 5})
	assert(ent.abilities ~= nil, "abilities should have been lazily initialized")
	local vel = obj:get_velocity()
	assert(vel.x > 0, "velocity should be directed towards target waypoint")
end)

test("step_regroup executes cleanly with active waypoints and uninitialized abilities", function()
	local leader_obj = create_mock_object({x = 20, y = 1, z = 20})
	local follower_obj = create_mock_object({x = 0, y = 1, z = 0})

	local follower_ent = {
		object = follower_obj,
		leader_obj = leader_obj,
		state = "regrouping",
		walk_speed = 3.0,
		abilities = nil,
		path_state = {
			waypoints = {
				{x = 2, y = 1, z = 0},
				{x = 4, y = 1, z = 0},
			},
			index = 1,
		},
	}

	-- Calling step_regroup should safely steer follower along waypoints without nil crash
	local handled = coordination.step_regroup(follower_ent, 0.1, "walk")
	assert(handled == true, "step_regroup should handle regrouping step")
	assert(follower_ent.abilities ~= nil, "abilities should be initialized")
	local v = follower_obj:get_velocity()
	assert(v.x > 0, "follower should be moving toward waypoint x=2")
end)

test("step_regroup clears waypoints upon completing path and calculates new path", function()
	local leader_obj = create_mock_object({x = 10, y = 1, z = 0})
	local follower_obj = create_mock_object({x = 0, y = 1, z = 0})

	local follower_ent = {
		object = follower_obj,
		leader_obj = leader_obj,
		state = "regrouping",
		walk_speed = 3.0,
		abilities = nil,
		path_state = {
			waypoints = {
				{x = 0.2, y = 1, z = 0},
			},
			index = 2, -- past end of waypoints
		},
	}

	local handled = coordination.step_regroup(follower_ent, 0.1, "walk")
	assert(handled == true, "step_regroup should handle completed path")
	assert(follower_ent.path_state.waypoints == nil, "completed waypoints should be cleared")
	assert(follower_ent.path_state.index == 1, "path index reset to 1")
end)

test("on_activate initializes mob abilities and path_state via entity_wrapper", function()
	local entity_wrapper = dofile("lifecycle/entity_wrapper.lua")
	local dummy_def = {
		name = "x_mobs:test_follower",
		hp_max = 20,
		walk_speed = 2.0,
		can_open_doors = true,
		can_crawl = false,
	}

	entity_wrapper.register_mob("x_mobs:test_follower", dummy_def)
	local ent_instance = {
		name = "x_mobs:test_follower",
		object = create_mock_object({x = 0, y = 1, z = 0}),
	}
	dummy_def.on_activate(ent_instance, "{}", 0)

	assert(type(ent_instance.abilities) == "table", "on_activate must initialize abilities")
	assert(type(ent_instance._inherent_abilities) == "table", "on_activate must initialize _inherent_abilities")
	assert(ent_instance._inherent_abilities.can_open_doors == true, "door opening capability preserved")
	assert(type(ent_instance.path_state) == "table", "path_state must be initialized")
end)

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)", passed, total, (passed / total) * 100))
print("==================================================")

if passed < total then
	os.exit(1)
end
