extends Node3D

class_name LED3D

## The approximate forward voltage drop required to light the LED.
@export var forward_voltage: float = 2.0
## The color the LED should emit when lit.
@export var led_color: Color = Color.RED
## Minimum current (Amps) required for the LED to light up.
@export var min_current_to_light: float = 0.015 # 15mA
## Maximum current (Amps) the LED can handle before burning out.
@export var max_current_before_burn: float = 0.040 # 40mA
## Minimum emission energy multiplier when LED is barely lit.
@export var min_emission_multiplier: float = 0.5
## Maximum emission energy multiplier when LED is at max safe current.
@export var max_emission_multiplier: float = 2.0


@onready var terminal_anode: Area3D = $TerminalAnode # Positive side
@onready var terminal_kathode: Area3D = $TerminalKathode # Negative side
@onready var led_mesh_instance: MeshInstance3D = $MeshInstance3D # The visual part of the LED
@onready var burn_label: Label3D = $BurnLabel
@onready var current_label: Label3D = $CurrentLabel

var _original_material: StandardMaterial3D = null
var _lit_material: StandardMaterial3D = null
var is_actually_burned: bool = false # Internal visual state

func _ready():
	if not burn_label:
		printerr("LED3D requires a child Label3D named 'BurnLabel'.")
	else:
		burn_label.visible = false

	if not current_label:
		printerr("LED3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false # Ensure it's hidden initially

	var base_material = led_mesh_instance.material_override if led_mesh_instance.material_override else led_mesh_instance.get_surface_override_material(0)

	if led_mesh_instance and base_material is StandardMaterial3D:
		_original_material = base_material.duplicate() as StandardMaterial3D
		_lit_material = _original_material.duplicate() as StandardMaterial3D
		_lit_material.emission_enabled = true
		_lit_material.emission = led_color
		# emission_energy_multiplier will be set in update_visual_state
	else:
		printerr("LED3D MeshInstance3D needs a StandardMaterial3D assigned in the editor.")
	
	reset_visual_state() # Ensure it starts off correctly

## Updates the visual state of the LED based on current and burned status.
## current: The calculated current flowing through the LED.
## is_logically_burned: Whether the circuit graph considers this LED burned.
func update_visual_state(current: float, p_is_logically_burned: bool):
	is_actually_burned = p_is_logically_burned

	if not burn_label: return # Safety check

	if is_actually_burned: # If the LED is logically burned
		burn_label.visible = true # Ensure the "BURNED!" label is displayed
		if _original_material:
			led_mesh_instance.material_override = _original_material # And ensure the LED itself is not lit
	else: # If the LED is not burned
		burn_label.visible = false # Ensure the "BURNED!" label is hidden
		
		if not _original_material or not _lit_material: # Ensure materials are valid
			if _original_material: # Fallback if materials aren't properly set up
				led_mesh_instance.material_override = _original_material
			return

		if current >= min_current_to_light and not is_nan(current):
			var current_range = max_current_before_burn - min_current_to_light
			var normalized_current_in_range = 0.0
			
			if current_range > 1e-6: # Avoid division by zero if min and max are effectively the same
				normalized_current_in_range = (current - min_current_to_light) / current_range
			elif current >= min_current_to_light: # If range is zero, but current meets min, consider it at min brightness or full if min=max
				normalized_current_in_range = 0.0 # or 1.0 if min_current_to_light == max_current_before_burn

			var clamped_intensity_factor = clampf(normalized_current_in_range, 0.0, 1.0)
			
			_lit_material.emission_energy_multiplier = min_emission_multiplier + clamped_intensity_factor * (max_emission_multiplier - min_emission_multiplier)
			_lit_material.emission = led_color # Ensure color is set (should be from _ready)
			led_mesh_instance.material_override = _lit_material
		else: # Current is too low (or NaN) to light up the LED
			led_mesh_instance.material_override = _original_material


## Resets the LED to its default visual state (off, not burned label).
func reset_visual_state():
	is_actually_burned = false
	if burn_label:
		burn_label.visible = false
	if current_label:
		current_label.visible = false
	if _original_material:
		led_mesh_instance.material_override = _original_material

func show_current(current_value: float):
	if not current_label or is_actually_burned: # Don't show current if burned label is showing
		if current_label: current_label.visible = false
		return

	if is_nan(current_value):
		current_label.text = "I: N/A"
	else:
		if abs(current_value) < 1e-3 and abs(current_value) > 1e-12:
			current_label.text = "I: {val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
		elif abs(current_value) < 1.0:
			current_label.text = "I: {val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
		else:
			current_label.text = "I: {val_str} A".format({"val_str": String.num(current_value, 2)})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false
