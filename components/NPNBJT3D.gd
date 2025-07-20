extends Node3D

class_name NPNBJT3D

const LinearSolver = preload("res://LinearSolver.gd")


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
	var Vbe = NAN
	var Vbc = NAN
	
	if not (!is_nan(Vc) and !is_nan(Vb) and !is_nan(Ve)):
		LinearSolver.print_vector(_x, "x on NPN results fail")
		printerr("NPNBJT {bjt}: Terminal voltage NaN in gather_sim_results. Vc={vc}, Vb={vb}, Ve={ve}".format({ "bjt": name, "vc": Vc, "vb": Vb, "ve": Ve }))
		return
	if not is_nan(Vc) and not is_nan(Vb) and not is_nan(Ve):
		Vbe = Vb - Ve
		Vbc = Vb - Vc
		comp_data.properties["_internal_vbe"] = Vbe
		comp_data.properties["_internal_vbc"] = Vbc

		var I_es = Is / alpha_f
		var I_cs = Is / alpha_r
		
		var Vcrit = Vt * log(1e14)
		var Vbe_limited = min(Vbe, Vcrit)
		var Vbc_limited = min(Vbc, Vcrit)

		Ie = I_es * (exp(Vbe_limited / Vt) - 1.0) - alpha_r * I_cs * (exp(Vbc_limited / Vt) - 1.0)
		Ic = alpha_f * I_es * (exp(Vbe_limited / Vt) - 1.0) - I_cs * (exp(Vbc_limited / Vt) - 1.0)
		Ib = Ie - Ic

	var region = "OFF"
	var Vth = 0.5
	if Vbe > Vth:
		if Vbc > 0:
			region = "SATURATION"
		else:
			region = "ACTIVE"
	elif Vbc > Vth:
		region = "INVERSE"

	circuit.component_results[comp_id]["Ic"] = Ic
	circuit.component_results[comp_id]["Ib"] = Ib
	circuit.component_results[comp_id]["Ie"] = Ie
	circuit.component_results[comp_id]["region"] = region

## Updates the BJT's operating region based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty(): return false

	var node_c_id = circuit.terminal_connections.get(terminal_c.get_instance_id(), -1)
	var node_b_id = circuit.terminal_connections.get(terminal_b.get_instance_id(), -1)
	var node_e_id = circuit.terminal_connections.get(terminal_e.get_instance_id(), -1)

	var idx_c = node_map_iter.get(node_c_id, -1)
	var idx_b = node_map_iter.get(node_b_id, -1)
	var idx_e = node_map_iter.get(node_e_id, -1)

	var Vc = x_iter[idx_c] if idx_c != -1 else (0.0 if node_c_id == circuit.ground_node_id else 0.0)
	var Vb = x_iter[idx_b] if idx_b != -1 else (0.0 if node_b_id == circuit.ground_node_id else 0.0)
	var Ve = x_iter[idx_e] if idx_e != -1 else (0.0 if node_e_id == circuit.ground_node_id else 0.0)

	var Vbe = Vb - Ve
	var Vbc = Vb - Vc

	# Clamp junction voltages to prevent extreme values in the stamp function
	var Vcrit_clamp = 1.5
	comp_data.properties["_internal_vbe"] = clampf(Vbe, -5.0, Vcrit_clamp)
	comp_data.properties["_internal_vbc"] = clampf(Vbc, -5.0, Vcrit_clamp)

	var previous_region = comp_data.properties["operating_region"]
	var new_region = "OFF"
	var Vth = 0.5
	if (Vb - Ve) > Vth:
		if (Vb - Vc) > 0: new_region = "SATURATION"
		else: new_region = "ACTIVE"
	elif (Vb - Vc) > Vth:
		new_region = "INVERSE"

	if new_region != previous_region:
		comp_data.properties["operating_region"] = new_region
		return true
	return false

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
	# Null check for terminals
	if not is_instance_valid(terminal_c) or not is_instance_valid(terminal_b) or not is_instance_valid(terminal_e):
		return
	# Simplified Ebers-Moll Model Stamp
	var Vbe = comp_data.properties.get("_internal_vbe", 0.0)
	var Vbc = comp_data.properties.get("_internal_vbc", 0.0)
	var Is = saturation_current
	var alpha_f = alpha_forward
	var alpha_r = alpha_reverse
	var Vt = THERMAL_VOLTAGE

	# --- Diode Limiting for numerical stability ---
	var Vcrit = Vt * log(1e12)
	var Vbe_limited = min(Vbe, Vcrit)
	var Vbc_limited = min(Vbc, Vcrit)
	
	# Conductances of the BE and BC diodes
	var I_es = Is / alpha_f
	var I_cs = Is / alpha_r
	var g_pi = (I_es / Vt) * exp(Vbe_limited / Vt)
	var g_mu = (I_cs / Vt) * exp(Vbc_limited / Vt)

	# Transconductances
	var gm_f = alpha_f * g_pi
	var gm_r = alpha_r * g_mu

	# Get node indices
	var idx_c = node_map.get(terminal_connections.get(terminal_c.get_instance_id(), -1), -1)
	var idx_b = node_map.get(terminal_connections.get(terminal_b.get_instance_id(), -1), -1)
	var idx_e = node_map.get(terminal_connections.get(terminal_e.get_instance_id(), -1), -1)

	# KCL Error vector F is [F_c, F_b, F_e] = [Ic, Ib, -Ie]. Stamp Jacobian dF/dV.
	# Collector Row: d(Ic)/dV
	if idx_c != -1:
		if idx_c != -1: A[idx_c][idx_c] += g_mu
		if idx_b != -1: A[idx_c][idx_b] += gm_f - g_mu
		if idx_e != -1: A[idx_c][idx_e] -= gm_f
	# Base Row: d(Ib)/dV = d(Ie-Ic)/dV
	if idx_b != -1:
		if idx_c != -1: A[idx_b][idx_c] += gm_r - g_mu
		if idx_b != -1: A[idx_b][idx_b] += g_pi - gm_f + g_mu - gm_r
		if idx_e != -1: A[idx_b][idx_e] += gm_f - g_pi
	# Emitter Row: d(-Ie)/dV
	if idx_e != -1:
		if idx_c != -1: A[idx_e][idx_c] += -gm_r
		if idx_b != -1: A[idx_e][idx_b] += gm_r - g_pi
		if idx_e != -1: A[idx_e][idx_e] += g_pi

	# Companion model current sources
	var Ie_last = I_es * (exp(Vbe_limited / Vt) - 1.0) - alpha_r * I_cs * (exp(Vbc_limited / Vt) - 1.0)
	var Ic_last = alpha_f * I_es * (exp(Vbe_limited / Vt) - 1.0) - I_cs * (exp(Vbc_limited / Vt) - 1.0)
	var Ib_last = Ie_last - Ic_last
	
	var Ieq_c = Ic_last - ((gm_f - g_mu) * Vbe + g_mu * Vbc)
	var Ieq_e = Ie_last - (g_pi * Vbe - gm_r * Vbc)
	var Ieq_b = Ib_last - ((g_pi - gm_f) * Vbe + (gm_r - g_mu) * Vbc)
	
	if idx_c != -1: b[idx_c] += Ieq_c
	if idx_b != -1: b[idx_b] += Ieq_b
	if idx_e != -1: b[idx_e] -= Ieq_e # F vector for emitter is -Ie
