"""Run through Blender MCP. Creates only its own scene; restores the open scene.

Meters, Blender Z up. Exports modular meshes for the live Godot arm rig.
No downloaded assets, textures, or third-party content.
"""
import bpy
import math
import os
import json
from mathutils import Vector

OUTPUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def generate():
    previous_scene = bpy.context.window.scene
    previous_active = bpy.context.view_layer.objects.active
    previous_selected = list(bpy.context.selected_objects)
    previous_path = bpy.data.filepath
    scene = bpy.data.scenes.new("SEEDLAB | Button garden")
    scene.unit_settings.system = 'METRIC'
    roots = {}
    current = None

    def material(name, color, metallic=0.0, roughness=0.4, emission=0):
        mat = bpy.data.materials.new("Seed_" + name)
        mat.diffuse_color = (*color, 1)
        mat.use_nodes = True
        node = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if node is None:
            node = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
            out = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
            mat.node_tree.links.new(node.outputs['BSDF'], out.inputs['Surface'])
        node.inputs['Base Color'].default_value = (*color, 1)
        node.inputs['Metallic'].default_value = metallic
        node.inputs['Roughness'].default_value = roughness
        if emission:
            node.inputs['Emission Color'].default_value = (*color, 1)
            node.inputs['Emission Strength'].default_value = emission
        return mat

    cream = material('Ceramic', (0.72, .73, .65), .15)
    dark = material('Ink', (.025, .062, .076), .45)
    steel = material('Steel', (.16, .24, .26), .7)
    teal = material('Petrol', (.045, .31, .30), .35)
    yellow = material('Saffron', (.96, .43, .075), .25)
    mint = material('Signal', (.25, .94, .7), .2, emission=.5)
    rubber = material('Rubber', (.012, .019, .024), 0, .85)
    red = material('Coral', (.92, .16, .075), .2)

    def group(name):
        nonlocal current
        current = bpy.data.objects.new(name, None)
        scene.collection.objects.link(current)
        roots[name] = current
        return current

    def finish(obj, name, mat):
        obj.name = 'Seed_' + name
        obj.parent = current
        obj.data.materials.append(mat)
        return obj

    def box(name, loc, size, mat, bevel=.05):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
        obj = finish(bpy.context.object, name, mat)
        obj.scale = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel:
            mod = obj.modifiers.new('Machined edges', 'BEVEL')
            mod.width = bevel
            mod.segments = 3
            bpy.ops.object.modifier_apply(modifier=mod.name)
            mod = obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
            bpy.ops.object.modifier_apply(modifier=mod.name)
        return obj

    def cylinder(name, loc, radius, depth, mat, axis=None, vertices=32):
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
        obj = finish(bpy.context.object, name, mat)
        if axis:
            obj.rotation_euler = Vector((0, 0, 1)).rotation_difference(Vector(axis)).to_euler()
        mod = obj.modifiers.new('Edge', 'BEVEL')
        mod.width = min(.035, depth * .12)
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for p in obj.data.polygons:
            p.use_smooth = len(p.vertices) == 4
        return obj

    def sphere(name, loc, size, mat):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1, location=loc)
        obj = finish(bpy.context.object, name, mat)
        obj.scale = size
        for p in obj.data.polygons:
            p.use_smooth = True
        return obj

    def rod(name, a, b, radius, mat):
        a, b = Vector(a), Vector(b)
        return cylinder(name, (a + b) / 2, radius, (b - a).length, mat, b - a)

    try:
        bpy.context.window.scene = scene
        group('workbench')
        box('Lower chassis', (0, 0, .18), (9.8, 6.4, .52), dark, .24)
        box('Enamel shell', (0, 0, .50), (9.65, 6.22, .38), teal, .18)
        box('Working surface', (0, 0, .72), (9.48, 6.08, .13), cream, .12)
        for x in [-4.5, 4.5]:
            for y in [-2.78, 2.78]:
                cylinder('Recessed screw', (x, y, .80), .065, .025, steel)
                box('Screw slot', (x, y, .814), (.07, .018, .004), rubber, 0)
                box('Foot housing', (x, y, -.30), (.48, .48, .62), steel, .12)
                cylinder('Rubber foot', (x, y, -.64), .29, .16, rubber)
        for x in [-4.2, 4.2]:
            rod('Carry handle', (x, -2.5, .85), (x, -1.5, .85), .085, dark)
            rod('Handle leg', (x, -2.5, .72), (x, -2.5, .85), .08, dark)
            rod('Handle leg', (x, -1.5, .72), (x, -1.5, .85), .08, dark)
        for i in range(22):
            box('Front cooling rib', (-1.95 + i * .185, -3.14, .39), (.095, .04, .20), dark, .014)
        for i in range(5):
            box('Warning stripe', (3.15 + i * .18, -2.85, .798), (.08, .30, .006), yellow, .005)
        box('Rear bus', (0, 2.45, .83), (7.9, .36, .12), steel)
        for x in [-2.4, 2.4]:
            rod('Data cable', (x, 2.3, .82), (x, 1.65, .82), .045, yellow)
        for x in [-3.5, 3.5]:
            rod('Light support', (x, 2.3, .78), (x, 2.3, 2.9), .055, steel)
            rod('Task light', (x, 2.3, 2.9), (x, 1.7, 2.9), .11, cream)
            box('Light diffuser', (x, 1.8, 2.84), (.13, .35, .06), mint)
        # Small retro instrument makes the workbench feel like equipment.
        box('Instrument case', (0, 2.5, 1.17), (1.4, .58, .7), cream, .13)
        box('Instrument glass', (0, 2.188, 1.24), (1.1, .035, .32), dark, .05)
        for i in range(8):
            box('VU segment', (-.42 + i * .12, 2.162, 1.24), (.045, .022, .07 + (i % 3) * .04), mint, .01)
        cylinder('Instrument dial', (.48, 2.16, .99), .07, .05, yellow, (0, 1, 0))

        group('robot_base')
        cylinder('Base gasket', (0, 0, .05), .65, .1, rubber)
        cylinder('Turret', (0, 0, .19), .58, .28, dark)
        cylinder('Status ring', (0, 0, .35), .51, .06, mint)
        cylinder('Shoulder body', (0, 0, .54), .45, .32, yellow)
        box('Shoulder yoke', (0, 0, .82), (.55, .6, .49), yellow, .13)
        for y in [-.34, .34]:
            cylinder('Shoulder hub', (0, y, .86), .22, .12, steel, (0, 1, 0))
            cylinder('Hub cap', (0, y * 1.16, .86), .12, .035, cream, (0, 1, 0))
        for a in range(4):
            angle = a * math.tau / 4 + math.pi / 4
            cylinder('Base bolt', (.48 * math.cos(angle), .48 * math.sin(angle), .35), .05, .04, steel)

        group('arm_link')
        # Origin at lower joint, 2.4 meters between joint centres.
        box('Arm enamel', (0, 0, 1.2), (.36, .31, 2.13), yellow, .09)
        box('Arm inset', (0, -.163, 1.2), (.17, .025, 1.65), dark, .035)
        box('Arm indicator', (0, -.18, 1.7), (.06, .015, .35), mint, .01)
        for x in [-.17, .17]:
            rod('Hydraulic strut', (x, .07, .25), (x, .07, 2.15), .045, steel)
        for z in [0, 2.4]:
            cylinder('Joint', (0, 0, z), .23, .36, dark, (0, 1, 0))
            for y in [-.20, .20]:
                cylinder('Joint disc', (0, y, z), .17, .05, cream, (0, 1, 0))
                cylinder('Joint axle', (0, y * 1.18, z), .072, .04, steel, (0, 1, 0))

        group('gripper')
        cylinder('Wrist cuff', (0, 0, .07), .25, .14, dark)
        box('Tool housing', (0, 0, -.12), (.55, .40, .27), cream, .1)
        box('Camera black surround', (0, -.22, -.09), (.28, .07, .17), dark, .04)
        cylinder('Camera lens', (0, -.272, -.09), .063, .04, teal, (0, 1, 0))
        sphere('Camera glint', (-.019, -.298, -.07), (.02, .012, .02), mint)
        rod('Finger piston', (0, 0, -.21), (0, 0, -.49), .075, steel)
        cylinder('Soft fingertip', (0, 0, -.51), .13, .09, rubber)
        for x in [-.20, .20]:
            box('Side finger', (x, 0, -.30), (.07, .12, .30), yellow, .025)
        box('Wrist status', (0, .212, -.09), (.30, .02, .06), mint, .015)

        os.makedirs(OUTPUT, exist_ok=True)
        reports = []
        for name, root in roots.items():
            bpy.ops.object.select_all(action='DESELECT')
            root.select_set(True)
            children = list(root.children_recursive)
            for obj in children:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = root
            path = os.path.join(OUTPUT, name + '.glb')
            bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                use_active_scene=True, export_apply=True, export_yup=True,
                export_cameras=False, export_lights=False)
            reports.append({'name': name, 'meshes': len(children), 'bytes': os.path.getsize(path)})
        # A library write preserves the user's current filepath and excludes their scenes.
        blend_path = os.path.join(OUTPUT, 'source', 'seedlab-workshop.blend')
        bpy.data.libraries.write(blend_path, {scene}, fake_user=True, compress=True)
        with open(os.path.join(OUTPUT, 'source', 'asset-report.json'), 'w') as file:
            json.dump({'blender': bpy.app.version_string, 'assets': reports,
                'scene': scene.name, 'source': 'Original procedural models; no external assets'}, file, indent=2)
        print(json.dumps(reports))
    finally:
        bpy.context.window.scene = previous_scene
        bpy.ops.object.select_all(action='DESELECT')
        for obj in previous_selected:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = previous_active
        assert bpy.data.filepath == previous_path
        print('Restored open scene and filepath:', previous_scene.name)


if __name__ == '__main__':
    generate()
