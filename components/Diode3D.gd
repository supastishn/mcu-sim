extends Node3D

class_name Diode3D


## The voltage drop across the diode when it is forward-biased, in volts.
@export var forward_voltage: float = 0.7

## Reference to the Anode terminal Area3D node.
@onready var terminal_anode: Area3D = $TerminalAnode 
## Reference to the Kathode terminal Area3D node.
@onready var terminal_kathode: Area3D = $TerminalKathode 
## Reference to the visual representation (MeshInstance3D) of the diode.
@onready var diode_mesh_instance: MeshInstance3D = $MeshInstance3D 
## Reference to the Label3D node for displaying current flow.
@onready var current_label: Label3D = $CurrentLabel

## Called when the node enters the scene tree for the first time. Initializes the component.
func _ready():
	if not current_label:
		printerr("Diode3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

## Displays the calculated current value on the component's 3D label.
func show_current(current_value: float):
	if not current_label: return
	if is_nan(current_value):
		current_label.text = "I: N/A"
	else:
		current_label.text = "I: " + StringUtils.format_current(current_value)
	current_label.visible = true

## Hides the current display label.
func hide_current():
	if not current_label: return
	current_label.visible = false

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"A": {"node": terminal_anode, "pos": terminal_anode.position},
		"K": {"node": terminal_kathode, "pos": terminal_kathode.position}
	}

## Extracts and stores simulation results for this component from the main solution vector.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		_x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		_inductor_map : Dictionary,
		_delta_time   : float) -> void:
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()

	var R_diode_on_model = circuit.R_DIODE_ON
	var Vf_diode_calc = comp_data.properties["forward_voltage"]
	var term_a = comp_data.terminals["A"]
	var term_k = comp_data.terminals["K"]
	var node_a_id = circuit.terminal_connections.get(term_a.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(term_k.get_instance_id(), -1)
	var Va = circuit.electrical_nodes.get(node_a_id, {}).get("voltage", NAN)
	var Vk = circuit.electrical_nodes.get(node_k_id, {}).get("voltage", NAN)
	var current = 0.0

	if comp_data.get("conducting", false) and not is_nan(Va) and not is_nan(Vk):
		var V_ak_calc = Va - Vk
		if V_ak_calc > Vf_diode_calc:
			current = (V_ak_calc - Vf_diode_calc) / R_diode_on_model
		else:
			current = 0.0
	else:
		current = 0.0

	circuit.component_results[comp_id]["current"] = current

## Updates the diode's conducting state based on the latest voltage solution from an MNA iteration.
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

## Applies the diode's contribution to the MNA matrices (A and b) based on its current state.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary,
	_inductor_map: Dictionary,
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	_delta_time: float
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
