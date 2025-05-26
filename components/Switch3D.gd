extends Node3D

class_name Switch3D


signal state_changed(switch_node: Node3D, new_state: int)


enum State {
	CONNECTED_NC, 
	CONNECTED_NO  
}


@export var current_state: State = State.CONNECTED_NC : set = set_state

@onready var terminal_com: Area3D = $TerminalCOM
@onready var terminal_nc: Area3D = $TerminalNC
@onready var terminal_no: Area3D = $TerminalNO

@onready var lever_mesh: MeshInstance3D = $LeverPivot/LeverMesh 
@onready var component_body: Area3D = $ComponentBody
@onready var current_label: Label3D = $CurrentLabel

const _LEVER_ANGLE_NC = deg_to_rad(-30.0) 
const _LEVER_ANGLE_NO = deg_to_rad(30.0)  

const MAX_REASONABLE_CURRENT_DISPLAY: float = 1_000_000.0 

func _ready():
	if not component_body:
		printerr("Switch3D requires a child Area3D named 'ComponentBody'.")
	if not current_label:
		printerr("Switch3D requires a child Label3D named 'CurrentLabel'.")
	else:
		current_label.visible = false

	_update_lever_visual()


func toggle_state():
	if current_state == State.CONNECTED_NC:
		set_state(State.CONNECTED_NO)
	else:
		set_state(State.CONNECTED_NC)


func set_state(new_state: State):
	if new_state != current_state:
		current_state = new_state
		_update_lever_visual()
		emit_signal("state_changed", self, int(current_state)) 
		print("Switch state changed to: {state_key}".format({"state_key": State.keys()[current_state]}))

func _update_lever_visual():
	var target_angle = _LEVER_ANGLE_NC if current_state == State.CONNECTED_NC else _LEVER_ANGLE_NO
	if lever_mesh and lever_mesh.get_parent() is Node3D:
		lever_mesh.get_parent().rotation.x = target_angle

func show_current(current_value: float):
	if not current_label: return
	if is_nan(current_value):
		current_label.text = "I: N/A"
	elif abs(current_value) > MAX_REASONABLE_CURRENT_DISPLAY:
		current_label.text = "I: >1MA (Shorted?)" 
	else:
		if abs(current_value) < 1e-3 and abs(current_value) > 1e-12: 
			current_label.text = "I: {val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
		elif abs(current_value) < 1.0: 
			current_label.text = "I: {val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
		else: 
			current_label.text = "I: {val_str} A".format({"val_str": String.num(current_value, 2)})
	current_label.visible = true

func hide_current():
	if not current_label: return
	current_label.visible = false

# -------------------------------------------------------------------------
# MNA‐stamping interface
func stamp(
	A: Array,
	b: Array, # Unused by Switch
	node_map: Dictionary,
	vs_map: Dictionary, # Unused by Switch
	inductor_map: Dictionary, # Unused by Switch
	terminal_connections: Dictionary,
	comp_data: Dictionary, # Used for 'state' (current_state of switch)
	delta_time: float # Unused by Switch
):
	var state_from_comp_data: Switch3D.State = comp_data.state # current_state is stored in comp_data by CircuitGraph
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

	# Helper for inlining _stamp_conductance
	var _inline_stamp_conductance = func(matrix_A, g_val, idx1, idx2):
		if idx1 != -1 and idx2 != -1:
			matrix_A[idx1][idx1] += g_val
			matrix_A[idx2][idx2] += g_val
			matrix_A[idx1][idx2] -= g_val
			matrix_A[idx2][idx1] -= g_val
		elif idx1 != -1:
			matrix_A[idx1][idx1] += g_val
		elif idx2 != -1:
			matrix_A[idx2][idx2] += g_val

	if state_from_comp_data == Switch3D.State.CONNECTED_NC:
		_inline_stamp_conductance.call(A, g_closed, idx_com, idx_nc)
		_inline_stamp_conductance.call(A, g_open, idx_com, idx_no) # NC to COM is closed, NO to COM is open
		_inline_stamp_conductance.call(A, g_open, idx_nc, idx_no) # NC to NO should be open
	elif state_from_comp_data == Switch3D.State.CONNECTED_NO:
		_inline_stamp_conductance.call(A, g_open, idx_com, idx_nc)  # NO to COM is closed, NC to COM is open
		_inline_stamp_conductance.call(A, g_closed, idx_com, idx_no)
		_inline_stamp_conductance.call(A, g_open, idx_nc, idx_no) # NC to NO should be open
