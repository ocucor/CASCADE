extends Node

# Extras page: splits, run cards, route line, practice tools and settings share / paste.


const SPLITS_PATH = "user://qol/splits.cfg"
const CARDS = "user://qol/cards/"
const CARD_DELAY = 4.0
const VISUALS = {"CRT": 0.0, "SCREEN_SHAKE": 0.0, "MOTION_BLUR": false, "HUDSWAY": false}
const DELTA_SHOW = 2.5
var GREEN = Color("4fe07a")
var RED = Color("e0494f")
const CB_GOOD = Color("4fa3ff")
const CB_BAD = Color("ff9d2e")
const GOLD = Color("ffd23f")

var q = null

var _splits = ConfigFile.new()
var _run_player_id = 0
var _run_level = ""
var _run_times = []
var _session_attempts = {}
var _session_start = 0

var _delta_layer: CanvasLayer = null
var _delta_label: Label = null
var _delta_left = 0.0
var _att_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1001
	_session_start = Time.get_ticks_msec()
	_splits.load(SPLITS_PATH)
	_build_delta()
	_build_attempts()
	_build_cross()
	_cd_label = _att_label.duplicate()
	_cd_label.name = "QolCooldowns"
	_att_label.add_sibling(_cd_label)
	_apply_palette()
	_prac_label = Label.new()
	_prac_label.text = "PRACTICE"
	_prac_label.visible = false
	_prac_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prac_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prac_label.offset_top = 6
	if _font():
		_prac_label.add_theme_font_override("font", _font())
	_prac_label.add_theme_font_size_override("font_size", 20)
	_prac_label.add_theme_color_override("font_color", RED)
	_prac_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_prac_label.add_theme_constant_override("outline_size", 4)
	_cross_layer.add_child(_prac_label)
	get_viewport().gui_focus_changed.connect(_on_focus)


func register_pages(pages: Array) -> void:
	pages.append({"mod": "QOL", "title": "SPLITS / ATTEMPTS", "build": _page})
	pages.append({"mod": "QOL", "title": "CROSSHAIR STYLE / TIMING", "build": _page_cross})
	pages.append({"mod": "QOL", "title": "PB HISTORY / SHARE", "build": _page_share})


func _page_share(api) -> void:
	api.header("PB HISTORY")
	var lvl = str(_splits.get_value("_", "last_level", ""))
	var hist: Array = _splits.get_value(lvl, "history", []) if lvl != "" else []
	if hist.is_empty():
		api.button("NO PBS YET", "PBs set with split deltas on are listed here, newest first.", "--", func(): pass)
	for i in range(hist.size() - 1, maxi(hist.size() - 8, 0) - 1, -1):
		var e = hist[i]
		var gain = "" if i == 0 else "  -%.3f" % (hist[i - 1][1] - e[1])
		api.button(lvl.to_upper() + "  " + Time.get_date_string_from_unix_time(int(e[0])), "A PB on the last level played.", q.format_time(e[1]) + gain, func(): pass)
	api.column_break()
	api.header("SHARE / ACCESSIBILITY")
	api.button("COPY SETTINGS", "Copy your QOL settings to the clipboard as a short code.", "COPY", _copy_settings)
	api.button("PASTE SETTINGS", "Apply a QOL settings code from the clipboard.", "PASTE", _paste_settings)
	api.toggle("RUN CARDS", "Save a PNG of the level complete screen to the run card folder.", q.s.x_run_cards, q._opt("x_run_cards"))
	api.button("RUN CARD FOLDER", "Open the run card folder.", "OPEN", func():
		DirAccess.make_dir_recursive_absolute(CARDS)
		OS.shell_open(ProjectSettings.globalize_path(CARDS)))
	api.toggle("REMEMBER LEVEL", "Level select focuses the level you last played when you open its chapter.", q.s.x_remember_level, q._opt("x_remember_level"))
	api.button("CLARITY PRESET", "CRT, screen shake, motion blur and HUD sway off. Your values are saved for RESTORE.", "APPLY", _clarity)
	api.button("RESTORE VISUALS", "Put back the visual settings saved by CLARITY PRESET.", "RESTORE", _restore_visuals)
	api.toggle("COLORBLIND DELTAS", "Use blue / orange instead of green / red for split deltas and jump timing.", q.s.x_colorblind, q._opt("x_colorblind"))


