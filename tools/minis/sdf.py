"""Signed-distance sculpting for the minis: smooth-blended ellipsoids, round cones and boxes are
polygonized with marching cubes and decimated to a triangle budget, which gives organic bodies
(faces, muscles, hands) that primitive meshes can't. Needs scikit-image and fast-simplification."""
import numpy as np

VOXEL = 0.0028  # world units; a one-square base is 0.84 across


class Term:
    def __init__(self, kind, params, M, blend=0.0, sub=False, offset=0.0, clip=None):
        self.kind, self.p, self.blend, self.sub, self.offset = kind, params, blend, sub, offset
        self.Minv = np.linalg.inv(M)
        self.k = float(np.linalg.svd(M[:3, :3], compute_uv=False).min())
        self.clip = clip  # (Minv of the figure frame, y_lo, y_hi, k)
        lo, hi = _local_bounds(kind, params)
        pad = offset + 0.002
        corners = np.array([(x, y, z, 1) for x in (lo[0] - pad, hi[0] + pad) for y in (lo[1] - pad, hi[1] + pad) for z in (lo[2] - pad, hi[2] + pad)])
        w = corners @ M.T
        self.lo, self.hi = w[:, :3].min(0), w[:, :3].max(0)

    def eval(self, P):
        L = P @ self.Minv[:3, :3].T + self.Minv[:3, 3]
        d = _dist(self.kind, self.p, L) * self.k - self.offset
        if self.clip is not None:
            Mi, ylo, yhi, kc = self.clip
            y = (P @ Mi[:3, :3].T + Mi[:3, 3])[:, 1]
            d = np.maximum(d, np.maximum(ylo - y, y - yhi) * kc)
        return d


def _local_bounds(kind, p):
    if kind == "ell":
        r = np.asarray(p["r"], float)
        return -r, r
    if kind == "cone":
        a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
        r = max(p["r1"], p["r2"]) + p.get("folds", (0, 0))[0]
        return np.minimum(a, b) - r, np.maximum(a, b) + r
    if kind == "box":
        h = np.asarray(p["h"], float)
        return -h, h
    if kind == "torus":
        R, r = p["R"], p["r"]
        return np.array((-R - r, -r, -R - r)), np.array((R + r, r, R + r))
    raise ValueError(kind)


def _dist(kind, p, L):
    if kind == "ell":  # Inigo Quilez's ellipsoid bound
        r = np.asarray(p["r"], float)
        k0 = np.linalg.norm(L / r, axis=1)
        k1 = np.linalg.norm(L / (r * r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    if kind == "cone":  # round cone between two spheres, with optional radial folds
        a, b = np.asarray(p["a"], float), np.asarray(p["b"], float)
        ba = b - a
        L2 = ba @ ba
        t = np.clip(((L - a) @ ba) / L2, 0, 1)
        q = L - (a + t[:, None] * ba)
        r = p["r1"] + (p["r2"] - p["r1"]) * t
        if "folds" in p:
            amp, n = p["folds"]
            ref = np.cross(ba, (1, 0, 0) if abs(ba[0]) < 0.9 * np.sqrt(L2) else (0, 0, 1))
            ref /= np.linalg.norm(ref)
            ang = np.arctan2(q @ np.cross(ba / np.sqrt(L2), ref), q @ ref)
            r = r + amp * np.sin(n * ang) * t
        return np.linalg.norm(q, axis=1) - r
    if kind == "box":
        h, rr = np.asarray(p["h"], float), p.get("round", 0.0)
        q = np.abs(L) - (h - rr)
        return np.linalg.norm(np.maximum(q, 0), axis=1) + np.minimum(q.max(1), 0) - rr
    if kind == "torus":
        q = np.c_[np.linalg.norm(L[:, [0, 2]], axis=1) - p["R"], L[:, 1]]
        return np.linalg.norm(q, axis=1) - p["r"]
    raise ValueError(kind)


def _smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def polygonize(terms, voxel=VOXEL):
    """Marching-cubes mesh (V, F) of the smooth union of `terms` (subtractions applied in order)."""
    from skimage.measure import marching_cubes
    adds = [t for t in terms if not t.sub]
    lo = np.min([t.lo for t in adds], 0) - 3 * voxel
    hi = np.max([t.hi for t in adds], 0) + 3 * voxel
    shape = np.ceil((hi - lo) / voxel).astype(int) + 1
    D = np.full(shape, 1.0, np.float32)
    for t in terms:
        m = t.blend + 2 * voxel
        i0 = np.clip(np.floor((t.lo - m - lo) / voxel).astype(int), 0, shape - 1)
        i1 = np.clip(np.ceil((t.hi + m - lo) / voxel).astype(int) + 1, 0, shape)
        if np.any(i1 <= i0):
            continue
        axes = [lo[a] + voxel * np.arange(i0[a], i1[a]) for a in range(3)]
        P = np.stack(np.meshgrid(*axes, indexing="ij"), -1).reshape(-1, 3)
        sub = D[i0[0]:i1[0], i0[1]:i1[1], i0[2]:i1[2]]
        d = t.eval(P).reshape(sub.shape)
        if t.sub:
            sub[...] = -_smin(-sub, d, t.blend)
        else:
            sub[...] = _smin(sub, d, t.blend)
    if D.min() >= 0:
        return np.zeros((0, 3)), np.zeros((0, 3), np.int64)
    V, F, _, _ = marching_cubes(D, 0.0, spacing=(voxel,) * 3)
    return V + lo, F.astype(np.int64)


def decimate(V, F, target):
    import fast_simplification
    if len(F) <= target:
        return V, F
    V2, F2 = fast_simplification.simplify(V.astype(np.float32), F.astype(np.int32), target_reduction=1 - target / len(F))
    return V2.astype(float), F2.astype(np.int64)
