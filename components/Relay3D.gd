extends Node3D

class_name Relay3D


## Emitted when a key property of the relay changes.
signal configuration_changed(component_node: Node3D)


## The voltage required at the signal pin to energize the relay coil, in Volts.
@export var signal_voltage_threshold: float = 2.5 : set = set_signal_voltage_threshold

## The electrical resistance of the relay's coil, in Ohms.
@export var coil_resistance: float = 100.0 : set = set_coil_resistance

## A flag indicating whether the relay coil is currently energized.
var is_energized: bool = false

## Reference to the coil's positive supply terminal Area3D node.
@onready var terminal_vcc: Area3D = $TerminalVCC         
## Reference to the coil's ground terminal Area3D node.
@onready var terminal_gnd: Area3D = $TerminalGND         
## Reference to the coil's signal input terminal Area3D node.
@onready var terminal_signal: Area3D = $TerminalSignal   
## Reference to the switch's common terminal Area3D node.
@onready var terminal_com: Area3D = $TerminalCOM         
## Reference to the switch's normally open terminal Area3D node.
@onready var terminal_no: Area3D = $TerminalNO           
## Reference to the switch's normally closed terminal Area3D node.
@onready var terminal_nc: Area3D = $TerminalNC           
## Reference to the Label3D for displaying simulation info.
@onready var info_label: Label3D = $InfoLabel
## Reference to the main mesh of the component.
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D 

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal_vcc or not terminal_gnd or not terminal_signal or \
	   not terminal_com or not terminal_no or not terminal_nc:
		printerr("Relay3D requires child Area3D nodes: 'TerminalVCC', 'TerminalGND', 'TerminalSignal', 'TerminalCOM', 'TerminalNO', 'TerminalNC'.")
	if not info_label:
		printerr("Relay3D requires a child Label3D named 'InfoLabel'.")
	if not mesh_instance:
		printerr("Relay3D requires a child MeshInstance3D named 'MeshInstance3D'.")
	
	reset_visual_state()
	set_signal_voltage_threshold(signal_voltage_threshold)
	set_coil_resistance(coil_resistance)

## Sets the signal voltage threshold, validates it, and emits a signal.
func set_signal_voltage_threshold(value: float):
	var new_threshold = max(0.1, value)
	if is_equal_approx(signal_voltage_threshold, new_threshold):
		signal_voltage_threshold = new_threshold
		return

	signal_voltage_threshold = new_threshold
	print("Relay3D {r_name} signal_voltage_threshold set to: {th_val} V".format({"r_name": name, "th_val": String.num(signal_voltage_threshold, 2)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)

## Sets the coil resistance, validates it, and emits a signal.
func set_coil_resistance(value: float):
	var new_resistance = max(1.0, value)
	if is_equal_approx(coil_resistance, new_resistance):
		coil_resistance = new_resistance
		return

	coil_resistance = new_resistance
	print("Relay3D {r_name} coil_resistance set to: {cr_val} Ω".format({"r_name": name, "cr_val": String.num(coil_resistance, 1)}))
	if is_inside_tree():
		emit_signal("configuration_changed", self)




## Displays the calculated state and voltages on the component's 3D label and updates the visual color.
func show_info(results: Dictionary):
	if not info_label: return

	var energized_state_from_results = results.get("is_energized", false)
	self.is_energized = energized_state_from_results

	if energized_state_from_results:
		if is_instance_valid(mesh_instance) and mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color.DARK_GREEN
		elif is_instance_valid(mesh_instance):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color.DARK_GREEN
			mesh_instance.material_override = mat
	else:
		if is_instance_valid(mesh_instance) and mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color(0.4, 0.4, 0.5, 1)
		elif is_instance_valid(mesh_instance):
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 0.4, 0.5, 1)
			mesh_instance.material_override = mat

## Updates the relay's energized state based on an MNA iteration.
func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, node_map_iter: Dictionary, _vs_map_iter: Dictionary) -> bool:
	if x_iter.is_empty():
		return false

	var term_vcc_relay = comp_data.terminals["VCC"]
	var term_gnd_relay = comp_data.terminals["GND"]
	var term_sig_relay = comp_data.terminals["Signal"]

	var node_vcc_id = circuit.terminal_connections.get(term_vcc_relay.get_instance_id(), -1)
	var node_gnd_id = circuit.terminal_connections.get(term_gnd_relay.get_instance_id(), -1)
	var node_sig_id = circuit.terminal_connections.get(term_sig_relay.get_instance_id(), -1)

	var idx_vcc = node_map_iter.get(node_vcc_id, -1)
	var idx_gnd = node_map_iter.get(node_gnd_id, -1)
	var idx_sig = node_map_iter.get(node_sig_id, -1)
	var V_vcc = x_iter[idx_vcc] if idx_vcc != -1 else (0.0 if node_vcc_id == circuit.ground_node_id else NAN)
	var V_gnd = x_iter[idx_gnd] if idx_gnd != -1 else (0.0 if node_gnd_id == circuit.ground_node_id else NAN)
	var V_sig = x_iter[idx_sig] if idx_sig != -1 else (0.0 if node_sig_id == circuit.ground_node_id else NAN)

	var sig_threshold_relay = comp_data.properties["signal_voltage_threshold"]
	var previous_energized_state = comp_data.properties["is_energized"]
	var new_energized_state = previous_energized_state

	if is_nan(V_vcc) or is_nan(V_gnd) or is_nan(V_sig):
		new_energized_state = false 
	else:
		var actual_signal_voltage = V_sig - V_gnd
		var actual_vcc_supply_voltage = V_vcc - V_gnd
		var vcc_min_voltage_for_operation = 0.5 # Define or get from comp_data if it varies

		var signal_is_high_enough = actual_signal_voltage >= (sig_threshold_relay - 1e-5)
		var vcc_is_sufficient = actual_vcc_supply_voltage >= vcc_min_voltage_for_operation

		new_energized_state = signal_is_high_enough and vcc_is_sufficient

	if new_energized_state != previous_energized_state:
		comp_data.properties["is_energized"] = new_energized_state
		return true
	return false




