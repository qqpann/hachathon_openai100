extends SceneTree
const Lab = preload("res://scripts/button_lab.gd")
const Brain = preload("res://scripts/vision_brain.gd")
var checks = 0
var failures = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var path = "res://tests/fixtures/mnist-observations.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixtures="): path = argument.trim_prefix("--fixtures=")
	var fixtures = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not fixtures is Array or fixtures.size() != 400:
		check(false, "Need 400 MNIST observations from the actual fixed / wrist render cameras")
		quit(1)
		return
	_check_dataset()
	_check_vision(fixtures)
	_check_separate_save()
	_check_unlocks(fixtures)
	_check_progression(fixtures)
	_check_camera_and_cadence()
	_check_gradient(fixtures)
	_check_exam(fixtures)
	_check_learning(fixtures)
	print("BUTTON_GARDEN_TESTS checks=", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)

func _pixels(fixtures: Array, mode: int, digit: int, variant: int = 0, testing: bool = false) -> Array:
	return fixtures[mode * 200 + (160 + digit * 4 + variant if testing else digit * 16 + variant)].pixels

func _check_dataset() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/mnist/manifest.json"))
	for split in ["train", "test"]:
		check(FileAccess.get_sha256("res://data/mnist/" + split + ".bin") == manifest.splits[split].sha256, "Bundled MNIST bytes match recorded checksum")
	check(manifest.splits.train.count == 640 and manifest.splits.test.count == 160, "Independent balanced MNIST train/test subsets are present")
	for digit in range(10):
		var source = Lab.Digits.image_for(digit, 0)
		check(source.get_size() == Vector2i(28, 28), "Real MNIST card retains native 28×28 source")
		check(source.get_data() != Lab.Digits.image_for(digit, 1).get_data(), "Each digit has different handwritten examples")
		check(source.get_data() != Lab.Digits.image_for(digit, 0, true).get_data(), "Test card is not a training card")

func _check_vision(fixtures: Array) -> void:
	for record in fixtures:
		check(Brain._row_ok(record.pixels, 144), "Camera yields 144 finite MNIST pixels")
	for mode in range(2):
		for a in range(10):
			var pixels = _pixels(fixtures, mode, a)
			for b in range(a + 1, 10):
				var other = _pixels(fixtures, mode, b)
				var difference = 0.0
				for i in range(144): difference += absf(pixels[i] - other[i])
				check(difference > .2, "Digit shapes are distinguishable in camera %d" % mode)
	var difference = 0.0
	for i in range(144): difference += absf(_pixels(fixtures, 0, 4)[i] - _pixels(fixtures, 1, 4)[i])
	check(difference > 1, "Fixed and wrist inputs are distinct views of the handwriting")
	var game = Lab.new()
	var pixels = _pixels(fixtures, 0, 4)
	var original = game.observation(pixels)
	game.target = 9
	game.credits = 999
	game.camera_mode = 1
	game.levels = [3,2,4,1]
	check(original == pixels and game.observation(pixels) == original and original.size() == 144, "Neither label nor progression leaks into image-only input")
	var prediction = game.brain.predict(original)
	var total = 0.0
	for value in prediction: total += value
	check(prediction.size() == 10 and absf(total - 1.0) < .000001, "Ten softmax probabilities sum to one")

