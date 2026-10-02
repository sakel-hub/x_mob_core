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
| `broadcast_threat` | `function CoordinationSubsystem.broadcast_threat(self: table, target: ObjectRef, radius?: number, max_allies?: integer)` | Broadcasts alert to nearby pack members or allies when taking damage or spotting an enemy @*param* `self` — Mob instance @*param* `target` — Threat target @*param* `radius` — Alert radius in nodes (default: 16.0) @*param* `max_allies` — Max allies to alert (default: 4) |
| `calculate_repulsion` | `function CoordinationSubsystem.calculate_repulsion(self: table, pos: Vector, radius?: number, strength?: number, ignore_behind?: boolean, min_sep?: number, vertical_factor?: number, horizontal_bias?: boolean)   -> sep_x: number   2. sep_y: number   3. sep_z: number` | Calculates 3D multi-agent Boids spatial repulsion with anti-stacking and soft/hard buffers @*param* `self` — Mob instance @*param* `pos` — Current world position @*param* `radius` — Repulsion radius (default: 2.0) @*param* `strength` — Push force multiplier (default: 2.4) @*param* `ignore_behind` — If true, ignores entities trailing behind self.object @*param* `min_sep` — Minimum hard penetration separation (default: radius * 0.6) @*param* `vertical_factor` — Vertical attenuation factor (default: 0.1) @*param* `horizontal_bias` — If true, applies horizontal anti-stacking bias (default: true) |
| `check_leash` | `function CoordinationSubsystem.check_leash(follower_self: table)   -> is_leashed: boolean   2. leader_pos: Vector\|nil   3. dist: number` | Checks if a follower has exceeded its leash distance from its leader @*param* `follower_self` — Follower mob instance @*return* `is_leashed` — True if within leash limit, false if leashed/separated @*return* `leader_pos` — Position of leader if valid @*return* `dist` — Distance to leader |
| `rally_followers` | `function CoordinationSubsystem.rally_followers(leader_self: table, target: ObjectRef)` | Rallies all pack followers to attack a shared target @*param* `leader_self` — Leader mob instance @*param* `target` — Target entity |
| `step_regroup` | `function CoordinationSubsystem.step_regroup(self: table, dtime: number, move_anim?: string, speed_mult?: number)   -> is_regrouping: boolean` | Handles movement for a follower returning to assemble with its pack leader @*param* `self` — Follower mob instance @*param* `dtime` — Step delta time @*param* `move_anim` — Movement animation (default: "walk") @*param* `speed_mult` — Speed multiplier (default: 1.25) @*return* `is_regrouping` — True if still actively regrouping, false if reached leader or leader lost |
| `trigger_cowardice_panic` | `function CoordinationSubsystem.trigger_cowardice_panic(death_pos: Vector, mob_name: string, radius?: number, panic_duration?: number, danger_dmg?: number)` | Triggers cowardice panic in nearby fellow mobs when a pack member dies @*param* `death_pos` — Position of the deceased mob @*param* `mob_name` — Name of the entity to match (e.g. "x_mobs:fallen_minion") @*param* `radius` — Search radius (default: 12.0) @*param* `panic_duration` — Duration in seconds for flee state (default: 4.0) @*param* `danger_dmg` — Perceived damage recorded in memory (default: 10) |

### `CustomStateDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `enter` | `fun(self: table)?` | Called when state is entered |
| `exit` | `fun(self: table)?` | Called when state is exited |
| `step` | `fun(self: table, dtime: number):string\|nil` | State step tick; return state name to transition |

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
| `clear_regen` | `function EffectsSubsystem.clear_regen(obj: ObjectRef)` | Clears any active regeneration flash on an entity, restoring its clean base texture modifier @*param* `obj` — Entity object |
| `indicate_damage` | `function EffectsSubsystem.indicate_damage(obj: ObjectRef)` | Flashes the entity red briefly upon taking damage for visual feedback. Prevents duplicate stacking, clears competing regen flashes, and handles rapid hits cleanly. @*param* `obj` — Entity object |
| `indicate_regen` | `function EffectsSubsystem.indicate_regen(obj: ObjectRef, color?: string, duration?: number)` | Flashes the entity with a visible texture overlay (white by default) upon health regeneration. Yields precedence to active damage flashes. @*param* `obj` — Entity object @*param* `color` — Optional texture modifier overlay (default: `^[colorize:#FFFFFF60`) @*param* `duration` — Duration in seconds (default: 0.25) |
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
| `register_mob` | `function EntityWrapperSubsystem.register_mob(name: string, def: table)` | Registers a mob definition with standardized physical properties and lifecycle integration. @*param* `name` — Entity name (e.g. "x_mobs:spider") @*param* `def` — Entity definition table |
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

