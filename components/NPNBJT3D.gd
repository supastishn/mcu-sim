extends Node3D

class_name NPNBJT3D


## Emitted when a key property of the BJT changes.
signal configuration_changed(component_node: Node3D)


## The saturation current of the transistor.
@export var saturation_current: float = 1e-15
## The forward common-base current gain.
@export var alpha_forward: float = 0.99
## The reverse common-base current gain.
@export var alpha_reverse: float = 0.5
const THERMAL_VOLTAGE: float = 0.02585

## Reference to the Collector terminal Area3D node.
@onready var terminal_c: Area3D = $TerminalC 
## Reference to the Base terminal Area3D node.
@onready var terminal_b: Area3D = $TerminalB 
## Reference to the Emitter terminal Area3D node.
@onready var terminal_e: Area3D = $TerminalE 
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal_c or not terminal_b or not terminal_e:
		printerr("NPNBJT3D requires child Area3D nodes named 'TerminalC', 'TerminalB', and 'TerminalE'.")
	if not info_label:
		printerr("NPNBJT3D requires a child Label3D named 'InfoLabel'.")
	
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
		"C": {"node": terminal_c, "pos": terminal_c.position},
		"B": {"node": terminal_b, "pos": terminal_b.position},
		"E": {"node": terminal_e, "pos": terminal_e.position}
	}

## Extracts and stores simulation results (currents, region) for this component.
func gather_sim_results(
		circuit      : CircuitGraph,
		comp_data    : Dictionary,
		_x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		_inductor_map : Dictionary,
		_delta_time   : float) -> void:
	var comp_id = comp_data.component_node.get_instance_id()
	
	var Vc = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["C"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vb = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["B"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Ve = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["E"].get_instance_id(), -1), {}).get("voltage", NAN)

	var Is = comp_data.properties["saturation_current"]
	var alpha_f = comp_data.properties["alpha_forward"]
	var alpha_r = comp_data.properties["alpha_reverse"]
	var Vt = THERMAL_VOLTAGE

	var Ic = NAN
	var Ib = NAN
	var Ie = NAN
	
	if not is_nan(Vc) and not is_nan(Vb) and not is_nan(Ve):
		var Vbe = Vb - Ve
		var Vbc = Vb - Vc
		comp_data.properties["_internal_vbe"] = Vbe
		comp_data.properties["_internal_vbc"] = Vbc

		var I_es = Is / alpha_f
		var I_cs = Is / alpha_r

		Ie = I_es * (exp(Vbe / Vt) - 1.0) - alpha_r * I_cs * (exp(Vbc / Vt) - 1.0)
		Ic = alpha_f * I_es * (exp(Vbe / Vt) - 1.0) - I_cs * (exp(Vbc / Vt) - 1.0)
		Ib = Ie - Ic

	circuit.component_results[comp_id]["Ic"] = Ic
	circuit.component_results[comp_id]["Ib"] = Ib
	circuit.component_results[comp_id]["Ie"] = Ie

## Applies the BJT's contribution to the MNA matrices based on its current operating region.
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
	# Simplified Ebers-Moll Model Stamp
	var Vbe = comp_data.properties.get("_internal_vbe", 0.7)
	var Vbc = comp_data.properties.get("_internal_vbc", 0.0)
	var Is = saturation_current
	var alpha_f = alpha_forward
	var alpha_r = alpha_reverse
	var Vt = THERMAL_VOLTAGE

	# Linearize BE and BC diodes
	var g_pi = (Is / Vt) * exp(Vbe / Vt)
	var I_be_eq = Is * (exp(Vbe / Vt) - 1.0) - g_pi * Vbe
	
	var g_mu = (Is / Vt) * exp(Vbc / Vt)
	var I_bc_eq = Is * (exp(Vbc / Vt) - 1.0) - g_mu * Vbc

	# Transconductances
	var gm_f = alpha_f * g_pi
	var gm_r = alpha_r * g_mu

	# Get node indices
	var idx_c = node_map.get(terminal_connections.get(terminal_c.get_instance_id(), -1), -1)
	var idx_b = node_map.get(terminal_connections.get(terminal_b.get_instance_id(), -1), -1)
	var idx_e = node_map.get(terminal_connections.get(terminal_e.get_instance_id(), -1), -1)

	# Stamp linearized model into MNA matrices
	if idx_b != -1:
		A[idx_b][idx_b] += g_pi + g_mu
		b[idx_b] -= -I_be_eq - I_bc_eq
		if idx_e != -1: A[idx_b][idx_e] -= g_pi
		if idx_c != -1: A[idx_b][idx_c] -= g_mu
	
	if idx_e != -1:
		A[idx_e][idx_e] += g_pi + gm_f - gm_r
		b[idx_e] -= I_be_eq + alpha_f * I_be_eq - alpha_r * I_bc_eq
		if idx_b != -1: A[idx_e][idx_b] -= g_pi + gm_f
		if idx_c != -1: A[idx_e][idx_c] += gm_r
	
	if idx_c != -1:
		A[idx_c][idx_c] += g_mu - gm_f + gm_r
		b[idx_c] -= I_bc_eq - alpha_f * I_be_eq + alpha_r * I_bc_eq
		if idx_b != -1: A[idx_c][idx_b] -= g_mu - gm_f
		if idx_e != -1: A[idx_c][idx_e] -= -gm_r
