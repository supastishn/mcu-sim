extends Node3D

class_name Inductor3D


signal configuration_changed(component_node: Node3D)


@export var inductance: float = 1.0e-3 : set = set_inductance 

@onready var terminal1: Area3D = $Terminal1
@onready var terminal2: Area3D = $Terminal2
@onready var info_label: Label3D = $InfoLabel 

func _ready():
	if not terminal1 or not terminal2:
		printerr("Inductor3D requires child Area3D nodes named 'Terminal1' and 'Terminal2'.")
	if not info_label:
		printerr("Inductor3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_inductance(inductance)

func set_inductance(value: float):
	var new_L = max(1e-9, value) 
	if not is_equal_approx(inductance, new_L):
		inductance = new_L
		print("Inductor3D {ind_name} inductance set to: {l_str} H".format({"ind_name": name, "l_str": String.num_scientific(inductance)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif inductance != new_L: 
		inductance = new_L





func show_info(current_value: float, voltage_value: float):
	if not info_label: return
	info_label.modulate = Color.WHITE

	var current_str = "I: N/A"
	if not is_nan(current_value):
		if abs(current_value) < 1e-3 and abs(current_value) > 1e-12: 
			current_str = "I: {val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
		elif abs(current_value) < 1.0: 
			current_str = "I: {val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
		else:
			current_str = "I: {val_str} A".format({"val_str": String.num(current_value, 2)})
	
	var voltage_str = "V: N/A"
	if not is_nan(voltage_value):
		voltage_str = "V: {val_str} V".format({"val_str": String.num(voltage_value, 2)})
		
	info_label.text = "{v_str}\n{c_str}".format({"v_str": voltage_str, "c_str": current_str})
	info_label.visible = true

func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

func reset_visual_state():
	hide_info()

# -------------------------------------------------------------------------
# MNA‐stamping interface
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary, # Unused by Inductor
	inductor_map: Dictionary, # This is inductor_id_to_matrix_index
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for inductance, current_through_L_prev_dt
	delta_time: float
):
	var L_val_prop = inductance # Direct access to exported property
	if L_val_prop <= 1e-12: L_val_prop = 1e-12 # Ensure L is not zero
	var I_L_prev_dt_val_prop = comp_data.properties.get("current_through_L_prev_dt", 0.0) # State from comp_data

	var t1_instance_id = terminal1.get_instance_id() if is_instance_valid(terminal1) else -1
	var t2_instance_id = terminal2.get_instance_id() if is_instance_valid(terminal2) else -1

	var node1_lookup_id = terminal_connections.get(t1_instance_id, -1)
	var node2_lookup_id = terminal_connections.get(t2_instance_id, -1)

	var idx1 = node_map.get(node1_lookup_id, -1)
	var idx2 = node_map.get(node2_lookup_id, -1)
	
	var self_instance_id = self.get_instance_id()
	if not inductor_map.has(self_instance_id):
		printerr("Critical Error: Inductor {ind_id_str} not found in inductor_map.".format({"ind_id_str": self_instance_id}))
		return
	var idx_I_L_val = inductor_map[self_instance_id] # Matrix index for this inductor's current

	# Inductor equation: V1 - V2 - L * d(I_L)/dt = 0
	# Using Backward Euler: V1(t) - V2(t) - L * (I_L(t) - I_L(t-dt))/dt = 0
	# Row for I_L: V1(t) - V2(t) - (L/dt)*I_L(t) = -(L/dt)*I_L(t-dt)
	
	var L_div_dt: float
	if delta_time <= 1e-9: # Avoid division by zero or very small dt
		# For DC or very small dt, inductor behaves like a short (or very small resistance)
		# This model becomes problematic. A common approach is to use a small series resistance.
		# For now, let's make L/dt very large, making I_L(t) try to match I_L(t-dt) if V1=V2.
		# Or, if we consider it a voltage source of 0V, its current is idx_I_L_val.
		# The MNA formulation for an inductor adds a current variable.
		# The equation is V1 - V2 = L * dI/dt.
		# V_L = L * (I_L - I_L_prev) / dt
		# V1 - V2 - (L/dt) * I_L = - (L/dt) * I_L_prev
		L_div_dt = L_val_prop / 1e-9 # Effectively a large number
		# This case should ideally be handled by how the solver treats dt=0 (e.g. DC analysis)
		# For transient, dt should not be zero.
	else:
		L_div_dt = L_val_prop / delta_time

	if idx1 != -1: A[idx_I_L_val][idx1] = 1.0
	if idx2 != -1: A[idx_I_L_val][idx2] = -1.0
	A[idx_I_L_val][idx_I_L_val] = -L_div_dt
	
	b[idx_I_L_val] = -L_div_dt * I_L_prev_dt_val_prop
	
	# KCL equations:
	# Node 1: ... + I_L = ...
	# Node 2: ... - I_L = ...
	if idx1 != -1: A[idx1][idx_I_L_val] = 1.0  # Current I_L flows from node 1
	if idx2 != -1: A[idx2][idx_I_L_val] = -1.0 # Current I_L flows to node 2

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

	if inductor_map.has(comp_id): 
		var matrix_idx_curr_L_final = inductor_map[comp_id]
		if matrix_idx_curr_L_final < x.size():
			var solved_current_L = x[matrix_idx_curr_L_final] 
			circuit.component_results[comp_id]["current"] = solved_current_L
			
			var term_1_L = comp_data.terminals["T1"]
			var term_2_L = comp_data.terminals["T2"]
			var V1_L = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_1_L.get_instance_id(), -1), {}).get("voltage", NAN)
			var V2_L = circuit.electrical_nodes.get(circuit.terminal_connections.get(term_2_L.get_instance_id(), -1), {}).get("voltage", NAN)
			var actual_V_across_L = NAN
			if not is_nan(V1_L) and not is_nan(V2_L): actual_V_across_L = V1_L - V2_L
			circuit.component_results[comp_id]["voltage_across"] = actual_V_across_L
	#endregion
