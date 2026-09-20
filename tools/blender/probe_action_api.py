# Probe how Blender 5.1 exposes action f-curves (the classic act.fcurves is gone).
import bpy

for block in (bpy.data.objects, bpy.data.actions, bpy.data.armatures, bpy.data.meshes):
    for it in list(block):
        try:
            block.remove(it)
        except Exception:
            pass

bpy.ops.import_scene.gltf(filepath=r"\\wsl.localhost\Ubuntu\home\martin_fabian\godot-arpg\models\hero.glb")
act = [a for a in bpy.data.actions if a.name == "Rig|Sword_Idle"][0]
print("ACTION", act.name)
print("attrs:", [a for a in dir(act) if not a.startswith("_")][:60])
print("has layers:", hasattr(act, "layers"), getattr(act, "layers", None) and len(act.layers))
for i, lay in enumerate(getattr(act, "layers", [])):
    print("  layer", i, lay.name, "strips:", len(lay.strips))
    for s in lay.strips:
        print("    strip", s.type, "channelbags:", len(getattr(s, "channelbags", [])))
        for cb in getattr(s, "channelbags", []):
            print("      channelbag slot", getattr(cb, "slot_handle", "?"), "fcurves:", len(cb.fcurves))
            for fc in list(cb.fcurves)[:5]:
                print("        ", fc.data_path, "[", fc.array_index, "]")
print("slots:", [(s.handle, s.name_display) for s in getattr(act, "slots", [])])
