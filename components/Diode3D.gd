extends Node3D

class_name Diode3D


## The saturation current of the diode.
@export var saturation_current: float = 1.0e-12
## The ideality factor (emission coefficient) of the diode.
@export var ideality_factor: float = 1.0
const THERMAL_VOLTAGE: float = 0.02585 # At room temperature (300K)

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

	var Va = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["A"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vk = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["K"].get_instance_id(), -1), {}).get("voltage", NAN)
	
	var Is = comp_data.properties["saturation_current"]
	var n = comp_data.properties["ideality_factor"]
	var V_thermal = THERMAL_VOLTAGE
	
	var current = NAN
	assert(!is_nan(Va) and !is_nan(Vk), "Diode terminal voltages are NaN in gather_sim_results.")
	var Vd = Va - Vk
	current = saturation_current * (exp(Vd / (ideality_factor * THERMAL_VOLTAGE)) - 1.0)
	assert(!is_nan(current), "Diode current is NaN in gather_sim_results.")
	comp_data.properties["_internal_voltage"] = Vd

	circuit.component_results[comp_id]["current"] = current

## Applies the diode's contribution to the MNA matrices (A and b) based on its current state.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary,
	_opamp_map: Dictionary,
	_inductor_map: Dictionary,
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	_delta_time: float
):
	# This function now stamps a linearized model for the Newton-Raphson solver.
	var Vd_last_iter = comp_data.properties.get("_internal_voltage", 0.0)
	var n_vt = ideality_factor * THERMAL_VOLTAGE

	# --- Diode Limiting for numerical stability ---
	# To prevent floating point overflow in exp(), we clamp the diode voltage.
	var Vcrit = n_vt * log(1e12) # A large but numerically stable conductance
	var Vd_limited = min(Vd_last_iter, Vcrit)

	# Linearized model from Shockley equation: Geq and Ieq
	var exp_term = exp(Vd_limited / n_vt)
	var Geq = (saturation_current / n_vt) * exp_term
	var Ieq = saturation_current * (exp_term - 1.0) - Geq * Vd_last_iter

	var na = terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var nk = terminal_connections.get(terminal_kathode.get_instance_id(), -1)
	var ia = node_map.get(na, -1)
	var ik = node_map.get(nk, -1)

	# Stamp the equivalent conductance
	CircuitGraph.stamp_conductance(A, Geq, ia, ik)

func get_kcl_contributions(graph: CircuitGraph, _all_node_voltages: Dictionary, F_v: Array, system: Dictionary, _delta_time: float):
	var node_a_id = graph.terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var node_k_id = graph.terminal_connections.get(terminal_kathode.get_instance_id(), -1)
	var Va = graph.electrical_nodes.get(node_a_id, {}).get("voltage", 0.0)
	var Vk = graph.electrical_nodes.get(node_k_id, {}).get("voltage", 0.0)
	var Vd = Va - Vk
	
	var current = saturation_current * (exp(Vd / (ideality_factor * THERMAL_VOLTAGE)) - 1.0)
	assert(!is_nan(current), "Diode current calculation resulted in NaN.")
	
	var ia = system.node_map.get(node_a_id, -1)
	var ik = system.node_map.get(node_k_id, -1)
	
	if ia != -1: F_v[ia] += current
	if ik != -1: F_v[ik] -= current
