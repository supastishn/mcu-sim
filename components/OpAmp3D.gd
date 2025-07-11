extends Node3D
class_name OpAmp3D

signal configuration_changed(component_node: Node3D)

# Properties for the ideal op-amp simulation model
@export var open_loop_gain: float = 200000.0
@export var rail_saturation_voltage: float = 1.5 # Voltage drop from the supply rails

# UI and component node references
@onready var terminal_vp: Area3D = $TerminalVp
@onready var terminal_vn: Area3D = $TerminalVn
@onready var terminal_vout: Area3D = $TerminalVout
@onready var terminal_vcc: Area3D = $TerminalVcc
@onready var terminal_vee: Area3D = $TerminalVee
@onready var info_label: Label3D = $InfoLabel

func _ready():
	hide_info()

# --- Visual Feedback ---
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

func hide_info():
	if is_instance_valid(info_label):
		info_label.visible = false

func reset_visual_state():
	hide_info()

# --- Simulation Interface ---
func update_nonlinear_state(
		circuit: CircuitGraph,
		comp_data: Dictionary,
		solution_vector: Array,
		node_map: Dictionary,
		vs_map: Dictionary
	) -> bool:
	
	var vp_node_id = circuit.terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = circuit.terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vcc_node_id = circuit.terminal_connections.get(terminal_vcc.get_instance_id(), -1)
	var vee_node_id = circuit.terminal_connections.get(terminal_vee.get_instance_id(), -1)
	
	var Vp = circuit.electrical_nodes.get(vp_node_id, {}).get("voltage", 0.0)
	var Vn = circuit.electrical_nodes.get(vn_node_id, {}).get("voltage", 0.0)
	var Vcc = circuit.electrical_nodes.get(vcc_node_id, {}).get("voltage", 15.0)
	var Vee = circuit.electrical_nodes.get(vee_node_id, {}).get("voltage", -15.0)
	
	if is_nan(Vcc): Vcc = 15.0
	if is_nan(Vee): Vee = -15.0
	if Vcc < Vee: # Swap if rails are inverted
		var temp = Vcc
		Vcc = Vee
		Vee = temp

	var ideal_vout = comp_data.properties.open_loop_gain * (Vp - Vn)
	
	var high_rail = Vcc - comp_data.properties.rail_saturation_voltage
	var low_rail = Vee + comp_data.properties.rail_saturation_voltage
	
	var new_region = ""
	if ideal_vout > high_rail:
		new_region = "SAT_HIGH"
	elif ideal_vout < low_rail:
		new_region = "SAT_LOW"
	else:
		new_region = "LINEAR"

	var previous_region = comp_data.properties.get("operating_region", "OFF")
	if new_region != previous_region:
		comp_data.properties.operating_region = new_region
		return true # State changed
	
	return false # State did not change

func stamp(
		A: Array,
		b: Array,
		node_map: Dictionary,
		vs_map: Dictionary,
		inductor_map: Dictionary,
		terminal_connections: Dictionary,
		comp_data: Dictionary,
		delta_time: float
	):
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
	
	var vs_idx = vs_map.get(self.get_instance_id(), -1)
	if vs_idx == -1:
		printerr("OpAmp stamp error: component not found in vs_map.")
		return
		
	# KCL: Current through OpAmp output terminal
	if vout_idx != -1:
		A[vout_idx][vs_idx] += 1.0
		
	# KVL: Equation for the controlled source
	var region = comp_data.properties.operating_region
	var sat_drop = comp_data.properties.rail_saturation_voltage
	
	if region == "LINEAR" or region == "OFF": # Treat OFF as linear for first iteration
		var gain = comp_data.properties.open_loop_gain
		# Vout = gain * (Vp - Vn)  =>  Vout - gain*Vp + gain*Vn = 0
		if vout_idx != -1: A[vs_idx][vout_idx] = 1.0
		if vp_idx != -1: A[vs_idx][vp_idx] = -gain
		if vn_idx != -1: A[vs_idx][vn_idx] = gain
		b[vs_idx] = 0.0
	elif region == "SAT_HIGH":
		# Vout = Vcc - sat_drop => Vout - Vcc = -sat_drop
		if vout_idx != -1: A[vs_idx][vout_idx] = 1.0
		if vcc_idx != -1: A[vs_idx][vcc_idx] = -1.0
		b[vs_idx] = -sat_drop
	elif region == "SAT_LOW":
		# Vout = Vee + sat_drop => Vout - Vee = sat_drop
		if vout_idx != -1: A[vs_idx][vout_idx] = 1.0
		if vee_idx != -1: A[vs_idx][vee_idx] = -1.0
		b[vs_idx] = sat_drop

func gather_sim_results(
		circuit: CircuitGraph,
		comp_data: Dictionary,
		x: Array,
		node_map: Dictionary,
		vs_map: Dictionary,
		inductor_map: Dictionary,
		delta_time: float):
		
	var comp_id = self.get_instance_id()
	if not circuit.component_results.has(comp_id):
		circuit.component_results[comp_id] = {}
		
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
