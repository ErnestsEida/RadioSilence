# Radio Silence — status & roadmap

## Current status (end of the previous conversation)
- **Feature Update #1 (Part 1) is DONE:** weather, time of day, night/storm immersion, headlights and light
  sources, game modes (Heist / CTF / TDM with 2 or 4 teams), mortar red ground warning + 30 s barrage
  special, 5 new weapons + weapon icons in loadout pickers + medkit heals teammates.
- **Follow-up fixes DONE:** players spawn on foot (not inside vehicles) spread on an arc at their camp;
  bunkers only exist in HEIST (other modes: open terrain + a resupply ammo crate at each camp); LAN lobby
  lets only pair leaders (team slots 0, 2) pick the vehicle; **bunker yard connectivity bug fixed** (the 4
  corners of the vault building are notched so the yard is one ring — before, each gate led to a separate
  sealed quarter, which is why AI never robbed vaults).
- **Player count change DONE:** menu/lobby choose total players (16 or 8); per-team size = total / teams
  (1v1 with 16 → 8 per team, 1v1v1v1 → 4 per team). Verified on all 8 maps × 3 modes × 2 team counts with
  `tools/teams_check.gd` (no blocked vehicle spawns, no stacked players).
- **User has NOT yet confirmed testing** of Part 1 + fixes. Next step: wait for the user's test feedback,
  then start Part 2.

## Pending: Part 2 — "Gameplay update #1" (user's list, verbatim intent)
1. Show **teammate health and nametags** (above teammates in the world).
2. Make the **game log** (kill feed / messages) **smaller**, add a **UI scale option**, and **highlight (bold)
   the current player's name** in it.
3. **Puzzles: much easier, remove memorization** (code lock's hidden-code stages, memory grid), but add more
   **motor-skill** challenges, and make puzzle selection **much more random** (user mostly gets the same 2).
4. **Show player models crouching or jumping** (sprite frames exist for crouch; add jumping pose / height).
5. **Change name in the multiplayer lobby** (currently only the menu callsign).
6. **UI scaling**: the menu breaks on 2K+ or small screens — auto-adjust (content scale / responsive layout).
7. **Heist: show which keys your team holds** somewhere in the HUD, and **any teammate can use the team's
   keys** (not only the player who picked them up).
Constraints from the user for every change: **keep multiplayer working**, develop Part 2 as its own chunk so it
can be tested separately, and **use sub-agents where it speeds things up but keep token usage minimal**.

## Known issues / loose ends
- AI-vs-AI heist: AI now does open vaults sometimes (2 of 5 selftest runs) but often times out — further AI
  tuning possible (bots are slow to coordinate rooms + vault).
- Exports in `export/` and the GitHub Pages screenshots predate Feature Update #1 — re-export before release.
- Not tested with real people: LAN play across PCs, Hamachi discovery, lobby vehicle-pick/team rules, CTF/TDM
  over the network, weather/time sync on clients (all rely on cfg/snapshot code that is unit-tested locally).
- Double-barrel / shotgun ADS still shows a bit of glove at the bottom of the screen.
- 3D vehicles: wheels/tracks don't visibly roll; vehicles always sit at height 0.
- Root `README.md` is outdated (from iteration 3); `context/` is the up-to-date description.
- Bots don't climb blocks/stairs (A* treats all blocks as solid); they shoot players on towers from below.

## Ideas mentioned but not requested
- PixelLab connector (pixel-art generation) is available in the claude.ai account if hand-drawn sprites are
  ever wanted instead of procedural art.