## Applies the relay's contribution to the MNA matrices based on its state.
func stamp(
	A: Array,
	_b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary,
	_inductor_map: Dictionary,
	terminal_connections: Dictionary,
	comp_data: Dictionary,
	_delta_time: float
):
	
	var R_coil_path_val: float
	# Use max() for coil resistance to avoid division by zero
	var R_coil_actual_prop = max(coil_resistance, 1e-9)
	var g_coil_path_val: float

	var vcc_id = terminal_vcc.get_instance_id()
	var gnd_id = terminal_gnd.get_instance_id()
	var node_vcc_lookup = terminal_connections.get(vcc_id, -1)
	var node_gnd_lookup = terminal_connections.get(gnd_id, -1)
	var idx_vcc = node_map.get(node_vcc_lookup, -1)
	var idx_gnd = node_map.get(node_gnd_lookup, -1)

	
	
	
	
	
	if comp_data.properties["is_energized"]: 
		R_coil_path_val = R_coil_actual_prop
	else:
		R_coil_path_val = CircuitGraph.R_SWITCH_OPEN 
	g_coil_path_val = 1.0 / R_coil_path_val
	CircuitGraph.stamp_conductance(A, g_coil_path_val, idx_vcc, idx_gnd)

	var R_sw_closed_const = CircuitGraph.R_SWITCH_CLOSED
	var g_sw_closed_val = 1.0 / R_sw_closed_const
	var R_sw_open_const = CircuitGraph.R_SWITCH_OPEN
	var g_sw_open_val = 1.0 / R_sw_open_const

	var com_sw_id = terminal_com.get_instance_id()
	var no_sw_id = terminal_no.get_instance_id()
	var nc_sw_id = terminal_nc.get_instance_id()

	var node_com_lookup_sw = terminal_connections.get(com_sw_id, -1)
	var node_no_lookup_sw = terminal_connections.get(no_sw_id, -1)
	var node_nc_lookup_sw = terminal_connections.get(nc_sw_id, -1)

	var idx_com_sw = node_map.get(node_com_lookup_sw, -1)
	var idx_no_sw = node_map.get(node_no_lookup_sw, -1)
	var idx_nc_sw = node_map.get(node_nc_lookup_sw, -1)

	if comp_data.properties["is_energized"]: 
		CircuitGraph.stamp_conductance(A, g_sw_closed_val, idx_com_sw, idx_no_sw)
		CircuitGraph.stamp_conductance(A, g_sw_open_val, idx_com_sw, idx_nc_sw)
	else: 
		CircuitGraph.stamp_conductance(A, g_sw_open_val, idx_com_sw, idx_no_sw)
		CircuitGraph.stamp_conductance(A, g_sw_closed_val, idx_com_sw, idx_nc_sw)
	return

## Hides the information label.
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

## Resets the component to its default de-energized visual state.
func reset_visual_state():
	hide_info()
	is_energized = false
	if is_instance_valid(mesh_instance):
		if mesh_instance.material_override:
			mesh_instance.material_override.albedo_color = Color(0.4, 0.4, 0.5, 1) 
		else:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 0.4, 0.5, 1)
			mesh_instance.material_override = mat

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"VCC": {"node": terminal_vcc, "pos": terminal_vcc.position},
		"GND": {"node": terminal_gnd, "pos": terminal_gnd.position},
		"Signal": {"node": terminal_signal, "pos": terminal_signal.position},
		"COM": {"node": terminal_com, "pos": terminal_com.position},
		"NO": {"node": terminal_no, "pos": terminal_no.position},
		"NC": {"node": terminal_nc, "pos": terminal_nc.position}
	}

## Extracts and stores simulation results for this component.
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

	var term_vcc_res = comp_data.terminals["VCC"]
	var term_gnd_res = comp_data.terminals["GND"]
	var term_sig_res = comp_data.terminals["Signal"]
	
	var node_vcc_id_res = circuit.terminal_connections.get(term_vcc_res.get_instance_id(), -1)
	var node_gnd_id_res = circuit.terminal_connections.get(term_gnd_res.get_instance_id(), -1)
	var node_sig_id_res = circuit.terminal_connections.get(term_sig_res.get_instance_id(), -1)

	var V_vcc_res = circuit.electrical_nodes.get(node_vcc_id_res, {}).get("voltage", NAN)
	var V_gnd_res = circuit.electrical_nodes.get(node_gnd_id_res, {}).get("voltage", NAN)
	var V_sig_res = circuit.electrical_nodes.get(node_sig_id_res, {}).get("voltage", NAN)
	
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
	
	circuit.component_results[comp_id]["signal_voltage"] = actual_signal_voltage
	circuit.component_results[comp_id]["vcc_voltage"] = actual_vcc_voltage
	circuit.component_results[comp_id]["coil_current"] = actual_coil_current
	circuit.component_results[comp_id]["is_energized"] = is_energized_res
	circuit.component_results[comp_id]["signal_threshold"] = comp_data.properties["signal_voltage_threshold"]
