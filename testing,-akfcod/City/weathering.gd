@tool
class_name Weathering
extends Node3D
## Applies the weathering overlay to every mesh under this node (in the editor
## and in game). Tweak the sliders to make a district look safer or more run down.
## Also repaints each building's grey facade with a colour from the city palette.

@export_range(0.0, 1.0) var grime := 0.5:
	set(v): grime = v; _apply()
@export_range(0.0, 1.0) var cracks := 0.3:
	set(v): cracks = v; _apply()
@export_range(0.0, 1.0) var moss := 0.0:
	set(v): moss = v; _apply()
## World height of the flood tide-mark. Leave at -100 for no flood stain.
@export var water_line := -100.0:
	set(v): water_line = v; _apply()
@export var ground_y := 0.0:
	set(v): ground_y = v; _apply()

@export_group("Colour")
## Paint building facades with the palette below.
@export var colorful := true:
	set(v): colorful = v; _apply()
## How strongly the palette replaces the grey walls (1 = full colour).
@export_range(0.0, 1.0) var paint_strength := 0.9:
	set(v): paint_strength = v; _apply()
## How strongly ground floors / ledges get a darker accent colour.
@export_range(0.0, 1.0) var trim_strength := 0.5:
	set(v): trim_strength = v; _apply()
## Change this to reshuffle which building gets which colour.
@export var palette_seed := 0:
	set(v): palette_seed = v; _apply()
## City palette. Any building can force a colour with metadata "paint_color" (Color).
@export var palette: PackedColorArray = PackedColorArray([
	Color8(97, 203, 140),   # mint green
	Color8(33, 141, 109),   # deep green
	Color8(255, 192, 68),   # sunflower yellow
	Color8(255, 154, 50),   # amber
	Color8(254, 127, 68),   # orange
	Color8(245, 104, 67),   # coral
	Color8(208, 83, 80),    # brick red
	Color8(102, 148, 217),  # sky blue
	Color8(90, 95, 200),    # indigo
]):
	set(v): palette = v; _apply()

const SHADER := preload("res://City/weathering.gdshader")
const PAINT_SHADER := preload("res://City/building_paint.gdshader")
const COLORMAP := preload("res://Models/GLB format/Textures/colormap.png")

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_inside_tree():
		return
	_apply_paint()
	var off := grime <= 0.0 and cracks <= 0.0 and moss <= 0.0 and water_line <= ground_y
	var i := 0
	for child in get_children():
		# one material per building so each gets its own pattern offset
		var mat: ShaderMaterial = null
		if off and not child.has_meta("grime"):
			for mesh in child.find_children("*", "MeshInstance3D", true, false):
				mesh.material_overlay = null
			i += 1
			continue
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("grime", child.get_meta("grime", grime))
		mat.set_shader_parameter("cracks", child.get_meta("cracks", cracks))
		mat.set_shader_parameter("moss", moss)
		mat.set_shader_parameter("water_line", water_line)
		mat.set_shader_parameter("ground_y", ground_y)
		mat.set_shader_parameter("seed", float(i) * 1.618)
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = mat
		if child is MeshInstance3D:
			child.material_overlay = mat
		i += 1

func _apply_paint() -> void:
	var n := palette.size()
	for child in get_children():
		if not child is Node3D:
			continue
		var meshes: Array = child.find_children("*", "MeshInstance3D", true, false)
		if child is MeshInstance3D:
			meshes.append(child)
		if not colorful or n == 0:
			for mesh in meshes:
				if mesh.material_override is ShaderMaterial and mesh.material_override.shader == PAINT_SHADER:
					mesh.material_override = null
			continue
		# pick colours from the building's position so neighbours differ and
		# the result stays the same every time the scene loads
		var p: Vector3 = child.position
		var h := absi(int(floor(p.x * 3.0)) * 73856093 ^ int(floor(p.z * 3.0)) * 19349663 ^ palette_seed * 83492791)
		var wall: Color = child.get_meta("paint_color", palette[h % n])
		var trim: Color = child.get_meta("trim_color", palette[(h / 7 + 3) % n])
		var mat := ShaderMaterial.new()
		mat.shader = PAINT_SHADER
		mat.set_shader_parameter("albedo_tex", _find_texture(meshes))
		mat.set_shader_parameter("paint_color", wall)
		mat.set_shader_parameter("trim_color", trim)
		mat.set_shader_parameter("paint_strength", child.get_meta("paint_strength", paint_strength))
		mat.set_shader_parameter("trim_strength", trim_strength)
		for mesh in meshes:
			mesh.material_override = mat

func _find_texture(meshes: Array) -> Texture2D:
	for mesh in meshes:
		var m: MeshInstance3D = mesh
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat is ShaderMaterial and mat.shader == PAINT_SHADER:
				mat = m.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and mat.albedo_texture:
				return mat.albedo_texture
	return COLORMAP
