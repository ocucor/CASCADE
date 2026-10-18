extends Node

# Shared settings hub: builds the pages every mod shows under Options > MODS.


const VERSION = 1


const ROW_W = 664.0
const ROW_H = 51.0
const ROW_SCALE = 0.6
const ROWS = 12
const ROW_GAP = 5.0
const COL_GAP = 24.0
const COL_W = ROW_W * ROW_SCALE
const AREA_LEFT = -860.0
const AREA_TOP = -253.0
const PAGE_W = COL_W * 2 + COL_GAP
const PAGE_H = ROWS * (ROW_H * ROW_SCALE + ROW_GAP)

const CORNERS = ["top_left", "top_right", "bottom_left", "bottom_right"]

const PRESET_COLORS = [
	Color(1, 1, 1), Color(0.627451, 0.627451, 0.627451), Color("c42b47"), Color("ea531f"),
	Color("ffd23f"), Color("3fd46b"), Color("2fc4e0"), Color("3f6bff"), Color("8700ff"),
	Color("ff4fb4"), Color(0, 0, 0),
]

var _screens = []
var _current_page = 0
var _corner_layer: CanvasLayer = null
var _corner_boxes = {}
var _font_title: Font = null
var _font_body: Font = null


class PageApi:
	var items = []

	func header(text: String) -> void:
		items.append({"t": "header", "label": text})

	func toggle(label: String, desc: String, value: bool, cb: Callable) -> void:
		items.append({"t": "toggle", "label": label, "desc": desc, "value": value, "cb": cb})

	func slider(label: String, desc: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> void:
		items.append({"t": "slider", "label": label, "desc": desc, "lo": lo, "hi": hi, "step": step, "value": value, "cb": cb})

	func choice(label: String, desc: String, options: Array, index: int, cb: Callable, preview: Callable = Callable()) -> void:
		items.append({"t": "choice", "label": label, "desc": desc, "options": options, "value": index, "cb": cb, "preview": preview})

	func color(label: String, desc: String, value: Color, cb: Callable) -> void:
		items.append({"t": "color", "label": label, "desc": desc, "value": value, "cb": cb})

	func button(label: String, desc: String, text: String, cb: Callable) -> void:
		items.append({"t": "button", "label": label, "desc": desc, "text": text, "cb": cb})

	func spacer() -> void:
		items.append({"t": "spacer"})

	func column_break() -> void:
		items.append({"t": "break"})

	func panel(build: Callable) -> void:
		items.append({"t": "panel", "build": build})


func _init() -> void:
	name = "GDPatchSettingsHub"
	Engine.set_meta("gdpatch_settings_hub", self)
	if !Engine.has_meta("gdpatch_settings_pages"):
		Engine.set_meta("gdpatch_settings_pages", [])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1001
	if ResourceLoader.exists("res://Assets/Fonts/Jupiteroid-Bold.ttf"):
		_font_title = load("res://Assets/Fonts/Jupiteroid-Bold.ttf")
	if ResourceLoader.exists("res://Assets/Fonts/bitpop.otf"):
		_font_body = load("res://Assets/Fonts/bitpop.otf")
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)


func _scan(node: Node) -> void:
	_on_node_added(node)
	for c in node.get_children():
		_scan(c)


func _on_node_added(node: Node) -> void:
	if node is Control and node.name == "Options":
		_inject.call_deferred(node)


func _registered_pages() -> Array:
	var pages = Engine.get_meta("gdpatch_settings_pages", [])
	var out = []
	for p in pages:
		if p is Dictionary and p.has("build") and (p.build as Callable).is_valid():
			out.append(p)

	var mods = []
	for p in out:
		var m = str(p.get("mod", "MOD"))
		if !mods.has(m):
			mods.append(m)
	mods.sort()
	var sorted = []
	for m in mods:
		for p in out:
			if str(p.get("mod", "MOD")) == m:
				sorted.append(p)
	return sorted


