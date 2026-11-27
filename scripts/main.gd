extends Node
## Menus, options, loadouts, game modes (Solo / Local Co-op / LAN, always 4-team capable),
## local input and the frame loop.

const MapData = preload("res://scripts/map_data.gd")
const World = preload("res://scripts/world.gd")
const GameView = preload("res://scripts/game_view.gd")
const Gfx = preload("res://scripts/gfx.gd")
const Defs = preload("res://scripts/defs.gd")
const SelfTest = preload("res://scripts/selftest.gd")
const MenuBg = preload("res://scripts/menu_bg.gd")
const VehicleBake = preload("res://scripts/vehicle_bake.gd")
const WeaponIcons = preload("res://scripts/weapon_icons.gd")
const Atmos = preload("res://scripts/atmos.gd")

const MAP_SEED := 20261119
const MOUSE_SENS := 0.0026
const RANDOM_MAP_ID := 999
const TIME_OPTIONS := [6, 10, 15, 20]
const SCORE_OPTIONS := [1500, 2500, 4000, 999999]

const CONTROLS := """KEYBOARD+MOUSE: WASD move/drive  Mouse aim  LMB fire  RMB aim down sights (tank: MG)  SHIFT sprint  C/CTRL crouch  SPACE jump
   E use / enter tank / hold at terminals   G grenade/medkit   1 primary  2 secondary  3 knife (wheel)   R reload   F seat   TAB scores
GAMEPAD (P2): L-stick move  R-stick aim  RT fire  LT aim  L3 sprint  B crouch  A jump  X use  LB gear  RB weapon  Y seat  D-pad up reload  Back scores
NUMPAD (P2, no pad): arrows move/turn  , . strafe  Num0 fire  Num. aim  Num9 sprint  Num/ crouch  Num7 jump  NumEnter use  Num8 gear  Num1-3 weapon  Num- reload  Num+ seat"""


class LocalP:
	var pid := 0
	var device := "kbm"
	var yaw := 0.0
	var pitch := 0.0
	var drv_look := 0.0   # driver free-look offset from the hull heading
	var psteer := 0.0     # plane pilot: mouse left/right = control stick (-1..1), slowly re-centres
	var role := 0
	var epoch := -1
	var use_count := 0
	var seat_count := 0
	var reload_count := 0
	var jump_count := 0
	var throw_count := 0
	var weapon_req := 1
	var weapon_seq := 0
	var prev := {}
	var kick := 0.0
	var last_shots := -1
	var wheel := 0
	var shake := 0.0
	var show_scores := false
	var ads := false
	var throw_t := 0.0
	var loadout := [3, 1, 0]
	var view_index := 0
	var view = null


enum St { MENU, LOBBY, GAME }

var state: int = St.MENU
var options_return: int = St.MENU
var mode := ""
var res := {}
var mapdata = null
var world = null
var snap: Dictionary = {}
var locals: Array = []
var effects: Array = []
var paused := false
var last_dyn := PackedInt32Array()
var last_doors := ""
var dust_t := 0.0
var shot_path := ""
var shot_mode := ""
var shot_frames := 0
var shot_aim := Vector2.ZERO
var loadout := [Defs.W_RIFLE, Defs.W_PISTOL, Defs.EQ_FRAG]

var game_root: Control
var views_box: HBoxContainer
var ui: CanvasLayer
var menu_root: Control
var lobby_root: Control
var pause_root: Control
var options_root: Control
var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: LineEdit
var browser_root: Control
var browser_list: VBoxContainer
var browser_status: Label
var browser_join: Button
var direct_port: LineEdit
var browser_rows := {}    # server key -> Button
var browser_cells := {}   # server key -> Array of Labels
var browser_sel := ""
var browser_msg := ""     # last connect message shown above the server list
var status_label: Label
var map_pick: OptionButton
var map_desc: Label
var ai_pick: OptionButton   # number of teams: 0 = 4 teams (3 enemy AI teams in solo), 1 = 2 teams
var mode_pick: OptionButton
var lobby_mode: OptionButton
var lobby_teams: OptionButton
var lobby_team_btns: Array = []
var mate_check: CheckBox
var size_pick: OptionButton
var lobby_size: OptionButton
var lobby_vehicle: OptionButton
var lobby_vehicle_desc: Label
var time_pick: OptionButton
var score_pick: OptionButton
var lobby_list: Label
var lobby_name: LineEdit
var ev_hold := PackedFloat32Array()   # host: events of WAR frames whose snapshot wasn't sent
var ui_key := ""
var lobby_info: Label
var lobby_map: OptionButton
var lobby_fill: CheckBox
var weather_pick: OptionButton   # index 0 = Random, else Atmos weather + 1
var tod_pick: OptionButton       # index 0 = Random, else Atmos tod + 1
var lobby_weather: OptionButton
var lobby_tod: OptionButton
var start_btn: Button
var loadout_pickers: Array = []
var ui_theme: Theme
var menu_bg = null
var map_preview: TextureRect
var vehicle_pick: OptionButton
var vehicle_desc: Label


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--selftest":
			get_tree().quit(SelfTest.run())
			return
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		if a.begins_with("--shotmode="):
			shot_mode = a.substr(11)
	res.shader = load("res://shaders/raycast.gdshader")
	res.wall_tex = Gfx.make_walls()
	res.sprite_tex = Atmos.add_lamp_sprite(Gfx.make_sprites())
	# 3D vehicle models pre-rendered from 16 angles (cached in user://)
	var baker = VehicleBake.new()
	add_child(baker)
	var vimg: Image = await baker.bake()
	baker.queue_free()
	res.veh_tex = ImageTexture.create_from_image(vimg) if vimg.get_width() >= 2048 else null
	print("3D vehicles: %s (%dx%d atlas)" % ["loaded" if res.veh_tex != null else "NOT AVAILABLE - using 2D sprites", vimg.get_width(), vimg.get_height()])
	# side-view weapon icons for the loadout pickers and the HUD (cached in user://)
	var icons: WeaponIcons = WeaponIcons.new()
	add_child(icons)
	await icons.bake(not OS.get_cmdline_user_args().has("--rebake-icons"))
	icons.queue_free()
	_add_ground_weapons()
	_build_ui()
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.game_started.connect(_on_net_game_started)
	Net.snapshot_received.connect(_apply_snapshot)
	Net.input_received.connect(_on_net_input)
	Net.connection_lost.connect(_on_connection_lost)
	Net.peer_left.connect(_on_peer_left)
	_show(St.MENU)
	if shot_path != "":
		var parts := shot_mode.split(":")
		shot_mode = parts[0]
		if parts.size() > 1:
			map_pick.select(int(parts[1]))
		if parts.size() > 2:
			loadout[0] = int(parts[2])
		if parts.size() > 3:
			size_pick.select(1 if int(parts[3]) <= 2 else 0)
		if parts.size() > 4:
			mode_pick.select(clampi(int(parts[4]), 0, Defs.MODE_NAMES.size() - 1))
			_on_mode_picked(mode_pick.selected)
		if parts.size() > 5:
			ai_pick.select(1 if int(parts[5]) == 2 else 0)
		if shot_mode != "menu":
			_start_local("coop" if shot_mode == "coop" else "solo")
		else:
			_on_map_picked(map_pick.selected)


