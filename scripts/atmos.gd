extends RefCounted
## Match weather + time of day: the host resolves them into the match cfg ("weather", "tod" ints),
## every client turns them into the same raycast shader look (sky, sun / moon, fog, ambient light).
##   cfg.weather: 0 clear, 1 cloudy, 2 rain, 3 thunderstorm, 4 fog, 5 snow (snow maps), 6 dust storm (arid maps)
##   cfg.tod:     0 morning, 1 day, 2 dusk, 3 night

const W_CLEAR := 0
const W_CLOUDY := 1
const W_RAIN := 2
const W_STORM := 3
const W_FOG := 4
const W_SNOW := 5
const W_DUST := 6
const WEATHER_NAMES := ["Clear", "Cloudy", "Rain", "Thunderstorm", "Fog", "Snow", "Dust storm"]
const T_MORNING := 0
const T_DAY := 1
const T_DUSK := 2
const T_NIGHT := 3
const TOD_NAMES := ["Morning", "Day", "Dusk", "Night"]
const FR_LAMP := 255        # lamp post / floodlight sprite frame (patched into the sprite atlas, see add_lamp_sprite)
const MAX_LIGHTS := 32
const MAX_MARKS := 16


## Map-compatible weather: snow only on snow maps (theme 2), dust only on arid maps (theme 1).
static func fit_weather(w: int, theme: int) -> int:
	if theme == 2:
		if w == W_RAIN or w == W_STORM or w == W_DUST:
			return W_SNOW
	else:
		if w == W_SNOW:
			return W_RAIN if theme != 1 else W_DUST
	if w == W_DUST and theme != 1:
		return W_FOG
	return clampi(w, 0, 6)


## pick: -1 = random. Weighted per map theme.
static func resolve_weather(pick: int, theme: int, rng: RandomNumberGenerator) -> int:
	if pick >= 0:
		return fit_weather(pick, theme)
	var pool: Array = [W_CLEAR, W_CLEAR, W_CLEAR, W_CLOUDY, W_CLOUDY, W_RAIN, W_STORM, W_FOG]
	if theme == 1:
		pool = [W_CLEAR, W_CLEAR, W_CLEAR, W_CLOUDY, W_DUST, W_DUST, W_STORM]
	elif theme == 2:
		pool = [W_CLEAR, W_CLEAR, W_CLOUDY, W_SNOW, W_SNOW, W_SNOW, W_FOG]
	return int(pool[rng.randi() % pool.size()])


static func resolve_tod(pick: int, rng: RandomNumberGenerator) -> int:
	if pick >= 0:
		return clampi(pick, 0, 3)
	var pool: Array = [T_MORNING, T_DAY, T_DAY, T_DAY, T_DUSK, T_DUSK, T_NIGHT, T_NIGHT]
	return int(pool[rng.randi() % pool.size()])


## Debug override from the command line: --weather=N / --tod=N (N = cfg int), else `fallback`.
static func arg_override(key: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + key + "="):
			return int(a.substr(key.length() + 3))
	return fallback


## Headlights / lamps switched on.
static func lights_on(weather: int, tod: int) -> bool:
	return tod == T_DUSK or tod == T_NIGHT or weather == W_STORM or weather == W_FOG or weather == W_DUST


