extends Node3D
class_name LinearRegulator3D

signal configuration_changed(component_node: Node3D)

@export var regulated_voltage: float = 5.0 : set = set_regulated_voltage
@export var dropout_voltage: float = 2.0 : set = set_dropout_voltage
@export var max_current: float = 1.0 : set = set_max_current

@onready var terminal_vin: Area3D = $TerminalVin
@onready var terminal_vout: Area3D = $TerminalVout
@onready var terminal_gnd: Area3D = $TerminalGnd
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal_vin or not terminal_vout or not terminal_gnd:
		printerr("Missing terminal(s) for LinearRegulator3D")
	reset_visual_state()
	set_regulated_voltage(regulated_voltage)
	set_dropout_voltage(dropout_voltage)
	set_max_current(max_current)

# Setters with validation
func set_regulated_voltage(value: float):
	var new_val = max(0.5, value)
	if not is_equal_approx(regulated_voltage, new_val):
		regulated_voltage = new_val
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif regulated_voltage != new_val:
		regulated_voltage = new_val

func set_dropout_voltage(value: float):
	var new_val = max(0.1, value)
	if not is_equal_approx(dropout_voltage, new_val):
		dropout_voltage = new_val
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif dropout_voltage != new_val:
		dropout_voltage = new_val

func set_max_current(value: float):
	var new_val = max(0.01, value)
	if not is_equal_approx(max_current, new_val):
		max_current = new_val
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif max_current != new_val:
		max_current = new_val

# UI display methods
func show_info(reg_voltage: float, status: String):
	if info_label:
		info_label.text = "Regulated: %.2f V\n%s" % [reg_voltage, status]
		info_label.visible = true

func hide_info():
	if info_label:
		info_label.visible = false

func reset_visual_state():
	hide_info()

# MNA Functions
func update_nonlinear_state(circuit, comp_data, x_iter, vs_map_iter)->bool:
	var term_vin_id = terminal_vin.get_instance_id()
	var term_vout_id = terminal_vout.get_instance_id()
	var vin_node = circuit.terminal_connections.get(term_vin_id, -1)
	var vout_node = circuit.terminal_connections.get(term_vout_id, -1)
	
	var v_vin = circuit.electrical_nodes.get(vin_node, {}).get("voltage", NAN)
	var v_vout = circuit.electrical_nodes.get(vout_node, {}).get("voltage", NAN)
	
	var new_status: String
	if is_nan(v_vin) or is_nan(v_vout):
		new_status = "DISCONNECTED"
	else:
		var v_diff = v_vin - v_vout
		if v_diff < dropout_voltage:
			new_status = "DROPOUT"
		else:
			new_status = "REGULATED"
	
	if comp_data.properties.get("status") != new_status:
		comp_data.properties["status"] = new_status
		return true
	return false

func stamp(
	A, b, node_map, vs_map, inductor_map, terminal_connections, comp_data, delta_time
):
	# Use a large conductance to enforce Vout = regulated_voltage or Vout = Vin - dropout_voltage
	# This preserves KCL and circuit topology, similar to a SPICE voltage source with large G
	var idx_vin = node_map.get(terminal_connections.get(terminal_vin.get_instance_id(), -1), -1)
	var idx_vout = node_map.get(terminal_connections.get(terminal_vout.get_instance_id(), -1), -1)
	var idx_gnd = node_map.get(terminal_connections.get(terminal_gnd.get_instance_id(), -1), -1)
	
	if idx_vout == -1:
		return
	
	var status = comp_data.properties.get("status", "DISCONNECTED")
	var Gbig = 1e9  # Large conductance for voltage stamping
	
	if status == "REGULATED":
		# Enforce Vout - GND = regulated_voltage using large conductance
		if idx_gnd != -1:
			A[idx_vout][idx_vout] += Gbig
			A[idx_vout][idx_gnd] -= Gbig
			b[idx_vout] += Gbig * regulated_voltage
		else:
			A[idx_vout][idx_vout] += Gbig
			b[idx_vout] += Gbig * regulated_voltage
	elif status == "DROPOUT":
		# Enforce Vout = Vin - dropout_voltage using large conductance
		if idx_vin != -1:
			A[idx_vout][idx_vout] += Gbig
			A[idx_vout][idx_vin] -= Gbig
			b[idx_vout] -= Gbig * dropout_voltage
		else:
			A[idx_vout][idx_vout] += 1e-9
	elif status == "DISCONNECTED":
		# No constraint, but add a tiny conductance to ground to avoid singular matrix
		if idx_gnd != -1:
			A[idx_vout][idx_vout] += 1e-9
			A[idx_vout][idx_gnd] -= 1e-9
		else:
			A[idx_vout][idx_vout] += 1e-9

func gather_sim_results(circuit, comp_data, x, node_map, vs_map, inductor_map, delta_time):
	var vout_id = terminal_vout.get_instance_id()
	var vout_node_id = circuit.terminal_connections.get(vout_id, -1)
	var v_vout = circuit.electrical_nodes.get(vout_node_id, {}).get("voltage", NAN)
	
	if not is_nan(v_vout):
		show_info(v_vout, comp_data.properties.get("status", "N/A"))
	else:
		hide_info()
	
	# Store results in circuit graph for test access
	var comp_id = self.get_instance_id()
	circuit.component_results[comp_id] = {
		"status": comp_data.properties.get("status", "UNKNOWN"),
		"voltage": v_vout
	}
