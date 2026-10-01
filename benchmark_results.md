# Luanti Mob Frameworks: Multiplayer Performance Benchmark Results

> Generated on: 2026-10-01 17:18:45Z


================================================================================
                     BENCHMARK RESULTS & METRIC COMPARISONS
================================================================================

--- [TABLE 1] CONCURRENCY SCALING (30 Mobs in Active Range) ---
| Players      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 10 Players   | Avg Step Latency | 133.7 us/tick    | 155.8 us/tick    | 33.1 us/tick     |
|              | Peak Tick Spike  | 246.0 us         | 284.0 us         | 104.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 1143.7 KB/s      | 1766.4 KB/s      | 74.7 KB/s        |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 30 Players   | Avg Step Latency | 292.7 us/tick    | 195.5 us/tick    | 71.7 us/tick     |
|              | Peak Tick Spike  | 494.0 us         | 474.0 us         | 235.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2456.0 KB/s      | 1711.6 KB/s      | 127.6 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 60 Players   | Avg Step Latency | 379.8 us/tick    | 233.5 us/tick    | 120.7 us/tick    |
|              | Peak Tick Spike  | 605.0 us         | 501.0 us         | 327.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2994.5 KB/s      | 1187.2 KB/s      | 161.5 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Players  | Avg Step Latency | 446.5 us/tick    | 301.4 us/tick    | 179.9 us/tick    |
|              | Peak Tick Spike  | 660.0 us         | 517.0 us         | 273.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 3015.5 KB/s      | 734.5 KB/s       | 132.7 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 2] ENTITY DENSITY SCALING (30 Concurrent Players) ---
| Mobs         | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 25 Mobs      | Avg Step Latency | 254.2 us/tick    | 173.2 us/tick    | 59.4 us/tick     |
|              | Node Queries     | 61819 queries    | 22019 queries    | 525 queries      |
|              | A* Path Requests | 1534 reqs        | 689 reqs         | 15 reqs          |
|              | Network Bandwidth | 532.75 KB/s      | 538.39 KB/s      | 425.56 KB/s      |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 50 Mobs      | Avg Step Latency | 443.6 us/tick    | 307.0 us/tick    | 109.4 us/tick    |
|              | Node Queries     | 94770 queries    | 36566 queries    | 884 queries      |
|              | A* Path Requests | 2458 reqs        | 1214 reqs        | 27 reqs          |
|              | Network Bandwidth | 1007.23 KB/s     | 1157.39 KB/s     | 1011.23 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Mobs     | Avg Step Latency | 895.1 us/tick    | 649.6 us/tick    | 206.5 us/tick    |
|              | Node Queries     | 200336 queries   | 76346 queries    | 1385 queries     |
|              | A* Path Requests | 5440 reqs        | 2715 reqs        | 48 reqs          |
|              | Network Bandwidth | 1809.54 KB/s     | 2623.51 KB/s     | 1896.71 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 200 Mobs     | Avg Step Latency | 1901.3 us/tick   | 1266.4 us/tick   | 419.4 us/tick    |
|              | Node Queries     | 443020 queries   | 131379 queries   | 3452 queries     |
|              | A* Path Requests | 11540 reqs       | 4359 reqs        | 128 reqs         |
|              | Network Bandwidth | 4288.48 KB/s     | 4678.73 KB/s     | 3576.61 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 3] OBSTACLE & PATHFINDING STRESS (50 Mobs, 30 Players) ---
| Environment      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Open Field       | Step Latency     | 178.6 us/tick    | 197.8 us/tick    | 200.4 us/tick    |
|                  | Raycast Probes   | 2110 casts       | 2610 casts       | 1565 casts       |
|                  | A* Invocations   | 0 searches       | 0 searches       | 0 searches       |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 2074 bypasses    |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Obstacle Maze    | Step Latency     | 355.9 us/tick    | 264.4 us/tick    | 96.8 us/tick     |
|                  | Raycast Probes   | 2330 casts       | 2144 casts       | 667 casts        |
|                  | A* Invocations   | 2019 searches    | 909 searches     | 11 searches      |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 404 bypasses     |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 4] MULTIPLAYER DISTANCE LOD IMPACT (60 Mobs, 50 Players) ---
| Distribution     | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Clustered Hub    | Step Latency     | 507.1 us/tick    | 449.3 us/tick    | 171.7 us/tick    |
|                  | A* Path Requests | 2541 reqs        | 1282 reqs        | 23 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 10 paused        |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Dispersed Map    | Step Latency     | 625.6 us/tick    | 429.5 us/tick    | 184.5 us/tick    |
|                  | A* Path Requests | 3322 reqs        | 1122 reqs        | 28 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 95 paused        |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 5] EXTREME MOB SURGE STRESS TEST (150 Mobs, 60 Players, 200 Ticks) ---
| Metric                   | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------------------|:-----------------|:-----------------|:-----------------|
| Average Step Latency     | 1634.1 us/tick   | 985.9 us/tick    | 541.6 us/tick    |
| Peak Tick Latency        | 3049.0 us        | 2509.0 us        | 1262.0 us        |
| Server TPS (20 Target)   | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
| Frame Overruns (>50ms)   | 0 ticks          | 0 ticks          | 0 ticks          |
| TPS Headroom (Budget)    | 96.7%            | 98.0%            | 98.9%            |
| Max Mobs (15ms Budget)   | ~1376 mobs       | ~2282 mobs       | ~4154 mobs       |
| Node & Map Queries       | 692430 queries   | 84059 queries    | 8013 queries     |
| Spatial Radius Scans     | 1500 scans       | 2700 scans       | 836 scans        |
| A* Path Searches         | 17284 searches   | 2242 searches    | 245 searches     |
| Corridor Bypasses        | 0 (N/A)          | 0 (N/A)          | 5025 bypasses    |
| Memory Allocation Rate   | 12337.1 KB/s     | 3511.6 KB/s      | 498.3 KB/s       |
| Network Bandwidth        | 6326.52 KB/s     | 6423.44 KB/s     | 5518.72 KB/s     |
|:-------------------------|:-----------------|:-----------------|:-----------------|

