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
	"""One texture for the whole bar, stretched across it: leather darkening toward the bottom and the
	ends, a bronze and gold top trim with studs, ornate end caps and an embossed inner border.
	The trim and caps sit inside the 9-slice margins (top 28, sides 64) so they keep their shape."""
	W, H = 1920, 240
	img = leather(W, H)
	y, x = np.mgrid[0:H, 0:W].astype(np.float32)
	shade = 0.55 + 0.45 * (1 - y / H) ** 0.6 * np.clip(np.minimum(x, W - x) / 260, 0.35, 1) ** 0.5
	px = np.asarray(img, np.float32)
	px[..., :3] *= shade[..., None]
	img = Image.fromarray(px.astype(np.uint8), "RGBA")
	d = ImageDraw.Draw(img)
	# embossed inner border: dark groove with a faint bronze highlight under it
	d.rounded_rectangle((14, 30, W - 15, H - 10), 10, outline=(0x0a, 0x07, 0x05), width=3)
	d.rounded_rectangle((16, 32, W - 17, H - 12), 9, outline=(0x4a, 0x37, 0x20), width=1)
	# top trim: shadow, bronze band with a bright gold line, studs
	d.rectangle((0, 0, W, 2), fill=(0x0b, 0x08, 0x06))
	band = [(0x5a, 0x43, 0x24), FRAME, (0xa8, 0x84, 0x4a), (0xc4, 0x9e, 0x5c), (0xa8, 0x84, 0x4a), FRAME, FRAME, (0x5a, 0x43, 0x24)]
	for i, col in enumerate(band):
		d.line((0, 3 + i, W, 3 + i), fill=col)
	d.line((0, 11, W, 11), fill=GOLD)
	d.line((0, 12, W, 12), fill=(0x0b, 0x08, 0x06))
	# soft shadow under the trim
	soft = leather(W, 13).resize((W, 13))
	sh = np.asarray(soft, np.float32)
	sh[..., :3] *= np.linspace(0.25, 0.9, 13)[:, None, None]
	img.paste(Image.fromarray(sh.astype(np.uint8), "RGBA"), (0, 13))
	d = ImageDraw.Draw(img)
	for sx in range(96, W - 64, 128):
		d.ellipse((sx - 3, 4, sx + 3, 10), fill=(0xe8, 0xc7, 0x7a), outline=(0x3a, 0x2a, 0x16))
	# end caps: a bronze scroll over each top corner
	for flip in (False, True):
		cap = Image.new("RGBA", (64, 60))
		cd = ImageDraw.Draw(cap)
		cd.polygon([(0, 0), (60, 0), (46, 10), (18, 14), (8, 26), (4, 58), (0, 58)], fill=FRAME, outline=(0x3a, 0x2a, 0x16))
		cd.line([(56, 2), (44, 8), (16, 12), (6, 24), (2, 56)], fill=GOLD, width=2)
		cd.ellipse((10, 16, 22, 28), fill=(0x5a, 0x43, 0x24), outline=GOLD, width=2)
		if flip:
			cap = cap.transpose(Image.FLIP_LEFT_RIGHT)
		img.alpha_composite(cap, (W - 64 if flip else 0, 0))
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
