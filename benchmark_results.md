# Luanti Mob Frameworks: Multiplayer Performance Benchmark Results

> Generated on: 2026-10-01 18:13:58Z


================================================================================
                     BENCHMARK RESULTS & METRIC COMPARISONS
================================================================================

--- [TABLE 1] CONCURRENCY SCALING (30 Mobs in Active Range) ---
| Players      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 10 Players   | Avg Step Latency | 223.0 us/tick    | 110.0 us/tick    | 35.1 us/tick     |
|              | Peak Tick Spike  | 361.0 us         | 289.0 us         | 167.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 1950.4 KB/s      | 1077.1 KB/s      | 88.8 KB/s        |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 30 Players   | Avg Step Latency | 327.4 us/tick    | 180.8 us/tick    | 74.2 us/tick     |
|              | Peak Tick Spike  | 544.0 us         | 462.0 us         | 266.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2645.3 KB/s      | 1310.7 KB/s      | 133.1 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 60 Players   | Avg Step Latency | 406.0 us/tick    | 226.4 us/tick    | 124.7 us/tick    |
|              | Peak Tick Spike  | 579.0 us         | 493.0 us         | 272.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2997.9 KB/s      | 932.4 KB/s       | 151.7 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Players  | Avg Step Latency | 470.0 us/tick    | 313.3 us/tick    | 178.3 us/tick    |
|              | Peak Tick Spike  | 696.0 us         | 540.0 us         | 258.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2996.8 KB/s      | 874.4 KB/s       | 113.8 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 2] ENTITY DENSITY SCALING (30 Concurrent Players) ---
| Mobs         | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 25 Mobs      | Avg Step Latency | 277.8 us/tick    | 154.8 us/tick    | 59.0 us/tick     |
|              | Node Queries     | 66175 queries    | 15152 queries    | 503 queries      |
|              | A* Path Requests | 1712 reqs        | 513 reqs         | 17 reqs          |
|              | Network Bandwidth | 596.61 KB/s      | 607.08 KB/s      | 534.44 KB/s      |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 50 Mobs      | Avg Step Latency | 469.4 us/tick    | 331.2 us/tick    | 113.1 us/tick    |
|              | Node Queries     | 100118 queries   | 36173 queries    | 1068 queries     |
|              | A* Path Requests | 2570 reqs        | 1150 reqs        | 34 reqs          |
|              | Network Bandwidth | 1234.17 KB/s     | 1169.50 KB/s     | 813.05 KB/s      |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Mobs     | Avg Step Latency | 898.0 us/tick    | 676.8 us/tick    | 221.6 us/tick    |
|              | Node Queries     | 185490 queries   | 78664 queries    | 1492 queries     |
|              | A* Path Requests | 4969 reqs        | 2549 reqs        | 55 reqs          |
|              | Network Bandwidth | 2141.99 KB/s     | 2381.10 KB/s     | 1880.38 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 200 Mobs     | Avg Step Latency | 2040.6 us/tick   | 1389.5 us/tick   | 443.3 us/tick    |
|              | Node Queries     | 443822 queries   | 151043 queries   | 3745 queries     |
|              | A* Path Requests | 11293 reqs       | 4735 reqs        | 138 reqs         |
|              | Network Bandwidth | 4554.35 KB/s     | 4368.29 KB/s     | 3710.68 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 3] OBSTACLE & PATHFINDING STRESS (50 Mobs, 30 Players) ---
| Environment      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Open Field       | Step Latency     | 213.3 us/tick    | 214.5 us/tick    | 270.5 us/tick    |
|                  | Raycast Probes   | 2473 casts       | 2996 casts       | 1643 casts       |
|                  | A* Invocations   | 0 searches       | 0 searches       | 0 searches       |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 2174 bypasses    |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Obstacle Maze    | Step Latency     | 289.4 us/tick    | 251.1 us/tick    | 95.7 us/tick     |
|                  | Raycast Probes   | 1885 casts       | 2120 casts       | 184 casts        |
|                  | A* Invocations   | 1409 searches    | 751 searches     | 7 searches       |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 40 bypasses      |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 4] MULTIPLAYER DISTANCE LOD IMPACT (60 Mobs, 50 Players) ---
| Distribution     | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Clustered Hub    | Step Latency     | 515.3 us/tick    | 435.4 us/tick    | 182.8 us/tick    |
|                  | A* Path Requests | 2393 reqs        | 1218 reqs        | 26 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 0 paused         |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Dispersed Map    | Step Latency     | 665.0 us/tick    | 467.0 us/tick    | 182.5 us/tick    |
|                  | A* Path Requests | 3132 reqs        | 1374 reqs        | 16 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 20 paused        |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 5] EXTREME MOB SURGE STRESS TEST (150 Mobs, 60 Players, 200 Ticks) ---
| Metric                   | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------------------|:-----------------|:-----------------|:-----------------|
| Average Step Latency     | 1758.5 us/tick   | 1029.3 us/tick   | 553.3 us/tick    |
| Peak Tick Latency        | 3252.0 us        | 2739.0 us        | 1033.0 us        |
| Server TPS (20 Target)   | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
| Frame Overruns (>50ms)   | 0 ticks          | 0 ticks          | 0 ticks          |
| TPS Headroom (Budget)    | 96.5%            | 97.9%            | 98.9%            |
| Max Mobs (15ms Budget)   | ~1279 mobs       | ~2185 mobs       | ~4066 mobs       |
| Node & Map Queries       | 709518 queries   | 101369 queries   | 4390 queries     |
| Spatial Radius Scans     | 1500 scans       | 2700 scans       | 836 scans        |
| A* Path Searches         | 17591 searches   | 2841 searches    | 146 searches     |
| Corridor Bypasses        | 0 (N/A)          | 0 (N/A)          | 4908 bypasses    |
| Memory Allocation Rate   | 12681.1 KB/s     | 4070.8 KB/s      | 392.6 KB/s       |
| Network Bandwidth        | 6348.56 KB/s     | 6592.43 KB/s     | 5636.73 KB/s     |
|:-------------------------|:-----------------|:-----------------|:-----------------|

