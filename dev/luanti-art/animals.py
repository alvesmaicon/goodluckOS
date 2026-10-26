#!/usr/bin/env python3
# goodluck_models' farm animals: Minecraft's models for its textures' layouts (the cow, the pig, the sheep with its
# wool, the chicken), one skinned mesh each, every part a joint, animated as Minecraft animates them. Written as
# binary glTF: Minecraft's model space (y down, the head toward -z, the right side toward -x) is turned to glTF's (the
# head toward -z, which Luanti's loader turns to +z, where a mob looks at yaw 0), 10 units a node. Frames are seconds:
# stand 0-1, walk from 1, run from 3, die 4-5, eat 6-8 (cow, sheep), flap from 9 (chicken)
#   python3 dev/luanti-art/animals.py [out dir]
import json, math, os, struct, sys
from mcmodel import box, posed

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
OUT = sys.argv[1] if len(sys.argv) > 1 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_models/models"
S = 10 / 16
FPS = 20


def gltf(p):
    x, y, z = p
    return (-x * S, (24 - y) * S, z * S)


def quat(axis, a):
    s = math.sin(a / 2)
    return tuple(s if i == axis else 0.0 for i in range(3)) + (math.cos(a / 2),)


# a turn about Minecraft's x is one about glTF's -x, about its z one about glTF's z
def mc_x(a):
    return quat(0, -a)


def mc_z(a):
    return quat(2, a)


def legs(height, front_z, hind_z, x, mirror_left):
    leg = lambda m: box(0, 16, -2, 0, -2, 4, height, 4, mirror=m)
    y = 24 - height
    return [("right_hind_leg", (-x, y, hind_z), (0, 0, 0), leg(False)),
            ("left_hind_leg", (x, y, hind_z), (0, 0, 0), leg(mirror_left)),
            ("right_front_leg", (-x, y, front_z), (0, 0, 0), leg(False)),
            ("left_front_leg", (x, y, front_z), (0, 0, 0), leg(mirror_left))]


def gait(amplitude, period, names=("right_hind_leg", "left_front_leg", "left_hind_leg", "right_front_leg")):
    # Minecraft's legs: diagonal pairs swing together, cos(limb swing * 0.6662) * 1.4 * swing amount
    def pose(t):
        a = amplitude * math.sin(2 * math.pi * t / period)
        half = len(names) // 2
        return {n: (mc_x(a if i < half else -a), None) for i, n in enumerate(names)}
    return pose


def die(t):
    # Minecraft's death: on its side, sqrt(ticks / 20 * 1.6) of a quarter turn about the body's length
    return {"root": (mc_z(min(1.0, math.sqrt(max(0.0, t) * 1.6)) * math.pi / 2), None)}


def eat(t):
    # the sheep eating grass: in 4 ticks the head goes 9 pixels down and pi/5 forward, nibbles for 32, comes back in 4
    tick = t * FPS
    if tick < 4:
        drop, angle = tick / 4, math.pi / 5 * tick / 4
    elif tick <= 36:
        drop, angle = 1.0, math.pi / 5 + 0.21991149 * math.sin((tick - 4) / 32 * 28.7)
    else:
        drop, angle = max(0.0, (40 - tick) / 4), math.pi / 5 * max(0.0, (40 - tick) / 4)
    return {"head": (mc_x(angle), (0, 9 * drop, 0))}


def flap(period):
    # the chicken's wings off the ground: (sin(flap) + 1) * flap speed about z, up and out
    def pose(t):
        bob = (math.sin(2 * math.pi * t / period - math.pi / 2) + 1) * 0.8
        return {"right_wing": (mc_z(bob), None), "left_wing": (mc_z(-bob), None)}
    return pose


QUADRUPED = lambda walk, run: [(0, 1, None), (1, walk[1], gait(walk[0], walk[1])), (3, run[1], gait(run[0], run[1])),
                               (4, 1, die)]