func _check_progression(fixtures: Array) -> void:
	for branch in range(4):
		var game = Lab.new()
		game.credits = 60
		check(game.buy_upgrade(branch), "Every branch can be chosen first")
		check(game.levels[branch] == 1 and game.credits == 60 - game.catalog[branch].base_cost, "Purchase charges exactly once")
		check(not game.buy_upgrade(branch, 0), "A stale physical button cannot repurchase")
	var game = Lab.new()
	var x = game.observation(_pixels(fixtures, 0, 4))
	check(game.begin_trial(x, 4) == 4, "A player demonstration chooses the actual location")
	check(game.begin_trial(x) == -1, "Cannot start overlapping trials")
	check(game.finish_trial().correct, "Answering with the handwritten digit earns G")
	var credits: int = game.credits
	check(game.finish_trial().is_empty() and game.credits == credits, "Cannot collect a second reward")
	var prediction = game.brain.predict(x)
	game.brain.grow()
	var grown = game.brain.predict(x)
	for i in range(10): check(absf(prediction[i] - grown[i]) < .000001, "Neuron growth preserves existing outputs")
	var copy = game.brain.copy_brain()
	copy.train(x, 0)
	check(game.brain.snapshot().wi != copy.snapshot().wi, "Counterfactual training uses independent weights")
	game = Lab.new()
	for i in range(30):
		game.target = i % 10
		game.begin_trial(game.observation(_pixels(fixtures, 0, i % 10)), i % 10)
		game.finish_trial()
	game.credits = 1000
	for level in range(3): game.buy_upgrade(2, level)
	x = game.observation(_pixels(fixtures, 0, 4))
	check(game.buy_upgrade(1, game.levels[1], true), "Coach purchase uses the same validated transaction")
	check(game.self_upgrades == 1 and game.credits >= 30, "Delegated upgrades are counted")
	game.auto_research = true
	check(game.buy_upgrade(2), "Manual upgrades remain available while delegated")
	var restored = Lab.new()
	var serialized = JSON.parse_string(JSON.stringify(game.snapshot()))
	check(restored.restore(serialized), "Actual JSON save roundtrip restores successfully")
	var before_save = game.brain.predict(x)
	var after_save = restored.brain.predict(x)
	var error = 0.0
	for i in range(10): error += absf(before_save[i] - after_save[i])
	check(restored.levels == game.levels and error < .00001 and restored.credits == game.credits, "Learned predictions and progress survive JSON numeric precision")
	check(not restored.auto_research and restored.pending.is_empty(), "Reload requires a fresh command to resume automation")
	serialized.brain.wi[0][0] = "bad"
	check(not Lab.new().restore(serialized), "Malformed neural weights are rejected")

func _check_gradient(fixtures: Array) -> void:
	var model = Brain.new()
	var x = Lab.new().observation(_pixels(fixtures, 0, 4))
	var action = 4
	var rate = .001
	var trained = model.copy_brain()
	trained.train(x, action, rate)
	for weight in [["wi", 0, 40], ["wo", action, 2], ["wo", 9, 3], ["bi", 3, -1], ["bo", action, -1], ["bo", 0, -1]]:
		var values = model.get(weight[0])
		var old: float = values[weight[1]][weight[2]] if weight[2] >= 0 else values[weight[1]]
		var losses: Array = []
		for offset in [-.00001, .00001]:
			if weight[2] >= 0: values[weight[1]][weight[2]] = old + offset
			else: values[weight[1]] = old + offset
			losses.append(-log(model.predict(x)[action]))
		if weight[2] >= 0: values[weight[1]][weight[2]] = old
		else: values[weight[1]] = old
		var updated = trained.get(weight[0])
		var after: float = updated[weight[1]][weight[2]] if weight[2] >= 0 else updated[weight[1]]
		var numerical: float = (losses[1] - losses[0]) / .00002
		check(absf(numerical - (old - after) / rate) < .00001, "Backprop matches numerical gradient for " + weight[0])
	var legacy = Lab.new().snapshot()
	legacy.version = 3
	check(not Lab.new().restore(legacy), "Light-task weights are not silently treated as digit recognition")
	var expanded = Lab.new()
	expanded.credits = 20000
	for level in range(6):
		for branch in range(4): check(expanded.buy_upgrade(branch, level), "All 24 upgrades are purchasable")
	check(expanded.brain.hidden_count == 32 and expanded.memory_capacity() == 2048, "Expansion effects update real model and replay capacity")
	check(Lab.new().restore(expanded.snapshot()), "Expanded progress restores")

