extends RefCounted
const Brain = preload("res://scripts/vision_brain.gd")
const Digits = preload("res://scripts/digit_deck.gd")
const NAMES = ["ひらめき", "記憶", "学び方", "アーム"]
const MAX_LEVEL = 6
const AUTO_UNLOCK = 24
var catalog: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/upgrades.json"))
var brain = Brain.new()
var rng = RandomNumberGenerator.new()
var card_rng = RandomNumberGenerator.new()
var variant = 0
var exam_saved_variant = 0
var exam_variants: Array = []
var credits = 0
var levels: Array = [0, 0, 0, 0]
var trials = 0
var successes = 0
var streak = 0
var target = 4
var archive: Array = []
var recent: Array = []
var self_upgrades = 0
var auto_research = false
var camera_mode = 0
var last_income = 0
var last_prediction: Array = []
var last_input: Array = []
var last_hidden: Array = []
var last_lesson: Dictionary = {}
var pending: Dictionary = {}
var demonstrations = 0
var position_tries: Array = [0,0,0,0,0,0,0,0,0,0]
var position_wins: Array = [0,0,0,0,0,0,0,0,0,0]
var exam_active = false
var exam_order: Array = []
var exam_results: Array = []
var exam_best: Array = [-1, -1]
var exam_last: Array = [-1, -1]
var medals: Array = [0, 0]
var exam_summary: Dictionary = {}
var exam_saved_target = 4

func _init(seed_value: int = 71) -> void:
	rng.seed = seed_value
	card_rng.seed = seed_value + 127
	brain = Brain.new(8, seed_value + 17)

func unlocked(feature: String) -> bool:
	for branch in range(4):
		for level in range(levels[branch]):
			if catalog[branch].upgrades[level].get("unlock", "") == feature: return true
	return false

func unlock_hint(feature: String) -> String:
	for branch in range(4):
		for level in range(MAX_LEVEL):
			var info = catalog[branch].upgrades[level]
			if info.get("unlock", "") == feature:
				return "左の%s Lv.%d「%s」を購入すると使えます。" % [NAMES[branch], level + 1, info.name]
	return ""

func speed_choices() -> Array:
	var values: Array = [1.0]
	if unlocked("speed_2"): values.append(2.0)
	if unlocked("speed_3"): values.append(3.0)
	return values

func can_delegate() -> bool:
	return unlocked("coach") and trials >= AUTO_UNLOCK

func memory_capacity(extra: int = 0) -> int:
	return 32 * (1 << (int(levels[1]) + extra))

func learning_passes(extra: int = 0) -> int:
	return 16 + (int(levels[2]) + extra) * 12

func time_factor() -> float:
	return 1.0 / (1.0 + float(levels[3]) * .25)

func cost_at(branch: int, level: int) -> int:
	return int(round(catalog[branch].base_cost * pow(1.72, level)))

func cost(branch: int) -> int:
	return cost_at(branch, levels[branch])

func can_upgrade(branch: int) -> bool:
	return branch >= 0 and branch < 4 and levels[branch] < MAX_LEVEL and credits >= cost(branch)

func upgrade_info(branch: int, level: int = -1) -> Dictionary:
	return catalog[branch].upgrades[clampi(levels[branch] if level < 0 else level, 0, MAX_LEVEL - 1)]

func upgrade_effect(branch: int) -> String:
	return upgrade_info(branch).effect

func buy_upgrade(branch: int, expected_level: int = -1, by_coach: bool = false) -> bool:
	if (by_coach and not can_delegate()) or exam_active or not can_upgrade(branch) or (expected_level >= 0 and levels[branch] != expected_level):
		return false
	credits -= cost(branch)
	levels[branch] += 1
	if branch == 0:
		brain.grow()
	if by_coach:
		self_upgrades += 1
	return true

func observation(pixels: Array, _growth: bool = false) -> Array:
	# No answer ID, money, progress or class metadata enters the neural policy.
	return pixels.duplicate() if pixels.size() == Brain.PIXELS else []

func card_image() -> Image:
	return Digits.image_for(target, variant, exam_active)

