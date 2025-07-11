extends Path3D

class_name Wire3D

## The CSGPolygon3D node used to render the wire.
@onready var csg_polygon: CSGPolygon3D = $CSGPolygon3D

## The starting terminal Area3D of the wire connection.
var terminal_start: Area3D = null
## The ending terminal Area3D of the wire connection.
var terminal_end: Area3D = null

## The 2D polygon shape extruded along the path to create the wire's geometry.
var wire_shape: PackedVector2Array = [
	Vector2(0.02, 0.02),
	Vector2(-0.02, 0.02),
	Vector2(-0.02, -0.02),
	Vector2(0.02, -0.02)
]

## Called when the node enters the scene tree. Initializes the wire's visual properties.
func _ready():
	csg_polygon.polygon = wire_shape
	csg_polygon.mode = CSGPolygon3D.MODE_PATH
	csg_polygon.path_node = self.get_path() 
	csg_polygon.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	csg_polygon.path_interval = 0.1 

## Sets the start and end points of the wire, connecting two terminals.
func set_endpoints(start_pos: Vector3, end_pos: Vector3, start_terminal: Area3D, end_terminal: Area3D):
	terminal_start = start_terminal
	terminal_end = end_terminal

	var new_curve = Curve3D.new()
	self.curve = new_curve 

	curve.clear_points()
	curve.add_point(start_pos)
	curve.add_point(end_pos)

## Called every frame. Updates the wire's end positions to follow the terminals if they move.
func _process(delta):
	if is_instance_valid(terminal_start) and is_instance_valid(terminal_end):
		var start_pos = terminal_start.global_position
		var end_pos = terminal_end.global_position
		if curve.get_point_count() == 2: 
			curve.set_point_position(0, start_pos)
			curve.set_point_position(1, end_pos)
