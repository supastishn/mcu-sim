extends Node3D

class_name Potentiometer3D


signal wiper_position_changed(pot_node: Node3D, new_position: float)


@export var total_resistance: float = 10000.0


@export var wiper_position: float = 0.5 : set = set_wiper_position

@onready var terminal1: Area3D = $Terminal1 
@onready var terminal2: Area3D = $Terminal2 
@onready var terminal_wiper: Area3D = $TerminalWiper 

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
	set_wiper_position(wiper_position)


func set_wiper_position(new_pos: float):
	var clamped_pos = clampf(new_pos, 0.0, 1.0)
	if not is_equal_approx(wiper_position, clamped_pos): 
		wiper_position = clamped_pos
		print("Potentiometer {pot_name} wiper position set to: {pos_str}".format({"pot_name": name, "pos_str": String.num(wiper_position, 2)}))
		if is_inside_tree(): 
			emit_signal("wiper_position_changed", self, wiper_position)
	elif wiper_position != clamped_pos: 
		wiper_position = clamped_pos






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
