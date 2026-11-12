"""The owl in 3D: turns the source GLBs into the rigged models the clients load.

The sources (`aaru_owl_mascot.glb`, `aaru_owl_on_books.glb`) are flat lists of named parts:
Z-up, no normals, no joints, no eyelids. This script, standard library only:

  1. turns the model Y-up, facing +Z, standing on the origin, one unit tall;
  2. groups the parts under joints (Body, Head, EyeL/R, PupilL/R, LidL/R, EarL/R, WingL/R,
     Tail, Feet, Books), each part's points relative to its joint;
  3. halves the densest hidden spheres, merges parts that share a material inside a joint;
  4. adds smooth normals with a crease angle;
  5. adds an eyelid over each eye (closed by scaling, see `owl-rig.json`);
  6. makes the ceramic glossier and the amber and cyan lights brighter, and paints the parts the
     source left white or silver in the poster's colours (`PAINT`): the eyes' amber ring, the
     wings graded from pale to slate with ember edges, ice-blue neck and ear feathers;
  7. writes `owl.glb`, `owl-on-books.glb` (web), `Owl.usdz`, `OwlOnBooks.usdz` (Apple) and
     `owl-rig.json` (joint names, rest transforms, the poster pose).

    python3 owl_3d.py --owl aaru_owl_mascot.glb --books aaru_owl_on_books.glb --out out/owl-3d

The USDZ step needs `usdcat` and `usdzip` (in /usr/bin on macOS); without them the .usda is kept.
"""

import argparse
import json
import math
import shutil
import struct
import subprocess
from collections import defaultdict
from pathlib import Path

CREASE = math.cos(math.radians(45))
BOOK_PREFIXES = ("BOOKS /", "ANIME /", "TV SHOWS /", "MOVIES /")
# Dense spheres kept whole because their outline shows at any size.
KEEP_DENSE = ("Head / main pearl ceramic",)
HEAD_SCALE = 1.08  # the poster's owl has a slightly larger head
LID_REST = 0.001  # eyelid scale on Y and Z when open; 1 is shut

# Looks, by source material name: (roughness, metallic, clearcoat, emissive colour, strength).
LOOKS = {
    "porcelain": (0.20, 0.0, 1.0, None, 0),
    "snow": (0.18, 0.0, 1.0, None, 0),
    "ceramic": (0.24, 0.0, 0.8, None, 0),
    "eyeglass": (0.04, 0.0, 1.0, None, 0),
    "pupil": (0.05, 0.0, 1.0, None, 0),
    # A strong glow clips to pale yellow in both renderers: the hue carries the ember, not the strength.
    "amber": (0.22, 0.3, 0.0, (1.0, 0.33, 0.02), 1.0),
    "amber_light": (0.23, 0.1, 0.0, (1.0, 0.42, 0.06), 1.1),
    "cyan": (0.24, 0.1, 0.0, (0.28, 0.72, 1.0), 2.0),
    "highlight": (0.2, 0.0, 0.0, (1.0, 1.0, 1.0), 1.0),
    "bezel": (0.30, 0.6, 0.0, None, 0),
    "plume_1": (0.30, 0.15, 0.6, None, 0),
    "plume_2": (0.32, 0.2, 0.5, None, 0),
    "plume_3": (0.34, 0.25, 0.4, None, 0),
    "plume_4": (0.36, 0.3, 0.3, None, 0),
    "plume_5": (0.38, 0.35, 0.3, None, 0),
    "covert_1": (0.22, 0.0, 0.9, None, 0),
    "covert_2": (0.24, 0.05, 0.8, None, 0),
    "ice_1": (0.24, 0.1, 0.6, (0.30, 0.62, 1.0), 0.35),
    "ice_2": (0.26, 0.15, 0.5, (0.22, 0.50, 1.0), 0.5),
}

# The poster's colours: base colour by name, for materials the source does not have and for
# the two ambers, which the source makes too pale to read as ember. Gloss and glow are in LOOKS.
COLOURS = {
    "amber": (0.60, 0.22, 0.03),
    "amber_light": (0.80, 0.40, 0.10),
    "bezel": (0.10, 0.09, 0.10),
    "plume_1": (0.62, 0.72, 0.88),
    "plume_2": (0.42, 0.53, 0.74),
    "plume_3": (0.28, 0.37, 0.58),
    "plume_4": (0.18, 0.24, 0.42),
    "plume_5": (0.10, 0.14, 0.26),
    "covert_1": (0.80, 0.87, 0.97),
    "covert_2": (0.62, 0.74, 0.93),
    "ice_1": (0.66, 0.82, 0.98),
    "ice_2": (0.42, 0.66, 0.94),
}

