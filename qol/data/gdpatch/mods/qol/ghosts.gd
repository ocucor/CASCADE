extends Node

# .cghost: "CGHOST" | u16 version | u32 header_len | JSON header | u32 raw_len | u32 comp_len
# | zstd body | u32 sig_len | RSA-SHA256 signature. One 60-byte record per physics tick.


const FORMAT_VERSION = 1
const MAGIC = "CGHOST"
const EXT = "cghost"
const REC = 60
const ROOT = "user://qol/ghosts/"
const MINE = ROOT + "mine/"
const IMPORTED = ROOT + "imported/"
const INBOX = ROOT + "inbox/"
const EXPORT_DIR = ROOT + "export/"
const KEY_PATH = ROOT + "signing_key.pem"
const SIGNERS_PATH = ROOT + "known_signers.cfg"
const RACE_PATH = ROOT + "race.cfg"
const MAX_FILE = 24 * 1024 * 1024
const MAX_SECONDS = 3600.0
const MAX_EVENTS = 50000

const F_FLOOR = 1
const F_AIM = 2
const F_DASH = 4
const F_STOMP = 8
const F_SLIDE = 16
const F_DEATH = 32
const F_ZONED = 64
const F_STAR = 128
const F_EXFIL = 256
const F_UNARMED = 512

const EVENT_TYPES = ["deploy", "core", "kill", "exfil", "death", "zoned", "star", "jump", "dash", "stomp", "shot", "hurt", "hit"]
const BAR_MODES = ["GAME", "ALWAYS", "OFF"]
const DEATH_TAIL = 4.0
const HEAD_OFFSET = Vector3(0, 1.5, 0)
const SHOWCASE_DASH_SPEED = 30.0
const STAT_EVENTS = {
	"stCore": "core", "stEnemyKills": "kill", "stExfil": "exfil", "stDeaths": "death",
	"stZoned": "zoned", "stStarstruck": "star", "stDash": "dash", "stStomp": "stomp",
}

const GHOST_COLORS = [Color(1, 1, 1), Color("c42b47"), Color("2fc4e0"), Color("ffd23f")]

const GHOST_SKINS = [
	"res://Assets/Models/BunnyGal FPS Anims_joy_tex.png",
	"res://Assets/Models/joyDEMO_tex.png",
	"res://Assets/Models/joyKLLR_tex.png",
	"res://Assets/Models/joyRBBT_tex.png",
	"res://Assets/Models/joyFLWR_tex.png",
]

var q = null
var theater = null


var _rec = false
var _rec_player = null
var _rec_done_id = 0
var _rec_buf = PackedByteArray()
var _rec_ticks = 0
var _rec_events = []
var _rec_complete = false
var _rec_level = ""
var _rec_jumps = 0.0
var _rec_hp = 0.0
var _rec_died_at = -1
var last_saved = ""
var _rec_skin = 0
var _rec_cskin = {}
var _tps = 60


var _crypto = Crypto.new()
var _key: CryptoKey = null
var _pub_pem = ""


var _header_cache = {}
var _sel_level = ""
var _sel_runs = []
var _cursor_run = ""
var _status = ""
var _focus_key = ""
var _audit_cache = {}


var _race_map = {}
var _race = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 900
	Engine.set_meta("qol_ghost", self)
	for d in [MINE, IMPORTED, INBOX, EXPORT_DIR]:
		DirAccess.make_dir_recursive_absolute(d)
	_load_race_map()
	get_window().files_dropped.connect(_on_files_dropped)


func register_pages(pages: Array) -> void:
	pages.append({"mod": "QOL", "title": "GHOSTS", "build": _page_library})
	pages.append({"mod": "QOL", "title": "GHOST SETTINGS", "build": _page_settings})


func _page_library(api) -> void:
	api.panel(_build_library)


func _page_settings(api) -> void:
	api.header("RECORDING")
	api.toggle("RECORD RUNS", "Record completed runs for the ghost theater. Does not affect leaderboards.", q.s.ghost_record, q._opt("ghost_record"))
	api.toggle("SAVE DEATHS", "Keep recordings of runs that end in death.", q.s.ghost_save_deaths, q._opt("ghost_save_deaths"))
	api.slider("KEEP LATEST", "Set how many recent runs are kept per level, in addition to your 3 fastest.", 1, 30, 1, q.s.ghost_keep, q._opt("ghost_keep"))
	api.toggle("RACE GHOST", "Show selected race ghost during levels.", q.s.ghost_race, q._opt("ghost_race"))
	api.choice("THEATER HEALTH BARS", "Set when THREAT health bars appear in the ghost theater.", BAR_MODES, q.s.theater_bars, q._opt("theater_bars"))
	api.toggle("THREAT TRACKING", "Toggle THREATS turning to face the player in the ghost theater.", q.s.theater_watch, q._opt("theater_watch"))
	api.slider("RACE GHOST OPACITY", "Set opacity of race ghost.", 0.1, 1.0, 0.05, q.s.ghost_race_alpha, q._opt("ghost_race_alpha"))
	api.button("CONVERT GAME PB", "Create a showcase ghost from your personal best on the level selected in GHOSTS. Your personal best is unaffected.", "CONVERT", func():
		_status = convert_game_ghost(_sel_level) if _sel_level != "" else "SELECT A LEVEL ON THE GHOSTS PAGE FIRST"
		_refresh())
	api.column_break()
	api.header("SHARING")
	api.button("GHOST FOLDER", "Open the ghost folder. Exported ghosts are saved here.", "OPEN", func(): OS.shell_open(ProjectSettings.globalize_path(ROOT)))
	api.button("IMPORT INBOX", "Import ghost files from the inbox folder. Ghost files can also be dragged onto the game window.", "IMPORT", func():
		_status = _import_inbox()
		_refresh())
	api.button("MY SIGNING KEY", "Open the folder containing your ghost signing key. Do not share this key.", "SHOW", func(): OS.shell_open(ProjectSettings.globalize_path(ROOT)))
	api.button("FORGET SIGNERS", "Clear saved ghost signers. Use if a friend's ghosts show SIGNER CHANGED after a reinstall.", "CLEAR", func():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SIGNERS_PATH))
		_audit_cache.clear()
		_status = "PINNED SIGNERS CLEARED"
		_refresh())


