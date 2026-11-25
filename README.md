# Radio Silence

A raycaster (Wolfenstein-style) tank-and-commando game made with Godot 4.4. **4 teams compete to raid an enemy vault and bank the most loot.** All art and sound are generated in code, so the project has no asset files.

## Running it
- **Play.bat** starts the game.
- **Open in Godot Editor.bat** opens the project in Godot.
- Self-test, which includes a full 4-team AI match on every map: `_engine\Godot_v4.4.1-stable_win64_console.exe --headless --path . -- --selftest`
- Screenshot: `... --path . -- --shot=C:/tmp/x.png --shotmode=MODE[:map[:primaryWeaponId]]`, where MODE is one of `solo|coop|foot|ads|sprint|tank|puzzle|tuner|vault|battle`

## How a match plays
1. **Keys.** Every player carries their team's key. Kill an enemy-team player and they drop it; walk over it to bank a key for your team. Walk over your own team's dropped key to recover it, so nobody else can take it.
2. **Puzzle rooms.** Each key opens one of the two locked huts in the base. Doors open **only for your team**.
   - **Code Lock:** enter arrow sequences of length 4, 5 and 6. A mistake scrambles the code.
   - **Signal Tuner:** keep the needle inside a drifting frequency band, over 3 stages.

   The solver can't shoot, so the other player has to defend them.
3. **Vault.** Solving both puzzles opens the main bunker for your team. The first team in gets +100 and draws the garrison. Loot inside respawns: cash 50, documents 40, jewels 75, gold 100 and a golden idol worth 250.
4. **Bank it.** Carry loot back to your tank or base camp. If you die, you drop your loot bag.
5. The team with the most points when time runs out (or the first to reach the score limit) wins.

## Combat & movement
- Sprint uses stamina and you can't shoot while sprinting. Crouch lowers the camera, improves accuracy and makes you harder to hit. You can jump.
- Aim down sights; the sniper gets a full scope.
- **Loadout:**
  - Primary: Assault Rifle, SMG, Shotgun, Sniper or LMG
  - Secondary: Pistol or Revolver
  - Gear: Frag x2, Smoke x2 (blocks AI vision), Medkit x2, or an Ammo Bag
  - A knife is always carried.
- The armory hut refills ammo and gear.
- Tanks work as before. The driver drives and fires the hull MG; the gunner fires the cannon and coax MG.

## Modes
- **Solo:** you, plus an optional AI teammate, against 0–3 AI teams. With 0 opponents, the base guards drop the keys.
- **Local Co-op:** split screen against AI teams.
- **LAN:** up to 4 teams of 2. Empty slots can be filled with AI.

The match length and score limit can be set in the menu. Loadouts can be changed in the menu, lobby or pause screen, and take effect when you next respawn.

## Code
| file | what |
|---|---|
| `shaders/raycast.gdshader` | DDA raycaster, eye height (crouch/jump), themes, sprite renderer |
| `scripts/world.gd` | authoritative simulation: keys, puzzles, team doors, vault, loot, weapons, grenades, base AI, AI teams |
| `scripts/map_data.gd` | 4 map generators, puzzle huts, armory, vault, per-team door passability |
| `scripts/game_view.gd` | per-player view: weapon animation, ADS/scope, puzzle UI, HUD, fog of war |
| `scripts/main.gd` | menus, loadouts, options, rosters/bots, input devices, effects |
| `scripts/net.gd` | ENet LAN lobby, input and snapshot RPCs |
| `scripts/gfx.gd`, `scripts/sfx.gd` | procedural textures, sprites, first-person weapons, sounds |
