extends Node3D

class_name Diode3D


@export var forward_voltage: float = 0.7

@onready var terminal_anode: Area3D = $TerminalAnode 
@onready var terminal_kathode: Area3D = $TerminalKathode 
@onready var diode_mesh_instance: MeshInstance3D = $MeshInstance3D 
@onready var current_label: Label3D = $CurrentLabel

func _ready():
	if not current_label:
		printerr("Diode3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

func show_current(current_value: float):
	if not current_label: return
	if is_nan(current_value):
		current_label.text = "I: N/A"
	else:
		if abs(current_value) < 1e-3 and abs(current_value) > 1e-12:
			current_label.text = "I: {val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
		elif abs(current_value) < 1.0:
			current_label.text = "I: {val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
		else:
			current_label.text = "I: {val_str} A".format({"val_str": String.num(current_value, 2)})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false

# -----------------------------------------------------------------
# Simulation-results extraction
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		x            : Array,
		node_map     : Dictionary,
		vs_map       : Dictionary,
		inductor_map : Dictionary,
		delta_time   : float) -> void:
	#region LEGACY_RESULT_CODE
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()
	if not comp_id in circuit.component_results: circuit.component_results[comp_id] = {}

	var R_diode_on_model = circuit.R_DIODE_ON
	var Vf_diode_calc = comp_data.properties["forward_voltage"]
	var term_a = comp_data.terminals["A"]
	var term_k = comp_data.terminals["K"]
	var node_a_id = circuit.terminal_connections.get(term_a.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(term_k.get_instance_id(), -1)
	var Va = circuit.electrical_nodes.get(node_a_id, {}).get("voltage", NAN)
	var Vk = circuit.electrical_nodes.get(node_k_id, {}).get("voltage", NAN)
	var current = 0.0
	var log_msg_suffix = "Not Conducting"

	if comp_data.get("conducting", false) and not is_nan(Va) and not is_nan(Vk):
		var V_ak_calc = Va - Vk
		if V_ak_calc > Vf_diode_calc: 
			current = (V_ak_calc - Vf_diode_calc) / R_diode_on_model
		else:
			current = 0.0 
		log_msg_suffix = "Conducting (flag was true)"
	else: 
		current = 0.0
		if is_nan(Va) or is_nan(Vk):
			log_msg_suffix = "Not Conducting (NaN voltages)"

	circuit.component_results[comp_id]["current"] = current
	#endregion

func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty():
		return false

	var term_a = comp_data.terminals["A"]
	var term_k = comp_data.terminals["K"]
	var node_a_id = circuit.terminal_connections.get(term_a.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(term_k.get_instance_id(), -1)

	var idx_a = node_map_iter.get(node_a_id, -1)
	var idx_k = node_map_iter.get(node_k_id, -1)
	var Va = x_iter[idx_a] if idx_a != -1 else (0.0 if node_a_id == circuit.ground_node_id else NAN)
	var Vk = x_iter[idx_k] if idx_k != -1 else (0.0 if node_k_id == circuit.ground_node_id else NAN)

	var forward_voltage_threshold = comp_data.properties["forward_voltage"]
	var should_conduct = false
	if not is_nan(Va) and not is_nan(Vk) and (Va - Vk) >= forward_voltage_threshold:
		should_conduct = true

	if comp_data["conducting"] != should_conduct:
		comp_data["conducting"] = should_conduct
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
):
	var on = comp_data.get("conducting", false)
	var R_on = CircuitGraph.R_DIODE_ON 
	var R_off = CircuitGraph.R_DIODE_OFF 
	var g = 1.0 / (R_on if on else R_off)

	var anode_instance_id = terminal_anode.get_instance_id()
	var kathode_instance_id = terminal_kathode.get_instance_id()

	var na = terminal_connections.get(anode_instance_id, -1)
	var nk = terminal_connections.get(kathode_instance_id, -1)

	var ia = node_map.get(na, -1)
	var ik = node_map.get(nk, -1)

	if on:
		var Vf = forward_voltage 
		var offset_val = Vf / R_on 
		if ia != -1: b[ia] += offset_val
		if ik != -1: b[ik] -= offset_val
	
	
	if ia != -1 and ik != -1:
		A[ia][ia] += g
		A[ik][ik] += g
		A[ia][ik] -= g
		A[ik][ia] -= g
	elif ia != -1:
		A[ia][ia] += g
	elif ik != -1:
		A[ik][ik] += g
