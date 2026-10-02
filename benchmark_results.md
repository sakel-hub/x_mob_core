# Luanti Mob Frameworks: Multiplayer Performance Benchmark Results

> Generated on: 2026-10-02 15:52:57Z


================================================================================
                     BENCHMARK RESULTS & METRIC COMPARISONS
================================================================================

--- [TABLE 1] CONCURRENCY SCALING (30 Mobs in Active Range) ---
| Players      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 10 Players   | Avg Step Latency | 166.2 us/tick    | 154.9 us/tick    | 34.5 us/tick     |
|              | Peak Tick Spike  | 319.0 us         | 370.0 us         | 92.0 us          |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 1325.9 KB/s      | 1692.9 KB/s      | 76.0 KB/s        |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 30 Players   | Avg Step Latency | 238.7 us/tick    | 212.9 us/tick    | 81.6 us/tick     |
|              | Peak Tick Spike  | 453.0 us         | 493.0 us         | 202.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 1747.8 KB/s      | 1692.8 KB/s      | 116.9 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 60 Players   | Avg Step Latency | 359.2 us/tick    | 255.4 us/tick    | 128.8 us/tick    |
|              | Peak Tick Spike  | 614.0 us         | 512.0 us         | 265.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2411.3 KB/s      | 1241.9 KB/s      | 159.4 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Players  | Avg Step Latency | 453.2 us/tick    | 318.3 us/tick    | 192.3 us/tick    |
|              | Peak Tick Spike  | 717.0 us         | 564.0 us         | 303.0 us         |
|              | Server TPS       | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
|              | Memory Growth    | 2825.4 KB/s      | 748.2 KB/s       | 155.3 KB/s       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 2] ENTITY DENSITY SCALING (30 Concurrent Players) ---
| Mobs         | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 25 Mobs      | Avg Step Latency | 303.0 us/tick    | 172.7 us/tick    | 60.8 us/tick     |
|              | Node Queries     | 68705 queries    | 17682 queries    | 282 queries      |
|              | A* Path Requests | 1737 reqs        | 594 reqs         | 9 reqs           |
|              | Network Bandwidth | 589.24 KB/s      | 567.83 KB/s      | 495.67 KB/s      |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 50 Mobs      | Avg Step Latency | 501.1 us/tick    | 325.9 us/tick    | 112.5 us/tick    |
|              | Node Queries     | 108941 queries   | 34965 queries    | 494 queries      |
|              | A* Path Requests | 2804 reqs        | 1217 reqs        | 18 reqs          |
|              | Network Bandwidth | 1131.84 KB/s     | 1101.65 KB/s     | 886.42 KB/s      |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 100 Mobs     | Avg Step Latency | 974.7 us/tick    | 693.7 us/tick    | 233.9 us/tick    |
|              | Node Queries     | 206762 queries   | 72898 queries    | 1460 queries     |
|              | A* Path Requests | 5520 reqs        | 2378 reqs        | 55 reqs          |
|              | Network Bandwidth | 2318.45 KB/s     | 2322.30 KB/s     | 1863.16 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|
| 200 Mobs     | Avg Step Latency | 2086.4 us/tick   | 1349.2 us/tick   | 449.3 us/tick    |
|              | Node Queries     | 455574 queries   | 141818 queries   | 3525 queries     |
|              | A* Path Requests | 11689 reqs       | 4699 reqs        | 117 reqs         |
|              | Network Bandwidth | 4723.60 KB/s     | 5067.14 KB/s     | 3677.66 KB/s     |
|:-------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 3] OBSTACLE & PATHFINDING STRESS (50 Mobs, 30 Players) ---
| Environment      | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Open Field       | Step Latency     | 200.1 us/tick    | 216.3 us/tick    | 239.9 us/tick    |
|                  | Raycast Probes   | 2289 casts       | 2109 casts       | 1866 casts       |
|                  | A* Invocations   | 0 searches       | 0 searches       | 0 searches       |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 2452 bypasses    |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Obstacle Maze    | Step Latency     | 376.6 us/tick    | 285.0 us/tick    | 109.1 us/tick    |
|                  | Raycast Probes   | 2593 casts       | 2739 casts       | 792 casts        |
|                  | A* Invocations   | 2142 searches    | 738 searches     | 22 searches      |
|                  | Corridor Bypass  | 0 (N/A)          | 0 (N/A)          | 247 bypasses     |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 4] MULTIPLAYER DISTANCE LOD IMPACT (60 Mobs, 50 Players) ---
| Distribution     | Metric           | Mobs Redo API    | Creatura         | X Mob Core       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Clustered Hub    | Step Latency     | 465.4 us/tick    | 431.6 us/tick    | 178.0 us/tick    |
|                  | A* Path Requests | 2075 reqs        | 918 reqs         | 29 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 34 paused        |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|
| Dispersed Map    | Step Latency     | 659.8 us/tick    | 427.9 us/tick    | 195.6 us/tick    |
|                  | A* Path Requests | 3619 reqs        | 1102 reqs        | 40 reqs          |
|                  | LOD Pauses       | 0 (No LOD)       | 0 (No LOD)       | 115 paused       |
|:-----------------|:-----------------|:-----------------|:-----------------|:-----------------|

