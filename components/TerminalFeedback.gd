extends Area3D

class_name TerminalFeedback

@onready var visualization_mesh: MeshInstance3D = $Visualization
@onready var label: Label3D = $Label3D

var original_material: Material = null
var selected_material: StandardMaterial3D = null

var base_label_text: String = "" 
var is_selected: bool = false

func _ready():
	visualization_mesh = $Visualization 
	if not visualization_mesh:
		printerr("TerminalFeedback requires a child MeshInstance3D named 'Visualization'.")
		return
	if not label:
		printerr("TerminalFeedback requires a child Label3D named 'Label3D'.")
		return
	base_label_text = label.text 
	label.text = ""

	if visualization_mesh.material_override:
		original_material = visualization_mesh.material_override.duplicate() 
		if original_material is StandardMaterial3D:
			selected_material = original_material.duplicate()
			selected_material.albedo_color = original_material.albedo_color.darkened(0.4)
			selected_material.albedo_color.a = max(0.7, original_material.albedo_color.a) 
		else:
			selected_material = original_material
	else:
		printerr("Visualization mesh in terminal {term_name} has no material_override.".format({"term_name": self.name}))

	label.visible = false

func select():
	if selected_material:
		visualization_mesh.material_override = selected_material
	label.text = base_label_text
	label.visible = true
	is_selected = true

func deselect():
	if original_material:
		visualization_mesh.material_override = original_material
	if not label.text.ends_with(" V"):
		label.visible = false
		label.text = ""
	is_selected = false

func show_voltage(voltage: float):
	label.text = "{volt_str} V".format({"volt_str": String.num(voltage, 2)})
	label.visible = true

func hide_voltage():
	label.visible = false
	label.text = ""
