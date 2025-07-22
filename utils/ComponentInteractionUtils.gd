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
## The maximum pixel distance from a projected terminal center to register a click.
const PROJECTION_CLICK_RADIUS_PX = 20.0


## Performs a raycast and determines the interactive object under the cursor.
func get_interactive_object_at(camera: Camera3D, screen_pos: Vector2, components_parent: Node3D) -> Dictionary:
	# --- 1. Terminal check via screen-space projection ---
	var closest_terminal: Area3D = null
	var min_dist_sq := PROJECTION_CLICK_RADIUS_PX * PROJECTION_CLICK_RADIUS_PX

	for component in components_parent.get_children():
		if component is Node3D and component.has_method("get_terminal_info"):
			var terminal_info: Dictionary = component.get_terminal_info()
			for key in terminal_info:
				var term_data: Dictionary = terminal_info[key]
				var terminal_node: Area3D = term_data.get("node")
				if not is_instance_valid(terminal_node): continue

				var cam_transform = camera.global_transform
				var to_terminal = terminal_node.global_position - cam_transform.origin
				if to_terminal.dot(-cam_transform.basis.z) > 0: # Check if in front of camera
					var terminal_screen_pos = camera.project_position(terminal_node.global_position)
					var dist_sq = terminal_screen_pos.distance_squared_to(screen_pos)
					if dist_sq < min_dist_sq:
						min_dist_sq = dist_sq
						closest_terminal = terminal_node

	if is_instance_valid(closest_terminal):
		return {"type": "terminal", "node": closest_terminal, "position": closest_terminal.global_position}

	# --- 2. Fallback to raycast for bodies, wires, and ground ---
	var space_state = camera.get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos) * 1000
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction)
	
	query.collision_mask = COMPONENT_BODY_COLLISION_LAYER | GROUND_COLLISION_LAYER | WIRE_COLLISION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result = space_state.intersect_ray(query)
	
	if not result:
		return {"type": "none", "node": null, "position": Vector3.ZERO}
	
	var collider = result.collider
	var position = result.position
	
	if collider is Area3D:
		if collider.collision_layer == COMPONENT_BODY_COLLISION_LAYER:
			var component_node = collider.get_parent()
			return {"type": "component_body", "node": component_node, "position": position}
	
	if collider is CSGPolygon3D and collider.collision_layer == WIRE_COLLISION_LAYER:
		var wire_node = collider.get_parent()
		return {"type": "wire", "node": wire_node, "position": position}

	if collider.collision_layer == GROUND_COLLISION_LAYER:
		return {"type": "ground", "node": collider, "position": position}
		
	return {"type": "none", "node": null, "position": Vector3.ZERO}


