extends Node3D

class_name Resistor3D

## The resistance value in Ohms.
@export var resistance: float = 1000.0

# Add references to terminals if needed later e.g. for highlighting
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
		if abs(current_value) < 1e-3 and abs(current_value) > 1e-12: # Between 1uA and 1mA
			current_label.text = "I: {val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
		elif abs(current_value) < 1.0: # Between 1mA and 1A
			current_label.text = "I: {val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
		else:
			current_label.text = "I: {val_str} A".format({"val_str": String.num(current_value, 2)})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false
