extends Node3D
class_name OpAmp3D

signal configuration_changed(component_node: Node3D)

@export var open_loop_gain: float = 100000.0 : set = set_open_loop_gain
@export var rail_saturation_voltage: float = 1.0 : set = set_rail_saturation_voltage

@onready var terminal_vp: Area3D = $TerminalVp
@onready var terminal_vn: Area3D = $TerminalVn
@onready var terminal_vout: Area3D = $TerminalVout
@onready var terminal_vcc: Area3D = $TerminalVcc
@onready var terminal_vee: Area3D = $TerminalVee
@onready var info_label: Label3D = $InfoLabel

func _ready():
	reset_visual_state()
	set_open_loop_gain(open_loop_gain)
	set_rail_saturation_voltage(rail_saturation_voltage)

func set_open_loop_gain(value: float):
	var new_val = max(1000.0, value)
	if not is_equal_approx(open_loop_gain, new_val):
		open_loop_gain = new_val
		if is_inside_tree(): emit_signal("configuration_changed", self)
	elif open_loop_gain != new_val:
		open_loop_gain = new_val

func set_rail_saturation_voltage(value: float):
	var new_val = max(0.0, value)
	if not is_equal_approx(rail_saturation_voltage, new_val):
		rail_saturation_voltage = new_val
		if is_inside_tree(): emit_signal("configuration_changed", self)
	elif rail_saturation_voltage != new_val:
		rail_saturation_voltage = new_val

func show_info(results: Dictionary):
	if not info_label: return
	var region = results.get("region", "N/A")
	var vout = results.get("Vout", NAN)
	var v_p = results.get("Vp", NAN)
	var v_n = results.get("Vn", NAN)
	var vcc = results.get("Vcc", NAN)
	var vee = results.get("Vee", NAN)

	var vout_str = "Vout: --- V"
	if not is_nan(vout): vout_str = "Vout: %+.2f V" % vout

	var vin_diff_str = "Vp-Vn: --- V"
	if not is_nan(v_p) and not is_nan(v_n): vin_diff_str = "Vp-Vn: %.3f V" % (v_p - v_n)
	
	info_label.text = "Region: %s\n%s\n%s" % [region, vout_str, vin_diff_str]
	info_label.visible = true

func hide_info():
	if not info_label: return
	info_label.visible = false

func reset_visual_state():
	hide_info()

func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty(): # Cannot determine state if previous solve failed
		return false

	var vcc_node_id = circuit.terminal_connections.get(terminal_vcc.get_instance_id(), -1)
	var vee_node_id = circuit.terminal_connections.get(terminal_vee.get_instance_id(), -1)
	var vp_node_id = circuit.terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = circuit.terminal_connections.get(terminal_vn.get_instance_id(), -1)

	var idx_vcc = node_map_iter.get(vcc_node_id, -1)
	var idx_vee = node_map_iter.get(vee_node_id, -1)
	var idx_vp = node_map_iter.get(vp_node_id, -1)
	var idx_vn = node_map_iter.get(vn_node_id, -1)

	var vcc = x_iter[idx_vcc] if idx_vcc != -1 else (0.0 if vcc_node_id == circuit.ground_node_id else NAN)
	var vee = x_iter[idx_vee] if idx_vee != -1 else (0.0 if vee_node_id == circuit.ground_node_id else NAN)
	var vp = x_iter[idx_vp] if idx_vp != -1 else (0.0 if vp_node_id == circuit.ground_node_id else NAN)
	var vn = x_iter[idx_vn] if idx_vn != -1 else (0.0 if vn_node_id == circuit.ground_node_id else NAN)

	var gain = comp_data.properties.open_loop_gain
	var sat_drop = comp_data.properties.rail_saturation_voltage

	var previous_region = comp_data.properties.operating_region
	var new_region = previous_region

	if is_nan(vcc) or is_nan(vee) or is_nan(vp) or is_nan(vn):
		new_region = "OFF"
	else:
		var v_diff = vp - vn
		var ideal_out = v_diff * gain

		if ideal_out > vcc - sat_drop:
			new_region = "SAT_HIGH"
		elif ideal_out < vee + sat_drop:
			new_region = "SAT_LOW"
		else:
			new_region = "LINEAR"

	if new_region != previous_region:
		comp_data.properties.operating_region = new_region
		return true
	return false