--- [TABLE 5] EXTREME MOB SURGE STRESS TEST (150 Mobs, 60 Players, 200 Ticks) ---
| Metric                   | Mobs Redo API    | Creatura         | X Mob Core       |
|:-------------------------|:-----------------|:-----------------|:-----------------|
| Average Step Latency     | 1751.9 us/tick   | 1094.4 us/tick   | 553.7 us/tick    |
| Peak Tick Latency        | 2934.0 us        | 3164.0 us        | 1346.0 us        |
| Server TPS (20 Target)   | 20.0 TPS         | 20.0 TPS         | 20.0 TPS         |
| Frame Overruns (>50ms)   | 0 ticks          | 0 ticks          | 0 ticks          |
| TPS Headroom (Budget)    | 96.5%            | 97.8%            | 98.9%            |
| Max Mobs (15ms Budget)   | ~1284 mobs       | ~2055 mobs       | ~4063 mobs       |
| Node & Map Queries       | 741094 queries   | 105153 queries   | 5985 queries     |
| Spatial Radius Scans     | 1500 scans       | 2700 scans       | 836 scans        |
| A* Path Searches         | 18294 searches   | 2845 searches    | 196 searches     |
| Corridor Bypasses        | 0 (N/A)          | 0 (N/A)          | 5841 bypasses    |
| Memory Allocation Rate   | 13099.1 KB/s     | 4180.2 KB/s      | 467.2 KB/s       |
| Network Bandwidth        | 6251.34 KB/s     | 6587.49 KB/s     | 5751.02 KB/s     |
|:-------------------------|:-----------------|:-----------------|:-----------------|

--- [SUMMARY] PERFORMANCE ADVANTAGE & HEADROOM ---
| Metric | Mobs Redo API (`mobs_redo`) | Creatura (`creatura`) | X Mob Core (`x_mob_core`) | Advantage / Improvement |
|:---|:---|:---|:---|:---|
| **Average Step Latency** | `1751.9 µs/tick` | `1094.4 µs/tick` | **`553.7 µs/tick`** | **3.16x faster** than Mobs Redo, **1.98x faster** than Creatura |
| **Peak Tick Latency** | `2934.0 µs` | `3164.0 µs` | **`1346.0 µs`** | **2.18x lower spikes**, preventing tick jitter |
| **Server TPS (20 Target)** | `20.0 TPS` | `20.0 TPS` | **`20.0 TPS`** | **98.9% tick headroom** |
| **Max Capacity (15ms Budget)** | `~1284 mobs` | `~2055 mobs` | **`~4063 mobs`** | **3.16x higher entity capacity** |
| **Node / Map Queries** | `741094 queries` | `105153 queries` | **`5985 queries`** | **99.19% reduction** in map queries |
| **A\* Path Searches** | `18294 searches` | `2845 searches` | **`196 searches`** | **98.93% reduction** via Corridor LOS & LOD |
| **Corridor Fast-Path Bypasses** | `0 (N/A)` | `0 (N/A)` | **`5841 bypasses`** | Zero-overhead straight-line pursuit |
| **Lua GC Memory Rate** | `13099.1 KB/s` | `4180.2 KB/s` | **`467.2 KB/s`** | **28.04x lower memory churn** |
| **Network Egress Bandwidth** | `6251.34 KB/s` | `6587.49 KB/s` | **`5751.02 KB/s`** | **8.0% to 12.7% bandwidth reduction** |

[SUCCESS] Luanti Mob Frameworks Multiplayer Performance Benchmark completed successfully.

