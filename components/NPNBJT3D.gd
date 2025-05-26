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
