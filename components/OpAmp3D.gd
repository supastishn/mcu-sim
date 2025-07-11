extends Node3D

# Terminal References
@onready var terminal_vp  : Area3D = $TerminalVp
@onready var terminal_vn  : Area3D = $TerminalVn
@onready var terminal_vout: Area3D = $TerminalVout
@onready var terminal_vcc : Area3D = $TerminalVcc
@onready var terminal_vee : Area3D = $TerminalVee

# Properties
@export var open_loop_gain: float = 100000.0
@export var rail_saturation_voltage: float = 0.2

func update_nonlinear_state(
	graph: CircuitGraph, 
	comp_data: Dictionary, 
	x: Array, 
	node_map: Dictionary, 
	vs_map: Dictionary, 
	inductor_map: Dictionary
) -> bool:
	var term_vp = comp_data.terminals["Vp"]
	var term_vn = comp_data.terminals["Vn"]
	var term_vcc = comp_data.terminals["Vcc"]
	var term_vee = comp_data.terminals["Vee"]
	
	var node_id_vp = graph.terminal_connections.get(term_vp.get_instance_id(), -1)
	var node_id_vn = graph.terminal_connections.get(term_vn.get_instance_id(), -1)
	var node_id_vcc = graph.terminal_connections.get(term_vcc.get_instance_id(), -1)
	var node_id_vee = graph.terminal_connections.get(term_vee.get_instance_id(), -1)
	
	if node_id_vp == -1 or node_id_vn == -1 or node_id_vcc == -1 or node_id_vee == -1:
		return false
	
	# Get voltages
	var vcc = graph.electrical_nodes.get(node_id_vcc, {}).get("voltage", NAN)
	var vee = graph.electrical_nodes.get(node_id_vee, {}).get("voltage", NAN)
	var vp = graph.electrical_nodes.get(node_id_vp, {}).get("voltage", NAN)
	var vn = graph.electrical_nodes.get(node_id_vn, {}).get("voltage", NAN)
	
	# Check power validity
	if is_nan(vcc) or is_nan(vee) or is_nan(vp) or is_nan(vn) or vcc - vee < 0.1:
		comp_data.properties["operating_region"] = "OFF"
		comp_data["_output_voltage"] = 0.0
		return true
	
	# Determine output state
	var linear_out = open_loop_gain * (vp - vn)
	var vout_high = vcc - rail_saturation_voltage
	var vout_low = vee + rail_saturation_voltage
	
	var new_region: String
	var new_vout: float
	
	if linear_out >= vout_high:
		new_region = "SAT_HIGH"
		new_vout = vout_high
	elif linear_out <= vout_low:
		new_region = "SAT_LOW"
		new_vout = vout_low
	else:
		new_region = "LINEAR"
		new_vout = linear_out
	
	# Update state if changed
	if new_region != comp_data.properties.get("operating_region") or \
	   abs(new_vout - comp_data.get("_output_voltage", 0.0)) > 0.0001:
		comp_data.properties["operating_region"] = new_region
		comp_data["_output_voltage"] = new_vout
		return true
	
	return false

func stamp(
	A: Array, 
	b: Array, 
	node_map: Dictionary, 
	vs_map: Dictionary, 
	inductor_map: Dictionary, 
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	delta_time: float
) -> void:
	var output_voltage = comp_data.get("_output_voltage", 0.0)
	var term = terminal_vout
	var term_id = term.get_instance_id()
	
	# Get connected node for Vout
	var node_id = terminal_connections.get(term_id, -1)
	if node_id == -1: 
		return
	
	# Get matrix indices
	var n_nodes = node_map.size()
	var vs_id = vs_map.get(get_instance_id(), -1)
	if vs_id == -1: 
		return
	var idx_vout = node_map.get(node_id, -1)
	if idx_vout == -1: 
		return
	
	# Stamp as voltage source to ground
	if not is_nan(output_voltage):
		var col_idx = n_nodes + vs_id
		var row_idx = n_nodes + vs_id
		
		if col_idx < A[0].size() and row_idx < A.size():
			# KCL for Vout node
			A[idx_vout][col_idx] += 1.0
			# Voltage source equation
			A[row_idx][idx_vout] = 1.0
			b[row_idx] = output_voltage

func gather_sim_results(
	graph: CircuitGraph,
	comp_data: Dictionary,
	x: Array,
	node_map: Dictionary,
	vs_map: Dictionary,
	inductor_map: Dictionary,
	delta_time: float
) -> void:
	var results = {
		"region": comp_data.properties.get("operating_region", "OFF"),
		"Vout": comp_data.get("_output_voltage", 0.0)
	}
	graph.component_results[get_instance_id()] = results
