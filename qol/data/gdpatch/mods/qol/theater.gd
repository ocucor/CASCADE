extends Node

# The ghost theater: plays .cghost recordings in the level, POV / chase / free camera.


const SPEEDS = [0.05, 0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 4.0]
const CAM_MODES = ["POV", "CHASE", "FREE"]
const MAJOR = ["core", "kill", "exfil", "death", "zoned", "star"]
const MOVES = ["jump", "dash", "stomp"]
const EVENT_NAMES = {
	"deploy": "DEPLOY", "core": "CORE", "kill": "KILL", "exfil": "EXFIL", "death": "DEATH",
	"zoned": "ZONED", "star": "STARSTRUCK", "jump": "JUMP", "dash": "DASH", "stomp": "STOMP", "shot": "SHOT",
	"hurt": "HURT", "hit": "HIT",
}
const EVENT_COLORS = {
	"core": Color("ffd23f"), "kill": Color("c42b47"), "exfil": Color("3fd46b"), "death": Color(1, 1, 1),
	"zoned": Color("ff4fb4"), "star": Color("8700ff"), "jump": Color(0.75, 0.75, 0.75),
	"dash": Color("2fc4e0"), "stomp": Color("ea531f"), "shot": Color(0.55, 0.55, 0.55), "deploy": Color(1, 1, 1),
	"hurt": Color("ff7a1a"), "hit": Color("ffd23f"),
}
const MAJOR_EXTRA = ["hurt"]
const DEATH_FX = "res://Scenes/FX/death_particles.tscn"
const KILL_FX = "res://Scenes/FX/kill_cross.tscn"
const LAND_FX = "res://Scenes/FX/falllandfx.tscn"
const TRACER_LIFE = 0.12
const RAIL_LIFE = 0.45

var ghosts_mod = null
var active = false

var _pending = null
var _ghosts = []
var _focus = 0
var _t = 0.0
var _playing = true
var _speed_i = 4
var _cam_mode = 0
var _smooth = false
var _show_moves = true
var _show_shots = false
var _hud_on = true
var _scene = null
var _cam: Camera3D = null
var _free_pos = Vector3.ZERO
var _free_yaw = 0.0
var _free_pitch = 0.0
var _looking = false
var _dragging = false
var _chase_pos = Vector3.ZERO

var _hud: CanvasLayer = null
var _timeline: Control = null
var _time_label: Label = null
var _readout: Label = null
var _list: VBoxContainer = null
var _warn: Label = null
var _tip: Label = null
var _btn = {}
var _overlay: ColorRect = null
var _overlay_text: Label = null

var _fx = []
var _prev_tick = -1
var _enemies = []
var _cores = []
var _world_cache = {}
var _player = null
var _pcam: Camera3D = null
var _rig = null
var _rig_skin = -1
var _rig_cskin = null
var _rig_cskin_shown = {}
var _prev_stomp = false
var _alerted = {}
var _los_tick = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	process_priority = 1001
	Engine.set_meta("qol_theater", self)


func _hub():
	return Engine.get_meta("gdpatch_settings_hub") if Engine.has_meta("gdpatch_settings_hub") else null


func request(ghosts: Array, options) -> void:
	if ghosts.is_empty():
		return
	var g = get_node("/root/global")
	_pending = {"ghosts": ghosts, "scene_id": get_tree().current_scene.get_instance_id() if get_tree().current_scene else 0}
	var ui = get_node_or_null("/root/UI")
	if get_tree().paused and ui and ui.get("_pause"):
		ui._pause._unpausecommon()
	if options and is_instance_valid(options):
		options.hide()
	g._setlevel(ghosts[0].level, true, true)


func _begin() -> void:
	var g = get_node("/root/global")
	var p = g._player
	var ghosts = _pending.ghosts
	_pending = null
	active = true
	_scene = get_tree().current_scene

	p.active = false
	p.set_physics_process(false)
	p.set_process_unhandled_input(false)
	p.velocity = Vector3.ZERO
	var ui = get_node_or_null("/root/UI")
	if ui:
		ui.visible = false

	_ghosts.clear()
	for i in ghosts.size():
		var body = load("res://gdpatch/mods/qol/ghost_body.gd").new()
		body.name = "QolTheaterGhost%d" % i
		_scene.add_child(body)
		var c = ghosts_mod.GHOST_COLORS[i % ghosts_mod.GHOST_COLORS.size()]
		body.setup_theater(c, int(ghosts[i].get("skin", 0)), "%s  %s" % [ghosts[i].name, ghosts_mod._fmt(ghosts[i].time)], p,
			ghosts[i].get("cskin", {}))
		_ghosts.append({"gh": ghosts[i], "body": body, "color": c, "idx": _index(ghosts[i]),
			"audit": ghosts[i].get("audit", ghosts_mod.audit(ghosts[i]))})
	_freeze_world()
	for e in _ghosts:
		_locate_events(e)
		if e.gh.get("inferred", false):
			_infer_events(e)
	_player = p
	_pcam = p.camera
	_rig = p.get_node_or_null("Head/Camera3D/RigFPS")
	_rig_skin = -1
	_rig_cskin = null
	_rig_cskin_shown = {}
	if _rig:


		_rig.set("Ready", false)
		_rig.show()

	_cam = Camera3D.new()
	_cam.name = "QolTheaterCam"
	_cam.near = p.camera.near
	_cam.far = p.camera.far
	_scene.add_child(_cam)
	_cam.make_current()
	var f0 = ghosts_mod.frame(ghosts[0], 0)
	_free_pos = f0.cam_pos
	_free_yaw = f0.yaw
	_free_pitch = f0.pitch
	_chase_pos = f0.cam_pos
	_t = 0.0
	_focus = 0
	_playing = true
	_prev_tick = -1
	_build_hud()
	print("[qol] theater: %d ghost(s) on %s" % [_ghosts.size(), ghosts[0].level])


