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
	
	var R_coil_path_val: float
	var g_coil_path_val: float
	var R_coil_actual_prop = coil_resistance 
	if R_coil_actual_prop <= 1e-9: R_coil_actual_prop = 1e-9

	var vcc_id = terminal_vcc.get_instance_id()
	var gnd_id = terminal_gnd.get_instance_id()
	var node_vcc_lookup = terminal_connections.get(vcc_id, -1)
	var node_gnd_lookup = terminal_connections.get(gnd_id, -1)
	var idx_vcc = node_map.get(node_vcc_lookup, -1)
	var idx_gnd = node_map.get(node_gnd_lookup, -1)

	
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

	
	
	
	
	
	if comp_data.properties["is_energized"]: 
		R_coil_path_val = R_coil_actual_prop
	else:
		R_coil_path_val = CircuitGraph.R_SWITCH_OPEN 
	g_coil_path_val = 1.0 / R_coil_path_val
	_inline_stamp_conductance.call(A, g_coil_path_val, idx_vcc, idx_gnd)

	
	
	var R_signal_in_prop = comp_data.properties["input_signal_resistance"] 
	if R_signal_in_prop <= 1e-9: R_signal_in_prop = 1e-9
	var g_signal_in_val = 1.0 / R_signal_in_prop
	
	var sig_id = terminal_signal.get_instance_id()
	var node_sig_lookup = terminal_connections.get(sig_id, -1)
	var idx_sig = node_map.get(node_sig_lookup, -1)
	_inline_stamp_conductance.call(A, g_signal_in_val, idx_sig, idx_gnd) 

	
	var R_sw_closed_const = CircuitGraph.R_SWITCH_CLOSED
	var g_sw_closed_val = 1.0 / R_sw_closed_const
	var R_sw_open_const = CircuitGraph.R_SWITCH_OPEN
	var g_sw_open_val = 1.0 / R_sw_open_const

	var com_sw_id = terminal_com.get_instance_id()
	var no_sw_id = terminal_no.get_instance_id()
	var nc_sw_id = terminal_nc.get_instance_id()

	var node_com_lookup_sw = terminal_connections.get(com_sw_id, -1)
	var node_no_lookup_sw = terminal_connections.get(no_sw_id, -1)
	var node_nc_lookup_sw = terminal_connections.get(nc_sw_id, -1)

	var idx_com_sw = node_map.get(node_com_lookup_sw, -1)
	var idx_no_sw = node_map.get(node_no_lookup_sw, -1)
	var idx_nc_sw = node_map.get(node_nc_lookup_sw, -1)

	if comp_data.properties["is_energized"]: 
		_inline_stamp_conductance.call(A, g_sw_closed_val, idx_com_sw, idx_no_sw) 
		_inline_stamp_conductance.call(A, g_sw_open_val, idx_com_sw, idx_nc_sw)   
		_inline_stamp_conductance.call(A, g_sw_open_val, idx_no_sw, idx_nc_sw)    
	else: 
		_inline_stamp_conductance.call(A, g_sw_open_val, idx_com_sw, idx_no_sw)     
		_inline_stamp_conductance.call(A, g_sw_closed_val, idx_com_sw, idx_nc_sw)   
		_inline_stamp_conductance.call(A, g_sw_open_val, idx_no_sw, idx_nc_sw)      
	return          # or ‘pass’

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
