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
var _prev_region: String = "OFF"  # Track previous region for change detection

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	hide_info()
	print_debug("OpAmp3D: Initialized {name} with gain={gain}, saturation={sat}V".format({
		"name": name, "gain": open_loop_gain, "sat": rail_saturation_voltage
	}))

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
	
	print_debug("OpAmp3D({name}): ======= UPDATE NONLINEAR STATE STARTS =======".format({"name": self.name}))
	
	print_debug("OpAmp3D({name}): Previous region: {prev}".format({"name": self.name, "prev": _prev_region}))
	print_debug("OpAmp3D({name}): Solution vec size: {sz}".format({"name": self.name, "sz": solution_vector.size()}))
	
	var vp_node_id = circuit.terminal_connections.get(terminal_vp.get_instance_id(), -1)
	var vn_node_id = circuit.terminal_connections.get(terminal_vn.get_instance_id(), -1)
	var vcc_node_id = circuit.terminal_connections.get(terminal_vcc.get_instance_id(), -1)
	var vee_node_id = circuit.terminal_connections.get(terminal_vee.get_instance_id(), -1)
	
	var Vp = circuit.electrical_nodes.get(vp_node_id, {}).get("voltage", 0.0)
	var Vn = circuit.electrical_nodes.get(vn_node_id, {}).get("voltage", 0.0)
	var Vcc = circuit.electrical_nodes.get(vcc_node_id, {}).get("voltage", 15.0)
	var Vee = circuit.electrical_nodes.get(vee_node_id, {}).get("voltage", -15.0)
	
	print_debug("OpAmp3D({name}): Vp={vp}, Vn={vn}, Vcc={vcc}, Vee={vee}".format({
		"name": self.name, "vp": Vp, "vn": Vn, "vcc": Vcc, "vee": Vee
	}))
	
	if is_nan(Vcc): Vcc = 15.0
	if is_nan(Vee): Vee = -15.0
	if Vcc < Vee: # Swap if rails are inverted
		var temp = Vcc
		Vcc = Vee
		Vee = temp

	var gain = comp_data.properties["open_loop_gain"]
	var ideal_vout = gain * (Vp - Vn)

	var rail_drop = comp_data.properties["rail_saturation_voltage"]
	var high_rail = Vcc - rail_drop
	var low_rail  = Vee + rail_drop

	var new_region = ""
	if ideal_vout > high_rail:
		new_region = "SAT_HIGH"
	elif ideal_vout < low_rail:
		new_region = "SAT_LOW"
	else:
		new_region = "LINEAR"

	print_debug("OpAmp3D({name}): region={r} (previous={prev}), ideal_vout={iv}, high_rail={hr}, low_rail={lr}".format({
		"name": self.name, "r": new_region, "prev": comp_data.properties.operating_region,
		"iv": ideal_vout, "hr": high_rail, "lr": low_rail
	}))

	var previous_region = comp_data.properties["operating_region"]
	if new_region != previous_region:
		print_debug("OpAmp3D({name}): Region changed: {pr} -> {nr}".format({"pr": previous_region, "nr": new_region, "name": self.name}))
		comp_data.properties["operating_region"] = new_region
		_prev_region = new_region
		print_debug("OpAmp3D({name}): Returning true (state changed)".format({"name": self.name}))
		return true

	print_debug("OpAmp3D({name}): No region change".format({"name": self.name}))
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
	print_debug("OpAmp3D({name}): ======= STAMP OPAMP =======".format({"name": self.name}))
	
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
	
	print_debug("OpAmp3D({name}): indices - Vp:{vp}, Vn:{vn}, Vout:{vo}, Vcc:{vc}, Vee:{ve}, VS:{vs}"
		.format({
			"name": self.name,
			"vp": vp_idx, "vn": vn_idx, "vo": vout_idx,
			"vc": vcc_idx, "ve": vee_idx, "vs": vs_idx
		}))
	
	print_debug("OpAmp3D({name}): Pre-stamp: b[idx_vs] = {val}".format({
		"name": self.name, "val": b[vs_idx] if vs_idx != -1 else "invalid"
	}))
	var region = comp_data.properties["operating_region"]
	if vs_idx == -1:
		printerr("OpAmp stamp error: component not found in vs_map.")
		return

	# KCL: Current through OpAmp output terminal
	if vout_idx != -1:
		A[vout_idx][vs_idx] += 1.0

	# KVL: Equation for the controlled source

	if region == "LINEAR" or region == "OFF": # Treat OFF as linear for first iteration
		# Vout = G * (Vp - Vn)  =>  Vp - Vn - Vout/G = 0
		# This form is more numerically stable than the one with large gain factors.
		var gain = comp_data.properties["open_loop_gain"]
		if vp_idx != -1:
			A[vs_idx][vp_idx] = 1.0
		if vn_idx != -1:
			A[vs_idx][vn_idx] = -1.0
		if vout_idx != -1:
			A[vs_idx][vout_idx] = -1.0 / gain
		b[vs_idx] = 0.0
	elif region == "SAT_HIGH":
		var sat_drop = comp_data.properties["rail_saturation_voltage"]
		# Vout = Vcc - sat_drop => Vout - Vcc = -sat_drop
		if vout_idx != -1: A[vs_idx][vout_idx] = 1.0
		if vcc_idx != -1: A[vs_idx][vcc_idx] = -1.0
		b[vs_idx] = -sat_drop
	elif region == "SAT_LOW":
		var sat_drop = comp_data.properties["rail_saturation_voltage"]
		# Vout = Vee + sat_drop => Vout - Vee = sat_drop
		if vout_idx != -1: A[vs_idx][vout_idx] = 1.0
		if vee_idx != -1: A[vs_idx][vee_idx] = -1.0
		b[vs_idx] = sat_drop

	print_debug("OpAmp3D({name}): Post-stamp: b[idx_vs] = {val}".format({
		"name": self.name, "val": b[vs_idx] if vs_idx != -1 else "invalid"
	}))
	
	if vs_idx != -1:
		var row_str = "A[{vs}] = [ ".format({"vs": vs_idx})
		for j in range(A[vs_idx].size()):
			row_str += "{val:.2f} ".format({"val": A[vs_idx][j]})
		row_str += "]"
		print_debug("OpAmp3D({name}): {row}".format({"name": self.name, "row": row_str}))
	else:
		printerr("OpAmp3D({name}): Invalid vs_idx!".format({"name": self.name}))

## Extracts and stores simulation results for this component.
func gather_sim_results(
		circuit: CircuitGraph,
		comp_data: Dictionary,
		x: Array,
		node_map: Dictionary,
		vs_map: Dictionary,
		inductor_map: Dictionary,
		delta_time: float):
	print_debug("OpAmp3D({name}): ======= GATHER RESULTS =======".format({"name": self.name}))
		
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
	
	print_debug("OpAmp3D({name}): Vp={vp}, Vn={vn}, Vout={vo}, Vdiff={vd}".format({
		"name": self.name, "vp": Vp, "vn": Vn, "vo": Vout, "vd": results["Vp_minus_Vn"]
	}))
	
	var region = comp_data.properties.get("operating_region", "N/A")
	print_debug("OpAmp3D({name}): Operating region: {r}".format({"name": self.name, "r": region}))
		
	circuit.component_results[comp_id] = results
	
	print_debug("OpAmp3D({name}): Stored results: {res}".format({
		"name": self.name, "res": circuit.component_results
	}))
