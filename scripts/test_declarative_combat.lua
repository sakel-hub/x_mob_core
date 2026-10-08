--[[
	test_declarative_combat.lua - Declarative Combat Test Suite
	Verifies pure melee, pure shooter, and hybrid (melee + shooter)
	declarative pipeline execution and combat behaviors.
]]

local passed = 0
local failed = 0

local function assert_eq(desc, actual, expected)
	if actual == expected then
		print("  [PASS] " .. desc)
		passed = passed + 1
	else
		print(string.format("  [FAIL] %s: expected %s, got %s", desc, tostring(expected), tostring(actual)))
		failed = failed + 1
	end
end

local function assert_true(desc, condition)
	if condition then
		print("  [PASS] " .. desc)
		passed = passed + 1
	else
		print("  [FAIL] " .. desc)
		failed = failed + 1
	end
end

-- Minimal Luanti engine mock
_G.core = {
	registered_nodes = {
		["air"] = { walkable = false },
		["default:stone"] = { walkable = true },
	},
	get_node = function(pos)
		local y = pos and pos.y or 0
		if y < 0 then
			return { name = "default:stone" }
		end
		return { name = "air" }
	end,
	get_modpath = function(modname)
		if modname == "x_mob_core" then return "." end
		return nil
	end,
	dir_to_yaw = function(_dir) return 1.57 end,
	yaw_to_dir = function(_yaw) return {x = 0, y = 0, z = 1} end,
	after = function(_delay, func) func() end,
	sound_play = function() return 1 end,
	sound_stop = function() end,
	log = function() end,
	line_of_sight = function(_p1, _p2) return true end,
	get_us_time = function() return 1000000 end,
	get_gametime = function() return 1000 end,
	register_globalstep = function() end,
	register_on_mods_loaded = function() end,
	register_entity = function() end,
	get_translator = function() return function(s) return s end end,
	hash_node_position = function(pos)
		return string.format("%d,%d,%d", math.floor(pos.x or 0), math.floor(pos.y or 0), math.floor(pos.z or 0))
	end,
	get_node_or_nil = function(pos) return _G.core.get_node(pos) end,
	add_particlespawner = function() return 1 end,
	settings = {
		get = function() return nil end,
		get_bool = function() return false end,
	},
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

_G.Raycast = function()
	return function() return nil end
end

local utils = dofile("./core/utils.lua")
local events = dofile("./core/events.lua")

local safety = dofile("./motor/safety.lua")

_G.x_mob_core = {
	utils = utils,
	events = events,
	safety = safety,
	emit = events.emit,
}

local factions = dofile("./combat/factions.lua")
local animator = dofile("./animation/animator.lua")
local sound = dofile("./audio/sound.lua")
local mob_memory = dofile("./navigation/mob_memory.lua")
local melee = dofile("./combat/melee.lua")
local shooter = dofile("./combat/shooter.lua")
local locomotion = dofile("./motor/locomotion.lua")
local pipeline = dofile("./lifecycle/pipeline.lua")

_G.x_mob_core.combat = {
	factions = factions,
	melee = melee,
	shooter = shooter,
}
_G.x_mob_core.animator = animator
_G.x_mob_core.sound = sound
_G.x_mob_core.mob_memory = mob_memory
_G.x_mob_core.motor = {
	locomotion = locomotion,
	safety = safety,
}
_G.x_mob_core.pack = {
	coordination = {
		check_leash = function() return true end,
	},
}
_G.x_mob_core.combat.health_bar = {
	on_hp_change = function() end,
}
_G.x_mob_core.indicate_regen = function(_obj, _color, _dur) end
_G.x_mob_core.get_damage_multiplier = function(_target) return 1.0 end
_G.x_mob_core.halt_horizontal_velocity = function(self)
	if self.object then
		self.object:set_velocity({ x = 0, y = 0, z = 0 })
	end
end
_G.x_mob_core.retreat_from = function(_self, _tpos, _spd)
	return true
end
_G.x_mob_core.schedule = function(self, delay, tag, callback)
	if not self._scheduled_actions then self._scheduled_actions = {} end
	table.insert(self._scheduled_actions, {
		timer = delay,
		tag = tag,
		callback = callback
	})
end
_G.x_mob_core.step_tactical_retreat = locomotion.step_tactical_retreat

-- Wire pipeline hooks exactly as in entity_wrapper.lua
-- Priority 15: Pre-Combat Custom Abilities / Spells Hook
pipeline.register_step_hook("custom_step", 15, function(self, dtime, def, moveresult)
	local fn = def.custom_step or self.custom_step
	if fn and not self.is_dead and self.state ~= "flinching" then
		return fn(self, dtime, moveresult, def) == true
	end
	return false
end)

-- Priority 17: Tactical Retreat & Cornered Retaliation Hook
pipeline.register_step_hook("tactical_retreat", 17, function(self, dtime, def, moveresult)
	local is_fleeing = (self.state == "fleeing")
		or (self.state == "channeling")
		or (self.panic_timer and self.panic_timer > 0)
		or (self.memory and self.memory.flee_state)
	if is_fleeing and not self.is_dead and self.state ~= "flinching" then
		return locomotion.step_tactical_retreat(self, dtime, def, moveresult)
	end
	return false
end)

-- Priority 18: Melee Auto-Combat
pipeline.register_step_hook("melee", 18, function(self, dtime, def)
	local is_melee_enabled = false
	if def.melee == false then
		is_melee_enabled = false
	elseif def.melee == true or type(def.melee) == "table" then
		is_melee_enabled = true
	elseif def.melee == nil then
		if not def.shooter and not def.swarm and not def.shoal and (def.damage or def.attack_range or def.perform_attack) then
			is_melee_enabled = true
		end
	end

	if is_melee_enabled and self.target and self.state ~= "flinching" then
		return melee.step(self, dtime, def)
	end
	return false
end)

-- Priority 20: Shooter Auto-Combat
pipeline.register_step_hook("shooter", 20, function(self, dtime, def)
	if def.shooter and self.target and self.state ~= "flinching" then
		return shooter.step(self, dtime, def)
	end
	return false
end)

print("--- TEST SUITE 1: Pure Melee Declarative Combat ---")
do
	local target_pos = { x = 0, y = 0, z = 1.5 }
	local punched = false
	local punch_dmg = 0

	local mock_target = {
		is_valid = function() return true end,
		is_player = function() return true end,
		get_hp = function() return 20 end,
		get_pos = function() return target_pos end,
		punch = function(_self, _puncher, _tflp, caps, _dir)
			punched = true
			punch_dmg = caps and caps.damage_groups and caps.damage_groups.fleshy or 0
		end,
	}

	local mob_pos = { x = 0, y = 0, z = 0 }
	local stopped_vel = false
	local played_anim = nil

	local mock_mob = {
		object = {
			is_valid = function() return true end,
			get_pos = function() return mob_pos end,
			get_velocity = function() return { x = 1, y = 0, z = 0 } end,
			set_velocity = function(_s, v)
				if v.x == 0 and v.z == 0 then stopped_vel = true end
			end,
			set_yaw = function() end,
			get_luaentity = function() return nil end,
			get_animations = function() return {} end,
			set_animation = function() end,
			set_animation_frame_speed = function() end,
			play_animation = function(_s, anim) played_anim = anim return true end,
		},
		target = mock_target,
		attack_cooldown = 0,
		eye_offset = 1.5,
		_scheduled_actions = {},
	}

	-- Mock animator & sound
	x_mob_core.animator.play = function(_obj, anim) played_anim = anim end

	local mob_def = {
		attack_range = 2.0,
		damage = 6,
		attack_interval = 1.2,
		melee = {
			delay = 0.0,
		},
	}

	-- 1. Target in reach (1.5m <= 2.0m)
	local handled = pipeline.execute(mock_mob, 0.1, mob_def)
	assert_true("Melee pipeline handles in-range target", handled)
	assert_true("Horizontal velocity halted", stopped_vel)
	assert_eq("State changed to attacking", mock_mob.state, "attacking")
	assert_eq("Played attack animation", played_anim, "attack")
	assert_eq("Cooldown set to interval", mock_mob.attack_cooldown, 1.2)

	-- Execute scheduled action
	if mock_mob._scheduled_actions[1] then
		mock_mob._scheduled_actions[1].callback(mock_mob)
	end
	assert_true("Target was punched", punched)
	assert_eq("Dealt expected damage", punch_dmg, 6)

	-- 2. Target out of reach (3.5m > 2.0m)
	target_pos = { x = 0, y = 0, z = 3.5 }
	mock_mob.state = "idle"
	local out_handled = pipeline.execute(mock_mob, 0.1, mob_def)
	assert_eq("Melee pipeline returns false when out of reach", out_handled, false)
end

print("\n--- TEST SUITE 2: Pure Shooter Declarative Combat ---")
do
	local target_pos = { x = 0, y = 0, z = 10.0 }
	local mock_target = {
		is_valid = function() return true end,
		is_player = function() return true end,
		get_hp = function() return 20 end,
		get_pos = function() return target_pos end,
		get_velocity = function() return { x = 0, y = 0, z = 0 } end,
	}

	local mob_pos = { x = 0, y = 0, z = 0 }
	local mock_mob = {
		object = {
			is_valid = function() return true end,
			get_pos = function() return mob_pos end,
			get_velocity = function() return { x = 0, y = 0, z = 0 } end,
			set_velocity = function() end,
			set_yaw = function() end,
			get_luaentity = function() return nil end,
			get_animations = function() return {} end,
			set_animation = function() end,
			set_animation_frame_speed = function() end,
			play_animation = function() return true end,
		},
		target = mock_target,
		attack_cooldown = 0,
		eye_offset = 1.5,
		_scheduled_actions = {},
	}

	local mob_def = {
		attack_range = 15.0,
		shooter = {
			range = 15.0,
			min_range = 5.0,
			cooldown = 2.0,
			damage = 4,
		},
	}

	-- Shooter in range (10m <= 15m)
	local handled = pipeline.execute(mock_mob, 0.1, mob_def)
	assert_true("Shooter pipeline handles target within range", handled)
	assert_eq("State changed to attacking", mock_mob.state, "attacking")
	assert_eq("Attack cooldown set to shooter cooldown", mock_mob.attack_cooldown, 2.0)

	-- Shooter out of range (20m > 15m)
	target_pos = { x = 0, y = 0, z = 20.0 }
	local out_handled = pipeline.execute(mock_mob, 0.1, mob_def)
	assert_eq("Shooter pipeline returns false when beyond range", out_handled, false)
end

print("\n--- TEST SUITE 3: Hybrid (Melee + Alternative Shooter) Pipeline Interplay ---")
do
	local target_pos = { x = 0, y = 0, z = 1.8 }
	local punched = false

	local mock_target = {
		is_valid = function() return true end,
		is_player = function() return true end,
		get_hp = function() return 20 end,
		get_pos = function() return target_pos end,
		get_velocity = function() return { x = 0, y = 0, z = 0 } end,
		punch = function() punched = true end,
	}

	local mob_pos = { x = 0, y = 0, z = 0 }
	local mock_mob = {
		object = {
			is_valid = function() return true end,
			get_pos = function() return mob_pos end,
			get_velocity = function() return { x = 0, y = 0, z = 0 } end,
			set_velocity = function() end,
			set_yaw = function() end,
			get_luaentity = function() return nil end,
			get_animations = function() return {} end,
			set_animation = function() end,
			set_animation_frame_speed = function() end,
			play_animation = function() return true end,
		},
		target = mock_target,
		attack_cooldown = 0,
		eye_offset = 1.5,
		_scheduled_actions = {},
	}

	local hybrid_def = {
		attack_range = 2.2,
		damage = 5,
		melee = {
			range = 2.2,
			damage = 5,
			delay = 0,
		},
		shooter = {
			range = 14.0,
			min_range = 0,
			cooldown = 3.0,
			damage = 3,
		},
	}

	-- Scenario A: Target in close melee reach (1.8m <= 2.2m)
	-- Pipeline executes Melee hook (Priority 18) and intercepts before Shooter hook (Priority 20)
	local p_handled = pipeline.execute(mock_mob, 0.1, hybrid_def)
	assert_true("Pipeline handles target at melee range", p_handled)
	assert_eq("State is attacking from melee", mock_mob.state, "attacking")
	if mock_mob._scheduled_actions[1] then
		mock_mob._scheduled_actions[1].callback(mock_mob)
	end
	assert_true("Melee strike punched target", punched)

	-- Scenario B: Target outside melee reach, within shooter range (8.0m)
	target_pos = { x = 0, y = 0, z = 8.0 }
	mock_mob.state = "idle"
	mock_mob.attack_cooldown = 0
	mock_mob._scheduled_actions = {}

	local p_handled_ranged = pipeline.execute(mock_mob, 0.1, hybrid_def)
	assert_true("Pipeline handles target at ranged distance via shooter", p_handled_ranged)
	assert_eq("Cooldown set to shooter cooldown (3.0s)", mock_mob.attack_cooldown, 3.0)

	-- Scenario C: Target beyond shooter range (25.0m)
	target_pos = { x = 0, y = 0, z = 25.0 }
	mock_mob.state = "idle"
	mock_mob.attack_cooldown = 0

	local p_handled_far = pipeline.execute(mock_mob, 0.1, hybrid_def)
	assert_eq("Pipeline returns false beyond all combat ranges (falls back to locomotion A*)", p_handled_far, false)
end

print("\n--- TEST SUITE 4: Pre-Combat Custom Step Hook Interception ---")
do
	local target_pos = { x = 0, y = 0, z = 1.5 }
	local mock_target = {
		is_valid = function() return true end,
		is_player = function() return true end,
		get_hp = function() return 20 end,
		get_pos = function() return target_pos end,
		get_velocity = function() return { x = 0, y = 0, z = 0 } end,
	}

	local mob_pos = { x = 0, y = 0, z = 0 }
	local mock_mob = {
		object = {
			is_valid = function() return true end,
			get_pos = function() return mob_pos end,
			get_velocity = function() return { x = 0, y = 0, z = 0 } end,
			set_velocity = function() end,
			set_yaw = function() end,
			get_luaentity = function() return nil end,
			get_animations = function() return {} end,
			set_animation = function() end,
			set_animation_frame_speed = function() end,
			play_animation = function() return true end,
		},
		target = mock_target,
		attack_cooldown = 0,
		eye_offset = 1.5,
		_scheduled_actions = {},
	}

	local spell_cast = false
	local mob_def = {
		attack_range = 2.5,
		damage = 6,
		melee = {
			range = 2.5,
			damage = 6,
			delay = 0,
		},
		custom_step = function(mob, _dtime)
			if not spell_cast then
				spell_cast = true
				mob.state = "casting"
				return true -- Intercepts combat!
			end
			return false -- Fall through to melee!
		end,
	}

	-- 1. First tick: custom_step fires special spell and returns true
	local handled1 = pipeline.execute(mock_mob, 0.1, mob_def)
	assert_true("custom_step intercept returns true", handled1)
	assert_eq("State is casting from custom_step", mock_mob.state, "casting")
	assert_true("Spell was cast", spell_cast)

	-- 2. Second tick: custom_step returns false, falls through to Priority 18 Melee
	mock_mob.state = "idle"
	local handled2 = pipeline.execute(mock_mob, 0.1, mob_def)
	assert_true("Pipeline falls through to melee when custom_step returns false", handled2)
	assert_eq("State changed to attacking from melee", mock_mob.state, "attacking")
end

print("\n--- TEST SUITE 5: Tactical Retreat & Cornered Retaliation ---")
do
	local target_pos = { x = 0, y = 0, z = 1.5 }
	local punched = false
	local punch_dmg = 0
	local played_anim

	local mock_target = {
		is_valid = function() return true end,
		is_player = function() return true end,
		get_player_name = function() return "singleplayer" end,
		get_hp = function() return 20 end,
		get_pos = function() return target_pos end,
		get_velocity = function() return { x = 0, y = 0, z = 0 } end,
		get_wielded_item = function()
			return {
				is_empty = function() return true end,
				get_name = function() return "" end,
				get_tool_capabilities = function() return nil end,
			}
		end,
		punch = function(_self, _src, _interval, tool_caps, _dir)
			punched = true
			punch_dmg = tool_caps.damage_groups and tool_caps.damage_groups.fleshy or 0
		end,
	}

	local mob_pos = { x = 0, y = 0, z = 0 }
	local mob_vel = { x = 0, y = 0, z = 0 }
	local mock_mob
	mock_mob = {
		object = {
			is_valid = function() return true end,
			get_pos = function() return mob_pos end,
			get_velocity = function() return mob_vel end,
			set_velocity = function(_self, v) mob_vel = v end,
			add_velocity = function() end,
			set_acceleration = function() end,
			set_yaw = function() end,
			get_yaw = function() return 0 end,
			set_rotation = function() end,
			get_hp = function() return mock_mob.hp or 15 end,
			set_hp = function(_self, hp) mock_mob.hp = hp end,
			get_luaentity = function() return nil end,
			get_animations = function() return {} end,
			set_animation = function() end,
			set_animation_frame_speed = function() end,
			play_animation = function(_s, anim) played_anim = anim return true end,
		},
		target = mock_target,
		attack_cooldown = 0,
		state = "fleeing",
		memory = { flee_state = true },
		hp = 4,
		hp_max = 15,
		eye_offset = 1.2,
		_scheduled_actions = {},
	}

	local melee_mob_def = {
		attack_range = 2.0,
		damage = 4,
		max_flee_distance = 15.0,
		health_regen = {
			flee_threshold = 5,
			return_threshold = 12,
		},
		melee = {
			range = 2.0,
			damage = 4,
			delay = 0,
		},
	}

	-- 1. Fleeing melee mob with player in close reach (1.5m <= 2.0m): cornered retaliation!
	local handled1 = pipeline.execute(mock_mob, 0.1, melee_mob_def)
	assert_true("Tactical retreat handles cornered player in melee reach", handled1)
	assert_eq("State changed to attacking for retaliation", mock_mob.state, "attacking")
	if mock_mob._scheduled_actions[1] then
		mock_mob._scheduled_actions[1].callback(mock_mob)
	end
	assert_true("Player was punched in cornered retaliation", punched)
	assert_eq("Retaliation damage dealt correctly", punch_dmg, 4)

	-- 2. Fleeing melee mob with player out of reach (5.0m > 2.0m): forward escape sprint!
	mock_mob.state = "fleeing"
	mock_mob.attack_cooldown = 0
	target_pos = { x = 0, y = 0, z = 5.0 }
	local handled2 = pipeline.execute(mock_mob, 0.1, melee_mob_def)
	assert_true("Tactical retreat handles fleeing pursuit distance", handled2)
	assert_true("Mob actively moves in escape direction", mob_vel.z < 0) -- moves away from player at z=5

	-- 3. Fleeing melee mob beyond safe distance (18m >= 10m): transitions to channeling!
	target_pos = { x = 0, y = 0, z = 18.0 }
	local handled3 = pipeline.execute(mock_mob, 0.1, melee_mob_def)
	assert_true("Tactical retreat halts when safe distance reached", handled3)
	assert_eq("State transitioned to channeling to recover health", mock_mob.state, "channeling")

	-- 4. Fleeing shooter mob: standoff kiting (turn and sprint if < min_range, shoot if in standoff)
	local shooter_mob_def = {
		attack_range = 15.0,
		damage = 3,
		melee = {
			range = 2.0,
			damage = 3,
			delay = 0,
		},
		shooter = {
			min_range = 6.0,
			range = 15.0,
			damage = 5,
			cooldown = 2.0,
			velocity = 15.0,
		},
	}

	-- Inside standoff (< 6.0m, e.g. 4.0m): sprints forward away from player
	mock_mob.state = "fleeing"
	mock_mob._flee_channel_timer = nil
	mock_mob._flee_burst_timer = 3.0
	target_pos = { x = 0, y = 0, z = 4.0 }
	local handled4 = pipeline.execute(mock_mob, 0.1, shooter_mob_def)
	assert_true("Shooter sprints forward away when target is closer than min_range", handled4)
	assert_true("Velocity is directed away from threat", mob_vel.z < 0)

	-- In optimal standoff bracket (9.0m between 6m and 15m): turns and fires projectile
	target_pos = { x = 0, y = 0, z = 9.0 }
	mock_mob.attack_cooldown = 0
	local handled5 = pipeline.execute(mock_mob, 0.1, shooter_mob_def)
	assert_true("Shooter fires projectile in standoff bracket", handled5)
	assert_eq("State changed to attacking from shooter step", mock_mob.state, "attacking")

	-- 5. Skull mob (flee_threshold = 0, state = "walk"): stands ground, tactical retreat bypassed
	local skull_mob_def = {
		attack_range = 2.5,
		damage = 5,
		health_regen = {
			flee_threshold = 0,
		},
		melee = {
			range = 2.5,
			damage = 5,
			delay = 0,
		},
	}
	mock_mob.state = "walk"
	mock_mob.memory = { flee_state = false }
	target_pos = { x = 0, y = 0, z = 2.0 }
	mock_mob.attack_cooldown = 0
	local handled6 = pipeline.execute(mock_mob, 0.1, skull_mob_def)
	assert_true("Skull mob stands ground and executes standard melee", handled6)
	assert_eq("State changed to attacking without ever fleeing", mock_mob.state, "attacking")

	-- 6. Healing Shooter (e.g. Spectrum): flees away even in shooter standoff range (8.0m)
	local healing_shooter_def = {
		attack_range = 16.0,
		damage = 6,
		max_flee_distance = 14.0,
		health_regen = {
			flee_threshold = 20,
			return_threshold = 45,
			burst_duration = 3.5,
			safe_distance = 12.0,
		},
		shooter = {
			min_range = 4.0,
			range = 16.0,
			damage = 6,
			cooldown = 3.0,
		},
	}
	mock_mob.hp = 18
	mock_mob.hp_max = 60
	mock_mob.state = "fleeing"
	mock_mob.memory = { flee_state = true }
	mock_mob._flee_dir = nil
	mock_mob._flee_last_pos = nil
	mock_mob._flee_stagnant_timer = 0
	mock_mob._wall_stuck_timer = 0
	mock_mob._last_nav_pos = nil
	mock_mob._flee_channel_timer = nil
	mock_mob._flee_burst_timer = 3.0
	target_pos = { x = 0, y = 0, z = 8.0 }
	local handled7 = pipeline.execute(mock_mob, 0.1, healing_shooter_def)
	assert_true("Healing shooter flees when in shooter standoff range", handled7)
	assert_true(string.format("Healing shooter velocity directed away (got vel.z=%s)",
		tostring(mob_vel.z)), mob_vel.z < 0)
	assert_true("Healing shooter does not transition to attacking", mock_mob.state ~= "attacking")

	-- 7. Chased minion with stale fight_pos: flees away from chasing player at 5.0m
	mock_mob.memory = nil
	x_mob_core.mob_memory.init_memory(mock_mob)
	x_mob_core.mob_memory.record_fight_pos(mock_mob, { x = 0, y = 0, z = -20.0 }, 45.0)
	mock_mob.hp = 4
	mock_mob.hp_max = 15
	mock_mob.state = "fleeing"
	mock_mob.memory.flee_state = true
	mock_mob._flee_dir = nil
	mock_mob._flee_last_pos = nil
	mock_mob._flee_stagnant_timer = 0
	mock_mob._flee_channel_timer = nil
	mock_mob._flee_burst_timer = 3.0
	target_pos = { x = 0, y = 0, z = 5.0 }
	local handled8 = pipeline.execute(mock_mob, 0.1, melee_mob_def)
	assert_true("Fleeing minion prioritizes living target over stale fight_pos", handled8)
	assert_true("Minion flees away from player despite stale fight_pos", mob_vel.z < 0)

	-- 8. Cowardly minion with unlimited_flee: halts at max flee distance
	local minion_unlimited_def = {
		attack_range = 2.0,
		damage = 4,
		max_flee_distance = 15.0,
		health_regen = {
			unlimited_flee = true,
			flee_threshold = 5,
			return_threshold = 12,
			rate = 0.5,
		},
		melee = { range = 2.0, damage = 4 },
	}
	mock_mob.state = "fleeing"
	mock_mob._flee_used = nil
	mock_mob._flee_burst_timer = nil
	mock_mob._flee_channel_timer = nil
	target_pos = { x = 0, y = 0, z = 16.0 }
	played_anim = nil
	local handled9 = pipeline.execute(mock_mob, 0.1, minion_unlimited_def)
	assert_true("Unlimited flee minion halts at max flee distance", handled9)
	assert_eq("State transitions to idle when at max flee distance", mock_mob.state, "idle")
	assert_true("Plays idle animation when halted", played_anim == "idle" or played_anim == "stand")
	assert_true("Standoff flag set", mock_mob._flee_standoff == true)

	-- Hysteresis: within deadband (13.0m >= 11.5m), remains at standoff without oscillating
	target_pos = { x = 0, y = 0, z = 13.0 }
	pipeline.execute(mock_mob, 0.1, minion_unlimited_def)
	assert_true("Remains in standoff due to hysteresis deadband", mock_mob._flee_standoff == true)

	-- Threat closes in past deadband (< 11.5m, e.g. 10.0m): clears standoff and flees
	target_pos = { x = 0, y = 0, z = 10.0 }
	pipeline.execute(mock_mob, 0.1, minion_unlimited_def)
	assert_true("Standoff cleared when threat closes in past deadband", mock_mob._flee_standoff == nil)

	-- Channel completes uninterrupted -> heals and re-engages in combat
	mock_mob.state = "channeling"
	mock_mob.hp = 4
	mock_mob.hp_max = 20
	mock_mob._flee_channel_timer = 0.05
	mock_mob._flee_used = nil
	target_pos = { x = 0, y = 0, z = 12.0 }
	local handled10 = pipeline.execute(mock_mob, 0.1, melee_mob_def)
	assert_true("Channel completion handled", handled10)
	assert_true("HP restored after channel", mock_mob.hp > 4)
	assert_eq("State re-engages to walk", mock_mob.state, "walk")
	assert_true("1-time retreat lock activated", mock_mob._flee_used == true)

	-- Subsequent flee in same combat is blocked by _flee_used (stands and fights)
	mock_mob.state = "fleeing"
	local handled11 = pipeline.execute(mock_mob, 0.1, melee_mob_def)
	assert_true("Subsequent retreat rejected (_flee_used blocks retreat)", handled11 == false)
	assert_eq("State changed to combat (Last Stand)", mock_mob.state, "combat")

	-- Hit-interrupt during channeling breaks channel into Last Stand
	local hit_obj = {
		is_valid = function() return true end,
		get_pos = function() return { x = 0, y = 0, z = 0 } end,
		get_hp = function() return 6 end,
		set_hp = function() end,
		get_armor_groups = function() return { fleshy = 100 } end,
		get_properties = function() return { textures = {"test.png"} } end,
		set_properties = function() end,
		get_texture_mod = function() return "" end,
		set_texture_mod = function() end,
		get_luaentity = function() return nil end,
		get_animations = function() return {} end,
		set_animation = function() end,
		set_animation_frame_speed = function() end,
		play_animation = function() return true end,
		add_velocity = function() end,
		set_velocity = function() end,
	}
	local hit_mob = {
		object = hit_obj,
		state = "channeling",
		hp = 6,
		hp_max = 20,
		_flee_channel_timer = 2.5,
	}
	x_mob_core.mob_memory.init_memory(hit_mob)
	hit_mob.memory.flee_state = true
	local puncher = mock_mob.target
	local combat_handler = dofile("./lifecycle/combat_handler.lua")
	combat_handler.handle_punch(hit_mob, puncher, 1.0, {
		full_punch_interval = 1.0,
		damage_groups = { fleshy = 2 },
	}, { x = 0, y = 0, z = 1 }, 2, melee_mob_def)
	assert_true("Hit-interrupt locks _flee_used", hit_mob._flee_used == true)
	assert_true("Flee channel timer cleared", hit_mob._flee_channel_timer == nil)
	assert_true("Flee memory cleared", hit_mob.memory.flee_state == false)
	local forced_combat = (hit_mob.state == "flinching" or hit_mob.state == "combat")
	assert_true("Mob forced into flinching/combat (not channeling)", forced_combat)
end

print(string.format("\nTOTAL RESULTS: %d passed, %d failed", passed, failed))
if failed > 0 then
	os.exit(1)
end
