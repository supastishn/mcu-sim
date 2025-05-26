extends Path3D

class_name Wire3D

@onready var csg_polygon: CSGPolygon3D = $CSGPolygon3D

var terminal_start: Area3D = null
var terminal_end: Area3D = null

var wire_shape: PackedVector2Array = [
	Vector2(0.02, 0.02),
	Vector2(-0.02, 0.02),
	Vector2(-0.02, -0.02),
	Vector2(0.02, -0.02)
]

func _ready():
	csg_polygon.polygon = wire_shape
	csg_polygon.mode = CSGPolygon3D.MODE_PATH
	csg_polygon.path_node = self.get_path() 
	csg_polygon.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	csg_polygon.path_interval = 0.1 

func set_endpoints(start_pos: Vector3, end_pos: Vector3, start_terminal: Area3D, end_terminal: Area3D):
	terminal_start = start_terminal
	terminal_end = end_terminal

	var new_curve = Curve3D.new()
	self.curve = new_curve 

	curve.clear_points()
	curve.add_point(start_pos)
	curve.add_point(end_pos)

func _process(delta):
	if is_instance_valid(terminal_start) and is_instance_valid(terminal_end):
		var start_pos = terminal_start.global_position
		var end_pos = terminal_end.global_position
		if curve.get_point_count() == 2: 
			curve.set_point_position(0, start_pos)
			curve.set_point_position(1, end_pos)