func _layout_screens() -> Array:
	var screens = []
	for p in _registered_pages():
		var api = PageApi.new()
		p.build.call(api)
		var cols = [[]]
		var has_panel = false
		for it in api.items:
			if it.t == "panel":
				has_panel = true
				screens.append({"mod": str(p.get("mod", "MOD")), "title": str(p.get("title", "")),
					"part": 0, "parts": 1, "left": [], "right": [], "panel": it.build})
				continue
			if it.t == "break":
				if !cols[-1].is_empty():
					cols.append([])
				continue
			if cols[-1].size() >= ROWS:
				cols.append([])
			cols[-1].append(it)
		if cols[-1].is_empty() and (cols.size() > 1 or has_panel):
			cols.pop_back()
		var count = int(ceil(cols.size() / 2.0))
		for i in count:
			screens.append({
				"mod": str(p.get("mod", "MOD")),
				"title": str(p.get("title", "")),
				"part": i, "parts": count,
				"left": cols[i * 2],
				"right": cols[i * 2 + 1] if i * 2 + 1 < cols.size() else [],
			})
	return screens


func _inject(options: Control) -> void:
	if !is_instance_valid(options) or options.has_node("ModSettings"):
		return
	var main_select = options.get_node_or_null("MainSelect")
	if main_select == null:
		return

	var template: Button = null
	for c in main_select.get_children():
		if c is Button:
			template = c
	if template == null:
		return

	var b: Button = template.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION)
	b.name = "Mods"
	b.text = "MODS"
	main_select.add_child(b)
	b.pressed.connect(_open.bind(options))

	var root = Control.new()
	root.name = "ModSettings"
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	options.add_child(root)

	var what = options.get_node_or_null("what")
	if what:
		options.move_child(root, what.get_index())

	var screen = {"options": options, "root": root}
	screen.left = _make_column(root, AREA_LEFT)
	screen.right = _make_column(root, AREA_LEFT + COL_W + COL_GAP)
	var area = Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.anchor_left = 0.5
	area.anchor_right = 0.5
	area.anchor_top = 0.5
	area.anchor_bottom = 0.5
	area.offset_left = AREA_LEFT
	area.offset_right = AREA_LEFT + PAGE_W
	area.offset_top = AREA_TOP
	area.offset_bottom = AREA_TOP + PAGE_H
	root.add_child(area)
	screen.area = area
	_make_nav(screen)
	_make_preview(screen)
	_screens.append(screen)


func _make_column(parent: Control, x: float) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = x
	col.offset_right = x + COL_W
	col.offset_top = AREA_TOP
	col.offset_bottom = AREA_TOP + PAGE_H
	col.add_theme_constant_override("separation", int(ROW_GAP))
	parent.add_child(col)
	return col


func _make_nav(screen: Dictionary) -> void:
	var bar = Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 0.5
	bar.anchor_bottom = 0.5
	bar.offset_left = AREA_LEFT
	bar.offset_right = AREA_LEFT + PAGE_W
	bar.offset_top = AREA_TOP - 56.0
	bar.offset_bottom = AREA_TOP - 12.0
	screen.root.add_child(bar)

	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bg)


	var row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	var prev = _nav_button("<")
	prev.custom_minimum_size = Vector2(44, 0)
	prev.pressed.connect(func(): _step(-1))
	row.add_child(prev)


	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tabs)

	var label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if _font_title:
		label.add_theme_font_override("font", _font_title)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(label)


	var dots = HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_END
	dots.add_theme_constant_override("separation", 4)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dots)

	var next = _nav_button(">")
	next.custom_minimum_size = Vector2(44, 0)
	next.pressed.connect(func(): _step(1))
	row.add_child(next)

	var hint = Label.new()
	hint.text = "Q / E   LB / RB   CYCLE PAGES"
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = PAGE_H + 12.0 + 6.0
	hint.offset_bottom = hint.offset_top + 22.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _font_body:
		hint.add_theme_font_override("font", _font_body)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.627451, 0.627451, 0.627451))
	bar.add_child(hint)

	screen.nav_label = label
	screen.tabs = tabs
	screen.dots = dots
	screen.prev = prev
	screen.next = next


func _nav_button(text: String) -> Button:
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if _font_title:
		b.add_theme_font_override("font", _font_title)
	b.add_theme_font_size_override("font_size", 26)
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 1)
	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(0, 0, 0))
	b.add_theme_color_override("font_focus_color", Color(0, 0, 0))
	b.add_theme_color_override("font_pressed_color", Color(0, 0, 0))
	return b


func _active_screen():
	for s in _screens:
		if is_instance_valid(s.root) and s.root.is_visible_in_tree():
			return s
	return null


func _open(options: Control) -> void:
	for s in _screens:
		if s.options == options:
			options.get_node("MainSelect").hide()
			for page in ["Audio", "Video", "Controls", "Interface", "Game", "Live"]:
				var n = options.get_node_or_null(page)
				if n:
					n.hide()
			s.root.show()
			if options.has_method("_hideheader"):
				options._hideheader("MODS")
			_render(s, true)
			return


