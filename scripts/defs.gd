extends RefCounted
## Shared constants.

const E_SOLDIER := 1
const E_TURRET := 2
const E_TANK := 3
const E_PLAYER := 4
const E_SHELL := 7
const E_WRECK := 8
const E_KEY := 9
const E_LOOT := 10
const E_GRENADE := 11
const E_SMOKE := 12
const E_TERMINAL := 13
const E_AMMO := 14
const E_BULLET := 15

const ROLE_FOOT := 0
const ROLE_SOLO := 1
const ROLE_DRIVER := 2
const ROLE_GUNNER := 3
const ROLE_DEAD := 4
const ROLE_NAMES := ["ON FOOT", "VEHICLE COMMANDER", "DRIVER", "GUNNER", "KIA"]

const EV_SHOT := 1        # x2 = weapon id
const EV_CANNON := 3
const EV_EXPLOSION := 4
const EV_KNIFE := 5
const EV_ENEMY_SHOT := 6
const EV_MG := 7
const EV_IMPACT := 8
const EV_DOOR := 10
const EV_WIN := 11
const EV_HIT := 12
const EV_GATE := 13
const EV_BEEP := 14
const EV_TRACER := 15
const EV_PICKUP := 16     # x2 = 0 key, 1 loot
const EV_DEPOSIT := 17
const EV_UNLOCK := 18
const EV_PZ_OK := 19
const EV_PZ_BAD := 20
const EV_THROW := 21
const EV_BOUNCE := 22
const EV_SMOKE := 23
const EV_HEAL := 24
const EV_EVENT := 25      # x2 = event kind, y2 = phase (0 announced, 1 action starts, 2 over, 3 crate landed)

# ---------------------------------------------------------------- random events
const E_DROP := 16
const EVT_SUPPLY := 0
const EVT_ARTY := 1
const EVT_STORM := 2
const EVT_JAM := 3
const EVT_GOLD := 4
const EVT_BOUNTY := 5
const EVENT_NAMES := ["SUPPLY DROP", "AIR STRIKE", "STORM", "RADIO JAMMED", "GOLD RUSH", "BOUNTY"]
const STORM_NAMES := ["THUNDERSTORM", "SANDSTORM", "BLIZZARD", "ASH STORM"]
const EVENT_INFO := [
	"A crate is parachuting in: 250 pts of loot + full ammo and health. Grab it!",
	"Bombers and shells all over the map - avoid the red lines and markers!",
	"Visibility drops to almost nothing. Ambush time.",
	"Enemy jamming: minimaps are dead. Trust your eyes.",
	"Banked loot is worth DOUBLE right now!",
	"The leading team has a price on their heads: +100 pts per kill.",
]
const SUPPLY_VALUE := 250
const BOUNTY_VALUE := 100
const EV_STRIDE := 5      # type, x, y, x2, y2

# ---------------------------------------------------------------- game modes
const MODE_HEIST := 0
const MODE_CTF := 1
const MODE_TDM := 2
const MODE_NAMES := ["HEIST", "CAPTURE THE FLAG", "TEAM DEATHMATCH"]
const MODE_UNITS := ["pts", "captures", "kills"]
const MODE_SCORES := [[1500, 2500, 4000, 999999], [3, 5, 8, 999999], [25, 40, 60, 999999]]
const E_FLAG := 30         # team flag: fl = state (0 home, 1 carried, 2 dropped), aux = z
const H_FLAG_NOVEH := 30   # flag carriers can't use vehicles
const FLAG_RETURN := 25.0  # a dropped flag returns home after this long

const H_ENTER := 1
const H_KEYDOOR := 2      # need a key
const H_UNLOCK := 3       # can unlock with a key
const H_TERMINAL := 4
const H_VAULT := 5
const H_AMMO := 6
const H_DEPOSIT := 7
const H_SOLVED := 8
const H_HEAL := 30        # [gear] heal the hurt teammate in front of you (player record "hid" = their id)
const H_MORTAR := 20      # [use] man the base mortar
const H_MORTAR_BUSY := 21 # a teammate is already on it

# ---------------------------------------------------------------- base mortars
const EV_MORTAR := 40     # mortar fired at its emplacement; x2 = team
const EV_MORTAR_IN := 41  # incoming shell about to land here (whistle); x2 = team, y2 = time left
const FR_MORTAR := 245    # (240 = FR_PLANE)