func _end(to_menu: bool) -> void:
	active = false
	_clear_fx()
	_enemies.clear()
	_cores.clear()
	_world_cache.clear()
	_player = null
	_pcam = null

	if is_instance_valid(_rig) and Engine.has_meta("skinkit"):
		Engine.get_meta("skinkit").replay_end(_rig)
	_rig = null
	for e in _ghosts:
		if is_instance_valid(e.body):
			e.body.queue_free()
	_ghosts.clear()
	if is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	if _hud:
		_hud.queue_free()
		_hud = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if to_menu:
		var g = get_node("/root/global")
		g._goto_menu()


func _process(delta: float) -> void:
	if _pending != null and !active:
		var g = get_node_or_null("/root/global")
		var p = g.get("_player") if g else null
		var sc = get_tree().current_scene
		if is_instance_valid(p) and p.is_inside_tree() and p.is_node_ready() and sc \
				and sc.get_instance_id() != _pending.scene_id and str(g.currentlevel) == _pending.ghosts[0].level:
			_begin()
		return
	if !active:
		return
	if !is_instance_valid(_scene) or get_tree().current_scene != _scene:
		_end(false)
		return

	var g = get_node("/root/global")
	g.showmouse = true
	if !_looking:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var lead = _ghosts[_focus].gh
	var max_t = 0.0
	for e in _ghosts:
		max_t = maxf(max_t, float(e.gh.ticks - 1) / e.gh.tps * lead.tps)
	if _playing:
		_t += delta * SPEEDS[_speed_i] * lead.tps
		if _t >= max_t:
			_t = max_t
			_playing = false
	_t = clampf(_t, 0.0, max_t)

	var seconds = _t / lead.tps
	var cur_tick = int(floor(_t))


	var forward = _prev_tick >= 0 and cur_tick > _prev_tick and cur_tick - _prev_tick <= lead.tps
	if !forward and cur_tick != _prev_tick:
		_clear_fx()
		for e in _ghosts:
			e.body.reset_fx()
	var anim_dt = delta * SPEEDS[_speed_i] if _playing else 0.0
	for i in _ghosts.size():
		var e = _ghosts[i]
		var tt = seconds * e.gh.tps
		var st = ghosts_mod.pose(e.gh, tt, _smooth)
		_state(e, st, tt)
		e.body.drive(st, anim_dt, forward)
		var pov_self = i == _focus and _cam_mode == 0
		e.body.visible = !pov_self and tt <= e.gh.ticks - 1 + 0.5
		e.body.show_tag(_ghosts.size() > 1 or _cam_mode != 0)
		if forward:
			var prev_tt = float(_prev_tick) / lead.tps * e.gh.tps
			_spawn_fx(e, int(floor(prev_tt)), int(floor(tt)), i == _focus)
	_sync_world(lead, cur_tick)
	_watch_runner(_ghosts[_focus], seconds * lead.tps)
	_feed_rig(_ghosts[_focus], seconds * lead.tps)
	_prev_tick = cur_tick
	_update_fx()
	_update_camera(delta)
	_update_overlay(_ghosts[_focus], seconds * lead.tps)
	_update_hud()


func _update_camera(delta: float) -> void:
	var e = _ghosts[_focus]
	var pz = ghosts_mod.pose(e.gh, _t, _smooth)
	var pov_cam = _pcam if is_instance_valid(_pcam) else _cam
	var want = pov_cam if _cam_mode == 0 else _cam
	if !want.current:
		want.make_current()
	match _cam_mode:
		0:
			pov_cam.global_transform = Transform3D(Basis(pz.cam_quat), pz.cam_pos)
			pov_cam.fov = pz.fov
		1:
			var target = pz.pos + Vector3(0, 1.2, 0)
			var behind = Basis(Vector3.UP, pz.yaw) * Vector3(0, 0.0, 4.0) + Vector3(0, 1.4, 0)
			_chase_pos = _chase_pos.lerp(target + behind, clampf(delta * 10.0, 0.0, 1.0))
			_cam.global_position = _chase_pos
			if _chase_pos.distance_to(target) > 0.01:
				_cam.look_at(target, Vector3.UP)
			_cam.fov = 80.0
		2:
			var dir = Vector3.ZERO
			var mv = Input.get_vector("left", "right", "forward", "back") if InputMap.has_action("left") else Vector2.ZERO
			if Input.is_key_pressed(KEY_W): mv.y -= 1
			if Input.is_key_pressed(KEY_S): mv.y += 1
			if Input.is_key_pressed(KEY_A): mv.x -= 1
			if Input.is_key_pressed(KEY_D): mv.x += 1
			mv = mv.limit_length(1.0)
			var basis = Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0))
			dir = basis * Vector3(mv.x, 0, mv.y)
			if Input.is_key_pressed(KEY_E): dir.y += 1
			if Input.is_key_pressed(KEY_Q): dir.y -= 1
			var look = Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
			if look.length() > 0.15:
				_free_yaw -= look.x * 2.5 * delta
				_free_pitch = clampf(_free_pitch - look.y * 2.0 * delta, -1.5, 1.5)
			var spd = 30.0 if Input.is_key_pressed(KEY_SHIFT) else 10.0
			_free_pos += dir * spd * delta
			_cam.global_transform = Transform3D(Basis.from_euler(Vector3(_free_pitch, _free_yaw, 0)), _free_pos)
			_cam.fov = 80.0


func _input(event: InputEvent) -> void:
	if !active:
		return
	if event is InputEventMouseMotion and _looking and _cam_mode == 2:
		_free_yaw -= event.relative.x * 0.003
		_free_pitch = clampf(_free_pitch - event.relative.y * 0.003, -1.5, 1.5)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed and _cam_mode == 2
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		return
	var handled = true
	if event is InputEventKey and event.pressed:
		var big = event.shift_pressed
		match event.keycode:
			KEY_SPACE: _toggle_play()
			KEY_LEFT: _step(-1, big)
			KEY_RIGHT: _step(1, big)
			KEY_COMMA: _jump_event(-1)
			KEY_PERIOD: _jump_event(1)
			KEY_UP: _speed(1)
			KEY_DOWN: _speed(-1)
			KEY_C: _cycle_cam()
			KEY_TAB: _cycle_focus()
			KEY_H: _toggle_hud()
			KEY_HOME: _seek(0.0)
			KEY_ESCAPE: _end(true)
			_: handled = false
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _toggle_play()
			JOY_BUTTON_B: _end(true)
			JOY_BUTTON_X: _cycle_cam()
			JOY_BUTTON_Y: _cycle_focus()
			JOY_BUTTON_LEFT_SHOULDER: _step(-1, false)
			JOY_BUTTON_RIGHT_SHOULDER: _step(1, false)
			JOY_BUTTON_DPAD_LEFT: _step(-1, true)
			JOY_BUTTON_DPAD_RIGHT: _step(1, true)
			JOY_BUTTON_DPAD_UP: _speed(1)
			JOY_BUTTON_DPAD_DOWN: _speed(-1)
			JOY_BUTTON_BACK: _toggle_hud()
			_: handled = false
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _lead():
	return _ghosts[_focus].gh


