extends Node                     # lets us add it to the scene-tree

class_name TestRig

const EditorScene := preload("res://CircuitEditor3D.tscn")

var editor : CircuitEditor3D
var graph  : CircuitGraph

# ------------------------------------------------------------------ #
# life-cycle
func init() -> void:             # call with:  await rig.init()
	editor = EditorScene.instantiate()
	get_tree().current_scene.add_child(editor)
	await get_tree().process_frame
	graph  = editor.circuit_graph


func cleanup() -> void:
	if is_instance_valid(editor):
		editor.queue_free()
	queue_free()

# ------------------------------------------------------------------ #
# helpers
func add(scene: PackedScene, pos := Vector3.ZERO) -> Node3D:
	return editor._add_component(scene, pos)

func cfg(comp: Node3D) -> void:
	graph.component_config_changed(comp)

func wire(a: Area3D, b: Area3D) -> void:
	graph.connect_terminals(a, b)

func ground(t: Area3D) -> void:
	graph.set_ground_node(t)

func solve(dt := 0.01) -> bool:
	return graph.solve_single_time_step(dt)

func results(comp: Node3D) -> Dictionary:
	return graph.component_results.get(comp.get_instance_id(), {})

# -- optional between-sub-test reset (replaces old helper) ----------
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
