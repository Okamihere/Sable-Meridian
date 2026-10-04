class_name ThirdPersonCameraController
extends Node3D

const TARGET_BLEND_DURATION := 0.22

## Câmera em terceira pessoa com órbita, suavização e enquadramento do lock-on.
##
## O SpringArm3D evita atravessar o cenário; impactos aplicam tremor e variação de FOV.
## A câmera segue o jogador com suavização exponencial e ajusta a distância
## automaticamente quando há um alvo de lock-on.
##
## Uso típico:
##   - Adicionar como filho da cena (não do jogador)
##   - Configurar [member player_path] para apontar para o jogador
##   - A câmera captura o mouse automaticamente

## Caminho para o jogador.
@export var player_path: NodePath = NodePath("../Player")
## Sensibilidade do mouse.
@export var mouse_sensitivity: float = 0.0028
## Pitch mínimo em graus.
@export var min_pitch_degrees: float = -55.0
## Pitch máximo em graus.
@export var max_pitch_degrees: float = 35.0
## Altura da câmera acima do jogador.
@export var follow_height: float = 1.35
## Velocidade de suavização do seguimento.
@export var camera_lag: float = 12.0
## Velocidade de suavização da rotação.
@export var rotation_lag: float = 10.0
## Distância base da câmera.
@export var base_distance: float = 6.4
## Distância desejada ajustável com a roda, antes da colisão do SpringArm.
@export var min_distance: float = 3.2
@export var max_distance: float = 9.2
@export var zoom_step: float = 0.75
@export var zoom_smoothing: float = 9.0
## Bônus de distância máxima com lock-on.
@export var lock_distance_bonus: float = 2.6
## FOV base da câmera.
@export var base_fov: float = 72.0
## Deslocamento sutil do jogador para a esquerda da composição.
@export var composition_offset: float = 0.3
@export var lock_composition_offset: float = 0.23
@export var composition_smoothing: float = 7.0
@export var lock_focus_enter_duration: float = 0.26
@export var lock_focus_exit_duration: float = 0.38
@export_range(0.0, 1.0, 0.01) var lock_blur_strength: float = 0.46
@export_range(0.0, 1.0, 0.01) var lock_desaturation_strength: float = 0.84
@export_range(0.0, 200.0, 0.1) var desaturation_near: float = 8.0
@export_range(0.0, 500.0, 0.1) var desaturation_far: float = 32.0

## Referência ao SpringArm3D.
@onready var spring_arm: SpringArm3D = $SpringArm3D
## Referência à Camera3D.
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var lock_focus: MeshInstance3D = $SpringArm3D/Camera3D/LockFocus

## Referência ao jogador.
var _player: Node3D
## Yaw atual da câmera.
var _yaw: float = 0.0
## Pitch atual da câmera.
var _pitch: float = deg_to_rad(-12.0)
## Força do tremor de câmera.
var _shake_strength: float = 0.0
## Velocidade de decaimento do tremor.
var _shake_decay: float = 8.0
## Tween de FOV atual.
var _fov_tween: Tween
var _zoom_distance: float = 6.4
var _composition: float = 0.0
var _lock_focus_amount: float = 0.0
var _focus_transition_locked: bool = false
var _focus_transition_from: float = 0.0
var _focus_transition_elapsed: float = 0.0
var _focus_transition_duration: float = 0.0
var _target_blend_elapsed: float = TARGET_BLEND_DURATION
var _focus_material: ShaderMaterial
var _focus_target: Node3D

## Inicializa a câmera: configura SpringArm, captura mouse e posiciona.
func _ready() -> void:
	mouse_sensitivity = GameManager.camera_sensitivity
	GameManager.camera_sensitivity_changed.connect(_on_camera_sensitivity_changed)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player = get_node_or_null(player_path) as Node3D
	
	# Initialize shader parameters with current values
	_focus_material = lock_focus.material_override as ShaderMaterial
	if _focus_material:
		_focus_material.set_shader_parameter("desaturation_near", desaturation_near)
		_focus_material.set_shader_parameter("desaturation_far", desaturation_far)
		_focus_material.set_shader_parameter("target_blend", 1.0)

## Callback quando a sensibilidade da câmera muda (via GameManager).
func _on_camera_sensitivity_changed(value: float) -> void:
	mouse_sensitivity = value
	_zoom_distance = clampf(base_distance, min_distance, max_distance)
	spring_arm.spring_length = _zoom_distance
	camera.fov = base_fov
	_composition = composition_offset
	camera.h_offset = _composition
	_focus_material = lock_focus.material_override as ShaderMaterial
	camera.add_to_group("game_camera")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(_player):
		global_position = _player.global_position + Vector3.UP * follow_height
		yaw_from_player()

