extends Node

class_name CircuitGraph

enum LogLevel { NONE, LOW, HIGH }
@export var current_log_level: LogLevel = LogLevel.LOW

func _log(message: String, level: LogLevel = LogLevel.HIGH, is_error: bool = false):
	return
	if current_log_level == LogLevel.NONE:
		return
	if level == LogLevel.NONE: # Explicitly logging at NONE level means don't log
		return
	if level > current_log_level:
		return
	if is_error:
		printerr(message)
	else:
		print(message)

const LinearSolver = preload("res://LinearSolver.gd")
const BJT_SATURATION_VOLTAGE_MARGIN: float = 0.05 # Margin for Vce/Vec check in saturation

# Manages the logical representation of the electrical circuit.

# Maps terminal Area3D instance IDs to the electrical node ID they are connected to.
var terminal_connections: Dictionary = {} # { terminal_instance_id: node_id }

# Stores information about each electrical node (net).
var electrical_nodes: Dictionary = {} # { node_id: { terminals: Array[Area3D], voltage: float (NaN until solved) } }

# List of components with their electrical properties
# Structure: [ { component_node: Node3D, type: String, properties: Dictionary, terminals: {term_name: Area3D} }, ... ]
var components: Array[Dictionary] = []
# Stores results specific to components after simulation (e.g., current, voltage across CC source)
# Structure: { component_instance_id: { "current": float, "voltage": float } }
var component_results: Dictionary = {}

# ID of the node designated as ground (0V reference)
var ground_node_id: int = -1 # -1 means no ground is set
var _is_solved: bool = false # Flag indicating if the circuit has been successfully solved
var _needs_rebuild: bool = true # Flag if MNA matrix needs rebuilding (component add/remove/state change)

var _next_node_id: int = 0

## Generates a new unique ID for an electrical node.
func _get_new_node_id() -> int:
	_next_node_id += 1
	return _next_node_id

## Registers a component and its terminals.
func add_component(component: Node3D):
	_is_solved = false # Adding a component invalidates the previous solution
	_needs_rebuild = true
	# Avoid adding duplicates - check if the component node is already tracked
	for comp_data in components:
		if comp_data.component_node == component:
			_log("Component {comp_name} already added to graph.".format({"comp_name": component.name}), LogLevel.HIGH)
			return

	var component_data: Dictionary = {
		"component_node": component,
		"type": "Unknown",
		"properties": {}, # Holds specific props like resistance, voltage, mode, etc.
		"state": -1, # For Switch state (using enum integer value)
		"terminals": {}
	}
	# component_data["conducting"] = false # Track diode conduction state # Initialized based on type

	if component is Resistor3D:
		component_data.type = "Resistor"
		component_data.properties["resistance"] = component.resistance
		component_data.terminals["T1"] = component.terminal1
		component_data.terminals["T2"] = component.terminal2
		_log("Added Resistor with R={r_val}, Terminals: {t1_name}, {t2_name}".format({"r_val": component.resistance, "t1_name": component.terminal1.name, "t2_name": component.terminal2.name}), LogLevel.LOW)
	elif component is PowerSource3D:
		component_data.type = "PowerSource"
		component_data.properties["target_voltage"] = component.target_voltage
		component_data.properties["target_current"] = component.target_current
		component_data.properties["current_operating_mode"] = "CV" # CV or CC
		component_data.properties["cc_current_direction_sign"] = 1.0 # +1 or -1, relevant for CC mode
		# component_data.properties["mode"] = component.current_mode # Mode is removed
		component_data.terminals["POS"] = component.terminal_pos # Positive terminal
		component_data.terminals["NEG"] = component.terminal_neg # Negative terminal
		_log("Added PowerSource with V_target={v_target}, I_limit={i_limit}, Mode=CV, Terminals: +({pos_term_name}), -({neg_term_name})".format({"v_target": component.target_voltage, "i_limit": component.target_current, "pos_term_name": component.terminal_pos.name, "neg_term_name": component.terminal_neg.name}), LogLevel.LOW)
	elif component is Battery3D:
		component_data.type = "Battery"
		component_data.properties["target_voltage"] = component.target_voltage # Derived from num_cells
		component_data.properties["num_cells"] = component.num_cells
		component_data.terminals["POS"] = component.terminal_pos
		component_data.terminals["NEG"] = component.terminal_neg
		_log("Added Battery with {n_cells} cells (V_target={v_target}), Terminals: +({pos_term_name}), -({neg_term_name})".format({"n_cells": component.num_cells, "v_target": component.target_voltage, "pos_term_name": component.terminal_pos.name, "neg_term_name": component.terminal_neg.name}), LogLevel.LOW)
	elif component is LED3D:
		component_data.type = "LED"
		component_data.properties["forward_voltage"] = component.forward_voltage
		component_data.terminals["A"] = component.terminal_anode # Anode terminal
		component_data.terminals["K"] = component.terminal_kathode # Kathode terminal
		component_data["conducting"] = false # Initialize conducting state for LED
		component_data.properties["min_current"] = component.min_current_to_light # Moved to properties
		component_data.properties["max_current"] = component.max_current_before_burn # Moved to properties
		component_data.is_burned = false # Initialize burned state
		_log("Added LED with Vf={vf}, MinI={min_i_str}, MaxI={max_i_str}, Terminals: A({anode_name}), K({kathode_name})".format({"vf": component.forward_voltage, "min_i_str": "%.3f" % component.min_current_to_light, "max_i_str": "%.3f" % component.max_current_before_burn, "anode_name": component.terminal_anode.name, "kathode_name": component.terminal_kathode.name}), LogLevel.LOW)
	elif component is Diode3D:
		component_data.type = "Diode"
		component_data.properties["forward_voltage"] = component.forward_voltage # Changed value to properties
		component_data.terminals["A"] = component.terminal_anode # Anode terminal
		component_data.terminals["K"] = component.terminal_kathode # Kathode terminal
		component_data["conducting"] = false # Initialize conducting state for Diode
		_log("Added Diode with Vf={vf}, Terminals: A({anode_name}), K({kathode_name})".format({"vf": component.forward_voltage, "anode_name": component.terminal_anode.name, "kathode_name": component.terminal_kathode.name}), LogLevel.LOW)
	elif component is Switch3D:
		component_data.type = "Switch"
		# component_data.properties["value"] = NAN # Switches don't have a primary numeric value (value was already NAN)
		component_data.state = component.current_state # Store initial state (as enum int)
		component_data.terminals["COM"] = component.terminal_com
		component_data.terminals["NC"] = component.terminal_nc
		component_data.terminals["NO"] = component.terminal_no
		_log("Added Switch with State={state_key}, Terminals: COM({com_name}), NC({nc_name}), NO({no_name})".format({"state_key": Switch3D.State.keys()[component.current_state], "com_name": component.terminal_com.name, "nc_name": component.terminal_nc.name, "no_name": component.terminal_no.name}), LogLevel.LOW)
	elif component is Potentiometer3D:
		component_data.type = "Potentiometer"
		component_data.properties["total_resistance"] = component.total_resistance
		component_data.properties["wiper_position"] = component.wiper_position
		
		# Robustly fetch terminal nodes
		var t1_node = component.get_node_or_null("Terminal1")
		var t2_node = component.get_node_or_null("Terminal2")
		var tw_node = component.get_node_or_null("TerminalWiper")

		component_data.terminals["T1"] = t1_node if is_instance_valid(t1_node) else null
		component_data.terminals["T2"] = t2_node if is_instance_valid(t2_node) else null
		component_data.terminals["W"] = tw_node if is_instance_valid(tw_node) else null

		# Safer print statement
		var t1_name_str = t1_node.name if is_instance_valid(t1_node) else "INVALID"
		var t2_name_str = t2_node.name if is_instance_valid(t2_node) else "INVALID"
		var w_name_str = tw_node.name if is_instance_valid(tw_node) else "INVALID"
		_log("Added Potentiometer with R_total={r_total}, Wiper={wiper_str}, Terminals: T1({t1_name}), T2({t2_name}), W({w_name})".format({"r_total": component.total_resistance, "wiper_str": "%.2f" % component.wiper_position, "t1_name": t1_name_str, "t2_name": t2_name_str, "w_name": w_name_str}), LogLevel.LOW)
	elif component is PolarizedCapacitor3D:
		component_data.type = "PolarizedCapacitor"
		component_data.properties["capacitance"] = component.capacitance
		component_data.properties["max_voltage"] = component.max_voltage
		component_data.properties["voltage_across_cap_prev_dt"] = 0.0 # Initial voltage across capacitor Vc(t-dt)
		component_data.is_exploded = false # Initialize exploded state
		component_data.terminals["T1"] = component.terminal1 # Positive
		component_data.terminals["T2"] = component.terminal2 # Negative
		_log("Added PolarizedCapacitor C={cap_str} F, MaxV={max_v_str}V, Vc(t-dt)=0.0, Terminals: T1+({t1_name}), T2-({t2_name})".format({"cap_str": String.num_scientific(component.capacitance), "max_v_str": String.num(component.max_voltage,2), "t1_name": component.terminal1.name, "t2_name": component.terminal2.name}), LogLevel.LOW)
	elif component is NonPolarizedCapacitor3D:
		component_data.type = "NonPolarizedCapacitor"
		component_data.properties["capacitance"] = component.capacitance
		component_data.properties["max_voltage"] = component.max_voltage # Store for info, not for explosion logic
		component_data.properties["voltage_across_cap_prev_dt"] = 0.0 # Initial voltage
		# No is_exploded state for non-polarized
		component_data.terminals["T1"] = component.terminal1
		component_data.terminals["T2"] = component.terminal2
		_log("Added NonPolarizedCapacitor C={cap_str} F, MaxV={max_v_str}V, Vc(t-dt)=0.0, Terminals: T1({t1_name}), T2({t2_name})".format({"cap_str": String.num_scientific(component.capacitance), "max_v_str": String.num(component.max_voltage,2), "t1_name": component.terminal1.name, "t2_name": component.terminal2.name}), LogLevel.LOW)
	elif component is Inductor3D:
		component_data.type = "Inductor"
		component_data.properties["inductance"] = component.inductance
		component_data.properties["current_through_L_prev_dt"] = 0.0 # Initial current I_L(t-dt)
		component_data.terminals["T1"] = component.terminal1
		component_data.terminals["T2"] = component.terminal2
		_log("Added Inductor L={l_str} H, I_L(t-dt)=0.0, Terminals: T1({t1_name}), T2({t2_name})".format({"l_str": String.num_scientific(component.inductance), "t1_name": component.terminal1.name, "t2_name": component.terminal2.name}), LogLevel.LOW)
	elif component is NPNBJT3D:
		component_data.type = "NPNBJT"
		component_data.properties["beta_dc"] = component.beta_dc
		component_data.properties["vbe_on"] = component.vbe_on
		component_data.properties["vce_sat"] = component.vce_sat
		component_data.properties["operating_region"] = "OFF" # Initial assumption: OFF, ACTIVE, SATURATION
		component_data.terminals["C"] = component.terminal_c
		component_data.terminals["B"] = component.terminal_b
		component_data.terminals["E"] = component.terminal_e
		_log("Added NPNBJT Beta={b_str}, Vbe_on={vbe_str}V, Vce_sat={vce_str}V, Terminals: C({c_n}), B({b_n}), E({e_n})".format({
			"b_str": String.num(component.beta_dc,1), "vbe_str": String.num(component.vbe_on,2), "vce_str": String.num(component.vce_sat,2),
			"c_n": component.terminal_c.name, "b_n": component.terminal_b.name, "e_n": component.terminal_e.name
			}), LogLevel.LOW)
	elif component is PNPBJT3D:
		component_data.type = "PNPBJT"
		component_data.properties["beta_dc"] = component.beta_dc
		component_data.properties["veb_on"] = component.veb_on # Emitter-Base voltage
		component_data.properties["vec_sat"] = component.vec_sat # Emitter-Collector saturation voltage
		component_data.properties["operating_region"] = "OFF"
		component_data.terminals["E"] = component.terminal_e # Emitter
		component_data.terminals["B"] = component.terminal_b # Base
		component_data.terminals["C"] = component.terminal_c # Collector
		_log("Added PNPBJT Beta={b_str}, Veb_on={veb_str}V, Vec_sat={vec_str}V, Terminals: E({e_n}), B({b_n}), C({c_n})".format({
			"b_str": String.num(component.beta_dc,1), "veb_str": String.num(component.veb_on,2), "vec_str": String.num(component.vec_sat,2),
			"e_n": component.terminal_e.name, "b_n": component.terminal_b.name, "c_n": component.terminal_c.name
			}), LogLevel.LOW)
	elif component is ZenerDiode3D:
		component_data.type = "ZenerDiode"
		component_data.properties["forward_voltage"] = component.forward_voltage
		component_data.properties["zener_voltage"] = component.zener_voltage
		component_data.properties["operating_state"] = "OFF" # OFF, FORWARD, ZENER
		component_data.terminals["A"] = component.terminal_anode
		component_data.terminals["K"] = component.terminal_kathode
		_log("Added ZenerDiode Vf={vf_str}, Vz={vz_str}, Terminals: A({anode_name}), K({kathode_name})".format({
			"vf_str": String.num(component.forward_voltage, 2), 
			"vz_str": String.num(component.zener_voltage, 2),
			"anode_name": component.terminal_anode.name, 
			"kathode_name": component.terminal_kathode.name
			}), LogLevel.LOW)
	elif component is Relay3D:
		component_data.type = "Relay"
		component_data.properties["coil_voltage_threshold"] = component.coil_voltage_threshold
		component_data.properties["coil_resistance"] = component.coil_resistance
		component_data.properties["is_energized"] = false # Initial state: de-energized
		component_data.terminals["CoilP"] = component.terminal_coil_p
		component_data.terminals["CoilN"] = component.terminal_coil_n
		component_data.terminals["COM"] = component.terminal_com
		component_data.terminals["NO"] = component.terminal_no
		component_data.terminals["NC"] = component.terminal_nc
		_log("Added Relay Threshold={thresh_s}V, CoilR={coilr_s}Ω. Terminals: CP({cp_n}), CN({cn_n}), COM({com_n}), NO({no_n}), NC({nc_n})".format({
			"thresh_s": String.num(component.coil_voltage_threshold,2), "coilr_s": String.num(component.coil_resistance,1),
			"cp_n": component.terminal_coil_p.name, "cn_n": component.terminal_coil_n.name,
			"com_n": component.terminal_com.name, "no_n": component.terminal_no.name, "nc_n": component.terminal_nc.name
			}), LogLevel.LOW)

	# If terminals already exist in the connection map (e.g., due to adding, removing, then re-adding without clearing),
	# ensure they are removed from their old nodes before being potentially reconnected.
	# This prevents stale connections if a component is deleted and a new one is added before wiring.
	for term_name in component_data.terminals:
		var terminal = component_data.terminals[term_name]
		var term_id = terminal.get_instance_id()
		if term_id in terminal_connections:
			var old_node_id = terminal_connections[term_id]
			if old_node_id in electrical_nodes:
				var term_list = electrical_nodes[old_node_id]["terminals"]
				var term_index = term_list.find(terminal)
				if term_index != -1:
					_log("Removing stale terminal {term_name} ({term_instance_id}) from old node {old_n_id}".format({"term_name": terminal.name, "term_instance_id": term_id, "old_n_id": old_node_id}), LogLevel.HIGH)
					term_list.remove_at(term_index)
					# Optional: Clean up node if it becomes empty? Maybe later.
			# Remove the stale entry from the connection map itself
			terminal_connections.erase(term_id)

	# Ensure all terminals of the component are associated with a node.
	# If a terminal is not yet in terminal_connections, create a new node for it.
	# This ensures that even unconnected terminals (like a potentiometer wiper) get a node_id
	# and are included in the MNA system if their component type requires it.
	for term_name_ensure_node in component_data.terminals:
		var terminal_ensure_node = component_data.terminals[term_name_ensure_node]
		
		if not is_instance_valid(terminal_ensure_node):
			_log("CircuitGraph.add_component: Terminal object for key '{term_key}' on component '{comp_name}' is invalid. Skipping node assignment for this terminal.".format({
				"term_key": term_name_ensure_node, "comp_name": component.name
			}), LogLevel.LOW, true)
			continue

		var term_id_ensure_node = terminal_ensure_node.get_instance_id()
		
		# Defensive check for term_id 0, which usually means a freed node or issue.
		if term_id_ensure_node == 0:
			_log("CircuitGraph.add_component: Terminal '{term_actual_name}' (key: '{term_key}') on component '{comp_name}' has instance ID 0. This might indicate an issue.".format({
				"term_actual_name": terminal_ensure_node.name, "term_key": term_name_ensure_node, "comp_name": component.name
			}), LogLevel.LOW, true)
			# Decide if to proceed or skip for ID 0. For now, let's allow it but with a warning.
			# If 0 is a problematic key, this could be a source of issues.

		if not term_id_ensure_node in terminal_connections: # If terminal is still not mapped to any node
			var new_node_id_for_floating_term = _get_new_node_id()
			electrical_nodes[new_node_id_for_floating_term] = { "terminals": [terminal_ensure_node], "voltage": NAN }
			terminal_connections[term_id_ensure_node] = new_node_id_for_floating_term
			_log("AddComp: Ensured floating terminal {t_name} (ID: {tid}) on component {comp_name} has new node {n_id}".format({
				"t_name": terminal_ensure_node.name, 
				"tid": term_id_ensure_node, 
				"comp_name": component.name, # 'component' is the function parameter
				"n_id": new_node_id_for_floating_term
			}), LogLevel.HIGH)
			
	components.push_back(component_data)

