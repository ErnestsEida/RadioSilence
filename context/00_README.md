# Radio Silence — context pack

Context files for continuing development of **Radio Silence** in a new Claude project/conversation.
Upload all of them as project knowledge. Read in this order:

| File | What it covers |
|---|---|
| `01_PROJECT_OVERVIEW.md` | What the game is: modes, features, content, controls |
| `02_ARCHITECTURE.md` | Code structure, every script's role, networking model, data formats (input array, snapshot, match cfg), rendering |
| `03_DEV_WORKFLOW.md` | How to run, test, screenshot, export; engine paths; coding rules and gotchas |
| `04_STATUS_AND_ROADMAP.md` | What is done, known issues, and the **pending "Gameplay update #1" (Part 2)** |
| `05_HISTORY_AND_PREFERENCES.md` | How the project evolved, and how the user likes to work |

Project root: `E:\Games\Radio Silence` (Windows 10, PowerShell + Git Bash available).
Engine: Godot **4.4.1** (GL Compatibility renderer), GDScript only, no addons.
Size: ~19,000 lines across 22 scripts + 2 shaders, all procedural (no image/audio/model asset files).
