extends Node3D

class_name LED3D


## The voltage drop across the LED when conducting, in Volts.
@export var forward_voltage: float = 2.0

## The color of the light emitted by the LED.
@export var led_color: Color = Color.RED

## The minimum forward current required for the LED to start emitting visible light, in Amperes.
@export var min_current_to_light: float = 0.015 

## The maximum forward current the LED can handle before being destroyed, in Amperes.
@export var max_current_before_burn: float = 0.040 

## The emission energy multiplier when the current is at `min_current_to_light`.
@export var min_emission_multiplier: float = 0.5

## The emission energy multiplier when the current is at or above `max_current_before_burn`.
@export var max_emission_multiplier: float = 2.0


## Reference to the Anode terminal Area3D node.
@onready var terminal_anode: Area3D = $TerminalAnode 
## Reference to the Kathode terminal Area3D node.
@onready var terminal_kathode: Area3D = $TerminalKathode 
## Reference to the visual representation (MeshInstance3D) of the LED.
@onready var led_mesh_instance: MeshInstance3D = $MeshInstance3D 
## Reference to the Label3D node for displaying the "burned" message.
@onready var burn_label: Label3D = $BurnLabel
## Reference to the Label3D node for displaying current flow.
@onready var current_label: Label3D = $CurrentLabel

## A copy of the LED's material when it is off.
var _original_material: StandardMaterial3D = null
## A copy of the LED's material, modified to emit light.
var _lit_material: StandardMaterial3D = null
## A flag indicating if the LED has been destroyed by excessive current.
var is_actually_burned: bool = false 

## Called when the node enters the scene tree. Initializes materials and labels.
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

## Updates the LED's conducting state based on the latest voltage solution from an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty():
		return false

	var term_a = comp_data.terminals["A"]
	var term_k = comp_data.terminals["K"]
	var node_a_id = circuit.terminal_connections.get(term_a.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(term_k.get_instance_id(), -1)

	var idx_a = node_map_iter.get(node_a_id, -1)
	var idx_k = node_map_iter.get(node_k_id, -1)

	var Va = x_iter[idx_a] if idx_a != -1 else (0.0 if node_a_id == circuit.ground_node_id else NAN)
	var Vk = x_iter[idx_k] if idx_k != -1 else (0.0 if node_k_id == circuit.ground_node_id else NAN)

	var forward_voltage_threshold = comp_data.properties["forward_voltage"]
	var should_conduct = false
	if not is_nan(Va) and not is_nan(Vk) and (Va - Vk) >= forward_voltage_threshold:
		should_conduct = true

	if comp_data["conducting"] != should_conduct:
		comp_data["conducting"] = should_conduct
		return true
	return false


## Updates the LED's visual appearance (lit, unlit, or burned) based on the simulation results.
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



## Resets the LED to its default, unlit, and unburned state.
func reset_visual_state():
	is_actually_burned = false
	if burn_label:
		burn_label.visible = false
	if current_label:
		current_label.visible = false
	if _original_material:
		led_mesh_instance.material_override = _original_material

## Displays the calculated current value on the component's 3D label.
func show_current(current_value: float):
	if not current_label or is_actually_burned: 
		if current_label: current_label.visible = false
		return

	if is_nan(current_value):
		current_label.text = "I: N/A"
	else:
		current_label.text = "I: " + StringUtils.format_current(current_value)
	current_label.visible = true

## Hides the current display label.
func hide_current():
	if not current_label: return
	current_label.visible = false



# -----------------------------------------------------------------
# Simulation-results extraction
## Extracts and stores simulation results for this component from the main solution vector.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		x            : Array,
		node_map     : Dictionary,
		vs_map       : Dictionary,
		inductor_map : Dictionary,
		delta_time   : float) -> void:
	#region LEGACY_RESULT_CODE
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()

	var R_led_model = circuit.R_LED_ON
	var term_a = comp_data.terminals["A"]
	var term_k = comp_data.terminals["K"]
	var node_a_id = circuit.terminal_connections.get(term_a.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(term_k.get_instance_id(), -1)
	var Va = circuit.electrical_nodes.get(node_a_id, {}).get("voltage", NAN)
	var Vk = circuit.electrical_nodes.get(node_k_id, {}).get("voltage", NAN)
	var Vf_led = comp_data.properties["forward_voltage"]
	var current = 0.0
	var log_msg_suffix = ""
	var is_logically_burned = comp_data.get("is_burned", false)

	if is_logically_burned:
		current = 0.0
		log_msg_suffix = "Burned (Current is 0)"
	elif comp_data.get("conducting", false) and not is_nan(Va) and not is_nan(Vk):
		var effective_voltage_across_Rd_on = (Va - Vk) - Vf_led
		if effective_voltage_across_Rd_on > 0:
			current = effective_voltage_across_Rd_on / R_led_model
		else:
			current = 0.0 

		log_msg_suffix = "Conducting"
		if current > comp_data.properties["max_current"]:
			comp_data.is_burned = true
			comp_data.conducting = false 
			current = 0.0 
			log_msg_suffix = "JUST BURNED! (Current is 0)"
	else: 
		current = 0.0
		log_msg_suffix = "Not Conducting (Below Vf or error)"
	
	circuit.component_results[comp_id]["current"] = current
	#endregion

## Applies the LED's contribution to the MNA matrices based on its current state.
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
	var burned = comp_data.get("is_burned", false)
	var on = comp_data.get("conducting", false) and not burned
	var R_on = CircuitGraph.R_LED_ON 
	var R_off = CircuitGraph.R_LED_OFF 
	var g = 1.0 / (R_on if on else R_off)
	
	var anode_id = terminal_anode.get_instance_id()
	var kathode_id = terminal_kathode.get_instance_id()
	
	var na = terminal_connections.get(anode_id, -1)
	var nk = terminal_connections.get(kathode_id, -1)
	
	var ia = node_map.get(na, -1)
	var ik = node_map.get(nk, -1)
	
	if on:
		var Vf = forward_voltage 
		var offset = Vf / R_on
		if ia != -1: b[ia] += offset
		if ik != -1: b[ik] -= offset
	
	
	if ia != -1 and ik != -1:
		A[ia][ia] += g
		A[ik][ik] += g
		A[ia][ik] -= g
		A[ik][ia] -= g
	elif ia != -1:
		A[ia][ia] += g
	elif ik != -1:
		A[ik][ik] += g
