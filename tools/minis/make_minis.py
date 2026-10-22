"""Generates the low-poly tabletop minifigures in assets/minis/ (one .glb per figure).

    python3 tools/minis/make_minis.py [--previews DIR]

Every figure stands on a round base (radius 0.42 = one 5-ft square) facing +Z. The base rim
uses a material named "team", which the board repaints with the token's team colour. Each model
is tuned to land near 30,000 triangles (25,000-35,000), and gets shared procedural
textures (assets/minis/textures/) and baked ambient occlusion in its vertex colours.
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import meshkit as mk
import surface
from meshkit import A, R, S, T, chain, box, cyl, extrude, lathe, sphere, torus, tube

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "minis")
BASE_H = 0.085
TRI_MIN, TRI_MAX, TRI_TARGET = 25000, 35000, 30000
HEAD = 0.82  # head size relative to the sculpted proportions: about 6.5 heads tall, like real minis
LOWPOLY = 1.4  # segment multiplier for the hard-surface parts


def mat(color, metal=0.0, rough=0.7, **kw):
    c = tuple(int(color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    if "emit" not in kw:  # muted, painted-mini colours rather than toy-bright ones
        grey = sum(c) / 3
        c = tuple(grey + (x - grey) * 0.65 for x in c)
    return dict(color=tuple(x ** 2.2 for x in c), metal=metal, rough=rough, **kw)


COMMON = {
    "base": mat("#2b2b2e", rough=0.5),
    "team": mat("#8a8a8a", rough=0.4, metal=0.3),
    "eye": mat("#2a1d14", rough=0.2),
    "eye_white": mat("#e8e2d8", rough=0.3),
    "steel": mat("#b9bec6", metal=0.85, rough=0.3),
    "iron": mat("#6c6f75", metal=0.7, rough=0.5),
    "gold": mat("#d9a838", metal=0.9, rough=0.3),
    "leather": mat("#6b4428", rough=0.8),
    "dark_leather": mat("#3b2a1e", rough=0.8),
    "wood": mat("#7a5230", rough=0.85),
    "skin": mat("#c98e6a"),
    "skin_dark": mat("#8d5a3c"),
    "hair_brown": mat("#4a3020", rough=0.9),
    "hair_white": mat("#e8e4dc", rough=0.9),
    "cloth_white": mat("#e9e4d6"),
    "rope": mat("#b89a64", rough=0.9),
    "lips": mat("#b5675f", rough=0.5),
    "hair_black": mat("#1c1a18", rough=0.9),
    "bone": mat("#e6dcc4", rough=0.6),
}


# ---------------- building blocks ----------------

def base(m):
    """Plain bevelled round base with a team-coloured rim."""
    m.add("base", lathe([(0.0, 0.0), (0.41, 0.0), (0.42, 0.008), (0.42, 0.064), (0.405, 0.078), (0.39, BASE_H), (0.0, BASE_H)], 48))
    m.add("team", lathe([(0.4215, 0.018), (0.428, 0.022), (0.428, 0.05), (0.4215, 0.054)], 48))


def head_part(fn):
    """Decorator for helpers that build on the head: everything they add is shrunk with it."""
    def wrapped(m, fig, *a, **kw):
        prev = m.post
        fig.head_scope(whole=True)
        fn(m, fig, *a, **kw)
        m.post = prev
    return wrapped


def limb(m, material, pts, r0, r1, joints=True):
    rs = np.linspace(r0, r1, len(pts))
    for p0, p1, a, b in zip(pts, pts[1:], rs, rs[1:]):
        m.blob(material, "cone", a=p0, b=p1, r1=a, r2=b, blend=0.006 if joints else 0.0)
    if joints:
        for p, r in zip(pts[1:-1], rs[1:-1]):
            m.blob(material, "ell", T(*p), r=(r * 1.25,) * 3, blend=0.008)


def bend(p0, p1, out, drop=0.03):
    """Elbow/knee point between p0 and p1, pushed sideways by `out`."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    return (p0 + p1) / 2 + np.asarray(out, float) + (0, -drop, 0)


class Fig:
    """A humanoid built in its own units (feet at y=0, ~0.9 tall at scale 1), placed on the base."""

    def __init__(self, m, s=1.0, bulk=1.0, hunch=0.0, female=False):
        self.m, self.s, self.bulk, self.hunch, self.female = m, s, bulk, hunch, female
        if female:
            self.bulk = bulk = bulk * 0.88
        m.push(chain(T(0, BASE_H, 0), S(s)))
        self.shoulder_y = 0.655
        self.sh = {"R": np.array((-0.145 * bulk, self.shoulder_y, 0.0)), "L": np.array((0.145 * bulk, self.shoulder_y, 0.0))}
        self.head = np.array((0.0, 0.80, 0.005))

    def done(self):
        self.m.post = None
        self.m.pop()

    def head_scope(self, whole=False):
        """Shrink what is built next around the head by HEAD: parts centred above the neck, or
        every part when `whole` (headwear, hair and beards)."""
        c = (self.m._stack[-1] @ np.r_[self.head, 1.0])[:3]
        self.m.post = (chain(T(*c), S(HEAD), T(*-c)), -1e9 if whole else c[1] - 0.07 * self.s)

    def body_scope(self):
        self.m.post = None

    def upper(self):
        """Enter the (possibly hunched) upper-body frame."""
        self.m.push(chain(T(0, 0.42, 0), R(self.hunch, 0, 0), T(0, -0.42, 0)))

    def legs(self, pants, boots, apart=0.068, stance=0.0, boot_top=0.17):
        self.body_scope()
        m, b = self.m, self.bulk
        for sx, st in ((-1, stance), (1, -stance)):
            x = sx * apart
            hip, ankle = np.array((x, 0.43, 0)), np.array((x * 1.15, 0.055, st))
            knee = bend(hip, ankle, (sx * 0.004, 0, 0.02 + abs(st) * 0.2), 0)
            cut = (boot_top - 0.02, 1.0)
            m.blob(pants, "cone", a=hip, b=knee, r1=0.058 * b, r2=0.04, blend=0.02, clip=cut)
            m.blob(pants, "ell", T(*(hip + (knee - hip) * 0.4 + (0, 0, 0.012))), r=(0.05 * b, 0.09, 0.05), blend=0.03, clip=cut)
            m.blob(pants, "cone", a=knee, b=ankle, r1=0.04, r2=0.027, blend=0.015, clip=cut)
            m.blob(pants, "ell", T(*(knee + (ankle - knee) * 0.3 + (0, 0, -0.012))), r=(0.036, 0.065, 0.036), blend=0.02, clip=cut)
            foot = A(np.array((x * 1.15, 0.026, st + 0.03)), (0, 0, 1), (0, -1, 0))
            m.blob(boots, "cone", a=knee + (ankle - knee) * 0.2, b=ankle, r1=0.042, r2=0.031, offset=0.004, blend=0.015, clip=(-1, boot_top))
            m.blob(boots, "ell", foot, r=(0.034, 0.068, 0.03), blend=0.025, clip=(0.0, 1.0))
            if boot_top > 0.12:
                cuff = knee + (ankle - knee) * max(0.0, (knee[1] - boot_top) / (knee[1] - ankle[1]))
                m.add(boots, torus(0.043, 0.009, 14, 5), A(cuff, knee - ankle))
        m.blob(pants, "ell", T(0, 0.43, -0.005), r=((0.128 if self.female else 0.118) * b, 0.075, 0.082 * b), blend=0.03)

    def robe(self, material, r=0.19, top=0.47, boots="dark_leather", hem=None):
        self.body_scope()
        m = self.m
        prof = [(0.0, 0.0), (r, 0.0), (r * 0.94, 0.08), (r * 0.76, 0.25), (0.115 * self.bulk, top), (0.0, top + 0.01)]
        m.add(material, lathe(prof, 40), S(1, 1, 0.85), deform=folds(0.06, 11, BASE_H + top * self.s))
        if hem:
            m.add(hem, lathe([(r * 1.012, 0.0), (r * 1.017, 0.0), (r * 0.99, 0.04), (r * 0.98, 0.04)], 40), S(1, 1, 0.85), deform=folds(0.06, 11, BASE_H + top * self.s))
        for sx in (-1, 1):
            m.blob(boots, "ell", T(sx * 0.06, 0.02, r * 0.8), r=(0.035, 0.024, 0.06))

    def torso(self, material, belt=None, chest=0.13, collar=None):
        self.body_scope()
        m, b = self.m, self.bulk
        c = chest / 0.13
        fem = self.female
        m.blob(material, "ell", T(0, 0.6, 0), r=((0.105 if fem else 0.122) * b * c, 0.085, 0.07 * b), blend=0.0)
        for sx in (-1, 1):
            if fem:
                m.blob(material, "ell", T(sx * 0.042, 0.59, 0.05), r=(0.04, 0.038, 0.034), blend=0.018)
            else:
                m.blob(material, "ell", T(sx * 0.05 * b, 0.6, 0.048 * b), r=(0.052 * b, 0.036, 0.03), blend=0.02)
            m.blob(material, "cone", a=(sx * 0.03, 0.695, -0.012), b=(sx * (0.11 if fem else 0.125) * b, 0.665, -0.004), r1=0.026 if fem else 0.03, r2=0.03 if fem else 0.034, blend=0.03)
            m.blob(material, "ell", T(sx * 0.06 * b, 0.585, -0.045 * b), r=(0.05 * b, 0.07, 0.03), blend=0.03)
        m.blob(material, "ell", T(0, 0.495, 0.006), r=((0.08 if fem else 0.097) * b, 0.095, 0.062 * b), blend=0.045)
        m.blob(material, "ell", T(0, 0.43, -0.004), r=((0.122 if fem else 0.108) * b, 0.065, 0.078 * b), blend=0.035)
        if belt:
            m.add(belt, lathe([(0.104, 0.425), (0.11, 0.43), (0.11, 0.468), (0.104, 0.473)], 32), S(b, 1, 0.76 * b))
            m.add("gold", box(0.035, 0.03, 0.01), T(0, 0.449, 0.085 * b))
            for sx in (-1, 1):
                M = chain(T(sx * 0.085 * b, 0.43, 0.055 * b), R(0, sx * 0.9, 0))
                m.add("leather", box(0.045, 0.05, 0.026), M)
                m.add("leather", box(0.048, 0.022, 0.03), chain(M, T(0, 0.018, 0.002), R(0.2, 0, 0)))
                m.add("gold", sphere(0.005, 7, 5), chain(M, T(0, 0.006, 0.017)))
        if collar:
            m.add(collar, torus(0.06, 0.02, 20, 8), T(0, 0.705, 0))

    def neck_head(self, skin, eyes=True, r=0.085, lips="lips"):
        """Sculpted head: cranium, jaw, cheekbones, brow, nose, lips and ears."""
        self.head_scope()
        m, h, k = self.m, self.head, r / 0.085
        m.blob(skin, "cone", a=(0, 0.655, -0.004), b=(0, 0.76, -0.01), r1=0.038, r2=0.034, blend=0.02)
        m.push(chain(T(*h), S(k)))
        m.blob(skin, "ell", T(0, 0.012, -0.01), r=(0.074, 0.084, 0.086))
        fem = self.female
        m.blob(skin, "ell", T(0, -0.032, 0.022), r=(0.05 if fem else 0.058, 0.054, 0.056), blend=0.025)
        m.blob(skin, "ell", T(0, -0.066, 0.048), r=(0.019 if fem else 0.026, 0.018, 0.018), blend=0.016)
        for sx in (-1, 1):
            m.blob(skin, "ell", T(sx * 0.04, -0.008, 0.055), r=(0.026, 0.018, 0.02), blend=0.014)
            m.blob(skin, "ell", R(0, sx * 0.25, 0) @ T(sx * 0.074, -0.006, -0.004), r=(0.01, 0.026, 0.017), blend=0.008)
        m.blob(skin, "ell", T(0, 0.02, 0.066), r=(0.05 if fem else 0.058, 0.008 if fem else 0.012, 0.016 if fem else 0.02), blend=0.012)
        m.blob(skin, "cone", a=(0, 0.008, 0.08), b=(0, -0.024, 0.093), r1=0.006 if fem else 0.007, r2=0.009 if fem else 0.012, blend=0.008)
        m.blob(lips if fem and lips else skin, "ell", T(0, -0.046, 0.073), r=(0.018, 0.009 if fem else 0.008, 0.011), blend=0.005)
        if eyes:
            for sx in (-1, 1):
                m.blob(skin, "ell", T(sx * 0.03, 0.002, 0.08), r=(0.019, 0.012, 0.016), sub=True, blend=0.006)
                m.add("eye_white", sphere(0.0108, 12, 8), T(sx * 0.03, 0.001, 0.068))
                m.add("eye", sphere(0.0055, 8, 6), T(sx * 0.03, 0.001, 0.0765))
        m.blob(skin, "box", T(0, -0.05, 0.083), h=(0.016, 0.0018, 0.008), sub=True, blend=0.002)
        m.pop()

    def arm(self, side, hand, sleeve, skin, elbow=None, r0=0.042, fist=0.037, pad=None):
        self.body_scope()
        m = self.m
        sh = self.sh[side]
        sx = -1 if side == "R" else 1
        hand = np.asarray(hand, float)
        el = bend(sh, hand, (sx * 0.05, 0, -0.03)) if elbow is None else np.asarray(elbow, float)
        fore = (hand - el) / np.linalg.norm(hand - el)
        wrist = hand - fore * 0.03
        k = r0 / 0.042
        m.blob(sleeve, "ell", T(*(sh + (sx * 0.005, 0.0, 0))), r=(0.045 * k, 0.048 * k, 0.047 * k), blend=0.01)
        m.blob(sleeve, "cone", a=sh, b=el, r1=0.037 * k, r2=0.029 * k, blend=0.015)
        m.blob(sleeve, "ell", A(sh + (el - sh) * 0.5 + fore * 0.0, el - sh), r=(0.03 * k, 0.05, 0.034 * k), blend=0.02)
        m.blob(sleeve, "cone", a=el, b=wrist, r1=0.031 * k, r2=0.022 * k, blend=0.012)
        m.blob(sleeve, "ell", A(el + (wrist - el) * 0.3, wrist - el), r=(0.032 * k, 0.045, 0.03 * k), blend=0.02)
        self.fist(skin, hand, fore, side, fist / 0.037)
        if sleeve != skin:
            m.add(sleeve, torus(0.025 * k, 0.007, 12, 5), A(wrist + fore * 0.004, fore))
        if pad:
            m.add(pad, lathe([(0.0, 0.03), (0.04, 0.02), (0.06, -0.01), (0.062, -0.025), (0.0, -0.01)], 20),
                  chain(T(*(sh + (0, 0.015, 0))), R(0, 0, -0.35 if side == "R" else 0.35)))
        return hand

    def fist(self, skin, at, fore, side, k=1.0):
        """Closed hand around `at` (where props are held); fingers curl round the grip."""
        m = self.m
        sx = -1 if side == "R" else 1
        m.push(chain(A(at, fore, (-sx, 0, 0)), S(k)))
        m.blob(skin, "box", T(0, -0.012, -0.012), h=(0.02, 0.026, 0.009), round=0.008, blend=0.008)
        for i, x in enumerate((-0.014, -0.005, 0.004, 0.013)):
            m.blob(skin, "cone", a=(x, 0.012, -0.014), b=(x, 0.022, 0.006), r1=0.0072, r2=0.0068, blend=0.004)
            m.blob(skin, "cone", a=(x, 0.022, 0.006), b=(x, 0.008 - 0.001 * i, 0.016), r1=0.0068, r2=0.006, blend=0.004)
        m.blob(skin, "cone", a=(0.016 * -1, -0.02, -0.004), b=(-0.008, 0.004, 0.018), r1=0.009, r2=0.0065, blend=0.006)
        m.pop()


def folds(amp, n, top):
    """Radial cloth folds around the figure's axis, growing below world height `top`."""
    def f(V):
        ang = np.arctan2(V[:, 2], V[:, 0])
        g = np.clip((top - V[:, 1]) / max(top, 1e-6), 0, 1) ** 0.8
        return V * np.c_[1 + amp * g * np.sin(n * ang), np.ones(len(V)), 1 + amp * g * np.sin(n * ang)]
    return f


# ---------------- props ----------------

def sword(m, hand, direction, length=0.42, blade="steel", hilt="leather", guard="gold", width=0.04, zhint=(0, 0, 1)):
    M = A(hand, direction, zhint)
    m.push(M)
    m.add(hilt, cyl(0.016, 0.016, 0.1, 8), T(0, -0.05, 0))
    m.add(guard, sphere(0.024, 10, 6), T(0, -0.06, 0))
    m.add(guard, box(width * 3.2, 0.022, 0.03), T(0, 0.05, 0))
    m.add(blade, extrude([(-width / 2, 0), (width / 2, 0), (width / 2, length * 0.85), (0, length), (-width / 2, length * 0.85)], 0.012), T(0, 0.06, 0))
    m.pop()


def axe(m, hand, direction, haft=0.62, double=True, head="steel", zhint=(0, 0, 1), grip=0.15):
    """`hand` sits `grip` along the haft from its butt."""
    m.push(A(hand, direction, zhint))
    m.add("wood", cyl(0.018, 0.016, haft, 10), T(0, -grip, 0))
    top = haft - grip
    blade = [(0.02, -0.07), (0.12, -0.12), (0.17, -0.02), (0.18, 0.05), (0.13, 0.14), (0.02, 0.08)]
    for sx in ((1, -1) if double else (1,)):
        m.add(head, extrude([(x * sx, y) for x, y in blade], 0.018), T(0, top - 0.09, 0))
    m.add("iron", cyl(0.03, 0.03, 0.12, 10), T(0, top - 0.15, 0))
    m.add(head, cyl(0.02, 0.0, 0.07, 8), T(0, top - 0.03, 0))
    m.pop()


