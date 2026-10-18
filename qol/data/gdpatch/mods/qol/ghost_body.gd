extends Node3D

# The visible ghost: the game's own ghost model, used by the race ghost and the theater.


const SPEED_REGULAR = 12.0
const JUMP_VELOCITY = 14.0
const ANIM_STEP = 1.0 / 12.0

const GUN_SKINS = [
	"res://Assets/Models/BunnyGal FPS Anims_joy_tex.png",
	"res://Assets/Models/joyDEMO_tex.png",
	"res://Assets/Models/joyKLLR_tex.png",
	"res://Assets/Models/joyRBBT_tex.png",
	"res://Assets/Models/joyFLWR_tex.png",
]

const PLAYER_FX = ["DashParticles", "SlopeParticles", "stompparticles", "fallparticles",
	"zonedparticles", "starstruckparticles", "ZonedBurst", "StarBurst"]

const ONE_SHOTS = {
	"fire": [["parameters/GunMovement/Fire/blend_amount", "parameters/GunMovement/FireSeek/seek_request"]],
	"jump": [["parameters/GunMovement/Jump/blend_amount", "parameters/GunMovement/JumpReset/seek_request"],
		["parameters/Jump/blend_amount", "parameters/JumpReset/seek_request"]],
	"land": [["parameters/GunMovement/LandBlend/blend_amount", "parameters/GunMovement/LandReset/seek_request"]],
	"dash": [["parameters/GunMovement/Dash/blend_amount", "parameters/GunMovement/DashReset/seek_request"]],
	"core": [["parameters/GunMovement/CoreCollect/blend_amount", "parameters/GunMovement/CoreCollectReset/seek_request"]],
	"star": [["parameters/GunMovement/StarStruck/blend_amount", "parameters/GunMovement/StarStruckReset/seek_request"]],
}
const ONE_SHOT_LEN = {"fire": 0.45, "jump": 0.7, "land": 0.45, "dash": 0.7, "core": 1.2, "star": 1.2}
const FADE = 0.15

var color = Color(1, 1, 1)
var theater = false
var _model: Node3D = null
var _tree: AnimationTree = null
var _spine: Node = null
var _gun: Node3D = null
var _fallback: MeshInstance3D = null
var _anim_acc = 0.0

var _fx_root: Node3D = null
var _parts = {}
var _prev_flags = -1
var _tag: Label3D = null
var _body_mats = []


func _instance_model() -> Node:
	var scn = load("res://Scenes/System/ghost.tscn") if ResourceLoader.exists("res://Scenes/System/ghost.tscn") else null
	var inst = scn.instantiate() if scn else null
	if inst:

		for c in inst.get_incoming_connections():
			if c.signal.is_connected(c.callable):
				c.signal.disconnect(c.callable)
		inst.set_script(null)
		_model = inst.get_node_or_null("BunnyGal")
	if _model == null:
		if inst:
			inst.free()
		return null
	add_child(inst)
	_model.visible = true
	_tree = _model.get_node_or_null("AnimationTree")
	if _tree:
		_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_tree.active = true
	_spine = _model.get_node_or_null("rig/Skeleton3D/SpineLook")
	_gun = _model.get_node_or_null("GunRotator")
	var ik = _model.get_node_or_null("rig/Skeleton3D/SkeletonIK3D")
	if ik and ik.has_method("start"):
		ik.start()
	return inst


func setup(tint: Color, alpha: float = 1.0, cskin: Dictionary = {}) -> void:
	color = tint
	var inst = _instance_model()
	if inst == null:
		_make_fallback(alpha)
		return
	_apply_skins(inst, cskin)
	_tint(_model, alpha)


func _apply_skins(inst: Node, cskin: Dictionary) -> Dictionary:
	if !Engine.has_meta("skinkit"):
		return {}
	return Engine.get_meta("skinkit").replay_apply(inst, cskin)


