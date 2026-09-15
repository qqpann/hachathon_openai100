extends Node3D
const Monitor = preload("res://scripts/brain_monitor.gd")
const Arm = preload("res://scripts/robot_arm.gd")
const WORKBENCH = preload("res://assets/workbench.glb")
const INK = Color("13272e")
const CREAM = Color("dce3cb")
const AMBER = Color("ffae46")
const MINT = Color("73f3c2")
const BRANCH_COLORS = [Color("62dbbd"), Color("64b9e3"), Color("ae98f1"), Color("f5ac65")]
const PRACTICE_CENTER = Vector3(2.3, 1.0, -.15)
const GROWTH_CENTER = Vector3(-2.3, 1.0, -.15)
var arm: Node3D
var camera: Camera3D
var vision_view: SubViewport
var eye: Camera3D
var monitor_view: SubViewport
var monitor_display
var monitor_root: Node3D
var digit_root: Node3D
var digit_material: StandardMaterial3D
var card_key = ""
var page_button: Dictionary
var practice: Array = []
var growth: Array = []
var sparks: Array = []
var nodes: Array = []
var aim = Vector3(0, 1.35, 0)
var yaw = .06
var pitch = .90
var distance = 14.1
var current_yaw = .06
var current_pitch = .90
var current_distance = 14.1
var view_mode = 0
var growth_view = false
var growth_page = 0
var saved_camera: Dictionary = {}
var camera_mode = 0
var time = 0.0
var hover_kind = ""
var hover_index = -1
var shake = 0.0
var font: SystemFont
var lab

func setup(state) -> void:
	lab = state
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "Hiragino Sans", "sans-serif"])
	font.font_weight = 700
	_environment()
	var bench = WORKBENCH.instantiate()
	add_child(bench)
	_clear_monitor_view(bench)
	growth_page = 1 if lab.levels.min() >= 4 else 0
	_boards()
	arm = Arm.new()
	add_child(arm)
	_make_neurons()
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = 48
	camera.near = .05
	camera.far = 120
	camera.current = true
	vision_view = SubViewport.new()
	vision_view.name = "RobotVision"
	vision_view.size = Vector2i(512, 512)
	vision_view.world_3d = get_world_3d()
	vision_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vision_view)
	eye = Camera3D.new()
	vision_view.add_child(eye)
	eye.current = true
	eye.near = .04
	eye.far = 40
	var paper_environment = Environment.new()
	paper_environment.background_mode = Environment.BG_COLOR
	paper_environment.background_color = Color.WHITE
	eye.environment = paper_environment
	_digit_card()
	_monitor()
	refresh_buttons()
	_update_cameras(1.0)

func _clear_monitor_view(node: Node) -> void:
	# Move the left task-light assembly to the table edge, clear of the screen.
	if node is Node3D and "light" in String(node.name).to_lower() and absf(node.position.x) > 3.0:
		node.position.x += signf(node.position.x) * 1.2
	for child in node.get_children(): _clear_monitor_view(child)

func _digit_card() -> void:
	digit_root = Node3D.new()
	digit_root.name = "Handwritten digit card"
	add_child(digit_root)
	digit_root.position = Vector3(-3.65, 2.87, -2.7)
	digit_root.rotation.x = -.44
	box(digit_root, Vector3.ZERO, Vector3(2.42, 2.59, .30), mat(CREAM))
	box(digit_root, Vector3(0, 0, .16), Vector3(2.27, 2.27, .06), mat(INK))
	var paper = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(2.15, 2.15)
	paper.mesh = quad
	paper.layers = 4
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	digit_material = StandardMaterial3D.new()
	digit_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	digit_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	paper.material_override = digit_material
	digit_root.add_child(paper)
	paper.position.z = .205
	var title = Label3D.new()
	title.text = "M N I S T  /  読む"
	title.font = font
	title.font_size = 27
	title.pixel_size = .005
	title.outline_size = 0
	title.modulate = INK
	digit_root.add_child(title)
	title.position = Vector3(0, -1.2, .19)
	box(self, Vector3(-3.65, 1.58, -2.95), Vector3(.14, 1.2, .18), mat(INK))
	box(self, Vector3(-3.65, 1.0, -2.7), Vector3(.78, .12, .88), mat(INK))
	# Camera housing sits beside the card; the policy camera sees only its ink.
	box(self, Vector3(-5.05, 2.3, -2.5), Vector3(.10, 2.7, .10), mat(INK))
	box(self, Vector3(-4.90, 3.6, -2.5), Vector3(.42, .25, .30), mat(CREAM))