def round_shield(m, center, facing, r=0.16, face="wood", rim="iron", boss="steel", emblem=None):
    m.push(A(center, facing))
    m.add(face, lathe([(0.0, 0.025), (r * 0.6, 0.02), (r, 0.0), (r, -0.012), (0.0, -0.008)], 28))
    m.add(rim, torus(r, 0.012, 28, 6))
    m.add(boss, sphere(1, 12, 8), S(0.04, 0.03, 0.04), )
    if emblem:
        emblem(m, r)
    m.pop()


def kite_shield(m, center, facing, h=0.36, w=0.24, face="steel", trim="gold", up=(0, 1, 0), emblem=None):
    m.push(chain(A(center, facing, up), R(-math.pi / 2, 0, 0)))  # extrude plane XY = shield face
    poly = [(-w / 2, h * 0.3), (-w * 0.48, h * 0.42), (0, h * 0.5), (w * 0.48, h * 0.42), (w / 2, h * 0.3), (w * 0.35, -h * 0.1), (0, -h / 2), (-w * 0.35, -h * 0.1)]
    m.add(trim, extrude(poly, 0.02))
    inner = [(x * 0.84, y * 0.86 + 0.005) for x, y in poly]
    m.add(face, extrude(inner, 0.028))
    if emblem:
        emblem(m)
    m.pop()


def staff(m, hand, length=0.95, top_frac=0.75, material="wood", wobble=0.012, seed=0):
    rng = np.random.default_rng(seed)
    n = 9
    ys = np.linspace(-length * (1 - top_frac), length * top_frac, n)
    pts = [(hand[0] + rng.uniform(-wobble, wobble), hand[1] + y, hand[2] + rng.uniform(-wobble, wobble)) for y in ys]
    pts[0] = (hand[0], hand[1] + ys[0], hand[2])
    m.add(material, tube(pts, np.linspace(0.016, 0.02, n), 8))
    return np.array(pts[-1])


def gem(m, at, r=0.04, material="crystal"):
    m.add(material, lathe([(0.0, -r * 1.3), (r, 0.0), (0.0, r * 1.6)], 6), T(*at))


@head_part
def eyes_glow(m, fig, material, dz=0.0):
    for sx in (-1, 1):
        m.add(material, sphere(0.014, 8, 5), T(sx * 0.03, fig.head[1] + 0.008, fig.head[2] + 0.078 + dz))


@head_part
def hair_cap(m, fig, material, r=0.09, back=0.012, low=-0.35):
    """Sculpted hair: a cap over the crown and a fall at the back (longer when `low` is lower)."""
    h, k = fig.head, r / 0.09
    m.blob(material, "ell", T(h[0], h[1] + 0.016, h[2] - 0.012 - back * 0.3), r=(0.079 * k, 0.088 * k, 0.09 * k), clip=(h[1] + 0.025, 2.0))
    m.blob(material, "ell", T(h[0], h[1] + 0.005, h[2] - 0.03 - back), r=(0.08 * k, 0.09 * k, 0.07 * k), blend=0.02, clip=(h[1] + low * 0.2, 2.0))
    strands(m, material, h + (0, 0.01, -0.012), 0.086 * k, np.random.default_rng(7), az_skip=0.95, els=np.linspace(1.35, max(low, -0.6), 7), length=0.055 * k, n_az=32)


def strands(m, material, center, r, rng, az_skip=0.0, az_range=math.pi, els=(0.0,), length=0.05, down=0.7, n_az=22):
    """Clumps of hair/fur: small cones sprouting from a sphere around `center`, hanging down."""
    for az in np.linspace(-az_range, az_range, n_az, endpoint=az_range < math.pi):
        for el in els:
            if abs(az) < az_skip and el < 1.0:
                continue  # keep the face clear; only a fringe crosses the front
            a = az + rng.uniform(-0.08, 0.08)
            d = np.array((math.cos(el) * math.sin(a), math.sin(el), math.cos(el) * math.cos(a)))
            v = d * (1 - down) + np.array((0, -down, -0.15))
            v /= np.linalg.norm(v)
            ln = length * rng.uniform(0.75, 1.25)
            m.add(material, cyl(r * 0.2, 0.0, ln, 7), A(center + d * r - v * 0.008, v))


def hood(m, fig, material, r=0.108, tip=0.06):
    """Hood: a sphere shell with the face cut out, plus a drape over the shoulders."""
    fig.head_scope()
    a0, a1 = math.pi / 2 + 0.75, math.pi / 2 - 0.75 + 2 * math.pi
    prof = [(0.0, -r * 0.55)] + [(r * math.cos(a), r * math.sin(a)) for a in np.linspace(-0.6, math.pi / 2, 8)[1:-1]] + [(0.0, r)]
    m.add(material, lathe(prof, 22, a0, a1), chain(T(fig.head[0], fig.head[1] + 0.01, fig.head[2] - 0.01), S(1, 1.12, 1.08)))
    m.add(material, lathe([(0.17, 0.6), (0.13, 0.68), (0.07, 0.74)], 22), S(fig.bulk, 1, 0.8 * fig.bulk))
    if tip:
        m.add(material, cyl(0.05, 0.0, tip, 10), chain(T(0, fig.head[1] + 0.07, fig.head[2] - 0.07), R(-1.1, 0, 0)))


def cape(m, material, r_top=0.12, r_bot=0.25, top=0.7, spread=1.25, length=0.68, flutter=0.0):
    a0, a1 = -math.pi / 2 - spread, -math.pi / 2 + spread
    prof = [(r_top + (r_bot - r_top) * (1 - t) ** 1.3, top - length * (1 - t)) for t in np.linspace(0, 1, 9)]
    fold = folds(0.08, 9, top + BASE_H)
    m.add(material, lathe(prof, 40, a0, a1), deform=lambda V: fold(V) + np.c_[np.zeros(len(V)), np.zeros(len(V)), -flutter * np.clip(top - V[:, 1], 0, None) ** 2])


@head_part
def pointy_hat(m, fig, material, band=None, brim=0.19, height=0.34, droop=0.5):
    h0 = fig.head[1] + 0.05
    prof = [(0.0, 0.0), (brim, 0.0), (brim * 1.01, 0.012), (0.095, 0.022), (0.08, height * 0.35), (0.05, height * 0.65), (0.022, height * 0.88), (0.0, height)]
    def droopy(V):
        y = V[:, 1] - h0
        k = np.clip(y - height * 0.45, 0, None)
        return V + np.c_[np.zeros(len(V)), -droop * k ** 2, -droop * 1.6 * k ** 2]
    m.add(material, lathe(prof, 30), T(0, h0, fig.head[2]), deform=droopy)
    if band:
        m.add(band, lathe([(0.097, 0.02), (0.098, 0.022), (0.09, 0.05), (0.089, 0.052)], 24), T(0, h0, fig.head[2]))


@head_part
def beard(m, fig, material, length=0.2, width=0.06):
    """Sculpted beard and moustache hanging from the jaw."""
    h = fig.head
    n = 6
    for i in range(n):
        t = i / (n - 1)
        w = width * (1.05 - 0.75 * t ** 1.5)
        m.blob(material, "ell", T(0, h[1] - 0.05 - length * t, h[2] + 0.055 + 0.02 * t), r=(w, length / n * 1.3, 0.032 * (1 - 0.5 * t)), blend=0.02)
    for sx in (-1, 1):
        m.blob(material, "ell", T(sx * 0.05, h[1] - 0.035, h[2] + 0.045), r=(0.022, 0.04, 0.03), blend=0.02)
        m.blob(material, "cone", a=(sx * 0.004, h[1] - 0.037, h[2] + 0.088), b=(sx * 0.034, h[1] - 0.052, h[2] + 0.074), r1=0.008, r2=0.004, blend=0.006)
    rng = np.random.default_rng(3)
    for i in range(5):  # hanging locks over the sculpted beard
        t = i / 4
        strands(m, material, h + (0, -0.05 - length * 0.55 * t, 0.03 + 0.015 * t), width * (1 - 0.6 * t) * 0.9, rng,
                az_range=1.3, els=(-0.2,), length=length * 0.35, down=0.8, n_az=7)


def horns(m, at, side, material, length=0.12, curl=1.0):
    sx = 1 if side == "L" else -1
    pts = [np.asarray(at) + (sx * (0.04 * t + 0.03 * math.sin(t * 1.4 * curl) * curl), 0.06 * t + 0.02 * t * t * curl, -0.04 * t * t * curl) for t in np.linspace(0, 1.6 * length / 0.12, 8)]
    m.add(material, tube(pts, np.linspace(0.022 * length / 0.12, 0.003, 8), 8))


@head_part
def helmet(m, fig, material, r=0.095, nasal=True, crest=None):
    h = fig.head
    m.add(material, lathe([(r, -0.02), (r * 1.02, 0.0), (r * 0.95, 0.04)] + [(r * math.cos(a) * 0.95, 0.04 + r * math.sin(a)) for a in np.linspace(0.3, math.pi / 2, 6)[:-1]] + [(0.0, 0.04 + r)], 22),
          chain(T(h[0], h[1] + 0.005, h[2]), S(1, 1, 1.05)))
    for a in np.linspace(0, 2 * math.pi, 14, endpoint=False):
        m.add("iron", sphere(0.0055, 7, 5), T(h[0] + r * 1.02 * math.cos(a), h[1] - 0.004, h[2] + r * 1.07 * math.sin(a)))
    if nasal:
        m.add(material, box(0.018, 0.07, 0.012), T(0, h[1] - 0.005, h[2] + r * 1.02))


@head_part
def great_helm(m, fig, material, trim="gold", slit="eye"):
    h = fig.head
    m.add(material, lathe([(0.0, -0.085), (0.09, -0.085), (0.096, -0.04), (0.096, 0.04), (0.085, 0.075), (0.05, 0.095), (0.0, 0.1)], 20),
          chain(T(*h), S(1, 1, 1.06)))
    m.add(slit, box(0.13, 0.014, 0.03), T(0, h[1] + 0.01, h[2] + 0.092))
    m.add(trim, box(0.016, 0.13, 0.02), T(0, h[1] - 0.005, h[2] + 0.1))
    m.add(trim, torus(0.095, 0.008, 20, 5), chain(T(*(h + (0, -0.08, 0))), S(1, 1, 1.06)))


def plume(m, at, material, length=0.22, rise=0.05):
    pts = [np.asarray(at) + (0, rise * math.sin(t * 2.2) + 0.03 * t, -length * t) for t in np.linspace(0, 1, 9)]
    m.add(material, tube(pts, 0.035 * np.sin(np.linspace(0.3, math.pi - 0.2, 9)) + 0.004, 10))


def pauldron(m, fig, side, material, trim=None):
    sh = fig.sh[side]
    sx = -1 if side == "R" else 1
    M = chain(T(*(sh + (sx * 0.01, 0.02, 0))), R(0, 0, -sx * 0.45))
    prof = [(0.0, 0.045)] + [(0.075 * math.cos(a), 0.045 * math.sin(a) - 0.005) for a in np.linspace(0.25, 1.3, 4)][::-1] + [(0.08, -0.03), (0.0, -0.01)]
    prof = [(0.0, 0.045), (0.035, 0.04), (0.06, 0.025), (0.078, 0.0), (0.082, -0.032), (0.0, -0.01)]
    m.add(material, lathe(prof, 16), M)
    for a in np.linspace(0.3, 2 * math.pi - 0.3, 8):
        m.add(trim or "iron", sphere(0.006, 7, 5), chain(M, T(0.072 * math.cos(a), -0.022, 0.072 * math.sin(a))))
    if trim:
        m.add(trim, torus(0.08, 0.007, 16, 5), chain(M, T(0, -0.03, 0)))


def tabard(m, material, trim=None, front=True, back=True, width=0.13, top=0.62, bottom=0.14, depth=0.08):
    for zs in ((1,) if front else ()) + ((-1,) if back else ()):
        poly = [(-width / 2, top), (width / 2, top), (width * 0.55, bottom), (0, bottom - 0.03), (-width * 0.55, bottom)]
        m.add(material, extrude(poly, 0.012), chain(T(0, 0, zs * depth), R(-zs * 0.06, 0, 0)))
        if trim:
            m.add(trim, extrude([(-width * 0.58, bottom + 0.02), (width * 0.58, bottom + 0.02), (width * 0.58, bottom), (0, bottom - 0.035), (-width * 0.58, bottom)], 0.014),
                  chain(T(0, 0, zs * depth), R(-zs * 0.06, 0, 0)))


def skirt(m, fig, material, top=0.46, bottom=0.25, r_top=0.12, r_bot=0.16, segs=24, jag=0.0, seed=0):
    rng = np.random.default_rng(seed)
    def ragged(V):
        if not jag:
            return V
        low = V[:, 1] < top - 0.01
        V = V.copy()
        V[low, 1] += rng.uniform(-jag, jag, low.sum())
        return V
    fold = folds(0.05, 13, BASE_H + top * fig.s)
    prof = [(r_top + (r_bot - r_top) * t, top - (top - bottom) * t) for t in np.linspace(1, 0, 6)]
    m.add(material, lathe(prof, segs * 1.6), S(fig.bulk, 1, 0.82 * fig.bulk), deform=lambda V: ragged(fold(V)))


def book(m, at, facing, cover="dark_leather", pages="cloth_white"):
    m.push(A(at, facing))
    m.add(cover, box(0.12, 0.03, 0.15))
    m.add(pages, box(0.11, 0.032, 0.14), T(0.006, 0, 0))
    m.add("gold", box(0.04, 0.034, 0.04))
    m.pop()


def flames(m, at, core="fire", outer="fire_out", size=0.06, seed=0):
    rng = np.random.default_rng(seed)
    m.add(core, sphere(size * 0.6, 12, 8), T(*at))
    for k in range(7):
        a = k / 7 * 2 * math.pi + rng.uniform(-0.2, 0.2)
        tilt = rng.uniform(0.15, 0.45)
        m.add(outer, cyl(size * 0.38, 0.0, size * rng.uniform(1.4, 2.2), 8),
              chain(T(*at), R(0, a, tilt), T(0, -size * 0.2, 0)))


def quiver(m, at, material="leather"):
    m.push(chain(T(*at), R(0.25, 0, -0.35)))
    m.add(material, cyl(0.04, 0.045, 0.3, 12))
    for k in range(5):
        a = k / 5 * 2 * math.pi
        x, z = 0.022 * math.cos(a), 0.022 * math.sin(a)
        m.add("wood", cyl(0.005, 0.005, 0.1, 5), T(x, 0.28, z))
        m.add("fletch", extrude([(0, 0), (0.012, 0.01), (0.012, 0.05), (0, 0.04)], 0.004), chain(T(x, 0.33, z), R(0, a, 0)))
    m.pop()


def bow(m, grip, up=(0, 1, 0), forward=(0, 0, 1), length=0.62, material="wood", string_to=None):
    up, fw = np.asarray(up, float), np.asarray(forward, float)
    up /= np.linalg.norm(up)
    fw = fw - up * np.dot(fw, up)
    fw /= np.linalg.norm(fw)
    ts = np.linspace(-1, 1, 15)
    pts = [np.asarray(grip) + up * t * length / 2 + fw * (0.06 * (1 - t * t) - 0.02 * t ** 4) for t in ts]
    m.add(material, tube(pts, 0.012 + 0.008 * (1 - np.abs(ts)), 8))
    tips = pts[0], pts[-1]
    mid = np.asarray(grip) - fw * 0.02 if string_to is None else np.asarray(string_to)
    m.add("rope", tube([tips[0], mid, tips[1]], 0.0035, 5, caps=False))


# ---------------- figures ----------------

def barbarian(m):
    f = Fig(m, s=1.04, bulk=1.15)
    m.materials.update(fur=mat("#8a6a4a", rough=1.0), war_paint=mat("#2f5d9e"))
    f.legs("leather", "fur", apart=0.075, stance=0.05)
    skirt(m, f, "fur", top=0.47, bottom=0.27, r_top=0.115, r_bot=0.15, jag=0.025, seed=3)
    f.upper()
    f.torso("skin", belt="dark_leather", chest=0.135)
    m.add("fur", torus(0.115, 0.04, 22, 8), chain(T(0, 0.665, -0.005), S(1.15, 0.8, 0.85)))
    f.neck_head("skin")
    hair_cap(m, f, "hair_brown", r=0.092, back=0.02)
    beard(m, f, "hair_brown", length=0.09, width=0.05)
    for sx in (-1, 1):  # braids
        m.add("hair_brown", tube([(sx * 0.07, 0.78, -0.02), (sx * 0.085, 0.7, 0.0), (sx * 0.08, 0.62, 0.02)], [0.016, 0.014, 0.01], 6))
    for sx in (-1, 1):  # war paint stripes
        m.add("war_paint", box(0.012, 0.014, 0.02), T(sx * 0.045, 0.815, 0.08))
    hl, hr = np.array((0.04, 0.5, 0.15)), np.array((-0.15, 0.74, 0.12))
    f.arm("R", hr, "skin", "skin", elbow=(-0.25, 0.62, 0.02), r0=0.048, fist=0.042)
    f.arm("L", hl, "skin", "skin", elbow=(0.2, 0.5, 0.06), r0=0.048, fist=0.042)
    for side in ("R", "L"):
        m.add("dark_leather", tube([f.sh[side] * (1.05, 1, 1) + (0, -0.06, 0), f.sh[side] * (1.12, 1, 1) + (0, -0.1, 0)], 0.05, 12))
    axe(m, hl, hr - hl, haft=0.78, grip=0.1)
    m.pop()
    f.done()