## Removes a component and its terminals from the graph.
## Also implicitly disconnects terminals from electrical nodes.
func remove_component(component_node: Node3D):
	_log("Removing component from graph: {0}".format([component_node.name]), LogLevel.LOW)
	_is_solved = false
	_needs_rebuild = true
	var component_index = -1
	for i in range(components.size()):
		if components[i].component_node == component_node:
			component_index = i
			break

	if component_index == -1:
		_log("Component {comp_name} not found in graph for removal.".format({"comp_name": component_node.name}), LogLevel.LOW, true)
		return

	var component_data = components[component_index]

	# Remove terminals from connection map and electrical nodes
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
					_log("Removed terminal {term_name} ({term_instance_id}) from node {n_id}".format({"term_name": terminal.name, "term_instance_id": term_id, "n_id": node_id}), LogLevel.HIGH)
					# Optional: Check if node needs cleanup (e.g., becomes empty or isolated)
			terminal_connections.erase(term_id) # Remove from connection map

	# Remove the component data itself
	components.remove_at(component_index)
	_log("Component {comp_name} removed from graph list.".format({"comp_name": component_node.name}), LogLevel.HIGH)

	# No specific logic needed here after component removal from 'components' list and terminal_connections.

## Connects two component terminals, updating the electrical node graph.
func connect_terminals(terminal_a: Area3D, terminal_b: Area3D):
	_is_solved = false # Changing connections invalidates the previous solution
	_needs_rebuild = true # Connections change the matrix structure
	if terminal_a == terminal_b:
		_log("Cannot connect a terminal to itself.", LogLevel.LOW, true)
		return

	var a_id = terminal_a.get_instance_id()
	var b_id = terminal_b.get_instance_id()

	var node_a: int = terminal_connections.get(a_id, -1)
	var node_b: int = terminal_connections.get(b_id, -1)

	_log("Connecting terminals: A={term_a_name} (Node {n_a}), B={term_b_name} (Node {n_b})".format({"term_a_name": terminal_a.name, "n_a": node_a, "term_b_name": terminal_b.name, "n_b": node_b}), LogLevel.LOW)

	if node_a == -1 and node_b == -1:
		var new_node_id = _get_new_node_id()
		electrical_nodes[new_node_id] = { "terminals": [terminal_a, terminal_b], "voltage": NAN }
		terminal_connections[a_id] = new_node_id
		terminal_connections[b_id] = new_node_id
		_log("Created new node {new_n_id} for terminals A and B".format({"new_n_id": new_node_id}), LogLevel.HIGH)
	elif node_a != -1 and node_b == -1:
		terminal_connections[b_id] = node_a
		electrical_nodes[node_a]["terminals"].push_back(terminal_b)
		_log("Connected terminal B to existing node {n_a}".format({"n_a": node_a}), LogLevel.HIGH)
	elif node_a == -1 and node_b != -1:
		terminal_connections[a_id] = node_b
		electrical_nodes[node_b]["terminals"].push_back(terminal_a)
		_log("Connected terminal A to existing node {n_b}".format({"n_b": node_b}), LogLevel.HIGH)
	elif node_a != -1 and node_b != -1:
		if node_a == node_b:
			_log("Terminals already connected to the same node {n_a}".format({"n_a": node_a}), LogLevel.HIGH)
			return
		else:
			_log("Merging node {n_b} into node {n_a}".format({"n_b": node_b, "n_a": node_a}), LogLevel.HIGH)
			var node_b_terminals = electrical_nodes[node_b]["terminals"].duplicate()
			for terminal in node_b_terminals:
				var term_id = terminal.get_instance_id()
				terminal_connections[term_id] = node_a
				electrical_nodes[node_a]["terminals"].push_back(terminal)
			electrical_nodes.erase(node_b)
			_log("Merge complete. Node {n_b} removed.".format({"n_b": node_b}), LogLevel.HIGH)

## Designates the electrical node connected to the given terminal as ground (0V).
func set_ground_node(terminal: Area3D):
	_is_solved = false # Changing ground invalidates the previous solution
	_needs_rebuild = true # Ground node affects matrix structure
	if not is_instance_valid(terminal):
		_log("Set ground node failed: Invalid terminal provided.", LogLevel.LOW, true)
		return

	var term_id = terminal.get_instance_id()
	var node_id = terminal_connections.get(term_id, -1)

	if node_id == -1:
		# Terminal is not connected to anything yet. Create a new node for it and set as ground.
		ground_node_id = _get_new_node_id()
		electrical_nodes[ground_node_id] = { "terminals": [terminal], "voltage": 0.0 } # Set voltage immediately
		terminal_connections[term_id] = ground_node_id
		_log("Set ground: Created new node {gnd_node_id} for unconnected terminal {term_name}.".format({"gnd_node_id": ground_node_id, "term_name": terminal.name}), LogLevel.LOW)
	else:
		ground_node_id = node_id
		electrical_nodes[ground_node_id].voltage = 0.0 # Set voltage immediately
		_log("Set ground: Node {gnd_node_id} (connected to terminal {term_name}) is now ground.".format({"gnd_node_id": ground_node_id, "term_name": terminal.name}), LogLevel.LOW)

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
		_log("Component {comp_name} not found in graph for config update.".format({"comp_name": component_node.name}), LogLevel.LOW, true)
		return

	_log("Updating graph config for component: {comp_name}".format({"comp_name": component_node.name}), LogLevel.LOW)
	var comp_type = found_component_data.type # Get type from existing graph data
	
	if comp_type == "Resistor" and component_node is Resistor3D:
		found_component_data.properties["resistance"] = component_node.resistance
	elif comp_type == "PowerSource" and component_node is PowerSource3D:
		found_component_data.properties["target_voltage"] = component_node.target_voltage
		var new_target_current = component_node.target_current
		if new_target_current < 0:
			_log("Warning: PowerSource {comp_name} target current limit is negative ({curr_target}A). Clamping to 0.0A.".format({"comp_name": component_node.name, "curr_target": new_target_current}), LogLevel.LOW)
			new_target_current = 0.0
			component_node.target_current = 0.0 # Also update the node's property
		found_component_data.properties["target_current"] = new_target_current
		found_component_data.properties["current_operating_mode"] = "CV" # Reset to CV on config change
		found_component_data.properties["cc_current_direction_sign"] = 1.0
		# found_component_data.properties["mode"] = component_node.current_mode # Mode removed
	elif comp_type == "Battery" and component_node is Battery3D:
		found_component_data.properties["target_voltage"] = component_node.target_voltage # Update from component
		found_component_data.properties["num_cells"] = component_node.num_cells
	elif comp_type == "LED" and component_node is LED3D:
		found_component_data.properties["forward_voltage"] = component_node.forward_voltage
		# Min/max current are usually fixed but could be updated if they become dynamic exports
		found_component_data.properties["min_current"] = component_node.min_current_to_light
		found_component_data.properties["max_current"] = component_node.max_current_before_burn
		found_component_data.is_burned = false # Reset burn state on config change (e.g. Vf change)
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
		# When config changes, reset the stored previous voltage and exploded state for stability/predictability
		found_component_data.properties["voltage_across_cap_prev_dt"] = 0.0
		found_component_data.is_exploded = false # Reset exploded state
	elif comp_type == "NonPolarizedCapacitor" and component_node is NonPolarizedCapacitor3D:
		found_component_data.properties["capacitance"] = component_node.capacitance
		found_component_data.properties["max_voltage"] = component_node.max_voltage
		found_component_data.properties["voltage_across_cap_prev_dt"] = 0.0
		# No is_exploded state
	elif comp_type == "Inductor" and component_node is Inductor3D:
		found_component_data.properties["inductance"] = component_node.inductance
		found_component_data.properties["current_through_L_prev_dt"] = 0.0 # Reset on config change
	elif comp_type == "NPNBJT" and component_node is NPNBJT3D:
		found_component_data.properties["beta_dc"] = component_node.beta_dc
		found_component_data.properties["vbe_on"] = component_node.vbe_on
		found_component_data.properties["vce_sat"] = component_node.vce_sat
		found_component_data.properties["operating_region"] = "OFF" # Reset region on config change
	elif comp_type == "PNPBJT" and component_node is PNPBJT3D:
		found_component_data.properties["beta_dc"] = component_node.beta_dc
		found_component_data.properties["veb_on"] = component_node.veb_on
		found_component_data.properties["vec_sat"] = component_node.vec_sat
		found_component_data.properties["operating_region"] = "OFF" # Reset region on config change
	elif comp_type == "ZenerDiode" and component_node is ZenerDiode3D:
		found_component_data.properties["forward_voltage"] = component_node.forward_voltage
		found_component_data.properties["zener_voltage"] = component_node.zener_voltage
		found_component_data.properties["operating_state"] = "OFF" # Reset state on config change
	elif comp_type == "Relay" and component_node is Relay3D:
		found_component_data.properties["coil_voltage_threshold"] = component_node.coil_voltage_threshold
		found_component_data.properties["coil_resistance"] = component_node.coil_resistance
		found_component_data.properties["is_energized"] = false # Reset state on config change
	else:
		_log("Cannot update config for component {comp_name}: Type mismatch or unknown type '{c_type}'.".format({"comp_name": component_node.name, "c_type": comp_type}), LogLevel.LOW, true)
		return
	_log("Graph config updated for {comp_name}. New props: {props}, State: {state_val}".format({"comp_name": component_node.name, "props": found_component_data.properties, "state_val": found_component_data.state if "state" in found_component_data else "N/A"}), LogLevel.HIGH)


## Resets calculated voltages (except ground) to NaN.
func _reset_voltages():
	component_results.clear() # Clear component-specific results too
	_is_solved = false


