--[[
	x_mob_core - Type Definitions & Annotations
	EmmyLua annotations for IDE code completion and static analysis
]]

---@class AnimationParams
---@field speed? number Playback speed multiplier (default: 1.0)
---@field loop? boolean Whether to loop animation (default: true)
---@field blend? number Blend duration in seconds (default: 0.15)
---@field priority? number Animation track priority (default: 0)
---@field force? boolean Force restart track even if already playing

---@class MobAnimationDef
---@field track string Named glTF animation track
---@field speed? number Playback speed multiplier (default: 1.0)
---@field loop? boolean Whether to loop animation by default

---@class MobPackDef
---@field role? "leader"|"member" Role within the pack
---@field pack_id? string Optional existing pack UUID
---@field leader_type? string Expected entity name of the leader
---@field follower_type? string Expected entity name of the followers
---@field max_followers? integer Max followers for a leader (default: 3)
---@field leash_distance? number Distance before followers regroup (default: 18.0)
---@field regroup_distance? number Target distance when regrouping to leader (default: 4.0)
---@field spawn_on_init? boolean Whether leader auto-spawns initial followers on activate

---@field on_leader_lost? "fight"|"flee"|fun(self: table, leader?: table) Callback or behavior when pack leader dies

---@class ShooterConfigDef
---@field projectile? string Technical entity name of projectile (default: "x_mobs:archer_arrow")
---@field range? number Maximum firing range in nodes (default: def.attack_range or 15.0)
---@field min_range? number Minimum distance threshold under which mob retreats (default: 0.0)
---@field retreat_speed? number Speed when kiting / backing away from player (default: 1.0)
---@field shoot_while_retreating? boolean Whether mob can fire projectiles while kiting / backing away (default: true)
---@field cooldown? number Attack cooldown between shots in seconds (default: 2.0)
---@field fire_duration? number Duration mob holds shooting pose in seconds (default: 1.0)
---@field fire_delay? number Delay before projectile is released in seconds (default: 0.4)
---@field velocity? number Projectile flight speed in nodes/sec (default: 18.0)
---@field damage? number Projectile damage (default: 3)
---@field animation? string Animation track name played when shooting (default: "attack")
---@field sound? string Sound played when shooting (default: "shoot")
---@field predict_aim? boolean Whether to apply aim lead prediction based on target velocity (default: false)

---@class ProjectileTargetOptions
---@field allow_players? boolean Whether players are valid targets (default: true)
---@field allow_allies? boolean Whether friendly/allied entities can be hit (default: false)
---@field ignore_entities? string[]|table<string, boolean> Additional entity technical names to ignore

---@class ProjectileStepOptions: ProjectileTargetOptions
---@field damage? number Damage applied when impacting target without on_hit_object (default: self._damage or 5)
---@field lifetime? number Maximum projectile lifetime in seconds before removal (default: 4.0)
---@field radius? number Proximity fallback collision radius in nodes (default: 1.5)
---@field rotate? boolean Whether to automatically rotate projectile along velocity vector (default: true)
---@field remove_on_hit? boolean Whether to remove projectile entity upon impact (default: true)
---@field on_hit_object? fun(self: table, hit_obj: ObjectRef, hit_pos: Vector, dir: Vector) Object hit callback
---@field on_hit_node? fun(self: table, hit_pos: Vector, node: table) Callback when hitting a solid node
---@field on_hit? fun(self: table, hit_obj: ObjectRef|nil, hit_pos: Vector) Callback executed on any impact
---@field on_step? fun(self: table, dtime: number, pos: Vector) Callback executed on every unobstructed flight step

---@class CustomStateDef
---@field enter? fun(self: table) Called when state is entered
---@field step fun(self: table, dtime: number): string|nil State step tick; return state name to transition
---@field exit? fun(self: table) Called when state is exited

