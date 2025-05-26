extends Node

class_name CircuitGraph

const LinearSolver = preload("res://LinearSolver.gd")
const R_LED_ON            := 0.1                   
const R_LED_OFF           := 1.0e9                 
const R_DIODE_ON          := R_LED_ON              
const R_DIODE_OFF         := R_LED_OFF
const R_SWITCH_CLOSED     := 1e-6                  
const R_SWITCH_OPEN       := 1.0e12                

static func fmt(t : String, d : Dictionary) -> String:
	return t.format(d)

const BJT_SATURATION_VOLTAGE_MARGIN: float = 0.05 


var terminal_connections: Dictionary = {} 

var electrical_nodes: Dictionary = {} 

var components: Array[Dictionary] = []
var component_results: Dictionary = {}

var ground_node_id: int = -1 
var _is_solved: bool = false 
var _needs_rebuild: bool = true 

var _next_node_id: int = 0

## Generates a new unique ID for an electrical node.
func _get_new_node_id() -> int:
	_next_node_id += 1
	return _next_node_id

## Registers a component and its terminals.
func add_component(component: Node3D):
	_is_solved = false 
	_needs_rebuild = true
	for comp_data in components:
		if comp_data.component_node == component:
			return

	var component_data: Dictionary = {
		"component_node": component,
		"type": "Unknown",
		"properties": {}, 
		"state": -1, 
		"terminals": {}
	}

	if component is Resistor3D:
		component_data.type = "Resistor"
		component_data.properties["resistance"] = component.resistance
		component_data.terminals["T1"] = component.terminal1
		component_data.terminals["T2"] = component.terminal2
	elif component is PowerSource3D:
		component_data.type = "PowerSource"
		component_data.properties["target_voltage"] = component.target_voltage
		component_data.properties["target_current"] = component.target_current
		component_data.properties["current_operating_mode"] = "CV" 
		component_data.properties["cc_current_direction_sign"] = 1.0 
		component_data.terminals["POS"] = component.terminal_pos
		component_data.terminals["NEG"] = component.terminal_neg
	elif component is Battery3D:
		component_data.type = "Battery"
		component_data.properties["target_voltage"] = component.target_voltage 
		component_data.properties["num_cells"] = component.num_cells
		component_data.terminals["POS"] = component.terminal_pos
		component_data.terminals["NEG"] = component.terminal_neg
	elif component is LED3D:
		component_data.type = "LED"
		component_data.properties["forward_voltage"] = component.forward_voltage
		component_data.terminals["A"] = component.terminal_anode
		component_data.terminals["K"] = component.terminal_kathode
		component_data["conducting"] = false 
		component_data.properties["min_current"] = component.min_current_to_light 
		component_data.properties["max_current"] = component.max_current_before_burn 
		component_data.is_burned = false 
	elif component is Diode3D:
		component_data.type = "Diode"
		component_data.properties["forward_voltage"] = component.forward_voltage 
		component_data.terminals["A"] = component.terminal_anode
		component_data.terminals["K"] = component.terminal_kathode
		component_data["conducting"] = false 
	elif component is Switch3D:
		component_data.type = "Switch"
		component_data.state = component.current_state 
		component_data.terminals["COM"] = component.terminal_com
		component_data.terminals["NC"] = component.terminal_nc
		component_data.terminals["NO"] = component.terminal_no
	elif component is Potentiometer3D:
		component_data.type = "Potentiometer"
		component_data.properties["total_resistance"] = component.total_resistance
		component_data.properties["wiper_position"] = component.wiper_position
		
		var t1_node = component.get_node_or_null("Terminal1")
		var t2_node = component.get_node_or_null("Terminal2")
		var tw_node = component.get_node_or_null("TerminalWiper")

		component_data.terminals["T1"] = t1_node if is_instance_valid(t1_node) else null
		component_data.terminals["T2"] = t2_node if is_instance_valid(t2_node) else null
		component_data.terminals["W"] = tw_node if is_instance_valid(tw_node) else null

		var t1_name_str = t1_node.name if is_instance_valid(t1_node) else "INVALID"
		var t2_name_str = t2_node.name if is_instance_valid(t2_node) else "INVALID"
		var w_name_str = tw_node.name if is_instance_valid(tw_node) else "INVALID"
	elif component is PolarizedCapacitor3D:
		component_data.type = "PolarizedCapacitor"
		component_data.properties["capacitance"] = component.capacitance
		component_data.properties["max_voltage"] = component.max_voltage
		component_data.properties["voltage_across_cap_prev_dt"] = 0.0 
		component_data.is_exploded = false 
		component_data.terminals["T1"] = component.terminal1 
		component_data.terminals["T2"] = component.terminal2 
	elif component is NonPolarizedCapacitor3D:
		component_data.type = "NonPolarizedCapacitor"
		component_data.properties["capacitance"] = component.capacitance
		component_data.properties["max_voltage"] = component.max_voltage 
		component_data.properties["voltage_across_cap_prev_dt"] = 0.0 
		component_data.terminals["T1"] = component.terminal1
		component_data.terminals["T2"] = component.terminal2
	elif component is Inductor3D:
		component_data.type = "Inductor"
		component_data.properties["inductance"] = component.inductance
		component_data.properties["current_through_L_prev_dt"] = 0.0 
		component_data.terminals["T1"] = component.terminal1
		component_data.terminals["T2"] = component.terminal2
	elif component is NPNBJT3D:
		component_data.type = "NPNBJT"
		component_data.properties["beta_dc"] = component.beta_dc
		component_data.properties["vbe_on"] = component.vbe_on
		component_data.properties["vce_sat"] = component.vce_sat
		component_data.properties["operating_region"] = "OFF" 
		component_data.terminals["C"] = component.terminal_c
		component_data.terminals["B"] = component.terminal_b
		component_data.terminals["E"] = component.terminal_e
	elif component is PNPBJT3D:
		component_data.type = "PNPBJT"
		component_data.properties["beta_dc"] = component.beta_dc
		component_data.properties["veb_on"] = component.veb_on 
		component_data.properties["vec_sat"] = component.vec_sat 
		component_data.properties["operating_region"] = "OFF"
		component_data.terminals["E"] = component.terminal_e 
		component_data.terminals["B"] = component.terminal_b 
		component_data.terminals["C"] = component.terminal_c 
	elif component is ZenerDiode3D:
		component_data.type = "ZenerDiode"
		component_data.properties["forward_voltage"] = component.forward_voltage
		component_data.properties["zener_voltage"] = component.zener_voltage
		component_data.properties["operating_state"] = "OFF" 
		component_data.terminals["A"] = component.terminal_anode
		component_data.terminals["K"] = component.terminal_kathode
	elif component is NChannelMOSFET3D:
		component_data.type = "NChannelMOSFET"
		component_data.properties["threshold_voltage"] = component.threshold_voltage
		component_data.properties["transconductance_parameter"] = component.transconductance_parameter
		component_data.properties["operating_region"] = "OFF" 
		component_data.terminals["D"] = component.terminal_d
		component_data.terminals["G"] = component.terminal_g
		component_data.terminals["S"] = component.terminal_s
	elif component is Relay3D:
		component_data.type = "Relay"
		component_data.properties["signal_voltage_threshold"] = component.signal_voltage_threshold
		component_data.properties["coil_resistance"] = component.coil_resistance 
		component_data.properties["is_energized"] = false 
		component_data.properties["input_signal_resistance"] = 1.0e6 
		component_data.terminals["VCC"] = component.terminal_vcc
		component_data.terminals["GND"] = component.terminal_gnd
		component_data.terminals["Signal"] = component.terminal_signal
		component_data.terminals["COM"] = component.terminal_com
		component_data.terminals["NO"] = component.terminal_no
		component_data.terminals["NC"] = component.terminal_nc

	for term_name in component_data.terminals:
		var terminal = component_data.terminals[term_name]
		var term_id = terminal.get_instance_id()
		if term_id in terminal_connections:
			var old_node_id = terminal_connections[term_id]
			if old_node_id in electrical_nodes:
				var term_list = electrical_nodes[old_node_id]["terminals"]
				var term_index = term_list.find(terminal)
				if term_index != -1:
					term_list.remove_at(term_index)
			terminal_connections.erase(term_id)

	for term_name_ensure_node in component_data.terminals:
		var terminal_ensure_node = component_data.terminals[term_name_ensure_node]
		
		if not is_instance_valid(terminal_ensure_node):
			continue

		var term_id_ensure_node = terminal_ensure_node.get_instance_id()
		
		if term_id_ensure_node == 0:
			pass

		if not term_id_ensure_node in terminal_connections: 
			var new_node_id_for_floating_term = _get_new_node_id()
			electrical_nodes[new_node_id_for_floating_term] = { "terminals": [terminal_ensure_node], "voltage": NAN }
			terminal_connections[term_id_ensure_node] = new_node_id_for_floating_term
			
	components.push_back(component_data)

## Removes a component and its terminals from the graph.
## Also implicitly disconnects terminals from electrical nodes.
func remove_component(component_node: Node3D):
	_is_solved = false
	_needs_rebuild = true
	var component_index = -1
	for i in range(components.size()):
		if components[i].component_node == component_node:
			component_index = i
			break

	if component_index == -1:
		return

	var component_data = components[component_index]

	for term_name in component_data.terminals:
		var terminal = component_data.terminals[term_name]
		var term_id = terminal.get_instance_id()
		if term_id in terminal_connections:
			var node_id = terminal_connections[term_id]
			if node_id in electrical_nodes:
				var term_list = electrical_nodes[node_id]["terminals"]
				var term_index = term_list.find(terminal)
				if term_index != -1:
					term_list.remove_at(term_index)
			terminal_connections.erase(term_id) 

	components.remove_at(component_index)


## Connects two component terminals, updating the electrical node graph.
func connect_terminals(terminal_a: Area3D, terminal_b: Area3D):
	_is_solved = false 
	_needs_rebuild = true 
	if terminal_a == terminal_b:
		return

	var a_id = terminal_a.get_instance_id()
	var b_id = terminal_b.get_instance_id()

	var node_a: int = terminal_connections.get(a_id, -1)
	var node_b: int = terminal_connections.get(b_id, -1)

	if node_a == -1 and node_b == -1:
		var new_node_id = _get_new_node_id()
		electrical_nodes[new_node_id] = { "terminals": [terminal_a, terminal_b], "voltage": NAN }
		terminal_connections[a_id] = new_node_id
		terminal_connections[b_id] = new_node_id
	elif node_a != -1 and node_b == -1:
		terminal_connections[b_id] = node_a
		electrical_nodes[node_a]["terminals"].push_back(terminal_b)
	elif node_a == -1 and node_b != -1:
		terminal_connections[a_id] = node_b
		electrical_nodes[node_b]["terminals"].push_back(terminal_a)
	elif node_a != -1 and node_b != -1:
		if node_a == node_b:
			return
		else:
			var node_b_terminals = electrical_nodes[node_b]["terminals"].duplicate()
			for terminal in node_b_terminals:
				var term_id = terminal.get_instance_id()
				terminal_connections[term_id] = node_a
				electrical_nodes[node_a]["terminals"].push_back(terminal)
			electrical_nodes.erase(node_b)

