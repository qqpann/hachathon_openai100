extends RefCounted
## Real MNIST bytes. Labels select the environment's card, never policy inputs.
const SIDE = 28
const TRAIN_PER_DIGIT = 64
const TEST_PER_DIGIT = 16
static var train_bytes = PackedByteArray()
static var test_bytes = PackedByteArray()

static func image_for(digit: int, variant: int, testing: bool = false) -> Image:
	if train_bytes.is_empty():
		train_bytes = FileAccess.get_file_as_bytes("res://data/mnist/train.bin")
		test_bytes = FileAccess.get_file_as_bytes("res://data/mnist/test.bin")
	var count = TEST_PER_DIGIT if testing else TRAIN_PER_DIGIT
	assert(digit >= 0 and digit < 10 and variant >= 0 and variant < count)
	var bytes = test_bytes if testing else train_bytes
	assert(bytes.size() == count * 10 * SIDE * SIDE)
	var start = (digit * count + variant) * SIDE * SIDE
	var image = Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_L8, bytes.slice(start, start + SIDE * SIDE))
	# The physical card is black ink on white paper. The camera downsamples it.
	for y in range(SIDE):
		for x in range(SIDE):
			var paper = 1.0 - image.get_pixel(x, y).r
			image.set_pixel(x, y, Color(paper, paper, paper))
	return image
