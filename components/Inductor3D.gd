extends Node3D

class_name Inductor3D


## Emitted when a key property (like inductance) of the inductor changes.
signal configuration_changed(component_node: Node3D)


## The inductance value in Henrys.
@export var inductance: float = 1.0e-3 : set = set_inductance 
## The DC resistance (DCR) of the inductor's winding in Ohms.
@export var dc_resistance: float = 0.1

## Reference to the first terminal Area3D node.
@onready var terminal1: Area3D = $Terminal1
## Reference to the second terminal Area3D node.
@onready var terminal2: Area3D = $Terminal2
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel 
var _internal_node_id = -1

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal1 or not terminal2:
		printerr("Inductor3D requires child Area3D nodes named 'Terminal1' and 'Terminal2'.")
	if not info_label:
		printerr("Inductor3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_inductance(inductance)

## Sets the inductance value, validates it, and emits the configuration_changed signal.
func set_inductance(value: float):
	var new_L = max(1e-9, value)
	if is_equal_approx(inductance, new_L):
		inductance = new_L
		return

	inductance = new_L
	print("Inductor3D {ind_name} inductance set to: {l_str} H".format({"ind_name": name, "l_str": String.num_scientific(inductance)}))
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
		
	info_label.text = "{v_str}\n{c_str}".format({"v_str": voltage_str, "c_str": current_str})
	info_label.visible = true

## Hides the information label.
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

## Resets the component to its default visual state, hiding any simulation info.
func reset_visual_state():
	hide_info()

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"T1": {"node": terminal1, "pos": terminal1.position},
		"T2": {"node": terminal2, "pos": terminal2.position}
	}

## Returns any internal nodes this component requires.
func get_internal_nodes(graph: CircuitGraph) -> Array:
	if _internal_node_id == -1:
		_internal_node_id = graph._get_internal_node_id()
	return [_internal_node_id]

## Stamps the inductor's contribution to the MNA matrices for transient analysis.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary, # Unused by Inductor
	_opamp_map: Dictionary,
	inductor_map: Dictionary, # This is inductor_id_to_matrix_index
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for inductance, current_through_L_prev_dt
	delta_time: float
):
	# --- Numerical stability: clamp delta_time ---
	delta_time = clamp(delta_time, 1e-12, 0.1)

	var dcr = dc_resistance
	var internal_node_idx = node_map.get(_internal_node_id, -1)

	var t1_idx = node_map.get(terminal_connections.get(terminal1.get_instance_id(), -1), -1)
	var t2_idx = node_map.get(terminal_connections.get(terminal2.get_instance_id(), -1), -1)
	
	# Stamp DCR between terminal 1 and internal node
	if dcr > 1e-9:
		var g_dcr = 1.0 / dcr
		CircuitGraph.stamp_conductance(A, g_dcr, t1_idx, internal_node_idx)
	else:
		CircuitGraph.stamp_conductance(A, 1e9, t1_idx, internal_node_idx)

	var L_val_prop = inductance
	if L_val_prop <= 1e-12: L_val_prop = 1e-12 # Ensure L is not zero
	var I_L_prev_dt_val_prop = comp_data.properties.get("current_through_L_prev_dt", 0.0)

	var t2_instance_id = terminal2.get_instance_id() if is_instance_valid(terminal2) else -1
	
	var self_instance_id = self.get_instance_id()
	if not inductor_map.has(self_instance_id):
		printerr("Critical Error: Inductor {ind_id_str} not found in inductor_map.".format({"ind_id_str": self_instance_id}))
		return
	var idx_I_L_val = inductor_map[self_instance_id]

	# Inductor equation: V1 - V2 - L * d(I_L)/dt = 0
	# Using Backward Euler: V_internal(t) - V2(t) - L * (I_L(t) - I_L(t-dt))/dt = 0
	# Row for I_L: V_internal(t) - V2(t) - (L/dt)*I_L(t) = -(L/dt)*I_L(t-dt)
	
	var L_div_dt: float
	if delta_time <= 1e-9:
		L_div_dt = L_val_prop / 1e-9
	else:
		L_div_dt = L_val_prop / delta_time

	if internal_node_idx != -1: A[idx_I_L_val][internal_node_idx] = 1.0
	if t2_idx != -1: A[idx_I_L_val][t2_idx] = -1.0
	A[idx_I_L_val][idx_I_L_val] = -L_div_dt
	
	b[idx_I_L_val] = -L_div_dt * I_L_prev_dt_val_prop
	
	# KCL equations for ideal inductor
	if internal_node_idx != -1: A[internal_node_idx][idx_I_L_val] = 1.0
	if t2_idx != -1: A[t2_idx][idx_I_L_val] = -1.0

## Extracts and stores simulation results (current, voltage) for this component.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		inductor_map : Dictionary,
		_delta_time   : float) -> void:
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()
	var solved_current_L : float = NAN # holds I_L for later reuse

	if inductor_map.has(comp_id): 
		var matrix_idx_curr_L_final = inductor_map[comp_id]
		if matrix_idx_curr_L_final < x.size():
			solved_current_L = x[matrix_idx_curr_L_final]
			circuit.component_results[comp_id]["current"] = solved_current_L
			
			var term_1_L = comp_data.terminals["T1"]
			var term_2_L = comp_data.terminals["T2"]
			var V1_L = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_1_L.get_instance_id(), -1), {}).get("voltage", NAN)
			var V2_L = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_2_L.get_instance_id(), -1), {}).get("voltage", NAN)
			var actual_V_across_L = NAN
			if not is_nan(V1_L) and not is_nan(V2_L): actual_V_across_L = V1_L - V2_L
			circuit.component_results[comp_id]["voltage_across"] = actual_V_across_L

	# Store current for next time-step (needed by stamp’s Backward-Euler)
	if not is_nan(solved_current_L):
		comp_data.properties["current_through_L_prev_dt"] = solved_current_L
