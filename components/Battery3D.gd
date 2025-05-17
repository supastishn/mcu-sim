extends Node3D

class_name Battery3D

## Signal emitted when the number of cells (and thus voltage) changes.
signal configuration_changed(component_node: Node3D)

const VOLTAGE_PER_CELL: float = 1.5

## Number of 1.5V cells in series.
@export_range(1, 4, 1) var num_cells: int = 1 : set = set_num_cells

## The calculated target voltage of the battery pack.
var target_voltage: float = VOLTAGE_PER_CELL # Initial value for 1 cell

@onready var terminal_pos: Area3D = $TerminalPositive
@onready var terminal_neg: Area3D = $TerminalNegative
@onready var current_label: Label3D = $CurrentLabel
# Assuming you will name the cell meshes Cell1, Cell2, Cell3, Cell4 in the .tscn file
var cell_meshes: Array[MeshInstance3D] # Declare, but don't initialize with $ paths here

func _ready():
	# Populate cell_meshes array in _ready
	cell_meshes = [
		get_node("Cell1") as MeshInstance3D,
		get_node("Cell2") as MeshInstance3D,
		get_node("Cell3") as MeshInstance3D,
		get_node("Cell4") as MeshInstance3D
	]
	if not current_label:
		printerr("Battery3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false
	
	# Initial calculation and visual update
	_recalculate_voltage()
	_update_cell_visuals()

func _recalculate_voltage():
	target_voltage = float(num_cells) * VOLTAGE_PER_CELL
	print("Battery {batt_name} voltage recalculated to: {volt_str}V for {num_c} cells".format({"batt_name": name, "volt_str": String.num(target_voltage, 2), "num_c": num_cells}))

func set_num_cells(value: int):
	var new_val = clamp(value, 1, 4)
	if num_cells != new_val:
		num_cells = new_val
		_recalculate_voltage()
		_update_cell_visuals()
		if is_inside_tree(): # Only emit if part of the scene tree and actually changed
			emit_signal("configuration_changed", self)
	elif not is_inside_tree(): # Ensure initial setup if value is set before ready
		num_cells = new_val
		_recalculate_voltage()
		# _update_cell_visuals will be called in _ready


func _update_cell_visuals():
	if not cell_meshes or cell_meshes.is_empty() or not is_instance_valid(cell_meshes[0]):
		# This can happen if @onready vars are not yet available (e.g. during initial set_num_cells from export)
		# _ready() will call this again.
		return

	# Adjust visibility and position of cell meshes
	var cell_length = 0.18 # Actual length of the cell mesh (its original height)
	var spacing = 0.02   # Spacing between cells
	var total_stack_length = 0.0
	
	for i in range(cell_meshes.size()):
		if is_instance_valid(cell_meshes[i]):
			if i < num_cells:
				cell_meshes[i].visible = true
				# Stack them along the X axis, centered.
				var x_pos = (float(i) * (cell_length + spacing)) - (float(num_cells - 1) * (cell_length + spacing) / 2.0)
				cell_meshes[i].position = Vector3(x_pos, 0, 0) # Set full position vector
				total_stack_length += cell_length + (spacing if i < num_cells -1 else 0.0)
			else:
				cell_meshes[i].visible = false
	
	# Optional: Adjust overall component size or terminal positions based on stack length.
	# Terminal positions are fixed in the .tscn for now, but could be made dynamic here.
	# This example assumes fixed terminal positions relative to the main Battery3D node.


func show_current(actual_current: float, actual_voltage: float):
	if not current_label: return

	var current_str = "N/A"
	var disp_current: float = NAN 

	if not is_nan(actual_current):
		# MNA current for a source: positive if current flows from external circuit INTO positive terminal (charging)
		# Negative if current flows OUT of positive terminal (supplying).
		# We display positive as supplying.
		disp_current = -actual_current 
		
		if abs(disp_current) < 1e-3 and abs(disp_current) > 1e-12: # Between 1uA and 1mA
			current_str = "{curr_val} µA".format({"curr_val": String.num(disp_current * 1e6, 2)})
		elif abs(disp_current) < 1.0: # Between 1mA and 1A
			current_str = "{curr_val} mA".format({"curr_val": String.num(disp_current * 1e3, 2)})
		else:
			current_str = "{curr_val} A".format({"curr_val": String.num(disp_current, 2)})

	var voltage_str = "N/A"
	if not is_nan(actual_voltage):
		voltage_str = "{volt_val} V".format({"volt_val": String.num(actual_voltage, 2)})
	
	current_label.text = "{curr} @ {volt}".format({"curr": current_str, "volt": voltage_str}) # Batteries are always "CV" effectively
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false