## Attempts to solve the circuit for a single time step using Modified Nodal Analysis (MNA).
## delta_time: The time step for this simulation increment (currently unused by DC components).
## Returns true if successful, false otherwise.
func solve_single_time_step(delta_time: float) -> bool:
	_log("\n--- Starting Transient Analysis Step (dt = {dt_str}s) ---".format({"dt_str": String.num(delta_time, 4)}), LogLevel.LOW)

	# Reset only voltages, keep component values/states (except ground)
	for node_id in electrical_nodes:
		if node_id != ground_node_id:
			electrical_nodes[node_id].voltage = NAN
		else:
			electrical_nodes[node_id].voltage = 0.0 # Ensure ground stays 0
	component_results.clear() # Clear previous results
	_is_solved = false # Mark as unsolved until success

	if ground_node_id == -1:
		_log("Circuit Error: No ground node defined. Cannot solve.", LogLevel.LOW, true)
		return false


	if electrical_nodes.is_empty():
		_log("Circuit Warning: No electrical nodes to solve.", LogLevel.LOW)
		return true # Technically solved (empty circuit)

	# --- Initialize conduction flags and BJT regions before iteration ---
	for comp_data_item in components: # Use a different variable name to avoid conflict
		if comp_data_item.type == "Diode" or comp_data_item.type == "LED":
			comp_data_item["conducting"] = false
		elif comp_data_item.type == "ZenerDiode":
			comp_data_item.properties["operating_state"] = "OFF" # Initial state
		elif comp_data_item.type == "Relay":
			comp_data_item.properties["is_energized"] = false # Initial assumption for iteration
		elif comp_data_item.type == "NPNBJT" or comp_data_item.type == "PNPBJT":
			# Keep current region or reset to OFF? For now, let's assume it might retain for stability,
			# or reset to "OFF" if we want a full re-evaluation.
			# For simplicity on first pass, let's try resetting to OFF. This might cause more iterations.
			comp_data_item.properties["operating_region"] = "OFF"

	var max_iter = 30 # Increased max iterations for BJT/MOSFET state changes
	var iterations_done = 0
	var x = []
	var converged = false # Renamed from changed_conduction_state for clarity
	var result_iter: Dictionary = {} # Declare result_iter outside the loop

	for i in range(max_iter):
		iterations_done = i + 1
		# --- Build MNA System for current iteration ---
		result_iter = _build_mna_system(delta_time) # Assign to the outer-scoped result_iter
		
		var A_iter = result_iter.A
		var b_iter = result_iter.b
		var node_map_iter = result_iter.node_map
		var active_vs_map_iter = result_iter.vs_map # Map for PS in CV mode and Batteries
		var inductor_map_iter = result_iter.inductor_map # Map for Inductors

		var N_iter = A_iter.size()

		if N_iter == 0 and node_map_iter.is_empty() and active_vs_map_iter.is_empty() and inductor_map_iter.is_empty():
			# System is truly empty (e.g. only ground, or just isolated open components not forming a system)
			_log("Circuit Warning: System is empty (N=0, no mapped nodes/sources/inductors) in iteration {iter_num}.".format({"iter_num": i+1}), LogLevel.LOW)
			_is_solved = true
			_calculate_passive_component_currents(delta_time)
			return true
		elif N_iter == 0 : # N=0 but there are mapped items, means _build_mna_system decided this is an open circuit
			_log("Circuit Warning: MNA system resulted in N=0 (likely open circuit) in iteration {iter_num}.".format({"iter_num": i+1}), LogLevel.LOW)
			# Voltages of non-ground nodes that are part of node_map_iter but not solved (e.g. isolated) will remain NaN.
			# If all non-ground nodes were isolated and not connected to sources, N could be 0.
			# This state might be considered 'solved' if all unmapped nodes are intended to be floating.
			_is_solved = true # Let's assume this is a "solved" open state.
			_calculate_passive_component_currents(delta_time) # currents will likely be 0 or NaN
			return true


		if A_iter.is_empty() or b_iter.is_empty() or b_iter.size() != N_iter:
			_log("Circuit Error: MNA system inconsistently built in iteration {iter_num}. N={n_val}, A size={a_sz}, b size={b_sz}".format({"iter_num":i+1, "n_val":N_iter, "a_sz":A_iter.size(), "b_sz":b_iter.size()}), LogLevel.LOW, true)
			# This case should ideally be caught by N_iter == 0 if the system is validly empty.
			# If N_iter > 0 but A/b are empty, it's a deeper issue in _build_mna_system.
			# For now, treat as solver failure for this iteration.
			x = [] # Ensure x is empty to signify failure
			pass # Let loop continue, hoping state change fixes it or post-loop handles empty x


		# --- Solve Ax = b for current iteration ---
		var current_iter_x = LinearSolver.solve(A_iter, b_iter)

		if current_iter_x.is_empty():
			x = [] # Ensure x is marked as empty for this iteration's result
			_log("Warning: Solver failed in iteration {iter_num} (matrix singular or near-singular).".format({"iter_num": i + 1}), LogLevel.LOW)
			_log("Component states for this failed solve attempt:", LogLevel.HIGH)
			for comp_data_diag in components:
				if comp_data_diag.type == "NPNBJT" or comp_data_diag.type == "PNPBJT":
					_log("    {name} ({type}): Region={reg}".format({
						"name": comp_data_diag.component_node.name,
						"type": comp_data_diag.type,
						"reg": comp_data_diag.properties["operating_region"]
					}), LogLevel.HIGH)
				elif comp_data_diag.type == "LED" or comp_data_diag.type == "Diode":
					_log("    {name} ({type}): Conducting={cond}, Burned={burn}".format({
						"name": comp_data_diag.component_node.name,
						"type": comp_data_diag.type,
						"cond": comp_data_diag.get("conducting", "N/A"),
						"burn": comp_data_diag.get("is_burned", "N/A") if comp_data_diag.type == "LED" else "N/A"
					}), LogLevel.HIGH)
				elif comp_data_diag.type == "ZenerDiode":
					_log("    {name} ({type}): State={state}".format({
						"name": comp_data_diag.component_node.name,
						"type": comp_data_diag.type,
						"state": comp_data_diag.properties.get("operating_state", "N/A")
					}), LogLevel.HIGH)
				elif comp_data_diag.type == "PowerSource":
					_log("    {name} ({type}): Mode={mode}".format({
						"name": comp_data_diag.component_node.name,
						"type": comp_data_diag.type,
						"mode": comp_data_diag.properties.get("current_operating_mode", "N/A")
					}), LogLevel.HIGH)
			# If states didn't change from the previous iteration and it still failed,
			# this implies the current MNA system for these states is persistently unsolvable.
			# The state_changed_this_iteration check later will handle breaking if stuck.
		else:
			x = current_iter_x # Store successful solve
			# Solution 'x' found for this iteration, update node voltages
			for node_id_key in node_map_iter:
				var matrix_index = node_map_iter[node_id_key]
				if electrical_nodes.has(node_id_key) and matrix_index < x.size():
					electrical_nodes[node_id_key].voltage = x[matrix_index]
				# else: printerr("Error mapping node for voltage update in iteration.") # Should not happen

		# --- Check and update states for Diodes, LEDs, and PowerSources ---
		var state_changed_this_iteration = false

		# Diodes/LEDs
		for comp_data_nl in components: # nl for non-linear
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
					# print_debug("  {type} {name} conduction changed to {cond}".format({"type": comp_data_nl.type, "name": comp_data_nl.component_node.name, "cond": should_conduct}))
		
		# NPN BJTs
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
				var new_region = previous_region # Default to no change

				if is_nan(Vb) or is_nan(Ve) or is_nan(Vc):
					new_region = "OFF" # If voltages are indeterminate, assume OFF
					print_debug("  NPNBJT {name} region check: Vb, Ve, or Vc is NaN. Setting to OFF.".format({ "name": comp_data_bjt.component_node.name }))
				else:
					var Vbe = Vb - Ve
					var Vce = Vc - Ve
					var vbe_tolerance = 1e-5 # Small tolerance for Vbe comparison, e.g. 0.01mV
					
					print_debug("  NPNBJT {name} ({prev_reg}) Check: Vb={vb_s}V, Ve={ve_s}V, Vc={vc_s}V => Vbe={vbe_s}V, Vce={vce_s}V. Thresholds: Vbe_on={vbe_on_s}V, Vce_sat={vce_sat_s}V".format({
						"name": comp_data_bjt.component_node.name, "prev_reg": previous_region,
						"vb_s": String.num(Vb,4), "ve_s": String.num(Ve,4), "vc_s": String.num(Vc,4),
						"vbe_s": String.num(Vbe,4), "vce_s": String.num(Vce,4),
						"vbe_on_s": String.num(vbe_on_bjt,4), "vce_sat_s": String.num(vce_sat_bjt,4)
					}))

					if Vbe < (vbe_on_bjt - vbe_tolerance): # If Vbe is clearly less than Vbe_on
						new_region = "OFF"
					else: # Vbe >= (vbe_on_bjt - vbe_tolerance) -> Consider it potentially ON
						# Now check for SATURATION vs ACTIVE based on Vce
						var vce_saturation_check_upper_bound = vce_sat_bjt + BJT_SATURATION_VOLTAGE_MARGIN
						if Vce <= vce_saturation_check_upper_bound: 
							new_region = "SATURATION"
						else: # Vce > vce_saturation_check_upper_bound
							new_region = "ACTIVE"
				
				if new_region != previous_region:
					comp_data_bjt.properties["operating_region"] = new_region
					state_changed_this_iteration = true
					# print_debug("  NPNBJT {name} region changed from {old_r} to {new_r} (Vbe={vbe_s}, Vce={vce_s})".format({
					#	 "name": comp_data_bjt.component_node.name, "old_r": previous_region, "new_r": new_region,
					#	 "vbe_s": String.num(Vbe,2) if not is_nan(Vb) else "N/A", # Vb, Ve, Vc, Vbe, Vce are from NPN scope
					#	 "vce_s": String.num(Vce,2) if not is_nan(Vc) else "N/A" 
					# }))

		# PowerSources
		for comp_data_ps in components:
			if comp_data_ps.type == "PowerSource":
				var ps_node = comp_data_ps.component_node
				var ps_id = ps_node.get_instance_id()
				var I_limit = comp_data_ps.properties.target_current # Assume non-negative
				var V_target_ps = comp_data_ps.properties.target_voltage
				var previous_op_mode = comp_data_ps.properties.current_operating_mode
				var current_mna_val_for_ps = NAN # Current from MNA system for this PS (if CV)

				if previous_op_mode == "CV":
					var vs_current_idx = active_vs_map_iter.get(ps_id, -1)
					if vs_current_idx != -1 and vs_current_idx < x.size():
						current_mna_val_for_ps = x[vs_current_idx] # MNA current for VSource (current INTO positive terminal)
						var current_supplied_by_ps = -current_mna_val_for_ps
						# Switch to CC if magnitude of supplied current exceeds I_limit
						# Use a small tolerance (e.g., 1nA) for comparison to I_limit.
						if abs(current_supplied_by_ps) > (I_limit + 1e-9):
							comp_data_ps.properties.current_operating_mode = "CC"
							comp_data_ps.properties.cc_current_direction_sign = sign(current_supplied_by_ps)
							# print_debug("PS {0} CV -> CC. I_supp={1}, I_lim={2}, Sign={3}".format([ps_node.name, current_supplied_by_ps, I_limit, comp_data_ps.properties.cc_current_direction_sign]))
					# else: Error, PS was CV but not in active_vs_map or x out of bounds - should not happen
				
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
						# Switch back to CV if the voltage across the CC source is "less constrained" than V_target.
						# i.e. if abs(V_across_cc) < abs(V_target_ps) (considering signs appropriately)
						# Simplified: If (signed) V_across_cc is closer to zero than (signed) V_target_ps,
						# when operating in the direction of cc_current_direction_sign.
						# If V_target_ps > 0 and cc_current_direction_sign > 0 (supplying positive current):
						# If V_across_cc < V_target_ps, it means the limit is no longer needed to achieve V_target_ps.
						# Use a small tolerance for voltage comparison.
						# If in CC mode, and the voltage required to drive I_limit would EXCEED V_target,
						# then the PS must switch to CV mode (voltage clamp).
						if comp_data_ps.properties.cc_current_direction_sign * V_across_cc > comp_data_ps.properties.cc_current_direction_sign * V_target_ps + 1e-6 :
							comp_data_ps.properties.current_operating_mode = "CV"
							# print_debug("PS {0} CC -> CV (Voltage Clamp: V_across_cc={1} > V_target={2})".format([ps_node.name, V_across_cc, V_target_ps]))
						# Original condition for switching if load lightens (V_across_cc < V_target_ps) might cause oscillations
						# and is typically handled by the fact that if it *can* be CV (i.e. current would be < I_limit),
						# it would have been set to CV in a prior CV->CC check if current was too low.
						# For now, the primary concern is preventing V_across_cc from exceeding V_target_ps.
					# else: Voltages not solved, retain CC mode.
				
				if comp_data_ps.properties.current_operating_mode != previous_op_mode:
					state_changed_this_iteration = true

		# PNP BJTs (similar to NPN, but Veb, Vec)
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
					var Veb_pnp = Ve_pnp - Vb_pnp # Emitter - Base
					var Vec_pnp = Ve_pnp - Vc_pnp # Emitter - Collector
					var veb_tolerance_pnp = 1e-5

					# print_debug("  PNPBJT {name} ({prev_reg}) Check: Ve={ve_s}V, Vb={vb_s}V, Vc={vc_s}V => Veb={veb_s}V, Vec={vec_s}V. Thresholds: Veb_on={veb_on_s}V, Vec_sat={vec_sat_s}V".format({
					#	"name": comp_data_pnp_bjt.component_node.name, "prev_reg": previous_region_pnp,
					#	"ve_s": String.num(Ve_pnp,4), "vb_s": String.num(Vb_pnp,4), "vc_s": String.num(Vc_pnp,4),
					#	"veb_s": String.num(Veb_pnp,4), "vec_s": String.num(Vec_pnp,4),
					#	"veb_on_s": String.num(veb_on_pnp_model,4), "vec_sat_s": String.num(vec_sat_pnp_model,4)
					# }))
					
					if Veb_pnp < (veb_on_pnp_model - veb_tolerance_pnp): # If Veb is clearly less than Veb_on (Base not sufficiently lower than Emitter)
						new_region_pnp = "OFF"
					else: # Veb_pnp >= (veb_on_pnp_model - veb_tolerance_pnp) -> Potentially ON
						var vec_saturation_check_upper_bound_pnp = vec_sat_pnp_model + BJT_SATURATION_VOLTAGE_MARGIN
						if Vec_pnp <= vec_saturation_check_upper_bound_pnp: # If Emitter is not sufficiently higher than Collector
							new_region_pnp = "SATURATION"
						else: # Vec_pnp > vec_saturation_check_upper_bound_pnp
							new_region_pnp = "ACTIVE"
				
				if new_region_pnp != previous_region_pnp:
					comp_data_pnp_bjt.properties["operating_region"] = new_region_pnp
					state_changed_this_iteration = true
					# print_debug("  PNPBJT {name} region changed from {old_r} to {new_r}".format({
					#	"name": comp_data_pnp_bjt.component_node.name, "old_r": previous_region_pnp, "new_r": new_region_pnp
					# }))

		# Zener Diodes
		for comp_data_zener in components:
			if comp_data_zener.type == "ZenerDiode":
				var term_a_z = comp_data_zener.terminals["A"]
				var term_k_z = comp_data_zener.terminals["K"]
				var node_a_id_z = terminal_connections.get(term_a_z.get_instance_id(), -1)
				var node_k_id_z = terminal_connections.get(term_k_z.get_instance_id(), -1)
				
				var Va_z = electrical_nodes.get(node_a_id_z, {}).get("voltage", NAN)
				var Vk_z = electrical_nodes.get(node_k_id_z, {}).get("voltage", NAN)
				
				var Vf_z_model = comp_data_zener.properties["forward_voltage"]
				var Vz_model = comp_data_zener.properties["zener_voltage"] # This is positive Vz value
				var previous_state_z = comp_data_zener.properties["operating_state"]
				var new_state_z = previous_state_z

				if is_nan(Va_z) or is_nan(Vk_z):
					new_state_z = "OFF" # Cannot determine state if voltages are unknown
				else:
					var Vak_z = Va_z - Vk_z # Voltage Anode - Kathode
					var zener_voltage_threshold = -Vz_model # Zener breakdown occurs when Vak is more negative than -Vz
					var zener_on_margin = 1e-5 # Small margin for Zener breakdown voltage

					if Vak_z >= (Vf_z_model - 1e-5): # Forward biased or slightly below Vf
						new_state_z = "FORWARD"
					elif Vak_z <= (zener_voltage_threshold + zener_on_margin): # Reverse biased AND at or beyond Zener voltage
						new_state_z = "ZENER"
					else: # Reverse biased but not in Zener breakdown, or slightly forward but below Vf
						new_state_z = "OFF"
				
				if new_state_z != previous_state_z:
					comp_data_zener.properties["operating_state"] = new_state_z
					state_changed_this_iteration = true
					# print_debug("  ZenerDiode {name} state changed from {old_s} to {new_s} (Vak={vak_s})".format({
					# "name": comp_data_zener.component_node.name, "old_s": previous_state_z, "new_s": new_state_z,
					# "vak_s": String.num(Vak_z, 4) if not is_nan(Va_z) else "N/A"
					# }))

		# Relays
		for comp_data_relay in components:
			if comp_data_relay.type == "Relay":
				var term_coil_p_relay = comp_data_relay.terminals["CoilP"]
				var term_coil_n_relay = comp_data_relay.terminals["CoilN"]
				var node_coil_p_id = terminal_connections.get(term_coil_p_relay.get_instance_id(), -1)
				var node_coil_n_id = terminal_connections.get(term_coil_n_relay.get_instance_id(), -1)

				var V_coil_p = electrical_nodes.get(node_coil_p_id, {}).get("voltage", NAN)
				var V_coil_n = electrical_nodes.get(node_coil_n_id, {}).get("voltage", NAN)
				
				var threshold_relay = comp_data_relay.properties["coil_voltage_threshold"]
				var previous_energized_state = comp_data_relay.properties["is_energized"]
				var new_energized_state = previous_energized_state

				if is_nan(V_coil_p) or is_nan(V_coil_n):
					new_energized_state = false # Cannot determine, assume de-energized
				else:
					var actual_coil_voltage = V_coil_p - V_coil_n
					# Use a small tolerance for threshold comparison
					if actual_coil_voltage >= (threshold_relay - 1e-5):
						new_energized_state = true
					else:
						new_energized_state = false
				
				if new_energized_state != previous_energized_state:
					comp_data_relay.properties["is_energized"] = new_energized_state
					state_changed_this_iteration = true
					# print_debug("  Relay {name} energized state changed to {new_e_state} (Vcoil={v_coil_s})".format({
					# "name": comp_data_relay.component_node.name, "new_e_state": new_energized_state,
					# "v_coil_s": String.num(actual_coil_voltage, 2) if not is_nan(V_coil_p) else "N/A"
					# }))
					
		if not state_changed_this_iteration and not x.is_empty():
			converged = true
			_log("Converged in {iter_num} iterations.".format({"iter_num": i + 1}), LogLevel.HIGH)
			break # Exit loop

	_log("--- Iterative Solver (Diode/LED/PS) Finished after {iters_done} iterations. Converged: {conv_flag} ---".format({"iters_done": iterations_done, "conv_flag": converged}), LogLevel.LOW)

	# --- Post-Iteration: Final processing ---
	if not converged and iterations_done >= max_iter:
		_log("Warning: Max iterations reached ({iters_done}). Performing one final consistency solve.".format({"iters_done": iterations_done}), LogLevel.LOW)
		# The 'operating_region' properties are set based on voltages from the last iteration.
		# Re-build and re-solve MNA with these latest determined states.
		var result_final_consistency_solve = _build_mna_system(delta_time) # Build with final states
		var A_final_consistency = result_final_consistency_solve.A
		var b_final_consistency = result_final_consistency_solve.b
		var node_map_final_consistency = result_final_consistency_solve.node_map
		# vs_map and inductor_map from result_final_consistency_solve will be used later if solve is successful
		
		if A_final_consistency.is_empty() or A_final_consistency.size() == 0 : # Check if system is empty
			_log("Final consistency MNA system is empty. Using previous solution vector x (if any).", LogLevel.HIGH)
			# 'x' still holds the solution from the last iteration of the main loop.
			# No change to 'x' or electrical_nodes needed here if system is empty.
		else:
			var x_consistency_solve = LinearSolver.solve(A_final_consistency, b_final_consistency)
			
			if not x_consistency_solve.is_empty():
				x = x_consistency_solve # IMPORTANT: Update the main solution vector 'x'
				result_iter = result_final_consistency_solve # IMPORTANT: Update result_iter for maps
				# Update electrical_nodes with this final consistent solution
				for node_id_key in node_map_final_consistency:
					var matrix_index = node_map_final_consistency[node_id_key]
					if electrical_nodes.has(node_id_key) and matrix_index < x.size():
						electrical_nodes[node_id_key].voltage = x[matrix_index]
				_log("Final consistency solve successful. Voltages updated.", LogLevel.HIGH)
			else:
				# Consistency solve failed. 'x' from the main loop's last iteration might be kept,
				# or we can mark it as entirely failed. For now, set x to empty.
				_log("Final consistency MNA solve FAILED. Marking solution as unreliable.", LogLevel.LOW, true)
				x = [] # Mark main solution 'x' as empty (failed)
	
	# _is_solved is true if and only if the final solution vector 'x' (possibly from consistency solve) is not empty.
	if not x.is_empty():
		_is_solved = true
		# If 'converged' was true from the main loop, this message is skipped.
		# If 'converged' was false (max_iter) but consistency solve provided a solution, this is fine.
		if not converged: # This 'converged' is from the main loop.
			_log("Note: Main iteration loop reached max_iter. Final solution obtained (possibly via consistency solve).", LogLevel.HIGH)
		
		# Voltages are already updated from the last successful x in the loop.
		# Print final node voltages:
		var final_node_map_print = result_iter.get("node_map", {}) # Use node_map from the last build
		_log("Final Node Voltages from solution:", LogLevel.HIGH)
		if final_node_map_print: 
			for node_id_key_print in final_node_map_print:
				# matrix_index_print is not needed here as voltages are already in electrical_nodes
				if electrical_nodes.has(node_id_key_print): # and matrix_index_print < x.size() no longer needed
					_log("  Node {nkp} Voltage = {volt_str} V".format({"nkp": node_id_key_print, "volt_str": String.num(electrical_nodes[node_id_key_print].voltage, 4)}), LogLevel.HIGH)

		# Update/Store currents and voltages for PowerSources (CV mode), Batteries, and Inductors
		var final_active_vs_map = result_iter.get("vs_map", {}) 
		var final_inductor_map = result_iter.get("inductor_map", {})

		for comp_data_final_res in components: # Iterate all components for results
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
						_log("{lt} {ln} (CV Mode): Solved Supplied I={lcurr} A, Actual V_across={lva} V (Target V={lvt}{lilim})".format({
							"lt": log_type, "ln": log_name, "lcurr": log_curr, "lva": log_volt_across, "lvt":log_vtarget, "lilim":log_ilim}), LogLevel.HIGH)
			
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
				_log("PowerSource {psn} (CC Mode): Set Current={pscc} A, Actual V_across={psva} V (Target I={psti}A)".format({
					"psn":comp_node_final.name, "pscc":String.num(cc_current_val,4), "psva":String.num(actual_V_across_cc,2),
					"psti":String.num(comp_data_final_res.properties.target_current,2)}), LogLevel.HIGH)

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
						
						_log("Inductor {ind_name}: Solved I_L={l_curr} A, Actual V_across={l_va} V".format({
							"ind_name": comp_node_final.name, "l_curr": String.num(solved_current_L, 4), "l_va": String.num(actual_V_across_L, 2)
						}), LogLevel.HIGH)
	else: # x is empty, meaning the loop finished with a failed solve.
		_is_solved = false
		_log("Error: Solver loop concluded with a failed matrix solution. Circuit state is unreliable.", LogLevel.LOW, true)
		# Voltages will retain their last known values from a previous successful iteration, or be NAN.
		# No fallback to 0V here, as _is_solved = false should prevent display of these unreliable values.

	# --- Calculate currents for other components & update capacitor Vc(t-dt) ---
	# This will use the voltages from the final state of 'x' (if solved) or previous state (if last 'x' was empty)
	_calculate_passive_component_currents(delta_time)

	_log("--- Transient Analysis Step Concluded (Converged: {conv_f}, Solved: {is_solv_f}, dt={dt_s}s) ---".format({"conv_f":converged, "is_solv_f": _is_solved, "dt_s": String.num(delta_time, 4)}), LogLevel.LOW)
	return _is_solved


