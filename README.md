# X Mob Core [`x_mob_core`]

[![ContentDB](https://content.luanti.org/packages/SaKeL/x_mob_core/shields/title/)](https://content.luanti.org/packages/SaKeL/x_mob_core/)
[![ContentDB Downloads](https://content.luanti.org/packages/SaKeL/x_mob_core/shields/downloads/)](https://content.luanti.org/packages/SaKeL/x_mob_core/)
![Luanti](https://img.shields.io/badge/Luanti-5.17%2B-5599ff.svg)
[![Luacheck](https://img.shields.io/github/actions/workflow/status/sakel-hub/x_mob_core/luacheck.yml?label=Luacheck&logo=lua)](https://github.com/sakel-hub/x_mob_core/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.txt)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/sakel-hub/x_mob_core/pulls)
![AI-Assisted](https://img.shields.io/badge/AI--assisted-gray)

A high-performance, **zero-dependency** mob engine and spawner framework for Luanti built on **S.O.L.I.D.** architecture principles.

![X Mob Core Technical Blueprint Showcase](screenshot.png)

---

## Features

- **Zero External Dependencies**: Operates exclusively with native Luanti engine C++ APIs (`core.*`).
- **3D A\* Hierarchical Pathfinding**:
  - Binary min-heap priority queue with zero-allocation push/pop operations.
  - Volumetric multi-ray corridor line-of-sight check bypassing expensive graph traversals.
  - LRU path caching and pre-cached Content ID (CID) flat lookups.
  - Asynchronous coroutine time-sliced path search with strict 1.5ms per-tick CPU budget.
- **Motor & Steering Controller**:
  - Pursuit-gated traversal (smart door opening, ladder climbing, liquid swimming).
  - Surface climbing and dynamic rotation interpolation.
  - Tactical retreat and flee steering vectors.
  - Multiplayer distance-based LOD execution and idle culling.
- **glTF Multi-Track Animator**:
  - Native Luanti glTF named track playback with priority blending and track transition clearing.
  - Zero-latency runtime playback speed scaling and looping track synchronization.
  - Frame-range fallback for legacy skeletal animations.
- **Combat & Damage Subsystems**:
  - Declarative melee combat (`melee = { range = ..., damage = ..., cooldown = ..., duration = ..., delay = ... }`) with automatic reach tolerance, horizontal halting, animation timing, and impact damage.
  - Declarative ranged combat & intercept aiming (`shooter = { projectile = ..., range = ..., min_range = ..., velocity = ..., predict_aim = ... }`) with tactical kiting and aim prediction.
  - Native tool capabilities calculation, damage groups, and weapon wear mechanics.
  - Directional damage particles (configurable blood, ichor, smoke, spectral, sparks) and damage indicator flashing.
  - Liquid knockback dampening and configurable knockback resistance multipliers.
  - Factions and allegiance system (`x_mob_core.are_allies`, `x_mob_core.are_enemies`).
  - Ballistic intercept aim prediction (`x_mob_core.predict_aim`) and projectile flight/collision pipeline (`x_mob_core.step_projectile`, `x_mob_core.is_valid_projectile_target`).
  - Declarative loot drop tables with radial parabolic fountain drops (`x_mob_core.drop_items`).
  - Procedural `[combine:` overhead health bars with 5-tier color palettes, proportional bounding box scaling, head clearance, and auto-resetting timeout windows.
  - Universal child, passenger, and arrow detachment on entity death.
- **Status Effects, 3D Envelops & Fullscreen Vignettes**:
  - Centralized status effects framework (`x_mob_core.apply_status_effect`, `x_mob_core.remove_status_effect`, `x_mob_core.has_status_effect`, `x_mob_core.get_damage_multiplier`).
  - Compound player physics override aggregation (`speed_factor`, `jump_factor`, `gravity_factor`) supporting `player_monoids`, `pova`, and vanilla fallbacks.
  - Armor-penetrating Damage-over-Time (DoT) tickers with custom interval and particle spawner callbacks.
  - 3D visual envelop sleeve attachments (`x_mob_core.apply_envelop`) mapped to entities and players.
  - Full-viewport responsive screen vignette HUD subsystem (`x_mob_core.hud_effects`) with multi-effect compositing and dynamic colorization.
  - Multi-mod hunger and stamina drain adapter (`x_mob_core.hunger_adapter`) with anti-heal suppression compatible with `stamina`, `hbhunger`, and `hunger_ng`.
- **Pack Coordination & Swarm Intelligence**:
  - Pack UUID generation, leader-follower registry, and automatic orphan adoption.
  - Spatial leash tethering, regroup steering vectors, and rally commands.
  - Shared threat and aggro broadcasting with cowardice panic propagation.
  - 3D Boids spatial separation with horizontal anti-stacking bias.
  - Aerial swarm flocking and coordinated dive-bomb combat patterns (`pack/swarm.lua`).
  - Aquatic shoal flocking and synchronized swimming (`pack/shoal.lua`).
  - Democratic leader election (`x_mob_core.elect_successor`) upon leader death.
- **Dynamic Natural Spawner**:
  - Mapgen population pass (`core.register_on_generated`) and player-proximity trickle loop without ABMs.
  - Dynamic ground filtering from registered spawn node lists and group definitions (`group:soil`, `group:stone`).
  - Cohesive group spawning with safe radial distribution (`x_mob_core.spawn_mob_group`).
  - Detailed environmental condition filters: light thresholds, time-of-day windows, elevation limits, and density caps.
- **Lifecycle, Pipeline & Event Bus**:
  - Prioritized step middleware pipeline (`x_mob_core.register_step_hook`) for modular gameplay expansions.
  - Entity-tied action scheduler (`x_mob_core.schedule`) safe against entity death and despawning.
  - Pub-sub event bus (`listen`, `unlisten`, `emit`) for decoupled mod hooks (`on_mob_spawn`, `on_mob_death`, `on_mob_target`, `on_mob_damage`).
- **Positional Audio Subsystem**:
  - Spatial distance attenuation and pitch randomization for hurt, death, attack, ambient, and alert sound cues.

---

## Architecture

```text
x_mob_core/
├── mod.conf                 # Mod metadata and dependencies
├── .cdb.json                # ContentDB package metadata
├── LICENSE.txt              # MIT License
├── README.md                # Mod documentation and showcase
├── API.md                   # Complete API reference and EmmyLua documentation
├── settingtypes.txt         # Engine configuration settings
├── api.lua                  # Public API namespace 'x_mob_core'
├── init.lua                 # Bootstrap entry point
├── core/
│   ├── types.lua            # EmmyLua type definitions and interfaces
│   ├── utils.lua            # UUID generator, line-of-sight, ground scan helpers
│   └── events.lua           # Event bus registry (pub/sub)
├── navigation/
│   ├── min_heap.lua         # Binary min-heap priority queue
│   ├── path_cache.lua       # Content ID and path cache
│   ├── fast_pathfinder.lua  # Volumetric raycasts and 3D A* search
│   └── mob_memory.lua       # Spatial memory blackboard
├── motor/
│   ├── node_cache.lua       # Cached VoxelArea & node lookups
│   ├── doors.lua            # Door opening detection and interaction
│   ├── surface.lua          # Surface alignment and rotation interpolation
│   ├── safety.lua           # Aquatic detection, shore finding, step safety checks
│   ├── locomotion.lua       # Yaw, velocity, liquid buoyancy, wall collision, movement
│   └── mob_ai.lua           # Navigation coordinator (pursuit-gating, wander/move steps)
├── animation/
│   └── animator.lua         # glTF multi-track dispatcher
├── combat/
│   ├── damage.lua           # Damage calculation and tool wear
│   ├── knockback.lua        # Knockback physics dampening
│   ├── effects.lua          # Damage indication and directional particles
│   ├── factions.lua         # Faction allegiance and relationship checks
│   ├── health_bar.lua       # Procedural overhead health bar rendering and color bands
│   ├── melee.lua            # Declarative melee combat, reach checks, and attack delays
│   ├── shooter.lua          # Predictive intercept aiming, kiting, and projectile pipeline
│   ├── loot.lua             # Radial parabolic item drops and declarative drop tables
│   ├── envelop.lua          # Reusable 3D sleeve envelop framework
│   ├── status_effects.lua   # Centralized status effects, physics overrides, and DoTs
│   ├── hud_effects.lua      # Responsive full-viewport HUD screen vignettes
│   ├── hunger_adapter.lua   # Multi-mod hunger and stamina drain adapter
│   └── detachment.lua       # Child, passenger, and arrow detachment on death
├── spawning/
│   ├── registry.lua         # Spawn rule registry
│   ├── conditions.lua       # Ground, light, elevation, density validators
│   └── engine.lua           # Mapgen and trickle spawner loops
├── pack/
│   ├── squad.lua            # Leader/follower tracking, orphan adoption, and leader election
│   ├── coordination.lua     # Spatial leash tethering and aggro broadcast
│   ├── swarm.lua            # 3D aerial flocking, vortex holding, and dive-bomb runs
│   └── shoal.lua            # Aquatic schooling, alignment, and separation
├── lifecycle/
│   ├── entity_wrapper.lua   # Engine entity registration adapter
│   ├── state_machine.lua    # State execution pipeline (idle, walk, combat, flee, custom)
│   ├── combat_handler.lua   # Universal combat punch intake and event dispatching
│   ├── culling.lua          # Multiplayer distance-based LOD and sleep culling
│   ├── environment.lua      # Node interaction, fall damage, and liquid buoyancy
│   ├── pipeline.lua         # Prioritized step middleware pipeline
│   └── properties.lua       # Dynamic property sync and scale management
└── audio/
    └── sound.lua            # Positional audio dispatcher and pitch variation
```

---

## API Quickstart

For full documentation of all classes, types, and methods, see [API.md](API.md).

### 1. Registering a Custom Melee Mob

```lua
x_mob_core.register_mob("mymod:goblin", {
    initial_properties = {
        hp_max = 20,
        mesh = "mymod_goblin.glb",
        textures = {
            "mymod_goblin.png",
            "mymod_goblin.png^[colorize:#22aa55:30", -- Forest goblin variant
        },
        collisionbox = {-0.3, -0.01, -0.3, 0.3, 1.2, 0.3},
        visual_size = {x = 1.0, y = 1.0},
        stepheight = 1.1,
    },

    -- Faction Allegiance & Combat Attributes
    factions = { "goblin", "monsters" },
    armor_groups = { fleshy = 100 },
    aggro_radius = 16.0,
    knockback_mult = 0.8,
    damage_effect = { type = "blood", count = 10 },

    -- Locomotion & Physics Tuning (Flat properties on def)
    walk_speed = 3.0,
    pursuit_speed = 4.5,
    wander_speed = 1.8,
    wander_radius = 12.0,
    can_swim = true,
    can_climb = true,
    can_open_doors = true,
    can_crawl = false,

    -- Declarative Melee Combat Pipeline
    melee = {
        range = 2.0,
        damage = 4,
        cooldown = 1.2,
        duration = 0.5,
        delay = 0.25,
        animation = "attack",
        sound = "attack",
    },

    -- Skeletal glTF Multi-Track Animations Map
    animations = {
        idle   = { track = "idle",   speed = 1.0, loop = true },
        walk   = { track = "walk",   speed = 1.0, loop = true },
        run    = { track = "run",    speed = 1.2, loop = true },
        attack = { track = "attack", speed = 1.2, loop = false },
        death  = { track = "death",  speed = 1.0, loop = false },
    },

    -- Positional Audio Feedback
    sounds = {
        distance = 16.0,
        gain = 0.8,
        hurt = "mymod_goblin_hurt",
        death = "mymod_goblin_death",
        random = "mymod_goblin_ambient",
        attack = "mymod_goblin_attack",
    },

    -- Declarative Loot Drops (Radial parabolic launch)
    drops = {
        { name = "default:gold_lump", chance = 0.25, min = 1, max = 2 },
        { name = "default:flint",     chance = 0.50, min = 1, max = 3 },
    },

    -- Overhead Combat Health Bar (Enabled by default; fully customizable)
    health_bar = {
        enabled = true,                     -- Overhead health bar display on damage
        width = 64,                         -- Texture canvas width in px
        height = 8,                         -- Texture canvas height in px
        timeout = 4.0,                      -- Duration before auto-hiding (resets on damage)
        auto_scale = true,                  -- Proportional scaling relative to mob bounding box
        spacing = 0.35,                     -- Vertical clearance above collisionbox top
        colors = {
            { threshold = 0.80, color = "#00FF00" }, -- Emerald Green
            { threshold = 0.60, color = "#7CFC00" }, -- Lime
            { threshold = 0.40, color = "#FFD700" }, -- Gold
            { threshold = 0.20, color = "#FF8C00" }, -- Dark Orange
            { threshold = 0.00, color = "#FF2200" }, -- Crimson Red
        },
    },

    -- Health Regeneration & Tactical Retreat
    -- Default: Tactical Disengage & Vulnerable Channel (sprints away, channels heal, re-engages)
    -- Continuous retreat with per-second regen: unlimited_flee = true
    health_regen = {
        enabled = true,                     -- Enable health regeneration and retreat (default: true)
        flee_threshold = 6,                 -- Absolute HP threshold to trigger retreat (default: 25% max HP)
        return_threshold = 14,              -- Absolute HP threshold to exit retreat & re-engage (default: 60% max HP)
        burst_duration = 3.5,               -- Sprint burst seconds before channeling (default: 3.5s)
        channel_duration = 3.0,             -- Seconds stationary channeling heal (default: 3.0s)
        safe_distance = 10.0,               -- Distance in nodes to halt and channel early (default: 10.0m)
        heal_amount = 8,                    -- HP restored on channel completion (default: return - flee)
        flee_speed = 4.2,                   -- Balanced sprint speed in m/s (default: <= 4.2 m/s for catchability)
        overlay = true,                     -- Flash white texture overlay on heal / channel pulse (default: true)
        overlay_color = "^[colorize:#FFFFFF60", -- Custom overlay tint (default: white)
        passive = false,                    -- Enable passive recovery out of combat (default: false)
        rate = 0.5,                         -- HP/s for passive recovery or unlimited_flee (default: 0.5)
        unlimited_flee = false,             -- Set true for cowardly mobs to flee continuously without channel
    },

    -- Pack & Squad Coordination (Handled automatically by x_mob_core)
    pack = {
        role = "member",
        leader_type = "mymod:goblin_chief",
        leash_distance = 16.0,
        regroup_distance = 4.0,
        on_leader_lost = "flee",
        swarm_alert = true,
    },

    -- Declarative Pack Threat Rally
    swarm_alert = {
        enabled = true,
        radius = 16.0,
        max_allies = 4,
    },

    -- Optional Custom States
    custom_states = {
        ["dance"] = {
            enter = function(self)
                x_mob_core.play_animation(self.object, "dance")
            end,
            step = function(self, dtime)
                -- Custom state logic
            end,
            exit = function(self)
                x_mob_core.stop_animation(self.object, "dance")
            end,
        }
    },
})
```

### 2. Registering a Ranged / Archer Mob

```lua
x_mob_core.register_mob("mymod:skeleton_archer", {
    initial_properties = {
        hp_max = 20,
        mesh = "mymod_skeleton.glb",
        textures = { "mymod_skeleton.png" },
        collisionbox = {-0.35, 0.0, -0.35, 0.35, 1.8, 0.35},
        visual_size = {x = 1.0, y = 1.0},
    },

    factions = { "undead", "skeleton" },
    aggro_radius = 20.0,
    walk_speed = 3.2,
    pursuit_speed = 4.0,
    wander_speed = 1.8,
    knockback_mult = 0.5,
    damage_effect = { type = "none" },

    -- Declarative Ranged Combat & Tactical Kiting
    shooter = {
        projectile = "mymod:arrow",         -- Technical entity name of spawned projectile
        velocity = 18.0,                    -- Projectile launch velocity in nodes/s
        damage = 5,                         -- Projectile impact damage
        range = 16.0,                       -- Maximum firing range in nodes
        min_range = 5.0,                    -- Minimum distance before kiting/backing away
        cooldown = 2.5,                     -- Firing cooldown in seconds
        fire_duration = 0.8,                -- Windup / draw duration holding pose
        fire_delay = 0.4,                   -- Delay before projectile releases
        animation = "shoot",                -- Animation track for drawing/shooting
        sound = "mymod_bow_shoot",          -- Sound played on release
        predict_aim = true,                 -- Intercept lead aiming based on target velocity
        retreat_speed = 3.5,                -- Movement speed while kiting
        shoot_while_retreating = true,      -- Can fire arrows while backing away
    },

    animations = {
        idle  = { track = "idle",  speed = 1.0, loop = true },
        walk  = { track = "walk",  speed = 1.0, loop = true },
        run   = { track = "run",   speed = 1.0, loop = true },
        shoot = { track = "shoot", speed = 1.0, loop = false },
        death = { track = "death", speed = 1.0, loop = false },
    },
})
```

### 3. Registering Natural Spawning

```lua
x_mob_core.register_spawn("mymod:goblin", {
    nodes = { "group:soil", "default:dirt_with_grass", "default:stone" },
    biomes = { "grassland", "deciduous_forest" },
    chance = 2000,
    active_object_count = 3,
    max_total_in_radius = 6,
    group_min = 2,
    group_max = 4,
    min_light = 0,
    max_light = 12,
    min_elevation = -31000,
    max_elevation = 31000,
    night_only = true,
})
```

### 4. Event Bus Integration

Listen to decoupled lifecycle and combat events:

```lua
x_mob_core.listen("on_mob_death", function(self, killer)
    if killer and killer:is_player() then
        core.chat_send_player(killer:get_player_name(), "You vanquished " .. self.name .. "!")
    end
end)
```

### 5. Step Pipeline Middleware

Inject custom crowd-control or status effect logic into the entity update loop without modifying core files:

```lua
-- Priority 10: Crowd-control hook halts movement and attacks before standard combat
x_mob_core.register_step_hook("mymod:freeze_aura", 10, function(self, _dtime, _def, _moveresult)
    if self.is_frozen then
        x_mob_core.halt_horizontal_velocity(self)
        return true -- Halts subsequent pipeline steps and locomotion
    end
end)
```

### 6. Applying Status Effects & 3D Envelops

Apply custom status effects with compound physics modifiers, 3D visual sleeves, and responsive fullscreen HUD vignettes:

```lua
-- Apply an armor-penetrating burn with visual envelop sleeve and responsive HUD vignette
x_mob_core.apply_status_effect(target, {
    id = "ignite",
    duration = 4.0,
    interval = 1.0,
    damage = 1,
    speed_factor = 0.85,
    envelop_texture = "x_mobs_fire_envelop.png",
    hud_vignette = "x_mob_core_vignette.png^[colorize:#ff450077",
    cleanse_in_water = true,
})
```

---

## Configuration & Settings

Configurable via `minetest.conf` or the Luanti **Settings -> Mod Settings** UI:

| Setting | Type | Default | Description |
|:---|:---|:---|:---|
| `x_mob_damage_particles` | `enum` | `mob_default` | Visual damage particle style (`mob_default`, `blood`, `smoke`, `ichor`, `spectral`, `sparks`, `none`). |
| `x_mob_damage_particle_multiplier` | `float` | `1.0` | Global particle count scaling multiplier (`0.0` to `3.0`). |
| `x_mob_core_enable_health_bars` | `bool` | `true` | Enable procedural overhead health bars when mobs take damage. |
| `x_mob_core_health_bar_timeout` | `float` | `4.0` | Duration in seconds before a mob health bar automatically hides (`1.0` to `30.0`). |
| `x_mob_core_health_bar_auto_remove` | `bool` | `true` | Automatically remove inactive health bar child entities on timeout instead of keeping hidden. |
| `x_mob_core_enable_hud_vignettes` | `bool` | `true` | Enable responsive fullscreen HUD screen vignettes for status effects. |
| `x_mob_core_hud_vignette_opacity_multiplier` | `float` | `1.0` | Opacity/prominence scaling multiplier for HUD vignettes (`0.5` to `2.5`). |

---

## Multiplayer Performance & Benchmarks

`x_mob_core` includes an automated load, performance, and stress test benchmark suite comparing major Luanti mob frameworks (**Mobs Redo API**, **Creatura**, and **X Mob Core**).

### Running the Benchmark Suite

Execute via standard Lua or npm:

```bash
# Direct Lua execution
lua test_multiplayer_perf.lua

# Or via npm script
npm run test:perf
```

### Benchmark Summary (Extreme Surge: 150 Mobs, 60 Concurrent Players)

| Metric | Mobs Redo API (`mobs_redo`) | Creatura (`creatura`) | X Mob Core (`x_mob_core`) | Advantage / Improvement |
|:---|:---|:---|:---|:---|
| **Average Step Latency** | `1,758.5 µs/tick` | `1,029.3 µs/tick` | **`553.3 µs/tick`** | **3.18x faster** than Mobs Redo, **1.86x faster** than Creatura |
| **Peak Tick Latency** | `3,252.0 µs` | `2,739.0 µs` | **`1,033.0 µs`** | **3.15x lower spikes**, preventing tick jitter |
| **Server TPS (20 Target)** | `20.0 TPS` | `20.0 TPS` | **`20.0 TPS`** | **98.9% tick headroom** |
| **Max Capacity (15ms Budget)** | `~1,279 mobs` | `~2,185 mobs` | **`~4,066 mobs`** | **3.18x higher entity capacity** |
| **Node / Map Queries** | `709,518 queries` | `101,369 queries` | **`4,390 queries`** | **99.38% reduction** in map queries |
| **A\* Path Searches** | `17,591 searches` | `2,841 searches` | **`146 searches`** | **99.17% reduction** via Corridor LOS & LOD |
| **Corridor Fast-Path Bypasses** | `0 (N/A)` | `0 (N/A)` | **`4,908 bypasses`** | Zero-overhead straight-line pursuit |
| **Lua GC Memory Rate** | `12,681.1 KB/s` | `4,070.8 KB/s` | **`392.6 KB/s`** | **32.30x lower memory churn** |
| **Network Egress Bandwidth** | `6,348.56 KB/s` | `6,592.43 KB/s` | **`5,636.73 KB/s`** | **11.2% to 14.5% bandwidth reduction** |

For complete multi-scenario tables (Concurrency Scaling, Entity Density, Obstacle Stress, and Distance LOD), see [benchmark_results.md](benchmark_results.md).
