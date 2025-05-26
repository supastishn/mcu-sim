extends Node3D

class_name LED3D


@export var forward_voltage: float = 2.0

@export var led_color: Color = Color.RED

@export var min_current_to_light: float = 0.015 

@export var max_current_before_burn: float = 0.040 

@export var min_emission_multiplier: float = 0.5

@export var max_emission_multiplier: float = 2.0


@onready var terminal_anode: Area3D = $TerminalAnode 
@onready var terminal_kathode: Area3D = $TerminalKathode 
@onready var led_mesh_instance: MeshInstance3D = $MeshInstance3D 
@onready var burn_label: Label3D = $BurnLabel
@onready var current_label: Label3D = $CurrentLabel

var _original_material: StandardMaterial3D = null
var _lit_material: StandardMaterial3D = null
var is_actually_burned: bool = false 

func _ready():
	if not burn_label:
		printerr("LED3D requires a child Label3D named 'BurnLabel'.")
	else:
		burn_label.visible = false

	if not current_label:
		printerr("LED3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false 

	var base_material = led_mesh_instance.material_override if led_mesh_instance.material_override else led_mesh_instance.get_surface_override_material(0)

	if led_mesh_instance and base_material is StandardMaterial3D:
		_original_material = base_material.duplicate() as StandardMaterial3D
		_lit_material = _original_material.duplicate() as StandardMaterial3D
		_lit_material.emission_enabled = true
		_lit_material.emission = led_color
	else:
		printerr("LED3D MeshInstance3D needs a StandardMaterial3D assigned in the editor.")
	
	reset_visual_state() 




func update_visual_state(current: float, p_is_logically_burned: bool):
	is_actually_burned = p_is_logically_burned

	if not burn_label: return 

	if is_actually_burned: 
		burn_label.visible = true 
		if _original_material:
			led_mesh_instance.material_override = _original_material 
	else: 
		burn_label.visible = false 
		
		if not _original_material or not _lit_material: 
			if _original_material: 
				led_mesh_instance.material_override = _original_material
			return

		if current >= min_current_to_light and not is_nan(current):
			var current_range = max_current_before_burn - min_current_to_light
			var normalized_current_in_range = 0.0
			
			if current_range > 1e-6: 
				normalized_current_in_range = (current - min_current_to_light) / current_range
			elif current >= min_current_to_light: 
				normalized_current_in_range = 0.0 

			var clamped_intensity_factor = clampf(normalized_current_in_range, 0.0, 1.0)
			
			_lit_material.emission_energy_multiplier = min_emission_multiplier + clamped_intensity_factor * (max_emission_multiplier - min_emission_multiplier)
			_lit_material.emission = led_color 
			led_mesh_instance.material_override = _lit_material
		else: 
			led_mesh_instance.material_override = _original_material



func reset_visual_state():
	is_actually_burned = false
	if burn_label:
		burn_label.visible = false
	if current_label:
		current_label.visible = false
	if _original_material:
		led_mesh_instance.material_override = _original_material

func show_current(current_value: float):
	if not current_label or is_actually_burned: 
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

# -------------------------------------------------------------------------
# MNA‐stamping interface
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary, # Unused by LED
	inductor_map: Dictionary, # Unused by LED
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for 'conducting' and 'is_burned' state
	delta_time: float # Unused by LED
):
	var burned = comp_data.get("is_burned", false)
	var on = comp_data.get("conducting", false) and not burned
	var R_on = CircuitGraph.R_LED_ON # Accessing const from CircuitGraph
	var R_off = CircuitGraph.R_LED_OFF # Accessing const from CircuitGraph
	var g = 1.0 / (R_on if on else R_off)
	
	var anode_id = terminal_anode.get_instance_id()
	var kathode_id = terminal_kathode.get_instance_id()
	
	var na = terminal_connections.get(anode_id, -1)
	var nk = terminal_connections.get(kathode_id, -1)
	
	var ia = node_map.get(na, -1)
	var ik = node_map.get(nk, -1)
	
	if on:
		var Vf = forward_voltage # Direct access to exported property
		var offset = Vf / R_on
		if ia != -1: b[ia] += offset
		if ik != -1: b[ik] -= offset
	
	# Inlined _stamp_conductance(A, g, ia, ik)
	if ia != -1 and ik != -1:
		A[ia][ia] += g
		A[ik][ik] += g
		A[ia][ik] -= g
		A[ik][ia] -= g
	elif ia != -1:
		A[ia][ia] += g
	elif ik != -1:
		A[ik][ik] += g