static func _grey(c: Color, k: float) -> Color:
	var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	return c.lerp(Color(l, l, l), k)


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Look for a weather x time of day on a THEMES palette `th` and weather class `theme`.
static func look(weather: int, tod: int, th: Array, theme: int) -> Dictionary:
	var top: Color = th[4]
	var hor: Color = th[5]
	var fog: Color = th[6]
	var mnt: Color = th[7]
	var amb := Color(1.0, 1.0, 1.0)
	var sun := Color(1.0, 0.9, 0.7)
	var sun_s := 0.3
	var sun_h := 0.22
	var sun_a := 0.9
	var sun_p := 9.0
	var disc := 0.5
	var fogk := 1.0
	var stars := 0.0
	var clouds := 0.15
	var cloud := Color(1.0, 1.0, 1.0)
	var night := tod == T_NIGHT
	if tod == T_MORNING:
		top = top.lerp(Color(0.42, 0.56, 0.80), 0.5)
		hor = hor.lerp(Color(1.0, 0.76, 0.55), 0.6)
		fog = fog.lerp(Color(0.88, 0.80, 0.72), 0.65)
		mnt = mnt.lerp(Color(0.46, 0.42, 0.52), 0.45)
		amb = Color(0.97, 0.88, 0.78)
		sun = Color(1.0, 0.78, 0.5)
		sun_s = 0.75
		sun_h = 0.06
		sun_a = 0.3
		sun_p = 5.0
		disc = 1.0
		fogk = 0.7
		cloud = Color(1.0, 0.86, 0.78)
	elif tod == T_DUSK:
		top = Color(0.20, 0.16, 0.36)
		hor = Color(0.98, 0.48, 0.24)
		fog = Color(0.50, 0.34, 0.36)
		mnt = Color(0.20, 0.14, 0.22)
		amb = Color(0.78, 0.56, 0.50)
		sun = Color(1.0, 0.42, 0.16)
		sun_s = 1.0
		sun_h = 0.035
		sun_a = 3.6
		sun_p = 4.0
		disc = 1.0
		fogk = 0.85
		cloud = Color(0.95, 0.52, 0.42)
	elif night:
		top = Color(0.010, 0.016, 0.045)
		hor = Color(0.045, 0.065, 0.12)
		fog = Color(0.035, 0.048, 0.085)
		mnt = Color(0.018, 0.022, 0.04)
		amb = Color(0.19, 0.23, 0.36)
		sun = Color(0.72, 0.8, 1.0)
		sun_s = 0.18
		sun_h = 0.3
		sun_a = 2.4
		sun_p = 60.0
		disc = 1.0
		stars = 1.0
		fogk = 0.66
		cloud = Color(0.10, 0.12, 0.18)
	# weather on top (multiplicative, softened at night so it stays playable)
	var soft := 0.45 if night else 0.0
	var am := 1.0
	var tint := Color(1, 1, 1)
	if weather == W_CLOUDY:
		top = _grey(top, 0.75) * 0.88
		hor = _grey(hor, 0.6) * 0.92
		fog = _grey(fog, 0.4)
		am = 0.8
		sun_s *= 0.15
		disc = 0.0
		clouds = 0.85
		cloud = _grey(cloud, 0.7) * 0.8
		fogk *= 0.88
		stars *= 0.1
	elif weather == W_RAIN or weather == W_STORM:
		var st := weather == W_STORM
		top = _grey(top, 0.9) * (0.38 if st else 0.6)
		hor = _grey(hor, 0.85) * (0.45 if st else 0.68)
		fog = _grey(fog, 0.75) * (0.52 if st else 0.72)
		mnt = mnt * 0.6
		am = 0.45 if st else 0.62
		sun_s = 0.0
		disc = 0.0
		clouds = 1.0
		cloud = _grey(cloud, 0.9) * (0.45 if st else 0.6)
		fogk *= 0.48 if st else 0.62
		stars = 0.0
	elif weather == W_FOG:
		fog = _grey(fog.lerp(hor, 0.4), 0.55)
		hor = hor.lerp(fog, 0.75)
		mnt = mnt.lerp(fog, 0.6)
		am = 0.86
		sun_s *= 0.35
		disc *= 0.3
		clouds = 0.5
		fogk *= 0.36
		stars *= 0.2
	elif weather == W_SNOW:
		top = _grey(top, 0.7) * 0.9
		hor = _grey(hor, 0.6)
		fog = _grey(fog, 0.5)
		am = 0.84
		sun_s *= 0.2
		disc = 0.0
		clouds = 0.9
		cloud = _grey(cloud, 0.6)
		fogk *= 0.52
		stars = 0.0
	elif weather == W_DUST:
		var fl := fog.r * 0.3 + fog.g * 0.59 + fog.b * 0.11
		fog = Color(1.0, 0.76, 0.48) * (fl * 1.05)
		hor = hor.lerp(fog, 0.8)
		top = top.lerp(fog * 0.8, 0.55)
		mnt = mnt.lerp(fog, 0.55)
		am = 0.8
		tint = Color(1.0, 0.86, 0.68)
		sun_s *= 0.5
		disc *= 0.4
		clouds = 0.3
		cloud = fog
		fogk *= 0.38
		stars = 0.0
	am = lerpf(am, 1.0, soft)
	amb = Color(amb.r * am * tint.r, amb.g * am * tint.g, amb.b * am * tint.b)
	# falling particles: 0 pollen (fireflies at night), 1 dust, 2 snow, 3 embers, 4 rain, -1 none
	var pw := theme
	var pamt := 1.0
	if theme == 2:
		pw = -1
	if weather == W_CLOUDY and theme == 2:
		pw = 2
		pamt = 0.4
	elif weather == W_RAIN:
		pw = 4
		pamt = 2.2
	elif weather == W_STORM:
		pw = 4 if theme != 2 else 2
		pamt = 4.2
	elif weather == W_FOG:
		pw = 0 if night and theme == 0 else -1
		pamt = 0.6
	elif weather == W_SNOW:
		pw = 2
		pamt = 2.4
	elif weather == W_DUST:
		pw = 1
		pamt = 4.5
	return {
		"sky_top": _v3(top), "sky_hor": _v3(hor), "fog_col": fog, "mount_col": _v3(mnt), "ambient": _v3(amb),
		"sun_col": _v3(sun * sun_s), "sun_dir": Vector2(sun_a, sun_h), "sun_size": sun_p, "sun_disc": disc,
		"stars": stars, "clouds": clouds, "cloud_col": _v3(cloud),
		"fog_k": fogk, "particles": pw, "particle_amt": pamt,
		"lightning": weather == W_STORM, "heads": lights_on(weather, tod), "night": night, "tod": tod, "weather": weather,
	}