## Processa input de mouse para órbita da câmera.
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch -= motion.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	elif event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				adjust_zoom(-1)
				get_viewport().set_input_as_handled()
				return
			if button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				adjust_zoom(1)
				get_viewport().set_input_as_handled()
				return
		if button_event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Alteração incremental; o SpringArm interpola até este alvo e continua colidindo.
func adjust_zoom(steps: int) -> void:
	_zoom_distance = clampf(_zoom_distance + float(steps) * zoom_step, min_distance, max_distance)

## Processa seguimento suavizado do jogador e ajuste de lock-on.
func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var lock_target: Node3D = null
	if _player.has_method("get_lock_target"):
		lock_target = _player.call("get_lock_target") as Node3D
	
	# Validate lock_target: must be alive and in range
	if is_instance_valid(lock_target):
		if lock_target.has_method("is_alive") and not lock_target.call("is_alive"):
			lock_target = null
	
	var locked := is_instance_valid(lock_target)
	
	# First, advance the lock focus transition (starts/stops transition)
	# This must run BEFORE _update_lock_focus so the transition state is updated
	_advance_lock_focus(locked, delta)
	
	# Then update lock focus with the validated target (sets shader params)
	# This must run BEFORE handling acquisition logic so shader params are set
	_update_lock_focus(lock_target)
	
	# Handle target acquisition
	if locked:
		var first_acquisition := not is_instance_valid(_focus_target)
		var target_switched := is_instance_valid(_focus_target) and _focus_target != lock_target and _lock_focus_amount > 0.0
		
		if first_acquisition:
			# Initialize previous_target from current target on FIRST acquisition
			print("DEBUG: First acquisition - initializing previous_target")
			var prev_uv = _focus_material.get_shader_parameter("target_uv")
			var prev_radius = _focus_material.get_shader_parameter("target_radius")
			print("DEBUG: target_uv = ", prev_uv, " target_radius = ", prev_radius)
			_focus_material.set_shader_parameter("previous_target_uv", prev_uv)
			_focus_material.set_shader_parameter("previous_target_radius", prev_radius)
			_target_blend_elapsed = 0.0
		elif target_switched:
			# Switching targets: copy current to previous, reset blend
			_focus_material.set_shader_parameter("previous_target_uv", _focus_material.get_shader_parameter("target_uv"))
			_focus_material.set_shader_parameter("previous_target_radius", _focus_material.get_shader_parameter("target_radius"))
			_target_blend_elapsed = 0.0
		
		_focus_target = lock_target
	
	# Handle target loss
	if not locked and is_instance_valid(_focus_target):
		# Lock lost: clear focus_target immediately to prevent dead target leakage
		_focus_target = null
		# Clear previous_target in shader to avoid stale data on next acquisition
		_focus_material.set_shader_parameter("previous_target_uv", Vector2(0.5, 0.5))
		_focus_material.set_shader_parameter("previous_target_radius", Vector2(0.08, 0.16))
		_target_blend_elapsed = 0.0
	
	var follow_target := _player.global_position + Vector3.UP * follow_height
	if locked:
		var toward_target := lock_target.global_position - _player.global_position
		toward_target.y = 0.0
		follow_target += toward_target.limit_length(7.0) * 0.12
	global_position = global_position.lerp(follow_target, 1.0 - exp(-camera_lag * delta))
	if is_instance_valid(lock_target):
		var direction := lock_target.global_position - _player.global_position
		direction.y = 0.0
		if direction.length_squared() > 0.01:
			var desired_yaw := atan2(-direction.x, -direction.z)
			_yaw = lerp_angle(_yaw, desired_yaw, 1.0 - exp(-rotation_lag * delta))
		var target_distance := clampf(_zoom_distance + minf(lock_distance_bonus, _player.global_position.distance_to(lock_target.global_position) * 0.12), min_distance, max_distance)
		spring_arm.spring_length = lerpf(spring_arm.spring_length, target_distance, 1.0 - exp(-zoom_smoothing * delta))
	else:
		spring_arm.spring_length = lerpf(spring_arm.spring_length, _zoom_distance, 1.0 - exp(-zoom_smoothing * delta))
	rotation.y = _yaw
	spring_arm.rotation.x = _pitch
	_composition = lerpf(_composition, lock_composition_offset if locked else composition_offset, 1.0 - exp(-composition_smoothing * delta))
	_target_blend_elapsed = minf(_target_blend_elapsed + delta, TARGET_BLEND_DURATION)
	_update_shake(delta)

## Reposiciona a câmera imediatamente para a posição do jogador.
func snap_to_player() -> void:
	if not is_instance_valid(_player):
		return
	global_position = _player.global_position + Vector3.UP * follow_height
	_composition = composition_offset
	camera.h_offset = _composition
	camera.v_offset = 0.0

