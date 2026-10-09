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
- [Status Effects, Envelops & Screen Vignettes API](#status-effects-envelops--screen-vignettes-api)
- [Spawner Engine API](#spawner-engine-api)
- [Audio & Sound Subsystem API](#audio--sound-subsystem-api)
- [Core Utilities, Spatial Queries & Event Bus API](#core-utilities-spatial-queries--event-bus-api)
- [Registries & State Tables](#registries--state-tables)

---

## Classes & Data Structures

### `ActiveEffectRecord`

Active status effect runtime tracking record on an afflicted player or entity.

| Field | Type | Description |
| :--- | :--- | :--- |
| `anti_heal` | `boolean?` | Whether health regeneration is suppressed during effect |
| `attack_multiplier` | `number?` | Outgoing damage multiplier (e.g. 1.35 for +35% attack power) |
| `caster` | `ObjectRef?` | Attacking entity or player source |
| `category` | `("buff"\|"debuff")?` | Polarity category for cleansing and dispelling |
| `chance` | `number?` | Optional trigger chance (fraction 0.0-1.0 or percentage 1-100; default: 100%) |
| `cleanse_debuffs` | `boolean?` | Whether active debuffs/DoTs/slows are purged upon application |
| `cleanse_in_water` | `boolean?` | Whether immersion in water immediately cleanses the effect |
| `damage` | `number?` | Damage per interval tick for DoT |
| `damage_multiplier` | `number?` | Incoming damage multiplier while afflicted (e.g. 1.35 for brittle, 0.6 for ironhide) |
| `damage_type` | `string?` | Damage group name for DoT (default: "fleshy") |
| `drain_hunger` | `number?` | Hunger or stamina units drained per tick via hunger_adapter |
| `duration` | `number` | Duration in seconds |
| `envelop` | `EnvelopConfig?` | Visual envelop configuration |
| `envelop_texture` | `string?` | Visual envelop sleeve texture asset |
| `fov_duration` | `number?` | Optional sub-duration for FOV effect in seconds (defaults to effect duration) |
| `fov_factor` | `number?` | Camera FOV multiplier (e.g. 0.85 for shockwave / tunnel vision) |
| `fov_transition` | `number?` | FOV transition smoothing time in seconds (default: 0.2) |
| `gravity_factor` | `number?` | Gravity fractional multiplier |
| `has_envelop` | `boolean` | Whether an envelop entity was attached |
| `heal` | `number?` | Health restored per interval tick for HoT (Health over Time) |
| `hud_vignette` | `(string\|VignetteConfig)?` | Fullscreen responsive screen vignette configuration |
| `id` | `string?` | Unique status effect identifier (e.g. "venom", "haste", "freeze", "ironhide") |
| `interval` | `number?` | Interval between DoT/HoT ticks in seconds (default: 1.0) |
| `jump_factor` | `number?` | Jump fractional multiplier (e.g. 0.0 to prevent jump) |
| `knockback_resilience` | `number?` | Knockback reduction factor (0.0 = full knockback, 1.0 = immovable) |
| `on_apply` | `fun(target: ObjectRef)?` | Callback when effect is first applied |
| `on_remove` | `fun(target: ObjectRef)?` | Callback when effect is removed or expires |
| `on_step` | `fun(dtime: number, target: ObjectRef)?` | Callback on step tick (forwarded to envelop) |
| `on_tick` | `fun(target: ObjectRef)?` | Callback on periodic DoT/HoT tick (e.g. particle spawner) |
| `particle_spawner` | `(ParticleSpawnerDef\|fun(target: ObjectRef):ParticleSpawnerDef)?` | Particle spawner definition or generator callback for periodic ticks. |
| `penetrate_armor` | `boolean?` | Whether DoT bypasses armor damage reduction (default: true) |
| `speed_factor` | `number?` | Movement speed fractional multiplier (e.g. 0.5 for 50% slow, 1.35 for haste) |
| `target` | `ObjectRef` | Target entity or player |
| `thorns` | `ThornsDef?` | Reactive thorns on melee attackers |
| `timer` | `number` | Remaining duration in seconds |
| `token` | `string\|integer` | Cancellation and refresh token |
| `type` | `("buff"\|"custom"\|"debuff"\|"dot"\|"root"...(+1))?` | Effect archetype ("root" halts movement and jump) |

### `AnimationParams`

Optional playback parameters for skeletal animations.

| Field | Type | Description |
| :--- | :--- | :--- |
| `blend` | `number?` | Blend duration in seconds (default: 0.15) |
| `force` | `boolean?` | Force restart track even if already playing |
| `loop` | `boolean?` | Whether to loop animation (default: true) |
| `priority` | `number?` | Animation track priority (default: 0) |
| `speed` | `number?` | Playback speed multiplier (default: 1.0) |

### `AuraPulseDef`

Periodic radius aura pulse specification applied to pack followers or nearby allies.

| Field | Type | Description |
| :--- | :--- | :--- |
| `effect` | `string\|StatusEffectDef` | Buff preset identifier or status effect definition |
| `id` | `string` | Unique aura identifier |
| `max_targets` | `integer?` | Maximum number of affected targets |
| `radius` | `number?` | Pulse effect radius in blocks (default: 16.0) |
| `sound` | `string?` | Audio cue played at caster position |
| `target` | `("allies"\|"pack_followers"\|"self")?` | Beneficiary selector (default: "pack_followers") |
| `vfx` | `(string\|fun(pos: Vector))?` | Visual effect trigger or callback |

### `CollisionInfo`

Detailed individual collision record from Luanti physical object movement.

| Field | Type | Description |
| :--- | :--- | :--- |
| `axis` | `"x"\|"y"\|"z"` | World axis along which collision occurred |
| `new_velocity` | `Vector` | Velocity vector of the entity after collision response |
| `node_pos` | `Vector?` | Coordinates of collided node when type == "node" |
| `object` | `ObjectRef?` | Reference to collided entity or player when type == "object" |
| `old_velocity` | `Vector` | Velocity vector of the entity before collision occurred |
| `plane` | `{ normal: Vector }?` | Collision contact plane normal if reported |
| `type` | `"node"\|"object"` | Type of collider impacted ("node" for voxel blocks, "object" for entities/players) |

### `CowardicePanicOptions`

Configuration options for cowardice panic triggers on pack member death.

| Field | Type | Description |
| :--- | :--- | :--- |
| `danger_dmg` | `number?` | Perceived damage recorded in danger memory (default: 10) |
| `panic_duration` | `number?` | Duration in seconds for flee state (default: 4.0) |
| `radius` | `number?` | Search radius for alerting fellow mobs (default: 12.0) |

### `CustomStateDef`

Custom state machine state handlers table.

| Field | Type | Description |
| :--- | :--- | :--- |
| `enter` | `fun(self: MobStateContext)?` | Called when state is entered |
| `exit` | `fun(self: MobStateContext)?` | Called when state is exited |
| `step` | `fun(self: MobStateContext, dtime: number):string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+7)` | State tick; return state name to transition |

### `DamageEffectDef`

Directional combat damage hit particle preset configuration.

| Field | Type | Description |
| :--- | :--- | :--- |
| `color` | `string?` | Hex color string override (e.g. "#8A0303") |
| `colors` | `string[]?` | Multi-shade hex color list override for texpool (e.g. {"#E0AAFF", "#C77DFF", "#9D4EDD"}) |
| `count` | `integer?` | Base particle droplet count (default: 8) |
| `enabled` | `boolean?` | Set to false to disable default core damage particles (default: true) |
| `scale` | `number?` | Particle size multiplier (default: 1.0) |
| `texture` | `string?` | Custom texture override (e.g. "[fill:3x3:#FF0000") |
| `type` | `(string\|"blood"\|"ichor"\|"none"\|"smoke"...(+2))?` | Particle effect preset style |

### `DespawnConditionsDef`

Granular conditions evaluated to determine if a mob should despawn.

| Field | Type | Description |
| :--- | :--- | :--- |
| `daylight` | `boolean?` | Despawn when exposed to daytime sunlight (default: false) |
| `max_time` | `number?` | Time of day window end (0.0 to 1.0) |
| `min_natural_light` | `integer?` | Natural sunlight threshold (default: 11) |
| `min_time` | `number?` | Time of day window start (0.0 to 1.0) |
| `require_natural_light` | `boolean?` | If true, time_range despawn only applies if exposed to natural sunlight |
| `time_range` | `{ min: number, max: number }?` | Custom time-of-day despawn window |

### `DropEntryDef`

Declarative loot item drop entry.

| Field | Type | Description |
| :--- | :--- | :--- |
| `chance` | `number?` | Probability to drop between 0.0 and 1.0 (default: 1.0) |
| `max` | `integer?` | Maximum count to drop (default: 1) |
| `min` | `integer?` | Minimum count to drop (default: 1) |
| `name` | `string` | Technical item name (e.g. "default:diamond") |

### `DropOptions`

Physics, fountain launch arc, particle trail, and audio overrides for mob item drops.

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

### `EngineMoveResult`

Luanti engine moveresult table returned by physics steps and entity collision detection.

| Field | Type | Description |
| :--- | :--- | :--- |
| `collides` | `boolean` | Whether entity collided with any solid node or object during the step |
| `collisions` | `CollisionInfo[]` | List of detailed collision events encountered during the step |
| `standing_on_object` | `boolean` | Whether entity is physically standing atop another ObjectRef |
| `touching_ground` | `boolean` | Whether entity is in physical contact with a walkable ground surface |

### `EnvelopConfig`

Visual envelop sleeve configuration wrapping the target.

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | `string?` | Unique effect identifier |
| `texture` | `string` | Visual texture asset applied to the open rectangular sleeve |

### `EnvelopEffectDef`

Envelop effect definition configuring visual sleeves and status hooks.

| Field | Type | Description |
| :--- | :--- | :--- |
| `duration` | `number` | Total duration in seconds |
| `id` | `string` | Unique identifier of the status effect (e.g. "venom", "frost", "web") |
| `on_remove` | `fun(target: ObjectRef)?` | Cleanup callback upon expiration or removal |
| `on_step` | `fun(dtime: number, target: ObjectRef)?` | Per-step logic callback forwarded to envelop |
| `texture` | `string` | Visual texture applied to the envelop sleeve |
| `timer` | `number?` | Remaining duration in seconds |

### `EnvelopTargetRecord`

Active enveloped target tracking record linking the envelop entity and target ObjectRef.

| Field | Type | Description |
| :--- | :--- | :--- |
| `envelop` | `ObjectRef` | Envelop entity reference |
| `target` | `ObjectRef` | Enveloped target reference |

### `HealthRegenDef`

Declarative health regeneration and tactical retreat configuration.

### Attribute Precedence & Mutual Exclusivity:
- **`can_flee = false`**: Disables fleeing entirely. The mob will fight to the death without running away,
  and all flee/channel attributes (`flee_threshold`, `flee_ratio`, `return_threshold`, `return_ratio`,
  `burst_duration`, `channel_duration`, `safe_distance`, `heal_amount`) are **ignored**.
- **`flee_threshold` vs `flee_ratio`**: `flee_threshold` (absolute HP integer) takes precedence.
  If `flee_threshold` is explicitly defined, `flee_ratio` is **ignored**.
- **`return_threshold` vs `return_ratio`**: `return_threshold` (absolute HP integer) takes precedence.
  If `return_threshold` is explicitly defined, `return_ratio` is **ignored**.
- **`unlimited_flee = true`**: Mob flees continuously without time limit while passively regenerating at `rate`.
  `burst_duration`, `channel_duration`, `safe_distance`, and `heal_amount` are **ignored**.
- **`passive = true`**: Regenerates `rate` HP/sec continuously during normal idle, walking, and combat states
  without requiring the mob to disengage or enter the vulnerable channeling state.

| Field | Type | Description |
| :--- | :--- | :--- |
| `burst_duration` | `number?` | Seconds mob sprints in disengage burst (default: 3.5s; ignored if unlimited_flee is true). |
| `can_flee` | `boolean?` | Whether mob tactically flees when low HP (default: true; false for stand-and-fight) |
| `channel_duration` | `number?` | Seconds mob channels heal once safe (default: 3.0s; ignored if unlimited_flee is true). |
| `enabled` | `boolean?` | Whether health regeneration is enabled (default: true) |
| `flee_ratio` | `number?` | HP ratio below which mob flees (default: 0.25; ignored if flee_threshold is set) |
| `flee_speed` | `number?` | Speed in m/s while fleeing (default: capped at 4.2 m/s for catchability, or def.flee_speed) |
| `flee_threshold` | `number?` | Absolute HP threshold below which mob flees (takes precedence over flee_ratio) |
| `heal_amount` | `number?` | Flat HP restored when channel completes (default: return - flee threshold; ignored if unlimited_flee is true). |
| `max_flee_distance` | `number?` | Maximum retreat distance before halting or resting (default: 15.0) |
| `overlay` | `boolean?` | Whether visual texture overlay flashes on regeneration (default: true) |
| `overlay_color` | `string?` | Custom texture modifier overlay string (default: "^[colorize:#FFFFFF60") |
| `passive` | `boolean?` | Whether regeneration occurs passively at all times while idle/walking (default: false) |
| `rate` | `number?` | HP regenerated per second for passive regeneration or unlimited_flee (default: 0.5) |
| `return_ratio` | `number?` | HP ratio to exit fleeing/channeling and return to combat (default: 0.60; ignored if return_threshold is set). |
| `return_threshold` | `number?` | Absolute HP threshold to exit fleeing/channeling (takes precedence over return_ratio) |
| `safe_distance` | `number?` | Safe distance to halt sprint and channel heal (default: 10.0m; ignored if unlimited_flee is true). |
| `unlimited_flee` | `boolean?` | Continuous sprint without burst timeout or channel halt (ignores burst/channel durations). |

### `MeleeAttackDef`

Individual melee attack profile for declarative single or multi-attack combat.
Used inside the `attacks` array of `MeleeConfigDef`, or as a single attack definition.

### Attribute Precedence & Exclusivity Rules:
- **`aoe = true` vs `perform_attack`**: Setting `aoe = true` **requires** `perform_attack`.
  When `aoe = true` and `perform_attack` is provided, line-of-sight and target range re-validation
  at `delay` time are **bypassed**, ensuring the attack executes at the ground epicenter even if the
  primary target dodged, jumped away, or moved out of range during windup. If `perform_attack` is omitted,
  `aoe = true` is **ignored** and standard single-target range validation applies.
- **`aoe = true` vs `reach_tolerance`**: `reach_tolerance` is **ignored** when `aoe = true`, because
  target distance is not re-checked at impact time.
- **`perform_attack` vs `damage`**: When `perform_attack` is provided, default engine `target:punch(...)`
  is bypassed, so the `damage` field is **ignored** by the core loop (the callback applies its own damage).
- **`on_strike` vs `perform_attack`**: `on_strike` runs after impact. With default punch, it executes
  immediately after `target:punch(...)`. If `perform_attack` is provided, `on_strike` runs after `perform_attack`.
  For AoE attacks, splash logic should reside directly inside `perform_attack`.
- **`on_start` vs `on_charge`**: `on_charge` is a backwards-compatible alias for `on_start`.

| Field | Type | Description |
| :--- | :--- | :--- |
| `anim_speed` | `number?` | Playback speed multiplier for the attack animation (default: 1.2) |
| `animation` | `string?` | Animation track name played when initiating this attack (default: "attack") |
| `aoe` | `boolean?` | Area of Effect flag; bypasses target range/LOS checks at impact time (requires perform_attack) |
| `cooldown` | `number?` | Cooldown interval before next attack can begin in seconds (default: 1.2) |
| `damage` | `number?` | Base melee strike damage dealt to target (default: 4; ignored if perform_attack is set) |
| `delay` | `number?` | Keyframe impact delay before punch or callback executes in seconds (default: 0.25) |
| `duration` | `number?` | Action timer duration holding the attacking state in seconds (default: 0.5) |
| `on_charge` | `fun(self: MobEntity, target?: ObjectRef)?` | Alias for on_start |
| `on_start` | `fun(self: MobEntity, target?: ObjectRef)?` | Callback executed immediately upon attack initiation |
| `on_strike` | `fun(self: MobEntity, target: ObjectRef, dir: Vector)?` | Callback executed on punch impact |
| `perform_attack` | `CustomAttackCallback?` | Custom melee attack callback override |
| `reach_tolerance` | `number?` | Additional reach buffer for moving targets at hit time (default: 0.6; ignored if aoe = true). |
| `sound` | `string?` | Sound played upon initiating the attack (default: "attack") |
| `weight` | `number?` | Relative selection probability weight when choosing between multiple attacks (default: 1) |

### `MeleeConfigDef`

Declarative close-quarters melee combat configuration.
When configured in `x_mob_core.register_mob`, the core pipeline automatically manages
reach distance validation, raycast line-of-sight checks, horizontal velocity halting,
attack animations, directional audio cues, cooldown intervals, and timed strike impacts.

### How It Works:
1. **Reach & Line of Sight**: During each tick, checks if target distance <= `range` and target is visible.
2. **Halting & Facing**: Upon reach entry, halts horizontal movement and turns the mob to face the target.
3. **Strike Execution**: Starts `duration` pose, triggers `animation`, plays `sound`, and queues delayed hit.
4. **Tolerance Validation**: At `delay` time, confirms target remains within `range + reach_tolerance`
   (bypassed if `aoe = true`).
5. **Impact Feedback**: Applies fleshy punch damage (or calls `perform_attack`) and invokes `on_strike`.

### Attribute Precedence & Mutual Exclusivity:
- **`attacks = { ... }` vs Top-Level Fields**:
  When `attacks` is provided with one or more `MeleeAttackDef` entries, attack selection rolls randomly
  based on `weight`. The selected attack's `animation`, `anim_speed`, `sound`, `duration`, `cooldown`, `delay`,
  `damage`, `reach_tolerance`, `aoe`, `on_start`, and `perform_attack` take precedence over top-level fields.
  Top-level `range` and `max_height_diff` are ALWAYS the common spatial triggers to initiate melee combat.
- **`aoe = true` vs `perform_attack` vs `reach_tolerance`**:
  `aoe = true` requires `perform_attack`. Bypasses target distance and line-of-sight re-validation at `delay`
  time, ensuring ground smashes, shockwaves, or radial spells detonate at the epicenter even if the primary
  target sprinted away. `reach_tolerance` and `damage` are ignored.
- **`melee` vs `shooter` Interplay**:
  Pipeline Priority 18 (`melee`) runs before Priority 20 (`shooter`).
  When a target is within `melee.range`, melee intercepts combat, halts movement, and returns `true`,
  preventing `shooter` from firing. When outside `melee.range`, melee returns `false`, allowing `shooter`
  to kite or fire projectiles at range.
- **`melee = false`**:
  Completely disables melee combat, even if the target is within point-blank range (used for pure ranged mobs).
  If `shooter` is defined and `melee` is `nil`, melee defaults to disabled.

| Field | Type | Description |
| :--- | :--- | :--- |
| `anim_speed` | `number?` | Animation playback speed multiplier (default: 1.2) |
| `animation` | `string?` | Animation track name played when attacking (default: "attack") |
| `aoe` | `boolean?` | Area of Effect flag; bypasses target range/LOS checks at impact time (requires perform_attack) |
| `attacks` | `MeleeAttackDef[]?` | Array of weighted attacks; overrides top-level attack attributes when populated |
| `cooldown` | `number?` | Attack cooldown between strikes in seconds (default: def.attack_interval or 1.2) |
| `damage` | `number?` | Base melee strike damage dealt to targets (default: def.damage or 4; ignored if perform_attack is set). |
| `delay` | `number?` | Delay before punch damage or callback executes in seconds (default: 0.25) |
| `duration` | `number?` | Action timer duration holding attack pose in seconds (default: 0.5) |
| `max_height_diff` | `number?` | Vertical reach tolerance in nodes (default: 2.0) |
| `on_charge` | `fun(self: MobEntity, target?: ObjectRef)?` | Alias for on_start |
| `on_start` | `fun(self: MobEntity, target?: ObjectRef)?` | Callback executed immediately upon attack initiation |
| `on_strike` | `fun(self: MobEntity, target: ObjectRef, dir: Vector)?` | Callback executed on punch impact |
| `perform_attack` | `CustomAttackCallback?` | Custom melee attack callback override |
| `range` | `number?` | Melee attack reach in nodes; entry trigger for melee combat (default: def.attack_range or 2.0) |
| `reach_tolerance` | `number?` | Additional reach buffer for moving targets at hit time (default: 0.6; ignored if aoe = true). |
| `sound` | `string?` | Sound played when attacking (default: "attack") |
| `weight` | `number?` | Default selection weight (default: 1) |

### `MobAnimationDef`

Named glTF or skeletal animation track mapping.

| Field | Type | Description |
| :--- | :--- | :--- |
| `loop` | `boolean?` | Whether to loop animation by default |
| `speed` | `number?` | Playback speed multiplier (default: 1.0) |
| `track` | `string` | Named glTF animation track |

### `MobAuraDef`

Periodic radial aura emitted by mob commanders or totems.

| Field | Type | Description |
| :--- | :--- | :--- |
| `effect` | `string\|StatusEffectDef` | Effect preset name or custom definition |
| `id` | `string` | Unique aura identifier |
| `interval` | `number?` | Seconds between pulses (default: 5.0) |
| `max_targets` | `integer?` | Maximum number of affected targets |
| `radius` | `number?` | Spatial radius in nodes (default: 16.0) |
| `sound` | `string?` | Audio cue played at caster position |
| `target` | `("allies"\|"pack_followers"\|"self")?` | Target filter selector (default: "pack_followers") |
| `vfx` | `(string\|fun(pos: Vector))?` | Declarative VFX preset or callback |

### `MobBoneDef`

Bone attachment pivot and structural orientation definition.

| Field | Type | Description |
| :--- | :--- | :--- |
| `pivot` | `Vector?` | Pivot offset for bone attachments and inverse kinematics |
| `position` | `Vector?` | Bone position offset |
| `rotation` | `Vector?` | Default bone orientation rotation |

### `MobBuffsDef`

Declarative buffs, periodic auras, HP thresholds, and event triggers.

| Field | Type | Description |
| :--- | :--- | :--- |
| `auras` | `MobAuraDef[]?` | Periodic radial auras emitted by commanders/totems |
| `thresholds` | `MobThresholdDef[]?` | Reactive HP threshold events (e.g. Phase 2 Enrage) |
| `triggers` | `MobTriggerDef[]?` | Event-driven reactions (on_damaged, on_heavy_damage) |

### `MobEntity`

Runtime mob LuaEntity instance table representing an active mob in the world.
Passed as `self` across mob step callbacks, punch handlers, and custom abilities.

| Field | Type | Description |
| :--- | :--- | :--- |
| `action_timer` | `number?` | Duration remaining for uninterruptible action (strike windup, shooting) |
| `air_timer` | `number?` | Elapsed time beached on land for aquatic mobs |
| `attack_cooldown` | `number?` | Global melee or ranged combat attack cooldown timer |
| `base_texture` | `string[]?` | Currently applied clean base texture list |
| `block_suffocation_timer` | `number?` | Elapsed time head is trapped inside solid node |
| `can_climb` | `boolean?` | Whether entity climbs ladders, vines, and walls |
| `can_crawl` | `boolean?` | Whether entity navigates 1-block crawlways and ceilings |
| `can_flinch` | `boolean?` | Whether mob flinches on punch |
| `can_open_doors` | `boolean?` | Whether entity opens wooden doors in its path |
| `can_swim` | `boolean?` | Whether entity navigates liquid bodies |
| `can_wander` | `boolean?` | Whether entity wanders when idle |
| `collisionbox` | `number[]?` | 6-element collision box: {minx, miny, minz, maxx, maxy, maxz} |
| `combat_hover_offset` | `number?` | Desired hovering elevation above ground during combat in nodes |
| `combat_standoff` | `number?` | Desired horizontal standoff distance in front of target in combat |
| `cooldowns` | `table<string, number>?` | Named ability cooldown timers in seconds |
| `despawn_timer` | `number?` | Sustained duration far from players before despawning |
| `drowning_timer` | `number?` | Elapsed time submerged without breath |
| `eye_offset` | `number?` | Vertical eye offset in nodes |
| `faction_list` | `string[]?` | Pre-parsed list of faction identifiers |
| `factions` | `(string\|string[])?` | Faction tag or list of faction tags |
| `flee_speed` | `number?` | Tactical retreat speed in nodes/sec |
| `flight_elevation` | `number?` | Desired cruising elevation above ground/player in nodes |
| `half_width` | `number?` | Lateral collision half-width in nodes |
| `halt_horizontal_velocity` | `fun(self: MobEntity)` | Halts horizontal velocity preserving gravity |
| `hover_offset` | `number?` | Desired hovering elevation above ground in nodes |
| `hp` | `number` | Current health points |
| `hp_max` | `number` | Maximum health points |
| `in_water` | `boolean?` | Whether entity is currently submerged in liquid |
| `is_dead` | `boolean` | Flag indicating whether the entity is dead or dying |
| `is_floating` | `boolean?` | Whether entity hovers in mid-air with zero-gravity locomotion |
| `knockback_mult` | `number?` | Knockback impulse multiplier (0 for unyielding) |
| `lost_sight_timer` | `number?` | Seconds elapsed since losing direct line of sight to target |
| `mob_height` | `number?` | Collision height in nodes |
| `name` | `string` | Technical registered entity name (e.g. "x_mobs:spider", "mymod:golem") |
| `object` | `ObjectRef` | Luanti engine C++ userdata pointer representing the active entity |
| `on_wall_or_ceiling` | `boolean?` | Whether climbing mob is attached to wall/ceiling |
| `panic_timer` | `number?` | Duration remaining for panic flee state |
| `previous_state` | `(string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6))?` | Previous state identifier prior to last transition |
| `pursuit_speed` | `number?` | Running pursuit speed in nodes/sec |
| `scan_timer` | `number?` | Throttle timer for periodic target scanning |
| `selectionbox` | `number[]?` | 6-element selection box: {minx, miny, minz, maxx, maxy, maxz} |
| `set_armor_groups` | `fun(self: MobEntity, groups: table<string, number>)` | Sets or updates armor groups |
| `set_cooldown` | `fun(self: MobEntity, key: string, duration: number)` | Sets or resets an ability cooldown |
| `set_texture` | `fun(self: MobEntity, id: integer, vars?: (string[])[]):string[]\|nil` | Sets texture variation |
| `state` | `string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6)` | Current active state identifier ("idle", "wander", "combat", "fleeing", etc.) |
| `state_timer` | `number?` | Time elapsed in current state in seconds |
| `target` | `ObjectRef?` | Currently acquired hostile or pursuit target |
| `texture_no` | `integer?` | Currently selected texture variation index |
| `texture_variations` | `(string[])[]?` | List of available phenotype texture variations |
| `walk_speed` | `number?` | Base walking speed in nodes/sec |
| `wander_radius` | `number?` | Maximum wandering patrol radius in nodes |
| `wander_speed` | `number?` | Wandering patrol speed in nodes/sec |

### `MobHealthBarColorBand`

Color threshold band for dynamic overhead health bar display.

| Field | Type | Description |
| :--- | :--- | :--- |
| `color` | `string` | Hex color string (e.g. "#00FF00") |
| `threshold` | `number` | Health ratio threshold (0.0 to 1.0) |

### `MobHealthBarConfig`

Overhead dynamic combat health bar configuration.

### Attribute Precedence & Mutual Exclusivity:
- Setting `health_bar = false` in `MobRegistrationDef` completely disables the overhead health bar.
  All options in `MobHealthBarConfig` are **ignored**.
- `auto_scale = true`: Width is dynamically scaled to match mob collisionbox width.
  `visual_size` is **ignored** when `auto_scale = true`.

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
| `visual_size` | `Vector2d?` | Explicit sprite visual size override in world coordinates (ignored if auto_scale is true). |
| `width` | `integer?` | Texture width in pixels (default: 64) |

### `MobImmunitiesDef`

Environmental hazard immunities table.
Setting `immunities` supersedes legacy flat flags (`immune_to_lava`, `immune_to_fire`, `immune_to`).

| Field | Type | Description |
| :--- | :--- | :--- |
| `damage_per_second` | `boolean?` | Immune to node damage_per_second |
| `drown` | `boolean?` | Immune to water drowning |
| `environment` | `boolean?` | Immune to all ambient environmental hazard node DPS |
| `fire` | `boolean?` | Immune to fire and igniter damage |
| `lava` | `boolean?` | Immune to lava damage |
| `suffocation` | `boolean?` | Immune to solid block asphyxiation |

### `MobInitialPropertiesDef`

Engine object properties table configured in Luanti ObjectRef properties.
Can be specified inside `initial_properties` or directly at top-level in `MobRegistrationDef`.

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
| `nametag_bgcolor` | `(string\|{ r: integer, g: integer, b: integer, a: integer })?` | Nametag background color |
| `nametag_color` | `(string\|{ r: integer, g: integer, b: integer, a: integer })?` | Nametag text color |
| `physical` | `boolean?` | Whether entity is subject to physical collisions (default: true) |
| `pointable` | `boolean?` | Whether entity can be pointed at or punched (default: true) |
| `selectionbox` | `number[]?` | 6-element selection box: {minx, miny, minz, maxx, maxy, maxz} |
| `shaded` | `boolean?` | Whether mesh is affected by world lighting (default: true) |
| `show_on_minimap` | `boolean?` | Whether entity appears on player minimap |
| `static_save` | `boolean?` | Whether entity persists in block static data across server restarts (default: true) |
| `stepheight` | `number?` | Maximum step-up height in nodes (default: 1.1) |
| `textures` | `string[]?` | List of texture filenames or texture modifier strings |
| `use_texture_alpha` | `(boolean\|string)?` | Texture alpha transparency mode (true, false, "clip", "blend", "opaque") |
| `visual` | `("cube"\|"mesh"\|"sprite")?` | Visual rendering mode (default: "mesh" if mesh is specified) |
| `visual_size` | `(Vector\|Vector2d)?` | Visual model scale factors |
| `zoom_fov` | `number?` | Camera zoom field of view in degrees |

### `MobMemoryDangerRecord`

Tactical danger/threat coordinate record stored in short-term spatial memory.

| Field | Type | Description |
| :--- | :--- | :--- |
| `active` | `boolean` | Whether danger slot is populated |
| `expire` | `number` | Expiration timestamp |
| `threat` | `number` | Threat intensity score |
| `x` | `number` | Danger position X coordinate |
| `y` | `number` | Danger position Y coordinate |
| `z` | `number` | Danger position Z coordinate |

### `MobMemoryState`

Short-term tactical spatial memory buffer tracking targets, threats, and oscillation history.

| Field | Type | Description |
| :--- | :--- | :--- |
| `blocked_spots` | `Vector[]` | Obstruction memory for deadlock evasion |
| `dangers` | `MobMemoryDangerRecord[]` | Pre-allocated circular buffer of active pain/danger positions |
| `fight` | `{ x: number, y: number, z: number, valid: boolean }` | Combat location memory for return-to-fight logic |
| `flee_state` | `boolean` | Whether entity is currently in low-HP tactical retreat |
| `regen_timer` | `number` | Elapsed time during low-HP passive health regeneration |
| `target` | `MobMemoryTargetRecord` | Single predictive target pursuit record (8-second LKP) |
| `trail` | `Vector[]` | Pre-allocated circular buffer of recent positions for anti-oscillation |

### `MobMemoryTargetRecord`

Single predictive target pursuit memory record (8-second Last Known Position tracker).

| Field | Type | Description |
| :--- | :--- | :--- |
| `has_record` | `boolean` | Whether target memory slot is populated |
| `last_seen` | `number` | Timestamp of last target sighting |
| `lkp` | `Vector` | Last known 3D position vector |
| `name` | `string` | Entity name of remembered target |

### `MobMovementDef`

Locomotion traversal abilities, physical constraints, and routing options.
Passed to pathfinder functions (`find_path`, `find_path_sync`) and safety locomotion.

| Field | Type | Description |
| :--- | :--- | :--- |
| `can_climb` | `boolean?` | Whether entity climbs ladders, vines, and climbable walls (default: false) |
| `can_crawl` | `boolean?` | Whether entity can navigate 1-block high crawlways and low ceilings (default: false) |
| `can_open_doors` | `boolean?` | Whether entity opens wooden doors blocking its path (default: false) |
| `can_swim` | `boolean?` | Whether entity navigates water and liquid bodies (default: true) |
| `disallow_water` | `boolean?` | Explicit flag strictly preventing pathfinder from routing through liquid (default: false). |
| `flank_slot` | `integer?` | Multi-agent encirclement slot offsetting destination around target (default: 1) |
| `is_floating` | `boolean?` | Whether entity hovers or flies freely through 3D air without ground support (default: false). |
| `path_seed` | `integer?` | Random pseudo-random seed for path jitter and diverse flanking routes (default: 0) |

### `MobPackDef`

Declarative multi-agent pack and squad coordination configuration.

### Attribute Precedence & Mutual Exclusivity:
- **`role = "member"` vs `role = "leader"`**:
  When `role = "member"`, `max_followers` and `spawn_on_init` are **ignored** (only leaders maintain rosters).
  When `role = "leader"`, `leash_distance` is **ignored** on the leader itself (followers leash to the leader).
- **`auto_succession = true`**: When the leader dies, surviving followers hold an election; the nearest peer
  promotes to new pack leader and inherits remaining followers.
- **`swarm_alert`**: When defined, damage or death automatically triggers pack threat alerts and writes
  coordinate memory for obscured pack allies.

| Field | Type | Description |
| :--- | :--- | :--- |
| `auto_succession` | `boolean?` | Whether surviving followers promote new leader on death (default: false) |
| `follower_type` | `(string\|string[])?` | Expected entity name or list of entity names of the followers |
| `leader_type` | `string?` | Expected entity name of the leader |
| `leash_distance` | `number?` | Distance before followers regroup (default: 18.0; ignored on leader) |
| `max_followers` | `integer?` | Max followers for a leader (default: 3; ignored if role is "member") |
| `on_leader_lost` | `("fight"\|"flee"\|fun(self: MobEntity, leader?: MobEntity))?` | Callback or behavior when pack leader dies. |
| `pack_id` | `string?` | Optional existing pack UUID |
| `regroup_distance` | `number?` | Target distance when regrouping to leader (default: 4.0) |
| `role` | `("leader"\|"member")?` | Role within the pack (default: "member") |
| `spawn_on_init` | `boolean?` | Whether leader auto-spawns initial followers on activate (default: false; ignored if role is "member"). |
| `swarm_alert` | `(boolean\|SwarmAlertDef)?` | Declarative pack & faction rally configuration on damage and death |

### `MobRegistrationDef`

Complete mob entity registration specification, physical properties,
combat tuning, AI navigation, and lifecycle callback configuration.

### Architecture & Attribute Precedence Rules:
- **`initial_properties.*` vs Top-Level Engine Object Properties**:
  Standard Luanti ObjectProperties (`mesh`, `textures`, `hp_max`, `collisionbox`, `selectionbox`,
  `visual_size`, `stepheight`, `glow`, `nametag`, `use_texture_alpha`, etc.) can be placed either inside
  `initial_properties` or directly at top-level. If specified in both, `initial_properties` takes precedence
  and the top-level duplicate is automatically migrated and stripped.
- **Combat Execution Pipeline Precedence**:
  1. `custom_step` (Priority 15): If defined and returns `true`, **intercepts** the combat pipeline,
     bypassing all declarative melee and shooter logic for that tick (used for spells, summoning, standoff).
  2. `melee` (Priority 18): Engages when target is within `melee.range`. Halts horizontal velocity, faces
     target, and returns `true`, intercepting and preventing `shooter` from firing.
  3. `shooter` (Priority 20): Engages when target is within `shooter.range` and outside `melee.range`.
     If target closes inside `shooter.min_range`, mob kites backwards (unless `kiting = false`).
- **Melee vs Shooter Default Behavior**:
  If `shooter` is defined and `melee` is omitted (`nil`), melee defaults to disabled (pure shooter).
  To create a hybrid mob that shoots at distance and fights with melee at close range, explicitly provide
  both `shooter = { ... }` and `melee = { range = ..., ... }`.
- **Locomotion Archetypes**:
  - `is_floating = true`: Zero-gravity flight locomotion. Overrides terrestrial walking; sets
    `props.makes_footstep_sound` to `false` by default. Terrestrial climbing/stepping/crawling are ignored.
  - `is_aquatic = true`: 3D underwater liquid locomotion. On land, mob will suffocate after `air_grace_period`
    unless `amphibious = true` or `can_breathe = true`.
  - `amphibious = true`: Immune to both water drowning and beach land suffocation.
- **Swarm and Shoal Multi-Agent Coordination**:
  Enabling `swarm` or `shoal` automatically sets `collide_with_objects = false` by default to prevent
  clustered entities from pushing each other into physics glitches.
- **Hazard Immunities**:
  The `immunities = { ... }` table is the single source of truth. Setting `immunities` supersedes legacy flat
  flags (`immune_to_lava`, `immune_to_fire`, `immune_to`).

| Field | Type | Description |
| :--- | :--- | :--- |
| `abilities` | `MobMovementDef?` | Optional explicit abilities configuration table overrides |
| `aggro_radius` | `number?` | Player and target detection range in nodes (default: 16.0) |
| `air_grace_period` | `number?` | Seconds before beached aquatic mob suffocates on land (default: 5.0) |
| `amphibious` | `boolean?` | Whether mob is amphibious (immune to both drowning and beach suffocation) |
| `animations` | `table<string, string\|MobAnimationDef>?` | Declarative glTF skeletal animations map |
| `armor_groups` | `table<string, number>?` | Luanti armor groups (e.g. {fleshy = 80, cracky = 70}) |
| `attack_interval` | `number?` | Cooldown between attacks in seconds (default: 1.2) |
| `attack_range` | `number?` | Melee attack reach in nodes (default: 2.0) |
| `auto_scan` | `boolean?` | Whether mob automatically scans for nearby player targets (default: true) |
| `automatic_rotate` | `number?` | Continuous Y-axis rotation speed in radians/sec |
| `backface_culling` | `boolean?` | Whether backfaces of the 3D model are culled (default: true) |
| `block_suffocation_dps` | `number?` | Damage per second when head is buried inside solid block (default: 2) |
| `bones` | `table<string, MobBoneDef>?` | Bone attachment pivots and structural metadata map |
| `breath_max` | `number?` | Breath holding duration in seconds before drowning begins (default: 15.0) |
| `buffs` | `MobBuffsDef?` | Declarative buffs, auras, thresholds, and reactive triggers |
| `can_breathe` | `boolean?` | Whether entity breathes air (false for aquatic mobs) |
| `can_breathe_water` | `boolean?` | Whether terrestrial mob can breathe underwater without drowning |
| `can_climb` | `boolean?` | Whether entity climbs ladders, vines, and walls (default: false) |
| `can_crawl` | `boolean?` | Whether entity navigates 1-block crawlways and ceilings (default: false) |
| `can_flinch` | `(boolean\|fun(self: MobEntity):boolean)?` | Whether mob flinches on punch (default: true) |
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
| `custom_step` | `fun(self: MobEntity, dt: number, res?: EngineMoveResult, def?: MobRegistrationDef):boolean??` | Pre-combat custom ability hook (return true to intercept) |
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
| `flight_elevation` | `number?` | Desired cruising elevation above ground/player in nodes (default: 1.85) |
| `friendly_fire` | `boolean?` | Whether allies/same-faction can damage this mob (default: false) |
| `get_staticdata` | `(fun(self: MobEntity):string)?` | Callback returning serialized state for persistence |
| `glow` | `integer?` | Light emission level in dark environments 0..14 (default: 0) |
| `half_width` | `number?` | Collision half-width for lateral obstacle clearance (default: 0.4) |
| `health_bar` | `(boolean\|MobHealthBarConfig)?` | Overhead combat health bar configuration (false disables) |
| `health_regen` | `(boolean\|number\|HealthRegenDef)?` | Health regen rate, disable toggle, or config table |
| `hooks` | `table<string, fun(self: MobEntity, ...any)>?` | Lifecycle hook callbacks |
| `hover_offset` | `number?` | Desired hovering elevation above ground for floating mobs in nodes (default: 0.4) |
| `hp_max` | `number?` | Maximum health points (synced to ObjectRef properties and engine HP, default: 20) |
| `immunities` | `MobImmunitiesDef?` | Environmental hazard immunities table |
| `infotext` | `string?` | Tooltip text displayed when player points at the entity |
| `initial_properties` | `MobInitialPropertiesDef?` | Luanti ObjectRef properties table (hp, mesh, boxes, etc.) |
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
| `nametag_bgcolor` | `(string\|{ r: integer, g: integer, b: integer, a: integer })?` | Overhead nametag background color |
| `nametag_color` | `(string\|{ r: integer, g: integer, b: integer, a: integer })?` | Overhead nametag text color |
| `on_action_end` | `fun(self: MobEntity)?` | Callback executed when action_timer completes |
| `on_activate` | `fun(self: MobEntity, staticdata: string, dtime_s: number, raw?: string)?` | Called on activation |
| `on_deactivate` | `fun(self: MobEntity, removal: boolean)?` | Called when entity is unloaded or removed |
| `on_death` | `fun(self: MobEntity, killer: ObjectRef\|nil)?` | Callback invoked when entity dies |
| `on_despawn` | `fun(self: MobEntity, reason?: string)?` | Callback when entity despawns gracefully |
| `on_hurt` | `fun(self: MobEntity, puncher: ObjectRef\|nil, damage: number)?` | Callback invoked on taking damage |
| `on_punch` | `fun(self: MobEntity, src: ObjectRef, tflp: number, caps: ToolCapabilities, dir: Vector, dmg: number)?` | Callback invoked when entity is punched |
| `on_regen_step` | `fun(self: MobEntity, hp_added: number)?` | Optional callback executed on each health regeneration step. |
| `on_return_to_fight` | `fun(self: MobEntity)?` | Optional callback executed when mob recovers HP and exits fleeing |
| `on_rightclick` | `(fun(self: MobEntity, clicker: ObjectRef):any)?` | Callback invoked when entity is right-clicked |
| `on_step` | `fun(self: MobEntity, dtime: number, moveresult?: EngineMoveResult)?` | Callback on each physics and logic step. |
| `pack` | `MobPackDef?` | Pack and squad coordination options |
| `perform_attack` | `fun(self: MobEntity, target: ObjectRef, dir: Vector)?` | Custom melee attack callback |
| `physical` | `boolean?` | Whether entity is subject to physical collisions (default: true) |
| `pointable` | `boolean?` | Whether entity can be pointed at or punched (default: true) |
| `pursuit_speed` | `number?` | Running pursuit speed in nodes/sec (default: walk_speed * 1.4) |
| `scan_interval` | `number?` | Frequency of target scanning in seconds (default: 0.4) |
| `selectionbox` | `number[]?` | 6-element selection box: {minx, miny, minz, maxx, maxy, maxz} |
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
| `visual_size` | `(Vector\|Vector2d)?` | Visual model scale factors |
| `walk_speed` | `number?` | Base walking speed in nodes/sec (default: 2.5) |
| `wander_radius` | `number?` | Maximum wandering patrol radius in nodes (default: 10.0) |
| `wander_speed` | `number?` | Wandering patrol speed in nodes/sec (default: walk_speed * 0.6) |
| `zoom_fov` | `number?` | Camera zoom field of view in degrees |

### `MobSoundDef`

Acoustic sound feedback configuration mapping event categories to sounds.

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
| `attack_cooldown` | `number?` | Global melee/combat attack cooldown timer |
| `cooldowns` | `table<string, number>?` | Named ability cooldown timers in seconds |
| `custom_states` | `table<string, CustomStateDef>?` | Map of registered custom states |
| `is_dead` | `boolean` | Flag indicating whether the entity is dead or dying |
| `lost_sight_timer` | `number?` | Seconds elapsed since losing direct line of sight to target |
| `memory` | `MobMemoryState?` | Short-term tactical memory buffer (LKP, threats, repulsion, trail) |
| `name` | `string` | Technical registered entity name (e.g. "x_mobs:golem") |
| `object` | `ObjectRef` | Luanti engine C++ userdata pointer representing the active entity |
| `panic_timer` | `number?` | Duration remaining for panic flee state |
| `path_state` | `{ waypoints: Vector[], index: integer, target_pos: Vector }?` | Pathfinding traversal state |
| `previous_state` | `(string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6))?` | State prior to last transition |
| `scan_timer` | `number?` | Throttle timer for periodic target scanning |
| `set_cooldown` | `fun(self: MobStateContext, key: string, duration: number)` | Helper to set ability cooldown |
| `state` | `string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6)` | Current active state identifier |
| `state_timer` | `number?` | Time elapsed in current state in seconds |
| `target` | `ObjectRef?` | Currently acquired hostile or pursuit target |

### `MobThresholdDef`

Reactive HP threshold trigger for boss phase shifts or rage mechanics.

| Field | Type | Description |
| :--- | :--- | :--- |
| `cleanse` | `boolean?` | Whether to automatically purge debuffs upon triggering |
| `effect` | `(string\|StatusEffectDef)?` | Effect preset name or custom definition |
| `hp_ratio` | `number` | HP percentage trigger (e.g. 0.35 for <= 35% HP) |
| `id` | `string?` | Unique threshold identifier |
| `once` | `boolean?` | Whether this triggers only once per spawn lifecycle (default: true) |
| `sound` | `string?` | Audio cue played on trigger |
| `vfx` | `(string\|fun(pos: Vector))?` | Visual effect trigger or callback |

### `MobTriggerDef`

Event-driven reaction triggered by taking damage.

| Field | Type | Description |
| :--- | :--- | :--- |
| `cleanse` | `boolean?` | Whether to automatically purge debuffs upon triggering |
| `cooldown` | `number?` | Internal cooldown in seconds (default: 10.0) |
| `effect` | `(string\|StatusEffectDef)?` | Effect preset name or custom definition |
| `event` | `"on_damaged"\|"on_heavy_damage"` | Trigger event |
| `id` | `string?` | Unique trigger identifier |
| `sound` | `string?` | Audio cue played on trigger |
| `threshold_damage` | `number?` | Damage threshold for on_heavy_damage (default: 25% max HP) |
| `vfx` | `(string\|fun(pos: Vector))?` | Visual effect trigger or callback |

### `PackBuffOptions`

Configuration options for pulsing or applying buffs to pack members via x_mob_core.apply_pack_buff.

| Field | Type | Description |
| :--- | :--- | :--- |
| `include_leader` | `boolean?` | Whether the buff applies to the leader in addition to followers (default: true) |
| `max_targets` | `integer?` | Maximum number of pack entities affected (default: all) |
| `sound` | `string?` | Audio cue played at caster position |
| `vfx` | `(string\|fun(pos: Vector))?` | Visual effect trigger or callback |

### `ParticleSpawnerDef`

Luanti particle spawner definition table.
Supports structured range bounds, Brownian jitter, drag physics, and texture pools.

| Field | Type | Description |
| :--- | :--- | :--- |
| `amount` | `integer?` | Number of particles spawned over lifetime (default: 1) |
| `attached` | `ObjectRef?` | Entity ObjectRef to which the particle spawner is attached |
| `collision_removal` | `boolean?` | Whether particles disappear upon touching solid nodes |
| `collisiondetection` | `boolean?` | Whether particles collide with solid walkable nodes |
| `glow` | `integer?` | Light emission rating 0..14 in dark environments |
| `maxacc` | `Vector?` | Maximum continuous acceleration vector |
| `maxexptime` | `number?` | Maximum particle lifespan in seconds |
| `maxpos` | `Vector?` | Maximum world coordinate bounds for particle birth |
| `maxsize` | `number?` | Maximum visual particle size in nodes |
| `maxvel` | `Vector?` | Maximum initial velocity vector |
| `minacc` | `Vector?` | Minimum continuous acceleration vector (e.g. gravity `{x=0, y=-9.81, z=0}`) |
| `minexptime` | `number?` | Minimum particle lifespan in seconds |
| `minpos` | `Vector?` | Minimum world coordinate bounds for particle birth |
| `minsize` | `number?` | Minimum visual particle size in nodes |
| `minvel` | `Vector?` | Minimum initial velocity vector |
| `object_collision` | `boolean?` | Whether particles collide with players and entities |
| `playername` | `string?` | Optional player name to restrict packet transmission to single client |
| `texture` | `string?` | Visual texture asset filename or procedural modifier |
| `time` | `number?` | Lifetime of spawner in seconds (0 = continuous ongoing spawner) |
| `vertical` | `boolean?` | Whether particle texture is billboarded vertically to camera |

### `ProjectileStepOptions`

Configuration options for step_projectile ballistics and collision handling.

| Field | Type | Description |
| :--- | :--- | :--- |
| `allow_allies` | `boolean?` | Whether friendly/allied entities can be hit (default: false) |
| `allow_players` | `boolean?` | Whether players are valid targets (default: true) |
| `damage` | `number?` | Damage applied when impacting target without on_hit_object (default: self._damage or 5) |
| `ignore_entities` | `(string[]\|table<string, boolean>)?` | Additional entity technical names to ignore |
| `lifetime` | `number?` | Maximum projectile lifetime in seconds before removal (default: 4.0) |
| `on_hit` | `fun(self: MobEntity, hit_obj: ObjectRef\|nil, hit_pos: Vector)?` | Callback executed on any impact |
| `on_hit_node` | `fun(self: MobEntity, hit_pos: Vector, node: { name: string, param1: integer, param2: integer })?` | Callback when hitting a solid node. |
| `on_hit_object` | `fun(self: MobEntity, hit_obj: ObjectRef, hit_pos: Vector, dir: Vector)?` | Object hit callback |
| `on_step` | `fun(self: MobEntity, dtime: number, pos: Vector)?` | Callback executed on every unobstructed flight step |
| `radius` | `number?` | Proximity fallback collision radius in nodes (default: 1.5) |
| `remove_on_hit` | `boolean?` | Whether to remove projectile entity upon impact (default: true) |
| `rotate` | `boolean?` | Whether to automatically rotate projectile along velocity vector (default: true) |

### `ProjectileTargetOptions`

Validation options filtering targetable objects for projectiles and shooters.

| Field | Type | Description |
| :--- | :--- | :--- |
| `allow_allies` | `boolean?` | Whether friendly/allied entities can be hit (default: false) |
| `allow_players` | `boolean?` | Whether players are valid targets (default: true) |
| `ignore_entities` | `(string[]\|table<string, boolean>)?` | Additional entity technical names to ignore |

### `ScheduledAction`

Lifecycle-tied scheduled timer action managed on mob entity.
Automatically cancels if mob dies, despawns, or transitions into flinching.

| Field | Type | Description |
| :--- | :--- | :--- |
| `callback` | `fun(self: MobEntity)` | Callback executed when timer completes |
| `tag` | `string` | Unique action tag for debugging and cancellation |
| `timer` | `number` | Remaining seconds before callback fires |

### `ShoalConfigDef`

Aquatic fish schooling formation, 3D obstacle avoidance, and anchor steering configuration.

### Attribute Precedence & Mutual Exclusivity:
- **`shoal.enabled = true` vs Terrestrial Movement**:
  Enabling `shoal` forces 3D liquid schooling formations. Terrestrial walking is **ignored**.
- **Collision Jamming Safeguard**:
  Enabling `shoal` automatically sets `collide_with_objects = false` to prevent tightly clustered fish
  from pushing each other into block seams.

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

### `ShooterConfigDef`

Declarative ranged combat, projectile firing, and tactical kiting configuration.
When configured in `x_mob_core.register_mob`, the core pipeline automatically manages
distance acquisition, line-of-sight checks, tactical kiting/retreat, charge windup callbacks,
velocity-based lead aim prediction, and projectile spawning.

### How It Works:
1. **Distance Acquisition**: Engages when target distance is between `min_range` and `range` with line-of-sight.
2. **Tactical Kiting**: When target closes inside `min_range`, mob steers away at `retreat_speed`
   (unless `kiting = false`).
3. **Charge & Windup**: Sets `action_timer = fire_duration`, plays `animation`, `sound`, and calls `on_charge`.
4. **Aim Prediction**: After `fire_delay`, calculates lead trajectory if `predict_aim = true`.
5. **Spawning & Launch**: Spawns `projectile`, sets flight velocity/rotation, and calls `on_shoot`
   (or invokes `on_fire`).

### Attribute Precedence & Mutual Exclusivity:
- **`on_fire` vs `projectile` & `on_shoot`**:
  If `on_fire` is provided, automatic entity spawning of `projectile` and `on_shoot` are **ignored**.
  `on_fire` gives complete custom control over raycasting, multi-projectile salvos, or custom spell mechanics.
- **`projectile = false`**: Explicitly disables entity spawning if `on_fire` is not used.
  `kiting = false`: Disables tactical retreat when target is closer than `min_range`.
  `retreat_speed` is **ignored**. Allows hybrid mobs to yield to locomotion AI.
- **`shoot_while_retreating`**: If `true` (default), mob continues firing while kiting backward.
  If `false`, mob holds movement to fire or only flees when target is inside `min_range`.
- **`melee` vs `shooter`**: Melee (Priority 18) takes precedence when within `melee.range`.
  If `def.shooter` is defined and `def.melee` is `nil`, melee defaults to disabled.

| Field | Type | Description |
| :--- | :--- | :--- |
| `animation` | `string?` | Animation track name played when shooting (default: "attack") |
| `cooldown` | `number?` | Attack cooldown between shots in seconds (default: 2.0) |
| `damage` | `number?` | Projectile damage (default: 3; passed to projectile or used by step handler) |
| `fire_delay` | `number?` | Delay before projectile is released in seconds (default: 0.4) |
| `fire_duration` | `number?` | Duration mob holds shooting pose in seconds (default: 1.0) |
| `kiting` | `boolean?` | Whether mob tactically retreats when inside min_range (default: true; false for hybrid mobs) |
| `min_range` | `number?` | Minimum distance threshold under which mob retreats (default: 0.0) |
| `on_charge` | `fun(self: MobEntity, pos: Vector)?` | Callback executed during firing windup / charge |
| `on_fire` | `fun(self: MobEntity, origin: Vector, dir: Vector, vel: number, target_pos: Vector)?` |  |
| `on_shoot` | `fun(self: MobEntity, proj_obj: ObjectRef, dir: Vector, origin: Vector)?` | Spawn callback (ignored if on_fire is set). |
| `predict_aim` | `boolean?` | Whether to apply aim lead prediction based on target velocity (default: false) |
| `projectile` | `(string\|false)?` | Technical entity name of projectile (default: "x_mobs:archer_arrow"; false disables) |
| `range` | `number?` | Maximum firing range in nodes (default: def.attack_range or 15.0) |
| `retreat_speed` | `number?` | Speed when kiting / backing away from player (default: 1.0; ignored if kiting is false) |
| `shoot_while_retreating` | `boolean?` | Whether mob can fire projectiles while kiting / backing away (default: true) |
| `sound` | `string?` | Sound played when shooting (default: "shoot") |
| `state` | `string?` | Entity state set while shooting (default: "attacking") |
| `velocity` | `number?` | Projectile flight speed in nodes/sec (default: 18.0) |

### `SoundConfigDef`

Detailed sound trigger configuration with volume, hearing distance, pitch jitter, and throttle intervals.

| Field | Type | Description |
| :--- | :--- | :--- |
| `chance` | `number?` | Probability to play when interval expires (default: 1.0) |
| `distance` | `number?` | Maximum audible distance in nodes (default: 16.0) |
| `gain` | `number?` | Volume multiplier (default: 1.0) |
| `max_interval` | `number?` | Maximum cooldown between automatic triggers in seconds (default: 22.0) |
| `min_interval` | `number?` | Minimum cooldown between automatic triggers in seconds (default: 8.0) |
| `name` | `string\|string[]` | Technical sound name or list of sound variations |
| `pitch` | `number?` | Base pitch multiplier (default: 1.0) |
| `pitch_jitter` | `number?` | Random pitch variation factor (default: 0.05) |

### `SoundOverrides`

Positional audio parameter overrides passed to x_mob_core.play_sound.

| Field | Type | Description |
| :--- | :--- | :--- |
| `distance` | `number?` | Maximum audible hearing distance in nodes (default: 16.0) |
| `gain` | `number?` | Volume gain multiplier (default: 1.0) |
| `loop` | `boolean?` | Whether audio track loops indefinitely until stopped |
| `object` | `ObjectRef?` | Entity ObjectRef override to attach sound playback to |
| `pitch` | `number?` | Pitch multiplier (default: 1.0) |
| `pos` | `Vector?` | World coordinate override for sound emitter |
| `to_player` | `string?` | Play sound privately to a single connected player name |

### `SpawnConfig`

Environmental condition filters and population limits for natural mob spawning.

### Attribute Precedence & Mutual Exclusivity:
- **`is_aquatic = true` vs `nodes`**:
  When `is_aquatic = true`, the spawner validates that the spawn position is submerged inside
  liquid nodes (`group:water`) rather than standing on top of dry surface nodes.
- **`day_only = true` vs `night_only = true` vs `min_time` / `max_time`**:
  `day_only = true` restricts spawning to daytime (0.20 <= time <= 0.80).
  `night_only = true` restricts spawning to nighttime (time < 0.20 or time > 0.80).
  `min_time` and `max_time` define explicit time windows; when provided, they take precedence
  over `day_only` and `night_only`.
- **`exclude_nodes` & `exclude_groups`**:
  Checked after matching `nodes`. If a node matches `nodes` but is listed in `exclude_nodes` or
  `exclude_groups`, spawning is aborted.

| Field | Type | Description |
| :--- | :--- | :--- |
| `active_object_count` | `integer?` | Max nearby instances of this entity allowed within active block radius (default: 1). |
| `biomes` | `string[]?` | Optional list of biome technical names (e.g. `{"everness:crystal_forest"}`) |
| `chance` | `integer?` | 1 in X chance per mapblock evaluation tick (default: 1000) |
| `day_only` | `boolean?` | Only spawn during daytime (0.20 <= time <= 0.80) |
| `exclude_groups` | `string[]?` | Node groups to explicitly exclude from spawning (e.g. `{"river_water"}`) |
| `exclude_nodes` | `string[]?` | Specific nodes to explicitly exclude from spawning (e.g. `{"default:river_water_source"}`). |
| `group_max` | `integer?` | Maximum entities to spawn in a pack/swarm (default: 1) |
| `group_min` | `integer?` | Minimum entities to spawn in a pack/swarm (default: 1) |
| `is_aquatic` | `boolean?` | Whether mob spawns submerged inside liquid rather than on surface (default: false) |
| `max_elevation` | `number?` | Maximum Y coordinate (default: 31000) |
| `max_light` | `integer?` | Maximum light level 0..15 (default: 15) |
| `max_time` | `number?` | Specific maximum time-of-day (0.0 to 1.0; takes precedence over day/night flags) |
| `max_total_in_radius` | `integer?` | Max total living entities of any type allowed in radius (default: 8) |
| `min_elevation` | `number?` | Minimum Y coordinate (default: -31000) |
| `min_light` | `integer?` | Minimum light level 0..15 (default: 0) |
| `min_time` | `number?` | Specific minimum time-of-day (0.0 to 1.0; takes precedence over day/night flags) |
| `mob_name` | `string?` | Optional entity technical name override |
| `night_only` | `boolean?` | Only spawn during nighttime (time < 0.20 or time > 0.80) |
| `nodes` | `string[]?` | Valid ground node names or group filters (e.g. `{"default:dirt_with_grass", "group:sand"}`) |

### `SpawnDefinition`

Registered natural spawn rule linking an entity name with environmental spawning parameters.

| Field | Type | Description |
| :--- | :--- | :--- |
| `active_object_count` | `integer?` | Max nearby instances of this entity allowed within active block radius (default: 1). |
| `biomes` | `string[]?` | Optional list of biome technical names (e.g. `{"everness:crystal_forest"}`) |
| `chance` | `integer?` | 1 in X chance per mapblock evaluation tick (default: 1000) |
| `day_only` | `boolean?` | Only spawn during daytime (0.20 <= time <= 0.80) |
| `exclude_groups` | `string[]?` | Node groups to explicitly exclude from spawning (e.g. `{"river_water"}`) |
| `exclude_nodes` | `string[]?` | Specific nodes to explicitly exclude from spawning (e.g. `{"default:river_water_source"}`). |
| `group_max` | `integer?` | Maximum entities to spawn in a pack/swarm (default: 1) |
| `group_min` | `integer?` | Minimum entities to spawn in a pack/swarm (default: 1) |
| `is_aquatic` | `boolean?` | Whether mob spawns submerged inside liquid rather than on surface (default: false) |
| `max_elevation` | `number?` | Maximum Y coordinate (default: 31000) |
| `max_light` | `integer?` | Maximum light level 0..15 (default: 15) |
| `max_time` | `number?` | Specific maximum time-of-day (0.0 to 1.0; takes precedence over day/night flags) |
| `max_total_in_radius` | `integer?` | Max total living entities of any type allowed in radius (default: 8) |
| `min_elevation` | `number?` | Minimum Y coordinate (default: -31000) |
| `min_light` | `integer?` | Minimum light level 0..15 (default: 0) |
| `min_time` | `number?` | Specific minimum time-of-day (0.0 to 1.0; takes precedence over day/night flags) |
| `mob_name` | `string?` | Entity technical name (e.g. "x_mobs:spider") |
| `night_only` | `boolean?` | Only spawn during nighttime (time < 0.20 or time > 0.80) |
| `nodes` | `string[]?` | Valid ground node names or group filters (e.g. `{"default:dirt_with_grass", "group:sand"}`) |

### `StateTransitionDef`

Declarative state transition rule.

| Field | Type | Description |
| :--- | :--- | :--- |
| `condition` | `fun(self: MobStateContext):boolean` | Condition predicate returning true to transition |
| `from` | `string\|"*"\|"attacking"\|"combat"\|"dying"...(+7)` | Source state name or "*" for wildcard |
| `on_transition` | `fun(self: MobStateContext)?` | Optional callback executed during transition |
| `to` | `string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6)` | Destination state name |

### `StatusEffectDef`

Status effect specification table configuring buffs, debuffs, DoTs, roots, and visual overlays.

| Field | Type | Description |
| :--- | :--- | :--- |
| `anti_heal` | `boolean?` | Whether health regeneration is suppressed during effect |
| `attack_multiplier` | `number?` | Outgoing damage multiplier (e.g. 1.35 for +35% attack power) |
| `caster` | `ObjectRef?` | Attacking entity or player source |
| `category` | `("buff"\|"debuff")?` | Polarity category for cleansing and dispelling |
| `chance` | `number?` | Optional trigger chance (fraction 0.0-1.0 or percentage 1-100; default: 100%) |
| `cleanse_debuffs` | `boolean?` | Whether active debuffs/DoTs/slows are purged upon application |
| `cleanse_in_water` | `boolean?` | Whether immersion in water immediately cleanses the effect |
| `damage` | `number?` | Damage per interval tick for DoT |
| `damage_multiplier` | `number?` | Incoming damage multiplier while afflicted (e.g. 1.35 for brittle, 0.6 for ironhide) |
| `damage_type` | `string?` | Damage group name for DoT (default: "fleshy") |
| `drain_hunger` | `number?` | Hunger or stamina units drained per tick via hunger_adapter |
| `duration` | `number` | Duration in seconds |
| `envelop` | `EnvelopConfig?` | Visual envelop configuration |
| `envelop_texture` | `string?` | Visual envelop sleeve texture asset |
| `fov_duration` | `number?` | Optional sub-duration for FOV effect in seconds (defaults to effect duration) |
| `fov_factor` | `number?` | Camera FOV multiplier (e.g. 0.85 for shockwave / tunnel vision) |
| `fov_transition` | `number?` | FOV transition smoothing time in seconds (default: 0.2) |
| `gravity_factor` | `number?` | Gravity fractional multiplier |
| `heal` | `number?` | Health restored per interval tick for HoT (Health over Time) |
| `hud_vignette` | `(string\|VignetteConfig)?` | Fullscreen responsive screen vignette configuration |
| `id` | `string?` | Unique status effect identifier (e.g. "venom", "haste", "freeze", "ironhide") |
| `interval` | `number?` | Interval between DoT/HoT ticks in seconds (default: 1.0) |
| `jump_factor` | `number?` | Jump fractional multiplier (e.g. 0.0 to prevent jump) |
| `knockback_resilience` | `number?` | Knockback reduction factor (0.0 = full knockback, 1.0 = immovable) |
| `on_apply` | `fun(target: ObjectRef)?` | Callback when effect is first applied |
| `on_remove` | `fun(target: ObjectRef)?` | Callback when effect is removed or expires |
| `on_step` | `fun(dtime: number, target: ObjectRef)?` | Callback on step tick (forwarded to envelop) |
| `on_tick` | `fun(target: ObjectRef)?` | Callback on periodic DoT/HoT tick (e.g. particle spawner) |
| `particle_spawner` | `(ParticleSpawnerDef\|fun(target: ObjectRef):ParticleSpawnerDef)?` | Particle spawner definition or generator callback for periodic ticks. |
| `penetrate_armor` | `boolean?` | Whether DoT bypasses armor damage reduction (default: true) |
| `speed_factor` | `number?` | Movement speed fractional multiplier (e.g. 0.5 for 50% slow, 1.35 for haste) |
| `thorns` | `ThornsDef?` | Reactive thorns on melee attackers |
| `type` | `("buff"\|"custom"\|"debuff"\|"dot"\|"root"...(+1))?` | Effect archetype ("root" halts movement and jump) |

### `StatusEffectOverrideDef`

Optional field overrides when applying a status effect preset via x_mob_core.apply_buff.

| Field | Type | Description |
| :--- | :--- | :--- |
| `attack_multiplier` | `number?` | Outgoing attack power multiplier override |
| `caster` | `ObjectRef?` | Caster entity reference override |
| `damage` | `number?` | Damage per tick override for DoTs |
| `damage_multiplier` | `number?` | Incoming damage multiplier override |
| `duration` | `number?` | Duration in seconds override |
| `heal` | `number?` | Health restored per tick override for HoTs |
| `level` | `integer?` | Effect intensity tier or amplifier level |
| `speed_factor` | `number?` | Speed multiplier override |

### `SwarmAlertDef`

Declarative pack/faction rally configuration evaluated automatically on damage and death.
Unlike imperative broadcast_threat, swarm_alert also writes coordinate memory for obscured allies.

| Field | Type | Description |
| :--- | :--- | :--- |
| `enabled` | `boolean?` | Whether pack threat alerting is enabled (default: true) |
| `max_allies` | `integer?` | Maximum pack members rallied per threat alert (default: 8) |
| `radius` | `number?` | Search radius for alerting nearby pack allies (default: 24.0) |

### `SwarmCombatDef`

Coordinated aerial swarm combat vortex and dive-bomb configuration.

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

Aerial Boids swarm intelligence, 3D flocking, and coordinated dive-bombing configuration.

### Attribute Precedence & Mutual Exclusivity:
- **`swarm.enabled = true` vs Terrestrial Movement**:
  Enabling `swarm` forces zero-gravity aerial flocking and vortex combat. Terrestrial walking, crawling,
  and stepping are **ignored**.
- **Collision Jamming Safeguard**:
  Enabling `swarm` automatically sets `collide_with_objects = false` to prevent grouped airborne entities
  from causing physics glitches.

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

### `ThornsDef`

Reactive thorns combat configuration on a target entity.
Reflects damage back to attackers upon taking melee damage.

| Field | Type | Description |
| :--- | :--- | :--- |
| `chance` | `number?` | Trigger probability between 0.0 and 1.0 (default: 1.0) |
| `damage` | `number` | Flat damage reflected back to attacker on melee strike |
| `damage_type` | `string?` | Damage group name for reflected damage (default: "fleshy") |

### `ToolCapabilities`

Engine tool capabilities definition from Luanti item definitions or ItemStack:get_tool_capabilities().
Specifies full-punch intervals, group capabilities, and raw damage groups dealt to armor groups.

| Field | Type | Description |
| :--- | :--- | :--- |
| `damage_groups` | `table<string, number>?` | Base damage dealt to armor groups (e.g. `{ fleshy = 6 }`) |
| `full_punch_interval` | `number?` | Interval in seconds required for maximum punch damage (default: 1.0) |
| `groupcaps` | `table<string, ToolGroupCap>?` | Capability tables by node/item group (e.g. `{ cracky = ... }`) |
| `max_drop_level` | `integer?` | Maximum drop level tool can harvest (default: 0) |

### `ToolGroupCap`

Node group capability specification inside ToolCapabilities.

| Field | Type | Description |
| :--- | :--- | :--- |
| `maxlevel` | `integer?` | Maximum level supported for harvesting this group |
| `times` | `number[]?` | Digging times in seconds indexed by group level |
| `uses` | `integer?` | Maximum uses before tool breaking (wear per use = 65535 / uses) |

### `VignetteConfig`

Fullscreen responsive screen vignette configuration.

| Field | Type | Description |
| :--- | :--- | :--- |
| `color` | `string?` | Hex color string (e.g. "#8A2BE240" or "#FF450050") |
| `opacity` | `integer?` | Opacity value 0-255 |
| `texture` | `string?` | Custom texture or procedural texture modifier |
| `z_index` | `integer?` | Optional z-index override (default: -10) |

---

## Type Aliases & Callbacks

| Type Alias | Signature / Definition | Description |
| :--- | :--- | :--- |
| `ArmorGroups` | `table<string, number>` | Luanti armor groups mapping group names (e.g. `"fleshy"`, `"cracky"`) to damage percentage ratings. A fleshy rating of 100 takes 100% damage, 80 takes 80% damage, and 0 is completely immune. Setting `immortal = 1` protects the entity from engine-level death while x_mob_core manages combat. |
| `Box6d` | `number[]` | 6-element bounding box in world coordinates: `{min_x, min_y, min_z, max_x, max_y, max_z}`. Defines physical collision boundaries or interactive selection volumes in node units. |
| `ColorSpec` | `string\|{ r: integer, g: integer, b: integer, a: integer }` | Luanti color specification string (e.g. `"#FF0000"`, `"#FFFFFF60"`) or RGBA color table `{r, g, b, a}`. |
| `CoreEventName` | `string\|"on_mob_death"\|"on_mob_despawn"\|"on_mob_hurt"\|"on_mob_rightclick"...(+2)` | Standard pub-sub event names emitted across mob lifecycles on the x_mob_core event bus. |
| `CustomStepHandler` | `fun(self: MobEntity, dt: number, res?: EngineMoveResult, def?: MobRegistrationDef):boolean?` | Pre-combat custom ability interception hook handler. Executed at Priority 15 in the middleware pipeline prior to declarative melee and shooter logic. Return `true` to halt the pipeline (e.g. while casting spells, summoning minions, in tactical standoff). Return `false` or `nil` to fall through into standard declarative melee and ranged attacks. |
| `DamageGroups` | `table<string, number>` | Luanti damage groups mapping group names (e.g. `"fleshy"`) to raw damage points dealt by weapons. |
| `EventListenerCallback` | `fun(...any)` | Callback function invoked when a pub-sub event is emitted on the event bus. |
| `MobPunchCallback` | `fun(self: MobEntity, src: ObjectRef, tflp: number, caps: ToolCapabilities, dir: Vector, dmg: number)` | Callback invoked when an entity is punched by a player or another entity. |
| `MobStateType` | `string\|"attacking"\|"combat"\|"dying"\|"fleeing"...(+6)` | Canonical state machine states coordinating mob behavior, animation, and locomotion. |
| `PathfindingCallback` | `fun(path: Vector[]\|nil)` | Callback function invoked when an asynchronous A* path search completes. Receives an array of solved 3D waypoint vectors on success, or `nil` if unreachable. |
| `StepHookHandler` | `fun(self: MobEntity, dtime: number, def: MobRegistrationDef, res?: EngineMoveResult):boolean?` | Step hook callback invoked on every server step for living mob entities. Return values: - Return `true` to **intercept** step handling: cancels subsequent pipeline hooks from firing on this tick, and bypasses default pursuit and wandering locomotion. - Return `false` or `nil` to allow subsequent pipeline hooks and normal mob locomotion to proceed. |
| `ToolCaps` | `ToolCapabilities` | Tool capabilities shorthand alias for compact callback annotations. |

---

## Lifecycle & Entity Registration API

Standardized mob entity registration, state machine transitions, armor group handling, texture variation routing, target selection, lifecycle-tied action scheduling, and prioritized step middleware pipeline hooks.

#### `x_mob_core.cancel_scheduled`

Cancels scheduled actions by tag.

```lua
function x_mob_core.cancel_scheduled(self: MobEntity, tag: string)
```

**Parameters:**

* `self` (`MobEntity`): Mob entity reference
* `tag` (`string`): The tag to cancel

#### `x_mob_core.clear_scheduled`

Clears all scheduled actions for the mob.

```lua
function x_mob_core.clear_scheduled(self: MobEntity)
```

**Parameters:**

* `self` (`MobEntity`): Mob entity reference

#### `x_mob_core.register_mob`

Registers a mob definition with standardized physical properties and lifecycle integration.

### Key Configuration Attributes & Mutual Exclusivity Rules:
- **Locomotion Archetypes (`is_floating`, `is_aquatic`, `amphibious`)**:
  - `is_floating = true`: Mob hovers in mid-air or liquid with zero gravity. Node step-up, ground clinging,
    and fall damage are completely bypassed.
  - `is_aquatic = true`: Mob is strictly aquatic. Submerged swimming is enabled, but dry-land pathfinding
    is disabled and mob suffocates when beached (unless `amphibious = true`).
  - `amphibious = true`: Mob breathes freely both in liquid and on dry land, disabling both drowning
    and beach suffocation.
  - `can_climb = true`: Allows ascending vertical climbable nodes (ladders, vines).
  - `can_open_doors = true`: Mob automatically opens wooden doors obstructing its path.
- **Combat Pipelines (`custom_step`, `melee`, `shooter`)**:
  - `custom_step`: Priority 15 middleware hook. Returning `true` **intercepts** execution, completely skipping
    declarative `melee` and `shooter` combat routines for custom spells, charges, or channeled actions.
  - `melee = false`: Completely disables built-in melee attacks and reach calculations.
  - `shooter = false`: Completely disables ranged attack targeting, aim prediction, kiting, and projectile firing.
  - When `melee.aoe = true`: Targets all hostile entities within `attack_range`; single-target reach and aim
    tolerances are ignored.
- **Health, Fleeing & Regeneration**:
  - `can_flee = false`: Completely suppresses low-HP fleeing regardless of `flee_threshold` or `flee_ratio`.
  - `unlimited_flee = true`: Keeps mob permanently in retreat once triggered; passive health regeneration is
    suppressed.
  - `health_regen = false`: Disables passive health recovery out of combat.

```lua
function x_mob_core.register_mob(name: string, def: MobRegistrationDef)
```

**Parameters:**

* `name` (`string`): Technical entity name (e.g. "x_mobs:spider", "mymod:golem")
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
function x_mob_core.register_step_hook(name: string, priority: integer, handler: fun(self: MobEntity, dtime: number, def: MobRegistrationDef, res?: EngineMoveResult):boolean?)
```

**Parameters:**

* `name` (`string`): Unique hook identifier (namespaced, e.g. "mymod:freeze_aura")
* `priority` (`integer`): Execution order (lower runs first; see priority schedule)
* `handler` (`fun(self: MobEntity, dtime: number, def: MobRegistrationDef, res?: EngineMoveResult):boolean?`): Callback function. Return `true` to intercept, or `false`/`nil` to continue.

#### `x_mob_core.schedule`

Schedules an action to be executed in the future on the mob's timer.
Unlike `core.after`, scheduled actions are automatically tied to the mob's existence
and will safely cancel if the mob dies, despawns, or transitions into a flinching state.

```lua
function x_mob_core.schedule(self: MobEntity, delay: number, tag: string, callback: fun(self: MobEntity))
```

**Parameters:**

* `self` (`MobEntity`): Mob entity reference
* `delay` (`number`): Time in seconds
* `tag` (`string`): Identifier string, useful for cancellation or debugging
* `callback` (`fun(self: MobEntity)`): The function to execute, taking `self` as argument

#### `x_mob_core.set_armor_groups`

Sets or updates armor groups on a mob while maintaining engine immortal protection.
Immortal = 1 is preserved internally so that x_mob_core manages combat and health.

```lua
function x_mob_core.set_armor_groups(self: MobEntity|ObjectRef, groups: table<string, number>)
```

**Parameters:**

* `self` (`MobEntity|ObjectRef`): Mob entity instance or ObjectRef
* `groups` (`table<string, number>`): Armor groups rating percentage (e.g. { fleshy = 80, cracky = 70 })

#### `x_mob_core.set_target`

Sets a mob's target and emits the on_mob_target event if changed.

```lua
function x_mob_core.set_target(self: MobEntity, target: ObjectRef|nil)
  -> changed: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `target` (`ObjectRef|nil`): Target entity or player

**Returns:**

* `changed` (`boolean`): True if target changed

#### `x_mob_core.set_texture`

Sets a mob's active texture variation by index.

```lua
function x_mob_core.set_texture(self: MobEntity|ObjectRef, id: integer, variations?: string[][])
  -> applied: string[]?
```

**Parameters:**

* `self` (`MobEntity|ObjectRef`): Mob entity instance or ObjectRef
* `id` (`integer`): Texture variation index
* `variations` (`string[][]?`): Optional explicit variations list

**Returns:**

* `applied` (`string[]?`): The applied textures array

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
function x_mob_core.halt_horizontal_velocity(self: MobEntity)
```

**Parameters:**

* `self` (`MobEntity`): Entity instance

#### `x_mob_core.has_wall_collision`

Detects if entity has collided with a wall/solid obstacle or is physically stagnant against one.

```lua
function x_mob_core.has_wall_collision(self: MobEntity, current_pos: Vector, dtime: number)
  -> is_colliding: boolean
  2. wall_normal: Vector|nil
  3. node_pos: Vector|nil
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `current_pos` (`Vector`): Current world position
* `dtime` (`number`): Delta time

**Returns:**

* `is_colliding` (`boolean`): Whether the mob is colliding with a wall
* `wall_normal` (`Vector|nil`): Estimated normal pointing away from the wall
* `node_pos` (`Vector|nil`): Position of collided node if known

#### `x_mob_core.is_aquatic_mob`

Checks if an entity is an aquatic mob (fish, shoal, etc.) that swims freely in liquid.

```lua
function x_mob_core.is_aquatic_mob(self: MobEntity)
  -> is_aquatic: boolean
```

**Parameters:**

* `self` (`MobEntity`): Entity instance

**Returns:**

* `is_aquatic` (`boolean`)

#### `x_mob_core.retreat_from`

Executes tactical retreat steering away from a target position.

```lua
function x_mob_core.retreat_from(self: MobEntity, target_pos: Vector, speed?: number)
  -> is_retreating: boolean
```

**Parameters:**

* `self` (`MobEntity`): Entity instance
* `target_pos` (`Vector`): World position to flee from
* `speed` (`number?`): Movement speed multiplier

**Returns:**

* `is_retreating` (`boolean`): Whether retreat movement is actively executing

#### `x_mob_core.scan_for_player`

Scans for living players within radius using field of view and raycast line-of-sight checks.

```lua
function x_mob_core.scan_for_player(self: MobEntity, scan_radius?: number, eye_height?: number)
  -> player: ObjectRef|nil
```

**Parameters:**

* `self` (`MobEntity`): Entity instance
* `scan_radius` (`number?`): Detection radius in nodes (default: mob aggro_radius or 16.0)
* `eye_height` (`number?`): Vertical eye offset in nodes

**Returns:**

* `player` (`ObjectRef|nil`): Nearest visible living player or nil

#### `x_mob_core.set_horizontal_velocity`

Sets horizontal velocity of a mob entity along a given yaw while preserving vertical motion/gravity.

```lua
function x_mob_core.set_horizontal_velocity(self: MobEntity, speed: number, yaw: number)
```

**Parameters:**

* `self` (`MobEntity`): Entity instance
* `speed` (`number`): Horizontal movement speed in nodes/sec
* `yaw` (`number`): Orientation angle in radians

#### `x_mob_core.step_move_or_idle`

Advances directional steering locomotion towards destination or target entity.

```lua
function x_mob_core.step_move_or_idle(self: MobEntity, dtime: number, move_anim?: string, anim_speed?: number, idle_anim?: string)
  -> is_moving: boolean
```

**Parameters:**

* `self` (`MobEntity`): Entity instance
* `dtime` (`number`): Step delta time
* `move_anim` (`string?`): Movement animation track name
* `anim_speed` (`number?`): Animation speed multiplier
* `idle_anim` (`string?`): Idle animation track name

**Returns:**

* `is_moving` (`boolean`): Whether the mob is actively moving

#### `x_mob_core.step_tactical_retreat`

Advances tactical retreat, standoff kiting, and close-quarters retaliation for fleeing mobs.

```lua
function x_mob_core.step_tactical_retreat(self: MobEntity, dtime: number, def?: MobRegistrationDef, moveresult?: EngineMoveResult)
  -> handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Entity instance
* `dtime` (`number`): Step delta time
* `def` (`MobRegistrationDef?`): Entity definition table
* `moveresult` (`EngineMoveResult?`): Engine move result

**Returns:**

* `handled` (`boolean`): Whether tactical retreat intercepted the step

#### `x_mob_core.step_wander_or_idle`

Advances ambient idle or wandering locomotion state for an entity.

```lua
function x_mob_core.step_wander_or_idle(self: MobEntity, dtime: number, walk_anim?: string, idle_anim?: string)
  -> is_moving: boolean
```

**Parameters:**

* `self` (`MobEntity`): Entity instance
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
function x_mob_core.add_follower(leader_self: MobEntity, follower_obj: ObjectRef, force?: boolean)
  -> added: boolean
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob instance
* `follower_obj` (`ObjectRef`): Follower entity object
* `force` (`boolean?`): If true, bypasses max_followers capacity limit (default: false)

**Returns:**

* `added` (`boolean`): True if follower was newly registered, false if already present, full, or invalid

#### `x_mob_core.adopt_nearby_orphans`

Searches nearby area to adopt orphans or re-link separated followers.

```lua
function x_mob_core.adopt_nearby_orphans(leader_self: MobEntity, search_radius?: number)
  -> count: integer
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob instance
* `search_radius` (`number?`): Radius to search in nodes (default: 32.0)

**Returns:**

* `count` (`integer`): Number of orphans adopted

#### `x_mob_core.alert_nearby_allies`

Broadcasts threat alert to nearby pack members or allies within radius.

```lua
function x_mob_core.alert_nearby_allies(pos: Vector, radius?: number, target: ObjectRef, max_allies?: integer)
  -> count: integer
```

**Parameters:**

* `pos` (`Vector`): Center position to broadcast threat from
* `radius` (`number?`): Alert radius in nodes (default: 16.0)
* `target` (`ObjectRef`): Threat target to engage
* `max_allies` (`integer?`): Max allies to alert (default: 4)

**Returns:**

* `count` (`integer`): Number of allies alerted

#### `x_mob_core.apply_pack_buff`

Applies a status effect or buff preset to all active living followers in a leader's pack.

```lua
function x_mob_core.apply_pack_buff(leader_self: MobEntity, buff_def: string|StatusEffectDef, options?: PackBuffOptions)
  -> count: integer
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob entity instance
* `buff_def` (`string|StatusEffectDef`): Buff preset identifier or status effect definition table
* `options` (`PackBuffOptions?`): Configuration options (include_leader, max_targets, sound, vfx)

**Returns:**

* `count` (`integer`): Number of pack entities successfully buffed

#### `x_mob_core.broadcast_threat`

Broadcasts alert to nearby pack members or allies when taking damage or spotting an enemy.
Directly assigns `ent.target = target` and switches unengaged allies to `"combat"`.
Note: This is an imperative one-shot function requiring a valid living `ObjectRef`.
For automated damage and death rallying with spatial memory investigation (navigating
to disturbance coordinates even without line of sight), use declarative `swarm_alert`
in the mob definition instead.

```lua
function x_mob_core.broadcast_threat(self: MobEntity, target: ObjectRef, radius?: number, max_allies?: integer)
  -> count: integer
```

**Parameters:**

* `self` (`MobEntity`): Mob instance
* `target` (`ObjectRef`): Threat target
* `radius` (`number?`): Alert radius in nodes (default: 16.0)
* `max_allies` (`integer?`): Max allies to alert (default: 4)

**Returns:**

* `count` (`integer`): Number of allies alerted

#### `x_mob_core.calculate_repulsion`

Calculates 3D Boids spatial separation with horizontal anti-stacking bias.

```lua
function x_mob_core.calculate_repulsion(self: MobEntity, pos: Vector, radius?: number, strength?: number, horizontal_bias?: boolean)
  -> sep_x: number
  2. sep_y: number
  3. sep_z: number
```

**Parameters:**

* `self` (`MobEntity`): Mob instance
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
function x_mob_core.check_leash(follower_self: MobEntity)
  -> is_leashed: boolean
  2. leader_pos: Vector|nil
  3. dist: number
```

**Parameters:**

* `follower_self` (`MobEntity`): Follower mob instance

**Returns:**

* `is_leashed` (`boolean`): True if within leash limit, false if leashed/separated
* `leader_pos` (`Vector|nil`): Position of leader if valid
* `dist` (`number`): Distance to leader

#### `x_mob_core.clean_followers`

Cleans invalid or dead follower objects from a leader's roster and returns alive count.

```lua
function x_mob_core.clean_followers(leader_self: MobEntity)
  -> count: integer
  2. alive_followers: ObjectRef[]
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob instance

**Returns:**

* `count` (`integer`): Alive follower count
* `alive_followers` (`ObjectRef[]`): Array of living follower ObjectRefs

#### `x_mob_core.elect_successor`

Democratic leader election: surviving pack, swarm, or shoal members elect the first surviving peer as new leader.

```lua
function x_mob_core.elect_successor(self: MobEntity, search_radius?: number)
  -> success: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob instance
* `search_radius` (`number?`): Radius to search for surviving mates (default: 24.0)

**Returns:**

* `success` (`boolean`): True if a new leader was established

#### `x_mob_core.handle_leader_death`

Disbands the pack and notifies all followers when the leader dies.

```lua
function x_mob_core.handle_leader_death(leader_self: MobEntity)
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob instance

#### `x_mob_core.pulse_aura`

Pulses a radius aura applying a positive or neutral effect to allies or pack followers.

```lua
function x_mob_core.pulse_aura(caster_self: MobEntity, aura_def: AuraPulseDef)
  -> count: integer
```

**Parameters:**

* `caster_self` (`MobEntity`): Caster mob entity instance
* `aura_def` (`AuraPulseDef`): Aura specification table (id, effect, radius, target, sound, vfx, max_targets)

**Returns:**

* `count` (`integer`): Number of entities affected

#### `x_mob_core.rally_followers`

Rallies all pack followers to attack a shared target.

```lua
function x_mob_core.rally_followers(leader_self: MobEntity, target: ObjectRef)
  -> count: integer
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob instance
* `target` (`ObjectRef`): Target entity

**Returns:**

* `count` (`integer`): Number of followers rallied

#### `x_mob_core.relink_follower`

Follower searches nearby area to re-link with its pack leader if separated.

```lua
function x_mob_core.relink_follower(follower_self: MobEntity, search_radius?: number)
  -> relinked: boolean
```

**Parameters:**

* `follower_self` (`MobEntity`): Follower mob instance
* `search_radius` (`number?`): Radius to search in nodes (default: 32.0)

**Returns:**

* `relinked` (`boolean`): True if leader was found and re-linked

#### `x_mob_core.remove_follower`

Removes a follower object from a leader's roster.

```lua
function x_mob_core.remove_follower(leader_self: MobEntity, follower_obj: ObjectRef)
  -> removed: boolean
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob instance
* `follower_obj` (`ObjectRef`): Follower entity object

**Returns:**

* `removed` (`boolean`): True if follower was found and removed

#### `x_mob_core.spawn_initial_followers`

Adopts nearby orphans and spawns missing followers radially around the leader.

```lua
function x_mob_core.spawn_initial_followers(leader_self: MobEntity, follower_type?: string, max_count?: integer, spawn_radius?: number)
  -> spawned: integer
```

**Parameters:**

* `leader_self` (`MobEntity`): Leader mob instance
* `follower_type` (`string?`): Entity technical name (default: leader_self.pack_follower_type)
* `max_count` (`integer?`): Target follower count (default: leader_self.pack_max_followers or 3)
* `spawn_radius` (`number?`): Radial spawn distance (default: 1.5)

**Returns:**

* `spawned` (`integer`): Number of followers spawned

#### `x_mob_core.step_flock`

Advances ambient swarm flocking locomotion.

```lua
function x_mob_core.step_flock(self: MobEntity, dtime: number, def: MobRegistrationDef)
  -> is_handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob instance
* `dtime` (`number`): Step delta time
* `def` (`MobRegistrationDef`): Mob definition table

**Returns:**

* `is_handled` (`boolean`): True if flocking logic handled step

#### `x_mob_core.step_regroup`

Handles locomotion for a follower returning to assemble with its pack leader.

```lua
function x_mob_core.step_regroup(self: MobEntity, dtime: number, move_anim?: string, speed_mult?: number)
  -> is_regrouping: boolean
```

**Parameters:**

* `self` (`MobEntity`): Follower mob instance
* `dtime` (`number`): Step delta time
* `move_anim` (`string?`): Movement animation (default: "walk")
* `speed_mult` (`number?`): Speed multiplier (default: 1.25)

**Returns:**

* `is_regrouping` (`boolean`): True if still actively regrouping, false if reached leader or leader lost

#### `x_mob_core.step_shoal`

Advances fish schooling and shoal formation steering during an aquatic mob's step tick.
Coordinates leader-follower anchor swimming, 3D water boundary avoidance, and school panic.

```lua
function x_mob_core.step_shoal(self: MobEntity, dtime: number, def: MobRegistrationDef)
  -> is_handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob instance
* `dtime` (`number`): Step delta time
* `def` (`MobRegistrationDef`): Mob definition table containing shoal configuration

**Returns:**

* `is_handled` (`boolean`): True if shoal logic handled locomotion

#### `x_mob_core.step_swarm`

Advances master swarm AI step (flocking when idle, vortex and dive-bombs in combat).

```lua
function x_mob_core.step_swarm(self: MobEntity, dtime: number, def: MobRegistrationDef)
  -> is_handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob instance
* `dtime` (`number`): Step delta time
* `def` (`MobRegistrationDef`): Mob definition table

**Returns:**

* `is_handled` (`boolean`): True if swarm logic handled step

#### `x_mob_core.step_swarm_combat`

Advances coordinated swarm combat locomotion (vortex holding pattern and dive-bomb runs).

```lua
function x_mob_core.step_swarm_combat(self: MobEntity, dtime: number, def: MobRegistrationDef)
  -> is_handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob instance
* `dtime` (`number`): Step delta time
* `def` (`MobRegistrationDef`): Mob definition table

**Returns:**

* `is_handled` (`boolean`): True if swarm combat handled step

#### `x_mob_core.trigger_cowardice_panic`

Triggers cowardice panic in nearby fellow mobs when a pack member dies.
Causes eligible mobs within radius to enter the flee state and record danger memory.

```lua
function x_mob_core.trigger_cowardice_panic(death_pos: Vector, mob_name: string, radius?: number, panic_duration?: number, danger_dmg?: number)
  -> count: integer
```

**Parameters:**

* `death_pos` (`Vector`): Position of the deceased mob
* `mob_name` (`string`): Name of the entity to match (e.g. "x_mobs:fallen_minion")
* `radius` (`number?`): Search radius (default: 12.0)
* `panic_duration` (`number?`): Duration in seconds for flee state (default: 4.0)
* `danger_dmg` (`number?`): Perceived damage recorded in memory (default: 10)

**Returns:**

* `count` (`integer`): Number of panicked mobs

---

## Combat, Damage, Factions & Loot API

Tool capability damage calculations, weapon wear, water knockback dampening, directional damage particles, damage indicator flashing, child and arrow detachment on death, faction allegiance and enemy checks, predictive intercept aiming, and declarative parabolic loot drops.

#### `x_mob_core.are_allies`

Checks whether two entities or players are allies according to faction and pack rules.

```lua
function x_mob_core.are_allies(a: MobEntity|ObjectRef, b: MobEntity|ObjectRef)
  -> are_allies: boolean
```

**Parameters:**

* `a` (`MobEntity|ObjectRef`): First object, mob entity, or projectile
* `b` (`MobEntity|ObjectRef`): Second object, mob entity, or projectile

**Returns:**

* `are_allies` (`boolean`): True if both entities share allegiance

#### `x_mob_core.are_enemies`

Checks whether two entities or players are enemies according to faction rules.

```lua
function x_mob_core.are_enemies(a: MobEntity|ObjectRef, b: MobEntity|ObjectRef)
  -> are_enemies: boolean
```

**Parameters:**

* `a` (`MobEntity|ObjectRef`): First object, mob entity, or projectile
* `b` (`MobEntity|ObjectRef`): Second object, mob entity, or projectile

**Returns:**

* `are_enemies` (`boolean`): True if entities are hostile to each other

#### `x_mob_core.attach_particles`

Attaches an ongoing or burst particle spawner to a target ObjectRef.

```lua
function x_mob_core.attach_particles(target: ObjectRef, def: ParticleSpawnerDef, playername?: string)
  -> spawner_id: integer?
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `def` (`ParticleSpawnerDef`): Particle spawner definition table
* `playername` (`string?`): Optional player name for selective packet scoping

**Returns:**

* `spawner_id` (`integer?`): Particle spawner identifier

#### `x_mob_core.calculate_punch_damage`

Calculates damage from tool capabilities and mob armor groups, and applies wear to weapon.

```lua
function x_mob_core.calculate_punch_damage(self: MobEntity, puncher?: ObjectRef, time_from_last_punch?: number, tool_capabilities?: ToolCapabilities, dir?: Vector, damage_override?: number)
  -> dmg: number
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `puncher` (`ObjectRef?`): Punching entity or player
* `time_from_last_punch` (`number?`): Time since last punch in seconds
* `tool_capabilities` (`ToolCapabilities?`): Wielded tool capabilities
* `dir` (`Vector?`): Punch direction vector
* `damage_override` (`number?`): Direct damage override (ignores tool capabilities when > 0)

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

#### `x_mob_core.clear_target_particles`

Clears and deletes all active particle spawners for a given target.

```lua
function x_mob_core.clear_target_particles(target: ObjectRef)
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

#### `x_mob_core.dampen_water_knockback`

Dampens punch knockback when an entity is struck inside water.
Reduces horizontal impulse to prevent unrealistic gliding through liquid.

```lua
function x_mob_core.dampen_water_knockback(self: MobEntity)
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance

#### `x_mob_core.delete_particles`

Safely deletes an active particle spawner for a target.

```lua
function x_mob_core.delete_particles(target: ObjectRef, spawner_id: integer, playername?: string)
  -> success: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `spawner_id` (`integer`): Particle spawner identifier
* `playername` (`string?`): Optional player name if spawner was scoped

**Returns:**

* `success` (`boolean`): True if spawner was found and deleted

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
function x_mob_core.get_factions(obj: MobEntity|ObjectRef)
  -> factions: table<string, boolean>
```

**Parameters:**

* `obj` (`MobEntity|ObjectRef`): Target ObjectRef or mob entity

**Returns:**

* `factions` (`table<string, boolean>`): Set of active faction identifiers

#### `x_mob_core.get_knockback_mult`

Returns the effective knockback multiplier for an ObjectRef or LuaEntity.

```lua
function x_mob_core.get_knockback_mult(obj: MobEntity|ObjectRef)
  -> multiplier: number
```

**Parameters:**

* `obj` (`MobEntity|ObjectRef`): Target object or mob entity

**Returns:**

* `multiplier` (`number`): (1.0 for players, mob-defined knockback_mult, or 1.0 default)

#### `x_mob_core.handle_punch`

Universal combat punch intake handler applying damage, threat, knockback, and death callbacks.

```lua
function x_mob_core.handle_punch(self: MobEntity, puncher?: ObjectRef, time_from_last_punch?: number, tool_capabilities?: ToolCapabilities, dir?: Vector, damage?: number, def?: MobRegistrationDef)
  -> handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `puncher` (`ObjectRef?`): Attacking entity or player
* `time_from_last_punch` (`number?`): Elapsed time in seconds since last punch
* `tool_capabilities` (`ToolCapabilities?`): Weapon capabilities and damage groups
* `dir` (`Vector?`): Punch impulse direction vector
* `damage` (`number?`): Base damage override (bypasses tool capability calculation if provided)
* `def` (`MobRegistrationDef?`): Entity definition table

**Returns:**

* `handled` (`boolean`): True if punch was processed and registered

#### `x_mob_core.hide_health_bar`

Hides or removes the dynamic overhead health bar on a mob entity.

```lua
function x_mob_core.hide_health_bar(self: MobEntity, remove_completely?: boolean)
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
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
function x_mob_core.indicate_regen(obj: ObjectRef, color?: string|{ r: integer, g: integer, b: integer, a: integer }, duration?: number)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity object to flash
* `color` (`(string|{ r: integer, g: integer, b: integer, a: integer })?`): Optional custom colorize string or RGBA spec (default: "^[colorize:#FFFFFF60")
* `duration` (`number?`): Optional duration in seconds (default: 0.25)

#### `x_mob_core.is_projectile`

Agnostically checks whether a LuaEntity is classified as a projectile or arrow.

```lua
function x_mob_core.is_projectile(ent: LuaEntitySAO|MobEntity)
  -> is_projectile: boolean
```

**Parameters:**

* `ent` (`LuaEntitySAO|MobEntity`): LuaEntity table

**Returns:**

* `is_projectile` (`boolean`): True if entity has projectile markers

#### `x_mob_core.is_valid_projectile_target`

Validates whether an object is a targetable enemy for a projectile or shooter mob.
Filters out dropped items (__builtin:item), falling nodes, utility entities, shooter self-hits, and allies.

```lua
function x_mob_core.is_valid_projectile_target(source_or_proj: MobEntity|ObjectRef, obj: ObjectRef, options?: ProjectileTargetOptions)
  -> is_valid: boolean
```

**Parameters:**

* `source_or_proj` (`MobEntity|ObjectRef`): Projectile entity instance, shooter mob, or ObjectRef
* `obj` (`ObjectRef`): Target object to test
* `options` (`ProjectileTargetOptions?`): Optional configuration table

**Returns:**

* `is_valid` (`boolean`): True if target is attackable, false if ignored

#### `x_mob_core.perform_melee_attack`

Executes an instantaneous melee strike against a target entity.
Applies fleshy punch damage and triggers the configured on_strike callback or custom perform_attack override.

```lua
function x_mob_core.perform_melee_attack(self: MobEntity, target: ObjectRef, dir: Vector, def?: MobRegistrationDef, m_cfg?: MeleeConfigDef)
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `target` (`ObjectRef`): Target entity to punch
* `dir` (`Vector`): Strike impulse direction vector
* `def` (`MobRegistrationDef?`): Mob definition table
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
function x_mob_core.show_health_bar(self: MobEntity, cur_hp?: number, max_hp?: number)
  -> shown: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `cur_hp` (`number?`): Current health (defaults to self.hp)
* `max_hp` (`number?`): Maximum health (defaults to self.hp_max)

**Returns:**

* `shown` (`boolean`): True if health bar is shown or updated

#### `x_mob_core.spawn_damage_particles`

Spawns directional combat damage particles according to mob settings or global preferences.

```lua
function x_mob_core.spawn_damage_particles(obj: ObjectRef, puncher?: ObjectRef, dir?: Vector, damage?: number, def?: MobRegistrationDef)
```

**Parameters:**

* `obj` (`ObjectRef`): Entity receiving damage
* `puncher` (`ObjectRef?`): Attacker ObjectRef
* `dir` (`Vector?`): Strike/knockback direction vector
* `damage` (`number?`): Damage dealt
* `def` (`MobRegistrationDef?`): Entity definition table

#### `x_mob_core.step_melee`

Advances declarative melee combat for an entity during its step tick.
Validates attack range, raycast line-of-sight, halts horizontal velocity, turns mob to face target,
plays attack animation and sound, and schedules delayed punch execution with reach tolerance.

```lua
function x_mob_core.step_melee(self: MobEntity, dtime: number, def: MobRegistrationDef)
  -> handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `dtime` (`number`): Step delta time
* `def` (`MobRegistrationDef`): Entity definition table containing melee configuration

**Returns:**

* `handled` (`boolean`): True if melee logic handled combat, halting movement

#### `x_mob_core.step_projectile`

Processes a standard projectile flight step: ballistics rotation, lifetime expiry,
continuous raycasting, proximity collision, and impact handling.

```lua
function x_mob_core.step_projectile(self: MobEntity, dtime: number, options?: ProjectileStepOptions)
  -> hit: boolean
  2. hit_obj: ObjectRef|nil
  3. hit_pos: Vector|nil
```

**Parameters:**

* `self` (`MobEntity`): Projectile LuaEntity instance
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
function x_mob_core.step_shooter(self: MobEntity, dtime: number, def: MobRegistrationDef)
  -> handled: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance
* `dtime` (`number`): Step delta time
* `def` (`MobRegistrationDef`): Entity definition table containing shooter configuration

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
function x_mob_core.update_health_bar(self: MobEntity)
  -> shown: boolean
```

**Parameters:**

* `self` (`MobEntity`): Mob entity instance

**Returns:**

* `shown` (`boolean`): True if health bar was updated

---

## Status Effects, Envelops & Screen Vignettes API

Compound player and entity status effects (buffs, debuffs, DoTs, HoTs, roots, haste, slow, thorns), dynamic physical movement speed / jump / gravity / FOV modifiers, multi-effect stacking, 3D open rectangular sleeve visual envelops, and client-side responsive fullscreen HUD screen vignettes.

#### `x_mob_core.apply_buff`

Applies a buff (positive status effect) by preset name or definition.

```lua
function x_mob_core.apply_buff(target: ObjectRef, preset_or_def: string|StatusEffectDef, overrides?: StatusEffectOverrideDef)
  -> result: boolean|ObjectRef
```

**Parameters:**

* `target` (`ObjectRef`): Target player or mob entity
* `preset_or_def` (`string|StatusEffectDef`): Preset name or custom effect definition
* `overrides` (`StatusEffectOverrideDef?`): Optional field overrides (duration, level, etc.)

**Returns:**

* `result` (`boolean|ObjectRef`): Envelop object if envelop attached, or true on success

#### `x_mob_core.apply_envelop`

Applies or updates a visual sleeve envelop and status effect on target.

```lua
function x_mob_core.apply_envelop(target: ObjectRef, effect_def: EnvelopEffectDef)
  -> Envelop: ObjectRef?
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity to envelop
* `effect_def` (`EnvelopEffectDef`): Configuration: { id: string, duration: number, texture: string }

**Returns:**

* `Envelop` (`ObjectRef?`): entity object

#### `x_mob_core.apply_status_effect`

Applies or refreshes a status effect on target (player or mob entity).

```lua
function x_mob_core.apply_status_effect(target: ObjectRef, effect_def: StatusEffectDef)
  -> result: boolean|ObjectRef
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `effect_def` (`StatusEffectDef`): Status effect definition table

**Returns:**

* `result` (`boolean|ObjectRef`): Envelop object if envelop attached, or true on success

#### `x_mob_core.apply_vignette`

Applies or updates a fullscreen responsive screen vignette on a target player.

```lua
function x_mob_core.apply_vignette(player: ObjectRef, effect_id: string, config?: string|VignetteConfig)
  -> hud_id: integer?
```

**Parameters:**

* `player` (`ObjectRef`): Target player
* `effect_id` (`string`): Unique status effect identifier
* `config` (`(string|VignetteConfig)?`): Vignette configuration table or texture modifier

**Returns:**

* `hud_id` (`integer?`): Numerical HUD element ID or nil

#### `x_mob_core.cleanse_debuffs`

Cleanses all negative debuffs from target.

```lua
function x_mob_core.cleanse_debuffs(target: ObjectRef)
  -> count: integer
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `count` (`integer`): Number of cleansed debuffs

#### `x_mob_core.clear_status_effects`

Clears all active status effects and restores baseline physics on target.

```lua
function x_mob_core.clear_status_effects(target: ObjectRef)
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

#### `x_mob_core.clear_vignettes`

Clears all active vignettes and destroys the HUD element for a player.

```lua
function x_mob_core.clear_vignettes(player: ObjectRef)
```

**Parameters:**

* `player` (`ObjectRef`): Target player

#### `x_mob_core.dispel_buffs`

Dispels all positive buffs from target.

```lua
function x_mob_core.dispel_buffs(target: ObjectRef)
  -> count: integer
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `count` (`integer`): Number of dispelled buffs

#### `x_mob_core.get_attack_multiplier`

Calculates current attack power multiplier for target across all active status effects.

```lua
function x_mob_core.get_attack_multiplier(target: ObjectRef)
  -> multiplier: number
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `multiplier` (`number`): Compound attack multiplier (default: 1.0)

#### `x_mob_core.get_damage_multiplier`

Calculates current incoming damage multiplier for target across all active status effects.

```lua
function x_mob_core.get_damage_multiplier(target: ObjectRef)
  -> multiplier: number
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `multiplier` (`number`): Compound damage multiplier (default: 1.0)

#### `x_mob_core.get_envelop_data`

Returns active envelop data record for target if present.

```lua
function x_mob_core.get_envelop_data(target: ObjectRef)
  -> data: EnvelopTargetRecord?
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `data` (`EnvelopTargetRecord?`): Active envelop metadata

#### `x_mob_core.get_knockback_resilience`

Calculates total knockback resilience ratio [0.0, 1.0] for target.

```lua
function x_mob_core.get_knockback_resilience(target: ObjectRef)
  -> resilience: number
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `resilience` (`number`): Knockback resilience ratio (0.0 = full knockback, 1.0 = immune)

#### `x_mob_core.get_speed_multiplier`

Calculates current speed multiplier for target across all active status effects.

```lua
function x_mob_core.get_speed_multiplier(target: ObjectRef)
  -> multiplier: number
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `multiplier` (`number`): Compound speed multiplier (default: 1.0)

#### `x_mob_core.get_status_effect_preset`

Retrieves a registered status effect preset configuration by ID.

```lua
function x_mob_core.get_status_effect_preset(id: string)
  -> def: StatusEffectDef?
```

**Parameters:**

* `id` (`string`): Preset name

**Returns:**

* `def` (`StatusEffectDef?`): Preset definition table or nil

#### `x_mob_core.get_status_effects`

Retrieves all active status effects for a target.

```lua
function x_mob_core.get_status_effects(target: ObjectRef)
  -> effects: table<string, ActiveEffectRecord>?
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `effects` (`table<string, ActiveEffectRecord>?`): Active status effects map

#### `x_mob_core.get_thorns`

Retrieves active thorns configuration on target if any.

```lua
function x_mob_core.get_thorns(target: ObjectRef)
  -> thorns: ThornsDef?
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `thorns` (`ThornsDef?`): Thorns definition { damage: number, damage_type?: string, chance?: number }

#### `x_mob_core.get_vignette_prominence_multiplier`

Gets the global vignette prominence / opacity scaling multiplier.

```lua
function x_mob_core.get_vignette_prominence_multiplier()
  -> multiplier: number
```

**Returns:**

* `multiplier` (`number`): Current vignette prominence multiplier

#### `x_mob_core.has_envelop`

Convenience alias for `is_enveloped`. Checks if target currently has an active envelop or a specific active effect.

```lua
function x_mob_core.has_envelop(target: ObjectRef, effect_id?: string)
  -> is_enveloped: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `effect_id` (`string?`): Optional specific effect ID to query

**Returns:**

* `is_enveloped` (`boolean`): True if active envelop/effect exists

#### `x_mob_core.has_status_effect`

Checks if target currently has an active status effect.

```lua
function x_mob_core.has_status_effect(target: ObjectRef, effect_id: string)
  -> has_effect: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `effect_id` (`string`): Unique effect ID

**Returns:**

* `has_effect` (`boolean`): True if effect is active

#### `x_mob_core.has_vignette`

Checks if a player currently has an active screen vignette.

```lua
function x_mob_core.has_vignette(player: ObjectRef, effect_id?: string)
  -> has_vignette: boolean
```

**Parameters:**

* `player` (`ObjectRef`): Target player
* `effect_id` (`string?`): Optional specific effect ID

**Returns:**

* `has_vignette` (`boolean`): True if active

#### `x_mob_core.is_enveloped`

Checks if target currently has an active envelop or a specific active effect.

```lua
function x_mob_core.is_enveloped(target: ObjectRef, effect_id?: string)
  -> is_enveloped: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `effect_id` (`string?`): Optional specific effect ID to query

**Returns:**

* `is_enveloped` (`boolean`): True if active envelop/effect exists

#### `x_mob_core.is_rooted`

Checks if target is currently rooted / immobilized.

```lua
function x_mob_core.is_rooted(target: ObjectRef)
  -> is_rooted: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `is_rooted` (`boolean`): True if target has an active root status effect or speed_factor <= 0

#### `x_mob_core.register_status_effect_preset`

Registers a reusable status effect preset configuration (buff or debuff).

```lua
function x_mob_core.register_status_effect_preset(id: string, def: StatusEffectDef)
```

**Parameters:**

* `id` (`string`): Unique preset name (e.g. "frenzy", "ironhide", "haste")
* `def` (`StatusEffectDef`): Preset configuration table

#### `x_mob_core.register_status_preset`

Convenience alias for `register_status_effect_preset`. Registers a reusable status effect preset configuration.

```lua
function x_mob_core.register_status_preset(id: string, def: StatusEffectDef)
```

**Parameters:**

* `id` (`string`): Unique preset name (e.g. "frenzy", "ironhide", "haste")
* `def` (`StatusEffectDef`): Preset configuration table

#### `x_mob_core.register_vignette`

Registers or overrides a custom vignette texture or config for an effect ID.

```lua
function x_mob_core.register_vignette(effect_id: string, texture_spec: string|VignetteConfig)
```

**Parameters:**

* `effect_id` (`string`): Unique status effect ID
* `texture_spec` (`string|VignetteConfig`): Configuration table or texture modifier string

#### `x_mob_core.remove_envelop`

Removes all active effects and detaches/removes envelop entity from target.

```lua
function x_mob_core.remove_envelop(target: ObjectRef)
  -> nil
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity

**Returns:**

* `nil`

#### `x_mob_core.remove_envelop_effect`

Removes a specific active effect from target's envelop, preserving remaining effects.

```lua
function x_mob_core.remove_envelop_effect(target: ObjectRef, effect_id: string)
  -> nil
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `effect_id` (`string`): Unique effect ID to remove

**Returns:**

* `nil`

#### `x_mob_core.remove_status_effect`

Removes an active status effect from target.

```lua
function x_mob_core.remove_status_effect(target: ObjectRef, effect_id: string)
  -> success: boolean
```

**Parameters:**

* `target` (`ObjectRef`): Target player or entity
* `effect_id` (`string`): Unique effect ID to remove

**Returns:**

* `success` (`boolean`): True if effect was removed

#### `x_mob_core.remove_vignette`

Removes an active vignette effect for a player, restoring or updating composite overlays.

```lua
function x_mob_core.remove_vignette(player: ObjectRef, effect_id: string)
  -> removed: boolean
```

**Parameters:**

* `player` (`ObjectRef`): Target player
* `effect_id` (`string`): Unique status effect identifier

**Returns:**

* `removed` (`boolean`): True if vignette was found and removed

#### `x_mob_core.scale_damage_groups`

Scales damage groups by an attack multiplier.

```lua
function x_mob_core.scale_damage_groups(damage_groups: table<string, number>, multiplier: number)
  -> scaled: table<string, number>
```

**Parameters:**

* `damage_groups` (`table<string, number>`): Damage group table
* `multiplier` (`number`): Attack power multiplier

**Returns:**

* `scaled` (`table<string, number>`): Scaled copy of damage groups

#### `x_mob_core.set_default_vignette`

Sets the global default base vignette texture asset.

```lua
function x_mob_core.set_default_vignette(texture_name: string)
```

**Parameters:**

* `texture_name` (`string`): Texture asset filename

#### `x_mob_core.set_vignette_prominence_multiplier`

Sets the global vignette prominence / opacity scaling multiplier.

```lua
function x_mob_core.set_vignette_prominence_multiplier(multiplier: number)
```

**Parameters:**

* `multiplier` (`number`): Prominence multiplier (e.g. 1.0 = standard, 1.5 = high contrast)

---

## Spawner Engine API

Natural mob spawning engine, environmental condition validation, light and elevation limits, active entity caps, and cohesive group spawning.

#### `x_mob_core.register_spawn`

Registers a mob definition for natural map generation and environment spawning.

```lua
function x_mob_core.register_spawn(mob_name: string, def: MobSpawnDef)
```

**Parameters:**

* `mob_name` (`string`): Registered entity technical name (e.g. "x_mobs:spider")
* `def` (`MobSpawnDef`): Environmental spawning parameters and condition filters

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
function x_mob_core.spawn_mob_group(spawn_pos: Vector, def: string|MobSpawnDef, source?: string)
  -> count: integer
```

**Parameters:**

* `spawn_pos` (`Vector`): World center position
* `def` (`string|MobSpawnDef`): Spawn definition table or entity technical name
* `source` (`string?`): Optional spawner mechanism identifier (default: "Custom Spawning")

**Returns:**

* `count` (`integer`): Number of mobs successfully spawned

---

## Audio & Sound Subsystem API

Positional audio dispatcher, spatial distance attenuation, and pitch variation for mob sound cues.

#### `x_mob_core.play_sound`

Plays a configured sound type for a mob instance with positional audio and pitch variation.

```lua
function x_mob_core.play_sound(self: MobEntity|ObjectRef, sound_type: string, overrides?: SoundOverrides)
  -> sound_handle: integer?
```

**Parameters:**

* `self` (`MobEntity|ObjectRef`): Mob entity instance or ObjectRef
* `sound_type` (`string`): Category ("hurt", "death", "random", "attack", "alert") or technical sound name
* `overrides` (`SoundOverrides?`): Optional overrides (gain, distance, pitch, pos, object, to_player, loop)

**Returns:**

* `sound_handle` (`integer?`): Luanti sound handle or nil if not played

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
function x_mob_core.emit(event_name: string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_rightclick"...(+2), ...any)
```

**Parameters:**

* `event_name` (`string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_rightclick"...(+2)`): Event identifier
* `?` (`any`): Arguments passed to listeners

#### `x_mob_core.find_ground_level`

Finds the top surface Y coordinate of the solid walkable ground below a given 3D position.

```lua
function x_mob_core.find_ground_level(x: number, start_y: number, z: number, max_down?: number)
  -> ground_y: number?
```

**Parameters:**

* `x` (`number`): X world coordinate
* `start_y` (`number`): Y world coordinate
* `z` (`number`): Z world coordinate
* `max_down` (`number?`): Maximum distance to search downwards (default: 36)

**Returns:**

* `ground_y` (`number?`): Top surface Y of solid node, or nil if none found

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
  -> ground_y: number?
```

**Parameters:**

* `pos` (`Vector`): Position to check
* `max_down` (`number?`): Maximum distance to search downwards (default: 8)
* `max_up` (`number?`): Maximum distance to search upwards (default: 3)
* `walkable_only` (`boolean?`): If true, requires walkable non-liquid node with headroom (default: true)

**Returns:**

* `ground_y` (`number?`): Top surface height of highest ground node, or nil

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
function x_mob_core.listen(event_name: string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_rightclick"...(+2), callback: fun(...any))
  -> id: integer
```

**Parameters:**

* `event_name` (`string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_rightclick"...(+2)`): Event identifier (e.g. "on_mob_death", "on_mob_spawn", "on_mob_target")
* `callback` (`fun(...any)`): Callback function invoked when event is emitted

**Returns:**

* `id` (`integer`): Listener registration token

#### `x_mob_core.pick_ground_waypoint`

Picks a ground-anchored wander waypoint near current position over solid walkable nodes.

```lua
function x_mob_core.pick_ground_waypoint(current_pos: Vector, origin?: Vector, radius?: number, min_dist?: number, max_dist?: number, hover_offset?: number)
  -> waypoint: Vector?
```

**Parameters:**

* `current_pos` (`Vector`): Current mob world position
* `origin` (`Vector?`): Center origin of wander boundary (default: current_pos)
* `radius` (`number?`): Maximum wander radius from origin (default: 10.0)
* `min_dist` (`number?`): Minimum step distance from current position (default: 3.0)
* `max_dist` (`number?`): Maximum step distance from current position (default: 7.5)
* `hover_offset` (`number?`): Vertical offset above detected ground (default: 1.4)

**Returns:**

* `waypoint` (`Vector?`): Ground-anchored target position or nil

#### `x_mob_core.shallow_copy`

Shallow copies a table.

```lua
function x_mob_core.shallow_copy(tbl: <T:table>)
  -> <T:table>
```

**Parameters:**

* `tbl` (`<T:table>`)

**Returns:**

* `<T:table>`

#### `x_mob_core.unlisten`

Unregisters an event listener from the x_mob_core pub-sub event bus.

```lua
function x_mob_core.unlisten(event_name: string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_rightclick"...(+2), id: integer)
  -> success: boolean
```

**Parameters:**

* `event_name` (`string|"on_mob_death"|"on_mob_despawn"|"on_mob_hurt"|"on_mob_rightclick"...(+2)`): Event identifier
* `id` (`integer`): Listener registration token returned by listen()

**Returns:**

* `success` (`boolean`): True if listener was found and removed

---

## Registries & State Tables

| Registry / Table | Type | Description |
| :--- | :--- | :--- |
| `x_mob_core.registered_mobs` | `table<string, MobRegistrationDef>` | Registry of all active mob definitions |
| `x_mob_core.registered_spawns` | `MobSpawnDef[]` | Registry of all active natural spawn configurations |
