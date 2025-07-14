extends Control

class_name VirtualJoystick

## Emitted when the joystick is moved. Provides the direction vector and intensity (0.0 to 1.0).
signal joystick_updated(direction: Vector2, intensity: float)
## Emitted when the joystick is released.
signal joystick_released()

## The radius of the joystick's outer boundary.
@export var boundary_radius: float = 50.0 
## The radius of the inner dead zone where input is ignored.
@export var dead_zone_radius: float = 10.0 
## The speed at which the knob returns to the center when released.
@export var return_to_center_speed: float = 15.0 

## Reference to the TextureRect node for the joystick knob.
@onready var knob: TextureRect = $Knob

## The touch event index currently controlling this joystick.
var _touch_index: int = -1
## The current direction vector of the joystick.
var _current_direction: Vector2 = Vector2.ZERO
## The current intensity (magnitude) of the joystick input.
var _current_intensity: float = 0.0

## Called when the node enters the scene tree. Initializes the joystick.
func _ready():
	_reset_knob()
	knob.pivot_offset = knob.size / 2

## Resets the joystick knob to its center position and emits the released signal.
func _reset_knob():
	knob.position = size / 2 - knob.size / 2
	_current_direction = Vector2.ZERO
	_current_intensity = 0.0
	_touch_index = -1
	emit_signal("joystick_released")

## Handles GUI input events for touch and drag to control the joystick.
func _gui_input(event: InputEvent):
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if (event.position - size / 2).length() < boundary_radius * 1.5: 
				_touch_index = event.index
				_update_joystick(event.position)
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_reset_knob()
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_joystick(event.position)
		get_viewport().set_input_as_handled()

## Updates the joystick's state based on the touch position.
func _update_joystick(touch_pos: Vector2):
	var relative_pos = touch_pos - size / 2
	var length = relative_pos.length()

	if length < dead_zone_radius:
		_current_direction = Vector2.ZERO
		_current_intensity = 0.0
		knob.position = size / 2 - knob.size / 2 
	else:
		_current_direction = relative_pos.normalized()
		_current_intensity = min(1.0, (length - dead_zone_radius) / (boundary_radius - dead_zone_radius))
		var clamped_pos = size / 2 + _current_direction * min(length, boundary_radius)
		knob.position = clamped_pos - knob.size / 2 

	emit_signal("joystick_updated", _current_direction, _current_intensity)