def bard(m):
    f = Fig(m)
    m.materials.update(doublet=mat("#8e2d5c"), hose=mat("#2c3f6b"), feather=mat("#f2efe6"), lute=mat("#b5763a", rough=0.6), hat=mat("#3b2a5c"))
    f.legs("hose", "leather", stance=0.04, boot_top=0.2)
    f.upper()
    f.torso("doublet", belt="leather")
    skirt(m, f, "doublet", top=0.47, bottom=0.36, r_top=0.11, r_bot=0.135)
    cape(m, "hat", r_top=0.11, r_bot=0.2, length=0.5, spread=1.1)
    m.add("cloth_white", torus(0.055, 0.022, 16, 6), T(0, 0.7, 0.0))
    f.neck_head("skin")
    hair_cap(m, f, "hair_brown", back=0.02)
    hh = f.head + (0, 0.07, 0)
    m.add("hat", lathe([(0.0, 0.0), (0.16, 0.0), (0.165, 0.012), (0.09, 0.02), (0.085, 0.07), (0.06, 0.09), (0.0, 0.095)], 26), chain(T(*hh), R(0.12, 0, -0.18), S(1, 1, 0.9)))
    m.add("feather", tube([hh + (0.07, 0.05, -0.02), hh + (0.12, 0.13, -0.08), hh + (0.13, 0.22, -0.17)], [0.022, 0.028, 0.004], 8))
    body = np.array((0.02, 0.5, 0.11))
    m.push(chain(T(*body), R(0.2, 0, 0.9)))
    m.add("lute", sphere(1, 18, 12), S(0.085, 0.11, 0.045))
    m.add("eye", cyl(0.022, 0.022, 0.05, 12), chain(T(0, 0.01, 0.0), R(math.pi / 2, 0, 0), T(0, -0.025, 0)))
    m.add("wood", box(0.035, 0.24, 0.025), T(0, 0.19, 0.01))
    m.add("wood", box(0.045, 0.06, 0.03), chain(T(0, 0.33, 0.0), R(-0.4, 0, 0)))
    m.pop()
    f.arm("L", (-0.11, 0.66, 0.12), "doublet", "skin", elbow=(0.12, 0.6, 0.12))
    f.arm("R", (0.03, 0.47, 0.17), "doublet", "skin", elbow=(-0.17, 0.5, 0.08))
    m.pop()
    f.done()


def cleric(m):
    f = Fig(m)
    m.materials.update(vestment=mat("#e8e2d0"), tabard_blue=mat("#2d4f8a"), sun=mat("#ffd25a", metal=0.6, rough=0.3, emit=(0.25, 0.18, 0.02)))
    f.robe("vestment", r=0.18, hem="gold")
    f.upper()
    f.torso("steel", belt="leather")
    tabard(m, "tabard_blue", trim="gold", width=0.12, top=0.64, bottom=0.08, depth=0.1)
    f.neck_head("skin")
    helmet(m, f, "steel", nasal=False)
    m.add("sun", cyl(0.03, 0.03, 0.01, 12), chain(T(0, 0.55, 0.108), R(math.pi / 2, 0, 0)))
    for side in ("R", "L"):
        pauldron(m, f, side, "steel", trim="gold")
    hr = f.arm("R", (-0.2, 0.62, 0.14), "vestment", "steel", elbow=(-0.24, 0.52, 0.0))
    m.push(A(hr, (-0.15, 1, 0.25)))
    m.add("wood", cyl(0.016, 0.016, 0.3, 8), T(0, -0.07, 0))
    m.add("steel", sphere(0.045, 10, 8), T(0, 0.23, 0))
    for k in range(6):
        m.add("steel", box(0.012, 0.07, 0.03), chain(T(0, 0.23, 0), R(0, k * math.pi / 6, 0), T(0, 0, 0.04)))
    m.pop()
    f.arm("L", (0.2, 0.47, 0.1), "vestment", "steel", elbow=(0.22, 0.52, -0.02))

    def sunburst(mm, r):
        mm.add("sun", sphere(1, 12, 6), chain(T(0, 0.03, 0), S(0.045, 0.012, 0.045)))
        for k in range(8):
            mm.add("sun", box(0.016, 0.006, 0.07), chain(T(0, 0.03, 0), R(0, k * math.pi / 4, 0), T(0, 0, 0.07)))
    round_shield(m, (0.25, 0.47, 0.06), (1, 0, 0.35), r=0.15, face="tabard_blue", rim="gold", boss="gold", emblem=sunburst)
    m.pop()
    f.done()


def druid(m):
    f = Fig(m)
    m.materials.update(robe_green=mat("#4a6b3a"), mantle=mat("#6f5a3a", rough=1.0), leaf=mat("#7fb04a"), crystal=mat("#9ff0b0", rough=0.2, emit=(0.15, 0.45, 0.2)), antler=mat("#d8c8a8"))
    f.robe("robe_green", r=0.19, hem="mantle")
    f.upper()
    f.torso("robe_green", belt="rope")
    cape(m, "mantle", r_top=0.12, r_bot=0.22, length=0.62, spread=1.4)
    f.neck_head("skin")
    hood(m, f, "mantle", tip=0)
    beard(m, f, "hair_white", length=0.16, width=0.05)
    for side, sx in (("R", -1), ("L", 1)):  # antlers
        base_ = f.head + (sx * 0.06, 0.07, -0.01)
        main = [base_ + (sx * 0.03 * t + sx * 0.02 * t * t, 0.1 * t, -0.03 * t) for t in np.linspace(0, 1.4, 7)]
        m.add("antler", tube(main, np.linspace(0.014, 0.004, 7), 7))
        for k, t in enumerate((0.5, 0.9)):
            p = base_ + (sx * 0.03 * t + sx * 0.02 * t * t, 0.1 * t, -0.03 * t)
            m.add("antler", tube([p, p + (sx * 0.035, 0.03, 0.02 + 0.01 * k)], [0.008, 0.003], 6))
    hr = f.arm("R", (-0.2, 0.6, 0.1), "robe_green", "skin", elbow=(-0.23, 0.5, -0.02))
    top = staff(m, hr, length=1.05, top_frac=0.45, seed=2)
    for k in range(5):  # twisted crown holding a crystal
        a = k / 5 * 2 * math.pi
        m.add("wood", tube([top, top + (0.04 * math.cos(a), 0.06, 0.04 * math.sin(a)), top + (0.02 * math.cos(a + 0.6), 0.12, 0.02 * math.sin(a + 0.6))], [0.012, 0.008, 0.003], 6))
        m.add("leaf", sphere(1, 6, 4), chain(T(*(top + (0.05 * math.cos(a), 0.02, 0.05 * math.sin(a)))), R(0, -a, 0.6), S(0.03, 0.006, 0.016)))
    gem(m, top + (0, 0.07, 0), r=0.032)
    f.arm("L", (0.19, 0.5, 0.15), "robe_green", "skin", elbow=(0.2, 0.52, 0.0))
    m.add("leaf", sphere(1, 8, 6), chain(T(0.19, 0.55, 0.16), S(0.03, 0.04, 0.03)))
    m.pop()
    f.done()


def fighter(m):
    f = Fig(m, bulk=1.05)
    m.materials.update(chain_mail=mat("#8d929a", metal=0.7, rough=0.55), gambeson=mat("#9a3b2e"))
    f.legs("dark_leather", "leather", stance=0.06)
    skirt(m, f, "chain_mail", top=0.47, bottom=0.3, r_top=0.115, r_bot=0.14)
    f.upper()
    f.torso("chain_mail", belt="leather")
    tabard(m, "gambeson", width=0.15, top=0.6, bottom=0.26, depth=0.095)
    f.neck_head("skin")
    helmet(m, f, "steel")
    m.add("chain_mail", lathe([(0.12, 0.66), (0.1, 0.72), (0.093, 0.76)], 18), T(0, 0, 0))
    for side in ("R", "L"):
        pauldron(m, f, side, "steel")
    hr = f.arm("R", (-0.2, 0.55, 0.16), "chain_mail", "leather", elbow=(-0.25, 0.53, 0.02))
    sword(m, hr, (-0.15, 1, 0.55), length=0.44)
    f.arm("L", (0.19, 0.5, 0.13), "chain_mail", "leather")
    round_shield(m, (0.24, 0.5, 0.11), (1, 0, 0.7), r=0.15, face="gambeson", emblem=lambda mm, r: mm.add("steel", box(0.035, 0.012, 0.22), T(0, 0.02, 0)))
    m.pop()
    f.done()


def monk(m):
    f = Fig(m)
    m.materials.update(gi=mat("#e08a2a"), sash=mat("#7a2a1c"), bead=mat("#3b1f12", rough=0.4), wrap=mat("#e8dcc0"))
    f.legs("gi", "wrap", apart=0.085, stance=0.1, boot_top=0.1)
    f.upper()
    f.torso("gi")
    m.add("sash", lathe([(0.108, 0.42), (0.118, 0.43), (0.118, 0.48), (0.108, 0.49)], 24), S(1, 1, 0.78))
    m.add("sash", tube([(0.06, 0.45, 0.08), (0.08, 0.38, 0.1), (0.09, 0.3, 0.09)], [0.018, 0.02, 0.012], 6))
    f.neck_head("skin")
    for k in range(18):  # prayer beads
        a = k / 18 * 2 * math.pi
        m.add("bead", sphere(0.012, 6, 4), T(0.075 * math.cos(a), 0.66 - 0.06 * max(0, math.sin(a)), 0.06 * math.sin(a) + 0.005))
    f.arm("R", (-0.06, 0.62, 0.3), "gi", "wrap", elbow=(-0.19, 0.6, 0.12), r0=0.04)
    f.arm("L", (0.12, 0.56, 0.08), "gi", "wrap", elbow=(0.24, 0.56, -0.02), r0=0.04)
    m.add("wood", tube([(0.14, 0.28, -0.12), (0.0, 0.62, -0.11), (-0.14, 0.96, -0.1)], 0.014, 8))
    m.pop()
    f.done()


def paladin(m):
    f = Fig(m, bulk=1.08)
    m.materials.update(plate=mat("#d6dbe2", metal=0.9, rough=0.25), cape_white=mat("#f1ece0", double=True), holy=mat("#fff2b0", emit=(0.5, 0.42, 0.15), rough=0.2))
    f.legs("plate", "plate", stance=0.03, boot_top=0.24)
    skirt(m, f, "plate", top=0.47, bottom=0.3, r_top=0.115, r_bot=0.145)
    f.upper()
    cape(m, "cape_white", r_top=0.13, r_bot=0.26, length=0.66, spread=1.2)
    f.torso("plate", belt="gold")
    m.add("gold", extrude([(-0.012, -0.05), (0.012, -0.05), (0.012, 0.015), (0.04, 0.015), (0.04, 0.038), (0.012, 0.038), (0.012, 0.06), (-0.012, 0.06), (-0.012, 0.038), (-0.04, 0.038), (-0.04, 0.015), (-0.012, 0.015)], 0.01),
          T(0, 0.56, 0.1))
    f.neck_head("skin")
    great_helm(m, f, "plate")
    for sx in (-1, 1):  # helm wings
        m.add("gold", extrude([(0, 0), (0.1, 0.05), (0.13, 0.12), (0.07, 0.08), (0.09, 0.13), (0.03, 0.08), (0.0, 0.05)], 0.01),
              chain(T(sx * 0.09, f.head[1] + 0.01, f.head[2] - 0.02), S(sx, 1, 1), R(0, 0.6, 0)))
    for side in ("R", "L"):
        pauldron(m, f, side, "plate", trim="gold")
    grip = np.array((0.0, 0.5, 0.17))
    f.arm("R", grip + (-0.02, 0.0, 0), "plate", "plate", elbow=(-0.21, 0.52, 0.06))
    f.arm("L", grip + (0.02, 0.05, 0), "plate", "plate", elbow=(0.21, 0.55, 0.06))
    sword(m, grip + (0, 0.07, 0), (0, -1, 0.04), length=0.5, blade="holy", width=0.05)
    m.pop()
    f.done()


def ranger(m):
    f = Fig(m)
    m.materials.update(cloak=mat("#3f5a34", double=True), tunic=mat("#6f6a3a"), fletch=mat("#c9c2b0"))
    f.legs("dark_leather", "leather", stance=0.07, boot_top=0.22)
    f.upper()
    f.torso("tunic", belt="leather")
    skirt(m, f, "tunic", top=0.47, bottom=0.32, r_top=0.11, r_bot=0.14)
    m.add("leather", tube([(-0.11, 0.66, 0.06), (0.0, 0.55, 0.1), (0.11, 0.44, 0.06)], 0.012, 6))
    cape(m, "cloak", r_top=0.12, r_bot=0.24, length=0.6, spread=1.3, flutter=0.3)
    f.neck_head("skin")
    hood(m, f, "cloak", tip=0.05)
    quiver(m, (0.06, 0.45, -0.11))
    hand_l = np.array((0.18, 0.66, 0.26))
    f.arm("L", hand_l, "tunic", "leather", elbow=(0.2, 0.64, 0.1))
    hand_r = np.array((-0.03, 0.7, 0.06))
    f.arm("R", hand_r, "tunic", "leather", elbow=(-0.18, 0.7, -0.02))
    bow(m, hand_l, up=(0.15, 1, 0.0), forward=(0.2, 0, 1), length=0.66, string_to=hand_r)
    m.add("wood", cyl(0.005, 0.005, 0.32, 5), A(hand_r, hand_l - hand_r))
    m.add("steel", cyl(0.012, 0.0, 0.04, 6), A(hand_r + (hand_l - hand_r) / np.linalg.norm(hand_l - hand_r) * 0.32, hand_l - hand_r))
    m.pop()
    f.done()


def rogue(m):
    f = Fig(m, hunch=0.12)
    m.materials.update(shadow=mat("#2a2a33", double=True), vest=mat("#3a3530", rough=0.6), scarf=mat("#4c1d24"))
    f.legs("shadow", "dark_leather", apart=0.08, stance=0.09, boot_top=0.24)
    f.upper()
    f.torso("vest", belt="leather")
    m.add("leather", tube([(0.11, 0.66, 0.06), (0.0, 0.55, 0.095), (-0.11, 0.44, 0.06)], 0.012, 6))
    for k in range(3):
        m.add("leather", box(0.03, 0.035, 0.02), T(-0.04 + k * 0.035, 0.5 - k * 0.035, 0.1))
    cape(m, "shadow", r_top=0.12, r_bot=0.22, length=0.55, spread=1.25, flutter=0.5)
    f.neck_head("skin")
    hood(m, f, "shadow", tip=0.04)
    m.add("scarf", lathe([(0.075, -0.06), (0.09, -0.03), (0.086, 0.0)], 18, 0.3 - math.pi, math.pi - 0.3), chain(T(*f.head), R(0, math.pi / 2, 0)))
    for side, hand, d in (("R", (-0.22, 0.48, 0.18), (-0.25, -0.2, 1)), ("L", (0.2, 0.55, 0.14), (0.5, 0.6, 0.4))):
        h = f.arm(side, hand, "shadow", "dark_leather")
        sword(m, np.asarray(h), d, length=0.2, width=0.032, hilt="dark_leather", guard="iron")
    m.pop()
    f.done()


def sorcerer(m):
    f = Fig(m)
    m.materials.update(robe_red=mat("#8f1f1f"), robe_trim=mat("#e0a030", metal=0.5, rough=0.4), fire=mat("#ffe08a", emit=(1.0, 0.6, 0.15)), fire_out=mat("#ff6a1a", emit=(0.9, 0.25, 0.02)), scale=mat("#5a1414", rough=0.4))
    f.robe("robe_red", r=0.18, hem="robe_trim")
    f.upper()
    f.torso("robe_red", belt="robe_trim")
    m.add("robe_trim", lathe([(0.125, 0.58), (0.11, 0.66), (0.08, 0.72), (0.06, 0.78)], 20, math.pi * 1.15, math.pi * 1.85 + math.pi * 0.0), S(1, 1, 0.8))
    f.neck_head("skin")
    hair_cap(m, f, "hair_white", r=0.092, back=0.02)
    m.add("hair_white", tube([f.head + (0, 0.04, -0.07), f.head + (0, -0.08, -0.1), f.head + (0, -0.2, -0.08)], [0.04, 0.035, 0.01], 8))
    for side in ("R", "L"):
        horns(m, f.head + ((-1 if side == "R" else 1) * 0.05, 0.06, -0.02), side, "scale", length=0.1)
    for k in range(4):  # dragon scales on the cheek
        m.add("scale", sphere(1, 6, 4), chain(T(0.07 - 0.008 * k, f.head[1] - 0.01 + 0.012 * k, f.head[2] + 0.04), S(0.012, 0.01, 0.006)))
    f.arm("R", (-0.17, 0.82, 0.14), "robe_red", "skin", elbow=(-0.24, 0.66, 0.05))
    flames(m, (-0.17, 0.92, 0.16), size=0.065, seed=4)
    f.arm("L", (0.2, 0.52, 0.16), "robe_red", "skin")
    flames(m, (0.21, 0.58, 0.18), size=0.035, seed=5)
    m.pop()
    f.done()


