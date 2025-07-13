extends Node3D
class_name OpAmp3D

## Emitted when a key property of the op-amp changes.
signal configuration_changed(component_node: Node3D)

# Properties for the ideal op-amp simulation model
## The open-loop voltage gain of the op-amp.
@export var open_loop_gain: float = 200000.0
## The voltage drop from the supply rails for output saturation.
@export var rail_saturation_voltage: float = 1.5 # Voltage drop from the supply rails

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

# --- Simulation Interface ---
## Updates the op-amp's operating region (LINEAR, SAT_HIGH, SAT_LOW) based on an MNA iteration.
func update_nonlinear_state(
		circuit: CircuitGraph,
		comp_data: Dictionary,
		solution_vector: Array,
		node_map: Dictionary,
		vs_map: Dictionary
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
		vs_map: Dictionary,
		inductor_map: Dictionary,
		terminal_connections: Dictionary,
		comp_data: Dictionary,
		delta_time: float
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

	var Gbig = 1e9  # Large conductance for voltage stamping

	if region == "OFF":
		if vout_idx != -1:
			A[vout_idx][vout_idx] += 1e-9 # High impedance to ground
	elif region == "LINEAR":
		# Model as a VCVS: Vout = Aol * (Vp - Vn)
		# Enforced with a large-conductance model: G * (Vout - Aol * (Vp - Vn)) = 0
		# KCL at Vout: ... + G*Vout - G*Aol*Vp + G*Aol*Vn = 0
		var Aol = open_loop_gain
		if vout_idx != -1:
			A[vout_idx][vout_idx] += Gbig
			if vp_idx != -1:
				A[vout_idx][vp_idx] -= Gbig * Aol
			if vn_idx != -1:
				A[vout_idx][vn_idx] += Gbig * Aol
	elif region == "SAT_HIGH":
		# Enforce Vout = Vcc - rail_saturation_voltage
		var sat_drop = comp_data.properties["rail_saturation_voltage"]
		if vout_idx != -1:
			if vcc_idx != -1:
				A[vout_idx][vout_idx] += Gbig
				A[vout_idx][vcc_idx] -= Gbig
				b[vout_idx] += Gbig * ( -sat_drop )
			else: # Vcc not connected, clamp to GND reference
				A[vout_idx][vout_idx] += Gbig
				b[vout_idx] += Gbig * ( -sat_drop )
	elif region == "SAT_LOW":
		# Enforce Vout = Vee + rail_saturation_voltage
		var sat_drop = comp_data.properties["rail_saturation_voltage"]
		if vout_idx != -1:
			if vee_idx != -1:
				A[vout_idx][vout_idx] += Gbig
				A[vout_idx][vee_idx] -= Gbig
				b[vout_idx] += Gbig * sat_drop
			else: # Vee not connected
				A[vout_idx][vout_idx] += Gbig
				b[vout_idx] += Gbig * sat_drop

## Extracts and stores simulation results for this component.
func gather_sim_results(
		circuit: CircuitGraph,
		comp_data: Dictionary,
		x: Array,
		node_map: Dictionary,
		vs_map: Dictionary,
		inductor_map: Dictionary,
		delta_time: float):
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