### `KnockbackSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `dampen_water_knockback` | `function KnockbackSubsystem.dampen_water_knockback(self: table)` | Dampens punch knockback when an entity is struck inside water @*param* `self` — Mob entity instance |
| `get_multiplier` | `function KnockbackSubsystem.get_multiplier(obj: table\|ObjectRef)   -> multiplier: number` | Returns the effective knockback multiplier for an entity or ObjectRef @*param* `obj` — Target object or mob entity @*return* `multiplier` — (1.0 for players, mob-defined knockback_mult, or 1.0 default) |

### `LootSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `drop_item` | `function LootSubsystem.drop_item(origin: Vector, itemstack: string\|ItemStack, angle?: number, options?: DropOptions)   -> item_obj: ObjectRef\|nil` | Spawns a single item with a physical parabolic launch arc @*param* `origin` — World coordinate of spawn origin @*param* `itemstack` — Item or ItemStack to drop @*param* `angle` — Launch azimuth in radians @*param* `options` — Physics and effect overrides @*return* `item_obj` — Spawned item entity or nil |
| `drop_items` | `function LootSubsystem.drop_items(origin: Vector, drops: (string\|DropEntryDef)[], options?: DropOptions)   -> spawned_objects: ObjectRef[]` | Evaluates a declarative drop table and launches all dropped items in a radial fountain @*param* `origin` — World coordinate of spawn origin @*param* `drops` — List of drop table entries @*param* `options` — Physics, particle, and sound overrides @*return* `spawned_objects` — List of successfully spawned item ObjectRefs |
| `spawn_mob_drops` | `function LootSubsystem.spawn_mob_drops(self: table, killer?: ObjectRef, drops: (string\|DropEntryDef)[], options?: DropOptions)   -> spawned_objects: ObjectRef[]` | Convenience method to drop items from a dying mob instance @*param* `self` — Mob entity instance @*param* `killer` — Killer entity or player @*param* `drops` — Mob drop definitions @*param* `options` — Runtime drop overrides @*return* `spawned_objects` — List of spawned item ObjectRefs |

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
| `apply_liquid_buoyancy` | `function` |  |
| `check_and_open_forward_doors` | `function` |  |
| `check_corridor_line_of_sight` | `function` |  |
| `check_ground_line_of_sight` | `function` |  |
| `check_in_liquid` | `function` |  |
| `dir_to_surface_rotation` | `function` |  |
| `find_adjacent_surface` | `function` |  |
| `get_node` | `function MobAISubsystem.get_node(pos: any)   -> unknown` |  |
| `get_node_or_nil` | `function MobAISubsystem.get_node_or_nil(pos: any)   -> unknown\|nil` |  |
| `halt_horizontal_velocity` | `function` |  |
| `handle_mob_fleeing` | `function` |  |
| `handle_mob_movement` | `function` |  |
| `has_wall_collision` | `function` |  |
| `interpolate_rotation` | `function` |  |
| `is_door_open` | `function` |  |
| `is_openable_door` | `function` |  |
| `is_step_safe` | `function` |  |
| `is_valid_stand_pos` | `function` |  |
| `mob_memory` | `table` |  |
| `register_pathfinding_mob` | `function MobAISubsystem.register_pathfinding_mob(name: string, def: table)` | Entity Registration Helper Wraps standard mob definition with optimized pathfinding motor controller @*param* `name` — Entity technical name (e.g. "x_mobs:smart_zombie") @*param* `def` — Entity definition table |
| `retreat_from` | `function MobAISubsystem.retreat_from(self: table, target_pos: Vector, speed?: number)   -> success: boolean` | Executes a safe kiting retreat away from a target position with cliff/obstacle guard @*param* `self` — Mob instance @*param* `target_pos` — Threat / target world position @*param* `speed` — Movement speed (default: self.pursuit_speed or self.walk_speed or 3.0) @*return* `success` — True if a safe retreat direction was found and applied |
| `scan_for_player` | `function MobAISubsystem.scan_for_player(self: table, scan_radius?: number, eye_height?: number)   -> nearest_player: ObjectRef\|nil   2. nearest_dist: number\|nil` | Scans for the nearest valid living player within range and direct line of sight @*param* `self` — Mob instance @*param* `scan_radius` — Max search radius (default: self.aggro_radius or 16.0) @*param* `eye_height` — Mob eye height offset (default: self.eye_offset or 1.5) |
| `step_move_or_idle` | `function MobAISubsystem.step_move_or_idle(self: table, dtime: number, move_anim?: string, anim_speed?: number, idle_anim?: string)   -> nav: table\|nil` | Updates navigation movement and dispatches walk/run or idle animation @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `move_anim` — Movement animation (default: "walk") @*param* `anim_speed` — Animation speed (default: 1.0) @*param* `idle_anim` — Idle animation (default: "idle") @*return* `nav` — Navigation state |
| `step_wander_or_idle` | `function MobAISubsystem.step_wander_or_idle(self: table, dtime: number, walk_anim?: string, idle_anim?: string)   -> table\|nil` | Executes wander navigation or idle holding when no active target is present @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `walk_anim` — Custom walk animation name (default: "walk") @*param* `idle_anim` — Custom idle animation name (default: "idle") |
| `try_open_door` | `function` |  |
| `try_open_door_at_pos` | `function` |  |
| `update_navigation` | `function MobAISubsystem.update_navigation(self: table, dtime: number)   -> status: table` | Updates entity navigation, scanning, line-of-sight, and path execution @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*return* `status` — Locomotion status {moving = boolean, speed = number, has_los = boolean} |

