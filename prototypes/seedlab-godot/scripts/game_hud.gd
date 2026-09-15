extends Node2D
## Native Godot instrument panel; matrices remain physical clickable objects.
const DARK = Color("142832")
const PAPER = Color("e6ecd7")
const MUTED = Color("8aa8ad")
const MINT = Color("77edbd")
const GOLD = Color("ffbf61")
const ORANGE = Color("ed8544")
var game
var font: SystemFont
var latin: SystemFont
var hitboxes: Array = []

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans", "Noto Sans CJK JP", "Yu Gothic", "sans-serif"])
	font.font_weight = 600
	latin = SystemFont.new()
	latin.font_names = PackedStringArray(["Avenir Next", "sans-serif"])
	latin.font_weight = 700

func hit_at(point: Vector2) -> String:
	for item in hitboxes:
		if item.rect.has_point(point): return item.id
	return ""

func _draw() -> void:
	if game == null or font == null: return
	hitboxes.clear()
	_header()
	_mission()
	_observation()
	_controls()
	_coach()
	_growth_hint()
	if game.result_time > 0:
		center_text(Vector2(720, 128), game.result_text, 21, MINT if game.result_good else GOLD)
	if game.show_help: _help()
	if game.show_reset: _reset()

func _header() -> void:
	text_at(Vector2(32, 51), "S E E D L A B", 30, PAPER, latin)
	text_at(Vector2(34, 78), "BUTTON GARDEN  /  小さな知能を育てる実験室", 13, MUTED)
	draw_line(Vector2(33, 104), Vector2(1408, 104), Color("38525c"), 1)
	plate(Rect2(1110, 22, 298, 70), DARK, GOLD)
	text_at(Vector2(1130, 49), "所持金", 13, GOLD)
	text_at(Vector2(1128, 80), "%s G" % game.lab.credits, 27, PAPER, latin)
	button(Rect2(900, 34, 144, 44), "help", "遊び方  /  H", false, 14)
	text_at(Vector2(385, 61), "見て、押して、覚える。", 19, MINT)
	text_at(Vector2(386, 84), "テーブルのモニターで、考える様子を観察しよう。", 12, MUTED)

func _mission() -> void:
	var lab = game.lab
	text_at(Vector2(34, 153), "読む → 押す → 稼ぐ", 15, MINT)
	text_at(Vector2(33, 181), "手書き数字を読もう。", 20, PAPER)
	text_at(Vector2(34, 205), "同じ数字を右のボタンで答えよう。" if lab.unlocked("self_press") else "お手本で貯めて「自分で押す」を解放しよう。", 12, MUTED)
	var best = lab.exam_best[lab.camera_mode]
	button(Rect2(34, 550, 240, 43), "exam", "試験中  %d / 10" % (lab.exam_results.size() + 1) if lab.exam_active else ("10問の認定試験に挑む  /  T" if lab.unlocked("self_press") else "認定試験 / 学び方 I で解放"), lab.exam_active, 14, lab.unlocked("self_press"))
	text_at(Vector2(34, 618), "最高 %s / 10  ｜  メダルは 3・6・8 正解" % ("—" if best < 0 else str(best)), 12, GOLD)
	for i in range(10):
		var color = MINT if i < lab.exam_results.size() and lab.exam_results[i] == 1 else (ORANGE if i < lab.exam_results.size() else Color("314d57"))
		draw_circle(Vector2(40 + i * 24, 635), 4, color)

func _observation() -> void:
	text_at(Vector2(34, 464), "強化は、机のボタンで。", 17, GOLD)
	text_at(Vector2(34, 488), "重ねると効果、クリックで購入。", 12, MUTED)
	text_at(Vector2(34, 510), "↔ ボタンで基礎と拡張を切り替え。", 12, MUTED)
	text_at(Vector2(35, 665), "設備の解放", 15, MINT)
	var items = [["self_press", "自分で押す", "学び方 I"], ["auto_practice", "自動練習", "学び方 II"], ["speed_2", "2倍速", "アーム I"], ["speed_3", "3倍速", "アーム III"]]
	for i in range(items.size()):
		var ready: bool = game.lab.unlocked(items[i][0])
		text_at(Vector2(35, 698 + i * 31), ("✓ " if ready else "・ ") + items[i][1], 13, MINT if ready else MUTED)
		text_at(Vector2(169, 698 + i * 31), "解放済み" if ready else items[i][2], 12, MUTED)
	button(Rect2(32, 852, 190, 29), "eye", "固定カメラ  /  V" if game.lab.camera_mode == 0 else "手先カメラ  /  V", false, 12)
	button(Rect2(234, 852, 135, 29), "view", "視界を拡大  /  C", false, 12)

