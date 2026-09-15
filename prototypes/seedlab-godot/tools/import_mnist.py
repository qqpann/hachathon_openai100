"""Bundle a deterministic, balanced MNIST subset; no runtime download needed."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import gzip
import hashlib
import json
import struct
import urllib.request

BASE = "https://storage.googleapis.com/cvdf-datasets/mnist/"
OUT = Path(__file__).resolve().parents[1] / "data" / "mnist"
FILES = ["train-images-idx3-ubyte.gz", "train-labels-idx1-ubyte.gz",
         "t10k-images-idx3-ubyte.gz", "t10k-labels-idx1-ubyte.gz"]


def download(name):
    with urllib.request.urlopen(BASE + name, timeout=45) as response:
        data = response.read()
    return name, data


def main():
    with ThreadPoolExecutor(max_workers=4) as pool:
        sources = dict(pool.map(download, FILES))
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {"dataset": "MNIST", "authors": "Yann LeCun, Corinna Cortes, Christopher J. C. Burges",
                "source": "https://github.com/cvdfoundation/mnist", "size": [28, 28],
                "selection": "First 64 training / 16 testing examples of each digit in original IDX order",
                "sources": {name: {"url": BASE + name, "sha256": hashlib.sha256(data).hexdigest()}
                            for name, data in sources.items()}, "splits": {}}
    for split, prefix, per_digit in [("train", "train", 64), ("test", "t10k", 16)]:
        images = gzip.decompress(sources[prefix + "-images-idx3-ubyte.gz"])
        labels = gzip.decompress(sources[prefix + "-labels-idx1-ubyte.gz"])
        magic, count, rows, columns = struct.unpack(">IIII", images[:16])
        label_magic, label_count = struct.unpack(">II", labels[:8])
        assert magic == 2051 and label_magic == 2049 and count == label_count
        assert rows == columns == 28 and len(images) == 16 + count * 784 and len(labels) == 8 + count
        indices = [[] for _ in range(10)]
        for index, digit in enumerate(labels[8:]):
            if len(indices[digit]) < per_digit:
                indices[digit].append(index)
        assert all(len(group) == per_digit for group in indices)
        packed = b"".join(images[16 + index * 784:16 + (index + 1) * 784]
                          for group in indices for index in group)
        (OUT / (split + ".bin")).write_bytes(packed)
        manifest["splits"][split] = {"count": per_digit * 10, "per_digit": per_digit,
                                     "original_indices_by_digit": indices,
                                     "sha256": hashlib.sha256(packed).hexdigest()}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("MNIST: 640 training and 160 separate test images bundled (28 × 28).")


if __name__ == "__main__":
    main()
