# Radio Silence — history & working preferences

## How the project evolved (user requests, in order)
1. **Iteration 1:** new Godot game in `E:\Games` (engine copied from the user's other project "The Way is Up").
   Raycaster graphics; teams start in a 2-seat tank (driver + gunner); pistol/knife/rifle on foot;
   Solo / Co-op / LAN (up to 4 teams of 2). Original goal: disable alarms, open the main door, sabotage the
   radio server (later replaced).
2. Better graphics/movement, weapons held to the side, fog of war, bigger maps, sound options, more maps,
   4 teams against each other (including solo).
3. Better weapons; new goal: steal keys from other teams → keys open 2 puzzle rooms → vault → bring loot back
   for points; loadouts, more weapons, sprint/grenades.
4. 4 bunkers × 2 rooms; keys drop on death (max 8 keys); much bigger maps; stamina exhaustion lock;
   sniper bullets must travel (dodgeable); weapons rebuilt as proper 3D models by an "art agent".
   Keys are consumed when used; owners re-seal a bunker by holding it 60 s.
5. Own bunker's turrets must not shoot owners; longer/harder/varied/better-looking puzzles; menu redesign;
   vehicle choice (Tank, Broneviks, Motorcycle, Jeep, Rocket Truck).
6. Full FPS: look up/down (y-shear), block heights, more block types, livelier maps (weather particles,
   birds, smoke, swaying trees, water).
7. 3D vehicle models (art agent), lock mouse-Y in cars, random events (≥3 per 10-min match).
8. 4 players per team option (16 players, 16 keys, 16 puzzles); fixed bots never re-using vehicles.
9. Mortars at bases (top-down view), real 3D vehicles visible to others with aiming guns, vehicle look/aim
   (driver free-look X only, gunner aims Y), map-wide air strike, LAN/Hamachi auto-discovery.
10. 8 maps (4 new) with 4 base layouts; "Random map" option (menu + lobby).
11. Exports for Windows/Mac/Linux as playable zips; GitHub Pages download page (`docs/`); git + gh installed
    (user handles the GitHub repo/push).
12. **Feature Update #1 (Part 1)** — see 04_STATUS_AND_ROADMAP.md — then 4 fixes (spawn on foot, spawn
    spread, bunkers only in heist, lobby vehicle picks). **Part 2 pending.**

## User preferences (follow these)
- Wants **big, ambitious updates**, delivered as **numbered lists**; when they split work into parts, build
  and deliver **one part at a time** so they can test each.
- **Always keep multiplayer (LAN) working** — every feature server-authoritative and synced.
- **Use sub-agents** for parallel work when it helps, **but keep token usage low** (fewer, well-scoped
  agents with precise briefs; agents should Grep instead of reading huge files).
- Gets impatient with long silences — give short progress notes during long work.
- Blunt feedback style; dislikes low-quality art ("trash weapons"), so visual work should be verified with
  screenshots before reporting. Prefers real 3D models over sprites where it matters.
- Plays mainly via the exported/`Play.bat` build on Windows at up to 1080p/2K; GPU GTX 1660 Ti.
- Wants deliverables ready to use (zips that extract and play; pages with placeholders they fill in).
- Says "fix these before the next big update" for bug lists — do the fixes first, then wait.

## Lessons learned
- Verify visuals by taking screenshots (`--shot`) and looking at them; verify logic with the headless selftest.
- Headless diagnostic scripts (`-s tools/x.gd`) are the fastest way to find AI/gameplay bugs (e.g. the
  bunker yard connectivity bug was found by checking A* path lengths).
- When the user reports "I didn't see X", check `%APPDATA%\Godot\app_userdata\Radio Silence\logs` and launch
  the game normally to confirm what loads.