### `MobAnimationDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `loop` | `boolean?` | Whether to loop animation by default |
| `speed` | `number?` | Playback speed multiplier (default: 1.0) |
| `track` | `string` | Named glTF animation track |

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

### `MobMemorySubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `broadcast_alert` | `function MobMemorySubsystem.broadcast_alert(self: table, alert_pos: Vector, threat?: number, radius?: number, max_allies?: number)   -> alerted_count: integer` | Broadcasts a swarm alert to nearby allies of the same species Configurable via self.swarm_alert = {enabled = true, radius = 10.0, max_allies = 3} @*param* `self` — Entity instance sending the alert @*param* `alert_pos` — Position of the threat @*param* `threat` — Threat magnitude (default: 5.0) @*param* `radius` — Alert radius in nodes (default: 10.0) @*param* `max_allies` — Maximum allies to alert (default: 3) @*return* `alerted_count` — Number of allies alerted |
| `clear_danger_memory` | `function MobMemorySubsystem.clear_danger_memory(self: table)` | Clears all active danger memories (used on combat re-engagement or panic exit) @*param* `self` — Entity instance |
| `clear_target_memory` | `function MobMemorySubsystem.clear_target_memory(self: table)` | Clears target memory explicitly @*param* `self` — Entity instance |
| `clear_unreachable_target` | `function MobMemorySubsystem.clear_unreachable_target(self: table, target_obj: ObjectRef)` | Clears unreachable status for a target (e.g. when punched by that target) @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity |
| `evaluate_heading_bias` | `function MobMemorySubsystem.evaluate_heading_bias(self: table, candidate_dir: Vector, current_pos: Vector, current_time?: number)   -> score: number` | Evaluates a candidate movement direction against danger, novelty, and blocked memory Returns a scalar fitness score (higher is better) Utilizes a zero-allocation heading evaluation cache to avoid duplicate vector and sqrt computations @*param* `self` — Entity instance @*param* `candidate_dir` — Candidate heading direction (normalized) @*param* `current_pos` — Current mob position @*param* `current_time` — Current timestamp @*return* `score` — Fitness score |
| `get_danger_repulsion_vector` | `function MobMemorySubsystem.get_danger_repulsion_vector(self: table, current_pos: Vector, current_time?: number)   -> repulsion: Vector` | Calculates a spatial repulsion vector away from all active danger spots Uses inverse-square distance weighting @*param* `self` — Entity instance @*param* `current_pos` — Current mob position @*param* `current_time` — Current timestamp @*return* `repulsion` — Normalized 3D repulsive vector or {x=0, y=0, z=0} |
| `get_exploration_bias_vector` | `function MobMemorySubsystem.get_exploration_bias_vector(self: table, current_pos: Vector)   -> novelty: Vector` | Calculates an exploration novelty vector pointing away from recently visited positions Prevents ping-pong oscillations in corridors and dead ends @*param* `self` — Entity instance @*param* `current_pos` — Current mob position @*return* `novelty` — Normalized 3D exploration vector or {x=0, y=0, z=0} |
| `get_lkp_target` | `function MobMemorySubsystem.get_lkp_target(self: table, max_age?: number, current_time?: number)   -> lkp: Vector\|nil` | Retrieves active Last Known Position if within the 8.0s pursuit window @*param* `self` — Entity instance @*param* `max_age` — Maximum age in seconds (default: 8.0) @*param* `current_time` — Current timestamp @*return* `lkp` — Last known position or nil if expired |
| `init_memory` | `function MobMemorySubsystem.init_memory(self: table)   -> table` | Initializes a zero-allocation working memory buffer on an entity instance @*param* `self` — Entity instance |
| `is_target_unreachable` | `function MobMemorySubsystem.is_target_unreachable(self: table, target_obj: ObjectRef, current_time?: number)   -> is_unreachable: boolean` | Checks if a target is currently marked as unreachable @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity @*param* `current_time` — Current timestamp @*return* `is_unreachable` — True if target is unreachable and on cooldown |
| `record_blocked_spot` | `function MobMemorySubsystem.record_blocked_spot(self: table, blocked_pos: Vector, duration?: number, current_time?: number)` | Records a blocked position or cliff deadlock @*param* `self` — Entity instance @*param* `blocked_pos` — Position that could not be traversed @*param* `duration` — Duration in seconds (default: 8.0) @*param* `current_time` — Current timestamp |
| `record_danger` | `function MobMemorySubsystem.record_danger(self: table, danger_pos: Vector, threat_level: number, duration?: number, current_time?: number)` | Records a danger source (damage taken, enemy position, hazard) @*param* `self` — Entity instance @*param* `danger_pos` — World coordinates of the threat @*param* `threat_level` — Magnitude of the threat (e.g. damage amount) @*param* `duration` — Duration in seconds before expiration (default: 12.0) @*param* `current_time` — Current timestamp |
| `record_target_sighting` | `function MobMemorySubsystem.record_target_sighting(self: table, target_obj: ObjectRef, target_pos: Vector, current_time?: number)` | Records or updates target sighting and Last Known Position @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity @*param* `target_pos` — Target position @*param* `current_time` — Optional current time or timestamp |
| `record_trail_step` | `function MobMemorySubsystem.record_trail_step(self: table, current_pos: Vector, dtime: number, current_time?: number)` | Records a visited world position into the circular trail buffer Throttled to 1.0s intervals to minimize samples @*param* `self` — Entity instance @*param* `current_pos` — Current mob position @*param* `dtime` — Step delta time @*param* `current_time` — Current timestamp |
| `record_unreachable_target` | `function MobMemorySubsystem.record_unreachable_target(self: table, target_obj: ObjectRef, duration?: number, current_time?: number)` | Records a target as temporarily unreachable (e.g. across impassable water or chasm) @*param* `self` — Entity instance @*param* `target_obj` — Target player or entity @*param* `duration` — Duration in seconds before re-evaluating (default: 12.0) @*param* `current_time` — Current timestamp |
| `update_health_regen` | `function MobMemorySubsystem.update_health_regen(self: table, dtime: number, flee_ratio?: number, return_ratio?: number, regen_rate?: number)   -> is_fleeing: boolean` | Updates low-HP tactical fleeing and passive health regeneration When HP recovers to return threshold, exits fleeing state @*param* `self` — Entity instance @*param* `dtime` — Step delta time @*param* `flee_ratio` — HP ratio to enter fleeing (default: 0.25) @*param* `return_ratio` — HP ratio to exit fleeing (default: 0.60) @*param* `regen_rate` — HP regenerated per second while fleeing (default: 0.5) @*return* `is_fleeing` — Whether the mob is currently in fleeing state |

