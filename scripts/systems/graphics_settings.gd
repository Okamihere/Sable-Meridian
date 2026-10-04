extends Node

## Sistema centralizado de configurações gráficas.
##
## Gerencia presets (LOW/MEDIUM/HIGH/ULTRA/CUSTOM), aplica configurações
## via Viewport/RenderingServer/Environment e persiste em user://graphics_settings.cfg.
##
## Renderer atual do projeto: GL Compatibility (Godot 4.7).
## Por isso, SOMENTE estas opções têm efeito real e são expostas:
## - MSAA 3D, Render Scale, FSR 1 (espacial), filtro anisotrópico
## - tamanho dos atlas de sombra, SSAO, Fog padrão, Glow/Bloom
##
## NÃO têm efeito no Compatibility e por isso NÃO são expostas:
## TAA, FSR 2 (temporal), FXAA/SMAA, SSIL, volumetric fog, debanding.
## (Ver tabela oficial "Overview of renderers" para Compatibility.)
##
## Chaves legadas (fxaa, ssil_enabled, volumetric_fog_quality) continuam
## sendo lidas/preservadas no arquivo por compatibilidade, mas não dirigem nada.

signal preset_changed(preset_name: String)
signal settings_applied()

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

const SETTINGS_PATH := "user://graphics_settings.cfg"

## Preset atual
var current_preset: Preset = Preset.HIGH

## Configurações individuais (valores < 0 seguem o preset atual).
var render_scale: float = -1.0
var scaling_3d_mode: int = -1 # Reservado para Forward+; no Compatibility só Bilinear tem efeito (o motor avisa e ignora FSR).
var scaling_sharpness: float = 0.2 # nitidez do FSR (0.0 - 1.0); sem efeito no Compatibility, preservado para o futuro
var msaa_3d: int = -1
var anisotropic_filter: int = -1
var shadow_quality: int = -1 # 0 Baixa / 1 Média / 2 Alta -> atlas de sombra 1024 / 2048 / 4096
var ssao_enabled: bool = false
var fog_enabled: bool = true
var glow_enabled: bool = true

# Campos legados: preservados no arquivo, sem efeito na renderização.
var fxaa: bool = false
var ssil_enabled: bool = false
var volumetric_fog_quality: int = -1

const SHADOW_ATLAS_SIZES := [1024, 2048, 4096]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_apply_settings()
	_apply_to_environments.call_deferred()
	if get_tree().has_signal("scene_changed"):
		get_tree().scene_changed.connect(func() -> void: _apply_to_environments.call_deferred())


## Aplica um preset e atualiza todas as configurações
func apply_preset(preset: Preset) -> void:
	current_preset = preset
	match preset:
		Preset.LOW:
			render_scale = 0.75
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			msaa_3d = 0
			anisotropic_filter = 1
			shadow_quality = 0
			ssao_enabled = false
			fog_enabled = true
			glow_enabled = true
		Preset.MEDIUM:
			render_scale = 0.85
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			msaa_3d = 1
			anisotropic_filter = 2
			shadow_quality = 1
			ssao_enabled = false
			fog_enabled = true
			glow_enabled = true
		Preset.HIGH:
			render_scale = 1.0
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			msaa_3d = 2
			anisotropic_filter = 3
			shadow_quality = 2
			ssao_enabled = false
			fog_enabled = true
			glow_enabled = true
		Preset.ULTRA:
			render_scale = 1.0
			scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			msaa_3d = 3
			anisotropic_filter = 4
			shadow_quality = 2
			ssao_enabled = false
			fog_enabled = true
			glow_enabled = true
		Preset.CUSTOM:
			pass
	_apply_settings()
	_apply_to_environments()
	preset_changed.emit(_preset_to_string(preset))


## Aplica as configurações atuais (efeito imediato + padrões de boot).
func _apply_settings() -> void:
	var vp := get_viewport()
	if vp == null:
		return

	if render_scale >= 0.0:
		vp.scaling_3d_scale = render_scale
		RenderingServer.viewport_set_scaling_3d_scale(vp.get_viewport_rid(), render_scale)

	if scaling_3d_mode >= 0:
		var method := scaling_3d_mode as Viewport.Scaling3DMode
		if method != Viewport.SCALING_3D_MODE_BILINEAR and _is_compatibility_renderer():
			method = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_mode = method
	vp.fsr_sharpness = clampf(scaling_sharpness, 0.0, 1.0)

	if msaa_3d >= 0:
		ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", msaa_3d)
		vp.msaa_3d = msaa_3d as Viewport.MSAA

	if anisotropic_filter >= 0:
		# Afeta texturas carregadas depois da troca; já carregadas exigem reiniciar.
		ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", anisotropic_filter)

	if shadow_quality >= 0:
		var atlas: int = SHADOW_ATLAS_SIZES[clampi(shadow_quality, 0, 2)]
		vp.positional_shadow_atlas_size = atlas
		RenderingServer.directional_shadow_atlas_set_size(atlas, true)

	_apply_to_environments()
	settings_applied.emit()