func _hub():
	return Engine.get_meta("gdpatch_settings_hub") if Engine.has_meta("gdpatch_settings_hub") else null


func _refresh() -> void:
	var hub = _hub()
	if hub:
		hub.refresh()


func _physics_process(_delta: float) -> void:
	if theater and theater.active:
		return
	if get_tree().paused:
		return
	var g = get_node_or_null("/root/global")
	var ui = get_node_or_null("/root/UI")
	if g == null or ui == null:
		return
	var p = g.get("_player")
	var running = ui.get("_timerstart") == true
	if !_rec:
		if running and q.s.ghost_record and is_instance_valid(p) and p.is_inside_tree() \
				and g.levelrush != 1 and p.get_instance_id() != _rec_done_id:
			_start(g, p)
	elif !is_instance_valid(p) or p != _rec_player:
		print("[qol] ghost: player replaced (restart / level change)")
		_finish(g)
	elif _rec_died_at >= 0:

		_sample(p, ui)
		if _rec_ticks - _rec_died_at >= DEATH_TAIL * _tps:
			_finish(g)
	elif !running:
		_finish(g)
	else:
		_sample(p, ui)
	_update_race(g, p, running)


func _start(g, p) -> void:
	_rec = true
	_rec_player = p
	_rec_level = str(g.currentlevel)
	_tps = Engine.get_physics_ticks_per_second()
	_rec_buf = PackedByteArray()
	_rec_ticks = 0
	_rec_events = [[0, "deploy"]]
	_rec_complete = false
	_rec_died_at = -1
	_rec_jumps = float(p.get("jump_amnt")) if p.get("jump_amnt") != null else 0.0
	_rec_hp = float(p.get("energie")) if p.get("energie") != null else 0.0
	var saves = get_node_or_null("/root/saves")
	_rec_skin = int(saves.get("skin_joyeuse")) if saves and saves.get("skin_joyeuse") != null else 0
	_rec_cskin = Engine.get_meta("skinkit").replay_tag() if Engine.has_meta("skinkit") else {}
	if p.has_signal("Fired") and !p.Fired.is_connected(_on_fired):
		p.Fired.connect(_on_fired)

	var r = _encode(p, get_node("/root/UI"))
	for i in roundi(float(g.time) * _tps):
		_rec_buf.append_array(r)
		_rec_ticks += 1
	_sample(p, get_node("/root/UI"))
	print("[qol] ghost: recording %s (timer at tick %d)" % [_rec_level, _rec_ticks - 1])


func _now_tick() -> int:
	return maxi(_rec_ticks - 1, 0)


func _sample(p, ui) -> void:
	if _rec_ticks > MAX_SECONDS * _tps:
		print("[qol] ghost: run longer than an hour, not recorded")
		_rec_complete = false
		_rec_died_at = -1
		_finish(get_node("/root/global"))
		return
	_rec_buf.append_array(_encode(p, ui))
	_rec_ticks += 1
	var tick = _rec_ticks - 1
	var j = p.get("jump_amnt")
	if j != null:
		if float(j) > _rec_jumps:
			_rec_events.append([tick, "jump"])
		_rec_jumps = float(j)
	var hp = p.get("energie")
	if hp != null:
		if float(hp) < _rec_hp:
			_rec_events.append([tick, "hurt"])
		_rec_hp = float(hp)
	if p.get("death") == true and _rec_died_at < 0:
		_rec_died_at = tick
		if !_rec_events.any(func(e): return e[1] == "death"):
			_rec_events.append([tick, "death"])


func _encode(p, ui) -> PackedByteArray:
	var b = PackedByteArray()
	b.resize(REC)
	var cam: Camera3D = p.camera
	var ct = cam.global_transform
	var qt = ct.basis.get_rotation_quaternion()
	var v: Vector3 = p.velocity
	var pos: Vector3 = p.global_position
	var vals = [pos.x, pos.y, pos.z, ct.origin.x, ct.origin.y, ct.origin.z, qt.x, qt.y, qt.z, qt.w, cam.fov, v.x, v.y, v.z]
	for i in vals.size():
		b.encode_float(i * 4, vals[i])
	var f = 0
	if p.is_on_floor(): f |= F_FLOOR
	if p.get("aiming"): f |= F_AIM
	if p.get("is_dashing"): f |= F_DASH
	if p.get("stomp"): f |= F_STOMP
	if p.get("sloping"): f |= F_SLIDE
	if p.get("death"): f |= F_DEATH
	if ui.get("_zoned"): f |= F_ZONED
	if ui.get("starstruck"): f |= F_STAR
	if p.get("exfil"): f |= F_EXFIL
	if p.get("unarmed") == true: f |= F_UNARMED
	b.encode_u16(56, f)
	var j = p.get("jump_amnt")
	b.encode_u8(58, clampi(int(j) if j != null else 0, 0, 255))
	var hp = p.get("energie")
	b.encode_u8(59, clampi(roundi(float(hp) * 10.0) if hp != null else 0, 0, 255))
	return b


func on_stat(stat: String) -> void:
	if q and q.extras:
		q.extras.on_stat(stat)
	if !_rec or !STAT_EVENTS.has(stat):
		return
	var type = STAT_EVENTS[stat]
	if type == "death" and _rec_events.any(func(e): return e[1] == "death"):
		return
	_rec_events.append([_now_tick(), type])
	if type == "exfil":
		_rec_complete = true


func on_enemy_hit(pos: Vector3, health: float, max_health: float) -> void:
	if !_rec or max_health <= 0.0:
		return
	_rec_events.append([_now_tick(), "hit", pos.x, pos.y, pos.z, clampf(health / max_health, 0.0, 1.0)])


func on_event_pos(type: String, pos: Vector3) -> void:
	if !_rec:
		return
	for i in range(_rec_events.size() - 1, -1, -1):
		var e = _rec_events[i]
		if e[1] == type and e.size() == 2:
			e.append_array([pos.x, pos.y, pos.z])
			return
		if e[0] < _now_tick() - 1:
			break


func _on_fired() -> void:
	if _rec:
		_rec_events.append([_now_tick(), "shot"])


