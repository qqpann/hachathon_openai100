# MNIST subset

Source: [CVDF mirror of MNIST](https://github.com/cvdfoundation/mnist).
Authors: Yann LeCun, Corinna Cortes, Christopher J. C. Burges.
Original description: <http://yann.lecun.com/exdb/mnist/>.

`train.bin` contains the first 64 original training examples of each digit (640 images).
`test.bin` contains the first 16 original test examples of each digit (160 images).
The original training/test split is preserved. Each image is 28 × 28 unsigned bytes,
white ink on black, in row-major order. Images are grouped by digit 0–9.

`manifest.json` records original IDX indices, download URLs and SHA-256 checksums.
`tools/import_mnist.py` regenerates the same files from the CVDF mirror.
No image download or OpenAI call happens while playing the digit task.

The game displays black ink on a white card, enlarged to 512 × 512. This does not
add information to the 28 × 28 source. Godot renders the card through a 512 × 512
camera, then reduces that rendered image to the neural network's 12 × 12 input.
