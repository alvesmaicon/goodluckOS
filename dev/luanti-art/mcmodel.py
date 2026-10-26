# Minecraft's model geometry for models.py and animals.py: its boxes (a texture offset and a size each, unwrapped the
# way its models are: top and bottom over the four sides) and its block models' elements, in its pixels
import math


def box(u, v, x, y, z, w, h, d, grow=0, mirror=False):
    # a box in pixels from (x, y, z), and its six faces: corners and texture pixels, each face's corners in the
    # order its texture's top right, top left, bottom left, bottom right go, seen from outside; grow inflates the box
    # and not its texture, as Minecraft's deformation does, and mirror swaps its sides as Minecraft's does
    x, y, z = x - grow, y - grow, z - grow
    x1, y1, z1 = x + w + 2 * grow, y + h + 2 * grow, z + d + 2 * grow
    if mirror:
        x, x1 = x1, x
    c = [(x, y, z), (x1, y, z), (x1, y1, z), (x, y1, z), (x, y, z1), (x1, y, z1), (x1, y1, z1), (x, y1, z1)]
    f4, f5, f6, f7, f8, f9 = u, u + d, u + d + w, u + d + w + w, u + d + w + d, u + d + w + d + w
    f10, f11, f12 = v, v + d, v + d + h
    return [
        ([c[5], c[4], c[0], c[1]], (f5, f10, f6, f11)),  # bottom (-y)
        ([c[2], c[3], c[7], c[6]], (f6, f11, f7, f10)),  # top (+y)
        ([c[0], c[4], c[7], c[3]], (f4, f11, f5, f12)),  # -x
        ([c[1], c[0], c[3], c[2]], (f5, f11, f6, f12)),  # -z
        ([c[5], c[1], c[2], c[6]], (f6, f11, f8, f12)),  # +x
        ([c[4], c[5], c[6], c[7]], (f8, f11, f9, f12)),  # +z
    ]


def posed(faces, pivot=(0, 0, 0), rot=(0, 0, 0)):
    # a part's boxes moved to its pivot and turned about it (Minecraft turns x first, then y, then z)
    rx, ry, rz = rot

    def turn(p):
        x, y, z = p
        y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
        x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
        x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
        return (x + pivot[0], y + pivot[1], z + pivot[2])
    return [([turn(p) for p in corners], uv) for corners, uv in faces]


def element(frm, to, faces):
    # a block model element: from and to in pixels, each face's uv (x1, y1, x2, y2) on the texture
    (x, y, z), (x1, y1, z1) = frm, to
    c = {"down": [(x1, y, z1), (x, y, z1), (x, y, z), (x1, y, z)], "up": [(x1, y1, z), (x, y1, z), (x, y1, z1),
         (x1, y1, z1)], "north": [(x, y1, z), (x1, y1, z), (x1, y, z), (x, y, z)], "south": [(x1, y1, z1),
         (x, y1, z1), (x, y, z1), (x1, y, z1)], "west": [(x, y1, z1), (x, y1, z), (x, y, z), (x, y, z1)],
         "east": [(x1, y1, z), (x1, y1, z1), (x1, y, z1), (x1, y, z)]}
    return [(c[name], uv) for name, uv in faces.items()]