## Dropped guns in the world use the baked side-view weapon icons, shrunk into their sprite frames.
func _add_ground_weapons() -> void:
	var stex: ImageTexture = res.sprite_tex
	var simg: Image = stex.get_image()
	for w in range(1, Defs.FR_WEAPONS.size()):
		var ic: Texture2D = WeaponIcons.weapon(w)
		if ic == null:
			continue
		var im: Image = ic.get_image()
		if im == null or im.get_width() < 4:
			continue
		im.convert(Image.FORMAT_RGBA8)
		var tw := 62
		var th := maxi(4, int(62.0 * float(im.get_height()) / float(im.get_width())))
		im.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		var fr: int = int(Defs.FR_WEAPONS[w])
		simg.blend_rect(im, Rect2i(0, 0, tw, th), Vector2i((fr % 16) * 64 + 1, (fr / 16) * 64 + 62 - th))
	stex.update(simg)
	if OS.get_cmdline_user_args().has("--dump-atlas"):
		simg.save_png("res://tools/preview_out/atlas.png")


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	game_root = Control.new()
	game_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_root)
	views_box = HBoxContainer.new()
	views_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	views_box.add_theme_constant_override("separation", 4)
	views_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_root.add_child(views_box)
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	# ---- main menu: live map fly-through, title on the left, setup card on the right
	ui_theme = _make_theme()
	menu_root = Control.new()
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.theme = ui_theme
	ui.add_child(menu_root)
	menu_bg = MenuBg.new()
	menu_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(menu_bg)
	menu_bg.setup(res)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.9))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.25))
	grad.add_point(0.45, Color(0.0, 0.0, 0.0, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(shade)
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 60
	hbox.offset_right = -40
	hbox.offset_top = 40
	hbox.offset_bottom = -30
	hbox.add_theme_constant_override("separation", 40)
	menu_root.add_child(hbox)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", 10)
	hbox.add_child(left)
	var title := _label(left, "RADIO\nSILENCE", 92, Color(0.98, 0.76, 0.22))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.06, 0.0))
	title.add_theme_constant_override("shadow_offset_x", 5)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("line_spacing", -26)
	var tag := _label(left, "4 TEAMS  ·  4 BUNKERS  ·  STEAL THE KEYS  ·  CRACK THE ROOMS  ·  BANK THE LOOT", 14, Color(0.85, 0.82, 0.7))
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	left.add_child(sp)
	_big_button(left, "SOLO", "You (+ AI teammate) vs AI teams", func(): _start_local("solo"))
	_big_button(left, "LOCAL CO-OP", "Split screen - 2 players, one vehicle", func(): _start_local("coop"))
	_big_button(left, "HOST LAN GAME", "Up to 4 teams of 2 - AI fills the rest", _on_host)
	_big_button(left, "JOIN LAN GAME", "Browse LAN / Hamachi games or connect by IP", _open_browser)
	_big_button(left, "OPTIONS", "Sound, controls, view, AI difficulty", func(): _open_options(St.MENU))
	_big_button(left, "QUIT", "", func(): get_tree().quit())
	status_label = _label(left, "", 16, Color(1, 0.6, 0.4))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(fill)
	# setup card
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.045, 0.04, 0.86)
	cs.border_color = Color(0.98, 0.76, 0.22, 0.6)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(8)
	cs.set_content_margin_all(22)
	cs.shadow_color = Color(0, 0, 0, 0.5)
	cs.shadow_size = 14
	card.add_theme_stylebox_override("panel", cs)
	hbox.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	card.add_child(vb)
	_section(vb, "MISSION")
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 14)
	vb.add_child(mrow)
	map_preview = TextureRect.new()
	map_preview.custom_minimum_size = Vector2(150, 150)
	map_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	mrow.add_child(map_preview)
	var mcol := VBoxContainer.new()
	mcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(mcol)
	map_pick = _map_picker(mcol)
	map_desc = _label(mcol, "", 14, Color(0.75, 0.78, 0.7))
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	map_pick.item_selected.connect(_on_map_picked)
	mode_pick = OptionButton.new()
	for mn in Defs.MODE_NAMES:
		mode_pick.add_item("Mode: %s" % mn)
	mode_pick.item_selected.connect(_on_mode_picked)
	mcol.add_child(mode_pick)
	ai_pick = OptionButton.new()
	ai_pick.add_item("Teams: 4  (1v1v1v1 - 3 enemy teams)")
	ai_pick.add_item("Teams: 2  (1v1 - opposite corners)")
	mcol.add_child(ai_pick)
	size_pick = OptionButton.new()
	size_pick.add_item("16 players  (1v1: 8 per team / 1v1v1v1: 4 per team)")
	size_pick.add_item("8 players  (1v1: 4 per team / 1v1v1v1: 2 per team)")
	mcol.add_child(size_pick)
	var wrow := HBoxContainer.new()
	mcol.add_child(wrow)
	weather_pick = _weather_picker(wrow)
	tod_pick = _tod_picker(wrow)
	mate_check = CheckBox.new()
	mate_check.text = "AI teammates when playing solo"
	mate_check.button_pressed = true
	mcol.add_child(mate_check)
	var hm := _row(vb)
	_lbl90(hm, "Match")
	time_pick = OptionButton.new()
	for t in TIME_OPTIONS:
		time_pick.add_item("%d minutes" % t)
	time_pick.select(1)
	hm.add_child(time_pick)
	score_pick = OptionButton.new()
	for sc in SCORE_OPTIONS:
		score_pick.add_item("no score limit" if sc > 99999 else "first to %d" % sc)
	score_pick.select(1)
	hm.add_child(score_pick)
	_on_mode_picked(0)
	_section(vb, "SOLDIER & VEHICLE")
	var hb := _row(vb)
	_lbl90(hb, "Callsign")
	name_edit = LineEdit.new()
	name_edit.text = Settings.pname
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(t: String):
		Settings.pname = t.strip_edges()
		Settings.save_settings())
	hb.add_child(name_edit)
	_loadout_row(vb)
	var vr := _row(vb)
	_lbl90(vr, "Vehicle")
	vehicle_pick = OptionButton.new()
	for v in Defs.VEHICLES.slice(0, Defs.GROUND_VEHICLES):
		vehicle_pick.add_item(v.name)
	vr.add_child(vehicle_pick)
	vehicle_desc = _label(vr, Defs.VEHICLES[0].desc, 13, Color(0.75, 0.78, 0.7))
	vehicle_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vehicle_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_pick.item_selected.connect(func(i): vehicle_desc.text = Defs.VEHICLES[i].desc)
	_section(vb, "LAN")
	var hb2 := _row(vb)
	_lbl90(hb2, "Host port")
	port_edit = LineEdit.new()
	port_edit.text = str(Net.DEFAULT_PORT)
	port_edit.custom_minimum_size = Vector2(90, 0)
	hb2.add_child(port_edit)
	_label(hb2, "Games are found automatically (LAN + Hamachi)", 13, Color(0.7, 0.7, 0.62))
	var ctl := _label(vb, CONTROLS, 10, Color(0.55, 0.6, 0.55))
	ctl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_on_map_picked(0)

	# ---- lobby
	var l := _screen(Color(0.05, 0.06, 0.05))
	lobby_root = l[0]
	var lv: VBoxContainer = l[1]
	_label(lv, "LAN LOBBY", 48, Color(0.95, 0.75, 0.25))
	lobby_info = _label(lv, "", 16, Color(0.7, 0.8, 0.7))
	var lm := _row(lv)
	_label(lm, "Map:", 18)
	lobby_map = _map_picker(lm)
	lobby_map.item_selected.connect(func(_i): _push_lobby_cfg())
	lobby_fill = CheckBox.new()
	lobby_fill.text = "Fill empty slots with AI"
	lobby_fill.button_pressed = true
	lobby_fill.toggled.connect(func(_b): _push_lobby_cfg())
	lm.add_child(lobby_fill)
	lobby_size = OptionButton.new()
	lobby_size.add_item("16 players")
	lobby_size.add_item("8 players")
	lobby_size.item_selected.connect(func(_i): _push_lobby_cfg())
	lm.add_child(lobby_size)
	lobby_weather = _weather_picker(lm)
	lobby_weather.item_selected.connect(func(_i): _push_lobby_cfg())
	lobby_tod = _tod_picker(lm)
	lobby_tod.item_selected.connect(func(_i): _push_lobby_cfg())
	var lmm := _row(lv)
	lobby_mode = OptionButton.new()
	for mn in Defs.MODE_NAMES:
		lobby_mode.add_item("Mode: %s" % mn)
	lobby_mode.item_selected.connect(func(_i): _push_lobby_cfg())
	lmm.add_child(lobby_mode)
	lobby_teams = OptionButton.new()
	lobby_teams.add_item("Teams: 4")
	lobby_teams.add_item("Teams: 2")
	lobby_teams.item_selected.connect(func(_i): _push_lobby_cfg())
	lmm.add_child(lobby_teams)
	var nrow := _row(lv)
	_label(nrow, "Your name:", 18)
	lobby_name = LineEdit.new()
	lobby_name.max_length = 16
	lobby_name.custom_minimum_size = Vector2(220, 0)
	lobby_name.text_submitted.connect(func(_t): _on_lobby_name())
	lobby_name.focus_exited.connect(_on_lobby_name)
	nrow.add_child(lobby_name)
	_button(nrow, "RENAME", _on_lobby_name)
	lobby_list = _label(lv, "", 20)
	lobby_list.autowrap_mode = TextServer.AUTOWRAP_WORD
	lobby_list.custom_minimum_size = Vector2(900, 0)
	var th := _row(lv)
	_label(th, "Join team:", 18)
	lobby_team_btns = []
	for t in 4:
		var b := Button.new()
		b.text = Defs.TEAM_NAMES[t]
		b.custom_minimum_size = Vector2(100, 40)
		b.add_theme_color_override("font_color", Defs.TEAM_COLORS[t].lightened(0.3))
		b.pressed.connect(_on_team.bind(t))
		th.add_child(b)
		lobby_team_btns.append(b)
	var vrow := _row(lv)
	_label(vrow, "Your vehicle:", 18)
	lobby_vehicle = OptionButton.new()
	for v in Defs.VEHICLES.slice(0, Defs.GROUND_VEHICLES):
		lobby_vehicle.add_item(v.name)
	lobby_vehicle.item_selected.connect(_on_lobby_vehicle)
	vrow.add_child(lobby_vehicle)
	lobby_vehicle_desc = _label(vrow, Defs.VEHICLES[0].desc, 14, Color(0.75, 0.78, 0.7))
	_label(lv, "Vehicles: every pair of teammates crews one (2 per team in 4-player teams). The first player of each pair picks it.", 13, Color(0.65, 0.68, 0.6))
	_loadout_row(lv)
	start_btn = _button(lv, "START MISSION", _on_start_lan)
	_button(lv, "LEAVE", _quit_to_menu)

	# ---- pause
	var p := _screen(Color(0, 0, 0, 0.65))
	pause_root = p[0]
	var pv: VBoxContainer = p[1]
	_label(pv, "PAUSED", 48, Color(0.95, 0.75, 0.25))
	_label(pv, "Loadout changes apply when you next redeploy.", 14, Color(0.8, 0.8, 0.7))
	_loadout_row(pv)
	_button(pv, "RESUME", _toggle_pause)
	_button(pv, "OPTIONS", func(): _open_options(St.GAME))
	_button(pv, "QUIT TO MENU", _quit_to_menu)
	_label(pv, CONTROLS, 11, Color(0.75, 0.75, 0.75))

	_build_options()
	_build_browser()


## Primary / secondary / gear pickers. Several copies (menu, lobby, pause) stay in sync.
func _loadout_row(parent: Node) -> void:
	var r := _row(parent)
	_label(r, "Loadout:", 18)
	var lists := [Defs.PRIMARIES, Defs.SECONDARIES, [0, 1, 2, 3]]
	var pickers := []
	for slot in 3:
		var ob := OptionButton.new()
		for id in lists[slot]:
			var label: String = Defs.WPN[id].name if slot < 2 else Defs.EQUIP_NAMES[id]
			var icon: Texture2D = WeaponIcons.weapon_small(id) if slot < 2 else WeaponIcons.equip_small(id)
			if icon != null:
				ob.add_icon_item(icon, label)
			else:
				ob.add_item(label)
		ob.select(lists[slot].find(loadout[slot]))
		ob.item_selected.connect(func(i):
			loadout[slot] = lists[slot][i]
			_sync_loadout())
		r.add_child(ob)
		pickers.append(ob)
	loadout_pickers.append(pickers)


func _sync_loadout() -> void:
	var lists := [Defs.PRIMARIES, Defs.SECONDARIES, [0, 1, 2, 3]]
	for row in loadout_pickers:
		for slot in 3:
			row[slot].select(lists[slot].find(loadout[slot]))
	for lp in locals:
		if lp.view_index == 0:
			lp.loadout = loadout.duplicate()


func _build_options() -> void:
	var o := _screen(Color(0.04, 0.05, 0.04, 0.96))
	options_root = o[0]
	var v: VBoxContainer = o[1]
	_label(v, "OPTIONS", 48, Color(0.95, 0.75, 0.25))
	_label(v, "Sound", 22, Color(0.8, 0.9, 0.75))
	_slider(v, "Master volume", 0.0, 1.0, 0.05, Settings.master, func(x): Settings.master = x)
	_slider(v, "Effects volume", 0.0, 1.0, 0.05, Settings.sfx, func(x): Settings.sfx = x)
	_slider(v, "Ambience volume", 0.0, 1.0, 0.05, Settings.ambience, func(x): Settings.ambience = x)
	_label(v, "Controls & view", 22, Color(0.8, 0.9, 0.75))
	_slider(v, "Mouse sensitivity", 0.2, 3.0, 0.1, Settings.sens, func(x): Settings.sens = x)
	_slider(v, "Field of view", 60.0, 110.0, 1.0, Settings.fov, func(x): Settings.fov = x)
	var pr := _row(v)
	var pl := _label(pr, "Pixel size", 18)
	pl.custom_minimum_size = Vector2(220, 0)
	var pix := OptionButton.new()
	for nm in ["Sharp (1x)", "Fine (2x)", "Classic (3x)", "Chunky (4x)"]:
		pix.add_item(nm)
	pix.select(clampi(Settings.pixel - 1, 0, 3))
	pix.item_selected.connect(func(i):
		Settings.pixel = i + 1
		_options_changed())
	pr.add_child(pix)
	_check(v, "Head bob", Settings.bob, func(b): Settings.bob = b)
	_check(v, "Invert mouse Y", Settings.invert_y, func(b): Settings.invert_y = b)
	_check(v, "Fullscreen", Settings.fullscreen, func(b): Settings.fullscreen = b)
	_check(v, "Show FPS", Settings.show_fps, func(b): Settings.show_fps = b)
	_label(v, "Interface", 22, Color(0.8, 0.9, 0.75))
	_slider(v, "UI scale", 0.7, 1.5, 0.05, Settings.ui_scale, func(x): Settings.ui_scale = x)
	_slider(v, "Game log size", 0.6, 1.6, 0.05, Settings.log_size, func(x): Settings.log_size = x)
	_check(v, "Teammate name tags & health", Settings.nametags, func(b): Settings.nametags = b)
	_label(v, "Game", 22, Color(0.8, 0.9, 0.75))
	var dr := _row(v)
	var dl := _label(dr, "AI difficulty", 18)
	dl.custom_minimum_size = Vector2(220, 0)
	var diff := OptionButton.new()
	for nm in Defs.DIFFICULTY_NAMES:
		diff.add_item(nm)
	diff.select(Settings.difficulty)
	diff.item_selected.connect(func(i):
		Settings.difficulty = i
		_options_changed())
	dr.add_child(diff)
	_button(v, "BACK", _close_options)