### `MobPackDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `follower_type` | `string?` | Expected entity name of the followers |
| `leader_type` | `string?` | Expected entity name of the leader |
| `leash_distance` | `number?` | Distance before followers regroup (default: 18.0) |
| `max_followers` | `integer?` | Max followers for a leader (default: 3) |
| `pack_id` | `string?` | Optional existing pack UUID |
| `regroup_distance` | `number?` | Target distance when regrouping to leader (default: 4.0) |
| `role` | `("leader"\|"member")?` | Role within the pack |
| `spawn_on_init` | `boolean?` | Whether leader auto-spawns initial followers on activate |

### `MobRegistrationDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `armor_groups` | `table<string, number>?` | Luanti armor groups (e.g. {fleshy = 80}) |
| `faction` | `(string\|string[])?` | Faction tag or list of faction tags (default: "monsters") |
| `factions` | `(string\|string[])?` | Alias for faction |
| `friendly_fire` | `boolean?` | Whether allies/same-faction can damage this mob (default: false) |
| `initial_properties` | `table` | Luanti ObjectRef properties (hp_max, collisionbox, mesh, visual_size, textures, etc.) |
| `knockback_mult` | `number?` | Knockback impulse multiplier (0 for unyielding/immune, default: 1.5) |
| `textures` | `(string\|(string[])[]\|string[])?` | Texture or variations list (preferred in initial_properties) |

