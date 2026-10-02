--[[
	x_mob_core - Sound & Acoustic Feedback Subsystem
	Manages positional audio, ambient vocalizations, hurt/death triggers, and pitch jitter
]]

---@class SoundConfigDef
---@field name string|string[] Technical sound name or list of sound variations
---@field gain? number Volume multiplier (default: 1.0)
---@field distance? number Maximum audible distance in nodes (default: 16.0)
---@field max_hear_distance? number Alias for distance in nodes
---@field pitch? number Base pitch multiplier (default: 1.0)
---@field pitch_jitter? number Random pitch variation factor (default: 0.05)
---@field min_interval? number Minimum cooldown between automatic triggers (default: 8.0)
---@field max_interval? number Maximum cooldown between automatic triggers (default: 22.0)
---@field chance? number Probability to play when interval expires (default: 1.0)

---@class MobSoundDef
---@field distance? number Global default hear distance in nodes (default: 24.0)
---@field max_hear_distance? number Alias for distance in nodes
---@field gain? number Global default volume multiplier (default: 1.0)
---@field pitch_jitter? number Global default pitch jitter factor (default: 0.05)
---@field hurt? string|SoundConfigDef Sound played on non-lethal damage
---@field death? string|SoundConfigDef Sound played on lethal damage
---@field random? string|SoundConfigDef Periodic ambient sound played during wander/idle
---@field attack? string|SoundConfigDef Sound played on melee or ranged strike
---@field alert? string|SoundConfigDef Sound played when a target is first acquired

---@class SoundSubsystem
local sound = {}

-- De-bounce interval for rapid successive hurt sounds
local HURT_SOUND_DEBOUNCE = 0.25

