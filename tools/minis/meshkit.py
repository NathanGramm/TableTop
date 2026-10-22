"""Tiny mesh toolkit for the minifigure generator: primitives, transforms, auto-smooth
normals, a glTF (.glb) writer and a software renderer for preview images. Needs numpy (and
Pillow for previews)."""
import json
import math
import struct

import numpy as np

SCULPT_CREASE = 12.0  # degrees; hides decimation noise on sculpts but keeps the big facets
DETAIL = 1.0  # global segment multiplier; make_minis.py tunes it per model to hit the triangle budget


def seg(n, lo=3):
    return max(lo, int(round(n * DETAIL)))


# ---------------- transforms (4x4) ----------------

def T(x=0.0, y=0.0, z=0.0):
    m = np.eye(4)
    m[:3, 3] = (x, y, z)
    return m


def S(x=1.0, y=None, z=None):
    return np.diag([x, x if y is None else y, x if z is None else z, 1.0])


def R(rx=0.0, ry=0.0, rz=0.0):
    """Euler rotation in radians, applied X then Z then Y."""
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    mx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    my = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    mz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    m = np.eye(4)
    m[:3, :3] = my @ mz @ mx
    return m


def A(origin, ydir, zhint=(0, 0, 1)):
    """Frame at `origin` whose +Y points along `ydir` (+Z as close to `zhint` as possible)."""
    y = np.asarray(ydir, float)
    y = y / np.linalg.norm(y)
    z = np.asarray(zhint, float)
    x = np.cross(y, z)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross(y, (1, 0, 0) if abs(y[0]) < 0.9 else (0, 1, 0))
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = x, y, z, origin
    return m


def chain(*ms):
    out = np.eye(4)
    for m in ms:
        out = out @ m
    return out


# ---------------- primitives: each returns (V Nx3, F Mx3) ----------------

