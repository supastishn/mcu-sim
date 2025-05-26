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


func _get_new_node_id() -> int:
	_next_node_id += 1
	return _next_node_id


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



func _reset_voltages():
	component_results.clear() 
	_is_solved = false





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

		# --- BEGIN refactored nonlinear‐state update loop ---
		var state_changed_this_iteration = false
		for comp_data_item in components:
			var component_node = comp_data_item.component_node # Renamed 'node' to 'component_node' for clarity
			if is_instance_valid(component_node) and component_node.has_method("update_nonlinear_state"):
				# Assuming CircuitGraph might store these if needed by components like PowerSource
				# self._current_iteration_solution = x 
				# self._current_iteration_vs_map = active_vs_map_iter
				# self._current_iteration_node_map = node_map_iter
				# self._current_iteration_inductor_map = inductor_map_iter
				if component_node.update_nonlinear_state(self, comp_data_item, x, active_vs_map_iter): # Pass x and active_vs_map_iter
					state_changed_this_iteration = true

		if not state_changed_this_iteration and not x.is_empty():
			converged = true
			break
		# --- END refactored loop ---

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


	
	
	
	for cd_item_prep in components:
		if cd_item_prep.type == "NChannelMOSFET":
			var term_g_nmos_prep = cd_item_prep.terminals["G"]
			var term_s_nmos_prep = cd_item_prep.terminals["S"]
			var node_g_id_nmos_prep = terminal_connections.get(term_g_nmos_prep.get_instance_id(), -1) if is_instance_valid(term_g_nmos_prep) else -1
			var node_s_id_nmos_prep = terminal_connections.get(term_s_nmos_prep.get_instance_id(), -1) if is_instance_valid(term_s_nmos_prep) else -1
			
			cd_item_prep.properties["_internal_Vg_stamp"] = electrical_nodes.get(node_g_id_nmos_prep, {}).get("voltage", 0.0)
			cd_item_prep.properties["_internal_Vs_stamp"] = electrical_nodes.get(node_s_id_nmos_prep, {}).get("voltage", 0.0)

	for comp_data_item in components:
		var component_node = comp_data_item.component_node
		if is_instance_valid(component_node) and component_node.has_method("stamp"):
			component_node.stamp(
				A,
				b,
				node_id_to_matrix_index,
				active_vs_id_to_matrix_index, 
				inductor_id_to_matrix_index,  
				terminal_connections,
				comp_data_item,        
				delta_time
			)
			
	_needs_rebuild = false
	return { "A": A, "b": b, "node_map": node_id_to_matrix_index, "vs_map": active_vs_id_to_matrix_index, "inductor_map": inductor_id_to_matrix_index }




























































































































































































































































































































































































































































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
			
		




func reset_led_burn_state(component_node: Node3D): 
	for comp_data_item in components: 
		if comp_data_item.component_node == component_node and comp_data_item.type == "LED":
			if comp_data_item.get("is_burned", false): 
				comp_data_item.is_burned = false
				_is_solved = false 
				_needs_rebuild = true 
			return 
