extends Node3D

class_name Inductor3D

## Signal emitted when the configuration value changes.
signal configuration_changed(component_node: Node3D)

## Inductance in Henries (H).
@export var inductance: float = 1.0e-3 : set = set_inductance # Default to 1mH

@onready var terminal1: Area3D = $Terminal1
@onready var terminal2: Area3D = $Terminal2
@onready var info_label: Label3D = $InfoLabel # To display L, I, V

func _ready():
	if not terminal1 or not terminal2:
		printerr("Inductor3D requires child Area3D nodes named 'Terminal1' and 'Terminal2'.")
	if not info_label:
		printerr("Inductor3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	# Ensure initial inductance is validated
	set_inductance(inductance)

func set_inductance(value: float):
	var new_L = max(1e-9, value) # Inductance must be positive, 1nH minimum
	if not is_equal_approx(inductance, new_L):
		inductance = new_L
		print("Inductor3D {ind_name} inductance set to: {l_str} H".format({"ind_name": name, "l_str": String.num_scientific(inductance)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif inductance != new_L: # Handles initial NaN or if value was outside max()
		inductance = new_L


## Shows current, voltage across the inductor.
## current_value is I_L(t).
## voltage_value is V_L(t) = V(T1) - V(T2).
func show_info(current_value: float, voltage_value: float):
	if not info_label: return
	info_label.modulate = Color.WHITE

	var current_str = "I: N/A"
	if not is_nan(current_value):
		if abs(current_value) < 1e-3 and abs(current_value) > 1e-12: # Between 1uA and 1mA
			current_str = "I: {val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
		elif abs(current_value) < 1.0: # Between 1mA and 1A
			current_str = "I: {val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
		else:
			current_str = "I: {val_str} A".format({"val_str": String.num(current_value, 2)})
	
	var voltage_str = "V: N/A"
	if not is_nan(voltage_value):
		voltage_str = "V: {val_str} V".format({"val_str": String.num(voltage_value, 2)})
		
	info_label.text = "{v_str}\n{c_str}".format({"v_str": voltage_str, "c_str": current_str})
	info_label.visible = true

func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

func reset_visual_state():
	hide_info()