func _options_changed() -> void:
	Settings.apply()
	Settings.save_settings()


func _slider(parent: Node, text: String, lo: float, hi: float, stp: float, val: float, setter: Callable) -> void:
	var r := _row(parent)
	var tl := _label(r, text, 18)
	tl.custom_minimum_size = Vector2(220, 0)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = stp
	s.value = val
	s.custom_minimum_size = Vector2(260, 24)
	r.add_child(s)
	var vl := _label(r, str(snappedf(val, stp)), 16)
	s.value_changed.connect(func(x):
		setter.call(x)
		vl.text = str(snappedf(x, stp))
		_options_changed())


func _check(parent: Node, text: String, val: bool, setter: Callable) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = val
	c.add_theme_font_size_override("font_size", 18)
	c.toggled.connect(func(b):
		setter.call(b)
		_options_changed())
	parent.add_child(c)


func _open_options(ret: int) -> void:
	options_return = ret
	options_root.visible = true
	menu_root.visible = false
	pause_root.visible = false


func _close_options() -> void:
	options_root.visible = false
	if options_return == St.GAME and state == St.GAME:
		pause_root.visible = paused
	else:
		menu_root.visible = state == St.MENU


# ---------------------------------------------------------------- LAN server browser

const BROWSER_COLS := [210, 170, 90, 80, 70, 120]   # host, map, players, teams, ping, status


func _build_browser() -> void:
	var o := _screen(Color(0.04, 0.05, 0.04, 0.96))
	browser_root = o[0]
	browser_root.theme = ui_theme
	var v: VBoxContainer = o[1]
	v.custom_minimum_size = Vector2(800, 0)
	_label(v, "SERVER BROWSER", 48, Color(0.95, 0.75, 0.25))
	_section(v, "LAN GAMES")
	browser_status = _label(v, "", 14, Color(0.7, 0.8, 0.7))
	browser_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	v.add_child(head)
	var heads := ["HOST", "MAP", "PLAYERS", "TEAMS", "PING", "STATUS"]
	for i in heads.size():
		var hl := _label(head, ("    " if i == 0 else "") + str(heads[i]), 13, Color(0.98, 0.8, 0.4))
		hl.custom_minimum_size = Vector2(float(BROWSER_COLS[i]) + (20.0 if i == 0 else 0.0), 0)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(Color(0.02, 0.025, 0.02, 0.9), Color(0.98, 0.76, 0.22, 0.35), 1, 4, 4))
	v.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	browser_list = VBoxContainer.new()
	browser_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser_list.add_theme_constant_override("separation", 4)
	scroll.add_child(browser_list)
	var br := _row(v)
	browser_join = _button(br, "JOIN SELECTED", _on_browser_join)
	browser_join.custom_minimum_size = Vector2(200, 40)
	var rb := _button(br, "REFRESH", _on_browser_refresh)
	rb.custom_minimum_size = Vector2(140, 40)
	_label(br, "Double-click a game to join.", 13, Color(0.7, 0.7, 0.62))
	_section(v, "DIRECT CONNECT")
	var dr := _row(v)
	_lbl90(dr, "Host IP")
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(200, 0)
	dr.add_child(ip_edit)
	_label(dr, "Port", 16)
	direct_port = LineEdit.new()
	direct_port.text = str(Net.DEFAULT_PORT)
	direct_port.custom_minimum_size = Vector2(90, 0)
	dr.add_child(direct_port)
	var cb := _button(dr, "CONNECT", _on_join)
	cb.custom_minimum_size = Vector2(140, 40)
	_button(v, "BACK", _close_browser)
	Net.discovery.servers_changed.connect(_refresh_browser)


func _open_browser() -> void:
	menu_root.visible = false
	browser_root.visible = true
	browser_sel = ""
	browser_msg = ""
	Net.discovery.start_browse()
	_refresh_browser()


func _close_browser() -> void:
	if Net.online and not Net.is_host() and state == St.MENU:
		Net.leave()   # cancel a pending connection attempt
	browser_root.visible = false
	Net.discovery.stop_browse()
	menu_root.visible = state == St.MENU


func _on_browser_refresh() -> void:
	Net.discovery.stop_browse()
	Net.discovery.start_browse()
	var ip := ip_edit.text.strip_edges()
	if ip.count(".") == 3 and not ip.begins_with("127."):
		Net.discovery.query_address(ip)   # also ask the typed address directly
	browser_sel = ""
	_refresh_browser()


