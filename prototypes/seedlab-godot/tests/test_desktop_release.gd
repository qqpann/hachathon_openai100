extends SceneTree
## Run with an exported binary. Uses a fake key and never requests OpenAI.
var checks = 0
var failures = 0
var game

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("RELEASE_TEST_FAILED ", label)

func _run() -> void:
	check(not OS.has_feature("editor"), "test uses exported executable")
	check(FileAccess.file_exists("res://data/mnist/train.bin"), "MNIST train included")
	check(FileAccess.file_exists("res://data/mnist/test.bin"), "MNIST test included")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await create_timer(2.0).timeout
	check(game.coach.byot, "packaged game enables BYOT")
	check(game.coach.service_seen, "bundled runtime starts bridge")
	check(not game.coach.available, "no developer key inherited")
	check(game.coach.bridge_pid > 0, "game owns helper process")
	check(FileAccess.file_exists(game.coach._node_path()), "bundled Node exists")
	check(game.coach.session_token.length() == 64, "private session token generated")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("SEEDLAB_TEST_OUTPUT").path_join("release-game.png"))
	game._open_api_settings()
	await process_frame
	check(game.api_settings != null, "native key dialog opens")
	if game.api_settings != null:
		check(game.api_settings.key_input.secret, "key field is masked")
		game.api_settings.key_input.text = "sk-" + "release_test_fake_".repeat(3)
		game.api_settings._submit()
		await create_timer(1.0).timeout
		check(game.coach.available, "fake key configured locally without OpenAI")
		check(game.api_settings.key_input.text == "", "key cleared from input after configuration")
		check(game.coach.calls == 0, "settings never call paid API")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("SEEDLAB_TEST_OUTPUT").path_join("release-key-dialog.png"))
		await game.api_settings._configure("")
		check(not game.coach.available, "clear removes credential")
		game.api_settings._close()
		await process_frame
		check(game.api_settings == null, "dialog closes back to game")
	var port = game.coach.bridge_port
	game.queue_free()
	await create_timer(.3).timeout
	var probe = TCPServer.new()
	check(probe.listen(port, "127.0.0.1") == OK, "helper releases port with game")
	probe.stop()
	print("DESKTOP_RELEASE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
