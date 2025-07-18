extends Node3D

class_name PNPBJT3D


## Emitted when a key property of the BJT changes.
signal configuration_changed(component_node: Node3D)


## The saturation current of the transistor.
@export var saturation_current: float = 1e-15
## The forward common-base current gain.
@export var alpha_forward: float = 0.99
## The reverse common-base current gain.
@export var alpha_reverse: float = 0.5
const THERMAL_VOLTAGE: float = 0.02585

## Reference to the Emitter terminal Area3D node.
@onready var terminal_e: Area3D = $TerminalE 
## Reference to the Base terminal Area3D node.
@onready var terminal_b: Area3D = $TerminalB 
## Reference to the Collector terminal Area3D node.
@onready var terminal_c: Area3D = $TerminalC 
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal_e or not terminal_b or not terminal_c:
		printerr("PNPBJT3D requires child Area3D nodes named 'TerminalE', 'TerminalB', and 'TerminalC'.")
	if not info_label:
		printerr("PNPBJT3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()



## Displays the calculated operating region and currents on the component's 3D label.
func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var ic_str = "Ic: N/A" 
	if results.has("Ic") and not is_nan(results.Ic):
		ic_str = "Ic: " + StringUtils.format_current(results.Ic)
	
	var ib_str = "Ib: N/A" 
	if results.has("Ib") and not is_nan(results.Ib):
		ib_str = "Ib: " + StringUtils.format_current(results.Ib)

	var ie_str = "Ie: N/A" 
	if results.has("Ie") and not is_nan(results.Ie):
		ie_str = "Ie: " + StringUtils.format_current(results.Ie)

	var region_str = "Region: N/A"
	if results.has("region"):
		region_str = "Region: {reg}".format({"reg": results.region})
		
	info_label.text = "{r_str}\n{ic}\n{ib}\n{ie}".format({"r_str": region_str, "ic": ic_str, "ib": ib_str, "ie": ie_str})
	info_label.visible = true

## Hides the information label.
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = "" 


## Resets the component to its default visual state.
func reset_visual_state():
	hide_info()

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"E": {"node": terminal_e, "pos": terminal_e.position},
		"B": {"node": terminal_b, "pos": terminal_b.position},
		"C": {"node": terminal_c, "pos": terminal_c.position}
	}

## Extracts and stores simulation results (currents, region) for this component.
func gather_sim_results(
		circuit      : CircuitGraph,
		_comp_data    : Dictionary,
		_x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		_inductor_map : Dictionary,
		_delta_time   : float) -> void:
	# This function is now a placeholder as the simple region model is deprecated.
	# A full Ebers-Moll based calculation would be needed here.
	pass

## Applies the BJT's contribution to the MNA matrices based on its current operating region.
func stamp(
	_A: Array,
	_b: Array,
	_node_map: Dictionary,
	_vs_map: Dictionary,
	_inductor_map: Dictionary,
	_terminal_connections: Dictionary,
	_comp_data: Dictionary,
	_delta_time: float
):
	# Placeholder for a full PNP Ebers-Moll model stamp.
	# This would be similar to the NPN version but with voltages/currents reversed.
	pass