func _controls() -> void:
	plate(Rect2(376, 680, 664, 81), Color(.055, .115, .15, .90), Color("38525c"))
	plate(Rect2(376, 771, 664, 70), Color("19333d"), Color("597d81"))
	button(Rect2(390, 783, 298, 46), "launch", "NNに一度押させる  /  SPACE" if game.lab.unlocked("self_press") else "未解放 / 自分で押す", false, 15, game.lab.unlocked("self_press"))
	button(Rect2(700, 783, 222, 46), "auto", "自動練習を停止  /  A" if game.auto_trials else ("自動で練習  /  A" if game.lab.unlocked("auto_practice") else "未解放 / ひとり練習"), game.auto_trials, 14, game.lab.unlocked("auto_practice"))
	button(Rect2(934, 783, 91, 46), "speed", "× %d" % game.speed if game.lab.unlocked("speed_2") else "×1 固定", false, 16, game.lab.unlocked("speed_2"))
	var status_lines = wrap_lines(game.status, 650, 14)
	for i in range(mini(2, status_lines.size())): text_at(Vector2(386, 726 + i * 22), status_lines[i], 14, PAPER)
	button(Rect2(387, 852, 190, 29), "home", "作業台へ戻る  /  F", false, 12)
	text_at(Vector2(592, 873), "右ドラッグ：回転  /  ホイール：距離", 12, MUTED)
	var unlocked = game.lab.can_delegate()
	var label = "委任を停止  /  R" if game.lab.auto_research else ("OpenAIに育成を任せる  /  R" if unlocked else ("未解放 / 育成委任を購入" if not game.lab.unlocked("coach") else "あと %d 回でコーチ準備完了" % (24 - game.lab.trials)))
	button(Rect2(1070, 778, 338, 62), "research", label, game.lab.auto_research, 16, unlocked)
	text_at(Vector2(1083, 869), "練習24回ごとに相談  /  最短30秒間隔", 12, MUTED)
	text_at(Vector2(385, 701), "練習 %d 回   ｜   直近24回：%d%%（お手本を含む）" % [game.lab.trials, game.lab.accuracy() * 100], 12, MUTED)
	if game.save_error: text_at(Vector2(1070, 754), "保存できませんでした", 13, GOLD)

func _coach() -> void:
	plate(Rect2(1114, 385, 294, 296), Color(.055, .115, .15, .94), Color("38525c"))
	text_at(Vector2(1130, 415), "OPENAI コーチ", 18, GOLD)
	text_at(Vector2(1131, 440), "gpt-5.4-nano  /  相談 %d 回" % game.coach.calls, 12, MUTED)
	var label = "成績と盤面を見て、考えています…" if game.coach.waiting else game.coach_reason
	wrapped(Vector2(1130, 471), label, 257, 13, PAPER, 23)
	if game.coach_goal != "":
		text_at(Vector2(1130, 581), "コーチからの次の目標", 12, MINT)
		wrapped(Vector2(1130, 606), game.coach_goal, 257, 12, MUTED, 21)
	elif not game.lab.auto_research:
		wrapped(Vector2(1130, 586), game.coach.health_note, 257, 12, MINT if game.coach.available else MUTED, 21)
		if not game.coach.available:
			button(Rect2(1130, 630, 255, 32), "connect", "接続準備中…" if game.coach.connecting else "コーチに再接続", false, 13)

func _growth_hint() -> void:
	var row = -1
	var col = -1
	if game.hover.get("kind") == "growth":
		row = int(game.hover.index) / 6
		col = int(game.hover.index) % 6
	if row < 0: return
	var info = game.lab.upgrade_info(row, col)
	var color = game.World.BRANCH_COLORS[row]
	plate(Rect2(1114, 139, 294, 225), DARK, color)
	text_at(Vector2(1130, 169), "%s  Lv.%d" % [game.Lab.NAMES[row], col + 1], 13, color)
	text_at(Vector2(1130, 198), info.name, 21, PAPER)
	wrapped(Vector2(1130, 224), info.effect, 257, 13, PAPER, 21)
	var hint = "購入済み" if col < game.lab.levels[row] else ("前の段階を購入すると解放" if col > game.lab.levels[row] else "%d Gで購入" % game.lab.cost(row))
	text_at(Vector2(1130, 345), hint, 14, color)