## Static part of the look (everything except fog colour / distance / particles / lightning).
static func apply(mat: ShaderMaterial, lk: Dictionary) -> void:
	for k in ["sky_top", "sky_hor", "mount_col", "ambient", "sun_col", "sun_dir", "sun_size", "sun_disc", "stars", "clouds", "cloud_col"]:
		mat.set_shader_parameter(k, lk[k])


## Draws the lamp post frame into a copy of the sprite atlas (only if that cell is still empty).
static func add_lamp_sprite(tex: Texture2D) -> Texture2D:
	var img: Image = tex.get_image()
	if img == null:
		return tex
	var T := img.get_width() / 16
	var ox := (FR_LAMP % 16) * T
	var oy := (FR_LAMP / 16) * T
	for y in T:
		for x in T:
			if img.get_pixel(ox + x, oy + y).a > 0.05:
				push_warning("atmos: sprite frame %d already used, lamp sprite not added" % FR_LAMP)
				return tex
	var s := float(T) / 64.0
	var pole := Color(0.16, 0.17, 0.18)
	var hi := Color(0.30, 0.31, 0.32)
	var lamp := Color(1.0, 0.96, 0.72)
	var rects: Array = [
		[Rect2(30, 6, 4, 58), pole], [Rect2(31, 6, 1, 58), hi],      # pole
		[Rect2(27, 58, 10, 6), pole],                                 # foot
		[Rect2(30, 6, 16, 3), pole],                                  # arm
		[Rect2(40, 8, 10, 4), pole],                                  # hood
		[Rect2(41, 12, 8, 3), lamp],                                  # bulb (bright: glows at night)
	]
	for r in rects:
		var rc: Rect2 = r[0]
		var c: Color = r[1]
		img.fill_rect(Rect2i(ox + int(rc.position.x * s), oy + int(rc.position.y * s), maxi(1, int(rc.size.x * s)), maxi(1, int(rc.size.y * s))), c)
	return ImageTexture.create_from_image(img)