ANIMALS = {
    # 26.x's cow: the classic one with a muzzle, on 64x64; left legs mirrored
    "cow": ((64, 64), [
        ("head", (0, 4, -8), (0, 0, 0), box(0, 0, -4, -4, -6, 8, 8, 6) + box(1, 33, -3, 1, -7, 6, 3, 1) +
         box(22, 0, -5, -5, -4, 1, 3, 1) + box(22, 0, 4, -5, -4, 1, 3, 1)),
        ("body", (0, 5, 2), (math.pi / 2, 0, 0), box(18, 4, -6, -10, -7, 12, 18, 10) + box(52, 0, -2, 2, -8, 4, 6, 1)),
    ] + legs(12, -6, 7, 4, True), QUADRUPED((0.7, 1.0), (1.0, 0.5)) + [(6, 2, eat)]),
    "pig": ((64, 64), [
        ("head", (0, 12, -6), (0, 0, 0), box(0, 0, -4, -4, -8, 8, 8, 8) + box(16, 16, -2, 0, -9, 4, 3, 1)),
        ("body", (0, 11, 2), (math.pi / 2, 0, 0), box(28, 8, -5, -10, -7, 10, 16, 8)),
    ] + legs(6, -5, 7, 3, False), QUADRUPED((0.7, 0.8), (1.0, 0.4))),
    # the sheep and its wool on one texture: the body's 64x32 over the wool's
    "sheep": ((64, 64), [
        ("head", (0, 6, -8), (0, 0, 0), box(0, 0, -3, -4, -6, 6, 6, 8) + box(0, 32, -3, -4, -4, 6, 6, 6, grow=0.6)),
        ("body", (0, 5, 2), (math.pi / 2, 0, 0), box(28, 8, -4, -10, -7, 8, 16, 6) +
         box(28, 40, -4, -10, -7, 8, 16, 6, grow=1.75)),
    ] + [(n, p, r, f + box(0, 48, -2, 0, -2, 4, 6, 4, grow=0.5)) for n, p, r, f in legs(12, -5, 7, 3, False)],
        QUADRUPED((0.7, 1.0), (1.0, 0.5)) + [(6, 2, eat)]),
    "chicken": ((64, 32), [
        ("head", (0, 15, -4), (0, 0, 0), box(0, 0, -2, -6, -2, 4, 6, 3) + box(14, 0, -2, -4, -4, 4, 2, 2) +
         box(14, 4, -1, -2, -3, 2, 2, 2)),
        ("body", (0, 16, 0), (math.pi / 2, 0, 0), box(0, 9, -3, -4, -3, 6, 8, 6)),
        ("right_leg", (-2, 19, 1), (0, 0, 0), box(26, 0, -1, 0, -3, 3, 5, 3)),
        ("left_leg", (1, 19, 1), (0, 0, 0), box(26, 0, -1, 0, -3, 3, 5, 3)),
        ("right_wing", (-4, 13, 0), (0, 0, 0), box(24, 13, 0, 0, -3, 1, 4, 6)),
        ("left_wing", (4, 13, 0), (0, 0, 0), box(24, 13, -1, 0, -3, 1, 4, 6)),
    ], [(0, 1, None), (1, 0.5, gait(0.7, 0.5, ("right_leg", "left_leg"))),
        (3, 0.3, gait(1.0, 0.3, ("right_leg", "left_leg"))), (4, 1, die), (9, 0.3, flap(0.3))]),
}


