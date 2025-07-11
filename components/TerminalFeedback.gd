extends Area3D

class_name TerminalFeedback

## The MeshInstance3D used for visual feedback (e.g., highlighting).
@onready var visualization_mesh: MeshInstance3D = $Visualization
## The Label3D used to display terminal information like name or voltage.
@onready var label: Label3D = $Label3D

## Stores the default material of the terminal visualization.
var original_material: Material = null
## A modified material used to indicate when the terminal is selected.
var selected_material: StandardMaterial3D = null

## The original text of the label, stored to be restored later.
var base_label_text: String = "" 
## A flag indicating if the terminal is currently selected for wiring.
var is_selected: bool = false

## Called when the node enters the scene tree. Initializes materials and labels.
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

## Visually marks the terminal as selected for wiring.
func select():
	if selected_material:
		visualization_mesh.material_override = selected_material
	label.text = base_label_text
	label.visible = true
	is_selected = true

## Visually deselects the terminal.
func deselect():
	if original_material:
		visualization_mesh.material_override = original_material
	if not label.text.ends_with(" V"):
		label.visible = false
		label.text = ""
	is_selected = false

## Displays a voltage value on the terminal's label.
func show_voltage(voltage: float):
	label.text = "{volt_str} V".format({"volt_str": String.num(voltage, 2)})
	label.visible = true

## Hides the voltage display and resets the label.
func hide_voltage():
	label.visible = false
	label.text = ""
