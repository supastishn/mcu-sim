extends Node3D

class_name NChannelMOSFET3D

const LinearSolver = preload("res://LinearSolver.gd")


## Emitted when a key property of the MOSFET changes.
signal configuration_changed(component_node: Node3D)


## The gate-source threshold voltage (Vt) required to turn the MOSFET on.
@export var threshold_voltage: float = 2.0 : set = set_threshold_voltage

## The transconductance parameter (Kn), related to the MOSFET's current-carrying capability.
@export var transconductance_parameter: float = 0.1 : set = set_transconductance_parameter
## The channel-length modulation parameter (lambda). A value of 0.0 is ideal.
@export var lambda: float = 0.01

## Reference to the Drain terminal Area3D node.
@onready var terminal_d: Area3D = $TerminalD 
## Reference to the Gate terminal Area3D node.
@onready var terminal_g: Area3D = $TerminalG 
## Reference to the Source terminal Area3D node.
@onready var terminal_s: Area3D = $TerminalS 
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel
## Reference to the main mesh of the component.
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal_d or not terminal_g or not terminal_s:
		printerr("NChannelMOSFET3D requires child Area3D nodes named 'TerminalD', 'TerminalG', and 'TerminalS'.")
	if not info_label:
		printerr("NChannelMOSFET3D requires a child Label3D named 'InfoLabel'.")
	if not mesh_instance:
		printerr("NChannelMOSFET3D requires a child MeshInstance3D named 'MeshInstance3D'.")
	
	reset_visual_state()
	set_threshold_voltage(threshold_voltage)
	set_transconductance_parameter(transconductance_parameter)