### `MobSoundDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `alert` | `(string\|SoundConfigDef)?` | Sound played when a target is first acquired |
| `attack` | `(string\|SoundConfigDef)?` | Sound played on melee or ranged strike |
| `base` | `string?` | Default sound-group name used as fallback for all categories |
| `death` | `(string\|SoundConfigDef)?` | Sound played on lethal damage |
| `distance` | `number?` | Global default hear distance in nodes (default: 24.0) |
| `gain` | `number?` | Global default volume multiplier (default: 1.0) |
| `hurt` | `(string\|SoundConfigDef)?` | Sound played on non-lethal damage |
| `max_hear_distance` | `number?` | Alias for distance in nodes |
| `pitch_jitter` | `number?` | Global default pitch jitter factor (default: 0.05) |
| `random` | `(string\|SoundConfigDef)?` | Periodic ambient sound played during wander/idle |

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
| `allow_allies` | `boolean?` | If true, permits colliding with and damaging faction allies |
| `allow_players` | `boolean?` | If false, ignores players during collision raycasts (default: true) |
| `damage` | `number?` | Impact damage dealt to entity if self._damage is unset (default: 5) |
| `ignore_entities` | `(string[]|table<string, boolean>)?` | Specific entity names to ignore |
| `lifetime` | `number?` | Maximum flight duration before expiration (default: 4.0) |
| `on_hit` | `fun(self: table, hit_obj: ObjectRef?, hit_pos: Vector)?` | General impact callback called for any hit |
| `on_hit_node` | `fun(self: table, hit_pos: Vector, node: table)?` | Callback triggered when impacting a solid node |
| `on_hit_object` | `fun(self: table, hit_obj: ObjectRef, hit_pos: Vector, dir: Vector)?` | Custom object punch callback |
| `on_step` | `fun(self: table, dtime: number, pos: Vector)?` | Step callback triggered every frame during flight |
| `radius` | `number?` | Proximity collision fallback radius in nodes (default: 1.5) |
| `remove_on_hit` | `boolean?` | Whether to remove projectile entity on impact (default: true) |
| `rotate` | `boolean?` | Whether to automatically orient visual model along velocity vector (default: true) |

### `ProjectileTargetOptions`

| Field | Type | Description |
| :--- | :--- | :--- |
| `allow_allies` | `boolean?` | If true, permits targeting faction allies (default: false) |
| `allow_players` | `boolean?` | If false, ignores human players (default: true) |
| `ignore_entities` | `(string[]|table<string, boolean>)?` | Technical entity names to ignore (e.g. {"x_mobs:archer_arrow"}) |

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
| `get_water_column_bounds` | `function` |  |
| `init_entity` | `function ShoalSubsystem.init_entity(self: table, def: table, data: table)` | Initializes an entity's shoal role, index, and state on activation @*param* `self` — Mob instance @*param* `def` — Mob definition table @*param* `data` — Deserialized static data table |
| `is_navigable_water` | `function` |  |
| `is_safe_deep_water` | `function` |  |
| `is_water_node` | `function` |  |
| `on_action_end` | `function ShoalSubsystem.on_action_end(self: table, _def: table)` | Action end hook to transition attacking mobs back to swimming @*param* `self` — Mob instance @*param* `_def` — Mob definition table |
| `perform_attack` | `function ShoalSubsystem.perform_attack(self: table, target: ObjectRef, dir: Vector, _def: table)` | Executes predatory school strike with animation, rostrum damage, and recoil @*param* `self` — Mob instance @*param* `target` — Target entity @*param* `dir` — Strike direction @*param* `_def` — Mob definition table |
| `step` | `function ShoalSubsystem.step(self: table, dtime: number, def: table)   -> is_handled: boolean` | Master step dispatcher for schooling entities @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table |
| `step_combat` | `function ShoalSubsystem.step_combat(self: table, dtime: number, def: table, pos: Vector)   -> is_handled: boolean` | Advances coordinated combat locomotion when school has engaged a threat @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table @*param* `pos` — Current world position |
| `step_follower` | `function ShoalSubsystem.step_follower(self: table, dtime: number, def: table, pos: Vector)   -> is_handled: boolean` | Advances formation slot anchor steering and client velocity interpolation for school followers @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table @*param* `pos` — Current world position |
| `step_leader` | `function ShoalSubsystem.step_leader(self: table, dtime: number, def: table, pos: Vector)   -> is_handled: boolean` | Advances ambient swimming locomotion and lookahead boundary avoidance for the school leader @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*param* `def` — Mob definition table @*param* `pos` — Current world position |
| `sync_school_threat` | `function ShoalSubsystem.sync_school_threat(self: table)` | Synchronizes threat targets across the entire school to maintain cohesion @*param* `self` — Mob instance |

