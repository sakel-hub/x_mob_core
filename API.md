# x_mob_core API Reference

High-performance, zero-dependency S.O.L.I.D. mob and spawner framework for Luanti.

## Table of Contents

- [Classes & Data Structures](#classes--data-structures)
- [Type Aliases & Callbacks](#type-aliases--callbacks)
- [Lifecycle & Entity Registration API](#lifecycle--entity-registration-api)
- [Navigation & Pathfinding API](#navigation--pathfinding-api)
- [Motor & Steering Controller API](#motor--steering-controller-api)
- [Animation Subsystem API](#animation-subsystem-api)
- [Multi-Agent Pack, Swarm & Shoal Coordination API](#multi-agent-pack-swarm--shoal-coordination-api)
- [Combat, Damage, Factions & Loot API](#combat-damage-factions--loot-api)
- [Spawner Engine API](#spawner-engine-api)
- [Audio & Sound Subsystem API](#audio--sound-subsystem-api)
- [Core Utilities, Spatial Queries & Event Bus API](#core-utilities-spatial-queries--event-bus-api)
- [Registries & State Tables](#registries--state-tables)

---

## Classes & Data Structures

### `AnimationParams`

| Field | Type | Description |
| :--- | :--- | :--- |
| `blend` | `number?` | Blend duration in seconds (default: 0.15) |
| `force` | `boolean?` | Force restart track even if already playing |
| `loop` | `boolean?` | Whether to loop animation (default: true) |
| `priority` | `number?` | Animation track priority (default: 0) |
| `speed` | `number?` | Playback speed multiplier (default: 1.0) |

### `AnimatorSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `play` | `function AnimatorSubsystem.play(obj: ObjectRef, track_name: string, params?: AnimationParams)   -> success: boolean` | Dispatches skeletal animation to a Luanti object using modern glTF track playback @*param* `obj` — Target entity ObjectRef @*param* `track_name` — Named glTF animation track identifier @*param* `params` — Playback options (speed, loop, blend, priority, force) @*return* `success` — Whether animation playback was successfully dispatched |
| `stop` | `function AnimatorSubsystem.stop(obj: ObjectRef, track_name?: string)` | Stops current animation tracks on an object @*param* `track_name` — Optional specific track to stop |

### `CoordinationSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `broadcast_threat` | `function CoordinationSubsystem.broadcast_threat(self: table, target: ObjectRef, radius?: number, max_allies?: integer)` | Broadcasts alert to nearby pack members or allies when taking damage or spotting an enemy. Directly assigns `ent.target = target` and transitions idle/roaming allies into `"combat"`. Note: This is an imperative function requiring an active `ObjectRef`. Unlike declarative `swarm_alert`, it does not write coordinate memory for obscured allies, nor does it trigger automatically on death. @*param* `self` — Mob instance @*param* `target` — Threat target @*param* `radius` — Alert radius in nodes (default: 16.0) @*param* `max_allies` — Max allies to alert (default: 4) |
| `calculate_repulsion` | `function CoordinationSubsystem.calculate_repulsion(self: table, pos: Vector, radius?: number, strength?: number, ignore_behind?: boolean, min_sep?: number, vertical_factor?: number, horizontal_bias?: boolean)   -> sep_x: number   2. sep_y: number   3. sep_z: number` | Calculates 3D multi-agent Boids spatial repulsion with anti-stacking and soft/hard buffers @*param* `self` — Mob instance @*param* `pos` — Current world position @*param* `radius` — Repulsion radius (default: 2.0) @*param* `strength` — Push force multiplier (default: 2.4) @*param* `ignore_behind` — If true, ignores entities trailing behind self.object @*param* `min_sep` — Minimum hard penetration separation (default: radius * 0.6) @*param* `vertical_factor` — Vertical attenuation factor (default: 0.1) @*param* `horizontal_bias` — If true, applies horizontal anti-stacking bias (default: true) |
| `check_leash` | `function CoordinationSubsystem.check_leash(follower_self: table)   -> is_leashed: boolean   2. leader_pos: Vector\|nil   3. dist: number` | Checks if a follower has exceeded its leash distance from its leader @*param* `follower_self` — Follower mob instance @*return* `is_leashed` — True if within leash limit, false if leashed/separated @*return* `leader_pos` — Position of leader if valid @*return* `dist` — Distance to leader |
| `rally_followers` | `function CoordinationSubsystem.rally_followers(leader_self: table, target: ObjectRef)` | Rallies all pack followers to attack a shared target @*param* `leader_self` — Leader mob instance @*param* `target` — Target entity |
| `step_regroup` | `function CoordinationSubsystem.step_regroup(self: table, dtime: number, move_anim?: string, speed_mult?: number)   -> is_regrouping: boolean` | Handles movement for a follower returning to assemble with its pack leader @*param* `self` — Follower mob instance @*param* `dtime` — Step delta time @*param* `move_anim` — Movement animation (default: "walk") @*param* `speed_mult` — Speed multiplier (default: 1.25) @*return* `is_regrouping` — True if still actively regrouping, false if reached leader or leader lost |
| `trigger_cowardice_panic` | `function CoordinationSubsystem.trigger_cowardice_panic(death_pos: Vector, mob_name: string, radius?: number, panic_duration?: number, danger_dmg?: number)` | Triggers cowardice panic in nearby fellow mobs when a pack member dies @*param* `death_pos` — Position of the deceased mob @*param* `mob_name` — Name of the entity to match (e.g. "x_mobs:fallen_minion") @*param* `radius` — Search radius (default: 12.0) @*param* `panic_duration` — Duration in seconds for flee state (default: 4.0) @*param* `danger_dmg` — Perceived damage recorded in memory (default: 10) |

### `CustomStateDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `enter` | `fun(self: MobStateContext)?` | Called when state is entered |
| `exit` | `fun(self: MobStateContext)?` | Called when state is exited |
| `step` | `fun(self: MobStateContext, dtime: number):string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+7)` | State tick; return state name to transition |

### `DamageEffectDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `color` | `string?` | Hex color string override (e.g. "#8A0303") |
| `colors` | `string[]?` | Multi-shade hex color list override for texpool (e.g. {"#E0AAFF", "#C77DFF", "#9D4EDD"}) |
| `count` | `integer?` | Base particle droplet count (default: 8) |
| `enabled` | `boolean?` | Set to false to disable default core damage particles (default: true) |
| `scale` | `number?` | Particle size multiplier (default: 1.0) |
| `texture` | `string?` | Custom texture override (e.g. "[fill:3x3:#FF0000") |
| `type` | `(string\|"blood"\|"ichor"\|"none"\|"smoke"...(+2))?` | Particle effect preset style |

### `DamageSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `calculate_punch_damage` | `function DamageSubsystem.calculate_punch_damage(self: table, puncher?: ObjectRef, time_from_last_punch?: number, tool_capabilities?: table, _dir?: Vector, damage_override?: number)   -> dmg: number` | Calculates damage from tool capabilities and mob armor groups, and adds tool wear @*param* `self` — Mob entity instance @*param* `puncher` — Punching entity @*param* `time_from_last_punch` — Time since last punch @*param* `tool_capabilities` — Wielded tool capabilities @*param* `_dir` — Punch direction @*param* `damage_override` — Direct damage override @*return* `dmg` — Calculated damage integer |

### `DespawnConditionsDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `daylight` | `boolean?` | Despawn when exposed to daytime sunlight (default: false) |
| `max_time` | `number?` | Time of day window end (0.0 to 1.0) |
| `min_natural_light` | `integer?` | Natural sunlight threshold (default: 11) |
| `min_time` | `number?` | Time of day window start (0.0 to 1.0) |
| `require_natural_light` | `boolean?` | If true, time_range despawn only applies if exposed to natural sunlight |
| `time_range` | `{ min: number, max: number }?` | Custom time-of-day despawn window |

### `DetachmentSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `detach_attached_children` | `function DetachmentSubsystem.detach_attached_children(mob_obj: ObjectRef)` | Detaches and drops all attached child objects (arrows, passengers, accessories) from a mob when it dies @*param* `mob_obj` — The mob entity ObjectRef |

### `DoorsSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `check_and_open_forward_doors` | `function DoorsSubsystem.check_and_open_forward_doors(pos: Vector, dir?: Vector, abilities?: table, object?: ObjectRef)` | Checks and proactively opens any closed doors directly ahead in movement direction @*param* `pos` — Current entity position @*param* `dir` — Direction of movement @*param* `abilities` — Mob capabilities table @*param* `object` — Entity ObjectRef |
| `is_door_open` | `function DoorsSubsystem.is_door_open(pos: Vector, node?: table, def?: table)   -> is_open: boolean` | Checks if a door or trapdoor is currently already open @*param* `pos` — World position of door node @*param* `node` — Node table {name, param1, param2} @*param* `def` — Registered node definition @*return* `is_open` — True if door is already open |
| `is_openable_door` | `function DoorsSubsystem.is_openable_door(name: string, abilities?: table)   -> is_openable: boolean` | Checks if a node represents an unlocked, openable door @*param* `name` — Node technical name @*param* `abilities` — Mob capabilities table @*return* `is_openable` — True if node is an openable door and mob can open doors |
| `try_open_door` | `function DoorsSubsystem.try_open_door(pos: Vector, node?: table, def?: table, _user?: ObjectRef)   -> success: boolean` | Opens a door node if closed, ensuring already open doors are not toggled or touched @*param* `pos` — World position of door node @*param* `node` — Node table {name, param1, param2} @*param* `def` — Registered node definition @*param* `_user` — Entity attempting the interaction @*return* `success` — True if door is open or was successfully opened |
| `try_open_door_at_pos` | `function DoorsSubsystem.try_open_door_at_pos(pos: Vector, abilities?: table, object?: ObjectRef)   -> opened: boolean` | Checks and opens an openable door node at a specific position @*param* `pos` — World position @*param* `abilities` — Ability flags table @*param* `object` — User/mob object |

### `DropEntryDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `chance` | `number?` | Probability to drop between 0.0 and 1.0 (default: 1.0) |
| `max` | `integer?` | Maximum count to drop (default: 1) |
| `min` | `integer?` | Minimum count to drop (default: 1) |
| `name` | `string` | Technical item name (e.g. "everness:quartz_crystal") |

### `DropOptions`

| Field | Type | Description |
| :--- | :--- | :--- |
| `killer` | `ObjectRef?` | Killer object/player if applicable |
| `particle_color` | `string?` | Hex color for sparkle particles |
| `particle_texture` | `string?` | Optional custom base particle texture |
| `particles` | `boolean?` | Enable sparkle/burst particles (default: true) |
| `sound` | `string?` | Sound identifier to play on drop |
| `spread_max` | `number?` | Maximum horizontal spread velocity (default: 1.6) |
| `spread_min` | `number?` | Minimum horizontal spread velocity (default: 1.0) |
| `trails` | `boolean?` | Enable sparkling trail attached to flying items (default: true) |
| `up_vel_max` | `number?` | Maximum upward launch velocity (default: 5.8) |
| `up_vel_min` | `number?` | Minimum upward launch velocity (default: 4.6) |

### `EffectsSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `clear_damage` | `function EffectsSubsystem.clear_damage(obj: ObjectRef)` | Clears any active damage flash on an entity, restoring its clean base texture modifier @*param* `obj` — Entity object |
| `clear_regen` | `function EffectsSubsystem.clear_regen(obj: ObjectRef)` | Clears any active health regeneration flash on an entity, restoring its clean base texture modifier @*param* `obj` — Entity object |
| `indicate_damage` | `function EffectsSubsystem.indicate_damage(obj: ObjectRef)` | Flashes the entity red briefly upon taking damage for visual feedback. Prevents duplicate stacking, clears competing regen flashes, and handles rapid hits cleanly. @*param* `obj` — Entity object |
| `indicate_regen` | `function EffectsSubsystem.indicate_regen(obj: ObjectRef, color?: string, duration?: number)` | Flashes the entity white briefly upon health regeneration for visual feedback. Yields precedence to active damage flashes and suppresses while dying. @*param* `obj` — Entity object @*param* `color` — Optional texture modifier overlay (default: "^[colorize:#FFFFFF60") @*param* `duration` — Optional duration in seconds (default: 0.25) |
| `spawn_damage_particles` | `function EffectsSubsystem.spawn_damage_particles(obj: ObjectRef, puncher?: ObjectRef, dir?: Vector, damage?: number, def?: table)` | Spawns contextual, directional damage particles when an entity is damaged. Configurable globally via `x_mob_damage_particles` and `x_mob_damage_particle_multiplier`, or per-mob via `def.damage_effect`. Can be disabled by setting `damage_effect = false`, `damage_effect = "none"`, or `{ enabled = false }` / `{ type = "none" }`. @*param* `obj` — Entity object receiving damage @*param* `puncher` — Attacking entity or player @*param* `dir` — Strike/knockback direction vector @*param* `damage` — Damage points dealt @*param* `def` — Mob definition table |
| `strip_damage_mod` | `function EffectsSubsystem.strip_damage_mod(mod?: string)   -> clean_mod: string` | Strips transient damage flash colorize modifiers from a texture modifier string @*param* `mod` — Original texture modifier string @*return* `clean_mod` — Texture modifier without damage colorize |
| `strip_flash_mod` | `function EffectsSubsystem.strip_flash_mod(mod?: string)   -> clean_mod: string` | Strips all transient combat damage and regeneration flash colorize modifiers @*param* `mod` — Original texture modifier string @*return* `clean_mod` — Texture modifier without damage or regen colorize |
| `strip_regen_mod` | `function EffectsSubsystem.strip_regen_mod(mod?: string)   -> clean_mod: string` | Strips transient health regeneration flash colorize modifiers from a texture modifier string @*param* `mod` — Original texture modifier string @*return* `clean_mod` — Texture modifier without regen colorize |

### `EntityWrapperSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `combat_handler` | `unknown` |  |
| `culling` | `unknown` |  |
| `environment` | `unknown` |  |
| `handle_core_step` | `function EntityWrapperSubsystem.handle_core_step(self: table, dtime: number, def: table)   -> handled: boolean` | Universal step lifecycle handler. Manages death countdown, buoyancy, target validation, timers, action completions, and idle navigation. @*param* `self` — Mob entity instance @*param* `dtime` — Step delta time @*param* `def` — Entity definition table @*return* `handled` — True if step was fully handled (e.g. dying or action-locked) |
| `handle_punch` | `unknown` |  |
| `normalize_texture_variations` | `unknown` |  |
| `pipeline` | `unknown` |  |
| `properties` | `unknown` |  |
| `register_mob` | `function EntityWrapperSubsystem.register_mob(name: string, def: MobRegistrationDef)` | Registers a mob definition with standardized physical properties and lifecycle integration. @*param* `name` — Entity name (e.g. "x_mobs:spider") @*param* `def` — Entity definition table |
| `registered_mobs` | `table<string, MobRegistrationDef>` |  |
| `set_armor_groups` | `unknown` |  |
| `set_target` | `function EntityWrapperSubsystem.set_target(self: table, target: ObjectRef\|nil)   -> changed: boolean` | Sets the current target and fires on_mob_target event if target changed. @*param* `self` — Mob entity instance @*param* `target` — Target entity or player @*return* `changed` — True if target changed |
| `set_texture` | `unknown` |  |

### `EnvironmentSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `step` | `function EnvironmentSubsystem.step(self: table, dtime: number, def: table, combat_handler: table)   -> handled: boolean` | Throttled step processor evaluating environmental hazards @*param* `self` — Mob entity instance @*param* `dtime` — Step delta time @*param* `def` — Entity definition table @*param* `combat_handler` — Combat handler subsystem @*return* `handled` — True if mob died from environmental damage |

### `EventsSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `emit` | `function EventsSubsystem.emit(event_name: string, ...any)` | Emits an event to all registered listeners @*param* `...` — Arguments passed to listeners |
| `listen` | `function EventsSubsystem.listen(event_name: string, callback: fun(...any))   -> id: integer` | Registers an event listener @*param* `event_name` — Event identifier (e.g. "on_mob_death", "on_pack_spawn") @*param* `callback` — Function invoked when event is emitted @*return* `id` — Listener registration token |
| `listeners` | `table<string, fun(...any)[]>` |  |
| `unlisten` | `function EventsSubsystem.unlisten(event_name: string, id: integer)   -> success: boolean` | Unregisters an event listener by token @*param* `event_name` — Event identifier @*param* `id` — Listener registration token returned by listen() @*return* `success` — True if listener was found and removed |

### `FactionsSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `are_allies` | `function FactionsSubsystem.are_allies(a: any, b: any)   -> are_allies: boolean` | Checks whether two entities or players are allies @*param* `a` — First object, entity, or projectile @*param* `b` — Second object, entity, or projectile @*return* `are_allies` — True if both entities share allegiance |
| `are_enemies` | `function FactionsSubsystem.are_enemies(a: any, b: any)   -> are_enemies: boolean` | Checks whether two entities or players are enemies @*param* `a` — First object, entity, or projectile @*param* `b` — Second object, entity, or projectile @*return* `are_enemies` — True if enemies |
| `get_factions` | `function FactionsSubsystem.get_factions(obj: any)   -> factions: table<string, boolean>` | Returns the faction set for an entity or player @*param* `obj` — ObjectRef or mob entity @*return* `factions` — Set of active factions |
| `normalize_factions` | `function FactionsSubsystem.normalize_factions(input?: string\|string[])   -> set: table<string, boolean>   2. list: string[]` | Normalizes faction input into a fast O(1) set table and array list @*param* `input` — Faction string or array of faction strings @*return* `set` — Lookup set of factions @*return* `list` — Ordered list of faction strings |

### `FastPathfinder`

| Field | Type | Description |
| :--- | :--- | :--- |
| `find_path` | `function FastPathfinder.find_path(start_pos: Vector, target_pos: Vector, abilities: table, callback: fun(path: table\|nil), mob_height: integer\|nil)` | Queues an asynchronous pathfinding task @*param* `start_pos` — Starting world position @*param* `target_pos` — Target world position @*param* `abilities` — Mob movement capabilities @*param* `callback` — Callback invoked upon path completion @*param* `mob_height` — Mob height clearance in nodes |
| `find_path_sync` | `function FastPathfinder.find_path_sync(start_pos: Vector, target_pos: Vector, abilities: table, mob_height: integer\|nil)   -> table\|nil` | Synchronous path request (for fallback or immediate test verification) |
| `step` | `function FastPathfinder.step(_dtime: number)` | Globalstep processor executing search coroutines under the hard tick budget Uses strict sequential execution so concurrent mob searches never interleave or corrupt shared memory buffers @*param* `_dtime` — Server step delta time |

### `HealthBarSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `calculate_dimensions` | `function HealthBarSubsystem.calculate_dimensions(self: table, def?: table, cfg?: table)   -> visual_size: Vector2d   2. attach_pos: Vector` | Calculates proportional visual size and attachment position based on mob bounding box and nametag. @*param* `self` — Mob entity instance @*param* `def` — Entity definition table @*param* `cfg` — Health bar configuration @*return* `visual_size` — Sprite dimensions in world units @*return* `attach_pos` — Local attachment offset in engine units (tenths of a node) |
| `get_config` | `function HealthBarSubsystem.get_config(def?: table)   -> cfg: table` | Resolves effective health bar configuration for a mob. @*param* `def` — Entity definition table @*return* `cfg` — Merged configuration |
| `get_texture` | `function HealthBarSubsystem.get_texture(width: integer, height: integer, border: integer, fill_w: integer, bar_color: string, border_color: string, empty_color: string)   -> texture_modifier: string` | Generates or retrieves a memoized [combine: texture modifier string for the health bar. @*param* `width` — Total texture width in px @*param* `height` — Total texture height in px @*param* `border` — Border thickness in px @*param* `fill_w` — Width of the filled health bar in px @*param* `bar_color` — Fill color hex string (e.g. "#00FF00") @*param* `border_color` — Border color hex string (e.g. "#111111") @*param* `empty_color` — Background depleted track hex string (e.g. "#330000") @*return* `texture_modifier` — Compiled texture modifier string |
| `hide` | `function HealthBarSubsystem.hide(self: table)` | Hides the health bar entity by setting is_visible = false (soft hide). @*param* `self` — Mob entity instance |
| `on_hp_change` | `function HealthBarSubsystem.on_hp_change(self: table, _old_hp: number, new_hp: number, def?: table)` | Dispatches an HP change event to update the health bar. @*param* `self` — Mob entity instance @*param* `_old_hp` — Previous health value @*param* `new_hp` — Updated health value @*param* `def` — Entity definition table |
| `on_timeout` | `function HealthBarSubsystem.on_timeout(self: table, def?: table)` | Handles health bar auto-hiding when the countdown timer expires. @*param* `self` — Mob entity instance @*param* `def` — Entity definition table |
| `remove` | `function HealthBarSubsystem.remove(self: table)` | Removes and destroys the health bar child entity completely. @*param* `self` — Mob entity instance |
| `resolve_color` | `function HealthBarSubsystem.resolve_color(ratio: number, color_list: table[])   -> color: string` | Resolves the bar fill color according to current health ratio and color tiers. @*param* `ratio` — Current health ratio (0.0 to 1.0) @*param* `color_list` — List of {threshold: number, color: string} @*return* `color` — Hex color string |
| `show` | `function HealthBarSubsystem.show(self: table, cur_hp: number, max_hp: number, def?: table)   -> shown: boolean` | Shows or updates the overhead health bar on a mob entity, resetting the timeout window. @*param* `self` — Mob entity instance @*param* `cur_hp` — Current health value @*param* `max_hp` — Maximum health value @*param* `def` — Entity definition table @*return* `shown` — True if health bar is shown or updated |

### `HealthRegenDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `burst_duration` | `number?` | Maximum sprint duration in seconds for initial tactical disengage burst before halting to channel heal (default: `3.5`). *Ignored when `unlimited_flee = true`.* |
| `can_flee` | `boolean?` | Whether mob tactically flees when low on health (default: `true`, set `false` for stand-and-fight) |
| `channel_duration` | `number?` | Duration in seconds mob stands stationary channeling heal once safe distance is reached (default: `3.0`). *Ignored when `unlimited_flee = true`.* |
| `enabled` | `boolean?` | Whether health regeneration and tactical retreat are enabled (default: `true`) |
| `flee_ratio` | `number?` | HP ratio below which mob enters retreat (default: `0.25` / 25% max HP) |
| `flee_speed` | `number?` | Speed in m/s while fleeing (default: capped at `4.2` m/s for player catchability, or `def.flee_speed`) |
| `flee_threshold` | `number?` | Absolute HP threshold below which mob flees (default: derived from `flee_ratio` * `max_hp`) |
| `heal_amount` | `number?` | Flat HP restored when channeling completes uninterrupted (default: `return_threshold - flee_threshold`). *Ignored when `unlimited_flee = true`.* |
| `max_flee_distance` | `number?` | Maximum retreat distance from fight/threat before halting (default: `15.0`) |
| `overlay` | `boolean?` | Whether visual white texture overlay pulses on regeneration/channeling (default: `true`) |
| `overlay_color` | `string?` | Custom texture modifier overlay string (default: `"^[colorize:#FFFFFF60"`) |
| `passive` | `boolean?` | Whether regeneration occurs passively at all times while idle/walking (default: `false`) |
| `rate` | `number?` | HP regenerated per second for passive regeneration or `unlimited_flee = true` (default: `0.5`). *For tactical disengage fleeing, healing occurs via channel completion instead.* |
| `return_ratio` | `number?` | HP ratio to exit retreat and re-engage in combat (default: `0.60` / 60% max HP) |
| `return_threshold` | `number?` | Absolute HP threshold to exit retreat and return to fight (default: derived from `return_ratio` * `max_hp`) |
| `safe_distance` | `number?` | Distance in nodes from threat at which mob halts early to begin channeling heal (default: `10.0`). *Ignored when `unlimited_flee = true`.* |
| `unlimited_flee` | `boolean?` | If `true`, mob flees continuously without burst timeout, channel halt, or 1-time limit (e.g. cowardly minions). If `false` (default), uses Tactical Disengage & Vulnerable Channel. |

#### Tactical Fleeing & Health Regeneration Mechanics

##### 1. Tactical Disengage & Vulnerable Channel (Default, `unlimited_flee = false`)
Standard tactical retreat designed for balanced, engaging combat encounters without endless kiting loops:
1. **Disengage Burst**: When HP drops to `<= flee_threshold`, the mob sprints away for up to `burst_duration` (default 3.5s) or until reaching `safe_distance` (default 10.0m) from threat. Default flee speed is balanced (`<= 4.2` m/s) so players without sprint buffs can pursue and catch up.
2. **Stationary Channeling**: Upon reaching safe distance (or burst expiration), the mob stops in place, turns toward the threat, and channels for `channel_duration` (default 3.0s). During channeling, the mob emits visual white regeneration pulses every 0.6s.
3. **Channel Completion**: If left uninterrupted for the full channel duration, the mob instantly recovers `heal_amount` HP (up to `return_threshold`), sets its 1-time retreat lock (`_flee_used = true`), and re-engages in combat.
4. **Hit-Interrupt & Last Stand**: Striking the mob with a melee/ranged attack while fleeing or channeling immediately breaks the channel, sets `_flee_used = true`, and forces the mob to turn and fight to the death.
5. **1-Time Limit**: Mobs execute at most one tactical retreat per combat encounter. The 1-time limit resets only after the mob fully recovers to 100% max HP or its target is cleared.

##### 2. Unlimited Flee (`unlimited_flee = true`)
For cowardly mobs (such as [Fallen Minion](file:///Users/juraj/Library/Application%20Support/minetest/mods/x_mobs/mobs/fallen_minion.lua)) designed to persistently run away:
- Continues fleeing away from threat up to `max_flee_distance` without halting to channel.
- Regenerates incrementally every second at `rate` HP/s while fleeing until reaching `return_threshold`.
- Once HP reaches `return_threshold`, it exits retreat and returns to combat.
- Can flee repeatedly across encounters without a 1-time lock.
- **Ignored / Exclusive Properties**: `burst_duration`, `channel_duration`, `safe_distance`, and `heal_amount` are completely bypassed when `unlimited_flee = true`.

```lua
-- Example 1: Tactical Disengage Elite (Disengage & Channel)
health_regen = {
    flee_threshold = 20,
    return_threshold = 45,
    burst_duration = 3.5,
    channel_duration = 3.0,
    safe_distance = 12.0,
    heal_amount = 25,
    flee_speed = 4.2,
}

-- Example 2: Cowardly Minion (Unlimited Flee)
health_regen = {
    unlimited_flee = true,
    flee_threshold = 5,
    return_threshold = 12,
    rate = 0.5,
    flee_speed = 4.8,
}
```

### `KnockbackSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `dampen_water_knockback` | `function KnockbackSubsystem.dampen_water_knockback(self: table)` | Dampens punch knockback when an entity is struck inside water @*param* `self` — Mob entity instance |
| `get_multiplier` | `function KnockbackSubsystem.get_multiplier(obj: table\|ObjectRef)   -> multiplier: number` | Returns the effective knockback multiplier for an entity or ObjectRef @*param* `obj` — Target object or mob entity @*return* `multiplier` — (1.0 for players, mob-defined knockback_mult, or 1.0 default) |

### `LocomotionSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `apply_liquid_buoyancy` | `function LocomotionSubsystem.apply_liquid_buoyancy(self: table, dtime: number)   -> in_liquid: boolean   2. is_submerged: boolean   3. target_vy: number` | Applies active water buoyancy and partial submersion floating physics for swimming mobs @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*return* `in_liquid` — True if mob is currently inside a liquid node @*return* `is_submerged` — True if mob is submerged below target swimming waterline @*return* `target_vy` — Vertical velocity to maintain or reach swimming depth |
| `calculate_liquid_vertical_velocity` | `function LocomotionSubsystem.calculate_liquid_vertical_velocity(self: table, current_y: number, target_y: number, is_subm: boolean, target_vy: number)   -> y_vel: number` | Calculates vertical velocity and applies buoyancy acceleration when navigating liquids @*param* `self` — Mob entity instance @*param* `current_y` — Current mob vertical position @*param* `target_y` — Desired waypoint/target vertical position @*param* `is_subm` — True if submerged @*param* `target_vy` — Target floating velocity from check_in_liquid @*return* `y_vel` — Vertical velocity to assign |
| `calculate_separation_force` | `function LocomotionSubsystem.calculate_separation_force(self: table, current_pos: Vector, dtime: number, on_surface: boolean, normal: Vector)   -> sep_force: Vector` | Calculates a soft repulsive separation vector away from other nearby mobs to prevent clipping and merging into each other. Respects surface orientation (tangent projection on walls/ceilings). Throttled to 100ms per entity to ensure zero performance overhead on multiplayer servers. @*param* `self` — Mob entity state @*param* `current_pos` — Mob position @*param* `dtime` — Server step delta time @*param* `on_surface` — True if mob is on wall or ceiling @*param* `normal` — Surface normal vector (or {x=0, y=1, z=0} for floor) @*return* `sep_force` — Tangent/horizontal separation velocity offset |
| `get_pursuit_state` | `function LocomotionSubsystem.get_pursuit_state(self: table)   -> is_pursuing: boolean` | Determines if mob is in active pursuit of a living target @*param* `self` — Entity instance |
| `halt_horizontal_velocity` | `function LocomotionSubsystem.halt_horizontal_velocity(self: table)` | Halts horizontal velocity while preserving vertical motion/gravity and liquid buoyancy @*param* `self` — Mob entity instance |
| `handle_mob_fleeing` | `function LocomotionSubsystem.handle_mob_fleeing(self: table, dtime: number, current_pos: Vector, on_wall_or_ceiling: boolean)   -> status: table` | Updates tactical fleeing behavior away from danger/threat sources @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*param* `current_pos` — Current mob world position @*param* `on_wall_or_ceiling` — Whether mob is adhering to wall/ceiling @*return* `status` — Locomotion status {moving = boolean, speed = number, has_los = boolean} |
| `handle_mob_movement` | `function LocomotionSubsystem.handle_mob_movement(self: table, dtime: number, current_pos: Vector, next_waypoint: Vector)` | Handles physical movement and steering toward the next path waypoint @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*param* `current_pos` — Current mob world position @*param* `next_waypoint` — Target node world position |
| `handle_mob_wandering` | `function LocomotionSubsystem.handle_mob_wandering(self: table, dtime: number, current_pos: Vector, on_wall_or_ceiling: boolean)   -> status: table` | Updates autonomous local wandering and idling when mob is not pursuing a target @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*param* `current_pos` — Current mob world position @*param* `on_wall_or_ceiling` — Whether mob is adhering to wall/ceiling @*return* `status` — Locomotion status {moving = boolean, speed = number, has_los = boolean} |
| `has_wall_collision` | `function LocomotionSubsystem.has_wall_collision(self: table, current_pos: Vector, dtime: number)   -> is_colliding: boolean   2. wall_normal: Vector\|nil   3. node_pos: Vector\|nil` | Detects if entity has collided with a wall/solid obstacle or is physically stagnant against one @*param* `self` — Mob entity instance @*param* `current_pos` — Current world position @*param* `dtime` — Delta time @*return* `is_colliding` — Whether the mob is colliding with a wall @*return* `wall_normal` — Estimated normal pointing away from the wall @*return* `node_pos` — Position of collided node if known |
| `retreat_from` | `function LocomotionSubsystem.retreat_from(self: table, target_pos: Vector, speed?: number)   -> success: boolean` | Executes a safe kiting retreat away from a target position with cliff/obstacle guard @*param* `self` — Mob instance @*param* `target_pos` — Threat / target world position @*param* `speed` — Movement speed (default: self.pursuit_speed or self.walk_speed or 3.0) @*return* `success` — True if a safe retreat direction was found and applied |
| `safe_get_yaw` | `function LocomotionSubsystem.safe_get_yaw(obj: ObjectRef\|nil)   -> yaw: number` | Safely gets object yaw in radians |
| `safe_set_acceleration` | `function LocomotionSubsystem.safe_set_acceleration(obj: ObjectRef\|nil, acc: Vector)` | Safely sets object acceleration |
| `safe_set_rotation` | `function LocomotionSubsystem.safe_set_rotation(obj: ObjectRef\|nil, rot: Vector)` | Sets object rotation (Euler radians) |
| `safe_set_yaw` | `function LocomotionSubsystem.safe_set_yaw(obj: ObjectRef\|nil, yaw: number)` | Safely sets object yaw in radians |
| `set_horizontal_velocity` | `function LocomotionSubsystem.set_horizontal_velocity(self: table, speed: number, yaw: number)` | Sets horizontal velocity of a mob entity along a given yaw while preserving vertical motion/gravity @*param* `self` — Mob entity instance @*param* `speed` — Horizontal movement speed @*param* `yaw` — Orientation angle in radians |

### `LootSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `drop_item` | `function LootSubsystem.drop_item(origin: Vector, itemstack: string\|ItemStack, angle?: number, options?: DropOptions)   -> item_obj: ObjectRef\|nil` | Spawns a single item with a physical parabolic launch arc @*param* `origin` — World coordinate of spawn origin @*param* `itemstack` — Item or ItemStack to drop @*param* `angle` — Launch azimuth in radians @*param* `options` — Physics and effect overrides @*return* `item_obj` — Spawned item entity or nil |
| `drop_items` | `function LootSubsystem.drop_items(origin: Vector, drops: (string\|DropEntryDef)[], options?: DropOptions)   -> spawned_objects: ObjectRef[]` | Evaluates a declarative drop table and launches all dropped items in a radial fountain @*param* `origin` — World coordinate of spawn origin @*param* `drops` — List of drop table entries @*param* `options` — Physics, particle, and sound overrides @*return* `spawned_objects` — List of successfully spawned item ObjectRefs |
| `spawn_mob_drops` | `function LootSubsystem.spawn_mob_drops(self: table, killer?: ObjectRef, drops: (string\|DropEntryDef)[], options?: DropOptions)   -> spawned_objects: ObjectRef[]` | Convenience method to drop items from a dying mob instance @*param* `self` — Mob entity instance @*param* `killer` — Killer entity or player @*param* `drops` — Mob drop definitions @*param* `options` — Runtime drop overrides @*return* `spawned_objects` — List of spawned item ObjectRefs |

### `MeleeConfigDef`

Declarative close-quarters melee combat configuration.
When configured in `x_mob_core.register_mob`, the core pipeline automatically manages
reach distance validation, raycast line-of-sight checks, horizontal velocity halting,
attack animations, directional audio cues, cooldown intervals, and timed strike impacts.

### How It Works:
1. **Reach & Line of Sight**: During each tick, checks if target distance <= `range` and target is visible.
2. **Halting & Facing**: Upon reach entry, halts horizontal movement and turns the mob to face the target.
3. **Strike Execution**: Starts `duration` pose, triggers `animation`, plays `sound`, and queues delayed hit.
4. **Tolerance Validation**: At `delay` time, confirms target remains within `range + reach_tolerance`.
5. **Impact Feedback**: Applies fleshy punch damage and invokes optional `on_strike` callback.

### Usage Example:
```lua
melee = {
    range = 2.4,
    damage = 6,
    cooldown = 1.4,
    duration = 0.7,
    delay = 0.35,
    animation = "attack",
    sound = "attack",
    on_strike = function(self, target, dir)
        -- Custom impact VFX or effects
    end,
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `anim_speed` | `number?` | Animation playback speed multiplier (default: 1.2) |
| `animation` | `string?` | Animation track name played when attacking (default: "attack") |
| `cooldown` | `number?` | Attack cooldown between strikes in seconds (default: def.attack_interval or 1.2) |
| `damage` | `number?` | Base melee strike damage dealt to targets (default: def.damage or 4) |
| `delay` | `number?` | Delay before punch damage is applied in seconds (default: 0.25) |
| `duration` | `number?` | Action timer duration holding attack pose in seconds (default: 0.5) |
| `max_height_diff` | `number?` | Vertical reach tolerance in nodes (default: 2.0) |
| `on_strike` | `fun(self: table, target: ObjectRef, dir: Vector)?` | Callback executed on punch impact |
| `perform_attack` | `fun(self: table, target: ObjectRef, dir: Vector)?` | Custom melee attack callback override |
| `range` | `number?` | Melee attack reach in nodes (default: def.attack_range or 2.0) |
| `reach_tolerance` | `number?` | Additional reach buffer for moving targets at hit time (default: 0.6) |
| `sound` | `string?` | Sound played when attacking (default: "attack") |

### `MinHeap`

| Field | Type | Description |
| :--- | :--- | :--- |
| `clear` | `(method) MinHeap:clear()` | Resets the heap for reuse in O(1) without reallocating arrays |
| `get_size` | `(method) MinHeap:get_size()   -> integer` | Returns the current number of elements in the heap |
| `is_empty` | `(method) MinHeap:is_empty()   -> boolean` | Returns true if the heap contains no elements in O(1) |
| `new` | `function MinHeap.new(initial_capacity: integer\|nil)   -> MinHeap` | Creates a new reusable binary min-heap @*param* `initial_capacity` — Optional hint for pre-allocating heap slots |
| `peek` | `(method) MinHeap:peek()   -> val: integer\|nil   2. priority: number\|nil` | Peeks at the lowest priority element without removing it in O(1) |
| `pop` | `(method) MinHeap:pop()   -> val: integer\|nil   2. priority: number\|nil` | Removes and returns the minimum priority element in O(log N) Single-hole trickle down avoids intermediate swap assignments @*return* `val` — The popped value, or nil if heap is empty @*return* `priority` — The popped priority, or nil if heap is empty |
| `priorities` | `number[]` | Flat array of numeric priorities (e.g. f_score) |
| `push` | `(method) MinHeap:push(val: integer, priority: number)` | Inserts a value with a numeric priority into the heap in O(log N) Single-hole bubble up avoids intermediate swap assignments @*param* `val` — Flat node index or identifier @*param* `priority` — Priority key (lower value has higher priority) |
| `size` | `integer` | Current number of elements in the heap |
| `values` | `number[]` | Flat array of stored integer values / IDs |

### `MobAISubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `register_pathfinding_mob` | `function MobAISubsystem.register_pathfinding_mob(name: string, def: MobRegistrationDef)` | Entity Registration Helper Wraps standard mob definition with optimized pathfinding motor controller @*param* `name` — Entity technical name (e.g. "x_mobs:smart_zombie") @*param* `def` — Entity definition table |
| `scan_for_player` | `function MobAISubsystem.scan_for_player(self: table, scan_radius?: number, eye_height?: number)   -> nearest_player: ObjectRef\|nil   2. nearest_dist: number\|nil` | Scans for the nearest valid living player within range and direct line of sight @*param* `self` — Mob instance @*param* `scan_radius` — Max search radius (default: self.aggro_radius or 16.0) @*param* `eye_height` — Mob eye height offset (default: self.eye_offset or 1.5) |
| `step_move_or_idle` | `function MobAISubsystem.step_move_or_idle(self: table, dtime: number, move_anim?: string, anim_speed?: number, idle_anim?: string)   -> nav: table\|nil` | Updates navigation movement and dispatches walk/run or idle animation @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `move_anim` — Movement animation (default: "walk") @*param* `anim_speed` — Animation speed (default: 1.0) @*param* `idle_anim` — Idle animation (default: "idle") @*return* `nav` — Navigation state |
| `step_wander_or_idle` | `function MobAISubsystem.step_wander_or_idle(self: table, dtime: number, walk_anim?: string, idle_anim?: string)   -> table\|nil` | Executes wander navigation or idle holding when no active target is present @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `walk_anim` — Custom walk animation name (default: "walk") @*param* `idle_anim` — Custom idle animation name (default: "idle") |
| `update_navigation` | `function MobAISubsystem.update_navigation(self: table, dtime: number)   -> status: table` | Updates entity navigation, scanning, line-of-sight, and path execution @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*return* `status` — Locomotion status {moving = boolean, speed = number, has_los = boolean} |

### `MobAnimationDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `loop` | `boolean?` | Whether to loop animation by default |
| `speed` | `number?` | Playback speed multiplier (default: 1.0) |
| `track` | `string` | Named glTF animation track |

### `MobBoneDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `pivot` | `(Vector\|{ x: number, y: number, z: number })?` | Pivot offset for bone attachments and inverse kinematics |
| `position` | `(Vector\|{ x: number, y: number, z: number })?` | Bone position offset |
| `rotation` | `(Vector\|{ x: number, y: number, z: number })?` | Default bone orientation rotation |

### `MobHealthBarColorBand`

| Field | Type | Description |
| :--- | :--- | :--- |
| `color` | `string` | Hex color string (e.g. "#00FF00") |
| `threshold` | `number` | Health ratio threshold (0.0 to 1.0) |

### `MobHealthBarConfig`

| Field | Type | Description |
| :--- | :--- | :--- |
| `auto_remove` | `boolean?` | Whether to remove child entity on timeout (default: true) |
| `auto_scale` | `boolean?` | Whether to proportionally scale visual_size to mob bounding box (default: true) |
| `border` | `integer?` | Border thickness in pixels (default: 1) |
| `border_color` | `string?` | Hex color for outer border (default: "#111111") |
| `colors` | `MobHealthBarColorBand[]?` | List of color thresholds evaluated from highest to lowest |
| `empty_color` | `string?` | Hex color for depleted health background track (default: "#330000") |
| `enabled` | `boolean?` | Whether health bar is enabled for this mob (default: true) |
| `glow` | `integer?` | Light emission in dark environments 0..14 (default: 5) |
| `height` | `integer?` | Texture height in pixels (default: 8) |
| `offset_y` | `number?` | Direct height offset override in nodes |
| `spacing` | `number?` | Spacing in nodes above mob collisionbox top (default: 0.35) |
| `timeout` | `number?` | Duration in seconds before health bar auto-hides (default: 4.0) |
| `visual_size` | `Vector2d?` | Explicit sprite visual size override in world coordinates |
| `width` | `integer?` | Texture width in pixels (default: 64) |

### `MobImmunitiesDef`

| Field | Type | Description |
| `damage_per_second` | `boolean?` | Immune to node damage_per_second |
| `drown` | `boolean?` | Immune to water drowning |
| `environment` | `boolean?` | Immune to all ambient environmental hazard node DPS |
| `fire` | `boolean?` | Immune to fire and igniter damage |
| `lava` | `boolean?` | Immune to lava damage |
| `suffocation` | `boolean?` | Immune to solid block asphyxiation |

### `MobInitialPropertiesDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `automatic_rotate` | `number?` | Continuous Y-axis rotation speed in radians/sec |
| `backface_culling` | `boolean?` | Whether backfaces of the 3D model are culled (default: true) |
| `collide_with_objects` | `boolean?` | Whether entity collides with other entities and players (default: true) |
| `collisionbox` | `number[]?` | 6-element bounding collision box: {minx, miny, minz, maxx, maxy, maxz} |
| `damage_texture_modifier` | `string?` | Texture modifier applied when entity takes damage |
| `eye_height` | `number?` | Engine eye elevation in nodes |
| `glow` | `integer?` | Light emission level in dark environments 0..14 (default: 0) |
| `hp_max` | `number?` | Maximum health points (synced to ObjectRef properties and engine HP) |
| `infotext` | `string?` | Tooltip text displayed when player points at the entity |
| `makes_footstep_sound` | `boolean?` | Whether movement plays footstep audio (default: true unless floating) |
| `mesh` | `string?` | 3D model mesh filename (.glb, .gltf, or .b3d) |
| `nametag` | `string?` | Overhead nametag text |
| `nametag_bgcolor` | `(string\|table)?` | Nametag background color |
| `nametag_color` | `(string\|table)?` | Nametag text color |
| `physical` | `boolean?` | Whether entity is subject to physical collisions (default: true) |
| `pointable` | `boolean?` | Whether entity can be pointed at or punched (default: true) |
| `selectionbox` | `(table\|number[])?` | 6-element selection box: {minx, miny, minz, maxx, maxy, maxz} |
| `shaded` | `boolean?` | Whether mesh is affected by world lighting (default: true) |
| `show_on_minimap` | `boolean?` | Whether entity appears on player minimap |
| `static_save` | `boolean?` | Whether entity persists in block static data across server restarts (default: true) |
| `stepheight` | `number?` | Maximum step-up height in nodes (default: 1.1) |
| `textures` | `string[]?` | List of texture filenames or texture modifier strings |
| `use_texture_alpha` | `(boolean\|string)?` | Texture alpha transparency mode (true, false, "clip", "blend", "opaque") |
| `visual` | `("cube"\|"mesh"\|"sprite")?` | Visual rendering mode (default: "mesh" if mesh is specified) |
| `visual_size` | `(Vector\|Vector2d\|{ x: number, y: number, z: number })?` | Visual model scale factors |
| `zoom_fov` | `number?` | Camera zoom field of view in degrees |

### `MobMemoryDangerRecord`

| Field | Type | Description |
| :--- | :--- | :--- |
| `active` | `boolean` | Whether danger slot is populated |
| `expire` | `number` | Expiration timestamp |
| `threat` | `number` | Threat intensity score |
| `x` | `number` | Danger position X coordinate |
| `y` | `number` | Danger position Y coordinate |
| `z` | `number` | Danger position Z coordinate |

### `MobMemoryState`

| Field | Type | Description |
| :--- | :--- | :--- |
| `blocked_spots` | `table[]` | Obstruction memory for deadlock evasion |
| `dangers` | `MobMemoryDangerRecord[]` | Pre-allocated circular buffer of active pain/danger positions |
| `fight` | `table` | Combat location memory for return-to-fight logic |
| `flee_state` | `boolean` | Whether entity is currently in low-HP tactical retreat |
| `regen_timer` | `number` | Elapsed time during low-HP passive health regeneration |
| `target` | `MobMemoryTargetRecord` | Single predictive target pursuit record (8-second LKP) |
| `trail` | `table[]` | Pre-allocated circular buffer of recent positions for anti-oscillation |

### `MobMemorySubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `broadcast_alert` | `function MobMemorySubsystem.broadcast_alert(self: table, alert_pos: Vector, threat?: number, radius?: number, max_allies?: number)   -> alerted_count: integer` | Broadcasts a swarm alert to nearby allies of the same species. Injects danger threat records and `"swarm_alert"` coordinate memory into idle allies, prompting them to navigate to and investigate the disturbance location even without direct line of sight. Invoked automatically alongside `coordination.broadcast_threat` when `def.swarm_alert` is configured. Configurable via self.swarm_alert = {enabled = true, radius = 10.0, max_allies = 3} @*param* `self` — Entity instance sending the alert @*param* `alert_pos` — Position of the threat @*param* `threat` — Threat magnitude (default: 5.0) @*param* `radius` — Alert radius in nodes (default: 10.0) @*param* `max_allies` — Maximum allies to alert (default: 3) @*return* `alerted_count` — Number of allies alerted |
| `clear_danger_memory` | `function MobMemorySubsystem.clear_danger_memory(self: table)` | Clears all active danger memories (used on combat re-engagement or panic exit) @*param* `self` — Entity instance |
| `clear_fight_pos` | `function MobMemorySubsystem.clear_fight_pos(self: table)` | Clears fight memory explicitly @*param* `self` — Entity instance |
| `clear_target_memory` | `function MobMemorySubsystem.clear_target_memory(self: table)` | Clears target memory explicitly @*param* `self` — Entity instance |
| `clear_unreachable_target` | `function MobMemorySubsystem.clear_unreachable_target(self: table, target_obj: ObjectRef)` | Clears unreachable status for a target (e.g. when punched by that target) @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity |
| `evaluate_heading_bias` | `function MobMemorySubsystem.evaluate_heading_bias(self: table, candidate_dir: Vector, current_pos: Vector, current_time?: number)   -> score: number` | Evaluates a candidate movement direction against danger, novelty, and blocked memory Returns a scalar fitness score (higher is better) Utilizes a zero-allocation heading evaluation cache to avoid duplicate vector and sqrt computations @*param* `self` — Entity instance @*param* `candidate_dir` — Candidate heading direction (normalized) @*param* `current_pos` — Current mob position @*param* `current_time` — Current timestamp @*return* `score` — Fitness score |
| `get_danger_repulsion_vector` | `function MobMemorySubsystem.get_danger_repulsion_vector(self: table, current_pos: Vector, current_time?: number)   -> repulsion: Vector` | Calculates a spatial repulsion vector away from all active danger spots Uses inverse-square distance weighting @*param* `self` — Entity instance @*param* `current_pos` — Current mob position @*param* `current_time` — Current timestamp @*return* `repulsion` — Normalized 3D repulsive vector or {x=0, y=0, z=0} |
| `get_exploration_bias_vector` | `function MobMemorySubsystem.get_exploration_bias_vector(self: table, current_pos: Vector)   -> novelty: Vector` | Calculates an exploration novelty vector pointing away from recently visited positions Prevents ping-pong oscillations in corridors and dead ends @*param* `self` — Entity instance @*param* `current_pos` — Current mob position @*return* `novelty` — Normalized 3D exploration vector or {x=0, y=0, z=0} |
| `get_fight_pos` | `function MobMemorySubsystem.get_fight_pos(self: table, current_time?: number)   -> fight_pos: Vector\|nil` | Retrieves active fight location if not expired @*param* `self` — Entity instance @*param* `current_time` — Current timestamp @*return* `fight_pos` — Coordinates of the fight or nil |
| `get_lkp_target` | `function MobMemorySubsystem.get_lkp_target(self: table, max_age?: number, current_time?: number)   -> lkp: Vector\|nil` | Retrieves active Last Known Position if within the 8.0s pursuit window @*param* `self` — Entity instance @*param* `max_age` — Maximum age in seconds (default: 8.0) @*param* `current_time` — Current timestamp @*return* `lkp` — Last known position or nil if expired |
| `init_memory` | `function MobMemorySubsystem.init_memory(self: table)   -> table` | Initializes a zero-allocation working memory buffer on an entity instance @*param* `self` — Entity instance |
| `is_target_unreachable` | `function MobMemorySubsystem.is_target_unreachable(self: table, target_obj: ObjectRef, current_time?: number)   -> is_unreachable: boolean` | Checks if a target is currently marked as unreachable @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity @*param* `current_time` — Current timestamp @*return* `is_unreachable` — True if target is unreachable and on cooldown |
| `record_blocked_spot` | `function MobMemorySubsystem.record_blocked_spot(self: table, blocked_pos: Vector, duration?: number, current_time?: number)` | Records a blocked position or cliff deadlock @*param* `self` — Entity instance @*param* `blocked_pos` — Position that could not be traversed @*param* `duration` — Duration in seconds (default: 8.0) @*param* `current_time` — Current timestamp |
| `record_danger` | `function MobMemorySubsystem.record_danger(self: table, danger_pos: Vector, threat_level: number, duration?: number, current_time?: number)` | Records a danger source (damage taken, enemy position, hazard) @*param* `self` — Entity instance @*param* `danger_pos` — World coordinates of the threat @*param* `threat_level` — Magnitude of the threat (e.g. damage amount) @*param* `duration` — Duration in seconds before expiration (default: 12.0) @*param* `current_time` — Current timestamp |
| `record_fight_pos` | `function MobMemorySubsystem.record_fight_pos(self: table, fight_pos: Vector, duration?: number, current_time?: number)` | Records a combat / fight location @*param* `self` — Entity instance @*param* `fight_pos` — World coordinates of the fight @*param* `duration` — Duration in seconds before expiration (default: 45.0) @*param* `current_time` — Current timestamp |
| `record_target_sighting` | `function MobMemorySubsystem.record_target_sighting(self: table, target_obj: ObjectRef, target_pos: Vector, current_time?: number)` | Records or updates target sighting and Last Known Position @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity @*param* `target_pos` — Target position @*param* `current_time` — Optional current time or timestamp |
| `record_trail_step` | `function MobMemorySubsystem.record_trail_step(self: table, current_pos: Vector, dtime: number, current_time?: number)` | Records a visited world position into the circular trail buffer Throttled to 1.0s intervals to minimize samples @*param* `self` — Entity instance @*param* `current_pos` — Current mob position @*param* `dtime` — Step delta time @*param* `current_time` — Current timestamp |
| `record_unreachable_target` | `function MobMemorySubsystem.record_unreachable_target(self: table, target_obj: ObjectRef, duration?: number, current_time?: number)` | Records a target as temporarily unreachable (e.g. across impassable water or chasm) @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity @*param* `duration` — Duration in seconds before re-evaluating (default: 12.0) @*param* `current_time` — Current timestamp |
| `update_health_regen` | `function MobMemorySubsystem.update_health_regen(self: table, dtime: number, flee_ratio?: number, return_ratio?: number, regen_rate?: number)   -> is_fleeing: boolean` | Updates low-HP tactical fleeing and passive health regeneration When HP recovers to return threshold, exits fleeing state @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*param* `flee_ratio` — HP ratio to enter fleeing (default: 0.25) @*param* `return_ratio` — HP ratio to exit fleeing (default: 0.60) @*param* `regen_rate` — HP regenerated per second while fleeing (default: 0.5) @*return* `is_fleeing` — Whether the mob is currently in fleeing state |

### `MobMemoryTargetRecord`

| Field | Type | Description |
| :--- | :--- | :--- |
| `has_record` | `boolean` | Whether target memory slot is populated |
| `last_seen` | `number` | Timestamp of last target sighting |
| `lkp` | `Vector` | Last known 3D position vector |
| `name` | `string` | Entity name of remembered target |

### `MobPackDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `auto_succession` | `boolean?` | Whether surviving followers promote new leader on death (default: false) |
| `follower_type` | `(string\|string[])?` | Expected entity name or list of entity names of the followers |
| `leader_type` | `string?` | Expected entity name of the leader |
| `leash_distance` | `number?` | Distance before followers regroup (default: 18.0) |
| `max_followers` | `integer?` | Max followers for a leader (default: 3) |
| `on_leader_lost` | `("fight"\|"flee"\|fun(self: table, leader?: table))?` | Callback or behavior when pack leader dies |
| `pack_id` | `string?` | Optional existing pack UUID |
| `regroup_distance` | `number?` | Target distance when regrouping to leader (default: 4.0) |
| `role` | `("leader"\|"member")?` | Role within the pack |
| `spawn_on_init` | `boolean?` | Whether leader auto-spawns initial followers on activate |
| `swarm_alert` | `(boolean\|SwarmAlertDef)?` | Declarative pack & faction rally configuration on damage and death |

### `MobRegistrationDef`

Complete mob entity registration specification, physical properties,
combat tuning, AI navigation, and lifecycle callback configuration.

| Field | Type | Description |
| :--- | :--- | :--- |
| `abilities` | `table?` | Optional explicit abilities configuration table overrides |
| `aggro_radius` | `number?` | Player and target detection range in nodes (default: 16.0) |
| `air_grace_period` | `number?` | Seconds before beached aquatic mob suffocates on land (default: 5.0) |
| `amphibious` | `boolean?` | Whether mob is amphibious (immune to both drowning and beach suffocation) |
| `animations` | `table<string, string\|MobAnimationDef>?` | Declarative glTF skeletal animations map |
| `aquatic` | `boolean?` | Whether entity is strictly aquatic (swims in water, suffocates on land) |
| `armor_groups` | `table<string, number>?` | Luanti armor groups (e.g. {fleshy = 80, cracky = 70}) |
| `attack_interval` | `number?` | Cooldown between attacks in seconds (default: 1.2) |
| `attack_range` | `number?` | Melee attack reach in nodes (default: 2.0) |
| `auto_scan` | `boolean?` | Whether mob automatically scans for nearby player targets (default: true) |
| `automatic_rotate` | `number?` | Continuous Y-axis rotation speed in radians/sec |
| `backface_culling` | `boolean?` | Whether backfaces of the 3D model are culled (default: true) |
| `block_suffocation_dps` | `number?` | Damage per second when head is buried inside solid block (default: 2) |
| `bones` | `table<string, MobBoneDef>?` | Bone attachment pivots and structural metadata map |
| `breath_max` | `number?` | Breath holding duration in seconds before drowning begins (default: 15.0) |
| `can_breathe` | `boolean?` | Whether entity breathes air (false for aquatic mobs) |
| `can_breathe_water` | `boolean?` | Whether terrestrial mob can breathe underwater without drowning |
| `can_climb` | `boolean?` | Whether entity climbs ladders, vines, and walls (default: false) |
| `can_crawl` | `boolean?` | Whether entity navigates 1-block crawlways and ceilings (default: false) |
| `can_flinch` | `(boolean\|fun(self: table):boolean)?` | Whether mob flinches on punch (default: true) |
| `can_fly_in_water` | `boolean?` | Whether aquatic mob flies/glides in water |
| `can_open_doors` | `boolean?` | Whether entity opens wooden doors in its path (default: false) |
| `can_swim` | `boolean?` | Whether entity navigates liquid bodies (default: true) |
| `can_wander` | `boolean?` | Whether entity wanders when idle (default: true) |
| `collide_with_objects` | `boolean?` | Whether entity collides with other entities and players (default: true) |
| `collisionbox` | `number[]?` | 6-element bounding collision box: {minx, miny, minz, maxx, maxy, maxz} |
| `combat_hover_offset` | `number?` | Desired hovering elevation above ground during combat in nodes (default: 0.35) |
| `combat_standoff` | `number?` | Desired horizontal standoff distance in front of target in combat (default: 1.4) |
| `cooldowns` | `table<string, number>?` | Initial named cooldown timers in seconds (decremented per tick) |
| `custom_states` | `table<string, CustomStateDef>?` | Custom state machine states map |
| `custom_step` | `(fun(self: table, dtime: number, moveresult?: table, def?: table):boolean\|nil)?` | Pre-combat custom ability hook (return true to intercept) |
| `damage` | `number?` | Base melee strike damage dealt to targets (default: 4) |
| `damage_effect` | `(boolean\|string\|DamageEffectDef)?` | Directional hit particle feedback (false or "none" disables) |
| `damage_texture_modifier` | `string?` | Engine texture modifier applied when entity takes damage |
| `death_duration` | `number?` | Duration before entity removal on death in seconds (default: 1.5) |
| `despawn` | `boolean?` | Enables or disables distance despawning (default: true) |
| `despawn_conditions` | `DespawnConditionsDef?` | Granular despawn triggers (daylight, time-of-day ranges) |
| `despawn_in_daylight` | `boolean?` | Despawns mob in daytime sunlight without drops (default: false) |
| `despawn_natural_light` | `integer?` | Minimum natural sunlight level to trigger daylight despawn (default: 11) |
| `despawn_timer` | `number?` | Sustained duration in seconds far from players before despawning (default: 45.0) |
| `drop_options` | `DropOptions?` | Physics, launch arc, particle trail, and sound overrides for mob drops |
| `drops` | `(string\|DropEntryDef)[]?` | Declarative loot drop table spawned on defeat |
| `drowning_dps` | `number?` | Damage per second when drowning underwater (default: 2) |
| `eye_height` | `number?` | Engine eye elevation in nodes |
| `eye_offset` | `number?` | Eye level offset in nodes (default: collisionbox top * 0.85) |
| `factions` | `(string\|string[])?` | Faction tag or list of faction tags (default: "monsters") |
| `flee_speed` | `number?` | Tactical fleeing speed when low on health (default: walk_speed * 1.6) |
| `flight_elevation` | `number?` | Desired flight cruising elevation above ground or anchor in nodes (default: hover_offset or 1.85) |
| `friendly_fire` | `boolean?` | Whether allies/same-faction can damage this mob (default: false) |
| `get_staticdata` | `(fun(self: table):string\|table)?` | Callback returning serialized state for persistence |
| `glow` | `integer?` | Light emission level in dark environments 0..14 (default: 0) |
| `half_width` | `number?` | Collision half-width for lateral obstacle clearance (default: 0.4) |
| `health_bar` | `(boolean\|MobHealthBarConfig)?` | Overhead combat health bar configuration (false disables) |
| `health_regen` | `(boolean\|number\|HealthRegenDef)?` | Health regen rate, disable toggle, or config table |
| `hooks` | `table<string, fun(self: table, ...any)>?` | Lifecycle hook callbacks |
| `hover_offset` | `number?` | Desired hovering elevation above ground for floating mobs in nodes (default: 0.4) |
| `hp_max` | `number?` | Maximum health points (synced to ObjectRef properties and engine HP, default: 20) |
| `immunities` | `MobImmunitiesDef?` | Environmental hazard immunities table |
| `infotext` | `string?` | Tooltip text displayed when player points at the entity |
| `initial_properties` | `(table\|MobInitialPropertiesDef)?` | Luanti ObjectRef properties table (hp, mesh, boxes, etc.) |
| `is_aquatic` | `boolean?` | Whether entity is strictly aquatic (swims in water, suffocates on land) |
| `is_floating` | `boolean?` | Whether entity hovers in mid-air with zero-gravity locomotion (default: false) |
| `knockback_mult` | `number?` | Knockback impulse multiplier (0 for unyielding/immune, default: 1.5) |
| `makes_footstep_sound` | `boolean?` | Whether walking plays footstep audio (default: true unless floating) |
| `max_angular_speed` | `number?` | Maximum turning rotation speed in radians/sec (default: 4.0) |
| `melee` | `(boolean\|MeleeConfigDef)?` | Declarative melee combat configuration (false disables) |
| `mesh` | `string?` | 3D model mesh filename (.glb, .gltf, or .b3d) |
| `mob_height` | `number?` | Height in nodes (derived from collisionbox if omitted) |
| `mob_type` | `(string\|"animal"\|"aquatic"\|"monster")?` | Alternative entity category classifier |
| `name` | `string?` | Technical entity name (e.g. "x_mobs:spider", "mymod:golem") |
| `nametag` | `string?` | Overhead nametag text |
| `nametag_bgcolor` | `(string\|table)?` | Overhead nametag background color |
| `nametag_color` | `(string\|table)?` | Overhead nametag text color |
| `on_action_end` | `fun(self: table)?` | Callback executed when action_timer completes |
| `on_activate` | `fun(self: table, staticdata: string\|table, dtime_s: number, raw?: string)?` | Called on activation |
| `on_deactivate` | `fun(self: table, removal: boolean)?` | Called when entity is unloaded or removed |
| `on_death` | `fun(self: table, killer: ObjectRef\|nil)?` | Callback invoked when entity dies |
| `on_despawn` | `fun(self: table, reason?: string)?` | Callback when entity despawns gracefully |
| `on_hurt` | `fun(self: table, puncher: ObjectRef\|nil, damage: number)?` | Callback invoked on taking damage |
| `on_punch` | `fun(self: table, puncher: ObjectRef, tflp: number, tool_caps: table, dir: Vector, damage: number)?` |  |
| `on_regen_step` | `fun(self: table, hp_added: number)?` | Optional callback executed on each health regeneration step |
| `on_return_to_fight` | `fun(self: table)?` | Optional callback executed when mob recovers HP and exits fleeing |
| `on_rightclick` | `(fun(self: table, clicker: ObjectRef):any)?` | Callback invoked when entity is right-clicked |
| `on_step` | `fun(self: table, dtime: number, moveresult?: table)?` | Callback on each physics/logic step |
| `pack` | `MobPackDef?` | Pack and squad coordination options |
| `perform_attack` | `fun(self: table, target: ObjectRef, dir: Vector)?` | Custom melee attack callback |
| `physical` | `boolean?` | Whether entity is subject to physical collisions (default: true) |
| `pointable` | `boolean?` | Whether entity can be pointed at or punched (default: true) |
| `pursuit_speed` | `number?` | Running pursuit speed in nodes/sec (default: walk_speed * 1.4) |
| `scan_interval` | `number?` | Frequency of target scanning in seconds (default: 0.4) |
| `selectionbox` | `(table\|number[])?` | 6-element selection box: {minx, miny, minz, maxx, maxy, maxz} |
| `shaded` | `boolean?` | Whether mesh is shaded by world lighting (default: true) |
| `shoal` | `ShoalConfigDef?` | Fish schooling, 3D boundary avoidance, and anchor steering configuration |
| `shooter` | `ShooterConfigDef?` | Ranged combat, projectile firing, and kiting configuration |
| `show_on_minimap` | `boolean?` | Whether entity icon appears on player minimap |
| `sounds` | `(string\|MobSoundDef)?` | Acoustic sound feedback configuration |
| `static_save` | `boolean?` | Whether entity persists in block static data across server restarts (default: true) |
| `stepheight` | `number?` | Maximum step-up height in nodes (default: 1.1) |
| `suffocation_dps` | `number?` | Damage per second when beached out of water (default: 4) |
| `swarm` | `SwarmConfigDef?` | Swarm intelligence, 3D flocking, and vortex combat configuration |
| `swarm_alert` | `(boolean\|SwarmAlertDef)?` | Declarative pack & faction rally configuration on damage and death |
| `textures` | `(string\|(string[])[]\|string[])?` | Texture filename, list of textures, or phenotype variations |
| `transitions` | `StateTransitionDef[]?` | Declarative state transition rules |
| `type` | `(string\|"aquatic"\|"flying"\|"terrestrial")?` | Locomotion archetype classifier |
| `use_texture_alpha` | `(boolean\|string)?` | Texture alpha transparency mode (true, false, "clip", "blend", "opaque") |
| `visual` | `("cube"\|"mesh"\|"sprite")?` | Visual rendering mode (default: "mesh" if mesh is specified) |
| `visual_size` | `(Vector\|Vector2d\|{ x: number, y: number, z: number })?` | Visual model scale factors |
| `walk_speed` | `number?` | Base walking speed in nodes/sec (default: 2.5) |
| `wander_radius` | `number?` | Maximum wandering patrol radius in nodes (default: 10.0) |
| `wander_speed` | `number?` | Wandering patrol speed in nodes/sec (default: walk_speed * 0.6) |
| `zoom_fov` | `number?` | Camera zoom field of view in degrees |

### `MobSoundDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `alert` | `(string\|SoundConfigDef)?` | Sound played when a target is first acquired |
| `attack` | `(string\|SoundConfigDef)?` | Sound played on melee or ranged strike |
| `base` | `string?` | Default sound-group name used as fallback for all categories |
| `death` | `(string\|SoundConfigDef)?` | Sound played on lethal damage |
| `distance` | `number?` | Global default hear distance in nodes (default: 16.0) |
| `gain` | `number?` | Global default volume multiplier (default: 1.0) |
| `hurt` | `(string\|SoundConfigDef)?` | Sound played on non-lethal damage |
| `pitch_jitter` | `number?` | Global default pitch jitter factor (default: 0.05) |
| `random` | `(string\|SoundConfigDef)?` | Periodic ambient sound played during wander/idle |
| `shoot` | `(string\|SoundConfigDef)?` | Sound played when firing a ranged projectile |
| `smash` | `(string\|SoundConfigDef)?` | Sound played on heavy ground smash impact |
| `summon` | `(string\|SoundConfigDef)?` | Sound played when summoning minions or pack followers |

### `MobStateContext`

Mob entity execution context passed as `self` across state machine callbacks and hooks.
Provides developers direct access to engine references, state variables, timers, memory, and locomotion.

| Field | Type | Description |
| :--- | :--- | :--- |
| `action_timer` | `number?` | Duration remaining for uninterruptible action; locks standard locomotion while > 0 |
| `aggro_radius` | `number?` | Maximum distance to detect hostile targets |
| `attack_cooldown` | `number?` | Global melee/combat attack cooldown timer |
| `attack_range` | `number?` | Maximum distance to initiate melee attack |
| `can_climb` | `boolean?` | Whether mob can climb ladders/vines |
| `can_crawl` | `boolean?` | Whether mob can crawl through 1-node high spaces |
| `can_flinch` | `(fun(self: MobStateContext):boolean)?` | Custom hyper-armor/poise predicate |
| `can_open_doors` | `boolean?` | Whether mob can open wooden doors |
| `can_swim` | `boolean?` | Whether mob can traverse liquid nodes |
| `can_wander` | `boolean?` | Whether mob is permitted to wander autonomously |
| `combat_hover_offset` | `number?` | Target elevation offset above ground during combat |
| `combat_standoff` | `number?` | Desired horizontal standoff distance in combat |
| `cooldowns` | `table<string, number>?` | Named ability cooldown timers |
| `custom_states` | `table<string, CustomStateDef>?` | Map of registered custom states |
| `damage` | `number?` | Base melee attack damage dealt |
| `eye_offset` | `number?` | Vertical offset from base to eye level in nodes |
| `faction_list` | `string[]?` | Ordered list of faction names |
| `factions` | `table<string, boolean>?` | Set of faction identifiers |
| `flee_speed` | `number?` | Panic escape velocity |
| `friendly_fire` | `boolean?` | Whether entity attacks/damages friendly faction members |
| `half_width` | `number?` | Half-width bounding box dimension in nodes |
| `hover_offset` | `number?` | Target elevation offset above ground or water |
| `is_dead` | `boolean` | Flag indicating whether the entity is dead or dying |
| `is_floating` | `boolean?` | Whether gravity is disabled (flying/swimming) |
| `knockback_mult` | `number?` | Resistance multiplier to incoming kinetic knockback |
| `lost_sight_timer` | `number?` | Seconds elapsed since losing direct line of sight to target |
| `memory` | `MobMemoryState?` | Short-term tactical memory buffer (LKP, threats, repulsion, trail) |
| `mob_height` | `number?` | Mob height in nodes |
| `name` | `string` | Technical registered entity name (e.g. "x_mobs:golem") |
| `object` | `ObjectRef` | Luanti engine C++ userdata pointer representing the active entity |
| `on_action_end` | `fun(self: MobStateContext)?` | Invoked when action_timer reaches 0 |
| `on_return_to_fight` | `fun(self: MobStateContext)?` | Invoked when recovering from flee state |
| `pack_id` | `string?` | UUID of the squad/pack if participating in pack coordination |
| `pack_leader` | `ObjectRef?` | Reference to the squad leader entity |
| `panic_timer` | `number?` | Duration remaining for panic flee state |
| `path_state` | `table?` | Pathfinding waypoints and traversal state |
| `pursuit_speed` | `number?` | Combat chase velocity |
| `scan_timer` | `number?` | Throttle timer for periodic target scanning |
| `set_cooldown` | `fun(self: MobStateContext, key: string, duration: number)` | Helper to set ability cooldown |
| `sounds` | `(string\|MobSoundDef)?` | Sound configuration or sound group name |
| `state` | `string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6)` | Current active state identifier |
| `target` | `ObjectRef?` | Currently acquired hostile or pursuit target |
| `walk_speed` | `number?` | Standard walking velocity |
| `wander_radius` | `number?` | Maximum radius from anchor for wandering |
| `wander_speed` | `number?` | Ambient wandering velocity |

### `NodeCacheSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `clear` | `function NodeCacheSubsystem.clear()` | Clears the per-step node caches |
| `get_node` | `function NodeCacheSubsystem.get_node(pos: Vector)   -> node: table` | Retrieves node table from per-step cache or queries engine @*param* `pos` — Node world position @*return* `node` — Node definition table {name: string, param1: number, param2: number} |
| `get_node_or_nil` | `function NodeCacheSubsystem.get_node_or_nil(pos: Vector)   -> node: table\|nil` | Retrieves node table or nil from per-step cache or queries engine @*param* `pos` — Node world position @*return* `node` — Node definition table {name: string, param1: number, param2: number} or nil |

### `PathCache`

| Field | Type | Description |
| :--- | :--- | :--- |
| `base_cost` | `table<integer, number>` |  |
| `cid_air` | `integer` |  |
| `cid_ignore` | `integer` |  |
| `climbable` | `table<integer, boolean>` |  |
| `init` | `function PathCache.init()` | Scans and caches all registered Luanti node definitions into flat integer arrays |
| `initialized` | `boolean` |  |
| `is_hazard` | `table<integer, boolean>` |  |
| `node_names` | `table<integer, string>` |  |
| `openable` | `table<integer, boolean>` |  |
| `swimable` | `table<integer, boolean>` |  |
| `tall_obstacle` | `table<integer, boolean>` |  |
| `walkable` | `table<integer, boolean>` |  |

### `ProjectileStepOptions`

| Field | Type | Description |
| :--- | :--- | :--- |
| `allow_allies` | `boolean?` | Whether friendly/allied entities can be hit (default: false) |
| `allow_players` | `boolean?` | Whether players are valid targets (default: true) |
| `damage` | `number?` | Damage applied when impacting target without on_hit_object (default: self._damage or 5) |
| `ignore_entities` | `(string[]\|table<string, boolean>)?` | Additional entity technical names to ignore |
| `lifetime` | `number?` | Maximum projectile lifetime in seconds before removal (default: 4.0) |
| `on_hit` | `fun(self: table, hit_obj: ObjectRef\|nil, hit_pos: Vector)?` | Callback executed on any impact |
| `on_hit_node` | `fun(self: table, hit_pos: Vector, node: table)?` | Callback when hitting a solid node |
| `on_hit_object` | `fun(self: table, hit_obj: ObjectRef, hit_pos: Vector, dir: Vector)?` | Object hit callback |
| `on_step` | `fun(self: table, dtime: number, pos: Vector)?` | Callback executed on every unobstructed flight step |
| `radius` | `number?` | Proximity fallback collision radius in nodes (default: 1.5) |
| `remove_on_hit` | `boolean?` | Whether to remove projectile entity upon impact (default: true) |
| `rotate` | `boolean?` | Whether to automatically rotate projectile along velocity vector (default: true) |

### `ProjectileTargetOptions`

| Field | Type | Description |
| :--- | :--- | :--- |
| `allow_allies` | `boolean?` | Whether friendly/allied entities can be hit (default: false) |
| `allow_players` | `boolean?` | Whether players are valid targets (default: true) |
| `ignore_entities` | `(string[]\|table<string, boolean>)?` | Additional entity technical names to ignore |

### `SafetySubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `check_corridor_line_of_sight` | `function SafetySubsystem.check_corridor_line_of_sight(pos: Vector, target_pos: Vector, eye_offset?: number, half_width?: number)   -> is_clear: boolean` | Volumetric multi-ray corridor check to determine if a direct straight-line path is clear. Checks eye-level, torso-level, and left/right lateral extents. If any obstacle blocks the corridor, direct path is obstructed and A* is required. @*param* `pos` — Mob base world position @*param* `target_pos` — Target world position @*param* `eye_offset` — Eye height offset above base pos @*param* `half_width` — Mob collision half-width (default 0.4) @*return* `is_clear` — True if entire corridor has unobstructed line of sight |
| `check_ground_line_of_sight` | `function SafetySubsystem.check_ground_line_of_sight(pos: Vector, target_pos: Vector, abilities?: table)   -> has_ground: boolean   2. reason: string?` | Verifies that there is a continuous, safe ground path along the straight line between pos and target_pos (no chasms, deep cliffs, or un-swimmable water). @*param* `pos` — Mob position @*param* `target_pos` — Target position @*param* `abilities` — Mob abilities @*return* `has_ground` — True if continuous safe ground exists @*return* `reason` — Failure reason if not safe ("water", "cliff", "hazard", etc.) |
| `check_in_liquid` | `function SafetySubsystem.check_in_liquid(pos: Vector, abilities?: table, mob_height?: number)   -> in_liquid: boolean   2. is_submerged: boolean   3. surface_y: number\|nil   4. target_vy: number` | Checks if entity is in liquid and calculates water surface and immersion level @*param* `pos` — World position @*param* `abilities` — Mob abilities table @*param* `mob_height` — Height of mob (default 1.5) @*return* `in_liquid` — True if in liquid and submerged or at waterline @*return* `is_submerged` — True if mob is submerged below target swimming waterline @*return* `surface_y` — Y elevation of topmost water surface in node column @*return* `target_vy` — Recommended vertical velocity to reach/maintain swimming depth |
| `find_nearest_shore_pos` | `function SafetySubsystem.find_nearest_shore_pos(pos: Vector, max_radius?: number)   -> shore_pos: Vector\|nil` | Scans for the nearest dry, walkable shoreline position from a liquid location Uses expanding concentric box rings with early exit for maximum performance @*param* `pos` — Current world position in liquid @*param* `max_radius` — Maximum search radius in nodes (default: 16) @*return* `shore_pos` — Nearest dry walkable shore position or nil |
| `init_abilities` | `function SafetySubsystem.init_abilities(self: table, def?: table)` | Initializes an entity's inherent abilities and active dynamic abilities table @*param* `self` — Entity instance @*param* `def` — Entity definition table |
| `is_aquatic_mob` | `function SafetySubsystem.is_aquatic_mob(self: table)   -> is_aquatic: boolean` | Checks if a mob is strictly aquatic (shoal fish, shark, aquatic faction) @*param* `self` — Entity instance or mob definition table |
| `is_step_safe` | `function SafetySubsystem.is_step_safe(pos: Vector, move_dir: Vector, abilities?: table, max_drop?: number)   -> is_safe: boolean   2. reason: string?` | Checks whether a step in the given horizontal direction is safe for a ground mob: - Detects cliffs (drops >= 3 blocks) - Detects un-swimmable liquid (water, river water) - Detects damaging hazard nodes (lava, fire) - Verifies 1-node step-up or direct ground footstep @*param* `pos` — Mob position @*param* `move_dir` — Horizontal direction vector {x, y, z} @*param* `abilities` — Mob abilities (can_swim, can_climb, can_crawl) @*param* `max_drop` — Maximum safe drop height (default 2) @*return* `is_safe` — True if the step is physically safe to take @*return* `reason` — Rejection reason if not safe ("wall", "cliff", "hazard", "water", "headroom") |
| `is_valid_stand_pos` | `function SafetySubsystem.is_valid_stand_pos(pos: Vector)   -> is_valid: boolean` | Checks whether a world position is a valid, standing location (not inside a wall, has ground support) @*return* `is_valid` — True if pos is clear of walkable blocks and supported by ground |

### `ShoalConfigDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `auto_succession` | `boolean?` | Whether surviving followers promote new leader on death (default: true) |
| `cull_distance` | `number?` | Active player proximity distance before hibernation (default: 36.0) |
| `enabled` | `boolean?` | Whether fish schooling is enabled (default: true) |
| `member_type` | `string?` | Custom technical entity name for school followers (default: self.name) |
| `predator` | `boolean?` | Whether school attacks threats or flees (default: true) |
| `repulsion_radius` | `number?` | Separation radius in nodes (defaults to diameter + padding) |
| `repulsion_strength` | `number?` | Anti-stacking separation push multiplier (default: 2.2) |
| `separation_padding` | `number?` | Extra distance padding added on top of collisionbox diameter (default: 0.5) |
| `size` | `integer?` | Total fish in school including leader (default: 6) |
| `spacing_x` | `number?` | Lateral distance between staggered school members (default: 2.2) |
| `spacing_y` | `number?` | Vertical depth tier spacing (default: 0.60) |
| `spacing_z` | `number?` | Longitudinal trailing distance between school ranks (default: 1.8) |
| `wander_radius` | `number?` | Leader 3D patrol radius in nodes (default: 16.0) |

### `ShoalSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `get_boundary_repulsion` | `function` |  |
| `get_collision_padding` | `function ShoalSubsystem.get_collision_padding(self: table, def: table)   -> pad: table` | Derives horizontal collision radius, diameter, height, and safe distance padding from entity collisionbox @*param* `self` — Mob instance @*param* `def` — Mob definition table @*return* `pad` — Collision padding parameters |
| `get_vertical_containment` | `function` |  |
| `get_water_column_bounds` | `unknown` |  |
| `init_entity` | `function ShoalSubsystem.init_entity(self: table, def: table, data: table)` | Initializes an entity's shoal role, index, and state on activation @*param* `self` — Mob instance @*param* `def` — Mob definition table @*param* `data` — Deserialized static data table |
| `is_navigable_water` | `unknown` |  |
| `is_safe_deep_water` | `function` |  |
| `is_water_node` | `unknown` |  |
| `on_action_end` | `function ShoalSubsystem.on_action_end(self: table, _def: table)` | Action end hook to transition attacking mobs back to swimming @*param* `self` — Mob instance @*param* `_def` — Mob definition table |
| `perform_attack` | `function ShoalSubsystem.perform_attack(self: table, target: ObjectRef, dir: Vector, _def: table)` | Executes predatory school strike with animation, rostrum damage, and recoil @*param* `self` — Mob instance @*param* `target` — Target entity @*param* `dir` — Strike direction @*param* `_def` — Mob definition table |
| `step` | `function ShoalSubsystem.step(self: table, dtime: number, def: table)   -> is_handled: boolean` | Master step dispatcher for schooling entities @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table |
| `step_combat` | `function ShoalSubsystem.step_combat(self: table, dtime: number, def: table, pos: Vector)   -> is_handled: boolean` | Advances coordinated combat locomotion when school has engaged a threat @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table @*param* `pos` — Current world position |
| `step_follower` | `function ShoalSubsystem.step_follower(self: table, dtime: number, def: table, pos: Vector)   -> is_handled: boolean` | Advances formation slot anchor steering and client velocity interpolation for school followers @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table @*param* `pos` — Current world position |
| `step_leader` | `function ShoalSubsystem.step_leader(self: table, dtime: number, def: table, pos: Vector)   -> is_handled: boolean` | Advances ambient swimming locomotion and lookahead boundary avoidance for the school leader @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table @*param* `pos` — Current world position |
| `sync_school_threat` | `function ShoalSubsystem.sync_school_threat(self: table)` | Synchronizes threat targets across the entire school to maintain cohesion @*param* `self` — Mob instance |

### `ShooterConfigDef`

Declarative ranged combat, projectile firing, and tactical kiting configuration.
When configured in `x_mob_core.register_mob`, the core pipeline automatically manages
distance acquisition, line-of-sight checks, tactical kiting/retreat, charge windup callbacks,
velocity-based lead aim prediction, and projectile spawning.

### How It Works:
1. **Distance Acquisition**: Engages when target distance is between `min_range` and `range` with line-of-sight.
2. **Tactical Kiting**: When target closes inside `min_range`, mob steers away at `retreat_speed`.
3. **Charge & Windup**: Sets `action_timer = fire_duration`, plays `animation`, `sound`, and calls `on_charge`.
4. **Aim Prediction**: After `fire_delay`, calculates lead trajectory if `predict_aim = true`.
5. **Spawning & Launch**: Spawns `projectile`, sets flight velocity/rotation, and calls `on_shoot`.

### Usage Example:
```lua
shooter = {
    projectile = "x_mobs:spectrum_orb",
    range = 16.0,
    min_range = 4.0,
    retreat_speed = 1.2,
    velocity = 14.0,
    damage = 6,
    cooldown = 3.2,
    fire_duration = 0.8,
    fire_delay = 0.4,
    predict_aim = true,
    animation = "shoot",
    sound = "shoot",
    on_charge = function(self, pos)
        -- Spawn windup charging VFX
    end,
    on_shoot = function(self, proj_obj, dir, origin)
        -- Custom projectile setup
    end,
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `animation` | `string?` | Animation track name played when shooting (default: "attack") |
| `cooldown` | `number?` | Attack cooldown between shots in seconds (default: 2.0) |
| `damage` | `number?` | Projectile damage (default: 3) |
| `fire_delay` | `number?` | Delay before projectile is released in seconds (default: 0.4) |
| `fire_duration` | `number?` | Duration mob holds shooting pose in seconds (default: 1.0) |
| `min_range` | `number?` | Minimum distance threshold under which mob retreats (default: 0.0) |
| `on_charge` | `fun(self: table, pos: Vector)?` | Callback executed during firing windup / charge |
| `on_shoot` | `fun(self: table, proj_obj: ObjectRef, dir: Vector, origin: Vector)?` | Spawn callback |
| `predict_aim` | `boolean?` | Whether to apply aim lead prediction based on target velocity (default: false) |
| `projectile` | `string?` | Technical entity name of projectile (default: "x_mobs:archer_arrow") |
| `range` | `number?` | Maximum firing range in nodes (default: def.attack_range or 15.0) |
| `retreat_speed` | `number?` | Speed when kiting / backing away from player (default: 1.0) |
| `shoot_while_retreating` | `boolean?` | Whether mob can fire projectiles while kiting / backing away (default: true) |
| `sound` | `string?` | Sound played when shooting (default: "shoot") |
| `velocity` | `number?` | Projectile flight speed in nodes/sec (default: 18.0) |

### `SoundConfigDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `chance` | `number?` | Probability to play when interval expires (default: 1.0) |
| `distance` | `number?` | Maximum audible distance in nodes (default: 16.0) |
| `gain` | `number?` | Volume multiplier (default: 1.0) |
| `max_interval` | `number?` | Maximum cooldown between automatic triggers (default: 22.0) |
| `min_interval` | `number?` | Minimum cooldown between automatic triggers (default: 8.0) |
| `name` | `string\|string[]` | Technical sound name or list of sound variations |
| `pitch` | `number?` | Base pitch multiplier (default: 1.0) |
| `pitch_jitter` | `number?` | Random pitch variation factor (default: 0.05) |

### `SoundSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `play` | `function SoundSubsystem.play(self: table\|userdata, sound_type: string, overrides?: table)   -> sound_handle: integer\|nil` | Plays a configured sound type for a mob instance with positional attenuation and pitch variation @*param* `self` — Mob instance or ObjectRef @*param* `sound_type` — Category ("hurt", "death", "random", "attack", "alert") or technical sound name @*param* `overrides` — Optional overrides (gain, distance, pitch, pos, object, to_player, loop) @*return* `sound_handle` — Luanti sound handle or nil if not played |
| `stop` | `function SoundSubsystem.stop(handle?: integer)` | Stops a playing sound handle @*param* `handle` — Luanti sound handle |
| `update` | `function SoundSubsystem.update(self: table, dtime: number)` | Updates ambient random sound cooldown timer and triggers wander vocalizations @*param* `self` — Mob instance @*param* `dtime` — Step delta time |

### `SpawnConfig`

| Field | Type | Description |
| :--- | :--- | :--- |
| `active_object_count` | `integer?` | Max nearby instances allowed (default: 1) |
| `biomes` | `string[]?` | Optional list of biome technical names (e.g. {"everness:crystal_forest"}) |
| `chance` | `integer?` | 1 in X chance per tick (default: 1000) |
| `day_only` | `boolean?` | Only spawn during daytime (0.20 <= time <= 0.80) |
| `exclude_groups` | `string[]?` | Node groups to explicitly exclude from spawning (e.g. "river_water") |
| `exclude_nodes` | `string[]?` | Specific nodes to explicitly exclude from spawning (e.g. "default:river_water_source") |
| `group_max` | `integer?` | Maximum entities to spawn in a pack/swarm (default: 1) |
| `group_min` | `integer?` | Minimum entities to spawn in a pack/swarm (default: 1) |
| `is_aquatic` | `boolean?` | Whether mob spawns submerged inside liquid rather than on surface |
| `max_elevation` | `number?` | Maximum Y coordinate (default: 31000) |
| `max_light` | `integer?` | Maximum light level 0..15 (default: 15) |
| `max_time` | `number?` | Specific maximum time-of-day (0.0 to 1.0) |
| `max_total_in_radius` | `integer?` | Max total living mobs allowed in spawn radius (default: 8) |
| `min_elevation` | `number?` | Minimum Y coordinate (default: -31000) |
| `min_light` | `integer?` | Minimum light level 0..15 (default: 0) |
| `min_time` | `number?` | Specific minimum time-of-day (0.0 to 1.0) |
| `mob_name` | `string?` | Optional entity technical name override |
| `night_only` | `boolean?` | Only spawn during nighttime (time < 0.20 or time > 0.80) |
| `nodes` | `string[]?` | Valid ground node names or group filters (e.g. "group:water") |

### `SpawnDefinition`

| Field | Type | Description |
| :--- | :--- | :--- |
| `active_object_count` | `integer?` | Max nearby instances allowed (default: 1) |
| `biomes` | `string[]?` | Optional list of biome technical names (e.g. {"everness:crystal_forest"}) |
| `chance` | `integer?` | 1 in X chance per tick (default: 1000) |
| `day_only` | `boolean?` | Only spawn during daytime (0.20 <= time <= 0.80) |
| `exclude_groups` | `string[]?` | Node groups to explicitly exclude from spawning (e.g. "river_water") |
| `exclude_nodes` | `string[]?` | Specific nodes to explicitly exclude from spawning (e.g. "default:river_water_source") |
| `group_max` | `integer?` | Maximum entities to spawn in a pack/swarm (default: 1) |
| `group_min` | `integer?` | Minimum entities to spawn in a pack/swarm (default: 1) |
| `is_aquatic` | `boolean?` | Whether mob spawns submerged inside liquid rather than on surface |
| `max_elevation` | `number?` | Maximum Y coordinate (default: 31000) |
| `max_light` | `integer?` | Maximum light level 0..15 (default: 15) |
| `max_time` | `number?` | Specific maximum time-of-day (0.0 to 1.0) |
| `max_total_in_radius` | `integer?` | Max total living mobs allowed in spawn radius (default: 8) |
| `min_elevation` | `number?` | Minimum Y coordinate (default: -31000) |
| `min_light` | `integer?` | Minimum light level 0..15 (default: 0) |
| `min_time` | `number?` | Specific minimum time-of-day (0.0 to 1.0) |
| `mob_name` | `string?` | Entity technical name (e.g. "x_mobs:spider") |
| `night_only` | `boolean?` | Only spawn during nighttime (time < 0.20 or time > 0.80) |
| `nodes` | `string[]?` | Valid ground node names or group filters (e.g. "group:water") |

### `SpawningConditions`

| Field | Type | Description |
| :--- | :--- | :--- |
| `MAX_TOTAL_RADIUS_MOBS` | `integer` |  |
| `check` | `function SpawningConditions.check(pos: Vector, def: SpawnConfig\|SpawnDefinition, is_mapgen?: boolean)   -> is_valid: boolean` | Checks if a position satisfies all conditions for a spawn definition @*param* `pos` — Proposed spawn world position @*param* `def` — Spawn definition table @*param* `is_mapgen` — Whether check is performed during mapgen chunk generation |
| `count_mobs_in_radius` | `function` |  |
| `is_mob_entity` | `function` |  |

### `SpawningEngine`

| Field | Type | Description |
| :--- | :--- | :--- |
| `conditions` | `unknown` |  |
| `registry` | `unknown` |  |
| `spawn_mob_group` | `function` |  |

### `SpawningRegistry`

| Field | Type | Description |
| :--- | :--- | :--- |
| `cached_surface_node_list` | `string[]\|nil` |  |
| `get_spawns` | `function SpawningRegistry.get_spawns()   -> SpawnDefinition[]` | Returns all registered spawn definitions |
| `get_surface_nodes` | `function SpawningRegistry.get_surface_nodes()   -> string[]` | Returns flat list of all unique surface nodes registered across all mobs |
| `register_spawn` | `function SpawningRegistry.register_spawn(mob_name: string, def: SpawnConfig\|SpawnDefinition)` | Registers a mob for natural spawning @*param* `mob_name` — Registered entity technical name @*param* `def` — Spawn parameters |
| `registered_groups` | `table<string, boolean>` |  |
| `spawns` | `SpawnDefinition[]` |  |
| `surface_nodes` | `table<string, boolean>` |  |
| `surface_nodes_dirty` | `boolean` |  |

### `SquadSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `add_follower` | `function SquadSubsystem.add_follower(self: table, follower_obj: ObjectRef, force?: boolean)   -> added: boolean` | Registers a follower under a leader @*param* `self` — Leader mob instance @*param* `follower_obj` — Follower entity object @*param* `force` — If true, bypasses max_followers capacity limit (default: false) @*return* `added` — True if follower was newly registered or reconfirmed, false if full or invalid |
| `adopt_nearby_orphans` | `function SquadSubsystem.adopt_nearby_orphans(self: table, search_radius?: number)` | Leader searches nearby area to adopt orphans or re-link separated followers @*param* `self` — Leader mob instance @*param* `search_radius` — Radius to search (default: 32.0) |
| `clean_followers` | `function SquadSubsystem.clean_followers(self: table)   -> count: integer   2. alive_followers: table` | Cleans invalid/dead follower objects from a leader's roster in-place without table allocations @*param* `self` — Leader mob instance |
| `elect_successor` | `function SquadSubsystem.elect_successor(self: table, search_radius?: number)   -> success: boolean` | Democratic leader election: promotes the first surviving follower in-place @*param* `self` — Mob instance (dying leader or surviving follower) @*param* `search_radius` — Radius to search for surviving members (default: 24.0) @*return* `success` — True if a new leader was established |
| `handle_leader_death` | `function SquadSubsystem.handle_leader_death(self: table)` | Disbands the pack and notifies all followers when the leader dies @*param* `self` — Leader mob instance |
| `init_leader` | `function SquadSubsystem.init_leader(self: table, config: MobPackDef)` | Registers an entity as a pack leader @*param* `self` — Mob instance @*param* `config` — Pack options |
| `init_member` | `function SquadSubsystem.init_member(self: table, config: MobPackDef)` | Registers an entity as a pack follower/member @*param* `self` — Mob instance @*param* `config` — Pack options |
| `relink_follower` | `function SquadSubsystem.relink_follower(self: table, search_radius?: number)   -> linked: boolean` | Follower searches nearby area to re-link with its pack leader if separated @*param* `self` — Follower mob instance @*param* `search_radius` — Radius to search (default: 32.0) @*return* `linked` — True if successfully re-linked |
| `remove_follower` | `function SquadSubsystem.remove_follower(self: table, follower_obj: ObjectRef)` | Removes a follower object from a leader's roster @*param* `self` — Leader mob instance @*param* `follower_obj` — Follower entity object |
| `spawn_cluster` | `function SquadSubsystem.spawn_cluster(self: table, def: table)` | Spawns missing follower peers/members radially around the cluster leader Single unified engine method supporting aquatic shoals, airborne swarms, and ground squads @*param* `self` — Leader mob instance @*param* `def` — Mob definition table |
| `spawn_initial_followers` | `function SquadSubsystem.spawn_initial_followers(self: table, follower_type?: string\|table, max_count?: integer, spawn_radius?: number)` | Adopts nearby orphans and spawns missing followers radially around the leader @*param* `self` — Leader mob instance @*param* `follower_type` — Entity technical name (default: self.pack_follower_type) @*param* `max_count` — Target follower count (default: self.pack_max_followers or 3) @*param* `spawn_radius` — Radial spawn distance (default: 1.5) |

### `StatusEffectDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `string` | Unique effect identifier |
| `duration` | `number` | Duration in seconds |
| `type` | `("custom"\|"debuff"\|"dot"\|"root"\|"slow")?` | Effect archetype (`"root"` halts movement/jump; `"debuff"` for weakness, damage amp, healing suppression, or stamina drain) |
| `chance` | `number?` | Optional success chance (fraction `0.0`-`1.0` or percentage `1`-`100`; defaults to 100% when undefined) |
| `speed_factor` | `number?` | Movement speed fractional multiplier (e.g. 0.5 for 50% slow) |
| `jump_factor` | `number?` | Jump fractional multiplier (e.g. 0.0 to prevent jump) |
| `gravity_factor` | `number?` | Gravity fractional multiplier |
| `fov_factor` | `number?` | Camera FOV multiplier factor applied to player target (e.g. 0.85 for shock/concussion dip; compounded on top of baseline FOV) |
| `fov_duration` | `number?` | Optional sub-duration in seconds for FOV override if shorter than effect duration (e.g. 0.8s flash dip within 3.5s effect) |
| `fov_transition` | `number?` | FOV smoothing transition time in seconds (default: 0.2s) |
| `damage` | `number?` | Damage per interval tick for DoT |
| `interval` | `number?` | Interval between DoT ticks in seconds (default: 1.0) |
| `damage_type` | `string?` | Damage group name for DoT (default: "fleshy") |
| `caster` | `ObjectRef?` | Attacking entity or player source |
| `penetrate_armor` | `boolean?` | Whether DoT bypasses armor damage reduction (default: true) |
| `particle_spawner` | `table\|fun(target: ObjectRef):table?` | Particle spawner definition for DoT ticks |
| `envelop` | `table<{ texture: string }>?` | Visual envelop configuration |
| `envelop_texture` | `string?` | Visual envelop sleeve texture asset |
| `hud_vignette` | `string\|table?` | Fullscreen responsive screen vignette configuration |
| `cleanse_in_water` | `boolean?` | Whether immersion in water immediately cleanses the effect |
| `drain_hunger` | `number?` | Hunger or stamina units drained per tick via hunger_adapter |
| `anti_heal` | `boolean?` | Whether health regeneration is suppressed during effect |
| `damage_multiplier` | `number?` | Incoming damage multiplier while afflicted (e.g. 1.35 for brittle) |
| `on_apply` | `fun(target: ObjectRef)?` | Callback when effect is first applied |
| `on_step` | `fun(dtime: number, target: ObjectRef)?` | Callback on step tick (forwarded to envelop) |
| `on_tick` | `fun(target: ObjectRef)?` | Callback on periodic DoT tick |
| `on_remove` | `fun(target: ObjectRef)?` | Callback when effect is removed or expires |

### `StatusEffectsSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `apply_effect` | `function StatusEffectsSubsystem.apply_effect(target: ObjectRef, effect_def: StatusEffectDef)   -> ObjectRef\|boolean` | Applies or refreshes a status effect on target (player or entity) |
| `remove_effect` | `function StatusEffectsSubsystem.remove_effect(target: ObjectRef, effect_id: string)   -> success: boolean` | Removes an active status effect from target |
| `has_effect` | `function StatusEffectsSubsystem.has_effect(target: ObjectRef, effect_id: string)   -> has_effect: boolean` | Checks if target currently has an active status effect |
| `get_effects` | `function StatusEffectsSubsystem.get_effects(target: ObjectRef)   -> effects: table\|nil` | Retrieves all active status effects for a target |
| `clear_effects` | `function StatusEffectsSubsystem.clear_effects(target: ObjectRef)` | Clears all active status effects and restores baseline physics on target |
| `get_damage_multiplier` | `function StatusEffectsSubsystem.get_damage_multiplier(target: ObjectRef)   -> multiplier: number` | Retrieves compound damage multiplier across all active status effects on target |
| `is_rooted` | `function StatusEffectsSubsystem.is_rooted(target: ObjectRef)   -> is_rooted: boolean` | Checks if target is currently affected by a root status effect or has speed factor <= 0 |

### `StateMachineSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `transition_to` | `function StateMachineSubsystem.transition_to(self: MobStateContext, new_state: string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6))` | Transitions an entity to a new state, invoking exit and enter hooks. ### How States Are Set & Transition Mechanisms: 1. **Canonical Transition API (`x_mob_core.transition_to` / `state_machine.transition_to`)**: The standard method to transition between states. It checks whether `old_state == new_state` (preventing redundant cycles), calls `custom_states[old_state].exit(self)` if available, updates `self.state = new_state`, and calls `custom_states[new_state].enter(self)`. 2. **Custom State Step Tick Return**: Inside `custom_states[state].step(self, dtime)`, return a target state name string (e.g., `return "idle"` or `return "fleeing"`) to trigger an automatic call to `state_machine.transition_to(self, next_state)`. Returning `nil` or `true` retains current state. 3. **Declarative State Transitions (`transitions = { ... }`)**: Evaluated every tick in the lifecycle step pipeline. When `condition(self)` evaluates to `true`, `self.state` transitions from `from` (or wildcard `"*"`) to `to`, and `on_transition(self)` runs. 4. **Core AI / Subsystem Direct Assignment (`self.state = "..."`)**: Core internal routines (`mob_ai.step_wander_or_idle`, `combat_handler`, `shoal`, `coordination`) set `self.state` directly during built-in behaviors. Note: direct assignment does not trigger `custom_states` `exit` or `enter` hooks; use `transition_to` when custom state hooks are needed. 5. **Action Timer Completion**: When `self.action_timer` completes, `self:on_action_end()` is invoked and `self.state` resets to `"idle"`. ### What Is Available on `self` for Developers: Inside state callbacks (`enter`, `step`, `exit`), developers have full access to `self` (`MobStateContext`): - **Engine Object**: `self.object` (`ObjectRef`), `self.name`, `self._moveresult`. - **Timers & Cooldowns**: `self.action_timer`, `self.attack_cooldown`, `self.panic_timer`, `self.cooldowns`, - and helper `self:set_cooldown(key, duration)`. - **Tactical Memory**: `self.memory` (`MobMemoryState`: target LKP, danger repulsion, flee state). - **Locomotion Attributes**: `self.walk_speed`, `self.pursuit_speed`, `self.wander_speed`, `self.flee_speed`, - `self.wander_radius`, and `self.path_state`. - **Combat & Defense**: `self.damage`, `self.attack_range`, `self.aggro_radius`, `self.knockback_mult`, - and `self.factions`. - **Animation & Audio**: `x_mob_core.animator.play(self.object, anim_name, opts)` and - `x_mob_core.sound.play(self, sound_type)`. @*param* `self` — Mob instance context table @*param* `new_state` — Target state name to transition to ```lua -- Canonical state machine states coordinating mob behavior, animation, and locomotion. new_state: \| "idle" -- Entity is stationary, resting, or scanning for nearby targets \| "wandering" -- Entity is passively exploring local terrain within wander_radius \| "walk" -- Entity is traversing toward an objective, waypoint, or squad position \| "combat" -- Entity has acquired a hostile target and is actively maneuvering/pursuing \| "attacking" -- Entity is executing an active melee attack animation or combat ability \| "shooting" -- Entity is executing a ranged attack windup, casting, or projectile launch \| "fleeing" -- Entity is executing a tactical retreat due to low HP or threat level \| "regrouping" -- Entity is returning to its squad leader or shoal anchor position \| "flinching" -- Entity is in hit-stun recoil from taking damage (hyper-armor checked) \| "dying" -- Entity has reached zero HP and is playing its defeat animation before removal ``` |
| `update` | `function StateMachineSubsystem.update(self: MobStateContext, dtime: number)   -> handled: boolean` | Updates the current custom state if one is active. Invoked every server tick during the mob's step pipeline. If `self.state` matches a registered entry in `self.custom_states`, executes its `step(self, dtime)` callback. If that callback returns a different state name, triggers `state_machine.transition_to(self, next_state)`. @*param* `self` — Mob instance context table @*param* `dtime` — Step delta time in seconds @*return* `handled` — True if handled by an active custom state, false otherwise |

### `StateTransitionDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `condition` | `fun(self: MobStateContext):boolean` | Condition predicate returning true to transition |
| `from` | `string\|"*"\|"attacking"\|"combat"\|"dying"...(+7)` | Source state name or "*" for wildcard |
| `on_transition` | `fun(self: MobStateContext)?` | Optional callback executed during transition |
| `to` | `string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6)` | Destination state name |

### `StepHook`

| Field | Type | Description |
| :--- | :--- | :--- |
| `handler` | `fun(self: table, dtime: number, def: table, moveresult?: table):boolean\|nil` | Middleware callback executed each step |
| `name` | `string` | Unique identifier of the hook (e.g. "mymod:freeze_aura") |
| `priority` | `integer` | Execution order (lower runs first; see priority schedule in documentation) |

### `StepPipeline`

| Field | Type | Description |
| :--- | :--- | :--- |
| `execute` | `function StepPipeline.execute(self: table, dtime: number, def: table\|MobRegistrationDef, moveresult?: table)   -> handled: boolean` | Executes registered step hooks sequentially in priority order. If any hook handler returns `true`, pipeline execution halts immediately and returns `true`. @*param* `self` — Mob entity instance @*param* `dtime` — Step delta time in seconds @*param* `def` — Entity definition table @*param* `moveresult` — Engine move result @*return* `handled` — True if intercepted by any hook, false otherwise |
| `register_step_hook` | `function StepPipeline.register_step_hook(name: string, priority: integer, handler: fun(self: table, dtime: number, def: table, moveresult?: table):boolean\|nil)` | Registers a step middleware hook executed during entity step lifecycle. Hooks execute sequentially in ascending priority order on every server tick. If the handler returns `true`, subsequent step handling is intercepted (early return). @*param* `name` — Unique hook identifier (namespaced, e.g. "mymod:freeze_aura") @*param* `priority` — Execution order (lower runs first; e.g. < 18 for CC/stun, 18 melee, 20 shooter, 50+ aura) @*param* `handler` — Callback function. Return `true` to intercept, or `false`/`nil` to continue. |
| `unregister_step_hook` | `function StepPipeline.unregister_step_hook(name: string)` | Unregisters a previously registered step hook by identifier name. @*param* `name` — Unique hook identifier to remove |

### `SurfaceSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `dir_to_surface_rotation` | `function SurfaceSubsystem.dir_to_surface_rotation(dir: Vector, up: Vector)   -> Euler: Vector` | Computes 3D Euler angles (pitch, yaw, roll in radians) matching Luanti extrinsic Z-X-Y order @*param* `dir` — Movement direction @*param* `up` — Surface normal @*return* `Euler` — rotation in radians {x = pitch, y = yaw, z = roll} |
| `find_adjacent_surface` | `function SurfaceSubsystem.find_adjacent_surface(pos: Vector, preferred_normal?: Vector)   -> surface_info: table\|nil` | Checks whether an entity is physically adjacent to a solid walkable surface (floor, wall, ceiling, or uneven corner) within reach (~1.15m). Retains preferred_normal if the existing surface is still in contact (hysteresis). Returns surface info table or nil if entity is floating in mid-air. @*param* `pos` — World position @*param* `preferred_normal` — Previous surface normal for geometric hysteresis @*return* `surface_info` — {has_surface = boolean, normal = Vector, surface_type = string} |
| `interpolate_rotation` | `function SurfaceSubsystem.interpolate_rotation(cur_rot: Vector, target_rot: Vector, factor: number, max_delta?: number)   -> Vector` | Smoothly interpolates Euler angles handling modulo wrap with optional angular rate limiting @*param* `cur_rot` — Current rotation @*param* `target_rot` — Target rotation @*param* `factor` — Interpolation factor [0, 1] @*param* `max_delta` — Maximum angular delta allowed per step (radians) |
| `interpolate_vector` | `function SurfaceSubsystem.interpolate_vector(v1: Vector, v2: Vector, factor: number)   -> Vector` | Linearly interpolates and normalizes two 3D vectors @*param* `v1` — Start vector @*param* `v2` — Target vector @*param* `factor` — Interpolation factor [0, 1] |

### `SwarmAlertDef`

Declarative pack/faction rally configuration evaluated automatically by combat_handler on damage and death.
Unlike imperative broadcast_threat, swarm_alert also writes coordinate memory for obscured allies.

| Field | Type | Description |
| :--- | :--- | :--- |
| `enabled` | `boolean?` | Whether pack threat alerting is enabled (default: true) |
| `max_allies` | `integer?` | Maximum pack members rallied per threat alert (default: 8) |
| `radius` | `number?` | Search radius for alerting nearby pack allies (default: 24.0) |

### `SwarmCombatDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `clamp_ceiling` | `boolean?` | Prevent flying above target head (default: true) |
| `dive_range` | `number?` | Distance threshold to trigger dive attack (default: 9.0) |
| `dive_speed` | `number?` | Speed during dive-bomb run (default: 6.4) |
| `exclusion_radius` | `number?` | Repulsion cylinder around target (default: 2.4) |
| `height_offset` | `number?` | Desired altitude relative to target (default: 1.0) |
| `mode` | `("direct"\|"vortex")?` | Combat locomotion style (default: "vortex") |
| `orbit_radius` | `number?` | Base orbit distance around target (default: 3.2) |
| `orbit_shells` | `integer?` | Concentric radial shells for multi-agent spacing (default: 3) |
| `recoil` | `number?` | Horizontal pushback force after attack punch (default: 4.5) |
| `two_way_orbit` | `boolean?` | Alternate CW and CCW orbits (default: true) |

### `SwarmConfigDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `attack_cooldown_min` | `number?` | Minimum cooldown before next dive attack (default: 2.5) |
| `attack_cooldown_rand` | `number?` | Random additional cooldown before next dive (default: 2.5) |
| `auto_succession` | `boolean?` | Democratic election of new anchor on leader death (default: true) |
| `combat` | `SwarmCombatDef?` | Coordinated combat vortex and dive-bomb options |
| `enabled` | `boolean?` | Whether swarm intelligence is active (default: true) |
| `flock_radius` | `number?` | Idle orbiting radius around anchor (default: 2.0) |
| `hover_elevation` | `number?` | Height anchored above walkable terrain (default: 1.4) |
| `member_type` | `string?` | Entity technical name of swarm peers (default: self.name) |
| `micro_darts` | `boolean?` | Random sudden velocity impulses with drag decay (default: true) |
| `organic_jitter` | `boolean?` | Multi-frequency harmonic velocity jitter (default: true) |
| `repulsion_radius` | `number?` | Inter-mob 3D separation radius (default: 2.2) |
| `repulsion_strength` | `number?` | Inter-mob repulsion push force (default: 2.8) |
| `size` | `integer?` | Total swarm cluster size (default: 4) |
| `stagger_attacks` | `boolean?` | Offsets attack cooldowns across swarm members (default: true) |

### `SwarmSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `init_entity` | `function SwarmSubsystem.init_entity(self: table, def: table, data: table)` | Initializes an entity's swarm role, index, and state on activation @*param* `self` — Mob instance @*param* `def` — Mob definition table @*param* `data` — Deserialized static data table |
| `on_action_end` | `function SwarmSubsystem.on_action_end(self: table, _def: table)` | Action end hook to transition attacking mobs back to combat walk @*param* `self` — Mob instance @*param* `_def` — Mob definition table |
| `perform_attack` | `function SwarmSubsystem.perform_attack(self: table, target: ObjectRef, dir: Vector, def: table)` | Executes standard dive attack strike with animation, sound, and horizontal recoil @*param* `self` — Mob instance @*param* `target` — Target entity @*param* `dir` — Strike direction @*param* `def` — Mob definition table |
| `step` | `function SwarmSubsystem.step(self: table, dtime: number, def: table)   -> is_handled: boolean` | Master step dispatcher for swarming entities @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table |
| `step_combat` | `function SwarmSubsystem.step_combat(self: table, dtime: number, def: table)   -> is_handled: boolean` | Advances coordinated combat locomotion: vortex holding pattern and dive-bomb attack runs @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table |
| `step_flock` | `function SwarmSubsystem.step_flock(self: table, dtime: number, def: table)   -> is_handled: boolean` | Advances ambient swarm idle locomotion: dynamic flocking, leader patrol, and ground contour tethering @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table |

### `UtilsSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `avoid_solid_nodes` | `function UtilsSubsystem.avoid_solid_nodes(target_pos: Vector, safe_origin: Vector, look_dir?: Vector)   -> clear_pos: Vector` | Verifies if a target coordinate is safely in passable air; if blocked, returns an adjusted clear position. Probes lower elevations and ray-traces back towards safe_origin to prevent entities clipping into solid geometry. @*param* `target_pos` — Desired 3D coordinate @*param* `safe_origin` — Known safe origin or anchor (e.g. player or mob origin) @*param* `look_dir` — Optional directional vector to tuck behind if in tight enclosure @*return* `clear_pos` — Adjusted safe 3D coordinate |
| `find_ground_level` | `function UtilsSubsystem.find_ground_level(x: number, start_y: number, z: number, max_down?: number)   -> ground_y: number\|nil` | Finds the top surface Y coordinate of the solid walkable ground below a given 3D position @*param* `x` — X world coordinate @*param* `start_y` — Y world coordinate @*param* `z` — Z world coordinate @*param* `max_down` — Maximum distance to search downwards (default: 36) @*return* `ground_y` — Top surface Y of solid node, or nil if none found |
| `generate_uuid` | `function UtilsSubsystem.generate_uuid()   -> uuid: string` | Generates an RFC 4122 Version 4 compliant UUID. Uses Luanti's OS-backed SecureRandom for guaranteed uniqueness, with an automatic RFC 4122 template math.random fallback. |
| `get_ground_y` | `function UtilsSubsystem.get_ground_y(pos: Vector, max_down?: number, max_up?: number, walkable_only?: boolean)   -> ground_y: number\|nil` | Finds the topmost solid ground surface near a given coordinate @*param* `pos` — Position to check @*param* `max_down` — Maximum distance to search downwards (default: 8) @*param* `max_up` — Maximum distance to search upwards (default: 3) @*param* `walkable_only` — If true, requires walkable non-liquid node with headroom (default: true) @*return* `ground_y` — Top surface height of highest ground node, or nil |
| `get_headroom` | `function UtilsSubsystem.get_headroom(origin: Vector, max_check?: number)   -> headroom: number` | Scans vertically upwards from origin to check distance to the first solid ceiling node. @*param* `origin` — Base position (e.g. foot or center coordinate) @*param* `max_check` — Maximum nodes to scan upward (default: 4.0) @*return* `headroom` — Distance to first walkable ceiling node, or max_check if open sky |
| `get_water_column_bounds` | `function UtilsSubsystem.get_water_column_bounds(pos: Vector, _pad?: number\|table)   -> safe_min_y: number   2. safe_max_y: number   3. is_shallow: boolean   4. surface_y: number   5. floor_y: number` | Determines safe submerged vertical range for an entity in the water column. Strictly guarantees minimum 2-node clearance below the air surface. @*param* `pos` — World position @*param* `_pad` — Optional padding @*return* `safe_min_y` — Lowest safe Y coordinate (above seabed) @*return* `safe_max_y` — Highest safe Y coordinate (at least 2 nodes below surface air) @*return* `is_shallow` — True if water depth is under 3.5 nodes @*return* `surface_y` — Highest water block Y @*return* `floor_y` — Lowest water block Y |
| `is_player_alive` | `function UtilsSubsystem.is_player_alive(player: ObjectRef)   -> is_alive: boolean` | Checks if an ObjectRef is a valid living player or entity @*param* `player` — Target entity @*return* `is_alive` — True if player reference is valid and alive |
| `is_walkable_node` | `function UtilsSubsystem.is_walkable_node(pos_or_x: number\|Vector, y?: number, z?: number)   -> is_walkable: boolean` | Checks if a world position or coordinate represents a walkable solid node. @*param* `pos_or_x` — World position table or X coordinate @*param* `y` — Y coordinate @*param* `z` — Z coordinate |
| `is_water_node` | `function UtilsSubsystem.is_water_node(pos_or_x: number\|Vector, y?: number, z?: number)   -> is_water: boolean` | Checks if a world position or coordinate represents a water node. @*param* `pos_or_x` — World position table or X coordinate @*param* `y` — Y coordinate @*param* `z` — Z coordinate |
| `line_of_sight` | `function UtilsSubsystem.line_of_sight(p1: Vector, p2: Vector)   -> is_clear: boolean` | Line of sight check between two points using native engine C++ ray traversal with liquid penetration support |
| `pick_ground_waypoint` | `function UtilsSubsystem.pick_ground_waypoint(current_pos: Vector, origin?: Vector, radius?: number, min_dist?: number, max_dist?: number, hover_offset?: number)   -> waypoint: Vector\|nil` | Picks a ground-anchored wander waypoint near current position over solid walkable nodes @*param* `current_pos` — Current mob world position @*param* `origin` — Center origin of wander boundary (default: current_pos) @*param* `radius` — Maximum wander radius from origin (default: 10.0) @*param* `min_dist` — Minimum step distance from current position (default: 3.0) @*param* `max_dist` — Maximum step distance from current position (default: 7.5) @*param* `hover_offset` — Vertical offset above detected ground (default: 1.4) @*return* `waypoint` — Ground-anchored target position or nil |
| `shallow_copy` | `function UtilsSubsystem.shallow_copy(tbl: <T:table>)   -> <T:table>` | Shallow copies a table |

---

## Type Aliases & Callbacks

| Type Alias | Signature / Definition | Description |
| :--- | :--- | :--- |
| `CoreEventName` | `"on_mob_death"\|"on_mob_despawn"\|"on_mob_hurt"\|"on_mob_spawn"` | Standard pub-sub event names emitted across mob lifecycles on the x_mob_core event bus. |
| `CustomStepHandler` | `fun(self: table, dtime: number, moveresult?: table, def?: table):boolean\|nil` | Pre-combat custom ability interception hook handler. Executed at Priority 15 in the middleware pipeline prior to declarative melee and shooter logic. Return `true` to halt the pipeline (e.g. while casting spells, summoning minions, in tactical standoff). Return `false` or `nil` to fall through into standard declarative melee and ranged attacks. |
| `EventListenerCallback` | `fun(...any)` | Callback function invoked when a pub-sub event is emitted on the event bus. |
| `MobStateType` | `string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6)` | Canonical state machine states coordinating mob behavior, animation, and locomotion. |
| `PathfindingCallback` | `fun(path: Vector[]\|nil)` | Callback function invoked when an asynchronous A* path search completes. Receives an array of solved 3D waypoint vectors on success, or `nil` if unreachable. |
| `StepHookHandler` | `fun(self: table, dtime: number, def: table, moveresult?: table):boolean\|nil` | Step hook callback invoked on every server step for living mob entities. Return values: - Return `true` to **intercept** step handling: cancels subsequent pipeline hooks from firing on this tick, and bypasses default pursuit and wandering locomotion. - Return `false` or `nil` to allow subsequent pipeline hooks and normal mob locomotion to proceed. |

---

## Lifecycle & Entity Registration API

Standardized mob entity registration, state machine transitions, armor group handling, texture variation routing, target selection, lifecycle-tied action scheduling, and prioritized step middleware pipeline hooks.

#### `x_mob_core.cancel_scheduled`

Cancels scheduled actions by tag.

```lua
function x_mob_core.cancel_scheduled(self: table, tag: string)
```

**Parameters:**

* `self` (`table`): Mob entity reference
* `tag` (`string`): The tag to cancel

#### `x_mob_core.clear_scheduled`

Clears all scheduled actions for the mob.

```lua
function x_mob_core.clear_scheduled(self: table)
```

**Parameters:**

* `self` (`table`): Mob entity reference

#### `x_mob_core.register_mob`

Registers a mob definition with standardized physical properties and lifecycle integration.

```lua
function x_mob_core.register_mob(name: string, def: MobRegistrationDef)
```

**Parameters:**

* `name` (`string`): Technical entity name (e.g. "x_mobs:spider")
* `def` (`MobRegistrationDef`): Mob specification and callback configuration table

#### `x_mob_core.register_step_hook`

Registers an extensible step middleware hook into the mob execution pipeline.
Allows 3rd-party mods and core subsystems to inject custom step logic without
modifying core engine loops or overriding mob `on_step` callbacks (Open/Closed Principle).

### Lifecycle & Execution Order
Step hooks execute sequentially on every server tick for all living `x_mob_core` entities
during `on_step`, after core lifecycle routines (death countdown, buoyancy, timers, target validation)
and custom state machines have run, but before fallback idle wandering or target pursuit.

Hooks are evaluated in ascending order of `priority` (lower numerical values run first).

### Early Return & Interception
The return value of `handler` controls execution flow:
- Return `true`: **Intercepts** the step. Halts subsequent pipeline hooks from firing on this tick,
  and bypasses default idle wandering (`step_wander_or_idle`) and target pursuit (`step_move_or_idle`).
  Ideal for crowd control effects (stun, freeze, sleep, fear, paralysis).
- Return `false` or `nil`: Continues to the next hook in the pipeline and allows normal locomotion.

### Priority Schedule & Reference Table
| Priority | Subsystem / Recommended Usage | Description |
|:---|:---|:---|
| `< 15` | Crowd Control / Status Effects | Stuns, freezes, sleep. Returning `true` halts attacks & movement. |
| `15` | Built-in `"custom_step"` | Pre-combat custom ability hook (spells, summons, tactical standoff). |
| `18` | Built-in `"melee"` | Internal melee attack range validation and strikes. |
| `20` | Built-in `"shooter"` | Internal projectile attack aiming and shooting. |
| `25` | Built-in `"environment"` | Internal hazard checks (lava, fire, drowning, suffocation). |
| `30` | Built-in `"pack_cluster"` | Internal pack and squad cluster spawning trigger. |
| `40` | Built-in `"swarm_nav"` | Internal 3D aerial Boids swarm navigation and dive-bombing. |
| `42` | Built-in `"shoal_nav"` | Internal aquatic schooling navigation and anchor steering. |
| `50+` | Post-Combat / Passives | Periodic damage ticks, status aura updates, dynamic buffs, telemetry. |

```lua
function x_mob_core.register_step_hook(name: string, priority: integer, handler: fun(self: table, dtime: number, def: table, moveresult?: table):boolean|nil)
```

**Parameters:**

* `name` (`string`): Unique hook identifier (namespaced, e.g. "mymod:freeze_aura")
* `priority` (`integer`): Execution order (lower runs first; see priority schedule)
* `handler` (`fun(self: table, dtime: number, def: table, moveresult?: table):boolean|nil`): Callback function. Return `true` to intercept, or `false`/`nil` to continue.

#### `x_mob_core.schedule`

Schedules an action to be executed in the future on the mob's timer.
Unlike `core.after`, scheduled actions are automatically tied to the mob's existence
and will safely cancel if the mob dies, despawns, or transitions into a flinching state.

```lua
function x_mob_core.schedule(self: table, delay: number, tag: string, callback: function)
```

**Parameters:**

* `self` (`table`): Mob entity reference
* `delay` (`number`): Time in seconds
* `tag` (`string`): Identifier string, useful for cancellation or debugging
* `callback` (`function`): The function to execute, taking `self` as argument

#### `x_mob_core.set_armor_groups`

Sets or updates armor groups on a mob while maintaining engine immortal protection.

```lua
function x_mob_core.set_armor_groups(self: table|ObjectRef, groups: table<string, number>)
```

**Parameters:**

* `self` (`table|ObjectRef`): Mob entity instance or ObjectRef
* `groups` (`table<string, number>`): Armor groups (e.g. { fleshy = 80 })

#### `x_mob_core.set_target`

Sets a mob's target and emits the on_mob_target event if changed.

```lua
function x_mob_core.set_target(self: table, target: ObjectRef|nil)
  -> changed: boolean
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `target` (`ObjectRef|nil`): Target entity or player

**Returns:**

* `changed` (`boolean`): True if target changed

#### `x_mob_core.set_texture`

Sets a mob's active texture variation by index.

```lua
function x_mob_core.set_texture(self: table|ObjectRef, id: integer, variations?: table[])
  -> applied: string[]|nil
```

**Parameters:**

* `self` (`table|ObjectRef`): Mob entity instance or ObjectRef
* `id` (`integer`): Texture variation index
* `variations` (`table[]?`): Optional explicit variations list

**Returns:**

* `applied` (`string[]|nil`): The applied textures array

#### `x_mob_core.transition_to`

Transitions an entity to a new state machine state, invoking exit and enter hooks.

```lua
function x_mob_core.transition_to(self: MobStateContext, new_state: string|"attacking"|"combat"|"dying"|"fleeing"...(+6))
```

**Parameters:**

* `self` (`MobStateContext`): Mob instance context table
* `new_state` (`string|"attacking"|"combat"|"dying"|"fleeing"...(+6)`): Target state name

#### `x_mob_core.unregister_step_hook`

Unregisters a previously registered step middleware hook by unique identifier name.

```lua
function x_mob_core.unregister_step_hook(name: string)
```

**Parameters:**

* `name` (`string`): Unique hook identifier to remove (e.g. "mymod:freeze_aura")

---

## Navigation & Pathfinding API

Time-sliced coroutine A* pathfinding, binary min-heap priority queue, pre-cached content ID lookups, and spatial memory blackboard.

#### `x_mob_core.find_path`

Queues an asynchronous time-sliced coroutine A* path search with a strict 1.5ms per-tick CPU budget.

```lua
function x_mob_core.find_path(start_pos: Vector, target_pos: Vector, abilities?: MobMovementDef, callback: fun(path: Vector[]|nil), mob_height?: number)
```

**Parameters:**

* `start_pos` (`Vector`): Starting world position
* `target_pos` (`Vector`): Target world position
* `abilities` (`MobMovementDef?`): Locomotion and traversal abilities (swim, climb, doors)
* `callback` (`fun(path: Vector[]|nil)`): Function invoked when path search completes
* `mob_height` (`number?`): Vertical clearance in nodes (default: 2)

#### `x_mob_core.find_path_sync`

Executes a synchronous A* path search.

```lua
function x_mob_core.find_path_sync(start_pos: Vector, target_pos: Vector, abilities?: MobMovementDef, mob_height?: number)
  -> path: Vector[]|nil
```

**Parameters:**

* `start_pos` (`Vector`): Starting world position
* `target_pos` (`Vector`): Target world position
* `abilities` (`MobMovementDef?`): Locomotion and traversal abilities (swim, climb, doors)
* `mob_height` (`number?`): Vertical clearance in nodes (default: 2)

**Returns:**

* `path` (`Vector[]|nil`): Solved waypoint path array or nil if unreachable

---

## Motor & Steering Controller API

Autonomous steering behaviors, surface climbing, liquid swimming, idle and wander routines, raycast player perception, tactical retreat, and velocity damping.

#### `x_mob_core.find_nearest_shore_pos`

Finds the nearest dry walkable shoreline node adjacent to water within max_radius.

```lua
function x_mob_core.find_nearest_shore_pos(pos: Vector, max_radius?: number)
  -> shore_pos: Vector|nil
```

**Parameters:**

* `pos` (`Vector`): Starting position (usually in water)
* `max_radius` (`number?`): Maximum search radius in blocks (default: 16)

**Returns:**

* `shore_pos` (`Vector|nil`): Nearest dry shore coordinate, or nil if none found

#### `x_mob_core.halt_horizontal_velocity`

Halts horizontal velocity of a mob entity while preserving vertical motion/gravity and liquid buoyancy.

```lua
function x_mob_core.halt_horizontal_velocity(self: table)
```

**Parameters:**

* `self` (`table`): Entity instance

#### `x_mob_core.is_aquatic_mob`

Checks if an entity is an aquatic mob (fish, shoal, etc.) that swims freely in liquid.

```lua
function x_mob_core.is_aquatic_mob(self: table)
  -> is_aquatic: boolean
```

**Parameters:**

* `self` (`table`): Entity instance

**Returns:**

* `is_aquatic` (`boolean`)

#### `x_mob_core.retreat_from`

Executes tactical retreat steering away from a target position.

```lua
function x_mob_core.retreat_from(self: table, target_pos: Vector, speed?: number)
  -> is_retreating: boolean
```

**Parameters:**

* `self` (`table`): Entity instance
* `target_pos` (`Vector`): World position to flee from
* `speed` (`number?`): Movement speed multiplier

**Returns:**

* `is_retreating` (`boolean`): Whether retreat movement is actively executing

#### `x_mob_core.scan_for_player`

Scans for living players within radius using field of view and raycast line-of-sight checks.

```lua
function x_mob_core.scan_for_player(self: table, scan_radius?: number, eye_height?: number)
  -> player: ObjectRef|nil
```

**Parameters:**

* `self` (`table`): Entity instance
* `scan_radius` (`number?`): Detection radius in nodes
* `eye_height` (`number?`): Vertical eye offset

**Returns:**

* `player` (`ObjectRef|nil`): Nearest visible living player or nil

#### `x_mob_core.set_horizontal_velocity`

Sets horizontal velocity of a mob entity along a given yaw while preserving vertical motion/gravity.

```lua
function x_mob_core.set_horizontal_velocity(self: table, speed: number, yaw: number)
```

**Parameters:**

* `self` (`table`): Entity instance
* `speed` (`number`): Horizontal movement speed
* `yaw` (`number`): Orientation angle in radians

#### `x_mob_core.step_move_or_idle`

Advances directional steering locomotion towards destination or target entity.

```lua
function x_mob_core.step_move_or_idle(self: table, dtime: number, move_anim?: string, anim_speed?: number, idle_anim?: string)
  -> is_moving: boolean
```

**Parameters:**

* `self` (`table`): Entity instance
* `dtime` (`number`): Step delta time
* `move_anim` (`string?`): Movement animation track name
* `anim_speed` (`number?`): Animation speed multiplier
* `idle_anim` (`string?`): Idle animation track name

**Returns:**

* `is_moving` (`boolean`): Whether the mob is actively moving

#### `x_mob_core.step_wander_or_idle`

Advances ambient idle or wandering locomotion state for an entity.

```lua
function x_mob_core.step_wander_or_idle(self: table, dtime: number, walk_anim?: string, idle_anim?: string)
  -> is_moving: boolean
```

**Parameters:**

* `self` (`table`): Entity instance
* `dtime` (`number`): Step delta time
* `walk_anim` (`string?`): Walking animation track name
* `idle_anim` (`string?`): Idle animation track name

**Returns:**

* `is_moving` (`boolean`): Whether the mob is currently walking

---

## Animation Subsystem API

Skeletal animation playback, modern glTF named multi-track blending, playback speed scaling, and loop synchronization.

#### `x_mob_core.play_animation`

Dispatches skeletal animation to an object using glTF tracks with fallback to legacy frame ranges.

```lua
function x_mob_core.play_animation(obj: ObjectRef, track_name: string, params?: AnimationParams)
  -> success: boolean
```

**Parameters:**

* `obj` (`ObjectRef`): Target entity ObjectRef
* `track_name` (`string`): Named glTF animation track identifier
* `params` (`AnimationParams?`): Playback options (speed, loop, blend, priority, force)

**Returns:**

* `success` (`boolean`): Whether animation playback was successfully dispatched

#### `x_mob_core.stop_animation`

Stops current animation tracks on an ObjectRef.

```lua
function x_mob_core.stop_animation(obj: ObjectRef, track_name?: string)
```

**Parameters:**

* `obj` (`ObjectRef`): Target entity ObjectRef
* `track_name` (`string?`): Optional specific track to stop

---

## Multi-Agent Pack, Swarm & Shoal Coordination API

Multi-agent squad hierarchies, leader-follower tracking, orphan adoption, spatial leash tethering, regroup locomotion, threat alerts, 3D Boids spatial separation with horizontal anti-stacking bias, aerial swarm flocking and vortex dive-bomb combat, aquatic schooling, and democratic leader election.

#### `x_mob_core.add_follower`

Registers a follower under a pack leader.

```lua
function x_mob_core.add_follower(leader_self: table, follower_obj: ObjectRef, force?: boolean)
  -> added: boolean
```

**Parameters:**

* `leader_self` (`table`): Leader mob instance
* `follower_obj` (`ObjectRef`): Follower entity object
* `force` (`boolean?`): If true, bypasses max_followers capacity limit (default: false)

**Returns:**

* `added` (`boolean`): True if follower was newly registered, false if already present, full, or invalid

#### `x_mob_core.adopt_nearby_orphans`

Searches nearby area to adopt orphans or re-link separated followers.

```lua
function x_mob_core.adopt_nearby_orphans(leader_self: table, search_radius?: number)
```

**Parameters:**

* `leader_self` (`table`): Leader mob instance
* `search_radius` (`number?`): Radius to search in nodes (default: 32.0)

#### `x_mob_core.alert_nearby_allies`

Broadcasts threat alert to nearby pack members or allies within radius.

```lua
function x_mob_core.alert_nearby_allies(pos: Vector, radius?: number, target: ObjectRef, max_allies?: integer)
```

**Parameters:**

* `pos` (`Vector`): Center position to broadcast threat from
* `radius` (`number?`): Alert radius in nodes (default: 16.0)
* `target` (`ObjectRef`): Threat target to engage
* `max_allies` (`integer?`): Max allies to alert (default: 4)

#### `x_mob_core.broadcast_threat`

Broadcasts alert to nearby pack members or allies when taking damage or spotting an enemy.
Directly assigns `ent.target = target` and switches unengaged allies to `"combat"`.
Note: This is an imperative one-shot function requiring a valid living `ObjectRef`.
For automated damage and death rallying with spatial memory investigation (navigating
to disturbance coordinates even without line of sight), use declarative `swarm_alert`
in the mob definition instead.

```lua
function x_mob_core.broadcast_threat(self: table, target: ObjectRef, radius?: number, max_allies?: integer)
```

**Parameters:**

* `self` (`table`): Mob instance
* `target` (`ObjectRef`): Threat target
* `radius` (`number?`): Alert radius in nodes (default: 16.0)
* `max_allies` (`integer?`): Max allies to alert (default: 4)

#### `x_mob_core.calculate_repulsion`

Calculates 3D Boids spatial separation with horizontal anti-stacking bias.

```lua
function x_mob_core.calculate_repulsion(self: table, pos: Vector, radius?: number, strength?: number, horizontal_bias?: boolean)
  -> sep_x: number
  2. sep_y: number
  3. sep_z: number
```

**Parameters:**

* `self` (`table`): Mob instance
* `pos` (`Vector`): World position
* `radius` (`number?`): Repulsion radius (default: 2.2)
* `strength` (`number?`): Push force multiplier (default: 2.8)
* `horizontal_bias` (`boolean?`): If true, prevents vertical totem pole stacking (default: true)

**Returns:**

* `sep_x` (`number`)
* `sep_y` (`number`)
* `sep_z` (`number`)

#### `x_mob_core.check_leash`

Checks if a follower has exceeded its leash distance from its leader.

```lua
function x_mob_core.check_leash(follower_self: table)
  -> is_leashed: boolean
  2. leader_pos: Vector|nil
  3. dist: number
```

**Parameters:**

* `follower_self` (`table`): Follower mob instance

**Returns:**

* `is_leashed` (`boolean`): True if within leash limit, false if leashed/separated
* `leader_pos` (`Vector|nil`): Position of leader if valid
* `dist` (`number`): Distance to leader

#### `x_mob_core.clean_followers`

Cleans invalid or dead follower objects from a leader's roster and returns alive count.

```lua
function x_mob_core.clean_followers(leader_self: table)
  -> count: integer
  2. alive_followers: table
```

**Parameters:**

* `leader_self` (`table`): Leader mob instance

**Returns:**

* `count` (`integer`): Alive follower count
* `alive_followers` (`table`): Array of living follower ObjectRefs

#### `x_mob_core.elect_successor`

Democratic leader election: surviving pack, swarm, or shoal members elect the first surviving peer as new leader.

```lua
function x_mob_core.elect_successor(self: table, search_radius?: number)
  -> success: boolean
```

**Parameters:**

* `self` (`table`): Mob instance
* `search_radius` (`number?`): Radius to search for surviving mates (default: 24.0)

**Returns:**

* `success` (`boolean`): True if a new leader was established

#### `x_mob_core.handle_leader_death`

Disbands the pack and notifies all followers when the leader dies.

```lua
function x_mob_core.handle_leader_death(leader_self: table)
```

**Parameters:**

* `leader_self` (`table`): Leader mob instance

#### `x_mob_core.rally_followers`

Rallies all pack followers to attack a shared target.

```lua
function x_mob_core.rally_followers(leader_self: table, target: ObjectRef)
```

**Parameters:**

* `leader_self` (`table`): Leader mob instance
* `target` (`ObjectRef`): Target entity

#### `x_mob_core.relink_follower`

Follower searches nearby area to re-link with its pack leader if separated.

```lua
function x_mob_core.relink_follower(follower_self: table, search_radius?: number)
```

**Parameters:**

* `follower_self` (`table`): Follower mob instance
* `search_radius` (`number?`): Radius to search in nodes (default: 32.0)

#### `x_mob_core.remove_follower`

Removes a follower object from a leader's roster.

```lua
function x_mob_core.remove_follower(leader_self: table, follower_obj: ObjectRef)
```

**Parameters:**

* `leader_self` (`table`): Leader mob instance
* `follower_obj` (`ObjectRef`): Follower entity object

#### `x_mob_core.spawn_initial_followers`

Adopts nearby orphans and spawns missing followers radially around the leader.

```lua
function x_mob_core.spawn_initial_followers(leader_self: table, follower_type?: string, max_count?: integer, spawn_radius?: number)
```

**Parameters:**

* `leader_self` (`table`): Leader mob instance
* `follower_type` (`string?`): Entity technical name (default: leader_self.pack_follower_type)
* `max_count` (`integer?`): Target follower count (default: leader_self.pack_max_followers or 3)
* `spawn_radius` (`number?`): Radial spawn distance (default: 1.5)

#### `x_mob_core.step_flock`

Advances ambient swarm flocking locomotion.

```lua
function x_mob_core.step_flock(self: table, dtime: number, def: table)
  -> is_handled: boolean
```

**Parameters:**

* `self` (`table`): Mob instance
* `dtime` (`number`): Step delta time
* `def` (`table`): Mob definition table

**Returns:**

* `is_handled` (`boolean`)

#### `x_mob_core.step_regroup`

Handles locomotion for a follower returning to assemble with its pack leader.

```lua
function x_mob_core.step_regroup(self: table, dtime: number, move_anim?: string, speed_mult?: number)
  -> is_regrouping: boolean
```

**Parameters:**

* `self` (`table`): Follower mob instance
* `dtime` (`number`): Step delta time
* `move_anim` (`string?`): Movement animation (default: "walk")
* `speed_mult` (`number?`): Speed multiplier (default: 1.25)

**Returns:**

* `is_regrouping` (`boolean`): True if still actively regrouping, false if reached leader or leader lost

#### `x_mob_core.step_swarm`

Advances master swarm AI step (flocking when idle, vortex and dive-bombs in combat).

```lua
function x_mob_core.step_swarm(self: table, dtime: number, def: table)
  -> is_handled: boolean
```

**Parameters:**

* `self` (`table`): Mob instance
* `dtime` (`number`): Step delta time
* `def` (`table`): Mob definition table

**Returns:**

* `is_handled` (`boolean`)

#### `x_mob_core.step_swarm_combat`

Advances coordinated swarm combat locomotion (vortex holding pattern and dive-bomb runs).

```lua
function x_mob_core.step_swarm_combat(self: table, dtime: number, def: table)
  -> is_handled: boolean
```

**Parameters:**

* `self` (`table`): Mob instance
* `dtime` (`number`): Step delta time
* `def` (`table`): Mob definition table

**Returns:**

* `is_handled` (`boolean`)

---

## Combat, Damage, Factions & Loot API

Tool capability damage calculations, weapon wear, water knockback dampening, directional damage particles, damage indicator flashing, child and arrow detachment on death, faction allegiance and enemy checks, predictive intercept aiming, and declarative parabolic loot drops.

#### `x_mob_core.apply_envelop`

Attaches a 3D rectangular sleeve visual envelop to a target entity or player.

```lua
function x_mob_core.apply_envelop(target: ObjectRef, def: table)
  -> envelop_obj: ObjectRef
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity
* `def` (`table`): Envelop configuration table (`id`, `duration`, `texture`, `on_step`, `on_remove`)

**Returns:**

* `envelop_obj` (`ObjectRef`): Attached envelop entity ObjectRef

#### `x_mob_core.apply_status_effect`

Applies or refreshes a status effect on a target entity or player.
Handles compound physics overrides, camera FOV factor overrides, DoT ticks, armor penetration, visual envelop sleeve binding, and HUD screen vignettes.

```lua
function x_mob_core.apply_status_effect(target: ObjectRef, effect_def: StatusEffectDef)
  -> result: ObjectRef|boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity
* `effect_def` (`StatusEffectDef`): Status effect definition table

**Returns:**

* `result` (`ObjectRef|boolean`): Attached envelop object if visual sleeve bound, or true on success

#### `x_mob_core.are_allies`

Checks whether two entities or players are allies according to faction and pack rules.

```lua
function x_mob_core.are_allies(a: any, b: any)
  -> are_allies: boolean
```

**Parameters:**

* `a` (`any`): First object, entity, or projectile
* `b` (`any`): Second object, entity, or projectile

**Returns:**

* `are_allies` (`boolean`): True if both entities share allegiance

#### `x_mob_core.are_enemies`

Checks whether two entities or players are enemies.

```lua
function x_mob_core.are_enemies(a: any, b: any)
  -> are_enemies: boolean
```

**Parameters:**

* `a` (`any`): First object, entity, or projectile
* `b` (`any`): Second object, entity, or projectile

**Returns:**

* `are_enemies` (`boolean`): True if enemies

#### `x_mob_core.calculate_punch_damage`

Calculates damage from tool capabilities and mob armor groups, and applies wear to weapon.

```lua
function x_mob_core.calculate_punch_damage(self: table, puncher?: ObjectRef, time_from_last_punch?: number, tool_capabilities?: table, dir?: Vector, damage_override?: number)
  -> dmg: number
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `puncher` (`ObjectRef?`): Punching entity
* `time_from_last_punch` (`number?`): Time since last punch in seconds
* `tool_capabilities` (`table?`): Wielded tool capabilities
* `dir` (`Vector?`): Punch direction vector
* `damage_override` (`number?`): Direct damage override

**Returns:**

* `dmg` (`number`): Calculated damage integer

#### `x_mob_core.clear_damage`

Clears any active damage flash on an entity, restoring its clean base texture modifier.

```lua
function x_mob_core.clear_damage(obj: ObjectRef)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object

#### `x_mob_core.clear_regen`

Clears any active health regeneration flash on an entity, restoring its clean base texture modifier.

```lua
function x_mob_core.clear_regen(obj: ObjectRef)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object

#### `x_mob_core.dampen_water_knockback`

Dampens punch knockback when an entity is struck inside water.

```lua
function x_mob_core.dampen_water_knockback(self: table)
```

**Parameters:**

* `self` (`table`): Mob entity instance

#### `x_mob_core.detach_attached_children`

Detaches and drops all attached child objects (arrows, passengers, accessories) from a mob when it dies.

```lua
function x_mob_core.detach_attached_children(mob_obj: ObjectRef)
```

**Parameters:**

* `mob_obj` (`ObjectRef`): The mob entity ObjectRef

#### `x_mob_core.drop_item`

Spawns a single item with a physical parabolic launch arc.

```lua
function x_mob_core.drop_item(origin: Vector, itemstack: string|ItemStack, angle?: number, options?: DropOptions)
  -> item_obj: ObjectRef|nil
```

**Parameters:**

* `origin` (`Vector`): World coordinate of spawn origin
* `itemstack` (`string|ItemStack`): Item or ItemStack to drop
* `angle` (`number?`): Launch azimuth in radians
* `options` (`DropOptions?`): Physics and effect overrides

**Returns:**

* `item_obj` (`ObjectRef|nil`): Spawned item entity or nil

#### `x_mob_core.drop_items`

Evaluates a declarative drop table and launches all dropped items in a radial fountain.

```lua
function x_mob_core.drop_items(origin: Vector, drops: (string|DropEntryDef)[], options?: DropOptions)
  -> spawned_objects: ObjectRef[]
```

**Parameters:**

* `origin` (`Vector`): World coordinate of spawn origin
* `drops` (`(string|DropEntryDef)[]`): List of drop table entries
* `options` (`DropOptions?`): Physics, particle, and sound overrides

**Returns:**

* `spawned_objects` (`ObjectRef[]`): List of successfully spawned item ObjectRefs

#### `x_mob_core.get_factions`

Returns the active faction set for an entity or player.

```lua
function x_mob_core.get_factions(obj: any)
  -> factions: table<string, boolean>
```

**Parameters:**

* `obj` (`any`): ObjectRef or mob entity

**Returns:**

* `factions` (`table<string, boolean>`): Set of active factions

#### `x_mob_core.get_knockback_mult`

Returns the effective knockback multiplier for an ObjectRef or LuaEntity.

```lua
function x_mob_core.get_knockback_mult(obj: table|ObjectRef)
  -> multiplier: number
```

**Parameters:**

* `obj` (`table|ObjectRef`): Target object or mob entity

**Returns:**

* `multiplier` (`number`): (1.0 for players, mob-defined knockback_mult, or 1.0 default)

#### `x_mob_core.handle_punch`

Universal combat punch intake handler applying damage, threat, knockback, and death callbacks.

```lua
function x_mob_core.handle_punch(self: table, puncher?: ObjectRef, time_from_last_punch?: number, tool_capabilities?: table, dir?: Vector, damage?: number, def?: table)
  -> handled: boolean
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `puncher` (`ObjectRef?`): Attacking entity
* `time_from_last_punch` (`number?`): Elapsed time in seconds
* `tool_capabilities` (`table?`): Weapon capabilities
* `dir` (`Vector?`): Punch impulse direction
* `damage` (`number?`): Base damage override
* `def` (`table?`): Entity definition table

**Returns:**

* `handled` (`boolean`)

#### `x_mob_core.hide_health_bar`

Hides or removes the dynamic overhead health bar on a mob entity.

```lua
function x_mob_core.hide_health_bar(self: table, remove_completely?: boolean)
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `remove_completely` (`boolean?`): If true, destroys child entity; otherwise sets is_visible = false

#### `x_mob_core.indicate_damage`

Flashes the entity red briefly upon taking damage for visual feedback.

```lua
function x_mob_core.indicate_damage(obj: ObjectRef)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object to flash

#### `x_mob_core.indicate_regen`

Flashes the entity with a visible texture overlay (white by default) upon health regeneration.

```lua
function x_mob_core.indicate_regen(obj: ObjectRef, color?: string, duration?: number)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object to flash
* `color` (`string?`): Optional custom colorize string (default: "^[colorize:#FFFFFF60")
* `duration` (`number?`): Optional duration in seconds (default: 0.25)

#### `x_mob_core.is_projectile`

Agnostically checks whether a LuaEntity is classified as a projectile or arrow.

```lua
function x_mob_core.is_projectile(ent: table)
  -> is_projectile: boolean
```

**Parameters:**

* `ent` (`table`): LuaEntity table

**Returns:**

* `is_projectile` (`boolean`)

#### `x_mob_core.is_valid_projectile_target`

Validates whether an object is a targetable enemy for a projectile or shooter mob.
Filters out dropped items (__builtin:item), falling nodes, utility entities, shooter self-hits, and allies.

```lua
function x_mob_core.is_valid_projectile_target(source_or_proj: table|ObjectRef, obj: ObjectRef, options?: ProjectileTargetOptions)
  -> is_valid: boolean
```

**Parameters:**

* `source_or_proj` (`table|ObjectRef`): Projectile entity instance, shooter mob, or ObjectRef
* `obj` (`ObjectRef`): Target object to test
* `options` (`ProjectileTargetOptions?`): Optional configuration table

**Returns:**

* `is_valid` (`boolean`): True if target is attackable, false if ignored

#### `x_mob_core.perform_melee_attack`

Executes an instantaneous melee strike against a target entity.
Applies fleshy punch damage and triggers the configured on_strike callback or custom perform_attack override.

```lua
function x_mob_core.perform_melee_attack(self: table, target: ObjectRef, dir: Vector, def?: table, m_cfg?: MeleeConfigDef)
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `target` (`ObjectRef`): Target entity to punch
* `dir` (`Vector`): Strike impulse direction vector
* `def` (`table?`): Mob definition table
* `m_cfg` (`MeleeConfigDef?`): Melee configuration table override

#### `x_mob_core.predict_aim`

Predicts target intercept position and direction based on target velocity and projectile speed.

```lua
function x_mob_core.predict_aim(origin: Vector, tgt_pos: Vector, tgt_vel?: Vector, proj_speed: number)
  -> predicted_pos: Vector
  2. dir: Vector
```

**Parameters:**

* `origin` (`Vector`): Projectile launch origin
* `tgt_pos` (`Vector`): Current target position
* `tgt_vel` (`Vector?`): Target velocity vector
* `proj_speed` (`number`): Projectile travel speed

**Returns:**

* `predicted_pos` (`Vector`): Predicted intercept position
* `dir` (`Vector`): Normalized direction vector towards predicted position

#### `x_mob_core.show_health_bar`

Displays or updates the dynamic overhead health bar on a mob entity.

```lua
function x_mob_core.show_health_bar(self: table, cur_hp?: number, max_hp?: number)
  -> shown: boolean
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `cur_hp` (`number?`): Current health (defaults to self.hp)
* `max_hp` (`number?`): Maximum health (defaults to self.hp_max)

**Returns:**

* `shown` (`boolean`): True if health bar is shown or updated

#### `x_mob_core.spawn_damage_particles`

Spawns directional combat damage particles according to mob settings or global preferences.

```lua
function x_mob_core.spawn_damage_particles(obj: ObjectRef, puncher?: ObjectRef, dir?: Vector, damage?: number, def?: table)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity receiving damage
* `puncher` (`ObjectRef?`): Attacker ObjectRef
* `dir` (`Vector?`): Strike/knockback direction vector
* `damage` (`number?`): Damage dealt
* `def` (`table?`): Entity definition table

#### `x_mob_core.step_melee`

Advances declarative melee combat for an entity during its step tick.
Validates attack range, raycast line-of-sight, halts horizontal velocity, turns mob to face target,
plays attack animation and sound, and schedules delayed punch execution with reach tolerance.

```lua
function x_mob_core.step_melee(self: table, dtime: number, def: table)
  -> handled: boolean
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `dtime` (`number`): Step delta time
* `def` (`table`): Entity definition table containing melee configuration

**Returns:**

* `handled` (`boolean`): True if melee logic handled combat, halting movement

#### `x_mob_core.step_projectile`

Processes a standard projectile flight step: ballistics rotation, lifetime expiry,
continuous raycasting, proximity collision, and impact handling.

```lua
function x_mob_core.step_projectile(self: table, dtime: number, options?: ProjectileStepOptions)
  -> hit: boolean
  2. hit_obj: ObjectRef|nil
  3. hit_pos: Vector|nil
```

**Parameters:**

* `self` (`table`): Projectile LuaEntity instance
* `dtime` (`number`): Step delta time
* `options` (`ProjectileStepOptions?`): Projectile configuration options

**Returns:**

* `hit` (`boolean`): True if the projectile impacted an object or solid node
* `hit_obj` (`ObjectRef|nil`): Direct object impacted, if any
* `hit_pos` (`Vector|nil`): World coordinate of the impact

#### `x_mob_core.step_shooter`

Advances declarative ranged combat (shooter) for an entity during its step tick.
Validates range distance, raycast line-of-sight, performs tactical kiting if target enters min_range,
dispatches charge windup callbacks, calculates aim lead trajectory, and spawns projectile entities.

```lua
function x_mob_core.step_shooter(self: table, dtime: number, def: table)
  -> handled: boolean
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `dtime` (`number`): Step delta time
* `def` (`table`): Entity definition table containing shooter configuration

**Returns:**

* `handled` (`boolean`): True if shooter logic handled combat, halting or kiting movement

#### `x_mob_core.strip_damage_mod`

Strips transient damage flash colorize modifiers from a texture modifier string.

```lua
function x_mob_core.strip_damage_mod(mod?: string)
  -> clean_mod: string
```

**Parameters:**

* `mod` (`string?`): Original texture modifier string

**Returns:**

* `clean_mod` (`string`): Texture modifier without damage colorize

#### `x_mob_core.strip_flash_mod`

Strips all transient combat damage and health regeneration flash colorize modifiers.

```lua
function x_mob_core.strip_flash_mod(mod?: string)
  -> clean_mod: string
```

**Parameters:**

* `mod` (`string?`): Original texture modifier string

**Returns:**

* `clean_mod` (`string`): Texture modifier without damage or regen colorize

#### `x_mob_core.strip_regen_mod`

Strips transient health regeneration flash colorize modifiers from a texture modifier string.

```lua
function x_mob_core.strip_regen_mod(mod?: string)
  -> clean_mod: string
```

**Parameters:**

* `mod` (`string?`): Original texture modifier string

**Returns:**

* `clean_mod` (`string`): Texture modifier without regen colorize

#### `x_mob_core.update_health_bar`

Forces an update of the health bar based on current mob HP.

```lua
function x_mob_core.update_health_bar(self: table)
  -> shown: boolean
```

**Parameters:**

* `self` (`table`): Mob entity instance

**Returns:**

#### `x_mob_core.clear_status_effects`

Clears all active status effects and restores baseline physics on a target player or mob entity.

```lua
function x_mob_core.clear_status_effects(target: ObjectRef)
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity

#### `x_mob_core.get_damage_multiplier`

Retrieves the compound damage multiplier across all active status effects on a target (e.g. 1.35 for brittle / crystallize).

```lua
function x_mob_core.get_damage_multiplier(target: ObjectRef)
  -> multiplier: number
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity

**Returns:**

* `multiplier` (`number`): Compound damage multiplier (default: 1.0)

#### `x_mob_core.get_status_effects`

Retrieves all active status effect records for a target.

```lua
function x_mob_core.get_status_effects(target: ObjectRef)
  -> effects: table<string, StatusEffectDef>|nil
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity

**Returns:**

* `effects` (`table<string, StatusEffectDef>|nil`): Active status effects map

#### `x_mob_core.has_envelop`

Checks whether a target currently has an attached visual 3D envelop sleeve.

```lua
function x_mob_core.has_envelop(target: ObjectRef)
  -> has_envelop: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity

**Returns:**

* `has_envelop` (`boolean`): True if target has an attached envelop

#### `x_mob_core.has_status_effect`

Checks whether a target currently has a specific active status effect.

```lua
function x_mob_core.has_status_effect(target: ObjectRef, effect_id: string)
  -> has_effect: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity
* `effect_id` (`string`): Unique status effect identifier

**Returns:**

* `has_effect` (`boolean`): True if effect is currently active

#### `x_mob_core.is_enveloped`

Checks whether a target currently has an active visual envelop sleeve attached. Alias of `x_mob_core.has_envelop`.

```lua
function x_mob_core.is_enveloped(target: ObjectRef)
  -> is_enveloped: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity

**Returns:**

* `is_enveloped` (`boolean`): True if target has an active envelop sleeve

#### `x_mob_core.is_rooted`

Checks whether a target entity or player currently has an active root status effect or has speed factor <= 0.

```lua
function x_mob_core.is_rooted(target: ObjectRef)
  -> is_rooted: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity

**Returns:**

* `is_rooted` (`boolean`): True if target is rooted or has zero movement speed

#### `x_mob_core.register_vignette`

Registers a reusable custom screen vignette configuration for a specific status effect.

```lua
function x_mob_core.register_vignette(id: string, def: table)
```

**Parameters:**

* `id` (`string`): Effect identifier
* `def` (`table`): Vignette definition (`texture`, `colorize`, `opacity`, `z_index`)

#### `x_mob_core.remove_envelop`

Detaches and removes the active visual 3D envelop sleeve from a target.

```lua
function x_mob_core.remove_envelop(target: ObjectRef)
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity

#### `x_mob_core.remove_status_effect`

Removes an active status effect from a target, restoring physics modifiers, detaching envelops, and clearing HUD vignettes.

```lua
function x_mob_core.remove_status_effect(target: ObjectRef, effect_id: string)
  -> success: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity
* `effect_id` (`string`): Unique status effect identifier

**Returns:**

* `success` (`boolean`): True if the effect was removed

#### `x_mob_core.set_default_vignette`

Overrides the fallback default base texture for fullscreen HUD screen vignettes across all effects.

```lua
function x_mob_core.set_default_vignette(texture: string)
```

**Parameters:**

* `texture` (`string`): Fallback texture asset name (default: "x_mob_core_vignette.png")

#### `x_mob_core.set_vignette_prominence_multiplier`

Sets the global vignette prominence / opacity scaling multiplier (e.g. `1.0` = default, `1.5` = extra prominent high-contrast mode for bright daylight).

```lua
function x_mob_core.set_vignette_prominence_multiplier(multiplier: number)
```

**Parameters:**

* `multiplier` (`number`): Scaling factor clamped to `[0.1, 3.0]`.

#### `x_mob_core.get_vignette_prominence_multiplier`

Retrieves the current active global vignette prominence scaling multiplier.

```lua
function x_mob_core.get_vignette_prominence_multiplier(): number
```

**Returns:**

* `multiplier` (`number`): Active prominence multiplier (default: `1.0`).

---

## Spawner Engine API

Natural mob spawning engine, environmental condition validation, light and elevation limits, active entity caps, and cohesive group spawning.

#### `x_mob_core.register_spawn`

Registers a mob definition for natural map generation and environment spawning.

```lua
function x_mob_core.register_spawn(mob_name: string, def: SpawnConfig|SpawnDefinition)
```

**Parameters:**

* `mob_name` (`string`): Registered entity technical name (e.g. "x_mobs:spider")
* `def` (`SpawnConfig|SpawnDefinition`): Environmental spawning parameters and condition filters

#### `x_mob_core.spawn_mob`

Spawns a single mob entity with action logging and returns the object reference.

```lua
function x_mob_core.spawn_mob(pos: Vector, mob_name: string, staticdata?: string)
  -> obj: ObjectRef|nil
```

**Parameters:**

* `pos` (`Vector`): Spawn world position
* `mob_name` (`string`): Registered mob technical name
* `staticdata` (`string?`): Optional serialized staticdata

**Returns:**

* `obj` (`ObjectRef|nil`): Spawned entity ObjectRef or nil on failure

#### `x_mob_core.spawn_mob_group`

Spawns a cohesive group of mobs scattered safely around a center point according to a spawn definition.

```lua
function x_mob_core.spawn_mob_group(spawn_pos: Vector, def: string|table|SpawnDefinition, source?: string)
  -> count: integer
```

**Parameters:**

* `spawn_pos` (`Vector`): World center position
* `def` (`string|table|SpawnDefinition`): Spawn definition table or entity technical name
* `source` (`string?`): Optional spawner mechanism identifier (default: "Custom Spawning")

**Returns:**

* `count` (`integer`): Number of mobs successfully spawned

---

## Audio & Sound Subsystem API

Positional audio dispatcher, spatial distance attenuation, and pitch variation for mob sound cues.

#### `x_mob_core.play_sound`

Plays a configured sound type for a mob instance with positional audio and pitch variation.

```lua
function x_mob_core.play_sound(self: table|userdata, sound_type: string, overrides?: table)
  -> sound_handle: integer|nil
```

**Parameters:**

* `self` (`table|userdata`): Mob entity instance or ObjectRef
* `sound_type` (`string`): Category ("hurt", "death", "random", "attack", "alert") or technical sound name
* `overrides` (`table?`): Optional overrides (gain, distance, pitch, pos, object, to_player, loop)

**Returns:**

* `sound_handle` (`integer|nil`): Luanti sound handle or nil if not played

#### `x_mob_core.stop_sound`

Stops a playing sound handle.

```lua
function x_mob_core.stop_sound(handle?: integer)
```

**Parameters:**

* `handle` (`integer?`): Luanti sound handle returned by play_sound or core.sound_play

---

## Core Utilities, Spatial Queries & Event Bus API

RFC 4122 v4 UUID generation, raycast line-of-sight checks, player vitality verification, solid ground detection, headroom scanning, passable air clearance, and decoupled pub/sub event bus.

#### `x_mob_core.avoid_solid_nodes`

Verifies if a target coordinate is safely in passable air; if blocked, returns an adjusted clear position.

```lua
function x_mob_core.avoid_solid_nodes(target_pos: Vector, safe_origin: Vector, look_dir?: Vector)
  -> clear_pos: Vector
```

**Parameters:**

* `target_pos` (`Vector`): Desired 3D coordinate
* `safe_origin` (`Vector`): Known safe origin or anchor (e.g. player or mob origin)
* `look_dir` (`Vector?`): Optional directional vector to tuck behind if in tight enclosure

**Returns:**

* `clear_pos` (`Vector`): Adjusted safe 3D coordinate

#### `x_mob_core.emit`

Emits an event to all registered listeners on the x_mob_core pub-sub event bus.

```lua
function x_mob_core.emit(event_name: string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_spawn", ...any)
```

**Parameters:**

* `event_name` (`string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_spawn"`): Event identifier
* `?` (`any`): Arguments passed to listeners

#### `x_mob_core.find_ground_level`

Finds the top surface Y coordinate of the solid walkable ground below a given 3D position.

```lua
function x_mob_core.find_ground_level(x: number, start_y: number, z: number, max_down?: number)
  -> ground_y: number|nil
```

**Parameters:**

* `x` (`number`): X world coordinate
* `start_y` (`number`): Y world coordinate
* `z` (`number`): Z world coordinate
* `max_down` (`number?`): Maximum distance to search downwards (default: 36)

**Returns:**

* `ground_y` (`number|nil`): Top surface Y of solid node, or nil if none found

#### `x_mob_core.generate_uuid`

Generates an RFC 4122 Version 4 compliant UUID.
Uses Luanti OS-backed SecureRandom for guaranteed uniqueness, with math.random fallback.

```lua
function x_mob_core.generate_uuid()
  -> uuid: string
```

**Returns:**

* `uuid` (`string`)

#### `x_mob_core.get_ground_y`

Finds the topmost solid ground surface near a given coordinate.

```lua
function x_mob_core.get_ground_y(pos: Vector, max_down?: number, max_up?: number, walkable_only?: boolean)
  -> ground_y: number|nil
```

**Parameters:**

* `pos` (`Vector`): Position to check
* `max_down` (`number?`): Maximum distance to search downwards (default: 8)
* `max_up` (`number?`): Maximum distance to search upwards (default: 3)
* `walkable_only` (`boolean?`): If true, requires walkable non-liquid node with headroom (default: true)

**Returns:**

* `ground_y` (`number|nil`): Top surface height of highest ground node, or nil

#### `x_mob_core.get_headroom`

Scans vertically upwards from origin to check distance to the first solid ceiling node.

```lua
function x_mob_core.get_headroom(origin: Vector, max_check?: number)
  -> headroom: number
```

**Parameters:**

* `origin` (`Vector`): Base position (e.g. foot or center coordinate)
* `max_check` (`number?`): Maximum nodes to scan upward (default: 4.0)

**Returns:**

* `headroom` (`number`): Distance to first walkable ceiling node, or max_check if open sky

#### `x_mob_core.is_player_alive`

Checks if an ObjectRef is a connected living player or valid entity with HP > 0.

```lua
function x_mob_core.is_player_alive(target: ObjectRef)
  -> is_alive: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target entity or player ObjectRef

**Returns:**

* `is_alive` (`boolean`): True if reference is valid and alive

#### `x_mob_core.line_of_sight`

Performs an unobstructed line of sight check between two points using Raycast.

```lua
function x_mob_core.line_of_sight(p1: Vector, p2: Vector)
  -> is_clear: boolean
```

**Parameters:**

* `p1` (`Vector`): Starting position
* `p2` (`Vector`): Ending position

**Returns:**

* `is_clear` (`boolean`): True if ray has no solid node obstruction

#### `x_mob_core.listen`

Registers an event listener callback on the x_mob_core pub-sub event bus.

```lua
function x_mob_core.listen(event_name: string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_spawn", callback: fun(...any))
  -> id: integer
```

**Parameters:**

* `event_name` (`string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_spawn"`): Event identifier (e.g. "on_mob_death", "on_mob_spawn", "on_mob_target")
* `callback` (`fun(...any)`): Callback function invoked when event is emitted

**Returns:**

* `id` (`integer`): Listener registration token

#### `x_mob_core.pick_ground_waypoint`

Picks a ground-anchored wander waypoint near current position over solid walkable nodes.

```lua
function x_mob_core.pick_ground_waypoint(current_pos: Vector, origin?: Vector, radius?: number, min_dist?: number, max_dist?: number, hover_offset?: number)
  -> waypoint: Vector|nil
```

**Parameters:**

* `current_pos` (`Vector`): Current mob world position
* `origin` (`Vector?`): Center origin of wander boundary (default: current_pos)
* `radius` (`number?`): Maximum wander radius from origin (default: 10.0)
* `min_dist` (`number?`): Minimum step distance from current position (default: 3.0)
* `max_dist` (`number?`): Maximum step distance from current position (default: 7.5)
* `hover_offset` (`number?`): Vertical offset above detected ground (default: 1.4)

**Returns:**

* `waypoint` (`Vector|nil`): Ground-anchored target position or nil

#### `x_mob_core.unlisten`

Unregisters an event listener from the x_mob_core pub-sub event bus.

```lua
function x_mob_core.unlisten(event_name: string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_spawn", id: integer)
  -> success: boolean
```

**Parameters:**

* `event_name` (`string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_spawn"`): Event identifier
* `id` (`integer`): Listener registration token returned by listen()

**Returns:**

* `success` (`boolean`): True if listener was found and removed

---

## Registries & State Tables

| Registry / Table | Type | Description |
| :--- | :--- | :--- |
| `x_mob_core.animator` | `table` | Animation Subsystem Skeletal animation player |
| `x_mob_core.combat` | `table<string, table>` | Combat Subsystems Combat calculation, knockback, damage effects, and child detachment subsystems |
| `x_mob_core.events` | `table` | Pub-sub event dispatcher subsystem |
| `x_mob_core.fast_pathfinder` | `table` | Time-sliced coroutine A* pathfinding engine |
| `x_mob_core.lifecycle` | `table<string, table>` | Lifecycle & Entity Registration Entity registration wrapper and state machine |
| `x_mob_core.min_heap` | `MinHeap` | Navigation & Pathfinding Binary min-heap priority queue |
| `x_mob_core.mob_memory` | `table` | Short-term mob memory buffer |
| `x_mob_core.motor` | `table<string, table>` | Motor Subsystems & Navigation Coordinator Modular motor subsystems and navigation coordinator |
| `x_mob_core.pack` | `table<string, table>` | Multi-Agent Pack Coordination & Swarm Intelligence Multi-agent squad, coordination, and swarm subsystems |
| `x_mob_core.path_cache` | `table` | Pre-cached node content ID registry for zero-overhead pathfinding |
| `x_mob_core.registered_mobs` | `table<string, MobRegistrationDef>` | Registry of all active mob definitions |
| `x_mob_core.registered_spawns` | `SpawnDefinition[]` | Registry of all active natural spawn configurations |
| `x_mob_core.sound` | `SoundSubsystem` | Audio & Sound Subsystem |
| `x_mob_core.spawning` | `table` | Spawner Engine Natural spawning engine and spawn registry |
| `x_mob_core.utils` | `table` | Core utilities and event dispatcher Core utilities subsystem (UUID generation, line-of-sight, player vitality) |
