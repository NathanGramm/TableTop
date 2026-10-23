"""Textures for the BG3-style action bar in assets/ui/ (dark leather panel, bronze frames, empty slots).

Matches the icon tiles of tools/icons/style.py (same bronze and dark radial). Needs Pillow and numpy.
Run from the repo root: python3 tools/ui/bar_art.py
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = "assets/ui/"
FRAME = (0x8a, 0x6a, 0x3a)
FRAME_IN = (0x4a, 0x37, 0x20)
GOLD = (0xc9, 0xa3, 0x5a)
rng = np.random.default_rng(7)


def noise(w, h, scale, amp):
	"""Tileable value noise: random grid blurred with wrap-around, in [-amp, amp]."""
	g = rng.random((h // scale, w // scale)).astype(np.float32)
	im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
	a = np.asarray(im, np.float32) / 255 - 0.5
	return a * 2 * amp


def leather(w, h, base=(0x1c, 0x16, 0x12)):
	"""Dark grained leather: two octaves of noise plus fine speckle."""
	n = noise(w, h, 16, 10) + noise(w, h, 4, 5) + (rng.random((h, w)) - 0.5) * 6
	c = np.clip(np.array(base, np.float32)[None, None] + n[..., None] * np.array([1.0, 0.85, 0.7]), 0, 255)
	return Image.fromarray(c.astype(np.uint8), "RGB").convert("RGBA")


def bar():
	"""Panel: leather with an ornate top trim (shadow, bronze band, bright gold line). Tiles sideways."""
	img = leather(128, 128)
	d = ImageDraw.Draw(img)
	d.rectangle((0, 0, 127, 1), fill=(0x0b, 0x08, 0x06))
	for y, col in enumerate([(0x5a, 0x43, 0x24), FRAME, (0xa8, 0x84, 0x4a), FRAME, (0x5a, 0x43, 0x24)]):
		d.line((0, 2 + y, 127, 2 + y), fill=col)
	d.line((0, 7, 127, 7), fill=GOLD)
	d.line((0, 8, 127, 8), fill=(0x0b, 0x08, 0x06))
	shade = Image.new("RGBA", (128, 128))
	sd = ImageDraw.Draw(shade)
	for y in range(9, 21):
		sd.line((0, y, 127, y), fill=(0, 0, 0, int(110 * (1 - (y - 9) / 12))))
	img.alpha_composite(shade)
	img.save(OUT + "bar.png", optimize=True)


def framed(size, radius, inner, path, border=FRAME, glow=False):
	"""Rounded bronze frame (as on the icon tiles) around a dark radial or leather centre; 9-slice friendly."""
	s = size * 4
	y, x = np.mgrid[0:s, 0:s].astype(np.float32)
	r = np.clip(np.hypot(x - s / 2, y - s * 0.42) / (s * 0.72), 0, 1)[..., None]
	c = np.array(inner[0], np.float32) * (1 - r) + np.array(inner[1], np.float32) * r
	img = Image.fromarray(c.astype(np.uint8), "RGB").convert("RGBA")
	d = ImageDraw.Draw(img)
	R = radius * 4
	d.rounded_rectangle((3, 3, s - 4, s - 4), R - 3, outline=border, width=8)
	d.rounded_rectangle((11, 11, s - 12, s - 12), R - 11, outline=FRAME_IN, width=3)
	if glow:
		d.rounded_rectangle((1, 1, s - 2, s - 2), R - 1, outline=GOLD, width=3)
	cut = Image.new("L", (s, s), 0)
	ImageDraw.Draw(cut).rounded_rectangle((0, 0, s - 1, s - 1), R, fill=255)
	a = np.asarray(img.getchannel("A"), np.float32) * np.asarray(cut, np.float32) / 255
	img.putalpha(Image.fromarray(a.astype(np.uint8)))
	img.resize((size, size), Image.LANCZOS).save(OUT + path, optimize=True)


def ring():
	"""Hover/selected ring drawn over an icon: a gold rounded outline, transparent inside."""
	s = 256
	img = Image.new("RGBA", (s, s))
	d = ImageDraw.Draw(img)
	d.rounded_rectangle((2, 2, s - 3, s - 3), 38, outline=(0xf2, 0xd2, 0x8a, 255), width=10)
	img = img.filter(ImageFilter.GaussianBlur(1.2))
	img.resize((64, 64), Image.LANCZOS).save(OUT + "slot_ring.png", optimize=True)


if __name__ == "__main__":
	import os
	os.makedirs(OUT, exist_ok=True)
	bar()
	framed(64, 10, ((0x1e, 0x1a, 0x17), (0x0e, 0x0c, 0x0a)), "slot.png")  # empty slot
	framed(64, 10, ((0x34, 0x2a, 0x20), (0x1a, 0x14, 0x10)), "button.png")  # text buttons
	framed(64, 10, ((0x48, 0x38, 0x26), (0x24, 0x1b, 0x13)), "button_hover.png", border=(0xb0, 0x8a, 0x4c), glow=True)
	framed(64, 10, ((0x5a, 0x40, 0x22), (0x2c, 0x1e, 0x12)), "button_pressed.png", border=GOLD)
	ring()