def warlock(m):
    f = Fig(m)
    m.materials.update(robe_black=mat("#1f1a2a"), robe_violet=mat("#4b2a6b", double=True), eldritch=mat("#c27bff", emit=(0.55, 0.15, 0.9)))
    f.robe("robe_black", r=0.19, hem="robe_violet")
    f.upper()
    f.torso("robe_black", belt="bone")
    cape(m, "robe_violet", r_top=0.12, r_bot=0.25, length=0.68, spread=1.35, flutter=0.4)
    m.add("robe_violet", lathe([(0.12, 0.66), (0.13, 0.74), (0.15, 0.86), (0.155, 0.88)], 24, math.pi * 1.1, math.pi * 1.9), S(1, 1, 0.9))  # high collar
    f.neck_head("skin")
    hood(m, f, "robe_black", tip=0.07)
    eyes_glow(m, f, "eldritch")
    for k in range(5):
        m.add("bone", sphere(1, 8, 6), chain(T(-0.05 + 0.025 * k, 0.6 - 0.02 * abs(k - 2), 0.105), S(0.012, 0.016, 0.01)))
    f.arm("L", (0.18, 0.55, 0.17), "robe_black", "skin", elbow=(0.22, 0.52, 0.02))
    book(m, (0.17, 0.6, 0.19), (0.3, 1, 0.5), cover="robe_violet")
    hr = f.arm("R", (-0.2, 0.74, 0.18), "robe_black", "skin", elbow=(-0.25, 0.62, 0.05))
    m.add("eldritch", sphere(0.05, 16, 10), T(-0.2, 0.83, 0.2))
    m.add("eldritch", torus(0.075, 0.006, 24, 4), chain(T(-0.2, 0.83, 0.2), R(0.6, 0, 0.4)))
    m.add("eldritch", torus(0.085, 0.006, 24, 4), chain(T(-0.2, 0.83, 0.2), R(-0.5, 0.0, -0.6)))
    m.pop()
    f.done()


def wizard(m):
    f = Fig(m)
    m.materials.update(robe_blue=mat("#2a3d8f"), star=mat("#f2d36b", metal=0.6, rough=0.3), crystal=mat("#9fd8ff", rough=0.15, emit=(0.2, 0.45, 0.7)))
    f.robe("robe_blue", r=0.2, hem="star")
    f.upper()
    f.torso("robe_blue", belt="rope")
    m.add("robe_blue", lathe([(0.0, 0.62), (0.14, 0.64), (0.09, 0.72), (0.0, 0.73)], 22), S(1, 1, 0.85))
    f.neck_head("skin")
    hair_cap(m, f, "hair_white", r=0.09, back=0.015)
    beard(m, f, "hair_white", length=0.28, width=0.065)
    pointy_hat(m, f, "robe_blue", band="star", brim=0.2, height=0.36, droop=1.2)
    for k, (y, a) in enumerate(((0.2, 0.9), (0.33, 2.6), (0.12, 4.2))):  # stars on the robe
        m.add("star", extrude([(0.025 * math.cos(t) * (1 if i % 2 == 0 else 0.45), 0.025 * math.sin(t) * (1 if i % 2 == 0 else 0.45)) for i, t in enumerate(np.linspace(math.pi / 2, math.pi / 2 + 2 * math.pi, 10, endpoint=False))], 0.006),
              chain(R(0, a, 0), T(0, y, 0.165), R(-0.15, 0, 0)))
    hr = f.arm("R", (-0.21, 0.6, 0.1), "robe_blue", "skin", elbow=(-0.24, 0.5, -0.02))
    top = staff(m, hr, length=1.08, top_frac=0.48, seed=7)
    m.add("wood", torus(0.035, 0.01, 12, 5), T(*(top + (0, 0.02, 0))))
    gem(m, top + (0, 0.07, 0), r=0.04)
    f.arm("L", (0.17, 0.56, 0.17), "robe_blue", "skin", elbow=(0.22, 0.52, 0.02))
    m.add("crystal", sphere(0.025, 10, 6), T(0.17, 0.62, 0.19))
    m.pop()
    f.done()


def knight(m):
    f = Fig(m, bulk=1.1)
    m.materials.update(plate=mat("#c4c9d0", metal=0.9, rough=0.3), heraldry=mat("#2b4aa0"), plume_red=mat("#c0262b"), cape_blue=mat("#24387a", double=True))
    f.legs("plate", "plate", stance=0.04, boot_top=0.24)
    f.upper()
    cape(m, "cape_blue", r_top=0.13, r_bot=0.26, length=0.66, spread=1.2, flutter=0.2)
    f.torso("plate", belt="leather")
    tabard(m, "heraldry", trim="gold", width=0.15, top=0.6, bottom=0.18, depth=0.1)
    f.neck_head("skin")
    great_helm(m, f, "plate")
    plume(m, f.head + (0, 0.1, 0.0), "plume_red", length=0.24)
    for side in ("R", "L"):
        pauldron(m, f, side, "plate", trim="gold")
    hr = f.arm("R", (-0.21, 0.6, 0.15), "plate", "plate", elbow=(-0.26, 0.54, 0.02))
    sword(m, hr, (-0.05, 1, 0.15), length=0.5)

    def lion(mm):
        mm.add("gold", extrude([(0, 0.08), (0.04, 0.03), (0.03, -0.06), (0, -0.09), (-0.03, -0.06), (-0.04, 0.03)], 0.034))
    f.arm("L", (0.2, 0.5, 0.12), "plate", "plate")
    kite_shield(m, (0.25, 0.48, 0.1), (1, 0, 0.6), face="heraldry", emblem=lion)
    m.pop()
    f.done()


def goblin(m):
    f = Fig(m, s=0.7, bulk=1.05, hunch=0.18)
    m.materials.update(gob=mat("#6f9a3a"), rag=mat("#7a6a4a"), gob_eye=mat("#ffd23a", emit=(0.5, 0.35, 0.0)))
    f.legs("rag", "gob", apart=0.08, stance=0.08, boot_top=0.12)
    skirt(m, f, "rag", top=0.47, bottom=0.28, r_top=0.12, r_bot=0.15, jag=0.03, seed=11)
    f.upper()
    f.torso("leather", belt="dark_leather")
    f.neck_head("gob", eyes=False, r=0.1)
    eyes_glow(m, f, "gob_eye", dz=0.015)
    m.add("gob", cyl(0.025, 0.0, 0.07, 8), chain(T(0, f.head[1] - 0.01, f.head[2] + 0.09), R(math.pi / 2 - 0.3, 0, 0)))
    for sx in (-1, 1):
        m.add("gob", extrude([(0, -0.03), (0.16, 0.03), (0.02, 0.04)], 0.015), chain(T(sx * 0.09, f.head[1] + 0.01, f.head[2] - 0.01), R(0, 0 if sx > 0 else math.pi, 0.15)))
    for sx in (-1, 1):
        m.add("bone", cyl(0.007, 0.0, 0.03, 5), chain(T(sx * 0.025, f.head[1] - 0.06, f.head[2] + 0.085), R(0, 0, 0)))
    hr = f.arm("R", (-0.22, 0.62, 0.16), "gob", "gob", r0=0.038)
    m.push(A(hr, (-0.2, 1, 0.5)))  # scimitar
    m.add("leather", cyl(0.018, 0.018, 0.1, 8), T(0, -0.05, 0))
    m.add("iron", box(0.09, 0.02, 0.03), T(0, 0.05, 0))
    m.add("iron", extrude([(-0.02, 0), (0.025, 0), (0.06, 0.18), (0.035, 0.33), (0.0, 0.2)], 0.012), T(0, 0.06, 0))
    m.pop()
    f.arm("L", (0.2, 0.52, 0.12), "gob", "gob", r0=0.038)
    round_shield(m, (0.25, 0.53, 0.1), (1, 0, 0.6), r=0.14, face="wood", rim="leather", boss="iron")
    m.pop()
    f.done()


def kobold(m):
    f = Fig(m, s=0.66, hunch=0.15)
    m.materials.update(kob=mat("#b0592f"), kob_belly=mat("#d9a36b"), kob_eye=mat("#ffe060", emit=(0.4, 0.3, 0.0)))
    f.legs("kob", "kob", apart=0.075, stance=0.06, boot_top=0.1)
    m.add("kob", tube([(0, 0.4, -0.06), (0, 0.25, -0.2), (0.05, 0.08, -0.32), (0.12, 0.04, -0.4)], [0.06, 0.045, 0.025, 0.006], 10))
    f.upper()
    f.torso("kob_belly", belt="leather")
    f.neck_head("kob", eyes=False)
    m.add("kob", lathe([(0.06, 0.0), (0.05, 0.06), (0.035, 0.11), (0.0, 0.13)], 14), chain(T(0, f.head[1] - 0.01, f.head[2] + 0.04), R(math.pi / 2, 0, 0), S(1, 1, 0.8)))
    eyes_glow(m, f, "kob_eye", dz=0.0)
    for side in ("R", "L"):
        horns(m, f.head + ((-1 if side == "R" else 1) * 0.04, 0.05, -0.04), side, "bone", length=0.08, curl=0.5)
    m.add("kob", lathe([(0.0, 0.0), (0.03, 0.01), (0.0, 0.08)], 6, -math.pi / 2, math.pi / 2), chain(T(0, f.head[1] + 0.06, f.head[2] - 0.06), R(-0.8, 0, 0)))
    hr = f.arm("R", (-0.17, 0.52, 0.16), "kob", "kob", r0=0.035)
    hl = f.arm("L", (0.1, 0.62, 0.2), "kob", "kob", r0=0.035)
    d = hl - hr
    m.add("wood", cyl(0.014, 0.014, 0.8, 8), A(hr - d / np.linalg.norm(d) * 0.3, d))
    m.add("iron", lathe([(0.0, 0.0), (0.025, 0.02), (0.0, 0.11)], 4), A(hr + d / np.linalg.norm(d) * 0.5, d))
    m.pop()
    f.done()


def bandit(m):
    f = Fig(m, hunch=0.05)
    m.materials.update(bandana=mat("#7a1f1f"), jerkin=mat("#5a4632"), trousers=mat("#3e3a33"))
    f.legs("trousers", "dark_leather", stance=0.08, boot_top=0.22)
    f.upper()
    f.torso("jerkin", belt="leather")
    skirt(m, f, "jerkin", top=0.47, bottom=0.34, r_top=0.11, r_bot=0.14, jag=0.015, seed=8)
    m.add("bandana", tube([(-0.1, 0.65, 0.06), (0.0, 0.58, 0.1), (0.1, 0.65, 0.06)], 0.016, 6))
    f.neck_head("skin")
    hair_cap(m, f, "hair_brown", back=0.015)
    m.add("bandana", lathe([(0.0, 0.03)] + [(0.092 * math.cos(a), 0.092 * math.sin(a) + 0.01) for a in np.linspace(0.2, math.pi / 2, 5)][::-1] + [(0.094, 0.0)], 18, 0, 2 * math.pi),
          T(*(f.head + (0, 0.02, 0))))
    m.add("bandana", lathe([(0.07, -0.065), (0.09, -0.03), (0.088, -0.005)], 18, 0.35 - math.pi, math.pi - 0.35), chain(T(*f.head), R(0, math.pi / 2, 0)))
    m.add("bandana", tube([f.head + (0, 0.04, -0.09), f.head + (0.02, -0.02, -0.12), f.head + (0.03, -0.08, -0.12)], [0.014, 0.012, 0.004], 6))
    hr = f.arm("R", (-0.22, 0.56, 0.16), "jerkin", "dark_leather")
    m.push(A(hr, (-0.25, 0.5, 1)))
    m.add("leather", cyl(0.016, 0.016, 0.1, 8), T(0, -0.05, 0))
    m.add("iron", box(0.08, 0.018, 0.03), T(0, 0.05, 0))
    m.add("steel", extrude([(-0.02, 0), (0.02, 0), (0.05, 0.2), (0.03, 0.36), (-0.005, 0.22)], 0.012), T(0, 0.06, 0))
    m.pop()
    f.arm("L", (0.2, 0.5, 0.12), "jerkin", "dark_leather")
    m.add("leather", cyl(0.06, 0.05, 0.1, 12), chain(T(0.13, 0.42, 0.04), R(0, 0, 0.3)))  # coin purse
    m.pop()
    f.done()


def skeleton(m):
    f = Fig(m, s=1.0)
    m.materials.update(rust=mat("#8a5a3a", metal=0.4, rough=0.7), socket=mat("#140f0c"))
    for sx in (-1, 1):
        x = sx * 0.065
        hip, ankle = (x, 0.42, 0), (x * 1.2, 0.04, sx * -0.05)
        knee = bend(hip, ankle, (0, 0, 0.03), 0)
        limb(m, "bone", [hip, knee, ankle], 0.02, 0.016)
        m.add("bone", sphere(0.03, 10, 6), T(*knee))
        m.add("bone", sphere(1, 10, 6), chain(T(x * 1.2, 0.02, sx * -0.05 + 0.035), S(0.035, 0.022, 0.06)))
    m.add("bone", lathe([(0.0, 0.36), (0.09, 0.38), (0.11, 0.42), (0.09, 0.46), (0.0, 0.45)], 16), S(1, 1, 0.7))
    m.add("bone", tube([(0, 0.44, -0.03), (0, 0.55, -0.045), (0, 0.72, -0.02)], 0.02, 8))
    for k in range(5):
        y = 0.5 + k * 0.045
        w = 0.1 - abs(k - 2.5) * 0.008
        pts = [(w * math.cos(a), y - 0.012 * math.sin(a), 0.07 * math.sin(a) - 0.01) for a in np.linspace(-math.pi * 0.05, math.pi * 1.05, 9)]
        pts = [(x, y_, -z) for x, y_, z in pts] + [(x, y_, z * 0.0 + 0.06 * math.sin(math.pi * i / 8)) for i, (x, y_, z) in enumerate(pts)][::-1][1:]
        m.add("bone", tube(pts, 0.011, 6))
    m.add("bone", tube([(-0.13, 0.69, 0.0), (0.0, 0.7, 0.02), (0.13, 0.69, 0.0)], 0.014, 6))
    m.add("bone", sphere(1, 18, 12), chain(T(*(f.head + (0, 0.01, 0))), S(0.08, 0.085, 0.09)))
    m.add("bone", box(0.09, 0.04, 0.06), T(*(f.head + (0, -0.06, 0.03))))
    for sx in (-1, 1):
        m.add("socket", sphere(0.022, 10, 6), T(*(f.head + (sx * 0.03, 0.01, 0.07))))
    m.add("socket", lathe([(0.0, 0.0), (0.01, 0.0), (0.0, 0.02)], 3), chain(T(*(f.head + (0, -0.025, 0.083))), R(0, 0, 0)))
    for side, hand in (("R", (-0.2, 0.6, 0.15)), ("L", (0.2, 0.52, 0.1))):
        sh = f.sh[side] * (0.9, 1, 1)
        el = bend(sh, hand, (-0.05 if side == "R" else 0.05, 0, -0.03))
        limb(m, "bone", [sh, el, hand], 0.018, 0.014)
        m.add("bone", sphere(0.028, 10, 6), T(*sh))
        m.add("bone", sphere(1, 8, 6), chain(T(*hand), S(0.03, 0.04, 0.025)))
    sword(m, np.array((-0.2, 0.6, 0.15)), (-0.1, 1, 0.5), length=0.38, blade="rust", hilt="dark_leather", guard="iron")
    round_shield(m, (0.24, 0.52, 0.1), (1, 0, 0.6), r=0.14, face="wood", rim="rust", boss="rust")
    helmet(m, f, "rust", r=0.09, nasal=False)
    f.done()


def zombie(m):
    f = Fig(m, hunch=0.28)
    m.materials.update(rot=mat("#7d9168"), shirt=mat("#7a7062"), trousers=mat("#40453c"), blood=mat("#5a1414", rough=0.4))
    f.legs("trousers", "rot", apart=0.075, stance=0.1, boot_top=0.09)
    f.upper()
    f.torso("shirt")
    skirt(m, f, "shirt", top=0.47, bottom=0.34, r_top=0.11, r_bot=0.135, jag=0.035, seed=21)
    m.add("rot", sphere(1, 10, 6), chain(T(0.04, 0.53, 0.09), S(0.04, 0.05, 0.02)))
    m.add("blood", sphere(1, 8, 6), chain(T(-0.04, 0.6, 0.095), S(0.025, 0.035, 0.012)))
    m.push(chain(T(0, 0.7, 0), R(0.25, 0, 0.25), T(0, -0.7, 0)))
    f.neck_head("rot", eyes=False)
    hair_cap(m, f, "hair_brown", back=0.03)
    m.add("eye", sphere(0.015, 8, 5), T(*(f.head + (-0.03, 0.01, 0.078))))
    m.add("cloth_white", sphere(0.013, 8, 5), T(*(f.head + (0.03, 0.005, 0.08))))
    m.add("eye", box(0.06, 0.02, 0.02), T(*(f.head + (0, -0.045, 0.075))))
    m.pop()
    f.arm("R", (-0.12, 0.66, 0.38), "shirt", "rot", elbow=(-0.15, 0.66, 0.16))
    f.arm("L", (0.13, 0.6, 0.36), "shirt", "rot", elbow=(0.17, 0.62, 0.15))
    for side, hand in (("R", (-0.12, 0.66, 0.38)), ("L", (0.13, 0.6, 0.36))):
        for k in range(3):
            m.add("rot", tube([np.add(hand, (-0.02 + 0.02 * k, 0, 0.02)), np.add(hand, (-0.02 + 0.02 * k, -0.03, 0.06))], [0.009, 0.006], 5))
    m.pop()
    f.done()


