extends Node

# CICADAMATA QOL. GDPatch loads this as a mod node; patcher.lua patches the game in memory.
# Settings live in user://qol.cfg; pages show under Options > MODS (settings_hub.gd).


const MOD_ID = "qol"
const SETTINGS_PATH = "user://qol.cfg"
const PORTRAIT_DIR = "user://qol/portraits/"
const PORTRAIT_KINDS = ["default", "damage", "zoned", "starstruck"]
const TEMPLATE_PACK = "_template (game)"
const EXAMPLE_PACK = "example (mono)"


const LATCH_ACTIONS = ["jump", "dash", "stomp", "shoot", "aim", "restart"]
const BUFFERED_ACTIONS = ["jump", "dash", "stomp", "shoot"]
const MAX_QUEUED = 2

const TIMER_FORMATS = ["MM:SS.MMM (GAME)", "SS.MMM", "MM:SS.CC", "H:MM:SS.MMM", "MM:SS.MMM + TICKS"]
const CORNER_IDS = ["top_left", "top_right", "bottom_left", "bottom_right"]
const CORNER_NAMES = ["TOP LEFT", "TOP RIGHT", "BOTTOM LEFT", "BOTTOM RIGHT"]
const FPS_DETAILS = ["FPS", "FPS + MS", "FPS + MS + 1% LOW", "ALL + GRAPH"]
const FAST_MENU_NAMES = ["OFF", "1.5X", "2X", "3X"]
const FAST_MENU_SPEEDS = [1.0, 1.5, 2.0, 3.0]


const FAST_MENU_SCENES = ["menu.tscn", "pause.tscn", "options.tscn", "death_screen.tscn", "level_complete.tscn",
	"chaptercomplete.tscn", "deploy_screen.tscn", "level_transition.tscn", "loading_screen.tscn",
	"unlock_notif.tscn", "newgame.tscn"]

const GAME_TIMER_COLOR = Color(0.627451, 0.627451, 0.627451, 1)
const GAME_OVERLAY_ON = Color(0.627451, 0.627451, 0.627451, 1)
const GAME_OVERLAY_OFF = Color(0.627451, 0.627451, 0.627451, 0.1)

const DEFAULTS = {
	"input_fix": true,
	"fast_menus": 0,
	"input_buffer": 0,
	"timer_tick_fix": true,
	"timer_format": 0,
	"timer_color": GAME_TIMER_COLOR,
	"timer_scale": 1.0,
	"timer_pb": false,
	"hide_hud": false,
	"hide_cross": false,
	"hud_opacity": 1.0,
	"hud_scale": 1.0,
	"hud_tint": Color(1, 1, 1),
	"overlay_on": GAME_OVERLAY_ON,
	"overlay_off": GAME_OVERLAY_OFF,
	"cross_color": Color(1, 1, 1),
	"cross_scale": 1.0,
	"cross_opacity": 1.0,
	"hit_color": Color(1, 1, 1),
	"port_scale": 1.0,
	"port_opacity": 1.0,
	"port_motion": true,
	"port_custom": false,
	"port_pack": "",
	"ui_vel_color": Color(1, 1, 1),
	"ui_jump_color": Color(1, 1, 1),
	"ui_points_color": Color(1, 1, 1),
	"ui_health_color": Color(1, 1, 1),
	"ui_bars_color": Color(1, 1, 1),
	"ui_level_color": Color(1, 1, 1),
	"ui_timerbox_color": Color(1, 1, 1),
	"ui_flash_alpha": 1.0,
	"ui_lowhp_alpha": 1.0,
	"ui_speedlines_alpha": 1.0,
	"ui_hitmarker_size": 1.0,
	"fps_on": false,
	"fps_corner": 0,
	"fps_detail": 1,
	"fps_color": Color(1, 1, 1, 0.85),
	"fps_size": 16,
	"hide_compass": false,
	"hide_velocity": false,
	"hide_level": false,
	"hide_points": false,
	"hide_timer": false,
	"hide_jumps": false,
	"hide_cores": false,
	"ghost_record": true,
	"ghost_save_deaths": true,
	"ghost_keep": 10,
	"ghost_race": true,
	"ghost_race_alpha": 0.6,
	"theater_bars": 0,
	"theater_watch": true,
	"x_splits": false,
	"x_golds": true,
	"x_attempts": false,
	"x_attempts_corner": 2,
	"x_level_hop": false,
	"x_suit_vol": 1.0,
	"x_pin_key": false,
	"x_keep_near": 0.0,
	"x_jump_timing": false,
	"x_cross_style": 0,
	"x_cross_gap": 4.0,
	"x_cross_len": 8.0,
	"x_cross_thick": 2.0,
	"x_cross_outline": true,
	"x_colorblind": false,
	"x_remember_level": false,
	"x_run_cards": false,
	"x_route_line": false,
	"x_cd_ticks": false,
	"x_sub_scale": 1.0,
	"x_practice": false,
	"x_overlay_min": false,
}


const HIDEABLE = {
	"hide_compass": ["UI/compass"],
	"hide_velocity": ["UI/VelocityCounter", "UI/VelocityYPlusBar", "UI/VelocityYMinusBar"],
	"hide_level": ["UI/LevelDisplay"],
	"hide_points": ["UI/PointsBG", "UI/PointsWhite"],
	"hide_timer": ["UI/TimerBG", "UI/TimerBGRush"],
	"hide_jumps": ["UI/jumpcounterbg"],
	"hide_cores": ["UI/CoreCount"],
}