## Constructs the MNA matrices A and b for the current time step.
## delta_time: The simulation time step, crucial for capacitor model.
## Returns a dictionary: { A: Array[Array], b: Array, node_map: Dict, vs_map: Dict } or empty dict on error.
func _build_mna_system(delta_time: float) -> Dictionary:
	var non_ground_nodes: Array[int] = []
	for node_id in electrical_nodes:
		if node_id != ground_node_id:
			non_ground_nodes.push_back(node_id)

	# Count active voltage sources (Batteries + PowerSources in CV mode)
	var active_voltage_sources: Array[Dictionary] = []
	for comp_data_item_vs in components: # Renamed loop var
		if comp_data_item_vs.type == "Battery":
			active_voltage_sources.push_back(comp_data_item_vs)
		elif comp_data_item_vs.type == "PowerSource" and comp_data_item_vs.properties.get("current_operating_mode") == "CV":
			active_voltage_sources.push_back(comp_data_item_vs)

	# Count active inductors
	var active_inductors: Array[Dictionary] = []
	for comp_data_item_L in components: # Renamed loop var
		if comp_data_item_L.type == "Inductor":
			active_inductors.push_back(comp_data_item_L)


	var num_nodes = non_ground_nodes.size()
	var num_active_vs = active_voltage_sources.size()
	var num_inductors = active_inductors.size()
	var N = num_nodes + num_active_vs + num_inductors # Total size of the MNA system

	# Create mappings from node_id / active_vs_id / inductor_id to matrix index
	var node_id_to_matrix_index: Dictionary = {}
	for i in range(num_nodes):
		node_id_to_matrix_index[non_ground_nodes[i]] = i

	var active_vs_id_to_matrix_index: Dictionary = {} # Only for Batteries and PS in CV mode
	for i in range(num_active_vs):
		var vs_comp_data = active_voltage_sources[i]
		var vs_id = vs_comp_data.component_node.get_instance_id()
		active_vs_id_to_matrix_index[vs_id] = num_nodes + i # Index after node voltages

	var inductor_id_to_matrix_index: Dictionary = {}
	for i in range(num_inductors):
		var ind_comp_data = active_inductors[i]
		var ind_id = ind_comp_data.component_node.get_instance_id()
		inductor_id_to_matrix_index[ind_id] = num_nodes + num_active_vs + i # Index after VS currents
		
	if N == 0:
		# Return structure expected by caller even if system is empty
		return {"A": [], "b": [], "node_map": node_id_to_matrix_index, "vs_map": active_vs_id_to_matrix_index, "inductor_map": inductor_id_to_matrix_index}

	# Initialize matrices A (NxN) and b (Nx1) with zeros
	var A: Array = []
	A.resize(N)
	for i in range(N):
		A[i] = []
		A[i].resize(N)
		A[i].fill(0.0)
	var b: Array = []
	b.resize(N)
	b.fill(0.0)

	# --- Stamp components into A and b ---

	# Stamp components into A and b
	for comp_data in components:
		if comp_data.type == "Resistor":
			var R = comp_data.properties["resistance"]
			if R == 0.0: R = 1e-9 # Avoid division by zero, treat as near short
			var g = 1.0 / R
			var term1 = comp_data.terminals["T1"]
			var term2 = comp_data.terminals["T2"]
			var node1_id = terminal_connections.get(term1.get_instance_id() if is_instance_valid(term1) else -1, -1)
			var node2_id = terminal_connections.get(term2.get_instance_id() if is_instance_valid(term2) else -1, -1)

			var idx1 = node_id_to_matrix_index.get(node1_id, -1)
			var idx2 = node_id_to_matrix_index.get(node2_id, -1)

			if idx1 != -1: A[idx1][idx1] += g
			if idx2 != -1: A[idx2][idx2] += g
			if idx1 != -1 and idx2 != -1:
				A[idx1][idx2] -= g
				A[idx2][idx1] -= g
		
		elif comp_data.type == "LED":
			var is_logically_burned = comp_data.get("is_burned", false)
			# 'conducting' flag is set based on voltage threshold in solve_dc loop.
			# If burned, it overrides the conducting flag for MNA stamping.
			var stamp_as_conducting = comp_data.get("conducting", false) and not is_logically_burned

			var term_a = comp_data.terminals["A"]
			var term_k = comp_data.terminals["K"]
			var node_a_id = terminal_connections.get(term_a.get_instance_id() if is_instance_valid(term_a) else -1, -1)
			var node_k_id = terminal_connections.get(term_k.get_instance_id() if is_instance_valid(term_k) else -1, -1)
			var idx_a = node_id_to_matrix_index.get(node_a_id, -1)
			var idx_k = node_id_to_matrix_index.get(node_k_id, -1)

			var g_stamp_led: float
			var R_led_on_model = 0.1 # Ohms - LED dynamic resistance when forward biased
			if R_led_on_model < 1e-9: R_led_on_model = 1e-9 
			var R_led_off_model = 1.0e9 # Very high resistance for "off" state or burned (1 GigaOhm)


			if stamp_as_conducting: # Not burned AND voltage indicates it should conduct
				g_stamp_led = 1.0 / R_led_on_model
				var Vf_led = comp_data.properties["forward_voltage"]
				var current_offset = Vf_led / R_led_on_model
				# This offset represents an equivalent current source due to Vf for the linear model
				# Positive current into Anode, Negative current into Kathode (from the perspective of the source)
				# So for KCL at node A: +current_offset, at node K: -current_offset
				# If Vf_led / R_led_on_model is I_eq.
				# Node A equation: ... G_led * Va - G_led * Vk = I_eq  => b[idx_a] += I_eq
				# Node K equation: ... -G_led * Va + G_led * Vk = -I_eq => b[idx_k] -= I_eq
				if idx_a != -1: b[idx_a] += current_offset
				if idx_k != -1: b[idx_k] -= current_offset
			else: # Burned OR (Not burned AND voltage indicates not conducting)
				g_stamp_led = 1.0 / R_led_off_model
			
			# Stamp conductance
			if idx_a != -1: A[idx_a][idx_a] += g_stamp_led
			if idx_k != -1: A[idx_k][idx_k] += g_stamp_led
			if idx_a != -1 and idx_k != -1:
				A[idx_a][idx_k] -= g_stamp_led
				A[idx_k][idx_a] -= g_stamp_led
		
		elif comp_data.type == "Diode":
			var term_a_diode = comp_data.terminals["A"]
			var term_k_diode = comp_data.terminals["K"]
			var node_a_id_diode = terminal_connections.get(term_a_diode.get_instance_id() if is_instance_valid(term_a_diode) else -1, -1)
			var node_k_id_diode = terminal_connections.get(term_k_diode.get_instance_id() if is_instance_valid(term_k_diode) else -1, -1)
			var idx_a_diode = node_id_to_matrix_index.get(node_a_id_diode, -1)
			var idx_k_diode = node_id_to_matrix_index.get(node_k_id_diode, -1)

			var g_stamp_diode: float
			var R_diode_on_model = 0.1 # Ohms - Diode dynamic resistance when forward biased
			if R_diode_on_model < 1e-9: R_diode_on_model = 1e-9

			if comp_data.get("conducting", false):
				g_stamp_diode = 1.0 / R_diode_on_model
				var Vf_diode = comp_data.properties["forward_voltage"]
				var current_offset_diode = Vf_diode / R_diode_on_model
				# Similar to LED:
				if idx_a_diode != -1: b[idx_a_diode] += current_offset_diode
				if idx_k_diode != -1: b[idx_k_diode] -= current_offset_diode
			else:
				var R_diode_off_model = 1.0e9 # Very high resistance for "off" state (1 GigaOhm)
				g_stamp_diode = 1.0 / R_diode_off_model

			# Stamp conductance for Rd_on or Rd_off
			if idx_a_diode != -1: A[idx_a_diode][idx_a_diode] += g_stamp_diode
			if idx_k_diode != -1: A[idx_k_diode][idx_k_diode] += g_stamp_diode
			if idx_a_diode != -1 and idx_k_diode != -1:
				A[idx_a_diode][idx_k_diode] -= g_stamp_diode
				A[idx_k_diode][idx_a_diode] -= g_stamp_diode
		
		elif comp_data.type == "Switch":
			var state: Switch3D.State = comp_data.state
			var R_closed = 1e-6 
			if R_closed <= 1e-9: R_closed = 1e-9 # Ensure positive non-zero
			var g_closed = 1.0 / R_closed
			
			var R_open = 1.0e12 # Large resistance for open contacts (1 TeraOhm)
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
				_stamp_conductance(A, g_closed, idx_com, idx_nc) # COM-NC is closed
				_stamp_conductance(A, g_open, idx_com, idx_no)   # COM-NO is open (tiny conductance)
			elif state == Switch3D.State.CONNECTED_NO:
				_stamp_conductance(A, g_open, idx_com, idx_nc)   # COM-NC is open (tiny conductance)
				_stamp_conductance(A, g_closed, idx_com, idx_no) # COM-NO is closed
		
		elif comp_data.type == "Potentiometer":
			var total_R = comp_data.properties["total_resistance"] # Use properties
			var wiper_pos = comp_data.properties["wiper_position"] # Use properties
			
			var R1 = total_R * wiper_pos
			if R1 < 1e-9: R1 = 1e-9 # Avoid division by zero, treat as near short
			var g1 = 1.0 / R1

			var R2 = total_R * (1.0 - wiper_pos)
			if R2 < 1e-9: R2 = 1e-9 # Avoid division by zero
			var g2 = 1.0 / R2
			
			var term1 = comp_data.terminals["T1"]
			var term2 = comp_data.terminals["T2"]
			var termW = comp_data.terminals["W"] # Wiper terminal
			
			var node1_id = terminal_connections.get(term1.get_instance_id() if is_instance_valid(term1) else -1, -1)
			var node2_id = terminal_connections.get(term2.get_instance_id() if is_instance_valid(term2) else -1, -1)
			var nodeW_id = terminal_connections.get(termW.get_instance_id() if is_instance_valid(termW) else -1, -1)
			
			var idx1 = node_id_to_matrix_index.get(node1_id, -1)
			var idx2 = node_id_to_matrix_index.get(node2_id, -1)
			var idxW = node_id_to_matrix_index.get(nodeW_id, -1)
			
			# Stamp R1 (between Terminal1 and Wiper)
			if idx1 != -1: A[idx1][idx1] += g1
			if idxW != -1: A[idxW][idxW] += g1
			if idx1 != -1 and idxW != -1:
				A[idx1][idxW] -= g1
				A[idxW][idx1] -= g1
				
			# Stamp R2 (between Wiper and Terminal2)
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
				# Current 'actual_current_stamp_cc' is defined as flowing OUT of POS terminal (supplying).
				# KCL at POS: ... + (-actual_current_stamp_cc) = 0 => b[pos_idx_ps] += actual_current_stamp_cc (RHS convention: current INTO node)
				# KCL at NEG: ... + (actual_current_stamp_cc) = 0  => b[neg_idx_ps] -= actual_current_stamp_cc
				if pos_idx_ps != -1:
					b[pos_idx_ps] += actual_current_stamp_cc 
				if neg_idx_ps != -1:
					b[neg_idx_ps] -= actual_current_stamp_cc
					
		elif comp_data.type == "Battery": # Batteries are always ideal voltage sources
			var pos_term_bat = comp_data.terminals["POS"]
			var neg_term_bat = comp_data.terminals["NEG"]
			var pos_node_id_bat = terminal_connections.get(pos_term_bat.get_instance_id() if is_instance_valid(pos_term_bat) else -1, -1)
			var neg_node_id_bat = terminal_connections.get(neg_term_bat.get_instance_id() if is_instance_valid(neg_term_bat) else -1, -1)
			var pos_idx_bat = node_id_to_matrix_index.get(pos_node_id_bat, -1)
			var neg_idx_bat = node_id_to_matrix_index.get(neg_node_id_bat, -1)

			var bat_id = comp_data.component_node.get_instance_id()
			if not active_vs_id_to_matrix_index.has(bat_id): # Should always be in active_vs map
				printerr("Critical Error: Battery {batid} not found in active_vs_id_to_matrix_index.".format({"batid": bat_id}))
				continue
			
			var bat_current_idx = active_vs_id_to_matrix_index[bat_id]
			var V_target_bat = comp_data.properties["target_voltage"]
			
			# Equation: V_pos - V_neg = V_target_bat
			b[bat_current_idx] = V_target_bat
			if pos_idx_bat != -1:
				A[bat_current_idx][pos_idx_bat] = 1.0
				A[pos_idx_bat][bat_current_idx] = 1.0 
			if neg_idx_bat != -1:
				A[bat_current_idx][neg_idx_bat] = -1.0
				A[neg_idx_bat][bat_current_idx] = -1.0
		
		elif comp_data.type == "PolarizedCapacitor":
			var G_eq: float
			var I_eq_source: float = 0.0 # Default to no current source part

			if comp_data.get("is_exploded", false):
				# If exploded, model as a very high resistance (low conductance)
				G_eq = 1e-9 # Effectively an open circuit
				# I_eq_source remains 0.0
			else:
				var C = comp_data.properties["capacitance"]
				if C <= 1e-12: C = 1e-12 # Avoid issues with zero or too small capacitance
				var Vc_prev_dt = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)
				
				G_eq = C / delta_time
				I_eq_source = G_eq * Vc_prev_dt

			var term1_cap = comp_data.terminals["T1"] # Positive terminal
			var term2_cap = comp_data.terminals["T2"] # Negative terminal
			var node1_id_cap = terminal_connections.get(term1_cap.get_instance_id() if is_instance_valid(term1_cap) else -1, -1)
			var node2_id_cap = terminal_connections.get(term2_cap.get_instance_id() if is_instance_valid(term2_cap) else -1, -1)
			
			var idx1_cap = node_id_to_matrix_index.get(node1_id_cap, -1)
			var idx2_cap = node_id_to_matrix_index.get(node2_id_cap, -1)

			# Stamp G_eq
			if idx1_cap != -1: A[idx1_cap][idx1_cap] += G_eq
			if idx2_cap != -1: A[idx2_cap][idx2_cap] += G_eq
			if idx1_cap != -1 and idx2_cap != -1:
				A[idx1_cap][idx2_cap] -= G_eq
				A[idx2_cap][idx1_cap] -= G_eq
			
			# Stamp I_eq_source contribution to RHS (b vector)
			# Current I_eq_source flows effectively from node1 to node2 due to Vc_prev_dt
			# KCL at node1: ... = I_eq_source
			# KCL at node2: ... = -I_eq_source
			if idx1_cap != -1: b[idx1_cap] += I_eq_source
			if idx2_cap != -1: b[idx2_cap] -= I_eq_source
		
		elif comp_data.type == "NonPolarizedCapacitor":
			# Logic is identical to PolarizedCapacitor for MNA stamping, but without explosion check
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
			if L_val <= 1e-12: L_val = 1e-12 # Min inductance
			var I_L_prev_dt_val = comp_data.properties.get("current_through_L_prev_dt", 0.0)

			var term1_L = comp_data.terminals["T1"]
			var term2_L = comp_data.terminals["T2"]
			var node1_id_L = terminal_connections.get(term1_L.get_instance_id() if is_instance_valid(term1_L) else -1, -1)
			var node2_id_L = terminal_connections.get(term2_L.get_instance_id() if is_instance_valid(term2_L) else -1, -1)

			var idx1_L = node_id_to_matrix_index.get(node1_id_L, -1) # Matrix index for V_node1
			var idx2_L = node_id_to_matrix_index.get(node2_id_L, -1) # Matrix index for V_node2
			
			var inductor_id = comp_data.component_node.get_instance_id()
			if not inductor_id_to_matrix_index.has(inductor_id):
				printerr("Critical Error: Inductor {ind_id_str} not found in inductor_id_to_matrix_index.".format({"ind_id_str": inductor_id}))
				continue
			var idx_I_L = inductor_id_to_matrix_index[inductor_id] # Matrix index for I_L variable

			# Branch equation: V1 - V2 - (L/dt) * I_L(t) = -(L/dt) * I_L(t-dt)
			# Row for I_L variable (index idx_I_L):
			if idx1_L != -1: A[idx_I_L][idx1_L] = 1.0 # V1 contribution
			if idx2_L != -1: A[idx_I_L][idx2_L] = -1.0 # V2 contribution
			A[idx_I_L][idx_I_L] = -L_val / delta_time  # I_L(t) contribution
			b[idx_I_L] = -(L_val / delta_time) * I_L_prev_dt_val # RHS
			
			# KCL contributions:
			# Current I_L flows from T1 to T2.
			# At node1 (T1): current I_L leaves (defined from T1 to T2), so A[idx1_L][idx_I_L] = 1.0
			# At node2 (T2): current I_L enters, so A[idx2_L][idx_I_L] = -1.0
			if idx1_L != -1: A[idx1_L][idx_I_L] = 1.0 # Current I_L leaving node1
			if idx2_L != -1: A[idx2_L][idx_I_L] = -1.0 # Current I_L entering node2

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
			
			# Model parameters (could be made configurable later if needed)
			var R_be_active_model = 50.0  # Effective B-E resistance when ON (Ohms)
			var R_ce_sat_model = 5.0    # Effective C-E resistance in saturation (Ohms)
			var R_bjt_off_model = 1.0e9 # Resistance for OFF state (Ohms)

			if region == "OFF":
				var g_off = 1.0 / R_bjt_off_model
				# Model B-E junction as off
				_stamp_conductance(A, g_off, idx_b, idx_e)
				# Model C-E path as off
				_stamp_conductance(A, g_off, idx_c, idx_e)
				# Model C-B junction as off (reverse biased)
				_stamp_conductance(A, g_off, idx_c, idx_b)
			
			elif region == "ACTIVE":
				# 1. Base-Emitter Diode Model (Norton Equivalent)
				# Vb - Ve = Vbe_on + Ib * R_be_active_model  => Ib = (Vb - Ve - Vbe_on) / R_be_active_model
				# This is a voltage source Vbe_on in series with R_be_active_model.
				var G_be_active = 1.0 / R_be_active_model
				var Is_be_active = vbe_on_model / R_be_active_model # Current source part of Norton equiv.

				if idx_b != -1: A[idx_b][idx_b] += G_be_active; b[idx_b] += Is_be_active
				if idx_e != -1: A[idx_e][idx_e] += G_be_active; b[idx_e] -= Is_be_active
				if idx_b != -1 and idx_e != -1:
					A[idx_b][idx_e] -= G_be_active; A[idx_e][idx_b] -= G_be_active
				
				# 2. Collector Current Source: Ic = beta * Ib
				# Ic = beta * (Vb - Ve - Vbe_on) / R_be_active_model
				# Ic = (beta / R_be_active_model) * (Vb - Ve) - (beta * Vbe_on / R_be_active_model)
				# Let Gm_bjt = beta / R_be_active_model
				# Let Ic_offset_bjt = beta * Vbe_on / R_be_active_model
				# So, Ic = Gm_bjt * (Vb - Ve) - Ic_offset_bjt. This current flows from C to E.
				
				var Gm_bjt = beta / R_be_active_model
				var Ic_offset_bjt = beta * vbe_on_model / R_be_active_model

				# KCL at Collector (node C): current Ic is leaving C.
				if idx_c != -1:
					if idx_b != -1: A[idx_c][idx_b] += Gm_bjt   # d(Ic)/d(Vb)
					if idx_e != -1: A[idx_c][idx_e] -= Gm_bjt   # d(Ic)/d(Ve)
					b[idx_c] += Ic_offset_bjt             # -(-Ic_offset_bjt) for RHS
				
				# KCL at Emitter (node E): current Ic is entering E. (Part of Ie = Ib+Ic, Ic flows C -> E)
				# The VCCS for Ic = Gm_bjt * (Vb - Ve) - Ic_offset_bjt (flowing C to E) means:
				# A[idx_e][idx_b] -= Gm_bjt
				# A[idx_e][idx_e] += Gm_bjt
				# b[idx_e] -= Ic_offset_bjt  (current source component -Ic_offset_bjt is C->E, so it *enters* E)
				# This matches the standard VCCS stamp.
				if idx_e != -1:
					if idx_b != -1: A[idx_e][idx_b] -= Gm_bjt
					if idx_e != -1: A[idx_e][idx_e] += Gm_bjt
					b[idx_e] -= Ic_offset_bjt

			elif region == "SATURATION":
				# 1. Base-Emitter Diode Model (Same as Active)
				var G_be_sat = 1.0 / R_be_active_model # Use same R_be for saturation model
				var Is_be_sat = vbe_on_model / R_be_active_model

				if idx_b != -1: A[idx_b][idx_b] += G_be_sat; b[idx_b] += Is_be_sat
				if idx_e != -1: A[idx_e][idx_e] += G_be_sat; b[idx_e] -= Is_be_sat
				if idx_b != -1 and idx_e != -1:
					A[idx_b][idx_e] -= G_be_sat; A[idx_e][idx_b] -= G_be_sat
				
				# 2. Collector-Emitter Model (Norton Equivalent for Vce_sat in series with R_ce_sat_model)
				# Vc - Ve = Vce_sat + Ice_sat_calc * R_ce_sat_model
				var G_ce_sat = 1.0 / R_ce_sat_model
				var Is_ce_sat = vce_sat_model / R_ce_sat_model # Current source part of Norton equiv.

				if idx_c != -1: A[idx_c][idx_c] += G_ce_sat; b[idx_c] += Is_ce_sat
				if idx_e != -1: A[idx_e][idx_e] += G_ce_sat; b[idx_e] -= Is_ce_sat
				if idx_c != -1 and idx_e != -1:
					A[idx_c][idx_e] -= G_ce_sat; A[idx_e][idx_c] -= G_ce_sat
		
		elif comp_data.type == "PNPBJT":
			var region_pnp = comp_data.properties["operating_region"]
			var beta_pnp = comp_data.properties["beta_dc"]
			var veb_on_model_pnp = comp_data.properties["veb_on"] # Ve - Vb
			var vec_sat_model_pnp = comp_data.properties["vec_sat"] # Ve - Vc
			
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
			var R_pnp_off_model = 1.0e9 # Consistent with NPN off resistance

			if region_pnp == "OFF":
				var g_off_pnp = 1.0 / R_pnp_off_model
				_stamp_conductance(A, g_off_pnp, idx_e_pnp, idx_b_pnp) # E-B
				_stamp_conductance(A, g_off_pnp, idx_e_pnp, idx_c_pnp) # E-C
				_stamp_conductance(A, g_off_pnp, idx_b_pnp, idx_c_pnp) # B-C (reverse)
			
			elif region_pnp == "ACTIVE":
				# 1. Emitter-Base Diode (Norton: G_eb in parallel with Is_eb from E to B)
				var G_eb_active_pnp = 1.0 / R_eb_active_model_pnp
				var Is_eb_active_pnp = veb_on_model_pnp / R_eb_active_model_pnp

				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += G_eb_active_pnp; b[idx_e_pnp] += Is_eb_active_pnp
				if idx_b_pnp != -1: A[idx_b_pnp][idx_b_pnp] += G_eb_active_pnp; b[idx_b_pnp] -= Is_eb_active_pnp
				if idx_e_pnp != -1 and idx_b_pnp != -1:
					A[idx_e_pnp][idx_b_pnp] -= G_eb_active_pnp; A[idx_b_pnp][idx_e_pnp] -= G_eb_active_pnp
				
				# 2. Collector Current Source: Ic = beta * Ib. (Ib flows E->B, Ic flows E->C)
				# Ic = Gm_pnp * (Ve - Vb) - Ic_const_offset_pnp. This current flows from E to C.
				var Gm_pnp_mna = beta_pnp * G_eb_active_pnp
				var Ic_const_offset_pnp_mna = beta_pnp * Is_eb_active_pnp # = beta_pnp * veb_on_model_pnp / R_eb_active_model_pnp
				
				# VCCS stamp for current Gm_pnp_mna * (Ve - Vb) flowing E -> C
				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += Gm_pnp_mna
				if idx_e_pnp != -1 and idx_b_pnp != -1: A[idx_e_pnp][idx_b_pnp] -= Gm_pnp_mna
				if idx_c_pnp != -1 and idx_e_pnp != -1: A[idx_c_pnp][idx_e_pnp] -= Gm_pnp_mna
				if idx_c_pnp != -1 and idx_b_pnp != -1: A[idx_c_pnp][idx_b_pnp] += Gm_pnp_mna
				
				# Current source component (-Ic_const_offset_pnp_mna) flowing E -> C
				# Correction: Stamp as entering Emitter (+), leaving Collector (-)
				if idx_e_pnp != -1: b[idx_e_pnp] += Ic_const_offset_pnp_mna
				if idx_c_pnp != -1: b[idx_c_pnp] -= Ic_const_offset_pnp_mna

			elif region_pnp == "SATURATION":
				# 1. Emitter-Base Diode Model (Same as Active)
				var G_eb_sat_pnp = 1.0 / R_eb_active_model_pnp 
				var Is_eb_sat_pnp = veb_on_model_pnp / R_eb_active_model_pnp

				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += G_eb_sat_pnp; b[idx_e_pnp] += Is_eb_sat_pnp
				if idx_b_pnp != -1: A[idx_b_pnp][idx_b_pnp] += G_eb_sat_pnp; b[idx_b_pnp] -= Is_eb_sat_pnp
				if idx_e_pnp != -1 and idx_b_pnp != -1:
					A[idx_e_pnp][idx_b_pnp] -= G_eb_sat_pnp; A[idx_b_pnp][idx_e_pnp] -= G_eb_sat_pnp
				
				# 2. Emitter-Collector Model (Norton: G_ec_sat in parallel with Is_ec_sat from E to C)
				var G_ec_sat_pnp = 1.0 / R_ec_sat_model_pnp
				var Is_ec_sat_pnp = vec_sat_model_pnp / R_ec_sat_model_pnp

				if idx_e_pnp != -1: A[idx_e_pnp][idx_e_pnp] += G_ec_sat_pnp; b[idx_e_pnp] += Is_ec_sat_pnp
				if idx_c_pnp != -1: A[idx_c_pnp][idx_c_pnp] += G_ec_sat_pnp; b[idx_c_pnp] -= Is_ec_sat_pnp
				if idx_e_pnp != -1 and idx_c_pnp != -1:
					A[idx_e_pnp][idx_c_pnp] -= G_ec_sat_pnp; A[idx_c_pnp][idx_e_pnp] -= G_ec_sat_pnp
		
		elif comp_data.type == "ZenerDiode":
			var state_zener = comp_data.properties["operating_state"]
			var Vf_zener_model = comp_data.properties["forward_voltage"]
			var Vz_zener_model = comp_data.properties["zener_voltage"] # Positive value

			var term_a_z = comp_data.terminals["A"]
			var term_k_z = comp_data.terminals["K"]
			var node_a_id_z = terminal_connections.get(term_a_z.get_instance_id() if is_instance_valid(term_a_z) else -1, -1)
			var node_k_id_z = terminal_connections.get(term_k_z.get_instance_id() if is_instance_valid(term_k_z) else -1, -1)
			var idx_a_z = node_id_to_matrix_index.get(node_a_id_z, -1)
			var idx_k_z = node_id_to_matrix_index.get(node_k_id_z, -1)

			var R_on_model = 0.1 # Small resistance for FORWARD and ZENER states
			if R_on_model < 1e-9: R_on_model = 1e-9
			var G_on_model = 1.0 / R_on_model
			var R_off_model = 1.0e9 # High resistance for OFF state
			var G_off_model = 1.0 / R_off_model

			if state_zener == "OFF":
				_stamp_conductance(A, G_off_model, idx_a_z, idx_k_z)
			elif state_zener == "FORWARD":
				# Model as Vf_zener_model in series with R_on_model (Norton equivalent)
				# Current flows A -> K. I = (Vak - Vf) / R_on = G_on * Vak - G_on * Vf
				# KCL at A: ... + G_on*Vk - G_on*Va = -G_on*Vf  => b[idx_a_z] += G_on*Vf
				# KCL at K: ... + G_on*Va - G_on*Vk =  G_on*Vf  => b[idx_k_z] -= G_on*Vf
				_stamp_conductance(A, G_on_model, idx_a_z, idx_k_z)
				var current_offset_fwd = G_on_model * Vf_zener_model
				if idx_a_z != -1: b[idx_a_z] += current_offset_fwd
				if idx_k_z != -1: b[idx_k_z] -= current_offset_fwd
			elif state_zener == "ZENER":
				# Model as Vz_zener_model (reverse) in series with R_on_model (Norton equivalent)
				# Current flows K -> A. Vka = Vk - Va. Zener breakdown is Vka = Vz_model.
				# I_rev = (Vka - Vz_model) / R_on_model = G_on * Vka - G_on * Vz_model
				# This current I_rev flows K -> A.
				# KCL at K: ... + G_on*Va - G_on*Vk = -G_on*Vz_model  => b[idx_k_z] += G_on*Vz_model
				# KCL at A: ... + G_on*Vk - G_on*Va =  G_on*Vz_model  => b[idx_a_z] -= G_on*Vz_model
				_stamp_conductance(A, G_on_model, idx_a_z, idx_k_z) # Conductance part is same as forward
				var current_offset_zener = G_on_model * Vz_zener_model
				if idx_k_z != -1: b[idx_k_z] += current_offset_zener # Current source into K
				if idx_a_z != -1: b[idx_a_z] -= current_offset_zener # Current source out of A
		
		elif comp_data.type == "Relay":
			# 1. Stamp Coil Resistance
			var R_coil = comp_data.properties["coil_resistance"]
			if R_coil <= 1e-9: R_coil = 1e-9 # Min resistance
			var g_coil = 1.0 / R_coil
			
			var term_cp = comp_data.terminals["CoilP"]
			var term_cn = comp_data.terminals["CoilN"]
			var node_cp_id = terminal_connections.get(term_cp.get_instance_id() if is_instance_valid(term_cp) else -1, -1)
			var node_cn_id = terminal_connections.get(term_cn.get_instance_id() if is_instance_valid(term_cn) else -1, -1)
			var idx_cp = node_id_to_matrix_index.get(node_cp_id, -1)
			var idx_cn = node_id_to_matrix_index.get(node_cn_id, -1)
			_stamp_conductance(A, g_coil, idx_cp, idx_cn)

			# 2. Stamp Switch Contacts
			var R_sw_closed = 1e-6 
			if R_sw_closed <= 1e-9: R_sw_closed = 1e-9
			var g_sw_closed = 1.0 / R_sw_closed
			var R_sw_open = 1.0e12 
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

			if comp_data.properties["is_energized"]: # Energized: COM-NO closed, COM-NC open
				_stamp_conductance(A, g_sw_closed, idx_com_relay, idx_no_relay)
				_stamp_conductance(A, g_sw_open, idx_com_relay, idx_nc_relay)
			else: # De-energized: COM-NC closed, COM-NO open
				_stamp_conductance(A, g_sw_open, idx_com_relay, idx_no_relay)
				_stamp_conductance(A, g_sw_closed, idx_com_relay, idx_nc_relay)

	_needs_rebuild = false
	return { "A": A, "b": b, "node_map": node_id_to_matrix_index, "vs_map": active_vs_id_to_matrix_index, "inductor_map": inductor_id_to_matrix_index }