func _browser_row(key: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 38)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.add_theme_constant_override("separation", 0)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var cells: Array = []
	for w in BROWSER_COLS:
		var l := _label(hb, "", 16)
		l.custom_minimum_size = Vector2(float(w), 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cells.append(l)
	b.pressed.connect(_browser_select.bind(key))
	b.gui_input.connect(_on_browser_row_input.bind(key))
	b.mouse_entered.connect(func(): Sfx.play("switch", -16.0, 1.5))
	browser_list.add_child(b)
	browser_rows[key] = b
	browser_cells[key] = cells
	return b


func _on_browser_row_input(ev: InputEvent, key: String) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
		browser_sel = key
		_on_browser_join()


func _browser_select(key: String) -> void:
	browser_sel = key
	for k: String in browser_rows:
		var b: Button = browser_rows[k]
		b.set_pressed_no_signal(k == key)
	browser_join.disabled = false


func _refresh_browser() -> void:
	if browser_root == null or not browser_root.visible:
		return
	var servers: Array = Net.discovery.get_servers()
	var seen := {}
	var idx := 0
	for s: Dictionary in servers:
		var key: String = str(s.get("key", ""))
		seen[key] = true
		var b: Button = browser_rows.get(key, null)
		if b == null:
			b = _browser_row(key)
		browser_list.move_child(b, idx)
		idx += 1
		var cells: Array = browser_cells[key]
		var mi: int = clampi(int(s.get("map", 0)), 0, MapData.MAPS.size() - 1)
		var players: int = int(s.get("players", 0))
		var mx: int = int(s.get("max", 8))
		var ping: int = int(s.get("ping", -1))
		var busy: bool = bool(s.get("in_game", false))
		var ip: String = str(s.get("ip", ""))
		var name_l: Label = cells[0]
		name_l.text = str(s.get("name", "Host"))
		name_l.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
		var map_l: Label = cells[1]
		map_l.text = str(MapData.MAPS[mi].name) if int(s.get("map", 0)) < MapData.MAPS.size() else "Random map"
		var pl_l: Label = cells[2]
		pl_l.text = "%d/%d" % [players, mx]
		var tm_l: Label = cells[3]
		tm_l.text = "%d x %d" % [int(s.get("teams", 4)), int(s.get("size", 2))]
		var pg_l: Label = cells[4]
		pg_l.text = ("%d ms" % ping) if ping >= 0 else "-"
		var st_l: Label = cells[5]
		if busy:
			st_l.text = "IN PROGRESS"
			st_l.add_theme_color_override("font_color", Color(1, 0.55, 0.4))
		elif players >= mx:
			st_l.text = "FULL"
			st_l.add_theme_color_override("font_color", Color(1, 0.55, 0.4))
		else:
			st_l.text = "LOBBY"
			st_l.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
		var lab := Net.Discovery.address_label(ip)
		b.tooltip_text = "%s:%d  (%s)" % [ip, int(s.get("port", Net.DEFAULT_PORT)), lab]
		b.set_pressed_no_signal(key == browser_sel)
	for k: String in browser_rows.keys():
		if not seen.has(k):
			var old: Button = browser_rows[k]
			old.queue_free()
			browser_rows.erase(k)
			browser_cells.erase(k)
			if browser_sel == k:
				browser_sel = ""
	browser_join.disabled = browser_sel == ""
	var txt := ""
	if servers.is_empty():
		txt = "Searching for games on %s ..." % Net.Discovery.describe_addresses()
	else:
		txt = "%d game%s found  -  searching on %s" % [servers.size(), "" if servers.size() == 1 else "s", Net.Discovery.describe_addresses()]
	browser_status.text = (browser_msg + "\n" + txt) if browser_msg != "" else txt


func _on_browser_join() -> void:
	if browser_sel == "":
		return
	var s: Dictionary = Net.discovery.get_server(browser_sel)
	var ip: String = str(s.get("ip", ""))
	if ip == "":
		browser_status.text = "That game is no longer answering."
		return
	ip_edit.text = ip
	direct_port.text = str(int(s.get("port", Net.DEFAULT_PORT)))
	_on_join()


func _map_picker(parent: Node) -> OptionButton:
	var ob := OptionButton.new()
	for mi in MapData.MAPS:
		ob.add_item("%s  (%dx%d)" % [mi.name, mi.size, mi.size])
	ob.add_separator()
	ob.add_item("?  RANDOM MAP", RANDOM_MAP_ID)
	parent.add_child(ob)
	return ob


## Map index for a picker: a fixed map, or a random one when "RANDOM MAP" is chosen.
func _picked_map(ob: OptionButton) -> int:
	var id := ob.get_selected_id()
	if id == RANDOM_MAP_ID or id < 0 or id >= MapData.MAPS.size():
		return randi() % MapData.MAPS.size()
	return id


func _row(parent: Node) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	parent.add_child(hb)
	return hb


func _screen(bg: Color) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	var r := ColorRect.new()
	r.color = bg
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(r)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(640, 0)
	cc.add_child(vb)
	root.visible = false
	return [root, vb]


func _label(parent: Node, text: String, size: int, col := Color(0.88, 0.88, 0.82)) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", col)
	parent.add_child(lab)
	return lab


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _show(st: int) -> void:
	state = st
	menu_root.visible = st == St.MENU
	lobby_root.visible = st == St.LOBBY
	pause_root.visible = false
	options_root.visible = false
	game_root.visible = st == St.GAME
	if browser_root != null and browser_root.visible:
		if st == St.MENU:
			menu_root.visible = false   # e.g. a failed join: stay in the server browser
		else:
			browser_root.visible = false
			Net.discovery.stop_browse()
	if st != St.GAME:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Sfx.set_ambience(false)


func _player_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Player"


# ---------------------------------------------------------------- modes / rosters

func _add_bots(roster: Array, team: int, count: int) -> void:
	for i in count:
		var pid := 100 + roster.size()
		var n := Defs.BOT_NAMES.size()
		var k := pid - 100
		# 30 bots in a 16 v 16 war: names get a number once the list wraps ("Opus 2")
		var nm: String = Defs.BOT_NAMES[k % n] + ("" if k < n else " %d" % (k / n + 1))
		roster.append({"pid": pid, "peer": 0, "name": nm, "team": team, "bot": true})


func _match_cfg(roster: Array, map_i: int, team_size := 2, game_mode := 0, n_teams := 4) -> Dictionary:
	var gm := clampi(game_mode, 0, Defs.MODE_NAMES.size() - 1)
	var scores: Array = Defs.MODE_SCORES[gm]
	return _with_atmos(map_i, {"seed": MAP_SEED, "map": map_i, "roster": roster, "difficulty": Settings.difficulty, "team_size": team_size,
		"time": float(TIME_OPTIONS[time_pick.selected]) * 60.0, "score": int(scores[score_pick.selected]),
		"mode": gm, "teams": 2 if n_teams == 2 else 4})


## Weather + time of day: the host resolves "Random" here, so every client gets the same "weather" / "tod" ints.
func _with_atmos(map_i: int, cfg: Dictionary) -> Dictionary:
	var lan := Net.online and Net.is_host()
	var wp: OptionButton = lobby_weather if lan else weather_pick
	var tp: OptionButton = lobby_tod if lan else tod_pick
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var theme := int(MapData.MAPS[clampi(map_i, 0, MapData.MAPS.size() - 1)].theme)
	cfg["weather"] = Atmos.resolve_weather(Atmos.arg_override("weather", wp.selected - 1), theme, rng)
	cfg["tod"] = Atmos.resolve_tod(Atmos.arg_override("tod", tp.selected - 1), rng)
	if int(cfg.get("mode", 0)) == Defs.MODE_WAR:
		# a war is fought at dusk or at night, under clear, cloudy or stormy skies
		if int(cfg.tod) < 2:
			cfg["tod"] = 2 + rng.randi() % 2
		if not [0, 1, 3].has(int(cfg.weather)):
			cfg["weather"] = [0, 1, 3][rng.randi() % 3]
	return cfg


func _weather_picker(parent: Node) -> OptionButton:
	var ob := OptionButton.new()
	ob.add_item("Weather: Random")
	for n in Atmos.WEATHER_NAMES:
		ob.add_item("Weather: " + str(n))
	parent.add_child(ob)
	return ob


func _tod_picker(parent: Node) -> OptionButton:
	var ob := OptionButton.new()
	ob.add_item("Time: Random")
	for n in Atmos.TOD_NAMES:
		ob.add_item("Time: " + str(n))
	parent.add_child(ob)
	return ob


## Game mode changed in the menu: relabel the score limits (points / captures / kills).
func _on_mode_picked(i: int) -> void:
	if score_pick == null:
		return
	var scores: Array = Defs.MODE_SCORES[clampi(i, 0, Defs.MODE_SCORES.size() - 1)]
	# WAR: always 2 teams of 16 - the team / player pickers are locked
	var war := i == Defs.MODE_WAR
	if ai_pick != null and size_pick != null:
		ai_pick.disabled = war
		size_pick.disabled = war
		size_pick.set_item_text(0, "32 players  (WAR: 16 v 16, 2 teams)" if war else "16 players  (1v1: 8 per team / 1v1v1v1: 4 per team)")
		ai_pick.set_item_text(1, "Teams: 2  (WAR: 16 v 16)" if war else "Teams: 2  (1v1 - opposite corners)")
		if war:
			size_pick.select(0)
			ai_pick.select(1)
	for k in scores.size():
		var sc: int = scores[k]
		score_pick.set_item_text(k, "no score limit" if sc > 99999 else "first to %d %s" % [sc, Defs.MODE_UNITS[i]])


func _start_local(m: String) -> void:
	var roster: Array = [{"pid": 1, "peer": 1, "name": _player_name(), "team": 0, "loadout": loadout.duplicate(), "vehicle": vehicle_pick.selected}]
	var n_teams: int = 2 if ai_pick.selected == 1 else 4
	# total players is fixed (16 or 8); 1v1 makes big teams, 1v1v1v1 small ones
	var ts: int = (8 if size_pick.selected == 1 else 16) / n_teams
	if mode_pick.selected == Defs.MODE_WAR:
		n_teams = 2
		ts = 16   # WAR is always 16 v 16
	if m == "coop":
		roster.append({"pid": 2, "peer": 1, "name": "Player 2", "team": 0, "loadout": [Defs.W_SMG, Defs.W_PISTOL, Defs.EQ_MEDKIT]})
		_add_bots(roster, 0, ts - 2)
	elif mate_check.button_pressed:
		_add_bots(roster, 0, ts - 1)
	for t in range(1, n_teams):
		_add_bots(roster, t, ts)
	_begin(_match_cfg(roster, _picked_map(map_pick), ts, mode_pick.selected, n_teams), true, m)


func _on_host() -> void:
	Net.my_vehicle = vehicle_pick.selected
	lobby_vehicle.select(vehicle_pick.selected)
	var err := Net.host(int(port_edit.text), _player_name())
	if err != OK:
		status_label.text = "Could not host on port %s (error %d)" % [port_edit.text, err]
		return
	lobby_info.text = "Hosting on port %s - friends find this game under JOIN LAN GAME (LAN and Hamachi).\nYour addresses for direct connect: %s" % [port_edit.text, Net.Discovery.describe_addresses()]
	lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	lobby_map.select(map_pick.selected)
	lobby_weather.select(weather_pick.selected)
	lobby_tod.select(tod_pick.selected)
	_push_lobby_cfg()
	_show(St.LOBBY)
	_on_lobby_changed()


func _push_lobby_cfg() -> void:
	if Net.is_host():
		Net.lobby_cfg = {"map": lobby_map.selected, "fill": lobby_fill.button_pressed, "size": (8 if lobby_size.selected == 1 else 16) / (2 if lobby_teams.selected == 1 else 4)}
		Net.lobby_cfg["weather"] = lobby_weather.selected
		Net.lobby_cfg["tod"] = lobby_tod.selected
		Net.lobby_cfg["mode"] = lobby_mode.selected
		Net.lobby_cfg["teams"] = 2 if lobby_teams.selected == 1 else 4
		if lobby_mode.selected == Defs.MODE_WAR:
			Net.lobby_cfg["teams"] = 2
			Net.lobby_cfg["size"] = 16
		Net.fit_teams()   # players on teams that no longer play move to an active one
		Net.sync_lobby.rpc(Net.players, Net.lobby_cfg)


func _on_join() -> void:
	var port := int(direct_port.text) if direct_port.text.strip_edges().is_valid_int() else Net.DEFAULT_PORT
	Net.my_vehicle = vehicle_pick.selected
	var err := Net.join(ip_edit.text.strip_edges(), port, _player_name())
	if err != OK:
		status_label.text = "Could not connect (error %d)" % err
		browser_msg = status_label.text
		_refresh_browser()
		return
	status_label.text = "Connecting to %s:%d..." % [ip_edit.text.strip_edges(), port]
	browser_msg = status_label.text
	_refresh_browser()


func _on_lobby_changed() -> void:
	if not Net.online:
		return
	if state == St.MENU:
		lobby_info.text = "Connected to %s. Waiting for the host to start." % ip_edit.text
		_show(St.LOBBY)
	var host := Net.is_host()
	lobby_map.disabled = not host
	lobby_fill.disabled = not host
	lobby_size.disabled = not host
	lobby_weather.disabled = not host
	lobby_tod.disabled = not host
	lobby_mode.disabled = not host
	lobby_teams.disabled = not host
	var war_lobby: bool = int(Net.lobby_cfg.get("mode", 0)) == Defs.MODE_WAR
	if war_lobby:
		lobby_size.disabled = true
		lobby_teams.disabled = true
	lobby_size.set_item_text(0, "32 players (16 v 16)" if war_lobby else "16 players")
	if war_lobby:
		lobby_size.select(0)
		lobby_teams.select(1)
	if not host:
		lobby_map.select(int(Net.lobby_cfg.get("map", 0)))
		lobby_fill.button_pressed = bool(Net.lobby_cfg.get("fill", true))
		lobby_size.select(1 if Net.team_size() * Net.team_count() <= 8 else 0)
		lobby_weather.select(clampi(int(Net.lobby_cfg.get("weather", 0)), 0, lobby_weather.item_count - 1))
		lobby_tod.select(clampi(int(Net.lobby_cfg.get("tod", 0)), 0, lobby_tod.item_count - 1))
		lobby_mode.select(clampi(int(Net.lobby_cfg.get("mode", 0)), 0, Defs.MODE_NAMES.size() - 1))
		lobby_teams.select(1 if Net.team_count() == 2 else 0)
	for t in lobby_team_btns.size():
		(lobby_team_btns[t] as Button).visible = t < Net.team_count()
	var me_id := multiplayer.get_unique_id()
	if Net.players.has(me_id) and not lobby_name.has_focus():
		lobby_name.text = str(Net.players[me_id].name)
	if Net.players.has(me_id) and lobby_vehicle.selected != int(Net.players[me_id].get("vehicle", 0)):
		lobby_vehicle.select(int(Net.players[me_id].get("vehicle", 0)))
		lobby_vehicle_desc.text = Defs.VEHICLES[lobby_vehicle.selected].desc
	# teammates crew vehicles in pairs (join order): only the 1st, 3rd... player of a team picks the vehicle
	var my_slot := Net.team_slot(me_id)
	var picks := my_slot % 2 == 0
	lobby_vehicle.disabled = not picks
	if not picks:
		var leader := Net.slot_player(int(Net.players[me_id].team), my_slot - 1) if Net.players.has(me_id) else -1
		lobby_vehicle_desc.text = "%s picks your vehicle (you crew it with them)." % (str(Net.players[leader].name) if Net.players.has(leader) else "Your teammate")
	elif lobby_vehicle_desc.text.ends_with("(you crew it with them)."):
		lobby_vehicle_desc.text = Defs.VEHICLES[lobby_vehicle.selected].desc
	var txt := "%s  -  %d teams\n" % [Defs.MODE_NAMES[clampi(int(Net.lobby_cfg.get("mode", 0)), 0, Defs.MODE_NAMES.size() - 1)], Net.team_count()]
	for t in Net.team_count():
		var names: Array = []
		var ids: Array = Net.players.keys()
		ids.sort()
		var k := 0
		for id in ids:
			if int(Net.players[id].team) == t:
				var vn: String = Defs.VEHICLES[clampi(int(Net.players[id].get("vehicle", 0)), 0, 4)].name
				names.append("%s%s%s" % [str(Net.players[id].name), " (host)" if int(id) == 1 else "", " [%s]" % vn if k % 2 == 0 else ""])
				k += 1
		var fill := "  + AI" if lobby_fill.button_pressed and names.size() < Net.team_size() else ""
		txt += "%s:  %s%s\n" % [Defs.TEAM_NAMES[t], ", ".join(names) if names.size() > 0 else "-", fill]
	lobby_list.text = txt
	start_btn.disabled = not host


func _on_lobby_name() -> void:
	var n := lobby_name.text.strip_edges().substr(0, 16)
	if n == "" or not Net.online:
		return
	var me_id := multiplayer.get_unique_id()
	if Net.players.has(me_id) and str(Net.players[me_id].name) == n:
		return
	name_edit.text = n
	Settings.pname = n
	Settings.save_settings()
	if Net.is_host():
		Net.set_pname(1, n)
	else:
		Net.request_name.rpc_id(1, n)


func _on_lobby_vehicle(i: int) -> void:
	lobby_vehicle_desc.text = Defs.VEHICLES[i].desc
	vehicle_pick.select(i)
	Net.my_vehicle = i
	if Net.is_host():
		Net.set_vehicle(1, i)
	elif Net.online:
		Net.request_vehicle.rpc_id(1, i)


func _on_team(t: int) -> void:
	if Net.is_host():
		Net.set_team(1, t)
	elif Net.online:
		Net.request_team.rpc_id(1, t)


func _on_start_lan() -> void:
	if not Net.is_host():
		return
	var ids: Array = Net.players.keys()
	ids.sort()
	var roster: Array = []
	Net.pid_owner = {}
	var pid := 1
	var counts := [0, 0, 0, 0]
	for id in ids:
		var t := int(Net.players[id].team)
		var entry := {"pid": pid, "peer": id, "name": Net.players[id].name, "team": t}
		entry["vehicle"] = int(Net.players[id].get("vehicle", 0))
		roster.append(entry)
		counts[t] += 1
		Net.pid_owner[pid] = id
		pid += 1
	if lobby_fill.button_pressed:
		for t in Net.team_count():
			_add_bots(roster, t, Net.team_size() - int(counts[t]))
	Net.start_game.rpc(_match_cfg(roster, _picked_map(lobby_map), Net.team_size(), int(Net.lobby_cfg.get("mode", 0)), Net.team_count()))


func _on_net_game_started(cfg: Dictionary) -> void:
	_begin(cfg, Net.is_host(), "host" if Net.is_host() else "client")


func _on_net_input(pid: int, inp: Array) -> void:
	if world != null:
		world.set_input(pid, inp)


func _on_peer_left(peer: int) -> void:
	if world == null:
		return
	for pid in Net.pid_owner.keys():
		if int(Net.pid_owner[pid]) == peer:
			world.remove_player(int(pid))


func _on_connection_lost(reason: String) -> void:
	_teardown()
	_show(St.MENU)
	status_label.text = reason
	browser_msg = reason
	_refresh_browser()


func _begin(cfg: Dictionary, authority: bool, m: String) -> void:
	_teardown()
	mode = m
	var map_i := int(cfg.get("map", 0))
	mapdata = MapData.new()
	var team_size := int(cfg.get("team_size", 2))
	var bunkers_on := int(cfg.get("mode", 0)) == Defs.MODE_HEIST   # bunkers only exist in HEIST
	mapdata.generate(map_i, int(cfg.seed), team_size, bunkers_on)
	mapdata.weather = int(cfg.get("weather", 0))
	mapdata.tod = int(cfg.get("tod", 1))
	res.map_tex = ImageTexture.create_from_image(_map_image())
	res.mini_tex = ImageTexture.create_from_image(_mini_image())
	if authority:
		# the simulation gets its own copy: the client map shows doors opened only for our team
		var world_map = MapData.new()
		world_map.generate(map_i, int(cfg.seed), team_size, bunkers_on)
		world_map.weather = mapdata.weather
		world_map.tod = mapdata.tod
		world = World.new(world_map, cfg.roster, int(cfg.seed), int(cfg.get("difficulty", 1)), float(cfg.get("time", 600.0)), int(cfg.get("score", 2500)), int(cfg.get("mode", 0)))
	var my_peer := multiplayer.get_unique_id() if (m == "host" or m == "client") else 1
	var devices: Array = ["kbm"]
	if m == "coop":
		devices.append("pad" if Input.get_connected_joypads().size() > 0 else "kb2")
	var k := 0
	for r in cfg.roster:
		if not r.get("bot", false) and int(r.peer) == my_peer and k < devices.size():
			var lp := LocalP.new()
			lp.pid = int(r.pid)
			lp.device = devices[k]
			lp.view_index = k
			lp.loadout = r.get("loadout", loadout).duplicate()
			k += 1
			locals.append(lp)
	for lp in locals:
		var v := GameView.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		views_box.add_child(v)
		v.setup(res, lp, mapdata, Settings.pixel)
		lp.view = v
	if world != null:
		_apply_snapshot(world.snapshot())
	_show(St.GAME)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Sfx.set_ambience(true)


func _teardown() -> void:
	world = null
	snap = {}
	locals.clear()
	effects.clear()
	paused = false
	last_dyn = PackedInt32Array()
	last_doors = ""
	shot_frames = 0
	Sfx.set_engine(0)
	for c in views_box.get_children():
		c.queue_free()


func _quit_to_menu() -> void:
	if Net.online:
		Net.leave()
	_teardown()
	_show(St.MENU)


func _toggle_pause() -> void:
	if state != St.GAME:
		return
	if options_root.visible:
		_close_options()
		return
	paused = not paused
	pause_root.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- map textures

func _map_image() -> Image:
	return mapdata.pack_image()


func _mini_image() -> Image:
	var th: Array = MapData.THEMES[mapdata.palette]
	var wc := [Color(0, 0, 0), Color(0.45, 0.4, 0.35) * th[8], Color(0.55, 0.3, 0.2), Color(0.62, 0.62, 0.6),
		Color(0.35, 0.42, 0.55), Color(0.95, 0.2, 0.2), Color(0.95, 0.8, 0.2), Color(0.72, 0.72, 0.66), Color(0.95, 0.6, 0.1),
		Color(0.62, 0.55, 0.38), Color(0.6, 0.44, 0.24), Color(0.2, 0.4, 0.5), Color(0.6, 0.6, 0.58), Color(0.55, 0.38, 0.22),
		Color(0.45, 0.46, 0.5), Color(0.18, 0.36, 0.14), Color(0.74, 0.66, 0.52)]
	var fc := [th[0].darkened(0.2), th[2], Color(0.3, 0.3, 0.3), Color(0.18, 0.2, 0.25), Color(0.15, 0.3, 0.45), Color(0.38, 0.35, 0.32)]
	var img := Image.create(mapdata.W, mapdata.H, false, Image.FORMAT_RGBA8)
	for y in mapdata.H:
		for x in mapdata.W:
			var i: int = y * mapdata.W + x
			var w: int = mapdata.wall[i]
			var c: Color = fc[mapdata.flo[i]]
			if w > 0:
				# taller blocks draw brighter, low cover darker
				c = (wc[w] as Color) * clampf(0.6 + mapdata.hgt[i] * 0.22, 0.6, 1.3)
			elif mapdata.roof[i] != 0:
				c = c.darkened(0.2)
			elif mapdata.obst[i] != 0:
				c = c.darkened(0.35)
			img.set_pixel(x, y, c)
	return img


# ---------------------------------------------------------------- frame loop

func _rec(pid: int) -> Dictionary:
	for r in snap.get("p", []):
		if int(r.id) == pid:
			return r
	return {}


func _input(event: InputEvent) -> void:
	if state != St.GAME:
		return
	var mm := event as InputEventMouseMotion
	var mb := event as InputEventMouseButton
	var kb := event as InputEventKey
	if mm != null:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused:
			for lp in locals:
				if lp.device == "kbm" and lp.view != null and lp.view.mview != null and lp.view.mview.on:
					lp.view.mview.mouse_move(mm.relative)   # manning the mortar: the mouse moves the reticle
				elif lp.device == "kbm":
					var z := 1.0
					if lp.view != null and lp.ads:
						z = lerpf(1.0, float(Defs.WPN[lp.view.last_weapon if lp.view.last_weapon >= 0 else 0].zoom), lp.view.ads_t)
					var dx := mm.relative.x * MOUSE_SENS * Settings.sens / z
					var pilot: bool = lp.role == Defs.ROLE_DRIVER and lp.view != null and int(lp.view.my_vtype) >= Defs.PLANE_FIRST
					if pilot:
						lp.psteer = clampf(lp.psteer + dx * 2.2, -1.0, 1.0)   # plane: the mouse is the stick
					elif lp.role == Defs.ROLE_DRIVER:
						lp.drv_look = clampf(lp.drv_look + dx, -2.4, 2.4)   # driver looks around, the hull keeps its course
					else:
						lp.yaw += dx
					var dy := mm.relative.y * MOUSE_SENS * Settings.sens / z
					lp.pitch = clampf(lp.pitch + (dy if Settings.invert_y else -dy), -0.95, 0.95)
	elif mb != null and mb.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if not paused:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			for lp in locals:
				if lp.device == "kbm":
					lp.wheel = -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
	elif kb != null and kb.pressed and not kb.echo:
		if kb.keycode == KEY_ESCAPE:
			_toggle_pause()
		elif (kb.keycode == KEY_ENTER or kb.keycode == KEY_KP_ENTER) and bool(snap.get("over", false)):
			_quit_to_menu()


func _physics_process(delta: float) -> void:
	if state != St.GAME:
		return
	for lp in locals:
		var rec := _rec(lp.pid)
		if not rec.is_empty() and int(rec.ep) != lp.epoch:
			lp.epoch = int(rec.ep)
			lp.yaw = float(rec.yaw)
		var inp := _read_input(lp, rec, delta)
		if world != null:
			world.set_input(lp.pid, inp)
		elif Net.online:
			Net.client_input.rpc_id(1, lp.pid, inp)
	if world != null:
		if not (paused and mode != "host"):
			world.step(delta)
		var s: Dictionary = world.snapshot()
		if mode == "host":
			# WAR (32 players): clients get 30 snapshots/s; events of skipped frames ride along with the next one
			if world.mode == Defs.MODE_WAR and Engine.get_physics_frames() % 2 == 1:
				ev_hold.append_array(s.ev)
			else:
				var out: Dictionary = s
				if not ev_hold.is_empty():
					out = s.duplicate(false)
					var ev2 := ev_hold.duplicate()
					ev2.append_array(s.ev)
					out["ev"] = ev2
					ev_hold.clear()
				Net.snapshot.rpc(out)
		_apply_snapshot(s)


func _k(key: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(key) else 0.0


func _kp(key: Key) -> bool:
	return Input.is_physical_key_pressed(key)


func _edge(lp, key: String, down: bool) -> bool:
	var was: bool = lp.prev.get(key, false)
	lp.prev[key] = down
	return down and not was


func _dz(v: float) -> float:
	return 0.0 if absf(v) < 0.2 else v


func _read_input(lp, rec: Dictionary, dt: float) -> Array:
	var role: int = rec.get("role", Defs.ROLE_FOOT)
	var drive_role := role == Defs.ROLE_SOLO or role == Defs.ROLE_DRIVER
	var in_puzzle: bool = rec.get("pz") != null
	var w_slot := 1
	if not rec.is_empty():
		var wid: int = rec.w
		w_slot = 3 if wid == Defs.W_KNIFE else (2 if wid == int(rec.sec) else 1)
	var mx := 0.0
	var my := 0.0
	var fire := false
	var alt := false
	var use := false
	var seat := false
	var rel := false
	var sprint := false
	var crouch := false
	var jump := false
	var gear := false
	var w := 0
	var k1 := false
	var k2 := false
	var k3 := false
	var active := not paused and state == St.GAME and not options_root.visible
	lp.show_scores = false
	if active:
		if lp.device == "kbm":
			lp.show_scores = _kp(KEY_TAB)
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				mx = _k(KEY_D) - _k(KEY_A)
				my = _k(KEY_W) - _k(KEY_S)
				if in_puzzle:
					mx += _k(KEY_RIGHT) - _k(KEY_LEFT)
					my += _k(KEY_UP) - _k(KEY_DOWN)
				fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
				alt = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
				use = _kp(KEY_E)
				seat = _kp(KEY_F)
				rel = _kp(KEY_R)
				sprint = _kp(KEY_SHIFT)
				crouch = _kp(KEY_C) or _kp(KEY_CTRL)
				jump = _kp(KEY_SPACE)
				gear = _kp(KEY_G)
				k1 = _kp(KEY_1)
				k2 = _kp(KEY_2)
				k3 = _kp(KEY_3)
				if lp.wheel != 0:
					w = wrapi(w_slot - 1 + lp.wheel, 0, 3) + 1
			lp.wheel = 0
		elif lp.device == "kb2":
			var lr := _k(KEY_RIGHT) - _k(KEY_LEFT)
			var cp := _k(KEY_PERIOD) - _k(KEY_COMMA)
			my = _k(KEY_UP) - _k(KEY_DOWN)
			if drive_role or in_puzzle:
				mx = lr
				lp.yaw += cp * 2.4 * dt
			else:
				mx = cp
				lp.yaw += lr * 2.6 * dt
			fire = _kp(KEY_KP_0)
			alt = _kp(KEY_KP_PERIOD)
			use = _kp(KEY_KP_ENTER)
			seat = _kp(KEY_KP_ADD)
			rel = _kp(KEY_KP_SUBTRACT)
			sprint = _kp(KEY_KP_9)
			crouch = _kp(KEY_KP_DIVIDE)
			jump = _kp(KEY_KP_7)
			gear = _kp(KEY_KP_8)
			k1 = _kp(KEY_KP_1)
			k2 = _kp(KEY_KP_2)
			k3 = _kp(KEY_KP_3)
			lp.show_scores = _kp(KEY_KP_MULTIPLY)
		else:
			mx = _dz(Input.get_joy_axis(0, JOY_AXIS_LEFT_X))
			my = -_dz(Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
			if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT): mx = -1.0
			if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT): mx = 1.0
			if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN): my = -1.0
			var rx := _dz(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)) * 3.2 * Settings.sens * dt / (1.0 + (2.0 if lp.ads else 0.0))
			if lp.role == Defs.ROLE_DRIVER:
				lp.drv_look = clampf(lp.drv_look + rx, -2.4, 2.4)
			else:
				lp.yaw += rx
			var ry := _dz(Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)) * 2.0 * Settings.sens * dt / (1.0 + (2.0 if lp.ads else 0.0))
			lp.pitch = clampf(lp.pitch + (ry if Settings.invert_y else -ry), -0.95, 0.95)
			fire = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.4
			alt = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.4
			use = Input.is_joy_button_pressed(0, JOY_BUTTON_X)
			seat = Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
			rel = Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP) and not in_puzzle
			if in_puzzle and Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
				my = 1.0
			sprint = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)
			crouch = Input.is_joy_button_pressed(0, JOY_BUTTON_B)
			jump = Input.is_joy_button_pressed(0, JOY_BUTTON_A)
			gear = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
			lp.show_scores = Input.is_joy_button_pressed(0, JOY_BUTTON_BACK)
			if _edge(lp, "rb", Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)):
				w = wrapi(w_slot, 0, 3) + 1
	if shot_mode == "ads":
		alt = true
	lp.ads = alt and role == Defs.ROLE_FOOT
	if _edge(lp, "k1", k1): w = 1
	if _edge(lp, "k2", k2): w = 2
	if _edge(lp, "k3", k3): w = 3
	if _edge(lp, "use", use): lp.use_count += 1
	if _edge(lp, "seat", seat): lp.seat_count += 1
	if _edge(lp, "rel", rel): lp.reload_count += 1
	if _edge(lp, "jump", jump): lp.jump_count += 1
	if _edge(lp, "gear", gear) and role == Defs.ROLE_FOOT and not in_puzzle:
		lp.throw_count += 1
		if not rec.is_empty() and int(rec.eqn) > 0 and (int(rec.eqt) == Defs.EQ_FRAG or int(rec.eqt) == Defs.EQ_SMOKE):
			lp.throw_t = 0.5
	if w > 0:
		lp.weapon_req = w
		lp.weapon_seq += 1
	if lp.view_index == 0:
		lp.loadout = loadout.duplicate()
	if lp.device == "kb2":
		# no mouse: drift the view back to level, the server's aim assist handles height
		lp.pitch = move_toward(lp.pitch, 0.0, dt * 1.5)
	if in_puzzle:
		lp.pitch = move_toward(lp.pitch, 0.0, dt * 3.0)
	lp.role = role
	if (role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER) and lp.view != null:
		var lim: Vector2 = World.TRAVERSE[clampi(lp.view.my_vtype, 0, 4)]
		if lim.x > -PI:
			var hull: float = lp.view.my_hull
			lp.yaw = hull + clampf(angle_difference(hull, lp.yaw), lim.x, lim.y)
	var in_plane: bool = lp.view != null and int(lp.view.my_vtype) >= Defs.PLANE_FIRST and role != Defs.ROLE_FOOT and role != Defs.ROLE_DEAD
	if in_plane and role == Defs.ROLE_DRIVER:
		lp.pitch = clampf(lp.pitch, -0.7, 0.7)   # pilot: mouse up/down = climb / dive
		if lp.device == "kbm":
			# mouse steers (stick position, eases back to centre); A/D do nothing, W/S stay throttle
			mx = lp.psteer
			lp.psteer = move_toward(lp.psteer, 0.0, dt * 0.5)
			lp.drv_look = 0.0
	else:
		lp.psteer = 0.0
	if in_plane and role == Defs.ROLE_DRIVER:
		pass
	elif in_plane:
		lp.pitch = clampf(lp.pitch, -1.3, 0.3)   # bomber: look down through the bombsight
	elif role == Defs.ROLE_DRIVER:
		lp.pitch = 0.0   # the driver only looks left/right (up/down breaks the cockpit view)
	elif role == Defs.ROLE_SOLO or role == Defs.ROLE_GUNNER:
		# gun elevation limits
		lp.pitch = clampf(lp.pitch, -0.45, 0.6)
	if role != Defs.ROLE_DRIVER:
		lp.drv_look = move_toward(lp.drv_look, 0.0, dt * 4.0)
	elif lp.device == "kb2":
		lp.drv_look = move_toward(lp.drv_look, 0.0, dt * 2.0)
	var aim := Vector2.ZERO
	if lp.view != null and lp.view.mview != null:
		aim = lp.view.mview.update_aim(lp, Vector2(mx, my), sprint, dt)
	return [mx, my, lp.yaw, fire, alt, use, lp.use_count, lp.seat_count, lp.weapon_req, lp.weapon_seq, lp.reload_count, lp.epoch,
		sprint, crouch, lp.jump_count, lp.throw_count, lp.loadout[0], lp.loadout[1], lp.loadout[2], lp.pitch, lp.device != "kbm", aim.x, aim.y]


