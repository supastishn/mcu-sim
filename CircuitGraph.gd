extends Node

class_name CircuitGraph

const LinearSolver = preload("res://LinearSolver.gd")
const R_LED_ON            := 0.1
const R_LED_OFF           := 1.0e9
const R_DIODE_ON          := R_LED_ON
const R_DIODE_OFF         := R_LED_OFF
const R_SWITCH_CLOSED     := 1e-6
const R_SWITCH_OPEN       := 1.0e12

## Helper function for string formatting.
static func fmt(t : String, d : Dictionary) -> String:
	return t.format(d)

## Voltage margin used to determine if a BJT is in saturation.
const BJT_SATURATION_VOLTAGE_MARGIN: float = 0.05 


## Maps terminal instance IDs to electrical node IDs.
var terminal_connections: Dictionary = {} 

## Stores data for each electrical node, including connected terminals and solved voltage.
var electrical_nodes: Dictionary = {} 

## An array containing data for each component in the circuit.
var components: Array[Dictionary] = []
## Stores the latest simulation results for each component, keyed by instance ID.
var component_results: Dictionary = {}

## Maps component Node3D instances to their data dictionary in the `components` array.
var component_node_map: Dictionary = {}

## The ID of the node designated as ground (0V reference).
var ground_node_id: int = -1 


## Stamps a conductance `g_val` between two nodes into the MNA matrix `A`.
static func stamp_conductance(matrix_A: Array, g_val: float, idx1: int, idx2: int) -> void:
	if idx1 != -1:
		matrix_A[idx1][idx1] += g_val
	if idx2 != -1:
		matrix_A[idx2][idx2] += g_val
	if idx1 != -1 and idx2 != -1:
		matrix_A[idx1][idx2] -= g_val
		matrix_A[idx2][idx1] -= g_val
## Flag indicating if the circuit has a valid solution from the last simulation step.
var _is_solved: bool = false 
## Flag indicating if the MNA system needs to be rebuilt due to circuit changes.
var _needs_rebuild: bool = true 

# --- MNA System Caching for Performance ---
var _cached_system: Dictionary = {}
var _cached_delta_time: float = 0.0

## A counter to generate unique electrical node IDs.
var _next_node_id: int = 0
var _next_internal_node_id: int = -1 # Use negative numbers for internal nodes

## Returns a new unique ID for an electrical node.
func _get_new_node_id() -> int:
	_next_node_id += 1
	return _next_node_id


## Adds a component to the circuit graph, creating its data structure.
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
		component_data.properties["saturation_current"] = component.saturation_current
		component_data.properties["ideality_factor"] = component.ideality_factor
		component_data.terminals["A"] = component.terminal_anode
		component_data.terminals["K"] = component.terminal_kathode
		component_data["conducting"] = false 
		component_data.is_burned = false 
	elif component is Diode3D:
		component_data.type = "Diode"
		component_data.properties["saturation_current"] = component.saturation_current
		component_data.properties["ideality_factor"] = component.ideality_factor
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
	elif component is PChannelMOSFET3D:
		component_data.type = "PChannelMOSFET"
		component_data.properties["threshold_voltage"]           = component.threshold_voltage
		component_data.properties["transconductance_parameter"]  = component.transconductance_parameter
		component_data.properties["operating_region"]            = "OFF"
		component_data.terminals["D"] = component.terminal_d
		component_data.terminals["G"] = component.terminal_g
		component_data.terminals["S"] = component.terminal_s
	elif component is LinearRegulator3D:
		component_data.type = "LinearRegulator"
		component_data.properties["regulated_voltage"] = component.regulated_voltage
		component_data.properties["dropout_voltage"] = component.dropout_voltage
		component_data.properties["max_current"] = component.max_current
		component_data.properties["status"] = "UNKNOWN"
		component_data.terminals["Vin"] = component.terminal_vin
		component_data.terminals["Vout"] = component.terminal_vout
		component_data.terminals["GND"] = component.terminal_gnd
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
	elif component is OpAmp3D:
		component_data.type = "OpAmp"
		component_data.properties["open_loop_gain"] = component.open_loop_gain
		component_data.properties["rail_saturation_voltage"] = component.rail_saturation_voltage
		component_data.properties["operating_region"] = "LINEAR" # Start in linear region
		component_data.terminals["Vp"] = component.terminal_vp
		component_data.terminals["Vn"] = component.terminal_vn
		component_data.terminals["Vout"] = component.terminal_vout
		component_data.terminals["Vcc"] = component.terminal_vcc
		component_data.terminals["Vee"] = component.terminal_vee
	elif component is Breadboard3D:
		component_data.type = "Breadboard"

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

	component_node_map[component] = component_data



