"""Textures for the BG3-style action bar in assets/ui/ (smoky dark gray panel, bronze frames, empty slots).

Matches the icon tiles of tools/icons/style.py (same bronze and dark radial). Needs Pillow and numpy.
Run from the repo root: python3 tools/ui/bar_art.py
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = "assets/ui/"
FRAME = (0x8a, 0x6a, 0x3a)
FRAME_IN = (0x4a, 0x37, 0x20)
GOLD = (0xc9, 0xa3, 0x5a)
rng = np.random.default_rng(7)  # fixed seed: rerunning gives the same art


def vnoise(w, h, cx, cy):
	"""Value noise with cells cx by cy px (bicubic over a random grid)."""
	g = rng.random((h // cy + 3, w // cx + 3)).astype(np.float32)
	im = Image.fromarray(g, "F").resize(((w // cx + 3) * cx, (h // cy + 3) * cy), Image.BICUBIC)
	return np.asarray(im, np.float32)[:h, :w]


def fbm(w, h, cx, cy, octaves=6, gain=0.5):
	out = np.zeros((h, w), np.float32)
	amp, tot = 1.0, 0.0
	for o in range(octaves):
		out += amp * vnoise(w, h, max(1, cx >> o), max(1, cy >> o))
		tot += amp
		amp *= gain
	return out / tot


def sample(f, x, y):
	"""Bilinear lookup of field f at float coords."""
	h, w = f.shape
	x = np.clip(x, 0, w - 1.001)
	y = np.clip(y, 0, h - 1.001)
	x0, y0 = x.astype(np.int32), y.astype(np.int32)
	fx, fy = x - x0, y - y0
	return (f[y0, x0] * (1 - fx) + f[y0, x0 + 1] * fx) * (1 - fy) + (f[y0 + 1, x0] * (1 - fx) + f[y0 + 1, x0 + 1] * fx) * fy


def smoke(W, H):
	"""Dark gray with a low fog bank and soft smoke in an oval U: along the bottom and up both sides,
	clear in the middle. Domain-warped fbm (f(p + k*r(p + k*q(p)))) with taller-than-wide cells."""
	P = 400  # fields run past the image so warped lookups never clamp at its edges
	FW, FH = W + 2 * P, H + 2 * P
	y, x = np.mgrid[0:H, 0:W].astype(np.float32)
	crop = lambda f: f[P:P + H, P:P + W]
	q1, q2 = crop(fbm(FW, FH, 320, 200)), crop(fbm(FW, FH, 320, 200))
	r1 = sample(fbm(FW, FH, 256, 160), x + P + 180 * q1, y + P + 120 * q2)
	r2 = sample(fbm(FW, FH, 256, 160), x + P + 180 * q2, y + P + 120 * q1)
	f = sample(fbm(FW, FH, 256, 160), x + P + 260 * r1 - 130, y + P + 160 * r2 - 80)
	f = 0.75 * f + 0.25 * sample(fbm(FW, FH, 64, 48, 5), x + P + 60 * r1, y + P + 40 * r2)
	ex, ey = (x - W / 2) / (W * 0.45), (y + H * 0.1) / (H * 0.85)
	d = np.sqrt(ex * ex + ey * ey) + (r1 - 0.5) * 0.35  # noise breaks up the U's edge
	mask = np.clip((d - 0.7) / 0.5, 0, 1) ** 1.2
	dens = np.clip((f - 0.36) * 2.0, 0, 1) ** 1.3 * mask
	lit = np.clip(dens - np.roll(dens, 6, axis=0), 0, 1)  # upper edges of the puffs catch a little light
	# a low fog bank: rises from the bottom, thicker toward the sides, its top rolling with the noise
	t = y / H + (r2 - 0.5) * 0.25 + (1 - np.clip(np.abs(x - W / 2) / (W * 0.5), 0, 1)) * -0.08
	fog = np.clip((t - 0.45) / 0.55, 0, 1) ** 1.5 * (0.75 + 0.5 * (f - 0.5))
	v = 0.11 + fog * 0.2 + dens * 0.2 + lit * 0.12  # dark gray base, soft contrast
	rgb = np.clip(v[..., None] * np.array([0.96, 0.96, 1.0], np.float32) * 255, 0, 255)
	img = Image.fromarray(rgb.astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(1.2))
	return img.convert("RGBA")


def bar():
	"""The whole bar's background, stretched across it: fog and smoke on dark gray under a bronze and gold top trim.
	The trim sits in the top 9-slice margin (30 px); the end caps are a separate overlay (bar_cap.png)
	so they keep their shape however wide the bar is. Studs are drawn wide since the bar is usually
	narrower than 3840 px and squeezes them."""
	W, H = 3840, 400
	img = smoke(W, H)
	d = ImageDraw.Draw(img)
	d.rectangle((0, 0, W, 2), fill=(0x0b, 0x08, 0x06))
	band = [(0x5a, 0x43, 0x24), FRAME, (0xa8, 0x84, 0x4a), (0xc4, 0x9e, 0x5c), (0xa8, 0x84, 0x4a), FRAME, FRAME, (0x5a, 0x43, 0x24)]
	for i, col in enumerate(band):
		d.line((0, 3 + i, W, 3 + i), fill=col)
	d.line((0, 11, W, 11), fill=GOLD)
	d.line((0, 12, W, 12), fill=(0x0b, 0x08, 0x06))
	shade = Image.new("RGBA", (W, H))  # soft shadow under the trim, blended (drawing alpha would punch holes)
	sd = ImageDraw.Draw(shade)
	for i in range(14):
		sd.line((0, 13 + i, W, 13 + i), fill=(0, 0, 0, int(200 * (1 - i / 14))))
	img.alpha_composite(shade)
	d = ImageDraw.Draw(img)
	for sx in range(160, W - 120, 256):
		d.ellipse((sx - 7, 4, sx + 7, 10), fill=(0xe8, 0xc7, 0x7a), outline=(0x3a, 0x2a, 0x16))
	img.save(OUT + "bar.png", optimize=True)
	cap = Image.new("RGBA", (64, 60))
	cd = ImageDraw.Draw(cap)
	cd.polygon([(0, 0), (60, 0), (46, 10), (18, 14), (8, 26), (4, 58), (0, 58)], fill=FRAME, outline=(0x3a, 0x2a, 0x16))
	cd.line([(56, 2), (44, 8), (16, 12), (6, 24), (2, 56)], fill=GOLD, width=2)
	cd.ellipse((10, 16, 22, 28), fill=(0x5a, 0x43, 0x24), outline=GOLD, width=2)
	cap.save(OUT + "bar_cap.png", optimize=True)


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
