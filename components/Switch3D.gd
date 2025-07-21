extends Node3D

class_name Switch3D


## Emitted when the switch's state changes between connected to NC and connected to NO.
signal state_changed(switch_node: Node3D, new_state: int)


## Defines the possible states of the switch: connected to Normally Closed or Normally Open terminal.
enum State {
	CONNECTED_NC, 
	CONNECTED_NO  
}


## The current state of the switch (CONNECTED_NC or CONNECTED_NO).
@export var current_state: State = State.CONNECTED_NC : set = set_state

## Reference to the Common terminal Area3D node.
@onready var terminal_com: Area3D = $TerminalCOM
## Reference to the Normally Closed terminal Area3D node.
@onready var terminal_nc: Area3D = $TerminalNC
## Reference to the Normally Open terminal Area3D node.
@onready var terminal_no: Area3D = $TerminalNO

## Reference to the MeshInstance3D for the switch's lever.
@onready var lever_mesh: MeshInstance3D = $LeverPivot/LeverMesh 
## Reference to the main body Area3D for collision detection.
@onready var component_body: Area3D = $ComponentBody
## Reference to the Label3D for displaying current.
@onready var current_label: Label3D = $CurrentLabel

## The rotation angle for the lever when in the NC state.
const _LEVER_ANGLE_NC = deg_to_rad(-30.0) 
## The rotation angle for the lever when in the NO state.
const _LEVER_ANGLE_NO = deg_to_rad(30.0)  

## A threshold to prevent displaying absurdly large current values.
const MAX_REASONABLE_CURRENT_DISPLAY: float = 1_000_000.0 

## Called when the node enters the scene tree. Initializes the component visuals.
func _ready():
	if not component_body:
		printerr("Switch3D requires a child Area3D named 'ComponentBody'.")
	if not current_label:
		printerr("Switch3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

	_update_lever_visual()


## Toggles the switch between its NC and NO states.
func toggle_state():
	if current_state == State.CONNECTED_NC:
		set_state(State.CONNECTED_NO)
	else:
		set_state(State.CONNECTED_NC)


## Sets the switch to a new state and updates its visual representation.
func set_state(new_state: State):
	if new_state != current_state:
		current_state = new_state
		_update_lever_visual()
		emit_signal("state_changed", self, int(current_state)) 
		print("Switch state changed to: {state_key}".format({"state_key": State.keys()[current_state]}))

## Updates the rotation of the switch lever mesh to reflect the current state.
func _update_lever_visual():
	var target_angle = _LEVER_ANGLE_NC if current_state == State.CONNECTED_NC else _LEVER_ANGLE_NO
	if lever_mesh and lever_mesh.get_parent() is Node3D:
		lever_mesh.get_parent().rotation.x = target_angle

## Displays the calculated current value on the component's 3D label.
func show_current(current_value: float):
	if not current_label: return
	if is_nan(current_value):
		current_label.text = "I: N/A"
	elif abs(current_value) > MAX_REASONABLE_CURRENT_DISPLAY:
		current_label.text = "I: >1MA (Shorted?)" 
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
		"COM": {"node": terminal_com, "pos": terminal_com.position},
		"NC": {"node": terminal_nc, "pos": terminal_nc.position},
		"NO": {"node": terminal_no, "pos": terminal_no.position}
	}

## Stamps the switch's conductances into the MNA matrix based on its current state.
func stamp(
	A: Array,
	_b: Array, # Unused by Switch
	node_map: Dictionary,
	_vs_map: Dictionary, # Unused by Switch
	_inductor_map: Dictionary, # Unused by Switch
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for 'state' (current_state of switch)
	_delta_time: float # Unused by Switch
):
	var state_from_comp_data: Switch3D.State = comp_data.state
	var R_closed = CircuitGraph.R_SWITCH_CLOSED
	var g_closed = 1.0 / R_closed
	var R_open = CircuitGraph.R_SWITCH_OPEN
	var g_open = 1.0 / R_open

	var com_id = terminal_com.get_instance_id()
	var nc_id = terminal_nc.get_instance_id()
	var no_id = terminal_no.get_instance_id()

	var node_com_id_lookup = terminal_connections.get(com_id, -1)
	var node_nc_id_lookup = terminal_connections.get(nc_id, -1)
	var node_no_id_lookup = terminal_connections.get(no_id, -1)

	var idx_com = node_map.get(node_com_id_lookup, -1)
	var idx_nc = node_map.get(node_nc_id_lookup, -1)
	var idx_no = node_map.get(node_no_id_lookup, -1)

	if state_from_comp_data == Switch3D.State.CONNECTED_NC:
		print_debug("Switch '{n}' stamp: State=NC. Stamping COM-NC ({ic},{inc}) closed, COM-NO ({ic},{ino}) open.".format({"n":name, "ic":idx_com, "inc":idx_nc, "ino":idx_no}))
		CircuitGraph.stamp_conductance(A, g_closed, idx_com, idx_nc)
		CircuitGraph.stamp_conductance(A, g_open, idx_com, idx_no)
	elif state_from_comp_data == Switch3D.State.CONNECTED_NO:
		print_debug("Switch '{n}' stamp: State=NO. Stamping COM-NC ({ic},{inc}) open, COM-NO ({ic},{ino}) closed.".format({"n":name, "ic":idx_com, "inc":idx_nc, "ino":idx_no}))
		CircuitGraph.stamp_conductance(A, g_open, idx_com, idx_nc)
		CircuitGraph.stamp_conductance(A, g_closed, idx_com, idx_no)

## Extracts and stores the current flowing through the active path of the switch.
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

	var state: Switch3D.State = comp_data.state 
	var R_closed = CircuitGraph.R_SWITCH_CLOSED
	var term_com = comp_data.terminals["COM"]
	var node_com_id = circuit.terminal_connections.get(term_com.get_instance_id(), -1)
	var V_com = circuit.electrical_nodes.get(node_com_id, {}).get("voltage", NAN)
	var active_term_name = "NC" if state == Switch3D.State.CONNECTED_NC else "NO"
	var active_term = comp_data.terminals[active_term_name]
	var active_node_id = circuit.terminal_connections.get(active_term.get_instance_id(), -1)
	var V_active = circuit.electrical_nodes.get(active_node_id, {}).get("voltage", NAN)
	var current = NAN
	if not is_nan(V_com) and not is_nan(V_active):
		current = (V_com - V_active) / R_closed
	circuit.component_results[comp_id]["current"] = current
