"""gap.py <screenshot.png> <lane_y> <playhead_y>

Prints "x" for the middle of the first empty stretch of the caption lane (at
least 40 px of bare lane background) to the right of the playhead, or of the
first one anywhere when the playhead is off screen. Exits 1 when none.
"""

import subprocess
import sys

image, lane_y, head_y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
W = 1600


def row(y):
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", image, "-vf", f"crop={W}:1:0:{y}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True,
        check=True,
    ).stdout
    return [tuple(raw[i * 3 : i * 3 + 3]) for i in range(W)]


BACKGROUNDS = [(244, 244, 244), (48, 48, 50)]


def is_lane(p):
    return any(all(abs(a - b) <= 4 for a, b in zip(p, bg)) for bg in BACKGROUNDS)


head = [x for x, (r, g, b) in enumerate(row(head_y)) if r > 200 and g < 90 and b < 90]
after = (sum(head) / len(head) + 4) if head else 130
lane = row(lane_y)
runs, start = [], None
for x in range(130, W - 40):
    if is_lane(lane[x]):
        start = x if start is None else start
    elif start is not None:
        runs.append((start, x))
        start = None
if start is not None:
    runs.append((start, W - 40))
runs = [r for r in runs if r[1] - r[0] >= 40]
for s, e in runs:
    if s >= after:
        print(round((s + e) / 2))
        sys.exit(0)
if runs:
    print(round((runs[0][0] + runs[0][1]) / 2))
    sys.exit(0)
sys.exit(1)
