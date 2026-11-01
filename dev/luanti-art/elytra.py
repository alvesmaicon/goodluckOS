#!/usr/bin/env python3
# The elytra and the firework rocket when the player has no Minecraft of their own: Pixel Perfection Legacy by Nova
# Wostra (CC BY-SA 4.0, https://modrinth.com/resourcepack/pixel-perfection-legacy, 26.3-97.2 unzipped), copied under
# goodluck_elytra's names, the rocket's sparks and smoke as strips of their frames. And the wings' mesh, Minecraft's
# ElytraModel on the body's top (10x20x2 each, 1 px bigger all round, 2 px behind the back), as goodluck_models'
# elytra.glb. Its animation holds the wings' poses as ElytraAnimationState sets them, frames in seconds: 0-1 spreading
# from folded (x 15, z -15 degrees) to the glide's (x 20, z -90), 1-2 folding back, 2-3 the crouch's (x 40, y 5,
# z -45, 3 px lower), 3-4 back
#   python3 dev/luanti-art/elytra.py <pixel perfection legacy dir> [textures dir] [models dir]
import contextlib, io, math, os, shutil, sys, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE + "/../.."
MODS = ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods"
SRC = sys.argv[1] + "/assets/minecraft/textures/"
TEX = sys.argv[2] if len(sys.argv) > 2 else MODS + "/goodluck_elytra/textures"
MODELS = sys.argv[3] if len(sys.argv) > 3 else MODS + "/goodluck_models/models"
FILES = {"entity/equipment/wings/elytra": "wings", "item/elytra": "elytra", "item/elytra_broken": "elytra_broken",
         "item/firework_rocket": "firework_rocket"}

os.makedirs(TEX, exist_ok=True)
for path, name in FILES.items():
    shutil.copyfile(SRC + path + ".png", f"{TEX}/goodluck_elytra_{name}.png")
# the rocket's trail (Minecraft's firework particle, spark_7 to spark_0 as it dies) and the smoke of its end (poof:
# generic_7 to generic_0), each a vertical strip for a particle's animation
for prefix, name in (("spark", "spark"), ("generic", "poof")):
    frames = [Image.open(f"{SRC}particle/{prefix}_{i}.png").convert("RGBA") for i in range(7, -1, -1)]
    w, h = frames[0].size
    strip = Image.new("RGBA", (w, h * len(frames)))
    for i, frame in enumerate(frames):
        strip.paste(frame, (0, i * h))
    strip.save(f"{TEX}/goodluck_elytra_{name}.png")

# animals.py builds every model when imported: into a scratch dir here, then only the elytra into goodluck_models
sys.path.insert(0, HERE)
argv, sys.argv = sys.argv, [sys.argv[0], tempfile.mkdtemp()]
with contextlib.redirect_stdout(io.StringIO()):
    import animals
from mcmodel import box
shutil.rmtree(sys.argv[1])
sys.argv = argv
animals.OUT = MODELS

D = math.radians
FOLDED, SPREAD, CROUCH = (D(15), 0, D(-15)), (D(20), 0, D(-90)), (D(40), D(5), D(-45))


def turn(rot, side):
    # the left wing's angles; the right one's y and z the other way, as ElytraModel.setupAnim mirrors them
    x, y, z = rot
    return animals.mc_rot(x, side * y, side * z)


def conj(q):
    return (-q[0], -q[1], -q[2], q[3])


# both wings' pivots at the top of the body (y 24 here, the mesh's origin), 5 px to each side, 2 px behind it
PARTS = [animals.part("left_wing", (5, 24, 2), box(22, 0, -10, 0, 0, 10, 20, 2, grow=1), rot=FOLDED),
         animals.part("right_wing", (-5, 24, 2), box(22, 0, 0, 0, 0, 10, 20, 2, grow=1, mirror=True),
                      rot=(FOLDED[0], 0, -FOLDED[2]))]


def pose(a, b, drop_a=0, drop_b=0):
    # from pose a to pose b as Minecraft lerps the angles, as a turn from the folded rest the mesh is built in
    def at(t):
        out = {}
        for joint, side in (("left_wing", 1), ("right_wing", -1)):
            rot = tuple(p + (q - p) * t for p, q in zip(a, b))
            q = animals.qmul(turn(rot, side), conj(turn(FOLDED, side)))
            out[joint] = (q, (0, drop_a + (drop_b - drop_a) * t, 0))
        return out
    return at


SEGMENTS = [(0, 1, pose(FOLDED, SPREAD)), (1, 1, pose(SPREAD, FOLDED)), (2, 1, pose(FOLDED, CROUCH, 0, 3)),
            (3, 1, pose(CROUCH, FOLDED, 3, 0))]
print("elytra %d vertices, %d triangles" % animals.build("elytra", (64, 32), PARTS, SEGMENTS))
print(len(FILES) + 2, "textures in", os.path.relpath(TEX, ROOT), "and the mesh in", os.path.relpath(MODELS, ROOT))
