extends Node3D
const Lab = preload("res://scripts/button_lab.gd")
const World = preload("res://scripts/workshop.gd")
const Hud = preload("res://scripts/game_hud.gd")
const Coach = preload("res://scripts/openai_coach.gd")
var coach
var coach_reason = "学び方Lv.3「育成委任」を購入すると、強化の選択を任せられます。"
var coach_goal = ""
var playtest = false
var separate_garden = false
var lab = Lab.new()
var world
var hud
var busy = false
var auto_trials = false
var speed = 1.0
var phase = "READY"
var status = "左奥の手書き数字を読んで、右の数字ボタンを押そう。"
var elapsed = 0.0
var result_text = ""
var result_good = true
var result_time = 0.0
var reveal_time = 0.0
var hover: Dictionary = {}
var pointer = Vector2(-100, -100)
var dragging = false
var show_help = false
var show_reset = false
var muted = false
var player: AudioStreamPlayer
var no_save = false
var capture_path = ""
var vision_check_path = ""
var frame = 0
var monitor_elapsed = 0.0
var next_camera = -1
var chosen_button = -1
var save_error = false

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--no-save": no_save = true
		if argument == "--playtest": playtest = true
		if argument == "--new-garden": separate_garden = true
		if argument.begins_with("--capture="): capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--vision-check="):
			vision_check_path = argument.trim_prefix("--vision-check=")
			no_save = true
	_load_game()
	if playtest: no_save = true
	coach = Coach.new()
	add_child(coach)
	world = World.new()
	add_child(world)
	world.setup(lab)
	world.camera_mode = lab.camera_mode
	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	player = AudioStreamPlayer.new()
	player.volume_db = -20
	add_child(player)
	get_tree().auto_accept_quit = false
	if lab.trials > 0:
		status = "おかえり。%d 回分、覚えているよ。" % lab.trials
	if lab.can_delegate():
		coach_reason = "成績と強化盤を見て次の強化を選びます。Rでコーチに任せられます。"
	if vision_check_path != "":
		_validate_vision.call_deferred()

func _process(delta: float) -> void:
	elapsed += delta
	frame += 1
	result_time = maxf(0, result_time - delta)
	reveal_time = maxf(0, reveal_time - delta)
	if world != null:
		if not show_help and not show_reset and hud.hit_at(pointer) == "":
			hover = world.pick(pointer)
		else:
			hover = {}
		world.hover_kind = hover.get("kind", "")
		world.hover_index = hover.get("index", -1)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if not hover.is_empty() or hud.hit_at(pointer) != "" else Input.CURSOR_ARROW)
	if ((auto_trials and lab.unlocked("auto_practice")) or lab.exam_active) and not busy and not show_help and not show_reset and vision_check_path == "":
		_run_trial()
	monitor_elapsed += delta
	if monitor_elapsed >= .20:
		monitor_elapsed = 0.0
		_update_monitor()
	hud.queue_redraw()
	if capture_path != "" and frame == 30:
		_capture.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		# Event coordinates stay correct under Retina scaling and window resize.
		pointer = event.position
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			if dragging: world.manual_camera()
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			world.manual_camera()
			world.distance = maxf(8.0, world.distance - .6)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			world.manual_camera()
			world.distance = minf(20.0, world.distance + .6)
		if event.button_index == MOUSE_BUTTON_LEFT:
			var action = hud.hit_at(event.position)
			if action != "":
				activate(action)
				return
			if show_help or show_reset:
				return
			var hit = world.pick(event.position)
			if hit.get("kind") == "practice":
				_run_trial(hit.index)
			elif hit.get("kind") == "page":
				world.depress(world.page_button)
				activate("page")
			elif hit.get("kind") == "growth":
				_buy(hit.index / 6, hit.index % 6)
	if event is InputEventMouseMotion and dragging and not show_help:
		world.view_mode = 0
		world.yaw -= event.relative.x * .006
		world.pitch = clampf(world.pitch + event.relative.y * .004, .35, 1.40)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if show_reset:
				show_reset = false
			else:
				show_help = not show_help
			return
		if show_help or show_reset:
			return
		match event.keycode:
			KEY_SPACE: activate("launch")
			KEY_A: activate("auto")
			KEY_V: activate("eye")
			KEY_C: activate("view")
			KEY_R: activate("research")
			KEY_H: activate("help")
			KEY_M: activate("mute")
			KEY_F: activate("home")
			KEY_T: activate("exam")
			KEY_B: activate("page")
			KEY_F12:
				if capture_path != "": _capture()
			KEY_Q:
				world.manual_camera()
				world.yaw -= .25
			KEY_E:
				world.manual_camera()
				world.yaw += .25