---@class SoundConfigDef
---@field name string|string[] Technical sound name or list of sound variations
---@field gain? number Volume multiplier (default: 1.0)
---@field distance? number Maximum audible distance in nodes (default: 16.0)
---@field pitch? number Base pitch multiplier (default: 1.0)
---@field pitch_jitter? number Random pitch variation factor (default: 0.05)
---@field min_interval? number Minimum cooldown between automatic triggers (default: 8.0)
---@field max_interval? number Maximum cooldown between automatic triggers (default: 22.0)
---@field chance? number Probability to play when interval expires (default: 1.0)

---@class MobSoundDef
---@field base? string Default sound-group name used as fallback for all categories
---@field distance? number Global default hear distance in nodes (default: 16.0)
---@field gain? number Global default volume multiplier (default: 1.0)
---@field pitch_jitter? number Global default pitch jitter factor (default: 0.05)
---@field hurt? string|SoundConfigDef Sound played on non-lethal damage
---@field death? string|SoundConfigDef Sound played on lethal damage
---@field random? string|SoundConfigDef Periodic ambient sound played during wander/idle
---@field attack? string|SoundConfigDef Sound played on melee or ranged strike
---@field alert? string|SoundConfigDef Sound played when a target is first acquired

---@class DamageEffectDef
---@field enabled? boolean Set to false to disable default core damage particles (default: true)
---@field type? "blood"|"smoke"|"ichor"|"spectral"|"sparks"|"none"|string Particle effect preset style
---@field color? string Hex color string override (e.g. "#8A0303")
---@field colors? string[] Multi-shade hex color list override for texpool (e.g. {"#E0AAFF", "#C77DFF", "#9D4EDD"})
---@field count? integer Base particle droplet count (default: 8)
---@field scale? number Particle size multiplier (default: 1.0)
---@field texture? string Custom texture override (e.g. "[fill:3x3:#FF0000")

---@class SwarmAlertDef
---@field enabled? boolean Whether pack threat alerting is enabled
---@field radius? number Search radius for alerting nearby pack allies (default: 24.0)
---@field max_allies? integer Maximum pack members rallied per threat alert (default: 8)

---@class SwarmCombatDef
---@field mode? "vortex"|"direct" Combat locomotion style (default: "vortex")
---@field orbit_radius? number Base orbit distance around target (default: 3.2)
---@field orbit_shells? integer Concentric radial shells for multi-agent spacing (default: 3)
---@field two_way_orbit? boolean Alternate CW and CCW orbits (default: true)
---@field exclusion_radius? number Repulsion cylinder around target (default: 2.4)
---@field dive_speed? number Speed during dive-bomb run (default: 6.4)
---@field dive_range? number Distance threshold to trigger dive attack (default: 9.0)
---@field height_offset? number Desired altitude relative to target (default: 1.0)
---@field clamp_ceiling? boolean Prevent flying above target head (default: true)
---@field recoil? number Horizontal pushback force after attack punch (default: 4.5)

---@class SwarmConfigDef
---@field enabled? boolean Whether swarm intelligence is active (default: true)
---@field size? integer Total swarm cluster size (default: 4)
---@field member_type? string Entity technical name of swarm peers (default: self.name)
---@field repulsion_radius? number Inter-mob 3D separation radius (default: 2.2)
---@field repulsion_strength? number Inter-mob repulsion push force (default: 2.8)
---@field flock_radius? number Idle orbiting radius around anchor (default: 2.0)
---@field hover_elevation? number Height anchored above walkable terrain (default: 1.4)
---@field organic_jitter? boolean Multi-frequency harmonic velocity jitter (default: true)
---@field micro_darts? boolean Random sudden velocity impulses with drag decay (default: true)
---@field auto_succession? boolean Democratic election of new anchor on leader death (default: true)
---@field stagger_attacks? boolean Offsets attack cooldowns across swarm members (default: true)
---@field attack_cooldown_min? number Minimum cooldown before next dive attack (default: 2.5)
---@field attack_cooldown_rand? number Random additional cooldown before next dive (default: 2.5)
---@field combat? SwarmCombatDef Coordinated combat vortex and dive-bomb options

