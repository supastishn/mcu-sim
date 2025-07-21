extends Node3D

class_name ZenerDiode3D




## Emitted when a key property (like forward or zener voltage) of the diode changes.
signal configuration_changed(component_node: Node3D)


## The saturation current of the diode model.
@export var saturation_current: float = 1e-12 : set = set_saturation_current
## The ideality factor (emission coefficient) of the diode model.
@export var ideality_factor: float = 1.0 : set = set_ideality_factor
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


## Sets the saturation current and emits a signal.
func set_saturation_current(value: float):
	if is_equal_approx(saturation_current, value):
		saturation_current = value
		return
	saturation_current = value
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the ideality factor and emits a signal.
func set_ideality_factor(value: float):
	if is_equal_approx(ideality_factor, value):
		ideality_factor = value
		return
	ideality_factor = value
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
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty(): return false

	var node_a_id = circuit.terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(terminal_kathode.get_instance_id(), -1)

	var idx_a = node_map_iter.get(node_a_id, -1)
	var idx_k = node_map_iter.get(node_k_id, -1)

	var Va = x_iter[idx_a] if idx_a != -1 else (0.0 if node_a_id == circuit.ground_node_id else 0.0)
	var Vk = x_iter[idx_k] if idx_k != -1 else (0.0 if node_k_id == circuit.ground_node_id else 0.0)
	
	var Vd = Va - Vk
	comp_data.properties["_internal_voltage"] = Vd
	
	return false

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
		var err_msg = "Zener {z}: Terminal voltage NaN in gather_sim_results. Va={va}, Vk={vk}".format({ "z": name, "va": Va, "vk": Vk })
		err_msg += "\nSolution vector x: " + LinearSolver.vector_to_string(_x)
		assert(false, err_msg)
		return
	if not is_nan(Va) and not is_nan(Vk):
		var Vd = Va - Vk
		
		# Forward bias calculation (with clamping for safety)
		var n_vt = n * V_thermal
		var Vcrit_fwd = n_vt * log(1e12)
		var Vd_limited_fwd = min(Vd, Vcrit_fwd)
		var I_fwd = Is * (exp(Vd_limited_fwd / n_vt) - 1.0)
		
		# Reverse bias (Zener) calculation (with clamping for safety)
		var Vrev = -(Vd + Vz)
		var Vcrit_rev = V_thermal * log(1e12)
		var Vrev_limited = min(Vrev, Vcrit_rev)
		var I_rev = Is * (exp(Vrev_limited / V_thermal) - 1.0)
		
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
	
	print_debug("Zener '{n}' stamp: Vd_last={vd:.3f}".format({"n":name, "vd":Vd_last}))
	
	# --- Diode Limiting for numerical stability ---
	var Vcrit_fwd = n_vt * log(1e12)
	var Vd_limited_fwd = min(Vd_last, Vcrit_fwd)
	var Vrev = -(Vd_last + Vz)
	var Vcrit_rev = THERMAL_VOLTAGE * log(1e12)
	var Vrev_limited = min(Vrev, Vcrit_rev)

	print_debug("  Zener '{n}' stamp: Vd_lim_fwd={vdf:.3f}, Vrev_lim={vr:.3f}".format({"n":name, "vdf":Vd_limited_fwd, "vr":Vrev_limited}))

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
	
	var I_fwd_last = saturation_current * (exp_fwd - 1.0)
	var I_rev_last = saturation_current * (exp_rev - 1.0)
	var I_total_last = I_fwd_last - I_rev_last
	var Ieq = I_total_last - Geq * Vd_last
	
	print_debug("  Zener '{n}' stamp: G_fwd={gf:.3g}, G_rev={gr:.3g}, Geq={geq:.3g}, Ieq={ieq:.3g}".format({"n":name, "gf":G_fwd, "gr":G_rev, "geq":Geq, "ieq":Ieq}))
	
	CircuitGraph.stamp_conductance(A, Geq, ia, ik)

	if ia != -1: b[ia] -= Ieq
	if ik != -1: b[ik] += Ieq