func begin_trial(x: Array, manual_action: int = -1, excluded: int = -1) -> int:
	if manual_action < 0 and not unlocked("self_press"): return -1
	if not pending.is_empty() or x.size() != Brain.INPUTS or manual_action < -1 or manual_action >= 10 or (exam_active and manual_action >= 0):
		return -1
	last_prediction = brain.predict(x)
	last_input = x.duplicate()
	last_hidden = brain.activity.duplicate()
	var action = manual_action
	if action < 0:
		var choices: Array = []
		for i in range(10):
			if i != excluded: choices.append(i)
		choices.sort_custom(func(a, b): return last_prediction[a] > last_prediction[b])
		action = choices[0]
		# MNIST supplies the label after grading, so random wrong answers are
		# unnecessary for learning. Curiosity only explores the close runner-up.
		if not exam_active and levels[0] >= 5 and last_prediction[choices[0]] - last_prediction[choices[1]] < .15 and rng.randf() < .30:
			action = choices[1]
	pending = {"x": x.duplicate(), "action": action, "target": target, "manual": manual_action >= 0}
	return action

func finish_trial() -> Dictionary:
	if pending.is_empty(): return {}
	var correct: bool = pending.action == pending.target
	var action: int = pending.action
	var result = {"correct": correct, "action": action, "target": pending.target, "income": 0, "exam": exam_active}
	if exam_active:
		exam_results.append(int(correct))
		pending.clear()
		if exam_results.size() == 10: _finish_exam()
		return result
	var sample = {"x": pending.x, "label": pending.target, "correct": correct}
	archive.append(sample)
	if archive.size() > 2048: archive.pop_front()
	# After the physical press, the examiner reveals the correct digit for learning.
	# Its label is never part of the observation used to choose that press.
	var reinforcement = 4 if correct else 1
	if pending.manual:
		demonstrations += 1
		if correct and levels[2] >= 5: reinforcement = 12
	else:
		position_tries[pending.target] += 1
		position_wins[pending.target] += int(correct)
	var before: float = last_prediction[pending.target]
	for i in range(reinforcement): brain.train(sample.x, sample.label)
	_replay(brain, learning_passes(), memory_capacity())
	last_lesson = {"action": action, "label": pending.target, "correct": correct, "before": before,
		"after": brain.predict(sample.x)[pending.target], "change": brain.last_weight_change, "manual": pending.manual}
	trials += 1
	successes += int(correct)
	streak = streak + 1 if correct else 0
	recent.append(int(correct))
	if recent.size() > 24: recent.pop_front()
	last_income = 5 + (10 + mini(streak, 5) if correct else 0)
	if correct and levels[3] >= 5: last_income += 2 * mini(streak, 10)
	credits += last_income
	result.income = last_income
	pending.clear()
	return result

func next_target() -> void:
	if exam_active:
		target = exam_order[exam_results.size()]
		variant = exam_variants[exam_results.size()]
		return
	# Environment curriculum may choose targets; policy never receives their IDs.
	if levels[2] >= 6 and rng.randf() < .5:
		var weakest = -1
		var score = 2.0
		for i in range(10):
			var value = (position_wins[i] + 1.0) / (position_tries[i] + 2.0)
			if i != target and value < score:
				weakest = i
				score = value
		target = weakest
	else:
		target = posmod(target + rng.randi_range(1, 9), 10)
	variant = card_rng.randi_range(0, Digits.TRAIN_PER_DIGIT - 1)

func accuracy() -> float:
	if recent.is_empty(): return 0.0
	var total = 0.0
	for value in recent: total += value
	return total / recent.size()

func _replay(model, passes: int, capacity: int) -> void:
	if archive.is_empty(): return
	var start = maxi(0, archive.size() - capacity)
	var positives: Array = []
	if levels[1] >= 6:
		for i in range(start, archive.size()):
			if archive[i].correct: positives.append(i)
	for i in range(passes):
		var sample = archive[rng.randi_range(start, archive.size() - 1)]
		if levels[1] >= 6 and i % 4 == 0 and not positives.is_empty():
			sample = archive[positives[rng.randi_range(0, positives.size() - 1)]]
		elif levels[1] >= 5:
			var error: float = -log(maxf(.000001, model.predict(sample.x)[int(sample.label)]))
			for attempt in range(2):
				var candidate = archive[rng.randi_range(start, archive.size() - 1)]
				var candidate_error: float = -log(maxf(.000001, model.predict(candidate.x)[int(candidate.label)]))
				if candidate_error > error:
					sample = candidate
					error = candidate_error
		model.train(sample.x, int(sample.label))

func start_exam() -> bool:
	if not unlocked("self_press") or exam_active or not pending.is_empty(): return false
	exam_saved_target = target
	exam_saved_variant = variant
	exam_order = range(10)
	# Separate RNG: exams don't change training randomness or its input context.
	var exam_rng = RandomNumberGenerator.new()
	exam_rng.seed = trials + 911
	for i in range(9, 0, -1):
		var j = exam_rng.randi_range(0, i)
		var old = exam_order[i]
		exam_order[i] = exam_order[j]
		exam_order[j] = old
	exam_variants.clear()
	for digit in range(10): exam_variants.append(exam_rng.randi_range(0, Digits.TEST_PER_DIGIT - 1))
	exam_results.clear()
	exam_summary.clear()
	exam_active = true
	target = exam_order[0]
	variant = exam_variants[0]
	return true