---@class DropEntryDef
---@field name string Technical item name (e.g. "everness:quartz_crystal")
---@field min? integer Minimum count to drop (default: 1)
---@field max? integer Maximum count to drop (default: 1)
---@field chance? number Probability to drop between 0.0 and 1.0 (default: 1.0)


---@class DropOptions
---@field up_vel_min? number Minimum upward launch velocity (default: 4.6)
---@field up_vel_max? number Maximum upward launch velocity (default: 5.8)
---@field spread_min? number Minimum horizontal spread velocity (default: 1.0)
---@field spread_max? number Maximum horizontal spread velocity (default: 1.6)
---@field particles? boolean Enable sparkle/burst particles (default: true)
---@field trails? boolean Enable sparkling trail attached to flying items (default: true)
---@field particle_color? string Hex color for sparkle particles
---@field sound? string Sound identifier to play on drop
---@field killer? ObjectRef Killer object/player if applicable

---@class HealthRegenDef
---@field rate? number HP regenerated per second while running away or passively (default: 0.5)
---@field enabled? boolean Whether health regeneration is enabled (default: true)
---@field overlay? boolean Whether visual texture overlay flashes on regeneration (default: true)
---@field overlay_color? string Custom texture modifier overlay string (default: "^[colorize:#FFFFFF60")
---@field passive? boolean Whether regeneration occurs passively at all times (default: false)
---@field flee_threshold? number Absolute HP threshold below which mob flees (default: nil / 25% max)
---@field flee_ratio? number HP ratio below which mob flees (default: 0.25)
---@field return_threshold? number Absolute HP threshold to exit fleeing and return to combat (default: nil / 60% max)
---@field return_ratio? number HP ratio to exit fleeing and return to combat (default: 0.60)

---@class MobRegistrationDef
---@field textures? string|string[]|(string[])[] Texture or variations list (preferred in initial_properties)
---@field initial_properties table Luanti ObjectRef properties (hp_max, collisionbox, mesh, visual_size, textures, etc.)
---@field collisionbox? number[] Optional 6-element collision box: {minx, miny, minz, maxx, maxy, maxz}
---@field selectionbox? table|number[] Optional selection box: {minx, miny, minz, maxx, maxy, maxz}
---@field armor_groups? table<string, number> Luanti armor groups (e.g. {fleshy = 80})
---@field knockback_mult? number Knockback impulse multiplier (0 for unyielding/immune, default: 1.5)
---@field faction? string|string[] Faction tag or list of faction tags (default: "monsters")
---@field factions? string|string[] Alias for faction
---@field friendly_fire? boolean Whether allies/same-faction can damage this mob (default: false)

---@field walk_speed? number Base walking speed (default: 2.5)
---@field pursuit_speed? number Pursuit running speed (default: 3.5)
---@field wander_speed? number Wandering patrol speed (default: 1.5)
---@field flee_speed? number Fleeing speed when low on health (default: 4.0)
---@field health_regen? number|boolean|HealthRegenDef Health regeneration rate, disable toggle, or configuration table
---@field on_regen_step? fun(self: table, hp_added: number) Optional callback executed on health regeneration tick
---@field on_return_to_fight? fun(self: table) Optional callback executed when mob recovers HP and exits fleeing
---@field can_wander? boolean Whether entity wanders when idle (default: true)
---@field wander_radius? number Maximum wandering patrol radius (default: 10.0)
---@field can_swim? boolean Whether entity navigates water (default: true)
---@field can_climb? boolean Whether entity climbs ladders and vines (default: false)
---@field can_open_doors? boolean Whether entity opens doors (default: false)
---@field can_crawl? boolean Whether entity navigates 1-block crawlways (default: false)
---@field is_floating? boolean Whether entity hovers in mid-air (default: false)
---@field hover_offset? number Desired hovering height above ground in nodes (default: 1.5)
---@field aggro_radius? number Detection range in nodes (default: 20.0)
---@field attack_range? number Attack reach in nodes (default: 2.5)
---@field damage? number Base melee damage (default: 4)
---@field attack_interval? number Cooldown between attacks in seconds (default: 1.2)
---@field scan_interval? number Frequency of target scanning in seconds (default: 0.5)
---@field death_duration? number Duration before entity removal on death in seconds
---@field swarm_alert? SwarmAlertDef Pack rally configuration on threat detection