var _fit_label: Label = null
var _fit_text = ""


func _process(_delta: float) -> void:
	_screens = _screens.filter(func(s): return is_instance_valid(s.root))
	_fit_description()
	for s in _screens:
		if !s.root.visible:
			continue

		var ms = s.options.get_node_or_null("MainSelect")
		var ays = s.options.get_node_or_null("AreYouSure")
		if (ms and ms.visible) or (ays and ays.visible):
			s.root.hide()
			_preview_off(s)


func _input(event: InputEvent) -> void:
	var s = _active_screen()
	if s == null or event.is_echo():
		return
	var focus = s.root.get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var dir = 0
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q, KEY_PAGEUP: dir = -1
			KEY_E, KEY_PAGEDOWN: dir = 1
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_LEFT_SHOULDER: dir = -1
			JOY_BUTTON_RIGHT_SHOULDER: dir = 1
	if dir != 0:
		_step(dir)
		s.root.get_viewport().set_input_as_handled()
		return

	if (event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		var p = _active_screen()
		if p != null and p.has("preview") and p.preview.visible:
			if event.is_action_pressed("ui_left"):
				_preview_step(-1)
				s.root.get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_right"):
				_preview_step(1)
				s.root.get_viewport().set_input_as_handled()


func _step(dir: int) -> void:
	var s = _active_screen()
	if s == null:
		return
	_current_page += dir
	_play_ui("sndUIHover")
	_render(s, true)


func _jump_to(i: int) -> void:
	var s = _active_screen()
	if s == null:
		return
	_current_page = i
	_play_ui("sndUIHover")
	_render(s, true)


func refresh() -> void:
	var s = _active_screen()
	if s:
		_render(s, false)


func _render(s: Dictionary, grab: bool) -> void:
	_preview_off(s)
	var screens = _layout_screens()
	for col in [s.left, s.right, s.area]:
		for c in col.get_children():
			col.remove_child(c)
			c.queue_free()
	for box in [s.dots, s.tabs]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()

	if screens.is_empty():
		s.nav_label.text = "NO MOD SETTINGS"
		return
	_current_page = posmod(_current_page, screens.size())
	var cur = screens[_current_page]
	var title = cur.title
	if cur.parts > 1:
		title += "  (%d/%d)" % [cur.part + 1, cur.parts]
	s.nav_label.text = title

	var first: Control = null
	if cur.has("panel"):
		s.left.hide()
		s.right.hide()
		s.area.show()
		var f = cur.panel.call(s.area)
		if f is Control:
			first = f
	else:
		s.left.show()
		s.right.show()
		s.area.hide()
	for side in ["left", "right"]:
		for it in cur[side]:
			var f = _build_row(s[side], it)
			if first == null and f:
				first = f

	var mods = []
	for i in screens.size():
		if mods.is_empty() or mods[-1].mod != screens[i].mod:
			mods.append({"mod": screens[i].mod, "first": i, "pages": 0})
		mods[-1].pages += 1
	var own = []
	for i in screens.size():
		if screens[i].mod == cur.mod:
			own.append(i)


	var dots_w = 0.0
	if own.size() > NAV_MAX_DOTS:
		dots_w = _tab_width("%d/%d" % [own.size(), own.size()])
	elif own.size() > 1:
		dots_w = own.size() * 18.0 - 4.0
	var room = PAGE_W - 44.0 * 2 - 8.0 * 4 - NAV_MIN_TITLE - dots_w
	var full = 0.0
	var short = 0.0
	for m in mods:
		full += _tab_width(m.mod) + 4.0
		short += _tab_width(m.mod if m.mod == cur.mod else _short_name(m.mod)) + 4.0
	var mode = 0 if full <= room else (1 if short <= room else 2)
	if mode < 2:
		for m in mods:
			var current = m.mod == cur.mod
			var tab = _mod_tab(m.mod if current or mode == 0 else _short_name(m.mod), current)
			tab.tooltip_text = m.mod
			tab.pressed.connect(_jump_to.bind(m.first))
			s.tabs.add_child(tab)
	else:
		var tab = _mod_tab(cur.mod, true)
		tab.pressed.connect(_jump_to.bind(own[0]))
		s.tabs.add_child(tab)
		var more = _mod_tab("+%d" % (mods.size() - 1), false)
		more.tooltip_text = "All mods"
		more.pressed.connect(_mod_list.bind(more, mods, cur.mod))
		s.tabs.add_child(more)

	if own.size() > NAV_MAX_DOTS:
		var count = make_label("%d/%d" % [own.find(_current_page) + 1, own.size()], 18, Color(1, 1, 1), true)
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		s.dots.add_child(count)
	for i in own:
		if own.size() > NAV_MAX_DOTS:
			break
		var dot = Button.new()
		dot.focus_mode = Control.FOCUS_NONE
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.tooltip_text = screens[i].mod + " / " + screens[i].title
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1) if i == _current_page else Color(0.35, 0.35, 0.35)
		for k in ["normal", "hover", "pressed", "focus"]:
			dot.add_theme_stylebox_override(k, sb)
		dot.pressed.connect(_jump_to.bind(i))
		s.dots.add_child(dot)

	if grab:
		if first:
			first.grab_focus()
		else:
			s.next.grab_focus()


