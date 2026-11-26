# Radio Silence — architecture

## Layout
```
E:\Games\Radio Silence\
  project.godot          autoloads: Settings, Net, Sfx; main scene scenes/main.tscn; GL Compatibility
  Play.bat               runs the game with the bundled editor exe
  Open in Godot Editor.bat
  _engine\               Godot_v4.4.1-stable_win64(.exe/_console.exe) — NOT for git (156 MB)
  scenes\main.tscn       root node running scripts/main.gd
  scripts\               all game code (below)
  shaders\raycast.gdshader     the world renderer
  shaders\mortar_map.gdshader  top-down terrain view for the mortar
  tools\                 dev scripts (previews, diagnostics) — excluded from exports
  export\                built zips + export_presets.cfg targets (Windows/Linux/macOS)
  docs\                  GitHub Pages download page
  context\               these context files
```

## Scripts (role, roughly by size)
| Script | Role |
|---|---|
| `world.gd` (~3.7k lines) | **Authoritative simulation** (runs on host / locally): players, bots (AI), vehicles, enemies (bunker guards/turrets), bullets, shells/rockets, grenades, keys/bunkers/puzzles/vault/loot (heist), flags (CTF), TDM scoring, random events + air strike, mortars, snapshot(). |
| `main.gd` (~1.9k) | App shell: menus (MISSION card, options, pause, LAN lobby, server browser), match config, local input → input arrays, applying snapshots, events → sounds/effects, screenshot/test modes. |
| `game_view.gd` (~2k) | One player's screen: feeds the raycast shader (camera, sprites, lights, weather, ground marks), HUD, minimap (fog of war), puzzle UI, cockpit/weapon overlays, event banners. |
| `map_data.gd` (~1.4k) | Deterministic map generator (seeded): height-field grid (wall id, block height, roof slab, floor type, obstacles), layouts, bunkers, camps, towers, houses, terrain styles, decor, emitters, lamps, mortar pits, camp ammo crates; collision helpers (circle_blocked with foot height, ground_at, ray3/los3 3D rays, sphere_blocked); `pack_image()` for the shader; `apply_shader()`. |
| `viewmodel.gd` (~1.6k) | Procedural 3D first-person weapon models (Rig per weapon id) in a SubViewport; `update_pose()`; `icon_pose()`. |
| `gfx.gd` | Procedural pixel art: wall atlas (16 types × 64px) and sprite atlas (16×16 frames of 64px; soldiers per team, props, effects, flags, birds, plane, mortar, lamp at frame 255). |
| `defs.gd` | Shared constants: entity types E_*, events EV_*, hints H_*, weapons WPN table, PRIMARIES/SECONDARIES, equipment, loot, atlas frames FR_*, VEHICLES table, puzzles, event names, game modes. |
| `vehicle_models.gd` | Procedural 3D vehicle meshes (`build(vtype, part, wreck)`), TURRET_PIVOT, SEAT. |
| `vehicle_bake.gd` | Bakes vehicles into a 16-angle sprite atlas (cached `user://vehicles_v1.png`) — fallback path. |
| `vehicle_layer.gd` | **Real 3D vehicles in the world**: SubViewport + depth pass composited into the raycast shader with correct occlusion; turret yaw + gun pitch; headlamps. |
| `vehicle_view.gd` | First-person 3D cockpit per vehicle/seat (driver look, gun elevation, steering, recoil). |
| `mortar_view.gd` | Top-down mortar aiming view + HUD + minimap marks. |
| `atmos.gd` | Weather/time-of-day constants, random resolution, look table, debug overrides. |
| `weapon_icons.gd` | Renders weapon side-view icons from the view models (cached in user://). |
| `net.gd` (autoload Net) | ENet LAN: host/join, lobby (players, teams, vehicle picks, lobby_cfg sync), RPCs for input/snapshots/start. |
| `discovery.gd` | UDP 7778 beacons/queries for LAN + Hamachi server discovery (per-adapter broadcasts). |
| `menu_bg.gd` | Live raycast fly-through behind the main menu + map preview texture. |
| `sfx.gd` (autoload Sfx) | All sounds synthesized at startup (guns, explosions, engine loop, ambience, events). |
| `settings.gd` (autoload Settings) | Options saved to `user://settings.cfg` (volumes, sens, invert Y, pixel scale, fov, bob, fullscreen, difficulty). |
| `selftest.gd` | Headless test suite (see 03_DEV_WORKFLOW.md). |

## Networking model
- **Host-authoritative.** The host (or the local game in solo/co-op) owns a `World`. Clients only send
  input arrays and render snapshots. Host and every client generate the **same map** from the match cfg
  (seed, map index, team size, bunkers on/off) — the client keeps its own `mapdata` copy for rendering and
  applies dynamic door/gate changes from the snapshot (`dyn`).
- Snapshot rate: every physics frame (60 Hz), `Net.snapshot.rpc(dict)` (unreliable_ordered).
- **Match cfg** (dict built in `main._match_cfg` + `_with_atmos`, sent via `Net.start_game`):
  `seed, map, roster[{pid, peer, name, team, bot?, loadout?, vehicle?}], difficulty, team_size (2|4|8 = total 16 or 8 / teams),
  time (s), score, mode (0 heist,1 ctf,2 tdm), teams (2|4), weather (0..6), tod (0..3)`.
  Random map / weather / time are resolved by the host before sending.
- **Lobby cfg** (`Net.lobby_cfg`, host-only edits, synced): map, fill (AI), size, mode, teams, weather, tod.
  Players: `{name, team, vehicle}`; only even team-slots (pair leaders) pick a vehicle.

## Input array (client → server), `world.gd` I_* constants, INPUT_SIZE = 23
`0 mx, 1 my, 2 yaw, 3 fire, 4 alt(RMB), 5 use(held), 6 use_count, 7 seat_count, 8 weapon_req, 9 weapon_seq,
10 reload_count, 11 epoch, 12 sprint, 13 crouch, 14 jump_count, 15 throw_count, 16 primary, 17 secondary,
18 equipment, 19 pitch, 20 auto-aim flag, 21 mortar aim x, 22 mortar aim y`.
Edge-triggered actions use incrementing counters. `epoch` resyncs yaw after respawn/teleport.
**If you add inputs:** append at the end and also update `world._bot_think` (returns the same array for
bots) and `selftest._inp`.

## Snapshot (server → clients)
`t, e (PackedFloat32Array of entities, 9 floats each: type, x, y, ang, team, flags, hp, aux, id),
p (player records: id, tm, role, x, y, yaw, hp, weapon/mag/res, z, air, cr, sp, st, ex, pz (puzzle), stolen,
own_key, loot, eqt/eqn, mortar, hid (heal target)...), dyn (door/gate cells), ev (events: 5 floats each),
msg, alert, teams{t:{score,keys}}, bunkers[{owner,acc,sol,hold,keys}], tl, lim, win, over, nkeys,
evt (active random event), mortar{m,s,rng,min,rel,spl,spmax}, mode, flags[[team,x,y,state,carrier,ret]]`.
Vehicle entity flags: bit0 firing, bit1 moving, bits 8–11 vtype, bits 12–19 gun pitch ((p+1)*127.5).

## Rendering
- `raycast.gdshader` (canvas_item on a ColorRect in a low-res SubViewport, scale = Settings.pixel):
  per-pixel DDA through the height field (block faces/tops, roof slabs, lintels, ceilings, floor types incl.
  water), **y-shear** for pitch (`look = tan(pitch)*vscale`), billboard sprites from a data texture,
  composited 3D vehicles (`veh3d_*`), up to 32 dynamic lights (`lights/light_cols/light_dirs`), ambient,
  weather particles (pollen/dust/snow/embers/rain), lightning, fog, sky (sun/moon/stars/clouds),
  ground warning marks (`marks[16]`, set via `game_view.set_ground_marks(Array[Vector4])`).
- Map texture RGBA8: r wall id, g roof top ×40, b floor type, a block height ×40.
- World units: 1 cell = 1 unit; soldier 0.95 tall; eye 0.62 (crouch 0.38); STEP 0.36; ceiling 1.0.
- 3D layers (view model, cockpit, vehicles) are SubViewports rendered and drawn over/into the view.

## AI (bots)
Bots are `Player` objects with a `Bot` brain (`_bot_think` → input array). Foot logic in `_bot_foot`
(heist: keys/rooms/vault/defend; other modes via `_bot_mode_goal`), vehicles in `_bot_tank` (gate assault
in heist, "taxi" travel otherwise), puzzles in `_bot_puzzle`, mortar in `_bot_mortar`. AStarGrid2D for
foot paths (all blocks solid — bots don't climb) and a separate tank grid. 3D visibility via `_vis()`.