const OVERLAY_BUTTONS = {
	"Stomp": "stomp", "Left": "left", "Up": "forward", "Down": "back", "Right": "right",
	"Dash": "dash", "Jump": "jump", "Shoot": "shoot", "Aim": "aim",
}

var s = {}

var _pending = {}
var _held = {}
var _was_paused = false

var _hub = null
var ghosts = null
var theater = null
var extras = null
var _fps_box: VBoxContainer = null
var _fps_label: Label = null
var _fps_graph: Control = null
var _frame_ms = PackedFloat32Array()
var _fps_acc = 0.0
var _fps_frames = 0

var _fast_players = []
var _time_scaled = false
var _dirty = false
var _dirty_since = 0

var _custom_ports = {}
var _pb_label: Label = null
var _pb_level = ""
var _pb_time = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	_load_settings()
	Engine.set_meta("qol_input", self)
	Engine.set_meta("qol", self)

	_hub = Engine.get_meta("gdpatch_settings_hub") if Engine.has_meta("gdpatch_settings_hub") else null
	if _hub == null or !is_instance_valid(_hub):
		_hub = load("res://gdpatch/mods/qol/settings_hub.gd").new()
		add_child(_hub)

	var pages = Engine.get_meta("gdpatch_settings_pages", [])
	pages.append({"mod": "QOL", "title": "INPUT / TIMER", "build": _page_input_timer})
	pages.append({"mod": "QOL", "title": "HUD / CROSSHAIR", "build": _page_hud})
	pages.append({"mod": "QOL", "title": "PORTRAIT / FPS METER", "build": _page_portrait_fps})
	pages.append({"mod": "QOL", "title": "UI COLORS / EFFECTS", "build": _page_ui})
	pages.append({"mod": "QOL", "title": "HUD ELEMENTS", "build": _page_elements})

	ghosts = load("res://gdpatch/mods/qol/ghosts.gd").new()
	ghosts.name = "Ghosts"
	ghosts.q = self
	theater = load("res://gdpatch/mods/qol/theater.gd").new()
	theater.name = "Theater"
	theater.ghosts_mod = ghosts
	ghosts.theater = theater
	add_child(ghosts)
	add_child(theater)
	ghosts.register_pages(pages)
	extras = load("res://gdpatch/mods/qol/extras.gd").new()
	extras.name = "Extras"
	extras.q = self
	add_child(extras)
	extras.register_pages(pages)
	Engine.set_meta("gdpatch_settings_pages", pages)

	_migrate_portraits()
	_load_custom_portraits()
	_sync_gdpatch_config()
	get_tree().node_added.connect(_on_node_added_fast)
	_scan_fast(get_tree().root)
	print("[qol] ready. input fix=%s buffer=%d" % [s.input_fix, s.input_buffer])


func _exit_tree() -> void:
	if _dirty:
		_save_settings()
	if _time_scaled:
		Engine.time_scale = 1.0
	for k in ["qol", "qol_input", "qol_ghost", "qol_theater", "gdpatch_settings_hub", "gdpatch_settings_pages"]:
		if Engine.has_meta(k):
			Engine.remove_meta(k)


func _load_settings() -> void:
	s = DEFAULTS.duplicate()
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in DEFAULTS:
			var v = cfg.get_value("qol", k, DEFAULTS[k])
			if typeof(v) == typeof(DEFAULTS[k]) or (DEFAULTS[k] is float and v is int):
				s[k] = v


func _migrate_portraits() -> void:
	if !s.port_custom or s.port_pack != "":
		return
	var found = false
	for kind in PORTRAIT_KINDS:
		var src = PORTRAIT_DIR + kind + ".png"
		if FileAccess.file_exists(src):
			DirAccess.make_dir_recursive_absolute(PORTRAIT_DIR + "custom")
			DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(PORTRAIT_DIR + "custom/" + kind + ".png"))
			found = true
	s.port_custom = false
	if found:
		s.port_pack = "custom"
	_save_settings()


func _save_settings() -> void:
	var cfg = ConfigFile.new()
	for k in s:
		cfg.set_value("qol", k, s[k])
	cfg.save(SETTINGS_PATH)


func set_opt(key: String, value) -> void:
	if DEFAULTS[key] is int:
		value = int(value)
	elif DEFAULTS[key] is float:
		value = float(value)
	s[key] = value

	_dirty = true
	_dirty_since = Time.get_ticks_msec()
	match key:
		"fast_menus":
			_apply_fast_all()
		"timer_tick_fix":
			_sync_gdpatch_config()
		"fps_corner":
			if _fps_box and _hub:
				_hub.corner_add(CORNER_IDS[s.fps_corner], _fps_box)
		"fps_size", "fps_color", "fps_detail":
			_style_fps()
		"port_pack":
			_load_custom_portraits()
	if key.begins_with("x_") and extras:
		extras.on_setting(key)


func _opt(key: String) -> Callable:
	return func(v): set_opt(key, v)


func _sync_gdpatch_config() -> void:
	var gdpatch = get_node_or_null("/root/GDPatch")
	if gdpatch and gdpatch.has_method("set_config_option"):
		gdpatch.set_config_option(MOD_ID, "timer", "tick_accurate", s.timer_tick_fix)