def lathe(profile, segs=24, a0=0.0, a1=2 * math.pi, cap0=False, cap1=False):
    """Surface of revolution around +Y. profile: [(radius, y), ...]; walking along it, the
    outside is on the right (bottom-to-top is an outward-facing wall). A radius of 0 welds the
    ring into one pole vertex."""
    n = seg(segs)
    full = abs(a1 - a0 - 2 * math.pi) < 1e-9
    cols = n if full else n + 1
    ang = a0 + (a1 - a0) * np.arange(cols) / n
    V, rings = [], []
    for r, y in profile:
        if r == 0:
            rings.append([len(V)] * cols)
            V.append((0, y, 0))
        else:
            rings.append(list(range(len(V), len(V) + cols)))
            V.extend(zip(r * np.cos(ang), [y] * cols, r * np.sin(ang)))
    F = []
    for i in range(len(profile) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(n):
            k = (j + 1) % cols
            F += [(a[j], b[j], a[k]), (a[k], b[j], b[k])]
    for cap, idx, up in ((cap0, 0, False), (cap1, -1, True)):
        r, y = profile[idx]
        if not cap or r == 0:
            continue
        c = len(V)
        V.append((0, y, 0))
        ring = list(range(len(V), len(V) + cols))
        V.extend(zip(r * np.cos(ang), [y] * cols, r * np.sin(ang)))
        for j in range(n):
            k = (j + 1) % cols
            F.append((c, ring[k], ring[j]) if up else (c, ring[j], ring[k]))
    return _clean(np.array(V, float), F)


def _clean(V, F):
    F = np.array([f for f in F if len(set(f)) == 3], dtype=np.int64)
    return V, F


def sphere(r=1.0, segs=16, rings=10):
    n = seg(rings)
    t = np.linspace(-math.pi / 2, math.pi / 2, n + 1)
    prof = [(0.0 if i in (0, n) else r * math.cos(a), r * math.sin(a)) for i, a in enumerate(t)]
    return lathe(prof, segs)


def cyl(r0, r1, h, segs=16, caps=True):
    return lathe([(r0, 0.0), (r1, h)], segs, cap0=caps, cap1=caps)


def torus(R_, r, segs=24, tube=8):
    n = seg(tube)
    prof = [(R_ + r * math.cos(t), r * math.sin(t)) for t in np.linspace(-math.pi, math.pi, n + 1)]
    return lathe(prof, segs)


def box(sx, sy, sz):
    V = np.array([(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)], float) * (sx / 2, sy / 2, sz / 2)
    F = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1),
         (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
    return _orient(V, np.array(F))


def tube(points, radii, segs=10, caps=True):
    """Sweep a circle along a polyline. radii: one per point (or a single number)."""
    P = np.asarray(points, float)
    rr = np.broadcast_to(np.asarray(radii, float), (len(P),))
    n = seg(segs)
    tang = np.gradient(P, axis=0) if len(P) > 2 else np.repeat([P[1] - P[0]], len(P), 0)
    tang = tang / np.linalg.norm(tang, axis=1, keepdims=True)
    ref = np.array((0, 0, 1.0)) if abs(tang[0][2]) < 0.9 else np.array((1.0, 0, 0))
    N = np.cross(tang[0], ref)
    N /= np.linalg.norm(N)
    ang = 2 * math.pi * np.arange(n) / n
    V, F = [], []
    for i, (p, t, r) in enumerate(zip(P, tang, rr)):
        N = N - t * np.dot(N, t)  # parallel transport
        N /= np.linalg.norm(N)
        B = np.cross(t, N)
        for a in ang:
            V.append(p + r * (math.cos(a) * N + math.sin(a) * B))
    for i in range(len(P) - 1):
        for j in range(n):
            a, b, c, d = i * n + j, (i + 1) * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n
            F += [(a, c, b), (c, d, b)]
    if caps:
        for i, end in ((0, False), (len(P) - 1, True)):
            c = len(V)
            V.append(P[i])
            for j in range(n):
                a, b = i * n + j, i * n + (j + 1) % n
                F.append((c, a, b) if end else (c, b, a))
    return _orient(np.array(V), np.array(F))


def extrude(poly, depth):
    """Extrude a simple 2D polygon (XY) along Z, centred on z=0."""
    P = np.asarray(poly, float)
    if _area2(P) < 0:
        P = P[::-1]
    n = len(P)
    tris = _earclip(P)
    V = np.vstack([np.c_[P, np.full(n, depth / 2)], np.c_[P, np.full(n, -depth / 2)]])
    F = [tuple(t) for t in tris] + [(t[0] + n, t[2] + n, t[1] + n) for t in tris]
    for i in range(n):
        j = (i + 1) % n
        F += [(i, i + n, j), (j, i + n, j + n)]
    return _orient(V, np.array(F))


def _area2(P):
    return float(np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1]))