## Designates the electrical node connected to the given terminal as ground (0V).
func set_ground_node(terminal: Area3D):
	_is_solved = false 
	_needs_rebuild = true 
	if not is_instance_valid(terminal):
		return

	var term_id = terminal.get_instance_id()
	var node_id = terminal_connections.get(term_id, -1)

	if node_id == -1:
		ground_node_id = _get_new_node_id()
		electrical_nodes[ground_node_id] = { "terminals": [terminal], "voltage": 0.0 }
		terminal_connections[term_id] = ground_node_id
	else:
		ground_node_id = node_id
		electrical_nodes[ground_node_id].voltage = 0.0

## Reloads configuration for a component from its Node3D instance.
func component_config_changed(component_node: Node3D):
	_is_solved = false
	_needs_rebuild = true
	var found_component_data: Dictionary = {}
	for comp_data_item in components:
		if comp_data_item.component_node == component_node:
			found_component_data = comp_data_item
			break
	
	if found_component_data.is_empty():
		return

	var comp_type = found_component_data.type 
	
	if comp_type == "Resistor" and component_node is Resistor3D:
		found_component_data.properties["resistance"] = component_node.resistance
	elif comp_type == "PowerSource" and component_node is PowerSource3D:
		found_component_data.properties["target_voltage"] = component_node.target_voltage
		var new_target_current = component_node.target_current
		if new_target_current < 0:
			new_target_current = 0.0
			component_node.target_current = 0.0 
		found_component_data.properties["target_current"] = new_target_current
		found_component_data.properties["current_operating_mode"] = "CV" 
		found_component_data.properties["cc_current_direction_sign"] = 1.0
	elif comp_type == "Battery" and component_node is Battery3D:
		found_component_data.properties["target_voltage"] = component_node.target_voltage 
		found_component_data.properties["num_cells"] = component_node.num_cells
	elif comp_type == "LED" and component_node is LED3D:
		found_component_data.properties["forward_voltage"] = component_node.forward_voltage
		found_component_data.properties["min_current"] = component_node.min_current_to_light
		found_component_data.properties["max_current"] = component_node.max_current_before_burn
		found_component_data.is_burned = false 
	elif comp_type == "Diode" and component_node is Diode3D:
		found_component_data.properties["forward_voltage"] = component_node.forward_voltage
	elif comp_type == "Switch" and component_node is Switch3D:
		found_component_data.state = component_node.current_state
	elif comp_type == "Potentiometer" and component_node is Potentiometer3D:
		found_component_data.properties["total_resistance"] = component_node.total_resistance
		found_component_data.properties["wiper_position"] = component_node.wiper_position
	elif comp_type == "PolarizedCapacitor" and component_node is PolarizedCapacitor3D:
		found_component_data.properties["capacitance"] = component_node.capacitance
		found_component_data.properties["max_voltage"] = component_node.max_voltage
		found_component_data.properties["voltage_across_cap_prev_dt"] = 0.0
		found_component_data.is_exploded = false 
	elif comp_type == "NonPolarizedCapacitor" and component_node is NonPolarizedCapacitor3D:
		found_component_data.properties["capacitance"] = component_node.capacitance
		found_component_data.properties["max_voltage"] = component_node.max_voltage
		found_component_data.properties["voltage_across_cap_prev_dt"] = 0.0
	elif comp_type == "Inductor" and component_node is Inductor3D:
		found_component_data.properties["inductance"] = component_node.inductance
		found_component_data.properties["current_through_L_prev_dt"] = 0.0 
	elif comp_type == "NPNBJT" and component_node is NPNBJT3D:
		found_component_data.properties["beta_dc"] = component_node.beta_dc
		found_component_data.properties["vbe_on"] = component_node.vbe_on
		found_component_data.properties["vce_sat"] = component_node.vce_sat
		found_component_data.properties["operating_region"] = "OFF" 
	elif comp_type == "PNPBJT" and component_node is PNPBJT3D:
		found_component_data.properties["beta_dc"] = component_node.beta_dc
		found_component_data.properties["veb_on"] = component_node.veb_on
		found_component_data.properties["vec_sat"] = component_node.vec_sat
		found_component_data.properties["operating_region"] = "OFF" 
	elif comp_type == "ZenerDiode" and component_node is ZenerDiode3D:
		found_component_data.properties["forward_voltage"] = component_node.forward_voltage
		found_component_data.properties["zener_voltage"] = component_node.zener_voltage
		found_component_data.properties["operating_state"] = "OFF" 
	elif comp_type == "NChannelMOSFET" and component_node is NChannelMOSFET3D:
		found_component_data.properties["threshold_voltage"] = component_node.threshold_voltage
		found_component_data.properties["transconductance_parameter"] = component_node.transconductance_parameter
		found_component_data.properties["operating_region"] = "OFF" 
	elif comp_type == "Relay" and component_node is Relay3D:
		found_component_data.properties["signal_voltage_threshold"] = component_node.signal_voltage_threshold
		found_component_data.properties["coil_resistance"] = component_node.coil_resistance
		found_component_data.properties["is_energized"] = false 
	else:
		return


## Resets calculated voltages (except ground) to NaN.
func _reset_voltages():
	component_results.clear() 
	_is_solved = false