func _finish_exam() -> void:
	var score = 0
	for value in exam_results: score += value
	var rank = 3 if score >= 8 else (2 if score >= 6 else (1 if score >= 3 else 0))
	var reward = 0
	for tier in range(medals[camera_mode], rank): reward += [60, 120, 240][tier]
	exam_summary = {"score": score, "previous": exam_last[camera_mode], "rank": rank, "reward": reward}
	exam_last[camera_mode] = score
	exam_best[camera_mode] = maxi(exam_best[camera_mode], score)
	medals[camera_mode] = maxi(medals[camera_mode], rank)
	credits += reward
	exam_active = false
	target = exam_saved_target
	variant = exam_saved_variant

func coach_state() -> Dictionary:
	return {"task": "mnist", "trials": trials, "credits": credits, "levels": levels.duplicate(), "recent": recent.duplicate(),
		"camera": camera_mode, "exam_best": exam_best.duplicate(), "demonstrations": demonstrations,
		"position_tries": position_tries.duplicate(), "position_wins": position_wins.duplicate(),
		"hidden": brain.hidden_count, "learning_steps": brain.steps, "streak": streak}

func snapshot() -> Dictionary:
	return {"version": 4, "task": "mnist", "variant": exam_saved_variant if exam_active else variant, "card_rng": str(card_rng.state), "brain": brain.snapshot(), "credits": credits, "levels": levels.duplicate(),
		"trials": trials, "successes": successes, "target": exam_saved_target if exam_active else target,
		"archive": archive.duplicate(true), "recent": recent.duplicate(), "self_upgrades": self_upgrades,
		"camera_mode": camera_mode, "rng": str(rng.state), "demonstrations": demonstrations,
		"position_tries": position_tries.duplicate(), "position_wins": position_wins.duplicate(),
		"exam_best": exam_best.duplicate(), "exam_last": exam_last.duplicate(), "medals": medals.duplicate()}

func restore(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 4 or data.get("task") != "mnist" or not data.get("brain") is Dictionary: return false
	if not Brain._row_ok(data.get("levels"), 4): return false
	for level in data.levels:
		if level < 0 or level > MAX_LEVEL or float(level) != float(int(level)): return false
	var candidate = Brain.new()
	if not candidate.restore(data.brain) or candidate.hidden_count != 8 + int(data.levels[0]) * 4: return false
	if not data.get("archive") is Array: return false
	for sample in data.archive:
		if not sample is Dictionary or not Brain._row_ok(sample.get("x"), Brain.INPUTS): return false
		if not sample.get("label") is float and not sample.get("label") is int: return false
		if sample.label < 0 or sample.label > 9 or sample.label != int(sample.label) or not sample.get("correct") is bool: return false
	brain = candidate
	levels = data.levels.map(func(v): return int(v))
	credits = clampi(int(data.get("credits", 0)), 0, 10000000)
	trials = clampi(int(data.get("trials", 0)), 0, 10000000)
	successes = clampi(int(data.get("successes", 0)), 0, trials)
	target = clampi(int(data.get("target", 4)), 0, 9)
	variant = clampi(int(data.get("variant", 0)), 0, Digits.TRAIN_PER_DIGIT - 1)
	card_rng.state = int(data.get("card_rng", "198"))
	archive = data.archive.slice(maxi(0, data.archive.size() - 2048))
	recent = []
	if data.get("recent") is Array:
		for value in data.recent.slice(-24):
			if value in [0.0, 1.0]: recent.append(int(value))
	self_upgrades = maxi(0, int(data.get("self_upgrades", 0)))
	camera_mode = clampi(int(data.get("camera_mode", 0)), 0, 1)
	demonstrations = clampi(int(data.get("demonstrations", 0)), 0, trials)
	for key in ["position_tries", "position_wins", "exam_best", "exam_last", "medals"]:
		var size_value = 10 if key.begins_with("position") else 2
		if Brain._row_ok(data.get(key), size_value):
			var lower = -1 if key.begins_with("exam") else 0
			var upper = 3 if key == "medals" else (10 if key.begins_with("exam") else 10000000)
			set(key, data[key].map(func(v): return clampi(int(v), lower, upper)))
	rng.state = int(data.get("rng", "71"))
	auto_research = false
	exam_active = false
	pending.clear()
	return true
