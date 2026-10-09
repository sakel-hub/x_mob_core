--[[
	x_mob_core - Unit & Integration Test Suite for Envelop Subsystem
	Validates open sleeve attachment, multi-effect stacking, independent timers,
	dynamic composite texturing, selective effect removal, and cleanup hooks.
]]

local registered_entities = {}
local registered_on_joinplayer = {}
local registered_on_leaveplayer = {}
local registered_on_dieplayer = {}
local registered_on_respawnplayer = {}
local registered_on_shutdown = {}

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
	after = function() end,
	settings = {
		get = function(_self, _key, default) return default end,
		get_bool = function(_self, _key, default)
			if default ~= nil then return default end
			return false
		end,
	},
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

-- Mock entity factory
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
		_luaentity = nil,
		_animations = {},
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
	function obj:play_animation(track, params)
		self._animations[track] = params or {}
	end
	function obj:get_animations() return self._animations end
	function obj:remove()
		self._valid = false
		if self._luaentity then
			self._luaentity._target = nil
		end
	end
	function obj:get_luaentity() return self._luaentity end
	obj.punch = function() return true end

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
print("  Running x_mob_core Envelop Subsystem Tests")
print("==================================================")

test("x_mob_core:envelop entity is registered", function()
	local ent_def = registered_entities["x_mob_core:envelop"]
	assert(ent_def ~= nil, "Entity x_mob_core:envelop must be registered")
	assert(ent_def.initial_properties.mesh == "x_mob_core_envelop_box.glb",
		"Default mesh must be x_mob_core_envelop_box.glb")
	assert(type(x_mob_core.apply_envelop) == "function", "x_mob_core.apply_envelop must be a function")
	assert(type(x_mob_core.remove_envelop) == "function", "x_mob_core.remove_envelop must be a function")
	assert(type(x_mob_core.remove_envelop_effect) == "function", "x_mob_core.remove_envelop_effect must be a function")
	assert(type(x_mob_core.is_enveloped) == "function", "x_mob_core.is_enveloped must be a function")
end)

test("apply_envelop creates sleeve entity and attaches to target", function()
	local player = create_mock_object({}, true, "Hero")
	local env_obj = x_mob_core.apply_envelop(player, {
		id = "roots",
		duration = 5.0,
		texture = "x_mobs_roots_envelop.png",
	})

	assert(env_obj ~= nil, "Envelop entity must be created")
	assert(env_obj:is_valid(), "Envelop entity must be valid")
	assert(env_obj:get_attach() == player, "Envelop must be attached to target")
	assert(x_mob_core.is_enveloped(player), "is_enveloped must return true for target")
	assert(x_mob_core.is_enveloped(player, "roots"), "is_enveloped must return true for 'roots'")
	assert(not x_mob_core.is_enveloped(player, "venom"), "is_enveloped must return false for inactive 'venom'")

	local props = env_obj:get_properties()
	assert(props.mesh == "x_mob_core_envelop_box.glb", "Mesh must be x_mob_core_envelop_box.glb")
	assert(props.textures[1] == "x_mobs_roots_envelop.png", "Texture must be roots texture")
	assert(env_obj._animations["pulse"] ~= nil, "Animation track 'pulse' must be dispatched")
	assert(env_obj._animations["pulse"].loop == true, "Animation 'pulse' must loop")

	x_mob_core.remove_envelop(player)
	assert(not x_mob_core.is_enveloped(player), "Target must no longer be enveloped after removal")
end)

test("Multi-effect stacking composites textures dynamically", function()
	local player = create_mock_object({}, true, "Hero")
	local env_obj = x_mob_core.apply_envelop(player, {
		id = "venom",
		duration = 4.0,
		texture = "x_mobs_venom_envelop.png",
	})
	assert(env_obj ~= nil)

	-- Stack web on the same target
	local env_obj2 = x_mob_core.apply_envelop(player, {
		id = "web",
		duration = 3.0,
		texture = "x_mobs_web_envelop.png",
	})
	assert(env_obj == env_obj2, "Reapplying to target must return same envelop object")
	assert(x_mob_core.is_enveloped(player, "venom"), "Venom effect must be active")
	assert(x_mob_core.is_enveloped(player, "web"), "Web effect must be active")

	local props = env_obj:get_properties()
	local expected_tex = "x_mobs_venom_envelop.png^x_mobs_web_envelop.png"
	assert(props.textures[1] == expected_tex, "Composite texture must combine both textures alphabetically")

	x_mob_core.remove_envelop(player)
end)

