extends Node2D
# SAUTE-NUAGES
# Plume rebondit tout seul sur les nuages : on le dirige à gauche ou à droite
# pour grimper le plus haut possible. Tout est dessiné par le code.

const W := 540.0                # largeur du jeu (la hauteur s'adapte à l'écran)
const GRAVITY := 1900.0
const JUMP_V := -960.0
const SPRING_V := -1650.0
const MOVE_SPEED := 430.0
const ACCEL := 2800.0
const R := 22.0                 # rayon de Plume
const CLOUD_TOP := 16.0         # dessus du nuage par rapport à son centre
const SAVE_PATH := "user://saute_nuages.json"

enum { TITLE, PLAY, OVER }
enum { NORMAL, MOVING, FRAGILE, GROUND }

var state := TITLE
var H := 960.0
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var cam_y := 0.0
var start_y := 0.0
var top_y := 0.0
var bonus := 0
var score := 0
var best := 0
var new_best := false
var clouds: Array = []
var stars: Array = []
var puffs: Array = []
var bg_stars: Array = []
var bg_clouds: Array = []
var next_y := 0.0
var squash := 0.0
var facing := 1.0
var t := 0.0
var over_t := 0.0
var play_t := 0.0
var touches := {}
var autoplay := false
var rng := RandomNumberGenerator.new()
var sfx := {}
var font: Font


func _ready() -> void:
	rng.randomize()
	font = ThemeDB.fallback_font
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	var deco := RandomNumberGenerator.new()
	deco.seed = 7
	for i in 70:
		bg_stars.append(Vector3(deco.randf() * W, deco.randf() * 2000.0, deco.randf_range(1.0, 2.6)))
	for i in 9:
		bg_clouds.append(Vector3(deco.randf() * W, deco.randf() * 1800.0, deco.randf_range(0.6, 1.3)))
	_make_sounds()
	_load_best()
	reset_game()


# ---------------------------------------------------------------- partie

func reset_game() -> void:
	H = get_viewport_rect().size.y
	clouds.clear()
	stars.clear()
	puffs.clear()
	cam_y = 0.0
	start_y = H - 110.0
	clouds.append(_cloud(W * 0.5, start_y, W * 2.0, GROUND))
	next_y = start_y
	_spawn_until(cam_y - 300.0)
	pos = Vector2(W * 0.5, start_y - CLOUD_TOP - R)
	vel = Vector2(0.0, JUMP_V * 0.6)
	top_y = pos.y
	bonus = 0
	score = 0
	new_best = false
	play_t = 0.0


func start_play() -> void:
	state = PLAY
	play_t = 0.0
	_sound("star")


func game_over() -> void:
	state = OVER
	over_t = 0.0
	_sound("fall")
	if score > best:
		best = score
		new_best = true
		_save_best()
	if autoplay:
		print("PARTIE score=%d hauteur=%d" % [score, int((start_y - top_y) / 10.0)])


func _difficulty(y: float) -> float:
	return clampf((start_y - y) / 25000.0, 0.0, 1.0)


func _cloud(x: float, y: float, w: float, type: int) -> Dictionary:
	return {"x": x, "y": y, "w": w, "type": type, "vx": 0.0, "spring": false,
		"spring_off": 0.0, "spring_t": 0.0, "broken": false, "fall_v": 0.0, "alpha": 1.0}


