extends Node3D

class_name Breadboard3D

@onready var terminals_container = $Terminals

const TerminalFeedbackScript = preload("res://components/TerminalFeedback.gd")
const col_labels = ["a", "b", "c", "d", "e"]

## Called when the node enters the scene tree.
func _ready():
	var circuit_graph: CircuitGraph = get_tree().current_scene.get_node_or_null("CircuitGraph")
	if not is_instance_valid(circuit_graph):
		printerr("Breadboard3D: Could not find CircuitGraph node.")
		return
		
	var all_terminals = generate_terminals()
	circuit_graph.register_dynamic_terminals(self, all_terminals)
	call_deferred("connect_internal_strips")

## Creates all terminal Area3D nodes for the breadboard.
func generate_terminals() -> Array[Node]:
	var terminals_array: Array[Node] = []
	# Mini-breadboard layout
	var row_count = 10
	var x_spacing = 0.1
	var z_spacing = 0.1
	var strip_x_offset = -0.3
	var x_start = -((col_labels.size() / 2.0 - 0.5) * x_spacing)
	var z_start = -((row_count / 2.0 - 0.5) * z_spacing)

	# Terminal strips
	for row in range(1, row_count + 1):
		for j in range(col_labels.size()):
			var x_pos = strip_x_offset + x_start + j * x_spacing
			var z_pos = z_start + (row - 1) * z_spacing
			var term_name = "s1_{row}{col}".format({"row": row, "col": col_labels[j]})
			var terminal = _create_terminal(Vector3(x_pos, 0.1, z_pos), term_name)
			terminals_array.push_back(terminal)

	# Power rails
	var rail_x_pos = 0.3
	for i in range(row_count):
		var z_pos = z_start + i * z_spacing
		var p_terminal = _create_terminal(Vector3(rail_x_pos, 0.1, z_pos), "P_r{i}".format({"i": i}))
		var n_terminal = _create_terminal(Vector3(rail_x_pos + 0.1, 0.1, z_pos), "N_r{i}".format({"i": i}))
		terminals_array.push_back(p_terminal)
		terminals_array.push_back(n_terminal)
		
	return terminals_array

## Helper function to create a single terminal node.
func _create_terminal(pos: Vector3, p_name: String) -> Area3D:
	var terminal = Area3D.new()
	terminal.name = p_name
	terminal.transform.origin = pos
	terminal.collision_layer = 2 # Terminal layer
	terminal.script = TerminalFeedbackScript

	var viz = MeshInstance3D.new()
	viz.name = "Visualization"
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.02
	sphere_mesh.height = 0.04
	viz.mesh = sphere_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	viz.material_override = mat
	terminal.add_child(viz)

	var label = Label3D.new()
	label.name = "Label3D"
	label.text = ""
	label.visible = false
	terminal.add_child(label)

	terminals_container.add_child(terminal)
	return terminal

## Connects the internal strips of the breadboard after terminals are created.
func connect_internal_strips():
	var circuit_graph: CircuitGraph = get_tree().current_scene.get_node_or_null("CircuitGraph")
	if not is_instance_valid(circuit_graph):
		printerr("Breadboard3D: cannot connect strips, CircuitGraph is invalid.")
		return
	
	# Connect terminal strips
	for row in range(1, 11):
		for i in range(col_labels.size() - 1): # a-b, b-c, c-d, d-e
			var col1 = col_labels[i]
			var col2 = col_labels[i + 1]
			var term_a_name = "s1_{row}{col}".format({"row": row, "col": col1})
			var term_b_name = "s1_{row}{col}".format({"row": row, "col": col2})
			var term_a = terminals_container.get_node_or_null(term_a_name)
			var term_b = terminals_container.get_node_or_null(term_b_name)
			if is_instance_valid(term_a) and is_instance_valid(term_b):
				circuit_graph.connect_terminals(term_a, term_b)

	# Connect power rails
	for i in range(9):
		var term_a_p = terminals_container.get_node_or_null("P_r{i}".format({"i": i}))
		var term_b_p = terminals_container.get_node_or_null("P_r{i_1}".format({"i_1": i+1}))
		if is_instance_valid(term_a_p) and is_instance_valid(term_b_p):
			circuit_graph.connect_terminals(term_a_p, term_b_p)
		
		var term_a_n = terminals_container.get_node_or_null("N_r{i}".format({"i": i}))
		var term_b_n = terminals_container.get_node_or_null("N_r{i_1}".format({"i_1": i+1}))
		if is_instance_valid(term_a_n) and is_instance_valid(term_b_n):
			circuit_graph.connect_terminals(term_a_n, term_b_n)