func refresh_card() -> void:
	if digit_material == null: return
	var key = "%d:%d:%s" % [lab.target, lab.variant, lab.exam_active]
	if key == card_key: return
	card_key = key
	var source: Image = lab.card_image()
	source.resize(512, 512, Image.INTERPOLATE_CUBIC)
	digit_material.albedo_texture = ImageTexture.create_from_image(source)

func _monitor() -> void:
	monitor_view = SubViewport.new()
	monitor_view.name = "NeuralMonitorScreen"
	monitor_view.size = Vector2i(1280, 480)
	monitor_view.disable_3d = true
	monitor_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(monitor_view)
	monitor_display = Monitor.new()
	monitor_display.lab = lab
	monitor_display.camera_texture = vision_view.get_texture()
	monitor_view.add_child(monitor_display)
	monitor_root = Node3D.new()
	monitor_root.name = "Workbench neural monitor"
	add_child(monitor_root)
	var housing = Node3D.new()
	monitor_root.add_child(housing)
	housing.position = Vector3(.90, 2.87, -2.7)
	housing.rotation.x = -.44
	box(housing, Vector3.ZERO, Vector3(6.52, 2.59, .30), mat(CREAM))
	box(housing, Vector3(0, .05, .16), Vector3(6.32, 2.39, .08), mat(INK))
	var screen = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(6.12, 2.295)
	screen.mesh = quad
	var display_material = StandardMaterial3D.new()
	display_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	display_material.albedo_texture = monitor_view.get_texture()
	display_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.material_override = display_material
	housing.add_child(screen)
	screen.position = Vector3(0, .05, .208)
	for x in [-3.13, 3.13]:
		for y in [-1.17, 1.17]:
			var screw = cylinder(housing, Vector3(x, y, .17), .037, .045, mat(INK), 12)
			screw.rotation.x = PI / 2
	for x in [-1.0, 3.7]:
		box(monitor_root, Vector3(x, 1.58, -2.95), Vector3(.14, 1.20, .18), mat(INK))
		box(monitor_root, Vector3(x, 1.00, -2.70), Vector3(.78, .12, .88), mat(INK))
	for i in range(7):
		box(housing, Vector3(2.24 + i * .09, -1.19, .18), Vector3(.035, .08, .025), mat(INK))
	# Exclude the monitor and its shadows from both learning cameras. The
	# policy must never see a recursive screen containing its own predictions.
	_monitor_layer(monitor_root)

func _monitor_layer(node: Node) -> void:
	if node is VisualInstance3D: node.layers = 2
	if node is GeometryInstance3D: node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _monitor_layer(child)

