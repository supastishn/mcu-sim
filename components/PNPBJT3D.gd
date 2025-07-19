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
		comp_data    : Dictionary,
		_x            : Array,
		_node_map     : Dictionary,
		_vs_map       : Dictionary,
		_inductor_map : Dictionary,
		_delta_time   : float) -> void:
	var comp_id = comp_data.component_node.get_instance_id()
	
	var Ve = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["E"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vb = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["B"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vc = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["C"].get_instance_id(), -1), {}).get("voltage", NAN)

	var Is = comp_data.properties["saturation_current"]
	var alpha_f = comp_data.properties["alpha_forward"]
	var alpha_r = comp_data.properties["alpha_reverse"]
	var Vt = THERMAL_VOLTAGE

	var Ic = NAN
	var Ib = NAN
	var Ie = NAN
	var Veb = NAN
	var Vcb = NAN
	
	if not is_nan(Vc) and not is_nan(Vb) and not is_nan(Ve):
		Veb = Ve - Vb
		Vcb = Vc - Vb
		comp_data.properties["_internal_veb"] = Veb
		comp_data.properties["_internal_vcb"] = Vcb

		var I_es = Is / alpha_f
		var I_cs = Is / alpha_r

		Ie = I_es * (exp(Veb / Vt) - 1.0) - alpha_r * I_cs * (exp(Vcb / Vt) - 1.0)
		Ic = alpha_f * I_es * (exp(Veb / Vt) - 1.0) - I_cs * (exp(Vcb / Vt) - 1.0)
		Ib = -(Ie - Ic) # Current flows into base for PNP, so it's negative

	var region = "OFF"
	var Vth = 0.5
	if Veb > Vth:
		if Vcb > 0:
			region = "SATURATION"
		else:
			region = "ACTIVE"
	elif Vcb > Vth:
		region = "INVERSE"

	circuit.component_results[comp_id]["Ic"] = -Ic
	circuit.component_results[comp_id]["Ib"] = Ib
	circuit.component_results[comp_id]["Ie"] = Ie
	circuit.component_results[comp_id]["region"] = region

## Applies the BJT's contribution to the MNA matrices based on its current operating region.
func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary,
	_opamp_map: Dictionary,
	_inductor_map: Dictionary,
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	_delta_time: float
):
	# Null check for terminals
	if not is_instance_valid(terminal_e) or not is_instance_valid(terminal_b) or not is_instance_valid(terminal_c):
		return
	# Simplified Ebers-Moll Model Stamp for PNP
	var Veb = comp_data.properties.get("_internal_veb", 0.7)
	var Vcb = comp_data.properties.get("_internal_vcb", 0.0)
	var Is = saturation_current
	var alpha_f = alpha_forward
	var alpha_r = alpha_reverse
	var Vt = THERMAL_VOLTAGE

	# Linearize EB and CB diodes
	var g_pi_pnp = (Is / Vt) * exp(Veb / Vt)
	var I_eb_eq = Is * (exp(Veb / Vt) - 1.0) - g_pi_pnp * Veb
	
	var g_mu_pnp = (Is / Vt) * exp(Vcb / Vt)
	var I_cb_eq = Is * (exp(Vcb / Vt) - 1.0) - g_mu_pnp * Vcb

	# Transconductances
	var gm_f_pnp = alpha_f * g_pi_pnp
	var gm_r_pnp = alpha_r * g_mu_pnp

	# Get node indices
	var idx_e = node_map.get(terminal_connections.get(terminal_e.get_instance_id(), -1), -1)
	var idx_b = node_map.get(terminal_connections.get(terminal_b.get_instance_id(), -1), -1)
	var idx_c = node_map.get(terminal_connections.get(terminal_c.get_instance_id(), -1), -1)

	# Stamp linearized model into MNA matrices (current directions are reversed for PNP)
	if idx_b != -1:
		A[idx_b][idx_b] += g_pi_pnp + g_mu_pnp
		if idx_e != -1: A[idx_b][idx_e] -= g_pi_pnp
		if idx_c != -1: A[idx_b][idx_c] -= g_mu_pnp
	
	if idx_e != -1:
		A[idx_e][idx_e] += g_pi_pnp + gm_f_pnp
		if idx_b != -1: A[idx_e][idx_b] -= g_pi_pnp + gm_f_pnp
	
	if idx_c != -1:
		A[idx_c][idx_c] += g_mu_pnp + gm_r_pnp
		if idx_b != -1: A[idx_c][idx_b] -= g_mu_pnp + gm_r_pnp

func get_kcl_contributions(graph: CircuitGraph, _all_node_voltages: Dictionary, F_v: Array, system: Dictionary, _delta_time: float):
	var node_e_id = graph.terminal_connections.get(terminal_e.get_instance_id(), -1)
	var node_b_id = graph.terminal_connections.get(terminal_b.get_instance_id(), -1)
	var node_c_id = graph.terminal_connections.get(terminal_c.get_instance_id(), -1)
	var Ve = graph.electrical_nodes.get(node_e_id, {}).get("voltage", 0.0)
	var Vb = graph.electrical_nodes.get(node_b_id, {}).get("voltage", 0.0)
	var Vc = graph.electrical_nodes.get(node_c_id, {}).get("voltage", 0.0)

	var Veb = Ve - Vb
	var Vcb = Vc - Vb
	
	var I_es = saturation_current / alpha_forward
	var I_cs = saturation_current / alpha_reverse

	# The implemented Ebers-Moll equations calculate magnitudes of currents leaving the E and C terminals.
	var Ie_mag = I_es * (exp(Veb / THERMAL_VOLTAGE) - 1.0) - alpha_reverse * I_cs * (exp(Vcb / THERMAL_VOLTAGE) - 1.0)
	var Ic_mag = alpha_forward * I_es * (exp(Veb / THERMAL_VOLTAGE) - 1.0) - I_cs * (exp(Vcb / THERMAL_VOLTAGE) - 1.0)
	var Ib_mag = Ie_mag - Ic_mag

	var idx_e = system.node_map.get(node_e_id, -1)
	var idx_b = system.node_map.get(node_b_id, -1)
	var idx_c = system.node_map.get(node_c_id, -1)

	# For PNP: Ie flows IN, Ic and Ib flow OUT.
	# KCL error vector is sum of currents LEAVING the node.
	if idx_e != -1: F_v[idx_e] -= Ie_mag
	if idx_c != -1: F_v[idx_c] += Ic_mag
	if idx_b != -1: F_v[idx_b] += Ib_mag