func _toggle_play() -> void:
	_playing = !_playing


func _step(dir: int, big: bool) -> void:
	_playing = false
	var n = _lead().tps if big else 1
	_t = floor(_t) + dir * n
	_t = maxf(_t, 0.0)


func _seek(tick: float) -> void:
	_t = maxf(tick, 0.0)


func _speed(dir: int) -> void:
	_speed_i = clampi(_speed_i + dir, 0, SPEEDS.size() - 1)


func _cycle_cam() -> void:
	_cam_mode = (_cam_mode + 1) % CAM_MODES.size()
	if _cam_mode == 2 and is_instance_valid(_cam):
		_free_pos = _cam.global_position
		var e = _cam.global_transform.basis.get_euler()
		_free_yaw = e.y
		_free_pitch = e.x


func _cycle_focus() -> void:

	var sec = _t / _lead().tps
	_focus = (_focus + 1) % _ghosts.size()
	_t = sec * _lead().tps
	_rebuild_list()


func _toggle_hud() -> void:
	_hud_on = !_hud_on
	if _hud:
		_hud.visible = _hud_on


func _visible_event(type: String) -> bool:
	if MAJOR.has(type) or MAJOR_EXTRA.has(type) or type == "deploy":
		return true
	if MOVES.has(type):
		return _show_moves
	return (type == "shot" or type == "hit") and _show_shots


func _jump_event(dir: int) -> void:
	var cur = floor(_t)
	var best = -1.0
	for e in _lead().events:
		if !MAJOR.has(e[1]):
			continue
		if dir > 0 and e[0] > cur and (best < 0 or e[0] < best):
			best = e[0]
		elif dir < 0 and e[0] < cur and (best < 0 or e[0] > best):
			best = e[0]
	if best >= 0:
		_playing = false
		_t = best


func _label(text: String, size: int, color: Color = Color(1, 1, 1), title: bool = false) -> Label:
	var hub = _hub()
	if hub:
		return hub.make_label(text, size, color, title)
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable, w: float = 0.0) -> Button:
	var hub = _hub()
	var b: Button = hub.make_button(text, 20) if hub else Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	if w > 0:
		b.custom_minimum_size = Vector2(w, 34)
	b.pressed.connect(cb)
	return b


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "QolTheaterHud"
	_hud.layer = 129
	add_child(_hud)
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)


	_overlay = ColorRect.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(0, 0, 0, 0)
	root.add_child(_overlay)
	_overlay_text = _label("TERMINATED", 96, Color("c42b47"), true)
	_overlay_text.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_overlay_text.offset_left = -500.0
	_overlay_text.offset_right = 500.0
	_overlay_text.offset_top = -80.0
	_overlay_text.offset_bottom = 40.0
	_overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_text.visible = false
	root.add_child(_overlay_text)


	var bar = ColorRect.new()
	bar.color = Color(0, 0, 0, 0.88)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -150.0
	root.add_child(bar)

	_timeline = Control.new()
	_timeline.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_timeline.offset_left = 40.0
	_timeline.offset_right = -40.0
	_timeline.offset_top = 12.0
	_timeline.offset_bottom = 78.0
	_timeline.mouse_filter = Control.MOUSE_FILTER_STOP
	_timeline.draw.connect(_draw_timeline)
	_timeline.gui_input.connect(_timeline_input)
	_timeline.mouse_exited.connect(func(): _tip.visible = false)
	bar.add_child(_timeline)

	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 40.0
	row.offset_right = -40.0
	row.offset_top = -58.0
	row.offset_bottom = -16.0
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	row.add_child(_button("|<", func(): _seek(0.0), 50))
	row.add_child(_button("<EV", func(): _jump_event(-1), 64))
	row.add_child(_button("-1S", func(): _step(-1, true), 56))
	row.add_child(_button("-1T", func(): _step(-1, false), 56))
	_btn.play = _button("PAUSE", _toggle_play, 96)
	row.add_child(_btn.play)
	row.add_child(_button("+1T", func(): _step(1, false), 56))
	row.add_child(_button("+1S", func(): _step(1, true), 56))
	row.add_child(_button("EV>", func(): _jump_event(1), 64))
	row.add_child(_button("-", func(): _speed(-1), 40))
	_btn.speed = _label("1.00X", 22)
	_btn.speed.custom_minimum_size = Vector2(76, 34)
	_btn.speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn.speed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_btn.speed)
	row.add_child(_button("+", func(): _speed(1), 40))
	_btn.cam = _button("CAM POV", _cycle_cam, 140)
	row.add_child(_btn.cam)
	_btn.smooth = _button("1:1 TICKS", func(): _smooth = !_smooth, 150)
	_btn.smooth.set_meta("tip", "1:1 shows each recorded physics tick exactly. SMOOTH blends between ticks (for slow motion viewing).")
	row.add_child(_btn.smooth)
	_btn.moves = _button("MOVES ON", func():
		_show_moves = !_show_moves
		_timeline.queue_redraw(), 130)
	row.add_child(_btn.moves)
	_btn.shots = _button("SHOTS OFF", func():
		_show_shots = !_show_shots
		_timeline.queue_redraw(), 130)
	row.add_child(_btn.shots)
	_btn.bars = _button("BARS GAME", func():
		var q = ghosts_mod.q
		q.set_opt("theater_bars", (int(q.s.theater_bars) + 1) % ghosts_mod.BAR_MODES.size()), 140)
	row.add_child(_btn.bars)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_time_label = _label("", 24, Color(1, 1, 1), true)
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_time_label)
	row.add_child(_button("EXIT", func(): _end(true), 80))


	var lp = ColorRect.new()
	lp.color = Color(0, 0, 0, 0.8)
	lp.position = Vector2(20, 20)
	lp.size = Vector2(470, 40 + 34 * _ghosts.size())
	root.add_child(lp)
	var title = _label("GHOST THEATER", 22, Color("c42b47"), true)
	title.position = Vector2(12, 6)
	lp.add_child(title)
	_list = VBoxContainer.new()
	_list.position = Vector2(8, 36)
	_list.size = Vector2(454, 34 * _ghosts.size())
	_list.add_theme_constant_override("separation", 2)
	lp.add_child(_list)
	_rebuild_list()


	var rp = ColorRect.new()
	rp.color = Color(0, 0, 0, 0.8)
	rp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rp.offset_left = -360.0
	rp.offset_right = -20.0
	rp.offset_top = 20.0
	rp.offset_bottom = 168.0
	root.add_child(rp)
	_readout = _label("", 19)
	_readout.position = Vector2(12, 8)
	_readout.size = Vector2(320, 140)
	rp.add_child(_readout)


	_warn = _label("", 20, Color("c42b47"), true)
	_warn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_warn.offset_left = -420.0
	_warn.offset_right = 420.0
	_warn.offset_top = 20.0
	_warn.offset_bottom = 120.0
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_warn)
	var lines = []
	var worst = "VERIFIED"
	var showcase_only = true
	for i in _ghosts.size():
		var a = _ghosts[i].audit
		if a.state != "VERIFIED" and a.state != "SHOWCASE":
			showcase_only = false
		if a.state != "VERIFIED":
			lines.append("%s (%s): %s. %s" % [_ghosts[i].gh.name, ghosts_mod._fmt(_ghosts[i].gh.time), a.state, a.notes[0] if !a.notes.is_empty() else ""])
			if worst == "VERIFIED" or worst == "SHOWCASE" or a.state == "MODIFIED" or a.state == "SIGNER CHANGED":
				worst = a.state
	_warn.visible = !lines.is_empty()
	if _warn.visible:
		_warn.text = ("SHOWCASE GHOST\n" if showcase_only else "WARNING: UNTRUSTED GHOST\n") + "\n".join(lines)
		_warn.add_theme_color_override("font_color", ghosts_mod.badge_color(worst))
		_warn.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_warn.add_theme_constant_override("outline_size", 6)

	_tip = _label("", 18)
	_tip.visible = false
	_tip.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_tip.add_theme_constant_override("outline_size", 5)
	root.add_child(_tip)

	var help = _label("SPACE PLAY   ARROWS STEP (SHIFT 1S)   , . EVENTS   UP/DOWN SPEED   C CAMERA   TAB GHOST   H HUD   ESC EXIT   FREE CAM: RMB LOOK + WASD/QE", 14, Color(0.65, 0.65, 0.65))
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -172.0
	help.offset_bottom = -152.0
	help.offset_left = 40.0
	root.add_child(help)
	_hud.visible = _hud_on


