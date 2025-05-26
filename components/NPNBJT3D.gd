extends Node3D

class_name NPNBJT3D


signal configuration_changed(component_node: Node3D)


@export var beta_dc: float = 100.0 : set = set_beta_dc

@export var vbe_on: float = 0.7 : set = set_vbe_on

@export var vce_sat: float = 0.2 : set = set_vce_sat

@onready var terminal_c: Area3D = $TerminalC 
@onready var terminal_b: Area3D = $TerminalB 
@onready var terminal_e: Area3D = $TerminalE 
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal_c or not terminal_b or not terminal_e:
		printerr("NPNBJT3D requires child Area3D nodes named 'TerminalC', 'TerminalB', and 'TerminalE'.")
	if not info_label:
		printerr("NPNBJT3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_beta_dc(beta_dc)
	set_vbe_on(vbe_on)
	set_vce_sat(vce_sat)

func set_beta_dc(value: float):
	var new_beta = max(1.0, value) 
	if not is_equal_approx(beta_dc, new_beta):
		beta_dc = new_beta
		print("NPNBJT {bjt_name} beta_dc set to: {beta_str}".format({"bjt_name": name, "beta_str": String.num(beta_dc, 1)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif beta_dc != new_beta: 
		beta_dc = new_beta

func set_vbe_on(value: float):
	var new_vbe = max(0.1, value) 
	if not is_equal_approx(vbe_on, new_vbe):
		vbe_on = new_vbe
		print("NPNBJT {bjt_name} vbe_on set to: {vbe_str} V".format({"bjt_name": name, "vbe_str": String.num(vbe_on, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif vbe_on != new_vbe: 
		vbe_on = new_vbe

func set_vce_sat(value: float):
	var new_vce_sat = max(0.0, value) 
	if not is_equal_approx(vce_sat, new_vce_sat):
		vce_sat = new_vce_sat
		print("NPNBJT {bjt_name} vce_sat set to: {vce_str} V".format({"bjt_name": name, "vce_str": String.num(vce_sat, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif vce_sat != new_vce_sat: 
		vce_sat = new_vce_sat



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
	var term_c = comp_data.terminals["C"]
	var term_b = comp_data.terminals["B"]
	var term_e = comp_data.terminals["E"]
	var node_c_id = circuit.terminal_connections.get(term_c.get_instance_id(), -1)
	var node_b_id = circuit.terminal_connections.get(term_b.get_instance_id(), -1)
	var node_e_id = circuit.terminal_connections.get(term_e.get_instance_id(), -1)

	var Vc = NAN
	if circuit.electrical_nodes.has(node_c_id): Vc = circuit.electrical_nodes[node_c_id].voltage
	var Vb = NAN
	if circuit.electrical_nodes.has(node_b_id): Vb = circuit.electrical_nodes[node_b_id].voltage
	var Ve = NAN
	if circuit.electrical_nodes.has(node_e_id): Ve = circuit.electrical_nodes[node_e_id].voltage
	
	var vbe_on_bjt = comp_data.properties["vbe_on"]
	var vce_sat_bjt = comp_data.properties["vce_sat"]
	var previous_region = comp_data.properties["operating_region"]
	var new_region = previous_region 

	if is_nan(Vb) or is_nan(Ve) or is_nan(Vc):
		new_region = "OFF" 
		# print_debug("  NPNBJT {name} region check: Vb, Ve, or Vc is NaN. Setting to OFF.".format({ "name": comp_data.component_node.name }))
	else:
		var Vbe = Vb - Ve
		var Vce = Vc - Ve
		var vbe_tolerance = 1e-5 
		
		# print_debug("  NPNBJT {name} ({prev_reg}) Check: Vb={vb_s}V, Ve={ve_s}V, Vc={vc_s}V => Vbe={vbe_s}V, Vce={vce_s}V. Thresholds: Vbe_on={vbe_on_s}V, Vce_sat={vce_sat_s}V".format({
		# 	"name": comp_data.component_node.name, "prev_reg": previous_region,
		# 	"vb_s": String.num(Vb,4), "ve_s": String.num(Ve,4), "vc_s": String.num(Vc,4),
		# 	"vbe_s": String.num(Vbe,4), "vce_s": String.num(Vce,4),
		# 	"vbe_on_s": String.num(vbe_on_bjt,4), "vce_sat_s": String.num(vce_sat_bjt,4)
		# }))

		if Vbe < (vbe_on_bjt - vbe_tolerance): 
			new_region = "OFF"
		else: 
			var vce_saturation_check_upper_bound = vce_sat_bjt + circuit.BJT_SATURATION_VOLTAGE_MARGIN
			if Vce <= vce_saturation_check_upper_bound: 
				new_region = "SATURATION"
			else: 
				new_region = "ACTIVE"
	
	if new_region != previous_region:
		comp_data.properties["operating_region"] = new_region
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
	var region = comp_data.properties["operating_region"]
	var beta_val = beta_dc 
	var vbe_on_model_val = vbe_on 
	var vce_sat_model_val = vce_sat 

	var c_id = terminal_c.get_instance_id()
	var b_id = terminal_b.get_instance_id()
	var e_id = terminal_e.get_instance_id()

	var node_c_lookup = terminal_connections.get(c_id, -1)
	var node_b_lookup = terminal_connections.get(b_id, -1)
	var node_e_lookup = terminal_connections.get(e_id, -1)

	var idx_c = node_map.get(node_c_lookup, -1)
	var idx_b = node_map.get(node_b_lookup, -1)
	var idx_e = node_map.get(node_e_lookup, -1)

	var R_be_active_model_const = 50.0  
	var R_ce_sat_model_const = 5.0    
	var R_bjt_off_model_const = 1.0e9 

	
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

	if region == "OFF":
		var g_off = 1.0 / R_bjt_off_model_const
		_inline_stamp_conductance.call(A, g_off, idx_b, idx_e) 
		_inline_stamp_conductance.call(A, g_off, idx_c, idx_e) 
		_inline_stamp_conductance.call(A, g_off, idx_c, idx_b) 
		
	elif region == "ACTIVE":
		
		var G_be_active = 1.0 / R_be_active_model_const
		var Is_be_active = vbe_on_model_val / R_be_active_model_const 
		if idx_b != -1: A[idx_b][idx_b] += G_be_active; b[idx_b] += Is_be_active
		if idx_e != -1: A[idx_e][idx_e] += G_be_active; b[idx_e] -= Is_be_active 
		if idx_b != -1 and idx_e != -1:
			A[idx_b][idx_e] -= G_be_active
			A[idx_e][idx_b] -= G_be_active
		
		
		
		
		
		
		var Gm_bjt_active = beta_val / R_be_active_model_const
		var Ic_const_offset_active = beta_val * vbe_on_model_val / R_be_active_model_const 

		
		
		
		
		
		if idx_c != -1:
			if idx_b != -1: A[idx_c][idx_b] += Gm_bjt_active
			if idx_e != -1: A[idx_c][idx_e] -= Gm_bjt_active
			b[idx_c] += Ic_const_offset_active 
		if idx_e != -1: 
			if idx_b != -1: A[idx_e][idx_b] -= Gm_bjt_active
			if idx_e != -1: A[idx_e][idx_e] += Gm_bjt_active 
			b[idx_e] -= Ic_const_offset_active

	elif region == "SATURATION":
		
		var G_be_sat = 1.0 / R_be_active_model_const 
		var Is_be_sat = vbe_on_model_val / R_be_active_model_const
		if idx_b != -1: A[idx_b][idx_b] += G_be_sat; b[idx_b] += Is_be_sat
		if idx_e != -1: A[idx_e][idx_e] += G_be_sat; b[idx_e] -= Is_be_sat
		if idx_b != -1 and idx_e != -1:
			A[idx_b][idx_e] -= G_be_sat
			A[idx_e][idx_b] -= G_be_sat
			
		
		var G_ce_sat = 1.0 / R_ce_sat_model_const
		var Is_ce_sat = vce_sat_model_val / R_ce_sat_model_const 
		if idx_c != -1: A[idx_c][idx_c] += G_ce_sat; b[idx_c] += Is_ce_sat
		if idx_e != -1: A[idx_e][idx_e] += G_ce_sat; b[idx_e] -= Is_ce_sat 
		if idx_c != -1 and idx_e != -1:
			A[idx_c][idx_e] -= G_ce_sat
			A[idx_e][idx_c] -= G_ce_sat