const NAV_MAX_DOTS = 8
const NAV_MIN_TITLE = 150.0


func _tab_width(text: String) -> float:
	var font: Font = _font_title if _font_title else ThemeDB.fallback_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 20.0


func _short_name(mod: String) -> String:
	var words = mod.split(" ", false)
	if words.size() > 1:
		var out = ""
		for w in words.slice(0, 3):
			out += w[0]
		return out
	return mod.left(3)


func _mod_tab(text: String, current: bool) -> Button:
	var tab = _nav_button(text)
	tab.focus_mode = Control.FOCUS_NONE
	tab.add_theme_font_size_override("font_size", 18)
	for k in ["normal", "hover", "pressed"]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color("c42b47") if current else (Color(1, 1, 1) if k != "normal" else Color(0.14, 0.14, 0.15))
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		tab.add_theme_stylebox_override(k, sb)
	if current:
		tab.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		tab.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	return tab


func _mod_list(from: Button, mods: Array, current: String) -> void:
	var menu = PopupMenu.new()
	if _font_title:
		menu.add_theme_font_override("font", _font_title)
	menu.add_theme_font_size_override("font_size", 18)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0)
	bg.border_color = Color(1, 1, 1)
	bg.set_border_width_all(2)
	bg.set_content_margin_all(6)
	menu.add_theme_stylebox_override("panel", bg)
	var hl = StyleBoxFlat.new()
	hl.bg_color = Color(1, 1, 1)
	menu.add_theme_stylebox_override("hover", hl)
	menu.add_theme_color_override("font_color", Color(1, 1, 1))
	menu.add_theme_color_override("font_hover_color", Color(0, 0, 0))
	for i in mods.size():
		var m = mods[i]
		menu.add_item(m.mod + ("" if m.pages == 1 else "  (%d)" % m.pages), i)
		if m.mod == current:
			menu.set_item_disabled(i, true)
	menu.id_pressed.connect(func(id): _jump_to(mods[id].first))
	menu.popup_hide.connect(menu.queue_free)
	from.add_child(menu)

	var scale = from.get_global_transform_with_canvas().get_scale()
	menu.position = Vector2i(from.get_screen_position() + Vector2(0, from.size.y * scale.y + 4))
	menu.popup()


func _row_slot(list: Control) -> Control:
	var holder = Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(COL_W, ROW_H * ROW_SCALE)
	var inner = Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.size = Vector2(ROW_W, ROW_H)
	inner.scale = Vector2(ROW_SCALE, ROW_SCALE)
	holder.add_child(inner)
	list.add_child(holder)
	return inner


