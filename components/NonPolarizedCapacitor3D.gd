extends Node3D

class_name NonPolarizedCapacitor3D


## Emitted when a key property (like capacitance or max voltage) of the capacitor changes.
signal configuration_changed(component_node: Node3D)


## The capacitance value in Farads.
@export var capacitance: float = 1.0e-6 : set = set_capacitance 

## The maximum voltage the capacitor can safely handle, in Volts.
@export var max_voltage: float = 400.0 : set = set_max_voltage 

## Reference to the first terminal Area3D node.
@onready var terminal1: Area3D = $Terminal1
## Reference to the second terminal Area3D node.
@onready var terminal2: Area3D = $Terminal2
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal1 or not terminal2:
		printerr("NonPolarizedCapacitor3D requires child Area3D nodes named 'Terminal1' and 'Terminal2'.")
	if not info_label:
		printerr("NonPolarizedCapacitor3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_capacitance(capacitance)
	set_max_voltage(max_voltage)

## Sets the capacitance value, validates it, and emits the configuration_changed signal.
func set_capacitance(value: float):
	var new_cap = max(1e-12, value)
	if is_equal_approx(capacitance, new_cap):
		capacitance = new_cap
		return

	capacitance = new_cap
	print("NonPolarizedCapacitor {cap_name} capacitance set to: {cap_str} F".format({"cap_name": name, "cap_str": String.num_scientific(capacitance)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)


## Sets the maximum voltage rating, validates it, and emits the configuration_changed signal.
func set_max_voltage(value: float):
	var new_max_v = max(0.1, value)
	if is_equal_approx(max_voltage, new_max_v):
		max_voltage = new_max_v
		return

	max_voltage = new_max_v
	print("NonPolarizedCapacitor {cap_name} max_voltage set to: {max_v_str} V".format({"cap_name": name, "max_v_str": String.num(max_voltage, 2)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)




## Displays the calculated voltage and current on the component's 3D label.
func show_info(current_value: float, voltage_value: float):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var current_str = "I: N/A"
	if not is_nan(current_value): current_str = "I: " + StringUtils.format_current(current_value)
	
	var voltage_str = "V: N/A"
	if not is_nan(voltage_value):
		voltage_str = "V: {val_str} V".format({"val_str": String.num(voltage_value, 2)})
		if abs(voltage_value) > max_voltage:
			voltage_str += " (OVER!)"
			info_label.modulate = Color.ORANGE 
		
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
	hide_info()

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"T1": {"node": terminal1, "pos": terminal1.position},
		"T2": {"node": terminal2, "pos": terminal2.position}
	}

# -------------------------------------------------------------------------
# MNA‐stamping interface
## Stamps the capacitor's equivalent conductance and current source into the MNA matrices for transient analysis.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary, # Unused by NonPolarizedCapacitor
	_inductor_map: Dictionary, # Unused by NonPolarizedCapacitor
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for capacitance, voltage_across_cap_prev_dt
	delta_time: float
):
	var C_val = capacitance # Direct access to exported property
	if C_val <= 1e-12: C_val = 1e-12
	var Vc_prev_dt_val = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0) # State from comp_data

	var G_eq: float
	var I_eq_source: float
	
	if delta_time <= 1e-9: # Avoid division by zero or very small dt
		G_eq = 1e9 # Effectively a short for DC analysis if dt is zero
		I_eq_source = 0.0
	else:
		G_eq = C_val / delta_time
		I_eq_source = G_eq * Vc_prev_dt_val

	var t1_instance_id = terminal1.get_instance_id() if is_instance_valid(terminal1) else -1
	var t2_instance_id = terminal2.get_instance_id() if is_instance_valid(terminal2) else -1

	var node1_lookup_id = terminal_connections.get(t1_instance_id, -1)
	var node2_lookup_id = terminal_connections.get(t2_instance_id, -1)

	var idx1 = node_map.get(node1_lookup_id, -1)
	var idx2 = node_map.get(node2_lookup_id, -1)

	# Stamp conductance part (G_eq)
	if idx1 != -1: A[idx1][idx1] += G_eq
	if idx2 != -1: A[idx2][idx2] += G_eq
	if idx1 != -1 and idx2 != -1:
		A[idx1][idx2] -= G_eq
		A[idx2][idx1] -= G_eq
		
	# Stamp current source part (I_eq_source)
	if idx1 != -1: b[idx1] += I_eq_source
	if idx2 != -1: b[idx2] -= I_eq_source

# -----------------------------------------------------------------
# Simulation-results extraction
## Extracts and stores simulation results (current, voltage) for this component.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		_x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		_inductor_map : Dictionary,
		delta_time   : float) -> void:
	#region LEGACY_RESULT_CODE
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()

	var C_np_val = comp_data.properties["capacitance"]
	var max_V_np_cap = comp_data.properties["max_voltage"]
	var Vc_prev_dt_np_val = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)

	var term1_np_cap_node = comp_data.terminals["T1"]
	var term2_np_cap_node = comp_data.terminals["T2"]
	var node1_id_np_cap_val = circuit.terminal_connections.get(term1_np_cap_node.get_instance_id(), -1)
	var node2_id_np_cap_val = circuit.terminal_connections.get(term2_np_cap_node.get_instance_id(), -1)

	var V1_np_cap_t = circuit.electrical_nodes.get(node1_id_np_cap_val, {}).get("voltage", NAN)
	var V2_np_cap_t = circuit.electrical_nodes.get(node2_id_np_cap_val, {}).get("voltage", NAN)
	
	var current_np_cap = NAN
	var Vc_np_t = NAN

	if not is_nan(V1_np_cap_t) and not is_nan(V2_np_cap_t):
		Vc_np_t = V1_np_cap_t - V2_np_cap_t
		current_np_cap = C_np_val * (Vc_np_t - Vc_prev_dt_np_val) / delta_time
		comp_data.properties["voltage_across_cap_prev_dt"] = Vc_np_t
		
		if abs(Vc_np_t) > max_V_np_cap:
			# Overvoltage condition is handled in show_info
			pass

	else:
		pass

	circuit.component_results[comp_id]["current"] = current_np_cap
	circuit.component_results[comp_id]["voltage_across"] = Vc_np_t
	#endregion