func _tint(node: Node, alpha: float) -> void:
	if node is MeshInstance3D:
		var m = node.get_active_material(0)
		if m is ShaderMaterial:
			var d: ShaderMaterial = m.duplicate()
			var a = d.get_shader_parameter("albedo")
			if a is Color:
				d.set_shader_parameter("albedo", Color(color.r, color.g, color.b, a.a * alpha))
			node.material_override = d
		elif m is BaseMaterial3D:
			var d2: BaseMaterial3D = m.duplicate()
			d2.albedo_color = Color(color, d2.albedo_color.a * alpha)
			node.material_override = d2
	for c in node.get_children():
		_tint(c, alpha)


func _make_fallback(alpha: float) -> void:
	_fallback = MeshInstance3D.new()
	var cap = CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	_fallback.mesh = cap
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.45 * alpha)
	_fallback.material_override = mat
	add_child(_fallback)


func show_pose(pose: Dictionary, delta: float) -> void:
	if _fallback:
		_fallback.position = pose.pos + Vector3(0, 0.9, 0)
		_fallback.rotation = Vector3(0, pose.yaw, 0)
		return
	_place(pose)
	if _tree:
		var v: Vector3 = pose.vel
		_tree.set("parameters/Movement/blend_position", Vector2(v.x, -v.z).rotated(-pose.yaw) / SPEED_REGULAR)
		_tree.set("parameters/MidAir/blend_amount", 0.0 if pose.floor else 1.0)
		_tree.set("parameters/Up/blend_amount", clampf(v.y / (JUMP_VELOCITY * 0.5), 0.0, 1.0))
		_anim_acc += absf(delta)
		if _anim_acc >= ANIM_STEP:
			_tree.advance(_anim_acc)
			_anim_acc = 0.0


func _place(pose: Dictionary) -> void:
	_model.position = pose.pos
	_model.quaternion = Quaternion.from_euler(Vector3(0, pose.yaw - PI, 0))
	if _spine:
		_spine.set("XRot", -pose.pitch)
	if _gun:
		_gun.quaternion = Quaternion.from_euler(Vector3(-pose.pitch + PI * 0.5, 0, 0))


func setup_theater(tint: Color, skin: int, tag_text: String, player: Node, cskin: Dictionary = {}) -> void:
	color = tint
	theater = true
	var inst = _instance_model()
	if inst == null:
		_make_fallback(1.0)
	else:
		var debug_capsule = inst.get_node_or_null("Ghost2")
		if debug_capsule:
			debug_capsule.visible = false
		var shown = _apply_skins(inst, cskin)

		if cskin.has("joyeuse") and !shown.get("joyeuse_custom", false):
			skin = 0
		_character_materials(_model, clampi(skin, 0, GUN_SKINS.size() - 1), shown.get("joyeuse_texture", false))

	_fx_root = Node3D.new()
	_fx_root.name = "FX"
	add_child(_fx_root)
	if is_instance_valid(player):
		for n in PLAYER_FX:
			var src = player.get_node_or_null(n)
			if src is GPUParticles3D:
				var d: GPUParticles3D = src.duplicate()
				d.emitting = false
				d.visible = true
				d.transform = src.transform
				_fx_root.add_child(d)
				_parts[n] = d

	_tag = Label3D.new()
	_tag.text = tag_text
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.fixed_size = true
	_tag.pixel_size = 0.0012
	_tag.font_size = 22
	_tag.outline_size = 8
	_tag.modulate = tint
	_tag.outline_modulate = Color(0, 0, 0, 0.9)
	if ResourceLoader.exists("res://Assets/Fonts/bitpop.otf"):
		_tag.font = load("res://Assets/Fonts/bitpop.otf")
	add_child(_tag)


func _character_materials(node: Node, skin: int, own_gun_texture: bool = false) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var src = node.get_active_material(i)
			var tex = null
			if src is ShaderMaterial:
				tex = src.get_shader_parameter("texture_albedo")
			elif src is BaseMaterial3D:
				tex = src.albedo_texture
			if node.name == "Joyeuse" and !own_gun_texture and ResourceLoader.exists(GUN_SKINS[skin]):
				tex = load(GUN_SKINS[skin])
			var m = StandardMaterial3D.new()
			m.albedo_texture = tex
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.roughness = 1.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.emission_enabled = true
			m.emission = Color("c42b47")
			m.emission_energy_multiplier = 0.0
			node.set_surface_override_material(i, m)
			_body_mats.append(m)
	for c in node.get_children():
		_character_materials(c, skin, own_gun_texture)