# Which parts take which colour: the part's name without its side letter, then the material.
# The source builds the wings from white, silver and ceramic; the poster grades them from pale
# at the shoulder to slate at the tips, with ember along the edges, and rings the eyes in amber.
PAINT = {
    "eye outer copper bezel": "bezel",
    "primary flight feather 1": "plume_1",
    "primary flight feather 2": "plume_1",
    "primary flight feather 3": "plume_2",
    "primary flight feather 4": "plume_2",
    "primary flight feather 5": "plume_3",
    "primary flight feather 6": "plume_3",
    "primary flight feather 7": "plume_4",
    "primary flight feather 8": "plume_4",
    "long flight tip 0": "plume_4",
    "long flight tip 1": "amber",
    "long flight tip 2": "plume_5",
    "long flight tip 3": "amber",
    "porcelain upper overlay 1": "covert_1",
    "porcelain upper overlay 2": "covert_2",
    "neck secondary cyan feather 0": "ice_1",
    "neck secondary cyan feather 2": "ice_2",
    "ear lower silver": "ice_1",
    "lower haunch": "plume_3",
    "fine chest silver seam": "amber",
    "Tail underside feather 0": "plume_2",
    "Tail underside feather 1": "plume_4",
    "Tail underside feather 2": "plume_2",
    "Tail underside feather 3": "plume_4",
    "Tail underside feather 4": "plume_2",
}


# ---------------------------------------------------------------- reading


def read_glb(path):
    """Returns (parts, materials): parts are {name, material, points, faces} in source space."""
    data = Path(path).read_bytes()
    json_len = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20 : 20 + json_len])
    blob = data[28 + json_len :]
    accessors, views = doc["accessors"], doc["bufferViews"]

    def read(index):
        acc = accessors[index]
        view = views[acc["bufferView"]]
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        width = {"SCALAR": 1, "VEC3": 3}[acc["type"]]
        code = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[acc["componentType"]]
        flat = struct.unpack_from(f"<{acc['count'] * width}{code}", blob, offset)
        return [flat[i : i + width] for i in range(0, len(flat), width)] if width > 1 else flat

    parts = []
    for node in doc["nodes"]:
        if "mesh" not in node:
            continue
        if any(key in node for key in ("matrix", "translation", "rotation", "scale")):
            raise SystemExit(f"{node['name']}: the source is expected to have no transforms")
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            flat = read(prim["indices"])
            parts.append(
                {
                    "name": node["name"],
                    "material": doc["materials"][prim["material"]]["name"],
                    "points": [tuple(p) for p in read(prim["attributes"]["POSITION"])],
                    "faces": [tuple(flat[i : i + 3]) for i in range(0, len(flat), 3)],
                }
            )
    materials = {}
    for mat in doc["materials"]:
        pbr = mat["pbrMetallicRoughness"]
        materials[mat["name"]] = {
            "color": tuple(pbr.get("baseColorFactor", (1, 1, 1, 1))[:3]),
            "roughness": pbr.get("roughnessFactor", 1.0),
            "metallic": pbr.get("metallicFactor", 0.0),
            "emissive": tuple(mat.get("emissiveFactor", (0, 0, 0))),
        }
    return parts, materials


# ---------------------------------------------------------------- geometry


def bounds(points):
    return [min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]


def centre(points):
    low, high = bounds(points)
    return tuple((low[i] + high[i]) / 2 for i in range(3))


def unsubdivide(part):
    """Undoes one trimesh subdivision (each face became 4, new points appended). True if done."""
    faces, count = part["faces"], len(part["points"])
    if len(faces) % 4:
        return False
    coarse, top = [], 0
    for i in range(0, len(faces), 4):
        (a, m0, m2), (m0b, b, m1), (m2b, m1b, c), inner = faces[i : i + 4]
        if (m0b, m2b, m1b) != (m0, m2, m1) or inner != (m0, m1, m2):
            return False
        coarse.append((a, b, c))
        top = max(top, a, b, c)
    kept = top + 1
    if kept >= count or any(min(face) < kept for face in faces[3::4]):
        return False
    part["points"], part["faces"] = part["points"][:kept], coarse
    return True