### `ShooterConfigDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `animation` | `string?` | Animation track name played when shooting (default: "attack") |
| `cooldown` | `number?` | Attack cooldown between shots in seconds (default: 2.0) |
| `damage` | `number?` | Projectile damage (default: 3) |
| `fire_delay` | `number?` | Delay before projectile is released in seconds (default: 0.4) |
| `fire_duration` | `number?` | Duration mob holds shooting pose in seconds (default: 1.0) |
| `min_range` | `number?` | Minimum distance threshold under which mob retreats (default: 0.0) |
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
| `max_hear_distance` | `number?` | Alias for distance in nodes |
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
| `add_follower` | `function SquadSubsystem.add_follower(self: table, follower_obj: ObjectRef, force?: boolean)   -> added: boolean` | Registers a follower under a leader @*param* `self` — Leader mob instance @*param* `follower_obj` — Follower entity object @*param* `force` — If true, bypasses max_followers capacity limit (default: false) @*return* `added` — True if follower was newly registered, false if already present, full, or invalid |
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

### `StateMachineSubsystem`

| Field | Type | Description |
| :--- | :--- | :--- |
| `transition_to` | `function StateMachineSubsystem.transition_to(self: table, new_state: string)` | Transitions an entity to a new state, invoking exit and enter hooks @*param* `self` — Mob instance @*param* `new_state` — Target state name |
| `update` | `function StateMachineSubsystem.update(self: table, dtime: number)   -> handled: boolean` | Updates the current custom state if one is active @*param* `self` — Mob instance @*param* `dtime` — Step delta time @*return* `handled` — True if handled by a custom state, false otherwise |

### `StepHook`

| Field | Type | Description |
| :--- | :--- | :--- |
| `handler` | `fun(self: table, dtime: number, def: table, moveresult?: table):boolean\|nil` |  |
| `name` | `string` | Identifier of the hook |
| `priority` | `integer` | Execution order (lower runs first) |

### `StepPipeline`

| Field | Type | Description |
| :--- | :--- | :--- |
| `execute` | `function StepPipeline.execute(self: table, dtime: number, def: table, moveresult?: table)   -> handled: boolean` | Executes registered step hooks sequentially in priority order. @*param* `self` — Mob entity instance @*param* `dtime` — Step delta time @*param* `def` — Entity definition table @*param* `moveresult` — Engine move result @*return* `handled` — True if intercepted by any hook |
| `register_step_hook` | `function StepPipeline.register_step_hook(name: string, priority: integer, handler: fun(self: table, dtime: number, def: table, moveresult?: table):boolean\|nil)` | Registers a step middleware hook executed during handle_core_step. If the handler returns `true`, subsequent step handling is intercepted (early return). @*param* `name` — Unique hook identifier @*param* `priority` — Execution order (e.g. 10 for pre-combat, 50 for combat, 100 for post) |
| `unregister_step_hook` | `function StepPipeline.unregister_step_hook(name: string)` | Unregisters a previously registered step hook. |

### `SwarmAlertDef`