func _build_row(list: VBoxContainer, it: Dictionary) -> Control:
	var col = _row_slot(list)
	match it.t:
		"header":
			var h = col
			var bg = ColorRect.new()
			bg.color = Color(0, 0, 0, 1)
			bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			h.add_child(bg)
			var l = Label.new()
			l.text = it.label
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.offset_left = 10.0
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if _font_title:
				l.add_theme_font_override("font", _font_title)
			l.add_theme_font_size_override("font_size", 30)
			l.add_theme_color_override("font_color", Color("c42b47"))
			h.add_child(l)
			return null
		"spacer":
			return null
		"toggle":
			var box = load("res://Scenes/UI/option_checkbox.tscn").instantiate()
			box._text = it.label
			box._description = it.desc
			col.add_child(box)
			box.button.set_pressed_no_signal(it.value)
			box.button.toggled.connect(it.cb)
			return box.button
		"slider":
			var box = load("res://Scenes/UI/option_slider.tscn").instantiate()
			box._text = it.label
			box._description = it.desc
			box._min = it.lo
			box._max = it.hi
			box._step = it.step
			col.add_child(box)
			box.slider.set_value_no_signal(it.value)
			box.slider.value_changed.connect(it.cb)
			return box.slider
		"choice":
			var box = load("res://Scenes/UI/option_dropdown.tscn").instantiate()
			box._text = it.label
			box._description = it.desc
			col.add_child(box)
			var ob: OptionButton = box.button
			ob.clear()
			for o in it.options:
				ob.add_item(str(o))
			ob.select(clampi(it.value, 0, it.options.size() - 1))
			ob.item_selected.connect(it.cb)
			if it.preview.is_valid():
				_wire_preview(ob, it.preview)
			return ob
		"color":
			var box = load("res://Scenes/UI/option_dropdown.tscn").instantiate()
			box._text = it.label
			box._description = it.desc
			col.add_child(box)
			box.button.hide()
			box.button.focus_mode = Control.FOCUS_NONE

			var pick = Button.new()
			pick.focus_mode = Control.FOCUS_ALL
			pick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			pick.offset_left = 8.0
			pick.offset_right = -8.0
			pick.offset_top = 8.0
			pick.offset_bottom = -8.0
			if _font_title:
				pick.add_theme_font_override("font", _font_title)
			pick.add_theme_font_size_override("font_size", 26)
			pick.set_meta("desc", it.desc + " Press LEFT or RIGHT to cycle presets.")
			_set_swatch(pick, it.value)
			pick.pressed.connect(_open_color.bind(pick, it.cb))
			pick.gui_input.connect(_color_row_input.bind(pick, it.cb))
			box.get_node("BlackBG").add_child(pick)
			return pick
		"button":
			var box = load("res://Scenes/UI/option_dropdown.tscn").instantiate()
			box._text = it.label
			box._description = it.desc
			col.add_child(box)
			box.button.hide()
			box.button.focus_mode = Control.FOCUS_NONE
			var b = _nav_button(it.text)
			b.add_theme_font_size_override("font_size", 30)
			b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.set_meta("desc", it.desc)
			b.pressed.connect(func():
				_play_ui("sndUIPress")
				it.cb.call())
			box.get_node("BlackBG").add_child(b)
			return b
	return null


func _set_swatch(b: Button, c: Color) -> void:
	b.set_meta("color", c)
	var sb = StyleBoxFlat.new()
	sb.bg_color = c
	var focus = StyleBoxFlat.new()
	focus.bg_color = c
	focus.border_color = Color(1, 1, 1)
	focus.set_border_width_all(3)
	for k in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("focus", focus)
	b.text = "#" + c.to_html(c.a < 0.999).to_upper()
	var ink = Color(0, 0, 0) if c.get_luminance() > 0.5 and c.a > 0.4 else Color(1, 1, 1)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, ink)


func _color_row_input(event: InputEvent, pick: Button, cb: Callable) -> void:
	var dir = 0
	if event.is_action_pressed("ui_left"):
		dir = -1
	elif event.is_action_pressed("ui_right"):
		dir = 1
	if dir == 0:
		return
	var cur: Color = pick.get_meta("color", Color(1, 1, 1))
	var idx = -1
	for i in PRESET_COLORS.size():
		if PRESET_COLORS[i].is_equal_approx(Color(cur, 1.0)):
			idx = i
	idx = posmod(idx + dir, PRESET_COLORS.size()) if idx >= 0 else 0
	var c = Color(PRESET_COLORS[idx], cur.a)
	_set_swatch(pick, c)
	cb.call(c)
	_play_ui("sndUIHover")
	pick.accept_event()


var _cp: PopupPanel = null
var _cp_target: Button = null
var _cp_cb: Callable
var _cp_sliders = {}
var _cp_hex: LineEdit = null
var _cp_preview: ColorRect = null
var _cp_sync = false


func _open_color(row: Button, cb: Callable) -> void:
	if _cp == null:
		_build_color_popup()
	_cp_target = row
	_cp_cb = cb
	_cp_load(row.get_meta("color", Color(1, 1, 1)))
	_cp.popup_centered(Vector2i(520, 0))
	_cp_sliders.h.grab_focus()


