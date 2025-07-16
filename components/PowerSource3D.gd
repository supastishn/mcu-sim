extends Node3D

class_name PowerSource3D


## The target output voltage in Constant Voltage (CV) mode.
@export var target_voltage: float = 5.0

## The target output current in Constant Current (CC) mode.
@export var target_current: float = 1.0


## Reference to the positive terminal Area3D node.
@onready var terminal_pos: Area3D = $TerminalPositive
## Reference to the negative terminal Area3D node.
@onready var terminal_neg: Area3D = $TerminalNegative
## Reference to the Label3D for displaying simulation info.
@onready var current_label: Label3D = $CurrentLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not current_label:
		printerr("PowerSource3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false



## Displays the current, voltage, and operating mode (CV or CC) on the component's 3D label.
func show_current(actual_current: float, actual_voltage: float, operating_mode: String = "CV"):
	if not current_label: return

	var current_str = "N/A"
	var disp_current: float = NAN 

	if not is_nan(actual_current):
		disp_current = -actual_current
		current_str = StringUtils.format_current(disp_current)

	var voltage_str = "N/A"
	if not is_nan(actual_voltage):
		voltage_str = "{val_str} V".format({"val_str": String.num(actual_voltage, 2)})
	
	var op_mode_str: String
	if operating_mode == "CV":
		op_mode_str = "CV Mode"
		if not is_nan(actual_current):
			current_str = StringUtils.format_current(-actual_current)
		if not is_nan(actual_voltage) and not is_nan(target_voltage) and \
		   abs(actual_voltage - target_voltage) > 0.1 * abs(target_voltage) + 0.1 : 
			if abs(actual_current) > target_current + 1e-9: 
				op_mode_str = "CV (Overload?)"


	elif operating_mode == "CC":
		op_mode_str = "CC Limiting"
		if not is_nan(actual_current):
			current_str = StringUtils.format_current(actual_current)
		current_str += " (Limit)"
	else: 
		op_mode_str = operating_mode 

	current_label.text = "{op_mode}: {curr_str} @ {volt_str}".format({"op_mode": op_mode_str, "curr_str": current_str, "volt_str": voltage_str})
	current_label.visible = true

## Hides the information label.
func hide_current():
	if not current_label: return
	current_label.visible = false

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"POS": {"node": terminal_pos, "pos": terminal_pos.position},
		"NEG": {"node": terminal_neg, "pos": terminal_neg.position}
	}

## Updates the power supply's operating mode (CV or CC) based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, vs_map_iter: Dictionary) -> bool:
	# x_iter is the current iteration's solution vector (circuit._current_iteration_solution)
	# node_map_iter is the current iteration's node map (circuit._current_iteration_node_map)
	# vs_map_iter is the current iteration's voltage source map (circuit._current_iteration_vs_map)
	# These would need to be set by CircuitGraph.solve_single_time_step before calling this.

	var ps_id = comp_data.component_node.get_instance_id()
	var I_limit = comp_data.properties.target_current 
	var V_target_ps = comp_data.properties.target_voltage
	var previous_op_mode = comp_data.properties.current_operating_mode
	var new_op_mode = previous_op_mode
	var state_changed = false

	if previous_op_mode == "CV":
		if x_iter != null and vs_map_iter != null:
			var vs_current_idx = vs_map_iter.get(ps_id, -1)
			if vs_current_idx != -1 and vs_current_idx < x_iter.size():
				var current_mna_val_for_ps = x_iter[vs_current_idx] 
				var current_supplied_by_ps = -current_mna_val_for_ps
				if abs(current_supplied_by_ps) > (I_limit + 1e-9): # Using a small tolerance for float comparison
					new_op_mode = "CC"
					comp_data.properties.cc_current_direction_sign = sign(current_supplied_by_ps) # Store direction for CC mode
	
	elif previous_op_mode == "CC":
		if x_iter.is_empty():
			return false

		var term_p_ps = comp_data.terminals["POS"]
		var term_n_ps = comp_data.terminals["NEG"]
		var node_p_id_ps = circuit.terminal_connections.get(term_p_ps.get_instance_id(), -1)
		var node_n_id_ps = circuit.terminal_connections.get(term_n_ps.get_instance_id(), -1)
		
		var idx_p = node_map_iter.get(node_p_id_ps, -1)
		var idx_n = node_map_iter.get(node_n_id_ps, -1)
		var Vp_ps = x_iter[idx_p] if idx_p != -1 else (0.0 if node_p_id_ps == circuit.ground_node_id else NAN)
		var Vn_ps = x_iter[idx_n] if idx_n != -1 else (0.0 if node_n_id_ps == circuit.ground_node_id else NAN)
		
		if not is_nan(Vp_ps) and not is_nan(Vn_ps):
			var V_across_cc = Vp_ps - Vn_ps
			var cc_direction_sign = comp_data.properties.get("cc_current_direction_sign", 1.0)
			# If voltage rises above target voltage (considering direction) while in CC, switch back to CV
			if cc_direction_sign * V_across_cc > cc_direction_sign * V_target_ps + 1e-6: # Tolerance for float comparison
				new_op_mode = "CV"
	
	if new_op_mode != previous_op_mode:
		comp_data.properties.current_operating_mode = new_op_mode
		state_changed = true
		
	return state_changed