func _spawn_until(limit_y: float) -> void:
	while next_y > limit_y:
		var d := _difficulty(next_y)
		var gap := rng.randf_range(lerpf(55.0, 115.0, d), lerpf(105.0, 195.0, d))
		next_y -= gap
		var w := rng.randf_range(lerpf(105.0, 75.0, d), lerpf(130.0, 95.0, d))
		var x := rng.randf_range(w * 0.5 + 8.0, W - w * 0.5 - 8.0)
		var type := NORMAL
		if d > 0.02 and rng.randf() < lerpf(0.08, 0.45, d):
			type = MOVING
		var c := _cloud(x, next_y, w, type)
		if type == MOVING:
			c.vx = rng.randf_range(55.0, lerpf(90.0, 180.0, d)) * (1.0 if rng.randf() < 0.5 else -1.0)
		elif rng.randf() < 0.07:
			c.spring = true
			c.spring_off = rng.randf_range(-w * 0.25, w * 0.25)
		clouds.append(c)
		if not c.spring and rng.randf() < 0.22:
			stars.append({"x": x, "y": next_y - 62.0, "taken": false, "ph": rng.randf() * TAU})
		# Nuages fragiles en plus : ils ne cassent qu'après un rebond
		if gap > 80.0 and rng.randf() < lerpf(0.1, 0.4, d):
			var fw := rng.randf_range(80.0, 100.0)
			var fx := rng.randf_range(fw * 0.5 + 8.0, W - fw * 0.5 - 8.0)
			if absf(fx - x) > (fw + w) * 0.5 + 10.0:
				clouds.append(_cloud(fx, next_y + gap * 0.5, fw, FRAGILE))


# ---------------------------------------------------------------- boucle

func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	t += delta
	H = get_viewport_rect().size.y
	squash = move_toward(squash, 0.0, delta * 5.0)

	if state == PLAY:
		play_t += delta
	elif state == OVER:
		over_t += delta
		if autoplay and over_t > 1.0:
			reset_game()
			start_play()
	elif state == TITLE and autoplay and t > 0.5:
		start_play()

	_update_clouds(delta)
	_update_player(delta)

	if state == PLAY:
		var target := pos.y - H * 0.45
		if target < cam_y:
			cam_y = target
		top_y = minf(top_y, pos.y)
		score = int((start_y - top_y) / 10.0) + bonus
		_spawn_until(cam_y - 250.0)
		if pos.y - cam_y > H + R * 2.0:
			game_over()
	elif state == TITLE:
		start_y = H - 110.0
		clouds[0].y = start_y

	_cleanup()
	for p in puffs:
		p.life -= delta
		p.p += p.v * delta
		p.v *= 0.92
	puffs = puffs.filter(func(p): return p.life > 0.0)
	queue_redraw()


func _update_clouds(delta: float) -> void:
	for c in clouds:
		if c.type == MOVING:
			c.x += c.vx * delta
			if c.x < c.w * 0.5 + 4.0:
				c.x = c.w * 0.5 + 4.0
				c.vx = absf(c.vx)
			elif c.x > W - c.w * 0.5 - 4.0:
				c.x = W - c.w * 0.5 - 4.0
				c.vx = -absf(c.vx)
		if c.broken:
			c.fall_v += GRAVITY * 0.6 * delta
			c.y += c.fall_v * delta
			c.alpha = maxf(0.0, c.alpha - delta * 2.0)
		c.spring_t = maxf(0.0, c.spring_t - delta)


func _update_player(delta: float) -> void:
	var dir := 0.0
	if state == PLAY:
		dir = _bot_dir() if autoplay else _input_dir()
	vel.x = move_toward(vel.x, dir * MOVE_SPEED, ACCEL * delta)
	if dir != 0.0:
		facing = signf(dir)
	var prev_y := pos.y
	vel.y += GRAVITY * delta
	pos += vel * delta
	if pos.x < -R:
		pos.x += W + R * 2.0
	elif pos.x > W + R:
		pos.x -= W + R * 2.0

	if state == OVER:
		return
	if vel.y > 0.0:
		for c in clouds:
			if c.broken:
				continue
			var top: float = c.y - CLOUD_TOP
			if prev_y + R <= top + 4.0 and pos.y + R >= top and absf(pos.x - c.x) < c.w * 0.5 + R * 0.4:
				pos.y = top - R
				_bounce(c)
				break

	if state == PLAY:
		for s in stars:
			if not s.taken and pos.distance_to(Vector2(s.x, s.y)) < R + 18.0:
				s.taken = true
				bonus += 25
				_sound("star")
				_burst(Vector2(s.x, s.y), Color(1.0, 0.85, 0.25), 10)