func _finish(g) -> void:
	_rec = false
	if is_instance_valid(_rec_player):
		_rec_done_id = _rec_player.get_instance_id()
		if _rec_player.has_signal("Fired") and _rec_player.Fired.is_connected(_on_fired):
			_rec_player.Fired.disconnect(_on_fired)
	_rec_player = null
	var died = _rec_died_at >= 0
	var save = (_rec_complete and !died) or (died and q.s.ghost_save_deaths)
	if !save:
		print("[qol] ghost: run not kept (%d ticks, not finished)" % _rec_ticks)
	if save and _rec_ticks > 1:
		var t = float(g.time) if !died else float(_rec_died_at) / _tps
		_rec_events.sort_custom(func(a, b): return a[0] < b[0])
		var header = {
			"v": FORMAT_VERSION, "level": _rec_level, "name": _player_name(),
			"time": t, "tps": _tps, "ticks": _rec_ticks, "end": "death" if died else "exfil",
			"skin": _rec_skin,
			"date": Time.get_datetime_string_from_system(false, true),
			"game": str(get_node("/root/Config").get("VERSION")) if get_node_or_null("/root/Config") else "",
			"recorder": "qol/1", "events": _rec_events,
		}
		if !_rec_cskin.is_empty():
			header["cskin"] = _rec_cskin
		var stamp = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
		var path = MINE + _rec_level + "/" + stamp + ("_death" if died else "") + "_%d.%s" % [roundi(t * 1000.0), EXT]
		var err = write_file(path, header, _rec_buf)
		if err == OK:
			last_saved = path
		print("[qol] ghost saved %s (%d ticks, %s, err %d)" % [path, _rec_ticks, header.end, err])
		_prune(_rec_level)
	_rec_buf = PackedByteArray()
	_rec_ticks = 0
	_rec_died_at = -1


func _player_name() -> String:
	if Engine.has_singleton("Steam"):
		var st = Engine.get_singleton("Steam")
		if st.has_method("getPersonaName"):
			return _clean_text(str(st.getPersonaName()), 32)
	return "PLAYER"


func _prune(level: String) -> void:
	var runs = list_runs(level).filter(func(r): return r.source == "mine" and !r.showcase)
	if runs.size() <= 3 + q.s.ghost_keep:
		return
	var keep = {}
	var by_time = runs.filter(func(r): return r.end == "exfil")
	by_time.sort_custom(func(a, b): return a.time < b.time)
	for i in mini(3, by_time.size()):
		keep[by_time[i].path] = true
	if q.s.x_keep_near > 0.0 and by_time.size() > 0:
		for r in by_time:
			if r.time <= by_time[0].time + q.s.x_keep_near:
				keep[r.path] = true
	for r in runs:
		if q.extras and q.extras.is_pinned(r.path):
			keep[r.path] = true
	var by_date = runs.duplicate()
	by_date.sort_custom(func(a, b): return a.mtime > b.mtime)
	for i in mini(q.s.ghost_keep, by_date.size()):
		keep[by_date[i].path] = true
	for r in runs:
		if !keep.has(r.path) and !_race_map.values().has(r.path):
			_delete(r.path)


func _ensure_key() -> bool:
	if _key:
		return true
	_key = CryptoKey.new()
	if FileAccess.file_exists(KEY_PATH) and _key.load(KEY_PATH) == OK:
		_pub_pem = _key.save_to_string(true)
		return true
	_key = _crypto.generate_rsa(2048)
	if _key == null:
		return false
	_key.save(KEY_PATH)
	_pub_pem = _key.save_to_string(true)
	return true


func _fingerprint(pem: String) -> String:
	return pem.sha256_text().substr(0, 16).to_upper()


func my_fingerprint() -> String:
	return _fingerprint(_pub_pem) if _ensure_key() else ""


func write_file(path: String, header: Dictionary, raw: PackedByteArray) -> int:
	if !_ensure_key():
		return ERR_CANT_CREATE
	header["signer"] = _pub_pem
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var hj = JSON.stringify(header).to_utf8_buffer()
	var comp = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var spb = StreamPeerBuffer.new()
	spb.put_data(MAGIC.to_ascii_buffer())
	spb.put_u16(FORMAT_VERSION)
	spb.put_u32(hj.size())
	spb.put_data(hj)
	spb.put_u32(raw.size())
	spb.put_u32(comp.size())
	spb.put_data(comp)
	var signed: PackedByteArray = spb.data_array
	var sig = _crypto.sign(HashingContext.HASH_SHA256, _sha256(signed), _key)
	spb.put_u32(sig.size())
	spb.put_data(sig)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(spb.data_array)
	f.close()
	_header_cache.erase(path)
	return OK


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var h = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()


func _clean_text(s: String, max_len: int) -> String:
	var out = ""
	for ch in s:
		var c = ch.unicode_at(0)
		if c >= 32 and c != 127 and !(c >= 0x200B and c <= 0x200F) and !(c >= 0x202A and c <= 0x202E):
			out += ch
	return out.strip_edges().substr(0, max_len)


func read_file(path: String, header_only: bool = false) -> Dictionary:
	var bytes = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return {"ok": false, "error": "UNREADABLE"}
	return parse_bytes(bytes, header_only, path)


