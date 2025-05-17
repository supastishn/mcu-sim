extends Control

class_name VirtualJoystick

# Signals
signal joystick_updated(direction: Vector2, intensity: float)
signal joystick_released()

# Export variables for customization
@export var boundary_radius: float = 50.0 # How far the knob can move from the center
@export var dead_zone_radius: float = 10.0 # Radius within which input is considered zero
@export var return_to_center_speed: float = 15.0 # How quickly the knob snaps back (0 for instant)

@onready var knob: TextureRect = $Knob

var _touch_index: int = -1
var _start_position: Vector2 = Vector2.ZERO
var _current_direction: Vector2 = Vector2.ZERO
var _current_intensity: float = 0.0

func _ready():
	# Ensure the knob starts at the center
	_reset_knob()
	# Use global position for touch events relative to viewport
	_start_position = global_position + size / 2
	knob.pivot_offset = knob.size / 2

func _reset_knob():
	knob.position = size / 2 - knob.size / 2
	_current_direction = Vector2.ZERO
	_current_intensity = 0.0
	_touch_index = -1
	emit_signal("joystick_released")

func _gui_input(event: InputEvent):
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			# Check if the touch is within the joystick's boundary (or maybe a larger activation area)
			if (event.position - size / 2).length() < boundary_radius * 1.5: # Allow slightly larger activation area
				_touch_index = event.index
				_update_joystick(event.position)
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_reset_knob()
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_joystick(event.position)
		get_viewport().set_input_as_handled()

func _update_joystick(touch_pos: Vector2):
	var relative_pos = touch_pos - size / 2
	var length = relative_pos.length()

	if length < dead_zone_radius:
		_current_direction = Vector2.ZERO
		_current_intensity = 0.0
		knob.position = size / 2 - knob.size / 2 # Snap to center within deadzone
	else:
		_current_direction = relative_pos.normalized()
		# Clamp intensity between 0 and 1 based on distance relative to boundary
		_current_intensity = min(1.0, (length - dead_zone_radius) / (boundary_radius - dead_zone_radius))
		# Clamp knob position to boundary
		var clamped_pos = size / 2 + _current_direction * min(length, boundary_radius)
		knob.position = clamped_pos - knob.size / 2 # Adjust for knob anchor/origin

	emit_signal("joystick_updated", _current_direction, _current_intensity)
