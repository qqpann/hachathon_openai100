extends Control
signal closed
const Fonts = preload("res://scripts/ui_fonts.gd")
var game
var key_input: LineEdit
var feedback: Label
var actions: Array[Button] = []
var submitting = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tint = ColorRect.new()
	tint.color = Color(.02, .045, .06, .96)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(tint)
	var panel = PanelContainer.new()
	panel.position = Vector2(310, 210)
	panel.size = Vector2(820, 470)
	var theme_value = Theme.new()
	theme_value.default_font = Fonts.make(PackedStringArray(["Hiragino Sans", "Noto Sans CJK JP", "sans-serif"]))
	theme_value.default_font_size = 18
	panel.theme = theme_value
	var style = StyleBoxFlat.new()
	style.bg_color = Color("142832")
	style.border_color = Color("77edbd")
	style.set_border_width_all(2)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var title = _label("自分のOpenAIキーで、育成を任せる。", 27)
	title.add_theme_color_override("font_color", Color("77edbd"))
	column.add_child(title)
	var description = _label("OpenAI APIキーを入力すると、この起動中だけコーチを利用できます。\nキーはこのPCの接続サービスに渡し、ファイルに保存しません。\n利用料金は、あなたのOpenAIアカウントにかかります。", 17)
	column.add_child(description)
	key_input = LineEdit.new()
	key_input.placeholder_text = "OpenAI APIキー（sk-…）"
	key_input.secret = true
	key_input.context_menu_enabled = false
	key_input.max_length = 512
	key_input.custom_minimum_size = Vector2(0, 48)
	key_input.text_submitted.connect(func(_text): _submit())
	column.add_child(key_input)
	column.add_child(_label("貼り付け：⌘V / Ctrl+V　｜　ゲーム終了時にキーを破棄\nモデル：gpt-5.4-nano　｜　最大20回 / この起動中", 15))
	feedback = _label(game.coach.health_note, 16)
	feedback.custom_minimum_size = Vector2(0, 50)
	column.add_child(feedback)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	_button(row, "戻る", _close)
	_button(row, "キーを破棄", func(): _configure(""))
	_button(row, "この起動中に使う", _submit)
	key_input.grab_focus()

func _label(value: String, size_value: int) -> Label:
	var label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", Color("e6ecd7"))
	return label

func _button(parent: Node, label: String, action: Callable) -> void:
	var button = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	actions.append(button)

func _submit() -> void:
	if key_input.text.strip_edges() == "":
		feedback.text = "APIキーを入力してください。"
		return
	_configure(key_input.text.strip_edges())

func _configure(key: String) -> void:
	if submitting: return
	submitting = true
	key_input.clear()
	key_input.editable = false
	for button in actions: button.disabled = true
	feedback.text = "設定しています…"
	var result = await game.coach.set_api_key(key)
	key = ""
	feedback.text = result.message
	game.status = result.message
	submitting = false
	key_input.editable = true
	for button in actions: button.disabled = false

func _close() -> void:
	if submitting: return
	key_input.clear()
	closed.emit()
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