func _help() -> void:
	draw_rect(Rect2(0, 0, 1440, 900), Color(.025, .055, .08, .92))
	hitboxes.clear()
	plate(Rect2(310, 140, 820, 625), DARK, MINT)
	text_at(Vector2(350, 190), "小さな知能を、あなたの手で。", 28, PAPER)
	var lines = [
		["01  教える", "左奥の手書き数字と同じボタンを押す。採点後にNNが正解を学ぶ。"],
		["02  育てる", "机の強化ボタンに重ねて効果を見る。Gで好きな行を育てよう。"],
		["03  試す", "Tで未学習の筆跡10問に挑戦。3 / 6 / 8点でメダルとG。"],
		["04  任せる", "学び方 III「育成委任」と24回の経験でR。OpenAIが強化を選ぶ。"],
		["05  観察する", "テーブル奥のモニターに、実際の視界・ニューロン・予測を常時表示。"]]
	for i in range(lines.size()):
		text_at(Vector2(351, 247 + i * 69), lines[i][0], 18, MINT)
		text_at(Vector2(351, 273 + i * 69), lines[i][1], 14, PAPER)
	text_at(Vector2(351, 618), "アーム Iで×2、IIIで×3を解放。V カメラ切替 / F 作業台 / M 消音", 13, MUTED)
	text_at(Vector2(351, 647), "失敗でも +5G。メダル報酬はカメラごとに初回だけ。", 13, GOLD)
	button(Rect2(351, 693, 190, 42), "reset", "はじめから", false, 14)
	button(Rect2(812, 693, 275, 42), "close_help", "育成を続ける  /  Esc", true, 14)

func _reset() -> void:
	draw_rect(Rect2(0, 0, 1440, 900), Color(.025, .055, .08, .95))
	hitboxes.clear()
	plate(Rect2(432, 319, 576, 264), DARK, GOLD)
	text_at(Vector2(470, 369), "新しいNNを育てますか？", 26, PAPER)
	text_at(Vector2(470, 410), "学習・お金・強化・メダルをリセットします。", 14, MUTED)
	button(Rect2(470, 495, 190, 45), "cancel_reset", "今の子を育てる", false, 15)
	button(Rect2(685, 495, 282, 45), "confirm_reset", "リセットして始める", true, 15)

func wrap_lines(value: String, width: float, size_value: int) -> Array:
	var lines: Array = []
	var line = ""
	for character in value:
		if character == "\n" or font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value).x > width:
			lines.append(line)
			line = "" if character == "\n" else character
		else: line += character
	if line != "": lines.append(line)
	return lines

func wrapped(point: Vector2, value: String, width: float, size_value: int, color: Color, spacing: float) -> void:
	var lines = wrap_lines(value, width, size_value)
	for i in range(lines.size()): text_at(point + Vector2(0, i * spacing), lines[i], size_value, color)

func plate(rect: Rect2, fill: Color, edge: Color) -> void:
	var c = 10.0
	var x = rect.position.x
	var y = rect.position.y
	var r = rect.end.x
	var b = rect.end.y
	var points = PackedVector2Array([Vector2(x + c, y), Vector2(r, y), Vector2(r, b - c), Vector2(r - c, b), Vector2(x, b), Vector2(x, y + c)])
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, edge, 1, true)

func button(rect: Rect2, id: String, label: String, selected: bool = false, size_value: int = 14, available: bool = true) -> void:
	var hover: bool = rect.has_point(game.pointer)
	var fill = (ORANGE if selected else Color("203c47")) if available else Color("142a33")
	if hover: fill = fill.lightened(.13)
	plate(rect, fill, GOLD if selected else (Color("607d83") if available else Color("38505a")))
	draw_line(rect.position + Vector2(10, 4), Vector2(rect.end.x - 5, rect.position.y + 4), Color(1, 1, 1, .15), 1)
	draw_line(Vector2(rect.position.x + 5, rect.end.y - 4), Vector2(rect.end.x - 10, rect.end.y - 4), Color(0, 0, 0, .2), 3)
	center_text(rect.get_center() + Vector2(0, size_value * .35), label, size_value, (Color("192b32") if selected else PAPER) if available else MUTED)
	hitboxes.append({"id": id, "rect": rect})

func text_at(point: Vector2, value: String, font_size: int, color: Color, selected_font: Font = null) -> void:
	var chosen = selected_font if selected_font else font
	draw_string_outline(chosen, point + Vector2(0, 1), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, .20))
	draw_string(chosen, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func center_text(point: Vector2, value: String, font_size: int, color: Color, selected_font: Font = null) -> void:
	var chosen = selected_font if selected_font else font
	var width = chosen.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	text_at(point - Vector2(width / 2, 0), value, font_size, color, chosen)

func _hex(center: Vector2, radius: float, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(6): points.append(center + Vector2.from_angle(PI / 6 + i * TAU / 6) * radius)
	draw_colored_polygon(points, color)
