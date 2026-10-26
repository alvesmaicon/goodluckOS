#!/usr/bin/env python3
# goodluck_models' meshes: Minecraft's shapes for its texture layouts, so its textures (and Pixel Perfection's, the
# default) fit them. Boxes are given as Minecraft lays them out, a texture offset and a size each, unwrapped the way
# its models are (top and bottom over the four sides); block models as their elements, a face's uv an area of the
# texture. Written as OBJ, for nodes (1 unit a node) and entities (10 units a node)
#   python3 dev/luanti-art/models.py [out dir]
import math, os, sys
from mcmodel import box, element, posed

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/../.."
OUT = sys.argv[1] if len(sys.argv) > 1 else \
    ROOT + "/rootfs/board/my-device/rootfs-overlay/usr/share/luanti/games/minetest_game/mods/goodluck_models/models"


def write(name, faces, tex, scale=1 / 16, centre=(8, 0, 8), lift=0):
    # Minecraft's north is -z, Luanti's +z; the OBJ loader takes x mirrored: both flips at once are a half turn
    w, h = tex
    lines = ["# goodluck_models, drawn by dev/luanti-art/models.py"]
    vs, vts = [], []
    for corners, (u0, v0, u1, v1) in faces:
        for (x, y, z), (u, v) in zip(corners, [(u1, v0), (u0, v0), (u0, v1), (u1, v1)]):
            vs.append(((centre[0] - x) * scale, (y - centre[1]) * scale + lift, (centre[2] - z) * scale))
            vts.append((u / w, 1 - v / h))
    lines += ["v %.5f %.5f %.5f" % p for p in vs] + ["vt %.5f %.5f" % t for t in vts]
    for i in range(0, len(vs), 4):
        lines.append("f " + " ".join("%d/%d" % (i + k + 1, i + k + 1) for k in range(4)))
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/{name}", "w") as f:
        f.write("\n".join(lines) + "\n")


# the chest, its lid and latch turning together on the lid's hinge (open: Minecraft's 90 degrees)
def chest(width_left=None, open_=False):
    lid = (-math.pi / 2 if open_ else 0, 0, 0)
    if width_left is None:
        parts = posed(box(0, 19, 1, 0, 1, 14, 10, 14)) + posed(box(0, 0, 1, 0, 0, 14, 5, 14), (0, 9, 1), lid) + \
            posed(box(0, 0, 7, -2, 14, 2, 4, 1), (0, 9, 1), lid)
    elif width_left:
        parts = posed(box(0, 19, 1, 0, 1, 15, 10, 14)) + posed(box(0, 0, 1, 0, 0, 15, 5, 14), (0, 9, 1), lid) + \
            posed(box(0, 0, 15, -2, 14, 1, 4, 1), (0, 9, 1), lid)
    else:
        parts = posed(box(0, 19, 0, 0, 1, 15, 10, 14)) + posed(box(0, 0, 0, 0, 0, 15, 5, 14), (0, 9, 1), lid) + \
            posed(box(0, 0, 0, -2, 14, 1, 4, 1), (0, 9, 1), lid)
    return parts


for name, half in (("chest", None), ("chest_left", True), ("chest_right", False)):
    write(f"goodluck_models_{name}.obj", chest(half), (64, 64), lift=-0.5)
    write(f"goodluck_models_{name}_open.obj", chest(half, True), (64, 64), lift=-0.5)

# the sign's board (its texture 32x32, uv in sixteenths of it); on a wall it lies as on the floor, the engine turns it
BOARD = {"north": (0, 8, 12, 14), "east": (12, 1, 13, 7), "south": (0, 1, 12, 7), "west": (12, 8, 13, 14),
         "up": (0, 0, 12, 1), "down": (0, 14, 12, 15)}
POST = {"north": (14, 8, 15, 15), "east": (15, 0, 16, 7), "south": (14, 0, 15, 7), "west": (15, 8, 16, 15),
        "down": (14, 15, 15, 16)}
t = 4 / 3
wall = posed(element((0, 4 + 1 / 3, 1 / 3), (16, 12 + 1 / 3, 1 + 2 / 3), BOARD), (0, 0, 0), (0, 0, 0))
# laid on the floor: the board's back (north) down
wall = [([(x, z, 16 - y) for x, y, z in c], uv) for c, uv in wall]
write("goodluck_models_sign_wall.obj", wall, (16, 16), lift=-0.5)
standing = element((8 - t / 2, 0, 8 - t / 2), (8 + t / 2, 9 + 1 / 3, 8 + t / 2), POST) + \
    element((0, 9 + 1 / 3, 8 - t / 2), (16, 17 + 1 / 3, 8 + t / 2), BOARD)
write("goodluck_models_sign_standing.obj", standing, (16, 16), lift=-0.5)

# the minecart: a floor and four sides, 64x32
cart = posed(box(0, 10, -10, -8, -1, 20, 16, 2), (0, 4, 0), (math.pi / 2, 0, 0))
for pivot, yaw in (((-9, 4, 0), 3 * math.pi / 2), ((9, 4, 0), math.pi / 2), ((0, 4, -7), math.pi), ((0, 4, 7), 0)):
    cart += posed(box(0, 0, -8, -9, -1, 16, 8, 2), pivot, (0, yaw, 0))
# Minecraft draws it upside down (x and y flipped), 6 pixels over the rail; carts' entity stands at the rail node's
# middle and runs along z at yaw 0, so the long side goes to z
cart = [([(z, 6 - y, x) for x, y, z in c], uv) for c, uv in cart]
write("goodluck_models_minecart.obj", cart, (64, 32), scale=10 / 16, centre=(0, 0, 0), lift=-5)
print("meshes in", os.path.relpath(OUT, ROOT))