## Sets the threshold voltage, validates it, and emits a signal.
func set_threshold_voltage(value: float):
	var new_vt = clampf(value, 0.1, 10.0)
	if is_equal_approx(threshold_voltage, new_vt):
		threshold_voltage = new_vt
		return

	threshold_voltage = new_vt
	print("NChannelMOSFET3D {name} threshold_voltage set to: {vt_str} V".format({"name": name, "vt_str": String.num(threshold_voltage, 2)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the transconductance parameter, validates it, and emits a signal.
func set_transconductance_parameter(value: float):
	var new_kn = max(1e-6, value)
	if is_equal_approx(transconductance_parameter, new_kn):
		transconductance_parameter = new_kn
		return

	transconductance_parameter = new_kn
	print("NChannelMOSFET3D {name} transconductance_parameter set to: {kn_str} A/V^2".format({"name": name, "kn_str": String.num_scientific(transconductance_parameter)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)



## Displays the calculated operating region and characteristics on the component's 3D label.
func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var id_str = "Id: N/A" 
	if results.has("Id") and not is_nan(results.Id):
		id_str = "Id: " + StringUtils.format_current(results.Id)
	
	var vgs_str = "Vgs: N/A" 
	if results.has("Vgs") and not is_nan(results.Vgs):
		vgs_str = "Vgs: {val_str} V".format({"val_str": String.num(results.Vgs, 2)})

	var vds_str = "Vds: N/A" 
	if results.has("Vds") and not is_nan(results.Vds):
		vds_str = "Vds: {val_str} V".format({"val_str": String.num(results.Vds, 2)})

	var region_str = "Region: N/A"
	if results.has("region"):
		region_str = "Region: {reg}".format({"reg": results.region})
		
	info_label.text = "{r_str}\n{id}\nVgs: {vgs}\nVds: {vds}".format({
		"r_str": region_str, 
		"id": id_str, 
		"vgs": vgs_str.replace("Vgs: ", ""), 
		"vds": vds_str.replace("Vds: ", "")  
		})
	info_label.visible = true

## Hides the information label.
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = "" 


## Resets the component to its default visual state.
func reset_visual_state():
	hide_info()
	if is_instance_valid(mesh_instance):
		mesh_instance.material_override = null 

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"D": {"node": terminal_d, "pos": terminal_d.position},
		"G": {"node": terminal_g, "pos": terminal_g.position},
		"S": {"node": terminal_s, "pos": terminal_s.position}
	}

## Extracts and stores simulation results (currents, voltages, region) for this component.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		_x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		_inductor_map : Dictionary,
		_delta_time   : float) -> void:
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()

	var Vd_nmos_calc = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["D"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vg_nmos_calc = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["G"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vs_nmos_calc = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["S"].get_instance_id(), -1), {}).get("voltage", NAN)
	
	var region_nmos_calc = comp_data.properties["operating_region"]
	var vt_nmos_model_calc = comp_data.properties["threshold_voltage"]
	var kn_nmos_model_calc = comp_data.properties["transconductance_parameter"]
	
	var Id_nmos: float = NAN
	var Vgs_nmos_actual: float = NAN
	var Vds_nmos_actual: float = NAN

	if not is_nan(Vg_nmos_calc) and not is_nan(Vs_nmos_calc) and not is_nan(Vd_nmos_calc):
		Vgs_nmos_actual = Vg_nmos_calc - Vs_nmos_calc
		Vds_nmos_actual = Vd_nmos_calc - Vs_nmos_calc
		var vgs_vt_diff_calc = Vgs_nmos_actual - vt_nmos_model_calc

		if region_nmos_calc == "OFF": 
			Id_nmos = 0.0
		elif region_nmos_calc == "TRIODE": 
			Id_nmos = kn_nmos_model_calc * (vgs_vt_diff_calc * Vds_nmos_actual - 0.5 * pow(Vds_nmos_actual, 2.0)) * (1 + lambda * Vds_nmos_actual)
		elif region_nmos_calc == "SATURATION": 
			Id_nmos = 0.5 * kn_nmos_model_calc * pow(vgs_vt_diff_calc, 2.0) * (1 + lambda * Vds_nmos_actual)
	
	circuit.component_results[comp_id]["Id"] = Id_nmos
	circuit.component_results[comp_id]["Vgs"] = Vgs_nmos_actual
	circuit.component_results[comp_id]["Vds"] = Vds_nmos_actual
	circuit.component_results[comp_id]["region"] = region_nmos_calc

## Updates the MOSFET's operating region based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty():
		return false

	var term_d_nmos = comp_data.terminals["D"]
	var term_g_nmos = comp_data.terminals["G"]
	var term_s_nmos = comp_data.terminals["S"]
	var node_d_id_nmos = circuit.terminal_connections.get(term_d_nmos.get_instance_id(), -1)
	var node_g_id_nmos = circuit.terminal_connections.get(term_g_nmos.get_instance_id(), -1)
	var node_s_id_nmos = circuit.terminal_connections.get(term_s_nmos.get_instance_id(), -1)

	var idx_d = node_map_iter.get(node_d_id_nmos, -1)
	var idx_g = node_map_iter.get(node_g_id_nmos, -1)
	var idx_s = node_map_iter.get(node_s_id_nmos, -1)
	var Vd_nmos = x_iter[idx_d] if idx_d != -1 else (0.0 if node_d_id_nmos == circuit.ground_node_id else NAN)
	var Vg_nmos = x_iter[idx_g] if idx_g != -1 else (0.0 if node_g_id_nmos == circuit.ground_node_id else NAN)
	var Vs_nmos = x_iter[idx_s] if idx_s != -1 else (0.0 if node_s_id_nmos == circuit.ground_node_id else NAN)

	if not is_nan(Vg_nmos): comp_data.properties["_internal_Vg_stamp"] = Vg_nmos
	if not is_nan(Vs_nmos): comp_data.properties["_internal_Vs_stamp"] = Vs_nmos
	if not is_nan(Vd_nmos) and not is_nan(Vs_nmos): comp_data.properties["_internal_Vds_stamp"] = Vd_nmos - Vs_nmos

	var vt_nmos_model = comp_data.properties["threshold_voltage"]
	var previous_region_nmos = comp_data.properties["operating_region"]
	var new_region_nmos = previous_region_nmos

	if is_nan(Vg_nmos) or is_nan(Vs_nmos) or is_nan(Vd_nmos):
		new_region_nmos = "OFF"
	else:
		var Vgs_nmos = Vg_nmos - Vs_nmos
		var Vds_nmos = Vd_nmos - Vs_nmos
		var vgs_vt_diff = Vgs_nmos - vt_nmos_model

		if Vgs_nmos <= vt_nmos_model: 
			new_region_nmos = "OFF"
		else: 
			if Vds_nmos < vgs_vt_diff: 
				new_region_nmos = "TRIODE"
			else: 
				new_region_nmos = "SATURATION"

	if new_region_nmos != previous_region_nmos:
		comp_data.properties["operating_region"] = new_region_nmos
		return true
	return false

## Applies the MOSFET's contribution to the MNA matrices based on its current operating region.
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
	var region_nmos_mna_val = comp_data.properties["operating_region"]
	var vt_nmos_mna_prop = threshold_voltage 
	var kn_nmos_mna_prop = transconductance_parameter 

	var d_id = terminal_d.get_instance_id()
	var g_id = terminal_g.get_instance_id()
	var s_id = terminal_s.get_instance_id()

	var node_d_lookup = terminal_connections.get(d_id, -1)
	var node_g_lookup = terminal_connections.get(g_id, -1)
	var node_s_lookup = terminal_connections.get(s_id, -1)

	var idx_d = node_map.get(node_d_lookup, -1)
	var idx_g = node_map.get(node_g_lookup, -1)
	var idx_s = node_map.get(node_s_lookup, -1)

	
	var G_gate_leakage_const = 1e-12 
	
	CircuitGraph.stamp_conductance(A, G_gate_leakage_const, idx_g, idx_d)
	CircuitGraph.stamp_conductance(A, G_gate_leakage_const, idx_g, idx_s)

	if region_nmos_mna_val == "OFF":
		var G_ds_off_const = 1e-9 
		CircuitGraph.stamp_conductance(A, G_ds_off_const, idx_d, idx_s)
	else:
		var Vg_prev_iter_val = comp_data.properties.get("_internal_Vg_stamp", 0.0) 
		var Vs_prev_iter_val = comp_data.properties.get("_internal_Vs_stamp", 0.0)
		var Vgs_for_model_val = Vg_prev_iter_val - Vs_prev_iter_val

		if region_nmos_mna_val == "TRIODE":
			# Smooth step transition for numerical stability
			var diff = Vgs_for_model_val - vt_nmos_mna_prop
			const DIFF_THRESHOLD = 0.01
			const SCALE = 50.0
			var lerp_weight = 1.0 / (1.0 + exp(-SCALE * (diff - DIFF_THRESHOLD)))
			var safe_diff = lerp(DIFF_THRESHOLD, diff, lerp_weight)
			var effective_conductance_triode = kn_nmos_mna_prop * safe_diff
			var R_ds_triode_approx_val = 1.0 / effective_conductance_triode
			if R_ds_triode_approx_val > 1e9: R_ds_triode_approx_val = 1e9
			if R_ds_triode_approx_val < 1e-3: R_ds_triode_approx_val = 1e-3 
			var G_ds_triode_val = 1.0 / R_ds_triode_approx_val
			CircuitGraph.stamp_conductance(A, G_ds_triode_val, idx_d, idx_s)
			
		elif region_nmos_mna_val == "SATURATION":
			# Model with channel length modulation: Id = 0.5 * Kn * (Vgs-Vt)^2 * (1 + lambda*Vds)
			# This linearizes to a current source, an output conductance g_ds, and a transconductance gm.
			var Vds_last = comp_data.properties.get("_internal_Vds_stamp", 0.0)
			var vgs_minus_vt = max(0, Vgs_for_model_val - vt_nmos_mna_prop)
			
			# Small-signal parameters (Jacobian elements)
			var g_ds = 0.5 * kn_nmos_mna_prop * pow(vgs_minus_vt, 2.0) * lambda
			var gm = kn_nmos_mna_prop * vgs_minus_vt * (1.0 + lambda * Vds_last)

			# KCL error at Drain is Id, at Source is -Id.
			# Stamp Drain row: d(Id)/dV
			if idx_d != -1:
				A[idx_d][idx_d] += g_ds
				A[idx_d][idx_g] += gm
				A[idx_d][idx_s] -= (gm + g_ds)
			# Stamp Source row: d(-Id)/dV
			if idx_s != -1:
				A[idx_s][idx_d] -= g_ds
				A[idx_s][idx_g] -= gm
				A[idx_s][idx_s] += (gm + g_ds)

			# Companion model current source
			var Id_last = 0.5 * kn_nmos_mna_prop * pow(vgs_minus_vt, 2.0) * (1 + lambda * Vds_last)
			var Ieq_d = Id_last - (gm * Vgs_for_model_val + g_ds * Vds_last)

			if idx_d != -1: b[idx_d] += Ieq_d
			if idx_s != -1: b[idx_s] -= Ieq_d

func get_kcl_contributions(graph: CircuitGraph, _all_node_voltages: Dictionary, F_v: Array, system: Dictionary, _delta_time: float):
	var node_d_id = graph.terminal_connections.get(terminal_d.get_instance_id(), -1)
	var node_g_id = graph.terminal_connections.get(terminal_g.get_instance_id(), -1)
	var node_s_id = graph.terminal_connections.get(terminal_s.get_instance_id(), -1)

	var Vd = graph.electrical_nodes.get(node_d_id, {}).get("voltage", 0.0)
	var Vg = graph.electrical_nodes.get(node_g_id, {}).get("voltage", 0.0)
	var Vs = graph.electrical_nodes.get(node_s_id, {}).get("voltage", 0.0)

	var Vgs = Vg - Vs
	var Vds = Vd - Vs
	var vt = threshold_voltage
	var kn = transconductance_parameter
	
	var Id = 0.0
	var region = "OFF"
	if Vgs > vt:
		if Vds < (Vgs - vt): # Triode
			Id = kn * ( (Vgs - vt) * Vds - 0.5 * pow(Vds, 2.0) ) * (1 + lambda * Vds)
			region = "TRIODE"
		else: # Saturation
			Id = 0.5 * kn * pow(Vgs - vt, 2.0) * (1 + lambda * Vds)
			region = "SATURATION"

	if not !is_nan(Id):
		LinearSolver.print_matrix(system.A, "A on N-MOS kcl fail")
		LinearSolver.print_vector(F_v, "F_v on N-MOS kcl fail")
		printerr("N-MOSFET {mos}: Id is NaN. Region={r}, Vgs={vgs}, Vds={vds}".format({ "mos": name, "r": region, "vgs": Vgs, "vds": Vds }))
		return

	var idx_d = system.node_map.get(node_d_id, -1)
	var idx_s = system.node_map.get(node_s_id, -1)

	if idx_d != -1: F_v[idx_d] += Id
	if idx_s != -1: F_v[idx_s] -= Id
