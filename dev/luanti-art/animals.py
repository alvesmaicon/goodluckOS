#!/usr/bin/env python3
# goodluck_models' creatures and things: Minecraft's models for its textures' layouts (the cow, the pig, the sheep
# with its wool, the chicken, the horse, the donkey the mule shares, the spider, the zombie, the skeleton, the
# villager, the boat, the arrow, and the Nether's ghast, blaze, magma cube, zombified piglin and wither skeleton, as
# 26.x has them), one skinned mesh each, every part a joint, animated as Minecraft animates them.
# Written as binary glTF: Minecraft's model space (y down, the head toward -z, the right side toward -x) is turned to
# glTF's (the head toward -z, which Luanti's loader turns to +z, where a mob looks at yaw 0), 10 units a node. Frames
# are seconds: stand 0-1, walk from 1, run from 3, die 4-5, eat 6-8 (cow, sheep), rear 6-7.6 (horses), hit or aim
# 6-6.5 (zombie, skeleton, zombified piglin, wither skeleton), lay 8-8.1 (villager), flap from 9 (chicken), hop 1-2
# (magma cube); the blaze stands 0-10 and dies 11-12. The horses' saddle, bridle and chests and the skeletons' and
# the piglin's bow or sword are a second primitive, so that a texture of their own draws them, and nothing where it
# is blank
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


def part(name, pivot, faces, rot=(0, 0, 0), gear=(), parent=None, skin=()):
    # a joint: its boxes' faces in Minecraft's space, turned about its pivot at rest; gear faces go to the second
    # primitive; with a parent it follows that joint's turns; skin: quads (corners, uv, normals, the joint of each
    # corner) that stretch between joints
    return {"name": name, "pivot": pivot, "rot": rot, "faces": faces, "gear": list(gear), "parent": parent,
            "skin": list(skin)}


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

def quad(corners, uv):
    # a two-sided quad, in the build's groups of six faces: the two sides and four empty faces at its middle
    m = tuple(sum(c[i] for c in corners) / 4 for i in range(3))
    return [(corners, uv), ([corners[1], corners[0], corners[3], corners[2]], uv)] + [([m, m, m, m], uv)] * 4


def humanoid(thin, held=None):
    # Minecraft's humanoid: the head and the body hang from y 0, the arms from the shoulders, the legs from the hips;
    # the skeleton's limbs 2 pixels wide (64x32), the zombie's 4 (64x64, where the player's left limbs are blank),
    # both's left ones the right ones mirrored; held in place of the skeleton's bow
    head = box(0, 0, -4, -8, -4, 8, 8, 8) + box(32, 0, -4, -8, -4, 8, 8, 8, grow=0.5)
    if thin:
        right_arm, left_arm = box(40, 16, -1, -2, -1, 2, 12, 2), box(40, 16, -1, -2, -1, 2, 12, 2, mirror=True)
        right_leg, left_leg = box(0, 16, -1, 0, -1, 2, 12, 2), box(0, 16, -1, 0, -1, 2, 12, 2, mirror=True)
        hip = 2
    else:
        right_arm, left_arm = box(40, 16, -3, -2, -2, 4, 12, 4), box(40, 16, -1, -2, -2, 4, 12, 4, mirror=True)
        right_leg, left_leg = box(0, 16, -2, 0, -2, 4, 12, 4), box(0, 16, -2, 0, -2, 4, 12, 4, mirror=True)
        hip = 1.9
    # the skeleton's bow: its item image on a square in the right hand, across the arm, drawn by the second texture
    bow = quad([(8, 10, -8), (-8, 10, -8), (-8, 10, 8), (8, 10, 8)], (0, 0, 64, 32)) if thin else ()
    return [part("head", (0, 0, 0), head), part("body", (0, 0, 0), box(16, 16, -4, 0, -2, 8, 12, 4)),
            part("right_arm", (-5, 2, 0), right_arm, gear=bow if held is None else held),
            part("left_arm", (5, 2, 0), left_arm),
            part("right_leg", (-hip, 12, 0), right_leg), part("left_leg", (hip, 12, 0), left_leg)]


