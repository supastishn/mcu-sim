extends Node3D
class_name OpAmp3D

## Emitted when a key property of the op-amp changes.
signal configuration_changed(component_node: Node3D)

# Properties for the ideal op-amp simulation model
## The open-loop voltage gain of the op-amp.
@export var open_loop_gain: float = 200000.0 : set = set_open_loop_gain
## The voltage drop from the supply rails for output saturation.
@export var rail_saturation_voltage: float = 1.5 : set = set_rail_saturation_voltage # Voltage drop from the supply rails
## The input resistance between the Vp and Vn terminals.
@export var input_resistance: float = 1.0e6
## The output resistance in series with the voltage source model.
@export var output_resistance: float = 50.0

# UI and component node references
## Reference to the non-inverting input terminal (+) Area3D node.
@onready var terminal_vp: Area3D = $TerminalVp
## Reference to the inverting input terminal (-) Area3D node.
@onready var terminal_vn: Area3D = $TerminalVn
## Reference to the output terminal Area3D node.
@onready var terminal_vout: Area3D = $TerminalVout
## Reference to the positive supply voltage terminal (Vcc) Area3D node.
@onready var terminal_vcc: Area3D = $TerminalVcc
## Reference to the negative supply voltage terminal (Vee) Area3D node.
@onready var terminal_vee: Area3D = $TerminalVee
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	hide_info()

## Sets the open-loop gain and emits the configuration_changed signal.
func set_open_loop_gain(value: float):
	if not is_equal_approx(open_loop_gain, value):
		open_loop_gain = value
		if is_inside_tree():
			emit_signal("configuration_changed", self)

## Sets the rail saturation voltage and emits the configuration_changed signal.
func set_rail_saturation_voltage(value: float):
	if not is_equal_approx(rail_saturation_voltage, value):
		rail_saturation_voltage = value
		if is_inside_tree():
			emit_signal("configuration_changed", self)

# --- Visual Feedback ---
## Displays the calculated operating region and voltages on the component's 3D label.
func show_info(results: Dictionary):
	if not is_instance_valid(info_label): return
	
	var region_str = results.get("region", "N/A")
	var vout_val = results.get("Vout", NAN)
	var vdiff_val = results.get("Vp_minus_Vn", NAN)

	var vout_str = "N/A"
	if not is_nan(vout_val):
		vout_str = "{v:.3f} V".format({"v": vout_val})

	var vdiff_str = "N/A"
	if not is_nan(vdiff_val):
		vdiff_str = "{v:.3f} mV".format({"v": vdiff_val * 1000.0})

	info_label.text = "Region: {r}\nVout: {vo}\nVp-Vn: {vd}".format({
		"r": region_str,
		"vo": vout_str,
		"vd": vdiff_str
	})
	info_label.visible = true

## Hides the information label.
func hide_info():
	if is_instance_valid(info_label):
		info_label.visible = false

## Resets the component to its default visual state.
func reset_visual_state():
	hide_info()

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"Vp": {"node": terminal_vp, "pos": terminal_vp.position},
		"Vn": {"node": terminal_vn, "pos": terminal_vn.position},
		"Vout": {"node": terminal_vout, "pos": terminal_vout.position},
		"Vcc": {"node": terminal_vcc, "pos": terminal_vcc.position},
		"Vee": {"node": terminal_vee, "pos": terminal_vee.position}
	}

