extends Node3D
class_name PChannelMOSFET3D

const LinearSolver = preload("res://LinearSolver.gd")

## Emitted when a key property of the MOSFET changes.
signal configuration_changed(component_node : Node3D)

## The absolute gate-source threshold voltage |Vtp| required to turn the MOSFET on.
@export var threshold_voltage : float = 2.0 : set = set_threshold_voltage
## The transconductance parameter (Kp), related to the MOSFET's current-carrying capability.
@export var transconductance_parameter : float = 0.1 : set = set_transconductance_parameter
## The channel-length modulation parameter (lambda). A value of 0.0 is ideal.
@export var lambda: float = 0.01

## Reference to the Drain terminal Area3D node.
@onready var terminal_d : Area3D = $TerminalD
## Reference to the Gate terminal Area3D node.
@onready var terminal_g : Area3D = $TerminalG
## Reference to the Source terminal Area3D node.
@onready var terminal_s : Area3D = $TerminalS
## Reference to the Label3D for displaying simulation info.
@onready var info_label : Label3D = $InfoLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
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
	print("PChannelMOSFET3D {name} threshold_voltage set to: {vt_str} V".format({"name": name, "vt_str": String.num(threshold_voltage, 2)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the transconductance parameter, validates it, and emits a signal.
func set_transconductance_parameter(value: float):
	var new_kp = max(1e-6, value)
	if is_equal_approx(transconductance_parameter, new_kp):
		transconductance_parameter = new_kp
		return

	transconductance_parameter = new_kp
	print("PChannelMOSFET3D {name} transconductance_parameter set to: {kp_str} A/V^2".format({"name": name, "kp_str": String.num_scientific(transconductance_parameter)}))
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

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"D": {"node": terminal_d, "pos": terminal_d.position},
		"G": {"node": terminal_g, "pos": terminal_g.position},
		"S": {"node": terminal_s, "pos": terminal_s.position}
	}

# ---------- NON-LINEAR REGION EVAL ----------
## Updates the MOSFET's operating region based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty():
		return false

	var node_s_id = circuit.terminal_connections.get(terminal_s.get_instance_id(), -1)
	var node_g_id = circuit.terminal_connections.get(terminal_g.get_instance_id(), -1)
	var node_d_id = circuit.terminal_connections.get(terminal_d.get_instance_id(), -1)

	var idx_s = node_map_iter.get(node_s_id, -1)
	var idx_g = node_map_iter.get(node_g_id, -1)
	var idx_d = node_map_iter.get(node_d_id, -1)

	var Vs = x_iter[idx_s] if idx_s != -1 else (0.0 if node_s_id == circuit.ground_node_id else NAN)
	var Vg = x_iter[idx_g] if idx_g != -1 else (0.0 if node_g_id == circuit.ground_node_id else NAN)
	var Vd = x_iter[idx_d] if idx_d != -1 else (0.0 if node_d_id == circuit.ground_node_id else NAN)

	if not is_nan(Vg): comp_data.properties["_int_Vg"] = Vg
	if not is_nan(Vs): comp_data.properties["_int_Vs"] = Vs
	if not is_nan(Vd): comp_data.properties["_int_Vd"] = Vd

	var prev = comp_data.properties["operating_region"]
	var reg  = prev
	if is_nan(Vs) or is_nan(Vg) or is_nan(Vd):
		reg = "OFF"
	else:
		var Vsg = Vs - Vg
		var Vsd = Vs - Vd
		if Vsg <= threshold_voltage:
			reg = "OFF"
		else:
			if Vsd <= (Vsg - threshold_voltage):
				reg = "TRIODE"
			else:
				reg = "SATURATION"
	if reg!=prev:
		comp_data.properties["operating_region"] = reg
		return true
	return false

# ---------- STAMP ----------
## Applies the MOSFET's contribution to the MNA matrices based on its current operating region.
func stamp(A, b, node_map, _vs_map, _inductor_map, term_conn, comp_data, _dt):
	var reg = comp_data.properties.get("operating_region")
	var vt  = threshold_voltage
	var kp  = transconductance_parameter
	var p_lambda = lambda

	var idx_d = node_map.get(term_conn.get(terminal_d.get_instance_id(),-1), -1)
	var idx_s = node_map.get(term_conn.get(terminal_s.get_instance_id(),-1), -1)
	var idx_g = node_map.get(term_conn.get(terminal_g.get_instance_id(),-1), -1)

	CircuitGraph.stamp_conductance(A, 1e-12, idx_g, idx_s) # Gate leakage
	
	var Vsg = comp_data.properties.get("_int_Vs",0.0) - comp_data.properties.get("_int_Vg",0.0)
	var Vsd = comp_data.properties.get("_int_Vs",0.0) - comp_data.properties.get("_int_Vd",0.0)

	if reg=="OFF":
		CircuitGraph.stamp_conductance(A, 1e-9, idx_s, idx_d)
	elif reg=="TRIODE":
		# Simplified model: treat as a resistor R_ds = 1 / (Kp * (Vsg - |Vt|))
		var vsg_minus_vt = max(0, Vsg - vt)
		var g_ds_triode = kp * vsg_minus_vt
		CircuitGraph.stamp_conductance(A, g_ds_triode, idx_s, idx_d)
	else: # SATURATION
		# Small-signal parameters (Jacobian elements) for Id(Vsg, Vsd)
		var vsg_minus_vt = max(0, Vsg - vt)
		var g_ds = 0.5 * kp * pow(vsg_minus_vt, 2.0) * p_lambda
		var gm = kp * vsg_minus_vt * (1.0 + p_lambda * Vsd)

		# KCL error at Source is Id, at Drain is -Id. Current flows S -> D.
		# Stamp Source row: d(Id)/dV
		if idx_s != -1:
			A[idx_s][idx_s] += gm + g_ds
			A[idx_s][idx_g] -= gm
			A[idx_s][idx_d] -= g_ds
		# Stamp Drain row: d(-Id)/dV
		if idx_d != -1:
			A[idx_d][idx_s] -= (gm + g_ds)
			A[idx_d][idx_g] += gm
			A[idx_d][idx_d] += g_ds

		# Companion model current source
		var Id_last = 0.5 * kp * pow(vsg_minus_vt, 2.0) * (1 + p_lambda * Vsd)
		var Ieq_d = Id_last - (gm * Vsg + g_ds * Vsd)
		
		# Current flows S to D. Ieq is for Id.
		if idx_s != -1: b[idx_s] += Ieq_d
		if idx_d != -1: b[idx_d] -= Ieq_d

# ---------- gather_sim_results ----------
## Extracts and stores simulation results (currents, voltages, region) for this component.
func gather_sim_results(circuit,comp_data,_x,_node_map,_vs_map,_inductor_map,_dt):
	var cid = comp_data.component_node.get_instance_id()
	var Vs = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_s.get_instance_id(),-1), {}).get("voltage", NAN)
	var Vg = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_g.get_instance_id(),-1), {}).get("voltage", NAN)
	var Vd = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_d.get_instance_id(),-1), {}).get("voltage", NAN)
	var vt = threshold_voltage

	var Vgs = Vg - Vs
	var Vds = Vd - Vs
	var Vsg = -Vgs
	var Vsd = -Vds
	var Id  = NAN
	var reg = comp_data.properties["operating_region"]
	if not (!is_nan(Vsg) and !is_nan(Vsd)):
		LinearSolver.print_vector(_x, "x on P-MOS results fail")
		printerr("P-MOSFET {p}: Terminal voltage is NaN. Vsg={vsg}, Vsd={vsd}".format({ "p": name, "vsg": Vsg, "vsd": Vsd }))
		return
	if not is_nan(Vsg) and not is_nan(Vsd):
		if reg=="OFF":
			Id = 0.0
		elif reg=="TRIODE":
			Id =  transconductance_parameter * ( (Vsg - vt) * Vsd - 0.5*pow(Vsd,2) ) * (1 + lambda * Vsd)
		else: # SATURATION
			Id = 0.5 * transconductance_parameter * pow(Vsg - vt,2) * (1 + lambda * Vsd)
	if not !is_nan(Id):
		LinearSolver.print_vector(_x, "x on P-MOS results fail")
		printerr("P-MOSFET {p}: Id is NaN. Region={r}, Vsg={vsg}, Vsd={vsd}".format({ "p": name, "r": reg, "vsg": Vsg, "vsd": Vsd }))
	
	circuit.component_results[cid]["Id"]  = Id
	circuit.component_results[cid]["Vgs"] = Vgs
	circuit.component_results[cid]["Vds"] = Vds
	circuit.component_results[cid]["region"] = reg