def with_normals(points, faces):
    """Splits points along creases. Returns (points, normals, faces)."""
    area_n, unit_n, around = [], [], defaultdict(list)
    for index, (a, b, c) in enumerate(faces):
        pa, pb, pc = points[a], points[b], points[c]
        u = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
        v = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
        area_n.append(n)
        unit_n.append((n[0] / length, n[1] / length, n[2] / length) if length > 1e-12 else None)
        for corner in (a, b, c):
            around[corner].append(index)
    out_points, out_normals, out_faces, seen = [], [], [], {}
    for index, face in enumerate(faces):
        mine = unit_n[index]
        if mine is None:
            continue
        corners = []
        for corner in face:
            total = [0.0, 0.0, 0.0]
            for other in around[corner]:
                theirs = unit_n[other]
                if theirs and mine[0] * theirs[0] + mine[1] * theirs[1] + mine[2] * theirs[2] >= CREASE:
                    for axis in range(3):
                        total[axis] += area_n[other][axis]
            length = math.sqrt(sum(x * x for x in total)) or 1.0
            normal = tuple(round(x / length, 3) for x in total)
            key = (corner, normal)
            if key not in seen:
                seen[key] = len(out_points)
                out_points.append(points[corner])
                out_normals.append(normal)
            corners.append(seen[key])
        out_faces.append(tuple(corners))
    return out_points, out_normals, out_faces


def eyelid(radius_x, radius_up, radius_front, rows=10, columns=16):
    """The front half of an ellipsoid hanging from its top point, in output space (Y up, +Z front)."""
    points, faces = [], []
    for row in range(rows + 1):
        theta = math.pi * row / rows
        for column in range(columns + 1):
            phi = -math.pi / 2 + math.pi * column / columns
            points.append(
                (
                    radius_x * math.sin(theta) * math.sin(phi),
                    radius_up * (math.cos(theta) - 1),
                    radius_front * math.sin(theta) * math.cos(phi),
                )
            )
    for row in range(rows):
        for column in range(columns):
            a = row * (columns + 1) + column
            b, c, d = a + 1, a + columns + 1, a + columns + 2
            faces += [(a, c, b), (b, c, d)]
    return points, faces


# ---------------------------------------------------------------- the rig


def joint_of(name, where):
    """The joint a source part belongs to. `where` is the part's centre, in source space."""
    if name.startswith(BOOK_PREFIXES):
        return "Books"
    side = name[0] if name[:2] in ("L ", "R ") else ""
    rest = name[2:] if side else name
    if side:
        if rest.startswith("ear"):
            return "Ear" + side
        if rest.startswith(("eye black pupil", "iris", "eye catchlight")):
            return "Pupil" + side
        if rest.startswith("eye "):
            return "Eye" + side
        if rest.startswith(("brow", "lower eye cheek")):
            return "Head"
        if rest.startswith("neck secondary"):
            return "Head" if where[2] > 2.0 else "Body"
        if rest.startswith(
            ("folded wing", "upper shoulder", "primary flight", "long flight tip", "wing integrated", "shoulder", "porcelain upper overlay")
        ):
            return "Wing" + side
        if rest.startswith(("chest", "fine chest", "collar", "lower haunch")):
            return "Body"
        if rest.startswith(("leg", "foot", "toe", "curved claw")):
            return "Feet"
    else:
        if rest.startswith(("Head /", "Cranial", "Central crest", "Beak", "Forehead")):
            return "Head"
        if rest.startswith(("Torso", "Lower feathered", "Chest", "Neck")):
            return "Body"
        if rest.startswith("Tail"):
            return "Tail"
    raise SystemExit(f"No joint for part '{name}'")


PARENTS = {
    "Owl": "Root", "Books": "Root", "Feet": "Owl", "Body": "Owl", "Tail": "Body", "WingL": "Body",
    "WingR": "Body", "Head": "Body", "EarL": "Head", "EarR": "Head", "EyeL": "Head", "EyeR": "Head",
    "PupilL": "EyeL", "PupilR": "EyeR", "LidL": "EyeL", "LidR": "EyeR",
}  # fmt: skip
ORDER = ["Root", "Books", "Owl", "Feet", "Body", "Tail", "WingL", "WingR", "Head", "EarL", "EarR",
         "EyeL", "PupilL", "LidL", "EyeR", "PupilR", "LidR"]  # fmt: skip


