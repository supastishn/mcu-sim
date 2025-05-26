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