func _environment() -> void:
	var world = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111f2a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bdcfdf")
	environment.ambient_light_energy = .32
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("ffe6b2")
	sun.light_energy = .82
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30
	add_child(sun)
	var fill = OmniLight3D.new()
	fill.position = Vector3(-4, 5, 3)
	fill.light_color = Color("79cddd")
	fill.light_energy = .40
	fill.omni_range = 14
	add_child(fill)
	var rim = OmniLight3D.new()
	rim.position = Vector3(2, 4, -4)
	rim.light_color = Color("ffac67")
	rim.light_energy = .55
	rim.omni_range = 10
	add_child(rim)
	box(self, Vector3(0, -.91, 0), Vector3(200, .1, 200), mat(Color("101c28"), 0, 0))
	var stage = cylinder(self, Vector3(0, -.80, 0), 6.7, .13, mat(Color("2d4b54")), 96)
	stage.name = "Workshop plinth"
	for i in range(28):
		var angle = i * TAU / 28
		box(self, Vector3(sin(angle) * 6.4, -.72, cos(angle) * 6.4), Vector3(.06, .01, .20), mat(Color("537477"))).rotation.y = angle

static func mat(color: Color, emission: float = 0.0, metallic: float = .15) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = .42
	if emission > 0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

static func box(parent: Node3D, position_value: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = BoxMesh.new()
	shape.size = size_value
	mesh.mesh = shape
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = position_value
	return mesh

static func cylinder(parent: Node3D, position_value: Vector3, radius: float, height: float, material: Material, segments: int = 32) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = segments
	mesh.mesh = shape
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = position_value
	return mesh

func _label(value: String, point: Vector3, font_size: int, scale_value: float, color: Color) -> Label3D:
	var label = Label3D.new()
	label.text = value
	label.font = font
	label.font_size = font_size
	label.pixel_size = scale_value
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.rotation_degrees.x = -90
	add_child(label)
	label.position = point
	return label

func _boards() -> void:
	for center in [PRACTICE_CENTER, GROWTH_CENTER]:
		box(self, center - Vector3(0, .13, 0), Vector3(3.65, .16, 3.75), mat(INK))
		box(self, center - Vector3(0, .025, 0), Vector3(3.45, .06, 3.5), mat(Color("244049")))
		for offset in [Vector3(-1.65, .005, -1.68), Vector3(1.65, .005, -1.68), Vector3(-1.65, .005, 1.68), Vector3(1.65, .005, 1.68)]:
			cylinder(self, center + offset, .045, .025, mat(CREAM))
	_label("数字を押す", PRACTICE_CENTER + Vector3(0, .05, -1.95), 44, .0065, INK)
	_label("Gで強化する", GROWTH_CENTER + Vector3(0, .05, -1.95), 44, .0065, INK)
	_label("S E E D  /  0 1", Vector3(0, .795, 2.8), 36, .009, INK)
	for i in range(10):
		var point = PRACTICE_CENTER + Vector3(0, .06, 1.31) if i == 0 else PRACTICE_CENTER + Vector3(((i - 1) % 3 - 1) * 1.03, .06, ((i - 1) / 3 - 1) * .83 - .38)
		practice.append(_button("practice", i, point, .34))
	for row in range(4):
		for col in range(6):
			var page = 0 if col < 4 else 1
			var offset = (col - 1.5) * .69 if page == 0 else (col - 4.5) * 1.36
			var point = GROWTH_CENTER + Vector3(offset, .06, (row - 1.5) * .75)
			var button = _button("growth", row * 6 + col, point, .265 if page == 0 else .31)
			button["page"] = page
			growth.append(button)
		_label(["ひらめき", "記憶", "学び方", "アーム"][row], GROWTH_CENTER + Vector3(-1.48, .08, (row - 1.5) * .75), 23, .007, BRANCH_COLORS[row]).rotation_degrees.y = 90
	page_button = _button("page", 0, GROWTH_CENTER + Vector3(0, .03, 2.03), .23)
	page_button.label.text = "↔"
	_label("基礎 / 拡張", GROWTH_CENTER + Vector3(0, .08, 2.52), 22, .007, INK)

func _button(kind: String, index: int, point: Vector3, radius: float) -> Dictionary:
	var base = cylinder(self, point - Vector3(0, .01, 0), radius + .055, .09, mat(Color("0b1920")))
	var ring = cylinder(self, point + Vector3(0, .035, 0), radius + .025, .03, mat(Color("3c6871")))
	var cap = Node3D.new()
	add_child(cap)
	cap.position = point
	var cap_mat = mat(Color("376570"))
	cylinder(cap, Vector3(0, .105, 0), radius, .16, cap_mat)
	cylinder(cap, Vector3(0, .19, 0), radius * .85, .018, cap_mat)
	var label = Label3D.new()
	cap.add_child(label)
	label.text = str(index) if kind == "practice" else str(index % 6 + 1)
	label.font = font
	label.font_size = 48 if kind == "practice" else 24
	label.pixel_size = .008
	label.outline_size = 0
	label.modulate = Color("a0c4c3")
	label.position.y = .207
	label.rotation_degrees.x = -90
	var body = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("kind", kind)
	body.set_meta("index", index)
	add_child(body)
	body.position = point + Vector3(0, .1, 0)
	var collision = CollisionShape3D.new()
	var shape = CylinderShape3D.new()
	shape.radius = radius + .035
	shape.height = .27
	collision.shape = shape
	body.add_child(collision)
	return {"base": base, "cap": cap, "mat": cap_mat, "ring": ring, "point": point, "label": label, "body": body, "index": index}

func _make_neurons() -> void:
	for i in range(32):
		var a = i * TAU / 8
		var point = Vector3(sin(a) * .38, 1.14 + (i / 8) * .12, 1.75 + cos(a) * .38)
		var node = cylinder(self, point, .035, .055, mat(MINT, 1.0), 12)
		nodes.append(node)

func refresh_buttons() -> void:
	refresh_card()
	for i in range(10):
		# All answers look identical until the robot presses and gets feedback.
		set_button(practice[i], Color("32636c"), 0.0)
	for i in range(24):
		var row = i / 6
		var col = i % 6
		var button = growth[i]
		var active: bool = col < lab.levels[row]
		var next: bool = col == lab.levels[row]
		var visible_value: bool = button.page == growth_page
		button.base.visible = visible_value
		button.cap.visible = visible_value
		button.ring.visible = visible_value
		button.body.collision_layer = 1 if visible_value else 0
		var color = BRANCH_COLORS[row] if active else (BRANCH_COLORS[row].darkened(.10) if next and lab.can_upgrade(row) else Color("2b424b"))
		set_button(button, color, .25 if active else 0.0)
		var upgrade = lab.upgrade_info(row, col)
		button.label.font_size = 16 if next else 24
		var name_value: String = upgrade.name
		if name_value.length() > 4: name_value = name_value.substr(0, 3) + "\n" + name_value.substr(3)
		button.label.text = name_value + "\n%dG" % lab.cost(row) if next else ("✓" if active else str(col + 1))
		button.label.modulate = INK if active else CREAM
	for i in range(nodes.size()):
		nodes[i].visible = i < lab.brain.hidden_count

func set_button(button: Dictionary, color: Color, glow: float = 0.0) -> void:
	button.mat.albedo_color = color
	button.mat.emission_enabled = glow > 0
	button.mat.emission = color
	button.mat.emission_energy_multiplier = glow

func depress(button: Dictionary) -> void:
	var tween = create_tween()
	tween.tween_property(button.cap, "position:y", button.point.y - .10, .07)
	tween.tween_interval(.10)
	tween.tween_property(button.cap, "position:y", button.point.y, .20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func burst(point: Vector3, color: Color, amount: int = 14) -> void:
	for i in range(amount):
		var particle = box(self, point, Vector3(.045, .045, .045), mat(color, .7))
		var angle = i * TAU / amount
		sparks.append({"node": particle, "velocity": Vector3(cos(angle) * randf_range(.6, 1.4), randf_range(1.0, 2.1), sin(angle) * randf_range(.6, 1.4)), "life": .8})
	shake = .025

func _process(delta: float) -> void:
	if lab == null:
		return
	time += delta
	_update_cameras(delta)
	for i in range(sparks.size() - 1, -1, -1):
		var s = sparks[i]
		s.life -= delta
		s.velocity.y -= delta * 3
		s.node.position += s.velocity * delta
		s.node.rotation += Vector3.ONE * delta * 3
		s.node.scale = Vector3.ONE * maxf(.01, s.life / .8)
		if s.life <= 0:
			s.node.queue_free()
			sparks.remove_at(i)
	for i in range(mini(nodes.size(), lab.brain.activity.size())):
		nodes[i].scale = Vector3.ONE * (1.0 + absf(lab.brain.activity[i]) * .65 + sin(time * 3 + i) * .1)
	for kind in ["practice", "growth"]:
		var buttons = practice if kind == "practice" else growth
		for button in buttons:
			var material: StandardMaterial3D = button.ring.material_override
			material.albedo_color = CREAM if hover_kind == kind and hover_index == button.index else Color("3c6871")

func _update_cameras(delta: float) -> void:
	if camera == null:
		return
	current_yaw = lerp_angle(current_yaw, yaw, minf(1, delta * 4))
	current_pitch = lerpf(current_pitch, pitch, minf(1, delta * 4))
	current_distance = lerpf(current_distance, distance, minf(1, delta * 3))
	var center = GROWTH_CENTER if growth_view else digit_root.to_global(Vector3(0, 0, .205))
	eye.cull_mask = 1 if growth_view else 4
	if growth_view:
		eye.projection = Camera3D.PROJECTION_ORTHOGONAL
		eye.size = 3.90
		eye.global_position = center + Vector3(0, 3.8, -.75)
		eye.look_at(center, Vector3.FORWARD)
	elif camera_mode == 0:
		eye.projection = Camera3D.PROJECTION_ORTHOGONAL
		eye.size = 2.15
		eye.global_position = center + digit_root.global_basis.z * 3.0
		eye.look_at(center, digit_root.global_basis.y)
	else:
		eye.projection = Camera3D.PROJECTION_PERSPECTIVE
		eye.fov = 30
		eye.global_position = arm.tip + Vector3(.0, -.04, -.31)
		eye.look_at(center, digit_root.global_basis.y)
	if view_mode == 1:
		camera.projection = eye.projection
		camera.size = eye.size * 1.25
		camera.fov = eye.fov
		camera.global_transform = eye.global_transform
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 48
		var direction = Vector3(sin(current_yaw) * cos(current_pitch), sin(current_pitch), cos(current_yaw) * cos(current_pitch))
		camera.position = aim + direction * current_distance
		camera.position.x += sin(time * 90) * shake
		camera.look_at(aim)
	shake = move_toward(shake, 0, delta * .12)

func pick(point: Vector2) -> Dictionary:
	var from = camera.project_ray_origin(point)
	var query = PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(point) * 100, 1)
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	return {"kind": hit.collider.get_meta("kind", ""), "index": hit.collider.get_meta("index", -1)}

func reset_camera() -> void:
	saved_camera.clear()
	yaw = .06
	pitch = .90
	distance = 14.1
	view_mode = 0

func reveal() -> void:
	if saved_camera.is_empty():
		saved_camera = {"yaw": yaw, "pitch": pitch, "distance": distance, "view_mode": view_mode}
	view_mode = 0
	yaw = -.40
	pitch = .66
	distance = 16.0

func restore_camera() -> void:
	if saved_camera.is_empty(): return
	yaw = saved_camera.yaw
	pitch = saved_camera.pitch
	distance = saved_camera.distance
	view_mode = saved_camera.view_mode
	saved_camera.clear()

func manual_camera() -> void:
	saved_camera.clear()

func set_growth_page(page: int) -> void:
	growth_page = clampi(page, 0, 1)
	refresh_buttons()

func button_for(branch: int, level: int) -> Dictionary:
	return growth[branch * 6 + level]
