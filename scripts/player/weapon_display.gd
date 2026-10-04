extends Node3D

## Adereços 3D compactos ao lado do AnimatedSprite3D, ligados ao equipamento atual.
const STAFF := preload("res://scenes/player/mage_staff.tscn")
const BLADE := preload("res://scenes/player/card_blade.tscn")
const GRIMOIRE_MODEL := preload("res://assets/3d model/grimorio.glb")

var _props: Dictionary = {}
var _equipped: StringName = &""
var _player: PlayerController

func _ready() -> void:
	_player = get_parent() as PlayerController
	_props[&"staff"] = _make_staff()
	_props[&"card_daggers"] = _make_daggers()
	_props[&"puppet_strings"] = _make_strings()
	_props[&"cane_blade"] = _make_cane()
	_props[&"living_grimoire"] = _make_grimoire()
	for prop in _props.values():
		prop.visible = false

func show_weapon(id: StringName) -> void:
	_equipped = id
	for key in _props:
		(_props[key] as Node3D).visible = key == id

func _process(delta: float) -> void:
	if _equipped == &"" or not is_instance_valid(_player):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var toward_camera := camera.global_position - _player.global_position
	toward_camera.y = 0.0
	toward_camera = toward_camera.normalized()
	var attacking := _player.combat != null and _player.combat.is_attacking()
	var offset := right * (0.57 if attacking else 0.68) + toward_camera * (0.32 if attacking else 0.43)
	if attacking:
		offset += _player.global_basis.z * 0.28
	var height := 1.02 if attacking else 0.92
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var bob := 0.025 * sin(Time.get_ticks_msec() * 0.012) * clampf(speed / 7.0, 0.0, 1.0)
	var target := _player.to_local(_player.global_position + offset + Vector3.UP * (height + bob))
	position = position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))
	look_at(camera.global_position, Vector3.UP)
	rotate_y(PI)
	var prop := _props.get(_equipped) as Node3D
	if prop == null:
		return
	var attack_tilt := 0.0
	var idle_tilt := 0.0
	match _equipped:
		&"staff":
			attack_tilt = -0.75
			idle_tilt = -0.42
		&"card_daggers": attack_tilt = -0.48
		&"puppet_strings": attack_tilt = 0.32
		&"cane_blade": attack_tilt = -0.9
		&"living_grimoire":
			attack_tilt = 0.18
			idle_tilt = -0.18
	prop.rotation.z = lerp_angle(prop.rotation.z, attack_tilt if attacking else idle_tilt, clampf(delta * 16.0, 0.0, 1.0))

func _make_staff() -> Node3D:
	var prop := STAFF.instantiate() as Node3D
	prop.name = "EquippedStaff"
	prop.scale = Vector3.ONE * 0.73
	prop.rotation_degrees.z = -24.0
	add_child(prop)
	return prop

func _make_daggers() -> Node3D:
	var holder := Node3D.new()
	holder.name = "EquippedCardDaggers"
	add_child(holder)
	for side in [-1.0, 1.0]:
		var blade := BLADE.instantiate() as Node3D
		blade.position = Vector3(side * 0.11, 0.24, side * 0.025)
		blade.rotation_degrees.z = side * 20.0
		blade.scale = Vector3.ONE * 0.88
		holder.add_child(blade)
	return holder

func _make_strings() -> Node3D:
	var holder := Node3D.new()
	holder.name = "EquippedPuppetStrings"
	add_child(holder)
	var dark := _material(Color(0.12, 0.13, 0.28), 0.0)
	var cyan := _material(Color(0.28, 0.82, 0.92), 1.7)
	_box(holder, Vector3.ZERO, Vector3(0.61, 0.36, 0.23), dark)
	_box(holder, Vector3(0.0, 0.02, 0.14), Vector3(0.41, 0.065, 0.035), cyan)
	for side in [-1.0, 1.0]:
		_box(holder, Vector3(side * 0.22, -0.4, 0.06), Vector3(0.035, 0.7, 0.035), cyan)
		_box(holder, Vector3(side * 0.22, 0.0, 0.14), Vector3(0.07, 0.25, 0.03), cyan)
	return holder

func _make_cane() -> Node3D:
	var holder := Node3D.new()
	holder.name = "EquippedCaneBlade"
	add_child(holder)
	var dark := _material(Color(0.16, 0.11, 0.26), 0.25)
	var gold := _material(Color(0.86, 0.63, 0.28), 0.3)
	_box(holder, Vector3(0.0, 0.0, 0.0), Vector3(0.085, 1.34, 0.085), dark)
	_box(holder, Vector3(0.12, 0.68, 0.0), Vector3(0.33, 0.085, 0.085), gold)
	_box(holder, Vector3(0.27, 0.55, 0.0), Vector3(0.075, 0.27, 0.075), gold)
	_box(holder, Vector3(0.0, -0.68, 0.0), Vector3(0.1, 0.14, 0.1), gold)
	return holder

func _make_grimoire() -> Node3D:
	var holder := Node3D.new()
	holder.name = "EquippedLivingGrimoire"
	add_child(holder)
	var book := GRIMOIRE_MODEL.instantiate() as Node3D
	book.scale = Vector3.ONE * 0.2
	book.position = Vector3(0.046, 0.003, 0.031)
	holder.add_child(book)
	holder.rotation_degrees.z = -10.0
	return holder

func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.position = at
	parent.add_child(visual)
	return visual