func _check_exam(fixtures: Array) -> void:
	var game = Lab.new()
	game.credits = 500
	game.buy_upgrade(2)
	game.auto_research = true
	var original = game.snapshot()
	check(game.start_exam(), "Exam starts")
	check(not game.start_exam(), "Overlapping exam rejected")
	check(not game.buy_upgrade(0), "Weights/upgrades cannot change during exam")
	check(game.begin_trial(game.observation(_pixels(fixtures, 0, game.target, game.variant % 4, true)), game.target) == -1, "Player cannot supply exam answers")
	var seen: Array = []
	for i in range(10):
		seen.append(game.target)
		game.begin_trial(game.observation(_pixels(fixtures, 0, game.target, game.variant % 4, true)))
		game.finish_trial()
		if game.exam_active: game.next_target()
	seen.sort()
	check(seen == range(10), "Exam visits each target once")
	check(not game.exam_active and game.exam_results.size() == 10, "Exam completes after ten presses")
	check(game.brain.snapshot() == original.brain and game.trials == original.trials and game.archive == original.archive, "Exam freezes weights and training history")
	check(game.rng.state == int(original.rng) and game.card_rng.state == int(original.card_rng) and game.variant == original.variant, "Exam does not consume training RNG")
	var credits = game.credits
	game.start_exam()
	for i in range(10):
		game.begin_trial(game.observation(_pixels(fixtures, 0, game.target, game.variant % 4, true)))
		game.finish_trial()
		if game.exam_active: game.next_target()
	check(game.credits == credits, "Same medal cannot grant rewards twice")
	game = Lab.new()
	game.levels[2] = 5
	game.target = 4
	game.begin_trial(game.observation(_pixels(fixtures, 0, 4)), 4)
	game.finish_trial()
	check(game.brain.steps == 12 + game.learning_passes(), "Demonstration perk makes twelve real gradient updates")
	game.levels[3] = 5
	game.begin_trial(game.observation(_pixels(fixtures, 0, 4)), 4)
	var result = game.finish_trial()
	check(result.income == 21, "Combo perk adds actual G")
	var retry = Lab.new()
	retry.credits = 35
	retry.buy_upgrade(2)
	for i in range(30): check(retry.begin_trial(retry.observation(_pixels(fixtures, 0, 4)), -1, 4) != 4 and not retry.finish_trial().is_empty(), "Retry excludes the failed position")

func _score(game, fixtures: Array, mode: int) -> float:
	var correct = 0.0
	for target in range(10):
		for variant in range(4):
			var values = game.brain.predict(game.observation(_pixels(fixtures, mode, target, variant, true)))
			var action = 0
			for i in range(1, 10):
				if values[i] > values[action]: action = i
			correct += float(action == target)
	return correct / 40.0

func _check_learning(fixtures: Array) -> void:
	for mode in range(2):
		var sum_before = 0.0
		var sum_after = 0.0
		for seed_value in [71, 381, 2026]:
			var game = Lab.new(seed_value)
			game.camera_mode = mode
			game.credits = 35
			game.buy_upgrade(2)
			var before = _score(game, fixtures, mode)
			for i in range(360):
				var pixels = _pixels(fixtures, mode, game.target, game.variant % 16)
				game.begin_trial(game.observation(pixels))
				game.finish_trial()
				game.next_target()
			var after = _score(game, fixtures, mode)
			sum_before += before
			sum_after += after
			print("MNIST_LEARNING camera=", mode, " seed=", seed_value, " before=", before, " held_out_after=", after, " online_accuracy=", game.accuracy())
		check(sum_after / 3 >= .35, "Actual camera MNIST predictions generalize above chance in camera %d" % mode)
		check(sum_after > sum_before + .6, "Held-out recognition improves across three independent seeds")

