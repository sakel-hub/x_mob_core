# X Mob Core (`x_mob_core`)

![AI-Assisted](https://img.shields.io/badge/AI--assisted-gray)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A high-performance, **zero-dependency** mob engine and spawner framework for Luanti built on **S.O.L.I.D.** architecture principles.

---

## Features

- **Zero External Dependencies**: Operates exclusively with native Luanti engine C++ APIs (`core.*`).
- **3D A\* Hierarchical Pathfinding**:
  - Binary min-heap priority queue with zero-allocation push/pop operations.
  - Volumetric multi-ray corridor line-of-sight check bypassing expensive graph traversals.
  - LRU path caching and Content ID (CID) flat lookups.
- **Motor & Steering Controller**:
  - Pursuit-gated traversal (smart door opening, ladder climbing, liquid swimming).
  - Surface climbing and dynamic rotation interpolation.
  - Multiplayer distance-based LOD execution.
- **glTF Multi-Track Animator**:
  - Native Luanti glTF named track playback with priority blending and track transition clearing.
  - Automatic fallback to frame-range animation playback for older entities.
- **Combat & Damage Subsystem**:
  - Native tool capabilities calculation, damage groups, and tool wear.
  - Liquid knockback dampening and damage indicator flashing.
  - Universal child/passenger/arrow detachment on entity death.
- **Generic Pack & Squad Coordination**:
  - Pack UUID generation, leader-follower registry, and orphan adoption.
  - Spatial leashing and regroup steering vectors.
  - Shared threat and aggro broadcasting.
- **Dynamic Natural Spawner**:
  - Mapgen population pass (`core.register_on_generated`) and player-proximity trickle loop without ABMs.
  - Dynamic ground filtering from registered spawn node lists and group definitions (`group:soil`, `group:stone`).

---

## Architecture

```text
x_mob_core/
├── mod.conf                 # Zero dependencies
├── api.lua                  # Public API namespace 'x_mob_core'
├── core/
│   ├── types.lua            # EmmyLua type definitions
│   ├── utils.lua            # UUID generator & table helpers
│   └── events.lua           # Event bus registry (pub/sub)
├── navigation/
│   ├── min_heap.lua         # Binary min-heap priority queue
│   ├── path_cache.lua       # Content ID and path cache
│   ├── fast_pathfinder.lua  # Volumetric raycasts and 3D A* search
│   └── mob_memory.lua       # Spatial memory blackboard
├── motor/
│   └── mob_ai.lua           # Motor controller, steering, climbing, swimming
├── animation/
│   └── animator.lua         # glTF multi-track dispatcher
├── combat/
│   ├── damage.lua           # Damage calculation and tool wear
│   ├── knockback.lua        # Knockback physics dampening
│   ├── effects.lua          # Damage indication
│   └── detachment.lua       # Child and arrow detachment on death
├── spawning/
│   ├── registry.lua         # Spawn rule registry
│   ├── conditions.lua       # Ground, light, elevation, density validators
│   └── engine.lua           # Mapgen and trickle spawner loops
├── pack/
│   ├── squad.lua            # Leader/follower tracking and orphan adoption
│   └── coordination.lua     # Spatial leash tethering and aggro broadcast
└── lifecycle/
    ├── entity_wrapper.lua   # Engine entity registration adapter
    └── state_machine.lua    # State execution pipeline (idle, walk, combat, flee, custom)
```

---

## API Quickstart

### Registering a Custom Mob

```lua
x_mob_core.register_mob("mymod:goblin", {
    initial_properties = {
        hp_max = 20,
        collisionbox = {-0.3, -0.01, -0.3, 0.3, 1.2, 0.3},
        mesh = "mymod_goblin.glb",
        textures = {"mymod_goblin.png"},
    },

    movement = {
        walk_speed = 3.0,
        run_speed = 4.5,
        can_swim = true,
        can_climb = true,
        can_open_doors = true,
    },

    combat = {
        damage = 4,
        reach = 2.0,
        aggro_radius = 16.0,
    },

    animation = {
        tracks = {
            idle = "idle",
            walk = "walk",
            combat = "attack",
            death = "death",
        },
    },

    -- Optional Pack Mechanics (Handled automatically by x_mob_core)
    pack = {
        role = "member",
        leader_type = "mymod:goblin_chief",
        leash_distance = 16.0,
        regroup_distance = 4.0,
        on_leader_lost = function(self)
            self.state = "fleeing"
        end,
    },

    -- Optional Custom States
    custom_states = {
        ["dance"] = {
            enter = function(self) ... end,
            step = function(self, dtime) ... end,
            exit = function(self) ... end,
        }
    },
})
```

### Registering Natural Spawning

```lua
x_mob_core.register_spawn("mymod:goblin", {
    nodes = {"group:soil", "default:dirt_with_grass", "default:stone"},
    chance = 2000,
    active_object_count = 3,
    min_light = 0,
    max_light = 12,
    min_elevation = -31000,
    max_elevation = 31000,
})
```

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
| **Average Step Latency** | `1,863.8 µs/tick` | `1,181.5 µs/tick` | **`530.2 µs/tick`** | **3.52x faster** than Mobs Redo, **2.23x faster** than Creatura |
| **Peak Tick Latency** | `3,302.0 µs` | `3,156.0 µs` | **`1,096.0 µs`** | **3.01x lower spikes**, preventing tick jitter |
| **Server TPS (20 Target)** | `20.0 TPS` | `20.0 TPS` | **`20.0 TPS`** | **98.9% tick headroom** |
| **Max Capacity (15ms Budget)** | `~1,207 mobs` | `~1,904 mobs` | **`~4,244 mobs`** | **3.52x higher entity capacity** |
| **Node / Map Queries** | `732,820 queries` | `129,208 queries` | **`1,146 queries`** | **99.84% reduction** in map queries |
| **A\* Path Searches** | `18,226 searches` | `3,543 searches` | **`38 searches`** | **99.79% reduction** via Corridor LOS & LOD |
| **Corridor Fast-Path Bypasses** | `0 (N/A)` | `0 (N/A)` | **`4,678 bypasses`** | Zero-overhead straight-line pursuit |
| **Lua GC Memory Rate** | `286.4 KB/s` | `253.6 KB/s` | **`27.4 KB/s`** | **10.45x lower memory churn** |
| **Network Egress Bandwidth** | `6,250.79 KB/s` | `6,312.93 KB/s` | **`5,398.42 KB/s`** | **13.6% to 14.5% bandwidth reduction** |

For complete multi-scenario tables (Concurrency Scaling, Entity Density, Obstacle Stress, and Distance LOD), see [benchmark_results.md](benchmark_results.md).