## Attempts to solve the circuit for a single time step using Modified Nodal Analysis (MNA).
## delta_time: The time step for this simulation increment (currently unused by DC components).
## Returns true if successful, false otherwise.
func solve_single_time_step(delta_time: float) -> bool:
	for node_id in electrical_nodes:
		if node_id != ground_node_id:
			electrical_nodes[node_id].voltage = NAN
		else:
			electrical_nodes[node_id].voltage = 0.0 
	component_results.clear() 
	_is_solved = false 

	if ground_node_id == -1:
		return false


	if electrical_nodes.is_empty():
		return true 

	for comp_data_item in components: 
		if comp_data_item.type == "Diode" or comp_data_item.type == "LED":
			comp_data_item["conducting"] = false
		elif comp_data_item.type == "ZenerDiode":
			comp_data_item.properties["operating_state"] = "OFF" 
		elif comp_data_item.type == "Relay":
			comp_data_item.properties["is_energized"] = false 
		elif comp_data_item.type == "NPNBJT" or comp_data_item.type == "PNPBJT" or comp_data_item.type == "NChannelMOSFET":
			comp_data_item.properties["operating_region"] = "OFF" 

	var max_iter = 30 
	var iterations_done = 0
	var x = []
	var converged = false 
	var result_iter: Dictionary = {} 

	for i in range(max_iter):
		iterations_done = i + 1
		result_iter = _build_mna_system(delta_time) 
		
		var A_iter = result_iter.A
		var b_iter = result_iter.b
		var node_map_iter = result_iter.node_map
		var active_vs_map_iter = result_iter.vs_map 
		var inductor_map_iter = result_iter.inductor_map 

		var N_iter = A_iter.size()

		if N_iter == 0 and node_map_iter.is_empty() and active_vs_map_iter.is_empty() and inductor_map_iter.is_empty():
			_is_solved = true
			_calculate_passive_component_currents(delta_time)
			return true
		elif N_iter == 0 : 
			_is_solved = true 
			_calculate_passive_component_currents(delta_time) 
			return true

		if A_iter.is_empty() or b_iter.is_empty() or b_iter.size() != N_iter:
			x = [] 
			pass 


		var current_iter_x = LinearSolver.solve(A_iter, b_iter)

		if current_iter_x.is_empty():
			x = [] 
			for comp_data_diag in components:
				if comp_data_diag.type == "NPNBJT" or comp_data_diag.type == "PNPBJT":
					pass
				elif comp_data_diag.type == "NChannelMOSFET":
					pass
				elif comp_data_diag.type == "LED" or comp_data_diag.type == "Diode":
					pass
				elif comp_data_diag.type == "ZenerDiode":
					pass
				elif comp_data_diag.type == "PowerSource":
					pass
		else:
			x = current_iter_x
			for node_id_key in node_map_iter:
				var matrix_index = node_map_iter[node_id_key]
				if electrical_nodes.has(node_id_key) and matrix_index < x.size():
					electrical_nodes[node_id_key].voltage = x[matrix_index]

		var state_changed_this_iteration = false

		for comp_data_nl in components: 
			if comp_data_nl.type == "Diode" or comp_data_nl.type == "LED":
				var term_a = comp_data_nl.terminals["A"]
				var term_k = comp_data_nl.terminals["K"]
				var node_a_id = terminal_connections.get(term_a.get_instance_id(), -1)
				var node_k_id = terminal_connections.get(term_k.get_instance_id(), -1)
				var Va = NAN
				if electrical_nodes.has(node_a_id): Va = electrical_nodes[node_a_id].voltage
				var Vk = NAN
				if electrical_nodes.has(node_k_id): Vk = electrical_nodes[node_k_id].voltage
				var forward_voltage_threshold = comp_data_nl.properties["forward_voltage"]
				var should_conduct = not is_nan(Va) and not is_nan(Vk) and (Va - Vk) >= forward_voltage_threshold
				if comp_data_nl["conducting"] != should_conduct:
					comp_data_nl["conducting"] = should_conduct
					state_changed_this_iteration = true
		
		for comp_data_bjt in components:
			if comp_data_bjt.type == "NPNBJT":
				var term_c = comp_data_bjt.terminals["C"]
				var term_b = comp_data_bjt.terminals["B"]
				var term_e = comp_data_bjt.terminals["E"]
				var node_c_id = terminal_connections.get(term_c.get_instance_id(), -1)
				var node_b_id = terminal_connections.get(term_b.get_instance_id(), -1)
				var node_e_id = terminal_connections.get(term_e.get_instance_id(), -1)

				var Vc = electrical_nodes.get(node_c_id, {}).get("voltage", NAN)
				var Vb = electrical_nodes.get(node_b_id, {}).get("voltage", NAN)
				var Ve = electrical_nodes.get(node_e_id, {}).get("voltage", NAN)
				
				var vbe_on_bjt = comp_data_bjt.properties["vbe_on"]
				var vce_sat_bjt = comp_data_bjt.properties["vce_sat"]
				var previous_region = comp_data_bjt.properties["operating_region"]
				var new_region = previous_region 

				if is_nan(Vb) or is_nan(Ve) or is_nan(Vc):
					new_region = "OFF" 
					print_debug("  NPNBJT {name} region check: Vb, Ve, or Vc is NaN. Setting to OFF.".format({ "name": comp_data_bjt.component_node.name }))
				else:
					var Vbe = Vb - Ve
					var Vce = Vc - Ve
					var vbe_tolerance = 1e-5 
					
					print_debug("  NPNBJT {name} ({prev_reg}) Check: Vb={vb_s}V, Ve={ve_s}V, Vc={vc_s}V => Vbe={vbe_s}V, Vce={vce_s}V. Thresholds: Vbe_on={vbe_on_s}V, Vce_sat={vce_sat_s}V".format({
						"name": comp_data_bjt.component_node.name, "prev_reg": previous_region,
						"vb_s": String.num(Vb,4), "ve_s": String.num(Ve,4), "vc_s": String.num(Vc,4),
						"vbe_s": String.num(Vbe,4), "vce_s": String.num(Vce,4),
						"vbe_on_s": String.num(vbe_on_bjt,4), "vce_sat_s": String.num(vce_sat_bjt,4)
					}))

					if Vbe < (vbe_on_bjt - vbe_tolerance): 
						new_region = "OFF"
					else: 
						var vce_saturation_check_upper_bound = vce_sat_bjt + BJT_SATURATION_VOLTAGE_MARGIN
						if Vce <= vce_saturation_check_upper_bound: 
							new_region = "SATURATION"
						else: 
							new_region = "ACTIVE"
				
				if new_region != previous_region:
					comp_data_bjt.properties["operating_region"] = new_region
					state_changed_this_iteration = true
		
		for comp_data_nmos in components:
			if comp_data_nmos.type == "NChannelMOSFET":
				var term_d_nmos = comp_data_nmos.terminals["D"]
				var term_g_nmos = comp_data_nmos.terminals["G"]
				var term_s_nmos = comp_data_nmos.terminals["S"]
				var node_d_id_nmos = terminal_connections.get(term_d_nmos.get_instance_id(), -1)
				var node_g_id_nmos = terminal_connections.get(term_g_nmos.get_instance_id(), -1)
				var node_s_id_nmos = terminal_connections.get(term_s_nmos.get_instance_id(), -1)

				var Vd_nmos = electrical_nodes.get(node_d_id_nmos, {}).get("voltage", NAN)
				var Vg_nmos = electrical_nodes.get(node_g_id_nmos, {}).get("voltage", NAN)
				var Vs_nmos = electrical_nodes.get(node_s_id_nmos, {}).get("voltage", NAN)
				
				var vt_nmos_model = comp_data_nmos.properties["threshold_voltage"]
				var previous_region_nmos = comp_data_nmos.properties["operating_region"]
				var new_region_nmos = previous_region_nmos

				if is_nan(Vg_nmos) or is_nan(Vs_nmos) or is_nan(Vd_nmos):
					new_region_nmos = "OFF"
				else:
					var Vgs_nmos = Vg_nmos - Vs_nmos
					var Vds_nmos = Vd_nmos - Vs_nmos
					var vgs_vt_diff = Vgs_nmos - vt_nmos_model
					

					if Vgs_nmos <= vt_nmos_model: 
						new_region_nmos = "OFF"
					else: 
						if Vds_nmos < vgs_vt_diff: 
							new_region_nmos = "TRIODE"
						else: 
							new_region_nmos = "SATURATION"
				
				if new_region_nmos != previous_region_nmos:
					comp_data_nmos.properties["operating_region"] = new_region_nmos
					state_changed_this_iteration = true

		for comp_data_ps in components:
			if comp_data_ps.type == "PowerSource":
				var ps_node = comp_data_ps.component_node
				var ps_id = ps_node.get_instance_id()
				var I_limit = comp_data_ps.properties.target_current 
				var V_target_ps = comp_data_ps.properties.target_voltage
				var previous_op_mode = comp_data_ps.properties.current_operating_mode
				var current_mna_val_for_ps = NAN 

				if previous_op_mode == "CV":
					var vs_current_idx = active_vs_map_iter.get(ps_id, -1)
					if vs_current_idx != -1 and vs_current_idx < x.size():
						current_mna_val_for_ps = x[vs_current_idx] 
						var current_supplied_by_ps = -current_mna_val_for_ps
						if abs(current_supplied_by_ps) > (I_limit + 1e-9):
							comp_data_ps.properties.current_operating_mode = "CC"
							comp_data_ps.properties.cc_current_direction_sign = sign(current_supplied_by_ps)
				
				elif previous_op_mode == "CC":
					var term_p_ps = comp_data_ps.terminals["POS"]
					var term_n_ps = comp_data_ps.terminals["NEG"]
					var node_p_id_ps = terminal_connections.get(term_p_ps.get_instance_id(), -1)
					var node_n_id_ps = terminal_connections.get(term_n_ps.get_instance_id(), -1)
					var Vp_ps = NAN
					if electrical_nodes.has(node_p_id_ps): Vp_ps = electrical_nodes[node_p_id_ps].voltage
					var Vn_ps = NAN
					if electrical_nodes.has(node_n_id_ps): Vn_ps = electrical_nodes[node_n_id_ps].voltage
					
					if not is_nan(Vp_ps) and not is_nan(Vn_ps):
						var V_across_cc = Vp_ps - Vn_ps
						if comp_data_ps.properties.cc_current_direction_sign * V_across_cc > comp_data_ps.properties.cc_current_direction_sign * V_target_ps + 1e-6 :
							comp_data_ps.properties.current_operating_mode = "CV"
				
				if comp_data_ps.properties.current_operating_mode != previous_op_mode:
					state_changed_this_iteration = true

		for comp_data_pnp_bjt in components:
			if comp_data_pnp_bjt.type == "PNPBJT":
				var term_e_pnp = comp_data_pnp_bjt.terminals["E"]
				var term_b_pnp = comp_data_pnp_bjt.terminals["B"]
				var term_c_pnp = comp_data_pnp_bjt.terminals["C"]
				var node_e_id_pnp = terminal_connections.get(term_e_pnp.get_instance_id(), -1)
				var node_b_id_pnp = terminal_connections.get(term_b_pnp.get_instance_id(), -1)
				var node_c_id_pnp = terminal_connections.get(term_c_pnp.get_instance_id(), -1)

				var Ve_pnp = electrical_nodes.get(node_e_id_pnp, {}).get("voltage", NAN)
				var Vb_pnp = electrical_nodes.get(node_b_id_pnp, {}).get("voltage", NAN)
				var Vc_pnp = electrical_nodes.get(node_c_id_pnp, {}).get("voltage", NAN)
				
				var veb_on_pnp_model = comp_data_pnp_bjt.properties["veb_on"]
				var vec_sat_pnp_model = comp_data_pnp_bjt.properties["vec_sat"]
				var previous_region_pnp = comp_data_pnp_bjt.properties["operating_region"]
				var new_region_pnp = previous_region_pnp

				if is_nan(Ve_pnp) or is_nan(Vb_pnp) or is_nan(Vc_pnp):
					new_region_pnp = "OFF"
				else:
					var Veb_pnp = Ve_pnp - Vb_pnp 
					var Vec_pnp = Ve_pnp - Vc_pnp 
					var veb_tolerance_pnp = 1e-5

					
					if Veb_pnp < (veb_on_pnp_model - veb_tolerance_pnp): 
						new_region_pnp = "OFF"
					else: 
						var vec_saturation_check_upper_bound_pnp = vec_sat_pnp_model + BJT_SATURATION_VOLTAGE_MARGIN
						if Vec_pnp <= vec_saturation_check_upper_bound_pnp: 
							new_region_pnp = "SATURATION"
						else: 
							new_region_pnp = "ACTIVE"
				
				if new_region_pnp != previous_region_pnp:
					comp_data_pnp_bjt.properties["operating_region"] = new_region_pnp
					state_changed_this_iteration = true

		for comp_data_zener in components:
			if comp_data_zener.type == "ZenerDiode":
				var term_a_z = comp_data_zener.terminals["A"]
				var term_k_z = comp_data_zener.terminals["K"]
				var node_a_id_z = terminal_connections.get(term_a_z.get_instance_id(), -1)
				var node_k_id_z = terminal_connections.get(term_k_z.get_instance_id(), -1)
				
				var Va_z = electrical_nodes.get(node_a_id_z, {}).get("voltage", NAN)
				var Vk_z = electrical_nodes.get(node_k_id_z, {}).get("voltage", NAN)
				
				var Vf_z_model = comp_data_zener.properties["forward_voltage"]
				var Vz_model = comp_data_zener.properties["zener_voltage"] 
				var previous_state_z = comp_data_zener.properties["operating_state"]
				var new_state_z = previous_state_z

				if is_nan(Va_z) or is_nan(Vk_z):
					new_state_z = "OFF" 
				else:
					var Vak_z = Va_z - Vk_z 
					var zener_voltage_threshold = -Vz_model 
					var zener_on_margin = 1e-5 

					if Vak_z >= (Vf_z_model - 1e-5): 
						new_state_z = "FORWARD"
					elif Vak_z <= (zener_voltage_threshold + zener_on_margin): 
						new_state_z = "ZENER"
					else: 
						new_state_z = "OFF"
				
				if new_state_z != previous_state_z:
					comp_data_zener.properties["operating_state"] = new_state_z
					state_changed_this_iteration = true

		for comp_data_relay in components:
			if comp_data_relay.type == "Relay":
				var term_vcc_relay = comp_data_relay.terminals["VCC"]
				var term_gnd_relay = comp_data_relay.terminals["GND"]
				var term_sig_relay = comp_data_relay.terminals["Signal"]
				
				var node_vcc_id = terminal_connections.get(term_vcc_relay.get_instance_id(), -1)
				var node_gnd_id = terminal_connections.get(term_gnd_relay.get_instance_id(), -1)
				var node_sig_id = terminal_connections.get(term_sig_relay.get_instance_id(), -1)

				var V_vcc = electrical_nodes.get(node_vcc_id, {}).get("voltage", NAN)
				var V_gnd = electrical_nodes.get(node_gnd_id, {}).get("voltage", NAN)
				var V_sig = electrical_nodes.get(node_sig_id, {}).get("voltage", NAN)
				
				var sig_threshold_relay = comp_data_relay.properties["signal_voltage_threshold"]
				var previous_energized_state = comp_data_relay.properties["is_energized"]
				var new_energized_state = previous_energized_state

				if is_nan(V_vcc) or is_nan(V_gnd) or is_nan(V_sig):
					new_energized_state = false 
				else:
					var actual_signal_voltage = V_sig - V_gnd
					var actual_vcc_supply_voltage = V_vcc - V_gnd
					var vcc_min_voltage_for_operation = 0.5 

					var signal_is_high_enough = actual_signal_voltage >= (sig_threshold_relay - 1e-5)
					var vcc_is_sufficient = actual_vcc_supply_voltage >= vcc_min_voltage_for_operation
					
					new_energized_state = signal_is_high_enough and vcc_is_sufficient
				
				if new_energized_state != previous_energized_state:
					comp_data_relay.properties["is_energized"] = new_energized_state
					state_changed_this_iteration = true
					
		if not state_changed_this_iteration and not x.is_empty():
			converged = true
			break 

	if not converged and iterations_done >= max_iter:
		var result_final_consistency_solve = _build_mna_system(delta_time) 
		var A_final_consistency = result_final_consistency_solve.A
		var b_final_consistency = result_final_consistency_solve.b
		var node_map_final_consistency = result_final_consistency_solve.node_map
		
		if A_final_consistency.is_empty() or A_final_consistency.size() == 0 : 
			pass
		else:
			var x_consistency_solve = LinearSolver.solve(A_final_consistency, b_final_consistency)
			
			if not x_consistency_solve.is_empty():
				x = x_consistency_solve 
				result_iter = result_final_consistency_solve 
				for node_id_key in node_map_final_consistency:
					var matrix_index = node_map_final_consistency[node_id_key]
					if electrical_nodes.has(node_id_key) and matrix_index < x.size():
						electrical_nodes[node_id_key].voltage = x[matrix_index]
			else:
				x = [] 
	
	if not x.is_empty():
		_is_solved = true
		if not converged: 
			pass
		
		var final_node_map_print = result_iter.get("node_map", {}) 
		if final_node_map_print: 
			for node_id_key_print in final_node_map_print:
				if electrical_nodes.has(node_id_key_print): 
					pass

		var final_active_vs_map = result_iter.get("vs_map", {}) 
		var final_inductor_map = result_iter.get("inductor_map", {})

		for comp_data_final_res in components: 
			var comp_node_final = comp_data_final_res.component_node
			if not is_instance_valid(comp_node_final): continue

			var comp_id_final = comp_node_final.get_instance_id()
			if not comp_id_final in component_results: component_results[comp_id_final] = {}

			if comp_data_final_res.type == "Battery" or \
			   (comp_data_final_res.type == "PowerSource" and comp_data_final_res.properties.current_operating_mode == "CV"):
				if final_active_vs_map.has(comp_id_final): 
					var matrix_idx_curr_final = final_active_vs_map[comp_id_final]
					if matrix_idx_curr_final < x.size():
						var solved_current_mna = x[matrix_idx_curr_final] 
						component_results[comp_id_final]["current"] = -solved_current_mna 
						
						var term_p_fv = comp_data_final_res.terminals["POS"]
						var term_n_fv = comp_data_final_res.terminals["NEG"]
						var Vp_fv = electrical_nodes.get(terminal_connections.get(term_p_fv.get_instance_id(), -1), {}).get("voltage", NAN)
						var Vn_fv = electrical_nodes.get(terminal_connections.get(term_n_fv.get_instance_id(), -1), {}).get("voltage", NAN)
						var actual_V_across_fv = NAN
						if not is_nan(Vp_fv) and not is_nan(Vn_fv): actual_V_across_fv = Vp_fv - Vn_fv
						component_results[comp_id_final]["voltage"] = actual_V_across_fv
						
						var log_type = comp_data_final_res.type
						var log_name = comp_node_final.name
						var log_curr = String.num(-solved_current_mna, 4) 
						var log_volt_across = String.num(actual_V_across_fv, 2)
						var log_vtarget = String.num(comp_data_final_res.properties.target_voltage, 2)
						var log_ilim = ""
						if log_type == "PowerSource": 
							log_ilim = ", Limit I=" + String.num(comp_data_final_res.properties.target_current,2)
							component_results[comp_id_final]["operating_mode"] = "CV" 
			
			elif comp_data_final_res.type == "PowerSource" and comp_data_final_res.properties.current_operating_mode == "CC":
				var cc_current_val = comp_data_final_res.properties.cc_current_direction_sign * comp_data_final_res.properties.target_current
				component_results[comp_id_final]["current"] = cc_current_val
				component_results[comp_id_final]["operating_mode"] = "CC"
				var term_p_cc = comp_data_final_res.terminals["POS"]
				var term_n_cc = comp_data_final_res.terminals["NEG"]
				var Vp_cc = electrical_nodes.get(terminal_connections.get(term_p_cc.get_instance_id(), -1), {}).get("voltage", NAN)
				var Vn_cc = electrical_nodes.get(terminal_connections.get(term_n_cc.get_instance_id(), -1), {}).get("voltage", NAN)
				var actual_V_across_cc = NAN
				if not is_nan(Vp_cc) and not is_nan(Vn_cc): actual_V_across_cc = Vp_cc - Vn_cc
				component_results[comp_id_final]["voltage"] = actual_V_across_cc

			elif comp_data_final_res.type == "Inductor":
				if final_inductor_map.has(comp_id_final): 
					var matrix_idx_curr_L_final = final_inductor_map[comp_id_final]
					if matrix_idx_curr_L_final < x.size():
						var solved_current_L = x[matrix_idx_curr_L_final] 
						component_results[comp_id_final]["current"] = solved_current_L
						
						var term_1_L = comp_data_final_res.terminals["T1"]
						var term_2_L = comp_data_final_res.terminals["T2"]
						var V1_L = electrical_nodes.get(terminal_connections.get(term_1_L.get_instance_id(), -1), {}).get("voltage", NAN)
						var V2_L = electrical_nodes.get(terminal_connections.get(term_2_L.get_instance_id(), -1), {}).get("voltage", NAN)
						var actual_V_across_L = NAN
						if not is_nan(V1_L) and not is_nan(V2_L): actual_V_across_L = V1_L - V2_L
						component_results[comp_id_final]["voltage_across"] = actual_V_across_L
						
	else: 
		_is_solved = false

	_calculate_passive_component_currents(delta_time)

	return _is_solved


