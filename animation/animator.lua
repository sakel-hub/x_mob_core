--[[
	x_mob_core - Animation Subsystem
	Dispatches skeletal animation to Luanti ObjectRefs using modern glTF track playback
]]

---@class AnimatorSubsystem
local animator = {}

--- Dispatches skeletal animation to a Luanti object using modern glTF track playback
---@param obj ObjectRef Target entity ObjectRef
---@param track_name string Named glTF animation track identifier
---@param params? AnimationParams Playback options (speed, loop, blend, priority, force)
---@return boolean success Whether animation playback was successfully dispatched
function animator.play(obj, track_name, params)
	if not obj or not obj:is_valid() then return false end
	params = params or {}
	local speed = params.speed or 1.0
	local loop = (params.loop ~= false)
	local blend = params.blend or 0.15
	local priority = params.priority or 0
	local force = (params.force == true)

	local luaentity = obj:get_luaentity()
	local prev_track = luaentity and luaentity._current_track

	local target_track = track_name
	local anim_def = nil
	if luaentity and luaentity.animations then
		anim_def = luaentity.animations[track_name]
		if not anim_def then
			if track_name == "death" then
				anim_def = luaentity.animations["die"]
			elseif track_name == "die" then
				anim_def = luaentity.animations["death"]
			elseif track_name == "idle" then
				anim_def = luaentity.animations["stand"]
			elseif track_name == "stand" then
				anim_def = luaentity.animations["idle"]
			end
		end
	end

	if type(anim_def) == "table" and anim_def.track then
		target_track = anim_def.track
		if anim_def.speed then
			speed = speed * anim_def.speed
		end
		if anim_def.loop ~= nil and params.loop == nil then
			loop = anim_def.loop
		end
	elseif type(anim_def) == "string" then
		target_track = anim_def
	elseif not anim_def then
		if target_track == "idle" then
			target_track = "stand"
		elseif target_track == "stand" then
			target_track = "idle"
		elseif target_track == "death" then
			target_track = "die"
		end
	end

	if luaentity and prev_track == target_track and loop and not force then
		-- Track is already looping actively; update parameters without restarting
		obj:update_animation(target_track, {speed = speed})
		return true
	end

	if luaentity then
		luaentity._current_track = target_track
	end

	-- Stop other animation tracks when switching to avoid multi-track blending
	local active = obj:get_animations()
	if active then
		for t, _ in pairs(active) do
			if t ~= target_track then
				obj:stop_animation(t)
			end
		end
	elseif prev_track and prev_track ~= target_track then
		obj:stop_animation(prev_track)
	end

	-- Modern Luanti glTF animation track playback
	obj:play_animation(target_track, {
		speed = speed,
		loop = loop,
		blend = blend,
		priority = priority,
	})
	return true
end

--- Stops current animation tracks on an object
---@param obj ObjectRef
---@param track_name? string Optional specific track to stop
function animator.stop(obj, track_name)
	if not obj or not obj:is_valid() then return end
	local luaentity = obj:get_luaentity()
	local target_track = track_name
	if track_name and luaentity and luaentity.animations then
		local def = luaentity.animations[track_name]
		if not def then
			if track_name == "death" then
				def = luaentity.animations["die"]
			elseif track_name == "die" then
				def = luaentity.animations["death"]
			elseif track_name == "idle" then
				def = luaentity.animations["stand"]
			elseif track_name == "stand" then
				def = luaentity.animations["idle"]
			end
		end
		if type(def) == "table" and def.track then
			target_track = def.track
		elseif type(def) == "string" then
			target_track = def
		end
	end
	if target_track then
		obj:stop_animation(target_track)
	else
		obj:stop_animation()
	end
	if luaentity then
		luaentity._current_track = nil
	end
end

return animator