# --- Simulation Interface ---
## Updates the op-amp's operating region (LINEAR, SAT_HIGH, SAT_LOW) based on an MNA iteration.
func update_nonlinear_state(
		circuit: CircuitGraph,
		comp_data: Dictionary,
		solution_vector: Array,
		node_map: Dictionary,
		_vs_map: Dictionary
	) -> bool:
	if solution_vector.is_empty():
		return false

	var vp_node_id = circuit.terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = circuit.terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vcc_node_id = circuit.terminal_connections.get(terminal_vcc.get_instance_id(), -1)
	var vee_node_id = circuit.terminal_connections.get(terminal_vee.get_instance_id(), -1)

	var vp_idx = node_map.get(vp_node_id, -1)
	var vn_idx = node_map.get(vn_node_id, -1)
	var vcc_idx = node_map.get(vcc_node_id, -1)
	var vee_idx = node_map.get(vee_node_id, -1)

	var Vp = solution_vector[vp_idx] if vp_idx != -1 else (0.0 if vp_node_id == circuit.ground_node_id else NAN)
	var Vn = solution_vector[vn_idx] if vn_idx != -1 else (0.0 if vn_node_id == circuit.ground_node_id else NAN)
	var Vcc = solution_vector[vcc_idx] if vcc_idx != -1 else (0.0 if vcc_node_id == circuit.ground_node_id else NAN)
	var Vee = solution_vector[vee_idx] if vee_idx != -1 else (0.0 if vee_node_id == circuit.ground_node_id else NAN)

	var new_region = ""
	if is_nan(Vp) or is_nan(Vn) or is_nan(Vcc) or is_nan(Vee):
		new_region = "OFF"
	else:
		if Vcc < Vee: # Swap if rails are inverted
			var temp = Vcc
			Vcc = Vee
			Vee = temp

		var gain = comp_data.properties["open_loop_gain"]
		var ideal_vout = gain * (Vp - Vn)

		var rail_drop = comp_data.properties["rail_saturation_voltage"]
		var high_rail = Vcc - rail_drop
		var low_rail  = Vee + rail_drop

		if ideal_vout > high_rail:
			new_region = "SAT_HIGH"
		elif ideal_vout < low_rail:
			new_region = "SAT_LOW"
		else:
			new_region = "LINEAR"

	var previous_region = comp_data.properties["operating_region"]
	if new_region != previous_region:
		comp_data.properties["operating_region"] = new_region
		return true

	return false


## Applies the op-amp's ideal voltage-controlled voltage source model to the MNA matrices.
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
	var region = comp_data.properties["operating_region"]

	var vp_node_id = terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vout_node_id = terminal_connections.get(terminal_vout.get_instance_id(), -1)
	var vcc_node_id = terminal_connections.get(terminal_vcc.get_instance_id(), -1)
	var vee_node_id = terminal_connections.get(terminal_vee.get_instance_id(), -1)

	var vp_idx = node_map.get(vp_node_id, -1)
	var vn_idx = node_map.get(vn_node_id, -1)
	var vout_idx = node_map.get(vout_node_id, -1)
	var vcc_idx = node_map.get(vcc_node_id, -1)
	var vee_idx = node_map.get(vee_node_id, -1)

	# Stamp input resistance between Vp and Vn
	var g_in = 1.0 / input_resistance
	CircuitGraph.stamp_conductance(A, g_in, vp_idx, vn_idx)

	# Model output as a Norton equivalent: I_n in parallel with Ro
	var Gbig = 1e9 # Large conductance for voltage stamping in saturation

	if region == "OFF":
		if vout_idx != -1:
			A[vout_idx][vout_idx] += 1e-9 # High impedance to ground
	elif region == "LINEAR":
		# Model as Norton equivalent: VCCS in parallel with output resistance.
		var g_out = 1.0 / output_resistance if output_resistance > 1e-9 else 1e9
		var transconductance = open_loop_gain * g_out
		
		# Stamp output resistance (to ground)
		if vout_idx != -1:
			A[vout_idx][vout_idx] += g_out
			
		# Stamp VCCS: i = transconductance * (Vp - Vn)
		# KCL at Vout is ... - i = 0. So d/dV terms are for -i.
		if vout_idx != -1:
			if vp_idx != -1:
				A[vout_idx][vp_idx] -= transconductance
			if vn_idx != -1:
				A[vout_idx][vn_idx] += transconductance
	elif region == "SAT_HIGH":
		# Enforce Vout = Vcc - rail_saturation_voltage with a large conductance model
		var sat_drop = comp_data.properties["rail_saturation_voltage"]
		CircuitGraph.stamp_conductance(A, Gbig, vout_idx, vcc_idx)
		if vout_idx != -1: b[vout_idx] -= Gbig * sat_drop
		if vcc_idx != -1: b[vcc_idx] += Gbig * sat_drop

	elif region == "SAT_LOW":
		# Enforce Vout = Vee + rail_saturation_voltage with a large conductance model
		var sat_drop = comp_data.properties["rail_saturation_voltage"]
		CircuitGraph.stamp_conductance(A, Gbig, vout_idx, vee_idx)
		if vout_idx != -1: b[vout_idx] += Gbig * sat_drop
		if vee_idx != -1: b[vee_idx] -= Gbig * sat_drop

