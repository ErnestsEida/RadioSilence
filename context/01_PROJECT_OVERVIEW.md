# Radio Silence — project overview

A free, retro-styled **team FPS** built in Godot 4.4.1. It looks like a Doom/Wolfenstein raycaster but is a
full FPS: height-field raycasting (look up/down, block heights, rooftops, stairs, windows), 3D vehicles and
3D first-person weapons composited over it. Everything (textures, sprites, sounds, models) is generated
procedurally in code.

## Players & modes
- **Solo** (you + AI teammates vs AI teams), **local split-screen co-op** (2 players: keyboard+mouse plus
  gamepad or a second keyboard layout), **LAN** up to 16 players (ENet, host-authoritative), with automatic
  server discovery (LAN + Hamachi) and direct-connect by IP. AI bots fill empty slots.
- **Teams & players:** 2 or 4 teams ("1v1" or "1v1v1v1") and a total of **16 or 8 players**; the team
  size follows: 16 players → 8 per team (1v1) or 4 per team (1v1v1v1); 8 players → 4 or 2 per team.
  Puzzle rooms per bunker = min(team size, 4) (2 or 4). One vehicle per pair (up to 4 per team).
- **Game modes** (`Defs.MODE_*`):
  - **HEIST** (0, original mode): each team owns a bunker. Every player carries a key to their own bunker;
    kill enemies to take their keys. Each key unlocks one puzzle room of that bunker (2 rooms per bunker
    with 2-player teams, 4 with 4-player teams → 8 or 16 keys/puzzles total). Solve all rooms → vault opens
    → carry loot back to your camp/vehicle to bank points. Used keys are consumed. Owners who hold their
    breached bunker for 60 s re-seal it and get their keys back.
  - **CAPTURE THE FLAG** (1): flags at each base camp; take an enemy flag home while yours is at home.
    Dropped flags return after 25 s or when touched by their team. Carriers can't enter vehicles.
  - **TEAM DEATHMATCH** (2): 1 point per kill, 2 for a crewed vehicle.
  - Bunkers (with guards/turrets/keys) exist **only in HEIST**; other modes generate open terrain there.

## Content
- **8 maps** (+ "Random map"): Green Valley, Dust Fortress, Frost Ridge, Ruined Town, Red Canyon,
  Harbor Yard, Marshlands, Coastline. 4 base layouts (cross, pinwheel, diamond, inner) so camps/bunkers move.
  Block types: rock, brick, concrete, tech walls, sandbags, crates, containers, planks, steel stairs,
  hedges, plaster; watchtowers, houses with windows/roofs/inner stairs, ponds/water, mesas, canals.
- **Weather** (random or chosen per match): clear, cloudy, rain, thunderstorm, fog, snow (snow maps), dust
  storm (arid maps). **Time of day**: morning, day, dusk, night. Dynamic lights: vehicle headlights, lamp
  posts at camps/bunkers, fires, muzzle flashes, explosions, lightning.
- **13 weapons:** knife, pistol, revolver, assault rifle, SMG, shotgun, sniper, LMG, burst rifle,
  marksman rifle, machine pistol, double barrel, rocket launcher. Travelling bullets (dodgeable),
  headshots, ADS zoom, loadouts with weapon icons. **Equipment:** frag, smoke, medkit (heals a teammate
  you look at, else yourself), ammo bag.
- **5 vehicles** (2 seats: driver + gunner): Tank, Broneviks (armoured car), Motorcycle (sidecar MG),
  Jeep, Rocket Truck. 1 vehicle per pair of teammates (2 per team with 4-player teams). Driver can
  free-look left/right; gunner aims up/down. Real 3D models in the world.
- **Base mortar** at every camp: top-down aiming view, ~quarter-map range, red ground warning 0.5 s before
  impact, RMB rapid-fire barrage special every 30 s. Bots may crew it.
- **Puzzles** (HEIST rooms): code lock, signal tuner, safe dial, memory grid, pressure valves.
- **Random events** (~every 2–2.5 min, ≥3 per 10-min match): supply drop, map-wide air strike (bomber
  waves + shelling), storm, radio jammed (minimap static), gold rush (x2 banking), bounty.
- Fall damage, stamina/exhaustion, sprint, crouch, jump, climb blocks, fog-of-war minimap.

## Controls (keyboard + mouse)
WASD move/drive · mouse look/aim · LMB fire · RMB ADS (vehicle: MG; mortar: barrage) · Shift sprint ·
Space jump · C/Ctrl crouch · R reload · 1/2/3/wheel weapons · G grenade/medkit · E use (vehicles, key
doors, terminals, mortar, ammo crates) · F switch seat · Tab scores · Esc pause/options.
Gamepad and a numpad "kb2" layout are supported for split-screen.

## Distribution
- Exports exist in `export/` (Windows/Linux/macOS zips) — **built before Feature Update #1, now outdated**.
- GitHub Pages download page: `docs/index.html` (+ `docs/img/`), with `REPLACE_WITH_*` link placeholders.
- The user handles GitHub (repo "RadioSilence", releases, Pages) themselves.
