extends Node3D

class_name Resistor3D


## The resistance value in Ohms.
@export var resistance: float = 1000.0

## Reference to the first terminal Area3D node.
@onready var terminal1: Area3D = $Terminal1
## Reference to the second terminal Area3D node.
@onready var terminal2: Area3D = $Terminal2
## Reference to the Label3D for displaying current.
@onready var current_label: Label3D = $CurrentLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not current_label:
		printerr("Resistor3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

## Displays the calculated current value on the component's 3D label.
func show_current(current_value: float):
	if not current_label: return
	if is_nan(current_value):
		current_label.text = "I: N/A"
	else:
		current_label.text = "I: " + StringUtils.format_current(current_value)
	current_label.visible = true

## Hides the current display label.
func hide_current():
	if not current_label: return
	current_label.visible = false

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"T1": {"node": terminal1, "pos": terminal1.position},
		"T2": {"node": terminal2, "pos": terminal2.position}
	}

## Stamps the resistor's conductance value into the MNA matrix.
func stamp(
	A: Array,
	_b: Array,
	node_map: Dictionary,
	_vs_map: Dictionary,
	_opamp_map: Dictionary,
	_inductor_map: Dictionary,
	terminal_connections: Dictionary,
	_comp_data: Dictionary,
	_delta_time: float
):
	
	var R = resistance 
	if R == 0.0: R = 1e-9
	var g = 1.0 / R
	
	var t1_instance_id = terminal1.get_instance_id()
	var t2_instance_id = terminal2.get_instance_id()
	
	var n1 = terminal_connections.get(t1_instance_id, -1)
	var n2 = terminal_connections.get(t2_instance_id, -1)
	
	var i1 = node_map.get(n1, -1)
	var i2 = node_map.get(n2, -1)
	
	
	CircuitGraph.stamp_conductance(A, g, i1, i2)

func get_kcl_contributions(graph: CircuitGraph, _all_node_voltages: Dictionary, F_v: Array, system: Dictionary, _delta_time: float):
	var R = resistance
	if R == 0.0: R = 1e-9
	var g = 1.0 / R
	
	var t1_instance_id = terminal1.get_instance_id()
	var t2_instance_id = terminal2.get_instance_id()
	
	var n1_id = graph.terminal_connections.get(t1_instance_id, -1)
	var n2_id = graph.terminal_connections.get(t2_instance_id, -1)
	
	var v1 = graph.electrical_nodes.get(n1_id, {}).get("voltage", 0.0)
	var v2 = graph.electrical_nodes.get(n2_id, {}).get("voltage", 0.0)

	var i1 = system.node_map.get(n1_id, -1)
	var i2 = system.node_map.get(n2_id, -1)
	
	var current = g * (v1 - v2)
	if i1 != -1: F_v[i1] += current
	if i2 != -1: F_v[i2] -= current

## Extracts and stores the current flowing through the resistor.
func gather_sim_results(
		circuit      : CircuitGraph,
		_comp_data    : Dictionary,
		_x           : Array,
		_node_map    : Dictionary,
		_vs_map      : Dictionary,
		_inductor_map: Dictionary,
		_delta_time  : float) -> void:
	var comp_id = self.get_instance_id()

	var n1_id = circuit.terminal_connections.get(terminal1.get_instance_id(), -1)
	var n2_id = circuit.terminal_connections.get(terminal2.get_instance_id(), -1)
	var v1    = circuit.electrical_nodes.get(n1_id, {}).get("voltage", NAN)
	var v2    = circuit.electrical_nodes.get(n2_id, {}).get("voltage", NAN)

	var i = NAN
	if not is_nan(v1) and not is_nan(v2):
		var R = max(resistance, 1e-12)   # avoid divide-by-zero
		i = (v1 - v2) / R

	circuit.component_results[comp_id]["current"] = i
