extends Node3D

class_name Relay3D


signal configuration_changed(component_node: Node3D)


@export var signal_voltage_threshold: float = 2.5 : set = set_signal_voltage_threshold

@export var coil_resistance: float = 100.0 : set = set_coil_resistance

var is_energized: bool = false

@onready var terminal_vcc: Area3D = $TerminalVCC         
@onready var terminal_gnd: Area3D = $TerminalGND         
@onready var terminal_signal: Area3D = $TerminalSignal   
@onready var terminal_com: Area3D = $TerminalCOM         
@onready var terminal_no: Area3D = $TerminalNO           
@onready var terminal_nc: Area3D = $TerminalNC           
@onready var info_label: Label3D = $InfoLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D 

func _ready():
	if not terminal_vcc or not terminal_gnd or not terminal_signal or \
	   not terminal_com or not terminal_no or not terminal_nc:
		printerr("Relay3D requires child Area3D nodes: 'TerminalVCC', 'TerminalGND', 'TerminalSignal', 'TerminalCOM', 'TerminalNO', 'TerminalNC'.")
	if not info_label:
		printerr("Relay3D requires a child Label3D named 'InfoLabel'.")
	if not mesh_instance:
		printerr("Relay3D requires a child MeshInstance3D named 'MeshInstance3D'.")
	
	reset_visual_state()
	set_signal_voltage_threshold(signal_voltage_threshold)
	set_coil_resistance(coil_resistance)

func set_signal_voltage_threshold(value: float):
	var new_threshold = max(0.1, value) 
	if not is_equal_approx(signal_voltage_threshold, new_threshold):
		signal_voltage_threshold = new_threshold
		print("Relay3D {r_name} signal_voltage_threshold set to: {th_val} V".format({"r_name": name, "th_val": String.num(signal_voltage_threshold, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif signal_voltage_threshold != new_threshold: 
		signal_voltage_threshold = new_threshold

func set_coil_resistance(value: float):
	var new_resistance = max(1.0, value) 
	if not is_equal_approx(coil_resistance, new_resistance):
		coil_resistance = new_resistance
		print("Relay3D {r_name} coil_resistance set to: {cr_val} Ω".format({"r_name": name, "cr_val": String.num(coil_resistance, 1)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif coil_resistance != new_resistance: 
		coil_resistance = new_resistance




func show_info(results: Dictionary):
	if not info_label: return

	var sig_v_str = "Sig V: N/A"
	if results.has("signal_voltage") and not is_nan(results.signal_voltage):
		sig_v_str = "Sig V: {val_str} V".format({"val_str": String.num(results.signal_voltage, 2)})

	var vcc_v_str = "VCC: N/A"
	if results.has("vcc_voltage") and not is_nan(results.vcc_voltage):
		vcc_v_str = "VCC: {val_str} V".format({"val_str": String.num(results.vcc_voltage, 2)})

	var state_str = "State: N/A"
	var energized_state_from_results = results.get("is_energized", false)
	self.is_energized = energized_state_from_results

	if energized_state_from_results:
		state_str = "State: Energized (COM-NO)"
		if is_instance_valid(mesh_instance) and mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color.DARK_GREEN
		elif is_instance_valid(mesh_instance):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.DARK_GREEN
			mesh_instance.material_override = mat
	else:
		state_str = "State: De-energized (COM-NC)"
		if is_instance_valid(mesh_instance) and mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color(0.4, 0.4, 0.5, 1) 
		elif is_instance_valid(mesh_instance):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 0.4, 0.5, 1)
			mesh_instance.material_override = mat


	var threshold_str = "Sig Thresh: N/A"
	if results.has("signal_threshold") and not is_nan(results.signal_threshold):
		threshold_str = "Sig Thresh: {val_str} V".format({"val_str": String.num(results.signal_threshold, 2)})
	else: 
		threshold_str = "Sig Thresh: {val_str} V".format({"val_str": String.num(signal_voltage_threshold, 2)})

	var coil_i_str = "Coil I: N/A" 
	if results.has("coil_current") and not is_nan(results.coil_current):
		coil_i_str = "Coil I: {val_str}".format({"val_str": _format_current(results.coil_current)})
		
	info_label.text = "{vcc_str}, {sig_str}\n{st_str}, {th_str}\n{ci_str}".format({
		"vcc_str": vcc_v_str, "sig_str": sig_v_str, 
		"st_str": state_str, "th_str": threshold_str, 
		"ci_str": coil_i_str
		})
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
	is_energized = false
	if is_instance_valid(mesh_instance):
		if mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color(0.4, 0.4, 0.5, 1) 
		else:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 0.4, 0.5, 1)
			mesh_instance.material_override = mat
