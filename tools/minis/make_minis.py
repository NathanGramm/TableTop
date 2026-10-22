"""Generates the low-poly tabletop minifigures in assets/minis/ (one .glb per figure).

    python3 tools/minis/make_minis.py [--previews DIR]

Every figure stands on a round base (radius 0.42 = one 5-ft square) facing +Z. The base rim
uses a material named "team", which the board repaints with the token's team colour. Each model
is tuned to land near 20,000 triangles (15,000-25,000).
"""
import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import meshkit as mk
from meshkit import A, R, S, T, chain, box, cyl, extrude, lathe, sphere, torus, tube

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "minis")
BASE_H = 0.085
TRI_MIN, TRI_MAX, TRI_TARGET = 15000, 25000, 20000
LOWPOLY = 0.55  # segment multiplier: few sides per round shape, so facets show
SCULPT_BUDGET = 6500  # triangles for the sculpted bodies: big, clean facets; grass and pebbles on the base use the rest


def mat(color, metal=0.0, rough=0.7, **kw):
    c = tuple(int(color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    if "emit" not in kw:  # muted, painted-mini colours rather than toy-bright ones
        grey = sum(c) / 3
        c = tuple(grey + (x - grey) * 0.8 for x in c)
    return dict(color=tuple(x ** 2.2 for x in c), metal=metal, rough=rough, **kw)


COMMON = {
    "base": mat("#2b2b2e", rough=0.5),
    "team": mat("#8a8a8a", rough=0.4, metal=0.3),
    "ground": mat("#5b4a36", rough=0.95),
    "rock": mat("#8a8780", rough=0.9),
    "grass": mat("#5d7a34", rough=0.9),
    "grass_dry": mat("#9a8a4a", rough=0.9),
    "stone": mat("#77736b", rough=0.9),
    "stone_dark": mat("#5e5b55", rough=0.9),
    "eye": mat("#2a1d14", rough=0.2),
    "eye_white": mat("#e8e2d8", rough=0.3),
    "steel": mat("#b9bec6", metal=0.85, rough=0.3),
    "iron": mat("#6c6f75", metal=0.7, rough=0.5),
    "gold": mat("#d9a838", metal=0.9, rough=0.3),
    "leather": mat("#6b4428", rough=0.8),
    "dark_leather": mat("#3b2a1e", rough=0.8),
    "wood": mat("#7a5230", rough=0.85),
    "skin": mat("#e0ac84"),
    "skin_dark": mat("#8d5a3c"),
    "hair_brown": mat("#4a3020", rough=0.9),
    "hair_white": mat("#e8e4dc", rough=0.9),
    "cloth_white": mat("#e9e4d6"),
    "rope": mat("#b89a64", rough=0.9),
    "bone": mat("#e6dcc4", rough=0.6),
}


# ---------------- building blocks ----------------

def base(m, rng):
    """Bevelled round base with a team-coloured rim, a flagstone floor and a few rocks."""
    m.add("base", lathe([(0.0, 0.0), (0.41, 0.0), (0.42, 0.008), (0.42, 0.064), (0.405, 0.078), (0.0, 0.078)], 48))
    m.add("team", lathe([(0.4215, 0.018), (0.428, 0.022), (0.428, 0.05), (0.4215, 0.054)], 48))
    m.add("ground", lathe([(0.0, 0.077), (0.385, 0.077), (0.38, BASE_H), (0.0, BASE_H)], 40))
    cell, n = 0.075, 6
    grid = {(i, j): (i * cell + rng.uniform(-0.018, 0.018), j * cell + rng.uniform(-0.018, 0.018)) for i in range(-n, n + 2) for j in range(-n, n + 2)}
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            quad = np.array([grid[i, j], grid[i + 1, j], grid[i + 1, j + 1], grid[i, j + 1]])
            if np.linalg.norm(quad, axis=1).max() > 0.37 or rng.random() < 0.18:
                continue
            c = quad.mean(0)
            quad = c + (quad - c) * 0.88
            h = rng.uniform(0.004, 0.01)
            m.add(rng.choice(["stone", "stone_dark", "rock"]), extrude([(x, -z) for x, z in quad], h),
                  chain(T(c[0] * 0, BASE_H - 0.002 + h / 2, 0), R(-math.pi / 2 + rng.uniform(-0.03, 0.03), 0, rng.uniform(-0.03, 0.03))))
    for _ in range(3):
        a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0.24, 0.34)
        s = rng.uniform(0.022, 0.04)
        m.add("rock", sphere(1, 6, 4), chain(T(d * math.cos(a), BASE_H + 0.004, d * math.sin(a)), R(rng.uniform(0, 3), rng.uniform(0, 3), 0), S(s, s * 0.7, s * 1.2)))


def base_fill(m, rng, budget):
    """Spend leftover triangles on grass tufts and pebbles around the rim."""
    while budget > 30:
        a, d = rng.uniform(0, 2 * math.pi), rng.uniform(0.2, 0.37)
        x, z = d * math.cos(a), d * math.sin(a)
        before = m.tris()
        if rng.random() < 0.75:
            for k in range(int(rng.integers(3, 6))):
                lean = R(rng.uniform(-0.5, 0.5), 0, rng.uniform(-0.5, 0.5))
                m.add("grass" if rng.random() < 0.7 else "grass_dry", cyl(0.006, 0.0, rng.uniform(0.025, 0.055), 3), chain(T(x + rng.uniform(-0.01, 0.01), BASE_H, z + rng.uniform(-0.01, 0.01)), lean))
        else:
            s_ = rng.uniform(0.006, 0.014)
            m.add("rock", sphere(1, 5, 3), chain(T(x, BASE_H + 0.004, z), R(rng.uniform(0, 3), rng.uniform(0, 3), 0), S(s_, s_ * 0.7, s_)))
        budget -= m.tris() - before


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

    def __init__(self, m, s=1.0, bulk=1.0, hunch=0.0):
        self.m, self.s, self.bulk, self.hunch = m, s, bulk, hunch
        m.push(chain(T(0, BASE_H, 0), S(s)))
        self.shoulder_y = 0.655
        self.sh = {"R": np.array((-0.145 * bulk, self.shoulder_y, 0.0)), "L": np.array((0.145 * bulk, self.shoulder_y, 0.0))}
        self.head = np.array((0.0, 0.80, 0.005))

    def done(self):
        self.m.pop()

    def upper(self):
        """Enter the (possibly hunched) upper-body frame."""
        self.m.push(chain(T(0, 0.42, 0), R(self.hunch, 0, 0), T(0, -0.42, 0)))

    def legs(self, pants, boots, apart=0.068, stance=0.0, boot_top=0.17):
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
        m.blob(pants, "ell", T(0, 0.43, -0.005), r=(0.118 * b, 0.075, 0.082 * b), blend=0.03)

    def robe(self, material, r=0.19, top=0.47, boots="dark_leather", hem=None):
        m = self.m
        prof = [(0.0, 0.0), (r, 0.0), (r * 0.94, 0.08), (r * 0.76, 0.25), (0.115 * self.bulk, top), (0.0, top + 0.01)]
        m.add(material, lathe(prof, 40), S(1, 1, 0.85), deform=folds(0.06, 11, BASE_H + top * self.s))
        if hem:
            m.add(hem, lathe([(r * 1.012, 0.0), (r * 1.017, 0.0), (r * 0.99, 0.04), (r * 0.98, 0.04)], 40), S(1, 1, 0.85), deform=folds(0.06, 11, BASE_H + top * self.s))
        for sx in (-1, 1):
            m.blob(boots, "ell", T(sx * 0.06, 0.02, r * 0.8), r=(0.035, 0.024, 0.06))

    def torso(self, material, belt=None, chest=0.13, collar=None):
        m, b = self.m, self.bulk
        c = chest / 0.13
        m.blob(material, "ell", T(0, 0.6, 0), r=(0.122 * b * c, 0.085, 0.074 * b), blend=0.0)
        for sx in (-1, 1):
            m.blob(material, "ell", T(sx * 0.05 * b, 0.6, 0.048 * b), r=(0.052 * b, 0.036, 0.03), blend=0.02)
            m.blob(material, "cone", a=(sx * 0.03, 0.695, -0.012), b=(sx * 0.125 * b, 0.665, -0.004), r1=0.03, r2=0.034, blend=0.03)
            m.blob(material, "ell", T(sx * 0.06 * b, 0.585, -0.045 * b), r=(0.05 * b, 0.07, 0.03), blend=0.03)
        m.blob(material, "ell", T(0, 0.495, 0.006), r=(0.097 * b, 0.095, 0.066 * b), blend=0.045)
        m.blob(material, "ell", T(0, 0.43, -0.004), r=(0.108 * b, 0.065, 0.074 * b), blend=0.035)
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

    def neck_head(self, skin, eyes=True, r=0.085):
        """Sculpted head: cranium, jaw, cheekbones, brow, nose, lips and ears."""
        m, h, k = self.m, self.head, r / 0.085
        m.blob(skin, "cone", a=(0, 0.655, -0.004), b=(0, 0.76, -0.01), r1=0.038, r2=0.034, blend=0.02)
        m.push(chain(T(*h), S(k)))
        m.blob(skin, "ell", T(0, 0.012, -0.01), r=(0.074, 0.084, 0.086))
        m.blob(skin, "ell", T(0, -0.032, 0.022), r=(0.058, 0.056, 0.058), blend=0.025)
        m.blob(skin, "ell", T(0, -0.068, 0.05), r=(0.026, 0.02, 0.02), blend=0.016)
        for sx in (-1, 1):
            m.blob(skin, "ell", T(sx * 0.04, -0.008, 0.055), r=(0.026, 0.018, 0.02), blend=0.014)
            m.blob(skin, "ell", R(0, sx * 0.25, 0) @ T(sx * 0.074, -0.006, -0.004), r=(0.01, 0.026, 0.017), blend=0.008)
        m.blob(skin, "ell", T(0, 0.02, 0.066), r=(0.058, 0.012, 0.02), blend=0.012)
        m.blob(skin, "cone", a=(0, 0.008, 0.08), b=(0, -0.026, 0.095), r1=0.007, r2=0.012, blend=0.008)
        m.blob(skin, "ell", T(0, -0.045, 0.074), r=(0.02, 0.008, 0.01), blend=0.005)
        if eyes:
            for sx in (-1, 1):
                m.blob(skin, "ell", T(sx * 0.03, 0.002, 0.08), r=(0.019, 0.012, 0.016), sub=True, blend=0.006)
                m.add("eye_white", sphere(0.0108, 12, 8), T(sx * 0.03, 0.001, 0.068))
                m.add("eye", sphere(0.0055, 8, 6), T(sx * 0.03, 0.001, 0.0765))
        m.blob(skin, "box", T(0, -0.05, 0.083), h=(0.016, 0.0018, 0.008), sub=True, blend=0.002)
        m.pop()

    def arm(self, side, hand, sleeve, skin, elbow=None, r0=0.042, fist=0.037, pad=None):
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


def eyes_glow(m, fig, material, dz=0.0):
    for sx in (-1, 1):
        m.add(material, sphere(0.014, 8, 5), T(sx * 0.03, fig.head[1] + 0.008, fig.head[2] + 0.078 + dz))


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


def helmet(m, fig, material, r=0.095, nasal=True, crest=None):
    h = fig.head
    m.add(material, lathe([(r, -0.02), (r * 1.02, 0.0), (r * 0.95, 0.04)] + [(r * math.cos(a) * 0.95, 0.04 + r * math.sin(a)) for a in np.linspace(0.3, math.pi / 2, 6)[:-1]] + [(0.0, 0.04 + r)], 22),
          chain(T(h[0], h[1] + 0.005, h[2]), S(1, 1, 1.05)))
    for a in np.linspace(0, 2 * math.pi, 14, endpoint=False):
        m.add("iron", sphere(0.0055, 7, 5), T(h[0] + r * 1.02 * math.cos(a), h[1] - 0.004, h[2] + r * 1.07 * math.sin(a)))
    if nasal:
        m.add(material, box(0.018, 0.07, 0.012), T(0, h[1] - 0.005, h[2] + r * 1.02))


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


FIGURES = {
    # one per class
    "barbarian": barbarian, "bard": bard, "cleric": cleric, "druid": druid, "fighter": fighter, "monk": monk,
    "paladin": paladin, "ranger": ranger, "rogue": rogue, "sorcerer": sorcerer, "warlock": warlock, "wizard": wizard,
    # tropes (the monster ones match ids in scripts/data/monsters.gd)
    "knight": knight, "goblin": goblin, "kobold": kobold, "bandit": bandit, "skeleton": skeleton, "zombie": zombie,
    "orc": orc, "ogre": ogre,
}


def build(name, detail):
    mk.DETAIL = detail
    mats = dict(COMMON)
    mats["blood_eye"] = mat("#ff3a1a", emit=(0.8, 0.1, 0.0))
    mats["fletch"] = mat("#c9c2b0")
    mats["crystal"] = mat("#9fd8ff", rough=0.15, emit=(0.2, 0.45, 0.7))
    m = mk.Model(mats)
    base(m, np.random.default_rng(sum(map(ord, name))))
    FIGURES[name](m)
    return m


def tuned(name):
    """Low-poly props and sculpts at fixed detail, then fill the base up to TRI_TARGET."""
    m = build(name, LOWPOLY)
    m.finalize(SCULPT_BUDGET)
    base_fill(m, np.random.default_rng(len(name)), TRI_TARGET - m.tris())
    assert TRI_MIN <= m.tris() <= TRI_MAX, f"{name}: {m.tris()} triangles"
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--previews", help="also render PNG previews (and a contact sheet) into this folder")
    ap.add_argument("names", nargs="*", default=list(FIGURES))
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
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
