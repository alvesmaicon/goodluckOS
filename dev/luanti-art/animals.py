#!/usr/bin/env python3
# goodluck_models' creatures: Minecraft's models for its textures' layouts (the cow, the pig, the sheep with its wool,
# the chicken, the horse, the donkey the mule shares, the spider), one skinned mesh each, every part a joint, animated
# as Minecraft animates them. Written as binary glTF: Minecraft's model space (y down, the head toward -z, the right
# side toward -x) is turned to glTF's (the head toward -z, which Luanti's loader turns to +z, where a mob looks at yaw
# 0), 10 units a node. Frames are seconds: stand 0-1, walk from 1, run from 3, die 4-5, eat 6-8 (cow, sheep), rear
# 6-7.6 (horses), flap from 9 (chicken). The horses' saddle, bridle and chests are a second primitive, so that a
# texture of their own draws them, and nothing where it is blank
#   python3 dev/luanti-art/animals.py [out dir]
import json, math, os, struct, sys
from mcmodel import box, posed

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
OUT = sys.argv[1] if len(sys.argv) > 1 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_models/models"
S = 10 / 16
FPS = 20
PI = math.pi


def gltf(p):
    x, y, z = p
    return (-x * S, (24 - y) * S, z * S)


def quat(axis, a):
    s = math.sin(a / 2)
    return tuple(s if i == axis else 0.0 for i in range(3)) + (math.cos(a / 2),)


def qmul(a, b):
    # the turn b, then a
    x1, y1, z1, w1 = a
    x2, y2, z2, w2 = b
    return (w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
            w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2)


# a turn about Minecraft's x is one about glTF's -x, about its y one about -y, about its z one about z
def mc_x(a):
    return quat(0, -a)


def mc_y(a):
    return quat(1, -a)


def mc_z(a):
    return quat(2, a)


def mc_rot(x=0.0, y=0.0, z=0.0):
    # Minecraft turns a part about x, then y, then z
    return qmul(mc_z(z), qmul(mc_y(y), mc_x(x)))


def part(name, pivot, faces, rot=(0, 0, 0), gear=(), parent=None):
    # a joint: its boxes' faces in Minecraft's space, turned about its pivot at rest; gear faces go to the second
    # primitive; with a parent it follows that joint's turns
    return {"name": name, "pivot": pivot, "rot": rot, "faces": faces, "gear": list(gear), "parent": parent}


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


def both(a, b):
    return lambda t: {**b(t), **a(t)}


QUADRUPED = lambda walk, run: [(0, 1, None), (1, walk[1], gait(walk[0], walk[1])), (3, run[1], gait(run[0], run[1])),
                               (4, 1, die)]


def horse(chested):
    # Minecraft's horse since 1.14; the donkey (and the mule) with its long ears and a chest at each side
    if chested:
        ear = lambda x: posed(box(0, 12, -1, -7, 0, 2, 7, 1), (x, -10, 4), (PI / 12, 0, PI / 12 if x > 0 else -PI / 12))
        ears = ear(1.25) + ear(-1.25)
    else:
        ears = box(19, 16, 0.55, -13, 4, 2, 3, 1, grow=-0.001) + box(19, 16, -2.55, -13, 4, 2, 3, 1, grow=-0.001)
    head = box(0, 35, -2.05, -6, -2, 4, 12, 7) + box(0, 13, -3, -11, -2, 6, 5, 7) + \
        box(56, 36, -1, -11, 5.01, 2, 16, 2) + box(0, 25, -2, -11, -7, 4, 5, 5) + ears
    # the saddle's bit, head straps and reins (Minecraft shows the reins only when the horse is ridden)
    bridle = box(29, 5, 2, -9, -6, 1, 2, 2) + box(29, 5, -3, -9, -6, 1, 2, 2) + \
        box(1, 1, -3, -11, -1.9, 6, 5, 6, grow=0.2) + box(19, 0, -2, -11, -4, 4, 5, 2, grow=0.2) + \
        posed(box(32, 2, 3.1, -6, -8, 0, 3, 16) + box(32, 2, -3.1, -6, -8, 0, 3, 16), (0, 0, 0), (-PI / 6, 0, 0))
    gear = box(26, 0, -5, -8, -9, 10, 9, 9, grow=0.5)
    if chested:
        chest = lambda x: posed(box(26, 21, -4, 0, -2, 8, 8, 3), (x, -8, 0), (0, -PI / 2 if x > 0 else PI / 2, 0))
        gear = gear + chest(6) + chest(-6)
    leg = lambda m, z: box(48, 21, -3 if m else -1, -1.01, z, 4, 11, 4, mirror=m)
    return [part("body", (0, 11, 5), box(0, 32, -5, -8, -17, 10, 10, 22, grow=0.05), gear=gear),
            part("head", (0, 4, -12), head, rot=(PI / 6, 0, 0), gear=bridle),
            part("tail", (0, 6, 7), box(42, 36, -1.5, 0, 0, 3, 14, 4), rot=(PI / 6, 0, 0), parent="body"),
            part("right_hind_leg", (-4, 14, 7), leg(False, -1)), part("left_hind_leg", (4, 14, 7), leg(True, -1)),
            part("right_front_leg", (-4, 14, -10), leg(False, -1.9)),
            part("left_front_leg", (4, 14, -10), leg(True, -1.9))]


