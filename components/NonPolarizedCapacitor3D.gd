extends Node3D

class_name NonPolarizedCapacitor3D

## Signal emitted when the configuration value changes.
signal configuration_changed(component_node: Node3D)

## Capacitance in Farads (F).
@export var capacitance: float = 1.0e-6 : set = set_capacitance # Default to 1uF
## Maximum voltage rating in Volts (V).
@export var max_voltage: float = 400.0 : set = set_max_voltage # Default to 400V

@onready var terminal1: Area3D = $Terminal1
@onready var terminal2: Area3D = $Terminal2
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal1 or not terminal2:
		printerr("NonPolarizedCapacitor3D requires child Area3D nodes named 'Terminal1' and 'Terminal2'.")
	if not info_label:
		printerr("NonPolarizedCapacitor3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	# Ensure initial values are validated by setters
	set_capacitance(capacitance)
	set_max_voltage(max_voltage)

func set_capacitance(value: float):
	var new_cap = max(1e-12, value) # Capacitance must be positive, 1pF minimum
	if not is_equal_approx(capacitance, new_cap):
		capacitance = new_cap
		print("NonPolarizedCapacitor {cap_name} capacitance set to: {cap_str} F".format({"cap_name": name, "cap_str": String.num_scientific(capacitance)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif capacitance != new_cap: # Handles initial NaN or if value was outside max()
		capacitance = new_cap


func set_max_voltage(value: float):
	var new_max_v = max(0.1, value) # Max voltage must be positive, 0.1V minimum
	if not is_equal_approx(max_voltage, new_max_v):
		max_voltage = new_max_v
		print("NonPolarizedCapacitor {cap_name} max_voltage set to: {max_v_str} V".format({"cap_name": name, "max_v_str": String.num(max_voltage, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif max_voltage != new_max_v: # Handles initial NaN or if value was outside max()
		max_voltage = new_max_v


## Shows current and voltage across the capacitor.
## voltage_value is V(T1) - V(T2).
func show_info(current_value: float, voltage_value: float):
	if not info_label: return
	info_label.modulate = Color.WHITE # Default color

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
		# Optionally, add a visual warning if voltage exceeds max_voltage, without "exploding"
		if abs(voltage_value) > max_voltage:
			voltage_str += " (OVER!)"
			info_label.modulate = Color.ORANGE # Warning color
		
	info_label.text = "{v_str}\n{c_str}".format({"v_str": voltage_str, "c_str": current_str})
	info_label.visible = true

## Hides all info display (V, I).
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = "" # Clear text
	info_label.modulate = Color.WHITE # Reset color

## Resets the visual state of the capacitor (info hidden).
func reset_visual_state():
	hide_info()
