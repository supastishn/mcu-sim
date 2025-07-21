extends Node3D

class_name LED3D


## The saturation current of the diode model.
@export var saturation_current: float = 1.0e-12
## The ideality factor (emission coefficient) of the diode model.
@export var ideality_factor: float = 1.5
const THERMAL_VOLTAGE: float = 0.02585 # At room temperature (300K)

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

## The reverse breakdown voltage for the LED (approximate).
const REVERSE_BREAKDOWN_VOLTAGE: float = 5.0


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


## Updates the LED's visual appearance (lit, unlit, or burned) based on the simulation results.
func update_visual_state(current: float, p_is_logically_burned: bool):
	if not burn_label: return 

	if p_is_logically_burned: 
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

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"A": {"node": terminal_anode, "pos": terminal_anode.position},
		"K": {"node": terminal_kathode, "pos": terminal_kathode.position}
	}

## Updates the LED's state (burned or not) based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty(): return false

	var node_a_id = circuit.terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var node_k_id = circuit.terminal_connections.get(terminal_kathode.get_instance_id(), -1)

	var idx_a = node_map_iter.get(node_a_id, -1)
	var idx_k = node_map_iter.get(node_k_id, -1)

	var Va = x_iter[idx_a] if idx_a != -1 else (0.0 if node_a_id == circuit.ground_node_id else 0.0)
	var Vk = x_iter[idx_k] if idx_k != -1 else (0.0 if node_k_id == circuit.ground_node_id else 0.0)
	
	var Vd = Va - Vk

	var was_burned = comp_data.get("is_burned", false)
	if was_burned:
		comp_data.properties["_internal_voltage"] = Vd
		return false # Once burned, state doesn't change

	var Vd_for_check = comp_data.properties.get("_internal_voltage", 0.0)
	comp_data.properties["_internal_voltage"] = Vd

	var is_burned_now = false
	# Check if forward voltage would cause overcurrent. Use previous voltage to avoid instability.
	var Vd_max = (ideality_factor * THERMAL_VOLTAGE) * log(max_current_before_burn / saturation_current + 1.0)
	
	if Vd_for_check < -REVERSE_BREAKDOWN_VOLTAGE:
		is_burned_now = true
	elif Vd_for_check > Vd_max:
		is_burned_now = true
	
	if is_burned_now:
		comp_data["is_burned"] = true
		print("LED '{n}' burned: Vd_check={vd:.3f}, Vd_max={vmax:.3f}".format({"n":name, "vd":Vd_for_check, "vmax":Vd_max}))
		return true # State changed from not-burned to burned
	
	return false

## Extracts and stores simulation results for this component from the main solution vector.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		_x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		_inductor_map : Dictionary,
		_delta_time   : float) -> void:
	var comp_id = comp_data.component_node.get_instance_id()
	
	var Va = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["A"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vk = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["K"].get_instance_id(), -1), {}).get("voltage", NAN)
	
	var current = NAN
	var is_logically_burned = comp_data.get("is_burned", false)

	if is_logically_burned:
		current = 0.0
	elif not is_nan(Va) and not is_nan(Vk):
		var Vd = Va - Vk
		# Use the full Shockley equation for final result, not the limited one
		current = saturation_current * (exp(Vd / (ideality_factor * THERMAL_VOLTAGE)) - 1.0)
	
	circuit.component_results[comp_id]["current"] = current

## Applies the LED's contribution to the MNA matrices based on its current state.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary,
	_inductor_map: Dictionary,
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	_delta_time: float
):
	var na = terminal_connections.get(terminal_anode.get_instance_id(), -1)
	var nk = terminal_connections.get(terminal_kathode.get_instance_id(), -1)
	var ia = node_map.get(na, -1)
	var ik = node_map.get(nk, -1)

	var is_burned = comp_data.get("is_burned", false)
	print_debug("LED '{n}' stamp: burned={b}, ia={ia}, ik={ik}".format({"n": name, "b": is_burned, "ia": ia, "ik": ik}))
	if is_burned:
		CircuitGraph.stamp_conductance(A, 1.0 / CircuitGraph.R_LED_OFF, ia, ik)
		return

	var Vd_last_iter = comp_data.properties.get("_internal_voltage", 0.0)
	var n_vt = ideality_factor * THERMAL_VOLTAGE

	# --- Diode Limiting for numerical stability ---
	var Vcrit = n_vt * log(1e12)
	var Vd_limited = min(Vd_last_iter, Vcrit)

	# Linearized model from Shockley equation
	var exp_term = exp(Vd_limited / n_vt)
	var Geq = (saturation_current / n_vt) * exp_term

	var I_last = saturation_current * (exp_term - 1.0)
	var Ieq = I_last - Geq * Vd_limited

	print_debug("  LED '{n}' stamp: Vd_last={vd}, Vd_lim={vdl}, Geq={g}, Ieq={i}".format({"n": name, "vd": Vd_last_iter, "vdl": Vd_limited, "g": Geq, "i": Ieq}))
	CircuitGraph.stamp_conductance(A, Geq, ia, ik)
	
	# Stamp the equivalent current source
	if ia != -1: b[ia] -= Ieq
	if ik != -1: b[ik] += Ieq
