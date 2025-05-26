extends Node3D

class_name NChannelMOSFET3D


signal configuration_changed(component_node: Node3D)


@export var threshold_voltage: float = 2.0 : set = set_threshold_voltage

@export var transconductance_parameter: float = 0.1 : set = set_transconductance_parameter

@onready var terminal_d: Area3D = $TerminalD 
@onready var terminal_g: Area3D = $TerminalG 
@onready var terminal_s: Area3D = $TerminalS 
@onready var info_label: Label3D = $InfoLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D


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

func set_threshold_voltage(value: float):
	var new_vt = clampf(value, 0.1, 10.0) 
	if not is_equal_approx(threshold_voltage, new_vt):
		threshold_voltage = new_vt
		print("NChannelMOSFET3D {name} threshold_voltage set to: {vt_str} V".format({"name": name, "vt_str": String.num(threshold_voltage, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif threshold_voltage != new_vt: 
		threshold_voltage = new_vt

func set_transconductance_parameter(value: float):
	var new_kn = max(1e-6, value) 
	if not is_equal_approx(transconductance_parameter, new_kn):
		transconductance_parameter = new_kn
		print("NChannelMOSFET3D {name} transconductance_parameter set to: {kn_str} A/V^2".format({"name": name, "kn_str": String.num_scientific(transconductance_parameter)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif transconductance_parameter != new_kn: 
		transconductance_parameter = new_kn



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


func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = "" 


func reset_visual_state():
	hide_info()
	if is_instance_valid(mesh_instance):
		mesh_instance.material_override = null 



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
	
	var _inline_stamp_conductance = func(matrix_A, g_val, idx1, idx2):
		if idx1 != -1 and idx2 != -1:
			matrix_A[idx1][idx1] += g_val
			matrix_A[idx2][idx2] += g_val
			matrix_A[idx1][idx2] -= g_val
			matrix_A[idx2][idx1] -= g_val
		elif idx1 != -1:
			matrix_A[idx1][idx1] += g_val
		elif idx2 != -1:
			matrix_A[idx2][idx2] += g_val
	
	_inline_stamp_conductance.call(A, G_gate_leakage_const, idx_g, idx_d)
	_inline_stamp_conductance.call(A, G_gate_leakage_const, idx_g, idx_s)

	if region_nmos_mna_val == "OFF":
		var G_ds_off_const = 1e-9 
		_inline_stamp_conductance.call(A, G_ds_off_const, idx_d, idx_s)
	else:
		
		
		
		var Vg_prev_iter_val = comp_data.properties.get("_internal_Vg_stamp", 0.0) 
		var Vs_prev_iter_val = comp_data.properties.get("_internal_Vs_stamp", 0.0)
		var Vgs_for_model_val = Vg_prev_iter_val - Vs_prev_iter_val

		if region_nmos_mna_val == "TRIODE":
			
			
			
			
			var effective_conductance_triode = kn_nmos_mna_prop * max(0.01, Vgs_for_model_val - vt_nmos_mna_prop)
			
			
			
			
			var R_ds_triode_approx_val = 1.0 / effective_conductance_triode
			if R_ds_triode_approx_val > 1e9: R_ds_triode_approx_val = 1e9
			if R_ds_triode_approx_val < 1e-3: R_ds_triode_approx_val = 1e-3 
			var G_ds_triode_val = 1.0 / R_ds_triode_approx_val
			_inline_stamp_conductance.call(A, G_ds_triode_val, idx_d, idx_s)
			
		elif region_nmos_mna_val == "SATURATION":
			
			
			
			
			
			var Id_sat_calc_val = 0.0
			if Vgs_for_model_val > vt_nmos_mna_prop:
				Id_sat_calc_val = 0.5 * kn_nmos_mna_prop * pow(Vgs_for_model_val - vt_nmos_mna_prop, 2.0)
			
			
			if idx_d != -1: b[idx_d] -= Id_sat_calc_val 
			if idx_s != -1: b[idx_s] += Id_sat_calc_val 
			
			
			
			
