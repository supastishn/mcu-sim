extends Node3D

class_name NPNBJT3D


## Emitted when a key property of the BJT changes.
signal configuration_changed(component_node: Node3D)


## The DC current gain (hFE) of the transistor.
@export var beta_dc: float = 100.0 : set = set_beta_dc

## The base-emitter voltage required to turn the transistor on, in Volts.
@export var vbe_on: float = 0.7 : set = set_vbe_on

## The collector-emitter saturation voltage, in Volts.
@export var vce_sat: float = 0.2 : set = set_vce_sat

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
	set_beta_dc(beta_dc)
	set_vbe_on(vbe_on)
	set_vce_sat(vce_sat)

## Sets the DC current gain (beta), validates it, and emits a signal.
func set_beta_dc(value: float):
	var new_beta = max(1.0, value)
	if is_equal_approx(beta_dc, new_beta):
		beta_dc = new_beta
		return

	beta_dc = new_beta
	print("NPNBJT {bjt_name} beta_dc set to: {beta_str}".format({"bjt_name": name, "beta_str": String.num(beta_dc, 1)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the base-emitter turn-on voltage, validates it, and emits a signal.
func set_vbe_on(value: float):
	var new_vbe = max(0.1, value)
	if is_equal_approx(vbe_on, new_vbe):
		vbe_on = new_vbe
		return

	vbe_on = new_vbe
	print("NPNBJT {bjt_name} vbe_on set to: {vbe_str} V".format({"bjt_name": name, "vbe_str": String.num(vbe_on, 2)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the collector-emitter saturation voltage, validates it, and emits a signal.
func set_vce_sat(value: float):
	var new_vce_sat = max(0.0, value)
	if is_equal_approx(vce_sat, new_vce_sat):
		vce_sat = new_vce_sat
		return
	
	vce_sat = new_vce_sat
	print("NPNBJT {bjt_name} vce_sat set to: {vce_str} V".format({"bjt_name": name, "vce_str": String.num(vce_sat, 2)}))
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
	var comp_node = comp_data.component_node
	var comp_id = comp_node.get_instance_id()

	var Vc = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["C"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Vb = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["B"].get_instance_id(), -1), {}).get("voltage", NAN)
	var Ve = circuit.electrical_nodes.get(circuit.terminal_connections.get(comp_data.terminals["E"].get_instance_id(), -1), {}).get("voltage", NAN)
	
	var region = comp_data.properties["operating_region"]
	var beta = comp_data.properties["beta_dc"]
	var vbe_on_calc = comp_data.properties["vbe_on"]
	var vce_sat_calc = comp_data.properties["vce_sat"]
	
	var Ic: float = NAN
	var Ib: float = NAN
	var Ie: float = NAN
	
	var R_be_active_model_calc = 50.0
	var R_ce_sat_model_calc = 5.0

	if not is_nan(Vc) and not is_nan(Vb) and not is_nan(Ve):
		var Vbe_actual = Vb - Ve
		var Vce_actual = Vc - Ve
		
		if region == "OFF":
			Ib = 0.0; Ic = 0.0; Ie = 0.0
		elif region == "ACTIVE":
			if Vbe_actual > vbe_on_calc:
				Ib = (Vbe_actual - vbe_on_calc) / R_be_active_model_calc
			else: 
				Ib = 0.0
			if Ib < 0.0: Ib = 0.0 
			
			Ic = beta * Ib
			Ie = Ic + Ib
		elif region == "SATURATION":
			if Vbe_actual > vbe_on_calc:
				Ib = (Vbe_actual - vbe_on_calc) / R_be_active_model_calc
			else:
				Ib = 0.0
			if Ib < 0.0: Ib = 0.0

			if Vce_actual > vce_sat_calc: 
				Ic = (Vce_actual - vce_sat_calc) / R_ce_sat_model_calc
			else: 
				Ic = 0.0 
			if Ic < 0.0: Ic = 0.0 

			Ie = Ic + Ib
	
	circuit.component_results[comp_id]["Ic"] = Ic
	circuit.component_results[comp_id]["Ib"] = Ib
	circuit.component_results[comp_id]["Ie"] = Ie
	circuit.component_results[comp_id]["region"] = region 

## Updates the BJT's operating region based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty():
		return false

	var term_c = comp_data.terminals["C"]
	var term_b = comp_data.terminals["B"]
	var term_e = comp_data.terminals["E"]
	var node_c_id = circuit.terminal_connections.get(term_c.get_instance_id(), -1)
	var node_b_id = circuit.terminal_connections.get(term_b.get_instance_id(), -1)
	var node_e_id = circuit.terminal_connections.get(term_e.get_instance_id(), -1)

	var idx_c = node_map_iter.get(node_c_id, -1)
	var idx_b = node_map_iter.get(node_b_id, -1)
	var idx_e = node_map_iter.get(node_e_id, -1)
	var Vc = x_iter[idx_c] if idx_c != -1 else (0.0 if node_c_id == circuit.ground_node_id else NAN)
	var Vb = x_iter[idx_b] if idx_b != -1 else (0.0 if node_b_id == circuit.ground_node_id else NAN)
	var Ve = x_iter[idx_e] if idx_e != -1 else (0.0 if node_e_id == circuit.ground_node_id else NAN)

	var vbe_on_bjt = comp_data.properties["vbe_on"]
	var vce_sat_bjt = comp_data.properties["vce_sat"]
	var previous_region = comp_data.properties["operating_region"]
	var new_region = previous_region 

	if is_nan(Vb) or is_nan(Ve) or is_nan(Vc):
		new_region = "OFF" 
	else:
		var Vbe = Vb - Ve
		var Vce = Vc - Ve
		var vbe_tolerance = 1e-5 

		if Vbe < (vbe_on_bjt - vbe_tolerance): 
			new_region = "OFF"
		else: 
			var vce_saturation_check_upper_bound = vce_sat_bjt + circuit.BJT_SATURATION_VOLTAGE_MARGIN
			if Vce <= vce_saturation_check_upper_bound: 
				new_region = "SATURATION"
			else: 
				new_region = "ACTIVE"

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
	var region = comp_data.properties["operating_region"]
	var beta_val = beta_dc 
	var vbe_on_model_val = vbe_on 
	var vce_sat_model_val = vce_sat 

	var c_id = terminal_c.get_instance_id()
	var b_id = terminal_b.get_instance_id()
	var e_id = terminal_e.get_instance_id()

	var node_c_lookup = terminal_connections.get(c_id, -1)
	var node_b_lookup = terminal_connections.get(b_id, -1)
	var node_e_lookup = terminal_connections.get(e_id, -1)

	var idx_c = node_map.get(node_c_lookup, -1)
	var idx_b = node_map.get(node_b_lookup, -1)
	var idx_e = node_map.get(node_e_lookup, -1)

	var R_be_active_model_const = 50.0  
	var R_ce_sat_model_const = 5.0    
	var R_bjt_off_model_const = 1.0e9 

	if region == "OFF":
		var g_off = 1.0 / R_bjt_off_model_const
		CircuitGraph.stamp_conductance(A, g_off, idx_b, idx_e)
		CircuitGraph.stamp_conductance(A, g_off, idx_c, idx_e)
		CircuitGraph.stamp_conductance(A, g_off, idx_c, idx_b)
		
	elif region == "ACTIVE":
		var G_be_active = 1.0 / R_be_active_model_const
		var Is_be_active = vbe_on_model_val / R_be_active_model_const 
		if idx_b != -1: A[idx_b][idx_b] += G_be_active; b[idx_b] += Is_be_active
		if idx_e != -1: A[idx_e][idx_e] += G_be_active; b[idx_e] -= Is_be_active 
		if idx_b != -1 and idx_e != -1:
			A[idx_b][idx_e] -= G_be_active
			A[idx_e][idx_b] -= G_be_active
		
		var Gm_bjt_active = beta_val / R_be_active_model_const
		var Ic_const_offset_active = beta_val * vbe_on_model_val / R_be_active_model_const 

		if idx_c != -1:
			if idx_b != -1: A[idx_c][idx_b] += Gm_bjt_active
			if idx_e != -1: A[idx_c][idx_e] -= Gm_bjt_active
			b[idx_c] += Ic_const_offset_active 
		if idx_e != -1: 
			if idx_b != -1: A[idx_e][idx_b] -= Gm_bjt_active
			if idx_e != -1: A[idx_e][idx_e] += Gm_bjt_active 
			b[idx_e] -= Ic_const_offset_active

	elif region == "SATURATION":
		var G_be_sat = 1.0 / R_be_active_model_const 
		var Is_be_sat = vbe_on_model_val / R_be_active_model_const
		if idx_b != -1: A[idx_b][idx_b] += G_be_sat; b[idx_b] += Is_be_sat
		if idx_e != -1: A[idx_e][idx_e] += G_be_sat; b[idx_e] -= Is_be_sat
		if idx_b != -1 and idx_e != -1:
			A[idx_b][idx_e] -= G_be_sat
			A[idx_e][idx_b] -= G_be_sat
			
		var G_ce_sat = 1.0 / R_ce_sat_model_const
		var Is_ce_sat = vce_sat_model_val / R_ce_sat_model_const 
		if idx_c != -1: A[idx_c][idx_c] += G_ce_sat; b[idx_c] += Is_ce_sat
		if idx_e != -1: A[idx_e][idx_e] += G_ce_sat; b[idx_e] -= Is_ce_sat 
		if idx_c != -1 and idx_e != -1:
			A[idx_c][idx_e] -= G_ce_sat
			A[idx_e][idx_c] -= G_ce_sat