func _copy_settings() -> void:
	var diff = {}
	for k in q.s:
		if q.s[k] != q.DEFAULTS[k]:
			diff[k] = q.s[k]
	var raw = var_to_bytes(diff)
	DisplayServer.clipboard_set("QOL1:" + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)) + ":" + str(raw.size()))
	_show_delta("SETTINGS COPIED", GOLD)


func _paste_settings() -> void:
	var parts = DisplayServer.clipboard_get().strip_edges().split(":")
	var d = null
	if parts.size() == 3 and parts[0] == "QOL1" and parts[2].is_valid_int() and int(parts[2]) < 65536:
		var raw = Marshalls.base64_to_raw(parts[1]).decompress(int(parts[2]), FileAccess.COMPRESSION_DEFLATE)
		d = bytes_to_var(raw)
	if !(d is Dictionary):
		_show_delta("NOT A SETTINGS CODE", RED)
		return
	var n = 0
	for k in d:
		if q.DEFAULTS.has(k) and typeof(d[k]) == typeof(q.DEFAULTS[k]):
			q.set_opt(k, d[k])
			n += 1
	_show_delta("%d SETTINGS APPLIED" % n, GOLD)
	if q._hub:
		q._hub.refresh()


const CROSS_STYLES = ["GAME", "CROSS", "DOT", "CROSS + DOT", "CIRCLE", "T"]

func _page_cross(api) -> void:
	api.header("CROSSHAIR STYLE")
	api.choice("STYLE", "Replace the game crosshair with a drawn one. Color, size and opacity settings still apply.", CROSS_STYLES, q.s.x_cross_style, q._opt("x_cross_style"))
	api.slider("GAP", "Set gap from center.", 0.0, 20.0, 1.0, q.s.x_cross_gap, q._opt("x_cross_gap"))
	api.slider("LENGTH", "Set line length.", 2.0, 30.0, 1.0, q.s.x_cross_len, q._opt("x_cross_len"))
	api.slider("THICKNESS", "Set line thickness.", 1.0, 8.0, 0.5, q.s.x_cross_thick, q._opt("x_cross_thick"))
	api.toggle("OUTLINE", "Draw a dark outline around the crosshair.", q.s.x_cross_outline, q._opt("x_cross_outline"))
	api.column_break()
	api.header("TIMING")
	api.toggle("ROUTE LINE", "Draw your race ghost's path through the level. Needs a race ghost set for the level.", q.s.x_route_line, q._opt("x_route_line"))
	api.toggle("DASH / STOMP TICKS", "Show dash and stomp recharge in ticks under the attempt counter corner.", q.s.x_cd_ticks, q._opt("x_cd_ticks"))
	api.slider("SUBTITLE SIZE", "Set size of subtitles.", 0.75, 2.0, 0.05, q.s.x_sub_scale, q._opt("x_sub_scale"))
	api.toggle("PRACTICE KEYS", "F5 saves your position, F6 loads it. Loading turns the run into PRACTICE: no score, PB, ghost or leaderboard upload until you restart.", q.s.x_practice, q._opt("x_practice"))
	api.toggle("MINIMAL INPUT OVERLAY", "Show only jump, dash, stomp, shoot and aim on the input overlay.", q.s.x_overlay_min, q._opt("x_overlay_min"))
	api.toggle("JUMP TIMING", "After each jump, show ticks between landing and jumping (or how early the press was).", q.s.x_jump_timing, q._opt("x_jump_timing"))


func _page(api) -> void:
	api.header("SPLITS")
	api.toggle("SPLIT DELTAS", "Show time against your PB splits at each core and at exfil.", q.s.x_splits, q._opt("x_splits"))
	api.toggle("GOLD SEGMENTS", "Show a gold delta when a segment beats your best ever.", q.s.x_golds, q._opt("x_golds"))
	api.button("SUM OF BEST", "Sum of your best segments on the last level played.", _sob_text(), func(): pass)
	api.button("CLEAR SPLITS", "Forget saved splits for every level.", "CLEAR", func():
		_splits = ConfigFile.new()
		_splits.save(SPLITS_PATH)
		if q._hub:
			q._hub.refresh())
	api.column_break()
	api.header("ATTEMPTS / DEATH")
	api.toggle("ATTEMPT COUNTER", "Show attempts on this level, attempts this session and session play time.", q.s.x_attempts, q._opt("x_attempts"))
	api.choice("ATTEMPTS CORNER", "Set screen corner of attempt counter.", q.CORNER_NAMES, q.s.x_attempts_corner, q._opt("x_attempts_corner"))
	api.toggle("LEVEL HOP KEYS", "In the pause menu, PAGE UP / PAGE DOWN load the next / previous unlocked level.", q.s.x_level_hop, q._opt("x_level_hop"))
	api.slider("PLAYER SOUNDS", "Set volume of your own movement sounds (jump, dash, stomp, land) relative to SFX.", 0.0, 2.0, 0.05, q.s.x_suit_vol, q._opt("x_suit_vol"))
	api.toggle("F8 KEEPS LAST RUN", "Press F8 to pin the last recorded run so ghost cleanup never deletes it.", q.s.x_pin_key, q._opt("x_pin_key"))
	api.slider("KEEP NEAR-PB RUNS", "Never clean up finished runs within this many seconds of your best. 0 = off.", 0.0, 5.0, 0.25, q.s.x_keep_near, q._opt("x_keep_near"))


