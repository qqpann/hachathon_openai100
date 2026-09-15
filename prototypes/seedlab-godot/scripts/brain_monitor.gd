extends Node2D
const Fonts = preload("res://scripts/ui_fonts.gd")
## The always-on screen rendered onto the physical workbench monitor.
const INK = Color("091c23")
const MINT = Color("82f2c2")
const GOLD = Color("ffc56d")
const PAPER = Color("e1ecd9")
const DIM = Color("729795")
var lab
var camera_texture: Texture2D
var pixels: Array = []
var outputs: Array = []
var activities: Array = []
var coach_active = false
var phase = "READY"
var font: Font

func _ready() -> void:
	font = Fonts.make(PackedStringArray(["Hiragino Sans", "Noto Sans CJK JP", "sans-serif"]))

func clear_signal() -> void:
	pixels.clear()
	outputs.clear()
	activities.clear()
	queue_redraw()

func _text(point: Vector2, value: String, size_value: int, color: Color = PAPER) -> void:
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, color)

func _unit_position(index: int) -> Vector2:
	var columns = 4
	var rows = maxi(2, ceili(lab.brain.hidden_count / 4.0))
	return Vector2(470 + (index % columns) * 83, 146 + (index / columns) * (212.0 / maxi(1, rows - 1)))

func _draw() -> void:
	if lab == null or font == null: return
	draw_rect(Rect2(0, 0, 1280, 480), INK)
	for y in range(0, 480, 4): draw_line(Vector2(0, y), Vector2(1280, y), Color(0, .05, .05, .20), 1)
	_text(Vector2(29, 47), "NEURAL / LIVE", 30, MINT)
	_text(Vector2(865, 47), "学習  %d 回" % lab.brain.steps, 30, MINT)
	draw_circle(Vector2(1241, 35), 7, GOLD if coach_active else MINT)
	draw_line(Vector2(28, 66), Vector2(1252, 66), Color("31554f"), 2)
	_text(Vector2(30, 108), "見る", 34, PAPER)
	_text(Vector2(451, 108), "考える / %d 個" % lab.brain.hidden_count, 34, PAPER)
	_text(Vector2(881, 108), "数字の予測", 32, PAPER)
	if camera_texture:
		draw_texture_rect(camera_texture, Rect2(30, 136, 174, 174), false)
	if pixels.size() == 144:
		for y in range(12):
			for x in range(12):
				draw_rect(Rect2(218 + x * 12, 151 + y * 12, 11, 11), INK.lerp(GOLD, pixels[y * 12 + x]))
	_text(Vector2(30, 348), "固定カメラ" if lab.camera_mode == 0 else "手先カメラ", 29, DIM)
	_text(Vector2(221, 348), "12 × 12", 27, DIM)
	# One strongest pixel connection per hidden unit, with its learned sign.
	for h in range(lab.brain.hidden_count):
		var strongest = 0
		for p in range(1, 144):
			if absf(lab.brain.wi[h][p]) > absf(lab.brain.wi[h][strongest]): strongest = p
		var from = Vector2(224 + (strongest % 12) * 12, 157 + (strongest / 12) * 12)
		var edge = MINT if lab.brain.wi[h][strongest] >= 0 else GOLD
		edge.a = .20
		draw_line(from, _unit_position(h), edge, 1.5, true)
	# Actual strongest hidden-to-output connection for each of the ten digits.
	for action in range(10):
		var strongest = 0
		for h in range(1, lab.brain.hidden_count):
			if absf(lab.brain.wo[action][h]) > absf(lab.brain.wo[action][strongest]): strongest = h
		draw_line(_unit_position(strongest), Vector2(882 + (action % 2) * 179, 155 + (action / 2) * 50), Color(.45, .9, .7, .18), 1.5, true)
	for h in range(lab.brain.hidden_count):
		var value: float = activities[h] if h < activities.size() else 0.0
		var center = _unit_position(h)
		draw_circle(center, 12, Color("244740"))
		draw_circle(center, 5 + absf(value) * 5, MINT if value >= 0 else GOLD)
	var best = -1
	if outputs.size() == 10:
		best = 0
		for action in range(1, 10):
			if outputs[action] > outputs[best]: best = action
	for action in range(10):
		var corner = Vector2(880 + (action % 2) * 179, 130 + (action / 2) * 50)
		var value: float = outputs[action] if outputs.size() == 10 else 0.0
		var color = GOLD if action == best else MINT
		draw_style_box(_tile(color, action == best), Rect2(corner, Vector2(166, 45)))
		_text(corner + Vector2(10, 31), str(action), 30, color)
		_text(corner + Vector2(67, 30), "%d%%" % (value * 100), 22, PAPER)
		draw_rect(Rect2(corner + Vector2(10, 36), Vector2(value * 145, 4)), color)
	draw_line(Vector2(28, 398), Vector2(1252, 398), Color("31554f"), 2)
	var summary = "見て、考えています。手書きと同じ数字を押して教えよう。"
	if coach_active:
		summary = "OpenAIコーチが強化盤を確認中 / NNの予測は待機"
	elif lab.exam_active:
		summary = "認定試験 / 重みを固定して挑戦中  %d / 10" % mini(10, lab.exam_results.size() + 1)
	elif not lab.last_lesson.is_empty():
		var lesson = lab.last_lesson
		summary = "直前の採点：%d / %s  学習前 %d%% → 学習後 %d%%" % [lesson.label, "成功" if lesson.correct else "失敗", lesson.before * 100, lesson.after * 100]
	_text(Vector2(30, 448), summary, 29, MINT)

func _tile(color: Color, selected: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("173b38") if selected else Color("102e31")
	style.border_color = color.darkened(.25) if selected else Color("31504e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	return style
