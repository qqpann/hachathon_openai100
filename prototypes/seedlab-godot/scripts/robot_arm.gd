extends Node3D
## Geometric two-link IK is the actuator. The neural policy selects a button.
const BASE = preload("res://assets/robot_base.glb")
const LINK = preload("res://assets/arm_link.glb")
const TOOL = preload("res://assets/gripper.glb")
const LENGTH_A = 2.4
const LENGTH_B = 2.4
var tip = Vector3(.6, 3.9, 1.2)
var home = Vector3(.6, 3.9, 1.2)
var upper: Node3D
var lower: Node3D
var gripper: Node3D
var shoulder = Vector3(0, 1.66, 1.75)
var elbow = Vector3.ZERO

func _ready() -> void:
	var base = BASE.instantiate()
	add_child(base)
	base.position = Vector3(0, .8, 1.75)
	upper = LINK.instantiate()
	lower = LINK.instantiate()
	gripper = TOOL.instantiate()
	add_child(upper)
	add_child(lower)
	add_child(gripper)
	_update_pose()

func _process(_delta: float) -> void:
	_update_pose()

func _update_pose() -> void:
	var delta = tip - shoulder
	var distance = clampf(delta.length(), .15, LENGTH_A + LENGTH_B - .001)
	var direction = delta.normalized()
	var along = (LENGTH_A * LENGTH_A - LENGTH_B * LENGTH_B + distance * distance) / (2.0 * distance)
	var height = sqrt(maxf(0, LENGTH_A * LENGTH_A - along * along))
	var bend = Vector3.UP - direction * direction.dot(Vector3.UP)
	if bend.length_squared() < .001:
		bend = Vector3.BACK
	elbow = shoulder + direction * along + bend.normalized() * height
	_place_link(upper, shoulder, elbow)
	_place_link(lower, elbow, tip)
	gripper.position = tip

func _place_link(link: Node3D, from: Vector3, to: Vector3) -> void:
	var y = (to - from).normalized()
	var x = y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < .01:
		x = Vector3.RIGHT
	var z = x.cross(y).normalized()
	link.transform = Transform3D(Basis(x, y * from.distance_to(to) / 2.4, z), from)

func move_to(destination: Vector3, duration: float, arc: float = .2) -> void:
	var start = tip
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(t): tip = start.lerp(destination, t) + Vector3.UP * sin(PI * t) * arc, 0.0, 1.0, maxf(.04, duration))
	await tween.finished
	_update_pose()