--- [SUMMARY] PERFORMANCE ADVANTAGE & HEADROOM ---
| Metric | Mobs Redo API (`mobs_redo`) | Creatura (`creatura`) | X Mob Core (`x_mob_core`) | Advantage / Improvement |
|:---|:---|:---|:---|:---|
| **Average Step Latency** | `1634.1 µs/tick` | `985.9 µs/tick` | **`541.6 µs/tick`** | **3.02x faster** than Mobs Redo, **1.82x faster** than Creatura |
| **Peak Tick Latency** | `3049.0 µs` | `2509.0 µs` | **`1262.0 µs`** | **2.42x lower spikes**, preventing tick jitter |
| **Server TPS (20 Target)** | `20.0 TPS` | `20.0 TPS` | **`20.0 TPS`** | **98.9% tick headroom** |
| **Max Capacity (15ms Budget)** | `~1376 mobs` | `~2282 mobs` | **`~4154 mobs`** | **3.02x higher entity capacity** |
| **Node / Map Queries** | `692430 queries` | `84059 queries` | **`8013 queries`** | **98.84% reduction** in map queries |
| **A\* Path Searches** | `17284 searches` | `2242 searches` | **`245 searches`** | **98.58% reduction** via Corridor LOS & LOD |
| **Corridor Fast-Path Bypasses** | `0 (N/A)` | `0 (N/A)` | **`5025 bypasses`** | Zero-overhead straight-line pursuit |
| **Lua GC Memory Rate** | `12337.1 KB/s` | `3511.6 KB/s` | **`498.3 KB/s`** | **24.76x lower memory churn** |
| **Network Egress Bandwidth** | `6326.52 KB/s` | `6423.44 KB/s` | **`5518.72 KB/s`** | **12.8% to 14.1% bandwidth reduction** |

[SUCCESS] Luanti Mob Frameworks Multiplayer Performance Benchmark completed successfully.

