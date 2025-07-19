extends Node3D

class_name Battery3D

const LinearSolver = preload("res://LinearSolver.gd")


## Emitted when a key property (like number of cells) changes.
signal configuration_changed(component_node: Node3D)

## The nominal voltage of a single battery cell.
const VOLTAGE_PER_CELL: float = 1.5


## The number of cells in the battery, determining its total voltage.
@export_range(1, 4, 1) var num_cells: int = 1 : set = set_num_cells


## The target voltage of the battery, calculated from `num_cells`.
var target_voltage: float = VOLTAGE_PER_CELL 

## Reference to the positive terminal Area3D node.
@onready var terminal_pos: Area3D = $TerminalPositive
## Reference to the negative terminal Area3D node.
@onready var terminal_neg: Area3D = $TerminalNegative
## Reference to the Label3D for displaying current.
@onready var current_label: Label3D = $CurrentLabel
## An array of MeshInstance3D nodes representing the individual cells.
var cell_meshes: Array[MeshInstance3D] 

## Called when the node enters the scene tree. Initializes the component.
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

## Recalculates the battery's total target voltage based on the number of cells.
func _recalculate_voltage():
	target_voltage = float(num_cells) * VOLTAGE_PER_CELL
	print("Battery {batt_name} voltage recalculated to: {volt_str}V for {num_c} cells".format({"batt_name": name, "volt_str": String.num(target_voltage, 2), "num_c": num_cells}))

## Sets the number of cells, validates the value, and updates visuals and voltage.
func set_num_cells(value: int):
	var new_val = clamp(value, 1, 4)
	if num_cells == new_val:
		return

	num_cells = new_val
	_recalculate_voltage()
	_update_cell_visuals()
	if is_inside_tree():
		emit_signal("configuration_changed", self)


## Updates the visibility and position of the cell meshes to match `num_cells`.
func _update_cell_visuals():
	if not cell_meshes or cell_meshes.is_empty() or not is_instance_valid(cell_meshes[0]):
		return

	var cell_length = 0.18 
	var spacing = 0.02
	
	for i in range(cell_meshes.size()):
		if is_instance_valid(cell_meshes[i]):
			if i < num_cells:
				cell_meshes[i].visible = true
				var x_pos = (float(i) * (cell_length + spacing)) - (float(num_cells - 1) * (cell_length + spacing) / 2.0)
				cell_meshes[i].position = Vector3(x_pos, 0, 0)
			else:
				cell_meshes[i].visible = false
	


## Displays the calculated current and voltage on the component's 3D label.
func show_current(actual_current: float, actual_voltage: float):
	if not current_label: return

	var current_str = "N/A"
	var disp_current: float = NAN 

	if not is_nan(actual_current):
		disp_current = -actual_current
		current_str = StringUtils.format_current(disp_current)

	var voltage_str = "N/A"
	if not is_nan(actual_voltage):
		voltage_str = "{volt_val} V".format({"volt_val": String.num(actual_voltage, 2)})
	
	current_label.text = "{curr} @ {volt}".format({"curr": current_str, "volt": voltage_str}) 
	current_label.visible = true

## Hides the current display label.
func hide_current():
	if not current_label: return
	current_label.visible = false

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"POS": {"node": terminal_pos, "pos": terminal_pos.position},
		"NEG": {"node": terminal_neg, "pos": terminal_neg.position}
	}

## Applies the battery's ideal voltage source contribution to the MNA matrices.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary,
	_inductor_map: Dictionary,
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	_delta_time: float
):
	var pos_term_instance_id = terminal_pos.get_instance_id() if is_instance_valid(terminal_pos) else -1
	var neg_term_instance_id = terminal_neg.get_instance_id() if is_instance_valid(terminal_neg) else -1

	var pos_node_lookup_id = terminal_connections.get(pos_term_instance_id, -1)
	var neg_node_lookup_id = terminal_connections.get(neg_term_instance_id, -1)

	var pos_idx = node_map.get(pos_node_lookup_id, -1)
	var neg_idx = node_map.get(neg_node_lookup_id, -1)
	
	var battery_instance_id = self.get_instance_id()
	if not vs_map.has(battery_instance_id):
		LinearSolver.print_matrix(A, "A on battery stamp fail")
		LinearSolver.print_vector(b, "b on battery stamp fail")
		printerr("Battery {id} not found in vs_map. Map: {map}".format({ "id": battery_instance_id, "map": vs_map }))
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

## Extracts and stores simulation results for this component from the main solution vector.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		x            : Array,
		_node_map     : Dictionary,
		vs_map       : Dictionary,
		_inductor_map : Dictionary,
		_delta_time   : float) -> void:
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()

	if not vs_map.has(comp_id):
		LinearSolver.print_vector(x, "x on battery results fail")
		printerr("Battery {id} not found in vs_map. Map: {map}".format({ "id": comp_id, "map": vs_map }))
		return
	var matrix_idx_curr_final = vs_map[comp_id]
	if not (matrix_idx_curr_final < x.size()):
		LinearSolver.print_vector(x, "x on battery results fail")
		printerr("Battery {id}: current index ({idx}) out of bounds in solution vector (size {sz}).".format({ "id": comp_id, "idx": matrix_idx_curr_final, "sz": x.size() }))
		return
	var solved_current_mna = x[matrix_idx_curr_final]
	if not !is_nan(solved_current_mna):
		LinearSolver.print_vector(x, "x on battery results fail")
		printerr("Battery {id}: solved current is NaN at index {idx}.".format({ "id": comp_id, "idx": matrix_idx_curr_final }))
	circuit.component_results[comp_id]["current"] = -solved_current_mna 
			
	var term_p_fv = comp_data.terminals["POS"]
	var term_n_fv = comp_data.terminals["NEG"]
	var Vp_fv = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_p_fv.get_instance_id(), -1), {}).get("voltage", NAN)
	var Vn_fv = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_n_fv.get_instance_id(), -1), {}).get("voltage", NAN)
	var actual_V_across_fv = NAN
	if not is_nan(Vp_fv) and not is_nan(Vn_fv): actual_V_across_fv = Vp_fv - Vn_fv
	circuit.component_results[comp_id]["voltage"] = actual_V_across_fv
