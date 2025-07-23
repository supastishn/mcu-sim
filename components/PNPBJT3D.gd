extends Node3D

class_name PNPBJT3D


## Emitted when a key property of the BJT changes.
signal configuration_changed(component_node: Node3D)


## The saturation current of the transistor.
@export var saturation_current: float = 1e-15 : set = set_saturation_current
## The forward common-base current gain.
@export var alpha_forward: float = 0.99 : set = set_alpha_forward
## The reverse common-base current gain.
@export var alpha_reverse: float = 0.5 : set = set_alpha_reverse
const THERMAL_VOLTAGE: float = 0.02585

@onready var terminal_e: Area3D = $TerminalE 
@onready var terminal_b: Area3D = $TerminalB 
@onready var terminal_c: Area3D = $TerminalC 
@onready var info_label: Label3D = $InfoLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal_e or not terminal_b or not terminal_c:
		printerr("PNPBJT3D requires child Area3D nodes named 'TerminalE', 'TerminalB', and 'TerminalC'.")
	if not info_label:
		printerr("PNPBJT3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()


## Sets the saturation current and emits a signal.
func set_saturation_current(value: float):
	if is_equal_approx(saturation_current, value):
		saturation_current = value
		return
	saturation_current = value
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the forward alpha and emits a signal.
func set_alpha_forward(value: float):
	if is_equal_approx(alpha_forward, value):
		alpha_forward = value
		return
	alpha_forward = value
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the reverse alpha and emits a signal.
func set_alpha_reverse(value: float):
	if is_equal_approx(alpha_reverse, value):
		alpha_reverse = value
		return
	alpha_reverse = value
	if is_inside_tree():
		emit_signal("configuration_changed", self)

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
	
	if not (!is_nan(Vc) and !is_nan(Vb) and !is_nan(Ve)):
		var err_msg = "PNPBJT {bjt}: Terminal voltage NaN in gather_sim_results. Vc={vc}, Vb={vb}, Ve={ve}".format({ "bjt": name, "vc": Vc, "vb": Vb, "ve": Ve })
		err_msg += "\nSolution vector x: " + LinearSolver.vector_to_string(_x)
		assert(false, err_msg)
		return
	if not is_nan(Vc) and not is_nan(Vb) and not is_nan(Ve):
		Veb = Ve - Vb
		Vcb = Vc - Vb
		comp_data.properties["_internal_veb"] = Veb
		comp_data.properties["_internal_vcb"] = Vcb

		var I_es = Is / alpha_f
		var I_cs = Is / alpha_r
		
		var Vcrit = Vt * log(1e14) # Use same Vcrit as in stamp() for consistency
		var Veb_limited = min(Veb, Vcrit)
		var Vcb_limited = min(Vcb, Vcrit)

		# Calculate current magnitudes based on Ebers-Moll
		var Ie_mag = I_es * (exp(Veb_limited / Vt) - 1.0) - alpha_r * I_cs * (exp(Vcb_limited / Vt) - 1.0)
		var Ic_mag = alpha_f * I_es * (exp(Veb_limited / Vt) - 1.0) - I_cs * (exp(Vcb_limited / Vt) - 1.0)
		var Ib_mag = Ie_mag - Ic_mag
		
		# Conventional currents: Ie flows IN (+), Ic and Ib flow OUT (-)
		Ie = Ie_mag
		Ic = -Ic_mag
		Ib = -Ib_mag
		
	var region = comp_data.properties.get("operating_region", "OFF")
	
	var Vec = Ve - Vc
	circuit.component_results[comp_id]["Ic"] = Ic
	circuit.component_results[comp_id]["Ib"] = Ib
	circuit.component_results[comp_id]["Ie"] = Ie
	circuit.component_results[comp_id]["Vec"] = Vec
	circuit.component_results[comp_id]["region"] = region

## Updates the BJT's operating region based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty(): return false

	var node_e_id = circuit.terminal_connections.get(terminal_e.get_instance_id(), -1)
	var node_b_id = circuit.terminal_connections.get(terminal_b.get_instance_id(), -1)
	var node_c_id = circuit.terminal_connections.get(terminal_c.get_instance_id(), -1)

	var idx_e = node_map_iter.get(node_e_id, -1)
	var idx_b = node_map_iter.get(node_b_id, -1)
	var idx_c = node_map_iter.get(node_c_id, -1)

	var Ve = x_iter[idx_e] if idx_e != -1 else (0.0 if node_e_id == circuit.ground_node_id else NAN)
	var Vb = x_iter[idx_b] if idx_b != -1 else (0.0 if node_b_id == circuit.ground_node_id else NAN)
	var Vc = x_iter[idx_c] if idx_c != -1 else (0.0 if node_c_id == circuit.ground_node_id else NAN)

	var previous_region = comp_data.properties["operating_region"]

	if is_nan(Ve) or is_nan(Vb) or is_nan(Vc):
		comp_data.properties["operating_region"] = "OFF"
		return previous_region != "OFF"

	var Veb = Ve - Vb
	var Vcb = Vc - Vb
	
	# Clamp junction voltages to prevent extreme values in the stamp function
	var Vcrit_clamp = THERMAL_VOLTAGE * log(1e14) # Use same Vcrit as in stamp() for consistency
	comp_data.properties["_internal_veb"] = clampf(Veb, -5.0, Vcrit_clamp)
	comp_data.properties["_internal_vcb"] = clampf(Vcb, -5.0, Vcrit_clamp)

	var new_region = previous_region
	var Vth_be = 0.5
	var Vth_cb = 0.4 # Use a lower threshold for the collector-base junction
	var HYSTERESIS = 0.05 # 50mV voltage margin

	# Determine new region with hysteresis to prevent oscillation
	match previous_region:
		"OFF":
			if Veb > Vth_be and Vcb > Vth_cb: new_region = "SATURATION"
			elif Veb > Vth_be: new_region = "ACTIVE"
			elif Vcb > Vth_cb: new_region = "INVERSE"
		"ACTIVE":
			if Veb < Vth_be - HYSTERESIS: new_region = "OFF"
			elif Vcb > Vth_cb: new_region = "SATURATION"
		"SATURATION":
			# Need to check both junctions to leave saturation
			var be_is_off = Veb < Vth_be - HYSTERESIS
			var cb_is_off = Vcb < Vth_cb - HYSTERESIS
			if be_is_off and cb_is_off: new_region = "OFF"
			elif be_is_off: new_region = "INVERSE" # CB still on
			elif cb_is_off: new_region = "ACTIVE"  # BE still on
		"INVERSE":
			if Vcb < Vth_cb - HYSTERESIS: new_region = "OFF"
			elif Veb > Vth_be: new_region = "SATURATION"

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
	if not is_instance_valid(terminal_e) or not is_instance_valid(terminal_b) or not is_instance_valid(terminal_c):
		return
	# Simplified Ebers-Moll Model Stamp for PNP
	var Veb = comp_data.properties.get("_internal_veb", 0.0)
	var Vcb = comp_data.properties.get("_internal_vcb", 0.0)
	var Is = saturation_current
	var alpha_f = alpha_forward
	var alpha_r = alpha_reverse
	var Vt = THERMAL_VOLTAGE

	# --- Diode Limiting for numerical stability ---
	# The Veb and Vcb values are already clamped in update_nonlinear_state.

	# Conductances of the EB and CB diodes
	var I_es = Is / alpha_f
	var I_cs = Is / alpha_r
	var g_pi_pnp = (I_es / Vt) * exp(Veb / Vt)
	var g_mu_pnp = (I_cs / Vt) * exp(Vcb / Vt)

	# Transconductances
	var gm_f_pnp = alpha_f * g_pi_pnp
	var gm_r_pnp = alpha_r * g_mu_pnp

	# Get node indices
	var idx_e = node_map.get(terminal_connections.get(terminal_e.get_instance_id(), -1), -1)
	var idx_b = node_map.get(terminal_connections.get(terminal_b.get_instance_id(), -1), -1)
	var idx_c = node_map.get(terminal_connections.get(terminal_c.get_instance_id(), -1), -1)

	# KCL Error vector F is [-Ie, Ic, Ib]. Stamp Jacobian dF/dV.
	# Emitter Row: d(-Ie)/dV
	if idx_e != -1:
		if idx_e != -1: A[idx_e][idx_e] -= g_pi_pnp
		if idx_b != -1: A[idx_e][idx_b] += g_pi_pnp - gm_r_pnp
		if idx_c != -1: A[idx_e][idx_c] += gm_r_pnp
	# Collector Row: d(Ic)/dV
	if idx_c != -1:
		if idx_e != -1: A[idx_c][idx_e] -= gm_f_pnp
		if idx_b != -1: A[idx_c][idx_b] += gm_f_pnp - g_mu_pnp
		if idx_c != -1: A[idx_c][idx_c] += g_mu_pnp
	# Base Row: d(Ib)/dV = d(-Ie + Ic)/dV
	if idx_b != -1:
		if idx_e != -1: A[idx_b][idx_e] += gm_f_pnp - g_pi_pnp
		if idx_b != -1: A[idx_b][idx_b] += g_pi_pnp - gm_f_pnp + g_mu_pnp - gm_r_pnp
		if idx_c != -1: A[idx_b][idx_c] += gm_r_pnp - g_mu_pnp

	# Companion model current sources, using conventional current directions
	var Ie_mag_last = I_es * (exp(Veb / Vt) - 1.0) - alpha_r * I_cs * (exp(Vcb / Vt) - 1.0)
	var Ic_mag_last = alpha_f * I_es * (exp(Veb / Vt) - 1.0) - I_cs * (exp(Vcb / Vt) - 1.0)
	
	var Ie_conv_last = Ie_mag_last
	var Ic_conv_last = -Ic_mag_last
	var Ib_conv_last = -(Ie_mag_last - Ic_mag_last)

	# We need to add the RHS for the Newton-Raphson update, which is J*V_last - F(V_last).
	# For PNP, KCL error vector F is [Ie, -Ic, -Ib] (currents LEAVING node).
	# The Ebers-Moll currents are conventional (Ie in, Ic/Ib out).
	# So F is [-Ie_conv, Ic_conv, Ib_conv].
	# The Jacobian d(F)/dV has already been stamped.
	# RHS = J*V_last - F(V_last)
	
	var J_V_e = (-g_pi_pnp * Veb + gm_r_pnp * Vcb)
	var J_V_c = (-gm_f_pnp * Veb + g_mu_pnp * Vcb)
	var J_V_b = ((gm_f_pnp - g_pi_pnp) * Veb + (gm_r_pnp - g_mu_pnp) * Vcb)
	
	var rhs_e = J_V_e + Ie_conv_last
	var rhs_c = J_V_c - Ic_conv_last
	var rhs_b = J_V_b - Ib_conv_last
	
	if idx_e != -1: b[idx_e] += rhs_e
	if idx_c != -1: b[idx_c] += rhs_c
	if idx_b != -1: b[idx_b] += rhs_b