def orc(m):
    f = Fig(m, s=1.1, bulk=1.25, hunch=0.1)
    m.materials.update(orc=mat("#5e7a4a"), hide=mat("#5a4030", rough=1.0), tusk=mat("#efe6cc"), hair_black=mat("#1c1a18"))
    f.legs("hide", "dark_leather", apart=0.08, stance=0.08)
    skirt(m, f, "hide", top=0.47, bottom=0.27, r_top=0.12, r_bot=0.16, jag=0.03, seed=5)
    f.upper()
    f.torso("orc", belt="dark_leather", chest=0.14)
    m.add("leather", tube([(0.13, 0.66, 0.05), (0.0, 0.55, 0.1), (-0.12, 0.44, 0.06)], 0.02, 6))
    for side in ("R", "L"):
        pauldron(m, f, side, "iron")
    f.neck_head("orc", eyes=False, r=0.088)
    eyes_glow(m, f, "blood_eye", dz=0.005)
    m.blob("orc", "ell", T(*(f.head + (0, 0.022, 0.066))), r=(0.07, 0.016, 0.026), blend=0.012)  # heavy brow
    m.add("orc", sphere(1, 12, 8), chain(T(*(f.head + (0, -0.05, 0.04))), S(0.07, 0.04, 0.06)))
    for sx in (-1, 1):
        m.add("tusk", lathe([(0.012, 0.0), (0.008, 0.03), (0.0, 0.05)], 8), chain(T(*(f.head + (sx * 0.035, -0.06, 0.085))), R(-0.3, 0, -sx * 0.2)))
        m.add("orc", extrude([(0, 0), (0.06, 0.02), (0.0, 0.035)], 0.012), chain(T(*(f.head + (sx * 0.085, 0.01, -0.01))), R(0, 0 if sx > 0 else math.pi, 0.25)))
    m.add("hair_black", tube([f.head + (0, 0.085, -0.02), f.head + (0, 0.13, -0.05), f.head + (0, 0.08, -0.13), f.head + (0, -0.02, -0.14)], [0.025, 0.03, 0.02, 0.01], 8))
    hr = f.arm("R", (-0.24, 0.78, 0.1), "orc", "orc", elbow=(-0.3, 0.64, -0.02), r0=0.05, fist=0.045)
    axe(m, hr, (-0.25, 1, 0.5), haft=0.55, double=False, head="iron", grip=0.12)
    f.arm("L", (0.22, 0.5, 0.12), "orc", "orc", r0=0.05, fist=0.045)
    m.pop()
    f.done()


def ogre(m):
    f = Fig(m, s=1.0, bulk=1.45, hunch=0.15)
    m.materials.update(ogre=mat("#a07a5a"), loin=mat("#5a4a30", rough=1.0), tusk=mat("#efe6cc"))
    f.legs("ogre", "ogre", apart=0.1, stance=0.05, boot_top=0.08)
    skirt(m, f, "loin", top=0.47, bottom=0.27, r_top=0.12, r_bot=0.15, jag=0.03, seed=9)
    f.upper()
    f.torso("ogre", belt="rope", chest=0.14)
    m.add("ogre", sphere(1, 18, 12), chain(T(0, 0.5, 0.05), S(0.17, 0.14, 0.13)))  # belly
    f.neck_head("ogre", r=0.08)
    m.add("ogre", sphere(1, 12, 8), chain(T(*(f.head + (0, -0.055, 0.035))), S(0.08, 0.045, 0.065)))
    for sx in (-1, 1):
        m.add("tusk", lathe([(0.01, 0.0), (0.006, 0.02), (0.0, 0.035)], 8), chain(T(*(f.head + (sx * 0.03, -0.06, 0.08))), R(-0.2, 0, -sx * 0.1)))
    hr = f.arm("R", (-0.28, 0.42, 0.12), "ogre", "ogre", r0=0.06, fist=0.055)
    m.add("wood", tube([hr - (0, 0.1, 0), hr + (0.0, 0.15, 0.12), hr + (0.02, 0.4, 0.22)], [0.03, 0.05, 0.075], 12))
    for k in range(5):
        m.add("iron", cyl(0.012, 0.0, 0.04, 5), chain(T(*(hr + (0.02, 0.33, 0.2))), R(0, k * 1.25, 1.2), T(0, 0.05, 0)))
    f.arm("L", (0.27, 0.45, 0.08), "ogre", "ogre", r0=0.06, fist=0.055)
    m.pop()
    f.done()


# ---------------- more props ----------------

@head_part
def long_hair(m, fig, material, length=0.22, style="loose"):
    """Hair past the shoulders: loose, a bun or a ponytail."""
    h = fig.head
    hair_cap(m, fig, material, back=0.01, low=-0.5)
    if style == "bun":
        m.blob(material, "ell", T(*(h + (0, 0.05, -0.085))), r=(0.04, 0.038, 0.038), blend=0.012)
    elif style == "ponytail":
        m.blob(material, "cone", a=h + (0, 0.04, -0.085), b=h + (0, -0.16, -0.13), r1=0.026, r2=0.01, blend=0.012)
    else:
        m.blob(material, "cone", a=h + (0, 0.0, -0.045), b=h + (0, -length, -0.075), r1=0.074, r2=0.062, blend=0.02)
        for sx in (-1, 1):
            m.blob(material, "cone", a=h + (sx * 0.07, 0.0, -0.01), b=h + (sx * 0.085, -length * 0.75, -0.03), r1=0.022, r2=0.016, blend=0.02)
        strands(m, material, h + (0, -length * 0.85, -0.075), 0.06, np.random.default_rng(5), az_skip=1.6, els=(-0.3,), length=0.05, down=0.9, n_az=14)


def mug(m, at, material="wood"):
    m.add(material, cyl(0.026, 0.024, 0.065, 12), T(*(np.asarray(at) + (0, -0.02, 0.0))))
    m.add("cloth_white", sphere(1, 10, 6), chain(T(*(np.asarray(at) + (0, 0.045, 0))), S(0.027, 0.012, 0.027)))
    m.add("iron", torus(0.026, 0.004, 12, 4), T(*(np.asarray(at) + (0, 0.03, 0))))


def spear(m, hand, direction, length=0.95, grip=0.4, tip="steel"):
    m.push(A(hand, direction))
    m.add("wood", cyl(0.012, 0.012, length, 8), T(0, -grip, 0))
    m.add(tip, lathe([(0.0, 0.0), (0.022, 0.03), (0.0, 0.13)], 4), T(0, length - grip, 0))
    m.pop()


def hammer(m, hand, direction, haft=0.32, grip=0.06):
    m.push(A(hand, direction))
    m.add("wood", cyl(0.014, 0.013, haft, 8), T(0, -grip, 0))
    m.add("iron", box(0.11, 0.05, 0.05), T(0, haft - grip, 0))
    m.pop()


def pitchfork(m, hand, direction, length=0.95, grip=0.4):
    m.push(A(hand, direction))
    m.add("wood", cyl(0.012, 0.012, length, 8), T(0, -grip, 0))
    top = length - grip
    m.add("iron", box(0.09, 0.012, 0.012), T(0, top, 0))
    for x in (-0.04, 0.0, 0.04):
        m.add("iron", cyl(0.006, 0.0, 0.13, 6), T(x, top, 0))
    m.pop()


@head_part
def tricorn(m, fig, material, trim="gold", feather=None):
    h = fig.head + (0, 0.055, 0)
    brim = 0.15
    def fold(V):
        d = V - h
        r = np.hypot(d[:, 0], d[:, 2])
        phi = np.arctan2(d[:, 2], d[:, 0]) - math.pi / 2
        up = 0.05 * np.clip(r / brim, 0, 1) ** 2 * (0.75 - 0.25 * np.cos(3 * phi))
        return V + np.c_[np.zeros(len(V)), up, np.zeros(len(V))]
    m.add(material, lathe([(0.0, 0.0), (brim, 0.0), (brim, 0.012), (0.09, 0.02), (0.085, 0.07), (0.06, 0.09), (0.0, 0.095)], 30), T(*h), deform=fold)
    m.add(trim, lathe([(brim * 1.005, 0.004), (brim * 1.01, 0.008), (brim * 1.005, 0.014), (brim * 0.99, 0.012)], 30), T(*h), deform=fold)
    if feather:
        m.add(feather, tube([h + (0.07, 0.06, -0.04), h + (0.13, 0.12, -0.1), h + (0.15, 0.17, -0.2)], [0.016, 0.022, 0.003], 8))


def potion(m, at, liquid):
    at = np.asarray(at)
    m.add("glass", lathe([(0.0, 0.0), (0.022, 0.004), (0.026, 0.03), (0.01, 0.05), (0.009, 0.07), (0.0, 0.07)], 10), T(*(at + (0, -0.015, 0))))
    m.add(liquid, sphere(0.02, 10, 6), T(*(at + (0, 0.005, 0))))
    m.add("wood", cyl(0.01, 0.011, 0.018, 6), T(*(at + (0, 0.055, 0))))


@head_part
def pointed_ears(m, fig, material, length=0.07):
    for sx in (-1, 1):
        m.add(material, extrude([(0, -0.02), (length, 0.035), (0.0, 0.015)], 0.01),
              chain(T(*(fig.head + (sx * 0.075, 0.0, -0.01))), R(0, 0 if sx > 0 else math.pi, 0.3)))


def apron(m, material, top=0.56, bottom=0.18, width=0.15):
    tabard(m, material, back=False, width=width, top=top, bottom=bottom, depth=0.085)
    m.add(material, lathe([(0.1, 0.47), (0.104, 0.475), (0.104, 0.49), (0.1, 0.495)], 24), S(1, 1, 0.78))


# ---------------- NPCs and enemies ----------------

def innkeeper(m):
    f = Fig(m, bulk=1.3)
    m.materials.update(shirt=mat("#d8cfb8"), trousers=mat("#4a3b2c"))
    f.legs("trousers", "dark_leather", stance=0.03)
    f.upper()
    f.torso("shirt", belt="leather")
    m.blob("shirt", "ell", T(0, 0.5, 0.05), r=(0.11, 0.1, 0.08), blend=0.03)  # belly
    apron(m, "cloth_white", top=0.6, bottom=0.2, width=0.17)
    f.neck_head("skin")
    beard(m, f, "hair_brown", length=0.03, width=0.045)
    for sx in (-1, 1):
        m.blob("hair_brown", "ell", T(*(f.head + (sx * 0.068, 0.0, -0.02))), r=(0.02, 0.035, 0.05), blend=0.01)
    f.arm("R", (-0.19, 0.6, 0.15), "shirt", "skin", elbow=(-0.23, 0.53, 0.02))
    mug(m, (-0.19, 0.64, 0.17))
    f.arm("L", (0.2, 0.47, 0.1), "shirt", "skin")
    m.add("cloth_white", box(0.04, 0.09, 0.012), chain(T(0.21, 0.41, 0.1), R(0, 0, 0.2)))
    m.pop()
    f.done()


def blacksmith(m):
    f = Fig(m, bulk=1.25)
    m.materials.update(trousers=mat("#3e3a33"))
    f.legs("trousers", "dark_leather", stance=0.06)
    f.upper()
    f.torso("skin", belt="dark_leather", chest=0.135)
    apron(m, "leather", top=0.64, bottom=0.16, width=0.17)
    for sx in (-1, 1):
        m.add("leather", tube([(sx * 0.07, 0.64, 0.088), (sx * 0.06, 0.7, 0.0), (sx * 0.05, 0.62, -0.08)], 0.01, 6))
    f.neck_head("skin")
    beard(m, f, "hair_black", length=0.1, width=0.055)
    hair_cap(m, f, "hair_black", back=0.02)
    hr = f.arm("R", (-0.17, 0.8, 0.08), "skin", "skin", elbow=(-0.26, 0.66, 0.0), r0=0.048, fist=0.042)
    hammer(m, hr, (0.3, 0.6, 0.6))
    f.arm("L", (0.2, 0.47, 0.12), "skin", "dark_leather", r0=0.048, fist=0.042)
    m.add("iron", box(0.03, 0.12, 0.015), chain(T(0.21, 0.41, 0.13), R(0.2, 0, 0)))  # tongs
    m.pop()
    f.done()


def noble(m):
    f = Fig(m)
    m.materials.update(velvet=mat("#5a2a6b"), cape_red=mat("#7a1f24", double=True), fur_white=mat("#ece6dc", rough=1.0), hose=mat("#2a2a33"))
    f.legs("hose", "dark_leather", stance=0.04, boot_top=0.22)
    f.upper()
    cape(m, "cape_red", r_top=0.12, r_bot=0.24, length=0.66, spread=1.3)
    m.add("fur_white", torus(0.11, 0.035, 22, 7), chain(T(0, 0.68, -0.01), S(1.1, 0.7, 0.85)))
    f.torso("velvet", belt="gold")
    skirt(m, f, "velvet", top=0.47, bottom=0.34, r_top=0.11, r_bot=0.135)
    f.neck_head("skin")
    hair_cap(m, f, "hair_brown", back=0.02)
    beard(m, f, "hair_brown", length=0.05, width=0.04)
    m.add("gold", torus(0.084, 0.006, 24, 4), T(*(f.head + (0, 0.04, -0.005))))
    hr = f.arm("R", (-0.2, 0.5, 0.15), "velvet", "skin")
    sword(m, hr, (-0.3, -0.2, 1), length=0.42, width=0.022)
    f.arm("L", (0.12, 0.47, 0.06), "velvet", "skin", elbow=(0.2, 0.5, -0.03))
    m.pop()
    f.done()


def town_guard(m):
    f = Fig(m, bulk=1.05)
    m.materials.update(chain_mail=mat("#8d929a", metal=0.7, rough=0.55), livery=mat("#2a5a3a"))
    f.legs("dark_leather", "leather", stance=0.02, boot_top=0.2)
    f.upper()
    f.torso("chain_mail", belt="leather")
    tabard(m, "livery", trim="gold", width=0.15, top=0.6, bottom=0.2, depth=0.095)
    f.neck_head("skin")
    helmet(m, f, "iron", nasal=False)
    m.add("iron", lathe([(0.14, 0.0), (0.14, 0.008), (0.09, 0.015)], 24), T(*(f.head + (0, 0.02, 0))))  # kettle brim
    beard(m, f, "hair_brown", length=0.03, width=0.04)
    hr = f.arm("R", (-0.2, 0.55, 0.12), "chain_mail", "leather", elbow=(-0.24, 0.5, 0.0))
    spear(m, hr, (0, 1, 0.05), length=1.05, grip=0.45)
    f.arm("L", (0.2, 0.5, 0.12), "chain_mail", "leather")
    round_shield(m, (0.25, 0.5, 0.1), (1, 0, 0.6), r=0.14, face="livery", rim="iron", boss="iron")
    m.pop()
    f.done()


def farmer(m):
    f = Fig(m, hunch=0.05)
    m.materials.update(overalls=mat("#4d5a6b"), shirt=mat("#a8462e"), straw=mat("#d6b86a", rough=1.0))
    f.legs("overalls", "dark_leather", stance=0.05, boot_top=0.14)
    f.upper()
    f.torso("shirt")
    m.add("overalls", box(0.12, 0.13, 0.01), T(0, 0.5, 0.075))
    for sx in (-1, 1):
        m.add("overalls", tube([(sx * 0.045, 0.56, 0.078), (sx * 0.06, 0.68, 0.03), (sx * 0.05, 0.6, -0.075)], 0.008, 5))
    m.blob("overalls", "ell", T(0, 0.43, 0), r=(0.115, 0.06, 0.08), blend=0.02)
    f.neck_head("skin")
    hair_cap(m, f, "hair_brown", back=0.02)
    hh = f.head + (0, 0.06, 0)
    m.add("straw", lathe([(0.0, 0.0), (0.17, -0.01), (0.175, 0.0), (0.085, 0.015), (0.08, 0.06), (0.06, 0.075), (0.0, 0.078)], 26), T(*hh))
    hr = f.arm("R", (-0.17, 0.55, 0.14), "shirt", "skin", elbow=(-0.22, 0.52, 0.02))
    pitchfork(m, hr, (0.05, 1, 0.1), length=1.0, grip=0.42)
    f.arm("L", (0.2, 0.45, 0.1), "shirt", "skin")
    m.pop()
    f.done()


def cultist(m):
    f = Fig(m, hunch=0.08)
    m.materials.update(cult_robe=mat("#5a1414"), cult_trim=mat("#1a1a1a"), sigil=mat("#f0c040", emit=(0.5, 0.35, 0.05)))
    f.robe("cult_robe", r=0.19, hem="cult_trim")
    f.upper()
    f.torso("cult_robe", belt="rope")
    f.neck_head("skin")
    hood(m, f, "cult_robe", tip=0.06)
    m.add("sigil", extrude([(0.03 * math.cos(a), 0.03 * math.sin(a)) for a in np.linspace(math.pi / 2, math.pi / 2 + 4 * math.pi, 5, endpoint=False)], 0.006), T(0, 0.57, 0.08))
    hr = f.arm("R", (-0.06, 0.76, 0.2), "cult_robe", "skin", elbow=(-0.2, 0.68, 0.08))
    sword(m, hr, (0.1, 1, 0.2), length=0.17, width=0.03, blade="steel", guard="iron", hilt="bone")
    f.arm("L", (0.08, 0.72, 0.2), "cult_robe", "skin", elbow=(0.2, 0.66, 0.08))
    m.pop()
    f.done()


def necromancer(m):
    f = Fig(m, hunch=0.06)
    m.materials.update(necro_robe=mat("#1e2a22"), necro_trim=mat("#3c5a3a"), soul=mat("#7dff9a", emit=(0.2, 0.9, 0.35)))
    f.robe("necro_robe", r=0.2, hem="necro_trim")
    f.upper()
    f.torso("necro_robe", belt="bone")
    cape(m, "necro_trim", r_top=0.12, r_bot=0.24, length=0.66, spread=1.3)
    for side in ("R", "L"):
        pauldron(m, f, side, "bone")
    f.neck_head("skin")
    hood(m, f, "necro_robe", tip=0.05)
    eyes_glow(m, f, "soul")
    beard(m, f, "hair_white", length=0.18, width=0.05)
    hr = f.arm("R", (-0.2, 0.6, 0.12), "necro_robe", "skin", elbow=(-0.24, 0.5, 0.0))
    top = staff(m, hr, length=1.05, top_frac=0.47, material="dark_leather", seed=4)
    m.add("bone", sphere(1, 12, 8), chain(T(*(top + (0, 0.04, 0))), S(0.045, 0.05, 0.05)))
    for sx in (-1, 1):
        m.add("soul", sphere(0.01, 6, 4), T(*(top + (sx * 0.017, 0.045, 0.04))))
    f.arm("L", (0.18, 0.66, 0.2), "necro_robe", "skin", elbow=(0.22, 0.56, 0.05))
    m.add("soul", sphere(0.04, 12, 8), T(0.18, 0.74, 0.21))
    m.pop()
    f.done()


