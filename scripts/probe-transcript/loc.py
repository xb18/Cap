"""loc.py <screenshot.png> <text> [min_x] [max_x] [min_y] [max_y]

Prints the centre "x y" of the first OCR token equal to <text> (ignoring
case and surrounding punctuation unless <text> has some) inside the box,
in screenshot pixels. Exits 1 when it is not found.
"""

import os
import subprocess
import sys
import tempfile

image, wanted = sys.argv[1], sys.argv[2]
box = [float(v) for v in sys.argv[3:7]]
box += [None] * (4 - len(box))
min_x, max_x, min_y, max_y = box
exact = any(not c.isalnum() for c in wanted)
SCALE = 3


def norm(text):
    return text if exact else text.strip(".,:;!?()").lower()


def tokens(path, invert):
    with tempfile.TemporaryDirectory() as tmp:
        scaled = os.path.join(tmp, "scaled.png")
        vf = f"scale=iw*{SCALE}:ih*{SCALE}:flags=lanczos,format=gray"
        if invert:
            vf += ",negate"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-vf", vf, scaled], check=True)
        tsv = subprocess.run(
            ["tesseract", scaled, "stdout", "--psm", "11", "tsv"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    for line in tsv.splitlines()[1:]:
        cols = line.split("\t")
        if len(cols) < 12 or not cols[11].strip():
            continue
        left, top, width, height = (int(v) / SCALE for v in cols[6:10])
        yield cols[11].strip(), left + width / 2, top + height / 2, left


target = wanted if exact else wanted.lower()
for invert in (False, True):
    for text, x, y, left in tokens(image, invert):
        if norm(text) != target:
            continue
        if min_x is not None and max_x is not None and not (min_x <= x <= max_x):
            continue
        if min_y is not None and max_y is not None and not (min_y <= y <= max_y):
            continue
        print(f"{round(x)} {round(y)} {round(left)}")
        sys.exit(0)
sys.exit(1)