| Field | Type | Description |
| :--- | :--- | :--- |
| `enabled` | `boolean?` | Whether pack threat alerting is enabled |
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
| `get_water_column_bounds` | `function UtilsSubsystem.get_water_column_bounds(pos: Vector, _pad?: number\|table)   -> safe_min_y: number, safe_max_y: number, is_shallow: boolean, surface_y: number, floor_y: number` | Determines safe submerged vertical range for an entity in the water column. Strictly guarantees minimum 2-node clearance below the air surface. @*param* `pos` — World position @*param* `_pad` — Optional padding @*return* `safe_min_y` — Lowest safe Y coordinate @*return* `safe_max_y` — Highest safe Y coordinate @*return* `is_shallow` — True if water depth is under 3.5 nodes @*return* `surface_y` — Highest water block Y @*return* `floor_y` — Lowest water block Y |
| `is_player_alive` | `function UtilsSubsystem.is_player_alive(player: ObjectRef)   -> is_alive: boolean` | Checks if an ObjectRef is a valid living player or entity @*param* `player` — Target entity @*return* `is_alive` — True if player reference is valid and alive |
| `is_walkable_node` | `function UtilsSubsystem.is_walkable_node(pos_or_x: Vector\|number, y?: number, z?: number)   -> is_walkable: boolean` | Checks if a node at world coordinates or Vector represents walkable solid terrain @*param* `pos_or_x` — Vector or X world coordinate @*param* `y` — Optional Y world coordinate @*param* `z` — Optional Z world coordinate @*return* `is_walkable` — True if node is registered and walkable |
| `is_water_node` | `function UtilsSubsystem.is_water_node(pos_or_x: Vector\|number, y?: number, z?: number)   -> is_water: boolean` | Checks if a node at world coordinates or Vector represents water @*param* `pos_or_x` — Vector or X world coordinate @*param* `y` — Optional Y world coordinate @*param* `z` — Optional Z world coordinate @*return* `is_water` — True if node is in group:water |
| `line_of_sight` | `function UtilsSubsystem.line_of_sight(p1: Vector, p2: Vector)   -> is_clear: boolean` | Line of sight check between two points using native engine C++ ray traversal with liquid penetration support |
| `pick_ground_waypoint` | `function UtilsSubsystem.pick_ground_waypoint(current_pos: Vector, origin?: Vector, radius?: number, min_dist?: number, max_dist?: number, hover_offset?: number)   -> waypoint: Vector\|nil` | Picks a ground-anchored wander waypoint near current position over solid walkable nodes @*param* `current_pos` — Current mob world position @*param* `origin` — Center origin of wander boundary (default: current_pos) @*param* `radius` — Maximum wander radius from origin (default: 10.0) @*param* `min_dist` — Minimum step distance from current position (default: 3.0) @*param* `max_dist` — Maximum step distance from current position (default: 7.5) @*param* `hover_offset` — Vertical offset above detected ground (default: 1.4) @*return* `waypoint` — Ground-anchored target position or nil |
| `shallow_copy` | `function UtilsSubsystem.shallow_copy(tbl: <T:table>)   -> <T:table>` | Shallow copies a table |

---

## Type Aliases & Callbacks

| Type Alias | Signature / Definition |
| :--- | :--- |
| `CoreEventName` | `"on_mob_death"\|"on_mob_despawn"\|"on_mob_hurt"\|"on_mob_spawn"` |
| `EventListenerCallback` | `fun(...any)` |
| `PathfindingCallback` | `fun(path: Vector[]\|nil)` |

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

```lua
function x_mob_core.register_step_hook(name: string, priority: integer, handler: fun(self: table, dtime: number, def: table, moveresult?: table):boolean|nil)
```

**Parameters:**

* `name` (`string`): Unique hook identifier
* `priority` (`integer`): Execution order (lower runs first)
* `handler` (`fun(self: table, dtime: number, def: table, moveresult?: table):boolean|nil`)

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
function x_mob_core.transition_to(self: table, new_state: string)
```

**Parameters:**

* `self` (`table`): Mob instance
* `new_state` (`string`): Target state name

#### `x_mob_core.unregister_step_hook`

Unregisters a previously registered step middleware hook.

```lua
function x_mob_core.unregister_step_hook(name: string)
```

**Parameters:**

* `name` (`string`)

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

#### `x_mob_core.halt_horizontal_velocity`

Halts horizontal velocity of a mob entity while preserving vertical motion/gravity and liquid buoyancy.

```lua
function x_mob_core.halt_horizontal_velocity(self: table)
```

**Parameters:**

* `self` (`table`): Entity instance

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

#### `x_mob_core.indicate_damage`

Flashes the entity red briefly upon taking damage for visual feedback.

```lua
function x_mob_core.indicate_damage(obj: ObjectRef)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object to flash

#### `x_mob_core.is_valid_projectile_target`

Validates whether an object is a targetable enemy for a projectile or shooter mob. Automatically filters out invalid references, the projectile itself, the firing shooter, engine built-ins (`__builtin:item`, `__builtin:falling_node`), utility entities (`x_mob_core:health_bar`), sister projectiles, and faction allies.

```lua
function x_mob_core.is_valid_projectile_target(source_or_proj: any, obj: any, options?: ProjectileTargetOptions)
  -> is_valid: boolean
```

**Parameters:**

* `source_or_proj` (`any`): Firing mob or projectile instance
* `obj` (`any`): Candidate target ObjectRef
* `options` (`ProjectileTargetOptions?`): Target filtering options

**Returns:**

* `is_valid` (`boolean`): True if targetable enemy

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

#### `x_mob_core.step_projectile`

Steps a projectile entity in flight, handling visual rotation, lifetime expiration, continuous collision raycasting, proximity fallback hit detection, node collision, damage application, and step/impact callbacks.

```lua
function x_mob_core.step_projectile(self: table, dtime: number, options?: ProjectileStepOptions)
  -> hit: boolean
  2. hit_obj: ObjectRef|nil
  3. hit_pos: Vector|nil
```

