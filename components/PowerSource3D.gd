extends Node3D

class_name PowerSource3D

## The target voltage value in Volts.
@export var target_voltage: float = 5.0
## The target current limit value in Amps.
@export var target_current: float = 1.0


# Add terminal references if needed
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
	var disp_current: float = NAN # Declare disp_current at function scope

	if not is_nan(actual_current):
		# MNA result for current through a voltage source is positive if consuming, negative if supplying.
		# We want to display positive current as supplying.
		disp_current = -actual_current # Assign value here
		
		if abs(disp_current) < 1e-3 and abs(disp_current) > 1e-12: # Between 1uA and 1mA
			current_str = "{val_str} µA".format({"val_str": String.num(disp_current * 1e6, 2)})
		elif abs(disp_current) < 1.0: # Between 1mA and 1A
			current_str = "{val_str} mA".format({"val_str": String.num(disp_current * 1e3, 2)})
		else:
			current_str = "{val_str} A".format({"val_str": String.num(disp_current, 2)})

	var voltage_str = "N/A"
	if not is_nan(actual_voltage):
		voltage_str = "{val_str} V".format({"val_str": String.num(actual_voltage, 2)})
	
	var op_mode_str: String
	if operating_mode == "CV":
		op_mode_str = "CV Mode"
		# Format current normally for CV mode
		if not is_nan(actual_current):
			var disp_cv_current = -actual_current # Positive for supplying
			if abs(disp_cv_current) < 1e-3 and abs(disp_cv_current) > 1e-12:
				current_str = "{val_str} µA".format({"val_str": String.num(disp_cv_current * 1e6, 2)})
			elif abs(disp_cv_current) < 1.0:
				current_str = "{val_str} mA".format({"val_str": String.num(disp_cv_current * 1e3, 2)})
			else:
				current_str = "{val_str} A".format({"val_str": String.num(disp_cv_current, 2)})
		# If actual_voltage is significantly different from target_voltage in CV mode, it might indicate overload
		# but the mode itself is still "CV" as decided by the graph. We trust the graph's mode.
		if not is_nan(actual_voltage) and not is_nan(target_voltage) and \
		   abs(actual_voltage - target_voltage) > 0.1 * abs(target_voltage) + 0.1 : # e.g. > 10% + 0.1V deviation
			if abs(actual_current) > target_current + 1e-9: # Check if current is also over limit
				op_mode_str = "CV (Overload?)"


	elif operating_mode == "CC":
		op_mode_str = "CC Limiting"
		# In CC mode, current should be the target_current (signed appropriately for display)
		# actual_current from graph for a CC source is already the set current.
		if not is_nan(actual_current):
			var disp_cc_current = actual_current # Graph gives supplied current for CC source
			if abs(disp_cc_current) < 1e-3 and abs(disp_cc_current) > 1e-12:
				current_str = "{val_str} µA".format({"val_str": String.num(disp_cc_current * 1e6, 2)})
			elif abs(disp_cc_current) < 1.0:
				current_str = "{val_str} mA".format({"val_str": String.num(disp_cc_current * 1e3, 2)})
			else:
				current_str = "{val_str} A".format({"val_str": String.num(disp_cc_current, 2)})
		current_str += " (Limit)"
	else: # Unknown mode from graph
		op_mode_str = operating_mode # Display whatever was passed

	current_label.text = "{op_mode}: {curr_str} @ {volt_str}".format({"op_mode": op_mode_str, "curr_str": current_str, "volt_str": voltage_str})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false