## Applies the power supply's contribution to the MNA matrices, modeling it as a voltage or current source.
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
	var ps_op_mode = comp_data.properties.get("current_operating_mode", "CV")
	
	var pos_term_id = terminal_pos.get_instance_id() if is_instance_valid(terminal_pos) else -1
	var neg_term_id = terminal_neg.get_instance_id() if is_instance_valid(terminal_neg) else -1

	var pos_node_lookup_id = terminal_connections.get(pos_term_id, -1)
	var neg_node_lookup_id = terminal_connections.get(neg_term_id, -1)

	var pos_idx = node_map.get(pos_node_lookup_id, -1)
	var neg_idx = node_map.get(neg_node_lookup_id, -1)

	if ps_op_mode == "CV":
		var ps_instance_id = self.get_instance_id()
		if not vs_map.has(ps_instance_id):
			printerr("Critical Error: PowerSource {psid} in CV mode not found in vs_map.".format({"psid": ps_instance_id}))
			return
		var ps_current_matrix_idx = vs_map[ps_instance_id]
		var V_target = comp_data.properties["target_voltage"] 
		
		b[ps_current_matrix_idx] = V_target
		if pos_idx != -1:
			A[ps_current_matrix_idx][pos_idx] = 1.0
			A[pos_idx][ps_current_matrix_idx] = 1.0
		if neg_idx != -1:
			A[ps_current_matrix_idx][neg_idx] = -1.0
			A[neg_idx][ps_current_matrix_idx] = -1.0
			
	elif ps_op_mode == "CC":
		var I_target = comp_data.properties["target_current"] 
		var direction_sign = comp_data.properties.get("cc_current_direction_sign", 1.0) 
		var actual_current_to_stamp = direction_sign * I_target
		
		if pos_idx != -1:
			b[pos_idx] += actual_current_to_stamp 
		if neg_idx != -1:
			b[neg_idx] -= actual_current_to_stamp 

## Extracts and stores simulation results (current, voltage, mode) for this component.
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

	var ps_op_mode = comp_data.properties.get("current_operating_mode", "CV")
	if ps_op_mode == "CV":
		if vs_map.has(comp_id): 
			var matrix_idx_curr_final = vs_map[comp_id]
			if matrix_idx_curr_final < x.size():
				var solved_current_mna = x[matrix_idx_curr_final] 
				circuit.component_results[comp_id]["current"] = -solved_current_mna 
				
				var term_p_fv = comp_data.terminals["POS"]
				var term_n_fv = comp_data.terminals["NEG"]
				var Vp_fv = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_p_fv.get_instance_id(), -1), {}).get("voltage", NAN)
				var Vn_fv = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_n_fv.get_instance_id(), -1), {}).get("voltage", NAN)
				var actual_V_across_fv = NAN
				if not is_nan(Vp_fv) and not is_nan(Vn_fv): actual_V_across_fv = Vp_fv - Vn_fv
				circuit.component_results[comp_id]["voltage"] = actual_V_across_fv
				circuit.component_results[comp_id]["operating_mode"] = "CV"
	elif ps_op_mode == "CC":
		var cc_current_val = comp_data.properties.cc_current_direction_sign * comp_data.properties.target_current
		circuit.component_results[comp_id]["current"] = cc_current_val
		circuit.component_results[comp_id]["operating_mode"] = "CC"
		var term_p_cc = comp_data.terminals["POS"]
		var term_n_cc = comp_data.terminals["NEG"]
		var Vp_cc = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_p_cc.get_instance_id(), -1), {}).get("voltage", NAN)
		var Vn_cc = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_n_cc.get_instance_id(), -1), {}).get("voltage", NAN)
		var actual_V_across_cc = NAN
		if not is_nan(Vp_cc) and not is_nan(Vn_cc): actual_V_across_cc = Vp_cc - Vn_cc
		circuit.component_results[comp_id]["voltage"] = actual_V_across_cc