func _bounce(c: Dictionary) -> void:
	squash = 1.0
	if c.spring and absf(pos.x - (c.x + c.spring_off)) < 26.0:
		vel.y = SPRING_V
		c.spring_t = 0.25
		_sound("spring")
	else:
		vel.y = JUMP_V
		_sound("jump")
	_burst(Vector2(pos.x, pos.y + R), Color(1, 1, 1, 0.9), 5)
	if c.type == FRAGILE:
		c.broken = true
		_sound("break")


func _cleanup() -> void:
	var limit := cam_y + H + 150.0
	clouds = clouds.filter(func(c): return c.type == GROUND and state == TITLE or c.y < limit)
	stars = stars.filter(func(s): return s.y < limit and not (s.taken and s.y > cam_y + H))


func _burst(at: Vector2, col: Color, n: int) -> void:
	for i in n:
		var a := rng.randf() * TAU
		puffs.append({"p": at, "v": Vector2(cos(a), sin(a) * 0.5) * rng.randf_range(60.0, 180.0),
			"life": 0.45, "col": col, "r": rng.randf_range(3.0, 7.0)})


# ---------------------------------------------------------------- commandes

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = e.position.x
			_tap()
		else:
			touches.erase(e.index)
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position.x
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			touches[-1] = e.position.x
			_tap()
		else:
			touches.erase(-1)
	elif e is InputEventMouseMotion and touches.has(-1):
		touches[-1] = e.position.x
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_SPACE or e.keycode == KEY_ENTER:
			_tap()
		elif state == TITLE and e.keycode in [KEY_LEFT, KEY_RIGHT]:
			_tap()


func _tap() -> void:
	if state == TITLE:
		start_play()
	elif state == OVER and over_t > 0.7:
		reset_game()
		start_play()


func _input_dir() -> float:
	var d := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q):
		d -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		d += 1.0
	for i in touches:
		d += -1.0 if float(touches[i]) < W * 0.5 else 1.0
	return clampf(d, -1.0, 1.0)


func _wrap_dx(dx: float) -> float:
	var span := W + R * 2.0
	if dx > span * 0.5:
		dx -= span
	elif dx < -span * 0.5:
		dx += span
	return dx


# Joueur automatique, seulement pour tester le jeu (--autoplay)
func _bot_dir() -> float:
	var apex := pos.y - (vel.y * vel.y / (2.0 * GRAVITY) if vel.y < 0.0 else 0.0)
	var best_c = null
	var best_score := INF
	for c in clouds:
		if c.broken:
			continue
		var top: float = c.y - CLOUD_TOP
		if top < apex + R + 6.0 or top > pos.y + R + 500.0:
			continue
		var dx := absf(_wrap_dx(c.x - pos.x))
		var s := top + dx * 0.4 + (60.0 if c.type == FRAGILE else 0.0)
		if s < best_score:
			best_score = s
			best_c = c
	if best_c == null:
		return 0.0
	var tx: float = best_c.x + (best_c.spring_off if best_c.spring else 0.0)
	var dx2 := _wrap_dx(tx - pos.x)
	if absf(dx2) < 10.0:
		return 0.0
	return signf(dx2)


# ---------------------------------------------------------------- dessin

func _sp(x: float, y: float) -> Vector2:
	return Vector2(x, y - cam_y)


func _draw() -> void:
	_draw_sky()
	for s in stars:
		if not s.taken:
			_draw_star(_sp(s.x, s.y + sin(t * 3.0 + s.ph) * 5.0), 15.0, t * 1.5 + s.ph)
	for c in clouds:
		_draw_cloud(c)
	for p in puffs:
		var col: Color = p.col
		col.a *= clampf(p.life / 0.45, 0.0, 1.0)
		draw_circle(p.p - Vector2(0, cam_y), p.r, col)
	_draw_player()
	_draw_hud()


