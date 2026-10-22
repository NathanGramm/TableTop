"""Surface realism for the minis: tileable procedural textures (colour variation + normal map)
per kind of material, box-projected UVs, and ambient occlusion baked into vertex colours."""
import os

import numpy as np

TEX_SIZE = 256
TILE = 0.12  # world units per texture repeat
KINDS = ("cloth", "leather", "metal", "wood", "skin", "hair", "smooth")
SKINS = ("skin", "pale", "gob", "orc", "ogre", "hob", "gnoll", "kob", "rot", "drow", "lips")


def kind_of(name, spec):
    n = name.lower()
    if n in ("base", "team") or "emit" in spec or n in ("eye", "eye_white", "glass", "crystal", "pearl"):
        return "smooth"
    if any(k in n for k in ("hair", "beard", "fur", "mane", "feather", "fletch", "plume", "straw")):
        return "hair"
    if n.startswith(SKINS) or n in ("skin_dark", "tusk", "bone", "antler", "nose"):
        return "skin"
    if any(k in n for k in ("wood", "lute", "staff")):
        return "wood"
    if spec.get("metal", 0) >= 0.5 or any(k in n for k in ("steel", "iron", "gold", "plate", "mail", "rust", "armor", "coin")):
        return "metal"
    if any(k in n for k in ("leather", "hide", "boot", "belt", "rope", "loin")):
        return "leather"
    return "cloth"


def _noise(rng, size, scale, aniso=(1.0, 1.0)):
    """Tileable fractal-ish noise: white noise low-passed in the frequency domain."""
    w = rng.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None] * size / aniso[1]
    fx = np.fft.fftfreq(size)[None, :] * size / aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    h = np.real(np.fft.ifft2(np.fft.fft2(w) * np.exp(-(f / scale) ** 2)))
    return (h - h.mean()) / (h.std() + 1e-9)


def _height(kind, rng, n):
    y, x = np.mgrid[0:n, 0:n] / n
    if kind == "cloth":  # plain weave: alternating over/under threads
        t = 24
        u, v = np.sin(2 * np.pi * x * t), np.sin(2 * np.pi * y * t)
        checker = np.sign(np.sin(np.pi * x * t) * np.sin(np.pi * y * t))
        return 0.15 * (np.abs(u) * (checker > 0) + np.abs(v) * (checker <= 0)) + 0.6 * _noise(rng, n, 8) + 0.3 * _noise(rng, n, 30)
    if kind == "leather":
        c = np.abs(_noise(rng, n, 18))
        return -np.exp(-c * 3) + 0.3 * _noise(rng, n, 60)
    if kind == "metal":  # brushed, with a few scratches
        h = 0.3 * _noise(rng, n, 50, aniso=(8, 0.5))
        for _ in range(14):
            x0, y0, ang, ln = rng.random(), rng.random(), rng.uniform(0, np.pi), rng.uniform(0.1, 0.4)
            d = np.abs((x - x0) * np.sin(ang) - (y - y0) * np.cos(ang))
            along = np.abs((x - x0) * np.cos(ang) + (y - y0) * np.sin(ang))
            h -= 0.8 * np.exp(-(d * n / 0.8) ** 2) * (along < ln)
        return h
    if kind == "wood":
        return np.sin(2 * np.pi * (y * 9 + 0.35 * _noise(rng, n, 6, aniso=(1, 6)))) + 0.4 * _noise(rng, n, 50, aniso=(1, 10))
    if kind == "skin":
        return 0.6 * _noise(rng, n, 70) + 0.4 * _noise(rng, n, 12)
    if kind == "hair":
        return _noise(rng, n, 60, aniso=(0.15, 6))
    return np.zeros((n, n))


STRENGTH = {"cloth": 2.0, "leather": 2.5, "metal": 1.2, "wood": 2.0, "skin": 0.8, "hair": 3.0, "smooth": 0.0}
VARIATION = {"cloth": 0.06, "leather": 0.12, "metal": 0.08, "wood": 0.18, "skin": 0.05, "hair": 0.12, "smooth": 0.0}