func parse_bytes(bytes: PackedByteArray, header_only: bool = false, path: String = "") -> Dictionary:
	if bytes.size() > MAX_FILE or bytes.size() < 24:
		return {"ok": false, "error": "BAD SIZE"}
	if bytes.slice(0, 6).get_string_from_ascii() != MAGIC:
		return {"ok": false, "error": "NOT A GHOST FILE"}
	var o = 6
	var ver = bytes.decode_u16(o); o += 2
	if ver != FORMAT_VERSION:
		return {"ok": false, "error": "UNSUPPORTED VERSION %d" % ver}
	var hlen = bytes.decode_u32(o); o += 4
	if hlen <= 0 or hlen > 4 * 1024 * 1024 or o + hlen + 8 > bytes.size():
		return {"ok": false, "error": "BAD HEADER"}
	var parsed = JSON.parse_string(bytes.slice(o, o + hlen).get_string_from_utf8())
	o += hlen
	if !(parsed is Dictionary):
		return {"ok": false, "error": "BAD HEADER"}
	var h = _sanitize_header(parsed)
	if h.has("error"):
		return {"ok": false, "error": h.error}
	var raw_len = bytes.decode_u32(o); o += 4
	var comp_len = bytes.decode_u32(o); o += 4
	if raw_len != h.ticks * REC or comp_len <= 0 or o + comp_len + 4 > bytes.size():
		return {"ok": false, "error": "BAD BODY"}
	var signed_end = o + comp_len
	var sig_len = bytes.decode_u32(signed_end)
	if sig_len > 4096 or signed_end + 4 + sig_len != bytes.size():
		return {"ok": false, "error": "BAD SIGNATURE BLOCK"}
	h["path"] = path
	h["sig_ok"] = _verify_sig(bytes.slice(0, signed_end), bytes.slice(signed_end + 4), h.signer)
	if header_only:
		return {"ok": true, "ghost": h}
	var raw = bytes.slice(o, signed_end).decompress(raw_len, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_len:
		return {"ok": false, "error": "BAD BODY"}
	for i in h.ticks:
		var ro = i * REC
		for k in 14:
			var x = raw.decode_float(ro + k * 4)
			if is_nan(x) or is_inf(x) or absf(x) > 1.0e6:
				return {"ok": false, "error": "BAD VALUE AT TICK %d" % i}
	h["data"] = raw
	return {"ok": true, "ghost": h}


func _verify_sig(signed: PackedByteArray, sig: PackedByteArray, pem: String) -> bool:
	if pem == "" or sig.is_empty():
		return false
	var k = CryptoKey.new()
	if k.load_from_string(pem, true) != OK:
		return false
	return _crypto.verify(HashingContext.HASH_SHA256, _sha256(signed), sig, k)


func _num(v, lo: float, hi: float):
	if !(v is float or v is int):
		return null
	var f = float(v)
	if is_nan(f) or is_inf(f) or f < lo or f > hi:
		return null
	return f


func _sanitize_header(d: Dictionary) -> Dictionary:
	var level = d.get("level")
	var re = RegEx.create_from_string("^[A-Za-z0-9_]{1,48}$")
	if !(level is String) or re.search(level) == null:
		return {"error": "BAD LEVEL"}
	var g = get_node_or_null("/root/global")
	if g and g.get("level_data") is Dictionary and !g.level_data.has(level):
		return {"error": "UNKNOWN LEVEL " + level.to_upper()}
	var tps = _num(d.get("tps"), 10, 480)
	var t = _num(d.get("time"), 0.0, MAX_SECONDS)
	if tps == null or t == null:
		return {"error": "BAD TIMING"}
	var ticks = _num(d.get("ticks"), 2, MAX_SECONDS * tps + 2)
	if ticks == null:
		return {"error": "BAD LENGTH"}
	var events = []
	var src_events = d.get("events")
	if src_events is Array and src_events.size() <= MAX_EVENTS:
		for e in src_events:
			if e is Array and e.size() >= 2 and EVENT_TYPES.has(e[1]):
				var tk = _num(e[0], 0, ticks)
				if tk == null:
					continue
				var ev = [int(tk), String(e[1])]
				if e.size() >= 5:
					var x = _num(e[2], -1.0e6, 1.0e6)
					var y = _num(e[3], -1.0e6, 1.0e6)
					var z = _num(e[4], -1.0e6, 1.0e6)
					if x != null and y != null and z != null:
						ev.append_array([x, y, z])
						if e.size() >= 6 and ev[1] == "hit":
							var hp = _num(e[5], 0.0, 1.0)
							if hp != null:
								ev.append(hp)
				events.append(ev)
	var signer = d.get("signer")
	if !(signer is String) or signer.length() > 2048 or !signer.begins_with("-----BEGIN PUBLIC KEY-----"):
		signer = ""
	return {
		"level": level, "time": t, "tps": int(tps), "ticks": int(ticks), "events": events,
		"name": _clean_text(str(d.get("name", "?")), 32),
		"date": _clean_text(str(d.get("date", "")), 32),
		"game": _clean_text(str(d.get("game", "")), 24),
		"recorder": _clean_text(str(d.get("recorder", "")), 24),
		"end": "death" if d.get("end") == "death" else "exfil",
		"showcase": d.get("showcase") == true,
		"inferred": d.get("inferred") == true,
		"origin": _clean_text(str(d.get("origin", "")), 240),
		"skin": int(_num(d.get("skin"), 0, 4)) if _num(d.get("skin"), 0, 4) != null else -1,
		"cskin": _clean_cskin(d.get("cskin")),
		"signer": signer,
	}


func _clean_cskin(v) -> Dictionary:
	var out = {}
	if !(v is Dictionary):
		return out
	for slot in ["arms", "body", "joyeuse"]:
		var e = v.get(slot)
		if !(e is Dictionary) or !(e.get("hash") is String):
			continue
		var h: String = e.hash
		if h.length() != 64 or !h.is_valid_hex_number(false):
			continue
		out[slot] = {"hash": h.to_lower(), "name": _clean_text(str(e.get("name", "")), 40)}
	return out


func frame(gh: Dictionary, i: int) -> Dictionary:
	var d: PackedByteArray = gh.data
	var o = clampi(i, 0, gh.ticks - 1) * REC
	var qt = Quaternion(d.decode_float(o + 24), d.decode_float(o + 28), d.decode_float(o + 32), d.decode_float(o + 36)).normalized()
	var e = Basis(qt).get_euler()
	var flags = d.decode_u16(o + 56)
	return {
		"pos": Vector3(d.decode_float(o), d.decode_float(o + 4), d.decode_float(o + 8)),
		"cam_pos": Vector3(d.decode_float(o + 12), d.decode_float(o + 16), d.decode_float(o + 20)),
		"cam_quat": qt, "fov": d.decode_float(o + 40),
		"vel": Vector3(d.decode_float(o + 44), d.decode_float(o + 48), d.decode_float(o + 52)),
		"flags": flags, "jumps": d.decode_u8(o + 58), "hp": d.decode_u8(o + 59) / 10.0,
		"yaw": e.y, "pitch": e.x, "floor": (flags & F_FLOOR) != 0,
	}


func pose(gh: Dictionary, t: float, smooth: bool) -> Dictionary:
	var i = int(floor(t))
	var a = frame(gh, i)
	if !smooth or i >= gh.ticks - 1:
		return a
	var b = frame(gh, i + 1)
	var k = t - i
	a.pos = a.pos.lerp(b.pos, k)
	a.cam_pos = a.cam_pos.lerp(b.cam_pos, k)
	a.cam_quat = a.cam_quat.slerp(b.cam_quat, k)
	a.fov = lerpf(a.fov, b.fov, k)
	a.vel = a.vel.lerp(b.vel, k)
	var e = Basis(a.cam_quat).get_euler()
	a.yaw = e.y
	a.pitch = e.x
	return a


func audit(gh: Dictionary) -> Dictionary:
	var path = str(gh.get("path", ""))
	if path != "" and _audit_cache.has(path) and gh.has("data") == _audit_cache[path].full:
		return _audit_cache[path]
	var notes = []
	var state = "VERIFIED"
	if gh.signer == "":
		state = "UNSIGNED"
		notes.append("No signature: origin and integrity unknown.")
	elif !gh.sig_ok:
		state = "MODIFIED"
		notes.append("Signature does not match: the file was changed after it was recorded.")
	else:
		var pin = _pinned(gh.name)
		var fp = _fingerprint(gh.signer)
		if pin != "" and pin != fp:
			state = "SIGNER CHANGED"
			notes.append("Signed with a different key than earlier ghosts from %s (was %s, now %s)." % [gh.name, pin, fp])
	if gh.showcase and state == "VERIFIED":
		var r0 = {"state": "SHOWCASE", "notes": [
			"Showcase ghost: " + (gh.origin if gh.origin != "" else "not a live recording") + ".",
			"Not a verified record. It was never submitted anywhere."], "full": gh.has("data")}
		if path != "":
			_audit_cache[path] = r0
		return r0
	var expect_ticks = roundi(gh.time * gh.tps)
	if gh.end == "death":
		if absi(gh.ticks - 1 - expect_ticks - roundi(DEATH_TAIL * gh.tps)) > 2:
			notes.append("Length does not match a death at %s." % _fmt(gh.time))
			if state == "VERIFIED": state = "SUSPICIOUS"
	elif absi(gh.ticks - 1 - expect_ticks) > 2:
		notes.append("Length (%d ticks) does not match the time %s." % [gh.ticks, _fmt(gh.time)])
		if state == "VERIFIED": state = "SUSPICIOUS"
	if gh.end == "exfil" and !gh.events.any(func(e): return e[1] == "exfil"):
		notes.append("No exfil event recorded.")
		if state == "VERIFIED": state = "SUSPICIOUS"
	if gh.has("data"):
		var phys = _physics_audit(gh)
		notes.append_array(phys.notes)
		if phys.bad and state == "VERIFIED":
			state = "SUSPICIOUS"
	var r = {"state": state, "notes": notes, "full": gh.has("data")}
	if path != "":
		_audit_cache[path] = r
	return r


func _physics_audit(gh: Dictionary) -> Dictionary:
	var dt = 1.0 / gh.tps
	var teleports = 0
	var drift = 0
	var fast = 0
	var detached = 0
	var first_bad = -1
	var prev = frame(gh, 0)
	for i in range(1, gh.ticks):
		var f = frame(gh, i)
		var moved = f.pos.distance_to(prev.pos)
		var allowed = maxf(f.vel.length(), prev.vel.length()) * dt * 1.6 + 0.35
		if moved > 6.0:
			teleports += 1
			if first_bad < 0: first_bad = i
		elif moved > allowed:
			drift += 1
		if f.vel.length() > 220.0:
			fast += 1
			if first_bad < 0: first_bad = i
		if f.cam_pos.distance_to(f.pos) > 4.0:
			detached += 1
			if first_bad < 0: first_bad = i
		prev = f
	var notes = []
	var bad = false
	if teleports > 0:
		notes.append("%d teleport(s) over 6 m in one tick." % teleports)
		bad = true

	if drift > maxi(30, gh.ticks / 25):
		notes.append("%d ticks moved further than their recorded velocity allows." % drift)
		bad = true
	if fast > 0:
		notes.append("%d ticks above any reachable speed." % fast)
		bad = true
	if detached > 0:
		notes.append("Camera detached from the body on %d ticks." % detached)
		bad = true
	if first_bad >= 0:
		notes.append("First anomaly at %s (tick %d)." % [_fmt(float(first_bad) / gh.tps), first_bad])
	if !bad:
		notes.append("Movement consistent with the game's physics on all %d ticks." % gh.ticks)
	return {"bad": bad, "notes": notes}


func _pinned(name: String) -> String:
	var cfg = ConfigFile.new()
	if cfg.load(SIGNERS_PATH) != OK:
		return ""
	return str(cfg.get_value("signers", name.to_lower(), ""))


func _pin(name: String, pem: String) -> void:
	if pem == "" or name == "":
		return
	var cfg = ConfigFile.new()
	cfg.load(SIGNERS_PATH)
	if str(cfg.get_value("signers", name.to_lower(), "")) == "":
		cfg.set_value("signers", name.to_lower(), _fingerprint(pem))
		cfg.save(SIGNERS_PATH)


static func badge_color(state: String) -> Color:
	match state:
		"VERIFIED": return Color("3fd46b")
		"SHOWCASE": return Color("b07cff")
		"SUSPICIOUS", "UNSIGNED": return Color("ea8f1f")
	return Color("c42b47")


func _fmt(t: float) -> String:
	return q.format_time(t) if q and q.has_method("format_time") else "%.3f" % t


func _files_in(dir: String) -> Array:
	var out = []
	var da = DirAccess.open(dir)
	if da == null:
		return out
	for f in da.get_files():
		if f.get_extension().to_lower() == EXT:
			out.append(dir.path_join(f))
	return out


func _info(path: String, source: String):
	var mt = FileAccess.get_modified_time(path)
	if _header_cache.has(path) and _header_cache[path].mtime == mt:
		return _header_cache[path].info
	var r = read_file(path, true)
	var info = null
	if r.ok:
		info = r.ghost
		info["source"] = source
		info["mtime"] = mt
	_header_cache[path] = {"mtime": mt, "info": info}
	return info


func list_levels() -> Array:
	var counts = {}
	for base in [MINE, IMPORTED]:
		var da = DirAccess.open(base)
		if da == null:
			continue
		for lvl in da.get_directories():
			var n = _files_in(base + lvl).size()
			if n > 0:
				counts[lvl] = counts.get(lvl, 0) + n
	var out = []
	for lvl in counts:
		out.append({"level": lvl, "count": counts[lvl]})
	out.sort_custom(func(a, b): return a.level < b.level)
	return out


func list_runs(level: String) -> Array:
	var out = []
	for pair in [[MINE, "mine"], [IMPORTED, "imported"]]:
		for path in _files_in(pair[0] + level):
			var info = _info(path, pair[1])
			if info:
				out.append(info)
	out.sort_custom(func(a, b): return a.time < b.time)
	return out


func load_ghost(path: String):
	var r = read_file(path)
	if !r.ok:
		_status = "COULD NOT LOAD: " + r.error
		return null
	r.ghost["source"] = "mine" if path.begins_with(MINE) else "imported"

	if r.ghost.skin < 0:
		var saves = get_node_or_null("/root/saves")
		var cur = saves.get("skin_joyeuse") if saves and r.ghost.source == "mine" else null
		r.ghost.skin = clampi(int(cur), 0, 4) if cur != null else 0
	return r.ghost


func level_title(level: String) -> String:
	var g = get_node_or_null("/root/global")
	if g and g.get("level_data") is Dictionary and g.level_data.has(level):
		var d = g.level_data[level]
		return (str(d.get("pretitle", "")) + " " + str(d.get("title", ""))).strip_edges().to_upper()
	return level.to_upper()


func import_path(src: String) -> String:
	var bytes = FileAccess.get_file_as_bytes(src)
	if bytes.is_empty():
		return "UNREADABLE"
	var r = parse_bytes(bytes, false, src)
	if !r.ok:
		return r.error
	var gh = r.ghost
	var safe_name = _clean_text(gh.name, 32).to_lower().validate_filename().replace(" ", "_")
	var dst = IMPORTED + gh.level + "/%s_%d_%s.%s" % [safe_name, roundi(gh.time * 1000.0), bytes.sha256_text().substr(0, 8), EXT]
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var f = FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return "CANNOT WRITE"
	f.store_buffer(bytes)
	f.close()

	if gh.sig_ok:
		_pin(gh.name, gh.signer)
	return ""


func _import_inbox() -> String:
	var ok = 0
	var errors = []
	for path in _files_in(INBOX):
		var err = import_path(path)
		if err == "":
			ok += 1
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			errors.append(path.get_file() + ": " + err)
	if ok == 0 and errors.is_empty():
		return "INBOX IS EMPTY"
	return "IMPORTED %d" % ok + ("" if errors.is_empty() else "  /  FAILED: " + ", ".join(errors))


func _on_files_dropped(files: PackedStringArray) -> void:
	var ok = 0
	var errors = []
	for path in files:
		if path.get_extension().to_lower() != EXT:
			continue
		var err = import_path(path)
		if err == "":
			ok += 1
		else:
			errors.append(path.get_file() + ": " + err)
	if ok == 0 and errors.is_empty():
		return
	_status = "IMPORTED %d" % ok + ("" if errors.is_empty() else "  /  FAILED: " + ", ".join(errors))
	print("[qol] ghost drop: ", _status)
	_refresh()


func export_run(path: String) -> String:
	var info = _info(path, "mine" if path.begins_with(MINE) else "imported")
	if info == null:
		return "COULD NOT READ"
	var name = "%s_%s_%s.%s" % [info.level, _fmt(info.time).replace(":", "-").replace(".", "-").replace(" ", ""), info.name.validate_filename().replace(" ", "_"), EXT]
	var dst = EXPORT_DIR + name
	var bytes = FileAccess.get_file_as_bytes(path)
	var f = FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return "CANNOT WRITE"
	f.store_buffer(bytes)
	f.close()
	OS.shell_open(ProjectSettings.globalize_path(EXPORT_DIR))
	return "EXPORTED " + name.to_upper()


func _delete(path: String) -> void:
	if !path.begins_with(ROOT) or path.get_extension() != EXT:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_header_cache.erase(path)
	_audit_cache.erase(path)
	_sel_runs.erase(path)


func _load_race_map() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(RACE_PATH) == OK:
		for k in cfg.get_section_keys("race"):
			_race_map[k] = str(cfg.get_value("race", k))


func _save_race_map() -> void:
	var cfg = ConfigFile.new()
	for k in _race_map:
		cfg.set_value("race", k, _race_map[k])
	cfg.save(RACE_PATH)


func _update_race(g, p, running: bool) -> void:
	var level = str(g.currentlevel)
	var want = running and q.s.ghost_race and is_instance_valid(p) and _race_map.has(level)
	var scene = get_tree().current_scene
	if _race and (!want or _race.scene != scene or !is_instance_valid(_race.body) or _race.level != level):
		if is_instance_valid(_race.body):
			_race.body.queue_free()
		_race = null
	if want and _race == null and scene:
		var gh = load_ghost(_race_map[level])
		if gh == null or gh.level != level:
			_race_map.erase(level)
			_save_race_map()
			return
		var body = load("res://gdpatch/mods/qol/ghost_body.gd").new()
		body.name = "QolRaceGhost"
		scene.add_child(body)
		body.setup(Color("2fc4e0"), q.s.ghost_race_alpha, gh.get("cskin", {}))
		_race = {"gh": gh, "body": body, "scene": scene, "level": level}
	if _race:
		var t = float(g.time) * _race.gh.tps
		_race.body.show_pose(pose(_race.gh, t, true), get_physics_process_delta_time())


func _build_library(area: Control):
	var hub = _hub()
	var col_w = hub.COL_W
	var gap = hub.COL_GAP
	var h = hub.PAGE_H
	var focus_target: Control = null
	var first: Control = null

	var levels = list_levels()
	if _sel_level == "" or !levels.any(func(l): return l.level == _sel_level):
		_sel_level = levels[0].level if !levels.is_empty() else ""


	_box_header(area, hub, Rect2(0, 0, col_w, 30), "LEVELS")
	var lscroll = _scroll(area, Rect2(0, 34, col_w, h - 34 - 58))
	var llist: VBoxContainer = lscroll.get_child(0)
	if levels.is_empty():
		llist.add_child(hub.make_label("NO GHOSTS YET. FINISH A LEVEL, OR DRAG A .CGHOST ONTO THE WINDOW.", 16, Color(0.8, 0.8, 0.8)))
	for l in levels:
		var b = hub.make_button("%s   %d" % [level_title(l.level), l.count], 18)
		b.custom_minimum_size = Vector2(col_w - 14, 30)
		_mark(b, "lvl:" + l.level, l.level == _sel_level)
		b.pressed.connect(func():
			_sel_level = l.level
			_sel_runs.clear()
			_focus_key = "lvl:" + l.level
			_refresh())
		llist.add_child(b)
		if first == null: first = b
		if _focus_key == "lvl:" + l.level: focus_target = b

	var status = hub.make_label(_status, 15, Color(0.85, 0.85, 0.85))
	status.position = Vector2(0, h - 54)
	status.size = Vector2(col_w, 54)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	area.add_child(status)


	var rx = col_w + gap
	_box_header(area, hub, Rect2(rx, 0, col_w, 30), "RUNS" + ("  /  " + level_title(_sel_level) if _sel_level != "" else ""))
	var rscroll = _scroll(area, Rect2(rx, 34, col_w, h - 34 - 112))
	var rlist: VBoxContainer = rscroll.get_child(0)
	var runs = list_runs(_sel_level) if _sel_level != "" else []
	if _cursor_run != "" and !runs.any(func(r): return r.path == _cursor_run):
		_cursor_run = ""
	if _cursor_run == "" and !runs.is_empty():
		_cursor_run = runs[0].path
	for r in runs:
		var a = audit(r)
		var tag = "YOU" if r.source == "mine" else r.name
		var race = " RACE" if _race_map.get(r.level, "") == r.path else ""
		var sel = _sel_runs.find(r.path)
		var mark = "[%d] " % (sel + 1) if sel >= 0 else ""
		var end_tag = "  DEATH" if r.end == "death" else ("  SHOWCASE" if r.showcase else "")
		var b = hub.make_button("%s%s%s  %s  %s%s" % [mark, _fmt(r.time), end_tag, tag, a.state, race], 17)
		b.custom_minimum_size = Vector2(col_w - 14, 28)
		b.add_theme_color_override("font_color", badge_color(a.state) if a.state != "VERIFIED" else Color(1, 1, 1))
		_mark(b, "run:" + r.path, r.path == _cursor_run)
		b.set_meta("desc", "%s  /  %s  /  %s\nINTEGRITY: %s. %s" % [r.name, _fmt(r.time), r.date, a.state, " ".join(a.notes)])
		b.pressed.connect(func():
			_cursor_run = r.path
			var i = _sel_runs.find(r.path)
			if i >= 0:
				_sel_runs.remove_at(i)
			elif _sel_runs.size() < 4:
				_sel_runs.append(r.path)
			_focus_key = "run:" + r.path
			_refresh())
		rlist.add_child(b)
		if _focus_key == "run:" + r.path: focus_target = b


	var actions = [
		["WATCH", "Watch selected runs in the ghost theater. Select up to 4 to compare.", _act_watch],
		["SELECT", "Add or remove highlighted run from selection.", _act_select],
		["RACE", "Show highlighted run as a race ghost on this level. Press again to clear.", _act_race],
		["EXPORT", "Save highlighted run to the export folder for sharing.", _act_export],
		["DELETE", "Delete highlighted run.", _act_delete],
		["CHECK", "Check highlighted run for tampering.", _act_check],
	]
	var bw = (col_w - 8) / 3.0
	for i in actions.size():
		var act = actions[i]
		var b = hub.make_button(act[0], 20)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.position = Vector2(rx + (i % 3) * (bw + 4), h - 74 + (i / 3) * 38)
		b.size = Vector2(bw, 34)
		b.set_meta("desc", act[1])
		b.disabled = runs.is_empty()
		var key = "act:" + act[0]
		b.pressed.connect(func():
			_focus_key = key
			act[2].call())
		area.add_child(b)
		if _focus_key == key: focus_target = b
	return focus_target if focus_target else first


func _mark(b: Button, key: String, on: bool) -> void:
	b.set_meta("gk", key)
	if on:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.25, 0.25, 0.25)
		b.add_theme_stylebox_override("normal", sb)