def build(owl_parts, book_parts, lift):
    """Returns (joints, meshes): joints {name: {pivot, scale}} and meshes {joint: {material: (points, normals, faces)}},
    all in output space. `lift` moves the owl (source units) onto the books."""
    named = {part["name"]: part for part in owl_parts}

    def box(name):
        return bounds(named[name]["points"])

    low_all, high_all = bounds([p for part in owl_parts for p in part["points"]])
    ground = low_all[2]
    size = 1.0 / (high_all[2] - ground)

    def out(point):  # source (x, y, z), Z up, facing -Y  ->  (x, z, -y), Y up, facing +Z
        return (point[0] * size, (point[2] - ground) * size, -point[1] * size)

    pivots = {"Root": (0, 0, ground), "Owl": (0, 0, ground), "Feet": (0, 0, ground), "Books": (0, 0, ground)}
    torso_low, torso_high = box("Torso / graphite chassis")
    pivots["Body"] = (0, (torso_low[1] + torso_high[1]) / 2, torso_low[2] + 0.25)
    pivots["Head"] = centre(named["Neck swivel / polished titanium"]["points"])
    tail_low, tail_high = bounds([p for part in owl_parts if part["name"].startswith("Tail") for p in part["points"]])
    pivots["Tail"] = (0, tail_low[1], tail_high[2])
    lids = {}
    for side in "LR":
        dome_low, dome_high = box(f"{side} eye glass dome")
        eye = tuple((dome_low[i] + dome_high[i]) / 2 for i in range(3))
        pivots["Eye" + side] = eye
        pivots["Pupil" + side] = centre(named[f"{side} eye black pupil"]["points"])
        front = min(p[1] for part in owl_parts if joint_of(part["name"], centre(part["points"])) == "Pupil" + side for p in part["points"])
        radii = ((dome_high[0] - dome_low[0]) / 2 * 1.07, (dome_high[2] - dome_low[2]) / 2 * 1.07, eye[1] - front + 0.03)
        pivots["Lid" + side] = (eye[0], eye[1], eye[2] + radii[1])
        lids[side] = radii
        ear_low, ear_high = box(f"{side} ear upper porcelain")
        inner = ear_high[0] if side == "L" else ear_low[0]
        pivots["Ear" + side] = (inner, (ear_low[1] + ear_high[1]) / 2, (ear_low[2] + ear_high[2]) / 2)
        sh_low, sh_high = box(f"{side} upper shoulder porcelain")
        pivots["Wing" + side] = ((sh_low[0] + sh_high[0]) / 2, (sh_low[1] + sh_high[1]) / 2, sh_high[2] - 0.15)

    # Source-space offset of each joint: the owl's joints move up with it when it stands on books.
    def source_pivot(joint):
        x, y, z = pivots[joint]
        in_owl = joint not in ("Root", "Books")
        return (x, y, z + (lift if in_owl else 0))

    base = ground  # the scene's ground: the books' floor, or the owl's feet
    meshes = defaultdict(lambda: defaultdict(lambda: ([], [], [])))
    halved = 0

    def add(joint, material, points, faces):
        points, normals, faces = with_normals(points, faces)
        target = meshes[joint][material]
        shift = len(target[0])
        target[0].extend(points)
        target[1].extend(normals)
        target[2].extend((a + shift, b + shift, c + shift) for a, b, c in faces)

    for part in owl_parts:
        if len(part["points"]) == 2562 and part["name"] not in KEEP_DENSE and unsubdivide(part):
            halved += 1
        joint = joint_of(part["name"], centre(part["points"]))
        px, py, pz = pivots[joint]
        local = [((p[0] - px) * size, (p[2] - pz) * size, -(p[1] - py) * size) for p in part["points"]]
        add(joint, part["material"], local, part["faces"])
    for part in book_parts:
        local = [(p[0] * size, (p[2] - base) * size, -p[1] * size) for p in part["points"]]
        add("Books", part["material"], local, part["faces"])
    for side in "LR":
        rx, rup, rfront = (r * size for r in lids[side])
        points, faces = eyelid(rx, rup, rfront)
        add("Lid" + side, "snow", points, faces)

    joints = {}
    for joint in ORDER:
        if joint == "Books" and not book_parts:
            continue
        parent = PARENTS.get(joint)
        here = source_pivot(joint)
        there = source_pivot(parent) if parent else (0, 0, base)
        delta = (here[0] - there[0], here[1] - there[1], here[2] - there[2])
        scale = (1, 1, 1)
        if joint == "Head":
            scale = (HEAD_SCALE,) * 3
        if joint.startswith("Lid"):
            scale = (1, LID_REST, LID_REST)
        joints[joint] = {
            "parent": parent,
            "translation": tuple(round(v, 5) for v in (delta[0] * size, delta[2] * size, -delta[1] * size)),
            "scale": scale,
        }
    return joints, meshes, halved


