extends Node3D

class_name Switch3D

## Signal emitted when the switch state changes.
signal state_changed(switch_node: Node3D, new_state: int)

## Represents the switch state.
enum State {
	CONNECTED_NC, # Common connected to Normally Closed
	CONNECTED_NO  # Common connected to Normally Open
}

## The current state of the switch.
@export var current_state: State = State.CONNECTED_NC : set = set_state

# Terminal references
@onready var terminal_com: Area3D = $TerminalCOM
@onready var terminal_nc: Area3D = $TerminalNC
@onready var terminal_no: Area3D = $TerminalNO

# Visual elements
@onready var lever_mesh: MeshInstance3D = $LeverPivot/LeverMesh # Mesh to rotate
@onready var component_body: Area3D = $ComponentBody
@onready var current_label: Label3D = $CurrentLabel

const _LEVER_ANGLE_NC = deg_to_rad(-30.0) # Rotation angle for NC state
const _LEVER_ANGLE_NO = deg_to_rad(30.0)  # Rotation angle for NO state

const MAX_REASONABLE_CURRENT_DISPLAY: float = 1_000_000.0 # 1 MegaAmp

func _ready():
	# Just check that component body exists
	if not component_body:
		printerr("Switch3D requires a child Area3D named 'ComponentBody'.")
	if not current_label:
		printerr("Switch3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

	# Set initial visual state based on exported current_state
	_update_lever_visual()

## Toggles the switch between NC and NO states.
func toggle_state():
	if current_state == State.CONNECTED_NC:
		set_state(State.CONNECTED_NO)
	else:
		set_state(State.CONNECTED_NC)

## Sets the switch state and updates visuals and emits signal.
func set_state(new_state: State):
	if new_state != current_state:
		current_state = new_state
		_update_lever_visual()
		emit_signal("state_changed", self, int(current_state)) # Explicitly cast enum to int
		print("Switch state changed to: {state_key}".format({"state_key": State.keys()[current_state]}))

func _update_lever_visual():
	var target_angle = _LEVER_ANGLE_NC if current_state == State.CONNECTED_NC else _LEVER_ANGLE_NO
	# Assuming the lever mesh should rotate around its parent's X-axis
	if lever_mesh and lever_mesh.get_parent() is Node3D:
		lever_mesh.get_parent().rotation.x = target_angle

func show_current(current_value: float):
	if not current_label: return
	# Current is through the COM terminal and the connected (NC or NO) terminal.
	if is_nan(current_value):
		current_label.text = "I: N/A"
	elif abs(current_value) > MAX_REASONABLE_CURRENT_DISPLAY:
		current_label.text = "I: >1MA (Shorted?)" # Display for very high currents
	else:
		if abs(current_value) < 1e-3 and abs(current_value) > 1e-12: # µA range
			current_label.text = "I: {val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
		elif abs(current_value) < 1.0: # mA range
			current_label.text = "I: {val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
		else: # A range
			current_label.text = "I: {val_str} A".format({"val_str": String.num(current_value, 2)})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false