func _box_header(area: Control, hub, r: Rect2, text: String) -> void:
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.position = r.position
	bg.size = r.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(bg)
	var l = hub.make_label(text, 20, Color("c42b47"), true)
	l.position = r.position + Vector2(8, 0)
	l.size = r.size - Vector2(8, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	area.add_child(l)


func _scroll(area: Control, r: Rect2) -> ScrollContainer:
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = r.position
	bg.size = r.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(bg)
	var sc = ScrollContainer.new()
	sc.position = r.position + Vector2(4, 4)
	sc.size = r.size - Vector2(8, 8)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	area.add_child(sc)
	return sc


func _act_select() -> void:
	if _cursor_run == "":
		return
	var i = _sel_runs.find(_cursor_run)
	if i >= 0:
		_sel_runs.remove_at(i)
	elif _sel_runs.size() < 4:
		_sel_runs.append(_cursor_run)
	_refresh()


func _act_watch() -> void:
	var paths = _sel_runs.duplicate() if !_sel_runs.is_empty() else ([_cursor_run] if _cursor_run != "" else [])
	var ghosts = []
	for p in paths:
		var gh = load_ghost(p)
		if gh:
			gh["audit"] = audit(gh)
			ghosts.append(gh)
	ghosts = ghosts.filter(func(x): return x.level == (ghosts[0].level if !ghosts.is_empty() else ""))
	if ghosts.is_empty():
		_refresh()
		return
	theater.request(ghosts, _hub().page_options() if _hub() else null)


func _act_race() -> void:
	if _cursor_run == "":
		return
	var info = _info(_cursor_run, "")
	if info == null:
		return
	if _race_map.get(info.level, "") == _cursor_run:
		_race_map.erase(info.level)
		_status = "RACE GHOST CLEARED FOR " + level_title(info.level)
	else:
		_race_map[info.level] = _cursor_run
		_status = "RACE GHOST SET: %s %s" % [info.name, _fmt(info.time)]
	_save_race_map()
	_refresh()


func _act_export() -> void:
	if _cursor_run != "":
		_status = export_run(_cursor_run)
		_refresh()


func _act_delete() -> void:
	if _cursor_run == "":
		return
	if _race_map.values().has(_cursor_run):
		for k in _race_map.keys():
			if _race_map[k] == _cursor_run:
				_race_map.erase(k)
		_save_race_map()
	_delete(_cursor_run)
	_cursor_run = ""
	_status = "DELETED"
	_refresh()


func _act_check() -> void:
	if _cursor_run == "":
		return
	_audit_cache.erase(_cursor_run)
	var gh = load_ghost(_cursor_run)
	if gh:
		var a = audit(gh)
		_status = "%s: %s" % [a.state, " ".join(a.notes)]
	_refresh()


func convert_game_ghost(level: String) -> String:
	var g = get_node_or_null("/root/global")
	if g == null or str(g.get("savelocation")) == "":
		return "SAVE LOCATION UNKNOWN"
	var src = str(g.savelocation) + "Ghosts/" + level + ".res"
	if !FileAccess.file_exists(src):
		return "NO GAME PB GHOST FOR " + level_title(level)

	var anim = ResourceLoader.load(src, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if !(anim is Animation) or anim.get_track_count() < 8 or anim.length <= 0.0:
		return "UNEXPECTED GHOST LAYOUT"
	var tps = Engine.get_physics_ticks_per_second()
	var ticks = int(round(anim.length * tps)) + 1
	if ticks < 2 or ticks > MAX_SECONDS * tps:
		return "BAD GHOST LENGTH"
	var fov = 90.0
	var cfg = get_node_or_null("/root/Config")
	if cfg and cfg.get("FOV") != null:
		fov = float(cfg.FOV)

	var pos = []
	var yaw = []
	var pitch = []
	var air = []
	for i in ticks:
		var tt = minf(float(i) / tps, anim.length)
		pos.append(anim.position_track_interpolate(0, tt))
		yaw.append(wrapf(anim.rotation_track_interpolate(1, tt).get_euler().y + PI, -PI, PI))
		var xr = anim.value_track_interpolate(5, tt)
		pitch.append(-float(xr) if (xr is float or xr is int) else 0.0)
		var ma = anim.value_track_interpolate(3, tt)
		air.append(float(ma) if (ma is float or ma is int) else 0.0)

	var events = [[0, "deploy"]]
	for k in anim.track_get_key_count(6):
		var v = anim.track_get_key_value(6, k)
		var tk = clampi(roundi(anim.track_get_key_time(6, k) * tps), 0, ticks - 1)
		if v is Dictionary:
			if v.get("method") == "Fire":
				events.append([tk, "shot"])
			elif v.get("method") == "Jump":
				events.append([tk, "jump"])


	var vels = []
	for i in ticks:
		var lo = maxi(i - 2, 0)
		var hi = mini(i + 2, ticks - 1)
		vels.append((pos[hi] - pos[lo]) * tps / maxf(float(hi - lo), 1.0))
	var dashing = []
	for i in ticks:
		dashing.append(Vector2(vels[i].x, vels[i].z).length() > SHOWCASE_DASH_SPEED)
	var raw = PackedByteArray()
	var last_dash = -1000
	for i in ticks:
		var vel = vels[i]
		var dash = dashing[i] and ((i >= 2 and dashing[i - 1] and dashing[i - 2]) or (i + 2 < ticks and dashing[i + 1] and dashing[i + 2]))
		if dash and (i == 0 or !dashing[i - 1] or i - last_dash > 20) and i - last_dash > 20:
			events.append([i, "dash"])
			last_dash = i
		elif dash:
			last_dash = i
		var q = Basis.from_euler(Vector3(pitch[i], yaw[i], 0)).get_rotation_quaternion()
		var cam = pos[i] + HEAD_OFFSET
		var rec = PackedByteArray()
		rec.resize(REC)
		var vals = [pos[i].x, pos[i].y, pos[i].z, cam.x, cam.y, cam.z, q.x, q.y, q.z, q.w, fov, vel.x, vel.y, vel.z]
		for k in vals.size():
			rec.encode_float(k * 4, vals[k])
		var f = 0
		if air[i] < 0.5: f |= F_FLOOR
		if dash: f |= F_DASH
		if i == ticks - 1: f |= F_EXFIL
		rec.encode_u16(56, f)
		raw.append_array(rec)
	events.append([ticks - 1, "exfil"])
	events.sort_custom(func(x, y): return x[0] < y[0])


	var time = anim.length
	var saves = get_node_or_null("/root/saves")
	if saves and saves.has_method("_get_time"):
		var pb = float(saves._get_time(level))
		if pb > 0.0 and absf(pb - anim.length) < 0.25:
			time = pb
	var header = {
		"v": FORMAT_VERSION, "level": level, "name": _player_name(), "time": time,
		"tps": tps, "ticks": ticks, "end": "exfil", "skin": 0,
		"date": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(src)),
		"game": str(cfg.get("VERSION")) if cfg else "", "recorder": "qol/1 showcase",
		"showcase": true, "inferred": true,
		"origin": "converted from the game's own PB ghost for this level (positions as precise as the game's compressed ghost; camera, velocity, dashes, cores and kills reconstructed)",
		"events": events,
	}
	var saves_skin = saves.get("skin_joyeuse") if saves else null
	if saves_skin != null:
		header.skin = int(saves_skin)
	var path = MINE + level + "/showcase_%d.%s" % [roundi(time * 1000.0), EXT]
	var err = write_file(path, header, raw)
	if err != OK:
		return "COULD NOT WRITE (%d)" % err
	print("[qol] showcase: %s -> %s (%d ticks, %d events)" % [src, path, ticks, events.size()])
	return "SHOWCASE GHOST MADE: %s %s" % [level_title(level), _fmt(time)]