---@field animations? table<string, MobAnimationDef|string> Declarative glTF animations map
---@field pack? MobPackDef Pack and squad coordination options
---@field swarm? SwarmConfigDef Swarm intelligence, 3D flocking, and vortex combat configuration
---@field shoal? ShoalConfigDef Fish schooling, 3D boundary avoidance, and anchor steering configuration
---@field shooter? ShooterConfigDef Ranged combat and kiting configuration
---@field sounds? string|MobSoundDef Acoustic sound feedback configuration
---@field damage_effect? DamageEffectDef|string|boolean Hit particle feedback (false/"none" disables)
---@field health_bar? MobHealthBarConfig|boolean Overhead combat health bar configuration (false disables)
---@field drops? (DropEntryDef|string)[] Declarative loot drop table spawned on defeat
---@field drop_options? DropOptions Physics, particle, and sound overrides for mob drops
---@field custom_states? table<string, CustomStateDef> Custom state machine states
---@field hooks? table<string, fun(self: table, ...)> Lifecycle hook callbacks
---@field despawn? boolean Enables or disables distance despawning (default: true)
---@field despawn_timer? number Duration in seconds entity remains far from players before despawning (default: 45.0)
---@field despawn_in_daylight? boolean Despawns mob in daytime sun without drops (default: false)
---@field despawn_natural_light? integer Minimum natural light level to trigger daylight despawn (default: 11)
---@field despawn_conditions? DespawnConditionsDef Granular despawn triggers (daylight, time-of-day ranges)
---@field on_despawn? fun(self: table, reason?: string) Callback when entity despawns gracefully
---@field on_activate? fun(self: table, staticdata: string, dtime_s: number) Called when entity activates in world
---@field on_step? fun(self: table, dtime: number, moveresult: table) Callback on each physics/logic step
---@field on_punch? fun(self: table, puncher: ObjectRef, tflp: number, tool_caps: table, dir: Vector, damage: number)
---@field on_hurt? fun(self: table, puncher: ObjectRef, damage: number) Callback invoked when entity takes damage
---@field on_death? fun(self: table, killer: ObjectRef) Callback invoked when entity dies
---@field on_rightclick? fun(self: table, clicker: ObjectRef) Callback invoked when entity is right-clicked
---@field get_staticdata? fun(self: table): string Callback returning serialized state string for persistence

---@class DespawnConditionsDef
---@field daylight? boolean Despawn when exposed to daytime sunlight (default: false)
---@field min_natural_light? integer Natural sunlight threshold (default: 11)
---@field min_time? number Time of day window start (0.0 to 1.0)
---@field max_time? number Time of day window end (0.0 to 1.0)
---@field time_range? { min: number, max: number } Custom time-of-day despawn window
---@field require_natural_light? boolean If true, time_range despawn only applies if exposed to natural sunlight

---@class ShoalConfigDef
---@field enabled? boolean Whether fish schooling is enabled (default: true)
---@field size? integer Total fish in school including leader (default: 6)
---@field member_type? string Custom technical entity name for school followers (default: self.name)
---@field spacing_x? number Lateral distance between staggered school members (default: 2.2)
---@field spacing_z? number Longitudinal trailing distance between school ranks (default: 1.8)
---@field spacing_y? number Vertical depth tier spacing (default: 0.60)
---@field wander_radius? number Leader 3D patrol radius in nodes (default: 16.0)
---@field cull_distance? number Active player proximity distance before hibernation (default: 36.0)
---@field predator? boolean Whether school attacks threats or flees (default: true)
---@field auto_succession? boolean Whether surviving followers promote new leader on death (default: true)
---@field repulsion_radius? number Separation radius in nodes (defaults to diameter + padding)
---@field repulsion_strength? number Anti-stacking separation push multiplier (default: 2.2)
---@field separation_padding? number Extra distance padding added on top of collisionbox diameter (default: 0.5)

