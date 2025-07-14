extends Node

## Collision layer for terminals.
const TERMINAL_COLLISION_LAYER = 2
## Collision layer for component bodies.
const COMPONENT_BODY_COLLISION_LAYER = 4
## Collision layer for wires.
const WIRE_COLLISION_LAYER = 16 
## Collision layer for the ground plane.
const GROUND_COLLISION_LAYER = 8 

## The maximum distance from a terminal's center to register a click.
const INTERACTION_RADIUS: float = 0.15


## Performs a raycast and determines the interactive object under the cursor.
func get_interactive_object_at(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var space_state = camera.get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos) * 1000 
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction)

	query.collision_mask = TERMINAL_COLLISION_LAYER | COMPONENT_BODY_COLLISION_LAYER | GROUND_COLLISION_LAYER | WIRE_COLLISION_LAYER
	query.collide_with_areas = true 
	query.collide_with_bodies = true 

	var result = space_state.intersect_ray(query)
	
	if not result:
		return {"type": "none", "node": null, "position": Vector3.ZERO}
	
	var collider = result.collider
	var position = result.position
	
	if collider is Area3D:
		if collider.collision_layer == TERMINAL_COLLISION_LAYER:
			return {"type": "terminal", "node": collider, "position": position}
		
		if collider.collision_layer == COMPONENT_BODY_COLLISION_LAYER:
			var component_node = collider.get_parent()
			var closest_terminal = get_closest_terminal(component_node, position)
			if is_instance_valid(closest_terminal):
				# Return the terminal if we clicked close enough to one on the body
				return {"type": "terminal", "node": closest_terminal, "position": closest_terminal.global_position}
			else:
				# Otherwise, return the body itself
				return {"type": "component_body", "node": component_node, "position": position}
	
	if collider is CSGPolygon3D and collider.collision_layer == WIRE_COLLISION_LAYER:
		var wire_node = collider.get_parent()
		return {"type": "wire", "node": wire_node, "position": position}

	if collider.collision_layer == GROUND_COLLISION_LAYER:
		return {"type": "ground", "node": collider, "position": position}
		
	return {"type": "none", "node": null, "position": Vector3.ZERO}


## Finds the closest terminal on a component to a given world position.
func get_closest_terminal(component_node: Node3D, world_hit_position: Vector3) -> Area3D:
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