func _sky_colors(f: float) -> Array:
	var day := [Color("6ec6ff"), Color("d4f0ff")]
	var dusk := [Color("ff8a65"), Color("ffd08a")]
	var night := [Color("0b1033"), Color("2c3270")]
	if f < 0.5:
		var k := f / 0.5
		return [day[0].lerp(dusk[0], k), day[1].lerp(dusk[1], k)]
	var k2 := (f - 0.5) / 0.5
	return [dusk[0].lerp(night[0], k2), dusk[1].lerp(night[1], k2)]


func _draw_sky() -> void:
	var f := clampf((start_y - cam_y - H) / 18000.0, 0.0, 1.0)
	var cols := _sky_colors(f)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([cols[0], cols[0], cols[1], cols[1]]))
	var star_a := clampf((f - 0.55) / 0.3, 0.0, 1.0)
	if star_a > 0.0:
		for s in bg_stars:
			var y := fposmod(s.y - cam_y * 0.05, 2000.0)
			if y < H:
				var tw := 0.6 + 0.4 * sin(t * 2.0 + s.x)
				draw_circle(Vector2(s.x, y), s.z, Color(1, 1, 0.9, star_a * tw))
	var cloud_a := 0.35 * (1.0 - f * 0.75)
	for b in bg_clouds:
		var y2 := fposmod(b.y - cam_y * 0.3, 1800.0) - 200.0
		if y2 > -100.0 and y2 < H + 100.0:
			var col := Color(1, 1, 1, cloud_a)
			var k: float = b.z
			draw_circle(Vector2(b.x, y2), 40.0 * k, col)
			draw_circle(Vector2(b.x + 45.0 * k, y2 + 8.0 * k), 30.0 * k, col)
			draw_circle(Vector2(b.x - 42.0 * k, y2 + 10.0 * k), 26.0 * k, col)


func _draw_cloud(c: Dictionary) -> void:
	var p := _sp(c.x, c.y)
	if p.y < -60.0 or p.y > H + 80.0:
		return
	var a: float = c.alpha
	if c.type == GROUND:
		var gx := -20.0
		while gx < W + 40.0:
			draw_circle(Vector2(gx, p.y + 22.0), 38.0, Color(0.86, 0.92, 0.98))
			draw_circle(Vector2(gx + 20.0, p.y + 18.0), 34.0, Color.WHITE)
			gx += 40.0
		draw_rect(Rect2(0, p.y + 30.0, W, maxf(0.0, H - p.y)), Color.WHITE)
		return
	var w: float = c.w
	var main := Color.WHITE
	var shade := Color(0.85, 0.91, 0.98)
	if c.type == MOVING:
		main = Color(0.82, 0.93, 1.0)
		shade = Color(0.62, 0.8, 0.96)
	elif c.type == FRAGILE:
		main = Color(0.78, 0.79, 0.84)
		shade = Color(0.6, 0.62, 0.68)
	main.a = a
	shade.a = a
	# ombre dessous puis corps du nuage
	_blob(p + Vector2(0, 4), w, shade)
	_blob(p, w, main)
	if c.type == FRAGILE:
		var crack := PackedVector2Array([p + Vector2(-w * 0.2, -10), p + Vector2(-w * 0.08, 0),
			p + Vector2(-w * 0.14, 6), p + Vector2(0, 12)])
		draw_polyline(crack, Color(0.35, 0.36, 0.42, a), 2.5)
	elif c.type == MOVING:
		var y := p.y + 2.0
		for sx in [-1.0, 1.0]:
			var bx: float = p.x + sx * (w * 0.5 - 14.0)
			draw_colored_polygon(PackedVector2Array([Vector2(bx + sx * 7.0, y), Vector2(bx - sx * 2.0, y - 6.0),
				Vector2(bx - sx * 2.0, y + 6.0)]), Color(0.3, 0.55, 0.85, 0.8 * a))
	if c.spring:
		_draw_spring(p + Vector2(c.spring_off, -CLOUD_TOP), c.spring_t > 0.0)