## Constructs the MNA matrices A and b for the current time step.
## delta_time: The simulation time step, crucial for capacitor model.
## Returns a dictionary: { A: Array[Array], b: Array, node_map: Dict, vs_map: Dict } or empty dict on error.
func _build_mna_system(delta_time: float) -> Dictionary:
	var non_ground_nodes: Array[int] = []
	for node_id in electrical_nodes:
		if node_id != ground_node_id:
			non_ground_nodes.push_back(node_id)

	var active_voltage_sources: Array[Dictionary] = []
	for comp_data_item_vs in components: 
		if comp_data_item_vs.type == "Battery":
			active_voltage_sources.push_back(comp_data_item_vs)
		elif comp_data_item_vs.type == "PowerSource" and comp_data_item_vs.properties.get("current_operating_mode") == "CV":
			active_voltage_sources.push_back(comp_data_item_vs)

	var active_inductors: Array[Dictionary] = []
	for comp_data_item_L in components: 
		if comp_data_item_L.type == "Inductor":
			active_inductors.push_back(comp_data_item_L)


	var num_nodes = non_ground_nodes.size()
	var num_active_vs = active_voltage_sources.size()
	var num_inductors = active_inductors.size()
	var N = num_nodes + num_active_vs + num_inductors 

	var node_id_to_matrix_index: Dictionary = {}
	for i in range(num_nodes):
		node_id_to_matrix_index[non_ground_nodes[i]] = i

	var active_vs_id_to_matrix_index: Dictionary = {} 
	for i in range(num_active_vs):
		var vs_comp_data = active_voltage_sources[i]
		var vs_id = vs_comp_data.component_node.get_instance_id()
		active_vs_id_to_matrix_index[vs_id] = num_nodes + i 

	var inductor_id_to_matrix_index: Dictionary = {}
	for i in range(num_inductors):
		var ind_comp_data = active_inductors[i]
		var ind_id = ind_comp_data.component_node.get_instance_id()
		inductor_id_to_matrix_index[ind_id] = num_nodes + num_active_vs + i 
		
	if N == 0:
		return {"A": [], "b": [], "node_map": node_id_to_matrix_index, "vs_map": active_vs_id_to_matrix_index, "inductor_map": inductor_id_to_matrix_index}

	var A: Array = []
	A.resize(N)
	for i in range(N):
		A[i] = []
		A[i].resize(N)
		A[i].fill(0.0)
	var b: Array = []
	b.resize(N)
	b.fill(0.0)


	for comp_data in components:
		if comp_data.type == "Resistor":
			var R = comp_data.properties["resistance"]
			if R == 0.0: R = 1e-9 
			var g = 1.0 / R
			var term1 = comp_data.terminals["T1"]
			var term2 = comp_data.terminals["T2"]
			var node1_id = terminal_connections.get(term1.get_instance_id() if is_instance_valid(term1) else -1, -1)
			var node2_id = terminal_connections.get(term2.get_instance_id() if is_instance_valid(term2) else -1, -1)

			var idx1 = node_id_to_matrix_index.get(node1_id, -1)
			var idx2 = node_id_to_matrix_index.get(node2_id, -1)

			_stamp_conductance(A, g, idx1, idx2)
		
		elif comp_data.type == "LED":
			var is_logically_burned = comp_data.get("is_burned", false)
			var stamp_as_conducting = comp_data.get("conducting", false) and not is_logically_burned

			var term_a = comp_data.terminals["A"]
			var term_k = comp_data.terminals["K"]
			var node_a_id = terminal_connections.get(term_a.get_instance_id() if is_instance_valid(term_a) else -1, -1)
			var node_k_id = terminal_connections.get(term_k.get_instance_id() if is_instance_valid(term_k) else -1, -1)
			var idx_a = node_id_to_matrix_index.get(node_a_id, -1)
			var idx_k = node_id_to_matrix_index.get(node_k_id, -1)

			var g_stamp_led: float
			var R_led_on_model  = R_LED_ON
			var R_led_off_model = R_LED_OFF

			if stamp_as_conducting: 
				g_stamp_led = 1.0 / R_led_on_model
				var Vf_led = comp_data.properties["forward_voltage"]
				var current_offset = Vf_led / R_led_on_model
				if idx_a != -1: b[idx_a] += current_offset
				if idx_k != -1: b[idx_k] -= current_offset
			else: 
				g_stamp_led = 1.0 / R_led_off_model

			_stamp_conductance(A, g_stamp_led, idx_a, idx_k)
		
		elif comp_data.type == "Diode":
			var term_a_diode = comp_data.terminals["A"]
			var term_k_diode = comp_data.terminals["K"]
			var node_a_id_diode = terminal_connections.get(term_a_diode.get_instance_id() if is_instance_valid(term_a_diode) else -1, -1)
			var node_k_id_diode = terminal_connections.get(term_k_diode.get_instance_id() if is_instance_valid(term_k_diode) else -1, -1)
			var idx_a_diode = node_id_to_matrix_index.get(node_a_id_diode, -1)
			var idx_k_diode = node_id_to_matrix_index.get(node_k_id_diode, -1)

			var g_stamp_diode: float
			var R_diode_on_model  = R_DIODE_ON
			var R_diode_off_model = R_DIODE_OFF

			if comp_data.get("conducting", false):
				g_stamp_diode = 1.0 / R_diode_on_model
				var Vf_diode = comp_data.properties["forward_voltage"]
				var current_offset_diode = Vf_diode / R_diode_on_model
				if idx_a_diode != -1: b[idx_a_diode] += current_offset_diode
				if idx_k_diode != -1: b[idx_k_diode] -= current_offset_diode
			else:
				g_stamp_diode = 1.0 / R_diode_off_model

			_stamp_conductance(A, g_stamp_diode, idx_a_diode, idx_k_diode)
		
		elif comp_data.type == "Switch":
			var state: Switch3D.State = comp_data.state
			var R_closed = R_SWITCH_CLOSED
			var g_closed = 1.0 / R_closed

			var R_open = R_SWITCH_OPEN
			var g_open = 1.0 / R_open

			var term_com = comp_data.terminals["COM"]
			var term_nc = comp_data.terminals["NC"]
			var term_no = comp_data.terminals["NO"]

			var node_com_id = terminal_connections.get(term_com.get_instance_id(), -1)
			var node_nc_id = terminal_connections.get(term_nc.get_instance_id(), -1)
			var node_no_id = terminal_connections.get(term_no.get_instance_id(), -1)

			var idx_com = node_id_to_matrix_index.get(node_com_id, -1)
			var idx_nc = node_id_to_matrix_index.get(node_nc_id, -1)
			var idx_no = node_id_to_matrix_index.get(node_no_id, -1)

			if state == Switch3D.State.CONNECTED_NC:
				_stamp_conductance(A, g_closed, idx_com, idx_nc) 
				_stamp_conductance(A, g_open, idx_com, idx_no)   
			elif state == Switch3D.State.CONNECTED_NO:
				_stamp_conductance(A, g_open, idx_com, idx_nc)   
				_stamp_conductance(A, g_closed, idx_com, idx_no) 
		
		elif comp_data.type == "Potentiometer":
			var total_R = comp_data.properties["total_resistance"]
			var wiper_pos = comp_data.properties["wiper_position"]
			
			var R1 = total_R * wiper_pos
			if R1 < 1e-9: R1 = 1e-9 
			var g1 = 1.0 / R1

			var R2 = total_R * (1.0 - wiper_pos)
			if R2 < 1e-9: R2 = 1e-9 
			var g2 = 1.0 / R2
			
			var term1 = comp_data.terminals["T1"]
			var term2 = comp_data.terminals["T2"]
			var termW = comp_data.terminals["W"]
			
			var node1_id = terminal_connections.get(term1.get_instance_id() if is_instance_valid(term1) else -1, -1)
			var node2_id = terminal_connections.get(term2.get_instance_id() if is_instance_valid(term2) else -1, -1)
			var nodeW_id = terminal_connections.get(termW.get_instance_id() if is_instance_valid(termW) else -1, -1)
			
			var idx1 = node_id_to_matrix_index.get(node1_id, -1)
			var idx2 = node_id_to_matrix_index.get(node2_id, -1)
			var idxW = node_id_to_matrix_index.get(nodeW_id, -1)
			
			if idx1 != -1: A[idx1][idx1] += g1
			if idxW != -1: A[idxW][idxW] += g1
			if idx1 != -1 and idxW != -1:
				A[idx1][idxW] -= g1
				A[idxW][idx1] -= g1
				
			if idxW != -1: A[idxW][idxW] += g2
			if idx2 != -1: A[idx2][idx2] += g2
			if idxW != -1 and idx2 != -1:
				A[idxW][idx2] -= g2
				A[idx2][idxW] -= g2
		
		elif comp_data.type == "PowerSource":
			var ps_op_mode = comp_data.properties.get("current_operating_mode", "CV")
			var pos_term_ps = comp_data.terminals["POS"]
			var neg_term_ps = comp_data.terminals["NEG"]
			var pos_node_id_ps = terminal_connections.get(pos_term_ps.get_instance_id() if is_instance_valid(pos_term_ps) else -1, -1)
			var neg_node_id_ps = terminal_connections.get(neg_term_ps.get_instance_id() if is_instance_valid(neg_term_ps) else -1, -1)
			var pos_idx_ps = node_id_to_matrix_index.get(pos_node_id_ps, -1)
			var neg_idx_ps = node_id_to_matrix_index.get(neg_node_id_ps, -1)

			if ps_op_mode == "CV":
				var ps_id_cv = comp_data.component_node.get_instance_id()
				if not active_vs_id_to_matrix_index.has(ps_id_cv):
					printerr("Critical Error: PowerSource {psid} in CV mode not found in active_vs_id_to_matrix_index.".format({"psid": ps_id_cv}))
					continue
				var ps_current_idx_cv = active_vs_id_to_matrix_index[ps_id_cv]
				var V_target_ps_cv = comp_data.properties["target_voltage"]
				
				b[ps_current_idx_cv] = V_target_ps_cv
				if pos_idx_ps != -1:
					A[ps_current_idx_cv][pos_idx_ps] = 1.0
					A[pos_idx_ps][ps_current_idx_cv] = 1.0
				if neg_idx_ps != -1:
					A[ps_current_idx_cv][neg_idx_ps] = -1.0
					A[neg_idx_ps][ps_current_idx_cv] = -1.0
			
			elif ps_op_mode == "CC":
				var I_target_cc = comp_data.properties["target_current"]
				var direction_sign_cc = comp_data.properties.get("cc_current_direction_sign", 1.0)
				var actual_current_stamp_cc = direction_sign_cc * I_target_cc
				if pos_idx_ps != -1:
					b[pos_idx_ps] += actual_current_stamp_cc 
				if neg_idx_ps != -1:
					b[neg_idx_ps] -= actual_current_stamp_cc
					
		elif comp_data.type == "Battery": 
			var pos_term_bat = comp_data.terminals["POS"]
			var neg_term_bat = comp_data.terminals["NEG"]
			var pos_node_id_bat = terminal_connections.get(pos_term_bat.get_instance_id() if is_instance_valid(pos_term_bat) else -1, -1)
			var neg_node_id_bat = terminal_connections.get(neg_term_bat.get_instance_id() if is_instance_valid(neg_term_bat) else -1, -1)
			var pos_idx_bat = node_id_to_matrix_index.get(pos_node_id_bat, -1)
			var neg_idx_bat = node_id_to_matrix_index.get(neg_node_id_bat, -1)

			var bat_id = comp_data.component_node.get_instance_id()
			if not active_vs_id_to_matrix_index.has(bat_id): 
				printerr("Critical Error: Battery {batid} not found in active_vs_id_to_matrix_index.".format({"batid": bat_id}))
				continue
			
			var bat_current_idx = active_vs_id_to_matrix_index[bat_id]
			var V_target_bat = comp_data.properties["target_voltage"]
			
			b[bat_current_idx] = V_target_bat
			if pos_idx_bat != -1:
				A[bat_current_idx][pos_idx_bat] = 1.0
				A[pos_idx_bat][bat_current_idx] = 1.0 
			if neg_idx_bat != -1:
				A[bat_current_idx][neg_idx_bat] = -1.0
				A[neg_idx_bat][bat_current_idx] = -1.0
		
		elif comp_data.type == "PolarizedCapacitor":
			var G_eq: float
			var I_eq_source: float = 0.0 

			if comp_data.get("is_exploded", false):
				G_eq = 1e-9 
			else:
				var C = comp_data.properties["capacitance"]
				if C <= 1e-12: C = 1e-12 
				var Vc_prev_dt = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)
				
				G_eq = C / delta_time
				I_eq_source = G_eq * Vc_prev_dt

			var term1_cap = comp_data.terminals["T1"] 
			var term2_cap = comp_data.terminals["T2"] 
			var node1_id_cap = terminal_connections.get(term1_cap.get_instance_id() if is_instance_valid(term1_cap) else -1, -1)
			var node2_id_cap = terminal_connections.get(term2_cap.get_instance_id() if is_instance_valid(term2_cap) else -1, -1)
			
			var idx1_cap = node_id_to_matrix_index.get(node1_id_cap, -1)
			var idx2_cap = node_id_to_matrix_index.get(node2_id_cap, -1)

			_stamp_conductance(A, G_eq, idx1_cap, idx2_cap)
			
			if idx1_cap != -1: b[idx1_cap] += I_eq_source
			if idx2_cap != -1: b[idx2_cap] -= I_eq_source
		
		elif comp_data.type == "NonPolarizedCapacitor":
			var C_np = comp_data.properties["capacitance"]
			if C_np <= 1e-12: C_np = 1e-12
			var Vc_prev_dt_np = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)
			
			var G_eq_np = C_np / delta_time
			var I_eq_source_np = G_eq_np * Vc_prev_dt_np

			var term1_np_cap = comp_data.terminals["T1"]
			var term2_np_cap = comp_data.terminals["T2"]
			var node1_id_np_cap = terminal_connections.get(term1_np_cap.get_instance_id() if is_instance_valid(term1_np_cap) else -1, -1)
			var node2_id_np_cap = terminal_connections.get(term2_np_cap.get_instance_id() if is_instance_valid(term2_np_cap) else -1, -1)
			
			var idx1_np_cap = node_id_to_matrix_index.get(node1_id_np_cap, -1)
			var idx2_np_cap = node_id_to_matrix_index.get(node2_id_np_cap, -1)

			if idx1_np_cap != -1: A[idx1_np_cap][idx1_np_cap] += G_eq_np
			if idx2_np_cap != -1: A[idx2_np_cap][idx2_np_cap] += G_eq_np
			if idx1_np_cap != -1 and idx2_np_cap != -1:
				A[idx1_np_cap][idx2_np_cap] -= G_eq_np
				A[idx2_np_cap][idx1_np_cap] -= G_eq_np
			
			if idx1_np_cap != -1: b[idx1_np_cap] += I_eq_source_np
			if idx2_np_cap != -1: b[idx2_np_cap] -= I_eq_source_np

		elif comp_data.type == "Inductor":
			var L_val = comp_data.properties["inductance"]
			if L_val <= 1e-12: L_val = 1e-12 
			var I_L_prev_dt_val = comp_data.properties.get("current_through_L_prev_dt", 0.0)

			var term1_L = comp_data.terminals["T1"]
			var term2_L = comp_data.terminals["T2"]
			var node1_id_L = terminal_connections.get(term1_L.get_instance_id() if is_instance_valid(term1_L) else -1, -1)
			var node2_id_L = terminal_connections.get(term2_L.get_instance_id() if is_instance_valid(term2_L) else -1, -1)

			var idx1_L = node_id_to_matrix_index.get(node1_id_L, -1)
			var idx2_L = node_id_to_matrix_index.get(node2_id_L, -1)
			
			var inductor_id = comp_data.component_node.get_instance_id()
			if not inductor_id_to_matrix_index.has(inductor_id):
				printerr("Critical Error: Inductor {ind_id_str} not found in inductor_id_to_matrix_index.".format({"ind_id_str": inductor_id}))
				continue
			var idx_I_L = inductor_id_to_matrix_index[inductor_id]

			if idx1_L != -1: A[idx_I_L][idx1_L] = 1.0
			if idx2_L != -1: A[idx_I_L][idx2_L] = -1.0
			A[idx_I_L][idx_I_L] = -L_val / delta_time
			b[idx_I_L] = -(L_val / delta_time) * I_L_prev_dt_val
			
			if idx1_L != -1: A[idx1_L][idx_I_L] = 1.0
			if idx2_L != -1: A[idx2_L][idx_I_L] = -1.0

		elif comp_data.type == "NPNBJT":
			var region = comp_data.properties["operating_region"]
			var beta = comp_data.properties["beta_dc"]
			var vbe_on_model = comp_data.properties["vbe_on"]
			var vce_sat_model = comp_data.properties["vce_sat"]
			
			var term_c_bjt = comp_data.terminals["C"]
			var term_b_bjt = comp_data.terminals["B"]
			var term_e_bjt = comp_data.terminals["E"]
			
			var node_c_id_bjt = terminal_connections.get(term_c_bjt.get_instance_id(), -1)
			var node_b_id_bjt = terminal_connections.get(term_b_bjt.get_instance_id(), -1)
			var node_e_id_bjt = terminal_connections.get(term_e_bjt.get_instance_id(), -1)

			var idx_c = node_id_to_matrix_index.get(node_c_id_bjt, -1)
			var idx_b = node_id_to_matrix_index.get(node_b_id_bjt, -1)
			var idx_e = node_id_to_matrix_index.get(node_e_id_bjt, -1)
			
			var R_be_active_model = 50.0  
			var R_ce_sat_model = 5.0    
			var R_bjt_off_model = 1.0e9 

			if region == "OFF":
				var g_off = 1.0 / R_bjt_off_model
				_stamp_conductance(A, g_off, idx_b, idx_e)
				_stamp_conductance(A, g_off, idx_c, idx_e)
				_stamp_conductance(A, g_off, idx_c, idx_b)
			
			elif region == "ACTIVE":
				var G_be_active = 1.0 / R_be_active_model
				var Is_be_active = vbe_on_model / R_be_active_model 

				if idx_b != -1: A[idx_b][idx_b] += G_be_active; b[idx_b] += Is_be_active
				if idx_e != -1: A[idx_e][idx_e] += G_be_active; b[idx_e] -= Is_be_active
				if idx_b != -1 and idx_e != -1:
					A[idx_b][idx_e] -= G_be_active; A[idx_e][idx_b] -= G_be_active
				
				
				var Gm_bjt = beta / R_be_active_model
				var Ic_offset_bjt = beta * vbe_on_model / R_be_active_model

				if idx_c != -1:
					if idx_b != -1: A[idx_c][idx_b] += Gm_bjt   
					if idx_e != -1: A[idx_c][idx_e] -= Gm_bjt   
					b[idx_c] += Ic_offset_bjt             
				
				if idx_e != -1:
					if idx_b != -1: A[idx_e][idx_b] -= Gm_bjt
					if idx_e != -1: A[idx_e][idx_e] += Gm_bjt
					b[idx_e] -= Ic_offset_bjt

			elif region == "SATURATION":
				var G_be_sat = 1.0 / R_be_active_model 
				var Is_be_sat = vbe_on_model / R_be_active_model

				if idx_b != -1: A[idx_b][idx_b] += G_be_sat; b[idx_b] += Is_be_sat
				if idx_e != -1: A[idx_e][idx_e] += G_be_sat; b[idx_e] -= Is_be_sat
				if idx_b != -1 and idx_e != -1:
					A[idx_b][idx_e] -= G_be_sat; A[idx_e][idx_b] -= G_be_sat
				
				var G_ce_sat = 1.0 / R_ce_sat_model
				var Is_ce_sat = vce_sat_model / R_ce_sat_model 

				if idx_c != -1: A[idx_c][idx_c] += G_ce_sat; b[idx_c] += Is_ce_sat
				if idx_e != -1: A[idx_e][idx_e] += G_ce_sat; b[idx_e] -= Is_ce_sat
				if idx_c != -1 and idx_e != -1:
					A[idx_c][idx_e] -= G_ce_sat; A[idx_e][idx_c] -= G_ce_sat
		
		elif comp_data.type == "PNPBJT":
			var region_pnp = comp_data.properties["operating_region"]
			var beta_pnp = comp_data.properties["beta_dc"]
			var veb_on_model_pnp = comp_data.properties["veb_on"] 
			var vec_sat_model_pnp = comp_data.properties["vec_sat"] 
			
			var term_e_pnp_mna = comp_data.terminals["E"]
			var term_b_pnp_mna = comp_data.terminals["B"]
			var term_c_pnp_mna = comp_data.terminals["C"]
			
			var node_e_id_pnp_mna = terminal_connections.get(term_e_pnp_mna.get_instance_id(), -1)
			var node_b_id_pnp_mna = terminal_connections.get(term_b_pnp_mna.get_instance_id(), -1)
			var node_c_id_pnp_mna = terminal_connections.get(term_c_pnp_mna.get_instance_id(), -1)

			var idx_e_pnp = node_id_to_matrix_index.get(node_e_id_pnp_mna, -1)
			var idx_b_pnp = node_id_to_matrix_index.get(node_b_id_pnp_mna, -1)
			var idx_c_pnp = node_id_to_matrix_index.get(node_c_id_pnp_mna, -1)
			
			var R_eb_active_model_pnp = 50.0 
			var R_ec_sat_model_pnp = 5.0   
			var R_pnp_off_model = 1.0e9 

			if region_pnp == "OFF":
				var g_off_pnp = 1.0 / R_pnp_off_model
				_stamp_conductance(A, g_off_pnp, idx_e_pnp, idx_b_pnp) 
				_stamp_conductance(A, g_off_pnp, idx_e_pnp, idx_c_pnp) 
				_stamp_conductance(A, g_off_pnp, idx_b_pnp, idx_c_pnp) 
			
			elif region_pnp == "ACTIVE":
				var G_eb_active_pnp = 1.0 / R_eb_active_model_pnp
				var Is_eb_active_pnp = veb_on_model_pnp / R_eb_active_model_pnp

				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += G_eb_active_pnp; b[idx_e_pnp] += Is_eb_active_pnp
				if idx_b_pnp != -1: A[idx_b_pnp][idx_b_pnp] += G_eb_active_pnp; b[idx_b_pnp] -= Is_eb_active_pnp
				if idx_e_pnp != -1 and idx_b_pnp != -1:
					A[idx_e_pnp][idx_b_pnp] -= G_eb_active_pnp; A[idx_b_pnp][idx_e_pnp] -= G_eb_active_pnp
				
				var Gm_pnp_mna = beta_pnp * G_eb_active_pnp
				var Ic_const_offset_pnp_mna = beta_pnp * Is_eb_active_pnp 
				
				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += Gm_pnp_mna
				if idx_e_pnp != -1 and idx_b_pnp != -1: A[idx_e_pnp][idx_b_pnp] -= Gm_pnp_mna
				if idx_c_pnp != -1 and idx_e_pnp != -1: A[idx_c_pnp][idx_e_pnp] -= Gm_pnp_mna
				if idx_c_pnp != -1 and idx_b_pnp != -1: A[idx_c_pnp][idx_b_pnp] += Gm_pnp_mna
				
				if idx_e_pnp != -1: b[idx_e_pnp] += Ic_const_offset_pnp_mna
				if idx_c_pnp != -1: b[idx_c_pnp] -= Ic_const_offset_pnp_mna

			elif region_pnp == "SATURATION":
				var G_eb_sat_pnp = 1.0 / R_eb_active_model_pnp 
				var Is_eb_sat_pnp = veb_on_model_pnp / R_eb_active_model_pnp

				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += G_eb_sat_pnp; b[idx_e_pnp] += Is_eb_sat_pnp
				if idx_b_pnp != -1: A[idx_b_pnp][idx_b_pnp] += G_eb_sat_pnp; b[idx_b_pnp] -= Is_eb_sat_pnp
				if idx_e_pnp != -1 and idx_b_pnp != -1:
					A[idx_e_pnp][idx_b_pnp] -= G_eb_sat_pnp; A[idx_b_pnp][idx_e_pnp] -= G_eb_sat_pnp
				
				var G_ec_sat_pnp = 1.0 / R_ec_sat_model_pnp
				var Is_ec_sat_pnp = vec_sat_model_pnp / R_ec_sat_model_pnp

				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += G_ec_sat_pnp; b[idx_e_pnp] += Is_ec_sat_pnp
				if idx_c_pnp != -1: A[idx_c_pnp][idx_c_pnp] += G_ec_sat_pnp; b[idx_c_pnp] -= Is_ec_sat_pnp
				if idx_e_pnp != -1 and idx_c_pnp != -1:
					A[idx_e_pnp][idx_c_pnp] -= G_ec_sat_pnp; A[idx_c_pnp][idx_e_pnp] -= G_ec_sat_pnp

		elif comp_data.type == "NChannelMOSFET":
			var region_nmos_mna = comp_data.properties["operating_region"]
			var vt_nmos_mna = comp_data.properties["threshold_voltage"]
			var kn_nmos_mna = comp_data.properties["transconductance_parameter"]
			
			var term_d_nmos_mna = comp_data.terminals["D"]
			var term_g_nmos_mna = comp_data.terminals["G"]
			var term_s_nmos_mna = comp_data.terminals["S"]
			
			var node_d_id_nmos_mna = terminal_connections.get(term_d_nmos_mna.get_instance_id(), -1)
			var node_g_id_nmos_mna = terminal_connections.get(term_g_nmos_mna.get_instance_id(), -1)
			var node_s_id_nmos_mna = terminal_connections.get(term_s_nmos_mna.get_instance_id(), -1)

			var idx_d_nmos = node_id_to_matrix_index.get(node_d_id_nmos_mna, -1)
			var idx_g_nmos = node_id_to_matrix_index.get(node_g_id_nmos_mna, -1)
			var idx_s_nmos = node_id_to_matrix_index.get(node_s_id_nmos_mna, -1)
			
			var G_gate_leakage = 1e-12 
			_stamp_conductance(A, G_gate_leakage, idx_g_nmos, idx_d_nmos)
			_stamp_conductance(A, G_gate_leakage, idx_g_nmos, idx_s_nmos)

			if region_nmos_mna == "OFF":
				var G_ds_off = 1e-9 
				_stamp_conductance(A, G_ds_off, idx_d_nmos, idx_s_nmos)
			else: 
				var Vg_prev_iter = electrical_nodes.get(node_g_id_nmos_mna, {}).get("voltage", 0.0) 
				var Vs_prev_iter = electrical_nodes.get(node_s_id_nmos_mna, {}).get("voltage", 0.0)
				var Vgs_for_model = Vg_prev_iter - Vs_prev_iter
				
				if region_nmos_mna == "TRIODE":
					var R_ds_triode_approx = 1.0 / (kn_nmos_mna * max(0.01, Vgs_for_model - vt_nmos_mna)) 
					if R_ds_triode_approx > 1e9: R_ds_triode_approx = 1e9
					if R_ds_triode_approx < 1e-3: R_ds_triode_approx = 1e-3 
					var G_ds_triode = 1.0 / R_ds_triode_approx
					_stamp_conductance(A, G_ds_triode, idx_d_nmos, idx_s_nmos)

				elif region_nmos_mna == "SATURATION":
					var Id_sat_val = 0.0
					if Vgs_for_model > vt_nmos_mna:
						Id_sat_val = 0.5 * kn_nmos_mna * pow(Vgs_for_model - vt_nmos_mna, 2.0)
					
					if idx_d_nmos != -1: b[idx_d_nmos] -= Id_sat_val 
					if idx_s_nmos != -1: b[idx_s_nmos] += Id_sat_val 
		
		elif comp_data.type == "ZenerDiode":
			var state_zener = comp_data.properties["operating_state"]
			var Vf_zener_model = comp_data.properties["forward_voltage"]
			var Vz_zener_model = comp_data.properties["zener_voltage"] 

			var term_a_z = comp_data.terminals["A"]
			var term_k_z = comp_data.terminals["K"]
			var node_a_id_z = terminal_connections.get(term_a_z.get_instance_id() if is_instance_valid(term_a_z) else -1, -1)
			var node_k_id_z = terminal_connections.get(term_k_z.get_instance_id() if is_instance_valid(term_k_z) else -1, -1)
			var idx_a_z = node_id_to_matrix_index.get(node_a_id_z, -1)
			var idx_k_z = node_id_to_matrix_index.get(node_k_id_z, -1)

			var R_on_model = 0.1 
			var G_on_model = 1.0 / R_on_model
			var R_off_model = 1.0e9 
			var G_off_model = 1.0 / R_off_model

			if state_zener == "OFF":
				_stamp_conductance(A, G_off_model, idx_a_z, idx_k_z)
			elif state_zener == "FORWARD":
				_stamp_conductance(A, G_on_model, idx_a_z, idx_k_z)
				var current_offset_fwd = G_on_model * Vf_zener_model
				if idx_a_z != -1: b[idx_a_z] += current_offset_fwd
				if idx_k_z != -1: b[idx_k_z] -= current_offset_fwd
			elif state_zener == "ZENER":
				_stamp_conductance(A, G_on_model, idx_a_z, idx_k_z)
				var current_offset_zener = G_on_model * Vz_zener_model
				if idx_k_z != -1: b[idx_k_z] += current_offset_zener
				if idx_a_z != -1: b[idx_a_z] -= current_offset_zener
		
		elif comp_data.type == "Relay":
			var R_coil_path: float
			var g_coil_path: float
			var R_coil_actual = comp_data.properties["coil_resistance"]
			if R_coil_actual <= 1e-9: R_coil_actual = 1e-9

			var term_vcc = comp_data.terminals["VCC"]
			var term_gnd = comp_data.terminals["GND"]
			var node_vcc_id = terminal_connections.get(term_vcc.get_instance_id() if is_instance_valid(term_vcc) else -1, -1)
			var node_gnd_id = terminal_connections.get(term_gnd.get_instance_id() if is_instance_valid(term_gnd) else -1, -1)
			var idx_vcc = node_id_to_matrix_index.get(node_vcc_id, -1)
			var idx_gnd = node_id_to_matrix_index.get(node_gnd_id, -1)

			if comp_data.properties["is_energized"]:
				R_coil_path = R_coil_actual 
				g_coil_path = 1.0 / R_coil_path
			else:
				R_coil_path = R_SWITCH_OPEN 
				g_coil_path = 1.0 / R_coil_path
			_stamp_conductance(A, g_coil_path, idx_vcc, idx_gnd)

			var R_signal_in = comp_data.properties["input_signal_resistance"]
			if R_signal_in <= 1e-9: R_signal_in = 1e-9
			var g_signal_in = 1.0 / R_signal_in
			var term_sig = comp_data.terminals["Signal"]
			var node_sig_id = terminal_connections.get(term_sig.get_instance_id() if is_instance_valid(term_sig) else -1, -1)
			var idx_sig = node_id_to_matrix_index.get(node_sig_id, -1)
			_stamp_conductance(A, g_signal_in, idx_sig, idx_gnd)


			var R_sw_closed = R_SWITCH_CLOSED
			var g_sw_closed = 1.0 / R_sw_closed
			var R_sw_open = R_SWITCH_OPEN
			var g_sw_open = 1.0 / R_sw_open

			var term_com_relay = comp_data.terminals["COM"]
			var term_no_relay = comp_data.terminals["NO"]
			var term_nc_relay = comp_data.terminals["NC"]
			
			var node_com_id_relay = terminal_connections.get(term_com_relay.get_instance_id(), -1)
			var node_no_id_relay = terminal_connections.get(term_no_relay.get_instance_id(), -1)
			var node_nc_id_relay = terminal_connections.get(term_nc_relay.get_instance_id(), -1)

			var idx_com_relay = node_id_to_matrix_index.get(node_com_id_relay, -1)
			var idx_no_relay = node_id_to_matrix_index.get(node_no_id_relay, -1)
			var idx_nc_relay = node_id_to_matrix_index.get(node_nc_id_relay, -1)

			if comp_data.properties["is_energized"]: 
				_stamp_conductance(A, g_sw_closed, idx_com_relay, idx_no_relay)
				_stamp_conductance(A, g_sw_open, idx_com_relay, idx_nc_relay)
			else: 
				_stamp_conductance(A, g_sw_open, idx_com_relay, idx_no_relay)
				_stamp_conductance(A, g_sw_closed, idx_com_relay, idx_nc_relay)

	_needs_rebuild = false
	return { "A": A, "b": b, "node_map": node_id_to_matrix_index, "vs_map": active_vs_id_to_matrix_index, "inductor_map": inductor_id_to_matrix_index }