func on_setting(key: String) -> void:
	match key:
		"x_colorblind":
			_apply_palette()
		"x_attempts_corner":
			if q._hub and _att_label:
				q._hub.corner_add(q.CORNER_IDS[q.s.x_attempts_corner], _att_label)


func _exit_tree() -> void:
	for k in ["qol_practice"]:
		if Engine.has_meta(k):
			Engine.remove_meta(k)


func _process(delta: float) -> void:
	var g = get_node_or_null("/root/global")
	var ui = get_node_or_null("/root/UI")
	if g == null or ui == null:
		return
	var p = g.get("_player")
	if ui.get("_timerstart") == true and is_instance_valid(p) and p.get_instance_id() != _run_player_id:
		_new_attempt(g, p)
	if _delta_left > 0.0:
		_delta_left -= delta
		_delta_label.modulate.a = clampf(_delta_left / 0.4, 0.0, 1.0)
		_delta_layer.visible = _delta_left > 0.0
	_update_attempts(g, ui)
	_update_suit_volume()
	_update_cross(ui)
	_update_route()
	_update_overlay(ui)
	_prac_label.visible = practice
	_update_cd(g)
	for n in ["_subtitles", "_subtitlesjoy"]:
		var sub = ui.get(n)
		if sub is Control and sub.scale.x != q.s.x_sub_scale:
			sub.pivot_offset = sub.size * Vector2(0.5, 1.0)
			sub.scale = Vector2.ONE * q.s.x_sub_scale


var _suit_applied = 1.0

func _update_suit_volume() -> void:
	var m = q.s.x_suit_vol
	if is_equal_approx(m, 1.0) and is_equal_approx(_suit_applied, 1.0):
		return
	var cfg = get_node_or_null("/root/Config")
	if cfg == null or cfg.get("SFX_VOLUME") == null:
		return
	var db = linear_to_db(pow(float(cfg.SFX_VOLUME), 2.0) * m)
	for bus in ["SFX_Suit", "UI_Suit"]:
		var i = AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, db)
	_suit_applied = m


func _unhandled_key_input(event: InputEvent) -> void:
	if !(event is InputEventKey) or !event.pressed or event.echo:
		return
	if (event.keycode == KEY_F5 or event.keycode == KEY_F6) and q.s.x_practice and !get_tree().paused:
		_practice_key(event.keycode == KEY_F5)
	elif event.keycode == KEY_F8 and q.s.x_pin_key:
		_pin_last()
	elif (event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN) and q.s.x_level_hop:
		_level_hop(1 if event.keycode == KEY_PAGEUP else -1)


func is_pinned(path: String) -> bool:
	return (_splits.get_value("_", "pinned", []) as Array).has(path)


func _pin_last() -> void:
	var path = q.ghosts.last_saved if q.ghosts else ""
	if path == "":
		_show_delta("NO RUN TO KEEP", RED)
		return
	var pins: Array = _splits.get_value("_", "pinned", [])
	if !pins.has(path):
		pins.append(path)
		_splits.set_value("_", "pinned", pins)
		_splits.save(SPLITS_PATH)
	_show_delta("RUN KEPT", GOLD)


func _level_hop(dir: int) -> void:
	var pause = get_node_or_null("/root/UI/Pause")
	var g = get_node_or_null("/root/global")
	var saves = get_node_or_null("/root/saves")
	if pause == null or !pause.visible or !get_tree().paused or g == null or saves == null or g.get("levelrush") == 1:
		return
	var lvls: Array = saves._lvls
	var i = lvls.find(g.currentlevel)
	if i < 0:
		return
	var j = i + dir
	while j >= 0 and j < lvls.size():
		var lv = lvls[j]

		if g.get("unlockall") or saves._get_points(lv) != -1 or (j > 0 and saves._get_points(lvls[j - 1]) != -1):
			if g.level_data.has(lv):
				break
		j += dir
	if j < 0 or j >= lvls.size():
		return
	var audio = get_node_or_null("/root/Audio")
	if audio:
		audio.reverb_trigger = 0
		audio.music_mult = 0.0
	pause._unpausecommon()
	g.showdeploying = true
	g._setlevel(lvls[j], true)


