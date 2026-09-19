# Probe the source base-character GLB: objects, materials, actions, sword cluster.
# Run: "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe" -b --factory-startup -P probe_enemy_src.py
import bpy
from mathutils import Vector

SRC = r"\\wsl.localhost\Ubuntu\home\martin_fabian\tools\kaykit\candidates\quat_base_character.glb"

for block in (bpy.data.objects, bpy.data.meshes, bpy.data.materials,
              bpy.data.armatures, bpy.data.actions, bpy.data.images):
    for item in list(block):
        try:
            block.remove(item)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=SRC)

print("=== OBJECTS")
for o in bpy.context.scene.objects:
    line = "%-28s type=%-9s parent=%s" % (o.name, o.type, o.parent.name if o.parent else "-")
    if o.type == 'MESH':
        line += " verts=%d mats=%s" % (len(o.data.vertices),
                                       [m.name if m else None for m in o.data.materials])
        line += " mods=%s" % [m.type for m in o.modifiers]
        line += " vgroups=%d" % len(o.vertex_groups)
    if o.type == 'ARMATURE':
        line += " bones=%d" % len(o.data.bones)
    print(line)

print("=== MATERIALS")
for m in bpy.data.materials:
    print("  %-24s nodes=%s" % (m.name, [n.type for n in m.node_tree.nodes] if m.use_nodes else "-"))

print("=== ACTIONS (%d)" % len(bpy.data.actions))
for a in sorted(bpy.data.actions, key=lambda x: x.name):
    print("  %-34s frames %.0f..%.0f  (%.2fs @24)" % (a.name, a.frame_range[0], a.frame_range[1],
                                                      (a.frame_range[1] - a.frame_range[0]) / 24.0))

print("=== WORLD BOUNDS per mesh object (evaluated)")
deps = bpy.context.evaluated_depsgraph_get()
for o in bpy.context.scene.objects:
    if o.type != 'MESH':
        continue
    ev = o.evaluated_get(deps)
    me = ev.to_mesh()
    if len(me.vertices) == 0:
        print("  %s EMPTY" % o.name)
        ev.to_mesh_clear()
        continue
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for v in me.vertices:
        w = ev.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i])
            mx[i] = max(mx[i], w[i])
    print("  %-24s min=(%.3f %.3f %.3f) max=(%.3f %.3f %.3f) size=(%.3f %.3f %.3f)"
          % (o.name, mn.x, mn.y, mn.z, mx.x, mx.y, mx.z,
             mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
    ev.to_mesh_clear()

print("=== ARMature bones (first 60)")
arm = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
if arm:
    for b in list(arm[0].data.bones)[:60]:
        print("   ", b.name)
print("DONE")