## Define o yaw da câmera baseado na rotação do jogador.
func yaw_from_player() -> void:
	if is_instance_valid(_player):
		_yaw = _player.rotation.y + PI

## Aplica tremor de câmera.
## @param strength Força do tremor.
## @param duration Duração do tremor (em segundos).
func shake(strength: float = 0.10, duration: float = 0.12) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_decay = maxf(1.0, strength / maxf(duration, 0.01))

## Aplica impacto de câmera (tremor + kick de FOV).
## @param strength Força do impacto.
## @param heavy Indica se é um golpe pesado.
func hit_impulse(strength: float, heavy: bool = false) -> void:
	shake(strength, 0.10 if not heavy else 0.16)
	kick_fov(2.0 if not heavy else 4.0, 0.12 if not heavy else 0.18)

## Aplica kick de FOV com tween.
## @param amount Quantidade de FOV a adicionar.
## @param duration Duração do efeito (em segundos).
func kick_fov(amount: float, duration: float) -> void:
	if is_instance_valid(_fov_tween):
		_fov_tween.kill()
	camera.fov = base_fov
	_fov_tween = create_tween()
	_fov_tween.tween_property(camera, "fov", base_fov + amount, duration * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fov_tween.tween_property(camera, "fov", base_fov, duration * 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

## Atualiza o tremor de câmera.
func _update_shake(delta: float) -> void:
	if _shake_strength <= 0.001:
		camera.h_offset = lerpf(camera.h_offset, _composition, clampf(delta * 18.0, 0.0, 1.0))
		camera.v_offset = lerpf(camera.v_offset, 0.0, clampf(delta * 18.0, 0.0, 1.0))
		return
	camera.h_offset = _composition + randf_range(-_shake_strength, _shake_strength)
	camera.v_offset = randf_range(-_shake_strength, _shake_strength)
	_shake_strength = maxf(0.0, _shake_strength - _shake_decay * delta)

func _advance_lock_focus(locked: bool, delta: float) -> void:
	if locked != _focus_transition_locked:
		_focus_transition_locked = locked
		_focus_transition_from = _lock_focus_amount
		_focus_transition_elapsed = 0.0
		var full_duration := lock_focus_enter_duration if locked else lock_focus_exit_duration
		_focus_transition_duration = maxf(0.001, full_duration * absf((1.0 if locked else 0.0) - _lock_focus_amount))
	_focus_transition_elapsed = minf(_focus_transition_elapsed + delta, _focus_transition_duration)
	var progress := smoothstep(0.0, 1.0, _focus_transition_elapsed / maxf(_focus_transition_duration, 0.001))
	_lock_focus_amount = lerpf(_focus_transition_from, 1.0 if locked else 0.0, progress)

func _update_lock_focus(target: Node3D) -> void:
	lock_focus.visible = _focus_transition_locked or _lock_focus_amount > 0.0
	if not lock_focus.visible:
		_focus_target = null
		return
	if _focus_material == null:
		return
	_focus_material.set_shader_parameter("focus_progress", _lock_focus_amount)
	_focus_material.set_shader_parameter("blur_strength", lock_blur_strength)
	_focus_material.set_shader_parameter("desaturation_strength", lock_desaturation_strength)
	_focus_material.set_shader_parameter("desaturation_near", desaturation_near)
	_focus_material.set_shader_parameter("desaturation_far", desaturation_far)
	_focus_material.set_shader_parameter("target_blend", smoothstep(0.0, TARGET_BLEND_DURATION, _target_blend_elapsed))
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_set_focus_subject("player", _player.global_position, 2.25, viewport_size)
	if is_instance_valid(target):
		_set_focus_subject("target", target.global_position, 2.1, viewport_size)
	else:
		# Target lost/dead: ensure target_uv/radius are set to defaults
		# so the shader doesn't use stale data
		_focus_material.set_shader_parameter("target_uv", Vector2(0.5, 0.5))
		_focus_material.set_shader_parameter("target_radius", Vector2(0.08, 0.16))

func _set_focus_subject(prefix: String, world_position: Vector3, height: float, viewport_size: Vector2) -> void:
	var feet := camera.unproject_position(world_position)
	var head := camera.unproject_position(world_position + Vector3.UP * height)
	var center := (feet + head) * 0.5
	var radius_y := maxf(24.0, absf(feet.y - head.y) * 0.58 + 10.0)
	var radius_x := radius_y * 0.65
	_focus_material.set_shader_parameter(prefix + "_uv", center / viewport_size)
	_focus_material.set_shader_parameter(prefix + "_radius", Vector2(radius_x / viewport_size.x, radius_y / viewport_size.y))