## Helper function to stamp a conductance G between node idx1 and node idx2 into matrix A.
## Handles cases where idx1 or idx2 might be -1 (ground).
func _stamp_conductance(A_matrix: Array, g_value: float, idx1: int, idx2: int):
	if idx1 != -1 and idx2 != -1: 
		A_matrix[idx1][idx1] += g_value
		A_matrix[idx2][idx2] += g_value
		A_matrix[idx1][idx2] -= g_value
		A_matrix[idx2][idx1] -= g_value
	elif idx1 != -1: 
		A_matrix[idx1][idx1] += g_value
	elif idx2 != -1: 
		A_matrix[idx2][idx2] += g_value

func _calculate_passive_component_currents(delta_time: float):
	if not _is_solved:
		return

	for comp_data in components:
		var comp_node = comp_data.component_node
		if not is_instance_valid(comp_node): 
			continue
		var comp_id = comp_node.get_instance_id()
		if not comp_id in component_results: component_results[comp_id] = {}


		if comp_data.type == "Resistor":
			var R = comp_data.properties["resistance"]
			var term1 = comp_data.terminals["T1"]
			var term2 = comp_data.terminals["T2"]
			var node1_id = terminal_connections.get(term1.get_instance_id(), -1)
			var node2_id = terminal_connections.get(term2.get_instance_id(), -1)
			var V1 = electrical_nodes.get(node1_id, {}).get("voltage", NAN)
			var V2 = electrical_nodes.get(node2_id, {}).get("voltage", NAN)
			if not is_nan(V1) and not is_nan(V2) and R > 1e-12:
				var current = (V1 - V2) / R
				component_results[comp_id]["current"] = current

		elif comp_data.type == "LED":
			var R_led_model = R_LED_ON
			var term_a = comp_data.terminals["A"]
			var term_k = comp_data.terminals["K"]
			var node_a_id = terminal_connections.get(term_a.get_instance_id(), -1)
			var node_k_id = terminal_connections.get(term_k.get_instance_id(), -1)
			var Va = electrical_nodes.get(node_a_id, {}).get("voltage", NAN)
			var Vk = electrical_nodes.get(node_k_id, {}).get("voltage", NAN)
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
			
			component_results[comp_id]["current"] = current

		elif comp_data.type == "Diode":
			var R_diode_on_model = R_DIODE_ON
			var Vf_diode_calc = comp_data.properties["forward_voltage"]
			var term_a = comp_data.terminals["A"]
			var term_k = comp_data.terminals["K"]
			var node_a_id = terminal_connections.get(term_a.get_instance_id(), -1)
			var node_k_id = terminal_connections.get(term_k.get_instance_id(), -1)
			var Va = electrical_nodes.get(node_a_id, {}).get("voltage", NAN)
			var Vk = electrical_nodes.get(node_k_id, {}).get("voltage", NAN)
			var current = 0.0
			var log_msg_suffix = "Not Conducting"

			if comp_data.get("conducting", false) and not is_nan(Va) and not is_nan(Vk):
				var V_ak_calc = Va - Vk
				if V_ak_calc > Vf_diode_calc: 
					current = (V_ak_calc - Vf_diode_calc) / R_diode_on_model
				else:
					current = 0.0 
				log_msg_suffix = "Conducting (flag was true)"
			else: 
				current = 0.0
				if is_nan(Va) or is_nan(Vk):
					log_msg_suffix = "Not Conducting (NaN voltages)"

			component_results[comp_id]["current"] = current

		elif comp_data.type == "Switch":
			var state: Switch3D.State = comp_data.state 
			var R_closed = R_SWITCH_CLOSED
			var term_com = comp_data.terminals["COM"]
			var node_com_id = terminal_connections.get(term_com.get_instance_id(), -1)
			var V_com = electrical_nodes.get(node_com_id, {}).get("voltage", NAN)
			var active_term_name = "NC" if state == Switch3D.State.CONNECTED_NC else "NO"
			var active_term = comp_data.terminals[active_term_name]
			var active_node_id = terminal_connections.get(active_term.get_instance_id(), -1)
			var V_active = electrical_nodes.get(active_node_id, {}).get("voltage", NAN)
			var current = NAN
			if not is_nan(V_com) and not is_nan(V_active):
				current = (V_com - V_active) / R_closed
			component_results[comp_id]["current"] = current
		
		elif comp_data.type == "PolarizedCapacitor":
			var C_val = comp_data.properties["capacitance"]
			var max_V_cap = comp_data.properties["max_voltage"]
			var Vc_prev_dt_val = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)

			var term1_cap_node = comp_data.terminals["T1"] 
			var term2_cap_node = comp_data.terminals["T2"] 
			var node1_id_cap_val = terminal_connections.get(term1_cap_node.get_instance_id(), -1)
			var node2_id_cap_val = terminal_connections.get(term2_cap_node.get_instance_id(), -1)

			var V1_cap_t = electrical_nodes.get(node1_id_cap_val, {}).get("voltage", NAN) 
			var V2_cap_t = electrical_nodes.get(node2_id_cap_val, {}).get("voltage", NAN) 
			
			var current_cap = NAN
			var Vc_t = NAN 

			if comp_data.get("is_exploded", false):
				current_cap = 0.0 
				if not is_nan(V1_cap_t) and not is_nan(V2_cap_t): Vc_t = V1_cap_t - V2_cap_t
			elif not is_nan(V1_cap_t) and not is_nan(V2_cap_t):
				Vc_t = V1_cap_t - V2_cap_t 
				
				var reverse_polarity_tolerance = -0.1 
				if Vc_t > max_V_cap or Vc_t < reverse_polarity_tolerance: 
					comp_data.is_exploded = true
					current_cap = 0.0 
				else: 
					current_cap = C_val * (Vc_t - Vc_prev_dt_val) / delta_time
					comp_data.properties["voltage_across_cap_prev_dt"] = Vc_t 
			else: 
				pass
			
			component_results[comp_id]["current"] = current_cap
			component_results[comp_id]["voltage_across"] = Vc_t
			component_results[comp_id]["is_exploded"] = comp_data.get("is_exploded", false)
		
		elif comp_data.type == "NonPolarizedCapacitor":
			var C_np_val = comp_data.properties["capacitance"]
			var max_V_np_cap = comp_data.properties["max_voltage"] 
			var Vc_prev_dt_np_val = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)

			var term1_np_cap_node = comp_data.terminals["T1"]
			var term2_np_cap_node = comp_data.terminals["T2"]
			var node1_id_np_cap_val = terminal_connections.get(term1_np_cap_node.get_instance_id(), -1)
			var node2_id_np_cap_val = terminal_connections.get(term2_np_cap_node.get_instance_id(), -1)

			var V1_np_cap_t = electrical_nodes.get(node1_id_np_cap_val, {}).get("voltage", NAN)
			var V2_np_cap_t = electrical_nodes.get(node2_id_np_cap_val, {}).get("voltage", NAN)
			
			var current_np_cap = NAN
			var Vc_np_t = NAN

			if not is_nan(V1_np_cap_t) and not is_nan(V2_np_cap_t):
				Vc_np_t = V1_np_cap_t - V2_np_cap_t
				current_np_cap = C_np_val * (Vc_np_t - Vc_prev_dt_np_val) / delta_time
				comp_data.properties["voltage_across_cap_prev_dt"] = Vc_np_t 
				
				var over_voltage_info = ""
				if abs(Vc_np_t) > max_V_np_cap: 
					over_voltage_info = " (WARNING: Exceeds Max Voltage {max_v_s}V)".format({"max_v_s": String.num(max_V_np_cap,2)})

			else:
				pass

			component_results[comp_id]["current"] = current_np_cap
			component_results[comp_id]["voltage_across"] = Vc_np_t

		elif comp_data.type == "Inductor":
			var I_L_t_val = component_results[comp_id].get("current", NAN) 
			var V_across_L_val = component_results[comp_id].get("voltage_across", NAN) 

			if not is_nan(I_L_t_val):
				comp_data.properties["current_through_L_prev_dt"] = I_L_t_val 
			
		
		elif comp_data.type == "NPNBJT":
			var Vc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["C"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Vb = electrical_nodes.get(terminal_connections.get(comp_data.terminals["B"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Ve = electrical_nodes.get(terminal_connections.get(comp_data.terminals["E"].get_instance_id(), -1), {}).get("voltage", NAN)
			
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
			
			component_results[comp_id]["Ic"] = Ic
			component_results[comp_id]["Ib"] = Ib
			component_results[comp_id]["Ie"] = Ie
			component_results[comp_id]["region"] = region 
			

		elif comp_data.type == "NChannelMOSFET":
			var Vd_nmos_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["D"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Vg_nmos_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["G"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Vs_nmos_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["S"].get_instance_id(), -1), {}).get("voltage", NAN)
			
			var region_nmos_calc = comp_data.properties["operating_region"]
			var vt_nmos_model_calc = comp_data.properties["threshold_voltage"]
			var kn_nmos_model_calc = comp_data.properties["transconductance_parameter"]
			
			var Id_nmos: float = NAN
			var Vgs_nmos_actual: float = NAN
			var Vds_nmos_actual: float = NAN

			if not is_nan(Vg_nmos_calc) and not is_nan(Vs_nmos_calc) and not is_nan(Vd_nmos_calc):
				Vgs_nmos_actual = Vg_nmos_calc - Vs_nmos_calc
				Vds_nmos_actual = Vd_nmos_calc - Vs_nmos_calc
				var vgs_vt_diff_calc = Vgs_nmos_actual - vt_nmos_model_calc

				if region_nmos_calc == "OFF": 
					Id_nmos = 0.0
				elif region_nmos_calc == "TRIODE": 
					Id_nmos = kn_nmos_model_calc * (vgs_vt_diff_calc * Vds_nmos_actual - 0.5 * pow(Vds_nmos_actual, 2.0))
					if Id_nmos < 0 : Id_nmos = 0 
				elif region_nmos_calc == "SATURATION": 
					Id_nmos = 0.5 * kn_nmos_model_calc * pow(vgs_vt_diff_calc, 2.0)
					if Id_nmos < 0 : Id_nmos = 0 
			
			component_results[comp_id]["Id"] = Id_nmos
			component_results[comp_id]["Vgs"] = Vgs_nmos_actual
			component_results[comp_id]["Vds"] = Vds_nmos_actual
			component_results[comp_id]["region"] = region_nmos_calc
			
		
		elif comp_data.type == "PNPBJT":
			var Ve_pnp_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["E"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Vb_pnp_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["B"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Vc_pnp_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["C"].get_instance_id(), -1), {}).get("voltage", NAN)
			
			var region_pnp_calc = comp_data.properties["operating_region"]
			var beta_pnp_calc = comp_data.properties["beta_dc"]
			var veb_on_pnp_model_calc = comp_data.properties["veb_on"]
			var vec_sat_pnp_model_calc = comp_data.properties["vec_sat"]
			
			var Ic_pnp: float = NAN 
			var Ib_pnp: float = NAN 
			var Ie_pnp: float = NAN 
			
			var R_eb_active_model_pnp_calc = 50.0
			var R_ec_sat_model_pnp_calc = 5.0

			if not is_nan(Ve_pnp_calc) and not is_nan(Vb_pnp_calc) and not is_nan(Vc_pnp_calc):
				var Veb_actual_pnp = Ve_pnp_calc - Vb_pnp_calc
				var Vec_actual_pnp = Ve_pnp_calc - Vc_pnp_calc
				
				if region_pnp_calc == "OFF":
					Ib_pnp = 0.0; Ic_pnp = 0.0; Ie_pnp = 0.0
				elif region_pnp_calc == "ACTIVE":
					if Veb_actual_pnp > veb_on_pnp_model_calc:
						Ib_pnp = (Veb_actual_pnp - veb_on_pnp_model_calc) / R_eb_active_model_pnp_calc
					else:
						Ib_pnp = 0.0
					if Ib_pnp < 0.0: Ib_pnp = 0.0
					
					Ic_pnp = beta_pnp_calc * Ib_pnp
					Ie_pnp = Ic_pnp + Ib_pnp
				elif region_pnp_calc == "SATURATION":
					if Veb_actual_pnp > veb_on_pnp_model_calc:
						Ib_pnp = (Veb_actual_pnp - veb_on_pnp_model_calc) / R_eb_active_model_pnp_calc
					else:
						Ib_pnp = 0.0
					if Ib_pnp < 0.0: Ib_pnp = 0.0

					if Vec_actual_pnp > vec_sat_pnp_model_calc:
						Ic_pnp = (Vec_actual_pnp - vec_sat_pnp_model_calc) / R_ec_sat_model_pnp_calc
					else:
						Ic_pnp = 0.0 
					if Ic_pnp < 0.0: Ic_pnp = 0.0
					Ie_pnp = Ic_pnp + Ib_pnp
			
			component_results[comp_id]["Ic"] = Ic_pnp
			component_results[comp_id]["Ib"] = Ib_pnp
			component_results[comp_id]["Ie"] = Ie_pnp
			component_results[comp_id]["region"] = region_pnp_calc
			

		elif comp_data.type == "ZenerDiode":
			var state_z = comp_data.properties["operating_state"]
			var Vf_z_calc = comp_data.properties["forward_voltage"]
			var Vz_calc = comp_data.properties["zener_voltage"] 
			var R_on_z_model = 0.1 

			var term_a_z_node = comp_data.terminals["A"]
			var term_k_z_node = comp_data.terminals["K"]
			var node_a_id_z_val = terminal_connections.get(term_a_z_node.get_instance_id(), -1)
			var node_k_id_z_val = terminal_connections.get(term_k_z_node.get_instance_id(), -1)

			var Va_z_val = electrical_nodes.get(node_a_id_z_val, {}).get("voltage", NAN)
			var Vk_z_val = electrical_nodes.get(node_k_id_z_val, {}).get("voltage", NAN)
			
			var current_zener = NAN
			var Vak_z_val = NAN

			if not is_nan(Va_z_val) and not is_nan(Vk_z_val):
				Vak_z_val = Va_z_val - Vk_z_val
				if state_z == "FORWARD":
					if Vak_z_val > Vf_z_calc:
						current_zener = (Vak_z_val - Vf_z_calc) / R_on_z_model 
					else:
						current_zener = 0.0
				elif state_z == "ZENER":
					if (Vk_z_val - Va_z_val) > Vz_calc : 
						current_zener = -( (Vk_z_val - Va_z_val) - Vz_calc ) / R_on_z_model
					else: 
						current_zener = 0.0

				elif state_z == "OFF":
					current_zener = 0.0
			
			component_results[comp_id]["current"] = current_zener
			component_results[comp_id]["voltage_ak"] = Vak_z_val 
			component_results[comp_id]["state"] = state_z
			
			
		elif comp_data.type == "Relay":
			var term_vcc_res = comp_data.terminals["VCC"]
			var term_gnd_res = comp_data.terminals["GND"]
			var term_sig_res = comp_data.terminals["Signal"]
			
			var node_vcc_id_res = terminal_connections.get(term_vcc_res.get_instance_id(), -1)
			var node_gnd_id_res = terminal_connections.get(term_gnd_res.get_instance_id(), -1)
			var node_sig_id_res = terminal_connections.get(term_sig_res.get_instance_id(), -1)

			var V_vcc_res = electrical_nodes.get(node_vcc_id_res, {}).get("voltage", NAN)
			var V_gnd_res = electrical_nodes.get(node_gnd_id_res, {}).get("voltage", NAN)
			var V_sig_res = electrical_nodes.get(node_sig_id_res, {}).get("voltage", NAN)
			
			var actual_signal_voltage = NAN
			if not is_nan(V_sig_res) and not is_nan(V_gnd_res):
				actual_signal_voltage = V_sig_res - V_gnd_res
				
			var actual_vcc_voltage = NAN
			if not is_nan(V_vcc_res) and not is_nan(V_gnd_res):
				actual_vcc_voltage = V_vcc_res - V_gnd_res

			var actual_coil_current = NAN
			var coil_R_val_res = comp_data.properties["coil_resistance"]
			var is_energized_res = comp_data.properties["is_energized"]

			if is_energized_res and not is_nan(actual_vcc_voltage) and coil_R_val_res > 1e-9:
				actual_coil_current = actual_vcc_voltage / coil_R_val_res
			elif not is_energized_res: 
				actual_coil_current = 0.0
			
			component_results[comp_id]["signal_voltage"] = actual_signal_voltage
			component_results[comp_id]["vcc_voltage"] = actual_vcc_voltage
			component_results[comp_id]["coil_current"] = actual_coil_current
			component_results[comp_id]["is_energized"] = is_energized_res
			component_results[comp_id]["signal_threshold"] = comp_data.properties["signal_voltage_threshold"]

			var R_sw_closed_calc = R_SWITCH_CLOSED
			var com_term_calc = comp_data.terminals["COM"]
			var no_term_calc = comp_data.terminals["NO"]
			var nc_term_calc = comp_data.terminals["NC"]
			var V_com_calc = electrical_nodes.get(terminal_connections.get(com_term_calc.get_instance_id(), -1), {}).get("voltage", NAN)
			var V_no_calc = electrical_nodes.get(terminal_connections.get(no_term_calc.get_instance_id(), -1), {}).get("voltage", NAN)
			var V_nc_calc = electrical_nodes.get(terminal_connections.get(nc_term_calc.get_instance_id(), -1), {}).get("voltage", NAN)
			
			var contact_current_str = ""
			if is_energized_res and not is_nan(V_com_calc) and not is_nan(V_no_calc):
				var i_no = (V_com_calc - V_no_calc) / R_sw_closed_calc
				contact_current_str = ", I_NO={ino_s}A".format({"ino_s": String.num(i_no,3)})
			elif not is_energized_res and not is_nan(V_com_calc) and not is_nan(V_nc_calc):
				var i_nc = (V_com_calc - V_nc_calc) / R_sw_closed_calc
				contact_current_str = ", I_NC={inc_s}A".format({"inc_s": String.num(i_nc,3)})


		elif comp_data.type == "Potentiometer":
			var total_R = comp_data.properties["total_resistance"]
			var wiper_pos = comp_data.properties["wiper_position"]

			var R1_val = total_R * wiper_pos
			if R1_val < 1e-12: R1_val = 1e-12 
			
			var R2_val = total_R * (1.0 - wiper_pos)
			if R2_val < 1e-12: R2_val = 1e-12

			var term1_node = comp_data.terminals["T1"]
			var term2_node = comp_data.terminals["T2"]
			var termW_node = comp_data.terminals["W"]

			var node1_id = terminal_connections.get(term1_node.get_instance_id(), -1)
			var node2_id = terminal_connections.get(term2_node.get_instance_id(), -1)
			var nodeW_id = terminal_connections.get(termW_node.get_instance_id(), -1)

			var V1 = electrical_nodes.get(node1_id, {}).get("voltage", NAN)
			var V2 = electrical_nodes.get(node2_id, {}).get("voltage", NAN)
			var VW = electrical_nodes.get(nodeW_id, {}).get("voltage", NAN)

			var current1W = NAN
			if not is_nan(V1) and not is_nan(VW):
				current1W = (V1 - VW) / R1_val if R1_val > 1e-12 else (V1 - VW) * 1e12 

			var currentW2 = NAN
			if not is_nan(VW) and not is_nan(V2):
				currentW2 = (VW - V2) / R2_val if R2_val > 1e-12 else (VW - V2) * 1e12

			component_results[comp_id]["current_T1_W"] = current1W
			component_results[comp_id]["current_W_T2"] = currentW2
			component_results[comp_id]["current_Wiper_Net"] = current1W - currentW2 if not is_nan(current1W) and not is_nan(currentW2) else NAN
			
		



## Resets the burn state of a specified LED.
func reset_led_burn_state(component_node: Node3D): 
	for comp_data_item in components: 
		if comp_data_item.component_node == component_node and comp_data_item.type == "LED":
			if comp_data_item.get("is_burned", false): 
				comp_data_item.is_burned = false
				_is_solved = false 
				_needs_rebuild = true 
			return 