func _build_color_popup() -> void:
	_cp = PopupPanel.new()
	_cp.name = "QolColorPicker"
	_cp.process_mode = Node.PROCESS_MODE_ALWAYS
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.96)
	bg.border_color = Color(1, 1, 1)
	bg.set_border_width_all(3)
	bg.set_content_margin_all(14)
	_cp.add_theme_stylebox_override("panel", bg)
	add_child(_cp)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_cp.add_child(v)

	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	_cp_preview = ColorRect.new()
	_cp_preview.custom_minimum_size = Vector2(64, 64)
	top.add_child(_cp_preview)
	var grid = GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	top.add_child(grid)
	for c in PRESET_COLORS:
		var sw = Button.new()
		sw.custom_minimum_size = Vector2(54, 28)
		sw.focus_mode = Control.FOCUS_ALL
		var sb = StyleBoxFlat.new()
		sb.bg_color = c
		var fb = StyleBoxFlat.new()
		fb.bg_color = c
		fb.border_color = Color("c42b47")
		fb.set_border_width_all(3)
		for k in ["normal", "pressed"]:
			sw.add_theme_stylebox_override(k, sb)
		sw.add_theme_stylebox_override("hover", fb)
		sw.add_theme_stylebox_override("focus", fb)
		sw.pressed.connect(func(): _cp_apply(Color(c, _cp_sliders.a.value)))
		grid.add_child(sw)

	for key in ["h", "s", "v", "a"]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l = make_label({"h": "HUE", "s": "SAT", "v": "VAL", "a": "ALPHA"}[key], 20)
		l.custom_minimum_size = Vector2(80, 0)
		row.add_child(l)
		var sl = HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.005
		sl.custom_minimum_size = Vector2(380, 26)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(_x): _cp_from_sliders())
		row.add_child(sl)
		v.add_child(row)
		_cp_sliders[key] = sl

	var bottom = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)
	_cp_hex = LineEdit.new()
	_cp_hex.custom_minimum_size = Vector2(200, 34)
	if _font_title:
		_cp_hex.add_theme_font_override("font", _font_title)
	_cp_hex.add_theme_font_size_override("font_size", 22)
	_cp_hex.text_submitted.connect(func(txt):
		if Color.html_is_valid(txt):
			_cp_apply(Color.html(txt)))
	bottom.add_child(_cp_hex)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var ok = make_button("DONE", 22)
	ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ok.custom_minimum_size = Vector2(120, 34)
	ok.pressed.connect(func(): _cp.hide())
	bottom.add_child(ok)
	_cp.popup_hide.connect(func():
		if is_instance_valid(_cp_target):
			_cp_target.grab_focus())


func _cp_load(c: Color) -> void:
	_cp_sync = true
	_cp_sliders.h.value = c.h
	_cp_sliders.s.value = c.s
	_cp_sliders.v.value = c.v
	_cp_sliders.a.value = c.a
	_cp_sync = false
	_cp_preview.color = c
	_cp_hex.text = c.to_html(c.a < 0.999).to_upper()


func _cp_from_sliders() -> void:
	if _cp_sync:
		return
	_cp_apply(Color.from_hsv(_cp_sliders.h.value, _cp_sliders.s.value, _cp_sliders.v.value, _cp_sliders.a.value), false)


func _cp_apply(c: Color, reload: bool = true) -> void:
	if reload:
		_cp_load(c)
	else:
		_cp_preview.color = c
		_cp_hex.text = c.to_html(c.a < 0.999).to_upper()
	if is_instance_valid(_cp_target):
		_set_swatch(_cp_target, c)
	if _cp_cb.is_valid():
		_cp_cb.call(c)


func _play_ui(snd: String) -> void:
	var audio = get_node_or_null("/root/Audio")
	if audio and audio.get(snd) != null and audio.has_method("sound_play_ui"):
		audio.sound_play_ui(audio.get(snd))


func corner_add(corner: String, ctrl: Control, margin: float = 10.0) -> void:
	if !CORNERS.has(corner):
		corner = "top_right"
	_ensure_corners(margin)
	var box: VBoxContainer = _corner_boxes[corner]
	if ctrl.get_parent() == box:
		return
	if ctrl.get_parent():
		ctrl.get_parent().remove_child(ctrl)
	box.add_child(ctrl)
	if ctrl is Label:
		ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if corner.ends_with("right") else HORIZONTAL_ALIGNMENT_LEFT
	ctrl.size_flags_horizontal = Control.SIZE_SHRINK_END if corner.ends_with("right") else Control.SIZE_SHRINK_BEGIN