def paint(parts):
    """The owl's parts with the poster's colours: a part named in PAINT takes that material."""
    unused = set(PAINT)
    painted = []
    for part in parts:
        name = part["name"]
        plain = name[2:] if name[:2] in ("L ", "R ") else name
        unused.discard(plain)
        painted.append({**part, "material": PAINT.get(plain, part["material"])})
    if unused:
        raise SystemExit(f"PAINT names parts the source does not have: {sorted(unused)}")
    return painted


def looks(materials):
    blank = {"roughness": 0.3, "metallic": 0.0, "emissive": (0.0, 0.0, 0.0)}
    materials = {**materials, **{name: {**blank, "color": colour} for name, colour in COLOURS.items()}}
    result = {}
    for name, mat in materials.items():
        rough, metal, coat, glow, strength = LOOKS.get(name, (mat["roughness"], mat["metallic"], 0.0, None, 0))
        result[name] = {
            "color": mat["color"],
            "roughness": rough,
            "metallic": metal,
            "clearcoat": coat,
            "emissive": glow or mat["emissive"],
            "strength": strength or 1.0,
        }
    return result


# ---------------------------------------------------------------- writing glTF


def write_glb(path, joints, meshes, materials):
    blob, views, accessors, gl_meshes, nodes = bytearray(), [], [], [], []
    names = sorted({m for joint in meshes.values() for m in joint})
    index_of = {name: i for i, name in enumerate(names)}

    def view(payload, target, stride=None):
        while len(blob) % 4:
            blob.append(0)
        entry = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(payload), "target": target}
        if stride:
            entry["byteStride"] = stride
        blob.extend(payload)
        views.append(entry)
        return len(views) - 1

    def clamp(value, top):
        return max(-top, min(top, round(value * top)))

    for joint in joints:
        node = {"name": joint}
        if any(joints[joint]["translation"]):
            node["translation"] = list(joints[joint]["translation"])
        if joints[joint]["scale"] != (1, 1, 1):
            node["scale"] = list(joints[joint]["scale"])
        if joint in meshes:
            prims = []
            for material in sorted(meshes[joint]):
                points, normals, faces = meshes[joint][material]
                if max(abs(v) for p in points for v in p) > 1:
                    raise SystemExit(f"{joint}: a point lies outside the quantised range")
                pos = b"".join(struct.pack("<3hxx", *(clamp(v, 32767) for v in p)) for p in points)
                nor = b"".join(struct.pack("<3bx", *(clamp(v, 127) for v in n)) for n in normals)
                wide = len(points) > 65535
                idx = struct.pack(f"<{len(faces) * 3}{'I' if wide else 'H'}", *(i for f in faces for i in f))
                low, high = bounds(points)
                accessors.append({"bufferView": view(pos, 34962, 8), "componentType": 5122, "normalized": True, "count": len(points),
                                  "type": "VEC3", "min": [clamp(v, 32767) / 32767 for v in low], "max": [clamp(v, 32767) / 32767 for v in high]})  # fmt: skip
                accessors.append({"bufferView": view(nor, 34962, 4), "componentType": 5120, "normalized": True, "count": len(points), "type": "VEC3"})  # fmt: skip
                accessors.append({"bufferView": view(idx, 34963), "componentType": 5125 if wide else 5123, "count": len(faces) * 3, "type": "SCALAR"})  # fmt: skip
                top = len(accessors)
                prims.append({"attributes": {"POSITION": top - 3, "NORMAL": top - 2}, "indices": top - 1, "material": index_of[material]})
            gl_meshes.append({"name": joint, "primitives": prims})
            node["mesh"] = len(gl_meshes) - 1
        nodes.append(node)
    order = list(joints)
    for joint, info in joints.items():
        if info["parent"]:
            nodes[order.index(info["parent"])].setdefault("children", []).append(order.index(joint))

    gl_materials = []
    for name in names:
        look = materials[name]
        entry = {
            "name": name,
            "pbrMetallicRoughness": {"baseColorFactor": [*look["color"], 1.0], "roughnessFactor": look["roughness"], "metallicFactor": look["metallic"]},
            "doubleSided": True,
        }
        extensions = {}
        if any(look["emissive"]):
            entry["emissiveFactor"] = list(look["emissive"])
            if look["strength"] != 1.0:
                extensions["KHR_materials_emissive_strength"] = {"emissiveStrength": look["strength"]}
        if look["clearcoat"]:
            extensions["KHR_materials_clearcoat"] = {"clearcoatFactor": look["clearcoat"], "clearcoatRoughnessFactor": 0.08}
        if extensions:
            entry["extensions"] = extensions
        gl_materials.append(entry)

    doc = {
        "asset": {"version": "2.0", "generator": "aaru docs/brand/owl_3d.py"},
        "extensionsUsed": ["KHR_mesh_quantization", "KHR_materials_clearcoat", "KHR_materials_emissive_strength"],
        "extensionsRequired": ["KHR_mesh_quantization"],
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "materials": gl_materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob)}],
    }
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    blob.extend(b"\0" * (-len(blob) % 4))
    total = 12 + 8 + len(text) + 8 + len(blob)
    Path(path).write_bytes(struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(blob), b"BIN\0") + blob)
    return len(gl_meshes), sum(len(m["primitives"]) for m in gl_meshes), total