func _rebuild_list() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	for i in _ghosts.size():
		var e = _ghosts[i]
		var a = e.audit
		var b = _button("", func():
			var sec = _t / _lead().tps
			_focus = i
			_t = sec * _lead().tps
			_rebuild_list(), 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(454, 32)
		b.text = "%s %s  %s  %s" % ["> " if i == _focus else "  ", e.gh.name, ghosts_mod._fmt(e.gh.time), a.state]
		b.add_theme_color_override("font_color", e.color)
		var chip = ColorRect.new()
		chip.color = ghosts_mod.badge_color(a.state)
		chip.custom_minimum_size = Vector2(8, 32)
		chip.position = Vector2(446, 0)
		chip.size = Vector2(8, 32)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(chip)
		_list.add_child(b)


func _update_hud() -> void:
	if _hud == null or !_hud.visible:
		return
	var gh = _lead()
	var tick = int(floor(_t))
	var f = ghosts_mod.frame(gh, tick)
	_time_label.text = "%s / %s   T %d/%d" % [ghosts_mod._fmt(float(tick) / gh.tps), ghosts_mod._fmt(gh.time), tick, gh.ticks - 1]
	_btn.play.text = "PAUSE" if _playing else "PLAY"
	_btn.speed.text = "%.2fX" % SPEEDS[_speed_i]
	_btn.cam.text = "CAM " + CAM_MODES[_cam_mode]
	_btn.smooth.text = "SMOOTH" if _smooth else "1:1 TICKS"
	_btn.moves.text = "MOVES " + ("ON" if _show_moves else "OFF")
	_btn.shots.text = "SHOTS " + ("ON" if _show_shots else "OFF")
	_btn.bars.text = "BARS " + ghosts_mod.BAR_MODES[clampi(int(ghosts_mod.q.s.theater_bars), 0, 2)]
	var states = []
	for pair in [[1, "FLOOR"], [2, "AIM"], [4, "DASH"], [8, "STOMP"], [16, "SLIDE"], [64, "ZONED"], [128, "STAR"], [256, "EXFIL"], [32, "DEAD"]]:
		if f.flags & pair[0]:
			states.append(pair[1])
	if !(f.flags & 1):
		states.push_front("AIR")
	var hv = Vector2(f.vel.x, f.vel.z).length()
	var lines = [
		"%s   %s" % [gh.name, gh.level.to_upper()],
		"SPEED %.2f   VERT %+.2f" % [hv, f.vel.y],
		"POS %.2f %.2f %.2f" % [f.pos.x, f.pos.y, f.pos.z],
		"JUMPS %d   FOV %.1f" % [f.jumps, f.fov],
		" ".join(states),
	]
	_readout.text = "\n".join(lines)
	_timeline.queue_redraw()


func _draw_timeline() -> void:
	var c = _timeline
	var w = c.size.x
	var gh = _lead()
	var total = float(maxi(gh.ticks - 1, 1))
	var bar_y = 30.0
	c.draw_rect(Rect2(0, bar_y, w, 10), Color(0.25, 0.25, 0.25))
	c.draw_rect(Rect2(0, bar_y, w * clampf(_t / total, 0.0, 1.0), 10), Color(0.85, 0.85, 0.85))

	for e in _ghosts:
		if e.gh == gh:
			continue
		var end_x = w * clampf((e.gh.time * gh.tps) / total, 0.0, 1.05)
		c.draw_line(Vector2(minf(end_x, w), bar_y - 4), Vector2(minf(end_x, w), bar_y + 14), e.color, 3.0)
	for ev in gh.events:
		if !_visible_event(ev[1]):
			continue
		var x = w * float(ev[0]) / total
		var col = EVENT_COLORS.get(ev[1], Color(1, 1, 1))
		if MAJOR.has(ev[1]) or MAJOR_EXTRA.has(ev[1]) or ev[1] == "deploy":
			_draw_icon(c, ev[1], Vector2(x, bar_y - 12), col)
		else:
			var y0 = bar_y + 14 if ev[1] != "shot" else bar_y + 24
			c.draw_line(Vector2(x, y0), Vector2(x, y0 + 8), col, 2.0)
	var px = w * clampf(_t / total, 0.0, 1.0)
	c.draw_line(Vector2(px, 0), Vector2(px, c.size.y), Color(1, 1, 1), 2.0)


func _draw_icon(c: Control, type: String, at: Vector2, col: Color) -> void:
	var s = 8.0
	match type:
		"core":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0)]), col)
		"kill":
			c.draw_line(at + Vector2(-s, -s), at + Vector2(s, s), col, 3.0)
			c.draw_line(at + Vector2(-s, s), at + Vector2(s, -s), col, 3.0)
		"exfil":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s - 2), at + Vector2(s + 2, s), at + Vector2(-s - 2, s)]), col)
		"death":
			c.draw_rect(Rect2(at - Vector2(s, s), Vector2(s, s) * 2), col)
			c.draw_rect(Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), Color(0, 0, 0))
		"zoned", "star":
			c.draw_circle(at, s, col)
		"hurt":
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, s), at + Vector2(-s, -s * 0.4), at + Vector2(s, -s * 0.4)]), col)
		"deploy":
			c.draw_line(at + Vector2(-s, -s), at + Vector2(-s, s + 12), col, 2.0)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-s, -s), at + Vector2(s, -s * 0.5), at + Vector2(-s, 0)]), col)