func _new_attempt(g, p) -> void:
	_run_player_id = p.get_instance_id()
	_set_practice(false)
	_run_level = str(g.currentlevel)
	_run_times = []
	if g.get("levelrush") == 1:
		return
	_session_attempts[_run_level] = _session_attempts.get(_run_level, 0) + 1
	_splits.set_value(_run_level, "attempts", int(_splits.get_value(_run_level, "attempts", 0)) + 1)
	_splits.save(SPLITS_PATH)


func on_stat(stat: String) -> void:
	if (stat != "stCore" and stat != "stExfil") or practice:
		return
	var g = get_node_or_null("/root/global")
	if g == null or g.get("levelrush") == 1 or str(g.currentlevel) != _run_level:
		return
	var t = float(g.time)
	var i = _run_times.size()
	_run_times.append(t)
	var pb: Array = _splits.get_value(_run_level, "pb", [])
	var golds: Array = _splits.get_value(_run_level, "gold", [])
	var seg = t - (_run_times[i - 1] if i > 0 else 0.0)
	var is_gold = i >= golds.size() or seg < golds[i] - 0.0001
	if is_gold:
		while golds.size() <= i:
			golds.append(INF)
		golds[i] = seg
		_splits.set_value(_run_level, "gold", golds)
	if q.s.x_splits and i < pb.size():
		var d = t - pb[i]
		var c = GOLD if (is_gold and q.s.x_golds) else (GREEN if d < 0.0 else RED)
		_show_delta(("-" if d < 0.0 else "+") + "%.3f" % absf(d), c)
	if stat == "stExfil" and (pb.is_empty() or t < pb[pb.size() - 1]):
		_splits.set_value(_run_level, "pb", _run_times.duplicate())
		var hist: Array = _splits.get_value(_run_level, "history", [])
		hist.append([int(Time.get_unix_time_from_system()), t])
		_splits.set_value(_run_level, "history", hist)
	_splits.set_value("_", "last_level", _run_level)
	_splits.save(SPLITS_PATH)
	if stat == "stExfil" and q.s.x_run_cards:
		_run_card(_run_level, t)


func _sob_text() -> String:
	var lvl = str(_splits.get_value("_", "last_level", ""))
	var golds: Array = _splits.get_value(lvl, "gold", []) if lvl != "" else []
	if golds.is_empty():
		return "--"
	var sum = 0.0
	for x in golds:
		sum += x
	return q.format_time(sum)


func _font():
	return load("res://Assets/Fonts/bitpop.otf") if ResourceLoader.exists("res://Assets/Fonts/bitpop.otf") else null


func _build_delta() -> void:
	_delta_layer = CanvasLayer.new()
	_delta_layer.layer = 127
	_delta_layer.visible = false
	add_child(_delta_layer)
	_delta_label = Label.new()
	_delta_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delta_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_delta_label.anchor_top = 0.2
	_delta_label.anchor_bottom = 0.2
	_delta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f = _font()
	if f:
		_delta_label.add_theme_font_override("font", f)
	_delta_label.add_theme_font_size_override("font_size", 32)
	_delta_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_delta_label.add_theme_constant_override("outline_size", 4)
	_delta_layer.add_child(_delta_label)


func _show_delta(text: String, c: Color) -> void:
	_delta_label.text = text
	_delta_label.add_theme_color_override("font_color", c)
	_delta_left = DELTA_SHOW
	_delta_layer.visible = true


func _build_attempts() -> void:
	_att_label = Label.new()
	_att_label.name = "QolAttempts"
	_att_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_att_label.visible = false
	var f = _font()
	if f:
		_att_label.add_theme_font_override("font", f)
	_att_label.add_theme_font_size_override("font_size", 16)
	_att_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_att_label.add_theme_constant_override("outline_size", 3)
	if q._hub:
		q._hub.corner_add(q.CORNER_IDS[q.s.x_attempts_corner], _att_label)
	else:
		var layer = CanvasLayer.new()
		layer.layer = 128
		add_child(layer)
		layer.add_child(_att_label)


