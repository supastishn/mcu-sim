extends Node3D

class_name Diode3D

const LinearSolver = preload("res://solvers/LinearSolver.gd")


## The saturation current of the diode.
@export var saturation_current: float = 1.0e-12
## The ideality factor (emission coefficient) of the diode.
@export var ideality_factor: float = 1.0
const THERMAL_VOLTAGE: float = 0.02585 # At room temperature (300K)

@onready var terminal_anode: Area3D = $TerminalAnode 
@onready var terminal_kathode: Area3D = $TerminalKathode 
@onready var diode_mesh_instance: MeshInstance3D = $MeshInstance3D 
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
	if not (!is_nan(Va) and !is_nan(Vk)):
		LinearSolver.print_vector(_x, "x on diode results fail")
		printerr("Diode {d}: Terminal voltage is NaN. Va={va}, Vk={vk}".format({ "d": name, "va": Va, "vk": Vk }))
		return
	var Vd = Va - Vk
	current = saturation_current * (exp(Vd / (ideality_factor * THERMAL_VOLTAGE)) - 1.0)
	if not !is_nan(current):
		LinearSolver.print_vector(_x, "x on diode results fail")
		printerr("Diode {d}: Current is NaN. Vd={vd}".format({"d": name, "vd": Vd}))
	comp_data.properties["_internal_voltage"] = Vd

	circuit.component_results[comp_id]["current"] = current

## Updates the diode's internal voltage state for the next linearization step.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	var node_a_id = circuit.terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(terminal_kathode.get_instance_id(), -1)

	var idx_a = node_map_iter.get(node_a_id, -1)
	var idx_k = node_map_iter.get(node_k_id, -1)

	var Va = x_iter[idx_a] if idx_a != -1 else (0.0 if node_a_id == circuit.ground_node_id else 0.0)
	var Vk = x_iter[idx_k] if idx_k != -1 else (0.0 if node_k_id == circuit.ground_node_id else 0.0)

	comp_data.properties["_internal_voltage"] = Va - Vk
	return false # Diode state doesn't "change" in a way that requires re-iteration, it's continuous.

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
	# This function now stamps a linearized model for the Newton-Raphson solver.
	var Vd_last_iter = comp_data.properties.get("_internal_voltage", 0.0)
	var n_vt = ideality_factor * THERMAL_VOLTAGE

	# --- Diode Limiting for numerical stability ---
	# To prevent floating point overflow in exp(), we clamp the diode voltage.
	var Vcrit = n_vt * log(1e12) # A large but numerically stable conductance
	var Vd_limited = min(Vd_last_iter, Vcrit)

	# Linearized model from Shockley equation: Geq
	var exp_term = exp(Vd_limited / n_vt)
	var Geq = (saturation_current / n_vt) * exp_term

	var na = terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var nk = terminal_connections.get(terminal_kathode.get_instance_id(), -1)
	var ia = node_map.get(na, -1)
	var ik = node_map.get(nk, -1)

	# Companion model current source: I(V0) - G*V0
	var I_last = saturation_current * (exp_term - 1.0)
	var Ieq = I_last - Geq * Vd_limited

	# Stamp the equivalent conductance
	CircuitGraph.stamp_conductance(A, Geq, ia, ik)

	# Stamp the equivalent current source. Ieq flows anode to cathode.
	if ia != -1: b[ia] -= Ieq
	if ik != -1: b[ik] += Ieq
