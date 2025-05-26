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

# -------------------------------------------------------------------------
# MNA‐stamping interface
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary, # Unused by ZenerDiode
	inductor_map: Dictionary, # Unused by ZenerDiode
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for operating_state, forward_voltage, zener_voltage
	delta_time: float # Unused by ZenerDiode
):
	var state_zener_val = comp_data.properties["operating_state"]
	var Vf_zener_model_prop = forward_voltage # Direct access to exported property
	var Vz_zener_model_prop = zener_voltage   # Direct access

	var a_id = terminal_anode.get_instance_id() if is_instance_valid(terminal_anode) else -1
	var k_id = terminal_kathode.get_instance_id() if is_instance_valid(terminal_kathode) else -1

	var node_a_lookup = terminal_connections.get(a_id, -1)
	var node_k_lookup = terminal_connections.get(k_id, -1)

	var idx_a = node_map.get(node_a_lookup, -1)
	var idx_k = node_map.get(node_k_lookup, -1)

	var R_on_model_const = 0.1    # Model parameter for on-resistance
	var G_on_model_val = 1.0 / R_on_model_const
	var R_off_model_const = 1.0e9 # Model parameter for off-resistance
	var G_off_model_val = 1.0 / R_off_model_const

	# Helper for inlining _stamp_conductance
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

	if state_zener_val == "OFF":
		_inline_stamp_conductance.call(A, G_off_model_val, idx_a, idx_k)
	elif state_zener_val == "FORWARD":
		# Model: Ideal diode with Vf + series Ron
		# I = (Vak - Vf) / Ron  => G*Vak - G*Vf
		_inline_stamp_conductance.call(A, G_on_model_val, idx_a, idx_k)
		var current_offset_fwd_val = G_on_model_val * Vf_zener_model_prop
		# Current flows A to K
		if idx_a != -1: b[idx_a] += current_offset_fwd_val # Current source into Anode
		if idx_k != -1: b[idx_k] -= current_offset_fwd_val # Current source out of Kathode
	elif state_zener_val == "ZENER":
		# Model: Ideal Zener diode with Vz + series Ron (in reverse)
		# I_rev = (Vka - Vz) / Ron => G*Vka - G*Vz
		# Current flows K to A (conventional current is A to K, so I = -I_rev)
		# I = -( (Vk - Va) - Vz ) / Ron = ( (Va - Vk) + Vz ) / Ron
		# I = G*(Va - Vk) + G*Vz
		_inline_stamp_conductance.call(A, G_on_model_val, idx_a, idx_k) # Conductance part
		var current_offset_zener_val = G_on_model_val * Vz_zener_model_prop
		# Current source for Zener voltage. Current flows K to A.
		# For KCL at A: current enters A. For KCL at K: current leaves K.
		# If current I flows A->K: b[idx_a] -= I_offset, b[idx_k] += I_offset
		# Original: b[idx_k_z] += current_offset_zener; b[idx_a_z] -= current_offset_zener
		# This means current_offset_zener is defined as flowing K->A.
		if idx_k != -1: b[idx_k] += current_offset_zener_val # Current source into Kathode
		if idx_a != -1: b[idx_a] -= current_offset_zener_val # Current source out of Anode
