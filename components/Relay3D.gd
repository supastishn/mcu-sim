extends Node3D

class_name Relay3D

## Signal emitted when a configuration value (coil_voltage_threshold, coil_resistance) changes.
signal configuration_changed(component_node: Node3D)

## Voltage across the coil required to energize the relay (Volts).
@export var coil_voltage_threshold: float = 5.0 : set = set_coil_voltage_threshold
## Resistance of the relay coil in Ohms.
@export var coil_resistance: float = 100.0 : set = set_coil_resistance

# Internal state, primarily managed by CircuitGraph based on coil voltage.
# This property in the component script itself is more for reflecting the graph's decision.
var is_energized: bool = false

@onready var terminal_coil_p: Area3D = $TerminalCoilP # Coil Positive
@onready var terminal_coil_n: Area3D = $TerminalCoilN # Coil Negative
@onready var terminal_com: Area3D = $TerminalCOM     # Common
@onready var terminal_no: Area3D = $TerminalNO       # Normally Open
@onready var terminal_nc: Area3D = $TerminalNC       # Normally Closed
@onready var info_label: Label3D = $InfoLabel
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D # For visual feedback if needed

func _ready():
	if not terminal_coil_p or not terminal_coil_n or not terminal_com or not terminal_no or not terminal_nc:
		printerr("Relay3D requires child Area3D nodes: 'TerminalCoilP', 'TerminalCoilN', 'TerminalCOM', 'TerminalNO', 'TerminalNC'.")
	if not info_label:
		printerr("Relay3D requires a child Label3D named 'InfoLabel'.")
	if not mesh_instance:
		printerr("Relay3D requires a child MeshInstance3D named 'MeshInstance3D'.")
	
	reset_visual_state()
	# Ensure initial values are validated and signals potentially emitted
	set_coil_voltage_threshold(coil_voltage_threshold)
	set_coil_resistance(coil_resistance)

func set_coil_voltage_threshold(value: float):
	var new_threshold = max(0.1, value) # Threshold must be positive
	if not is_equal_approx(coil_voltage_threshold, new_threshold):
		coil_voltage_threshold = new_threshold
		print("Relay3D {r_name} coil_voltage_threshold set to: {th_val} V".format({"r_name": name, "th_val": String.num(coil_voltage_threshold, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif coil_voltage_threshold != new_threshold: # Handles initial NaN or if value was outside max()
		coil_voltage_threshold = new_threshold

func set_coil_resistance(value: float):
	var new_resistance = max(1.0, value) # Coil resistance should be positive, practical minimum
	if not is_equal_approx(coil_resistance, new_resistance):
		coil_resistance = new_resistance
		print("Relay3D {r_name} coil_resistance set to: {cr_val} Ω".format({"r_name": name, "cr_val": String.num(coil_resistance, 1)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif coil_resistance != new_resistance: # Handles initial NaN or if value was outside max()
		coil_resistance = new_resistance

## Shows coil voltage, energized state, and threshold.
## results: Dictionary { "coil_voltage": float, "is_energized": bool, "coil_threshold": float, "coil_current": float (optional) }
func show_info(results: Dictionary):
	if not info_label: return

	var coil_v_str = "Coil V: N/A"
	if results.has("coil_voltage") and not is_nan(results.coil_voltage):
		coil_v_str = "Coil V: {val_str} V".format({"val_str": String.num(results.coil_voltage, 2)})

	var state_str = "State: N/A"
	var energized_state_from_results = results.get("is_energized", false) # Default to false if not provided
	self.is_energized = energized_state_from_results # Update internal state for visual feedback

	if energized_state_from_results:
		state_str = "State: Energized (COM-NO)"
		# Optional: Change mesh color or show an indicator
		if is_instance_valid(mesh_instance) and mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color.DARK_GREEN
		elif is_instance_valid(mesh_instance): # Create material if null
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.DARK_GREEN
			mesh_instance.material_override = mat
	else:
		state_str = "State: De-energized (COM-NC)"
		# Optional: Reset mesh color
		if is_instance_valid(mesh_instance) and mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color(0.4, 0.4, 0.5, 1) # Default "off" color
		elif is_instance_valid(mesh_instance):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 0.4, 0.5, 1)
			mesh_instance.material_override = mat


	var threshold_str = "Threshold: N/A"
	# The component itself knows its threshold.
	# threshold_str = "Threshold: {val_str} V".format({"val_str": String.num(coil_voltage_threshold, 2)})
	# It's better if the graph passes the threshold it used, for consistency in display
	if results.has("coil_threshold") and not is_nan(results.coil_threshold):
		threshold_str = "Threshold: {val_str} V".format({"val_str": String.num(results.coil_threshold, 2)})
	else: # Fallback to self if graph doesn't provide it
		threshold_str = "Threshold: {val_str} V".format({"val_str": String.num(coil_voltage_threshold, 2)})

	var coil_i_str = ""
	if results.has("coil_current") and not is_nan(results.coil_current):
		coil_i_str = "\nCoil I: {val_str}".format({"val_str": _format_current(results.coil_current)})
		
	info_label.text = "{cv_str}\n{st_str}\n{th_str}{ci_str}".format({
		"cv_str": coil_v_str, "st_str": state_str, "th_str": threshold_str, "ci_str": coil_i_str
		})
	info_label.visible = true

func _format_current(current_value: float) -> String:
	if abs(current_value) < 1e-6 and abs(current_value) > 1e-15 : # nA to µA (very small)
		return "{val_str} nA".format({"val_str": String.num(current_value * 1e9, 2)})
	elif abs(current_value) < 1e-3 and abs(current_value) >= 1e-12: # µA to mA
		return "{val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
	elif abs(current_value) < 1.0: # mA to A
		return "{val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
	else: # A
		return "{val_str} A".format({"val_str": String.num(current_value, 2)})

func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

func reset_visual_state():
	hide_info()
	is_energized = false # Reset internal state flag
	# Reset mesh color to default "off"
	if is_instance_valid(mesh_instance):
		if mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color(0.4, 0.4, 0.5, 1) # Default "off" color
		else:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 0.4, 0.5, 1)
			mesh_instance.material_override = mat
