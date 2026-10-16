# Luanti Mob Frameworks: Multiplayer Performance Benchmark Results

> Generated on: 2026-10-15 23:28:13Z


================================================================================
                     BENCHMARK RESULTS & METRIC COMPARISONS
================================================================================

--- [TABLE 1] CONCURRENCY SCALING (30 Mobs in Active Range) ---
| Players      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 10 Players   | Avg Step Latency | 137.6 us/tick    | 140.6 us/tick    | 34.2 us/tick     |
|              | Peak Tick Spike  | 251.0 us         | 289.0 us         | 91.0 us          |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 1097.0 KB/s      | 1520.9 KB/s      | 73.9 KB/s        |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 30 Players   | Avg Step Latency | 255.4 us/tick    | 184.2 us/tick    | 65.5 us/tick     |
|              | Peak Tick Spike  | 459.0 us         | 480.0 us         | 189.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 1968.1 KB/s      | 1395.1 KB/s      | 86.3 KB/s        |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 60 Players   | Avg Step Latency | 347.9 us/tick    | 232.1 us/tick    | 124.9 us/tick    |
|              | Peak Tick Spike  | 550.0 us         | 464.0 us         | 272.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2553.8 KB/s      | 1045.2 KB/s      | 181.8 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Players  | Avg Step Latency | 453.9 us/tick    | 318.4 us/tick    | 180.4 us/tick    |
|              | Peak Tick Spike  | 697.0 us         | 569.0 us         | 309.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 3073.1 KB/s      | 917.5 KB/s       | 157.8 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 2] ENTITY DENSITY SCALING (30 Concurrent Players) ---
| Mobs         | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 25 Mobs      | Avg Step Latency | 241.3 us/tick    | 191.7 us/tick    | 57.6 us/tick     |
|              | Node Queries     | 50886 queries    | 23951 queries    | 250 queries      |
|              | A* Path Requests | 1416 reqs        | 904 reqs         | 12 reqs          |
|              | Network Bandwidth | 589.24 KB/s      | 563.77 KB/s      | 441.15 KB/s      |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 50 Mobs      | Avg Step Latency | 428.8 us/tick    | 359.5 us/tick    | 111.9 us/tick    |
|              | Node Queries     | 86492 queries    | 42370 queries    | 711 queries      |
|              | A* Path Requests | 2333 reqs        | 1469 reqs        | 23 reqs          |
|              | Network Bandwidth | 1058.19 KB/s     | 960.79 KB/s      | 947.63 KB/s      |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Mobs     | Avg Step Latency | 941.0 us/tick    | 618.4 us/tick    | 211.8 us/tick    |
|              | Node Queries     | 217557 queries   | 63763 queries    | 1498 queries     |
|              | A* Path Requests | 5510 reqs        | 2004 reqs        | 45 reqs          |
|              | Network Bandwidth | 2326.19 KB/s     | 2141.86 KB/s     | 1843.56 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 200 Mobs     | Avg Step Latency | 1910.4 us/tick   | 1319.9 us/tick   | 428.6 us/tick    |
|              | Node Queries     | 440331 queries   | 150158 queries   | 4116 queries     |
|              | A* Path Requests | 11137 reqs       | 5422 reqs        | 127 reqs         |
|              | Network Bandwidth | 4790.27 KB/s     | 4427.32 KB/s     | 3715.03 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 3] OBSTACLE & PATHFINDING STRESS (50 Mobs, 30 Players) ---
| Environment      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Open Field       | Step Latency     | 190.4 us/tick    | 213.0 us/tick    | 180.2 us/tick    |
|                  | Raycast Probes   | 2047 casts       | 2983 casts       | 1095 casts       |
|                  | A* Invocations   | 0 searches       | 0 searches       | 0 searches       |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 1446 bypasses    |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Obstacle Maze    | Step Latency     | 261.5 us/tick    | 272.4 us/tick    | 102.3 us/tick    |
|                  | Raycast Probes   | 1804 casts       | 2557 casts       | 852 casts        |
|                  | A* Invocations   | 1371 searches    | 867 searches     | 20 searches      |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 292 bypasses     |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 4] MULTIPLAYER DISTANCE LOD IMPACT (60 Mobs, 50 Players) ---
| Distribution     | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Clustered Hub    | Step Latency     | 523.3 us/tick    | 431.4 us/tick    | 166.0 us/tick    |
|                  | A* Path Requests | 2606 reqs        | 1022 reqs        | 17 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 75 paused        |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Dispersed Map    | Step Latency     | 695.2 us/tick    | 433.8 us/tick    | 187.4 us/tick    |
|                  | A* Path Requests | 3812 reqs        | 1177 reqs        | 28 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 29 paused        |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 5] EXTREME MOB SURGE STRESS TEST (150 Mobs, 60 Players, 200 Ticks) ---
| Metric                   | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------------------|:-----------------|:-----------------|:-----------------|
| Average Step Latency     | 1713.7 us/tick   | 1005.4 us/tick   | 560.6 us/tick    |
| Peak Tick Latency        | 3088.0 us        | 2572.0 us        | 1089.0 us        |
| Server TPS (20 Target)   | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
| Frame Overruns (>50ms)   | 0 ticks          | 0 ticks          | 0 ticks          |
| TPS Headroom (Budget)    | 96.6%            | 98.0%            | 98.9%            |
| Max Mobs (15ms Budget)   | ~1312 mobs       | ~2237 mobs       | ~4013 mobs       |
| Node & Map Queries       | 746530 queries   | 88085 queries    | 8374 queries     |
| Spatial Radius Scans     | 1500 scans       | 2700 scans       | 836 scans        |
| A* Path Searches         | 18667 searches   | 2083 searches    | 266 searches     |
| Corridor Bypasses        | 0 (N/A)          | 0 (N/A)          | 3736 bypasses    |
| Memory Allocation Rate   | 13242.4 KB/s     | 3663.5 KB/s      | 583.7 KB/s       |
| Network Bandwidth        | 6582.49 KB/s     | 7238.99 KB/s     | 5395.46 KB/s     |
|:-------------------------|:-----------------|:-----------------|:-----------------|

