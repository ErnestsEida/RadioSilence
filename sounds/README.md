# Radio Silence - sound replacements

Drop your generated sounds in THIS folder (`sounds/`) using exactly the file names below.
Format: **.ogg** (preferred) or **.wav**, 44.1 or 48 kHz, mono is fine (stereo OK for ambience).
Trim silence at the start - the game fires them instantly. Normalise to about -1 dBFS peak;
the game sets relative volumes itself. Any file that is missing keeps the current synthesized sound.
(Part 2 of Gameplay update #1 wires this folder in.)

## Weapons (first-person, punchy, short tail; ~0.2-0.8 s)
| File | What it is |
|---|---|
| pistol | 9 mm pistol shot |
| revolver | heavy revolver shot, more boom |
| mpistol | machine pistol, very short snappy shot (fires fast) |
| smg | SMG shot, short (fires fast - keep the tail very short) |
| rifle | assault rifle shot |
| burst | burst rifle single shot (played per round) |
| dmr | marksman rifle, sharp crack, medium tail |
| sniper | bolt sniper, big crack + long echo tail (~1 s) |
| shotgun | pump shotgun blast |
| dbarrel | double-barrel shotgun blast, deeper than shotgun |
| lmg | light machine gun shot, chunky (fires fast) |
| mg | vehicle coax / mounted MG shot |
| enemy | distant-ish gunshot used for bunker guards / turrets |
| cannon | tank cannon fire, huge low boom (~1 s) |
| rpg | rocket launch: whoosh + motor hiss (~1 s) |
| knife | knife swing whoosh |

## Impacts and explosions
| File | What it is |
|---|---|
| explosion | grenade / shell / rocket explosion, big with debris (~1.5 s) |
| hit | bullet hitting a body / armour, short thud |
| clink | grenade bouncing / shell casing on ground |
| thunder | thunder clap with rumble (~3 s, storms) |
| whistle | incoming mortar/artillery shell whistle, falling pitch (~1 s) |

## Player and world
| File | What it is |
|---|---|
| step | one footstep on dirt/concrete (played every step, pitch-varied) |
| switch | weapon switch / gear rattle, short |
| pickup | picking up an item / key, bright short chime |
| cash | banking loot, coins / cash-register chime |
| door | heavy bunker door / gate opening, metal grind (~1.5 s) |
| unlock | key turning in a lock + clunk |
| hiss | gas / smoke grenade hiss (~1.2 s) |
| plane | propeller bomber fly-over (~4 s) |

## Terminals / puzzles / UI
| File | What it is |
|---|---|
| beep | terminal key press beep, very short |
| pz_ok | puzzle stage solved, positive two-note chime |
| pz_bad | puzzle mistake, low error buzz |
| alarm | bunker alarm siren, one cycle (~0.8 s) |
| event | random-event announcement jingle (radio-style, ~0.7 s) |
| win | match won jingle (~2 s) |

## Loops (must loop seamlessly)
| File | What it is |
|---|---|
| amb_wind | outdoor ambience: wind, distant birds (4-10 s loop) |
| engine | vehicle engine idle loop (~1-2 s; the game pitches it up when driving) |

Optional extras (nice to have, the game can use them in Part 2 if you make them):
`reload` (magazine swap), `jump_land` (landing thud), `rain_loop` (rain ambience loop), `tank_tracks` (track clatter loop).
