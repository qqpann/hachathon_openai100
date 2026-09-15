extends RefCounted
## Online MNIST classifier. Only camera pixels enter predict(); labels arrive after a press.
const SIDE = 12
const PIXELS = SIDE * SIDE
const INPUTS = PIXELS
const OUTPUTS = 10 # Softmax probabilities for handwritten digits 0–9.
var hidden_count = 8
var wi: Array = []
var bi: Array = []
var wo: Array = []
var bo: Array = []
var activity: Array = []
var steps = 0
var last_weight_change = 0.0
var rng = RandomNumberGenerator.new()

func _init(width: int = 8, seed_value: int = 71) -> void:
	rng.seed = seed_value
	hidden_count = width
	for h in range(width):
		wi.append(_random_row(INPUTS, 0.22))
		bi.append(0.0)
	for o in range(OUTPUTS):
		wo.append(_random_row(width, 0.20))
		bo.append(0.0)
	activity.resize(width)
	activity.fill(0.0)

func _random_row(count: int, amount: float) -> Array:
	var row: Array = []
	for i in range(count):
		row.append(rng.randf_range(-amount, amount))
	return row

static func pixels_from_image(source: Image) -> Array:
	if source == null or source.is_empty():
		return []
	var small = source.duplicate() as Image
	small.resize(SIDE, SIDE, Image.INTERPOLATE_LANCZOS)
	var pixels: Array = []
	for y in range(SIDE):
		for x in range(SIDE):
			var c = small.get_pixel(x, y)
			# Dark ink on white paper, from the rendered camera frame only.
			pixels.append(clampf(1.0 - (c.r * .2126 + c.g * .7152 + c.b * .0722), 0.0, 1.0))
	return pixels

func predict(x: Array) -> Array:
	assert(x.size() == INPUTS)
	for h in range(hidden_count):
		var z: float = bi[h]
		for i in range(INPUTS):
			z += float(wi[h][i]) * float(x[i])
		activity[h] = tanh(z)
	var out: Array = []
	for o in range(OUTPUTS):
		var z: float = bo[o]
		for h in range(hidden_count):
			z += float(wo[o][h]) * float(activity[h])
		out.append(z)
	var largest: float = out.max()
	var total = 0.0
	for o in range(OUTPUTS):
		out[o] = exp(out[o] - largest)
		total += out[o]
	for o in range(OUTPUTS): out[o] /= total
	return out

func train(x: Array, label: int, rate: float = 0.06) -> void:
	var prediction = predict(x)
	var errors: Array = []
	for o in range(OUTPUTS): errors.append(prediction[o] - (1.0 if o == label else 0.0))
	last_weight_change = 0.0
	# Compute hidden gradients before changing any output weights.
	var gradients: Array = []
	for h in range(hidden_count):
		var weighted_error = 0.0
		for o in range(OUTPUTS): weighted_error += errors[o] * wo[o][h]
		gradients.append(weighted_error * (1.0 - activity[h] * activity[h]))
	for o in range(OUTPUTS):
		for h in range(hidden_count):
			wo[o][h] -= rate * errors[o] * activity[h]
			last_weight_change += absf(rate * errors[o] * activity[h])
		bo[o] -= rate * errors[o]
		last_weight_change += absf(rate * errors[o])
	for h in range(hidden_count):
		var hidden_gradient: float = gradients[h]
		bi[h] -= rate * hidden_gradient
		last_weight_change += absf(rate * hidden_gradient)
		for i in range(INPUTS):
			last_weight_change += absf(rate * hidden_gradient * float(x[i]))
			wi[h][i] -= rate * hidden_gradient * float(x[i])
	steps += 1

func grow(count: int = 4) -> void:
	for h in range(count):
		wi.append(_random_row(INPUTS, .22))
		bi.append(0.0)
		activity.append(0.0)
		for o in range(OUTPUTS):
			wo[o].append(0.0)
	hidden_count += count

func copy_brain():
	var model = get_script().new(hidden_count)
	model.restore(snapshot())
	return model

func snapshot() -> Dictionary:
	return {"hidden": hidden_count, "wi": wi.duplicate(true), "bi": bi.duplicate(),
		"wo": wo.duplicate(true), "bo": bo.duplicate(), "steps": steps}

func restore(data: Dictionary) -> bool:
	var width = int(data.get("hidden", 0))
	if width < 8 or width > 32 or not _matrix_ok(data.get("wi"), width, INPUTS) or not _matrix_ok(data.get("wo"), OUTPUTS, width):
		return false
	if not _row_ok(data.get("bi"), width) or not _row_ok(data.get("bo"), OUTPUTS):
		return false
	hidden_count = width
	wi = data.wi.duplicate(true)
	bi = data.bi.duplicate()
	wo = data.wo.slice(0, OUTPUTS).duplicate(true)
	bo = data.bo.slice(0, OUTPUTS).duplicate()
	steps = maxi(0, int(data.get("steps", 0)))
	activity.resize(width)
	activity.fill(0.0)
	return true

static func _row_ok(value, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return false
	return true

static func _matrix_ok(value, rows: int, columns: int) -> bool:
	if not value is Array or value.size() != rows:
		return false
	for row in value:
		if not _row_ok(row, columns):
			return false
	return true