const TEAM_COLORS := [Color(0.25, 0.45, 0.9), Color(0.95, 0.5, 0.12), Color(0.2, 0.75, 0.4), Color(0.7, 0.3, 0.85)]
const TEAM_NAMES := ["BLUE", "ORANGE", "GREEN", "VIOLET"]
const DIFFICULTY_NAMES := ["Recruit", "Regular", "Veteran"]
const BOT_NAMES := ["Hawk", "Viper", "Bear", "Wolf", "Falcon", "Cobra", "Lynx", "Raven", "Moose", "Fox", "Badger", "Eagle", "Jackal", "Otter", "Bison", "Puma", "Heron", "Mako"]
const ROOM_NAMES := ["CODE LOCK", "SIGNAL TUNER", "VAULT"]
const BUNKER_NAMES := ["NORTH", "SOUTH", "WEST", "EAST"]

# ---------------------------------------------------------------- weapons
const W_KNIFE := 0
const W_PISTOL := 1
const W_REVOLVER := 2
const W_RIFLE := 3
const W_SMG := 4
const W_SHOTGUN := 5
const W_SNIPER := 6
const W_LMG := 7

# dmg per pellet, cooldown, magazine, reload s, spread, pellets, range, starting reserve (-1 = infinite), auto, move speed mult, ADS zoom
const WPN := [
	{"name": "KNIFE", "dmg": 55.0, "cd": 0.45, "mag": 0, "reload": 0.0, "spread": 0.0, "pellets": 1, "reach": 1.4, "reserve": 0, "auto": true, "speed": 1.08, "zoom": 1.0, "vel": 0.0},
	{"name": "PISTOL", "vel": 70.0, "dmg": 20.0, "cd": 0.22, "mag": 12, "reload": 1.1, "spread": 0.02, "pellets": 1, "reach": 30.0, "reserve": -1, "auto": false, "speed": 1.05, "zoom": 1.25},
	{"name": "REVOLVER", "vel": 75.0, "dmg": 45.0, "cd": 0.55, "mag": 6, "reload": 2.0, "spread": 0.012, "pellets": 1, "reach": 34.0, "reserve": 36, "auto": false, "speed": 1.05, "zoom": 1.35},
	{"name": "ASSAULT RIFLE", "vel": 85.0, "dmg": 15.0, "cd": 0.1, "mag": 30, "reload": 2.0, "spread": 0.035, "pellets": 1, "reach": 32.0, "reserve": 120, "auto": true, "speed": 1.0, "zoom": 1.45},
	{"name": "SMG", "vel": 65.0, "dmg": 11.0, "cd": 0.065, "mag": 35, "reload": 1.6, "spread": 0.06, "pellets": 1, "reach": 22.0, "reserve": 175, "auto": true, "speed": 1.07, "zoom": 1.3},
	{"name": "SHOTGUN", "vel": 55.0, "dmg": 13.0, "cd": 0.85, "mag": 6, "reload": 2.6, "spread": 0.11, "pellets": 8, "reach": 14.0, "reserve": 30, "auto": false, "speed": 1.0, "zoom": 1.2},
	{"name": "SNIPER", "vel": 36.0, "dmg": 85.0, "cd": 1.3, "mag": 5, "reload": 2.6, "spread": 0.004, "pellets": 1, "reach": 60.0, "reserve": 25, "auto": false, "speed": 0.93, "zoom": 3.2},
	{"name": "LMG", "vel": 80.0, "dmg": 16.0, "cd": 0.085, "mag": 80, "reload": 4.0, "spread": 0.055, "pellets": 1, "reach": 32.0, "reserve": 160, "auto": true, "speed": 0.85, "zoom": 1.35},
	# burst: rounds per trigger pull (burst_cd between them, cd after the burst); hip: spread when not aiming;
	# rocket: fires a slow explosive projectile (world.gd Shell) with this splash radius instead of bullets
	{"name": "BURST RIFLE", "vel": 88.0, "dmg": 19.0, "cd": 0.36, "mag": 30, "reload": 2.1, "spread": 0.022, "pellets": 1, "reach": 34.0, "reserve": 120, "auto": false, "speed": 1.0, "zoom": 1.6, "burst": 3, "burst_cd": 0.065},
	{"name": "MARKSMAN RIFLE", "vel": 55.0, "dmg": 42.0, "cd": 0.34, "mag": 12, "reload": 2.4, "spread": 0.008, "pellets": 1, "reach": 50.0, "reserve": 48, "auto": false, "speed": 0.96, "zoom": 2.4, "hip": 0.045},
	{"name": "MACHINE PISTOL", "vel": 62.0, "dmg": 10.0, "cd": 0.058, "mag": 20, "reload": 1.3, "spread": 0.07, "pellets": 1, "reach": 20.0, "reserve": 100, "auto": true, "speed": 1.06, "zoom": 1.2},
	{"name": "DOUBLE BARREL", "vel": 55.0, "dmg": 15.0, "cd": 0.2, "mag": 2, "reload": 2.2, "spread": 0.13, "pellets": 9, "reach": 12.0, "reserve": 24, "auto": false, "speed": 1.03, "zoom": 1.15},
	{"name": "ROCKET LAUNCHER", "vel": 19.0, "dmg": 200.0, "cd": 0.8, "mag": 1, "reload": 3.2, "spread": 0.006, "pellets": 1, "reach": 48.0, "reserve": 4, "auto": false, "speed": 0.9, "zoom": 1.4, "rocket": 1.5},
]
const W_BURST := 8
const W_DMR := 9
const W_MPISTOL := 10
const W_DBARREL := 11
const W_RPG := 12
const PRIMARIES := [W_RIFLE, W_SMG, W_SHOTGUN, W_SNIPER, W_LMG, W_BURST, W_DMR, W_DBARREL, W_RPG]
const SECONDARIES := [W_PISTOL, W_REVOLVER, W_MPISTOL]
const EQ_FRAG := 0
const EQ_SMOKE := 1
const EQ_MEDKIT := 2
const EQ_AMMO := 3
const EQUIP_NAMES := ["FRAG GRENADES x2", "SMOKE GRENADES x2", "MEDKIT x2", "AMMO BAG (+60%)"]
const EQUIP_SHORT := ["FRAG", "SMOKE", "MEDKIT", "AMMO BAG"]
const EQUIP_COUNT := [2, 2, 2, 0]

