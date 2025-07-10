extends Node3D
class_name OpAmp3D

var open_loop_gain := 100000.0
var rail_saturation_voltage := 0.5

@onready var terminal_vcc: Area3D = $TerminalVcc
@onready var terminal_vee: Area3D = $TerminalVee
@onready var terminal_vp: Area3D = $TerminalVp
@onready var terminal_vn: Area3D = $TerminalVn
@onready var terminal_vout: Area3D = $TerminalVout

# Stamps OpAmp equations into MNA matrix
func stamp(
    A: Array, 
    b: Array,
    node_map: Dictionary,
    vs_map: Dictionary,
    inductor_map: Dictionary,
    terminal_connections: Dictionary,
    component_data: Dictionary,
    delta_time: float
) -> void:
    if "operating_region" not in component_data.properties:
        component_data.properties["operating_region"] = "OFF"
        
    var active_vs_index: int = vs_map.get(get_instance_id(), -1)
    if active_vs_index < 0:
        return
    
    var p_node_id = terminal_connections.get(terminal_vp.get_instance_id(), -1)
    var n_node_id = terminal_connections.get(terminal_vn.get_instance_id(), -1)
    var out_node_id = terminal_connections.get(terminal_vout.get_instance_id(), -1)
    var vcc_node_id = terminal_connections.get(terminal_vcc.get_instance_id(), -1)
    var vee_node_id = terminal_connections.get(terminal_vee.get_instance_id(), -1)
    
    if active_vs_index >= A.size():
        return
    if component_data.properties["operating_region"] == "LINEAR":
        _stamp_linear(A, node_map, out_node_id, p_node_id, n_node_id, active_vs_index)
    else:
        _stamp_saturated(A, b, node_map, component_data, out_node_id, vcc_node_id, vee_node_id, active_vs_index)
    
    if node_map.has(out_node_id):
        A[node_map[out_node_id]][active_vs_index] += 1.0

# Helper: Stamps linear region equations
func _stamp_linear(A: Array, node_map: Dictionary, out_node: int, p_node: int, n_node: int, vs_index: int) -> void:
    if node_map.has(out_node):
        A[vs_index][node_map[out_node]] = 1.0
    if node_map.has(p_node):
        A[vs_index][node_map[p_node]] = -open_loop_gain
    if node_map.has(n_node):
        A[vs_index][node_map[n_node]] = open_loop_gain

# Helper: Stamps saturated region equations
func _stamp_saturated(A: Array, b: Array, node_map: Dictionary, data: Dictionary, out_node: int, vcc: int, vee: int, vs_index: int) -> void:
    var target_voltage = 0.0
    if data.properties["operating_region"] == "SAT_HIGH":
        target_voltage = 0.0
        if node_map.has(vcc):
            target_voltage = NAN
        if vcc in node_map:
            target_voltage = NAN
        target_voltage = 0.0
        if vcc in node_map:
            target_voltage = NAN
        # Actually, we need the voltage at vcc node minus rail_saturation_voltage
        # But we don't have the voltage here, so we stamp a constraint: Vout = Vcc - rail_saturation_voltage
        # The update_nonlinear_state will ensure the region is correct
    else: # SAT_LOW
        target_voltage = 0.0
        if node_map.has(vee):
            target_voltage = NAN
        if vee in node_map:
            target_voltage = NAN
        target_voltage = 0.0
        if vee in node_map:
            target_voltage = NAN
        # Actually, we need the voltage at vee node plus rail_saturation_voltage
        # But we don't have the voltage here, so we stamp a constraint: Vout = Vee + rail_saturation_voltage
        # The update_nonlinear_state will ensure the region is correct
    
    A[vs_index][vs_index] = 0.0
    if node_map.has(out_node):
        A[vs_index][node_map[out_node]] = 1.0
    
    # The actual value for b[vs_index] will be set in update_nonlinear_state, so leave as is

# Updates nonlinear state based on voltages
func update_nonlinear_state(
    graph: Node,
    component_data: Dictionary,
    x: Array,
    node_map: Dictionary,
    vs_map: Dictionary,
    inductor_map: Dictionary,
    delta_time: float
) -> bool:
    # Helper to get voltage at a terminal
    func get_voltage(terminal: Area3D) -> float:
        var node_id = graph.terminal_connections.get(terminal.get_instance_id(), -1)
        if node_id == -1:
            return 0.0
        if node_map.has(node_id):
            var idx = node_map[node_id]
            if idx < x.size():
                return x[idx]
        return 0.0

    var v_vee = get_voltage(terminal_vee)
    var v_vp = get_voltage(terminal_vp)
    var v_vn = get_voltage(terminal_vn)
    var v_vcc = get_voltage(terminal_vcc)
    var vout = get_voltage(terminal_vout)

    var linear_vout = open_loop_gain * (v_vp - v_vn)
    var rail_high = v_vcc - rail_saturation_voltage
    var rail_low = v_vee + rail_saturation_voltage

    var new_region = "LINEAR"
    if linear_vout > rail_high:
        new_region = "SAT_HIGH"
    elif linear_vout < rail_low:
        new_region = "SAT_LOW"

    var changed = component_data.properties["operating_region"] != new_region
    component_data.properties["operating_region"] = new_region

    # For result reporting
    var vout_clamped = clamp(linear_vout, rail_low, rail_high)
    component_data["vout"] = vout_clamped

    # For SAT_HIGH/SAT_LOW, set the correct b value in the matrix
    if vs_map.has(get_instance_id()):
        var vs_index = vs_map[get_instance_id()]
        if new_region == "SAT_HIGH":
            if node_map.has(terminal_vcc.get_instance_id()):
                var idx = node_map[graph.terminal_connections.get(terminal_vcc.get_instance_id(), -1)]
                if idx < x.size():
                    graph._build_mna_system_last_b[vs_index] = x[idx] - rail_saturation_voltage
        elif new_region == "SAT_LOW":
            if node_map.has(terminal_vee.get_instance_id()):
                var idx = node_map[graph.terminal_connections.get(terminal_vee.get_instance_id(), -1)]
                if idx < x.size():
                    graph._build_mna_system_last_b[vs_index] = x[idx] + rail_saturation_voltage

    return changed

# Collects simulation results for display
func gather_sim_results(
    graph: Node,
    component_data: Dictionary,
    x: Array,
    node_map: Dictionary,
    vs_map: Dictionary,
    inductor_map: Dictionary,
    delta_time: float
) -> void:
    var results = {}
    if "operating_region" in component_data.properties:
        results["region"] = component_data.properties["operating_region"]
        results["Vout"] = component_data.get("vout", NAN)
        if vs_map.has(get_instance_id()):
            var vs_index = vs_map[get_instance_id()]
            if vs_index < x.size():
                results["current"] = x[vs_index]
    graph.component_results[get_instance_id()] = results