---@class MobHealthBarColorBand
---@field threshold number Health ratio threshold (0.0 to 1.0)
---@field color string Hex color string (e.g. "#00FF00")

---@class MobHealthBarConfig
---@field enabled? boolean Whether health bar is enabled for this mob (default: true)
---@field width? integer Texture width in pixels (default: 64)
---@field height? integer Texture height in pixels (default: 8)
---@field border? integer Border thickness in pixels (default: 1)
---@field border_color? string Hex color for outer border (default: "#111111")
---@field empty_color? string Hex color for depleted health background track (default: "#330000")
---@field colors? MobHealthBarColorBand[] List of color thresholds evaluated from highest to lowest
---@field auto_scale? boolean Whether to proportionally scale visual_size to mob bounding box (default: true)
---@field visual_size? Vector2d Explicit sprite visual size override in world coordinates
---@field spacing? number Spacing in nodes above mob collisionbox top (default: 0.35)
---@field offset_y? number Direct height offset override in nodes
---@field timeout? number Duration in seconds before health bar auto-hides (default: 4.0)
---@field auto_remove? boolean Whether to remove child entity on timeout (default: true)
---@field glow? integer Light emission in dark environments 0..14 (default: 5)

---@class SpawnConfig
---@field nodes? string[] Valid ground node names or group filters (e.g. "group:water")
---@field exclude_nodes? string[] Specific nodes to explicitly exclude from spawning (e.g. "default:river_water_source")
---@field exclude_groups? string[] Node groups to explicitly exclude from spawning (e.g. "river_water")
---@field is_aquatic? boolean Whether mob spawns submerged inside liquid rather than on surface
---@field biomes? string[] Optional list of biome technical names (e.g. {"everness:crystal_forest"})
---@field chance? integer 1 in X chance per tick (default: 1000)
---@field active_object_count? integer Max nearby instances allowed (default: 1)
---@field max_total_in_radius? integer Max total living mobs allowed in spawn radius (default: 8)
---@field group_min? integer Minimum entities to spawn in a pack/swarm (default: 1)
---@field group_max? integer Maximum entities to spawn in a pack/swarm (default: 1)
---@field day_only? boolean Only spawn during daytime (0.20 <= time <= 0.80)
---@field night_only? boolean Only spawn during nighttime (time < 0.20 or time > 0.80)
---@field min_time? number Specific minimum time-of-day (0.0 to 1.0)
---@field max_time? number Specific maximum time-of-day (0.0 to 1.0)
---@field min_light? integer Minimum light level 0..15 (default: 0)
---@field max_light? integer Maximum light level 0..15 (default: 15)
---@field min_elevation? number Minimum Y coordinate (default: -31000)
---@field max_elevation? number Maximum Y coordinate (default: 31000)
---@field mob_name? string Optional entity technical name override

---@class SpawnDefinition : SpawnConfig
---@field mob_name? string Entity technical name (e.g. "x_mobs:spider")

---@alias PathfindingCallback fun(path: Vector[]|nil) Callback invoked when asynchronous path search completes
--- Standard pub-sub event names emitted by x_mob_core:
--- - "on_mob_spawn": (mob: table, is_fresh: boolean)
--- - "on_mob_death": (mob: table, puncher: ObjectRef|nil)
--- - "on_mob_despawn": (mob: table)
--- - "on_mob_hurt": (mob: table, puncher: ObjectRef|nil, dmg: number)
--- - "on_mob_target": (mob: table, target: ObjectRef|nil, old_target: ObjectRef|nil)
--- - "on_mob_rightclick": (mob: table, clicker: ObjectRef|nil, itemstack: ItemStack|nil)
---@alias CoreEventName "on_mob_spawn"|"on_mob_death"|"on_mob_despawn"
---| "on_mob_hurt"|"on_mob_target"|"on_mob_rightclick"|string
---@alias EventListenerCallback fun(...: any) Callback function invoked when a pub-sub event is emitted

local types = {}
return types
