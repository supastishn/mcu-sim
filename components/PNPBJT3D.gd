extends Node3D

class_name PNPBJT3D


signal configuration_changed(component_node: Node3D)


@export var beta_dc: float = 100.0 : set = set_beta_dc

@export var veb_on: float = 0.7 : set = set_veb_on

@export var vec_sat: float = 0.2 : set = set_vec_sat

@onready var terminal_e: Area3D = $TerminalE 
@onready var terminal_b: Area3D = $TerminalB 
@onready var terminal_c: Area3D = $TerminalC 
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal_e or not terminal_b or not terminal_c:
		printerr("PNPBJT3D requires child Area3D nodes named 'TerminalE', 'TerminalB', and 'TerminalC'.")
	if not info_label:
		printerr("PNPBJT3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_beta_dc(beta_dc)
	set_veb_on(veb_on)
	set_vec_sat(vec_sat)

func set_beta_dc(value: float):
	var new_beta = max(1.0, value) 
	if not is_equal_approx(beta_dc, new_beta):
		beta_dc = new_beta
		print("PNPBJT {bjt_name} beta_dc set to: {beta_str}".format({"bjt_name": name, "beta_str": String.num(beta_dc, 1)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif beta_dc != new_beta: 
		beta_dc = new_beta

func set_veb_on(value: float): 
	var new_veb = max(0.1, value) 
	if not is_equal_approx(veb_on, new_veb):
		veb_on = new_veb
		print("PNPBJT {bjt_name} veb_on set to: {veb_str} V".format({"bjt_name": name, "veb_str": String.num(veb_on, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif veb_on != new_veb: 
		veb_on = new_veb

func set_vec_sat(value: float): 
	var new_vec_sat = max(0.0, value) 
	if not is_equal_approx(vec_sat, new_vec_sat):
		vec_sat = new_vec_sat
		print("PNPBJT {bjt_name} vec_sat set to: {vec_str} V".format({"bjt_name": name, "vec_str": String.num(vec_sat, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif vec_sat != new_vec_sat: 
		vec_sat = new_vec_sat



func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var ic_str = "Ic: N/A" 
	if results.has("Ic") and not is_nan(results.Ic):
		ic_str = "Ic: {val_str}".format({"val_str": _format_current(results.Ic)})
	
	var ib_str = "Ib: N/A" 
	if results.has("Ib") and not is_nan(results.Ib):
		ib_str = "Ib: {val_str}".format({"val_str": _format_current(results.Ib)})

	var ie_str = "Ie: N/A" 
	if results.has("Ie") and not is_nan(results.Ie):
		ie_str = "Ie: {val_str}".format({"val_str": _format_current(results.Ie)})

	var region_str = "Region: N/A"
	if results.has("region"):
		region_str = "Region: {reg}".format({"reg": results.region})
		
	info_label.text = "{r_str}\n{ic}\n{ib}\n{ie}".format({"r_str": region_str, "ic": ic_str, "ib": ib_str, "ie": ie_str})
	info_label.visible = true

func _format_current(current_value: float) -> String:
	if abs(current_value) < 1e-6 and abs(current_value) > 1e-15 : 
		return "{val_str} nA".format({"val_str": String.num(current_value * 1e9, 2)})
	elif abs(current_value) < 1e-3 and abs(current_value) >= 1e-12: 
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

func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, _x_iter = null, _vs_map_iter = null) -> bool:
	var term_e_pnp = comp_data.terminals["E"]
	var term_b_pnp = comp_data.terminals["B"]
	var term_c_pnp = comp_data.terminals["C"]
	var node_e_id_pnp = circuit.terminal_connections.get(term_e_pnp.get_instance_id(), -1)
	var node_b_id_pnp = circuit.terminal_connections.get(term_b_pnp.get_instance_id(), -1)
	var node_c_id_pnp = circuit.terminal_connections.get(term_c_pnp.get_instance_id(), -1)

	var Ve_pnp = NAN
	if circuit.electrical_nodes.has(node_e_id_pnp): Ve_pnp = circuit.electrical_nodes[node_e_id_pnp].voltage
	var Vb_pnp = NAN
	if circuit.electrical_nodes.has(node_b_id_pnp): Vb_pnp = circuit.electrical_nodes[node_b_id_pnp].voltage
	var Vc_pnp = NAN
	if circuit.electrical_nodes.has(node_c_id_pnp): Vc_pnp = circuit.electrical_nodes[node_c_id_pnp].voltage
	
	var veb_on_pnp_model = comp_data.properties["veb_on"]
	var vec_sat_pnp_model = comp_data.properties["vec_sat"]
	var previous_region_pnp = comp_data.properties["operating_region"]
	var new_region_pnp = previous_region_pnp

	if is_nan(Ve_pnp) or is_nan(Vb_pnp) or is_nan(Vc_pnp):
		new_region_pnp = "OFF"
	else:
		var Veb_pnp = Ve_pnp - Vb_pnp 
		var Vec_pnp = Ve_pnp - Vc_pnp 
		var veb_tolerance_pnp = 1e-5
		
		if Veb_pnp < (veb_on_pnp_model - veb_tolerance_pnp): 
			new_region_pnp = "OFF"
		else: 
			var vec_saturation_check_upper_bound_pnp = vec_sat_pnp_model + circuit.BJT_SATURATION_VOLTAGE_MARGIN
			if Vec_pnp <= vec_saturation_check_upper_bound_pnp: 
				new_region_pnp = "SATURATION"
			else: 
				new_region_pnp = "ACTIVE"
	
	if new_region_pnp != previous_region_pnp:
		comp_data.properties["operating_region"] = new_region_pnp
		return true
	return false

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
	var region_pnp_val = comp_data.properties["operating_region"]
	var beta_pnp_prop = beta_dc 
	var veb_on_model_pnp_prop = veb_on 
	var vec_sat_model_pnp_prop = vec_sat 

	var e_term_id = terminal_e.get_instance_id()
	var b_term_id = terminal_b.get_instance_id()
	var c_term_id = terminal_c.get_instance_id()

	var node_e_lookup_id = terminal_connections.get(e_term_id, -1)
	var node_b_lookup_id = terminal_connections.get(b_term_id, -1)
	var node_c_lookup_id = terminal_connections.get(c_term_id, -1)

	var idx_e = node_map.get(node_e_lookup_id, -1)
	var idx_b = node_map.get(node_b_lookup_id, -1)
	var idx_c = node_map.get(node_c_lookup_id, -1)

	var R_eb_active_model_pnp_const = 50.0  
	var R_ec_sat_model_pnp_const = 5.0    
	var R_pnp_off_model_const = 1.0e9 

	
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

	if region_pnp_val == "OFF":
		var g_off_pnp_val = 1.0 / R_pnp_off_model_const
		_inline_stamp_conductance.call(A, g_off_pnp_val, idx_e, idx_b) 
		_inline_stamp_conductance.call(A, g_off_pnp_val, idx_e, idx_c) 
		_inline_stamp_conductance.call(A, g_off_pnp_val, idx_b, idx_c) 
		
	elif region_pnp_val == "ACTIVE":
		
		var G_eb_active_pnp_val = 1.0 / R_eb_active_model_pnp_const
		var Is_eb_active_pnp_val = veb_on_model_pnp_prop / R_eb_active_model_pnp_const 
		
		if idx_e != -1: A[idx_e][idx_e] += G_eb_active_pnp_val; b[idx_e] += Is_eb_active_pnp_val 
		if idx_b != -1: A[idx_b][idx_b] += G_eb_active_pnp_val; b[idx_b] -= Is_eb_active_pnp_val 
		if idx_e != -1 and idx_b != -1:
			A[idx_e][idx_b] -= G_eb_active_pnp_val
			A[idx_b][idx_e] -= G_eb_active_pnp_val
		
		
		
		
		var Gm_pnp_active = beta_pnp_prop / R_eb_active_model_pnp_const
		var Ic_const_offset_pnp_active = beta_pnp_prop * veb_on_model_pnp_prop / R_eb_active_model_pnp_const

		
		
		
		
		
		
		if idx_e != -1: 
			if idx_e != -1: A[idx_e][idx_e] += Gm_pnp_active 
			if idx_b != -1: A[idx_e][idx_b] -= Gm_pnp_active 
			b[idx_e] += Ic_const_offset_pnp_active 
		if idx_c != -1: 
			if idx_e != -1: A[idx_c][idx_e] -= Gm_pnp_active 
			if idx_b != -1: A[idx_c][idx_b] += Gm_pnp_active 
			b[idx_c] -= Ic_const_offset_pnp_active 

	elif region_pnp_val == "SATURATION":
		
		var G_eb_sat_pnp_val = 1.0 / R_eb_active_model_pnp_const 
		var Is_eb_sat_pnp_val = veb_on_model_pnp_prop / R_eb_active_model_pnp_const
		if idx_e != -1: A[idx_e][idx_e] += G_eb_sat_pnp_val; b[idx_e] += Is_eb_sat_pnp_val
		if idx_b != -1: A[idx_b][idx_b] += G_eb_sat_pnp_val; b[idx_b] -= Is_eb_sat_pnp_val
		if idx_e != -1 and idx_b != -1:
			A[idx_e][idx_b] -= G_eb_sat_pnp_val
			A[idx_b][idx_e] -= G_eb_sat_pnp_val
			
		
		
		var G_ec_sat_pnp_val = 1.0 / R_ec_sat_model_pnp_const
		var Is_ec_sat_pnp_val = vec_sat_model_pnp_prop / R_ec_sat_model_pnp_const 
		if idx_e != -1: A[idx_e][idx_e] += G_ec_sat_pnp_val; b[idx_e] += Is_ec_sat_pnp_val 
		if idx_c != -1: A[idx_c][idx_c] += G_ec_sat_pnp_val; b[idx_c] -= Is_ec_sat_pnp_val 
		if idx_e != -1 and idx_c != -1:
			A[idx_e][idx_c] -= G_ec_sat_pnp_val
			A[idx_c][idx_e] -= G_ec_sat_pnp_val
