extends Node3D

class_name ZenerDiode3D


signal configuration_changed(component_node: Node3D)


@export var forward_voltage: float = 0.7 : set = set_forward_voltage

@export var zener_voltage: float = 5.1 : set = set_zener_voltage

@onready var terminal_anode: Area3D = $TerminalAnode 
@onready var terminal_kathode: Area3D = $TerminalKathode 
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal_anode or not terminal_kathode:
		printerr("ZenerDiode3D requires child Area3D nodes named 'TerminalAnode' and 'TerminalKathode'.")
	if not info_label:
		printerr("ZenerDiode3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_forward_voltage(forward_voltage)
	set_zener_voltage(zener_voltage)

func set_forward_voltage(value: float):
	var new_vf = max(0.1, value) 
	if not is_equal_approx(forward_voltage, new_vf):
		forward_voltage = new_vf
		print("ZenerDiode3D {name} forward_voltage set to: {vf_str} V".format({"name": name, "vf_str": String.num(forward_voltage, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif forward_voltage != new_vf: 
		forward_voltage = new_vf

func set_zener_voltage(value: float):
	var new_vz = max(0.1, value) 
	if not is_equal_approx(zener_voltage, new_vz):
		zener_voltage = new_vz
		print("ZenerDiode3D {name} zener_voltage set to: {vz_str} V".format({"name": name, "vz_str": String.num(zener_voltage, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif zener_voltage != new_vz: 
		zener_voltage = new_vz



func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var current_val = results.get("current", NAN) 
	var voltage_ak_val = results.get("voltage_ak", NAN) 
	var state_val = results.get("state", "N/A")

	var current_str = "I: N/A"
	if not is_nan(current_val):
		if abs(current_val) < 1e-6 and abs(current_val) > 1e-15 : 
			current_str = "I: {val_str} nA".format({"val_str": String.num(current_val * 1e9, 2)})
		elif abs(current_val) < 1e-3 and abs(current_val) > 1e-12: 
			current_str = "I: {val_str} µA".format({"val_str": String.num(current_val * 1e6, 2)})
		elif abs(current_val) < 1.0: 
			current_str = "I: {val_str} mA".format({"val_str": String.num(current_val * 1e3, 2)})
		else: 
			current_str = "I: {val_str} A".format({"val_str": String.num(current_val, 2)})

	var voltage_str = "Vak: N/A" 
	if not is_nan(voltage_ak_val):
		voltage_str = "Vak: {val_str} V".format({"val_str": String.num(voltage_ak_val, 2)})
		
	info_label.text = "State: {s}\n{v_str}\n{c_str}".format({"s": state_val, "v_str": voltage_str, "c_str": current_str})
	info_label.visible = true

func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

func reset_visual_state():
	hide_info()