func activate(action: String) -> void:
	match action:
		"launch": _run_trial()
		"auto":
			if lab.exam_active: return
			if not lab.unlocked("auto_practice"):
				status = lab.unlock_hint("auto_practice")
				return
			auto_trials = not auto_trials
			status = "自分で見て、押して、覚える。" if auto_trials else "ひと休み。次はあなたが選んでもいいよ。"
		"speed":
			var choices: Array = lab.speed_choices()
			if choices.size() == 1:
				status = lab.unlock_hint("speed_2")
				return
			speed = choices[(choices.find(speed) + 1) % choices.size()]
			status = "動作速度 ×%d。解放した速度を切り替えられます。" % speed
		"eye":
			if lab.exam_active:
				status = "試験中は同じカメラで10問を解きます。"
				return
			if busy:
				next_camera = 1 - lab.camera_mode if next_camera < 0 else 1 - next_camera
				status = "動作が終わったら、カメラを切り替えるね。"
			else:
				lab.camera_mode = 1 - lab.camera_mode
				world.camera_mode = lab.camera_mode
				_save_game()
		"view":
			world.manual_camera()
			world.view_mode = 1 - world.view_mode
		"home": world.reset_camera()
		"exam": _start_exam()
		"page": world.set_growth_page(1 - world.growth_page)
		"research": _toggle_research()
		"connect":
			if not coach.connecting:
				await coach.ensure_connection()
				status = coach.health_note
		"help": show_help = not show_help
		"close_help": show_help = false
		"mute": muted = not muted
		"reset": show_reset = true
		"cancel_reset": show_reset = false
		"confirm_reset":
			if busy:
				status = "動作が終わってからリセットできます。"
				return
			coach.cancel()
			lab = Lab.new()
			world.lab = lab
			world.monitor_display.clear_signal()
			speed = 1.0
			coach_reason = "学び方Lv.3「育成委任」を購入すると、強化の選択を任せられます。"
			coach_goal = ""
			world.camera_mode = 0
			world.set_growth_page(0)
			world.reset_camera()
			auto_trials = false
			show_reset = false
			show_help = false
			status = "新しい小さなNN。まずは押してみよう。"
			_save_game()

func _start_exam() -> void:
	if not lab.unlocked("self_press"):
		status = lab.unlock_hint("self_press")
		return
	if busy or lab.exam_active:
		status = "動作が終わったら、認定試験を始められます。"
		return
	if lab.start_exam():
		auto_trials = false
		world.restore_camera()
		world.refresh_buttons()
		status = "認定試験。学習と探索を止めて、NNだけで10問に挑戦！"
		result_text = "ひとりで、できるかな？   10問の認定試験"
		result_time = 3

