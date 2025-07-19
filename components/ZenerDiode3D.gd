extends Node3D

class_name ZenerDiode3D

const LinearSolver = preload("res://LinearSolver.gd")


## Emitted when a key property (like forward or zener voltage) of the diode changes.
signal configuration_changed(component_node: Node3D)


## The saturation current of the diode model.
@export var saturation_current: float = 1e-12
## The ideality factor (emission coefficient) of the diode model.
@export var ideality_factor: float = 1.0
const THERMAL_VOLTAGE: float = 0.02585

## The reverse breakdown (Zener) voltage, in Volts.
@export var zener_voltage: float = 5.1 : set = set_zener_voltage

## Reference to the Anode terminal Area3D node.
@onready var terminal_anode: Area3D = $TerminalAnode 
## Reference to the Kathode terminal Area3D node.
@onready var terminal_kathode: Area3D = $TerminalKathode 
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal_anode or not terminal_kathode:
		printerr("ZenerDiode3D requires child Area3D nodes named 'TerminalAnode' and 'TerminalKathode'.")
	if not info_label:
		printerr("ZenerDiode3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_zener_voltage(zener_voltage)

## Sets the Zener voltage, validates it, and emits the configuration_changed signal.
func set_zener_voltage(value: float):
	var new_vz = max(0.1, value)
	if is_equal_approx(zener_voltage, new_vz):
		zener_voltage = new_vz
		return

	zener_voltage = new_vz
	print("ZenerDiode3D {name} zener_voltage set to: {vz_str} V".format({"name": name, "vz_str": String.num(zener_voltage, 2)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)



## Displays the calculated state, voltage, and current on the component's 3D label.
func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var current_val = results.get("current", NAN) 
	var voltage_ak_val = results.get("voltage_ak", NAN) 
	var state_val = results.get("state", "N/A")

	var current_str = "I: N/A"
	if not is_nan(current_val): current_str = "I: " + StringUtils.format_current(current_val)

	var voltage_str = "Vak: N/A" 
	if not is_nan(voltage_ak_val):
		voltage_str = "Vak: {val_str} V".format({"val_str": String.num(voltage_ak_val, 2)})
		
	info_label.text = "State: {s}\n{v_str}\n{c_str}".format({"s": state_val, "v_str": voltage_str, "c_str": current_str})
	info_label.visible = true

## Hides the information label.
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

## Resets the component to its default visual state.
func reset_visual_state():
	hide_info()

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
	var comp_id = comp_data.component_node.get_instance_id()

	var Va = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["A"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vk = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["K"].get_instance_id(), -1), {}).get("voltage", NAN)
	
	var Is = comp_data.properties["saturation_current"]
	var n = comp_data.properties["ideality_factor"]
	var Vz = comp_data.properties["zener_voltage"]
	var V_thermal = THERMAL_VOLTAGE
	
	var current = NAN
	var state = "OFF"

	if not (!is_nan(Va) and !is_nan(Vk)):
		LinearSolver.print_vector(_x, "x on zener results fail")
		printerr("Zener {z}: Terminal voltage NaN in gather_sim_results. Va={va}, Vk={vk}".format({ "z": name, "va": Va, "vk": Vk }))
		return
	if not is_nan(Va) and not is_nan(Vk):
		var Vd = Va - Vk
		comp_data.properties["_internal_voltage"] = Vd
		
		# Forward bias calculation
		var I_fwd = Is * (exp(Vd / (n * V_thermal)) - 1.0)
		
		# Reverse bias (Zener) calculation - consistent with get_kcl_contributions
		var Vrev = -(Vd + Vz)
		# Note: Reverse breakdown does not typically use ideality factor. Matching kcl function.
		var I_rev = Is * (exp(Vrev / V_thermal) - 1.0)
		
		current = I_fwd - I_rev # Total current

		# Determine state for display
		if Vd > 0.5: state = "FORWARD"
		elif Vd < -Vz: state = "ZENER"
		else: state = "OFF"

	circuit.component_results[comp_id]["current"] = current
	circuit.component_results[comp_id]["voltage_ak"] = comp_data.properties.get("_internal_voltage", NAN)
	circuit.component_results[comp_id]["state"] = state

## Applies the Zener diode's contribution to the MNA matrices based on its current state.
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
	var Vd_last = comp_data.properties.get("_internal_voltage", 0.0)
	var n_vt = ideality_factor * THERMAL_VOLTAGE
	var Vz = zener_voltage
	
	# --- Diode Limiting for numerical stability ---
	var Vcrit_fwd = n_vt * log(1e12)
	var Vd_limited_fwd = min(Vd_last, Vcrit_fwd)
	var Vrev = -(Vd_last + Vz)
	var Vcrit_rev = THERMAL_VOLTAGE * log(1e12)
	var Vrev_limited = min(Vrev, Vcrit_rev)

	# Forward-bias diode model
	var exp_fwd = exp(Vd_limited_fwd / n_vt)
	var G_fwd = (saturation_current / n_vt) * exp_fwd

	# Zener breakdown model (simplified)
	var exp_rev = exp(Vrev_limited / THERMAL_VOLTAGE)
	var G_rev = (saturation_current / THERMAL_VOLTAGE) * exp_rev

	# Total linearized model
	var Geq = G_fwd + G_rev

	var ia = node_map.get(terminal_connections.get(terminal_anode.get_instance_id(), -1), -1)
	var ik = node_map.get(terminal_connections.get(terminal_kathode.get_instance_id(), -1), -1)
	
	CircuitGraph.stamp_conductance(A, Geq, ia, ik)

func get_kcl_contributions(graph: CircuitGraph, _all_node_voltages: Dictionary, F_v: Array, system: Dictionary, _delta_time: float):
	var node_a_id = graph.terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var node_k_id = graph.terminal_connections.get(terminal_kathode.get_instance_id(), -1)
	var Va = graph.electrical_nodes.get(node_a_id, {}).get("voltage", 0.0)
	var Vk = graph.electrical_nodes.get(node_k_id, {}).get("voltage", 0.0)
	var Vd = Va - Vk

	var Is = saturation_current
	var n = ideality_factor
	var Vz = zener_voltage
	var V_thermal = THERMAL_VOLTAGE
	var n_vt = n * V_thermal
	
	# --- Diode Limiting for numerical stability ---
	var Vcrit_fwd = n_vt * log(1e12)
	var Vd_limited_fwd = min(Vd, Vcrit_fwd)
	
	var Vrev = -(Vd + Vz)
	var Vcrit_rev = V_thermal * log(1e12)
	var Vrev_limited = min(Vrev, Vcrit_rev)

	var I_fwd = Is * (exp(Vd_limited_fwd / n_vt) - 1.0)
	var I_rev = Is * (exp(Vrev_limited / V_thermal) - 1.0)
	var current = I_fwd - I_rev
	if not !is_nan(current):
		LinearSolver.print_matrix(system.A, "A on zener kcl fail")
		LinearSolver.print_vector(F_v, "F_v on zener kcl fail")
		printerr("Zener {z}: Current is NaN. I_fwd={ifwd}, I_rev={irev}, Vd_lim={vdlim}, Vrev_lim={vrevlim}".format({ "z": name, "ifwd": I_fwd, "irev": I_rev, "vdlim": Vd_limited_fwd, "vrevlim": Vrev_limited }))
		return

	var ia = system.node_map.get(node_a_id, -1)
	var ik = system.node_map.get(node_k_id, -1)
	
	if ia != -1: F_v[ia] += current
	if ik != -1: F_v[ik] -= current