func stamp(A, b, node_map, vs_map, inductor_map, terminal_connections, comp_data, delta_time):
	var gain = open_loop_gain
	var sat_drop = rail_saturation_voltage
	var region = comp_data.properties.operating_region

	var idx_opamp = vs_map.get(self.get_instance_id(), -1)
	if idx_opamp == -1: return

	var vp_node_id = terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vout_node_id = terminal_connections.get(terminal_vout.get_instance_id(), -1)
	var vcc_node_id = terminal_connections.get(terminal_vcc.get_instance_id(), -1)
	var vee_node_id = terminal_connections.get(terminal_vee.get_instance_id(), -1)

	var idx_vp = node_map.get(vp_node_id, -1)
	var idx_vn = node_map.get(vn_node_id, -1)
	var idx_vout = node_map.get(vout_node_id, -1)
	var idx_vcc = node_map.get(vcc_node_id, -1)
	var idx_vee = node_map.get(vee_node_id, -1)
	
	# High input impedance (tiny conductance between inputs)
	var G_in = 1e-12
	if idx_vp != -1 and idx_vn != -1:
		A[idx_vp][idx_vp] += G_in
		A[idx_vn][idx_vn] += G_in
		A[idx_vp][idx_vn] -= G_in
		A[idx_vn][idx_vp] -= G_in

	# Output stamping
	if idx_vout != -1:
		A[idx_vout][idx_opamp] = 1.0
		A[idx_opamp][idx_vout] = 1.0
	
	if region == "LINEAR":
		# Vout = gain * (Vp - Vn)  => Vout - gain*Vp + gain*Vn = 0
		if idx_vp != -1: A[idx_opamp][idx_vp] = -gain
		if idx_vn != -1: A[idx_opamp][idx_vn] = gain
		b[idx_opamp] = 0.0
	elif region == "SAT_HIGH":
		# Vout = Vcc - sat_drop. Model with a very small series resistance for numerical stability.
		# Vout - Vcc + R_sat * I_out = -sat_drop
		var R_sat = 1e-6
		A[idx_opamp][idx_opamp] += R_sat
		if idx_vcc != -1: A[idx_opamp][idx_vcc] = -1.0
		b[idx_opamp] = -sat_drop
	elif region == "SAT_LOW":
		# Vout = Vee + sat_drop. Model with a very small series resistance for numerical stability.
		# Vout - Vee + R_sat * I_out = sat_drop
		var R_sat = 1e-6
		A[idx_opamp][idx_opamp] += R_sat
		if idx_vee != -1: A[idx_opamp][idx_vee] = -1.0
		b[idx_opamp] = sat_drop
	else: # OFF
		b[idx_opamp] = 0.0

func gather_sim_results(circuit, comp_data, x, node_map, vs_map, inductor_map, delta_time):
	var comp_id = self.get_instance_id()
	if not comp_id in circuit.component_results: circuit.component_results[comp_id] = {}

	var vp_node_id = circuit.terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = circuit.terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vout_node_id = circuit.terminal_connections.get(terminal_vout.get_instance_id(), -1)
	var vcc_node_id = circuit.terminal_connections.get(terminal_vcc.get_instance_id(), -1)
	var vee_node_id = circuit.terminal_connections.get(terminal_vee.get_instance_id(), -1)

	var iout = NAN
	var opamp_idx = vs_map.get(comp_id, -1)
	if opamp_idx != -1 and opamp_idx < x.size():
		iout = x[opamp_idx]
	
	var results = {
		"Vp": circuit.electrical_nodes.get(vp_node_id, {}).get("voltage", NAN),
		"Vn": circuit.electrical_nodes.get(vn_node_id, {}).get("voltage", NAN),
		"Vout": circuit.electrical_nodes.get(vout_node_id, {}).get("voltage", NAN),
		"Vcc": circuit.electrical_nodes.get(vcc_node_id, {}).get("voltage", NAN),
		"Vee": circuit.electrical_nodes.get(vee_node_id, {}).get("voltage", NAN),
		"Iout": iout,
		"region": comp_data.properties.get("operating_region", "N/A")
	}
	circuit.component_results[comp_id] = results