func _page_input_timer(api) -> void:
	api.header("INPUT")
	api.toggle("INPUT FIX", "Prevent dropped jump, dash, stomp, shoot, aim and restart inputs.", s.input_fix, _opt("input_fix"))
	api.choice("FAST MENUS", "Set speed of menu transitions. Does not affect gameplay.", FAST_MENU_NAMES, s.fast_menus, _opt("fast_menus"))
	api.slider("INPUT BUFFER", "Set how many frames an early jump, dash, stomp or shot is held until it can happen. 0 matches the base game.", 0, 8, 1, s.input_buffer, _opt("input_buffer"))
	api.column_break()
	api.header("TIMER")
	api.choice("TIMER FORMAT", "Set in-game timer format. Results screens are unaffected.", TIMER_FORMATS, s.timer_format, _opt("timer_format"))
	api.color("TIMER COLOR", "Set color of in-game timer.", s.timer_color, _opt("timer_color"))
	api.slider("TIMER SIZE", "Set size of in-game timer.", 0.5, 2.0, 0.05, s.timer_scale, _opt("timer_scale"))
	api.toggle("PB UNDER TIMER", "Show personal best time below in-game timer.", s.timer_pb, _opt("timer_pb"))
	api.toggle("TICK-EXACT TIMES", "Toggle frame-accurate time display. Applies after restarting the game.", s.timer_tick_fix, _opt("timer_tick_fix"))


func _page_hud(api) -> void:
	api.header("HUD")
	api.toggle("HIDE HUD", "Hide the whole in-game HUD.", s.hide_hud, _opt("hide_hud"))
	api.slider("HUD OPACITY", "Set opacity of in-game HUD.", 0.1, 1.0, 0.05, s.hud_opacity, _opt("hud_opacity"))
	api.slider("HUD SIZE", "Set size of in-game HUD.", 0.6, 1.2, 0.05, s.hud_scale, _opt("hud_scale"))
	api.color("HUD TINT", "Set color tint of in-game HUD.", s.hud_tint, _opt("hud_tint"))
	api.color("INPUT OVERLAY ON", "Set color of held buttons on input overlay.", s.overlay_on, _opt("overlay_on"))
	api.color("INPUT OVERLAY OFF", "Set color of released buttons on input overlay.", s.overlay_off, _opt("overlay_off"))
	api.column_break()
	api.header("CROSSHAIR")
	api.toggle("HIDE CROSSHAIR", "Hide the in-game crosshair.", s.hide_cross, _opt("hide_cross"))
	api.color("CROSSHAIR COLOR", "Set color of in-game crosshair.", s.cross_color, _opt("cross_color"))
	api.slider("CROSSHAIR SIZE", "Set size of in-game crosshair.", 0.5, 2.0, 0.05, s.cross_scale, _opt("cross_scale"))
	api.slider("CROSSHAIR OPACITY", "Set opacity of in-game crosshair.", 0.1, 1.0, 0.05, s.cross_opacity, _opt("cross_opacity"))
	api.color("HITMARKER COLOR", "Set color of hitmarkers.", s.hit_color, _opt("hit_color"))


func _page_portrait_fps(api) -> void:
	api.header("PORTRAIT")
	api.slider("PORTRAIT SIZE", "Set size of HUD portrait.", 0.5, 1.5, 0.05, s.port_scale, _opt("port_scale"))
	api.slider("PORTRAIT OPACITY", "Set opacity of HUD portrait.", 0.0, 1.0, 0.05, s.port_opacity, _opt("port_opacity"))
	api.toggle("PORTRAIT MOTION", "Toggle HUD portrait sway and shake.", s.port_motion, _opt("port_motion"))
	_ensure_portrait_baseline()
	var packs = portrait_packs()
	var names = ["GAME"]
	for pk in packs:
		names.append(pk.to_upper())
	api.choice("PORTRAIT PACK", "Set HUD portrait images. Each pack is a folder in the portrait folder.", names, packs.find(s.port_pack) + 1, _choose_pack.bind(packs), _pack_preview.bind(packs))
	api.button("PORTRAIT FOLDER", "Open the portrait folder.", "OPEN", _open_portrait_folder)
	api.button("RELOAD PORTRAITS", "Reload portrait packs after adding or editing images.", "RELOAD", func():
		_load_custom_portraits()
		if _hub:
			_hub.refresh())
	api.column_break()
	api.header("FPS METER")
	api.toggle("FPS METER", "Show frames per second on screen.", s.fps_on, _opt("fps_on"))
	api.choice("FPS CORNER", "Set screen corner of FPS meter.", CORNER_NAMES, s.fps_corner, _opt("fps_corner"))
	api.choice("FPS DETAIL", "Set amount of information shown on FPS meter.", FPS_DETAILS, s.fps_detail, _opt("fps_detail"))
	api.color("FPS COLOR", "Set color of FPS meter.", s.fps_color, _opt("fps_color"))
	api.slider("FPS TEXT SIZE", "Set text size of FPS meter.", 10, 40, 1, s.fps_size, _opt("fps_size"))