func get_kcl_contributions(graph: CircuitGraph, all_node_voltages: Dictionary, F_v: Array, system: Dictionary, _delta_time: float):
	var comp_data = graph.component_node_map.get(self)
	if not comp_data: return
	var region = comp_data.properties["operating_region"]
	
	var vp_node_id = graph.terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = graph.terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vout_node_id = graph.terminal_connections.get(terminal_vout.get_instance_id(), -1)
	
	var Vp = all_node_voltages.get(vp_node_id, 0.0)
	var Vn = all_node_voltages.get(vn_node_id, 0.0)
	var Vout = all_node_voltages.get(vout_node_id, 0.0)
	
	# Input resistance contribution
	var g_in = 1.0 / input_resistance if input_resistance > 1e-9 else 1e9
	var i_in = g_in * (Vp - Vn)
	var vp_idx = system.node_map.get(vp_node_id, -1)
	var vn_idx = system.node_map.get(vn_node_id, -1)
	if vp_idx != -1: F_v[vp_idx] += i_in
	if vn_idx != -1: F_v[vn_idx] -= i_in

	# Output stage contribution
	if region == "LINEAR":
		var g_out = 1.0 / output_resistance if output_resistance > 1e-9 else 1e9
		var transconductance = open_loop_gain * g_out
		
		# VCCS current (flows into vout from ground)
		var i_vccs = transconductance * (Vp - Vn)
		# Resistor current (flows out of vout to ground)
		var i_rout = g_out * Vout
		
		var vout_idx = system.node_map.get(vout_node_id, -1)
		# Total current leaving vout is i_rout - i_vccs
		if vout_idx != -1:
			F_v[vout_idx] += i_rout - i_vccs
	# Note: Saturation modes are handled by large conductances stamped in stamp(),
	# which is simpler than calculating the currents here. The error vector
	# will be handled correctly by the solver from the stamped matrix.


## Extracts and stores simulation results for this component.
func gather_sim_results(
		circuit: CircuitGraph,
		comp_data: Dictionary,
		_x: Array,
		_node_map: Dictionary,
		_vs_map: Dictionary,
		_inductor_map: Dictionary,
		_delta_time: float):
	var comp_id = self.get_instance_id()
	var results = {}
	
	var vp_node_id = circuit.terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = circuit.terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vout_node_id = circuit.terminal_connections.get(terminal_vout.get_instance_id(), -1)
	
	var Vp = circuit.electrical_nodes.get(vp_node_id, {}).get("voltage", NAN)
	var Vn = circuit.electrical_nodes.get(vn_node_id, {}).get("voltage", NAN)
	var Vout = circuit.electrical_nodes.get(vout_node_id, {}).get("voltage", NAN)
	
	results["region"] = comp_data.properties.get("operating_region", "N/A")
	results["Vout"] = Vout
	
	if not is_nan(Vp) and not is_nan(Vn):
		results["Vp_minus_Vn"] = Vp - Vn
	else:
		results["Vp_minus_Vn"] = NAN
		
	circuit.component_results[comp_id] = results