func reset_fx() -> void:
	for n in _parts:
		_parts[n].emitting = false
		_parts[n].restart()
		_parts[n].emitting = false
	_prev_flags = -1


func show_tag(on: bool) -> void:
	if _tag:
		_tag.visible = on


func drive(st: Dictionary, delta: float, forward: bool) -> void:
	if _tag:
		_tag.position = st.pos + Vector3(0, 2.4, 0)
	if _fallback:
		_fallback.position = st.pos + Vector3(0, 0.9, 0)
		_fallback.rotation = Vector3(0, st.yaw, 0)
		_drive_fx(st, forward)
		return
	_place(st)

	var dead = st.dead
	_model.visible = dead < 0.0 or (dead < 0.45 and int(dead * 20.0) % 2 == 0)
	var hurt = st.since.get("hurt", -1.0)
	var glow = 0.0
	if hurt >= 0.0 and hurt < 0.35:
		glow = 2.5 * (1.0 - hurt / 0.35)
	if dead >= 0.0:
		glow = 4.0
	for m in _body_mats:
		m.emission_energy_multiplier = glow

	if _tree:
		var v: Vector3 = st.vel
		var hv = Vector2(v.x, v.z).length()
		var air = 0.0 if st.floor else 1.0
		_tree.set("parameters/Movement/blend_position", Vector2(v.x, -v.z).rotated(-st.yaw) / SPEED_REGULAR)
		_tree.set("parameters/MidAir/blend_amount", air)
		_tree.set("parameters/Up/blend_amount", clampf(v.y / (JUMP_VELOCITY * 0.5), 0.0, 1.0))
		_tree.set("parameters/GunMovement/Moving/blend_amount", clampf(hv / 4.0, 0.0, 1.0))
		_tree.set("parameters/GunMovement/MidAir/blend_amount", air)
		_tree.set("parameters/GunMovement/AirState/blend_amount", clampf(v.y + 1.0, 0.0, 1.0))
		_tree.set("parameters/GunMovement/Stomp/blend_amount", 1.0 if st.flags & 8 else 0.0)
		for kind in ONE_SHOTS:
			var since = st.since.get(kind, -1.0)
			var length = ONE_SHOT_LEN[kind]
			var w = 0.0
			if since >= 0.0 and since < length:
				w = 1.0 if since < length - FADE else (length - since) / FADE
			for pair in ONE_SHOTS[kind]:
				_tree.set(pair[0], w)
				if w > 0.0:
					_tree.set(pair[1], since)
		_tree.advance(absf(delta))
	_drive_fx(st, forward)


func _drive_fx(st: Dictionary, forward: bool) -> void:
	if _fx_root == null:
		return
	_fx_root.position = st.pos
	var f: int = st.flags
	_emit("DashParticles", (f & 4) != 0)
	if _parts.has("DashParticles"):
		_parts.DashParticles.rotation.y = st.yaw
	_emit("SlopeParticles", (f & 16) != 0)
	_emit("stompparticles", (f & 8) != 0)
	_emit("fallparticles", st.vel.y < -10.0)
	_emit("zonedparticles", (f & 64) != 0)
	_emit("starstruckparticles", (f & 128) != 0)
	if forward and _prev_flags >= 0:
		if (f & 64) and !(_prev_flags & 64):
			_burst("ZonedBurst")
		if (f & 128) and !(_prev_flags & 128):
			_burst("StarBurst")
	_prev_flags = f


func _emit(n: String, on: bool) -> void:
	if _parts.has(n) and _parts[n].emitting != on:
		_parts[n].emitting = on


func _burst(n: String) -> void:
	if _parts.has(n):
		_parts[n].restart()
		_parts[n].emitting = true