## Removes a component from the circuit graph and cleans up its terminal connections.
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
	component_node_map.erase(component_node)



## Connects two component terminals, merging their electrical nodes.
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


## Designates the electrical node connected to the given terminal as the circuit's ground reference.
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

## Returns a unique ID for an internal node within a component.
func _get_internal_node_id() -> int:
	_next_internal_node_id -= 1
	return _next_internal_node_id

## Registers dynamically created terminals from a component like a breadboard.
func register_dynamic_terminals(component_node: Node3D, terminals: Array):
	var component_data = component_node_map.get(component_node)
	if component_data:
		for terminal in terminals:
			if terminal is Area3D:
				component_data.terminals[terminal.name] = terminal
				var term_id = terminal.get_instance_id()
				if not terminal_connections.has(term_id):
					var new_node_id = _get_new_node_id()
					electrical_nodes[new_node_id] = { "terminals": [terminal], "voltage": NAN }
					terminal_connections[term_id] = new_node_id


## Updates the graph's internal data for a component whose properties have changed.
func component_config_changed(component_node: Node3D):
	_is_solved = false
	_needs_rebuild = true
	var found_component_data: Dictionary = component_node_map.get(component_node, {})
	
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
		found_component_data.properties["saturation_current"] = component_node.saturation_current
		found_component_data.properties["ideality_factor"] = component_node.ideality_factor
		found_component_data.is_burned = false 
	elif comp_type == "Diode" and component_node is Diode3D:
		found_component_data.properties["saturation_current"] = component_node.saturation_current
		found_component_data.properties["ideality_factor"] = component_node.ideality_factor
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
	elif comp_type == "PChannelMOSFET" and component_node is PChannelMOSFET3D:
		found_component_data.properties["threshold_voltage"]          = component_node.threshold_voltage
		found_component_data.properties["transconductance_parameter"] = component_node.transconductance_parameter
		found_component_data.properties["operating_region"]           = "OFF"
	elif comp_type == "Relay" and component_node is Relay3D:
		found_component_data.properties["signal_voltage_threshold"] = component_node.signal_voltage_threshold
		found_component_data.properties["coil_resistance"] = component_node.coil_resistance
		found_component_data.properties["is_energized"] = false 
	elif comp_type == "LinearRegulator" and component_node is LinearRegulator3D:
		found_component_data.properties["regulated_voltage"] = component_node.regulated_voltage
		found_component_data.properties["dropout_voltage"] = component_node.dropout_voltage
		found_component_data.properties["max_current"] = component_node.max_current
	elif comp_type == "OpAmp" and component_node is OpAmp3D:
		found_component_data.properties["open_loop_gain"] = component_node.open_loop_gain
		found_component_data.properties["rail_saturation_voltage"] = component_node.rail_saturation_voltage
		found_component_data.properties["operating_region"] = "LINEAR"
	else:
		return



## Resets all solved voltages and clears simulation results.
func _reset_voltages():
	component_results.clear() 
	_is_solved = false





