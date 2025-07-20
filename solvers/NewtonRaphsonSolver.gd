extends Node

class_name NewtonRaphsonSolver

## Solves a non-linear circuit using Newton-Raphson.
static func solve(circuit_graph: CircuitGraph, system: Dictionary, delta_time: float) -> bool:
	var max_iter = 100
	var v_tolerance = 1e-6
	
	# Initialize and maintain a full solution vector (x_k) for the iteration
	var x_k = []
	x_k.resize(system.N)
	x_k.fill(0.0)
	# Initialize voltages from the graph state
	for node_id in system.node_map:
		var idx = system.node_map[node_id]
		if circuit_graph.electrical_nodes.has(node_id):
			x_k[idx] = circuit_graph.electrical_nodes[node_id].get("voltage", 0.0)
	# Currents for VS/Inductors start at 0

	circuit_graph._last_solver_debug_info.clear()

	for i in range(max_iter):
		# Update graph state from solution vector BEFORE calculating error and stamping
		for node_id in system.node_map:
			var index = system.node_map[node_id]
			if circuit_graph.electrical_nodes.has(node_id):
				circuit_graph.electrical_nodes[node_id].voltage = x_k[index]

		var iter_info = {"iteration": i}
		iter_info["solution_vector_xk"] = x_k.duplicate()

		var voltages_before = {}
		for node_id in circuit_graph.electrical_nodes:
			voltages_before[node_id] = circuit_graph.electrical_nodes[node_id].get("voltage", 0.0)
		iter_info["voltages_before"] = voltages_before
		
		var component_states = {}
		for comp_data in circuit_graph.components:
			var state_key = "operating_region" if comp_data.properties.has("operating_region") else "operating_state" if comp_data.properties.has("operating_state") else "is_energized" if comp_data.properties.has("is_energized") else "is_exploded" if comp_data.has("is_exploded") else "state" if comp_data.has("state") else ""
			if not state_key.is_empty():
				var comp_node = comp_data.component_node
				if is_instance_valid(comp_node):
					component_states[comp_node.name] = comp_data.properties.get(state_key, comp_data.get(state_key, "N/A"))
		iter_info["component_states"] = component_states

		var matrices = circuit_graph._stamp_mna_matrices(system, delta_time)
		var A = matrices.A
		# The error vector for Newton-Raphson is -F(x_k). For our MNA, F(x) = A*x - b.
		# So, -F(x_k) = -(A*x_k - b) = b - A*x_k.
		var Ax = LinearSolver.multiply_matrix_vector(A, x_k)
		var b_error = LinearSolver.subtract_vectors(matrices.b, Ax)
		
		iter_info["jacobian_A"] = A.duplicate(true)
		iter_info["b_vector_from_stamp"] = matrices.b.duplicate()
		iter_info["error_vector_neg_F"] = b_error.duplicate()

		if A.is_empty(): return true

		# Newton-Raphson: Solve J * dx = -F(x_k)  (where J is our matrix A)
		var delta_x = LinearSolver.solve(A, b_error)
		iter_info["update_vector_dx"] = delta_x.duplicate()

		if delta_x.is_empty() and not A.is_empty():
			circuit_graph._last_solver_debug_info.push_back(iter_info)
			var msg = "Linear solver failed during Newton-Raphson iteration. System size: {s}\n".format({"s": A.size()})
			msg += circuit_graph.get_solver_debug_info_as_string()
			assert(false, msg)
			return false

		var norm = sqrt(delta_x.reduce(func(acc, val): return acc + val*val, 0.0))
		if is_nan(norm):
			circuit_graph._last_solver_debug_info.push_back(iter_info)
			var msg = "Solver update vector norm is NaN. delta_x: {dx}\n".format({"dx": delta_x})
			msg += circuit_graph.get_solver_debug_info_as_string()
			assert(false, msg)
			return false

		# --- Damping using voltage limiting ---
		var damping_factor = 1.0
		# Don't damp on the first iteration (i==0) to allow linear circuits to converge in one step.
		# For subsequent iterations, damping helps stabilize non-linear components.
		if i > 0:
			var max_dv = 0.0
			# Find max voltage change, only considering node voltage variables
			for node_id in system.node_map:
				var matrix_idx = system.node_map[node_id]
				if matrix_idx < delta_x.size():
					max_dv = max(max_dv, abs(delta_x[matrix_idx]))

			var VOLTAGE_CHANGE_LIMIT = 0.5 # Limit voltage change to 0.5V per iteration to improve stability
			if max_dv > VOLTAGE_CHANGE_LIMIT:
				damping_factor = VOLTAGE_CHANGE_LIMIT / max_dv
		
		iter_info["damping_factor"] = damping_factor
		
		# Update the full solution vector x_k
		for j in range(system.N):
			x_k[j] += damping_factor * delta_x[j]
		
		# THEN, update the graph's voltage state FROM the new x_k
		for node_id in system.node_map:
			var index = system.node_map[node_id]
			if circuit_graph.electrical_nodes.has(node_id):
				circuit_graph.electrical_nodes[node_id].voltage = x_k[index]

		var voltages_after = {}
		for node_id in circuit_graph.electrical_nodes:
			voltages_after[node_id] = circuit_graph.electrical_nodes[node_id].get("voltage", 0.0)
		iter_info["voltages_after"] = voltages_after
		
		circuit_graph._last_solver_debug_info.push_back(iter_info)

		var state_changed = _update_all_nonlinear_states(circuit_graph, system)
		
		# Converged ONLY if the update is small AND no component states changed.
		if not state_changed and _check_convergence(delta_x, v_tolerance):
			return true

	var msg = "NR failed to converge after {i} iterations.".format({"i": max_iter})
	msg += "\n" + circuit_graph.get_solver_debug_info_as_string()
	assert(false, msg)
	return false


static func _check_convergence(delta_x: Array, v_tol: float) -> bool:
	var norm = delta_x.reduce(func(acc, val): return acc + val*val, 0.0)
	return sqrt(norm) < v_tol


static func _update_all_nonlinear_states(circuit_graph: CircuitGraph, system: Dictionary) -> bool:
	var any_state_changed := false
	
	# Create a voltage vector from the graph's current state for components to read.
	var x_voltages = []
	x_voltages.resize(system.N)
	x_voltages.fill(NAN)
	for node_id in system.node_map:
		var idx = system.node_map[node_id]
		x_voltages[idx] = circuit_graph.electrical_nodes.get(node_id, {}).get("voltage", 0.0)

	for comp_data in circuit_graph.components:
		var node = comp_data.component_node
		if not is_instance_valid(node): continue

		if node.has_method("update_nonlinear_state"):
			# This function is responsible for updating the component's internal state
			# (e.g., operating_region) based on the latest voltages.
			if node.update_nonlinear_state(circuit_graph, comp_data, x_voltages, system.node_map, system.vs_map):
				any_state_changed = true

	return any_state_changed