func _update_attempts(g, ui) -> void:
	var show = q.s.x_attempts and _run_level != "" and ui.get("_ui") != null and ui._ui.is_visible_in_tree() \
			and str(g.currentlevel) == _run_level
	_att_label.visible = show
	if !show:
		return
	var secs = (Time.get_ticks_msec() - _session_start) / 1000
	_att_label.text = "ATTEMPT %d  /  SESSION %d  /  %d:%02d:%02d" % [
		int(_splits.get_value(_run_level, "attempts", 0)), _session_attempts.get(_run_level, 0),
		secs / 3600, (secs / 60) % 60, secs % 60]


var _was_floor = true
var _land_tick = -1
var _early_tick = -1
var _tick = 0

func _physics_process(_delta: float) -> void:
	if !q.s.x_jump_timing or get_tree().paused:
		return
	_tick += 1
	var g = get_node_or_null("/root/global")
	var p = g.get("_player") if g else null
	if !is_instance_valid(p) or !p.has_method("is_on_floor"):
		return
	var floor = p.is_on_floor()
	var pressed = Input.is_action_just_pressed("jump")
	if floor and !_was_floor:
		_land_tick = _tick
		if _early_tick >= 0 and _tick - _early_tick <= 15:
			_show_delta("EARLY %dt" % (_tick - _early_tick), RED)
		_early_tick = -1
	if pressed:
		if floor or _was_floor:
			var d = _tick - _land_tick if _land_tick >= 0 else 99
			if d <= 30:
				_show_delta("JUMP %dt" % d, GOLD if d == 0 else (GREEN if d <= 2 else RED))
		else:
			_early_tick = _tick
	_was_floor = floor


var _cross_layer: CanvasLayer = null
var _cross: Control = null

func _build_cross() -> void:
	_cross_layer = CanvasLayer.new()
	_cross_layer.layer = 126
	add_child(_cross_layer)
	_cross = Control.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.draw.connect(_draw_cross)
	_cross_layer.add_child(_cross)


func _update_cross(ui) -> void:
	var gc = ui.get("_crosshair")
	var on = q.s.x_cross_style > 0 and gc is CanvasItem and gc.is_visible_in_tree()
	_cross.visible = on
	if on:

		gc.modulate.a = 0.0
		gc.set_meta("qol_a_out", 0.0)
		var dot = ui.get("_crosshairdot")
		if dot is CanvasItem:
			dot.modulate.a = 0.0
		_cross.queue_redraw()