def normal(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    length = math.sqrt(sum(x * x for x in n)) or 1
    return tuple(x / length for x in n)


def build(name, tex, parts, segments):
    w, h = tex
    joints = ["root"] + [p[0] for p in parts]
    pos, nrm, uvs, jnt, idx = [], [], [], [], []
    for j, (_, pivot, rot, faces) in enumerate(parts, 1):
        # a box's six faces come together: its middle tells outward from inward
        for k in range(0, len(faces), 6):
            cube = posed(faces[k:k + 6], pivot, rot)
            corners = [gltf(p) for f, _ in cube for p in f]
            mid = [sum(p[i] for p in corners) / len(corners) for i in range(3)]
            for f, (u0, v0, u1, v1) in cube:
                quad = [gltf(p) for p in f]
                if max(abs(quad[0][i] - quad[2][i]) for i in range(3)) < 1e-6:
                    continue
                n = normal(*quad[:3])
                face_mid = [sum(p[i] for p in quad) / 4 for i in range(3)]
                order = (0, 1, 2, 0, 2, 3)
                if sum(n[i] * (face_mid[i] - mid[i]) for i in range(3)) < 0:
                    order, n = (0, 2, 1, 0, 3, 2), tuple(-x for x in n)
                base = len(pos)
                for p, (u, v) in zip(quad, [(u1, v0), (u0, v0), (u0, v1), (u1, v1)]):
                    pos.append(p)
                    nrm.append(n)
                    uvs.append((u / w, v / h))
                    jnt.append(j)
                idx += [base + o for o in order]
    rest = {"root": (0.0, 0.0, 0.0)}
    for jname, pivot, _, _ in parts:
        rest[jname] = gltf(pivot)
    # every key time of every segment, each animated joint keyed at all of them (rest outside its own)
    times, keyed = [], {}
    for start, length, pose in segments:
        n = max(1, round(length * FPS))
        for i in range(n + 1):
            t = i / n * length
            times.append(round(start + t, 4))
            if pose:
                for jname, (r, d) in pose(t).items():
                    keyed.setdefault(jname, set()).update(["rotation"] if r else [])
                    keyed[jname].update(["translation"] if d else [])
    times = sorted(set(times))

    def at(jname, time):
        for start, length, pose in segments:
            if pose and start - 1e-6 <= time <= start + length + 1e-6:
                r, d = pose(time - start).get(jname, (None, None))
                return r or (0.0, 0.0, 0.0, 1.0), d or (0, 0, 0)
        return (0.0, 0.0, 0.0, 1.0), (0, 0, 0)

    blob, views, accessors = bytearray(), [], []

    def add(fmt, rows, kind, ctype, target=None, minmax=False):
        while len(blob) % 4:
            blob.append(0)
        offset = len(blob)
        for r in rows:
            blob.extend(struct.pack("<" + fmt, *(r if isinstance(r, tuple) else (r,))))
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(blob) - offset}
        if target:
            view["target"] = target
        views.append(view)
        acc = {"bufferView": len(views) - 1, "componentType": ctype, "count": len(rows), "type": kind}
        if minmax:
            cols = list(zip(*[r if isinstance(r, tuple) else (r,) for r in rows]))
            acc["min"], acc["max"] = [min(c) for c in cols], [max(c) for c in cols]
        accessors.append(acc)
        return len(accessors) - 1

    FLOAT, UBYTE, USHORT = 5126, 5121, 5123
    attrs = {
        "POSITION": add("3f", pos, "VEC3", FLOAT, 34962, True),
        "NORMAL": add("3f", nrm, "VEC3", FLOAT, 34962),
        "TEXCOORD_0": add("2f", uvs, "VEC2", FLOAT, 34962),
        "JOINTS_0": add("4B", [(j, 0, 0, 0) for j in jnt], "VEC4", UBYTE, 34962),
        "WEIGHTS_0": add("4f", [(1.0, 0.0, 0.0, 0.0)] * len(pos), "VEC4", FLOAT, 34962),
    }
    indices = add("H", idx, "SCALAR", USHORT, 34963)
    ibm = []
    for jname in joints:
        x, y, z = rest[jname]
        ibm.append((1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1))
    inverse = add("16f", ibm, "MAT4", FLOAT)
    nodes = [{"name": "root", "children": list(range(1, len(joints)))}]
    for jname in joints[1:]:
        nodes.append({"name": jname, "translation": list(rest[jname])})
    nodes.append({"name": name, "mesh": 0, "skin": 0})
    channels, samplers = [], []
    tin = add("f", times, "SCALAR", FLOAT, None, True)
    for j, jname in enumerate(joints):
        for path in sorted(keyed.get(jname, ())):
            if path == "rotation":
                out = add("4f", [at(jname, t)[0] for t in times], "VEC4", FLOAT)
            else:
                moved = lambda d: tuple(r + o for r, o in zip(rest[jname], (-d[0] * S, -d[1] * S, d[2] * S)))
                out = add("3f", [moved(at(jname, t)[1]) for t in times], "VEC3", FLOAT)
            samplers.append({"input": tin, "output": out, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": path}})
    doc = {
        "asset": {"version": "2.0", "generator": "goodluckOS dev/luanti-art/animals.py"},
        "scene": 0, "scenes": [{"nodes": [0, len(nodes) - 1]}], "nodes": nodes,
        "meshes": [{"primitives": [{"attributes": attrs, "indices": indices}]}],
        "skins": [{"joints": list(range(len(joints))), "inverseBindMatrices": inverse, "skeleton": 0}],
        "animations": [{"name": "all", "channels": channels, "samplers": samplers}],
        "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors,
    }
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    blob += b"\0" * (-len(blob) % 4)
    glb = struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(text) + 8 + len(blob))
    glb += struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob)
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/goodluck_models_{name}.glb", "wb") as f:
        f.write(glb)
    return len(pos), len(idx) // 3


for animal, (tex, parts, segments) in ANIMALS.items():
    print(animal, "%d vertices, %d triangles" % build(animal, tex, parts, segments))
print("meshes in", os.path.relpath(OUT, ROOT))