func _timeline_input(event: InputEvent) -> void:
	var gh = _lead()
	var total = float(maxi(gh.ticks - 1, 1))
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_seek(roundf(clampf(event.position.x / _timeline.size.x, 0.0, 1.0) * total))
	elif event is InputEventMouseMotion:
		if _dragging:
			_seek(roundf(clampf(event.position.x / _timeline.size.x, 0.0, 1.0) * total))

		var best = null
		var best_d = 10.0
		for ev in gh.events:
			if !_visible_event(ev[1]):
				continue
			var d = absf(_timeline.size.x * float(ev[0]) / total - event.position.x)
			if d < best_d:
				best_d = d
				best = ev
		if best:
			_tip.text = "%s  %s" % [EVENT_NAMES.get(best[1], best[1]), ghosts_mod._fmt(float(best[0]) / gh.tps)]
			_tip.position = _timeline.get_global_rect().position + Vector2(event.position.x - 40, -34)
			_tip.visible = true
		else:
			_tip.visible = false


func _index(gh: Dictionary) -> Dictionary:
	var idx = {"fire": [], "jump": [], "land": [], "dash": [], "core": [], "star": [], "hurt": [], "death": []}
	var map = {"shot": "fire", "jump": "jump", "dash": "dash", "core": "core", "star": "star", "hurt": "hurt", "death": "death"}
	for e in gh.events:
		if map.has(e[1]):
			idx[map[e[1]]].append(e[0])

	var was_floor = true
	for i in gh.ticks:
		var on_floor = (gh.data.decode_u16(i * ghosts_mod.REC + 56) & 1) != 0
		if on_floor and !was_floor:
			idx.land.append(i)
		was_floor = on_floor
	for k in idx:
		idx[k].sort()
	return idx


func _since(list: Array, tick: float, tps: int) -> float:
	if list.is_empty():
		return -1.0
	var i = list.bsearch(int(floor(tick)), false) - 1
	if i < 0:
		return -1.0
	return (tick - list[i]) / tps


func _state(e: Dictionary, st: Dictionary, tt: float) -> void:
	var tps = e.gh.tps
	var since = {}
	for k in ["fire", "jump", "land", "dash", "core", "star", "hurt"]:
		since[k] = _since(e.idx[k], tt, tps)
	st["since"] = since
	st["dead"] = _since(e.idx.death, tt, tps)


func _spawn_fx(e: Dictionary, from_tick: int, to_tick: int, focused: bool) -> void:
	if focused:
		_rig_events(e, from_tick, to_tick)
	for ev in e.gh.events:
		var tk = ev[0]
		if tk <= from_tick or tk > to_tick:
			continue
		var f = ghosts_mod.frame(e.gh, tk)
		match ev[1]:
			"shot":
				_fx_shot(f, e.color, (f.flags & ghosts_mod.F_AIM) != 0)
			"kill":
				if ev.size() >= 5:
					var at = Vector3(ev[2], ev[3], ev[4])
					_fx_scene(DEATH_FX, at, 3.0)
					if focused:
						_fx_scene(KILL_FX, at, 3.0)
			"death":
				_fx_scene(DEATH_FX, f.pos + Vector3(0, 1.0, 0), 3.0)
			"core":
				if focused:
					_core_burst(e, tk)
	for tk in e.idx.land:
		if tk > from_tick and tk <= to_tick:
			var f = ghosts_mod.frame(e.gh, tk)
			if !(f.flags & ghosts_mod.F_STOMP):
				_fx_scene(LAND_FX, f.pos, 2.0)