func _check_camera_and_cadence() -> void:
	var world = preload("res://scripts/workshop.gd").new()
	world.yaw = .71
	world.pitch = .88
	world.distance = 11.3
	world.view_mode = 1
	world.reveal()
	world.reveal()
	world.restore_camera()
	check(world.yaw == .71 and world.pitch == .88 and world.distance == 11.3 and world.view_mode == 1, "Reveal restores the original camera, even from eye view")
	world.reveal()
	world.manual_camera()
	world.distance = 9.5
	world.restore_camera()
	check(world.distance == 9.5, "Manual camera input cancels automatic restoration")
	world.reset_camera()
	check(world.view_mode == 0 and world.distance == 14.1, "Return to workbench always works")
	world.free()
	var coach = preload("res://scripts/openai_coach.gd").new()
	coach.last_trial = 100
	coach.last_time = Time.get_ticks_msec() / 1000.0
	check(not coach.due(124), "24 presses alone cannot bypass API time interval")
	coach.last_time -= 31
	check(not coach.due(123) and coach.due(124), "API requires 24 new training presses and 30 seconds")
	var ticket = coach.generation
	coach.cancel()
	check(coach.generation != ticket, "Cancelling invalidates pending AI decisions")
	coach.free()

func _check_unlocks(fixtures: Array) -> void:
	var game = Lab.new()
	var x = game.observation(_pixels(fixtures, 0, 4))
	check(game.credits == 0 and game.speed_choices() == [1.0], "Fresh game starts with demonstrations and normal speed")
	check(game.begin_trial(x) == -1 and not game.start_exam(), "NN actions and exam cannot bypass the unpurchased control")
	check(not game.unlocked("auto_practice") and not game.can_delegate(), "Automatic practice and coach start locked")
	for i in range(3):
		game.begin_trial(game.observation(_pixels(fixtures, 0, 4)), 4)
		game.finish_trial()
	check(game.credits == 51 and game.brain.steps > 0, "Three real demonstrations earn the first unlock and train the NN")
	check(game.buy_upgrade(2, 0) and game.unlocked("self_press"), "First learning upgrade unlocks single NN actions")
	var probabilities = game.brain.predict(x)
	check(game.begin_trial(x) == probabilities.find(probabilities.max()), "Unlocked NN presses its highest-probability digit")
	game.finish_trial()
	game.credits = 1000
	check(game.buy_upgrade(2, 1) and game.unlocked("auto_practice"), "Second learning upgrade unlocks automatic practice")
	game.buy_upgrade(2, 2)
	check(not game.can_delegate(), "Buying coaching does not skip the 24-experience requirement")
	game.trials = 24
	check(game.can_delegate(), "Purchased coaching is available after 24 experiences")
	game.buy_upgrade(3, 0)
	check(game.speed_choices() == [1.0, 2.0], "First arm upgrade enables 2x, not 3x")
	game.buy_upgrade(3, 1)
	check(game.speed_choices() == [1.0, 2.0], "Second arm upgrade does not prematurely enable 3x")
	game.buy_upgrade(3, 2)
	check(game.speed_choices() == [1.0, 2.0, 3.0], "Third arm upgrade enables 3x")
	var restored = Lab.new()
	check(restored.restore(game.snapshot()) and restored.can_delegate() and restored.speed_choices() == game.speed_choices(), "Unlocks survive saving through purchased levels")
	var steps: int = game.brain.steps
	var before = game.snapshot()
	var pending = game.pending.duplicate(true)
	for i in range(8): game.brain.predict(x)
	check(game.snapshot() == before and game.pending == pending and game.brain.steps == steps, "Passive live monitor inference never trains or changes gameplay state")

func _check_separate_save() -> void:
	var game = preload("res://scripts/main.gd").new()
	var original = game._save_path()
	game.separate_garden = true
	var fresh = game._save_path()
	check(original.ends_with("seedlab-mnist.json") and fresh.ends_with("seedlab-mnist-new-garden.json") and original != fresh, "New garden saves independently without overwriting existing progress")
	game.free()