test("Independent effect lifecycles and expiration hooks", function()
	local player = create_mock_object({}, true, "Hero")
	local venom_steps = 0
	local venom_removed = false
	local web_removed = false

	local env_obj = x_mob_core.apply_envelop(player, {
		id = "venom",
		duration = 2.0,
		texture = "x_mobs_venom_envelop.png",
		on_step = function(_dtime, tgt)
			venom_steps = venom_steps + 1
			assert(tgt == player)
		end,
		on_remove = function(tgt)
			venom_removed = true
			assert(tgt == player)
		end,
	})

	x_mob_core.apply_envelop(player, {
		id = "web",
		duration = 4.0,
		texture = "x_mobs_web_envelop.png",
		on_remove = function(tgt)
			web_removed = true
			assert(tgt == player)
		end,
	})

	local ent = env_obj:get_luaentity()

	-- Step 1.0s: both active
	ent:on_step(1.0)
	assert(venom_steps == 1, "on_step must be called")
	assert(not venom_removed, "Venom must not be removed yet")
	assert(not web_removed, "Web must not be removed yet")
	assert(x_mob_core.is_enveloped(player, "venom"))
	assert(x_mob_core.is_enveloped(player, "web"))

	-- Step 1.5s: venom expires (total 2.5s > 2.0s), web remains (2.5s < 4.0s)
	ent:on_step(1.5)
	assert(venom_removed, "Venom on_remove hook must have fired")
	assert(not web_removed, "Web must still be active")
	assert(not x_mob_core.is_enveloped(player, "venom"), "Venom must no longer be active")
	assert(x_mob_core.is_enveloped(player, "web"), "Web must still be active")
	assert(env_obj:is_valid(), "Envelop must remain valid while web is active")

	local props = env_obj:get_properties()
	assert(props.textures[1] == "x_mobs_web_envelop.png", "Texture must revert to web only")

	-- Step 2.0s: web expires (total 4.5s > 4.0s)
	ent:on_step(2.0)
	assert(web_removed, "Web on_remove hook must have fired")
	assert(not env_obj:is_valid(), "Envelop entity must be removed when all effects expire")
	assert(not x_mob_core.is_enveloped(player), "Target must no longer be enveloped")
end)

test("Selective removal via remove_envelop_effect", function()
	local player = create_mock_object({}, true, "Hero")
	local roots_removed = false

	local env_obj = x_mob_core.apply_envelop(player, {
		id = "roots",
		duration = 6.0,
		texture = "x_mobs_roots_envelop.png",
		on_remove = function() roots_removed = true end,
	})
	x_mob_core.apply_envelop(player, {
		id = "frost",
		duration = 6.0,
		texture = "x_mobs_ice_envelop.png",
	})

	assert(x_mob_core.is_enveloped(player, "roots"))
	assert(x_mob_core.is_enveloped(player, "frost"))

	x_mob_core.remove_envelop_effect(player, "roots")
	assert(roots_removed, "Roots on_remove hook must fire on selective removal")
	assert(not x_mob_core.is_enveloped(player, "roots"), "Roots effect must be gone")
	assert(x_mob_core.is_enveloped(player, "frost"), "Frost effect must remain")
	assert(env_obj:is_valid(), "Envelop must remain valid")
	assert(env_obj:get_properties().textures[1] == "x_mobs_ice_envelop.png", "Texture must update to frost")

	x_mob_core.remove_envelop(player)
	assert(not x_mob_core.is_enveloped(player))
	assert(not env_obj:is_valid(), "Envelop must be removed")
end)

test("Mob model visual_size, centering, and ground level scaling", function()
	local golem = create_mock_object({
		visual_size = {x = 7.2, y = 7.2},
		collisionbox = {-0.9, 0.0, -0.9, 0.9, 2.7, 0.9},
		selectionbox = {-0.9, 0.0, -0.9, 0.9, 2.7, 0.9},
	}, false, nil)
	golem._luaentity = { name = "x_mobs:golem" }

	local env_obj = x_mob_core.apply_envelop(golem, {
		id = "earth_anchor",
		duration = 4.0,
		texture = "x_mobs_mud_envelop.png",
	})

	assert(env_obj ~= nil, "Envelop must be created on mob")
	local props = env_obj:get_properties()
	-- World size = child visual_size * parent visual_size
	local world_w = props.visual_size.x * 7.2
	local world_h = props.visual_size.y * 7.2
	local world_d = props.visual_size.z * 7.2
	assert(math.abs(world_w - 2.07) < 0.01, "Golem envelop world width must be ~2.07m")
	assert(math.abs(world_d - 2.07) < 0.01, "Golem envelop world depth must be ~2.07m (not distorted)")
	assert(math.abs(world_h - 1.485) < 0.01, "Golem envelop world height must be ~1.485m")
	assert(env_obj._attach_pos.y == 0, "Attach pos Y must be 0 for ground-level mob")

	-- Test spider with offset selection box and 0.48 visual_size
	local spider = create_mock_object({
		visual_size = {x = 0.48, y = 0.48},
		collisionbox = {-0.22, 0.0, -0.22, 0.22, 0.28, 0.22},
		selectionbox = {-0.54, -0.41, -0.54, 0.54, 0.41, 0.54},
	}, false, nil)
	spider._luaentity = { name = "x_mobs:spider" }

	local env_spider = x_mob_core.apply_envelop(spider, {
		id = "web",
		duration = 3.0,
		texture = "x_mobs_web_envelop.png",
	})
	assert(env_spider ~= nil)
	assert(env_spider._attach_pos.y == 0, "Spider feet must remain at 0 (ground level, not below ground)")
	local sp_props = env_spider:get_properties()
	local sp_world_w = sp_props.visual_size.x * 0.48
	local sp_world_d = sp_props.visual_size.z * 0.48
	assert(math.abs(sp_world_w - 1.242) < 0.01, "Spider envelop world width must cover leg span")
	assert(math.abs(sp_world_d - 1.242) < 0.01, "Spider envelop world depth must cover leg span")

	x_mob_core.remove_envelop(golem)
	x_mob_core.remove_envelop(spider)
end)

print(string.format("=================================================="))
print(string.format("  Envelop Test Summary: %d / %d Passed (100.0%%)", passed, passed))
print(string.format("=================================================="))