func _fx_scene(path: String, at: Vector3, life: float) -> void:
	if !ResourceLoader.exists(path):
		return
	var n = load(path).instantiate()
	_scene.add_child(n)
	if n is Node3D:
		n.global_position = at
	_fx.append({"node": n, "born": Time.get_ticks_msec(), "life": life, "mat": null})


func _fx_shot(f: Dictionary, tint: Color, aimed: bool) -> void:
	var basis = Basis(f.cam_quat)
	var muzzle = f.cam_pos + basis * Vector3(0.25, -0.28, -0.55)
	var dirs = [-basis.z] if aimed else [-basis.z, (basis * Basis(Vector3.UP, -0.05)) * Vector3.FORWARD, (basis * Basis(Vector3.UP, 0.05)) * Vector3.FORWARD]
	var space = _scene.get_world_3d().direct_space_state
	for d in dirs:
		var to = f.cam_pos + d * 250.0
		var q = PhysicsRayQueryParameters3D.create(f.cam_pos, to, 1)
		var hit = space.intersect_ray(q)
		var end = hit.position if hit else to
		var col = Color(0.65, 0.9, 1.0) if aimed else Color(1.0, 0.92, 0.6)
		_fx_beam(muzzle, end, 0.07 if aimed else 0.025, col.lerp(tint, 0.25), RAIL_LIFE if aimed else TRACER_LIFE)

	var flash = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.12 if !aimed else 0.2
	sphere.height = sphere.radius * 2.0
	flash.mesh = sphere
	var m = _fx_mat(Color(1, 0.95, 0.75))
	flash.material_override = m
	_scene.add_child(flash)
	flash.global_position = muzzle
	_fx.append({"node": flash, "born": Time.get_ticks_msec(), "life": 0.06, "mat": m})


func _fx_beam(a: Vector3, b: Vector3, width: float, col: Color, life: float) -> void:
	var length = a.distance_to(b)
	if length < 0.05:
		return
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(width, width, length)
	mi.mesh = box
	var m = _fx_mat(col)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene.add_child(mi)
	mi.global_position = (a + b) * 0.5
	if !(b - a).normalized().is_equal_approx(Vector3.UP) and !(b - a).normalized().is_equal_approx(Vector3.DOWN):
		mi.look_at(b, Vector3.UP)
	_fx.append({"node": mi, "born": Time.get_ticks_msec(), "life": life, "mat": m})