func _page_ui(api) -> void:
	api.header("COLORS")
	api.color("VELOCITY", "Set color of velocity counter.", s.ui_vel_color, _opt("ui_vel_color"))
	api.color("JUMP COUNTER", "Set color of jump counter.", s.ui_jump_color, _opt("ui_jump_color"))
	api.color("POINTS", "Set color of points counter.", s.ui_points_color, _opt("ui_points_color"))
	api.color("HEALTH BAR", "Set color of health bar.", s.ui_health_color, _opt("ui_health_color"))
	api.color("DASH / STOMP BARS", "Set color of dash and stomp recharge bars.", s.ui_bars_color, _opt("ui_bars_color"))
	api.color("LEVEL TAG", "Set color of level name display.", s.ui_level_color, _opt("ui_level_color"))
	api.color("TIMER BOX", "Set color of timer background.", s.ui_timerbox_color, _opt("ui_timerbox_color"))
	api.column_break()
	api.header("EFFECTS")
	api.slider("SCREEN FLASHES", "Set intensity of screen flashes on gameplay events.", 0.0, 1.0, 0.05, s.ui_flash_alpha, _opt("ui_flash_alpha"))
	api.slider("LOW HEALTH VIGNETTE", "Set intensity of low health screen effect.", 0.0, 1.0, 0.05, s.ui_lowhp_alpha, _opt("ui_lowhp_alpha"))
	api.slider("SPEED LINES", "Set intensity of speed lines.", 0.0, 1.0, 0.05, s.ui_speedlines_alpha, _opt("ui_speedlines_alpha"))
	api.slider("HITMARKER SIZE", "Set size of hitmarkers.", 0.5, 2.0, 0.05, s.ui_hitmarker_size, _opt("ui_hitmarker_size"))


func _page_elements(api) -> void:
	api.header("SHOW / HIDE")
	api.toggle("COMPASS", "Show compass on in-game HUD.", !s.hide_compass, func(on): set_opt("hide_compass", !on))
	api.toggle("VELOCITY", "Show velocity counter on in-game HUD.", !s.hide_velocity, func(on): set_opt("hide_velocity", !on))
	api.toggle("LEVEL TAG", "Show level name on in-game HUD.", !s.hide_level, func(on): set_opt("hide_level", !on))
	api.toggle("POINTS", "Show points counter on in-game HUD.", !s.hide_points, func(on): set_opt("hide_points", !on))
	api.toggle("TIMER", "Show timer on in-game HUD.", !s.hide_timer, func(on): set_opt("hide_timer", !on))
	api.toggle("JUMP COUNTER", "Show jump counter on in-game HUD.", !s.hide_jumps, func(on): set_opt("hide_jumps", !on))
	api.toggle("CORE COUNTER", "Show core counter on in-game HUD.", !s.hide_cores, func(on): set_opt("hide_cores", !on))
	api.column_break()
	api.header("RESET")
	api.button("RESET QOL", "Reset all QOL settings to default.", "RESET", _reset_all)


func _reset_all() -> void:
	s = DEFAULTS.duplicate()
	_save_settings()
	_sync_gdpatch_config()
	if extras:
		extras.on_setting("x_attempts_corner")
	_load_custom_portraits()
	_style_fps()
	if _fps_box and _hub:
		_hub.corner_add(CORNER_IDS[s.fps_corner], _fps_box)
	if _hub:
		_hub.refresh()