# ---------------------------------------------------------------- loot
const LOOT_NAMES := ["CASH", "GOLD BAR", "JEWELS", "DOCUMENTS", "GOLDEN IDOL", "LOOT BAG"]
const LOOT_VALUES := [50, 100, 75, 40, 250, 0]

# ---------------------------------------------------------------- sprite atlas (16 x 16 frames of 64 px)
const ATLAS_GRID := 16
const SO_FRONT := 0
const SO_SIDE := 3
const SO_BACK := 6
const SO_SHOOT := 9
const SO_SHOOT_SIDE := 10
const SO_DYING := 11
const SO_DEAD := 12
const SO_CROUCH := 13
const SO_JUMP := 14
const FR_TANK := 80
const FR_WRECK := 96
const FR_TURRET := 97
const FR_TURRET_DEAD := 98
const FR_SHELL := 105
const FR_EXPL := 106
const FR_PUFF := 109
const FR_BLOOD := 110
const FR_SMOKE := 111
const FR_DUST := 112
const FR_TRACER := 113
const FR_TREE := 120
const FR_PINE := 121
const FR_DEADTREE := 122
const FR_BUSH := 123
const FR_CACTUS := 124
const FR_CRATE := 125
const FR_BARREL := 126
const FR_CARWRECK := 127
const FR_RUBBLE := 128
const FR_GRASS := 129
const FR_SNOWBUSH := 130
const FR_SANDBAG := 131
const FR_DRYBUSH := 132
const FR_KEY := 133        # + 0 neutral, 1..4 team
const FR_LOOT := 138       # + loot kind (0..5)
const FR_GRENADE := 144
const FR_SMOKE_GREN := 145
const FR_TERMINAL := 146   # + 0 code, 1 signal, 2 solved
const FR_AMMO := 149
const FR_FLAG := 216       # + team * 2 + wave frame (team 4 = neutral)
const FR_BIRD := 226       # 2 wing frames
const FR_FIRE := 228       # 2 flame frames (burning barrel)
const FR_REEDS := 230
const FR_FLOWERS := 231
const FR_LEAF := 232
const FR_CHUTE := 233
const FR_DROP := 234
const FR_PLANE := 240      # bomber seen from below (air strike event)

