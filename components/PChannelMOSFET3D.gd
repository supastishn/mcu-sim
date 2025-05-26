extends Node3D
class_name PChannelMOSFET3D

signal configuration_changed(component_node : Node3D)

@export var threshold_voltage : float = 2.0    : set = set_threshold_voltage   # |Vtp|
@export var transconductance_parameter : float = 0.1 : set = set_kn            # kp

@onready var terminal_d : Area3D = $TerminalD
@onready var terminal_g : Area3D = $TerminalG
@onready var terminal_s : Area3D = $TerminalS
@onready var info_label : Label3D = $InfoLabel

func _ready():
	set_threshold_voltage(threshold_voltage)
	set_kn(transconductance_parameter)
	reset_visual_state()

func set_threshold_voltage(v):
	threshold_voltage = clampf(v,0.1,10.0)
	if is_inside_tree(): emit_signal("configuration_changed", self)

func set_kn(v):
	transconductance_parameter = max(1e-6,v)
	if is_inside_tree(): emit_signal("configuration_changed", self)

func _format_current(current_value: float) -> String:
	if abs(current_value) < 1e-9 and abs(current_value) > 1e-15 : 
		return "{val_str} pA".format({"val_str": String.num(current_value * 1e12, 2)})
	elif abs(current_value) < 1e-6 and abs(current_value) >= 1e-12 : 
		return "{val_str} nA".format({"val_str": String.num(current_value * 1e9, 2)})
	elif abs(current_value) < 1e-3: 
		return "{val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
	elif abs(current_value) < 1.0: 
		return "{val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
	else: 
		return "{val_str} A".format({"val_str": String.num(current_value, 2)})

func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var id_str = "Id: N/A" 
	if results.has("Id") and not is_nan(results.Id):
		id_str = "Id: {val_str}".format({"val_str": _format_current(results.Id)})
	
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

func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = "" 

func reset_visual_state():
	hide_info()

# ---------- NON-LINEAR REGION EVAL ----------
func update_nonlinear_state(circuit, comp_data, _x_iter=null, _vs_map_iter=null)->bool:
	var Vs = circuit.electrical_nodes.get(
		circuit.terminal_connections.get(terminal_s.get_instance_id(),-1),{}
		).get("voltage",NAN)
	var Vg = circuit.electrical_nodes.get(
		circuit.terminal_connections.get(terminal_g.get_instance_id(),-1),{}
		).get("voltage",NAN)
	var Vd = circuit.electrical_nodes.get(
		circuit.terminal_connections.get(terminal_d.get_instance_id(),-1),{}
		).get("voltage",NAN)

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

# --------------------------------------------------------------
# generic G-stamp helper (same style as other component scripts)
func _stamp_conductance(A: Array, g: float, idx1: int, idx2: int) -> void:
	if idx1 != -1 and idx2 != -1:
		A[idx1][idx1] += g
		A[idx2][idx2] += g
		A[idx1][idx2] -= g
		A[idx2][idx1] -= g
	elif idx1 != -1:
		A[idx1][idx1] += g
	elif idx2 != -1:
		A[idx2][idx2] += g

# ---------- STAMP ----------
func stamp(A,b,node_map,vs_map,inductor_map,term_conn,comp_data,dt):
	var reg = comp_data.properties["operating_region"]
	var vt  = threshold_voltage
	var kp  = transconductance_parameter

	var idx_d = node_map.get(term_conn.get(terminal_d.get_instance_id(),-1), -1)
	var idx_s = node_map.get(term_conn.get(terminal_s.get_instance_id(),-1), -1)
	var idx_g = node_map.get(term_conn.get(terminal_g.get_instance_id(),-1), -1)

	var G_gate_leak = 1e-12

	_stamp_conductance(A, G_gate_leak, idx_g, idx_s)
	_stamp_conductance(A, G_gate_leak, idx_g, idx_d)

	if reg=="OFF":
		_stamp_conductance(A, 1e-9, idx_s, idx_d)
	elif reg=="TRIODE":
		var Vsg = comp_data.properties.get("_int_Vs",0.0) - comp_data.properties.get("_int_Vg",0.0)
		var cond = kp * max(0.01, Vsg - vt)
		cond = clamp(cond,1e-3,1e9)
		_stamp_conductance(A, cond, idx_s, idx_d)
	else: # SATURATION
		var Vsg = comp_data.properties.get("_int_Vs",0.0) - comp_data.properties.get("_int_Vg",0.0)
		var Id_sat = 0.0
		if Vsg > vt:
			Id_sat = -0.5 * kp * pow(Vsg - vt,2.0)   # negative current (S->D)
		if idx_s!=-1: b[idx_s] += Id_sat
		if idx_d!=-1: b[idx_d] -= Id_sat
		# add a tiny output-resistance so the matrix is well-conditioned
		var Gds_sat := 1e-6      #  ≈ 1 MΩ
		_stamp_conductance(A, Gds_sat, idx_s, idx_d)

# ---------- gather_sim_results ----------
func gather_sim_results(circuit,comp_data,x,node_map,vs_map,inductor_map,dt):
	var cid = comp_data.component_node.get_instance_id()
	if not cid in circuit.component_results: circuit.component_results[cid] = {}
	var Vs = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_s.get_instance_id(),-1), {}).get("voltage", NAN)
	var Vg = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_g.get_instance_id(),-1), {}).get("voltage", NAN)
	var Vd = circuit.electrical_nodes.get(circuit.terminal_connections.get(terminal_d.get_instance_id(),-1), {}).get("voltage", NAN)
	var vt = threshold_voltage   # local copy for formulas

	var Vgs = Vg - Vs
	var Vds = Vd - Vs
	var Vsg = -Vgs
	var Vsd = -Vds
	var Id  = NAN
	var reg = comp_data.properties["operating_region"]
	if not is_nan(Vsg) and not is_nan(Vsd):
		if reg=="OFF":
			Id = 0.0
		elif reg=="TRIODE":
			Id =  transconductance_parameter * ( (Vsg - vt) * Vsd - 0.5*pow(Vsd,2) )
		else: # SATURATION
			Id = 0.5 * transconductance_parameter * pow(Vsg - vt,2)
	# ensure we always store a positive current magnitude
	if not is_nan(Id) and Id < 0.0:
		Id = -Id
	circuit.component_results[cid]["Id"]  = Id
	circuit.component_results[cid]["Vgs"] = Vgs
	circuit.component_results[cid]["Vds"] = Vds
	circuit.component_results[cid]["region"] = reg