def trot(amount, period):
    # Minecraft's horse: the front legs swing cos(limb swing * 0.6662 + pi) * 0.8 * amount, the hind ones half that
    # the other way, diagonal pairs together; the tail rises with the pace
    def pose(t):
        s = math.cos(2 * PI * t / period + PI)
        front, hind = s * 0.8 * amount, s * 0.5 * amount
        return {"left_front_leg": (mc_x(front), None), "right_front_leg": (mc_x(-front), None),
                "left_hind_leg": (mc_x(-hind), None), "right_hind_leg": (mc_x(hind), None),
                "tail": (mc_x(0.75 * amount), (0, amount, 2 * amount))}
    return pose


def rear(t):
    # Minecraft's rearing, up in 0.4 s, held, down in 0.4 s: the body an eighth turn back about the hips, the head up
    # and forward, the front legs up and forward kicking, the hind ones a little back
    s = max(0.0, min(1.0, t / 0.4, (1.6 - t) / 0.4))
    kick = math.cos(t * FPS * 0.6 + PI)
    return {"body": (mc_x(-PI / 4 * s), None), "head": (mc_x(-PI / 12 * s), (0, -8 * s, 8 * s)),
            "left_front_leg": (mc_x((-PI / 3 + kick) * s), (0, -12 * s, 4 * s)),
            "right_front_leg": (mc_x((-PI / 3 - kick) * s), (0, -12 * s, 4 * s)),
            "left_hind_leg": (mc_x(PI / 12 * s), None), "right_hind_leg": (mc_x(PI / 12 * s), None)}


HORSE = [(0, 1, None), (1, 1.0, trot(0.5, 1.0)), (3, 0.5, trot(1.0, 0.5)), (4, 1, die), (6, 1.6, rear)]

# the spider's leg pairs: name, z, the right one's rest turn about z (the left's the opposite) and y, its step's phase
SPIDER_LEGS = [("hind_leg", 2, -PI / 4, PI / 4, 0), ("middle_hind_leg", 1, -PI / 4 * 0.74, PI / 8, PI),
               ("middle_front_leg", 0, -PI / 4 * 0.74, -PI / 8, PI / 2), ("front_leg", -1, -PI / 4, -PI / 4, 3 * PI / 2)]


def spider():
    leg = lambda right: box(18, 0, -15 if right else -1, -1, -1, 16, 2, 2)
    parts = [part("head", (0, 15, -3), box(32, 4, -4, -4, -8, 8, 8, 8)),
             part("body0", (0, 15, 0), box(0, 0, -3, -3, -3, 6, 6, 6)),
             part("body1", (0, 15, 9), box(0, 12, -5, -4, -6, 10, 8, 12))]
    for name, z, _, _, _ in SPIDER_LEGS:
        parts += [part("right_" + name, (-4, 15, z), leg(True)), part("left_" + name, (4, 15, z), leg(False))]
    return parts


def crawl(amount, period):
    # Minecraft's spider legs, at rest and walking: each pair sweeps -cos(2 * limb swing * 0.6662 + phase) * 0.4 *
    # amount about y and lifts |sin(limb swing * 0.6662 + phase)| * 0.4 * amount about z, the left legs the other way
    def pose(t):
        k = PI * t / period
        out = {}
        for name, _, z0, y0, ph in SPIDER_LEGS:
            dy = -math.cos(2 * k + ph) * 0.4 * amount
            dz = abs(math.sin(k + ph)) * 0.4 * amount
            out["right_" + name] = (mc_rot(y=y0 + dy, z=z0 + dz), None)
            out["left_" + name] = (mc_rot(y=-y0 - dy, z=-z0 - dz), None)
        return out
    return pose


SPIDER = [(0, 1, crawl(0, 1)), (1, 0.6, crawl(1, 0.6)), (3, 0.4, crawl(1, 0.4)), (4, 1, both(die, crawl(0, 1)))]

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
    "horse": ((64, 64), horse(False), HORSE),
    "donkey": ((64, 64), horse(True), HORSE),
    "spider": ((64, 32), spider(), SPIDER),
}