# ---------------------------------------------------------------- vehicles
# main: "cannon" (slow heavy shell), "autocannon" (fast light shells), "rockets" (heavy splash), "none" (gunner only has the MG)
# armor: fraction of bullet damage that gets through (explosives always do full damage)
const VEHICLES := [
	{"name": "TANK", "hp": 500.0, "speed": 4.2, "rev": 2.4, "turn": 1.6, "r": 0.6, "armor": 0.15,
		"main": "cannon", "main_cd": 2.2, "main_dmg": 150.0, "splash": 1.8, "shell_speed": 16.0,
		"mg_cd": 0.09, "mg_dmg": 9.0, "driver_mg": true, "desc": "Slow, heavily armoured. Cannon + coax MG."},
	{"name": "BRONEVIKS", "hp": 320.0, "speed": 6.0, "rev": 3.0, "turn": 2.1, "r": 0.55, "armor": 0.25,
		"main": "autocannon", "main_cd": 0.32, "main_dmg": 38.0, "splash": 0.9, "shell_speed": 30.0,
		"mg_cd": 0.09, "mg_dmg": 9.0, "driver_mg": true, "desc": "Armoured car. Rapid autocannon turret."},
	{"name": "MOTORCYCLE", "hp": 110.0, "speed": 8.5, "rev": 3.0, "turn": 3.2, "r": 0.35, "armor": 0.7,
		"main": "none", "main_cd": 0.0, "main_dmg": 0.0, "splash": 0.0, "shell_speed": 0.0,
		"mg_cd": 0.08, "mg_dmg": 8.0, "driver_mg": false, "desc": "Very fast and fragile. Sidecar MG."},
	{"name": "JEEP", "hp": 200.0, "speed": 7.2, "rev": 3.2, "turn": 2.5, "r": 0.5, "armor": 0.45,
		"main": "none", "main_cd": 0.0, "main_dmg": 0.0, "splash": 0.0, "shell_speed": 0.0,
		"mg_cd": 0.11, "mg_dmg": 15.0, "driver_mg": false, "desc": "Fast scout. Heavy machine gun on the back."},
	{"name": "ROCKET TRUCK", "hp": 260.0, "speed": 5.2, "rev": 2.6, "turn": 1.8, "r": 0.6, "armor": 0.3,
		"main": "rockets", "main_cd": 1.3, "main_dmg": 115.0, "splash": 2.3, "shell_speed": 11.0,
		"mg_cd": 0.0, "mg_dmg": 0.0, "driver_mg": false, "desc": "Rocket launcher with huge splash. Breaks gates fast."},
]
const V_TANK := 0
const V_BRONEVIKS := 1
const V_MOTO := 2
const V_JEEP := 3
const V_ROCKET := 4
const FR_VEH := 150   # vehicle sprites for types 1..4: FR_VEH + (type-1)*16 + team*4 + (front, side a, side b, back)

# ---------------------------------------------------------------- puzzles
const PZ_CODE := 0
const PZ_TUNER := 1
const PZ_DIAL := 2
const PZ_TIMING := 3
const PZ_VALVES := 4
const PZ_STEADY := 5
const PZ_PUMP := 6
const PUZZLES := [
	{"name": "CODE LOCK", "stages": 2, "help": "Type the arrow code shown on the screen (WASD / arrows)."},
	{"name": "SIGNAL TUNER", "stages": 2, "help": "Keep the needle inside the drifting green band (left / right)."},
	{"name": "SAFE DIAL", "stages": 2, "help": "Turn RIGHT to the 1st number, LEFT to the 2nd... press FIRE on each."},
	{"name": "TIMING LOCK", "stages": 3, "help": "Press FIRE while the sweeping marker is inside the green zone."},
	{"name": "PRESSURE VALVES", "stages": 2, "help": "Keep all 3 gauges in the green zone. Left/right selects, up/down adjusts."},
	{"name": "STEADY HAND", "stages": 2, "help": "Steer the shaking cursor (WASD) and keep it inside the moving ring."},
	{"name": "PRESSURE PUMP", "stages": 2, "help": "Alternate LEFT / RIGHT fast to pump the gauge into the green - keep it there."},
]