def _earclip(P):
    idx = list(range(len(P)))
    out = []
    while len(idx) > 3:
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = P[i0], P[i1], P[i2]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                continue
            if any(_inside(P[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            out.append((i0, i1, i2))
            idx.pop(k)
            break
        else:  # degenerate polygon; fan the rest
            out += [(idx[0], idx[i], idx[i + 1]) for i in range(1, len(idx) - 1)]
            return out
    out.append(tuple(idx))
    return out


def _inside(p, a, b, c):
    def s(p1, p2, p3):
        return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
    d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
    return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))


def _orient(V, F):
    """Flip a closed mesh's faces if they point inwards."""
    v0, v1, v2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    if np.einsum("ij,ij->i", v0, np.cross(v1, v2)).sum() < 0:
        F = F[:, ::-1]
    return V, F


# ---------------- model ----------------

class Model:
    def __init__(self, materials):
        self.materials = materials  # name -> dict(color, metal, rough, emit?, double?)
        self.parts = []  # (material, V, F)
        self.sculpt = {}  # material -> [sdf.Term], polygonized by finalize()
        self.soft = set()  # indices of sculpted parts (decimated, so they need a little smoothing)
        self._stack = [np.eye(4)]

    def blob(self, mat, kind, M=None, blend=0.0, sub=False, offset=0.0, clip=None, **params):
        """Add a signed-distance term to `mat`'s sculpted surface. clip=(y_lo, y_hi) trims it
        to that height band of the current frame."""
        import sdf
        assert mat in self.materials, mat
        frame = self._stack[-1]
        W = frame @ (np.eye(4) if M is None else M)
        if clip is not None:
            clip = (np.linalg.inv(frame), clip[0], clip[1], float(np.linalg.svd(frame[:3, :3], compute_uv=False).min()))
        self.sculpt.setdefault(mat, []).append(sdf.Term(kind, params, W, blend, sub, offset, clip))

    def finalize(self, budget):
        """Polygonize the sculpted surfaces, sharing `budget` triangles by surface area."""
        import sdf
        raw = {mat: sdf.polygonize(terms) for mat, terms in self.sculpt.items()}
        total = sum(len(F) for _, F in raw.values()) or 1
        for mat, (V, F) in raw.items():
            if len(F):
                V, F = sdf.decimate(V, F, max(60, int(budget * len(F) / total)))
                self.soft.add(len(self.parts))
                self.parts.append((mat, V, _orient(V, F)[1]))
        self.sculpt = {}

    def add(self, mat, mesh, M=None, deform=None):
        V, F = mesh
        M = self._stack[-1] @ (np.eye(4) if M is None else M)
        V = V @ M[:3, :3].T + M[:3, 3]
        if np.linalg.det(M[:3, :3]) < 0:
            F = F[:, ::-1]
        if deform is not None:
            V = deform(V)
        assert mat in self.materials, mat
        self.parts.append((mat, V, F))

    def push(self, M):
        self._stack.append(self._stack[-1] @ M)
        return self

    def pop(self):
        self._stack.pop()

    def tris(self):
        return sum(len(F) for _, _, F in self.parts)

    def primitives(self, crease_deg=0.0):
        """Per material: positions, normals and indices. Faces are flat-shaded (crease 0) for the
        faceted low-poly look; a larger crease angle smooths across shallow edges."""
        out = {}
        for i, (mat, V, F) in enumerate(self.parts):
            P, N = _auto_smooth(V, F, SCULPT_CREASE if i in self.soft else crease_deg)
            out.setdefault(mat, []).append((P, N))
        res = {}
        for mat, chunks in out.items():
            P = np.vstack([c[0] for c in chunks]).astype(np.float32)
            N = np.vstack([c[1] for c in chunks]).astype(np.float32)
            # weld corners that share position and normal back into indexed vertices
            key = np.round(np.hstack([P, N]), 5)
            _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
            res[mat] = (P[first], N[first], inv.ravel().astype(np.uint32))
        return res


def _auto_smooth(V, F, crease_deg):
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    area = np.linalg.norm(fn, axis=1, keepdims=True)
    unit = fn / np.maximum(area, 1e-12)
    cos_c = math.cos(math.radians(crease_deg))
    adj = [[] for _ in range(len(V))]
    for fi, f in enumerate(F):
        for v in f:
            adj[v].append(fi)
    P = V[F].reshape(-1, 3)
    N = np.zeros_like(P)
    for fi, f in enumerate(F):
        for k, v in enumerate(f):
            nb = adj[v]
            ok = [g for g in nb if np.dot(unit[g], unit[fi]) >= cos_c]
            n = fn[ok].sum(0)
            N[fi * 3 + k] = n / max(np.linalg.norm(n), 1e-12)
    return P, N


# ---------------- glTF ----------------

def write_glb(model, path, name):
    prims = model.primitives()
    blob = bytearray()
    views, accessors, gl_prims, gl_mats = [], [], [], []

    def push(arr, target):
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": arr.nbytes, "target": target})
        blob.extend(arr.tobytes())
        return len(views) - 1

    for mi, (mat, (P, N, I)) in enumerate(prims.items()):
        spec = model.materials[mat]
        m = {"name": mat, "pbrMetallicRoughness": {"baseColorFactor": list(spec["color"]) + [1.0],
                                                   "metallicFactor": spec.get("metal", 0.0),
                                                   "roughnessFactor": spec.get("rough", 0.7)}}
        if "emit" in spec:
            m["emissiveFactor"] = list(spec["emit"])
        if spec.get("double"):
            m["doubleSided"] = True
        gl_mats.append(m)
        accessors.append({"bufferView": push(P, 34962), "componentType": 5126, "count": len(P), "type": "VEC3",
                          "min": P.min(0).tolist(), "max": P.max(0).tolist()})
        accessors.append({"bufferView": push(N, 34962), "componentType": 5126, "count": len(N), "type": "VEC3"})
        accessors.append({"bufferView": push(I, 34963), "componentType": 5125, "count": len(I), "type": "SCALAR"})
        a = len(accessors)
        gl_prims.append({"attributes": {"POSITION": a - 3, "NORMAL": a - 2}, "indices": a - 1, "material": mi})
    while len(blob) % 4:
        blob.append(0)
    doc = {"asset": {"version": "2.0", "generator": "TableTop tools/minis"}, "scene": 0,
           "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "mesh": 0}],
           "meshes": [{"name": name, "primitives": gl_prims}], "materials": gl_mats,
           "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


# ---------------- preview renderer ----------------

def render(model, size=(360, 480), yaw=-30.0, pitch=18.0, ss=2):
    """Z-buffered software render with a key light and rim light. Returns a PIL image."""
    from PIL import Image
    W, H = size[0] * ss, size[1] * ss
    allP = np.vstack([V for _, V, _ in model.parts])
    lo, hi = allP.min(0), allP.max(0)
    center = (lo + hi) / 2
    rot = R(math.radians(pitch), 0, 0)[:3, :3] @ R(0, math.radians(yaw), 0)[:3, :3]
    rad = np.linalg.norm(hi - lo) / 2
    dist = rad * 3.2
    f = H * 1.25
    img = np.zeros((H, W, 3))
    img[:] = np.linspace(0.93, 0.80, H)[:, None, None] * np.array([1.0, 0.98, 0.95])
    zbuf = np.full((H, W), np.inf)
    key = np.array([-0.5, 0.8, 0.6])
    key /= np.linalg.norm(key)
    for mat, (P, N, I) in model.primitives().items():
        P, N = P[I], N[I]
        spec = model.materials[mat]
        col = np.array(spec["color"]) ** (1 / 2.2)
        emit = np.array(spec.get("emit", (0, 0, 0))) ** (1 / 2.2)
        shine = 0.15 + 0.5 * spec.get("metal", 0) * (1 - spec.get("rough", 0.7))
        cam = (P - center) @ rot.T
        nc = N @ rot.T
        z = dist - cam[:, 2]
        sx = W / 2 + f * cam[:, 0] / z
        sy = H / 2 - f * cam[:, 1] / z
        for t in range(0, len(P), 3):
            xs, ys, zs = sx[t:t + 3], sy[t:t + 3], z[t:t + 3]
            x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, W - 1)
            y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, H - 1)
            if x0 > x1 or y0 > y1:
                continue
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(d) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
            w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
            w2 = 1 - w0 - w1
            m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not m.any():
                continue
            zz = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            m &= zz < sub
            if not m.any():
                continue
            n = w0[m, None] * nc[t] + w1[m, None] * nc[t + 1] + w2[m, None] * nc[t + 2]
            n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-9
            n[n[:, 2] < 0] *= -1 if spec.get("double") else 1
            lam = np.clip(n @ key, 0, 1)
            rim = np.clip(1 - n[:, 2], 0, 1) ** 3 * 0.25
            half = (key + np.array([0, 0, 1])) / np.linalg.norm(key + np.array([0, 0, 1]))
            spec_l = np.clip(n @ half, 0, 1) ** 24 * shine
            c = col * (0.35 + 0.75 * lam[:, None]) + rim[:, None] + spec_l[:, None] + emit
            sub[m] = zz[m]
            img[y0:y1 + 1, x0:x1 + 1][m] = np.clip(c, 0, 1)
    im = Image.fromarray((img * 255).astype(np.uint8))
    return im.resize(size, Image.LANCZOS)