def hobgoblin(m):
    f = Fig(m, s=1.02, bulk=1.1)
    m.materials.update(hob=mat("#b0562e"), hob_armor=mat("#5a3a2a", metal=0.4, rough=0.5), hair_black=mat("#1c1a18"), hob_eye=mat("#ffd23a", emit=(0.5, 0.35, 0.0)))
    f.legs("dark_leather", "hob_armor", stance=0.06, boot_top=0.22)
    skirt(m, f, "hob_armor", top=0.47, bottom=0.3, r_top=0.115, r_bot=0.145)
    f.upper()
    f.torso("hob_armor", belt="leather")
    for side in ("R", "L"):
        pauldron(m, f, side, "hob_armor", trim="iron")
    f.neck_head("hob", eyes=False)
    eyes_glow(m, f, "hob_eye")
    pointed_ears(m, f, "hob", length=0.06)
    m.add("hair_black", tube([f.head + (0, 0.085, -0.03), f.head + (0, 0.12, -0.08), f.head + (0, 0.06, -0.12)], [0.02, 0.022, 0.008], 8))
    hr = f.arm("R", (-0.22, 0.55, 0.15), "hob_armor", "hob")
    sword(m, hr, (-0.2, 1, 0.5), length=0.44, guard="iron")
    f.arm("L", (0.2, 0.5, 0.12), "hob_armor", "hob")
    kite_shield(m, (0.25, 0.48, 0.1), (1, 0, 0.6), face="hob_armor", trim="iron")
    m.pop()
    f.done()


def gnoll(m):
    f = Fig(m, s=1.1, hunch=0.22)
    m.materials.update(gnoll=mat("#b39a6a", rough=1.0), mane=mat("#3a2e22", rough=1.0), nose=mat("#1a1512", rough=0.4), gnoll_eye=mat("#ff5a1a", emit=(0.6, 0.15, 0.0)))
    f.legs("gnoll", "gnoll", apart=0.08, stance=0.08, boot_top=0.06)
    skirt(m, f, "leather", top=0.47, bottom=0.3, r_top=0.12, r_bot=0.15, jag=0.03, seed=13)
    f.upper()
    f.torso("gnoll", belt="dark_leather")
    f.neck_head("gnoll", eyes=False)
    eyes_glow(m, f, "gnoll_eye", dz=-0.005)
    m.blob("gnoll", "ell", T(*(f.head + (0, -0.03, 0.09))), r=(0.04, 0.038, 0.07), blend=0.02)
    m.add("nose", sphere(0.014, 8, 6), T(*(f.head + (0, -0.015, 0.16))))
    for sx in (-1, 1):
        m.add("gnoll", extrude([(0, 0), (0.045, 0.06), (0.03, 0.0)], 0.01), chain(T(*(f.head + (sx * 0.05, 0.06, -0.01))), R(0, 0 if sx > 0 else math.pi, 0.2)))
    strands(m, "mane", f.head + (0, 0.02, -0.05), 0.07, np.random.default_rng(9), az_skip=1.8, els=np.linspace(1.2, -0.8, 6), length=0.07, down=0.4)
    hr = f.arm("R", (-0.2, 0.58, 0.16), "gnoll", "gnoll")
    spear(m, hr, (-0.1, 0.4, 1), length=1.0, grip=0.5, tip="iron")
    f.arm("L", (0.18, 0.55, 0.2), "gnoll", "gnoll")
    m.pop()
    f.done()


def pirate(m):
    f = Fig(m, hunch=0.04)
    m.materials.update(stripe=mat("#e8e0d0"), pants=mat("#3a3a4a"), sash_red=mat("#9a2020"), hat_black=mat("#1e1c1c"))
    f.legs("pants", "dark_leather", stance=0.08, boot_top=0.24)
    f.upper()
    f.torso("stripe")
    m.add("sash_red", lathe([(0.104, 0.42), (0.114, 0.43), (0.114, 0.47), (0.104, 0.48)], 24), S(1, 1, 0.78))
    m.add("sash_red", tube([(0.07, 0.45, 0.08), (0.09, 0.38, 0.09), (0.1, 0.32, 0.07)], [0.016, 0.018, 0.01], 6))
    f.neck_head("skin")
    beard(m, f, "hair_black", length=0.1, width=0.05)
    m.add("hat_black", lathe([(0.0, 0.0), (0.03, 0.002), (0.026, 0.006), (0.0, 0.008)], 10), chain(T(*(f.head + (-0.03, 0.002, 0.08))), R(math.pi / 2, 0, 0)))  # eyepatch
    m.add("hat_black", torus(0.088, 0.003, 20, 3), chain(T(*(f.head + (0, 0.015, 0))), R(0.25, 0, 0)))
    tricorn(m, f, "hat_black")
    hr = f.arm("R", (-0.22, 0.6, 0.17), "stripe", "skin")
    m.push(A(hr, (-0.2, 0.7, 1)))  # cutlass
    m.add("leather", cyl(0.016, 0.016, 0.1, 8), T(0, -0.05, 0))
    m.add("gold", torus(0.03, 0.005, 10, 4), chain(T(0, 0.0, 0.02), R(math.pi / 2, 0, 0)))
    m.add("steel", extrude([(-0.02, 0), (0.02, 0), (0.05, 0.22), (0.03, 0.38), (-0.005, 0.24)], 0.012), T(0, 0.06, 0))
    m.pop()
    f.arm("L", (0.2, 0.48, 0.12), "stripe", "skin")
    m.pop()
    f.done()


def barmaid(m):
    f = Fig(m, female=True)
    m.materials.update(dress=mat("#3f5a7a"), bodice=mat("#5a3a2a"), blouse=mat("#e8e0d0"), hair_red=mat("#8a3a1a", rough=0.9))
    f.robe("dress", r=0.18, boots="dark_leather")
    f.upper()
    f.torso("blouse")
    m.blob("bodice", "ell", T(0, 0.49, 0.004), r=(0.087, 0.07, 0.066), blend=0.03)
    apron(m, "cloth_white", top=0.46, bottom=0.1, width=0.16)
    f.neck_head("skin")
    long_hair(m, f, "hair_red", style="bun")
    f.arm("R", (-0.17, 0.64, 0.15), "blouse", "skin", elbow=(-0.22, 0.55, 0.02))
    mug(m, (-0.17, 0.68, 0.17))
    f.arm("L", (0.17, 0.64, 0.15), "blouse", "skin", elbow=(0.22, 0.55, 0.02))
    mug(m, (0.17, 0.68, 0.17))
    m.pop()
    f.done()


def noblewoman(m):
    f = Fig(m, female=True)
    m.materials.update(gown=mat("#2a6b5a"), gown_trim=mat("#d9a838", metal=0.7, rough=0.3), hair_blonde=mat("#d8b870", rough=0.9), pearl=mat("#f0ece4", rough=0.2))
    f.robe("gown", r=0.23, hem="gown_trim", top=0.47)
    f.upper()
    f.torso("gown", belt="gown_trim")
    f.neck_head("skin")
    long_hair(m, f, "hair_blonde", length=0.2)
    m.add("gold", lathe([(0.075, 0.0), (0.08, 0.004), (0.08, 0.016), (0.075, 0.012)], 24), T(*(f.head + (0, 0.055, -0.005))))
    for a in np.linspace(-1.0, 1.0, 5):
        m.add("pearl", sphere(0.007, 6, 4), T(*(f.head + (0.08 * math.sin(a), 0.075 + 0.01 * math.cos(a * 2), 0.08 * math.cos(a) - 0.005))))
    for k in range(9):
        a = -1.3 + k * 0.33
        m.add("pearl", sphere(0.007, 6, 4), T(0.055 * math.sin(a), 0.66 - 0.03 * math.cos(a), 0.05 * math.cos(a) + 0.02))
    f.arm("R", (-0.1, 0.5, 0.13), "gown", "skin", elbow=(-0.18, 0.52, 0.02))
    f.arm("L", (0.19, 0.66, 0.12), "gown", "skin", elbow=(0.22, 0.54, 0.03))
    m.add("gown_trim", extrude([(0, 0)] + [(0.08 * math.cos(a), 0.08 * math.sin(a)) for a in np.linspace(0.3, 1.9, 8)], 0.005), chain(T(0.19, 0.69, 0.13), R(0, -0.4, 0)))  # fan
    m.pop()
    f.done()


def merchant(m):
    f = Fig(m, female=True, bulk=1.08)
    m.materials.update(robe_ochre=mat("#b5832e"), wrap=mat("#2e6a6a"), coin=mat("#e0b040", metal=0.9, rough=0.3))
    f.robe("robe_ochre", r=0.19, hem="wrap")
    f.upper()
    f.torso("robe_ochre", belt="leather")
    m.add("wrap", tube([(-0.11, 0.66, 0.05), (0.0, 0.58, 0.1), (0.11, 0.48, 0.07)], 0.02, 6))
    f.neck_head("skin_dark")
    hh = f.head
    m.blob("wrap", "ell", T(*(hh + (0, 0.035, -0.012))), r=(0.088, 0.075, 0.094), clip=(hh[1] + 0.005, 2.0))
    m.blob("wrap", "ell", T(*(hh + (0, 0.09, -0.02))), r=(0.07, 0.04, 0.075), blend=0.02)
    m.blob("wrap", "cone", a=hh + (0, 0.0, -0.06), b=hh + (0, -0.16, -0.09), r1=0.06, r2=0.075, blend=0.02)
    f.arm("R", (-0.16, 0.56, 0.18), "robe_ochre", "skin_dark", elbow=(-0.22, 0.52, 0.04))
    book(m, (-0.13, 0.58, 0.2), (0.4, 1, 0.6), cover="leather")
    f.arm("L", (0.19, 0.5, 0.12), "robe_ochre", "skin_dark")
    m.add("leather", lathe([(0.0, 0.0), (0.035, 0.01), (0.04, 0.04), (0.015, 0.06), (0.02, 0.07), (0.0, 0.07)], 12), T(0.2, 0.37, 0.12))
    for k in range(4):
        m.add("coin", cyl(0.012, 0.012, 0.004, 10), chain(T(0.2 + 0.01 * k, 0.45 + 0.004 * k, 0.15), R(0.6, 0, 0.3)))
    m.pop()
    f.done()


def guard_captain(m):
    f = Fig(m, female=True, bulk=1.05)
    m.materials.update(plate=mat("#c4c9d0", metal=0.9, rough=0.3), cape_blue=mat("#24387a", double=True), hair_black=mat("#1c1a18"))
    f.legs("plate", "plate", stance=0.05, boot_top=0.24)
    skirt(m, f, "plate", top=0.47, bottom=0.32, r_top=0.115, r_bot=0.145)
    f.upper()
    cape(m, "cape_blue", r_top=0.12, r_bot=0.25, length=0.66, spread=1.2, flutter=0.2)
    f.torso("plate", belt="leather")
    for side in ("R", "L"):
        pauldron(m, f, side, "plate", trim="gold")
    f.neck_head("skin")
    long_hair(m, f, "hair_black", style="ponytail")
    hr = f.arm("R", (-0.2, 0.62, 0.15), "plate", "plate", elbow=(-0.25, 0.55, 0.02))
    sword(m, hr, (-0.15, 1, 0.3), length=0.46)
    f.arm("L", (0.14, 0.44, 0.12), "plate", "plate", elbow=(0.22, 0.52, 0.0))
    m.pop()
    f.done()


def priestess(m):
    f = Fig(m, female=True)
    m.materials.update(vestment=mat("#ece6d6"), stole=mat("#8a6a2a"), sun=mat("#ffd25a", metal=0.6, rough=0.3, emit=(0.3, 0.22, 0.03)), hair_brown_l=mat("#6a4a30", rough=0.9))
    f.robe("vestment", r=0.2, hem="gold")
    f.upper()
    f.torso("vestment", belt="gold")
    for sx in (-1, 1):
        m.add("stole", box(0.03, 0.4, 0.008), chain(T(sx * 0.04, 0.42, 0.085), R(-0.12, 0, 0)))
    f.neck_head("skin")
    long_hair(m, f, "hair_brown_l", length=0.24)
    m.add("gold", torus(0.084, 0.005, 24, 4), T(*(f.head + (0, 0.035, -0.005))))
    hr = f.arm("R", (-0.2, 0.62, 0.1), "vestment", "skin", elbow=(-0.24, 0.52, 0.0))
    top = staff(m, hr, length=1.08, top_frac=0.46, material="gold", wobble=0.0)
    m.add("sun", cyl(0.06, 0.06, 0.012, 16), chain(T(*(top + (0, 0.06, 0))), R(math.pi / 2, 0, 0), T(0, -0.006, 0)))
    for k in range(8):
        m.add("sun", box(0.012, 0.05, 0.01), chain(T(*(top + (0, 0.06, 0))), R(0, 0, k * math.pi / 4), T(0, 0.085, 0)))
    f.arm("L", (0.08, 0.6, 0.16), "vestment", "skin", elbow=(0.2, 0.56, 0.06))
    m.pop()
    f.done()


def witch(m):
    f = Fig(m, female=True, hunch=0.12)
    m.materials.update(witch_robe=mat("#2a3a2a"), witch_hat=mat("#1e1e24"), brew=mat("#8aff5a", emit=(0.3, 0.8, 0.1)), glass=mat("#cfe6e0", rough=0.1), hair_grey=mat("#9a9a96", rough=0.9))
    f.robe("witch_robe", r=0.19, hem="witch_hat")
    f.upper()
    f.torso("witch_robe", belt="rope")
    cape(m, "witch_hat", r_top=0.12, r_bot=0.22, length=0.6, spread=1.3, flutter=0.3)
    f.neck_head("skin")
    m.blob("skin", "cone", a=f.head + (0, -0.01, 0.09), b=f.head + (0, -0.04, 0.125), r1=0.01, r2=0.005, blend=0.006)  # long nose
    long_hair(m, f, "hair_grey", length=0.26)
    pointy_hat(m, f, "witch_hat", band="leather", brim=0.19, height=0.34, droop=1.4)
    hr = f.arm("R", (-0.19, 0.62, 0.17), "witch_robe", "skin", elbow=(-0.24, 0.54, 0.04))
    potion(m, hr + (0, 0.04, 0), "brew")
    f.arm("L", (0.18, 0.5, 0.14), "witch_robe", "skin")
    staff(m, (0.18, 0.5, 0.14), length=1.0, top_frac=0.5, seed=12)
    m.pop()
    f.done()


def vampire(m):
    f = Fig(m, female=True)
    m.materials.update(pale=mat("#e6dcd6"), gown_black=mat("#16121a"), cape_crimson=mat("#6a0a14", double=True), blood_eye=mat("#ff2a2a", emit=(0.8, 0.05, 0.05)), hair_black=mat("#1c1a18"))
    f.robe("gown_black", r=0.2, hem="cape_crimson")
    f.upper()
    cape(m, "cape_crimson", r_top=0.12, r_bot=0.27, length=0.7, spread=1.35, flutter=0.3)
    m.add("cape_crimson", lathe([(0.12, 0.66), (0.13, 0.74), (0.16, 0.88), (0.17, 0.9)], 24, math.pi * 1.1, math.pi * 1.9), S(1, 1, 0.9))
    f.torso("gown_black", belt="gold")
    f.neck_head("pale", eyes=False, lips="blood_eye")
    eyes_glow(m, f, "blood_eye")
    long_hair(m, f, "hair_black", length=0.26)
    f.arm("R", (-0.17, 0.82, 0.16), "gown_black", "pale", elbow=(-0.25, 0.68, 0.06))
    for k in range(4):
        m.add("pale", cyl(0.004, 0.0, 0.035, 5), chain(T(-0.18 + 0.01 * k, 0.85, 0.17), R(0.3, 0, 0)))
    f.arm("L", (0.2, 0.5, 0.12), "gown_black", "pale")
    m.pop()
    f.done()


def assassin(m):
    f = Fig(m, female=True, hunch=0.12)
    m.materials.update(shadow=mat("#24242c"), mask=mat("#3a1a24"), hair_black=mat("#1c1a18"))
    f.legs("shadow", "dark_leather", apart=0.08, stance=0.1, boot_top=0.26)
    f.upper()
    f.torso("shadow", belt="leather")
    m.add("leather", tube([(0.1, 0.66, 0.05), (0.0, 0.55, 0.09), (-0.1, 0.44, 0.06)], 0.01, 6))
    for k in range(4):
        m.add("steel", lathe([(0.0, 0.0), (0.01, 0.02), (0.0, 0.06)], 4), chain(T(-0.05 + k * 0.03, 0.5 - k * 0.03 + 0.08, 0.09), R(0, 0, 0.9)))
    f.neck_head("skin")
    m.add("mask", lathe([(0.07, -0.065), (0.09, -0.03), (0.088, -0.003)], 18, 0.3 - math.pi, math.pi - 0.3), chain(T(*f.head), R(0, math.pi / 2, 0)))
    long_hair(m, f, "hair_black", style="ponytail")
    for side, hand, d in (("R", (-0.22, 0.46, 0.2), (-0.1, -0.5, 1)), ("L", (0.18, 0.62, 0.2), (0.2, -0.6, 1))):
        h = f.arm(side, hand, "shadow", "dark_leather")
        sword(m, np.asarray(h), d, length=0.22, width=0.03, hilt="dark_leather", guard="iron")
    m.pop()
    f.done()