## Helper function to stamp a conductance G between node idx1 and node idx2 into matrix A.
## Handles cases where idx1 or idx2 might be -1 (ground).
func _stamp_conductance(A_matrix: Array, g_value: float, idx1: int, idx2: int):
	if idx1 != -1 and idx2 != -1: # Both nodes are non-ground
		A_matrix[idx1][idx1] += g_value
		A_matrix[idx2][idx2] += g_value
		A_matrix[idx1][idx2] -= g_value
		A_matrix[idx2][idx1] -= g_value
	elif idx1 != -1: # node1 is non-ground, node2 is ground (idx2 == -1)
		A_matrix[idx1][idx1] += g_value
	elif idx2 != -1: # node2 is non-ground, node1 is ground (idx1 == -1)
		A_matrix[idx2][idx2] += g_value
	# If both idx1 and idx2 are -1 (both ground), do nothing.

# Calculate current through passive components AFTER node voltages are solved.
# Also updates state for next step (e.g. capacitor voltage Vc(t-dt)).
# delta_time is needed for capacitor current calculation.
func _calculate_passive_component_currents(delta_time: float):
	if not _is_solved:
		_log("Skipping passive current calculation as circuit is not solved.", LogLevel.HIGH)
		return

	_log("Calculating passive component currents & updating state for next step (dt={dt_str}s)...".format({"dt_str": String.num(delta_time, 4)}), LogLevel.LOW)
	for comp_data in components:
		var comp_node = comp_data.component_node
		if not is_instance_valid(comp_node): 
			_log("Skipping current calculation for invalid component node.", LogLevel.LOW, true)
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
				# if not comp_id in component_results: component_results[comp_id] = {} # Done above
				component_results[comp_id]["current"] = current
				_log("Resistor {comp_name} Current = {curr_str} A (V1={v1_str}, V2={v2_str}, R={r_str})".format({"comp_name": comp_node.name, "curr_str": String.num(current,4), "v1_str": String.num(V1,4), "v2_str": String.num(V2,4), "r_str": String.num(R,2)}), LogLevel.HIGH)
			# ... (error/NAN handling as before)

		elif comp_data.type == "LED":
			var R_led_model = 0.1 # Must match _build_mna_system
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
			elif comp_data.get("conducting", false) and not is_nan(Va) and not is_nan(Vk) and R_led_model > 1e-12:
				var effective_voltage_across_Rd_on = (Va - Vk) - Vf_led
				if effective_voltage_across_Rd_on > 0:
					current = effective_voltage_across_Rd_on / R_led_model
				else:
					current = 0.0 

				log_msg_suffix = "Conducting"
				# Check for burning only if not already burned
				if current > comp_data.properties["max_current"]:
					comp_data.is_burned = true
					comp_data.conducting = false 
					current = 0.0 
					log_msg_suffix = "JUST BURNED! (Current is 0)"
			else: 
				current = 0.0
				log_msg_suffix = "Not Conducting (Below Vf or error)"
			
			# if not comp_id in component_results: component_results[comp_id] = {} # Done above
			component_results[comp_id]["current"] = current
			_log("LED {comp_name} Current (Approx) = {curr_str} A (Va={va_str}, Vk={vk_str}, Vf={vf_str}, R_model={r_model_str}, {log_suffix})".format({"comp_name": comp_node.name, "curr_str": String.num(current,4), "va_str": String.num(Va,4), "vk_str": String.num(Vk,4), "vf_str": String.num(Vf_led,2), "r_model_str": String.num(R_led_model,2), "log_suffix": log_msg_suffix}), LogLevel.HIGH)
			# ... (error/NAN handling if Va/Vk are NAN)

		elif comp_data.type == "Diode":
			var R_diode_on_model = 0.1 # Must match R_diode_on_model in _build_mna_system
			var Vf_diode_calc = comp_data.properties["forward_voltage"]
			var term_a = comp_data.terminals["A"]
			var term_k = comp_data.terminals["K"]
			var node_a_id = terminal_connections.get(term_a.get_instance_id(), -1)
			var node_k_id = terminal_connections.get(term_k.get_instance_id(), -1)
			var Va = electrical_nodes.get(node_a_id, {}).get("voltage", NAN)
			var Vk = electrical_nodes.get(node_k_id, {}).get("voltage", NAN)
			var current = 0.0
			var log_msg_suffix = "Not Conducting"

			if comp_data.get("conducting", false) and not is_nan(Va) and not is_nan(Vk) and R_diode_on_model > 1e-12:
				var V_ak_calc = Va - Vk
				if V_ak_calc > Vf_diode_calc: # Check if voltage is enough to overcome Vf
					current = (V_ak_calc - Vf_diode_calc) / R_diode_on_model
				else:
					current = 0.0 # Not enough voltage across for current even if "conducting" flag was true
				log_msg_suffix = "Conducting (flag was true)"
			else: # Not conducting or NaN voltages
				current = 0.0
				if is_nan(Va) or is_nan(Vk):
					log_msg_suffix = "Not Conducting (NaN voltages)"
				# else: log_msg_suffix remains "Not Conducting" (flag was false)

			component_results[comp_id]["current"] = current
			_log("Diode {comp_name} Current (Approx) = {curr_str} A (Va={va_str}, Vk={vk_str}, Vf={vf_str}, R_on_model={r_on_model_str}, {log_suffix})".format({
				"comp_name": comp_node.name, "curr_str": String.num(current,4), 
				"va_str": String.num(Va,4), "vk_str": String.num(Vk,4), 
				"vf_str": String.num(Vf_diode_calc,2), "r_on_model_str": String.num(R_diode_on_model,2), 
				"log_suffix": log_msg_suffix
			}), LogLevel.HIGH)
			# ... (error/NAN handling)

		elif comp_data.type == "Switch":
			var state: Switch3D.State = comp_data.state # comp_data.state should exist
			var R_closed = 1e-6
			var term_com = comp_data.terminals["COM"]
			var node_com_id = terminal_connections.get(term_com.get_instance_id(), -1)
			var V_com = electrical_nodes.get(node_com_id, {}).get("voltage", NAN)
			var active_term_name = "NC" if state == Switch3D.State.CONNECTED_NC else "NO"
			var active_term = comp_data.terminals[active_term_name]
			var active_node_id = terminal_connections.get(active_term.get_instance_id(), -1)
			var V_active = electrical_nodes.get(active_node_id, {}).get("voltage", NAN)
			var current = NAN
			if not is_nan(V_com) and not is_nan(V_active) and R_closed > 1e-12:
				current = (V_com - V_active) / R_closed
				_log("Switch {comp_n} Current (Approx, {act_term}) = {curr_s} A (V_com={v_com_s}, V_{act_term}={v_act_s}, R_closed={r_closed_s})".format({
					"comp_n": comp_node.name, "act_term": active_term_name, "curr_s": String.num(current,4),
					"v_com_s": String.num(V_com,4), "v_act_s": String.num(V_active,4), "r_closed_s": String.num_scientific(R_closed)
				}), LogLevel.HIGH)
			# ... (error/NAN handling)
			# if not comp_id in component_results: component_results[comp_id] = {} # Done above
			component_results[comp_id]["current"] = current
		
		elif comp_data.type == "PolarizedCapacitor":
			var C_val = comp_data.properties["capacitance"]
			var max_V_cap = comp_data.properties["max_voltage"]
			var Vc_prev_dt_val = comp_data.properties.get("voltage_across_cap_prev_dt", 0.0)

			var term1_cap_node = comp_data.terminals["T1"] # Positive
			var term2_cap_node = comp_data.terminals["T2"] # Negative
			var node1_id_cap_val = terminal_connections.get(term1_cap_node.get_instance_id(), -1)
			var node2_id_cap_val = terminal_connections.get(term2_cap_node.get_instance_id(), -1)

			var V1_cap_t = electrical_nodes.get(node1_id_cap_val, {}).get("voltage", NAN) # Voltage at T1 (Positive)
			var V2_cap_t = electrical_nodes.get(node2_id_cap_val, {}).get("voltage", NAN) # Voltage at T2 (Negative)
			
			var current_cap = NAN
			var Vc_t = NAN # Voltage across capacitor: V(T1) - V(T2)

			if comp_data.get("is_exploded", false):
				current_cap = 0.0 # No current if exploded
				# Vc_t might be the voltage at explosion, or NaN if nodes are gone.
				# We should try to get it if possible for display, but don't update Vc_prev_dt.
				if not is_nan(V1_cap_t) and not is_nan(V2_cap_t): Vc_t = V1_cap_t - V2_cap_t
				_log("PolarizedCapacitor {comp_n}: EXPLODED. Current=0A. Vc(t-dt) was {vc_prev_s} V".format({"comp_n": comp_node.name, "vc_prev_s": String.num(Vc_prev_dt_val,4)}), LogLevel.HIGH)
			elif not is_nan(V1_cap_t) and not is_nan(V2_cap_t):
				Vc_t = V1_cap_t - V2_cap_t # Vc(t) = V(T1) - V(T2)
				
				# Check for explosion conditions
				var reverse_polarity_tolerance = -0.1 # Allow small negative voltage before "reverse" explosion
				if Vc_t > max_V_cap or Vc_t < reverse_polarity_tolerance: # V(T1)-V(T2) too high, or V(T1) significantly less than V(T2)
					comp_data.is_exploded = true
					current_cap = 0.0 # No current once exploded
					_log("PolarizedCapacitor {comp_n}: JUST EXPLODED! Vc(t)={vc_t_s}V (Max={max_v_s}V). Current becomes 0A.".format({"comp_n": comp_node.name, "vc_t_s": String.num(Vc_t,4), "max_v_s": String.num(max_V_cap,2)}), LogLevel.HIGH)
				else: # Not exploded, calculate current normally
					current_cap = C_val * (Vc_t - Vc_prev_dt_val) / delta_time
					comp_data.properties["voltage_across_cap_prev_dt"] = Vc_t # Store Vc_t for the next time step
					_log("PolarizedCapacitor {comp_n}: Current={i_cap_s} A, Vc(t)={vc_t_s} V (Vc(t-dt)={vc_prev_s} V, C={c_val_s} F, MaxV={max_v_s}V)".format({
						"comp_n": comp_node.name, "i_cap_s": String.num(current_cap,4), "vc_t_s": String.num(Vc_t,4),
						"vc_prev_s": String.num(Vc_prev_dt_val,4), "c_val_s": String.num_scientific(C_val), "max_v_s": String.num(max_V_cap,2)
					}), LogLevel.HIGH)
			else: # Voltages are NaN, cannot determine state or current
				_log("PolarizedCapacitor {comp_n}: Voltages NaN, cannot calculate current/state. Vc(t-dt) remains {vc_prev_s} V".format({"comp_n": comp_node.name, "vc_prev_s": String.num(Vc_prev_dt_val,4)}), LogLevel.HIGH)
			
			component_results[comp_id]["current"] = current_cap
			component_results[comp_id]["voltage_across"] = Vc_t
			component_results[comp_id]["is_exploded"] = comp_data.get("is_exploded", false)
		
		elif comp_data.type == "NonPolarizedCapacitor":
			var C_np_val = comp_data.properties["capacitance"]
			var max_V_np_cap = comp_data.properties["max_voltage"] # For info/warning, not explosion
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
				comp_data.properties["voltage_across_cap_prev_dt"] = Vc_np_t # Store for next step
				
				var over_voltage_info = ""
				if abs(Vc_np_t) > max_V_np_cap: # Check absolute voltage against max rating
					over_voltage_info = " (WARNING: Exceeds Max Voltage {max_v_s}V)".format({"max_v_s": String.num(max_V_np_cap,2)})

				_log("NonPolarizedCapacitor {comp_n}: Current={i_cap_s} A, Vc(t)={vc_t_s} V (Vc(t-dt)={vc_prev_s} V, C={c_val_s} F){warn_s}".format({
					"comp_n": comp_node.name, "i_cap_s": String.num(current_np_cap,4), "vc_t_s": String.num(Vc_np_t,4),
					"vc_prev_s": String.num(Vc_prev_dt_np_val,4), "c_val_s": String.num_scientific(C_np_val), "warn_s": over_voltage_info
				}), LogLevel.HIGH)
			else:
				_log("NonPolarizedCapacitor {comp_n}: Voltages NaN, cannot calculate current. Vc(t-dt) remains {vc_prev_s} V".format({"comp_n": comp_node.name, "vc_prev_s": String.num(Vc_prev_dt_np_val,4)}), LogLevel.HIGH)

			component_results[comp_id]["current"] = current_np_cap
			component_results[comp_id]["voltage_across"] = Vc_np_t
			# No is_exploded for non-polarized

		elif comp_data.type == "Inductor":
			# Current I_L(t) for inductor is already solved and stored in component_results[comp_id]["current"]
			# by the main solve loop from the MNA variable.
			# Here, we just need to update I_L(t-dt) for the next step and log.
			var I_L_t_val = component_results[comp_id].get("current", NAN) # This is I_L(t)
			var V_across_L_val = component_results[comp_id].get("voltage_across", NAN) # This is V_L(t) = V1-V2

			if not is_nan(I_L_t_val):
				comp_data.properties["current_through_L_prev_dt"] = I_L_t_val # Store I_L(t) for next step's I_L(t-dt)
			
			_log("Inductor {comp_n}: Final I_L(t)={i_l_s} A, V_L(t)={v_l_s} V. Stored I_L(t-dt) for next step: {i_l_prev_s} A".format({
				"comp_n": comp_node.name, 
				"i_l_s": String.num(I_L_t_val,4) if not is_nan(I_L_t_val) else "N/A",
				"v_l_s": String.num(V_across_L_val,4) if not is_nan(V_across_L_val) else "N/A",
				"i_l_prev_s": String.num(comp_data.properties["current_through_L_prev_dt"],4)
			}), LogLevel.HIGH)
			# Voltage across inductor is already in component_results from the main solve loop if successful.
		
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
			
			# Use the same model parameters as in _build_mna_system for consistency
			var R_be_active_model_calc = 50.0
			var R_ce_sat_model_calc = 5.0
			# R_bjt_off_model is not used for current calc directly, as currents are zero if OFF

			if not is_nan(Vc) and not is_nan(Vb) and not is_nan(Ve):
				var Vbe_actual = Vb - Ve
				var Vce_actual = Vc - Ve
				
				if region == "OFF":
					Ib = 0.0; Ic = 0.0; Ie = 0.0
				elif region == "ACTIVE":
					# Calculate Ib using the B-E diode model: Ib = (Vb - Ve - Vbe_on) / R_be_active_model
					if Vbe_actual > vbe_on_calc:
						Ib = (Vbe_actual - vbe_on_calc) / R_be_active_model_calc
					else: # If Vbe_actual not enough to overcome Vbe_on, Ib is effectively zero
						Ib = 0.0
					if Ib < 0.0: Ib = 0.0 # Base current cannot be negative in this simple model for NPN active
					
					Ic = beta * Ib
					Ie = Ic + Ib
				elif region == "SATURATION":
					# Calculate Ib using B-E diode model (same as active for Ib)
					if Vbe_actual > vbe_on_calc:
						Ib = (Vbe_actual - vbe_on_calc) / R_be_active_model_calc
					else:
						Ib = 0.0
					if Ib < 0.0: Ib = 0.0

					# Calculate Ic using C-E saturation model: Ice_sat = (Vc - Ve - Vce_sat) / R_ce_sat_model
					if Vce_actual > vce_sat_calc: # Transistor is trying to leave saturation towards active
						Ic = (Vce_actual - vce_sat_calc) / R_ce_sat_model_calc
					else: # Deeply saturated or at the Vce_sat edge
						Ic = 0.0 # If Vce_actual <= Vce_sat, current through R_ce_sat_model would be zero or negative (unphysical for this simplified model direction)
								 # A more accurate saturation model would handle Ic not being simply beta*Ib.
								 # For now, Ic is limited by the C-E path.
					if Ic < 0.0: Ic = 0.0 # Collector current in NPN saturation is positive C to E.

					# In saturation, Ic is NOT simply beta * Ib. It's limited by the external circuit.
					# The Ic calculated above is from the C-E path characteristics.
					# We must ensure that this Ic is not greater than what beta*Ib would allow if it were active.
					# However, the definition of saturation is that Ic < beta*Ib.
					# So, the Ic calculated from C-E path is the actual collector current.
					Ie = Ic + Ib
			
			component_results[comp_id]["Ic"] = Ic
			component_results[comp_id]["Ib"] = Ib
			component_results[comp_id]["Ie"] = Ie
			component_results[comp_id]["region"] = region # Store region used for MNA
			
			_log("NPNBJT {name}: Region={reg}, Ib={ib_s}A, Ic={ic_s}A, Ie={ie_s}A (Vbe={vbe_act_s}V, Vce={vce_act_s}V)".format({
				"name": comp_node.name, "reg": region, 
				"ib_s": String.num(Ib,4) if not is_nan(Ib) else "N/A", 
				"ic_s": String.num(Ic,4) if not is_nan(Ic) else "N/A", 
				"ie_s": String.num(Ie,4) if not is_nan(Ie) else "N/A",
				"vbe_act_s": String.num(Vb-Ve,2) if not is_nan(Vb) and not is_nan(Ve) else "N/A", # NPN Vbe, Vce
				"vce_act_s": String.num(Vc-Ve,2) if not is_nan(Vc) and not is_nan(Ve) else "N/A",
			}), LogLevel.HIGH)
		
		elif comp_data.type == "PNPBJT":
			var Ve_pnp_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["E"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Vb_pnp_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["B"].get_instance_id(), -1), {}).get("voltage", NAN)
			var Vc_pnp_calc = electrical_nodes.get(terminal_connections.get(comp_data.terminals["C"].get_instance_id(), -1), {}).get("voltage", NAN)
			
			var region_pnp_calc = comp_data.properties["operating_region"]
			var beta_pnp_calc = comp_data.properties["beta_dc"]
			var veb_on_pnp_model_calc = comp_data.properties["veb_on"]
			var vec_sat_pnp_model_calc = comp_data.properties["vec_sat"]
			
			var Ic_pnp: float = NAN # Current OUT of Collector
			var Ib_pnp: float = NAN # Current OUT of Base
			var Ie_pnp: float = NAN # Current IN to Emitter
			
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
			
			_log("PNPBJT {name}: Region={reg}, Ib={ib_s}A, Ic={ic_s}A, Ie={ie_s}A (Veb={veb_act_s}V, Vec={vec_act_s}V)".format({
				"name": comp_node.name, "reg": region_pnp_calc, 
				"ib_s": String.num(Ib_pnp,4) if not is_nan(Ib_pnp) else "N/A", 
				"ic_s": String.num(Ic_pnp,4) if not is_nan(Ic_pnp) else "N/A", 
				"ie_s": String.num(Ie_pnp,4) if not is_nan(Ie_pnp) else "N/A",
				"veb_act_s": String.num(Ve_pnp_calc-Vb_pnp_calc,2) if not is_nan(Ve_pnp_calc) and not is_nan(Vb_pnp_calc) else "N/A", # PNP Veb, Vec
				"vec_act_s": String.num(Ve_pnp_calc-Vc_pnp_calc,2) if not is_nan(Ve_pnp_calc) and not is_nan(Vc_pnp_calc) else "N/A",
			}), LogLevel.HIGH)

		elif comp_data.type == "ZenerDiode":
			var state_z = comp_data.properties["operating_state"]
			var Vf_z_calc = comp_data.properties["forward_voltage"]
			var Vz_calc = comp_data.properties["zener_voltage"] # Positive value
			var R_on_z_model = 0.1 # Matches R_on_model in _build_mna_system

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
						current_zener = (Vak_z_val - Vf_z_calc) / R_on_z_model # Current A->K
					else:
						current_zener = 0.0
				elif state_z == "ZENER":
					# Vka = Vk_z_val - Va_z_val. Current K->A is (Vka - Vz_calc) / R_on_z_model
					# Current A->K is -( (Vk_z_val - Va_z_val) - Vz_calc ) / R_on_z_model
					# = ( (Va_z_val - Vk_z_val) + Vz_calc ) / R_on_z_model
					# = (Vak_z_val + Vz_calc) / R_on_z_model
					# This current will be negative.
					if (Vk_z_val - Va_z_val) > Vz_calc : # If magnitude of reverse voltage (Vka) is greater than Vz
						current_zener = -( (Vk_z_val - Va_z_val) - Vz_calc ) / R_on_z_model
					else: # Not enough reverse voltage to maintain zener current based on model
						current_zener = 0.0

				elif state_z == "OFF":
					current_zener = 0.0
			
			component_results[comp_id]["current"] = current_zener
			component_results[comp_id]["voltage_ak"] = Vak_z_val # Voltage Anode - Kathode
			component_results[comp_id]["state"] = state_z
			
			_log("ZenerDiode {name}: State={st}, Current={i_s}A, Vak={vak_s}V (Vf={vf_s}, Vz={vz_s})".format({
				"name": comp_node.name, "st": state_z, 
				"i_s": String.num(current_zener,4) if not is_nan(current_zener) else "N/A", 
				"vak_s": String.num(Vak_z_val,2) if not is_nan(Vak_z_val) else "N/A",
				"vf_s": String.num(Vf_z_calc,2), "vz_s": String.num(Vz_calc,2)
			}), LogLevel.HIGH)
			
		elif comp_data.type == "Relay":
			var term_cp_res = comp_data.terminals["CoilP"]
			var term_cn_res = comp_data.terminals["CoilN"]
			var node_cp_id_res = terminal_connections.get(term_cp_res.get_instance_id(), -1)
			var node_cn_id_res = terminal_connections.get(term_cn_res.get_instance_id(), -1)
			var V_cp_res = electrical_nodes.get(node_cp_id_res, {}).get("voltage", NAN)
			var V_cn_res = electrical_nodes.get(node_cn_id_res, {}).get("voltage", NAN)
			
			var coil_voltage_actual_res = NAN
			var coil_current_res = NAN
			var coil_R_res = comp_data.properties["coil_resistance"]

			if not is_nan(V_cp_res) and not is_nan(V_cn_res):
				coil_voltage_actual_res = V_cp_res - V_cn_res
				if coil_R_res > 1e-9:
					coil_current_res = coil_voltage_actual_res / coil_R_res
			
			var is_energized_res = comp_data.properties["is_energized"]
			component_results[comp_id]["coil_voltage"] = coil_voltage_actual_res
			component_results[comp_id]["coil_current"] = coil_current_res
			component_results[comp_id]["is_energized"] = is_energized_res
			component_results[comp_id]["coil_threshold"] = comp_data.properties["coil_voltage_threshold"] # For display

			# Optionally calculate current through contacts if needed for specific logging
			var R_sw_closed_calc = 1e-6 # Match MNA model
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

			_log("Relay {name}: CoilV={cv_s}V, CoilI={ci_s}A, Energized={en_s}{contact_i_s}".format({
				"name": comp_node.name, 
				"cv_s": String.num(coil_voltage_actual_res,2) if not is_nan(coil_voltage_actual_res) else "N/A",
				"ci_s": String.num(coil_current_res,3) if not is_nan(coil_current_res) else "N/A",
				"en_s": is_energized_res,
				"contact_i_s": contact_current_str
			}), LogLevel.HIGH)

		elif comp_data.type == "Potentiometer":
			var total_R = comp_data.properties["total_resistance"]
			var wiper_pos = comp_data.properties["wiper_position"]

			var R1_val = total_R * wiper_pos
			if R1_val < 1e-12: R1_val = 1e-12 # Avoid div by zero, but use small for current calc
			
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
				current1W = (V1 - VW) / R1_val if R1_val > 1e-12 else (V1 - VW) * 1e12 # Handle near-zero R

			var currentW2 = NAN
			if not is_nan(VW) and not is_nan(V2):
				currentW2 = (VW - V2) / R2_val if R2_val > 1e-12 else (VW - V2) * 1e12

			# if not comp_id in component_results: component_results[comp_id] = {} # Done above
			component_results[comp_id]["current_T1_W"] = current1W
			component_results[comp_id]["current_W_T2"] = currentW2
			component_results[comp_id]["current_Wiper_Net"] = current1W - currentW2 if not is_nan(current1W) and not is_nan(currentW2) else NAN
			
			_log("Potentiometer {comp_n}: I(T1-W)={i1w_s} A, I(W-T2)={iw2_s} A (V1={v1_s},VW={vw_s},V2={v2_s}, R1={r1_s},R2={r2_s})".format({
				"comp_n": comp_node.name, "i1w_s": String.num(current1W,4), "iw2_s": String.num(currentW2,4),
				"v1_s": String.num(V1,2), "vw_s": String.num(VW,2), "v2_s": String.num(V2,2),
				"r1_s": String.num(R1_val,2), "r2_s": String.num(R2_val,2)
			}), LogLevel.HIGH)
		
		# Note: PowerSource currents/voltages are calculated/set directly after solver loop, not here.


