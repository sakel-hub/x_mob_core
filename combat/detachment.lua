--[[
	x_mob_core - Child Detachment Subsystem
	Detaches and drops all attached child objects (arrows, passengers, accessories) from a mob when it dies
]]

---@class DetachmentSubsystem
local detachment = {}

--- Detaches and drops all attached child objects (arrows, passengers, accessories) from a mob when it dies
---@param mob_obj ObjectRef The mob entity ObjectRef
function detachment.detach_attached_children(mob_obj)
	if not mob_obj or not mob_obj:is_valid() then
		return
	end

	local children = mob_obj:get_children()
	if not children or #children == 0 then
		return
	end

	local mob_pos = mob_obj:get_pos() or vector.new(0, 0, 0)

	for i = 1, #children do
		local child = children[i]
		if child and child:is_valid() then
			if child:is_player() then
				-- Detach living player passengers safely
				child:set_detach()
				local ppos = child:get_pos() or mob_pos
				child:set_pos({x = ppos.x, y = ppos.y + 0.2, z = ppos.z})
			else
				local ent = child:get_luaentity()
				local is_arrow = ent and (ent._is_arrow or ent.is_arrow or (ent.name and ent.name:find("^x_bows:")))

				if is_arrow then
					-- Smart Drop for arrows
					local child_pos = child:get_pos() or mob_pos
					local scatter_pos = {
						x = child_pos.x + (math.random() - 0.5) * 0.6,
						y = child_pos.y + 0.2,
						z = child_pos.z + (math.random() - 0.5) * 0.6,
					}

					local reg_ent = ent.name and core.registered_entities[ent.name]
					local on_death_fn = ent.on_death or (reg_ent and reg_ent.on_death)
					local called_death = false

					if type(on_death_fn) == "function" then
						local ok = pcall(function()
							on_death_fn(ent, nil)
						end)
						called_death = ok
					end

					-- Fallback drop if on_death was not available or not defined
					if not called_death and not ent._dropped then
						ent._dropped = true
						local is_creative = ent._is_creative or ent._creative or ent._no_drop
						local has_infinity = ent._x_enchanting and ent._x_enchanting.infinity and ent._x_enchanting.infinity.value > 0

						if not is_creative and not has_infinity then
							local item_name = ent._arrow_name or ent.itemstring or ent._item_name
							if item_name and item_name ~= "" then
								local _, dropped = core.item_drop(ItemStack(item_name), nil, scatter_pos)
								if dropped and dropped:is_valid() then
									dropped:set_velocity({
										x = (math.random() - 0.5) * 2.0,
										y = 2.0 + math.random() * 1.5,
										z = (math.random() - 0.5) * 2.0,
									})
								end
							end
						end
					end

					-- Cleanup particle spawners if still active
					if ent._trail_spawner_id then
						core.delete_particlespawner(ent._trail_spawner_id)
						ent._trail_spawner_id = nil
					end
					if ent._bubble_spawner_id then
						core.delete_particlespawner(ent._bubble_spawner_id)
						ent._bubble_spawner_id = nil
					end

					-- Safely detach and remove the arrow entity
					child:set_detach()
					child:remove()
				elseif ent and (ent._is_visual or ent.is_visual) then
					-- Visual prop attachment: remove to prevent ghost entities
					child:remove()
				else
					-- Generic attached entity: detach safely
					if ent and ent.on_detach_on_death then
						ent:on_detach_on_death(mob_obj)
					else
						child:set_detach()
					end
				end
			end
		end
	end
end

return detachment