def drow(m):
    f = Fig(m, female=True)
    m.materials.update(drow=mat("#4a3e5e"), drow_armor=mat("#1e1a2a", metal=0.6, rough=0.4), webbing=mat("#a070d0", metal=0.5, rough=0.3), drow_eye=mat("#ff4a6a", emit=(0.7, 0.1, 0.2)))
    f.legs("drow_armor", "drow_armor", stance=0.07, boot_top=0.28)
    f.upper()
    cape(m, "drow_armor", r_top=0.12, r_bot=0.23, length=0.62, spread=1.2, flutter=0.4)
    f.torso("drow_armor", belt="webbing")
    skirt(m, f, "drow_armor", top=0.47, bottom=0.33, r_top=0.11, r_bot=0.14, jag=0.02, seed=4)
    for side in ("R", "L"):
        pauldron(m, f, side, "drow_armor", trim="webbing")
    f.neck_head("drow", eyes=False, lips="drow_armor")
    eyes_glow(m, f, "drow_eye")
    pointed_ears(m, f, "drow", length=0.08)
    long_hair(m, f, "hair_white", length=0.28)
    for side, hand, d in (("R", (-0.22, 0.52, 0.17), (-0.3, 0.2, 1)), ("L", (0.2, 0.6, 0.15), (0.3, 1, 0.4))):
        h = f.arm(side, hand, "drow_armor", "drow")
        m.push(A(np.asarray(h), d))
        m.add("dark_leather", cyl(0.015, 0.015, 0.09, 8), T(0, -0.045, 0))
        m.add("webbing", box(0.07, 0.015, 0.025), T(0, 0.05, 0))
        m.add("webbing", extrude([(-0.015, 0), (0.015, 0), (0.045, 0.2), (0.025, 0.34), (-0.005, 0.2)], 0.01), T(0, 0.055, 0))
        m.pop()
    m.pop()
    f.done()


def pirate_captain(m):
    f = Fig(m, female=True)
    m.materials.update(coat=mat("#6a1a1e"), blouse=mat("#e8e0d0"), pants=mat("#2a2a33"), hat_black=mat("#1e1c1c"), feather=mat("#f2efe6"), hair_brown_l=mat("#5a3a22", rough=0.9))
    f.legs("pants", "dark_leather", stance=0.07, boot_top=0.26)
    f.upper()
    f.torso("blouse", belt="leather")
    skirt(m, f, "coat", top=0.5, bottom=0.18, r_top=0.135, r_bot=0.17)
    for sx in (-1, 1):  # open coat front panels
        m.blob("coat", "ell", T(sx * 0.07, 0.58, 0.0), r=(0.055, 0.11, 0.08), blend=0.02)
    f.neck_head("skin")
    long_hair(m, f, "hair_brown_l", length=0.22)
    tricorn(m, f, "hat_black", feather="feather")
    hr = f.arm("R", (-0.22, 0.62, 0.17), "coat", "skin")
    m.push(A(hr, (-0.2, 0.8, 1)))
    m.add("leather", cyl(0.016, 0.016, 0.1, 8), T(0, -0.05, 0))
    m.add("gold", torus(0.03, 0.005, 10, 4), chain(T(0, 0.0, 0.02), R(math.pi / 2, 0, 0)))
    m.add("steel", extrude([(-0.02, 0), (0.02, 0), (0.05, 0.22), (0.03, 0.38), (-0.005, 0.24)], 0.012), T(0, 0.06, 0))
    m.pop()
    hl = f.arm("L", (0.18, 0.6, 0.2), "coat", "skin", elbow=(0.22, 0.54, 0.04))
    m.push(A(hl, (0.1, 0.1, 1)))  # flintlock pistol
    m.add("wood", box(0.025, 0.06, 0.03), T(0, -0.01, -0.01))
    m.add("iron", cyl(0.008, 0.008, 0.13, 8), chain(T(0, 0.02, 0.0), R(math.pi / 2, 0, 0), T(0, 0, 0)))
    m.pop()
    m.pop()
    f.done()


# ---------------- Wild Shape beasts ----------------
# Ids match the beasts in scripts/data/monsters.gd: Wild Shape sets the druid's mini to the beast id.

def quad(m, hide, length=0.5, sh_h=0.3, hip_h=0.29, girth=0.085, chest=1.2, haunch=1.0, leg=0.026, paw=0.032,
         stride=0.05, neck=(0.0, 0.07, 0.09), head_r=(0.05, 0.05, 0.06), snout=0.07, snout_r=0.028, nose="nose",
         hind_bend=1.0, front_len=1.0, front_x=0.6):
    """A four-legged animal facing +Z mid-stride on the base. Returns anchor points for the details."""
    B = BASE_H
    zs, zh = length * 0.33, -length * 0.33
    Sh, Hp = np.array((0, B + sh_h, zs)), np.array((0, B + hip_h, zh))
    m.blob(hide, "cone", a=Hp, b=Sh, r1=girth * haunch, r2=girth * chest * 0.95)
    m.blob(hide, "ell", T(*(Sh + (0, -0.005, 0.02))), r=(girth * chest * 0.9, girth * chest * 1.05, girth * chest), blend=0.04)
    m.blob(hide, "ell", T(*(Hp + (0, 0.005, -0.01))), r=(girth * haunch * 0.95, girth * haunch, girth * haunch * 1.05), blend=0.04)
    m.blob(hide, "ell", T(0, B + (sh_h + hip_h) / 2 - girth * 0.35, 0), r=(girth * 0.8, girth * 0.7, length * 0.28), blend=0.05)
    for sx in (-1, 1):
        x, f = sx * girth * front_x, stride * sx  # diagonal gait: one front leg forward, the other hind leg back
        top = np.array((x, Sh[1] - girth * 0.45, zs + 0.01))
        wrist = np.array((x * 0.95, B + 0.05 * front_len, zs + f + 0.01))
        elbow = np.array((x * 1.05, top[1] - (top[1] - wrist[1]) * 0.5, zs - 0.02 + f * 0.4))
        limb(m, hide, [top, elbow, wrist], leg * 1.7, leg)
        m.blob(hide, "ell", T(*(wrist + (0, -0.03, 0.012))), r=(paw * 0.9, paw * 0.6, paw * 1.25), blend=0.015)
        m.blob(hide, "ell", T(*(top + (0, 0.02, 0.0))), r=(girth * 0.42, girth * 0.7, girth * 0.55), blend=0.03)  # shoulder blade
        x = sx * girth * 0.6
        top = np.array((x, Hp[1] - girth * 0.25, zh - 0.01))
        knee = np.array((x * 1.05, B + hip_h * 0.55, zh + 0.06 * hind_bend - f * 0.4))
        hock = np.array((x, B + hip_h * 0.28, zh - 0.05 * hind_bend - f))
        foot = np.array((x * 0.95, B + 0.03, zh - 0.025 - f))
        m.blob(hide, "ell", T(*(top + (0, -0.03, 0.02))), r=(girth * 0.5, girth * 0.95, girth * 0.8), blend=0.03)  # thigh
        limb(m, hide, [top, knee, hock, foot], leg * 2.0, leg * 0.9)
        m.blob(hide, "ell", T(*(foot + (0, -0.005, 0.02))), r=(paw * 0.85, paw * 0.55, paw * 1.2), blend=0.015)
    head = Sh + neck
    m.blob(hide, "cone", a=Sh + (0, 0.01, 0.01), b=head, r1=girth * 0.75, r2=head_r[0] * 0.85, blend=0.03)
    m.blob(hide, "ell", T(*head), r=head_r, blend=0.025)
    tip = head + (0, -head_r[1] * 0.3, head_r[2] * 0.7 + snout)
    if snout > 0:
        m.blob(hide, "cone", a=head + (0, -head_r[1] * 0.1, head_r[2] * 0.3), b=tip, r1=head_r[0] * 0.65, r2=snout_r, blend=0.025)
    if nose:
        m.add(nose, sphere(snout_r * 0.45, 10, 8), chain(T(*(tip + (0, snout_r * 0.35, snout_r * 0.75))), S(1.2, 0.8, 1)))
    for sx in (-1, 1):
        m.add("eye", sphere(0.0085, 8, 6), T(*(head + (sx * head_r[0] * 0.55, head_r[1] * 0.3, head_r[2] * 0.72))))
    return dict(S=Sh, H=Hp, head=head, tip=tip, girth=girth)


def tail(m, material, root, pts, r0, r1):
    limb(m, material, [np.asarray(root, float)] + [np.asarray(root, float) + p for p in pts], r0, r1)


def pointed_ear(m, material, head, sx, r=0.05, size=0.04, back=0.0):
    a = head + (sx * r * 0.55, r * 0.6, -back)
    m.blob(material, "cone", a=a, b=a + (sx * size * 0.35, size, -size * 0.15), r1=size * 0.38, r2=0.003, blend=0.01)


def round_ear(m, material, head, sx, r=0.06, size=0.022):
    m.blob(material, "ell", T(*(head + (sx * r * 0.7, r * 0.75, -r * 0.2))), r=(size, size, size * 0.5), blend=0.01)


def ruff(m, material, at, girth, rng, n=16, length=0.05):
    """Shaggy fur clumps around the neck and chest, sculpted into the body."""
    for k in range(n):
        a = rng.uniform(-2.4, 2.4)
        el = rng.uniform(-0.9, 0.6)
        d = np.array((math.sin(a) * math.cos(el), math.sin(el), math.cos(a) * math.cos(el)))
        v = d * 0.4 + np.array((0, -0.5, -0.5))
        m.blob(material, "ell", A(at + d * girth * 0.8, v, d), r=(girth * 0.28, length * rng.uniform(0.8, 1.2), girth * 0.16), blend=0.012)


def wolf(m, fur="wolf_fur", pale="wolf_pale", big=1.0):
    m.materials.setdefault(fur, mat("#5d5850", rough=1.0))
    m.materials.setdefault(pale, mat("#b5ac9c", rough=1.0))
    m.materials["nose"] = mat("#141210", rough=0.35)
    g = 0.078 * big
    a = quad(m, fur, length=0.52 * big, sh_h=0.3 * big, hip_h=0.285 * big, girth=g, chest=1.25, haunch=0.95, leg=0.022 * big,
             paw=0.03 * big, neck=(0, 0.06 * big, 0.1 * big), head_r=(0.048 * big, 0.05 * big, 0.06 * big), snout=0.07 * big, snout_r=0.022 * big)
    m.blob(pale, "ell", T(*(a["S"] + (0, -g * 0.55, g * 0.7))), r=(g * 0.7, g * 0.8, g * 0.5), blend=0.03)  # pale chest
    m.blob(pale, "ell", T(*(a["head"] + (0, -0.032 * big, 0.04 * big))), r=(0.026 * big, 0.016 * big, 0.05 * big), blend=0.025)  # pale jaw
    for sx in (-1, 1):
        pointed_ear(m, fur, a["head"], sx, r=0.05 * big, size=0.045 * big, back=0.02 * big)
    ruff(m, fur, a["S"] + (0, 0.04 * big, 0.06 * big), g * 1.05, np.random.default_rng(3), length=0.055 * big)
    tail(m, fur, a["H"] + (0, 0.02, -g * 0.8), [(0, -0.05 * big, -0.09 * big), (0.02, -0.14 * big, -0.14 * big), (0.04, -0.2 * big, -0.15 * big)], 0.03 * big, 0.022 * big)


def dire_wolf(m):
    m.materials["dire_fur"] = mat("#4a4440", rough=1.0)
    m.materials["dire_pale"] = mat("#8f857a", rough=1.0)
    wolf(m, "dire_fur", "dire_pale", big=1.2)


def bear(m, fur, muzzle, big=1.0):
    m.materials["nose"] = mat("#141210", rough=0.35)
    g = 0.12 * big
    a = quad(m, fur, length=0.48 * big, sh_h=0.3 * big, hip_h=0.27 * big, girth=g, chest=1.15, haunch=1.05, leg=0.036 * big,
             paw=0.042 * big, stride=0.04, neck=(0, 0.02 * big, 0.11 * big), head_r=(0.065 * big, 0.06 * big, 0.065 * big),
             snout=0.05 * big, snout_r=0.03 * big, hind_bend=0.6)
    m.blob(fur, "ell", T(*(a["S"] + (0, g * 0.55, -0.02))), r=(g * 0.7, g * 0.45, g * 0.7), blend=0.06)  # shoulder hump
    m.blob(muzzle, "ell", T(*(a["head"] + (0, -0.02 * big, 0.08 * big))), r=(0.034 * big, 0.03 * big, 0.045 * big), blend=0.02)
    for sx in (-1, 1):
        round_ear(m, fur, a["head"], sx, r=0.065 * big, size=0.022 * big)
    ruff(m, fur, a["S"] + (0, 0.0, 0.04), g * 0.95, np.random.default_rng(5), length=0.05 * big)
    m.blob(fur, "ell", T(*(a["H"] + (0, 0.02, -g * 0.9))), r=(0.025, 0.022, 0.025), blend=0.02)  # stub tail


def black_bear(m):
    m.materials["black_bear_fur"] = mat("#24201d", rough=1.0)
    m.materials["muzzle_tan"] = mat("#8a6a4a", rough=0.9)
    bear(m, "black_bear_fur", "muzzle_tan")


def brown_bear(m):
    m.materials["brown_bear_fur"] = mat("#6b4a2e", rough=1.0)
    m.materials["muzzle_brown"] = mat("#8f6d4c", rough=0.9)
    bear(m, "brown_bear_fur", "muzzle_brown", big=1.18)


def panther(m):
    m.materials["panther_fur"] = mat("#1f1e24", rough=0.7)
    m.materials["cat_eye"] = mat("#d8c040", emit=(0.35, 0.3, 0.05))
    m.materials["nose"] = mat("#141210", rough=0.35)
    g = 0.07
    a = quad(m, "panther_fur", length=0.56, sh_h=0.26, hip_h=0.27, girth=g, chest=1.15, haunch=1.0, leg=0.021, paw=0.03,
             stride=0.07, neck=(0, 0.035, 0.09), head_r=(0.045, 0.04, 0.045), snout=0.022, snout_r=0.024, hind_bend=1.2)
    for sx in (-1, 1):
        round_ear(m, "panther_fur", a["head"] + (0, 0, 0.0), sx, r=0.05, size=0.016)
        m.add("cat_eye", sphere(0.009, 8, 6), T(*(a["head"] + (sx * 0.025, 0.014, 0.034))))
    tail(m, "panther_fur", a["H"] + (0, 0.0, -g * 0.85),
         [(0, -0.07, -0.05), (0.02, -0.15, -0.08), (0.04, -0.19, -0.05), (0.07, -0.18, 0.02)], 0.017, 0.013)


def boar(m):
    m.materials["boar_fur"] = mat("#4e3d30", rough=1.0)
    m.materials["snout"] = mat("#8a6a62", rough=0.6)
    m.materials["tusk"] = mat("#efe6cc", rough=0.4)
    g = 0.105
    a = quad(m, "boar_fur", length=0.46, sh_h=0.25, hip_h=0.23, girth=g, chest=1.15, haunch=0.95, leg=0.018, paw=0.022,
             stride=0.04, neck=(0, -0.01, 0.1), head_r=(0.055, 0.06, 0.07), snout=0.07, snout_r=0.034, nose="snout", hind_bend=0.7)
    rng = np.random.default_rng(11)
    for k in range(26):  # bristly ridge along the spine
        z = np.interp(k, (0, 25), (a["H"][2], a["head"][2] - 0.02))
        y = np.interp(z, (a["H"][2], a["S"][2]), (a["H"][1], a["S"][1])) + g * 0.95
        m.add("boar_fur", cyl(0.012, 0.0, rng.uniform(0.03, 0.05), 5), A((rng.uniform(-0.01, 0.01), y - 0.01, z), (0, 1, -0.5)))
    for sx in (-1, 1):
        pointed_ear(m, "boar_fur", a["head"], sx, r=0.06, size=0.035, back=0.02)
        root = a["tip"] + (sx * 0.025, -0.008, -0.03)
        m.add("tusk", tube([root, root + (sx * 0.012, 0.025, 0.012), root + (sx * 0.01, 0.045, -0.005)], [0.008, 0.006, 0.001], 8))
    tail(m, "boar_fur", a["H"] + (0, 0.04, -g * 0.85), [(0, -0.03, -0.02), (0, -0.07, -0.02)], 0.01, 0.006)


def ape(m):
    m.materials["ape_fur"] = mat("#33302d", rough=1.0)
    m.materials["skin_ape"] = mat("#4a3c34", rough=0.6)
    g = 0.085
    a = quad(m, "ape_fur", length=0.36, sh_h=0.37, hip_h=0.24, girth=g, chest=1.25, haunch=0.9, leg=0.034, paw=0.04,
             stride=0.03, neck=(0, 0.045, 0.07), head_r=(0.058, 0.062, 0.058), snout=0.0, nose=None, hind_bend=1.3, front_x=1.15)
    h = a["head"]
    m.blob("skin_ape", "ell", T(*(h + (0, -0.01, 0.045))), r=(0.042, 0.048, 0.03), blend=0.015)  # face
    m.blob("skin_ape", "ell", T(*(h + (0, -0.04, 0.06))), r=(0.034, 0.024, 0.026), blend=0.015)  # muzzle
    m.blob("ape_fur", "ell", T(*(h + (0, 0.035, 0.035))), r=(0.05, 0.016, 0.03), blend=0.015)  # brow
    m.blob("ape_fur", "ell", T(*(h + (0, 0.05, -0.02))), r=(0.03, 0.04, 0.045), blend=0.02)  # crest
    for sx in (-1, 1):
        m.blob("skin_ape", "ell", T(*(h + (sx * 0.06, 0.0, -0.005))), r=(0.008, 0.016, 0.013), blend=0.006)
        m.add("eye", sphere(0.008, 8, 6), T(*(h + (sx * 0.016, 0.018, 0.075))))