--- [SUMMARY] PERFORMANCE ADVANTAGE & HEADROOM ---
| Metric | Mobs Redo API (`mobs_redo`) | Creatura (`creatura`) | X Mob Core (`x_mob_core`) | Advantage / Improvement |
|:---|:---|:---|:---|:---|
| **Average Step Latency** | `1758.5 µs/tick` | `1029.3 µs/tick` | **`553.3 µs/tick`** | **3.18x faster** than Mobs Redo, **1.86x faster** than Creatura |
| **Peak Tick Latency** | `3252.0 µs` | `2739.0 µs` | **`1033.0 µs`** | **3.15x lower spikes**, preventing tick jitter |
| **Server TPS (20 Target)** | `20.0 TPS` | `20.0 TPS` | **`20.0 TPS`** | **98.9% tick headroom** |
| **Max Capacity (15ms Budget)** | `~1279 mobs` | `~2185 mobs` | **`~4066 mobs`** | **3.18x higher entity capacity** |
| **Node / Map Queries** | `709518 queries` | `101369 queries` | **`4390 queries`** | **99.38% reduction** in map queries |
| **A\* Path Searches** | `17591 searches` | `2841 searches` | **`146 searches`** | **99.17% reduction** via Corridor LOS & LOD |
| **Corridor Fast-Path Bypasses** | `0 (N/A)` | `0 (N/A)` | **`4908 bypasses`** | Zero-overhead straight-line pursuit |
| **Lua GC Memory Rate** | `12681.1 KB/s` | `4070.8 KB/s` | **`392.6 KB/s`** | **32.30x lower memory churn** |
| **Network Egress Bandwidth** | `6348.56 KB/s` | `6592.43 KB/s` | **`5636.73 KB/s`** | **11.2% to 14.5% bandwidth reduction** |

[SUCCESS] Luanti Mob Frameworks Multiplayer Performance Benchmark completed successfully.