func _run_trial(manual: int = -1) -> void:
	if manual < 0 and not lab.unlocked("self_press"):
		status = lab.unlock_hint("self_press")
		return
	if busy or show_help or show_reset: return
	if lab.exam_active and manual >= 0:
		status = "試験中はNNに任せよう。お手本は練習で教えられます。"
		return
	busy = true
	var was_exam: bool = lab.exam_active
	var excluded = -1
	var attempts = 2 if lab.levels[0] >= 6 and manual < 0 and not was_exam else 1
	for attempt in range(attempts):
		phase = "EXAM" if was_exam else "LOOK"
		world.growth_view = false
		await _settle_vision()
		var pixels = Lab.Brain.pixels_from_image(world.vision_view.get_texture().get_image())
		var action: int = lab.begin_trial(lab.observation(pixels), manual, excluded)
		if action < 0:
			status = "カメラを読み込めませんでした。"
			auto_trials = false
			busy = false
			return
		chosen_button = action
		phase = "EXAM" if was_exam else "REACH"
		status = "お手本：%d。採点してから、正解を学習します。" % action if manual >= 0 else "NNの予測で %dへ。予測 %d%%" % [action, lab.last_prediction[action] * 100]
		if attempt == 1: status = "もう一手！ 外した場所を除き、%dに再挑戦。" % action
		var button = world.practice[action]
		var contact: Vector3 = button.point + Vector3(0, .62, 0)
		var duration = lab.time_factor() / speed
		var route = .75 if lab.levels[3] >= 6 else 1.0
		_sound(180, .08)
		await world.arm.move_to(contact + Vector3(0, .35, 0), .65 * duration * route, .10 if route < 1 else .28)
		await world.arm.move_to(contact, .19 * duration, 0)
		world.depress(button)
		var result: Dictionary = lab.finish_trial()
		var success: bool = result.correct
		world.set_button(button, World.MINT if success else Color("f16858"), .6)
		world.burst(button.point + Vector3(0, .25, 0), World.MINT if success else World.AMBER, 16 if success else 7)
		result_text = ("正解！" if success else "次につなげよう。") if was_exam else (("読めた！" if success else "正解は %d。覚えよう。" % result.target) + "   +%d G" % result.income)
		if success and lab.streak >= 3 and not was_exam: result_text += "   %d COMBO" % lab.streak
		result_good = success
		result_time = 2.4
		_sound(820 if success else 330, .17)
		phase = "EXAM" if was_exam else "LEARN"
		await get_tree().create_timer(.32 * duration).timeout
		await world.arm.move_to(world.arm.home, .65 * duration * route, .10 if route < 1 else .35)
		if success or was_exam: break
		excluded = action
		world.refresh_buttons()
	if was_exam:
		if lab.exam_active:
			lab.next_target()
		else:
			var summary: Dictionary = lab.exam_summary
			result_text = "認定試験  %d / 10 正解" % summary.score
			if summary.reward > 0: result_text += "   新メダル！ +%d G" % summary.reward
			result_time = 8
			result_good = summary.score >= 3
			status = "試験終了。教える → 左の強化盤 → もう一度試験、で成長を確かめよう。"
			_sound(1080 if summary.score >= 3 else 440, .3)
	else:
		if lab.trials >= Lab.AUTO_UNLOCK and lab.trials - attempts < Lab.AUTO_UNLOCK:
			result_text = "OpenAIコーチの準備OK！  [R]" if lab.unlocked("coach") else "24回の経験！ 「育成委任」の強化でコーチに任せよう。"
			result_time = 7
		lab.next_target()
	world.refresh_buttons()
	# A result belongs to the card just graded. Do not label the next image
	# with the previous answer; upgrade and milestone announcements remain.
	if result_text.begins_with("正解は") or result_text.begins_with("読めた！"):
		result_time = 0
	_apply_camera()
	_save_game()
	if not was_exam and lab.auto_research and coach.due(lab.trials): await _run_research()
	phase = "READY"
	chosen_button = -1
	await get_tree().create_timer(.22 / speed).timeout
	busy = false

func _toggle_research() -> void:
	if lab.auto_research:
		lab.auto_research = false
		coach.cancel()
		world.restore_camera()
		reveal_time = 0
		status = "委任を停止しました。強化はあなたが選べます。"
		return
	if not lab.unlocked("coach"):
		status = lab.unlock_hint("coach")
		return
	if lab.trials < Lab.AUTO_UNLOCK:
		status = "あと %d 回練習すると、OpenAIコーチに育成を任せられます。" % (Lab.AUTO_UNLOCK - lab.trials)
		return
	if lab.exam_active:
		status = "試験が終わったら委任できます。"
		return
	if coach.connecting:
		status = "コーチの接続準備中です。"
		return
	if not coach.available:
		status = "コーチに接続しています…"
		if not await coach.ensure_connection():
			coach_reason = coach.health_note
			status = coach.health_note
			return
	if not lab.can_delegate() or lab.exam_active: return
	lab.auto_research = true
	auto_trials = true
	status = "OpenAIが成績と強化盤を見て、次の強化を選びます。"
	if not busy and coach.due(lab.trials):
		busy = true
		await _run_research()
		busy = false