## Debug function to print the current state of the graph.
func print_graph_state():
	_log("\n--- Circuit Graph State ---", LogLevel.HIGH)
	_log("Terminal Connections (Terminal Instance ID -> Node ID):", LogLevel.HIGH)
	for term_id in terminal_connections:
		var terminal_node = instance_from_id(term_id)
		var terminal_name_display: String 
		if is_instance_valid(terminal_node):
			terminal_name_display = terminal_node.name
			_log("  Terminal {t_id} ({term_disp_name}): Node {node_val}".format({"t_id": term_id, "term_disp_name": terminal_name_display, "node_val": terminal_connections[term_id]}), LogLevel.HIGH)
		else:
			terminal_name_display = "INVALID/FREED"
			_log("  Terminal {t_id} ({term_disp_name}): Node {node_val}".format({"t_id": term_id, "term_disp_name": terminal_name_display, "node_val": terminal_connections[term_id]}), LogLevel.HIGH)
	_log("Electrical Nodes (Node ID -> {terminals, voltage}):", LogLevel.HIGH)
	for node_id in electrical_nodes:
		var terminal_names = []

		for terminal in electrical_nodes[node_id]["terminals"]:
			if is_instance_valid(terminal):
				terminal_names.push_back(terminal.name)
			else:
				terminal_names.push_back("INVALID_TERMINAL_REF")

		var voltage_val_node = electrical_nodes[node_id].voltage
		var voltage_str = "{v_str} V".format({"v_str": String.num(voltage_val_node, 4)}) if not is_nan(voltage_val_node) else "N/A"
		var ground_str = " (GROUND)" if node_id == ground_node_id else ""
		_log("  Node {n_id}{gnd_str}: Voltage={volt_s}, Connects=[{term_names_join}]".format({"n_id": node_id, "gnd_str": ground_str, "volt_s": voltage_str, "term_names_join": ", ".join(terminal_names)}), LogLevel.HIGH)

	_log("Components:", LogLevel.HIGH)
	for comp_data in components:
		var term_str_parts = []
		for term_name in comp_data.terminals:
			var terminal_node = comp_data.terminals[term_name]
			if is_instance_valid(terminal_node):
				term_str_parts.push_back("{n}:{nn}".format({"n": term_name, "nn": terminal_node.name}))
			else:
				term_str_parts.push_back("{n}:INVALID/FREED".format({"n": term_name}))
		var result_str = ""
		var comp_props = comp_data.properties
		
		if not is_instance_valid(comp_data.component_node):
			_log("  - Component Node INVALID/FREED, Type: {comp_type}, Properties: {props_str}, Terminals=({terms_str})".format({
				"comp_type": comp_data.type, "props_str": str(comp_props), "terms_str": ", ".join(term_str_parts)
			}), LogLevel.HIGH)
			continue # Skip to next component if this one is invalid

		var comp_id = comp_data.component_node.get_instance_id()
		var specific_results = component_results.get(comp_id, {})
		
		if comp_data.type == "Potentiometer":
			var current_t1_w_val = specific_results.get("current_T1_W", NAN)
			var current_w_t2_val = specific_results.get("current_W_T2", NAN)
			var current_t1_w_str = "N/A" if is_nan(current_t1_w_val) else String.num(current_t1_w_val, 4)
			var current_w_t2_str = "N/A" if is_nan(current_w_t2_val) else String.num(current_w_t2_val, 4)
			var wiper_val_pgs = comp_props.get("wiper_position", NAN)
			var wiper_pos_str_pgs = "N/A" if is_nan(wiper_val_pgs) else String.num(wiper_val_pgs, 2)
			result_str = " (I_T1W={i_t1w} A, I_WT2={i_wt2} A, Wiper={wp_str})".format({"i_t1w": current_t1_w_str, "i_wt2": current_w_t2_str, "wp_str": wiper_pos_str_pgs})
		elif "current" in specific_results:
			var current_val_sr = specific_results.current
			if not is_nan(current_val_sr):
				result_str = " (Actual I={curr_s} A".format({"curr_s": String.num(current_val_sr, 4)})
				if "voltage" in specific_results and not is_nan(specific_results.voltage): # For CC sources showing voltage
					var voltage_val_sr = specific_results.voltage
					result_str += ", Actual V={volt_s} V".format({"volt_s": String.num(voltage_val_sr, 2)})
				result_str += ")"
			else:
				result_str = " (Actual I=N/A)"
		
		var value_label = "Val"
		var value_display = "N/A"

		if comp_data.type == "Resistor":
			value_label = "R"
			value_display = str(comp_props.get("resistance", "N/A"))
		elif comp_data.type == "PowerSource":
			value_label = "Targets"
			var v_target_pd = comp_props.get("target_voltage", NAN)
			var i_limit_pd = comp_props.get("target_current", NAN)
			var op_mode_pd = comp_props.get("current_operating_mode", "CV")
			var v_target_str_pd = "N/A" if is_nan(v_target_pd) else String.num(v_target_pd, 2)
			var i_limit_str_pd = "N/A" if is_nan(i_limit_pd) else String.num(i_limit_pd, 2)
			value_display = "V:{v_str}V, Ilim:{i_str}A ({mode_str})".format({"v_str": v_target_str_pd, "i_str": i_limit_str_pd, "mode_str": op_mode_pd})
			# Result_str (actual current/voltage) is already populated for PowerSource based on component_results
		elif comp_data.type == "Battery":
			value_label = "Cells"
			var num_c_pd = comp_props.get("num_cells", 0)
			var v_target_b_pd = comp_props.get("target_voltage", NAN)
			var v_target_b_str_pd = "N/A" if is_nan(v_target_b_pd) else String.num(v_target_b_pd, 2)
			value_display = "{n_cells_val} ({v_str}V)".format({"n_cells_val": num_c_pd, "v_str": v_target_b_str_pd})
			# Batteries are ideal voltage sources, no limiting concept here for print_graph_state
		elif comp_data.type == "LED": 
			value_label = "Vf"
			value_display = str(comp_props.get("forward_voltage", "N/A"))
			var conducting_state_str = " (Non-Conducting)"
			if comp_data.get("conducting", false) and not comp_data.get("is_burned", false) :
				conducting_state_str = " (Conducting)"
			
			var burned_state_str = ""
			if comp_data.get("is_burned", false):
				burned_state_str = " (BURNED)"
				conducting_state_str = "" # Don't show conducting if burned

			result_str += conducting_state_str + burned_state_str
		elif comp_data.type == "Diode":
			value_label = "Vf"
			value_display = str(comp_props.get("forward_voltage", "N/A"))
			var conducting_state = " (Non-Conducting)"
			if comp_data.get("conducting", false):
				conducting_state = " (Conducting)"
			result_str += conducting_state
		elif comp_data.type == "Switch":
			value_label = "State"
			var current_switch_state = comp_data.state # Already stored directly
			if current_switch_state != -1 and current_switch_state < Switch3D.State.keys().size():
				value_display = Switch3D.State.keys()[current_switch_state]
			else:
				value_display = "N/A"
		elif comp_data.type == "Potentiometer":
			value_label = "Total_R"
			value_display = str(comp_props.get("total_resistance", "N/A"))
			# Wiper position and currents are in result_str
		elif comp_data.type == "PolarizedCapacitor":
			value_label = "C/MaxV"
			var cap_pc_pd = comp_props.get("capacitance", NAN)
			var max_v_pc_pd = comp_props.get("max_voltage", NAN)
			var cap_str_pc_pd = "N/A" if is_nan(cap_pc_pd) else String.num_scientific(cap_pc_pd)
			var max_v_str_pc_pd = "N/A" if is_nan(max_v_pc_pd) else String.num(max_v_pc_pd, 1)
			value_display = "{c_str}F / {mv_str}V".format({"c_str": cap_str_pc_pd, "mv_str": max_v_str_pc_pd})
			var v_prev_dt = comp_props.get("voltage_across_cap_prev_dt", NAN)
			var v_across = specific_results.get("voltage_across", NAN)
			var i_cap = specific_results.get("current", NAN)
			var exploded_state = specific_results.get("is_exploded", false)
			
			var v_prev_str = "N/A"; if not is_nan(v_prev_dt): v_prev_str = "{v_val_s}V".format({"v_val_s": String.num(v_prev_dt,4)})
			var v_across_str = "N/A"; if not is_nan(v_across): v_across_str = "{v_val_s}V".format({"v_val_s": String.num(v_across,4)})
			var i_cap_str = "N/A"; if not is_nan(i_cap): i_cap_str = "{i_val_s}A".format({"i_val_s": String.num(i_cap,4)})
			
			if exploded_state:
				result_str = " (EXPLODED)"
			else:
				result_str = " (Ic={ic_s}, Vc(t)={vc_s}, Vc_stored_next_dt={vc_prev_s})".format({"ic_s": i_cap_str, "vc_s": v_across_str, "vc_prev_s": v_prev_str})
		elif comp_data.type == "NonPolarizedCapacitor":
			value_label = "C/MaxV"
			var cap_npc_pd = comp_props.get("capacitance", NAN)
			var max_v_npc_pd = comp_props.get("max_voltage", NAN)
			var cap_str_npc_pd = "N/A" if is_nan(cap_npc_pd) else String.num_scientific(cap_npc_pd)
			var max_v_str_npc_pd = "N/A" if is_nan(max_v_npc_pd) else String.num(max_v_npc_pd, 1)
			value_display = "{c_str}F / {mv_str}V".format({"c_str": cap_str_npc_pd, "mv_str": max_v_str_npc_pd})
			
			var v_prev_dt_npc = comp_props.get("voltage_across_cap_prev_dt", NAN)
			var v_across_npc = specific_results.get("voltage_across", NAN)
			var i_cap_npc = specific_results.get("current", NAN)
			
			var v_prev_str_npc = "N/A"; if not is_nan(v_prev_dt_npc): v_prev_str_npc = "{v_val_s}V".format({"v_val_s": String.num(v_prev_dt_npc,4)})
			var v_across_str_npc = "N/A"; if not is_nan(v_across_npc): v_across_str_npc = "{v_val_s}V".format({"v_val_s": String.num(v_across_npc,4)})
			var i_cap_str_npc = "N/A"; if not is_nan(i_cap_npc): i_cap_str_npc = "{i_val_s}A".format({"i_val_s": String.num(i_cap_npc,4)})
			
			result_str = " (Ic={ic_s}, Vc(t)={vc_s}, Vc_stored_next_dt={vc_prev_s})".format({"ic_s": i_cap_str_npc, "vc_s": v_across_str_npc, "vc_prev_s": v_prev_str_npc})
			if not is_nan(v_across_npc) and abs(v_across_npc) > max_v_npc_pd:
				result_str += " (OVERVOLTAGE!)"
		elif comp_data.type == "Inductor":
			value_label = "L"
			var l_val_pd = comp_props.get("inductance", NAN)
			value_display = "N/A" if is_nan(l_val_pd) else String.num_scientific(l_val_pd)
			
			var i_L_pgs = specific_results.get("current", NAN)
			var v_L_pgs = specific_results.get("voltage_across", NAN)
			var i_L_prev_dt_pgs = comp_props.get("current_through_L_prev_dt", NAN)

			var i_L_str_pgs = "N/A" if is_nan(i_L_pgs) else String.num(i_L_pgs,4)
			var v_L_str_pgs = "N/A" if is_nan(v_L_pgs) else String.num(v_L_pgs,2)
			var i_L_prev_dt_str_pgs = "N/A" if is_nan(i_L_prev_dt_pgs) else String.num(i_L_prev_dt_pgs,4)
			
			result_str = " (I_L(t)={il_s} A, V_L(t)={vl_s} V, I_L_stored_next_dt={il_prev_s} A)".format({
				"il_s": i_L_str_pgs, "vl_s": v_L_str_pgs, "il_prev_s": i_L_prev_dt_str_pgs
			})
		elif comp_data.type == "NPNBJT":
			value_label = "B/Vbe/Vcesat"
			var beta_pgs = comp_props.get("beta_dc", NAN)
			var vbe_pgs = comp_props.get("vbe_on", NAN)
			var vcesat_pgs = comp_props.get("vce_sat", NAN)
			value_display = "B:{b_s},Vbe:{vbe_s},Vcesat:{vce_s}".format({
				"b_s": String.num(beta_pgs,1) if not is_nan(beta_pgs) else "N/A",
				"vbe_s": String.num(vbe_pgs,2) if not is_nan(vbe_pgs) else "N/A",
				"vce_s": String.num(vcesat_pgs,2) if not is_nan(vcesat_pgs) else "N/A"
			})
			var region_pgs = specific_results.get("region", "N/A")
			var ib_pgs = specific_results.get("Ib", NAN)
			var ic_pgs = specific_results.get("Ic", NAN)
			var ie_pgs = specific_results.get("Ie", NAN)
			result_str = " (Reg:{r}, Ib:{ib}A, Ic:{ic}A, Ie:{ie}A)".format({
				"r": region_pgs,
				"ib": String.num(ib_pgs,4) if not is_nan(ib_pgs) else "N/A",
				"ic": String.num(ic_pgs,4) if not is_nan(ic_pgs) else "N/A",
				"ie": String.num(ie_pgs,4) if not is_nan(ie_pgs) else "N/A"
			})
		elif comp_data.type == "PNPBJT":
			value_label = "B/Veb/Vecsat" # Note Veb, Vecsat for PNP
			var beta_pnp_pgs = comp_props.get("beta_dc", NAN)
			var veb_pnp_pgs = comp_props.get("veb_on", NAN)
			var vecsat_pnp_pgs = comp_props.get("vec_sat", NAN)
			value_display = "B:{b_s},Veb:{veb_s},Vecsat:{vec_s}".format({
				"b_s": String.num(beta_pnp_pgs,1) if not is_nan(beta_pnp_pgs) else "N/A",
				"veb_s": String.num(veb_pnp_pgs,2) if not is_nan(veb_pnp_pgs) else "N/A",
				"vec_s": String.num(vecsat_pnp_pgs,2) if not is_nan(vecsat_pnp_pgs) else "N/A"
			})
			var region_pnp_pgs = specific_results.get("region", "N/A")
			var ib_pnp_pgs = specific_results.get("Ib", NAN)
			var ic_pnp_pgs = specific_results.get("Ic", NAN)
			var ie_pnp_pgs = specific_results.get("Ie", NAN)
			result_str = " (Reg:{r}, Ib:{ib}A, Ic:{ic}A, Ie:{ie}A)".format({ # Ib, Ic are OUT, Ie is IN
				"r": region_pnp_pgs,
				"ib": String.num(ib_pnp_pgs,4) if not is_nan(ib_pnp_pgs) else "N/A",
				"ic": String.num(ic_pnp_pgs,4) if not is_nan(ic_pnp_pgs) else "N/A",
				"ie": String.num(ie_pnp_pgs,4) if not is_nan(ie_pnp_pgs) else "N/A"
			})
		elif comp_data.type == "NChannelMOSFET":
			value_label = "Vth/Kn"
			var vth_nmos_pgs = comp_props.get("vth", NAN)
			var kn_nmos_pgs = comp_props.get("k_n", NAN)
			value_display = "Vth:{vth_s}V, Kn:{kn_s}A/V^2".format({
				"vth_s": String.num(vth_nmos_pgs,2) if not is_nan(vth_nmos_pgs) else "N/A",
				"kn_s": String.num_scientific(kn_nmos_pgs) if not is_nan(kn_nmos_pgs) else "N/A"
			})
			var region_nmos_pgs = specific_results.get("region", "N/A")
			var id_nmos_pgs = specific_results.get("Id", NAN)
			var vgs_nmos_pgs = specific_results.get("Vgs", NAN)
			var vds_nmos_pgs = specific_results.get("Vds", NAN)
			result_str = " (Reg:{r}, Id:{id}A, Vgs:{vgs}V, Vds:{vds}V)".format({
				"r": region_nmos_pgs,
				"id": String.num(id_nmos_pgs,4) if not is_nan(id_nmos_pgs) else "N/A",
				"vgs": String.num(vgs_nmos_pgs,2) if not is_nan(vgs_nmos_pgs) else "N/A",
				"vds": String.num(vds_nmos_pgs,2) if not is_nan(vds_nmos_pgs) else "N/A"
			})
		elif comp_data.type == "Relay":
			value_label = "CoilVt/CoilR"
			var vt_relay_pgs = comp_props.get("coil_voltage_threshold", NAN)
			var cr_relay_pgs = comp_props.get("coil_resistance", NAN)
			value_display = "Vt:{vt_s}V, R:{cr_s}Ω".format({
				"vt_s": String.num(vt_relay_pgs,2) if not is_nan(vt_relay_pgs) else "N/A",
				"cr_s": String.num(cr_relay_pgs,1) if not is_nan(cr_relay_pgs) else "N/A"
			})
			var vcoil_pgs = specific_results.get("coil_voltage", NAN)
			var icoil_pgs = specific_results.get("coil_current", NAN)
			var energized_pgs = specific_results.get("is_energized", "N/A")
			result_str = " (Vcoil:{vc_s}V, Icoil:{ic_s}A, Energized:{en_s})".format({
				"vc_s": String.num(vcoil_pgs,2) if not is_nan(vcoil_pgs) else "N/A",
				"ic_s": String.num(icoil_pgs,4) if not is_nan(icoil_pgs) else "N/A",
				"en_s": str(energized_pgs)
			})
		elif comp_data.type == "ZenerDiode":
			value_label = "Vf/Vz"
			var vf_zd_pgs = comp_props.get("forward_voltage", NAN)
			var vz_zd_pgs = comp_props.get("zener_voltage", NAN)
			value_display = "Vf:{vf_s}V, Vz:{vz_s}V".format({
				"vf_s": String.num(vf_zd_pgs,2) if not is_nan(vf_zd_pgs) else "N/A",
				"vz_s": String.num(vz_zd_pgs,2) if not is_nan(vz_zd_pgs) else "N/A"
			})
			var state_zd_pgs = specific_results.get("state", "N/A")
			var i_zd_pgs = specific_results.get("current", NAN)
			var vak_zd_pgs = specific_results.get("voltage_ak", NAN)
			result_str = " (State:{s}, I={i}A, Vak={vak}V)".format({
				"s": state_zd_pgs,
				"i": String.num(i_zd_pgs,4) if not is_nan(i_zd_pgs) else "N/A",
				"vak": String.num(vak_zd_pgs,2) if not is_nan(vak_zd_pgs) else "N/A"
			})

		_log("  - {comp_n} ({comp_t}): {val_lbl}={val_disp}, Terminals={{{terms_val}}}{res_s}".format({
			"comp_n": comp_data.component_node.name, "comp_t": comp_data.type, "val_lbl": value_label,
			"val_disp": value_display, "terms_val": ", ".join(term_str_parts), "res_s": result_str
		}), LogLevel.HIGH)
	
	_log("Solved: {is_solved_flag}".format({"is_solved_flag": _is_solved}), LogLevel.HIGH)
	_log("---------------------------\n", LogLevel.HIGH)

## Resets the burn state of a specified LED.
func reset_led_burn_state(component_node: Node3D): # This function seems okay, uses comp_data.is_burned
	for comp_data_item in components: # Use different var name
		if comp_data_item.component_node == component_node and comp_data_item.type == "LED":
			if comp_data_item.get("is_burned", false): # Only act if it was burned
				comp_data_item.is_burned = false
				_log("CircuitGraph: Reset burn state for LED {comp_n}".format({"comp_n": component_node.name}), LogLevel.LOW)
				_is_solved = false # Changing burn state invalidates solution
				_needs_rebuild = true # Matrix needs rebuild as LED model changes
			return # Found the LED, no need to continue loop
	# printerr("CircuitGraph: Could not find LED {name} to reset burn state.".format({"name": component_node.name})) # Optional: if not found