--- [SUMMARY] PERFORMANCE ADVANTAGE & HEADROOM ---
| Metric | Mobs Redo API (`mobs_redo`) | Creatura (`creatura`) | X Mob Core (`x_mob_core`) | Advantage / Improvement |
|:---|:---|:---|:---|:---|
| **Average Step Latency** | `1713.7 µs/tick` | `1005.4 µs/tick` | **`560.6 µs/tick`** | **3.06x faster** than Mobs Redo, **1.79x faster** than Creatura |
| **Peak Tick Latency** | `3088.0 µs` | `2572.0 µs` | **`1089.0 µs`** | **2.84x lower spikes**, preventing tick jitter |
| **Server TPS (20 Target)** | `20.0 TPS` | `20.0 TPS` | **`20.0 TPS`** | **98.9% tick headroom** |
| **Max Capacity (15ms Budget)** | `~1312 mobs` | `~2237 mobs` | **`~4013 mobs`** | **3.06x higher entity capacity** |
| **Node / Map Queries** | `746530 queries` | `88085 queries` | **`8374 queries`** | **98.88% reduction** in map queries |
| **A\* Path Searches** | `18667 searches` | `2083 searches` | **`266 searches`** | **98.58% reduction** via Corridor LOS & LOD |
| **Corridor Fast-Path Bypasses** | `0 (N/A)` | `0 (N/A)` | **`3736 bypasses`** | Zero-overhead straight-line pursuit |
| **Lua GC Memory Rate** | `13242.4 KB/s` | `3663.5 KB/s` | **`583.7 KB/s`** | **22.69x lower memory churn** |
| **Network Egress Bandwidth** | `6582.49 KB/s` | `7238.99 KB/s` | **`5395.46 KB/s`** | **18.0% to 25.5% bandwidth reduction** |

[SUCCESS] Luanti Mob Frameworks Multiplayer Performance Benchmark completed successfully.
