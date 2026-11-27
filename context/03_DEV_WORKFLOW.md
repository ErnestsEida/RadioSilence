# Radio Silence — dev workflow

## Paths
- Project: `E:\Games\Radio Silence`
- Engine (console build, use for all CLI work): `E:\Games\Radio Silence\_engine\Godot_v4.4.1-stable_win64_console.exe`
- Export templates are installed in `%APPDATA%\Godot\export_templates\4.4.1.stable\`.
- User data (settings, caches, logs): `%APPDATA%\Godot\app_userdata\Radio Silence\`
  (caches: `vehicles_v1.png`, `weapon_icons_v1_13.png` — bump CACHE_VERSION in vehicle_bake.gd /
  weapon_icons.gd when models change; `--rebake-icons` forces icons).
- Tools available: Git + GitHub CLI installed (winget). **No Python.** Use PowerShell or Git Bash.

## Run / check
- Play: `Play.bat` (or `_engine\Godot_v4.4.1-stable_win64.exe --path .`).
- Compile check (fast, catches GDScript/shader parse errors):
  `& ".\_engine\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --import` → grep `SCRIPT ERROR|Parse Error|SHADER`.
- **Self-test** (headless, ~8 min full): `... --headless --path . -- --selftest`
  Sections only: `-- --selftest --mortars`, `--modes`, `--weapons`. Covers maps (all 8, both team sizes),
  heights/cover/stairs, bullets, keys/rooms/vault/reclaim, every puzzle type solved by AI, random events,
  air strike, mortars, game modes, weapons, and 12-min AI-vs-AI matches.
  **Known expected failure:** "AI opens a vault and banks loot" fails in some of the 5 AI match runs (AI is slow, see roadmap).
- **Screenshots** (non-headless; run with a timeout and kill only that process):
  `... --path . -- --shot=C:\path\out.png --shotmode=MODE[:map[:primary[:teamsize[:mode[:teams]]]]] [--weather=N --tod=N] [--fxtest=marks|lightning] [--veh-sprites]`
  Modes: `menu, solo, coop, foot, ads, sprint, up, tower, roof, tank, vehN (in vehicle N with enemy vehicles parked ahead),
  pzN (puzzle type N), vault, evtN (random event N), mortar, pit, ctf`. Frame is saved at ~120 frames and the game quits.
- Diagnostics in `tools/`: `ai_debug.gd`, `drive_debug.gd` (who drives vehicles), `discovery_test.gd`,
  `browser_shot.gd`, `viewmodel_preview.gd` / `vehicle_preview.gd` (render model sheets to tools/preview_out).
  Run with `--headless --path . -s tools/<file>.gd` (previews need non-headless).

## Export
`export_presets.cfg` has presets "Windows", "Linux", "macOS" (exclude tools/, export/, _engine/).
```
& ".\_engine\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --export-release Windows "export/windows/Radio Silence.exe"
... --export-release Linux "export/linux/Radio Silence.x86_64"
... --export-release macOS "export/mac/Radio Silence.zip"
```
Then zip as `export/RadioSilence-Windows.zip` (folder `Radio Silence/` with exe + README.txt),
`RadioSilence-Linux.zip` (set unix exec bit 0x81ED<<16 on the binary entry via .NET ZipArchive),
`RadioSilence-macOS.zip` (= Godot's mac zip, universal, ad-hoc signed). `export/README.txt` is the player readme.
Project setting `rendering/textures/vram_compression/import_etc2_astc=true` is required for the universal Mac build.

## Coding rules & gotchas
- **GDScript is strictly typed by convention:** never infer a type from a Variant — write
  `var x: float = d.get("k", 0.0)` not `var x := d.k` (that is a parse error in this project's setup).
  No `class_name`; scripts reference each other via `const X = preload("res://scripts/x.gd")`.
- Server-authoritative: gameplay changes go in `world.gd`; clients only render. Anything new a client must
  see goes into `snapshot()`; anything a client chooses goes into the input array or match cfg.
- Keep deterministic map generation identical on host and clients (same args to `MapData.generate`).
- Files are mostly CRLF; Godot accepts mixed endings. The Edit tool works; `sed -i` inserts LF (fine).
- When several agents edit at once: only exact-string Edit-tool changes in shared files, never whole-file
  rewrites; re-read on conflict. This worked well for parallel sub-agents.
- PowerShell `[IO.File]` calls ignore `cd` (use absolute paths). Don't `Stop-Process` all Godot processes
  (denied by the user's auto-mode policy) — kill only processes you started (`Start-Process -PassThru`).
- Performance budget: 60 FPS at 1080p on a GTX 1660 Ti (raycast view at 1/Settings.pixel resolution).

## Release checklist (every release - REQUIRED)
1. Bump the version (`project.godot` config/version and the "Version x.y" line in the `docs/index.html` hero).
2. **Write a changelog entry and ADD it to the GitHub Pages site** (`docs/index.html`, section `#changelog`):
   insert a new `<div class="release">` block at the TOP of `.changelog`, move the `latest` class + `LATEST` tag to it.
   The changelog is **append-only** - never delete or rewrite older entries; it is the history of the game.
3. Re-export Windows / Linux / macOS. **Every release gets its own subfolder: `export/v<version>/`** (e.g. `export/v1.2/`)
   holding `RadioSilence-{Windows,Linux,macOS}.zip`. Never overwrite an older version's folder. Zip names must stay
   the same in every folder - the download buttons use `releases/latest/download/<zip>`.
4. Update `docs/` text/screenshots if features changed; user pushes and publishes a full (non-pre-release) GitHub release.