# ---------------------------------------------------------------- writing USD


def write_usd(path, joints, meshes, materials, scene):
    def tuples(values, digits):
        return ", ".join("(" + ", ".join(f"{v:.{digits}g}" for v in t) + ")" for t in values)

    lines = ['#usda 1.0', '(', f'    defaultPrim = "{scene}"', '    metersPerUnit = 1', '    upAxis = "Y"', ')', '',
             f'def Xform "{scene}" (', '    kind = "component"', ')', '{', '    def Scope "Materials"', '    {']  # fmt: skip
    for name in sorted({m for joint in meshes.values() for m in joint}):
        look = materials[name]
        glow = tuple(c * look["strength"] for c in look["emissive"])
        root = f"/{scene}/Materials/{name}"
        lines += [
            f'        def Material "{name}"', '        {',
            f'            token outputs:surface.connect = <{root}/Surface.outputs:surface>',
            '            def Shader "Surface"', '            {',
            '                uniform token info:id = "UsdPreviewSurface"',
            f'                color3f inputs:diffuseColor = {tuples([look["color"]], 5)}',
            f'                float inputs:roughness = {look["roughness"]}',
            f'                float inputs:metallic = {look["metallic"]}',
            f'                float inputs:clearcoat = {look["clearcoat"]}',
            '                float inputs:clearcoatRoughness = 0.08',
            f'                color3f inputs:emissiveColor = {tuples([glow], 5)}',
            '                token outputs:surface', '            }', '        }',
        ]  # fmt: skip
    lines.append("    }")
    children = defaultdict(list)
    for joint, info in joints.items():
        children[info["parent"]].append(joint)

    def emit(joint, depth):
        pad = "    " * depth
        info = joints[joint]
        lines.append(f'{pad}def Xform "{joint}"')
        lines.append(pad + "{")
        lines.append(f"{pad}    double3 xformOp:translate = {tuples([info['translation']], 8)}")
        lines.append(f"{pad}    float3 xformOp:scale = {tuples([info['scale']], 6)}")
        lines.append(f'{pad}    uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scale"]')
        for material in sorted(meshes.get(joint, {})):
            points, normals, faces = meshes[joint][material]
            lines.extend([
                f'{pad}    def Mesh "{joint}_{material}" (', f'{pad}        prepend apiSchemas = ["MaterialBindingAPI"]', f'{pad}    )',
                pad + "    {",
                f"{pad}        uniform bool doubleSided = 1",
                f"{pad}        int[] faceVertexCounts = [{', '.join('3' for _ in faces)}]",
                f"{pad}        int[] faceVertexIndices = [{', '.join(str(i) for f in faces for i in f)}]",
                f"{pad}        point3f[] points = [{tuples(points, 6)}]",
                f'{pad}        normal3f[] normals = [{tuples(normals, 3)}] (', f'{pad}            interpolation = "vertex"', f'{pad}        )',
                f'{pad}        uniform token subdivisionScheme = "none"',
                f"{pad}        rel material:binding = </{scene}/Materials/{material}>",
                pad + "    }",
            ])  # fmt: skip
        for child in children[joint]:
            emit(child, depth + 1)
        lines.append(pad + "}")

    emit("Root", 1)
    lines.append("}")
    usda = Path(path).with_suffix(".usda")
    usda.write_text("\n".join(lines) + "\n")
    if not (shutil.which("usdcat") and shutil.which("usdzip")):
        return usda
    usdc = usda.with_suffix(".usdc")
    subprocess.run(["usdcat", str(usda), "-o", str(usdc)], check=True)
    Path(path).unlink(missing_ok=True)
    subprocess.run(["usdzip", str(Path(path).resolve()), usdc.name], check=True, cwd=usdc.parent)
    usda.unlink()
    usdc.unlink()
    return Path(path)


