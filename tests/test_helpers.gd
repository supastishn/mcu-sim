extends Node                     # lets us add it to the scene-tree

class_name TestRig

## Preloaded scene for the main editor, used to instantiate the test environment.
const EditorScene := preload("res://CircuitEditor3D.tscn")

var editor : CircuitEditor3D
var graph  : CircuitGraph

func init() -> void:             # call with:  await rig.init()
	editor = EditorScene.instantiate()
	get_tree().current_scene.add_child(editor)
	await get_tree().process_frame
	graph  = editor.circuit_graph


func cleanup() -> void:
	if is_instance_valid(editor):
		editor.queue_free()
	queue_free()

func add(scene: PackedScene, pos := Vector3.ZERO) -> Node3D:
	return editor._add_component(scene, pos)

func cfg(comp: Node3D) -> void:
	graph.component_config_changed(comp)

func wire(a: Area3D, b: Area3D) -> void:
	editor._create_wire(a, b)

func ground(t: Area3D) -> void:
	graph.set_ground_node(t)

func solve(dt := 0.01) -> bool:
	return graph.solve_single_time_step(dt)

func results(comp: Node3D) -> Dictionary:
	return graph.component_results.get(comp.get_instance_id(), {})

func reset_voltages() -> void:
	graph.component_results.clear()
	graph._is_solved = false
	for node_id in graph.electrical_nodes:
		graph.electrical_nodes[node_id].voltage = 0.0

func reset_graph() -> void:
	for cd in graph.components.duplicate():
		graph.remove_component(cd.component_node)
	for child in editor.components_node.get_children(): child.queue_free()
	for child in editor.wires_node.get_children():      child.queue_free()

	graph.electrical_nodes.clear()
	graph.terminal_connections.clear()
	graph.component_results.clear()
	graph.ground_node_id = -1
	graph._next_node_id  = 0
	graph._is_solved     = false
	graph._needs_rebuild = true
	await get_tree().process_frame
