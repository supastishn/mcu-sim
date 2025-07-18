extends Node3D

class_name PolarizedCapacitor3D


## Emitted when a key property (like capacitance or max voltage) of the capacitor changes.
signal configuration_changed(component_node: Node3D)


## The capacitance value in Farads.
@export var capacitance: float = 1.0e-6 : set = set_capacitance

## The maximum forward voltage the capacitor can safely handle before exploding.
@export var max_voltage: float = 16.0 : set = set_max_voltage
## The Equivalent Series Resistance (ESR) of the capacitor in Ohms.
@export var equivalent_series_resistance: float = 0.01

## Reference to the positive terminal (anode) Area3D node.
@onready var terminal1: Area3D = $Terminal1
## Reference to the negative terminal (cathode) Area3D node.
@onready var terminal2: Area3D = $Terminal2
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel

## Flag to track the visual "exploded" state.
var is_visually_exploded: bool = false
var _internal_node_id = -1

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal1 or not terminal2:
		printerr("PolarizedCapacitor3D requires child Area3D nodes named 'Terminal1' and 'Terminal2'.")
	if not info_label:
		printerr("PolarizedCapacitor3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	

## Sets the capacitance value, validates it, and emits the configuration_changed signal.
func set_capacitance(value: float):
	var new_cap = max(1e-12, value)
	if is_equal_approx(capacitance, new_cap):
		capacitance = new_cap
		return

	capacitance = new_cap
	print("PolarizedCapacitor {cap_name} capacitance set to: {cap_str} F".format({"cap_name": name, "cap_str": String.num_scientific(capacitance)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the maximum voltage rating, validates it, and emits the configuration_changed signal.
func set_max_voltage(value: float):
	var new_max_v = max(0.1, value)
	if is_equal_approx(max_voltage, new_max_v):
		max_voltage = new_max_v
		return

	max_voltage = new_max_v
	print("PolarizedCapacitor {cap_name} max_voltage set to: {max_v_str} V".format({"cap_name": name, "max_v_str": String.num(max_voltage, 2)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)



## Displays the calculated voltage, current, or exploded state on the component's 3D label.
func show_info(current_value: float, voltage_value: float, p_is_logically_exploded: bool):
	if not info_label: return

	is_visually_exploded = p_is_logically_exploded

	if is_visually_exploded:
		info_label.text = "EXPLODED!"
		info_label.modulate = Color.RED
		info_label.visible = true
		return

	info_label.modulate = Color.WHITE

	var current_str = "I: N/A"
	if not is_nan(current_value): current_str = "I: " + StringUtils.format_current(current_value)
	
	var voltage_str = "V: N/A"
	if not is_nan(voltage_value):
		voltage_str = "V: {val_str} V".format({"val_str": String.num(voltage_value, 2)})
		
	info_label.text = "{v_str}\n{c_str}".format({"v_str": voltage_str, "c_str": current_str})
	info_label.visible = true


## Hides the information label.
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""
	info_label.modulate = Color.WHITE


## Resets the component to its default visual state, hiding any simulation info.
func reset_visual_state():
	is_visually_exploded = false
	hide_info()

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"T1": {"node": terminal1, "pos": terminal1.position},
		"T2": {"node": terminal2, "pos": terminal2.position}
	}

## Returns any internal nodes this component requires.
func get_internal_nodes(graph: CircuitGraph) -> Array:
	# Request one internal node for the ESR connection.
	if _internal_node_id == -1:
		_internal_node_id = graph._get_internal_node_id()
	return [_internal_node_id]

## Stamps the capacitor's equivalent conductance and current source into the MNA matrices for transient analysis.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary, # Unused by PolarizedCapacitor
	_inductor_map: Dictionary, # Unused by PolarizedCapacitor
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for is_exploded, capacitance, voltage_across_cap_prev_dt
	delta_time: float
):
	var esr = equivalent_series_resistance
	var internal_node_idx = node_map.get(_internal_node_id, -1)

	var t1_idx = node_map.get(terminal_connections.get(terminal1.get_instance_id(),-1), -1)
	var t2_idx = node_map.get(terminal_connections.get(terminal2.get_instance_id(),-1), -1)
	
	# Stamp ESR between terminal 1 and the internal node
	if esr > 1e-9:
		var g_esr = 1.0 / esr
		CircuitGraph.stamp_conductance(A, g_esr, t1_idx, internal_node_idx)
	else: # If no ESR, effectively connect terminal 1 directly to the internal node
		CircuitGraph.stamp_conductance(A, 1e9, t1_idx, internal_node_idx)

	var G_eq: float
	var I_eq_source: float = 0.0
	
	if comp_data.get("is_exploded", false):
		G_eq = 1e-9 # Effectively open if exploded
	else:
		var C_val = capacitance
		if C_val <= 1e-12: C_val = 1e-12
		var Vc_prev_dt_val = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)
		
		if delta_time <= 1e-9: # Avoid division by zero or very small dt
			G_eq = 1e9 # Effectively a short for DC analysis if dt is zero
			I_eq_source = 0.0 # Or handle as error
		else:
			G_eq = C_val / delta_time
			I_eq_source = G_eq * Vc_prev_dt_val
			
	# Stamp the ideal capacitor between the internal node and terminal 2
	CircuitGraph.stamp_conductance(A, G_eq, internal_node_idx, t2_idx)
		
	if internal_node_idx != -1: b[internal_node_idx] += I_eq_source
	if t2_idx != -1: b[t2_idx] -= I_eq_source

func get_kcl_contributions(graph: CircuitGraph, all_node_voltages: Dictionary, F_v: Array, system: Dictionary, delta_time: float):
	var comp_data = graph.component_node_map.get(self)
	if comp_data.get("is_exploded", false): return

	var t1_node_id = graph.terminal_connections.get(terminal1.get_instance_id(), -1)
	var t2_node_id = graph.terminal_connections.get(terminal2.get_instance_id(), -1)
	var v1 = all_node_voltages.get(t1_node_id, 0.0)
	var v2 = all_node_voltages.get(t2_node_id, 0.0)
	var v_int = all_node_voltages.get(_internal_node_id, 0.0)

	# Current through ESR
	var esr = equivalent_series_resistance
	if esr > 1e-9:
		var I_esr = (v1 - v_int) / esr
		var idx1 = system.node_map.get(t1_node_id, -1)
		var idx_int = system.node_map.get(_internal_node_id, -1)
		if idx1 != -1: F_v[idx1] += I_esr
		if idx_int != -1: F_v[idx_int] -= I_esr
	
	# Current through ideal capacitor
	var Vc_prev = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)
	if delta_time < 1e-9: delta_time = 1e-9
	var I_cap = capacitance * ( (v_int - v2) - Vc_prev) / delta_time

	var idx_int_cap = system.node_map.get(_internal_node_id, -1)
	var idx2 = system.node_map.get(t2_node_id, -1)
	if idx_int_cap != -1: F_v[idx_int_cap] += I_cap
	if idx2 != -1: F_v[idx2] -= I_cap

## Extracts and stores simulation results, checking for overvoltage or reverse polarity explosion.
func gather_sim_results(
	circuit      : CircuitGraph,
	comp_data    : Dictionary,
	_x            : Array,
	_node_map     : Dictionary,
	_vs_map       : Dictionary,
	_inductor_map : Dictionary,
	delta_time   : float) -> void:
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()

	var C_val = comp_data.properties["capacitance"]
	var max_V_cap = comp_data.properties["max_voltage"]
	var Vc_prev_dt_val = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)

	var term1_cap_node = comp_data.terminals["T1"]
	var term2_cap_node = comp_data.terminals["T2"]
	var node1_id_cap_val = circuit.terminal_connections.get(term1_cap_node.get_instance_id(), -1)
	var node2_id_cap_val = circuit.terminal_connections.get(term2_cap_node.get_instance_id(), -1)

	var V1_cap_t = circuit.electrical_nodes.get(node1_id_cap_val, {}).get("voltage", NAN)
	var V2_cap_t = circuit.electrical_nodes.get(node2_id_cap_val, {}).get("voltage", NAN)
	
	var current_cap = NAN
	var Vc_t = NAN

	if comp_data.get("is_exploded", false):
		current_cap = 0.0
		if not is_nan(V1_cap_t) and not is_nan(V2_cap_t): Vc_t = V1_cap_t - V2_cap_t
	elif not is_nan(V1_cap_t) and not is_nan(V2_cap_t):
		Vc_t = V1_cap_t - V2_cap_t
		
		var reverse_polarity_tolerance = -0.1
		if Vc_t > max_V_cap or Vc_t < reverse_polarity_tolerance:
			comp_data.is_exploded = true
			current_cap = 0.0
		else:
			current_cap = C_val * (Vc_t - Vc_prev_dt_val) / delta_time
			comp_data.properties["voltage_across_cap_prev_dt"] = Vc_t
	else:
		pass
	
	circuit.component_results[comp_id]["current"] = current_cap
	circuit.component_results[comp_id]["voltage_across"] = Vc_t
	circuit.component_results[comp_id]["is_exploded"] = comp_data.get("is_exploded", false)
