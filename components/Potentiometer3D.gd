extends Node3D

class_name Potentiometer3D


## Emitted when the wiper position changes, usually via the UI slider.
signal wiper_position_changed(pot_node: Node3D, new_position: float)


## The total resistance between terminal 1 and terminal 2, in Ohms.
@export var total_resistance: float = 10000.0


## The wiper's position, from 0.0 (closest to terminal 1) to 1.0 (closest to terminal 2).
@export var wiper_position: float = 0.5 : set = set_wiper_position

## Reference to the first main terminal Area3D node.
@onready var terminal1: Area3D = $Terminal1 
## Reference to the second main terminal Area3D node.
@onready var terminal2: Area3D = $Terminal2 
## Reference to the wiper terminal Area3D node.
@onready var terminal_wiper: Area3D = $TerminalWiper 

## Reference to the main body Area3D for collision detection.
@onready var component_body: Area3D = $ComponentBody
## Reference to the Label3D for displaying current.
@onready var current_label: Label3D = $CurrentLabel

## Called when the node enters the scene tree. Initializes the component.
func _ready():
	if not terminal1 or not terminal2 or not terminal_wiper:
		printerr("Potentiometer3D requires child Area3D nodes named 'Terminal1', 'Terminal2', and 'TerminalWiper'.")
	if not component_body:
		printerr("Potentiometer3D requires a child Area3D named 'ComponentBody'.")
	if not current_label:
		printerr("Potentiometer3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false
	set_wiper_position(wiper_position)


## Sets the wiper position, clamps it between 0.0 and 1.0, and emits a signal.
func set_wiper_position(new_pos: float):
	var clamped_pos = clampf(new_pos, 0.0, 1.0)
	if is_equal_approx(wiper_position, clamped_pos):
		wiper_position = clamped_pos
		return

	wiper_position = clamped_pos
	print("Potentiometer {pot_name} wiper position set to: {pos_str}".format({"pot_name": name, "pos_str": String.num(wiper_position, 2)}))
	if is_inside_tree():
		emit_signal("wiper_position_changed", self, wiper_position)






## Displays the calculated currents flowing through the two resistive segments of the potentiometer.
func show_current(current_t1_w: float, current_w_t2: float):
	if not current_label: return

	var str_t1_w = StringUtils.format_current(current_t1_w).replace(" ", "")
	var str_w_t2 = StringUtils.format_current(current_w_t2).replace(" ", "")

	current_label.text = "I(T1-W): {val1}\nI(W-T2): {val2}".format({"val1": str_t1_w, "val2": str_w_t2})
	current_label.visible = true

## Hides the current display label.
func hide_current():
	if not current_label: return
	current_label.visible = false

## Returns a dictionary of terminal nodes and their local positions.
func get_terminal_info() -> Dictionary:
	return {
		"T1": {"node": terminal1, "pos": terminal1.position},
		"T2": {"node": terminal2, "pos": terminal2.position},
		"W": {"node": terminal_wiper, "pos": terminal_wiper.position}
	}

## Stamps the two resistances of the potentiometer model into the MNA matrix.
func stamp(
	A: Array,
	_b: Array, # Unused by Potentiometer
	node_map: Dictionary,
	_vs_map: Dictionary, # Unused by Potentiometer
	_inductor_map: Dictionary, # Unused by Potentiometer
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for total_resistance and wiper_position from comp_data.properties
	_delta_time: float # Unused by Potentiometer
):
	var total_R_val = comp_data.properties["total_resistance"]
	var wiper_pos_val = comp_data.properties["wiper_position"]

	var R1 = total_R_val * wiper_pos_val
	if R1 < 1e-9: R1 = 1e-9
	var g1 = 1.0 / R1
	
	var R2 = total_R_val * (1.0 - wiper_pos_val)
	if R2 < 1e-9: R2 = 1e-9
	var g2 = 1.0 / R2

	var t1_id = terminal1.get_instance_id() if is_instance_valid(terminal1) else -1
	var t2_id = terminal2.get_instance_id() if is_instance_valid(terminal2) else -1
	var tw_id = terminal_wiper.get_instance_id() if is_instance_valid(terminal_wiper) else -1

	var node1_lookup_id = terminal_connections.get(t1_id, -1)
	var node2_lookup_id = terminal_connections.get(t2_id, -1)
	var nodeW_lookup_id = terminal_connections.get(tw_id, -1)

	var idx1 = node_map.get(node1_lookup_id, -1)
	var idx2 = node_map.get(node2_lookup_id, -1)
	var idxW = node_map.get(nodeW_lookup_id, -1)

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

func get_kcl_contributions(graph: CircuitGraph, all_node_voltages: Dictionary, F_v: Array, system: Dictionary, _delta_time: float):
	var t1_node_id = graph.terminal_connections.get(terminal1.get_instance_id(), -1)
	var t2_node_id = graph.terminal_connections.get(terminal2.get_instance_id(), -1)
	var tw_node_id = graph.terminal_connections.get(terminal_wiper.get_instance_id(), -1)

	var v1 = all_node_voltages.get(t1_node_id, 0.0)
	var v2 = all_node_voltages.get(t2_node_id, 0.0)
	var vw = all_node_voltages.get(tw_node_id, 0.0)

	var R1 = total_resistance * wiper_position
	if R1 < 1e-9: R1 = 1e-9
	var R2 = total_resistance * (1.0 - wiper_position)
	if R2 < 1e-9: R2 = 1e-9

	var I1 = (v1 - vw) / R1
	var I2 = (vw - v2) / R2

	var idx1 = system.node_map.get(t1_node_id, -1)
	var idx2 = system.node_map.get(t2_node_id, -1)
	var idxw = system.node_map.get(tw_node_id, -1)

	if idx1 != -1: F_v[idx1] += I1
	if idxw != -1: F_v[idxw] -= I1
	if idxw != -1: F_v[idxw] += I2
	if idx2 != -1: F_v[idx2] -= I2

## Extracts and stores the currents flowing through the potentiometer's resistive segments.
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

	var total_R = comp_data.properties["total_resistance"]
	var wiper_pos = comp_data.properties["wiper_position"]

	var R1_val = total_R * wiper_pos
	if R1_val < 1e-12: R1_val = 1e-12 
	
	var R2_val = total_R * (1.0 - wiper_pos)
	if R2_val < 1e-12: R2_val = 1e-12

	var term1_node = comp_data.terminals["T1"]
	var term2_node = comp_data.terminals["T2"]
	var termW_node = comp_data.terminals["W"]

	var node1_id = circuit.terminal_connections.get(term1_node.get_instance_id(), -1)
	var node2_id = circuit.terminal_connections.get(term2_node.get_instance_id(), -1)
	var nodeW_id = circuit.terminal_connections.get(termW_node.get_instance_id(), -1)

	var V1 = circuit.electrical_nodes.get(node1_id, {}).get("voltage", NAN)
	var V2 = circuit.electrical_nodes.get(node2_id, {}).get("voltage", NAN)
	var VW = circuit.electrical_nodes.get(nodeW_id, {}).get("voltage", NAN)

	var current1W = NAN
	if not is_nan(V1) and not is_nan(VW):
		current1W = (V1 - VW) / R1_val if R1_val > 1e-12 else (V1 - VW) * 1e12 

	var currentW2 = NAN
	if not is_nan(VW) and not is_nan(V2):
		currentW2 = (VW - V2) / R2_val if R2_val > 1e-12 else (VW - V2) * 1e12

	circuit.component_results[comp_id]["current_T1_W"] = current1W
	circuit.component_results[comp_id]["current_W_T2"] = currentW2
	circuit.component_results[comp_id]["current_Wiper_Net"] = current1W - currentW2 if not is_nan(current1W) and not is_nan(currentW2) else NAN