func _ensure_corners(margin: float) -> void:
	if _corner_layer:
		return
	_corner_layer = CanvasLayer.new()
	_corner_layer.name = "GDPatchHudCorners"
	_corner_layer.layer = 128
	add_child(_corner_layer)
	for corner in CORNERS:
		var box = VBoxContainer.new()
		box.name = corner
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		var right = corner.ends_with("right")
		var bottom = corner.begins_with("bottom")
		box.anchor_left = 1.0 if right else 0.0
		box.anchor_right = box.anchor_left
		box.anchor_top = 1.0 if bottom else 0.0
		box.anchor_bottom = box.anchor_top
		box.offset_left = -margin if right else margin
		box.offset_right = box.offset_left
		box.offset_top = -margin if bottom else margin * 0.4
		box.offset_bottom = box.offset_top
		box.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
		box.alignment = BoxContainer.ALIGNMENT_END if bottom else BoxContainer.ALIGNMENT_BEGIN
		_corner_layer.add_child(box)
		_corner_boxes[corner] = box


func make_button(text: String, font_size: int = 22) -> Button:
	var b = _nav_button(text)
	b.add_theme_font_size_override("font_size", font_size)
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


func make_label(text: String, font_size: int = 20, color: Color = Color(1, 1, 1), title: bool = false) -> Label:
	var l = Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f = _font_title if title else _font_body
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func page_options():
	var s = _active_screen()
	return s.options if s else null


func _fit_description() -> void:
	var s = _active_screen()
	var lbl = s.options.get_node_or_null("what/maintext") if s else null
	if !(lbl is Label) or !lbl.is_visible_in_tree():
		if is_instance_valid(_fit_label) and s == null:
			_fit_label.remove_theme_font_size_override("font_size")
			_fit_label = null
			_fit_text = ""
		return
	if lbl == _fit_label and lbl.text == _fit_text:
		return
	_fit_label = lbl
	_fit_text = lbl.text

	var room = 84.0
	if lbl.get_parent() is Control:
		room = lbl.get_parent().size.y - lbl.position.y - 4.0
	var size = 30
	while true:
		lbl.add_theme_font_size_override("font_size", size)
		if size <= 14 or lbl.get_line_count() * lbl.get_line_height() <= room:
			break
		size -= 2


const PREVIEW_TOP = 118.0
const PREVIEW_BOTTOM = 370.0
const PREVIEW_IMG_H = 196.0