# ---------------------------------------------------------------- main


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--owl", required=True, help="aaru_owl_mascot.glb")
    parser.add_argument("--books", help="aaru_owl_on_books.glb")
    parser.add_argument("--out", default="out/owl-3d")
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    owl, materials = read_glb(args.owl)
    owl = paint(owl)
    variants = [("owl.glb", "Owl.usdz", "Owl", [], 0.0, materials)]
    if args.books:
        scene, scene_materials = read_glb(args.books)
        books = [part for part in scene if part["name"].startswith(BOOK_PREFIXES)]
        perched = next(part for part in scene if part["name"] == "Torso / graphite chassis")
        alone = next(part for part in owl if part["name"] == "Torso / graphite chassis")
        lift = bounds(perched["points"])[0][2] - bounds(alone["points"])[0][2]
        floor = min(p[2] for part in books for p in part["points"])
        ground = min(p[2] for part in owl for p in part["points"])
        # Books are measured from the owl's ground, so drop them by the gap and lift the owl.
        books = [{**part, "points": [(x, y, z - floor + ground) for x, y, z in part["points"]]} for part in books]
        variants.append(("owl-on-books.glb", "OwlOnBooks.usdz", "OwlOnBooks", books, lift - floor, {**scene_materials, **materials}))

    rig = {}
    for glb_name, usd_name, scene_name, books, lift, mats in variants:
        fresh = [{**part, "points": list(part["points"]), "faces": list(part["faces"])} for part in owl]
        joints, meshes, halved = build(fresh, books, lift)
        styled = looks(mats)
        mesh_count, draws, size = write_glb(out / glb_name, joints, meshes, styled)
        usd = write_usd(out / usd_name, joints, meshes, styled, scene_name)
        points = sum(len(m[0]) for joint in meshes.values() for m in joint.values())
        faces = sum(len(m[2]) for joint in meshes.values() for m in joint.values())
        print(f"{glb_name}: {size / 1024:.0f} KB, {len(joints)} joints, {mesh_count} meshes, {draws} draw calls, "
              f"{points} points, {faces} triangles, {halved} dense spheres halved")  # fmt: skip
        print(f"{usd.name}: {usd.stat().st_size / 1024:.0f} KB")
        rig[scene_name] = {name: {"parent": info["parent"], "translation": info["translation"], "scale": info["scale"]} for name, info in joints.items()}

    (out / "owl-rig.json").write_text(
        json.dumps(
            {
                "space": "Y up, the owl faces +Z, one unit tall, standing on the origin. L is the viewer's left (-X).",
                "eyelids": f"LidL and LidR close by scaling Y and Z from {LID_REST} (open, the rest state) to 1 (shut).",
                "look": "Move PupilL and PupilR a few hundredths on X and Y to look around; turn Head for more.",
                "posterPose": {"Owl": {"rotateYDegrees": -32}, "Head": {"rotateYDegrees": 24, "rotateZDegrees": -6}},
                "scenes": rig,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"Wrote {out}/owl-rig.json")


if __name__ == "__main__":
    main()
