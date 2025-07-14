extends Node

class_name ComponentInteractionUtils

## The maximum distance from a terminal's center to register a click.
const INTERACTION_RADIUS: float = 0.15

## Finds the closest terminal on a component to a given world position.
static func get_closest_terminal(component_node: Node3D, world_hit_position: Vector3) -> Area3D:
	if not is_instance_valid(component_node) or not component_node.has_method("get_terminal_info"):
		return null

	var terminal_info: Dictionary = component_node.get_terminal_info()
	if terminal_info.is_empty():
		return null

	var closest_terminal: Area3D = null
	var min_dist_sq: float = INTERACTION_RADIUS * INTERACTION_RADIUS

	for key in terminal_info:
		var term_data: Dictionary = terminal_info[key]
		var terminal_node: Area3D = term_data.get("node")
		var terminal_local_pos: Vector3 = term_data.get("pos")

		if not is_instance_valid(terminal_node):
			continue

		var terminal_world_pos = component_node.to_global(terminal_local_pos)
		var dist_sq = terminal_world_pos.distance_squared_to(world_hit_position)

		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest_terminal = terminal_node
			
	return closest_terminal