## Solves the circuit for a single transient time step using a Newton-Raphson solver.
func solve_single_time_step(delta_time: float) -> bool:
	_is_solved = false
	if ground_node_id == -1: return false

	# Reset stateful components that have state machines
	for comp_data_item in components:
		if comp_data_item.type in ["ZenerDiode", "Relay", "NPNBJT", "PNPBJT", "NChannelMOSFET", "PChannelMOSFET", "OpAmp"]:
			# The old BJT/MOSFET models need this reset. It's safe for new models.
			if comp_data_item.has("properties") and comp_data_item.properties.has("operating_region"):
				comp_data_item.properties["operating_region"] = "OFF"
			if comp_data_item.has("properties") and comp_data_item.properties.has("operating_state"):
				comp_data_item.properties["operating_state"] = "OFF"
			if comp_data_item.has("properties") and comp_data_item.properties.has("is_energized"):
				comp_data_item.properties["is_energized"] = false

	# --- MNA System Caching ---
	var system
	if not _needs_rebuild and is_equal_approx(delta_time, _cached_delta_time):
		print("Reusing cached MNA system")
		system = _cached_system
	else:
		system = _build_mna_system(delta_time)
		_cached_system = system
		_cached_delta_time = delta_time

	var converged = _solve_newton_raphson(delta_time)
	
	if not converged:
		printerr("Solver failed to converge.")
		# Clear results to indicate failure
		component_results.clear()
		return false
	
	_is_solved = true
	var final_system = system

	var final_solution = []
	final_solution.resize(final_system.A.size())
	final_solution.fill(0.0)
	for node_id in final_system.node_map:
		var index = final_system.node_map[node_id]
		final_solution[index] = electrical_nodes[node_id].voltage
	# Populate current variables for VS and Inductors
	# This part is complex and requires solving the final system one last time
	# to get the current variables. For simplicity, we skip this and calculate
	# currents in gather_sim_results where possible.

	# Gather final results from all components
	component_results.clear()
	for comp_data_item in components:
		var node = comp_data_item.component_node
		var comp_id = node.get_instance_id()
		if not comp_id in component_results: component_results[comp_id] = {}
		if is_instance_valid(node) and node.has_method("gather_sim_results"):
			node.gather_sim_results(self, comp_data_item, final_solution, final_system.node_map, final_system.vs_map, final_system.inductor_map, delta_time)
	
	return true

func _solve_newton_raphson(delta_time: float) -> bool:
	var max_iter = 100
	var v_tolerance = 1e-6

	for i in range(max_iter):
		var system = _build_mna_system(delta_time)
		var A = system.A
		var b_error = _calculate_kcl_error_vector(system)
		
		if A.is_empty(): return true

		# Newton-Raphson: Solve A * dV = F(V)
		var delta_x = LinearSolver.solve(A, b_error)

		if delta_x.is_empty():
			printerr("LinearSolver failed in Newton-Raphson iteration.")
			return false

		# Adaptive damping for stability
		var norm = sqrt(delta_x.reduce(func(acc, val): return acc + val*val, 0.0))
		var damping_factor = clamp(0.1 * log(norm + 1) + 0.3, 0.1, 0.8)
		var node_map = system.node_map
		for node_id in node_map:
			var index = node_map[node_id]
			if electrical_nodes.has(node_id):
				electrical_nodes[node_id].voltage += damping_factor * delta_x[index]

		if _check_convergence(delta_x, v_tolerance):
			return true

	return false

func _calculate_kcl_error_vector(system: Dictionary) -> Array:
	var num_vars = system.A.size()
	var error_vector: Array = []
	error_vector.resize(num_vars)
	error_vector.fill(0.0)

	# Independent sources are already in b, so just add component currents
	error_vector = system.b.duplicate()

	for comp_data in components:
		if not comp_data.component_node.has_method("get_kcl_contributions"):
			continue

		var node_voltages = {}
		for term_name in comp_data.terminals:
			var terminal = comp_data.terminals[term_name]
			var node_id = terminal_connections.get(terminal.get_instance_id(), -1)
			node_voltages[term_name] = electrical_nodes.get(node_id, {}).get("voltage", 0.0)
		
		comp_data.component_node.get_kcl_contributions(node_voltages, error_vector, system.node_map)

	# The vector we want is the error, which is the sum of currents at each node.
	# The update is J*dV = -F(V), so we need to negate the final vector.
	return error_vector.map(func(v): return -v)