func _apply_snapshot(s: Dictionary) -> void:
	if state != St.GAME and world == null:
		return
	snap = s
	if mapdata == null:
		return
	var changed := false
	var dyn: PackedInt32Array = s.get("dyn", PackedInt32Array())
	if dyn != last_dyn:
		last_dyn = dyn
		for i in range(0, dyn.size() - 2, 3):
			mapdata.set_wall(dyn[i], dyn[i + 1], dyn[i + 2])
		changed = true
	if changed:
		res.map_tex.update(_map_image())
		res.mini_tex.update(_mini_image())
	_handle_events(s.get("ev", PackedFloat32Array()))


func _listener() -> Vector2:
	if locals.size() > 0 and locals[0].view != null:
		return locals[0].view.cam_pos
	return Vector2.ZERO


func _fx(k: int, p: Vector2, life: float, p2 := Vector2.ZERO, z := -1.0) -> void:
	if effects.size() < 450:
		effects.append({"k": k, "p": p, "p2": p2, "t": 0.0, "life": life, "z": z})


const SHOT_SOUNDS := ["knife", "pistol", "revolver", "rifle", "smg", "shotgun", "sniper", "lmg", "burst", "dmr", "mpistol", "dbarrel", "rpg"]


func _handle_events(ev: PackedFloat32Array) -> void:
	var lis := _listener()
	var i := 0
	var st := Defs.EV_STRIDE
	while i + st - 1 < ev.size():
		var t := int(ev[i])
		var p := Vector2(ev[i + 1], ev[i + 2])
		var p2 := Vector2(ev[i + 3], ev[i + 4])
		i += st
		var d := lis.distance_to(p)
		var vol := -d * 0.9
		if t == Defs.EV_SHOT:
			Sfx.play(SHOT_SOUNDS[clampi(int(p2.x), 0, SHOT_SOUNDS.size() - 1)], vol - 2.0, randf_range(0.95, 1.05))
		elif t == Defs.EV_MG:
			Sfx.play("mg", vol - 4.0, randf_range(0.92, 1.08))
		elif t == Defs.EV_ENEMY_SHOT:
			Sfx.play("enemy", vol - 3.0, randf_range(0.85, 1.1))
		elif t == Defs.EV_CANNON:
			var vt := int(p2.x)
			if vt == Defs.V_BRONEVIKS:
				Sfx.play("cannon", vol - 4.0, 1.9)
			elif vt == Defs.V_ROCKET:
				Sfx.play("hiss", vol, 1.6)
				Sfx.play("cannon", vol - 2.0, 0.8)
			else:
				Sfx.play("cannon", vol + 2.0)
			_fx(4, p, 1.2)
			_shake(p, 4.0, 0.7)
		elif t == Defs.EV_EXPLOSION:
			Sfx.play("explosion", vol * 0.7 + 2.0, randf_range(0.9, 1.1))
			_fx(0, p, 0.45, Vector2.ZERO, p2.x if p2.x > 0.0 else -1.0)
			for k in 4:
				_fx(4, p + Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)), randf_range(1.2, 2.2))
			_shake(p, 9.0, 1.0)
		elif t == Defs.EV_MORTAR:
			# a base mortar fires: deep thump and a puff of smoke over the pit
			Sfx.play("cannon", vol + 3.0, 0.55)
			Sfx.play("hiss", vol - 8.0, 0.5)
			for k in 3:
				_fx(4, p + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), randf_range(1.4, 2.4), Vector2.ZERO, 0.9)
			_shake(p, 3.5, 0.35)
		elif t == Defs.EV_MORTAR_IN:
			# incoming whistle for everyone near the impact point
			if d < 32.0:
				Sfx.play("whistle", -d * 0.5 + 2.0, randf_range(0.92, 1.05))
		elif t == Defs.EV_KNIFE:
			Sfx.play("knife", vol)
		elif t == Defs.EV_IMPACT:
			_fx(1, p, 0.25, Vector2.ZERO, p2.x if p2.x > 0.0 else -1.0)
		elif t == Defs.EV_EVENT:
			var ek := int(p2.x)
			var ph := int(p2.y)
			if ph == 0:
				Sfx.play("event", -4.0)
				if ek == Defs.EVT_SUPPLY:
					Sfx.play("plane", -6.0)
				elif ek == Defs.EVT_ARTY:
					# air raid siren, wailing a few times
					for wail in 3:
						get_tree().create_timer(wail * 0.85).timeout.connect(func(): Sfx.play("alarm", -6.0, 0.7))
				elif ek == Defs.EVT_STORM:
					Sfx.play("thunder", -8.0, 0.6)
			elif ph == 1 and ek == Defs.EVT_ARTY:
				Sfx.play("alarm", -6.0, 0.6)
			elif ph == 4:
				# a bomber wave enters the map: engine drone, louder the closer its track passes
				Sfx.play("plane", maxf(-20.0, -2.0 - d * 0.12), randf_range(0.85, 1.05))
			elif ph == 3:
				Sfx.play("door", vol - 2.0, 1.4)
				_fx(5, p, 1.0)
			elif ph == 2:
				Sfx.play("beep", -10.0, 0.8)
		elif t == Defs.EV_HIT:
			Sfx.play("hit", vol - 4.0)
			if p2.x > 0.5:
				Sfx.play("beep", vol - 2.0, 2.2)   # headshot
			_fx(2, p, 0.2, Vector2.ZERO, p2.y if p2.y > 0.0 else -1.0)
		elif t == Defs.EV_TRACER:
			_fx(3, p, maxf(0.04, p.distance_to(p2) / 80.0), p2)
		elif t == Defs.EV_BEEP:
			Sfx.play("beep", vol - 6.0)
		elif t == Defs.EV_PZ_OK:
			Sfx.play("pz_ok", vol)
		elif t == Defs.EV_PZ_BAD:
			Sfx.play("pz_bad", vol)
		elif t == Defs.EV_PICKUP:
			Sfx.play("pickup" if int(p2.x) != 1 else "cash", vol)
		elif t == Defs.EV_DEPOSIT:
			Sfx.play("cash", vol + 2.0, 0.8)
		elif t == Defs.EV_UNLOCK:
			Sfx.play("unlock", vol)
		elif t == Defs.EV_THROW:
			Sfx.play("knife", vol - 2.0, 0.7)
		elif t == Defs.EV_BOUNCE:
			Sfx.play("clink", vol - 4.0, randf_range(0.9, 1.2))
		elif t == Defs.EV_SMOKE:
			Sfx.play("hiss", vol)
		elif t == Defs.EV_HEAL:
			Sfx.play("pz_ok", vol - 4.0, 1.4)
		elif t == Defs.EV_DOOR:
			Sfx.play("door", 0.0)
		elif t == Defs.EV_GATE:
			Sfx.play("door", vol * 0.5)
		elif t == Defs.EV_WIN:
			Sfx.play("win", 0.0)


