extends Node3D
class_name OpAmp3D

signal configuration_changed(component_node: Node3D)

# The amplification factor of the op-amp in its linear region.
@export var open_loop_gain: float = 100000.0 : set = set_open_loop_gain
# The voltage difference from the supply rails where the output clips.
@export var rail_saturation_voltage: float = 0.5 : set = set_rail_saturation_voltage

@onready var terminal_vp: Area3D = $TerminalVp
@onready var terminal_vn: Area3D = $TerminalVn
@onready var terminal_vout: Area3D = $TerminalVout
@onready var terminal_vcc: Area3D = $TerminalVcc
@onready var terminal_vee: Area3D = $TerminalVee
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal_vp or not terminal_vn or not terminal_vout or not terminal_vcc or not terminal_vee:
		printerr("OpAmp3D requires child Area3D nodes for all terminals (Vp, Vn, Vout, Vcc, Vee).")
	if not info_label:
		printerr("OpAmp3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	# Call setters to validate initial values and enforce constraints
	set_open_loop_gain(open_loop_gain)
	set_rail_saturation_voltage(rail_saturation_voltage)

func set_open_loop_gain(value: float):
	var new_gain = max(1000.0, value)
	if not is_equal_approx(open_loop_gain, new_gain):
		open_loop_gain = new_gain
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif open_loop_gain != new_gain:
		open_loop_gain = new_gain

func set_rail_saturation_voltage(value: float):
	var new_sat_v = max(0.0, value)
	if not is_equal_approx(rail_saturation_voltage, new_sat_v):
		rail_saturation_voltage = new_sat_v
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif rail_saturation_voltage != new_sat_v:
		rail_saturation_voltage = new_sat_v

func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE

	var region_str = "Region: {reg}".format({"reg": results.get("region", "N/A")})
	
	var vout_str = "Vout: N/A"
	if results.has("Vout") and not is_nan(results.Vout):
		vout_str = "Vout: {v} V".format({"v": String.num(results.Vout, 2)})

	var vdiff_str = "Vp-Vn: N/A"
	if results.has("Vp_minus_Vn") and not is_nan(results.Vp_minus_Vn):
		vdiff_str = "Vp-Vn: {v} mV".format({"v": String.num(results.Vp_minus_Vn * 1000.0, 3)})

	info_label.text = "{r}\n{vo}\n{vd}".format({"r": region_str, "vo": vout_str, "vd": vdiff_str})
	info_label.visible = true

func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

func reset_visual_state():
	hide_info()

func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty():
		return false

	var term_vp = comp_data.terminals["Vp"]
	var term_vn = comp_data.terminals["Vn"]
	var term_vout = comp_data.terminals["Vout"]
	var term_vcc = comp_data.terminals["Vcc"]
	var term_vee = comp_data.terminals["Vee"]

	var node_vp_id = circuit.terminal_connections.get(term_vp.get_instance_id(), -1)
	var node_vn_id = circuit.terminal_connections.get(term_vn.get_instance_id(), -1)
	var node_vout_id = circuit.terminal_connections.get(term_vout.get_instance_id(), -1)
	var node_vcc_id = circuit.terminal_connections.get(term_vcc.get_instance_id(), -1)
	var node_vee_id = circuit.terminal_connections.get(term_vee.get_instance_id(), -1)

	var idx_vp = node_map_iter.get(node_vp_id, -1)
	var idx_vn = node_map_iter.get(node_vn_id, -1)
	var idx_vout = node_map_iter.get(node_vout_id, -1)
	var idx_vcc = node_map_iter.get(node_vcc_id, -1)
	var idx_vee = node_map_iter.get(node_vee_id, -1)

	var Vp = x_iter[idx_vp] if idx_vp != -1 else (0.0 if node_vp_id == circuit.ground_node_id else NAN)
	var Vn = x_iter[idx_vn] if idx_vn != -1 else (0.0 if node_vn_id == circuit.ground_node_id else NAN)
	var Vout = x_iter[idx_vout] if idx_vout != -1 else (0.0 if node_vout_id == circuit.ground_node_id else NAN)
	var Vcc = x_iter[idx_vcc] if idx_vcc != -1 else (0.0 if node_vcc_id == circuit.ground_node_id else NAN)
	var Vee = x_iter[idx_vee] if idx_vee != -1 else (0.0 if node_vee_id == circuit.ground_node_id else NAN)

	var previous_region = comp_data.properties["operating_region"]
	var new_region = previous_region

	if is_nan(Vp) or is_nan(Vn) or is_nan(Vout) or is_nan(Vcc) or is_nan(Vee):
		new_region = "OFF"
	else:
		var rail_sat_v = comp_data.properties["rail_saturation_voltage"]
		var sat_high_threshold = Vcc - rail_sat_v
		var sat_low_threshold = Vee + rail_sat_v

		if previous_region == "LINEAR":
			if Vout >= sat_high_threshold - 1e-6:
				new_region = "SAT_HIGH"
			elif Vout <= sat_low_threshold + 1e-6:
				new_region = "SAT_LOW"
		elif previous_region == "SAT_HIGH":
			if Vp <= Vn: # Condition to leave high saturation
				new_region = "LINEAR"
		elif previous_region == "SAT_LOW":
			if Vp >= Vn: # Condition to leave low saturation
				new_region = "LINEAR"
		else: # Was OFF, initial check
			var v_diff_for_check = Vp - Vn
			var gain_for_check = open_loop_gain
			if gain_for_check > 1e-9:
				if v_diff_for_check > (sat_high_threshold / gain_for_check):
					new_region = "SAT_HIGH"
				elif v_diff_for_check < (sat_low_threshold / gain_for_check):
					new_region = "SAT_LOW"
				else:
					new_region = "LINEAR"
			else:
				new_region = "LINEAR"

	if new_region != previous_region:
		comp_data.properties["operating_region"] = new_region
		return true
	return false

func stamp(A: Array, b: Array, node_map: Dictionary, vs_map: Dictionary, _inductor_map: Dictionary, terminal_connections: Dictionary, comp_data: Dictionary, _delta_time: float):
	var opamp_id = self.get_instance_id()
	if not vs_map.has(opamp_id):
		printerr("OpAmp {id} not found in vs_map.".format({"id": opamp_id}))
		return

	var idx_i_out = vs_map[opamp_id]

	var idx_vp = node_map.get(terminal_connections.get(terminal_vp.get_instance_id(), -1), -1)
	var idx_vn = node_map.get(terminal_connections.get(terminal_vn.get_instance_id(), -1), -1)
	var idx_vout = node_map.get(terminal_connections.get(terminal_vout.get_instance_id(), -1), -1)

	# Input terminals have very high impedance (ideal op-amp)
	# Add a very small conductance to ground to prevent floating nodes if inputs are unconnected.
	var G_in = 1.0e-12
	if idx_vp != -1: A[idx_vp][idx_vp] += G_in
	if idx_vn != -1: A[idx_vn][idx_vn] += G_in

	# Handle KCL at output and define KVL for the opamp's behavior
	if idx_vout != -1:
		A[idx_vout][idx_i_out] = 1.0 # Current leaving Vout node

	var region = comp_data.properties["operating_region"]
	var circuit = comp_data.get("circuit_ref")

	if not is_instance_valid(circuit):
		# Fallback for OFF if circuit ref not available
		A[idx_i_out][idx_i_out] = 1.0
		b[idx_i_out] = 0.0
		return

	if region == "LINEAR":
		var gain = comp_data.properties["open_loop_gain"]
		# KVL: Vout - gain * (Vp - Vn) = 0
		A[idx_i_out][idx_vout] = 1.0
		if idx_vp != -1:   A[idx_i_out][idx_vp] = -gain
		if idx_vn != -1:   A[idx_i_out][idx_vn] = gain
		b[idx_i_out] = 0.0
	elif region == "SAT_HIGH":
		var rail_sat_v = comp_data.properties["rail_saturation_voltage"]
		var node_vcc_lookup = terminal_connections.get(terminal_vcc.get_instance_id(), -1)
		var Vcc_prev = circuit.electrical_nodes.get(node_vcc_lookup, {}).get("voltage", 15.0)
		if is_nan(Vcc_prev): Vcc_prev = 15.0
		# KVL: Vout = Vcc_prev - rail_sat_v
		A[idx_i_out][idx_vout] = 1.0
		b[idx_i_out] = Vcc_prev - rail_sat_v
	elif region == "SAT_LOW":
		var rail_sat_v = comp_data.properties["rail_saturation_voltage"]
		var node_vee_lookup = terminal_connections.get(terminal_vee.get_instance_id(), -1)
		var Vee_prev = circuit.electrical_nodes.get(node_vee_lookup, {}).get("voltage", -15.0)
		if is_nan(Vee_prev): Vee_prev = -15.0
		# KVL: Vout = Vee_prev + rail_sat_v
		A[idx_i_out][idx_vout] = 1.0
		b[idx_i_out] = Vee_prev + rail_sat_v
	else: # OFF or if Vout is not connected
		# KVL: i_out = 0 (high impedance output)
		A[idx_i_out][idx_i_out] = 1.0
		b[idx_i_out] = 0.0

func gather_sim_results(circuit: CircuitGraph, comp_data: Dictionary, x: Array, node_map: Dictionary, vs_map: Dictionary, _inductor_map: Dictionary, _delta_time: float):
	var comp_id = self.get_instance_id()
	if not comp_id in circuit.component_results:
		circuit.component_results[comp_id] = {}

	var Vp = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_vp.get_instance_id(), -1), {}).get("voltage", NAN)
	var Vn = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_vn.get_instance_id(), -1), {}).get("voltage", NAN)
	var Vout = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_vout.get_instance_id(), -1), {}).get("voltage", NAN)
	
	var Vp_minus_Vn = NAN
	if not is_nan(Vp) and not is_nan(Vn):
		Vp_minus_Vn = Vp - Vn
	
	var Iout = NAN
	if vs_map.has(comp_id):
		var idx_i_out = vs_map[comp_id]
		if idx_i_out < x.size():
			Iout = x[idx_i_out]

	circuit.component_results[comp_id]["region"] = comp_data.properties.get("operating_region", "N/A")
	circuit.component_results[comp_id]["Vout"] = Vout
	circuit.component_results[comp_id]["Vp_minus_Vn"] = Vp_minus_Vn
	circuit.component_results[comp_id]["Iout"] = Iout
