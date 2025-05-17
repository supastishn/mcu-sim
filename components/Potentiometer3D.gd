extends Node3D

class_name Potentiometer3D

## Signal emitted when the wiper position changes.
signal wiper_position_changed(pot_node: Node3D, new_position: float)

## The total resistance of the potentiometer in Ohms.
@export var total_resistance: float = 10000.0

## The wiper position, ranging from 0.0 (fully towards Terminal1) to 1.0 (fully towards Terminal2).
@export var wiper_position: float = 0.5 : set = set_wiper_position

# Terminal references
@onready var terminal1: Area3D = $Terminal1 # Fixed end 1
@onready var terminal2: Area3D = $Terminal2 # Fixed end 2
@onready var terminal_wiper: Area3D = $TerminalWiper # Wiper terminal

@onready var component_body: Area3D = $ComponentBody
@onready var current_label: Label3D = $CurrentLabel

func _ready():
	if not terminal1 or not terminal2 or not terminal_wiper:
		printerr("Potentiometer3D requires child Area3D nodes named 'Terminal1', 'Terminal2', and 'TerminalWiper'.")
	if not component_body:
		printerr("Potentiometer3D requires a child Area3D named 'ComponentBody'.")
	if not current_label:
		printerr("Potentiometer3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false
	# Ensure initial wiper position is applied if set via export
	set_wiper_position(wiper_position)

## Sets the wiper position and emits a signal.
func set_wiper_position(new_pos: float):
	var clamped_pos = clampf(new_pos, 0.0, 1.0)
	if not is_equal_approx(wiper_position, clamped_pos): # Check if it actually changed
		wiper_position = clamped_pos
		print("Potentiometer {pot_name} wiper position set to: {pos_str}".format({"pot_name": name, "pos_str": String.num(wiper_position, 2)}))
		if is_inside_tree(): # Only emit if part of the scene tree
			emit_signal("wiper_position_changed", self, wiper_position)
	elif wiper_position != clamped_pos: # handles initial NaN case
		wiper_position = clamped_pos


# Placeholder for any visual updates based on wiper position, if desired later.
# func _update_visuals():
#   pass

## Shows currents for the two resistive segments.
## current_t1_w: Current from Terminal1 to Wiper.
## current_w_t2: Current from Wiper to Terminal2.
func show_current(current_t1_w: float, current_w_t2: float):
	if not current_label: return
	
	var str_t1_w = "N/A"
	if not is_nan(current_t1_w):
		if abs(current_t1_w) < 1e-3 and abs(current_t1_w) > 1e-12: str_t1_w = "{val_str}µA".format({"val_str": String.num(current_t1_w * 1e6, 2)})
		elif abs(current_t1_w) < 1.0: str_t1_w = "{val_str}mA".format({"val_str": String.num(current_t1_w * 1e3, 2)})
		else: str_t1_w = "{val_str}A".format({"val_str": String.num(current_t1_w, 2)})

	var str_w_t2 = "N/A"
	if not is_nan(current_w_t2):
		if abs(current_w_t2) < 1e-3 and abs(current_w_t2) > 1e-12: str_w_t2 = "{val_str}µA".format({"val_str": String.num(current_w_t2 * 1e6, 2)})
		elif abs(current_w_t2) < 1.0: str_w_t2 = "{val_str}mA".format({"val_str": String.num(current_w_t2 * 1e3, 2)})
		else: str_w_t2 = "{val_str}A".format({"val_str": String.num(current_w_t2, 2)})
		
	current_label.text = "I(T1-W): {val1}\nI(W-T2): {val2}".format({"val1": str_t1_w, "val2": str_w_t2})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false
