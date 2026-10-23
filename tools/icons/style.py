"""Shared icon tile style for assets/icons/<set>/<id>.png (items, spells, actions).

Glyphs are game-icons.net silhouettes (CC BY 3.0, see assets/icons/CREDITS.md), read from the
@iconify-json/game-icons npm package: `npm pack @iconify-json/game-icons && tar xzf *.tgz`, then
pass package/icons.json. Needs Pillow, numpy and cairosvg.

Look: 64x64 rounded tile, dark radial background, bronze frame, glyph filled with a light-to-dark
material gradient, embossed edges, black outline and a soft drop shadow. Drawn at 256 px, then
downsampled with Lanczos.
"""
import io
import json

import cairosvg
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 256  # working size
OUT = 64
BG = ((0x2a, 0x26, 0x22), (0x15, 0x12, 0x0f))  # centre, edge
FRAME = (0x8a, 0x6a, 0x3a)
FRAME_IN = (0x4a, 0x37, 0x20)

_icons = {}


def load(path):
	_icons.update(json.load(open(path))["icons"])


def glyph_mask(name, scale=0.78, dx=0, dy=0, flip=False, rot=0):
	"""The game-icons silhouette `name` as an L mask, `scale` of the tile, centred (+dx, dy px at 256)."""
	body = _icons[name]["body"]
	svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><g fill="#fff">%s</g></svg>' % body
	n = int(S * scale)
	im = Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(), output_width=n, output_height=n)))
	a = im.getchannel("A")
	if flip:
		a = a.transpose(Image.FLIP_LEFT_RIGHT)
	if rot:
		a = a.rotate(rot, resample=Image.BICUBIC)
	m = Image.new("L", (S, S), 0)
	m.paste(a, ((S - n) // 2 + dx, (S - n) // 2 + dy))
	return m


def _gradient(light, dark, angle=(1, 1)):
	"""RGB image lerping light (top-left) to dark (bottom-right)."""
	y, x = np.mgrid[0:S, 0:S].astype(np.float32)
	t = (x * angle[0] + y * angle[1]) / (S * (angle[0] + angle[1]))
	t = np.clip((t - 0.2) / 0.6, 0, 1)[..., None]
	c = np.array(light, np.float32) * (1 - t) + np.array(dark, np.float32) * t
	return Image.fromarray(c.astype(np.uint8), "RGB")


def _shift(m, dx, dy):
	return ImageChops.offset(m, dx, dy)


def background(bg=BG):
	y, x = np.mgrid[0:S, 0:S].astype(np.float32)
	r = np.clip(np.hypot(x - S / 2, y - S * 0.42) / (S * 0.72), 0, 1)[..., None]
	c = np.array(bg[0], np.float32) * (1 - r) + np.array(bg[1], np.float32) * r
	return Image.fromarray(c.astype(np.uint8), "RGB").convert("RGBA")


def tile(layers, bg=BG, glow=None):
	"""layers: [(mask, (light_rgb, dark_rgb))] painted in order. glow: rgb aura behind the glyph."""
	img = background(bg)
	sil = Image.new("L", (S, S), 0)
	for m, _ in layers:
		sil = ImageChops.lighter(sil, m)
	outline = sil.filter(ImageFilter.MaxFilter(11))
	if glow:
		g = outline.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(14))
		img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (S, S), glow).split(), g.point(lambda v: v * 0.9))))
	shadow = _shift(outline, 5, 7).filter(ImageFilter.GaussianBlur(6)).point(lambda v: v * 0.7)
	img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (S, S), (0, 0, 0)).split(), shadow)))
	img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (S, S), (0x0d, 0x0a, 0x08)).split(), outline)))
	for m, (light, dark) in layers:
		fill = _gradient(light, dark).convert("RGBA")
		fill.putalpha(m)
		img.alpha_composite(fill)
		# emboss: brighten edges facing the top-left light, darken the others
		hi = ImageChops.subtract(m, _shift(m, 4, 4)).filter(ImageFilter.GaussianBlur(1.5))
		lo = ImageChops.subtract(m, _shift(m, -4, -4)).filter(ImageFilter.GaussianBlur(1.5))
		img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (S, S), (255, 255, 240)).split(), hi.point(lambda v: v * 0.55))))
		img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (S, S), (0, 0, 0)).split(), lo.point(lambda v: v * 0.5))))
	frame(img)
	return img


def frame(img):
	"""Rounded bronze frame; also cuts the corners transparent."""
	r = 40
	cut = Image.new("L", (S, S), 0)
	ImageDraw.Draw(cut).rounded_rectangle((0, 0, S - 1, S - 1), r, fill=255)
	d = ImageDraw.Draw(img)
	d.rounded_rectangle((3, 3, S - 4, S - 4), r - 3, outline=FRAME, width=8)
	d.rounded_rectangle((11, 11, S - 12, S - 12), r - 11, outline=FRAME_IN, width=3)
	img.putalpha(ImageChops.multiply(img.getchannel("A"), cut))


def save(img, path):
	img.resize((OUT, OUT), Image.LANCZOS).save(path, optimize=True)