func _make_preview(screen: Dictionary) -> void:
	var panel = ColorRect.new()
	panel.name = "ModPreview"
	panel.color = Color(0, 0, 0, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 77.0
	panel.offset_right = 858.0
	panel.offset_top = PREVIEW_TOP
	panel.offset_bottom = PREVIEW_BOTTOM
	panel.visible = false

	screen.options.add_child(panel)
	var title = make_label("", 24, Color("c42b47"), true)
	title.position = Vector2(14, 6)
	title.size = Vector2(566, 30)
	title.clip_text = true
	panel.add_child(title)
	var count = make_label("", 18, Color(0.8, 0.8, 0.8))
	count.position = Vector2(590, 8)
	count.size = Vector2(180, 24)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.visible = false
	panel.add_child(count)
	var prev = _nav_button("<")
	prev.focus_mode = Control.FOCUS_NONE
	prev.position = Vector2(6, 112)
	prev.size = Vector2(32, 52)
	prev.visible = false
	prev.pressed.connect(func(): _preview_step(-1))
	panel.add_child(prev)
	var next = _nav_button(">")
	next.focus_mode = Control.FOCUS_NONE
	next.position = Vector2(743, 112)
	next.size = Vector2(32, 52)
	next.visible = false
	next.pressed.connect(func(): _preview_step(1))
	panel.add_child(next)
	var desc = make_label("", 18, Color(0.85, 0.85, 0.85))
	desc.position = Vector2(326, 46)
	desc.size = Vector2(400, 190)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.visible = false
	panel.add_child(desc)
	var row = HBoxContainer.new()
	row.position = Vector2(14, 40)
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	screen.preview = panel
	screen.preview_title = title
	screen.preview_row = row
	screen.preview_count = count
	screen.preview_prev = prev
	screen.preview_next = next
	screen.preview_desc = desc


func _wire_preview(ob: OptionButton, preview: Callable) -> void:
	var show_selected = func(): _show_preview(ob, preview, ob.selected)
	ob.focus_entered.connect(show_selected)
	ob.mouse_entered.connect(show_selected)
	ob.item_selected.connect(func(i): _show_preview(ob, preview, i))
	ob.focus_exited.connect(func(): _hide_preview(ob))
	ob.mouse_exited.connect(func(): _hide_preview(ob))
	var popup = ob.get_popup()
	popup.id_focused.connect(func(id): _show_preview(ob, preview, ob.get_item_index(id)))
	popup.popup_hide.connect(func():
		if ob.has_focus():
			_show_preview(ob, preview, ob.selected)
		else:
			_hide_preview(ob))


func _screen_for(node: Node):
	for s in _screens:
		if is_instance_valid(s.root) and s.root.is_ancestor_of(node):
			return s
	return null


func _show_preview(ob: OptionButton, preview: Callable, index: int) -> void:
	var s = _screen_for(ob)
	if s == null or index < 0:
		return
	var data = preview.call(index)
	if !(data is Dictionary):
		return
	s.preview_data = data
	s.preview_index = 0
	s.preview.set_meta("owner_row", ob.get_instance_id())
	_preview_render(s)
	s.preview.show()


func _preview_render(s: Dictionary) -> void:
	var data = s.get("preview_data")
	if !(data is Dictionary):
		return
	s.preview_title.text = str(data.get("title", ""))
	for c in s.preview_row.get_children():
		s.preview_row.remove_child(c)
		c.queue_free()
	var images = data.get("images", [])
	var labels = data.get("labels", [])
	var n = images.size()
	var cycle = bool(data.get("cycle", false)) and n > 1
	var cur = clampi(int(s.get("preview_index", 0)), 0, maxi(0, n - 1))
	s.preview_index = cur
	var desc = str(data.get("desc", ""))
	s.preview_prev.visible = cycle
	s.preview_next.visible = cycle
	s.preview_count.visible = cycle
	s.preview_count.text = "VIEW  %d / %d" % [cur + 1, n] if cycle else ""
	s.preview_desc.visible = desc != ""
	s.preview_desc.text = desc
	if cycle:

		s.preview_row.position = Vector2(48, 40)
		s.preview_row.alignment = BoxContainer.ALIGNMENT_BEGIN if desc != "" else BoxContainer.ALIGNMENT_CENTER
	else:
		s.preview_row.position = Vector2(14, 40)
		s.preview_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var shown = [cur] if cycle else range(n)
	for i in shown:
		var tex = images[i]
		var cell = VBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 2)
		var img = TextureRect.new()
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var w = PREVIEW_IMG_H * 0.5
		if tex is Texture2D and tex.get_height() > 0:
			w = PREVIEW_IMG_H * tex.get_width() / tex.get_height()
		img.custom_minimum_size = Vector2(w, PREVIEW_IMG_H)
		img.texture = tex
		cell.add_child(img)
		var cap = make_label(str(labels[i]) if i < labels.size() else "", 14, Color(0.8, 0.8, 0.8))
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.custom_minimum_size = Vector2(w, 0)
		cell.add_child(cap)
		s.preview_row.add_child(cell)

	var on_view = data.get("on_view")
	if on_view is Callable and on_view.is_valid():
		on_view.call(cur if cycle else -1)


func _preview_step(dir: int) -> void:
	var s = _active_screen()
	if s == null or !s.has("preview") or !s.preview.visible:
		return
	var data = s.get("preview_data")
	if !(data is Dictionary) or !bool(data.get("cycle", false)):
		return
	var n = (data.get("images", []) as Array).size()
	if n < 2:
		return
	s.preview_index = posmod(int(s.get("preview_index", 0)) + dir, n)
	_play_ui("sndUIHover")
	_preview_render(s)


func _preview_off(s: Dictionary) -> void:
	if s.has("preview"):
		s.preview.hide()
	var data = s.get("preview_data")
	if data is Dictionary:
		var on_view = data.get("on_view")
		if on_view is Callable and on_view.is_valid():
			on_view.call(-1)


func _hide_preview(ob: OptionButton) -> void:
	var s = _screen_for(ob)
	if s == null:
		return

	if ob.get_popup().visible or ob.has_focus() or ob.get_global_rect().has_point(ob.get_global_mouse_position()):
		return
	if s.has("preview") and s.preview.visible and s.preview.get_global_rect().has_point(ob.get_global_mouse_position()):
		return
	if s.preview.get_meta("owner_row", 0) == ob.get_instance_id():
		_preview_off(s)
