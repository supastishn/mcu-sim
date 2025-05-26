extends Node3D

class_name Resistor3D


@export var resistance: float = 1000.0

@onready var terminal1: Area3D = $Terminal1
@onready var terminal2: Area3D = $Terminal2
@onready var current_label: Label3D = $CurrentLabel

func _ready():
	if not current_label:
		printerr("Resistor3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

func show_current(current_value: float):
	if not current_label: return
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



func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary, 
	inductor_map: Dictionary, 
	terminal_connections: Dictionary,
	comp_data: Dictionary, 
	delta_time: float 
):
	
	var R = resistance 
	if R == 0.0: R = 1e-9
	var g = 1.0 / R
	
	var t1_instance_id = terminal1.get_instance_id()
	var t2_instance_id = terminal2.get_instance_id()
	
	var n1 = terminal_connections.get(t1_instance_id, -1)
	var n2 = terminal_connections.get(t2_instance_id, -1)
	
	var i1 = node_map.get(n1, -1)
	var i2 = node_map.get(n2, -1)
	
	
	if i1 != -1 and i2 != -1:
		A[i1][i1] += g
		A[i2][i2] += g
		A[i1][i2] -= g
		A[i2][i1] -= g
	elif i1 != -1:
		A[i1][i1] += g
	elif i2 != -1:
		A[i2][i2] += g
