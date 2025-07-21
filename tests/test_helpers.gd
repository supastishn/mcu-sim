extends Node                     # lets us add it to the scene-tree

class_name TestRig

## Preloaded scene for the main editor, used to instantiate the test environment.
const EditorScene := preload("res://CircuitEditor3D.tscn")

## Reference to the instantiated CircuitEditor3D script.
var editor : CircuitEditor3D
## Reference to the CircuitGraph script within the editor.
var graph  : CircuitGraph

## Initializes the test rig by instantiating the editor scene and getting references.
func init() -> void:             # call with:  await rig.init()
	editor = EditorScene.instantiate()
	get_tree().current_scene.add_child(editor)
	await get_tree().process_frame
	graph  = editor.circuit_graph


## Cleans up the test rig by freeing the editor instance and itself.
func cleanup() -> void:
	if is_instance_valid(editor):
		editor.queue_free()
	queue_free()

## Helper to add a component to the circuit.
func add(scene: PackedScene, pos := Vector3.ZERO) -> Node3D:
	return editor._add_component(scene, pos)

## Helper to notify the graph that a component's configuration has changed.
func cfg(comp: Node3D) -> void:
	graph.component_config_changed(comp)

## Helper to create a wire between two terminals.
func wire(a: Area3D, b: Area3D) -> void:
	graph.connect_terminals(a, b)

## Helper to set a terminal as the ground node.
func ground(t: Area3D) -> void:
	graph.set_ground_node(t)

## Helper to run a single simulation step.
func solve(dt := 0.01) -> bool:
	return graph.solve_single_time_step(dt)

## Helper to get the simulation results for a specific component.
func results(comp: Node3D) -> Dictionary:
	return graph.component_results.get(comp.get_instance_id(), {})

## Resets node voltages to zero and clears any previous simulation results.
func reset_voltages() -> void:
	graph.component_results.clear()
	graph._is_solved = false
	for node_id in graph.electrical_nodes:
		graph.electrical_nodes[node_id].voltage = 0.0

## Resets the entire graph, removing all components and wires.
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