func _source_key(event: InputEvent) -> String:
	if event is InputEventKey:
		return "k%d" % (event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	if event is InputEventMouseButton:
		return "m%d" % event.button_index
	if event is InputEventJoypadButton:
		return "jb%d_%d" % [event.device, event.button_index]
	if event is InputEventJoypadMotion:
		return "ja%d_%d" % [event.device, event.axis]
	if event is InputEventAction:
		return "act_" + String(event.action)
	return ""


func _input(event: InputEvent) -> void:
	if event.is_echo() or event is InputEventMouseMotion:
		return
	var key = _source_key(event)
	if key == "":
		return
	var paused = get_tree().paused
	for a in LATCH_ACTIONS:
		if !InputMap.has_action(a) or !event.is_action(a):
			continue
		if !_held.has(a):
			_held[a] = {}
		if event.is_action_pressed(a):
			if !_held[a].has(key):
				_held[a][key] = true

				if !paused:
					if !_pending.has(a):
						_pending[a] = []
					var q: Array = _pending[a]
					q.append(Engine.get_physics_frames())
					while q.size() > MAX_QUEUED:
						q.pop_front()
		elif event.is_action_released(a):
			_held[a].erase(key)


func just(action: StringName, can: bool = true) -> bool:
	if !s.input_fix:
		return Input.is_action_just_pressed(action)
	var a = String(action)
	var q: Array = _pending.get(a, [])
	if q.is_empty():
		return false
	var now = Engine.get_physics_frames()
	var buffer = s.input_buffer if BUFFERED_ACTIONS.has(a) else 0


	var life = buffer + 2
	while !q.is_empty() and now - q[0] > life:
		q.pop_front()
	if q.is_empty():
		return false
	if can or buffer == 0 or now - q[0] >= buffer:
		q.pop_front()
		return true
	return false


func _physics_process(_delta: float) -> void:
	var paused = get_tree().paused
	if paused and !_was_paused:
		_pending.clear()
	_was_paused = paused


func _process(delta: float) -> void:
	if _dirty and Time.get_ticks_msec() - _dirty_since > 400:
		_dirty = false
		_save_settings()
	_update_fast_menus()
	_update_fps(delta)
	var ui = get_node_or_null("/root/UI")
	if ui == null or ui.get("_ui") == null:
		return
	_apply_hud(ui)
	_apply_crosshair(ui)
	_apply_overlay(ui)
	_apply_portrait(ui)
	_apply_timer(ui)
	_apply_ui_extras(ui)
	_apply_hidden(ui)


func _apply_hud(ui) -> void:
	var hud: CanvasItem = ui._ui
	hud.modulate = Color(s.hud_tint.r, s.hud_tint.g, s.hud_tint.b, _scaled_alpha(hud, 0.0 if s.hide_hud else s.hud_opacity))
	if hud is Control:
		var sc = Vector2(s.hud_scale, s.hud_scale)
		if hud.scale != sc:
			hud.pivot_offset = hud.size * 0.5
			hud.scale = sc


func _apply_crosshair(ui) -> void:
	var cross = ui.get("_crosshair")
	if cross is CanvasItem:
		cross.modulate = Color(s.cross_color.r, s.cross_color.g, s.cross_color.b, _scaled_alpha(cross, 0.0 if s.hide_cross else s.cross_opacity))
		if cross is Control:
			var sc = Vector2(s.cross_scale, s.cross_scale)
			if cross.scale != sc:
				cross.pivot_offset = cross.size * 0.5
				cross.scale = sc
	var dot = ui.get("_crosshairdot")
	if dot is CanvasItem:
		dot.modulate = Color(s.cross_color, s.cross_opacity)
	for n in ["hitmarker", "hitmarkerkill", "hitmarkerglass"]:
		var hm = ui.get(n)
		if hm is CanvasItem:
			hm.self_modulate = s.hit_color


func _scaled_alpha(node: CanvasItem, factor: float) -> float:
	var cur = node.modulate.a
	if node.has_meta("qol_a_out") and is_equal_approx(cur, node.get_meta("qol_a_out")):
		cur = node.get_meta("qol_a_in")
	var out = cur * factor
	node.set_meta("qol_a_in", cur)
	node.set_meta("qol_a_out", out)
	return out


func _scaled_scale(node: Control, factor: float) -> void:
	var cur = node.scale
	if node.has_meta("qol_s_out") and cur.is_equal_approx(node.get_meta("qol_s_out")):
		cur = node.get_meta("qol_s_in")
	var out = cur * factor
	node.set_meta("qol_s_in", cur)
	node.set_meta("qol_s_out", out)
	if node.scale != out:
		node.scale = out


func _tint(node, c: Color) -> void:
	if node is CanvasItem and node.self_modulate != c:
		node.self_modulate = c


func _apply_ui_extras(ui) -> void:
	_tint(ui.get_node_or_null("UI/VelocityCounter"), s.ui_vel_color)
	_tint(ui.get_node_or_null("UI/jumpcounterbg"), s.ui_jump_color)
	_tint(ui.get_node_or_null("UI/PointsBG"), s.ui_points_color)
	_tint(ui.get_node_or_null("UI/PointsBG/Points"), s.ui_points_color)
	_tint(ui.get_node_or_null("UI/Healthbar2"), s.ui_health_color)
	_tint(ui.get_node_or_null("UI/Healthbar2/HealthBarTest"), s.ui_health_color)
	_tint(ui.get_node_or_null("UI/dash/DashBar"), s.ui_bars_color)
	_tint(ui.get_node_or_null("UI/stomp/StompBar"), s.ui_bars_color)
	_tint(ui.get_node_or_null("UI/LevelDisplay"), s.ui_level_color)
	_tint(ui.get_node_or_null("UI/TimerBG"), s.ui_timerbox_color)
	for n in ["_whiteflash", "_redflash", "_blueflash"]:
		var fl = ui.get(n)
		if fl is CanvasItem:
			fl.modulate.a = _scaled_alpha(fl, s.ui_flash_alpha)
	var vig = ui.get("_lowhealthvig")
	if vig is CanvasItem:
		vig.modulate.a = _scaled_alpha(vig, s.ui_lowhp_alpha)
	var sl = ui.get("_speedlines")
	if sl is CanvasItem:
		sl.modulate.a = _scaled_alpha(sl, s.ui_speedlines_alpha)
	var hm = ui.get("hitmarkers")
	if hm is Control:
		if s.ui_hitmarker_size != 1.0 or hm.has_meta("qol_s_out"):
			hm.pivot_offset = hm.size * 0.5
			_scaled_scale(hm, s.ui_hitmarker_size)


func _apply_overlay(ui) -> void:
	if s.overlay_on == GAME_OVERLAY_ON and s.overlay_off == GAME_OVERLAY_OFF:
		return
	var ov = ui.get("_inputoverlay")
	if ov == null or !ov.visible:
		return
	for n in OVERLAY_BUTTONS:
		var b = ov.get_node_or_null(n)
		if b is ColorRect:
			b.color = s.overlay_on if Input.is_action_pressed(OVERLAY_BUTTONS[n]) else s.overlay_off


func _apply_portrait(ui) -> void:
	var cont = ui.get("portraitcontainer")
	if cont is Control:
		cont.modulate.a = _scaled_alpha(cont, s.port_opacity)
		var sc = Vector2(s.port_scale, s.port_scale)
		if cont.scale != sc:
			cont.pivot_offset = Vector2(0, cont.size.y)
			cont.scale = sc

	var port = ui.get("portrait")
	var bg = ui.get("portraitbg")
	if !s.port_motion and port is Control and bg is Control and ui.get("def_portposx") != null:
		var p = Vector2(ui.def_portposx, ui.def_portposy)
		port.position = p
		port.rotation = 0.0
		bg.position = p - Vector2(10, 0)
		bg.rotation = 0.0

	_apply_custom_portrait(ui)


func _apply_custom_portrait(ui) -> void:
	var port = ui.get("actualport")
	var bg = ui.get("portbg")
	if !(port is TextureRect):
		return
	var tex = port.texture
	var kind = _portrait_kind(ui, tex)
	if s.port_pack != "" and !_custom_ports.is_empty():

		if kind == "" and tex and tex.has_meta("qol_custom"):
			kind = tex.get_meta("qol_custom")
		var c = _custom_ports.get(kind, _custom_ports.get("default")) if kind != "" else null
		if c and c != tex:
			port.texture = c
			if bg is TextureRect:
				bg.texture = c
	elif tex and tex.has_meta("qol_custom"):

		var orig = ui.get({"default": "current_portrait", "damage": "current_portrait_damage", "zoned": "current_portrait_zoned", "starstruck": "current_portrait_starstruck"}[tex.get_meta("qol_custom")])
		if orig:
			port.texture = orig
			if bg is TextureRect:
				bg.texture = orig


func _portrait_kind(ui, tex) -> String:
	if tex == null:
		return ""
	for kind in ["default", "damage", "zoned", "starstruck"]:
		for skin in ["0", "1"]:
			if ui.get("portrait_%s_%s" % [kind, skin]) == tex:
				return kind
	return ""


func portrait_packs() -> Array:
	var out = []
	var da = DirAccess.open(PORTRAIT_DIR)
	if da == null:
		return out
	for d in da.get_directories():
		for kind in PORTRAIT_KINDS:
			if FileAccess.file_exists(PORTRAIT_DIR + d + "/" + kind + ".png"):
				out.append(d)
				break
	out.sort()
	return out


func _load_custom_portraits() -> void:
	_custom_ports.clear()
	if s.port_pack == "":
		return
	var dir = PORTRAIT_DIR + s.port_pack + "/"
	if !DirAccess.dir_exists_absolute(dir):
		print("[qol] portrait pack not found: ", s.port_pack)
		return
	var ui = get_node_or_null("/root/UI")
	var ref_size = Vector2i.ZERO
	if ui and ui.get("portrait_default_0") is Texture2D:
		ref_size = Vector2i(ui.portrait_default_0.get_size())
	for kind in PORTRAIT_KINDS:
		var path = dir + kind + ".png"
		if !FileAccess.file_exists(path):
			continue
		var img = Image.load_from_file(path)
		if img == null or img.is_empty():
			print("[qol] could not read ", path)
			continue
		if ref_size != Vector2i.ZERO and img.get_size() != ref_size:
			img.resize(ref_size.x, ref_size.y, Image.INTERPOLATE_NEAREST)
		var tex = ImageTexture.create_from_image(img)
		tex.set_meta("qol_custom", kind)
		_custom_ports[kind] = tex
	print("[qol] portrait pack %s: %s" % [s.port_pack, _custom_ports.keys()])


func _ensure_portrait_baseline() -> void:
	var ui = get_node_or_null("/root/UI")
	if ui == null or !(ui.get("portrait_default_0") is Texture2D):
		return
	DirAccess.make_dir_recursive_absolute(PORTRAIT_DIR)
	var readme = PORTRAIT_DIR + "README.txt"
	if !FileAccess.file_exists(readme):
		var f = FileAccess.open(readme, FileAccess.WRITE)
		if f:
			f.store_string("""CICADAMATA QOL portrait packs

Every folder here is a portrait pack. Pick one under Options > MODS > QOL >
PORTRAIT / FPS METER > PORTRAIT PACK (GAME = the game's own portraits).

A pack holds up to four PNG images:
  default.png      normal
  damage.png       taking damage
  zoned.png        ZONED
  starstruck.png   STARSTRUCK
Missing images fall back to the pack's default.png, then to the game's portrait.
Images are scaled to the game's portrait size (the template's size) if they differ.

To make your own: copy "%s", rename the copy, and edit its images.
"%s" and "%s" are re-created if deleted.
Press RELOAD PORTRAITS in the menu after changing files.
 % [TEMPLATE_PACK, TEMPLATE_PACK, EXAMPLE_PACK])
	var sources = {"default": "portrait_default_0", "damage": "portrait_damage_0", "zoned": "portrait_zoned_0", "starstruck": "portrait_starstruck_0"}
	for pack in [TEMPLATE_PACK, EXAMPLE_PACK]:
		var dir = PORTRAIT_DIR + pack + "/"
		if DirAccess.dir_exists_absolute(dir):
			continue
		DirAccess.make_dir_recursive_absolute(dir)
		for kind in sources:
			var tex = ui.get(sources[kind])
			if !(tex is Texture2D):
				continue
			var img: Image = tex.get_image()
			if img == null:
				continue
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if pack == EXAMPLE_PACK:
				img.adjust_bcs(1.0, 1.35, 0.0)
			img.save_png(dir + kind + ".png")
		print("[qol] portrait baseline written: ", dir)


func _choose_pack(i: int, packs: Array) -> void:
	set_opt("port_pack", "" if i <= 0 else packs[i - 1])


func _pack_preview(i: int, packs: Array) -> Dictionary:
	return _portrait_preview("" if i <= 0 or i > packs.size() else packs[i - 1])


var _preview_cache = {}


func _portrait_preview(pack: String) -> Dictionary:
	var ui = get_node_or_null("/root/UI")
	var game = {}
	if ui:
		for kind in PORTRAIT_KINDS:
			var key = "current_portrait" if kind == "default" else "current_portrait_" + kind
			var tex = ui.get(key)
			if !(tex is Texture2D):
				tex = ui.get("portrait_%s_0" % kind)
			game[kind] = tex
	var images = []
	var labels = []
	for kind in PORTRAIT_KINDS:
		var tex = null
		var note = ""
		if pack != "":
			tex = _preview_tex(PORTRAIT_DIR + pack + "/" + kind + ".png")
			if tex == null:
				tex = _preview_tex(PORTRAIT_DIR + pack + "/default.png")
				note = " (DEFAULT)" if tex else ""
			if tex == null:
				note = " (GAME)"
		if tex == null:
			tex = game.get(kind)
		images.append(tex)
		labels.append(kind.to_upper() + note)
	return {"title": "PREVIEW  /  " + ("GAME" if pack == "" else pack.to_upper()), "images": images, "labels": labels}


func _preview_tex(path: String):
	if !FileAccess.file_exists(path):
		return null
	var mt = FileAccess.get_modified_time(path)
	if _preview_cache.has(path) and _preview_cache[path][0] == mt:
		return _preview_cache[path][1]
	var img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var tex = ImageTexture.create_from_image(img)
	_preview_cache[path] = [mt, tex]
	return tex


func _open_portrait_folder() -> void:
	DirAccess.make_dir_recursive_absolute(PORTRAIT_DIR)
	OS.shell_open(ProjectSettings.globalize_path(PORTRAIT_DIR))


func _ticks(t: float) -> int:
	return roundi(t * Engine.get_physics_ticks_per_second())


func format_time(t: float) -> String:
	var tps = Engine.get_physics_ticks_per_second()
	var ticks = _ticks(maxf(t, 0.0))
	var ms_total = (ticks * 1000) / tps
	var ms = ms_total % 1000
	var sec_total = ms_total / 1000
	match s.timer_format:
		1:
			return "%d.%03d" % [sec_total, ms]
		2:
			return "%02d:%02d.%02d" % [sec_total / 60, sec_total % 60, ms / 10]
		3:
			return "%d:%02d:%02d.%03d" % [sec_total / 3600, (sec_total / 60) % 60, sec_total % 60, ms]
		4:
			return "%02d:%02d.%03d [%d]" % [sec_total / 60, sec_total % 60, ms, ticks]
	return "%02d:%02d.%03d" % [sec_total / 60, sec_total % 60, ms]


func _apply_timer(ui) -> void:
	var g = get_node_or_null("/root/global")
	var timer = ui.get("timer")
	if g == null or !(timer is RichTextLabel):
		return
	var labels = [timer, ui.get("timer_rush"), ui.get("timer_rush_small")]

	if s.timer_format != 0:
		var t = g.levelrush_time if g.levelrush == 1 else g.time
		timer.text = format_time(t)
		if labels[2] is RichTextLabel:
			labels[2].text = format_time(t)
		if labels[1] is RichTextLabel:
			labels[1].text = format_time(g.time + g.levelrush_time_thislevel)

	for l in labels:
		if l is RichTextLabel:
			if s.timer_color != GAME_TIMER_COLOR or l.has_theme_color_override("default_color"):
				if l.get_theme_color("default_color") != s.timer_color:
					l.add_theme_color_override("default_color", s.timer_color)

	var box = ui.get_node_or_null("UI/TimerBG")
	if box is Control:
		var sc = Vector2(s.timer_scale, s.timer_scale)
		if box.scale != sc:
			box.pivot_offset = Vector2(box.size.x * 0.5, 0)
			box.scale = sc
		_apply_pb(g, box)


func _apply_pb(g, box: Control) -> void:
	if !s.timer_pb or g.levelrush == 1:
		if _pb_label:
			_pb_label.visible = false
		return
	if _pb_label == null or !is_instance_valid(_pb_label):
		_pb_label = Label.new()
		_pb_label.name = "QolPB"
		_pb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pb_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists("res://Assets/Fonts/bitpop.otf"):
			_pb_label.add_theme_font_override("font", load("res://Assets/Fonts/bitpop.otf"))
		_pb_label.add_theme_font_size_override("font_size", 22)
		_pb_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_pb_label.add_theme_constant_override("outline_size", 4)
	if _pb_label.get_parent() != box:
		if _pb_label.get_parent():
			_pb_label.get_parent().remove_child(_pb_label)
		box.add_child(_pb_label)
	_pb_label.position = Vector2(0, box.size.y + 2)
	_pb_label.size = Vector2(box.size.x, 26)

	var level = str(g.currentlevel)
	if level != _pb_level:
		_pb_level = level
		var saves = get_node_or_null("/root/saves")
		_pb_time = saves._get_time(level) if saves and saves.has_method("_get_time") else -1.0
	if _pb_time <= 0.0:
		_pb_label.visible = false
		return
	_pb_label.visible = true
	var now = float(g.time)
	if _ticks(now) <= _ticks(_pb_time):
		_pb_label.text = "PB " + format_time(_pb_time)
		_pb_label.add_theme_color_override("font_color", Color("3fd46b"))
	else:
		_pb_label.text = "PB +" + format_time(now - _pb_time)
		_pb_label.add_theme_color_override("font_color", Color("c42b47"))

	if now == 0.0:
		_pb_level = ""


func _apply_hidden(ui) -> void:
	for k in HIDEABLE:
		for path in HIDEABLE[k]:
			var n = ui.get_node_or_null(path)
			if !(n is CanvasItem):
				continue
			if s[k]:
				if n.visible:
					n.set_meta("qol_hid", true)
					n.visible = false
			elif n.has_meta("qol_hid"):
				n.remove_meta("qol_hid")
				n.visible = true


func _update_fps(delta: float) -> void:
	if !s.fps_on:
		if _fps_box and _fps_box.visible:
			_fps_box.visible = false
		return
	if _fps_box == null:
		_build_fps()
	_fps_box.visible = true

	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > 240:
		_frame_ms = _frame_ms.slice(_frame_ms.size() - 240)
	_fps_acc += delta
	_fps_frames += 1
	if _fps_graph.visible:
		_fps_graph.queue_redraw()
	if _fps_acc < 0.25:
		return
	var fps = roundi(_fps_frames / _fps_acc)
	var ms = _fps_acc / _fps_frames * 1000.0
	_fps_acc = 0.0
	_fps_frames = 0
	var text = "%d FPS" % fps
	if s.fps_detail >= 1:
		text += "  %.1f MS" % ms
	if s.fps_detail >= 2 and _frame_ms.size() > 10:
		var sorted = _frame_ms.duplicate()
		sorted.sort()
		var worst = sorted[clampi(int(sorted.size() * 0.99), 0, sorted.size() - 1)]
		text += "  1%% LOW %d" % roundi(1000.0 / maxf(worst, 0.001))
	_fps_label.text = text


func _build_fps() -> void:
	_fps_box = VBoxContainer.new()
	_fps_box.name = "QolFps"
	_fps_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_box.add_theme_constant_override("separation", 2)
	_fps_label = Label.new()
	_fps_label.text = "-- FPS"
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://Assets/Fonts/bitpop.otf"):
		_fps_label.add_theme_font_override("font", load("res://Assets/Fonts/bitpop.otf"))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_fps_label.add_theme_constant_override("outline_size", 3)
	_fps_box.add_child(_fps_label)
	_fps_graph = Control.new()
	_fps_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_graph.custom_minimum_size = Vector2(180, 40)
	_fps_graph.draw.connect(_draw_graph)
	_fps_box.add_child(_fps_graph)
	_style_fps()
	if _hub:
		_hub.corner_add(CORNER_IDS[s.fps_corner], _fps_box)
	else:
		var layer = CanvasLayer.new()
		layer.layer = 128
		add_child(layer)
		layer.add_child(_fps_box)


func _style_fps() -> void:
	if _fps_label == null:
		return
	_fps_label.add_theme_font_size_override("font_size", s.fps_size)
	_fps_label.add_theme_color_override("font_color", s.fps_color)
	_fps_graph.visible = s.fps_detail >= 3
	var right = CORNER_IDS[s.fps_corner].ends_with("right")
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	_fps_graph.size_flags_horizontal = Control.SIZE_SHRINK_END if right else Control.SIZE_SHRINK_BEGIN


func _draw_graph() -> void:
	var sz = _fps_graph.size
	_fps_graph.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.45))
	var top_ms = 50.0
	for guide in [1000.0 / 60.0, 1000.0 / 30.0]:
		var y = sz.y - sz.y * guide / top_ms
		_fps_graph.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(1, 1, 1, 0.2), 1.0)
	var n = mini(_frame_ms.size(), int(sz.x))
	if n < 2:
		return
	var pts = PackedVector2Array()
	for i in n:
		var ms = _frame_ms[_frame_ms.size() - n + i]
		pts.append(Vector2(sz.x - n + i, sz.y - sz.y * clampf(ms / top_ms, 0.0, 1.0)))
	_fps_graph.draw_polyline(pts, s.fps_color, 1.0)


func _fast_speed() -> float:
	return FAST_MENU_SPEEDS[clampi(s.fast_menus, 0, FAST_MENU_SPEEDS.size() - 1)]


func _update_fast_menus() -> void:

	if _time_scaled:
		Engine.time_scale = 1.0
		_time_scaled = false
	var fast = _fast_speed()
	var keep = []
	for ap in _fast_players:
		if !is_instance_valid(ap):
			continue
		keep.append(ap)
		var base = ap.get_meta("qol_base_speed", 1.0)
		var want = base
		if fast != 1.0 and ap.is_playing() and ap.has_animation(ap.current_animation):
			var anim = ap.get_animation(ap.current_animation)
			if anim and anim.loop_mode == Animation.LOOP_NONE:
				want = base * fast
		if ap.speed_scale != want:
			ap.speed_scale = want
	_fast_players = keep


func _scan_fast(n: Node) -> void:
	_on_node_added_fast(n)
	for c in n.get_children():
		_scan_fast(c)


func _on_node_added_fast(n: Node) -> void:
	if n is AnimationPlayer and _in_menu_scene(n) and !n.has_meta("qol_base_speed"):
		n.set_meta("qol_base_speed", n.speed_scale)
		_fast_players.append(n)


func _in_menu_scene(n: Node) -> bool:
	var a = n.get_parent()
	while a:
		if FAST_MENU_SCENES.has(str(a.scene_file_path).get_file()):
			return true
		a = a.get_parent()
	return false


func _apply_fast_all() -> void:
	pass
