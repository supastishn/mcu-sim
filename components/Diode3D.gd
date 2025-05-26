extends Node3D

class_name Diode3D


@export var forward_voltage: float = 0.7

@onready var terminal_anode: Area3D = $TerminalAnode 
@onready var terminal_kathode: Area3D = $TerminalKathode 
@onready var diode_mesh_instance: MeshInstance3D = $MeshInstance3D 
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
	var on = comp_data.get("conducting", false)
	var R_on = CircuitGraph.R_DIODE_ON 
	var R_off = CircuitGraph.R_DIODE_OFF 
	var g = 1.0 / (R_on if on else R_off)

	var anode_instance_id = terminal_anode.get_instance_id()
	var kathode_instance_id = terminal_kathode.get_instance_id()

	var na = terminal_connections.get(anode_instance_id, -1)
	var nk = terminal_connections.get(kathode_instance_id, -1)

	var ia = node_map.get(na, -1)
	var ik = node_map.get(nk, -1)

	if on:
		var Vf = forward_voltage 
		var offset_val = Vf / R_on 
		if ia != -1: b[ia] += offset_val
		if ik != -1: b[ik] -= offset_val
	
	
	if ia != -1 and ik != -1:
		A[ia][ia] += g
		A[ik][ik] += g
		A[ia][ik] -= g
		A[ik][ia] -= g
	elif ia != -1:
		A[ia][ia] += g
	elif ik != -1:
		A[ik][ik] += g