def normal(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    length = math.sqrt(sum(x * x for x in n))
    return tuple(x / (length or 1) for x in n), length


def build(name, tex, parts, segments):
    w, h = tex
    parts = [p if isinstance(p, dict) else part(p[0], p[1], p[3], p[2]) for p in parts]
    joints = ["root"] + [p["name"] for p in parts]
    prims = [{"pos": [], "nrm": [], "uvs": [], "jnt": [], "idx": []} for _ in range(2)]
    for j, p in enumerate(parts, 1):
        for faces, prim in ((p["faces"], prims[0]), (p["gear"], prims[1])):
            # a box's six faces come together: its middle tells outward from inward
            for k in range(0, len(faces), 6):
                cube = posed(faces[k:k + 6], p["pivot"], p["rot"])
                corners = [gltf(q) for f, _ in cube for q in f]
                mid = [sum(q[i] for q in corners) / len(corners) for i in range(3)]
                for f, (u0, v0, u1, v1) in cube:
                    quad = [gltf(q) for q in f]
                    n, area = normal(*quad[:3])
                    if area < 1e-9:
                        continue
                    face_mid = [sum(q[i] for q in quad) / 4 for i in range(3)]
                    order = (0, 1, 2, 0, 2, 3)
                    if sum(n[i] * (face_mid[i] - mid[i]) for i in range(3)) < 0:
                        order, n = (0, 2, 1, 0, 3, 2), tuple(-x for x in n)
                    base = len(prim["pos"])
                    for q, (u, v) in zip(quad, [(u1, v0), (u0, v0), (u0, v1), (u1, v1)]):
                        prim["pos"].append(q)
                        prim["nrm"].append(n)
                        prim["uvs"].append((u / w, v / h))
                        prim["jnt"].append(j)
                    prim["idx"] += [base + o for o in order]
    prims = [prim for prim in prims if prim["pos"]]
    # every joint's rest place, and its place from its parent's
    rest, parent = {"root": (0.0, 0.0, 0.0)}, {"root": None}
    for p in parts:
        rest[p["name"]], parent[p["name"]] = gltf(p["pivot"]), p["parent"] or "root"
    local = {jname: tuple(rest[jname][i] - rest[parent[jname]][i] for i in range(3)) for jname in joints[1:]}
    # every key time of every segment, each animated joint keyed at all of them (rest outside its own); a segment's
    # first key sits 1 ms after the one that ends the segment before
    times, keyed = [], {}
    for s, (start, length, pose) in enumerate(segments):
        n = max(1, round(length * FPS))
        for i in range(n + 1):
            t = i / n * length
            times.append(round(start + t + (0.001 if i == 0 and s else 0), 4))
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
    primitives = []
    for prim in prims:
        attrs = {
            "POSITION": add("3f", prim["pos"], "VEC3", FLOAT, 34962, True),
            "NORMAL": add("3f", prim["nrm"], "VEC3", FLOAT, 34962),
            "TEXCOORD_0": add("2f", prim["uvs"], "VEC2", FLOAT, 34962),
            "JOINTS_0": add("4B", [(j, 0, 0, 0) for j in prim["jnt"]], "VEC4", UBYTE, 34962),
            "WEIGHTS_0": add("4f", [(1.0, 0.0, 0.0, 0.0)] * len(prim["pos"]), "VEC4", FLOAT, 34962),
        }
        primitives.append({"attributes": attrs, "indices": add("H", prim["idx"], "SCALAR", USHORT, 34963)})
    ibm = []
    for jname in joints:
        x, y, z = rest[jname]
        ibm.append((1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1))
    inverse = add("16f", ibm, "MAT4", FLOAT)
    nodes = [{"name": "root"}]
    for jname in joints[1:]:
        nodes.append({"name": jname, "translation": list(local[jname])})
    for j, jname in enumerate(joints):
        kids = [k for k, kname in enumerate(joints) if parent[kname] == jname]
        if kids:
            nodes[j]["children"] = kids
    nodes.append({"name": name, "mesh": 0, "skin": 0})
    channels, samplers = [], []
    tin = add("f", times, "SCALAR", FLOAT, None, True)
    for j, jname in enumerate(joints):
        for path in sorted(keyed.get(jname, ())):
            if path == "rotation":
                out = add("4f", [at(jname, t)[0] for t in times], "VEC4", FLOAT)
            else:
                moved = lambda d: tuple(r + o for r, o in zip(local[jname], (-d[0] * S, -d[1] * S, d[2] * S)))
                out = add("3f", [moved(at(jname, t)[1]) for t in times], "VEC3", FLOAT)
            samplers.append({"input": tin, "output": out, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": path}})
    doc = {
        "asset": {"version": "2.0", "generator": "goodluckOS dev/luanti-art/animals.py"},
        "scene": 0, "scenes": [{"nodes": [0, len(nodes) - 1]}], "nodes": nodes,
        "meshes": [{"primitives": primitives}],
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
    return sum(len(p["pos"]) for p in prims), sum(len(p["idx"]) for p in prims) // 3


for animal, (tex, parts, segments) in ANIMALS.items():
    print(animal, "%d vertices, %d triangles" % build(animal, tex, parts, segments))
print("meshes in", os.path.relpath(OUT, ROOT))
