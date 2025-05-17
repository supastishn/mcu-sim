# @tool # Temporarily commented out for debugging loading issue
extends Area3D

class_name TerminalFeedback

@onready var visualization_mesh: MeshInstance3D = $Visualization
@onready var label: Label3D = $Label3D

var original_material: Material = null
var selected_material: StandardMaterial3D = null

var base_label_text: String = "" # To store the initial text (T1, POS, etc.)
var is_selected: bool = false

func _ready():
	visualization_mesh = $Visualization # Ensure it's assigned even if @onready not finished
	# Ensure Label3D and Visualization nodes are present
	if not visualization_mesh:
		printerr("TerminalFeedback requires a child MeshInstance3D named 'Visualization'.")
		return
	if not label:
		printerr("TerminalFeedback requires a child Label3D named 'Label3D'.")
		return
	base_label_text = label.text # Store the text set in the scene file (e.g., "T1")
	label.text = "" # Clear display text initially

	# Store original material and create a darker selected material
	if visualization_mesh.material_override:
		original_material = visualization_mesh.material_override.duplicate() # Duplicate to avoid modifying the resource
		if original_material is StandardMaterial3D:
			selected_material = original_material.duplicate()
			# Make it darker and slightly less transparent (if it was transparent)
			selected_material.albedo_color = original_material.albedo_color.darkened(0.4)
			selected_material.albedo_color.a = max(0.7, original_material.albedo_color.a) # Ensure some opacity
		else:
			# Fallback if not StandardMaterial3D - just use original for selected
			selected_material = original_material
	else:
		printerr("Visualization mesh in terminal {term_name} has no material_override.".format({"term_name": self.name}))

	# Set base name for debugging, but hide initially
	# label.text = base_label_text # We now clear it above
	label.visible = false # Hide voltage label initially

func select():
	if selected_material:
		visualization_mesh.material_override = selected_material
	# Show the base label text (e.g., "T1") when selected for wiring
	label.text = base_label_text
	label.visible = true
	is_selected = true

func deselect():
	if original_material:
		visualization_mesh.material_override = original_material
	# Only hide the label if it's not currently showing a voltage value (ends with " V")
	if not label.text.ends_with(" V"):
		label.visible = false
		label.text = "" # Clear base text
	is_selected = false

# Show the calculated voltage
func show_voltage(voltage: float):
	label.text = "{volt_str} V".format({"volt_str": String.num(voltage, 2)})
	label.visible = true

# Hide the voltage display
func hide_voltage():
	label.visible = false
	label.text = "" # Clear text