def crocodile(m):
    m.materials["croc_hide"] = mat("#3b4630", rough=0.8)
    m.materials["croc_belly"] = mat("#b0a77e", rough=0.7)
    m.materials["tooth"] = mat("#efe6cc", rough=0.4)
    B = BASE_H
    rng = np.random.default_rng(17)
    # spine as a gentle S-curve so the long body fits on the base
    zs = np.linspace(0.29, -0.4, 16)
    xs = 0.07 * np.sin(np.linspace(0.3, 3.4, 16)) * np.linspace(0.2, 1.6, 16)
    rs = np.interp(np.arange(16), (0, 2, 4, 8, 11, 15), (0.022, 0.035, 0.05, 0.07, 0.045, 0.01))
    hs = np.interp(np.arange(16), (0, 4, 8, 15), (0.035, 0.05, 0.06, 0.025))
    pts = [np.array((x, B + h, z)) for x, h, z in zip(xs, hs, zs)]
    for k in range(15):
        m.blob("croc_hide", "cone", a=pts[k], b=pts[k + 1], r1=rs[k] * 1.25, r2=rs[k + 1] * 1.25, blend=0.02)
    for k in range(4, 13):  # flat, wide body: squash with a belly that spreads sideways
        m.blob("croc_belly", "ell", T(*(pts[k] + (0, -rs[k] * 0.5, 0))), r=(rs[k] * 1.15, rs[k] * 0.45, 0.045), blend=0.02)
    for k in range(2, 15):  # scutes
        for sx in (-1, 1):
            m.add("croc_hide", box(0.008, 0.006, 0.012), T(*(pts[k] + (sx * rs[k] * 0.45, rs[k] * 1.15, 0))))
        if k > 8:
            m.add("croc_hide", box(0.003, 0.012, 0.014), T(*(pts[k] + (0, rs[k] * 1.25 + 0.006, 0))))
    jaw = pts[0] + (0, -0.006, 0.0)
    m.blob("croc_hide", "cone", a=pts[2], b=jaw + (0, 0, 0.1), r1=0.034, r2=0.016, blend=0.02)
    for sx in (-1, 1):
        m.blob("croc_hide", "ell", T(*(pts[2] + (sx * 0.022, 0.03, -0.01))), r=(0.012, 0.012, 0.016), blend=0.01)  # eye bumps
        m.add("eye", sphere(0.007, 8, 6), T(*(pts[2] + (sx * 0.028, 0.034, 0.0))))
        for k in range(7):
            m.add("tooth", cyl(0.003, 0.0, 0.01, 5), chain(T(*(jaw + (sx * 0.02, -0.006, 0.09 - k * 0.018))), R(math.pi, 0, 0)))
    for k, sx in ((4, -1), (4, 1), (10, -1), (10, 1)):  # sprawled legs
        hip = pts[k] + (sx * rs[k] * 0.9, -0.005, 0)
        elbow = hip + (sx * 0.06, 0.015, 0.02 if k == 4 else -0.02)
        foot = hip + (sx * 0.08, -hs[k] + 0.012, 0.05 if k == 4 else -0.04)
        limb(m, "croc_hide", [hip, elbow, foot], 0.022, 0.014)
        for t in (-0.4, 0, 0.4):
            m.add("croc_hide", cyl(0.006, 0.002, 0.025, 5), A(foot + (0, -0.006, 0), (math.sin(t) * sx, 0, math.cos(t) if k == 4 else -math.cos(t))))


def giant_spider(m):
    m.materials["spider_hide"] = mat("#2f2f3f", rough=0.6)
    m.materials["spider_mark"] = mat("#8a2a1f", rough=0.6)
    m.materials["spider_eye"] = mat("#ff3a1a", emit=(0.7, 0.08, 0.0))
    B = BASE_H
    ceph = np.array((0, B + 0.14, 0.09))
    abd = np.array((0, B + 0.19, -0.13))
    m.blob("spider_hide", "ell", T(*ceph), r=(0.075, 0.05, 0.09), blend=0.0)
    m.blob("spider_hide", "ell", T(*abd), r=(0.12, 0.11, 0.15), blend=0.015)
    m.blob("spider_hide", "cone", a=ceph - (0, 0, 0.06), b=abd + (0, -0.02, 0.1), r1=0.025, r2=0.03, blend=0.02)
    m.blob("spider_mark", "ell", T(*(abd + (0, 0.1, -0.02))), r=(0.04, 0.02, 0.07), blend=0.0)
    for sx in (-1, 1):
        for k, ang in enumerate((0.55, 0.15, -0.25, -0.65)):  # four legs a side, fanning from front to back
            root = ceph + (sx * 0.055, -0.005, 0.03 - k * 0.025)
            d = np.array((sx * math.cos(ang), 0, math.sin(ang)))
            knee = root + d * 0.12 + (0, 0.13 - 0.01 * k, 0)
            ankle = root + d * 0.29 + (0, 0.02, 0)
            foot = root + d * 0.34 + (0, B - root[1] + 0.008, 0)
            limb(m, "spider_hide", [root, knee, ankle, foot], 0.018, 0.006)
        for k in range(4):  # eyes in two rows
            m.add("spider_eye", sphere(0.011 - 0.002 * (k // 2), 8, 6), T(*(ceph + (sx * (0.015 + 0.016 * (k % 2)), 0.035 + 0.012 * (k // 2), 0.07 - 0.012 * (k // 2)))))
        fang = ceph + (sx * 0.02, -0.03, 0.08)
        m.add("bone", tube([fang, fang + (sx * 0.005, -0.03, 0.02), fang + (0, -0.05, 0.0)], [0.009, 0.006, 0.001], 8))
        m.blob("spider_hide", "cone", a=ceph + (sx * 0.03, -0.01, 0.07), b=ceph + (sx * 0.05, -0.04, 0.13), r1=0.012, r2=0.008, blend=0.01)  # pedipalps
    for k in range(20):  # bristles
        rng = np.random.default_rng(k)
        d = rng.normal(size=3); d[1] = abs(d[1]) + 0.3; d /= np.linalg.norm(d)
        m.add("spider_hide", cyl(0.004, 0.0, 0.025, 4), A(abd + d * np.array((0.12, 0.11, 0.15)), d))


def giant_eagle(m):
    m.materials["eagle_feather"] = mat("#5a3e25", rough=0.9)
    m.materials["feather_white"] = mat("#ece6da", rough=0.9)
    m.materials["beak"] = mat("#d9a830", rough=0.4)
    B = BASE_H
    body = np.array((0, B + 0.25, -0.01))
    head = np.array((0, B + 0.43, 0.08))
    m.blob("eagle_feather", "ell", A(body, (0, 1, -0.35)), r=(0.085, 0.13, 0.08))
    m.blob("eagle_feather", "ell", T(*(body + (0, 0.04, 0.05))), r=(0.075, 0.08, 0.06), blend=0.04)  # breast
    m.blob("feather_white", "cone", a=body + (0, 0.1, 0.03), b=head, r1=0.05, r2=0.045, blend=0.03)
    m.blob("feather_white", "ell", T(*head), r=(0.045, 0.045, 0.055), blend=0.02)
    hook = head + (0, -0.03, 0.09)
    m.blob("beak", "cone", a=head + (0, -0.005, 0.035), b=head + (0, -0.002, 0.075), r1=0.02, r2=0.014, blend=0.006)
    m.blob("beak", "cone", a=head + (0, -0.002, 0.075), b=hook, r1=0.014, r2=0.003, blend=0.006)
    for sx in (-1, 1):
        m.add("eye", sphere(0.008, 8, 6), T(*(head + (sx * 0.03, 0.012, 0.03))))
        m.blob("feather_white", "ell", T(*(head + (sx * 0.022, 0.022, 0.025))), r=(0.012, 0.007, 0.02), blend=0.006)  # brow
        hip = body + (sx * 0.045, -0.08, 0.0)
        foot = np.array((sx * 0.055, B + 0.012, 0.02))
        limb(m, "eagle_feather", [hip, hip + (0, -0.05, 0.01)], 0.032, 0.025)
        limb(m, "beak", [hip + (0, -0.05, 0.01), foot], 0.012, 0.01)
        for t in (-0.5, 0.0, 0.5, math.pi):  # talons
            d = (math.sin(t) * 0.6, 0, math.cos(t))
            m.add("beak", tube([foot, foot + np.array(d) * 0.035, foot + np.array(d) * 0.05 + (0, -0.008, 0)], [0.007, 0.005, 0.001], 6))
        # half-raised wings: a broad sculpted arm plus layered primary feathers
        sh = body + (sx * 0.07, 0.08, 0.0)
        wrist = sh + (sx * 0.15, 0.1, -0.06)
        tipw = wrist + (sx * 0.12, -0.04, -0.12)
        m.blob("eagle_feather", "cone", a=sh, b=wrist, r1=0.035, r2=0.022, blend=0.02)
        m.blob("eagle_feather", "ell", A((sh + wrist) / 2 + (0, -0.03, -0.03), wrist - sh, (0, 0, 1)), r=(0.012, 0.1, 0.07), blend=0.02)
        for k in range(9):
            t = k / 8
            root = wrist + (tipw - wrist) * t * 0.3 + (0, -0.01 * k, 0.01 * k - 0.02)
            d = np.array((sx * (0.6 - 0.5 * t), -0.25 - 0.7 * t, -0.6 + 0.2 * t))
            d /= np.linalg.norm(d)
            m.add("eagle_feather", extrude([(0, 0), (0.016, 0.03), (0.012, 0.15 - 0.03 * t), (0, 0.17 - 0.03 * t), (-0.008, 0.03)], 0.004),
                  A(root, d, (sx, 0.2, 0)))
    for k in range(7):  # tail fan
        a = (k - 3) * 0.16
        d = np.array((math.sin(a) * 0.5, -0.55, -0.9))
        m.add("feather_white", extrude([(0, 0), (0.016, 0.03), (0.014, 0.14), (0, 0.16), (-0.014, 0.14), (-0.016, 0.03)], 0.004),
              A(body + (0, -0.08, -0.08), d / np.linalg.norm(d), (0, 1, 0)))


def horse(m, coat="horse_coat", mane="horse_mane", big=1.0, stock=1.0, blanket=None):
    """Riding horse; `stock` > 1 makes it shorter-legged and heavier (pony), `blanket` adds a saddle cloth."""
    m.materials.setdefault(coat, mat("#7a4a2c", rough=0.8))
    m.materials.setdefault(mane, mat("#241a14", rough=1.0))
    m.materials["nose"] = mat("#2a201a", rough=0.5)
    m.materials["hoof"] = mat("#1c1814", rough=0.6)
    g = 0.086 * big * stock
    a = quad(m, coat, length=0.64 * big, sh_h=0.4 * big / stock, hip_h=0.395 * big / stock, girth=g, chest=1.15, haunch=1.1,
             leg=0.02 * big, paw=0.024 * big, stride=0.06 * big, neck=(0, 0.16 * big, 0.13 * big), head_r=(0.032 * big, 0.038 * big, 0.052 * big),
             snout=0.085 * big, snout_r=0.026 * big, nose="nose", hind_bend=0.8, front_x=0.55)
    for sx in (-1, 1):
        pointed_ear(m, coat, a["head"], sx, r=0.035 * big, size=0.03 * big, back=0.01 * big)
    rng = np.random.default_rng(7)
    for k in range(9):  # mane along the top of the neck
        t = k / 8.0
        at = a["S"] + (0, 0.03 * big, 0.0) + (np.array((0, 0.16, 0.12)) * big) * t
        m.blob(mane, "ell", A(at + (0, g * (0.6 - 0.25 * t), -0.012 * big), (0, -0.4, -1), (rng.uniform(-0.3, 0.3), 1, 0)),
               r=(0.012 * big, 0.03 * big, 0.022 * big), blend=0.012)
    m.blob(mane, "ell", T(*(a["head"] + (0, 0.04 * big, 0.02 * big))), r=(0.014 * big, 0.012 * big, 0.03 * big), blend=0.01)  # forelock
    tail(m, mane, a["H"] + (0, 0.02 * big, -g * 0.9), [(0, -0.03 * big, -0.06 * big), (0.01, -0.14 * big, -0.1 * big), (0.02, -0.28 * big, -0.1 * big)],
         0.024 * big, 0.016 * big)
    if blanket:
        back = (a["S"] + a["H"]) / 2 + (0, g * 0.92, 0.01)
        m.blob(blanket, "ell", T(*back), r=(g * 1.12, g * 0.28, g * 1.25), blend=0.01)
        m.blob("dark_leather", "ell", T(*(back + (0, g * 0.25, 0.0))), r=(g * 0.62, g * 0.2, g * 0.85), blend=0.01)


def riding_horse(m):
    horse(m, blanket="dark_leather")


def warhorse(m):
    m.materials["war_coat"] = mat("#2b2421", rough=0.7)
    m.materials["war_mane"] = mat("#0f0d0c", rough=1.0)
    horse(m, "war_coat", "war_mane", big=1.05, stock=1.06, blanket="team")


def pony(m):
    m.materials["pony_coat"] = mat("#a8814f", rough=0.85)
    m.materials["pony_mane"] = mat("#e2d6bd", rough=1.0)
    horse(m, "pony_coat", "pony_mane", big=0.95, stock=1.25, blanket="dark_leather")


def mastiff(m):
    m.materials["mastiff_fur"] = mat("#a07a4e", rough=1.0)
    m.materials["mastiff_dark"] = mat("#2a221c", rough=1.0)
    m.materials["nose"] = mat("#141210", rough=0.35)
    g = 0.08
    a = quad(m, "mastiff_fur", length=0.54, sh_h=0.32, hip_h=0.31, girth=g, chest=1.3, haunch=0.9, leg=0.024, paw=0.03,
             neck=(0, 0.06, 0.09), head_r=(0.05, 0.05, 0.055), snout=0.06, snout_r=0.03)
    m.blob("mastiff_dark", "ell", T(*(a["tip"] + (0, 0.0, -0.01))), r=(0.036, 0.03, 0.03), blend=0.02)  # dark muzzle
    for sx in (-1, 1):  # floppy ears
        m.blob("mastiff_dark", "ell", T(*(a["head"] + (sx * 0.055, 0.015, -0.01))), r=(0.012, 0.035, 0.025), blend=0.01)
    tail(m, "mastiff_fur", a["H"] + (0, 0.02, -g * 0.8), [(0, 0.02, -0.06), (0, -0.04, -0.11)], 0.018, 0.012)


BEASTS = {
    "wolf": wolf, "dire_wolf": dire_wolf, "black_bear": black_bear, "brown_bear": brown_bear, "panther": panther,
    "boar": boar, "ape": ape, "crocodile": crocodile, "giant_spider": giant_spider, "giant_eagle": giant_eagle,
    # mounts
    "riding_horse": riding_horse, "warhorse": warhorse, "pony": pony, "mastiff": mastiff,
}


NPCS = {
    "innkeeper": innkeeper, "blacksmith": blacksmith, "noble": noble, "town_guard": town_guard, "farmer": farmer,
    "cultist": cultist, "necromancer": necromancer, "hobgoblin": hobgoblin, "gnoll": gnoll, "pirate": pirate,
    "barmaid": barmaid, "noblewoman": noblewoman, "merchant": merchant, "guard_captain": guard_captain, "priestess": priestess,
    "witch": witch, "vampire": vampire, "assassin": assassin, "drow": drow, "pirate_captain": pirate_captain,
}


FIGURES = {
    # one per class
    "barbarian": barbarian, "bard": bard, "cleric": cleric, "druid": druid, "fighter": fighter, "monk": monk,
    "paladin": paladin, "ranger": ranger, "rogue": rogue, "sorcerer": sorcerer, "warlock": warlock, "wizard": wizard,
    # tropes (the monster ones match ids in scripts/data/monsters.gd)
    "knight": knight, "goblin": goblin, "kobold": kobold, "bandit": bandit, "skeleton": skeleton, "zombie": zombie,
    "orc": orc, "ogre": ogre,
    # NPCs and enemies (men first, then women)
    **NPCS,
    # Wild Shape beasts
    **BEASTS,
}


def build(name, detail):
    mk.DETAIL = detail
    mats = dict(COMMON)
    mats["blood_eye"] = mat("#ff3a1a", emit=(0.8, 0.1, 0.0))
    mats["fletch"] = mat("#c9c2b0")
    mats["crystal"] = mat("#9fd8ff", rough=0.15, emit=(0.2, 0.45, 0.7))
    m = mk.Model(mats)
    base(m)
    FIGURES[name](m)
    return m


def tuned(name):
    """Low-poly props at fixed detail; the sculpted bodies get the rest of TRI_TARGET."""
    m = build(name, LOWPOLY)
    m.finalize(TRI_TARGET - m.tris())
    assert TRI_MIN <= m.tris() <= TRI_MAX, f"{name}: {m.tris()} triangles"
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--previews", help="also render PNG previews (and a contact sheet) into this folder")
    ap.add_argument("names", nargs="*", default=list(FIGURES))
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    surface.write_textures(os.path.join(OUT, "textures"))
    shots = []
    for name in a.names:
        m = tuned(name)
        mk.write_glb(m, os.path.join(OUT, name + ".glb"), name)
        print(f"{name:10s} {m.tris():6d} triangles")
        if a.previews:
            os.makedirs(a.previews, exist_ok=True)
            im = mk.render(m)
            im.save(os.path.join(a.previews, name + ".png"))
            shots.append((name, im))
    if shots:
        from PIL import Image, ImageDraw
        cols = 5
        w, h = shots[0][1].size
        sheet = Image.new("RGB", (cols * w, -(-len(shots) // cols) * (h + 28)), (236, 232, 224))
        d = ImageDraw.Draw(sheet)
        for i, (name, im) in enumerate(shots):
            x, y = (i % cols) * w, (i // cols) * (h + 28)
            sheet.paste(im, (x, y))
            d.text((x + w // 2 - len(name) * 3, y + h + 8), name.capitalize(), fill=(40, 36, 30))
        sheet.save(os.path.join(a.previews, "contact_sheet.png"))


if __name__ == "__main__":
    main()