func _run_research() -> void:
	if not lab.auto_research or not lab.can_delegate(): return
	phase = "COACH"
	world.growth_view = true
	await _settle_vision()
	status = "OpenAIコーチが、成績と強化盤を確認中…"
	var response: Dictionary = await coach.review(lab.coach_state(), world.vision_view.get_texture().get_image())
	if response.get("source") == "live":
		print("OPENAI_COACH model=", response.get("model"), " decision=", response.get("decision"), " usage=", response.get("usage"), " cached=", response.get("cacheHit", false))
	world.growth_view = false
	if not lab.auto_research or response.get("source") == "cancelled":
		world.restore_camera()
		phase = "READY"
		return
	coach_reason = response.get("reason", "コーチの回答を確認できませんでした。")
	coach_goal = response.get("next_goal", "")
	if response.get("source") == "local":
		coach_reason = "購入可能な強化がないため、OpenAIへの相談は見送りました。" + coach_reason
	if response.get("source") not in ["live", "local"]:
		lab.auto_research = false
		status = coach_reason
		world.restore_camera()
		phase = "READY"
		return
	if response.get("decision") == "wait":
		status = "次の強化に向けてGを貯めよう。" if response.get("source") == "local" else "コーチ：今回はGを貯めよう。"
		if lab.levels.min() == Lab.MAX_LEVEL: lab.auto_research = false
		phase = "READY"
		return
	var selection = response.get("selection", {})
	var branch = int(selection.get("branch", -1))
	var level = int(selection.get("level", -1))
	if branch < 0 or branch > 3 or level != lab.levels[branch] or not lab.can_upgrade(branch) or lab.credits - lab.cost(branch) < 30:
		status = "待っている間に強化が変わりました。次の練習後に見直します。"
		phase = "READY"
		return
	world.set_growth_page(1 if level >= 4 else 0)
	world.reveal()
	reveal_time = 4
	world.growth_view = true
	phase = "COACH / PRESS"
	status = "コーチが選択：%s。アームで強化盤を押します。" % lab.upgrade_info(branch, level).name
	await get_tree().create_timer(.8).timeout
	var button = world.button_for(branch, level)
	var duration = lab.time_factor() / speed
	var contact: Vector3 = button.point + Vector3(0, .62, 0)
	if lab.auto_research:
		await world.arm.move_to(contact + Vector3(0, .35, 0), .85 * duration, .4)
		await world.arm.move_to(contact, .22 * duration, 0)
		if lab.auto_research and lab.credits - lab.cost(branch) >= 30 and lab.buy_upgrade(branch, level, true):
			world.depress(button)
			_upgrade_feedback(branch, level, true)
		await get_tree().create_timer(.25 * duration).timeout
		await world.arm.move_to(world.arm.home, .75 * duration, .35)
	world.growth_view = false
	world.restore_camera()
	reveal_time = 0
	phase = "READY"
	_apply_camera()

func _buy(branch: int, level: int = -1) -> void:
	if lab.exam_active:
		status = "試験中は強化を固定しています。10問が終わったら選ぼう。"
		return
	if level < 0: level = lab.levels[branch]
	if level >= Lab.MAX_LEVEL:
		status = "この行は研究完了。他の行や認定試験に挑もう。"
		return
	if lab.buy_upgrade(branch, level):
		world.set_growth_page(1 if level >= 4 else 0)
		world.depress(world.button_for(branch, level))
		_upgrade_feedback(branch, level)
	else:
		status = "購入済みの強化です。" if level < lab.levels[branch] else ("同じ行の左から順に購入できます。行は自由に選べます。" if level > lab.levels[branch] else "あと %d Gで購入できます。" % maxi(0, lab.cost(branch) - lab.credits))
		_sound(140, .07)

func _upgrade_feedback(branch: int, level: int, by_coach: bool = false) -> void:
	world.burst(world.button_for(branch, level).point + Vector3(0, .25, 0), World.BRANCH_COLORS[branch], 24)
	world.refresh_buttons()
	result_text = ("コーチの強化！  " if by_coach else "強化！  ") + lab.upgrade_info(branch, level).name
	result_good = true
	result_time = 3.2
	if lab.upgrade_info(branch, level).has("unlock"):
		result_text = "新しい操作を解放！  " + lab.upgrade_info(branch, level).name
		result_time = 5.0
	status = lab.upgrade_info(branch, level).effect
	_sound(1100, .23)
	_save_game()