def affine(*steps):
    # 4x4 matrices multiplied in the order given: ("t", x, y, z), ("r", axis, degrees), ("s", k)
    m = [[float(i == j) for j in range(4)] for i in range(4)]
    for step in steps:
        n = [[float(i == j) for j in range(4)] for i in range(4)]
        if step[0] == "t":
            n[0][3], n[1][3], n[2][3] = step[1:]
        elif step[0] == "s":
            n[0][0] = n[1][1] = n[2][2] = step[1]
        else:
            i, j = {0: (1, 2), 1: (2, 0), 2: (0, 1)}[step[1]]
            c, s = math.cos(math.radians(step[2])), math.sin(math.radians(step[2]))
            n[i][i], n[i][j], n[j][i], n[j][j] = c, -s, s, c
        m = [[sum(m[i][k] * n[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
    return lambda p: tuple(16 * sum(m[i][k] * v for k, v in enumerate(p + (1,))) for i in range(3))


def held(tex, inward=0):
    # an item in the right hand as Minecraft draws it (ItemInHandLayer, item/handheld's thirdperson_righthand): from
    # the arm's pivot (the skeleton's moved inward 1) turned -90 about x and 180 about y, moved 1, 2 and -10 sixteenths,
    # then the display's 4 up and 0.5 ahead, 55 about z and -90 about y, 0.85 its size about its middle; its image on a
    # square at the middle of its thickness, each side as Minecraft's extruded item shows it, drawn whole by the second
    # texture (tex: the model's texture size, the unit of its uv)
    at = affine(("t", inward / 16, 0, 0), ("r", 0, -90), ("r", 1, 180), ("t", 1 / 16, 2 / 16, -10 / 16),
                ("t", 0, 4 / 16, 0.5 / 16), ("r", 1, -90), ("r", 2, 55), ("s", 0.85), ("t", -0.5, -0.5, -0.5))
    tr, tl, bl, br = (at((x, y, 0.5)) for x, y in ((1, 1), (0, 1), (0, 0), (1, 0)))
    w, h = tex
    mid = at((0.5, 0.5, 0.5))
    return [([tr, tl, bl, br], (0, 0, w, h)), ([tl, tr, br, bl], (w, 0, 0, h))] + [([mid] * 4, (0, 0, w, h))] * 4


def java_ints(seed, bound, n):
    # java.util.Random(seed).nextInt(bound), n of them
    mask = (1 << 48) - 1
    seed, out = (seed ^ 0x5DEECE66D) & mask, []
    while len(out) < n:
        seed = (seed * 0x5DEECE66D + 0xB) & mask
        bits = seed >> 17
        if bits - bits % bound + bound - 1 < 2 ** 31:
            out.append(bits % bound)
    return out


def ghast():
    # Minecraft's ghast: the body 16 a side about 17.6, nine tentacles 8 to 14 long (Random(1660)) from 24.6, in rows
    # of three half a step apart; the renderer scales it 4.5 about the ground (the mob's visual_size)
    parts = [part("body", (0, 17.6, 0), box(0, 0, -8, -8, -8, 16, 16, 16))]
    for i, extra in enumerate(java_ints(1660, 7, 9)):
        x = ((i % 3 - (i // 3 % 2) * 0.5 + 0.25) / 2 * 2 - 1) * 5
        z = ((i // 3) / 2 * 2 - 1) * 5
        parts.append(part("tentacle%d" % i, (x, 24.6, z), box(0, 0, -1, 0, -1, 2, extra + 8, 2)))
    return parts


def tentacles(t):
    # each swings 0.2 * sin(age * 0.3 + its number) + 0.4 about x
    return {"tentacle%d" % i: (mc_x(0.2 * math.sin(t * FPS * 0.3 + i) + 0.4), None) for i in range(9)}


# the blaze's rods: three rings of four, a quarter turn apart, going round once a second (-), every 10/3 s and every
# 2 s (-), at 9, 7 and 5 from the middle, bobbing; their bobbing a touch faster than Minecraft's (8 and 16 times
# where it goes 7.96 and 15.9) so that 10 s loop
BOB = (16 * PI / 200, 32 * PI / 200)


def rod(i, age):
    ring, k = divmod(i, 4)
    if ring == 0:
        f, r, y = age * PI * -0.1, 9, -2 + math.cos((2 * i + age) * BOB[0])
    elif ring == 1:
        f, r, y = PI / 4 + age * PI * 0.03, 7, 2 + math.cos((2 * i + age) * BOB[0])
    else:
        f, r, y = 0.47123894 + age * PI * -0.05, 5, 11 + math.cos((1.5 * i + age) * BOB[1])
    f += k * PI / 2
    return (math.cos(f) * r, y, math.sin(f) * r)


def blaze():
    # Minecraft's blaze: the head, and twelve rods of 2x8x2 that the animation carries round
    return [part("head", (0, 0, 0), box(0, 0, -4, -4, -4, 8, 8, 8))] + \
        [part("rod%d" % i, rod(i, 0), box(0, 16, 0, 0, 0, 2, 8, 2)) for i in range(12)]


def rods(t):
    age = t * FPS
    return {"rod%d" % i: (None, tuple(a - b for a, b in zip(rod(i, age), rod(i, 0)))) for i in range(12)}


def magma_cube():
    # Minecraft's magma cube since 26.x: eight slices of 8x1x8 from y 16, a joint each, around a core of 4; the
    # renderer scales it by its size (the mob's visual_size)
    parts = []
    for i in range(8):
        u, v = (0, 9 * i) if i < 4 else (32, 9 * i - 36)
        parts.append(part("slice%d" % i, (0, 0, 0), box(u, v, -4, 16 + i, -4, 8, 1, 8)))
    return parts + [part("core", (0, 0, 0), box(24, 40, -2, 18, -2, 4, 4, 4))]


def hop(t):
    # a jump: the slices part as Minecraft's squish does, from 1 at the jump easing to it by half a tick and dying
    # away 0.9 a tick, shown for a cube of size 2 (squish / (size * 0.5 + 1)): slice i moves -(4 - i) * 1.7 * squish;
    # the last 0.2 s close it
    s, target = 0.0, 1.0
    for _ in range(round(t * FPS)):
        s += (target - s) * 0.5
        target *= 0.9
    f = s / 2 * min(1.0, (1.0 - t) / 0.2)
    return {"slice%d" % i: (None, (0, -(4 - i) * 1.7 * f, 0)) for i in range(8)}


def zombified_piglin():
    # Minecraft's zombified piglin: the player's body on its 64x64 (the pants over the legs; no jacket, no hat, and
    # its sleeves are blank) with the piglin's wide head, snout, tusks and ears, a golden sword in the right hand
    head = box(0, 0, -5, -8, -4, 10, 8, 8) + box(31, 1, -2, -4, -5, 4, 4, 1) + box(2, 4, 2, -2, -5, 1, 2, 1) + \
        box(2, 0, -3, -2, -5, 1, 2, 1)
    leg = lambda u, v, pu, pv: box(u, v, -2, 0, -2, 4, 12, 4) + box(pu, pv, -2, 0, -2, 4, 12, 4, grow=0.25)
    return [part("head", (0, 0, 0), head),
            part("left_ear", (4.5, -6, 0), box(51, 6, 0, 0, -2, 1, 5, 4), rot=(0, 0, -PI / 6), parent="head"),
            part("right_ear", (-4.5, -6, 0), box(39, 6, -1, 0, -2, 1, 5, 4), rot=(0, 0, PI / 6), parent="head"),
            part("body", (0, 0, 0), box(16, 16, -4, 0, -2, 8, 12, 4)),
            part("right_arm", (-5, 2, 0), box(40, 16, -3, -2, -2, 4, 12, 4), gear=held((64, 64))),
            part("left_arm", (5, 2, 0), box(32, 48, -1, -2, -2, 4, 12, 4)),
            part("right_leg", (-1.9, 12, 0), leg(0, 16, 0, 32)), part("left_leg", (1.9, 12, 0), leg(16, 48, 0, 48))]


def ears(amount, period):
    # the piglin's ears flap out and in, a little standing, more with the step
    def pose(t):
        a = 2 * PI * t / period
        return {"left_ear": (mc_z(-math.cos(a) * amount), None), "right_ear": (mc_z(math.cos(a + 1) * amount), None)}
    return pose


def villager():
    # Minecraft's villager since 1.14: a tall head with its hat layer, the brim of a hat and the nose, the robe over
    # the body, the arms crossed and turned up, the legs
    rim = posed(box(30, 47, -8, -8, -6, 16, 16, 1), (0, 0, 0), (-PI / 2, 0, 0))
    head = box(0, 0, -4, -10, -4, 8, 10, 8) + box(32, 0, -4, -10, -4, 8, 10, 8, grow=0.51) + \
        box(24, 0, -1, -3, -6, 2, 4, 2) + rim
    arms = box(44, 22, -8, -2, -2, 4, 8, 4) + box(44, 22, 4, -2, -2, 4, 8, 4, mirror=True) + \
        box(40, 38, -4, 2, -2, 8, 4, 4)
    return [part("head", (0, 0, 0), head),
            part("body", (0, 0, 0), box(16, 20, -4, 0, -3, 8, 12, 6) + box(0, 38, -4, 0, -3, 8, 18, 6, grow=0.5)),
            part("arms", (0, 2, 0), arms, rot=(-0.75, 0, 0)),
            part("right_leg", (-2, 12, 0), box(0, 22, -2, 0, -2, 4, 12, 4)),
            part("left_leg", (2, 12, 0), box(0, 22, -2, 0, -2, 4, 12, 4, mirror=True))]


def stride(legs, arms, period):
    # Minecraft's humanoid walk: the legs cos(limb swing * 0.6662) * 1.4 * swing amount, each arm with the other leg
    # at 2 * 0.5 * the amount
    def pose(t):
        a = math.sin(2 * PI * t / period)
        return {"right_leg": (mc_x(legs * a), None), "left_leg": (mc_x(-legs * a), None),
                "right_arm": (mc_x(-arms * a), None), "left_arm": (mc_x(arms * a), None)}
    return pose


def sway(t):
    # the arms at rest: out by cos(age * 0.09) * 0.05 + 0.05 and back and forth by sin(age * 0.067) * 0.05
    z, x = math.cos(2 * PI * t) * 0.05 + 0.05, math.sin(2 * PI * t) * 0.05
    return {"right_arm": (mc_rot(x, 0, z), None), "left_arm": (mc_rot(-x, 0, -z), None)}


def zombie_arms(up, hit=None):
    # Minecraft's zombie: the arms up at -pi/2.25 (-pi/1.5 at someone), a little in; hitting, they swing down by
    # sin(attack * pi) * 1.2 and come back; the sway on top
    def pose(t):
        f = g = 0.0
        if hit:
            f, g = math.sin(t / hit * PI), math.sin((1 - (1 - t / hit) ** 2) * PI)
        x = up + f * 1.2 - g * 0.4
        z, bob = math.cos(2 * PI * t) * 0.05 + 0.05, math.sin(2 * PI * t) * 0.05
        return {"right_arm": (mc_rot(x + bob, -(0.1 - f * 0.6), z), None),
                "left_arm": (mc_rot(x - bob, 0.1 - f * 0.6, -z), None)}
    return pose


def aim(t):
    # the skeleton's bow up: both arms straight ahead, the right one a little in
    return {"right_arm": (mc_rot(-PI / 2, -0.1, 0), None), "left_arm": (mc_rot(-PI / 2, 0.1, 0), None)}


def lay(t):
    # on the back, the head toward the model's back, moved half its height ahead so that it lies about its position
    # (sleep.lua puts a villager at the bed's middle) and 3 pixels up so that the back lies on the bed
    return {"root": (mc_x(-PI / 2), (0, -3, -12))}


ZOMBIE_UP = -PI / 2.25
ZOMBIE = [(0, 1, zombie_arms(ZOMBIE_UP)), (1, 1.0, both(zombie_arms(ZOMBIE_UP), stride(0.7, 0, 1.0))),
          (3, 0.5, both(zombie_arms(ZOMBIE_UP), stride(1.4, 0, 0.5))), (4, 1, both(die, zombie_arms(ZOMBIE_UP))),
          (6, 0.5, zombie_arms(-PI / 1.5, 0.5))]
SKELETON = [(0, 1, sway), (1, 1.0, stride(0.7, 0.5, 1.0)), (3, 0.5, stride(1.4, 1.0, 0.5)), (4, 1, die), (6, 0.5, aim)]
# the zombified piglin's arms as the zombie's, higher at someone; the wither skeleton's straight ahead at someone, as
# 26.x's skeleton holding no bow
ANGRY = -PI / 1.5
PIGLIN = [(0, 1, both(zombie_arms(ZOMBIE_UP), ears(0.08, 1))),
          (1, 1.0, both(zombie_arms(ZOMBIE_UP), both(stride(0.7, 0, 1.0), ears(0.2, 1.0)))),
          (3, 0.5, both(zombie_arms(ANGRY), both(stride(1.4, 0, 0.5), ears(0.35, 0.5)))),
          (4, 1, both(die, zombie_arms(ZOMBIE_UP))), (6, 0.5, zombie_arms(ANGRY, 0.5))]
WITHER_SKELETON = [(0, 1, sway), (1, 1.0, stride(0.7, 0.5, 1.0)),
                   (3, 0.5, both(zombie_arms(-PI / 2), stride(1.4, 0, 0.5))), (4, 1, die),
                   (6, 0.5, zombie_arms(-PI / 2, 0.5))]
GHAST = [(0, 2 * PI / (0.3 * FPS), tentacles), (4, 1, both(die, tentacles))]
BLAZE = [(0, 10, rods), (11, 1, both(die, rods))]
MAGMA_CUBE = [(0, 1, None), (1, 1.0, hop), (4, 1, die)]
VILLAGER = [(0, 1, None), (1, 1.0, stride(0.7, 0, 1.0)), (3, 0.5, stride(1.4, 0, 0.5)), (4, 1, die), (8, 0.1, lay)]


# The witch (goodluck_monsters), 64x128: stands 0-1, walks 1-2, runs 3-3.5, dies 4-5; drinking it stands 6-6.1 and
# walks 7-8, its nose up with the potion at it (the second texture, blank but then)
def witch():
    # Minecraft's witch: the villager's body as VillagerModel.createBodyModel has it in 26.x (the robe 20 long, the
    # crossed arms from (0, 3, -1)) under a head without the villager's hat layer; the hat a brim and three tiers, each
    # on the one below it, a little turned; the nose with its mole, and the potion in front of it when it drinks
    hat = posed(box(0, 95, 0, 0, 0, 1, 2, 1, grow=0.25), (1.75, -2, 2), (-0.20943952, 0, 0.10471976))
    hat = posed(box(0, 87, 0, 0, 0, 4, 4, 4) + hat, (1.75, -4, 2), (-0.10471976, 0, 0.05235988))
    hat = posed(box(0, 76, 0, 0, 0, 7, 4, 7) + hat, (1.75, -4, 2), (-0.05235988, 0, 0.02617994))
    hat = posed(box(0, 64, 0, 0, 0, 10, 2, 10) + hat, (-5, -10.03125, -5))
    nose = box(24, 0, -1, -1, -6, 2, 4, 2) + posed(box(0, 0, 0, 3, -6.75, 1, 1, 1, grow=-0.25), (0, -2, 0))
    arms = box(44, 22, -8, -2, -2, 4, 8, 4) + box(44, 22, 4, -2, -2, 4, 8, 4, mirror=True) + \
        box(40, 38, -4, 2, -2, 8, 4, 4)
    return [part("head", (0, 0, 0), box(0, 0, -4, -10, -4, 8, 10, 8) + hat),
            part("nose", (0, -2, 0), nose, gear=potion((64, 128)), parent="head"),
            part("body", (0, 0, 0), box(16, 20, -4, 0, -3, 8, 12, 6) + box(0, 38, -4, 0, -3, 8, 20, 6, grow=0.5)),
            part("arms", (0, 3, -1), arms, rot=(-0.75, 0, 0)),
            part("right_leg", (-2, 12, 0), box(0, 22, -2, 0, -2, 4, 12, 4)),
            part("left_leg", (2, 12, 0), box(0, 22, -2, 0, -2, 4, 12, 4, mirror=True))]


def potion(tex):
    # the potion held at the nose as WitchItemLayer draws it: 1 and 4 pixels from the nose's pivot, turned 180 about
    # z, 140 about x, 10 about z and 180 about x, then item/generated's ground display (2 up, half its size) about its
    # middle; its image on a two-sided square, as held() draws an item
    at = affine(("t", 1 / 16, 4 / 16, 0), ("r", 2, 180), ("r", 0, 140), ("r", 2, 10), ("r", 0, 180),
                ("t", 0, 2 / 16, 0), ("s", 0.5), ("t", -0.5, -0.5, -0.5))
    tr, tl, bl, br = (at((x, y, 0.5)) for x, y in ((1, 1), (0, 1), (0, 0), (1, 0)))
    w, h = tex
    mid = at((0.5, 0.5, 0.5))
    return [([tr, tl, bl, br], (0, 0, w, h)), ([tl, tr, br, bl], (w, 0, 0, h))] + [([mid] * 4, (0, 0, w, h))] * 4


def sip(t):
    # holding a potion its nose goes to (0, 1, -1.5) and turns -0.9 about x
    return {"nose": (mc_x(-0.9), (0, 3, -1.5))}


# its legs swing half as far as the player's, as the villager's
WITCH = [(0, 1, None), (1, 1.0, stride(0.7, 0, 1.0)), (3, 0.5, stride(0.7, 0, 0.5)), (4, 1, die), (6, 0.1, sip),
         (7, 1.0, both(sip, stride(0.7, 0, 1.0)))]


def boat():
    # Minecraft's boat since 1.14, its bow at +x in its model, turned a quarter so that the bow leads, and 18 down so
    # that the entity sits at the waterline (its renderer lifts the model 6 pixels): the floor's underside on it, the
    # sides on the floor; the paddles rest on the sides
    def piece(u, v, x, y, z, w, h, d, pivot, rot=(0, 0, 0)):
        return posed(box(u, v, x, y, z, w, h, d), pivot, rot)
    paddle = lambda u, v, x: box(u, v, -1, 0, -5, 2, 2, 18) + box(u, v, x, -3, 8, 1, 6, 7)
    faces = piece(0, 0, -14, -9, -3, 28, 16, 3, (0, 3, 1), (PI / 2, 0, 0)) + \
        piece(0, 19, -13, -7, -1, 18, 6, 2, (-15, 4, 4), (0, PI * 1.5, 0)) + \
        piece(0, 27, -8, -7, -1, 16, 6, 2, (15, 4, 0), (0, PI / 2, 0)) + \
        piece(0, 35, -14, -7, -1, 28, 6, 2, (0, 4, -9), (0, PI, 0)) + \
        piece(0, 43, -14, -7, -1, 28, 6, 2, (0, 4, 9)) + \
        posed(paddle(62, 0, -1.001), (3, -5, 9), (0, 0, 0.19634955)) + \
        posed(paddle(62, 20, 0.001), (3, -5, -9), (0, PI, 0.19634955))
    return [part("boat", (0, 0, 0), posed(faces, (0, 18, 0), (0, PI / 2, 0)))]


def arrow():
    # Minecraft's arrow: two fins 16 by 4 crossed at an eighth of a turn and the tip a square of 4, the tip 4 pixels
    # ahead of the entity (its renderer draws it 0.9 of a pixel a unit: visual_size 0.9); its model points at -x,
    # here at -z
    z0, z1 = -12, 4
    faces = quad([(0, -2, z1), (0, -2, z0), (0, 2, z0), (0, 2, z1)], (0, 0, 16, 5)) + \
        quad([(-2, 0, z1), (-2, 0, z0), (2, 0, z0), (2, 0, z1)], (0, 0, 16, 5)) + \
        quad([(-2, -2, -11), (2, -2, -11), (2, 2, -11), (-2, 2, -11)], (0, 5, 5, 10))
    return [part("arrow", (0, 0, 0), posed(faces, (0, 24, 0), (0, 0, PI / 4)))]


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
    "zombie": ((64, 64), humanoid(False), ZOMBIE),
    "skeleton": ((64, 32), humanoid(True), SKELETON),
    "villager": ((64, 64), villager(), VILLAGER),
    "boat": ((128, 64), boat(), [(0, 1, None)]),
    "arrow": ((32, 32), arrow(), [(0, 1, None)]),
    "ghast": ((64, 32), ghast(), GHAST),
    "blaze": ((64, 32), blaze(), BLAZE),
    "magma_cube": ((64, 64), magma_cube(), MAGMA_CUBE),
    "zombified_piglin": ((64, 64), zombified_piglin(), PIGLIN),
    # the wither skeleton is the skeleton with a stone sword (the renderer draws it 1.2 times as big)
    "wither_skeleton": ((64, 32), humanoid(True, held((64, 32), 1)), WITHER_SKELETON),
    "witch": ((64, 128), witch(), WITCH),
}


# The End's creatures (goodluck_end), as 26.x has them: the enderman, whose head lifts off its jaw when angry
# (run 3-3.5, hit 6-6.5), and the silverfish, wriggling all the time


def enderman():
    # Minecraft's enderman: the humanoid 14 up, its limbs 2 a side and 30 long; the hat layer is the jaw the head
    # leaves behind
    limb = lambda m, y: box(56, 0, -1, y, -1, 2, 30, 2, mirror=m)
    return [part("head", (0, -13, 0), box(0, 0, -4, -8, -4, 8, 8, 8)),
            part("jaw", (0, -13, 0), box(0, 16, -4, -8, -4, 8, 8, 8, grow=-0.5)),
            part("body", (0, -14, 0), box(32, 16, -4, 0, -2, 8, 12, 4)),
            part("right_arm", (-5, -12, 0), limb(False, -2)), part("left_arm", (5, -12, 0), limb(True, -2)),
            part("right_leg", (-2, -5, 0), limb(False, 0)), part("left_leg", (2, -5, 0), limb(True, 0))]


def angry(t):
    return {"head": (None, (0, -5, 0))}


def ender_hit(t):
    # the right arm swung down from forward, as HumanoidModel's attack, with the head up
    f = math.sin(t / 0.5 * PI)
    return {"head": (None, (0, -5, 0)), "right_arm": (mc_x(-f * 1.2), None)}


# its walk is the humanoid's at half the swing, never past 0.4
ENDERMAN = [(0, 1, None), (1, 1.0, stride(0.4, 0.4, 1.0)), (3, 0.5, both(angry, stride(0.4, 0.4, 0.5))), (4, 1, die),
            (6, 0.5, ender_hit)]

SILVERFISH_SIZES = [(3, 2, 2), (4, 3, 2), (6, 4, 3), (3, 3, 3), (2, 2, 3), (2, 1, 2), (1, 1, 2)]
SILVERFISH_UV = [(0, 0), (0, 4), (0, 9), (0, 16), (0, 22), (11, 0), (13, 4)]


def silverfish_z():
    z, out = -3.5, []
    for i, (_, _, d) in enumerate(SILVERFISH_SIZES):
        out.append(z)
        if i < 6:
            z += (d + SILVERFISH_SIZES[i + 1][2]) * 0.5
    return out


def silverfish():
    # Minecraft's silverfish: seven segments from the head (-z) on the ground, three bristle layers over 2, 4 and 1
    z = silverfish_z()
    parts = []
    for i, ((w, h, d), (u, v)) in enumerate(zip(SILVERFISH_SIZES, SILVERFISH_UV)):
        parts.append(part("segment%d" % i, (0, 24 - h, z[i]), box(u, v, -w * 0.5, 0, -d * 0.5, w, h, d)))
    d2, d4, d1 = SILVERFISH_SIZES[2][2], SILVERFISH_SIZES[4][2], SILVERFISH_SIZES[1][2]
    parts.append(part("layer0", (0, 16, z[2]), box(20, 0, -5, 0, -d2 * 0.5, 10, 8, d2)))
    parts.append(part("layer1", (0, 20, z[4]), box(20, 11, -3, 0, -d4 * 0.5, 6, 4, d4)))
    parts.append(part("layer2", (0, 19, z[1]), box(20, 18, -3, 0, -d4 * 0.5, 6, 5, d1)))
    return parts


def wriggle(t):
    # each segment turns cos(age * 0.9 + i * 0.15 pi) * pi * 0.05 * (1 + |i - 2|) and sways sin(...) * pi * 0.2 *
    # |i - 2|, three times a second (Minecraft's 0.35 s); the layers go with their segments
    pose = {}
    for i in range(7):
        a = 2 * PI * 3 * t + i * 0.15 * PI
        pose["segment%d" % i] = (mc_y(math.cos(a) * PI * 0.05 * (1 + abs(i - 2))), (math.sin(a) * PI * 0.2 * abs(i - 2), 0, 0))
    for layer, seg in (("layer0", 2), ("layer1", 4), ("layer2", 1)):
        pose[layer] = pose["segment%d" % seg]
    return pose


SILVERFISH = [(0, 1, wriggle), (1, 1.0, wriggle), (4, 1, both(die, wriggle))]


def axis_quat(axis, a):
    s = math.sin(a / 2)
    return (axis[0] * s, axis[1] * s, axis[2] * s, math.cos(a / 2))


# the crystal's tilt: 60 degrees about Minecraft's (sin 45, 0, sin 45), glTF's (-sin 45, 0, sin 45)
TILT = axis_quat((-math.sin(PI / 4), 0, math.sin(PI / 4)), PI / 3)


def end_crystal():
    # Minecraft's end crystal (drawn at twice its size, the mob's visual_size): its base 12x4x12 sunk half a node
    # under it, the outer glass, the inner glass (0.875 of it) and the cube (0.766 of that) about one middle
    glass = lambda u, grow: box(u, 0, -4, -4, -4, 8, 8, 8, grow=grow)
    return [part("base", (0, 0, 0), box(0, 16, -6, 28, -6, 12, 4, 12)),
            part("outer", (0, 16, 0), glass(0, 0)),
            part("inner", (0, 16, 0), glass(0, -0.5), parent="outer"),
            part("cube", (0, 16, 0), glass(32, 4 * 0.875 * 0.765625 - 4), parent="inner")]


def spin(t):
    # 3 degrees a tick about y, the glass bobbing (Minecraft's sin(age * 0.2), here 4 times in the 6 s loop)
    a = math.radians(t * FPS * 3)
    f = math.sin(2 * PI * 4 * t / 6) / 2 + 0.5
    y = (f * f + f) * 0.4 - 1.4
    ry = mc_y(a)
    return {"outer": (qmul(ry, TILT), (0, -8 - 8 * y, 0)), "inner": (qmul(TILT, ry), None), "cube": (qmul(TILT, ry), None)}


def dragon_box(x, y, z, w, h, d, u, v, mirror=False):
    return box(u, v, x, y, z, w, h, d, mirror=mirror)


def pitch_off(off, rx):
    # a child's offset turned by its parent's rest pitch, as posed() turns a box
    x, y, z = off
    return (x, y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx))


def add(a, b):
    return tuple(i + j for i, j in zip(a, b))


NECK_REST = [(0, 20, -12 - i * 10) for i in range(5)]
TAIL_REST = [(0, 10, 60 + i * 10) for i in range(12)]
HEAD_REST = (0, 20, -62)


def ender_dragon():
    # Minecraft's ender dragon (EnderDragonModel, 256x256): the head with its jaw, five neck and twelve tail
    # segments (each a joint of its own, placed by the animation as Minecraft chains them), the body with its wings
    # and their tips, and the legs in three parts, each turned on from the one before; all under the root, which the
    # animation lifts, moves 48 forward and tilts
    head = dragon_box(-6, -1, -24, 12, 5, 16, 176, 44) + dragon_box(-8, -8, -10, 16, 16, 16, 112, 30) + \
        dragon_box(-5, -12, -4, 2, 4, 6, 0, 0, True) + dragon_box(-5, -3, -22, 2, 2, 4, 112, 0, True) + \
        dragon_box(3, -12, -4, 2, 4, 6, 0, 0, True) + dragon_box(3, -3, -22, 2, 2, 4, 112, 0, True)
    segment = lambda: dragon_box(-5, -5, -5, 10, 10, 10, 192, 104) + dragon_box(-1, -9, -3, 2, 4, 6, 48, 0)
    parts = [part("head", HEAD_REST, head),
             part("jaw", add(HEAD_REST, (0, 4, -8)), dragon_box(-6, 0, -16, 12, 4, 16, 176, 65), parent="head")]
    parts += [part("neck%d" % i, NECK_REST[i], segment()) for i in range(5)]
    parts += [part("tail%d" % i, TAIL_REST[i], segment()) for i in range(12)]
    body_at = (0, 20, 8)
    body = dragon_box(-12, -16, -16, 24, 24, 64, 0, 0) + sum(
        (dragon_box(-1, -22, z, 2, 6, 12, 220, 53) for z in (-10, 10, 30)), [])
    parts.append(part("body", body_at, body))
    for side, k in (("left", 1), ("right", -1)):
        m = side == "left"
        x0 = 0 if m else -56
        wing = add(body_at, (12 * k, -15, -6))
        parts.append(part(side + "_wing", wing, dragon_box(x0, -4, -4, 56, 8, 8, 112, 88, m) +
                          dragon_box(x0, 0, 2, 56, 0, 56, -56, 88, m), parent="body"))
        parts.append(part(side + "_wing_tip", add(wing, (56 * k, 0, 0)), dragon_box(x0, -2, -2, 56, 4, 4, 112, 136, m) +
                          dragon_box(x0, 0, 2, 56, 0, 56, -56, 144, m), parent=side + "_wing"))
        for leg, at, legs in (("front", (12 * k, 0, -6), ((1.3, (-4, -4, -4, 8, 24, 8, 112, 104)),
                                                       ((0, 20, -1), -0.5, (-3, -1, -3, 6, 24, 6, 226, 138)),
                                                       ((0, 23, 0), 0.75, (-4, 0, -12, 8, 4, 16, 144, 104)))),
                              ("hind", (16 * k, -4, 34), ((1.0, (-8, -4, -8, 16, 32, 16, 0, 0)),
                                                        ((0, 32, -4), 0.5, (-6, -2, 0, 12, 32, 12, 196, 0)),
                                                        ((0, 31, 4), 0.75, (-9, 0, -20, 18, 6, 24, 112, 0))))):
            rx, b = legs[0]
            pivot = add(body_at, at)
            names = [side + "_" + leg + "_leg", side + "_" + leg + "_leg_tip", side + "_" + leg + "_foot"]
            parts.append(part(names[0], pivot, dragon_box(*b), rot=(rx, 0, 0), parent="body"))
            for j, (off, drx, b) in enumerate(legs[1:], 1):
                pivot = add(pivot, pitch_off(off, rx))
                rx += drx
                parts.append(part(names[j], pivot, dragon_box(*b), rot=(rx, 0, 0), parent=names[j - 1]))
    return parts


def dragon_pose(period):
    # EnderDragonModel.setupAnim in a straight, level flight (its flight history all alike): the wings beat, the jaw
    # opens and shuts, the body heaves and the legs with it, the neck and the tail wave as they are chained segment by
    # segment, 10 apart
    def pose(t):
        f = 2 * PI * t / period
        out = {"jaw": (mc_x((math.sin(f) + 1) * 0.2), None)}
        l3 = math.sin(f - 1) + 1
        l3 = (l3 * l3 + l3 * 2) * 0.05
        out["root"] = (mc_x(math.radians(l3 * 2)), (0, (l3 - 2) * 16, -48))
        x, y, z = NECK_REST[0]
        for i in range(5):
            rx = math.cos(i * 0.45 + f) * 0.15
            out["neck%d" % i] = (mc_x(rx), (x - NECK_REST[i][0], y - NECK_REST[i][1], z - NECK_REST[i][2]))
            y += math.sin(rx) * 10
            z -= math.cos(rx) * 10
        out["head"] = (None, (x - HEAD_REST[0], y - HEAD_REST[1], z - HEAD_REST[2]))
        wx, wz = 0.125 - math.cos(f) * 0.2, -(math.sin(f) + 0.125) * 0.8
        tip = (math.sin(f + 2) + 0.5) * 0.75
        out["left_wing"] = (mc_rot(wx, -0.25, wz), None)
        out["right_wing"] = (mc_rot(wx, 0.25, -wz), None)
        out["left_wing_tip"] = (mc_z(tip), None)
        out["right_wing_tip"] = (mc_z(-tip), None)
        for side in ("left", "right"):
            out[side + "_front_leg"] = (mc_x(l3 * 0.1), None)
            out[side + "_front_leg_tip"] = (mc_x(-l3 * 0.1), None)
            out[side + "_front_foot"] = (mc_x(l3 * 0.1), None)
            for k in ("_hind_leg", "_hind_leg_tip", "_hind_foot"):
                out[side + k] = (mc_x(l3 * 0.1), None)
        x, y, z = TAIL_REST[0]
        sway = 0.0
        for i in range(12):
            sway += math.sin(i * 0.45 + f) * 0.05
            out["tail%d" % i] = (mc_x(-sway), (x - TAIL_REST[i][0], y - TAIL_REST[i][1], z - TAIL_REST[i][2]))
            y += math.sin(sway) * 10
            z += math.cos(sway) * 10
        return out
    return pose


# flying 0-1.75 (Minecraft's beat at full speed), perched 2-2.5 (its 0.1 a tick)
DRAGON = [(0, 1.75, dragon_pose(1.75)), (2, 0.5, dragon_pose(0.5))]

# The crystal's beam to the dragon (EnderDragonRenderer's): 8 sides, 0.75 round at the crystal and a fifth of that at
# the far end, one node from the joint "beam" toward -z (Luanti's +z), which the entity turns and stretches to the
# dragon. Minecraft scrolls its texture toward the crystal; here 8 rings slide an eighth of the way toward it in 0.6 s
# and start over, the texture's 32 rows between each two (as Minecraft's 8 a node on a beam of 32)
BEAM_RINGS, BEAM_LOOP = 8, 0.6


def beam_radius(f):
    # in pixels, f of the way from the crystal
    return 12 - 9.6 * f


def crystal_beam():
    rings = [("beam", 0.0)] + [("ring%d" % k, (k + 1) / BEAM_RINGS) for k in range(BEAM_RINGS)] + [("beam", 1.0)]
    at = lambda f, a: (beam_radius(f) * math.sin(a), 24 + beam_radius(f) * math.cos(a), -16 * f)
    out = lambda a: (math.sin(a), math.cos(a), 0)
    skin = []
    for (near, f0), (far, f1) in zip(rings, rings[1:]):
        for j in range(8):
            a0, a1 = 2 * PI * j / 8, 2 * PI * (j + 1) / 8
            skin.append(([at(f1, a1), at(f1, a0), at(f0, a0), at(f0, a1)], (2 * j, 0, 2 * j + 2, 32),
                         [out(a1), out(a0), out(a0), out(a1)], [far, far, near, near]))
    return [part("beam", (0, 24, 0), [], skin=skin)] + \
        [part(name, (0, 24, -16 * f), [], parent="beam") for name, f in rings[1:-1]]


def slide(t):
    # each ring toward the crystal, its round growing as the beam's does there
    phi = t / BEAM_LOOP
    pose = {}
    for k in range(BEAM_RINGS):
        f = (k + 1) / BEAM_RINGS
        s = beam_radius(f - phi / BEAM_RINGS) / beam_radius(f)
        pose["ring%d" % k] = (None, (0, 0, 16 * phi / BEAM_RINGS), (s, s, 1.0))
    return pose


ANIMALS.update({"enderman": ((64, 32), enderman(), ENDERMAN), "silverfish": ((64, 32), silverfish(), SILVERFISH),
                "end_crystal": ((64, 32), end_crystal(), [(0, 6, spin)]),
                "ender_dragon": ((256, 256), ender_dragon(), DRAGON),
                "crystal_beam": ((16, 32), crystal_beam(), [(0, BEAM_LOOP, slide)])})


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
    for p in parts:
        for corners, (u0, v0, u1, v1), normals, owners in p["skin"]:
            prim, base = prims[0], len(prims[0]["pos"])
            for q, (u, v), n, o in zip(corners, [(u1, v0), (u0, v0), (u0, v1), (u1, v1)], normals, owners):
                prim["pos"].append(gltf(q))
                prim["nrm"].append((-n[0], -n[1], n[2]))
                prim["uvs"].append((u / w, v / h))
                prim["jnt"].append(joints.index(o))
            prim["idx"] += [base + o for o in (0, 1, 2, 0, 2, 3)]
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
                # a joint's key: its turn, its move and (if given) its scale
                for jname, key in pose(t).items():
                    r, d, s = (tuple(key) + (None,))[:3]
                    keyed.setdefault(jname, set()).update(["rotation"] if r else [])
                    keyed[jname].update(["translation"] if d else [])
                    keyed[jname].update(["scale"] if s else [])
    times = sorted(set(times))

    def at(jname, time):
        for start, length, pose in segments:
            if pose and start - 1e-6 <= time <= start + length + 1e-6:
                r, d, s = (tuple(pose(time - start).get(jname, (None, None))) + (None,))[:3]
                return r or (0.0, 0.0, 0.0, 1.0), d or (0, 0, 0), s or (1.0, 1.0, 1.0)
        return (0.0, 0.0, 0.0, 1.0), (0, 0, 0), (1.0, 1.0, 1.0)

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
            elif path == "scale":
                out = add("3f", [at(jname, t)[2] for t in times], "VEC3", FLOAT)
            else:
                moved = lambda d: tuple(r + o for r, o in zip(local.get(jname, (0.0, 0.0, 0.0)), (-d[0] * S, -d[1] * S, d[2] * S)))
                out = add("3f", [moved(at(jname, t)[1]) for t in times], "VEC3", FLOAT)
            samplers.append({"input": tin, "output": out, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": path}})
    doc = {
        "asset": {"version": "2.0", "generator": "goodluckOS dev/luanti-art/animals.py"},
        "scene": 0, "scenes": [{"nodes": [0, len(nodes) - 1]}], "nodes": nodes,
        "meshes": [{"primitives": primitives}],
        "skins": [{"joints": list(range(len(joints))), "inverseBindMatrices": inverse, "skeleton": 0}],
        "animations": channels and [{"name": "all", "channels": channels, "samplers": samplers}] or None,
        "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors,
    }
    # a still thing (the boat, the arrow) has no animation: glTF allows none, not an empty one
    doc = {k: v for k, v in doc.items() if v is not None}
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
