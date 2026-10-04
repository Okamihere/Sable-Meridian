extends SceneTree

## Regression for pause navigation and saved video choices.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var menu := root.get_node("PauseMenu")
	menu.settings_path = "user://pause_menu_test.cfg"
	assert(InputMap.has_action("pause_menu"), "Esc action must exist")
	assert(menu.mode_selector.item_count == 4, "All four display modes must be listed")
	var two_monitors: Array[Vector2i] = [Vector2i(1366, 768), Vector2i(1920, 1080)]
	var available: Array[Vector2i] = menu._resolutions_for_screens(two_monitors)
	assert(available.has(Vector2i(1920, 1080)), "1080p must remain available with a smaller second monitor")
	assert(not available.has(Vector2i(2560, 1440)), "Do not offer sizes unsupported by any monitor")
	assert(menu._choose_screen_for_size(Vector2i(1920, 1080), two_monitors, 0, 1) == 1, "1080p must select the capable monitor")
	assert(not paused and not menu.overlay.visible, "Game must start unpaused")
	var old_mouse_mode := Input.mouse_mode
	menu.open_pause()
	assert(paused and menu.overlay.visible, "Pause overlay must stop gameplay")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause must release mouse")
	menu.show_options()
	assert(menu.options_page.visible and not menu.pause_page.visible, "Options page must open")
	var escape := InputEventAction.new()
	escape.action = "pause_menu"
	escape.pressed = true
	menu._input(escape)
	assert(paused and menu.pause_page.visible, "Esc in options must return to pause page")
	menu._input(escape)
	assert(not paused and not menu.overlay.visible, "Esc in pause page must resume")
	assert(Input.mouse_mode == old_mouse_mode, "Resume must restore prior mouse mode")
	menu.open_pause()
	menu.show_controls()
	assert(menu.controls_page.visible and not menu.pause_page.visible, "Controls page must open from pause")
	assert(menu._binding_text(&"interact").contains("F"), "Interact binding must come from InputMap")
	assert(menu._binding_text(&"lock_on").contains("meio"), "Lock-on must show the middle mouse button")
	var custom_key := InputEventKey.new()
	custom_key.physical_keycode = KEY_T
	InputMap.action_add_event(&"interact", custom_key)
	menu.show_controls()
	assert(menu._binding_text(&"interact").contains("T"), "Controls page must refresh from changed InputMap bindings")
	InputMap.action_erase_event(&"interact", custom_key)
	menu._input(escape)
	assert(paused and menu.pause_page.visible, "Esc in controls must return to pause page")
	menu.resume_game()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	assert(paused and menu.overlay.visible, "Physical Esc must open pause")
	menu.resume_game()

	menu._apply_mode(Window.MODE_WINDOWED)
	assert(not menu.resolution_selector.disabled, "Windowed mode must enable resolution")
	var size_index: int = menu._resolutions.find(Vector2i(1280, 720))
	assert(size_index >= 0, "1280x720 must be available")
	menu._on_resolution_selected(size_index)
	assert(menu._windowed_size == Vector2i(1280, 720), "Resolution choice must be applied")
	var config := ConfigFile.new()
	assert(config.load(menu.settings_path) == OK, "Display settings must be saved")
	assert(config.get_value("video", "windowed_size") == Vector2i(1280, 720), "Saved resolution must match")
	menu._on_mode_selected(3)
	assert(menu._active_mode == Window.MODE_FULLSCREEN, "Borderless selection must apply")
	assert(menu.resolution_selector.disabled, "Borderless mode uses monitor resolution")
	menu._apply_mode(Window.MODE_EXCLUSIVE_FULLSCREEN)
	assert(menu.resolution_selector.disabled, "Fullscreen mode uses monitor resolution")
	menu._apply_mode(Window.MODE_WINDOWED)
	assert(not menu.resolution_selector.disabled, "Returning to windowed must restore resolution control")

	menu.open_pause()
	menu.show_options()
	for dims in [Vector2i(320, 568), Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = dims
		await process_frame
		menu._layout_panel()
		var bounds: Rect2 = Rect2(menu.panel.position, menu.panel.size * menu.panel.scale)
		assert(Rect2(Vector2.ZERO, dims).grow(1).encloses(bounds), "Options panel must fit %s" % dims)
	menu.show_controls()
	for dims in [Vector2i(320, 568), Vector2i(640, 360), Vector2i(1280, 720)]:
		root.size = dims
		await process_frame
		menu._layout_panel()
		var bounds: Rect2 = Rect2(menu.panel.position, menu.panel.size * menu.panel.scale)
		assert(Rect2(Vector2.ZERO, dims).grow(1).encloses(bounds), "Controls panel must fit %s" % dims)
	menu.resume_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(menu.settings_path))
	print("PASS: pause, Esc navigation, mouse, video modes, resolution, persistence, layout")
	quit()