func _draw_cross() -> void:
	var c: Color = q.s.cross_color
	c.a *= q.s.cross_opacity
	var k = q.s.cross_scale
	var ctr = _cross.size * 0.5
	var gap = q.s.x_cross_gap * k
	var ln = q.s.x_cross_len * k
	var th = q.s.x_cross_thick * k
	var st = q.s.x_cross_style
	var passes = [[Color(0, 0, 0, c.a * 0.8), th + 2.0], [c, th]] if q.s.x_cross_outline else [[c, th]]
	for ps in passes:
		var col: Color = ps[0]
		var w: float = ps[1]
		if st == 1 or st == 3 or st == 5:
			var dirs = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN] if st == 5 else [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
			for d in dirs:
				_cross.draw_line(ctr + d * gap, ctr + d * (gap + ln), col, w)
		if st == 2 or st == 3:
			_cross.draw_circle(ctr, w * 0.75, col)
		if st == 4:
			_cross.draw_arc(ctr, gap + ln * 0.5, 0.0, TAU, 48, col, w, true)


func _apply_palette() -> void:
	GREEN = CB_GOOD if q.s.x_colorblind else Color("4fe07a")
	RED = CB_BAD if q.s.x_colorblind else Color("e0494f")


func _run_card(level: String, t: float) -> void:
	await get_tree().create_timer(CARD_DELAY, true, false, true).timeout
	var img = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(CARDS)
	var path = CARDS + "%s_%d_%s.png" % [level, roundi(t * 1000.0), Time.get_datetime_string_from_system().replace(":", "-")]
	if img and img.save_png(path) == OK:
		print("[qol] run card saved " + path)


var _focused_panels = {}

func _on_focus(c: Control) -> void:
	if !q.s.x_remember_level or c == null or c.name != "LevelButton":
		return
	var btn = c.get_parent()
	var panel = btn.get_parent() if btn else null
	var g = get_node_or_null("/root/global")
	if panel == null or g == null or btn.get("level") == null or _focused_panels.has(panel.get_instance_id()):
		return
	_focused_panels[panel.get_instance_id()] = true
	if btn.level == g.currentlevel:
		return
	for b in panel.get_children():
		if b.get("level") == g.currentlevel and b.has_node("LevelButton"):
			b.get_node("LevelButton").call_deferred("grab_focus")
			return


func _clarity() -> void:
	var cfg = get_node_or_null("/root/Config")
	if cfg == null:
		return
	if !_splits.has_section_key("_", "vis_saved"):
		var saved = {}
		for k in VISUALS:
			saved[k] = cfg.get(k)
		_splits.set_value("_", "vis_saved", saved)
		_splits.save(SPLITS_PATH)
	_set_visuals(cfg, VISUALS)
	_show_delta("CLARITY ON", GOLD)


func _restore_visuals() -> void:
	var cfg = get_node_or_null("/root/Config")
	var saved = _splits.get_value("_", "vis_saved", null)
	if cfg == null or !(saved is Dictionary):
		_show_delta("NOTHING TO RESTORE", RED)
		return
	_set_visuals(cfg, saved)
	_splits.erase_section_key("_", "vis_saved")
	_splits.save(SPLITS_PATH)
	_show_delta("VISUALS RESTORED", GOLD)


func _set_visuals(cfg, vals: Dictionary) -> void:
	for k in vals:
		if VISUALS.has(k) and cfg.get(k) != null:
			cfg.set(k, vals[k])
	if cfg.has_signal("crt_changed"):
		cfg.crt_changed.emit()
	if cfg.has_method("_save"):
		cfg._save()


var _cd_label: Label = null

func _update_cd(g) -> void:
	var p = g.get("_player")
	var show = q.s.x_cd_ticks and is_instance_valid(p) and p.get("dash_timer") != null and _att_label.get_parent() != null
	if _cd_label.get_parent() != _att_label.get_parent() and _att_label.get_parent():
		_cd_label.reparent(_att_label.get_parent())
	_cd_label.visible = show
	if show:
		_cd_label.text = "DASH %3dt  /  STOMP %3dt" % [p.dash_timer, p.stomp_timer]


var _route: MeshInstance3D = null
var _route_gh = null

func _update_route() -> void:
	var race = q.ghosts.get("_race") if q.ghosts else null
	var gh = race.gh if race and q.s.x_route_line else null
	if is_same(gh, _route_gh) and (gh == null or is_instance_valid(_route)):
		return
	if is_instance_valid(_route):
		_route.queue_free()
	_route = null
	_route_gh = gh
	if gh == null or race.scene == null:
		return
	var mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(0, gh.ticks, 3):
		mesh.surface_add_vertex(q.ghosts.frame(gh, i).pos + Vector3(0, 0.2, 0))
	mesh.surface_end()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(GOLD, 0.6)
	_route = MeshInstance3D.new()
	_route.mesh = mesh
	_route.material_override = mat
	_route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	race.scene.add_child(_route)


var practice = false
var _state = null
var _prac_label: Label = null

func _set_practice(on: bool) -> void:
	practice = on
	Engine.set_meta("qol_practice", on)


func _practice_key(save: bool) -> void:
	var g = get_node_or_null("/root/global")
	var p = g.get("_player") if g else null
	if !is_instance_valid(p) or g.get("levelrush") == 1 or !p.has_node("Head"):
		return
	if save:
		_state = {"level": str(g.currentlevel), "xf": p.global_transform, "vel": p.velocity,
			"head": p.get_node("Head").rotation, "time": float(g.time)}
		_show_delta("STATE SAVED", GOLD)
		return
	if _state == null or _state.level != str(g.currentlevel):
		_show_delta("NO STATE FOR THIS LEVEL", RED)
		return
	if !practice:
		_set_practice(true)

		if q.ghosts and q.ghosts.get("_rec"):
			q.ghosts._rec = false
			q.ghosts._rec_done_id = p.get_instance_id()
	p.global_transform = _state.xf
	p.velocity = _state.vel
	p.get_node("Head").rotation = _state.head
	g.time = _state.time
	_show_delta("STATE LOADED", GOLD)


func _update_overlay(ui) -> void:
	var ov = ui.get("_inputoverlay")
	if ov == null:
		return
	for n in ["Left", "Up", "Down", "Right"]:
		var b = ov.get_node_or_null(n)
		if b is CanvasItem:
			b.visible = !q.s.x_overlay_min
