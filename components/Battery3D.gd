extends Node3D

class_name Battery3D


signal configuration_changed(component_node: Node3D)

const VOLTAGE_PER_CELL: float = 1.5


@export_range(1, 4, 1) var num_cells: int = 1 : set = set_num_cells


var target_voltage: float = VOLTAGE_PER_CELL 

@onready var terminal_pos: Area3D = $TerminalPositive
@onready var terminal_neg: Area3D = $TerminalNegative
@onready var current_label: Label3D = $CurrentLabel
var cell_meshes: Array[MeshInstance3D] 

func _ready():
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
		if is_inside_tree(): 
			emit_signal("configuration_changed", self)
	elif not is_inside_tree(): 
		num_cells = new_val
		_recalculate_voltage()


func _update_cell_visuals():
	if not cell_meshes or cell_meshes.is_empty() or not is_instance_valid(cell_meshes[0]):
		return

	var cell_length = 0.18 
	var spacing = 0.02   
	var total_stack_length = 0.0
	
	for i in range(cell_meshes.size()):
		if is_instance_valid(cell_meshes[i]):
			if i < num_cells:
				cell_meshes[i].visible = true
				var x_pos = (float(i) * (cell_length + spacing)) - (float(num_cells - 1) * (cell_length + spacing) / 2.0)
				cell_meshes[i].position = Vector3(x_pos, 0, 0)
				total_stack_length += cell_length + (spacing if i < num_cells -1 else 0.0)
			else:
				cell_meshes[i].visible = false
	


func show_current(actual_current: float, actual_voltage: float):
	if not current_label: return

	var current_str = "N/A"
	var disp_current: float = NAN 

	if not is_nan(actual_current):
		disp_current = -actual_current 
		
		if abs(disp_current) < 1e-3 and abs(disp_current) > 1e-12: 
			current_str = "{curr_val} µA".format({"curr_val": String.num(disp_current * 1e6, 2)})
		elif abs(disp_current) < 1.0: 
			current_str = "{curr_val} mA".format({"curr_val": String.num(disp_current * 1e3, 2)})
		else:
			current_str = "{curr_val} A".format({"curr_val": String.num(disp_current, 2)})

	var voltage_str = "N/A"
	if not is_nan(actual_voltage):
		voltage_str = "{volt_val} V".format({"volt_val": String.num(actual_voltage, 2)})
	
	current_label.text = "{curr} @ {volt}".format({"curr": current_str, "volt": voltage_str}) 
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false

func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary,
	inductor_map: Dictionary,
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	delta_time: float
):
	var pos_term_instance_id = terminal_pos.get_instance_id() if is_instance_valid(terminal_pos) else -1
	var neg_term_instance_id = terminal_neg.get_instance_id() if is_instance_valid(terminal_neg) else -1

	var pos_node_lookup_id = terminal_connections.get(pos_term_instance_id, -1)
	var neg_node_lookup_id = terminal_connections.get(neg_term_instance_id, -1)

	var pos_idx = node_map.get(pos_node_lookup_id, -1)
	var neg_idx = node_map.get(neg_node_lookup_id, -1)
	
	var battery_instance_id = self.get_instance_id()
	if not vs_map.has(battery_instance_id):
		printerr("Critical Error: Battery {batid} not found in vs_map.".format({"batid": battery_instance_id}))
		return
	var battery_current_matrix_idx = vs_map[battery_instance_id]
	
	var V_target_val = comp_data.properties["target_voltage"]
	
	b[battery_current_matrix_idx] = V_target_val
	if pos_idx != -1:
		A[battery_current_matrix_idx][pos_idx] = 1.0
		A[pos_idx][battery_current_matrix_idx] = 1.0
	if neg_idx != -1:
		A[battery_current_matrix_idx][neg_idx] = -1.0
		A[neg_idx][battery_current_matrix_idx] = -1.0