func _blob(p: Vector2, w: float, col: Color) -> void:
	draw_rect(Rect2(p.x - w * 0.5 + 11.0, p.y - 11.0, w - 22.0, 22.0), col)
	draw_circle(p + Vector2(-w * 0.5 + 11.0, 0), 11.0, col)
	draw_circle(p + Vector2(w * 0.5 - 11.0, 0), 11.0, col)
	draw_circle(p + Vector2(-w * 0.18, -6.0), 13.0, col)
	draw_circle(p + Vector2(w * 0.12, -8.0), 14.0, col)


func _draw_spring(base: Vector2, pressed: bool) -> void:
	var h := 7.0 if pressed else 16.0
	var pts := PackedVector2Array()
	for i in 5:
		var x := -7.0 if i % 2 == 0 else 7.0
		pts.append(base + Vector2(x, -h * i / 4.0))
	draw_polyline(pts, Color(0.45, 0.47, 0.55), 3.0)
	draw_rect(Rect2(base.x - 13.0, base.y - h - 5.0, 26.0, 6.0), Color(0.93, 0.25, 0.3))


func _draw_star(c: Vector2, r: float, rot: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := rot + i * TAU / 10.0 - PI / 2.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color(1.0, 0.84, 0.2))
	pts.append(pts[0])
	draw_polyline(pts, Color(0.95, 0.55, 0.1), 2.0)


