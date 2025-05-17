extends Node3D

class_name Diode3D

## The approximate forward voltage drop.
@export var forward_voltage: float = 0.7

@onready var terminal_anode: Area3D = $TerminalAnode # Positive side
@onready var terminal_kathode: Area3D = $TerminalKathode # Negative side
@onready var diode_mesh_instance: MeshInstance3D = $MeshInstance3D # The visual part of the Diode
@onready var current_label: Label3D = $CurrentLabel

func _ready():
	if not current_label:
		printerr("Diode3D requires a child Label3D named 'CurrentLabel'.")
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
