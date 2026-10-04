extends SceneTree

## Exercita o fluxo entre título, pátio, NPC, pausa e configurações.
func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	await _frames(3)
	var menu := root.get_node("PauseMenu")
	var progress := root.get_node("Progression")
	menu.settings_path = "user://settings_flow_test.cfg"
	progress.save_path = "user://settings_flow_orbs_test.cfg"
	change_scene_to_file("res://scenes/ui/title_screen.tscn")
	await _frames(5)
	current_scene._on_choice("new_game")
	await create_timer(0.8).timeout
	await _frames(20)
	assert(current_scene.scene_file_path.ends_with("start_room.tscn"), "Novo jogo deve abrir o pátio")
	var initial_gameplay_mouse := Input.mouse_mode
	var player := current_scene.get_node("Player")
	var mentor := current_scene.get_node("Mentor") as Node3D
	player.global_position = mentor.global_position + mentor.global_basis.z * 1.5
	await _frames(20)
	var npc := root.get_node("NpcInteraction")
	assert(npc.try_interact(), "NPC deve ser interativo")
	assert(npc.dialogue_box.text_label.text == "Não vim ensinar você a vencer. Vim descobrir o que fará quando puder.", "Fala aprovada deve ser única")
	npc.dialogue_box.close_dialogue()
	menu.open_pause()
	assert(paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause deve liberar mouse")
	menu.show_options()
	assert(menu._tab_pages.size() == 4, "Quatro categorias devem existir")
	menu._show_tab(1)
	menu._volume_sliders["Master"].value = 55
	menu._volume_sliders["Music"].value = 70
	menu._volume_sliders["SFX"].value = 35
	assert(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) - linear_to_db(0.55)) < 0.1, "Volume geral deve alterar bus")
	assert(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.70)) < 0.1, "Música deve alterar bus")
	assert(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.35)) < 0.1, "Efeitos devem alterar bus")
	menu._show_tab(0)
	menu._fps_selector.item_selected.emit(2)
	menu._vsync_selector.item_selected.emit(0)
	assert(Engine.max_fps == 120, "FPS deve ser aplicado")
	menu._show_tab(2)
	menu._sensitivity_slider.value = 150
	assert(is_equal_approx(current_scene.get_node("CameraRig").mouse_sensitivity, 0.0042), "Câmera ativa deve receber sensibilidade")
	var config := ConfigFile.new()
	assert(config.load(menu.settings_path) == OK, "Configurações devem ser salvas")
	assert(config.get_value("audio", "master") == 55.0, "Áudio deve persistir")
	assert(config.get_value("audio", "music") == 70.0 and config.get_value("audio", "sfx") == 35.0, "Buses separados devem persistir")
	assert(config.get_value("video", "fps_limit") == 120, "FPS deve persistir")
	assert(config.get_value("video", "vsync") == false, "VSync deve persistir")
	assert(config.get_value("gameplay", "camera_sensitivity_percent") == 150.0, "Câmera deve persistir")
	menu._on_back_pressed()
	assert(menu.pause_page.visible and paused, "Voltar deve mostrar pause")
	menu.resume_game()
	assert(not paused and Input.mouse_mode == menu._previous_mouse_mode, "Retomar deve restaurar modo anterior do mouse")
	menu.open_pause()
	menu.return_to_title()
	await _frames(10)
	assert(not paused and current_scene.scene_file_path.ends_with("title_screen.tscn"), "Deve voltar ao título sem pause")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Título deve mostrar mouse")
	current_scene._on_choice("continue")
	await create_timer(0.8).timeout
	await _frames(10)
	assert(current_scene.scene_file_path.ends_with("start_room.tscn") and not paused, "Continuar deve reabrir gameplay")
	assert(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Gameplay deve capturar o mouse")
	menu._load_settings()
	assert(is_equal_approx(root.get_node("GameManager").camera_sensitivity, 0.0042), "Configuração deve recarregar")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(menu.settings_path))
	print("PASS: título, NPC, pause, áudio, FPS, câmera, persistência e retorno")
	quit()