--- Plays a configured sound type for a mob instance with positional attenuation and pitch variation
---@param self table|userdata Mob instance or ObjectRef
---@param sound_type string Category ("hurt", "death", "random", "attack", "alert") or technical sound name
---@param overrides? table Optional overrides (gain, distance, pitch, pos, object, to_player, loop)
---@return integer|nil sound_handle Luanti sound handle or nil if not played
function sound.play(self, sound_type, overrides)
	local self_tbl = type(self) == "table" and self or nil
	local obj = nil
	if type(self) == "userdata" or (type(self) == "table" and self.get_pos and not self.object) then
		obj = self
	elseif self_tbl and self_tbl.object then
		obj = self_tbl.object
	end

	local sound_tbl = self_tbl and self_tbl.sounds
	if not sound_tbl and self_tbl and self_tbl.name then
		local reg = x_mob_core.registered_mobs[self_tbl.name]
		sound_tbl = reg and reg.sounds
	end

	-- Support string shorthand e.g. sounds = "x_mobs_minion"
	if type(sound_tbl) == "string" then
		sound_tbl = { base = sound_tbl }
	end

	local spec
	if sound_tbl then
		spec = sound_tbl[sound_type] or sound_tbl.base or sound_type
	else
		-- Direct sound playback fallback if mob has no sound table or self is ObjectRef
		if type(sound_type) == "string" or type(sound_type) == "table" then
			spec = sound_type
		else
			return nil
		end
	end

	-- De-bounce hurt sounds using microsecond timer to prevent auditory spam
	local now = core.get_us_time() / 1000000
	if sound_type == "hurt" and self_tbl then
		local last_time = self_tbl._last_hurt_sound_time or 0
		if (now - last_time) < HURT_SOUND_DEBOUNCE then
			return nil
		end
		self_tbl._last_hurt_sound_time = now
	end

	-- Resolve sound name and acoustic parameters
	local sound_name = nil
	local gain = 1.0
	local distance = 24.0
	local pitch = 1.0
	local jitter = 0.05

	local global_gain = (sound_tbl and sound_tbl.gain) or 1.0
	local global_dist = (sound_tbl and (sound_tbl.distance or sound_tbl.max_hear_distance)) or 24.0
	local global_jitter = (sound_tbl and sound_tbl.pitch_jitter) or 0.05

	if type(spec) == "string" then
		sound_name = spec
		gain = global_gain
		distance = global_dist
		jitter = global_jitter
	elseif type(spec) == "table" then
		sound_name = spec.name or (sound_tbl and sound_tbl.base)
		if type(sound_name) == "table" and #sound_name > 0 then
			sound_name = sound_name[math.random(1, #sound_name)]
		end
		gain = spec.gain or global_gain
		distance = spec.distance or spec.max_hear_distance or global_dist
		pitch = spec.pitch or 1.0
		jitter = spec.pitch_jitter or global_jitter
	end

	if not sound_name or sound_name == "" then
		return nil
	end

	-- Apply runtime overrides if provided
	if overrides then
		if overrides.gain then gain = overrides.gain end
		if overrides.distance then distance = overrides.distance end
		if overrides.max_hear_distance then distance = overrides.max_hear_distance end
		if overrides.pitch then pitch = overrides.pitch end
		if overrides.pitch_jitter then jitter = overrides.pitch_jitter end
	end

	-- Subtle pitch variation to avoid repetitive acoustic fatigue
	if jitter > 0 then
		pitch = pitch * (1.0 + (math.random() * 2.0 - 1.0) * jitter)
	end

	-- Spatial binding: Sound must be strictly tied to an object or position with finite max_hear_distance.
	-- This explicitly prevents unbounded global sounds in Luanti multiplayer.
	local target_object = nil
	local target_pos = nil

	if overrides and overrides.object and overrides.object:is_valid() then
		target_object = overrides.object
	elseif overrides and overrides.pos then
		target_pos = overrides.pos
	else
		-- Determine based on mob entity state
		local is_obj_valid = obj and obj:is_valid()
		local is_dying_or_dead = (self_tbl and (self_tbl.is_dead or self_tbl.state == "dying")) or sound_type == "death"

		if is_obj_valid then
			if is_dying_or_dead then
				-- Play at static coordinate on death to prevent premature sound cut-off upon entity deletion
				target_pos = obj:get_pos()
			else
				-- Dynamic 3D positional audio tracking the moving mob object
				target_object = obj
			end
		elseif self_tbl and self_tbl._last_pos then
			target_pos = self_tbl._last_pos
		end
	end

	-- Luanti SoundParams: 'pos' and 'object' are strictly mutually exclusive.
	-- If neither is valid, abort sound playback to prevent global broadcast.
	local params = {
		gain = gain,
		max_hear_distance = distance,
		pitch = pitch,
	}

	if target_object then
		params.object = target_object
	elseif target_pos then
		params.pos = target_pos
	else
		-- Safety safeguard: NEVER broadcast globally without spatial anchor
		return nil
	end

	if overrides then
		if overrides.to_player then params.to_player = overrides.to_player end
		if overrides.exclude_player then params.exclude_player = overrides.exclude_player end
		if overrides.loop ~= nil then params.loop = overrides.loop end
		if overrides.fade ~= nil then params.fade = overrides.fade end
	end

	local ephemeral = overrides and overrides.ephemeral or false
	return core.sound_play(sound_name, params, ephemeral)
end

--- Updates ambient random sound cooldown timer and triggers wander vocalizations
---@param self table Mob instance
---@param dtime number Step delta time
function sound.update(self, dtime)
	if self._has_sounds == false then
		return
	end

	local sound_tbl = self.sounds
	if not sound_tbl and self.name then
		local reg = x_mob_core.registered_mobs[self.name]
		sound_tbl = reg and reg.sounds
	end
	if not sound_tbl then
		self._has_sounds = false
		return
	end

	-- Support string shorthand or base sound fallback
	local rcfg = (type(sound_tbl) == "string" and sound_tbl) or sound_tbl.random or sound_tbl.base
	if not rcfg then
		return
	end

	-- Skip ambient sounds during death sequence or active combat
	if self.is_dead or self.state == "dying" or self.target then
		return
	end

	local timer = (self._sound_timer or 5.0) - dtime
	if timer > 0 then
		self._sound_timer = timer
		return
	end

	local min_int = (type(rcfg) == "table" and rcfg.min_interval) or 8.0
	local max_int = (type(rcfg) == "table" and rcfg.max_interval) or 22.0
	local chance = (type(rcfg) == "table" and rcfg.chance) or 1.0

	self._sound_timer = min_int + math.random() * math.max(0.5, max_int - min_int)

	if chance >= 1.0 or math.random() <= chance then
		sound.play(self, "random")
	end
end

--- Stops a playing sound handle
---@param handle? integer Luanti sound handle
function sound.stop(handle)
	if handle then
		core.sound_stop(handle)
	end
end

return sound
