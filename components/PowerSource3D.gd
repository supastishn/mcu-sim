extends Node3D

class_name PowerSource3D

## The target voltage value in Volts.
@export var target_voltage: float = 5.0
## The target current limit value in Amps.
@export var target_current: float = 1.0


@onready var terminal_pos: Area3D = $TerminalPositive
@onready var terminal_neg: Area3D = $TerminalNegative
@onready var current_label: Label3D = $CurrentLabel

func _ready():
	if not current_label:
		printerr("PowerSource3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

## Shows current, voltage, and operating mode.
## operating_mode is "CV" or "CC", determined by CircuitGraph.
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