func _update_monitor() -> void:
	if world == null or world.monitor_display == null: return
	var display = world.monitor_display
	display.lab = lab
	display.coach_active = world.growth_view
	display.phase = phase
	if world.growth_view:
		display.queue_redraw()
		return
	# Read the real camera for passive inference. This never trains, chooses
	# actions, consumes RNG, or replaces the pending trial's prediction.
	var pixels = Lab.Brain.pixels_from_image(world.vision_view.get_texture().get_image())
	var x = lab.observation(pixels)
	if x.is_empty(): return
	display.pixels = pixels
	display.outputs = lab.brain.predict(x)
	display.activities = lab.brain.activity.duplicate()
	display.queue_redraw()

func _settle_vision() -> void:
	# Wait for camera transforms AND a new rendered image, not a stale frame.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _apply_camera() -> void:
	if next_camera >= 0:
		lab.camera_mode = next_camera
		world.camera_mode = next_camera
		next_camera = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
		get_tree().quit()

func _save_path() -> String:
	var filename = "seedlab-mnist-new-garden.json" if separate_garden else "seedlab-mnist.json"
	return ProjectSettings.globalize_path(("res://.local/" if OS.has_feature("editor") else "user://") + filename)

func _save_game() -> void:
	if no_save:
		return
	var path = _save_path()
	var error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error == OK:
		var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(lab.snapshot()))
			file.close()
			error = DirAccess.rename_absolute(path + ".tmp", path)
		else:
			error = FileAccess.get_open_error()
	if error != OK and not save_error:
		save_error = true
		status = "保存できませんでした。この回の進行は保存されません。"
		push_warning("Save failed: %s (%d)" % [path, error])

func _load_game() -> void:
	if no_save or not FileAccess.file_exists(_save_path()):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if not data is Dictionary or not lab.restore(data):
		status = "保存を読み込めませんでした。新しいNNで始めます。"

func _sound(frequency: float, length: float) -> void:
	if muted:
		return
	var sample_rate = 22050
	var samples = int(length * sample_rate)
	var data = PackedByteArray()
	data.resize(samples * 2)
	for i in range(samples):
		var t = float(i) / sample_rate
		var envelope = pow(1.0 - float(i) / samples, 2) * minf(t * 180, 1)
		var wave = sin(TAU * frequency * t) + .18 * sin(TAU * frequency * 2 * t)
		data.encode_s16(i * 2, int(wave * envelope * 12000))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	player.stream = stream
	player.play()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	print("CAPTURE ", capture_path, " status=", get_viewport().get_texture().get_image().save_png(capture_path))

func _validate_vision() -> void:
	var records: Array = []
	var monitor_difference = 0.0
	world.set_process(false)
	for mode in range(2):
		lab.camera_mode = mode
		world.camera_mode = mode
		for testing in [false, true]:
			lab.exam_active = testing
			for target in range(10):
				lab.target = target
				for variant in range(4 if testing else 16):
					lab.variant = variant
					world.refresh_buttons()
					world._update_cameras(1.0)
					await _settle_vision()
					var pixels = Lab.Brain.pixels_from_image(world.vision_view.get_texture().get_image())
					records.append({"camera": mode, "target": target, "variant": variant, "test": testing, "pixels": pixels})
					if variant == 0 and not testing:
						world.monitor_root.visible = false
						await _settle_vision()
						var without_monitor = Lab.Brain.pixels_from_image(world.vision_view.get_texture().get_image())
						for pixel in range(144): monitor_difference = maxf(monitor_difference, absf(pixels[pixel] - without_monitor[pixel]))
						world.monitor_root.visible = true
						if target == 4:
							world.vision_view.get_texture().get_image().save_png(vision_check_path.get_basename() + "-camera-%d.png" % mode)
			print("MNIST_CAPTURE camera=", mode, " test=", testing, " records=", records.size())
	var file = FileAccess.open(vision_check_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(records))
	file.close()
	print("VISION_FIXTURES ", vision_check_path, " records=", records.size(), " monitor_pixel_delta=", monitor_difference)
	get_tree().quit(0 if monitor_difference < .00001 else 1)
