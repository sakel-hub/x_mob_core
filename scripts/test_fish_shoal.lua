-- Simulation of skeleton swordfish shoal in x_mob_core
local world_nodes = {}
for x = -50, 50 do
	for z = -50, 50 do
		for y = -20, 0 do
			world_nodes[string.format("%d,%d,%d", x, y, z)] = {name = "default:water_source"}
		end
		for y = 1, 10 do
			world_nodes[string.format("%d,%d,%d", x, y, z)] = {name = "air"}
		end
	end
end

local all_entities = {}

local core = {
	get_modpath = function(modname)
		if modname == "x_mob_core" then return "." end
		if modname == "x_mobs" then return "../x_mobs" end
		return nil
	end,
	registered_nodes = {
		["default:water_source"] = {walkable = false, liquidtype = "source", liquid_viscosity = 1},
		["air"] = {walkable = false},
	},
	get_node = function(pos)
		local k = string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
		return world_nodes[k] or {name = "air"}
	end,
	get_node_or_nil = function(pos)
		local k = string.format("%d,%d,%d", math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
		return world_nodes[k] or {name = "air"}
	end,
	get_item_group = function(name, group)
		if group == "water" and name:find("water") then return 1 end
		return 0
	end,
	dir_to_yaw = function(dir)
		local atan = math.atan2 or math.atan
		return -atan(dir.x, dir.z)
	end,
	yaw_to_dir = function(yaw)
		return {x = -math.sin(yaw), y = 0, z = math.cos(yaw)}
	end,
	get_connected_players = function()
		return {
			{
				is_valid = function() return true end,
				is_player = function() return true end,
				get_pos = function() return {x = 0, y = -5, z = 0} end,
				get_hp = function() return 20 end,
			}
		}
	end,
	get_objects_inside_radius = function(pos, radius)
		local res = {}
		for _, e in ipairs(all_entities) do
			local p = e.pos
			local dx = p.x - pos.x
			local dy = p.y - pos.y
			local dz = p.z - pos.z
			if math.sqrt(dx*dx + dy*dy + dz*dz) <= radius then
				table.insert(res, e.object)
			end
		end
		return res
	end,
	log = function() end,
	serialize = function(t)
		local parts = {}
		for k, v in pairs(t) do
			table.insert(parts, string.format("%s=%q", k, tostring(v)))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end,
	deserialize = function(_s) return {} end,
	register_on_mods_loaded = function() end,
	register_globalstep = function() end,
	add_entity = function(_pos, _name, _staticdata)
		return nil
	end,
}
_G.core = core
_G.minetest = core

local vector = {
	distance = function(p1, p2)
		local dx = p1.x - p2.x
		local dy = p1.y - p2.y
		local dz = p1.z - p2.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
	direction = function(p1, p2)
		local dx = p2.x - p1.x
		local dy = p2.y - p1.y
		local dz = p2.z - p1.z
		local len = math.sqrt(dx * dx + dy * dy + dz * dz)
		if len < 0.0001 then return {x = 0, y = 0, z = 0} end
		return {x = dx / len, y = dy / len, z = dz / len}
	end,
	round = function(p)
		return {x = math.floor(p.x + 0.5), y = math.floor(p.y + 0.5), z = math.floor(p.z + 0.5)}
	end,
}
_G.vector = vector
_G.x_mob_core = {
	events = {
		listen = function() end,
	},
	animator = {
		play = function() end,
	},
}

local shoal = dofile("pack/shoal.lua")
local squad = dofile("pack/squad.lua")

local def = {
	name = "x_mobs:skeleton_swordfish",
	is_floating = true,
	walk_speed = 3.2,
	pursuit_speed = 5.6,
	wander_speed = 2.6,
	shoal = {
		size = 6,
		spacing_x = 2.2,
		spacing_z = 1.8,
		spacing_y = 0.6,
		repulsion_radius = 1.8,
		repulsion_strength = 2.0,
		wander_radius = 24.0,
		cull_distance = 64.0,
		predator = true,
	},
}

local function create_fish(pos, is_follower, follower_index, pack_id)
	local ent = {
		name = "x_mobs:skeleton_swordfish",
		pos = {x = pos.x, y = pos.y, z = pos.z},
		vel = {x = 0, y = 0, z = 0},
		yaw = 0,
		rot = {x = 0, y = 0, z = 0},
		is_dead = false,
		_def = def,
		wander_speed = def.wander_speed,
		pursuit_speed = def.pursuit_speed,
	}
	local obj = {
		is_valid = function() return not ent.is_dead end,
		is_player = function() return false end,
		get_luaentity = function() return ent end,
		get_pos = function() return ent.pos end,
		set_pos = function(_self, p) ent.pos = {x = p.x, y = p.y, z = p.z} end,
		get_velocity = function() return ent.vel end,
		set_velocity = function(_self, v) ent.vel = {x = v.x, y = v.y, z = v.z} end,
		get_yaw = function() return ent.yaw end,
		set_yaw = function(_self, y) ent.yaw = y end,
		get_rotation = function() return ent.rot end,
		set_rotation = function(_self, r) ent.rot = {x = r.x, y = r.y, z = r.z} end,
		set_acceleration = function() end,
		get_animations = function() return {} end,
		set_animation = function() end,
		play_animation = function() end,
		update_animation = function() end,
	}
	ent.object = obj

	shoal.init_entity(ent, def, {
		is_follower = is_follower,
		follower_index = follower_index,
		pack_id = pack_id,
		cluster_spawned = true,
	})
	table.insert(all_entities, ent)
	return obj, ent
end

core.add_entity = function(pos, _name, _staticdata)
	local obj = create_fish(pos, true, 1, "test_pack")
	return obj
end

-- Create leader at (0, -5, 0)
local leader_obj, leader_ent = create_fish({x = 0, y = -5, z = 0}, false, 0, "test_pack")
print("Leader role:", leader_ent.pack_role, "pack_id:", leader_ent.pack_id, "capacity:", leader_ent.pack_max_followers)
assert(leader_ent.pack_max_followers == 5, "Shoal leader should have max_followers = 5")

-- Spawn followers manually as squad.spawn_cluster would
for i = 1, 5 do
	local f_obj, f_ent = create_fish({x = i * 2, y = -5, z = -i * 2}, true, i, leader_ent.pack_id)
	squad.add_follower(leader_ent, f_obj)
	f_ent.leader_obj = leader_obj
end

print("Leader follower count:", #leader_ent.pack_followers)
assert(#leader_ent.pack_followers == 5, "Leader must have 5 followers registered")

-- Simulate world reload: all followers lose their in-memory leader_obj pointer
for i = 2, #all_entities do
	all_entities[i].leader_obj = nil
end

-- Followers attempt relinking in arbitrary order (reverse order to ensure followers are encountered first)
for i = #all_entities, 2, -1 do
	local fe = all_entities[i]
	local relinked = squad.relink_follower(fe, 64.0)
	assert(relinked == true, string.format("Follower %d must relink successfully", fe.follower_index))
	assert(fe.leader_obj == leader_obj, string.format("Follower %d must link to LEADER, not peer", fe.follower_index))
end
print("All 5 followers successfully relinked to the true LEADER!")

-- Simulate 100 steps (10 seconds) of ambient schooling
for _ = 1, 100 do
	local dt = 0.1
	-- Step leader
	shoal.step(leader_ent, dt, def)
	leader_ent.pos.x = leader_ent.pos.x + leader_ent.vel.x * dt
	leader_ent.pos.y = leader_ent.pos.y + leader_ent.vel.y * dt
	leader_ent.pos.z = leader_ent.pos.z + leader_ent.vel.z * dt

	-- Step followers
	for i = 2, #all_entities do
		local f_ent = all_entities[i]
		shoal.step(f_ent, dt, def)
		f_ent.pos.x = f_ent.pos.x + f_ent.vel.x * dt
		f_ent.pos.y = f_ent.pos.y + f_ent.vel.y * dt
		f_ent.pos.z = f_ent.pos.z + f_ent.vel.z * dt
	end
end

local leader_spd = math.sqrt(leader_ent.vel.x^2 + leader_ent.vel.z^2)
print(string.format("\nAfter 100 steps (10 seconds):"))
print(string.format("Leader pos: (%.1f, %.1f, %.1f), speed: %.2f",
	leader_ent.pos.x, leader_ent.pos.y, leader_ent.pos.z, leader_spd))
assert(leader_spd >= 2.0, "Leader speed should be cruising speed (not stalled)")

for i = 2, #all_entities do
	local fe = all_entities[i]
	local d = vector.distance(leader_ent.pos, fe.pos)
	local spd = math.sqrt(fe.vel.x^2 + fe.vel.z^2)
	print(string.format("Follower %d pos: (%.1f, %.1f, %.1f), speed: %.2f, dist_to_leader: %.2f",
		fe.follower_index, fe.pos.x, fe.pos.y, fe.pos.z, spd, d))
	assert(fe.leader_obj == leader_obj, "Follower must still be following leader")
	assert(d < 8.0, string.format("Follower %d is too far from leader: %.2f", fe.follower_index, d))
end

print("\nShoal simulation completed successfully with perfect cohesion and cruising locomotion!")