func _fx_mat(col: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = false
	return m


func _update_fx() -> void:
	var now = Time.get_ticks_msec()
	var keep = []
	for f in _fx:
		if !is_instance_valid(f.node):
			continue
		var age = (now - f.born) / 1000.0
		if age >= f.life:
			f.node.queue_free()
			continue
		if f.mat:
			f.mat.albedo_color.a = 1.0 - age / f.life
		keep.append(f)
	_fx = keep


func _clear_fx() -> void:
	for f in _fx:
		if is_instance_valid(f.node):
			f.node.queue_free()
	_fx.clear()


func _script_name(n: Node) -> String:
	var s = n.get_script()
	return String(s.get_global_name()) if s else ""


func _freeze_world() -> void:
	_enemies.clear()
	_cores.clear()
	_world_cache.clear()
	var stack = [_scene]
	while !stack.is_empty():
		var n = stack.pop_back()
		var cls = _script_name(n)
		if cls == "Enemy":
			n.process_mode = Node.PROCESS_MODE_DISABLED
			_enemies.append(n)
			continue
		if cls == "Core":
			n.process_mode = Node.PROCESS_MODE_DISABLED
			_cores.append(n)
			continue
		for c in n.get_children():
			stack.append(c)


func _nearest(list: Array, at: Vector3, taken: Dictionary, radius: float):
	var best = null
	var best_d = radius
	for n in list:
		if !is_instance_valid(n) or taken.has(n):
			continue
		var d = n.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = n
	return best


func _world_for(gh: Dictionary) -> Dictionary:
	var key = str(gh.get("path", "")) + "|" + str(gh.time) + "|" + str(gh.name)
	if _world_cache.has(key):
		return _world_cache[key]
	var w = {"kills": [], "cores": [], "health": {}}
	var taken = {}
	for ev in gh.events:
		if ev.size() < 5:
			continue
		var at = Vector3(ev[2], ev[3], ev[4])
		if ev[1] == "kill":
			var n = _nearest(_enemies, at, taken, 8.0)
			if n == null:
				n = _nearest(_enemies, at, taken, 20.0)
			if n:
				taken[n] = true
				w.kills.append([ev[0], n])
		elif ev[1] == "core":
			var c = _nearest(_cores, at, taken, 6.0)
			if c:
				taken[c] = true
				w.cores.append([ev[0], c])
	_build_health(gh, w)
	_world_cache[key] = w
	return w


func _sync_world(gh: Dictionary, tick: int) -> void:
	var w = _world_for(gh)
	var dead = {}
	for k in w.kills:
		if k[0] <= tick:
			dead[k[1]] = true
	for n in _enemies:
		if is_instance_valid(n):
			var show = !dead.has(n)
			if n.visible != show:
				n.visible = show
			if show:
				_sync_bar(n, w.health.get(n, []), tick)
	var got = {}
	for c in w.cores:
		if c[0] <= tick:
			got[c[1]] = true
	for c in _cores:
		if !is_instance_valid(c):
			continue
		var have = !got.has(c)
		for part in ["cube", "shadow"]:
			var n = c.get_node_or_null(part)
			if n and n.visible != have:
				n.visible = have
		var emit = c.get_node_or_null("emit")
		if emit is GPUParticles3D and emit.emitting != have:
			emit.emitting = have


func _core_burst(e: Dictionary, tick: int) -> void:
	for c in _world_for(e.gh).cores:
		if c[0] == tick and is_instance_valid(c[1]):
			var p = c[1].get_node_or_null("collect")
			if p is GPUParticles3D:
				p.restart()
				p.emitting = true


func _update_overlay(e: Dictionary, tt: float) -> void:
	if _overlay == null:
		return
	var tps = e.gh.tps
	var hurt = _since(e.idx.hurt, tt, tps)
	var dead = _since(e.idx.death, tt, tps)
	var a = 0.0
	var col = Color("c42b47")
	if _cam_mode == 0:
		if hurt >= 0.0 and hurt < 0.35:
			a = 0.45 * (1.0 - hurt / 0.35)
		if dead >= 0.0:

			a = clampf(dead / 1.2, 0.0, 0.75) * (0.85 + 0.15 * sin(dead * 60.0))
	_overlay.color = Color(col, a)
	_overlay_text.visible = dead >= 0.0 and int(dead * 6.0) % 2 == 0
	_overlay_text.text = "TERMINATED" if dead >= 0.0 else ""


func _feed_rig(e: Dictionary, tt: float) -> void:
	if !is_instance_valid(_rig) or !is_instance_valid(_player):
		return
	var f = ghosts_mod.frame(e.gh, int(floor(tt)))


	var cskin: Dictionary = e.gh.get("cskin", {})
	var tag = str(cskin)
	if tag != _rig_cskin:
		_rig_cskin = tag
		_rig_skin = -1
		_rig_cskin_shown = Engine.get_meta("skinkit").replay_apply(_rig, cskin) if Engine.has_meta("skinkit") else {}
	var skin = int(e.gh.get("skin", 0))
	if cskin.has("joyeuse") and !_rig_cskin_shown.get("joyeuse_custom", false):
		skin = 0
	if skin != _rig_skin and !_rig_cskin_shown.get("joyeuse_texture", false) and _rig.get("MatGun") is ShaderMaterial:
		var path = ghosts_mod.GHOST_SKINS[clampi(skin, 0, ghosts_mod.GHOST_SKINS.size() - 1)]
		if ResourceLoader.exists(path):
			_rig.MatGun.set_shader_parameter("texture_albedo", load(path))
		_rig_skin = skin

	var on_floor = (f.flags & ghosts_mod.F_FLOOR) != 0
	_player.velocity = f.vel
	_player.set("onfloor", on_floor)
	_player.set("aiming", (f.flags & ghosts_mod.F_AIM) != 0)
	_player.set("stomp", (f.flags & ghosts_mod.F_STOMP) != 0)
	_rig.set("velocity", f.vel)
	_rig.set("is_on_ground", on_floor)
	_rig.set("Unarmed", (f.flags & ghosts_mod.F_UNARMED) != 0)
	_rig.visible = (f.flags & ghosts_mod.F_EXFIL) == 0 and _since(e.idx.death, tt, e.gh.tps) < 0.0


func _rig_events(e: Dictionary, from_tick: int, to_tick: int) -> void:
	if !is_instance_valid(_rig):
		return
	var killflash = get_node_or_null("/root/Config") != null and get_node("/root/Config").get("KILLFLASH") == true
	for ev in e.gh.events:
		var tk = ev[0]
		if tk <= from_tick or tk > to_tick:
			continue
		match ev[1]:
			"shot":
				var aimed = (ghosts_mod.frame(e.gh, tk).flags & ghosts_mod.F_AIM) != 0
				_rig_call("Fire")
				var muzzle = _rig.get("MuzzleAnim")
				if muzzle is AnimationPlayer:
					var anim = ("ADS" if aimed else "Regular") + ("" if killflash else "Simple")
					if muzzle.has_animation(anim):
						muzzle.seek(0.0)
						muzzle.play(anim)
			"jump": _rig_call("Jump")
			"dash": _rig_call("Dash")
			"stomp": _rig_call("Stomp")
			"core": _rig_call("CoreCollect")
			"star": _rig_call("StarStruck")
			"kill":
				if killflash and _cam_mode == 0:
					_pixel_flash("_whitepixelflash")
			"hurt":
				if _cam_mode == 0:
					_pixel_flash("_dmgpixel")
	for tk in e.idx.land:
		if tk > from_tick and tk <= to_tick:
			_rig_call("Land")

	var stomping = (ghosts_mod.frame(e.gh, to_tick).flags & ghosts_mod.F_STOMP) != 0
	if _prev_stomp and !stomping:
		_rig_call("StompEarlyExit")
	_prev_stomp = stomping


func _rig_call(method: String) -> void:
	if is_instance_valid(_rig) and _rig.has_method(method):
		_rig.call(method)


func _pixel_flash(member: String) -> void:
	var n = _player.get(member) if is_instance_valid(_player) else null
	if n and n.has_method("_trig"):
		n._trig()


func _infer_events(e: Dictionary) -> void:
	var gh = e.gh
	var added = []
	var taken = {}
	for c in _cores:
		if !is_instance_valid(c):
			continue
		for i in range(0, gh.ticks, 2):
			if ghosts_mod.frame(gh, i).pos.distance_to(c.global_position) < 2.5:
				var at = c.global_position
				added.append([i, "core", at.x, at.y, at.z])
				break
	var space = _scene.get_world_3d().direct_space_state
	for ev in gh.events:
		if ev[1] != "shot":
			continue
		var f = ghosts_mod.frame(gh, ev[0])
		var dir = -Basis(f.cam_quat).z
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(f.cam_pos, f.cam_pos + dir * 250.0, 1))
		var reach = f.cam_pos.distance_to(hit.position) if hit else 250.0
		var best = null
		var best_along = reach
		for n in _enemies:
			if !is_instance_valid(n) or taken.has(n):
				continue
			var rel = n.global_position + Vector3(0, 0.8, 0) - f.cam_pos
			var along = rel.dot(dir)
			if along <= 0.0 or along > best_along:
				continue
			if (rel - dir * along).length() < 1.6:
				best = n
				best_along = along
		if best:
			taken[best] = true
			var at = best.global_position
			added.append([ev[0], "kill", at.x, at.y, at.z])
	for i in range(0, gh.ticks):
		var f = ghosts_mod.frame(gh, i)
		if !(f.flags & ghosts_mod.F_DASH):
			continue
		for n in _enemies:
			if is_instance_valid(n) and !taken.has(n) and f.pos.distance_to(n.global_position) < 2.2:
				taken[n] = true
				var at = n.global_position
				added.append([i, "kill", at.x, at.y, at.z])
	gh.events.append_array(added)
	gh.events.sort_custom(func(x, y): return x[0] < y[0])
	e.idx = _index(gh)
	_world_cache.clear()
	print("[qol] theater: showcase events reconstructed: %d cores, %d kills" % [
		added.filter(func(x): return x[1] == "core").size(), added.filter(func(x): return x[1] == "kill").size()])


