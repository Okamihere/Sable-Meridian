extends Area3D

## Expositor reutilizável: aproximação equipa a arma sem retirar a peça da sala.
@export var weapon_id: StringName
@export var title: String
@export_multiline var description: String
@export var accent: Color = Color(0.72, 0.38, 1.0)

const GRIMOIRE_MODEL := preload("res://assets/3d model/grimorio.glb")

var _time := 0.0
var _display: Node3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.3
	cylinder.height = 2.8
	shape.position.y = 1.4
	shape.shape = cylinder
	add_child(shape)
	var base := CylinderMesh.new()
	base.top_radius = 0.75
	base.bottom_radius = 0.9
	base.height = 0.55
	base.radial_segments = 8
	_mesh(base, Vector3(0, 0.28, 0), Color(0.13, 0.11, 0.22))
	var rim := CylinderMesh.new()
	rim.top_radius = 0.8
	rim.bottom_radius = 0.8
	rim.height = 0.055
	rim.radial_segments = 8
	_mesh(rim, Vector3(0, 0.57, 0), accent)
	_display = Node3D.new()
	_display.position.y = 1.45
	add_child(_display)
	_make_symbol()
	_light = OmniLight3D.new()
	_light.position.y = 1.8
	_light.light_color = accent
	_light.light_energy = 1.4
	_light.omni_range = 3.5
	add_child(_light)
	_label(title.to_upper(), 2.6, 38)
	_label(description, 2.17, 23)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	_display.rotation.y += delta * 0.7
	_display.position.y = 1.45 + sin(_time * 2.1) * 0.1
	_light.light_energy = 1.35 + sin(_time * 2.1) * 0.25

func _on_body_entered(body: Node3D) -> void:
	if not body is PlayerController or not body.is_alive():
		return
	if body.equipment.weapon == null:
		body.equip_staff()
	if body.equipment.unlock_weapon(weapon_id):
		body.equipment.request_weapon(weapon_id)
		var hud := get_parent().get_node_or_null("HUD")
		if hud != null:
			hud.show_notice(title.to_upper(), description.replace("\n", "  •  "), 3.0)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color * 0.45
	return material

func _mesh(mesh: Mesh, at: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	visual.material_override = _material(color)
	(parent if parent != null else self).add_child(visual)
	return visual

func _box(size: Vector3, at: Vector3, color: Color, angle: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := _mesh(mesh, at, color, _display)
	visual.rotation.z = angle

func _make_symbol() -> void:
	match weapon_id:
		&"card_daggers":
			_box(Vector3(0.15, 1.25, 0.08), Vector3(-0.2, 0, 0), accent, -0.38)
			_box(Vector3(0.15, 1.25, 0.08), Vector3(0.2, 0, 0), accent, 0.38)
			_box(Vector3(0.5, 0.7, 0.045), Vector3(0, 0.05, 0.07), Color(0.91, 0.83, 0.72), PI / 4.0)
		&"puppet_strings":
			for offset in [-0.34, 0.0, 0.34]:
				_box(Vector3(0.035, 1.55, 0.035), Vector3(offset, 0, 0), accent)
			_box(Vector3(1.25, 0.12, 0.12), Vector3(0, 0.7, 0), accent)
		&"cane_blade":
			_box(Vector3(0.09, 1.4, 0.09), Vector3(0, -0.12, 0), accent, -0.18)
			_box(Vector3(0.44, 0.09, 0.09), Vector3(0.12, 0.6, 0), Color(0.95, 0.82, 0.56))
		&"living_grimoire":
			var book := GRIMOIRE_MODEL.instantiate() as Node3D
			book.scale = Vector3.ONE * 0.32
			book.position = Vector3(0.074, 0.005, 0.049)
			_display.add_child(book)

func _label(copy: String, height: float, size: int) -> void:
	var label := Label3D.new()
	label.position = Vector3(0, height, 0)
	label.pixel_size = 0.003
	label.billboard = 1
	label.modulate = Color(0.97, 0.9, 0.78)
	label.outline_modulate = Color(0.03, 0.02, 0.07)
	label.outline_size = 7
	label.font_size = size
	label.text = copy
	add_child(label)