func _shake(p: Vector2, radius: float, amount: float) -> void:
	for lp in locals:
		if lp.view == null:
			continue
		var d: float = lp.view.cam_pos.distance_to(p)
		if d < radius:
			lp.shake = maxf(lp.shake, amount * (1.0 - d / radius))


## Menus are laid out for 1600x900 and scaled to fit any window (crisp, canvas-items stretch) times the
## UI scale option. While actually playing, stretching is off so the 3D view keeps its full resolution
## (the HUD sizes itself from the window and Settings.ui_scale).
func _apply_ui_scale() -> void:
	var playing: bool = state == St.GAME and not pause_root.visible and not options_root.visible
	var key := "%s|%.2f" % [playing, Settings.ui_scale]
	if key == ui_key or shot_path != "" and shot_mode != "menu":
		return
	ui_key = key
	var w := get_window()
	if playing:
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		w.content_scale_factor = 1.0
	else:
		w.content_scale_size = Vector2i(1600, 900)
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		w.content_scale_factor = clampf(Settings.ui_scale, 0.8, 1.25)


func _process(delta: float) -> void:
	_apply_ui_scale()
	if state != St.GAME:
		if shot_path != "" and shot_mode == "menu":
			_shot_step()
		return
	for fx in effects:
		fx.t += delta
	effects = effects.filter(func(fx): return fx.t < fx.life)
	dust_t -= delta
	if dust_t <= 0.0:
		dust_t = 0.09
		var e: PackedFloat32Array = snap.get("e", PackedFloat32Array())
		for j in e.size() / 9:
			var o := j * 9
			var typ := int(e[o])
			var pos := Vector2(e[o + 1], e[o + 2])
			if typ == Defs.E_TANK and (int(e[o + 5]) & 2):
				_fx(5, pos - Vector2.from_angle(e[o + 3]) * 0.8 + Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)), 0.8)
			elif typ == Defs.E_SHELL:
				_fx(4, pos, 0.5)
			elif typ == Defs.E_WRECK and randf() < 0.3:
				_fx(4, pos + Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)), 2.0)
			elif typ == Defs.E_SMOKE:
				var r: float = e[o + 7]
				for q in 2:
					_fx(6, pos + Vector2.from_angle(randf() * TAU) * randf() * r * 0.8, 2.2)
	var engine := 0
	for lp in locals:
		var rec := _rec(lp.pid)
		if not rec.is_empty():
			var sh := int(rec.shots)
			if lp.last_shots >= 0 and sh != lp.last_shots:
				lp.kick = 1.0
				# recoil climbs the view a little (heavier guns kick harder)
				if int(rec.role) == Defs.ROLE_FOOT and lp.device == "kbm":
					var rk: float = {Defs.W_PISTOL: 0.012, Defs.W_REVOLVER: 0.03, Defs.W_RIFLE: 0.009, Defs.W_SMG: 0.006,
						Defs.W_SHOTGUN: 0.04, Defs.W_SNIPER: 0.05, Defs.W_LMG: 0.008, Defs.W_BURST: 0.008, Defs.W_DMR: 0.022,
						Defs.W_MPISTOL: 0.005, Defs.W_DBARREL: 0.05, Defs.W_RPG: 0.06}.get(int(rec.w), 0.0)
					lp.pitch = minf(0.95, lp.pitch + rk * (0.5 if lp.ads else 1.0))
			lp.last_shots = sh
			var role := int(rec.role)
			if role == Defs.ROLE_SOLO or role == Defs.ROLE_DRIVER or role == Defs.ROLE_GUNNER:
				engine = maxi(engine, 2 if lp.view != null and lp.view.my_tank_moving else 1)
		lp.kick = maxf(0.0, lp.kick - delta * 2.5)
		lp.throw_t = maxf(0.0, lp.throw_t - delta)
		lp.view.render(snap, rec, effects, delta)
	Sfx.set_engine(engine)
	if shot_path != "":
		_shot_step()