func _draw_player() -> void:
	var sp := _sp(pos.x, pos.y)
	var sx := 1.0 + 0.28 * squash
	var sy := 1.0 - 0.28 * squash
	if vel.y < -700.0:
		sx *= 0.92
		sy *= 1.1
	draw_set_transform(sp + Vector2(0, R * (1.0 - sy)), 0.0, Vector2(sx, sy))
	var flap := sin(t * 18.0) * 5.0 if vel.y > 0.0 else -4.0
	draw_circle(Vector2(-21, 2 + flap), 9.0, Color("f2b705"))
	draw_circle(Vector2(21, 2 + flap), 9.0, Color("f2b705"))
	draw_circle(Vector2.ZERO, R, Color("ffd84a"))
	draw_circle(Vector2(0, 7), 13.0, Color("fff1b0"))
	draw_circle(Vector2(-2, -23), 5.0, Color("f2b705"))
	draw_circle(Vector2(4, -25), 4.0, Color("f2b705"))
	var look := Vector2(facing * 2.0, clampf(vel.y / 500.0, -1.0, 1.0) * 2.0)
	for ex in [-8.0, 8.0]:
		var e := Vector2(ex + facing * 4.0, -6.0)
		draw_circle(e, 7.0, Color.WHITE)
		draw_circle(e + look, 3.5, Color("1b1b2a"))
	draw_circle(Vector2(-13 + facing * 3.0, 5), 4.0, Color(1, 0.5, 0.5, 0.5))
	draw_circle(Vector2(13 + facing * 3.0, 5), 4.0, Color(1, 0.5, 0.5, 0.5))
	draw_colored_polygon(PackedVector2Array([Vector2(facing * 12.0, -1), Vector2(facing * 25.0, 3),
		Vector2(facing * 12.0, 8)]), Color("ff8c1a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _text(txt: String, pos2: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, width := W) -> void:
	draw_string_outline(font, pos2, txt, align, width, size, maxi(4, size / 5), Color(0.05, 0.07, 0.2, 0.55))
	draw_string(font, pos2, txt, align, width, size, col)


func _draw_hud() -> void:
	var blink := fmod(t, 1.0) < 0.65
	if state == TITLE:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.06, 0.12, 0.32, 0.55)
		panel.set_corner_radius_all(26)
		draw_style_box(panel, Rect2(18, H * 0.2 - 72, W - 36, H * 0.16 + 72 + (190.0 if best > 0 else 150.0)))
		_text("SAUTE-NUAGES", Vector2(0, H * 0.2), 58, Color("fff4c2"))
		_text("Aide Plume à grimper jusqu'aux étoiles !", Vector2(0, H * 0.2 + 46), 22, Color.WHITE)
		_text("Touche à gauche ou à droite de l'écran", Vector2(0, H * 0.36), 22, Color.WHITE)
		_text("pour diriger Plume", Vector2(0, H * 0.36 + 30), 22, Color.WHITE)
		_text("(sur ordinateur : flèches gauche / droite)", Vector2(0, H * 0.36 + 62), 18, Color(1, 1, 1, 0.85))
		_text("Nuage gris = il casse   ·   Ressort rouge = super saut", Vector2(0, H * 0.36 + 100), 17, Color(1, 1, 1, 0.85))
		if best > 0:
			_text("Record : %d" % best, Vector2(0, H * 0.36 + 142), 24, Color("ffe066"))
		if blink:
			_text("Touche l'écran pour jouer", Vector2(0, H * 0.62), 30, Color("fff4c2"))
		return

	_text(str(score), Vector2(20, 56), 44, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, W - 40)
	_text("Record : %d" % maxi(best, score), Vector2(20, 46), 20, Color("fff4c2"), HORIZONTAL_ALIGNMENT_RIGHT, W - 40)

	if state == PLAY and play_t < 4.0:
		var a := clampf(4.0 - play_t, 0.0, 1.0) * 0.45
		var y := H - 70.0
		draw_colored_polygon(PackedVector2Array([Vector2(30, y), Vector2(66, y - 24), Vector2(66, y + 24)]), Color(1, 1, 1, a))
		draw_colored_polygon(PackedVector2Array([Vector2(W - 30, y), Vector2(W - 66, y - 24), Vector2(W - 66, y + 24)]), Color(1, 1, 1, a))

	if state == OVER:
		draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.03, 0.12, minf(0.45, over_t)))
		_text("Plume est tombé !", Vector2(0, H * 0.3), 44, Color("fff4c2"))
		_text("Score : %d" % score, Vector2(0, H * 0.3 + 70), 36, Color.WHITE)
		if new_best:
			_text("Nouveau record !", Vector2(0, H * 0.3 + 120), 30, Color("ffe066"))
		else:
			_text("Record : %d" % best, Vector2(0, H * 0.3 + 120), 26, Color("ffe066"))
		if over_t > 0.7 and blink:
			_text("Touche l'écran pour rejouer", Vector2(0, H * 0.62), 28, Color.WHITE)


# ---------------------------------------------------------------- sons

func _make_sounds() -> void:
	var defs := {
		"jump": [320.0, 720.0, 0.11, 0.35, false],
		"spring": [260.0, 1300.0, 0.32, 0.4, false],
		"star": [880.0, 1500.0, 0.16, 0.3, false],
		"break": [0.0, 0.0, 0.2, 0.35, true],
		"fall": [620.0, 140.0, 0.6, 0.35, false],
	}
	for k in defs:
		var d: Array = defs[k]
		var p := AudioStreamPlayer.new()
		p.stream = _tone(d[0], d[1], d[2], d[3], d[4])
		add_child(p)
		sfx[k] = p


func _tone(f0: float, f1: float, dur: float, vol: float, noise: bool) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += lerpf(f0, f1, k) / rate
		var s := rng.randf_range(-1.0, 1.0) if noise else sin(TAU * ph)
		var env := minf(1.0, k * 40.0) * (1.0 - k) * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _sound(k: String) -> void:
	if sfx.has(k) and not autoplay:
		sfx[k].play()


# ---------------------------------------------------------------- record

func _load_best() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			best = int(data.get("best", 0))


func _save_best() -> void:
	if autoplay:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"best": best}))
