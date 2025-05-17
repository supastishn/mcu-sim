extends Path3D

class_name Wire3D

# CSGPolygon should be a direct child now
@onready var csg_polygon: CSGPolygon3D = $CSGPolygon3D

var terminal_start: Area3D = null
var terminal_end: Area3D = null

# Define the shape of the wire cross-section
var wire_shape: PackedVector2Array = [
	Vector2(0.02, 0.02),
	Vector2(-0.02, 0.02),
	Vector2(-0.02, -0.02),
	Vector2(0.02, -0.02)
]

func _ready():
	csg_polygon.polygon = wire_shape
	csg_polygon.mode = CSGPolygon3D.MODE_PATH
	csg_polygon.path_node = self.get_path() # Assign self (Path3D) as the path node
	csg_polygon.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	csg_polygon.path_interval = 0.1 # Adjust for smoothness vs performance

func set_endpoints(start_pos: Vector3, end_pos: Vector3, start_terminal: Area3D, end_terminal: Area3D):
	terminal_start = start_terminal
	terminal_end = end_terminal

	# Ensure the curve resource is unique to this instance by creating a new one.
	# Duplicate the existing curve resource to prevent modifications from affecting other instances.
	# self.curve = self.curve.duplicate() # Old method - might have issues with sub-resource handling
	var new_curve = Curve3D.new()
	self.curve = new_curve # Assign the new, empty curve resource

	# Set the curve points relative to the Path3D origin (which is likely the scene root)
	# Since Wire3D is added as a child of CircuitEditor3D (at origin), using global positions for local curve points works.
	curve.clear_points()
	curve.add_point(start_pos)
	curve.add_point(end_pos)
	# The CSGPolygon should update automatically as it uses the path_node property

# Called every frame. Delta is the elapsed time since the previous frame.
func _process(delta):
	# Continuously update wire endpoints if terminals are set and valid
	if is_instance_valid(terminal_start) and is_instance_valid(terminal_end):
		var start_pos = terminal_start.global_position
		var end_pos = terminal_end.global_position
		# Check if positions have changed significantly to avoid unnecessary updates
		# (Could use a threshold, but direct setting is often fine)
		if curve.get_point_count() == 2: # Ensure curve has been initialized
			curve.set_point_position(0, start_pos)
			curve.set_point_position(1, end_pos)
			# No need to manually update CSGPolygon, path_node property handles it.