## True quando o renderer efetivo é o GL Compatibility (sem FSR/TAA/FXAA/SSIL/volumetric).
func _is_compatibility_renderer() -> bool:
	return String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "gl_compatibility"


## Aplica fog/glow/ssao aos Environments da fase atual (sem tocar nos assets em disco).
## A tela de título ("title_screen") mantém o visual autoral e é ignorada.
func _apply_to_environments() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var scene := get_tree().current_scene
	if scene.is_in_group("title_screen"):
		return
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is WorldEnvironment:
			var env := (node as WorldEnvironment).environment
			if env != null:
				env.fog_enabled = fog_enabled
				env.glow_enabled = glow_enabled
				env.ssao_enabled = ssao_enabled
		for child in node.get_children():
			stack.append(child)


## Define uma configuração individual e muda para CUSTOM se não for o valor do preset atual
func set_setting(setting_name: String, value: Variant) -> void:
	match setting_name:
		"render_scale": render_scale = value
		"scaling_3d_mode": scaling_3d_mode = value
		"scaling_sharpness": scaling_sharpness = value
		"msaa_3d": msaa_3d = value
		"anisotropic_filter": anisotropic_filter = value
		"shadow_quality": shadow_quality = value
		"ssao_enabled": ssao_enabled = value
		"fog_enabled": fog_enabled = value
		"glow_enabled": glow_enabled = value
		# Legados: aceitos por compatibilidade, sem efeito.
		"fxaa": fxaa = value
		"ssil_enabled": ssil_enabled = value
		"volumetric_fog_quality": volumetric_fog_quality = value
		_: return

	if current_preset != Preset.CUSTOM:
		_verify_if_still_matches_preset()

	_apply_settings()


## Verifica se as configurações atuais ainda correspondem ao preset selecionado
func _verify_if_still_matches_preset() -> void:
	if current_preset == Preset.CUSTOM:
		return

	var matches := true
	match current_preset:
		Preset.LOW:
			matches = (render_scale == 0.75 and scaling_3d_mode == 0 and msaa_3d == 0 and
				anisotropic_filter == 1 and shadow_quality == 0 and ssao_enabled == false and
				fog_enabled == true and glow_enabled == true)
		Preset.MEDIUM:
			matches = (render_scale == 0.85 and scaling_3d_mode == 0 and msaa_3d == 1 and
				anisotropic_filter == 2 and shadow_quality == 1 and ssao_enabled == false and
				fog_enabled == true and glow_enabled == true)
		Preset.HIGH:
			matches = (render_scale == 1.0 and scaling_3d_mode == 0 and msaa_3d == 2 and
				anisotropic_filter == 3 and shadow_quality == 2 and ssao_enabled == false and
				fog_enabled == true and glow_enabled == true)
		Preset.ULTRA:
			matches = (render_scale == 1.0 and scaling_3d_mode == 0 and msaa_3d == 3 and
				anisotropic_filter == 4 and shadow_quality == 2 and ssao_enabled == false and
				fog_enabled == true and glow_enabled == true)

	if not matches:
		current_preset = Preset.CUSTOM
		preset_changed.emit("CUSTOM")


## Restaura os valores padrão (preset HIGH)
func restore_defaults() -> void:
	render_scale = -1.0
	scaling_3d_mode = -1
	scaling_sharpness = 0.2
	msaa_3d = -1
	anisotropic_filter = -1
	shadow_quality = -1
	ssao_enabled = false
	fog_enabled = true
	glow_enabled = true

	apply_preset(Preset.HIGH)


## Carrega configurações salvas
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		apply_preset(Preset.HIGH)
		return

	current_preset = int(config.get_value("graphics", "preset", int(Preset.HIGH)))
	render_scale = float(config.get_value("graphics", "render_scale", -1.0))
	scaling_3d_mode = int(config.get_value("graphics", "scaling_3d_mode", -1))
	if scaling_3d_mode != -1 and scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR and _is_compatibility_renderer():
		scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR # migração: FSR salvo não tem efeito aqui
	scaling_sharpness = clampf(float(config.get_value("graphics", "scaling_sharpness", 0.2)), 0.0, 1.0)
	msaa_3d = int(config.get_value("graphics", "msaa_3d", -1))
	anisotropic_filter = int(config.get_value("graphics", "anisotropic_filter", -1))
	shadow_quality = int(config.get_value("graphics", "shadow_quality", -1))
	ssao_enabled = bool(config.get_value("graphics", "ssao_enabled", false))
	fog_enabled = bool(config.get_value("graphics", "fog_enabled", true))
	glow_enabled = bool(config.get_value("graphics", "glow_enabled", true))
	# Legados (sem efeito, preservados).
	fxaa = bool(config.get_value("graphics", "fxaa", false))
	ssil_enabled = bool(config.get_value("graphics", "ssil_enabled", false))
	volumetric_fog_quality = int(config.get_value("graphics", "volumetric_fog_quality", -1))

	_apply_settings()