## Debug screenshot mode: --shot=path.png --shotmode=MODE[:map[:primary]]
## MODE: solo | coop | foot | tank | battle | puzzle | tuner | vault | ads | sprint
func _shot_step() -> void:
	shot_frames += 1
	if shot_mode == "menu":
		if shot_frames == 90:
			var mimg := get_viewport().get_texture().get_image()
			mimg.save_png(shot_path)
			print("Saved screenshot ", shot_path)
			get_tree().quit()
		return
	if shot_frames == 3 and world != null:
		var p = world.players[1]
		var b0: Dictionary = mapdata.bunkers[0] if mapdata.bunkers.size() > 0 else {"bx": int(mapdata.W / 2) - 12, "by": 12}
		var o := Vector2(b0.bx, b0.by)
		if shot_mode in ["foot", "ads", "sprint"]:
			world._exit_tank(p)
			p.pos = o + Vector2(11.5, 30.5)
			p.yaw = -PI * 0.5
			p.epoch += 1
		elif shot_mode == "up":
			world._exit_tank(p)
			p.pos = o + Vector2(11.5, 30.5)
			p.yaw = -PI * 0.5
			p.epoch += 1
			locals[0].pitch = 0.45
		elif shot_mode == "airfield" or shot_mode == "plane" or shot_mode == "bomber":
			# WAR planes: parked line-up seen from the ground / flying as pilot or bomber with an enemy plane ahead
			world._exit_tank(p)
			var mine = null
			var foe = null
			for t in world.tanks:
				if world._is_plane(t) and t.team == p.team and mine == null:
					mine = t
				elif world._is_plane(t) and t.team != p.team and foe == null:
					foe = t
			if mine != null and shot_mode == "airfield":
				p.pos = mine.pos + Vector2.from_angle(mine.hull + PI * 0.75) * 4.0
				p.yaw = (mine.pos - p.pos).angle() - 0.2
				p.epoch += 1
				locals[0].pitch = 0.05
			elif mine != null:
				world._enter_tank(p, mine)
				if shot_mode == "bomber":
					world._switch_seat(p)
				mine.z = 7.0
				mine.speed = 8.0
				mine.ppitch = 0.0
				mine.hull = (Vector2(mapdata.W * 0.5, mapdata.H * 0.5) - mine.pos).angle()
				mine.pos += Vector2.from_angle(mine.hull) * 15.0
				p.yaw = mine.hull
				p.epoch += 1
				locals[0].pitch = -0.15 if shot_mode == "plane" else -1.0
				if foe != null:
					foe.pos = mine.pos + Vector2.from_angle(mine.hull) * 9.0 + Vector2.from_angle(mine.hull + PI * 0.5) * 1.5
					foe.z = 7.8
					foe.hull = mine.hull + 0.4
					foe.speed = 9.5
					foe.bank = 0.4
		elif shot_mode == "items":
			# an armor vest and a few dropped guns on open ground in front of the player
			world._exit_tank(p)
			for e in world.enemies:
				e.dead = true
			var a0: Dictionary = world.armor_spots[0]
			p.pos = a0.pos + Vector2(-2.6, 0.0)
			p.yaw = 0.0
			p.epoch += 1
			locals[0].pitch = -0.25
			var k := 0
			for wid in [Defs.W_SNIPER, Defs.W_SHOTGUN, Defs.W_RPG, Defs.W_LMG]:
				world._drop_weapon(wid, 5, 10, a0.pos + Vector2(-0.6 + 0.2 * k, -1.1 + 0.75 * k), 0.0)
				k += 1
			for it in world.items:
				if it.k == 4:
					it.life = 1e6   # the software renderer is slow: keep them for the screenshot
		elif shot_mode == "tower":
			# on the team's watchtower, looking down over the field
			world._exit_tank(p)
			p.pos = Vector2(2.6, 3.4)
			p.z = 1.8
			p.yaw = 0.35
			p.epoch += 1
			locals[0].pitch = -0.3
		elif shot_mode == "roof":
			# on the highest walkable roof outside the bunkers
			world._exit_tank(p)
			var best := Vector2.ZERO
			var bh := 0.0
			for y in range(4, mapdata.H - 4):
				for x in range(4, mapdata.W - 4):
					var i: int = y * mapdata.W + x
					if mapdata.roof[i] != 0 and mapdata.wall[i] == 0 and mapdata.bunker_at(Vector2(x, y)) < 0 and mapdata.rtop[i] > bh:
						bh = mapdata.rtop[i]
						best = Vector2(x + 0.5, y + 0.5)
			p.pos = best
			p.z = bh
			p.yaw = 0.3
			p.epoch += 1
			locals[0].pitch = -0.2
		elif shot_mode.begins_with("evt"):
			# --shotmode=evtN : random event N running, seen from a soldier standing nearby
			world._exit_tank(p)
			var ek := int(shot_mode.substr(3))
			world.start_event(ek)
			var spot := Vector2(world.evt.x, world.evt.y)
			if ek == Defs.EVT_SUPPLY:
				world.evt.z = 2.2
			elif ek == Defs.EVT_ARTY:
				world.evt.warn = 0.2
				# make the bomber waves arrive now, one of them right over us
				var k := 0
				for run in world.evt.runs:
					run.t0 = float(run.t0) - 6.0 + k * 0.6
					k += 1
				var me_pos: Vector2 = spot + Vector2(0, 7)
				world.evt.runs[0].ax = me_pos.x - 40.0
				world.evt.runs[0].ay = me_pos.y - 12.0
				world.evt.runs[0].bx = me_pos.x + 120.0
				world.evt.runs[0].by = me_pos.y - 12.0
				world.evt.runs[0].t0 = world.elapsed - 1.0
			if spot == Vector2.ZERO:
				spot = o + Vector2(11.5, 40.5)
			p.pos = spot + Vector2(0, 7)
			p.yaw = -PI * 0.5
			p.epoch += 1
			locals[0].pitch = 0.12
		elif shot_mode.begins_with("pz"):
			# --shotmode=pzN : stand at a terminal working puzzle type N (mid-way through stage 2)
			world._exit_tank(p)
			for e in world.enemies:
				e.dead = true
			var ty := int(shot_mode.substr(2))
			var b1: Dictionary = mapdata.bunkers[1]
			var pz: Dictionary = world._new_puzzle(ty, 1)
			if pz.has("pos"):
				pz.pos = 2
			if pz.has("idx"):
				pz.idx = 1
				pz.v = 17.0
				pz.lastdir = -1
			if ty == Defs.PZ_TIMING:
				pz.hits = 1
			world.bstate[1].pz[0] = pz
			p.pos = b1.terminals[0]
			p.puzzle = 0
			p.pz_bunker = 1
			p.epoch += 1
		elif shot_mode == "vault":
			world._exit_tank(p)
			for e in world.enemies:
				e.dead = true
			var b1: Dictionary = mapdata.bunkers[1]
			for r in world.R + 1:
				world._grant(1, r)
			p.pos = Vector2(b1.bx + 12.5, b1.by + 16.5)
			p.yaw = -PI * 0.5
			p.epoch += 1
		elif shot_mode.begins_with("veh"):
			# --shotmode=vehN : sit in the team vehicle, which is changed to type N, next to an enemy vehicle
			if p.tank == null:
				world._enter_tank(p, world._slot_tank(p))
			var vt := int(shot_mode.substr(3))
			for t in world.tanks:
				t.vtype = vt
				t.hp = float(Defs.VEHICLES[vt].hp)
			var other = null
			for t in world.tanks:
				if t.team != 0:
					other = t
			p.tank.pos = Vector2(mapdata.W * 0.5 + 0.5, mapdata.H * 0.5 - 12.0)
			p.tank.hull = PI * 0.5
			p.tank.turret = PI * 0.5
			# park the other teams' vehicles (crews removed) in a row in front, each at a different angle
			for q in world.players.values():
				if q.team != 0:
					if q.tank != null:
						world._exit_tank(q)
					q.alive = false
					q.respawn = 999.0
			var k := 0
			for t in world.tanks:
				if t.team != 0:
					t.vtype = (vt + k + 1) % 5
					t.pos = p.tank.pos + Vector2(-2.6 + k * 2.6, 5.0 + k * 0.8)
					t.hull = 0.7 + k * 1.9
					t.turret = t.hull + 1.2
					k += 1
			world._resync_tank(p.tank)
		elif shot_mode == "ctf" and not world.flags.is_empty():
			# --shotmode=ctf:MAP:PRI:SIZE:1:TEAMS : carrying an enemy flag home, looking at our own flag
			world._exit_tank(p)
			var fh: Vector2 = world.flags[0].home
			for ft in world.flags:
				if int(ft) != 0:
					world.flags[ft].st = 1
					world.flags[ft].car = p.id
					break
			var cdir: Vector2 = (Vector2(mapdata.W, mapdata.H) * 0.5 - fh).normalized()
			p.pos = fh + cdir.orthogonal() * 3.5
			p.yaw = (fh - p.pos).angle()
			p.epoch += 1
		elif shot_mode == "tank":
			if p.tank == null:
				world._enter_tank(p, world._slot_tank(p))
			p.tank.pos = o + Vector2(11.5, 28.5)
			p.tank.turret = -PI * 0.5
			p.tank.hull = -PI * 0.5
			world._resync_tank(p.tank)
		elif shot_mode == "mortar":
			# --shotmode=mortar : man the base mortar, aim at a spot with a teammate and an enemy nearby
			world._exit_tank(p)
			p.pos = world.mortar_stand(p.team)
			world._mortar_man(p)
			var mp: Vector2 = world.mortars[p.team].pos
			var tgt: Vector2 = mp + (Vector2(mapdata.W, mapdata.H) * 0.5 - mp).normalized() * 24.0
			shot_aim = tgt
		elif shot_mode == "pit":
			# --shotmode=pit : on foot in the camp, looking at the mortar pit while a teammate fires it
			world._exit_tank(p)
			var st: Vector2 = world.mortar_stand(p.team)
			var mp: Vector2 = world.mortars[p.team].pos
			p.pos = st + (st - mp).normalized() * 3.5 + Vector2(0.0, 1.2)
			p.yaw = (mp - p.pos).angle()
			p.epoch += 1
			for q in world.players.values():
				if q.team == p.team and q != p:
					if q.tank != null:
						world._exit_tank(q)
					q.pos = st
					world._mortar_man(q)
					break
	if world != null and shot_mode == "pit" and (shot_frames == 40 or shot_frames == 100):
		for q in world.players.values():
			if world._mortar_user(q):
				world.mortars[q.team].cd = 0.0
				world._mortar_fire(q, world.mortars[q.team].pos + Vector2(30.0, 20.0))
	if world != null and shot_frames > 3 and shot_frames < 110 and shot_mode == "mortar":
		# keep a teammate and two enemies posed around the target (bots would wander off)
		var placed := 0
		for q in world.players.values():
			if q.id == 1:
				continue
			if q.tank != null:
				world._exit_tank(q)
			q.alive = true
			if q.team == 0:
				q.pos = shot_aim + Vector2(-4.0, 3.5)
				q.yaw = -0.6
			elif placed < 2 and q.team == 1:
				q.pos = shot_aim + Vector2(-5.5 + placed * 1.3, 6.5 + placed * 0.9)
				q.yaw = PI * 0.8
				placed += 1
	if world != null and shot_frames > 3 and shot_mode == "mortar" and locals[0].view.mview.on:
		var mv = locals[0].view.mview
		var p = world.players[1]
		mv.aim = shot_aim + Vector2(0.6, 0.4)
		if shot_frames < 20:
			mv.cam = mv.aim
		if shot_frames == 12 or shot_frames == 70:
			world.mortars[p.team].cd = 0.0
			world._mortar_fire(p, shot_aim + (Vector2(4.0, -6.0) if shot_frames == 12 else Vector2(-3.0, 2.5)))
		if shot_frames == 104:
			world._mortar_impact(p.team, p, shot_aim + Vector2(-9.0, -5.0))
		for q in world.players.values():
			q.hp = maxf(q.hp, 60.0)
	if world != null and shot_frames > 3:
		var p = world.players[1]
		if shot_mode == "ads" and p.inp.size() > 4:
			locals[0].ads = true
			p.inp[4] = true
		if shot_mode == "sprint":
			p.sprint = true
		if shot_mode.begins_with("pz") or shot_mode.begins_with("veh"):
			p.hp = 100.0
			for t in world.tanks:
				t.hp = float(Defs.VEHICLES[t.vtype].hp)
	if shot_frames == 120:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("Saved screenshot ", shot_path)
		get_tree().quit()


