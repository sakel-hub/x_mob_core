-- luacheck: globals export
-- scripts/doc_format.lua
-- Compact Markdown documentation generator for x_mob_core via lua-language-server
local util = require 'utility'
local jsonb = require 'json-beautify'

local function make_anchor(title)
	return title:lower():gsub("[^%w%s%-]", ""):gsub("%s", "-")
end

export.serializeAndExport = function(docs, outputDir)
	local jsonPath = outputDir .. '/doc.json'
	local mdPath = outputDir .. '/doc.md'

	-- Export standard JSON AST
	local old_support = jsonb.supportSparseArray
	jsonb.supportSparseArray = true
	local jsonOk, jsonErr = util.saveFile(jsonPath, jsonb.beautify(docs))
	jsonb.supportSparseArray = old_support

	-- Build compact, structured Markdown
	local lines = {}
	local function emit(str)
		table.insert(lines, str or "")
	end

	emit("# x_mob_core API Reference")
	emit("")
	emit("High-performance, zero-dependency S.O.L.I.D. mob and spawner framework for Luanti.")
	emit("")

	-- Categorize documentation items
	local classes = {}
	local aliases = {}
	local functions = {}
	local variables = {}

	for _, item in ipairs(docs) do
		local name = item.name
		if not name and item.defines and item.defines[1] then
			name = item.defines[1].view
		end

		local def1 = item.defines and item.defines[1]
		local file = (def1 and def1.file) or ""
		local is_foreign = file:find("^%[FOREIGN%]") or file:find("Luanti%.app") or file:find("builtin")

		-- Filter out foreign library definitions, internal engine overrides, and private fields
		local is_valid = name and name ~= "LuaLS"
			and not is_foreign
			and not name:find("^core%.")
			and not name:find("%.%_")
			and not name:find("^x_mob_core%.[^%.]+%.")
		if is_valid then
			if item.type == "type" and name ~= "x_mob_core" then
				if def1 and def1.type == "doc.alias" then
					table.insert(aliases, item)
				else
					table.insert(classes, item)
				end
			elseif def1 and (def1.view == "function"
				or (def1.extends and def1.extends.type == "function")) then
				table.insert(functions, item)
			elseif name ~= "x_mob_core" then
				table.insert(variables, item)
			end
		end
	end

	table.sort(classes, function(a, b) return (a.name or "") < (b.name or "") end)
	table.sort(aliases, function(a, b) return (a.name or "") < (b.name or "") end)
	table.sort(functions, function(a, b) return (a.name or "") < (b.name or "") end)
	table.sort(variables, function(a, b) return (a.name or "") < (b.name or "") end)

	-- Subsystem groups matching the latest x_mob_core architectural hierarchy
	local groups = {
		{
			title = "Lifecycle & Entity Registration API",
			desc = "Standardized mob entity registration, state machine transitions, armor group handling, "
				.. "texture variation routing, target selection, lifecycle-tied action scheduling, and "
				.. "prioritized step middleware pipeline hooks.",
			match = function(n)
				return n:find("register_mob") or n:find("transition") or n:find("armor_groups")
					or n:find("step_hook") or n:find("schedule") or n:find("set_target")
					or n:find("set_texture") or n:find("lifecycle")
			end
		},
		{
			title = "Navigation & Pathfinding API",
			desc = "Time-sliced coroutine A* pathfinding, binary min-heap priority queue, "
				.. "pre-cached content ID lookups, and spatial memory blackboard.",
			match = function(n)
				return n:find("path") or n:find("heap") or n:find("memory")
			end
		},
		{
			title = "Motor & Steering Controller API",
			desc = "Autonomous steering behaviors, surface climbing, liquid swimming, "
				.. "idle and wander routines, raycast player perception, tactical retreat, and velocity damping.",
			match = function(n)
				return n:find("step_move") or n:find("step_wander") or n:find("scan")
					or n:find("retreat") or n:find("steer") or n:find("halt")
			end
		},
		{
			title = "Animation Subsystem API",
			desc = "Skeletal animation playback, modern glTF named multi-track blending, "
				.. "playback speed scaling, and loop synchronization.",
			match = function(n)
				return n:find("anim")
			end
		},
		{
			title = "Multi-Agent Pack, Swarm & Shoal Coordination API",
			desc = "Multi-agent squad hierarchies, leader-follower tracking, orphan adoption, "
				.. "spatial leash tethering, regroup locomotion, threat alerts, 3D Boids spatial separation with "
				.. "horizontal anti-stacking bias, aerial swarm flocking and vortex dive-bomb combat, aquatic schooling, "
				.. "and democratic leader election.",
			match = function(n)
				return n:find("pack") or n:find("squad") or n:find("regroup")
					or n:find("alert_nearby_allies") or n:find("threat") or n:find("leash")
					or n:find("rally") or n:find("follower") or n:find("orphan")
					or n:find("leader") or n:find("repulsion") or n:find("successor")
					or n:find("swarm") or n:find("flock") or n:find("shoal")
			end
		},
		{
			title = "Combat, Damage, Factions & Loot API",
			desc = "Tool capability damage calculations, weapon wear, water knockback dampening, "
				.. "directional damage particles, damage indicator flashing, child and arrow detachment on death, "
				.. "faction allegiance and enemy checks, predictive intercept aiming, and declarative parabolic loot drops.",
			match = function(n)
				return n:find("damage") or n:find("punch") or n:find("knockback")
					or n:find("detach") or n:find("combat") or n:find("faction")
					or n:find("allies") or n:find("enemies") or n:find("predict_aim")
					or n:find("drop_item") or n:find("loot") or n:find("shooter")
			end
		},
		{
			title = "Spawner Engine API",
			desc = "Natural mob spawning engine, environmental condition validation, "
				.. "light and elevation limits, active entity caps, and cohesive group spawning.",
			match = function(n)
				return n:find("spawn")
			end
		},
		{
			title = "Audio & Sound Subsystem API",
			desc = "Positional audio dispatcher, spatial distance attenuation, "
				.. "and pitch variation for mob sound cues.",
			match = function(n)
				return n:find("sound")
			end
		},
		{
			title = "Core Utilities, Spatial Queries & Event Bus API",
			desc = "RFC 4122 v4 UUID generation, raycast line-of-sight checks, player vitality verification, "
				.. "solid ground detection, headroom scanning, passable air clearance, and decoupled pub/sub event bus.",
			match = function(n)
				return n:find("uuid") or n:find("line_of_sight") or n:find("player_alive")
					or n:find("event") or n:find("listen") or n:find("emit") or n:find("util")
					or n:find("ground") or n:find("headroom") or n:find("avoid_solid_nodes")
			end
		}
	}

	-- Explicit mapping table for 100% precise grouping of all current x_mob_core public APIs
	local function_group_map = {
		-- Group 1: Lifecycle & Entity Registration
		["x_mob_core.register_mob"] = 1,
		["x_mob_core.transition_to"] = 1,
		["x_mob_core.set_armor_groups"] = 1,
		["x_mob_core.set_target"] = 1,
		["x_mob_core.set_texture"] = 1,
		["x_mob_core.register_step_hook"] = 1,
		["x_mob_core.unregister_step_hook"] = 1,
		["x_mob_core.schedule"] = 1,
		["x_mob_core.cancel_scheduled"] = 1,
		["x_mob_core.clear_scheduled"] = 1,

		-- Group 2: Navigation & Pathfinding
		["x_mob_core.find_path"] = 2,
		["x_mob_core.find_path_sync"] = 2,

		-- Group 3: Motor & Steering Controller
		["x_mob_core.retreat_from"] = 3,
		["x_mob_core.scan_for_player"] = 3,
		["x_mob_core.step_wander_or_idle"] = 3,
		["x_mob_core.step_move_or_idle"] = 3,
		["x_mob_core.halt_horizontal_velocity"] = 3,

		-- Group 4: Animation Subsystem
		["x_mob_core.play_animation"] = 4,
		["x_mob_core.stop_animation"] = 4,

		-- Group 5: Multi-Agent Pack, Swarm & Shoal Coordination
		["x_mob_core.step_regroup"] = 5,
		["x_mob_core.alert_nearby_allies"] = 5,
		["x_mob_core.check_leash"] = 5,
		["x_mob_core.broadcast_threat"] = 5,
		["x_mob_core.rally_followers"] = 5,
		["x_mob_core.clean_followers"] = 5,
		["x_mob_core.adopt_nearby_orphans"] = 5,
		["x_mob_core.add_follower"] = 5,
		["x_mob_core.remove_follower"] = 5,
		["x_mob_core.handle_leader_death"] = 5,
		["x_mob_core.spawn_initial_followers"] = 5,
		["x_mob_core.relink_follower"] = 5,
		["x_mob_core.calculate_repulsion"] = 5,
		["x_mob_core.elect_successor"] = 5,
		["x_mob_core.step_swarm"] = 5,
		["x_mob_core.step_flock"] = 5,
		["x_mob_core.step_swarm_combat"] = 5,

		-- Group 6: Combat, Damage, Factions & Loot
		["x_mob_core.handle_punch"] = 6,
		["x_mob_core.calculate_punch_damage"] = 6,
		["x_mob_core.dampen_water_knockback"] = 6,
		["x_mob_core.get_knockback_mult"] = 6,
		["x_mob_core.are_allies"] = 6,
		["x_mob_core.are_enemies"] = 6,
		["x_mob_core.get_factions"] = 6,
		["x_mob_core.indicate_damage"] = 6,
		["x_mob_core.clear_damage"] = 6,
		["x_mob_core.strip_damage_mod"] = 6,
		["x_mob_core.spawn_damage_particles"] = 6,
		["x_mob_core.detach_attached_children"] = 6,
		["x_mob_core.predict_aim"] = 6,
		["x_mob_core.drop_item"] = 6,
		["x_mob_core.drop_items"] = 6,

		-- Group 7: Spawner Engine
		["x_mob_core.register_spawn"] = 7,
		["x_mob_core.spawn_mob_group"] = 7,
		["x_mob_core.spawn_mob"] = 7,

		-- Group 8: Audio & Sound Subsystem
		["x_mob_core.play_sound"] = 8,
		["x_mob_core.stop_sound"] = 8,

		-- Group 9: Core Utilities, Spatial Queries & Event Bus
		["x_mob_core.generate_uuid"] = 9,
		["x_mob_core.line_of_sight"] = 9,
		["x_mob_core.is_player_alive"] = 9,
		["x_mob_core.get_ground_y"] = 9,
		["x_mob_core.pick_ground_waypoint"] = 9,
		["x_mob_core.get_headroom"] = 9,
		["x_mob_core.avoid_solid_nodes"] = 9,
		["x_mob_core.find_ground_level"] = 9,
		["x_mob_core.listen"] = 9,
		["x_mob_core.unlisten"] = 9,
		["x_mob_core.emit"] = 9,
	}

	-- Table of Contents
	emit("## Table of Contents")
	emit("")
	emit("- [Classes & Data Structures](#classes--data-structures)")
	if #aliases > 0 then
		emit("- [Type Aliases & Callbacks](#type-aliases--callbacks)")
	end
	for _, grp in ipairs(groups) do
		local anchor = make_anchor(grp.title)
		emit(string.format("- [%s](#%s)", grp.title, anchor))
	end
	emit("- [Registries & State Tables](#registries--state-tables)")
	emit("")
	emit("---")
	emit("")

	-- Classes
	emit("## Classes & Data Structures")
	emit("")
	for _, cls in ipairs(classes) do
		local cname = cls.name or (cls.defines and cls.defines[1] and cls.defines[1].view) or "Unknown"
		emit("### `" .. cname .. "`")
		emit("")
		if cls.desc and cls.desc ~= "" then
			emit(cls.desc)
			emit("")
		end

		if cls.fields and #cls.fields > 0 then
			emit("| Field | Type | Description |")
			emit("| :--- | :--- | :--- |")
			local seen_fields = {}
			for _, field in ipairs(cls.fields) do
				local fname = field.name
				local is_private = fname and fname:find("^_")
				if fname and not seen_fields[fname] and not is_private then
					seen_fields[fname] = true
					local ftype = (field.extends and field.extends.view) or (field.view) or "any"
					ftype = ftype:gsub("\r\n", " "):gsub("\n", " "):gsub("|", "\\|")
					local fdesc = (field.desc or ""):gsub("\r\n", " "):gsub("\n", " "):gsub("|", "\\|")
					fdesc = fdesc:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
					emit(string.format("| `%s` | `%s` | %s |", fname, ftype, fdesc))
				end
			end
			emit("")
		end
	end

	emit("---")
	emit("")

	-- Type Aliases
	if #aliases > 0 then
		emit("## Type Aliases & Callbacks")
		emit("")
		emit("| Type Alias | Signature / Definition |")
		emit("| :--- | :--- |")
		for _, alias in ipairs(aliases) do
			local aname = alias.name or (alias.defines and alias.defines[1] and alias.defines[1].view) or "Unknown"
			local def1 = alias.defines and alias.defines[1]
			local sig = (def1 and def1.view) or "any"
			sig = sig:gsub("\r\n", " "):gsub("\n", " "):gsub("|", "\\|")
			emit(string.format("| `%s` | `%s` |", aname, sig))
		end
		emit("")
		emit("---")
		emit("")
	end

	-- Helper to render a function entry
	local function render_func(fn)
		local fname = fn.name or (fn.defines and fn.defines[1] and fn.defines[1].name)
		local def = fn.defines and fn.defines[1]
		local ext = def and def.extends

		emit("#### `" .. tostring(fname) .. "`")
		emit("")

		local desc = (def and def.rawdesc) or (fn.desc) or ""
		-- Strip any trailing raw enum code block that LuaLS appends to rawdesc
		if desc:find("\n\n```lua") then
			desc = desc:sub(1, desc:find("\n\n```lua") - 1)
		end
		desc = desc:gsub("^%s+", ""):gsub("%s+$", "")

		if desc ~= "" then
			emit(desc)
			emit("")
		end

		-- Signature
		if ext and ext.view then
			emit("```lua")
			emit(ext.view)
			emit("```")
			emit("")
		end

		-- Parameters
		if ext and ext.args and #ext.args > 0 then
			emit("**Parameters:**")
			emit("")
			for _, arg in ipairs(ext.args) do
				local aname = arg.name or "?"
				local atype = arg.view or "any"
				local adesc = arg.desc or arg.rawdesc or ""
				if adesc ~= "" then
					emit(string.format("* `%s` (`%s`): %s", aname, atype, adesc))
				else
					emit(string.format("* `%s` (`%s`)", aname, atype))
				end
			end
			emit("")
		end

		-- Returns
		if ext and ext.returns then
			local rets = ext.returns
			if rets.type then rets = {rets} end
			if #rets > 0 then
				emit("**Returns:**")
				emit("")
				for _, ret in ipairs(rets) do
					local rname = ret.name
					local rtype = ret.view or "any"
					local rdesc = ret.desc or ret.rawdesc or ""
					if rname and rname ~= "" then
						if rdesc ~= "" then
							emit(string.format("* `%s` (`%s`): %s", rname, rtype, rdesc))
						else
							emit(string.format("* `%s` (`%s`)", rname, rtype))
						end
					else
						if rdesc ~= "" then
							emit(string.format("* `%s`: %s", rtype, rdesc))
						else
							emit(string.format("* `%s`", rtype))
						end
					end
				end
				emit("")
			end
		end
	end

	local assigned = {}
	for idx, grp in ipairs(groups) do
		emit("## " .. grp.title)
		emit("")
		emit(grp.desc)
		emit("")
		for _, fn in ipairs(functions) do
			local fn_name = fn.name or (fn.defines and fn.defines[1] and fn.defines[1].name) or ""
			if not assigned[fn_name] then
				local mapped_idx = function_group_map[fn_name]
				if mapped_idx == idx or (not mapped_idx and grp.match(fn_name)) then
					assigned[fn_name] = true
					render_func(fn)
				end
			end
		end
		emit("---")
		emit("")
	end

	-- Remaining functions (if any newly added APIs were not matched above)
	local remaining = {}
	for _, fn in ipairs(functions) do
		local fn_name = fn.name or (fn.defines and fn.defines[1] and fn.defines[1].name) or ""
		if not assigned[fn_name] then
			table.insert(remaining, fn)
		end
	end
	if #remaining > 0 then
		emit("## Miscellaneous Functions")
		emit("")
		for _, fn in ipairs(remaining) do
			render_func(fn)
		end
		emit("---")
		emit("")
	end

	-- Registries & State Tables
	emit("## Registries & State Tables")
	emit("")
	emit("| Registry / Table | Type | Description |")
	emit("| :--- | :--- | :--- |")
	for _, var in ipairs(variables) do
		local vname = var.name or ""
		local def = var.defines and var.defines[1]
		local vtype = (def and def.view and def.view ~= "unknown" and def.view)
			or (def and def.extends and def.extends.view and def.extends.view ~= "unknown" and def.extends.view)
			or "table"
		vtype = vtype:gsub("\r\n", " "):gsub("\n", " "):gsub("|", "\\|")
		local vdesc = (def and def.rawdesc) or (var.desc) or ""
		vdesc = vdesc:gsub("\r\n", " "):gsub("\n", " "):gsub("|", "\\|")
		vdesc = vdesc:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " ")
		emit(string.format("| `%s` | `%s` | %s |", vname, vtype, vdesc))
	end
	emit("")

	local content = table.concat(lines, "\n")
	local mdOk, mdErr = util.saveFile(mdPath, content)

	if not (jsonOk and mdOk) then
		return false, {jsonPath, mdPath}, {jsonErr, mdErr}
	end

	return true, {jsonPath, mdPath}
end
