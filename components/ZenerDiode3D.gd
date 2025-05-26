extends Node3D

class_name ZenerDiode3D


signal configuration_changed(component_node: Node3D)


@export var forward_voltage: float = 0.7 : set = set_forward_voltage

@export var zener_voltage: float = 5.1 : set = set_zener_voltage

@onready var terminal_anode: Area3D = $TerminalAnode 
@onready var terminal_kathode: Area3D = $TerminalKathode 
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal_anode or not terminal_kathode:
		printerr("ZenerDiode3D requires child Area3D nodes named 'TerminalAnode' and 'TerminalKathode'.")
	if not info_label:
		printerr("ZenerDiode3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	set_forward_voltage(forward_voltage)
	set_zener_voltage(zener_voltage)

func set_forward_voltage(value: float):
	var new_vf = max(0.1, value) 
	if not is_equal_approx(forward_voltage, new_vf):
		forward_voltage = new_vf
		print("ZenerDiode3D {name} forward_voltage set to: {vf_str} V".format({"name": name, "vf_str": String.num(forward_voltage, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif forward_voltage != new_vf: 
		forward_voltage = new_vf

func set_zener_voltage(value: float):
	var new_vz = max(0.1, value) 
	if not is_equal_approx(zener_voltage, new_vz):
		zener_voltage = new_vz
		print("ZenerDiode3D {name} zener_voltage set to: {vz_str} V".format({"name": name, "vz_str": String.num(zener_voltage, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif zener_voltage != new_vz: 
		zener_voltage = new_vz



func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE 

	var current_val = results.get("current", NAN) 
	var voltage_ak_val = results.get("voltage_ak", NAN) 
	var state_val = results.get("state", "N/A")

	var current_str = "I: N/A"
	if not is_nan(current_val):
		if abs(current_val) < 1e-6 and abs(current_val) > 1e-15 : 
			current_str = "I: {val_str} nA".format({"val_str": String.num(current_val * 1e9, 2)})
		elif abs(current_val) < 1e-3 and abs(current_val) > 1e-12: 
			current_str = "I: {val_str} µA".format({"val_str": String.num(current_val * 1e6, 2)})
		elif abs(current_val) < 1.0: 
			current_str = "I: {val_str} mA".format({"val_str": String.num(current_val * 1e3, 2)})
		else: 
			current_str = "I: {val_str} A".format({"val_str": String.num(current_val, 2)})

	var voltage_str = "Vak: N/A" 
	if not is_nan(voltage_ak_val):
		voltage_str = "Vak: {val_str} V".format({"val_str": String.num(voltage_ak_val, 2)})
		
	info_label.text = "State: {s}\n{v_str}\n{c_str}".format({"s": state_val, "v_str": voltage_str, "c_str": current_str})
	info_label.visible = true

func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = ""

func reset_visual_state():
	hide_info()

# -----------------------------------------------------------------
# Simulation-results extraction
func gather_sim_results(
        circuit      : CircuitGraph,
        comp_data    : Dictionary,
        x            : Array,
        node_map     : Dictionary,
        vs_map       : Dictionary,
        inductor_map : Dictionary,
        delta_time   : float) -> void:
    #region LEGACY_RESULT_CODE
    var comp_node = comp_data.component_node
    var comp_id = comp_node.get_instance_id()
    if not comp_id in circuit.component_results: circuit.component_results[comp_id] = {}

    var state_z = comp_data.properties["operating_state"]
    var Vf_z_calc = comp_data.properties["forward_voltage"]
    var Vz_calc = comp_data.properties["zener_voltage"] 
    var R_on_z_model = 0.1 

    var term_a_z_node = comp_data.terminals["A"]
    var term_k_z_node = comp_data.terminals["K"]
    var node_a_id_z_val = circuit.terminal_connections.get(term_a_z_node.get_instance_id(), -1)
    var node_k_id_z_val = circuit.terminal_connections.get(term_k_z_node.get_instance_id(), -1)

    var Va_z_val = circuit.electrical_nodes.get(node_a_id_z_val, {}).get("voltage", NAN)
    var Vk_z_val = circuit.electrical_nodes.get(node_k_id_z_val, {}).get("voltage", NAN)
    
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
    
    circuit.component_results[comp_id]["current"] = current_zener
    circuit.component_results[comp_id]["voltage_ak"] = Vak_z_val 
    circuit.component_results[comp_id]["state"] = state_z
    #endregion

func update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, _x_iter = null, _vs_map_iter = null) -> bool:
	var term_a_z = comp_data.terminals["A"]
	var term_k_z = comp_data.terminals["K"]
	var node_a_id_z = circuit.terminal_connections.get(term_a_z.get_instance_id(), -1)
	var node_k_id_z = circuit.terminal_connections.get(term_k_z.get_instance_id(), -1)
	
	var Va_z = NAN
	if circuit.electrical_nodes.has(node_a_id_z): Va_z = circuit.electrical_nodes[node_a_id_z].voltage
	var Vk_z = NAN
	if circuit.electrical_nodes.has(node_k_id_z): Vk_z = circuit.electrical_nodes[node_k_id_z].voltage
	
	var Vf_z_model = comp_data.properties["forward_voltage"]
	var Vz_model = comp_data.properties["zener_voltage"] 
	var previous_state_z = comp_data.properties["operating_state"]
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
		comp_data.properties["operating_state"] = new_state_z
		return true
	return false

func stamp(
	A: Array,
	b: Array,
	node_map: Dictionary,
	vs_map: Dictionary, 
	inductor_map: Dictionary, 
	terminal_connections: Dictionary,
	comp_data: Dictionary, 
	delta_time: float 
):
	var state_zener_val = comp_data.properties["operating_state"]
	var Vf_zener_model_prop = forward_voltage 
	var Vz_zener_model_prop = zener_voltage   

	var a_id = terminal_anode.get_instance_id() if is_instance_valid(terminal_anode) else -1
	var k_id = terminal_kathode.get_instance_id() if is_instance_valid(terminal_kathode) else -1

	var node_a_lookup = terminal_connections.get(a_id, -1)
	var node_k_lookup = terminal_connections.get(k_id, -1)

	var idx_a = node_map.get(node_a_lookup, -1)
	var idx_k = node_map.get(node_k_lookup, -1)

	var R_on_model_const = 0.1    
	var G_on_model_val = 1.0 / R_on_model_const
	var R_off_model_const = 1.0e9 
	var G_off_model_val = 1.0 / R_off_model_const

	
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

	if state_zener_val == "OFF":
		_inline_stamp_conductance.call(A, G_off_model_val, idx_a, idx_k)
	elif state_zener_val == "FORWARD":
		
		
		_inline_stamp_conductance.call(A, G_on_model_val, idx_a, idx_k)
		var current_offset_fwd_val = G_on_model_val * Vf_zener_model_prop
		
		if idx_a != -1: b[idx_a] += current_offset_fwd_val 
		if idx_k != -1: b[idx_k] -= current_offset_fwd_val 
	elif state_zener_val == "ZENER":
		
		
		
		
		
		_inline_stamp_conductance.call(A, G_on_model_val, idx_a, idx_k) 
		var current_offset_zener_val = G_on_model_val * Vz_zener_model_prop
		
		
		
		
		
		if idx_k != -1: b[idx_k] += current_offset_zener_val 
		if idx_a != -1: b[idx_a] -= current_offset_zener_val 