# ---------------------------------------------------------------- menu styling

func _lbl90(parent: Node, text: String) -> Label:
	var l := _label(parent, text, 16, Color(0.98, 0.8, 0.4))
	l.custom_minimum_size = Vector2(90, 0)
	return l


func _on_map_picked(_i: int) -> void:
	var id := map_pick.get_selected_id()
	if id == RANDOM_MAP_ID:
		map_desc.text = "A surprise: one of the %d battlefields is chosen when the match starts." % MapData.MAPS.size()
		if menu_bg != null:
			map_preview.texture = null
		return
	map_desc.text = MapData.MAPS[id].desc
	if menu_bg != null:
		menu_bg.set_map(id)
		map_preview.texture = menu_bg.mini_tex


func _section(parent: Node, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	var l := _label(h, text, 15, Color(0.98, 0.76, 0.22))
	l.add_theme_constant_override("outline_size", 2)
	var line := ColorRect.new()
	line.color = Color(0.98, 0.76, 0.22, 0.35)
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)


func _big_button(parent: Node, text: String, sub: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = "  " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 54)
	b.add_theme_font_size_override("font_size", 26)
	b.tooltip_text = sub
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): Sfx.play("switch", -14.0, 1.4))
	b.pressed.connect(func(): Sfx.play("beep", -8.0, 0.8))
	parent.add_child(b)
	if sub != "":
		var l := _label(parent, "      " + sub, 12, Color(0.7, 0.7, 0.62))
		l.add_theme_constant_override("line_spacing", -4)


func _sb(bg: Color, border: Color, bw := 2, radius := 4, margin := 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin + 4.0
	s.content_margin_right = margin + 4.0
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


func _make_theme() -> Theme:
	var th := Theme.new()
	var amber := Color(0.98, 0.76, 0.22)
	var normal := _sb(Color(0.08, 0.085, 0.075, 0.88), Color(amber.r, amber.g, amber.b, 0.25))
	var hover := _sb(Color(0.2, 0.15, 0.05, 0.95), amber)
	hover.border_width_left = 6
	var pressed := _sb(Color(0.4, 0.28, 0.06, 0.95), amber.lightened(0.3))
	var disabled := _sb(Color(0.06, 0.06, 0.06, 0.7), Color(0.3, 0.3, 0.3, 0.4))
	for cls in ["Button", "OptionButton"]:
		th.set_stylebox("normal", cls, normal)
		th.set_stylebox("hover", cls, hover)
		th.set_stylebox("pressed", cls, pressed)
		th.set_stylebox("focus", cls, _sb(Color(0, 0, 0, 0), amber.darkened(0.2), 1))
		th.set_stylebox("disabled", cls, disabled)
		th.set_color("font_color", cls, Color(0.92, 0.9, 0.82))
		th.set_color("font_hover_color", cls, Color(1, 0.92, 0.7))
		th.set_color("font_pressed_color", cls, Color(1, 1, 1))
		th.set_font_size("font_size", cls, 17)
	th.set_stylebox("normal", "LineEdit", _sb(Color(0.03, 0.03, 0.03, 0.9), Color(amber.r, amber.g, amber.b, 0.35)))
	th.set_stylebox("focus", "LineEdit", _sb(Color(0.05, 0.04, 0.02, 0.95), amber))
	th.set_color("font_color", "LineEdit", Color(1, 0.95, 0.8))
	th.set_color("font_color", "CheckBox", Color(0.9, 0.88, 0.8))
	th.set_color("font_hover_color", "CheckBox", Color(1, 0.92, 0.7))
	var pm := _sb(Color(0.06, 0.06, 0.05, 0.97), amber, 1, 2)
	th.set_stylebox("panel", "PopupMenu", pm)
	th.set_stylebox("hover", "PopupMenu", _sb(Color(0.35, 0.25, 0.05), amber, 0, 2))
	th.set_color("font_color", "PopupMenu", Color(0.92, 0.9, 0.82))
	th.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))
	th.set_stylebox("slider", "HSlider", _sb(Color(0.1, 0.1, 0.1), Color(amber.r, amber.g, amber.b, 0.4), 1, 3, 2))
	th.set_stylebox("grabber_area", "HSlider", _sb(amber.darkened(0.3), amber, 1, 3, 2))
	th.set_stylebox("grabber_area_highlight", "HSlider", _sb(amber, amber, 1, 3, 2))
	return th