func _update_voltages_from_solution(delta_x: Array, system: Dictionary):
	var node_map = system.node_map
	for node_id in node_map:
		var index = node_map[node_id]
		if index < delta_x.size():
			if not electrical_nodes.has(node_id): electrical_nodes[node_id] = {"terminals": [], "voltage": 0.0}
			electrical_nodes[node_id].voltage += delta_x[index]
	
	# Update internal component voltages for next linearization
	for comp_data in components:
		var comp_type = comp_data.type
		if comp_type in ["Diode", "LED", "ZenerDiode"]:
			var va = electrical_nodes.get(terminal_connections.get(comp_data.terminals.A.get_instance_id(), -1), {}).get("voltage", 0.0)
			var vk = electrical_nodes.get(terminal_connections.get(comp_data.terminals.K.get_instance_id(), -1), {}).get("voltage", 0.0)
			comp_data.properties["_internal_voltage"] = va - vk
		elif comp_type == "NPNBJT":
			var vb = electrical_nodes.get(terminal_connections.get(comp_data.terminals.B.get_instance_id(), -1), {}).get("voltage", 0.0)
			var ve = electrical_nodes.get(terminal_connections.get(comp_data.terminals.E.get_instance_id(), -1), {}).get("voltage", 0.0)
			var vc = electrical_nodes.get(terminal_connections.get(comp_data.terminals.C.get_instance_id(), -1), {}).get("voltage", 0.0)
			comp_data.properties["_internal_vbe"] = vb - ve
			comp_data.properties["_internal_vbc"] = vb - vc
		elif comp_type == "PNPBJT":
			var ve = electrical_nodes.get(terminal_connections.get(comp_data.terminals.E.get_instance_id(), -1), {}).get("voltage", 0.0)
			var vb = electrical_nodes.get(terminal_connections.get(comp_data.terminals.B.get_instance_id(), -1), {}).get("voltage", 0.0)
			var vc = electrical_nodes.get(terminal_connections.get(comp_data.terminals.C.get_instance_id(), -1), {}).get("voltage", 0.0)
			comp_data.properties["_internal_veb"] = ve - vb
			comp_data.properties["_internal_vcb"] = vc - vb

func _check_convergence(delta_x: Array, v_tol: float) -> bool:
	var norm = delta_x.reduce(func(acc, val): return acc + val*val, 0.0)
	return sqrt(norm) < v_tol





## Builds the Modified Nodal Analysis (MNA) system matrices (A, b) and corresponding node maps for the current state of the circuit.
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
	
	# Discover internal nodes required by components
	var internal_nodes: Array[int] = []
	for comp in components:
		if comp.component_node.has_method("get_internal_nodes"):
			var comp_internal_nodes = comp.component_node.get_internal_nodes(self)
			for internal_node_id in comp_internal_nodes:
				if not internal_nodes.has(internal_node_id):
					internal_nodes.push_back(internal_node_id)

	var num_internal_nodes = internal_nodes.size()
	for i in range(num_internal_nodes):
		var internal_node_id = internal_nodes[i]
		node_id_to_matrix_index[internal_node_id] = num_nodes + num_active_vs + num_inductors + i
		if not electrical_nodes.has(internal_node_id):
			electrical_nodes[internal_node_id] = {"terminals": [], "voltage": 0.0}
		
	N += num_internal_nodes
		
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




























































































































































































































































































































































































































































## Resets the 'is_burned' state of an LED component.
func reset_led_burn_state(component_node: Node3D): 
	for comp_data_item in components: 
		if comp_data_item.component_node == component_node and comp_data_item.type == "LED":
			if comp_data_item.get("is_burned", false): 
				comp_data_item.is_burned = false
				_is_solved = false 
				_needs_rebuild = true 
			return 