## Salva configurações atuais (chamado pelo menu de opções após cada mudança).
func save_settings() -> void:
	_save_settings()


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "preset", int(current_preset))
	config.set_value("graphics", "render_scale", render_scale)
	config.set_value("graphics", "scaling_3d_mode", scaling_3d_mode)
	config.set_value("graphics", "scaling_sharpness", scaling_sharpness)
	config.set_value("graphics", "msaa_3d", msaa_3d)
	config.set_value("graphics", "anisotropic_filter", anisotropic_filter)
	config.set_value("graphics", "shadow_quality", shadow_quality)
	config.set_value("graphics", "ssao_enabled", ssao_enabled)
	config.set_value("graphics", "fog_enabled", fog_enabled)
	config.set_value("graphics", "glow_enabled", glow_enabled)
	config.set_value("graphics", "fxaa", fxaa)
	config.set_value("graphics", "ssil_enabled", ssil_enabled)
	config.set_value("graphics", "volumetric_fog_quality", volumetric_fog_quality)

	var result := config.save(SETTINGS_PATH)
	if result != OK:
		push_warning("Não foi possível salvar configurações gráficas: %s" % error_string(result))


## Retorna o nome do preset atual
func get_current_preset_name() -> String:
	return _preset_to_string(current_preset)


func _preset_to_string(preset: Preset) -> String:
	match preset:
		Preset.LOW: return "LOW"
		Preset.MEDIUM: return "MEDIUM"
		Preset.HIGH: return "HIGH"
		Preset.ULTRA: return "ULTRA"
		Preset.CUSTOM: return "CUSTOM"
	return "CUSTOM"


## Obtém o valor efetivo de uma configuração (considerando preset)
func get_effective_value(setting_name: String) -> Variant:
	match setting_name:
		"render_scale":
			if render_scale >= 0.0: return render_scale
			return _get_preset_value(current_preset, "render_scale")
		"scaling_3d_mode":
			if scaling_3d_mode >= 0: return scaling_3d_mode
			return _get_preset_value(current_preset, "scaling_3d_mode")
		"scaling_sharpness": return scaling_sharpness
		"msaa_3d":
			if msaa_3d >= 0: return msaa_3d
			return _get_preset_value(current_preset, "msaa_3d")
		"anisotropic_filter":
			if anisotropic_filter >= 0: return anisotropic_filter
			return _get_preset_value(current_preset, "anisotropic_filter")
		"shadow_quality":
			if shadow_quality >= 0: return shadow_quality
			return _get_preset_value(current_preset, "shadow_quality")
		"ssao_enabled": return ssao_enabled
		"fog_enabled": return fog_enabled
		"glow_enabled": return glow_enabled
	return null


func _get_preset_value(preset: Preset, setting: String) -> Variant:
	match preset:
		Preset.LOW:
			match setting:
				"render_scale": return 0.75
				"scaling_3d_mode": return 0
				"msaa_3d": return 0
				"anisotropic_filter": return 1
				"shadow_quality": return 0
				"ssao_enabled": return false
				"fog_enabled": return true
				"glow_enabled": return true
		Preset.MEDIUM:
			match setting:
				"render_scale": return 0.85
				"scaling_3d_mode": return 0
				"msaa_3d": return 1
				"anisotropic_filter": return 2
				"shadow_quality": return 1
				"ssao_enabled": return false
				"fog_enabled": return true
				"glow_enabled": return true
		Preset.HIGH:
			match setting:
				"render_scale": return 1.0
				"scaling_3d_mode": return 0
				"msaa_3d": return 2
				"anisotropic_filter": return 3
				"shadow_quality": return 2
				"ssao_enabled": return false
				"fog_enabled": return true
				"glow_enabled": return true
		Preset.ULTRA:
			match setting:
				"render_scale": return 1.0
				"scaling_3d_mode": return 0
				"msaa_3d": return 3
				"anisotropic_filter": return 4
				"shadow_quality": return 2
				"ssao_enabled": return false
				"fog_enabled": return true
				"glow_enabled": return true
	return null
