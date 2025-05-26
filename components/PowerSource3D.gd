extends Node3D

class_name PowerSource3D


@export var target_voltage: float = 5.0

@export var target_current: float = 1.0


@onready var terminal_pos: Area3D = $TerminalPositive
@onready var terminal_neg: Area3D = $TerminalNegative
@onready var current_label: Label3D = $CurrentLabel

func _ready():
	if not current_label:
		printerr("PowerSource3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false



func show_current(actual_current: float, actual_voltage: float, operating_mode: String = "CV"):
	if not current_label: return

	var current_str = "N/A"
	var disp_current: float = NAN 

	if not is_nan(actual_current):
		disp_current = -actual_current 
		
		if abs(disp_current) < 1e-3 and abs(disp_current) > 1e-12: 
			current_str = "{val_str} µA".format({"val_str": String.num(disp_current * 1e6, 2)})
		elif abs(disp_current) < 1.0: 
			current_str = "{val_str} mA".format({"val_str": String.num(disp_current * 1e3, 2)})
		else:
			current_str = "{val_str} A".format({"val_str": String.num(disp_current, 2)})

	var voltage_str = "N/A"
	if not is_nan(actual_voltage):
		voltage_str = "{val_str} V".format({"val_str": String.num(actual_voltage, 2)})
	
	var op_mode_str: String
	if operating_mode == "CV":
		op_mode_str = "CV Mode"
		if not is_nan(actual_current):
			var disp_cv_current = -actual_current 
			if abs(disp_cv_current) < 1e-3 and abs(disp_cv_current) > 1e-12:
				current_str = "{val_str} µA".format({"val_str": String.num(disp_cv_current * 1e6, 2)})
			elif abs(disp_cv_current) < 1.0:
				current_str = "{val_str} mA".format({"val_str": String.num(disp_cv_current * 1e3, 2)})
			else:
				current_str = "{val_str} A".format({"val_str": String.num(disp_cv_current, 2)})
		if not is_nan(actual_voltage) and not is_nan(target_voltage) and \
		   abs(actual_voltage - target_voltage) > 0.1 * abs(target_voltage) + 0.1 : 
			if abs(actual_current) > target_current + 1e-9: 
				op_mode_str = "CV (Overload?)"


	elif operating_mode == "CC":
		op_mode_str = "CC Limiting"
		if not is_nan(actual_current):
			var disp_cc_current = actual_current 
			if abs(disp_cc_current) < 1e-3 and abs(disp_cc_current) > 1e-12:
				current_str = "{val_str} µA".format({"val_str": String.num(disp_cc_current * 1e6, 2)})
			elif abs(disp_cc_current) < 1.0:
				current_str = "{val_str} mA".format({"val_str": String.num(disp_cc_current * 1e3, 2)})
			else:
				current_str = "{val_str} A".format({"val_str": String.num(disp_cc_current, 2)})
		current_str += " (Limit)"
	else: 
		op_mode_str = operating_mode 

	current_label.text = "{op_mode}: {curr_str} @ {volt_str}".format({"op_mode": op_mode_str, "curr_str": current_str, "volt_str": voltage_str})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false

# -------------------------------------------------------------------------
# MNA‐stamping interface
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary, # This is active_vs_id_to_matrix_index
	inductor_map: Dictionary, # Unused by PowerSource
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for op_mode, target_voltage, target_current, cc_current_direction_sign
	delta_time: float # Unused by PowerSource
):
	var ps_op_mode = comp_data.properties.get("current_operating_mode", "CV")
	
	var pos_term_id = terminal_pos.get_instance_id() if is_instance_valid(terminal_pos) else -1
	var neg_term_id = terminal_neg.get_instance_id() if is_instance_valid(terminal_neg) else -1

	var pos_node_lookup_id = terminal_connections.get(pos_term_id, -1)
	var neg_node_lookup_id = terminal_connections.get(neg_term_id, -1)

	var pos_idx = node_map.get(pos_node_lookup_id, -1)
	var neg_idx = node_map.get(neg_node_lookup_id, -1)

	if ps_op_mode == "CV":
		var ps_instance_id = self.get_instance_id()
		if not vs_map.has(ps_instance_id):
			printerr("Critical Error: PowerSource {psid} in CV mode not found in vs_map.".format({"psid": ps_instance_id}))
			return
		var ps_current_matrix_idx = vs_map[ps_instance_id]
		var V_target = comp_data.properties["target_voltage"] # From comp_data as per original
		
		b[ps_current_matrix_idx] = V_target
		if pos_idx != -1:
			A[ps_current_matrix_idx][pos_idx] = 1.0
			A[pos_idx][ps_current_matrix_idx] = 1.0
		if neg_idx != -1:
			A[ps_current_matrix_idx][neg_idx] = -1.0
			A[neg_idx][ps_current_matrix_idx] = -1.0
			
	elif ps_op_mode == "CC":
		var I_target = comp_data.properties["target_current"] # From comp_data
		var direction_sign = comp_data.properties.get("cc_current_direction_sign", 1.0) # From comp_data
		var actual_current_to_stamp = direction_sign * I_target
		
		if pos_idx != -1:
			b[pos_idx] += actual_current_to_stamp # Current source: current enters positive node
		if neg_idx != -1:
			b[neg_idx] -= actual_current_to_stamp # Current source: current leaves negative node
