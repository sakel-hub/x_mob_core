--[[
	test_health_bar.lua - Comprehensive Test Suite for Mob Health Bar Subsystem
	Validates:
	1. Default configuration merging and mob-specific overrides
	2. 5-tier color resolution (Emerald Green -> Lime -> Gold -> Orange -> Red)
	3. Custom color threshold resolution
	4. [combine: texture modifier compositing (canvas, border, track, fill)
	5. Full and zero health boundary conditions in texture generation
	6. Zero-allocation texture string memoization caching
	7. Proportional visual sizing based on mob collisionbox dimensions
	8. Vertical spacing and nametag clearance calculation
	9. Lazy child entity spawning and attachment on damage intake
	10. Timeout reset mechanics on repeated damage within the active window
	11. Auto-removal vs soft-hide behavior upon timer expiration
	12. Instant detachment and removal on lethal death
]]

local math = math

-- Minimal Luanti Engine Mock
local mock_entities = {}
local registered_entities = {}
local settings_store = {
	x_mob_core_enable_health_bars = "true",
	x_mob_core_health_bar_timeout = "4.0",
	x_mob_core_health_bar_auto_remove = "true",
}

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
			local f = io.open("mods/x_mob_core/api.lua", "r")
			if f then f:close() return "mods/x_mob_core" end
			return "."
		end
		return nil
	end,
	registered_entities = registered_entities,
	register_entity = function(name, def)
		registered_entities[name] = def
	end,
	add_entity = function(pos, name)
		local def = registered_entities[name]
		if not def then return nil end

		local obj = {
			_pos = { x = pos.x, y = pos.y, z = pos.z },
			_properties = {},
			_attached_to = nil,
			_attach_bone = nil,
			_attach_pos = nil,
			_attach_rot = nil,
			_removed = false,
			_armor_groups = {},
		}

		if def.initial_properties then
			for k, v in pairs(def.initial_properties) do
				obj._properties[k] = v
			end
		end

		function obj:is_valid()
			return not self._removed
		end

		function obj:get_pos()
			return self._pos
		end

		function obj:set_properties(props)
			for k, v in pairs(props) do
				self._properties[k] = v
			end
		end

		function obj:get_properties()
			return self._properties
		end

		function obj:set_attach(parent, bone, p, r)
			self._attached_to = parent
			self._attach_bone = bone
			self._attach_pos = p
			self._attach_rot = r
		end

		function obj:get_attach()
			return self._attached_to
		end

		function obj:set_detach()
			self._attached_to = nil
		end

		function obj:remove()
			self._removed = true
		end

		function obj:set_armor_groups(groups)
			self._armor_groups = groups
		end

		local ent = {}
		for k, v in pairs(def) do
			ent[k] = v
		end
		ent.object = obj
		obj.get_luaentity = function() return ent end

		if ent.on_activate then
			ent:on_activate()
		end

		mock_entities[#mock_entities + 1] = obj
		return obj
	end,
}
_G.core = core
_G.minetest = core

-- Load health bar subsystem under test
local modpath = core.get_modpath("x_mob_core")
local health_bar = dofile(modpath .. "/combat/health_bar.lua")

-- Test Runner Assertions
local total_tests = 0
local passed_tests = 0

local function run_test(name, fn)
	total_tests = total_tests + 1
	local ok, err = pcall(fn)
	if ok then
		passed_tests = passed_tests + 1
		print(string.format("  [PASS] %s", name))
	else
		print(string.format("  [FAIL] %s: %s", name, tostring(err)))
	end
end

print("==================================================")
print("  Running x_mob_core Health Bar Subsystem Tests")
print("==================================================")

-- 1. Configuration Resolution
run_test("get_config returns default 5-tier colors and timeout", function()
	local cfg = health_bar.get_config({})
	assert(cfg.enabled == true, "Health bar should be enabled by default")
	assert(cfg.timeout == 4.0, "Default timeout should be 4.0")
	assert(cfg.width == 64, "Default width should be 64")
	assert(cfg.height == 8, "Default height should be 8")
	assert(cfg.auto_remove == true, "Default auto_remove should be true")
	assert(#cfg.colors == 5, "Should have 5 color tiers")
	assert(cfg.colors[1].threshold == 0.80, "Tier 1 threshold should be 0.80")
	assert(cfg.colors[1].color == "#00FF00", "Tier 1 color should be #00FF00")
end)

run_test("get_config honors mob definition overrides", function()
	local def = {
		health_bar = {
			width = 96,
			height = 12,
			timeout = 6.5,
			auto_remove = false,
			colors = {
				{ threshold = 0.5, color = "#0000FF" },
				{ threshold = 0.0, color = "#FF0000" },
			},
		},
	}
	local cfg = health_bar.get_config(def)
	assert(cfg.width == 96, "Width should be overridden to 96")
	assert(cfg.height == 12, "Height should be overridden to 12")
	assert(cfg.timeout == 6.5, "Timeout should be overridden to 6.5")
	assert(cfg.auto_remove == false, "Auto_remove should be overridden to false")
	assert(#cfg.colors == 2, "Colors should have 2 custom tiers")
end)

run_test("get_config disables health bar when health_bar = false", function()
	local cfg = health_bar.get_config({ health_bar = false })
	assert(cfg.enabled == false, "Health bar should be disabled")
end)

-- 2. 5-Tier Color Resolution
run_test("resolve_color returns emerald green for HP > 80%", function()
	local col1 = health_bar.resolve_color(1.0)
	local col2 = health_bar.resolve_color(0.85)
	local col3 = health_bar.resolve_color(0.80)
	assert(col1 == "#00FF00", "100% HP should be #00FF00")
	assert(col2 == "#00FF00", "85% HP should be #00FF00")
	assert(col3 == "#00FF00", "80% HP should be #00FF00")
end)

run_test("resolve_color returns lime for HP between 60% and 80%", function()
	local col1 = health_bar.resolve_color(0.79)
	local col2 = health_bar.resolve_color(0.60)
	assert(col1 == "#7CFC00", "79% HP should be #7CFC00 (Lime)")
	assert(col2 == "#7CFC00", "60% HP should be #7CFC00 (Lime)")
end)

run_test("resolve_color returns golden yellow for HP between 40% and 60%", function()
	local col1 = health_bar.resolve_color(0.55)
	local col2 = health_bar.resolve_color(0.40)
	assert(col1 == "#FFD700", "55% HP should be #FFD700 (Gold)")
	assert(col2 == "#FFD700", "40% HP should be #FFD700 (Gold)")
end)

run_test("resolve_color returns dark orange for HP between 20% and 40%", function()
	local col1 = health_bar.resolve_color(0.35)
	local col2 = health_bar.resolve_color(0.20)
	assert(col1 == "#FF8C00", "35% HP should be #FF8C00 (Dark Orange)")
	assert(col2 == "#FF8C00", "20% HP should be #FF8C00 (Dark Orange)")
end)

run_test("resolve_color returns crimson red for HP <= 20%", function()
	local col1 = health_bar.resolve_color(0.19)
	local col2 = health_bar.resolve_color(0.05)
	local col3 = health_bar.resolve_color(0.00)
	assert(col1 == "#FF2200", "19% HP should be #FF2200 (Crimson Red)")
	assert(col2 == "#FF2200", "5% HP should be #FF2200 (Crimson Red)")
	assert(col3 == "#FF2200", "0% HP should be #FF2200 (Crimson Red)")
end)

run_test("resolve_color evaluates custom color tiers accurately", function()
	local custom_colors = {
		{ threshold = 0.5, color = "#123456" },
		{ threshold = 0.0, color = "#654321" },
	}
	assert(health_bar.resolve_color(0.8, custom_colors) == "#123456")
	assert(health_bar.resolve_color(0.5, custom_colors) == "#123456")
	assert(health_bar.resolve_color(0.49, custom_colors) == "#654321")
	assert(health_bar.resolve_color(0.0, custom_colors) == "#654321")
end)

-- 3. [combine: Texture Modifier Compositing & Caching
run_test("get_texture builds valid [combine: string with outer border, track, and fill", function()
	local tex = health_bar.get_texture(64, 8, 1, 31, "#00FF00", "#111111", "#330000")
	assert(tex:find("^%[combine:64x8"), "Must start with canvas declaration [combine:64x8")
	assert(tex:find(":0,0=%[combine\\:64x8\\%^%[noalpha\\%^%[colorize\\:#111111\\:255"), "Must have outer border layer")
	assert(tex:find(":1,1=%[combine\\:62x6\\%^%[noalpha\\%^%[colorize\\:#330000\\:255"), "Must have depleted track layer")
	assert(tex:find(":1,1=%[combine\\:31x6\\%^%[noalpha\\%^%[colorize\\:#00FF00\\:255"), "Must have dynamic fill layer")
	assert(not tex:find("%("), "Must not contain opening parenthesis inside modifier")
	assert(not tex:find("%)"), "Must not contain closing parenthesis inside modifier")
end)

run_test("get_texture handles zero health without emitting empty fill layer", function()
	local tex = health_bar.get_texture(64, 8, 1, 0, "#FF2200", "#111111", "#330000")
	assert(tex:find("^%[combine:64x8"), "Must start with canvas declaration")
	assert(tex:find(":1,1=%[combine\\:62x6\\%^%[noalpha\\%^%[colorize\\:#330000\\:255"), "Must retain track layer")
	assert(not tex:find("%[colorize\\:#FF2200"), "Must not contain active fill layer when fill_w is 0")
end)

run_test("get_texture memoization returns identical cached string instances", function()
	local tex1 = health_bar.get_texture(64, 8, 1, 45, "#7CFC00", "#111111", "#330000")
	local tex2 = health_bar.get_texture(64, 8, 1, 45, "#7CFC00", "#111111", "#330000")
	assert(tex1 == tex2, "Values must match")
	-- Verify zero new string creation via string table memoization
	assert(rawequal(tex1, tex2), "Cached texture string must be the exact same memoized reference")
end)

-- 4. Proportional Sizing and Attachment Placement
run_test("calculate_dimensions auto-scales for small mobs (e.g. bug)", function()
	local mob = {
		collisionbox = {-0.2, 0.0, -0.2, 0.2, 0.5, 0.2}, -- width 0.4, height 0.5
	}
	local v_size, attach_pos = health_bar.calculate_dimensions(mob)
	assert(v_size.x == 0.6, "Small mob width should clamp to minimum 0.6, got: " .. tostring(v_size.x))
	assert(v_size.y > 0.06 and v_size.y < 0.10, "Small mob height should be proportional")
	assert(attach_pos.y == (0.5 + 0.35) * 10, "Attachment Y should be (top_y + spacing) * 10 = 8.5")
end)

run_test("calculate_dimensions auto-scales for medium humanoid mobs", function()
	local mob = {
		collisionbox = {-0.4, 0.0, -0.4, 0.4, 1.8, 0.4}, -- width 0.8, height 1.8
	}
	local v_size, attach_pos = health_bar.calculate_dimensions(mob)
	local expected_w = 0.8 * 1.15 -- 0.92
	assert(math.abs(v_size.x - expected_w) < 0.01, "Medium mob width should be ~0.92")
	assert(attach_pos.y == (1.8 + 0.35) * 10, "Attachment Y should be 21.5")
end)

run_test("calculate_dimensions auto-scales for giant boss mobs", function()
	local mob = {
		collisionbox = {-1.5, 0.0, -1.5, 1.5, 3.5, 1.5}, -- width 3.0, height 3.5
	}
	local v_size, attach_pos = health_bar.calculate_dimensions(mob)
	assert(v_size.x == 2.4, "Boss mob width should clamp to maximum 2.4")
	assert(v_size.y > 0.20, "Boss mob height should be suitably thick")
	assert(attach_pos.y == (3.5 + 0.35) * 10, "Attachment Y should be 38.5")
end)

run_test("calculate_dimensions adds extra vertical spacing when nametag is present", function()
	local mob_without_tag = {
		collisionbox = {-0.4, 0.0, -0.4, 0.4, 1.8, 0.4},
	}
	local mob_with_tag = {
		collisionbox = {-0.4, 0.0, -0.4, 0.4, 1.8, 0.4},
		nametag = "King Skeleton",
	}
	local _, pos1 = health_bar.calculate_dimensions(mob_without_tag)
	local _, pos2 = health_bar.calculate_dimensions(mob_with_tag)
	assert(pos2.y > pos1.y, "Nametag mob attachment height must be higher than without nametag")
	assert(math.abs((pos2.y - pos1.y) - 1.5) < 0.01, "Nametag offset difference should be exactly 1.5 units (0.15 nodes)")
end)

run_test("calculate_dimensions normalizes for mob with large visual_size (e.g. crystal guardian)", function()
	local mob = {
		collisionbox = {-0.75, -0.7, -0.75, 0.75, 1.95, 0.75},
		visual_size = { x = 14, y = 14 },
	}
	local v_size, attach_pos = health_bar.calculate_dimensions(mob)
	local expected_attach_y = 23.0 / 14.0
	assert(math.abs(attach_pos.y - expected_attach_y) < 0.01, "Attach Y must be normalized by visual_size.y")
	-- Billboard quad geometry renders with ETS_WORLD IdentityMatrix in Luanti,
	-- so visual_size represents actual world units and is not divided by parent visual_size.
	local expected_w = 1.5 * 1.15
	assert(math.abs(v_size.x - expected_w) < 0.01,
		"Child visual_size.x must equal world width 1.725, got: " .. tostring(v_size.x))
	assert(math.abs(v_size.y - (expected_w * (8 / 64))) < 0.01, "Child visual_size.y must match 8:1 aspect ratio")
end)

run_test("calculate_dimensions normalizes for mob with small visual_size (e.g. spider)", function()
	local mob = {
		collisionbox = {-0.22, 0.0, -0.22, 0.22, 0.28, 0.22},
		visual_size = { x = 0.48, y = 0.48 },
	}
	local v_size, attach_pos = health_bar.calculate_dimensions(mob)
	local expected_attach_y = 6.3 / 0.48
	assert(math.abs(attach_pos.y - expected_attach_y) < 0.01, "Attach Y must be scaled up to compensate for 0.48x parent")
	assert(math.abs(v_size.x - 0.6) < 0.01,
		"Child visual_size.x must maintain clamped world minimum 0.6, got: " .. tostring(v_size.x))
	assert(math.abs(v_size.y - (0.6 * (8 / 64))) < 0.01, "Child visual_size.y must match 8:1 aspect ratio")
end)

-- 5. Lifecycle Spawning, Resetting, and Auto-Removal
local function create_mock_mob(hp, hp_max)
	local parent_obj = core.add_entity({x = 0, y = 5, z = 0}, "x_mob_core:health_bar")
	parent_obj._properties.collisionbox = {-0.4, 0.0, -0.4, 0.4, 1.8, 0.4}
	local mob = {
		hp = hp or 40,
		hp_max = hp_max or 40,
		object = parent_obj,
		state = "idle",
		_def = { hp_max = hp_max or 40 },
	}
	return mob
end

run_test("show spawns health bar child entity, attaches, and initializes timer", function()
	local mob = create_mock_mob(30, 40)
	local shown = health_bar.show(mob, 30, 40)
	assert(shown == true, "show should return true")
	assert(mob._health_bar_obj ~= nil, "Mob must have child health bar object")
	assert(mob._health_bar_obj:is_valid() == true, "Child health bar must be valid")
	assert(mob._health_bar_obj:get_attach() == mob.object, "Child must be attached to parent mob")
	assert(mob._health_bar_timer == 4.0, "Timer should be set to 4.0s")
	local props = mob._health_bar_obj:get_properties()
	assert(props.is_visible == true, "Child must be visible")
	assert(props.textures and props.textures[1]:find("%[combine:"), "Texture must be composited [combine: string")
end)

run_test("show reuses existing child entity on consecutive damage without respawning", function()
	local mob = create_mock_mob(35, 40)
	health_bar.show(mob, 35, 40)
	local first_child = mob._health_bar_obj

	-- Simulate 2 seconds passing
	mob._health_bar_timer = 2.0

	-- Mob takes another hit down to 20 HP
	mob.hp = 20
	health_bar.show(mob, 20, 40)
	local second_child = mob._health_bar_obj

	assert(first_child == second_child, "Must reuse same child entity instance")
	assert(mob._health_bar_timer == 4.0, "Timer must be reset back to 4.0s on damage intake")
end)

run_test("on_timeout removes child entity when auto_remove = true", function()
	local mob = create_mock_mob(25, 40)
	health_bar.show(mob, 25, 40)
	local child = mob._health_bar_obj
	assert(child:is_valid() == true)

	-- Timer expires
	health_bar.on_timeout(mob, mob._def)
	assert(mob._health_bar_obj == nil, "Child entity reference should be cleared")
	assert(child:is_valid() == false, "Child entity must be removed from engine")
	assert(mob._health_bar_timer == 0 or mob._health_bar_timer == nil, "Timer must be 0/nil")
end)

run_test("on_timeout soft-hides child entity when auto_remove = false", function()
	local mob = create_mock_mob(25, 40)
	mob._def.health_bar = { auto_remove = false }
	health_bar.show(mob, 25, 40, mob._def)
	local child = mob._health_bar_obj
	assert(child:is_valid() == true)

	-- Timer expires
	health_bar.on_timeout(mob, mob._def)
	assert(mob._health_bar_obj == child, "Child entity reference should be preserved for fast reuse")
	assert(child:is_valid() == true, "Child entity must NOT be removed from engine")
	local props = child:get_properties()
	assert(props.is_visible == false, "Child entity must be set to is_visible = false")
end)

run_test("remove instantly destroys child entity on lethal death", function()
	local mob = create_mock_mob(1, 40)
	health_bar.show(mob, 1, 40)
	local child = mob._health_bar_obj
	assert(child:is_valid() == true)

	health_bar.remove(mob)
	assert(mob._health_bar_obj == nil, "Child reference must be nil")
	assert(child:is_valid() == false, "Child entity must be completely removed")
	assert(mob._health_bar_timer == nil, "Timer must be nil")
end)

run_test("show refuses to show on dead or dying mobs", function()
	local mob = create_mock_mob(0, 40)
	mob.is_dead = true
	local shown = health_bar.show(mob, 0, 40)
	assert(shown == false, "Must return false for dead mob")
	assert(mob._health_bar_obj == nil, "Must not spawn child for dead mob")
end)

print("==================================================")
print(string.format("  Test Summary: %d / %d Passed (%.1f%%)",
	passed_tests, total_tests, (passed_tests / total_tests) * 100))
print("==================================================")

if passed_tests < total_tests then
	os.exit(1)
end
print("All health bar subsystem tests passed successfully!")