**Parameters:**

* `self` (`table`): Projectile LuaEntity table
* `dtime` (`number`): Delta time in seconds
* `options` (`ProjectileStepOptions?`): Flight and collision options

**Returns:**

* `hit` (`boolean`): True if projectile collided with target or solid node, or expired
* `hit_obj` (`ObjectRef|nil`): Target object collided with
* `hit_pos` (`Vector|nil`): Impact location in world coordinates

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

#### `x_mob_core.indicate_regen`

Flashes the entity with a visible texture overlay (white by default, matching hurt flash feedback) upon health regeneration. Yields precedence to active damage flashes.

```lua
function x_mob_core.indicate_regen(obj: ObjectRef, color?: string, duration?: number)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object to flash
* `color` (`string?`): Optional texture modifier overlay (default: `"^[colorize:#FFFFFF60"`)
* `duration` (`number?`): Duration in seconds (default: `0.25`)

#### `x_mob_core.clear_regen`

Clears any active health regeneration flash on an entity, restoring its clean base texture modifier.

```lua
function x_mob_core.clear_regen(obj: ObjectRef)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object

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

---

## Health Regeneration & Fleeing API

Every mob in `x_mob_core` features built-in tactical fleeing and small health regeneration when running away (`0.5 HP/s` default) with visible white texture overlay feedback. Third-party mob developers can configure and override every aspect of health regeneration in their mob definition table (`def`):

### Configuration Options

```lua
x_mob_core.register_mob("mymod:custom_mob", {
    initial_properties = { hp_max = 50 },

    -- Structured health regeneration configuration (single source of truth)
    health_regen = {
        rate = 1.5,                  -- HP regenerated per second (default: 0.5)
        enabled = true,              -- Set false to disable health regeneration
        overlay = true,              -- White texture overlay flash on regen tick (default: true)
        overlay_color = "#FFFFFF60", -- Custom colorize modifier (e.g. green or holy gold)
        passive = false,             -- Set true to regenerate health continuously while idle
        can_flee = true,             -- Set false to prevent mob from ever fleeing
        flee_threshold = 12,         -- HP below which mob runs away (default: 25% max HP)
        flee_ratio = 0.25,           -- Flee HP ratio (e.g. 0.25 for 25% max HP)
        return_threshold = 30,       -- HP to exit fleeing and return to combat (default: 60% max HP)
        return_ratio = 0.60,         -- Return HP ratio (e.g. 0.60 for 60% max HP)
    },

    -- Callbacks
    on_regen_step = function(self, hp_added)
        -- Custom sound or particle effects on each heal tick
    end,
    on_return_to_fight = function(self)
        -- Triggered when mob recovers health above return threshold
    end,
})
```

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

## Miscellaneous Functions

#### `x_mob_core.hide_health_bar`

Hides or removes the dynamic overhead health bar on a mob entity.

```lua
function x_mob_core.hide_health_bar(self: table, remove_completely?: boolean)
```

**Parameters:**

* `self` (`table`): Mob entity instance
* `remove_completely` (`boolean?`): If true, destroys child entity; otherwise sets is_visible = false

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

#### `x_mob_core.update_health_bar`

Forces an update of the health bar based on current mob HP.

```lua
function x_mob_core.update_health_bar(self: table)
  -> shown: boolean
```

**Parameters:**

* `self` (`table`): Mob entity instance

**Returns:**

* `shown` (`boolean`): True if health bar was updated

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
| `x_mob_core.motor` | `table<string, table>` | Modular motor subsystems (node_cache, doors, surface, safety, locomotion, ai) |
| `x_mob_core.mob_memory` | `table` | Short-term mob memory buffer |
| `x_mob_core.pack` | `table<string, table>` | Multi-Agent Pack Coordination & Swarm Intelligence Multi-agent squad, coordination, and swarm subsystems |
| `x_mob_core.path_cache` | `table` | Pre-cached node content ID registry for zero-overhead pathfinding |
| `x_mob_core.registered_mobs` | `table<string, MobRegistrationDef>` | Registry of all active mob definitions |
| `x_mob_core.registered_spawns` | `SpawnDefinition[]` | Registry of all active natural spawn configurations |
| `x_mob_core.sound` | `SoundSubsystem` | Audio & Sound Subsystem |
| `x_mob_core.spawning` | `table` | Spawner Engine Natural spawning engine and spawn registry |
| `x_mob_core.utils` | `table` | Core utilities and event dispatcher Core utilities subsystem (UUID generation, line-of-sight, player vitality) |