func _locate_events(e: Dictionary) -> void:
	var gh = e.gh
	var taken = {}
	var space = _scene.get_world_3d().direct_space_state
	var found = 0
	for ev in gh.events:
		if ev.size() >= 5 or (ev[1] != "kill" and ev[1] != "core"):
			continue
		var f = ghosts_mod.frame(gh, ev[0])
		var target = null
		if ev[1] == "core":
			target = _nearest(_cores, f.pos, taken, 8.0)
		else:
			var shot = -1
			for s2 in gh.events:
				if s2[1] == "shot" and s2[0] <= ev[0] and ev[0] - s2[0] <= gh.tps / 2:
					shot = s2[0]
			if shot >= 0:
				target = _on_line_of_fire(ghosts_mod.frame(gh, shot), space, taken)
			if target == null and (f.flags & ghosts_mod.F_DASH or f.flags & ghosts_mod.F_STOMP):
				target = _nearest(_enemies, f.pos, taken, 4.0)
			if target == null:
				target = _nearest(_enemies, f.pos, taken, 25.0)
		if target:
			taken[target] = true
			var at = target.global_position
			ev.append_array([at.x, at.y, at.z])
			found += 1
	if found > 0:
		_world_cache.clear()
		print("[qol] theater: located %d kill / core event(s) without positions" % found)


func _on_line_of_fire(f: Dictionary, space, taken: Dictionary):
	var dir = -Basis(f.cam_quat).z
	var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(f.cam_pos, f.cam_pos + dir * 250.0, 1))
	var reach = f.cam_pos.distance_to(hit.position) + 2.0 if hit else 250.0
	var best = null
	var best_along = reach
	for n in _enemies:
		if !is_instance_valid(n) or taken.has(n):
			continue
		var rel = n.global_position + Vector3(0, 0.8, 0) - f.cam_pos
		var along = rel.dot(dir)
		if along <= 0.0 or along > best_along:
			continue

		if (rel - dir * along).length() < 1.6 + along * 0.06:
			best = n
			best_along = along
	return best


func _build_health(gh: Dictionary, w: Dictionary) -> void:
	var has_hits = false
	for ev in gh.events:
		if ev[1] == "hit" and ev.size() >= 6:
			has_hits = true
			var n = _nearest(_enemies, Vector3(ev[2], ev[3], ev[4]), {}, 8.0)
			if n == null:
				n = _nearest(_enemies, Vector3(ev[2], ev[3], ev[4]), {}, 20.0)
			if n:
				if !w.health.has(n):
					w.health[n] = []
				w.health[n].append([ev[0], ev[5]])
	for k in w.kills:
		if !w.health.has(k[1]):
			w.health[k[1]] = []
		var steps = w.health[k[1]]
		if !has_hits:
			var space = _scene.get_world_3d().direct_space_state
			var shots = []
			for ev in gh.events:
				if ev[1] == "shot" and ev[0] < k[0] and k[0] - ev[0] < gh.tps * 20:
					if _on_line_of_fire(ghosts_mod.frame(gh, ev[0]), space, {}) == k[1]:
						shots.append(ev[0])
			var total = shots.size() + 1
			for i in shots.size():
				steps.append([shots[i], 1.0 - float(i + 1) / total])
		steps.append([k[0], 0.0])
	for n in w.health:
		w.health[n].sort_custom(func(a, b): return a[0] < b[0])


func _sync_bar(n: Node, steps: Array, tick: int) -> void:
	var bar = n.get_node_or_null("EnemyHealthBar")
	if bar == null or bar.get("max_value") == null:
		return
	var mode = int(ghosts_mod.q.s.theater_bars)
	var frac = 1.0
	var hit = false
	for st in steps:
		if st[0] > tick:
			break
		frac = st[1]
		hit = true
	var show = mode == 1 or (mode == 0 and hit)
	if bar.visible != show:
		bar.visible = show
	if !show:
		return
	var v = float(bar.max_value) * frac
	if !is_equal_approx(float(bar.value), v):
		bar.value = v

	var col = Color("#C42B47") if v < 1.0 else Color(1, 1, 1)
	if bar.progress_color != col:
		bar.progress_color = col


func _watch_runner(e: Dictionary, tt: float) -> void:
	if !ghosts_mod.q.s.theater_watch:
		return
	var f = ghosts_mod.frame(e.gh, int(floor(tt)))
	var target = f.pos
	var eye = f.pos + Vector3(0, 1.5, 0)
	var armed = (f.flags & ghosts_mod.F_UNARMED) == 0
	_los_tick = (_los_tick + 1) % 6
	var space = _scene.get_world_3d().direct_space_state
	for i in _enemies.size():
		var n = _enemies[i]
		if !is_instance_valid(n) or !n.visible or n.get("can_alert") == false:
			continue
		var dist = n.global_position.distance_to(target)
		var detect = float(n.get("DETECT_DIST")) if n.get("DETECT_DIST") != null else 20.0
		var undetect = float(n.get("UNDETECT_DIST")) if n.get("UNDETECT_DIST") != null else 25.0
		var alert = _alerted.get(n, false)
		if !alert and dist < detect and armed and i % 6 == _los_tick:
			var q = PhysicsRayQueryParameters3D.create(n.global_position + Vector3(0, 0.8, 0), eye, 1)
			alert = space.intersect_ray(q).is_empty()
		elif alert and (dist > undetect or !armed):
			alert = false
		_alerted[n] = alert

		if !alert or Vector2(target.x - n.global_position.x, target.z - n.global_position.z).length() < 0.2:
			continue
		var turret = n.get("turrettop")
		if n.get("enemy_type") == 4 and turret is Node3D:
			turret.look_at(target)
			turret.rotate_y(deg_to_rad(90))
			turret.rotation.z = clampf(turret.rotation.x, 0.0, PI / 2)
			turret.rotation.x = 0.0
		else:
			n.look_at(target)
			n.rotation.x = 0.0