def write_textures(folder):
    """Writes <kind>_col.png and <kind>_nrm.png for every textured kind."""
    from PIL import Image
    os.makedirs(folder, exist_ok=True)
    for i, kind in enumerate(KINDS[:-1]):
        rng = np.random.default_rng(100 + i)
        n = TEX_SIZE
        h = _height(kind, rng, n)
        h = h / (np.abs(h).max() + 1e-9)
        k = STRENGTH[kind] * n / 256
        dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / 2 * k
        dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / 2 * k
        nrm = np.dstack([-dx, dy, np.ones_like(h)])
        nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
        Image.fromarray(((nrm * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(folder, kind + "_nrm.png"))
        var = 1.0 - VARIATION[kind] * (0.5 + 0.5 * np.clip(_noise(rng, n, 10) * 0.5 + 0.3 * h, -1, 1))
        Image.fromarray((np.dstack([var] * 3) * 255).astype(np.uint8)).save(os.path.join(folder, kind + "_col.png"))


def box_uv(P, N):
    """Project each vertex onto the plane its normal faces most (triplanar-style UVs)."""
    a = np.abs(N).argmax(1)
    u = np.where(a == 0, P[:, 2], P[:, 0])
    v = np.where(a == 1, P[:, 2], P[:, 1])
    return (np.c_[u, -v] / TILE).astype(np.float32)


def bake_ao(tris, P, N, voxel=0.005, rays=24, reach=0.09, seed=0):
    """Ambient occlusion per vertex: the share of hemisphere rays that hit the surface within
    `reach`, tested against a voxelized copy of all triangles."""
    rng = np.random.default_rng(seed)
    lo = tris.reshape(-1, 3).min(0) - 2 * reach
    hi = tris.reshape(-1, 3).max(0) + 2 * reach
    shape = np.ceil((hi - lo) / voxel).astype(int) + 1
    occ = np.zeros(shape, bool)
    # sample every triangle densely enough that no voxel along it is missed
    edge = np.max(np.linalg.norm(tris - np.roll(tris, 1, 1), axis=2), 1)
    for k in np.unique(np.clip(np.ceil(edge / voxel * 1.5), 1, 64).astype(int)):
        sel = tris[np.clip(np.ceil(edge / voxel * 1.5), 1, 64).astype(int) == k]
        i, j = np.mgrid[0:k + 1, 0:k + 1]
        keep = i + j <= k
        b = np.c_[i[keep], j[keep]] / k
        w = np.c_[1 - b.sum(1), b]
        pts = np.einsum("bk,tkd->tbd", w, sel).reshape(-1, 3)
        idx = np.floor((pts - lo) / voxel).astype(int)
        occ[idx[:, 0], idx[:, 1], idx[:, 2]] = True
    # cosine-weighted hemisphere directions in a local frame, rotated per vertex
    u1, u2 = rng.random(rays), rng.random(rays)
    r, th = np.sqrt(u1), 2 * np.pi * u2
    local = np.c_[r * np.cos(th), r * np.sin(th), np.sqrt(1 - u1)]
    t = np.cross(N, np.where(np.abs(N[:, :1]) < 0.9, [[1, 0, 0]], [[0, 1, 0]]))
    t /= np.linalg.norm(t, axis=1, keepdims=True) + 1e-9
    b = np.cross(N, t)
    steps = np.linspace(2.0 * voxel, reach, 12)
    hit = np.zeros((len(P), rays), bool)
    D = local[None, :, 0:1] * t[:, None] + local[None, :, 1:2] * b[:, None] + local[None, :, 2:3] * N[:, None]
    for s in steps:
        Q = P[:, None] + N[:, None] * voxel * 1.2 + D * s
        idx = np.floor((Q - lo) / voxel).astype(int)
        idx = np.clip(idx, 0, shape - 1)
        hit |= occ[idx[..., 0], idx[..., 1], idx[..., 2]]
    return 1.0 - hit.mean(1)
