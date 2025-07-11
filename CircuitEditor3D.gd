extends Node3D
class_name CircuitEditor3D
const TERMINAL_COLLISION_LAYER = 2
const COMPONENT_BODY_COLLISION_LAYER = 4
const WIRE_COLLISION_LAYER = 16 
const GROUND_COLLISION_LAYER = 8 
const DRAG_PLANE_NORMAL = Vector3.UP 
const GRID_SIZE: float = 0.05 
const DEFAULT_PLACEMENT_DISTANCE = 5.0 

var ResistorScene = preload("res://components/Resistor3D.tscn")
var PowerSourceScene = preload("res://components/PowerSource3D.tscn")
var LEDScene = preload("res://components/LED3D.tscn")
var SwitchScene = preload("res://components/Switch3D.tscn")
var DiodeScene = preload("res://components/Diode3D.tscn")
var PotentiometerScene = preload("res://components/Potentiometer3D.tscn")
var WireScene = preload("res://components/Wire3D.tscn")
var BatteryScene = preload("res://components/Battery3D.tscn") 
var PolarizedCapacitorScene = preload("res://components/PolarizedCapacitor3D.tscn") 
var NonPolarizedCapacitorScene = preload("res://components/NonPolarizedCapacitor3D.tscn") 
var InductorScene = preload("res://components/Inductor3D.tscn") 
var NPNBJTScene = preload("res://components/NPNBJT3D.tscn") 
var PNPBJTScene = preload("res://components/PNPBJT3D.tscn") 
var ZenerDiodeScene = preload("res://components/ZenerDiode3D.tscn") 
var NChannelMOSFETScene = preload("res://components/NChannelMOSFET3D.tscn") 
var PChannelMOSFETScene = preload("res://components/PChannelMOSFET3D.tscn")
var RelayScene = preload("res://components/Relay3D.tscn") 
var LinearRegulatorScene = preload("res://components/LinearRegulator3D.tscn")
var OpAmpScene = preload("res://components/OpAmp3D.tscn")


@onready var camera: Camera3D = $Camera3D
@onready var circuit_graph: CircuitGraph = $CircuitGraph 


enum WireState { IDLE, START_SELECTED }
var current_wire_state: WireState = WireState.IDLE

var first_selected_terminal: Area3D = null

@onready var components_node: Node3D = $Components
@onready var wires_node: Node3D = $Wires 


var selected_component: Node3D = null
var _potential_drag_target: Node3D = null 
var _drag_start_position: Vector2 = Vector2.ZERO 

@onready var ui_layer: CanvasLayer = $UI
@onready var move_joystick: VirtualJoystick = $UI/MoveJoystick
@onready var look_joystick: VirtualJoystick = $UI/LookJoystick
@onready var component_grid: GridContainer = $UI/ComponentBar/ComponentGrid
@onready var property_container: VBoxContainer = $UI/SelectionBar/PropertyContainer
@onready var selection_bar: VBoxContainer = $UI/SelectionBar


var is_flying: bool = false
var is_simulating_continuously: bool = false
var show_voltage_labels: bool = false
var display_voltage_button: Button = null

@export var fly_speed: float = 5.0
@export var look_sensitivity: float = 0.002 

var move_vector: Vector2 = Vector2.ZERO
var look_vector: Vector2 = Vector2.ZERO
var move_intensity: float = 0.0
var look_intensity: float = 0.0

var is_mobile: bool = false


var is_dragging_component: bool = false
var dragged_component: Node3D = null
var _just_added_component: bool = false 
const DRAG_THRESHOLD: float = 5.0 

var _is_updating_pot_slider_programmatically: bool = false

const SIMULATION_TIME_STEP: float = 0.01 








func _ready():
	
	is_mobile = OS.has_feature("mobile")
	if is_mobile:
		print("Mobile platform detected. Enabling virtual joysticks.")
		
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
		move_joystick.joystick_updated.connect(_on_move_joystick_updated)
		move_joystick.joystick_released.connect(_on_move_joystick_released)
		look_joystick.joystick_updated.connect(_on_look_joystick_updated)
		look_joystick.joystick_released.connect(_on_look_joystick_released)
	else:
		print("Desktop platform detected. Hiding virtual joysticks.")
		move_joystick.visible = false
		look_joystick.visible = false
		
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_populate_component_bar()
	
	selection_bar.get_node("DeleteButton").pressed.connect(_on_delete_button_pressed)
	
	_deselect_component()
	_hide_voltage_displays() 
	
	# Handle beta components visibility
	var enable_beta = ProjectSettings.get_setting("mcu_sim/features/enable_beta_components", false)
	# The op-amp button will be handled in _populate_component_bar now.

func _input(event):
	
	
	if get_viewport().is_input_handled():
		print("--- _input: event already handled by GUI, returning. ---") 
		return

	
	
	


	
	
	if selection_bar.visible: 
		var ui_rect = selection_bar.get_global_rect()
		print("  Workaround check: SelectionBar visible. Rect: {rect}".format({"rect": ui_rect})) 

		var event_pos: Vector2 = Vector2.INF 
		var is_mouse_event: bool = false
		var is_touch_event: bool = false

		if event is InputEventMouse:
			event_pos = event.position
			is_mouse_event = true
			print("    Event is Mouse. Position: {pos}".format({"pos": event_pos})) 
		elif event is InputEventScreenTouch:
			event_pos = event.position
			is_touch_event = true
			print("    Event is Touch. Position: {pos}".format({"pos": event_pos})) 

		
		if (is_mouse_event or is_touch_event) and event_pos != Vector2.INF:
			var hit_ui = ui_rect.has_point(event_pos)
			print("    Rect.has_point(event_pos)? {hit}".format({"hit": hit_ui})) 
			if hit_ui:
				print("--- _input: event occurred over SelectionBar, manually stopping propagation. ---")
				return 
			else:
				print("  Workaround check: Event position is NOT inside SelectionBar rect.") 

	elif false: 
		print("--- _input: event occurred over SelectionBar, manually stopping propagation. ---")
		return 
	

	if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					
					
					
					

					print("Left Mouse Button Pressed at: {pos}".format({"pos": event.position}))

					
					
					if _just_added_component:
						print("  Ignoring input event immediately after component add button press.")
						_just_added_component = false 
						return 

					var mouse_pos = event.position
					var result = _raycast_from_camera(mouse_pos)
					_potential_drag_target = null 

					if result:
						var collider = result.collider
						
						if collider is Area3D and collider.collision_layer == TERMINAL_COLLISION_LAYER and not is_dragging_component:
							is_flying = false
							_hide_voltage_displays() 
							_deselect_component() 
							print("  Raycast hit terminal: {coll_name}".format({"coll_name": collider.name}))
							_handle_terminal_click(collider)
						
						elif collider is Area3D and collider.collision_layer == COMPONENT_BODY_COLLISION_LAYER:
							is_flying = false
							print("  Raycast hit component body: {parent_name}".format({"parent_name": collider.get_parent().name}))
							
							
							
							

							
							var component_node = collider.get_parent() 
							_select_component(component_node)
							_potential_drag_target = component_node 
							_drag_start_position = event.position
						
						elif collider is CSGPolygon3D and collider.collision_layer == WIRE_COLLISION_LAYER:
							is_flying = false
							var wire_node = collider.get_parent() 
							if wire_node is Wire3D:
								print("  Raycast hit wire: {wire_name}".format({"wire_name": wire_node.name}))
								
								_select_component(wire_node)
								
							else:
								print("  Raycast hit wire collision shape, but parent is not Wire3D?")
								_hide_voltage_displays()
								_deselect_component()
						
						else: 
							_hide_voltage_displays()
							print("  Raycast hit ground or other object. Resetting selection/wiring.")
							_deselect_component()
							_reset_wiring_state()

					else: 
						print("!!! Raycast missed in _input, deselecting component !!!") 
						print("  Raycast missed. Resetting selection/wiring.")
						_hide_voltage_displays()
						_deselect_component()
						_reset_wiring_state() 


				elif not event.pressed: 
					print("Left Mouse Button Released at: {0}".format([event.position]))


					if is_dragging_component and dragged_component: 
						print("  Was dragging component. Stopping drag.")
						_stop_component_drag() 
					
					_potential_drag_target = null

			
			elif event.button_index == MOUSE_BUTTON_RIGHT and not is_dragging_component: 
				if event.pressed:
					print("Right Mouse Button Pressed - Toggling fly cam ON")
					is_flying = true
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				else:
					print("Right Mouse Button Released - Toggling fly cam OFF")
					is_flying = false
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	elif event is InputEventMouseMotion:
		if is_dragging_component and dragged_component:
			
			
			_update_dragged_component_position(event.position)
		
		elif event.button_mask & MOUSE_BUTTON_LEFT and _potential_drag_target != null:
			
			if not _potential_drag_target is Wire3D:
				var distance_moved = (event.position - _drag_start_position).length()
				if distance_moved > DRAG_THRESHOLD:
					print("Drag threshold exceeded for {target_name}. Starting drag.".format({"target_name": _potential_drag_target.name}))
					
					if _potential_drag_target == selected_component:
						_start_component_drag(_potential_drag_target)
						_update_dragged_component_position(event.position) 
						_potential_drag_target = null 
		elif is_flying and not is_mobile: 

				
				
				
				camera.rotate_y(-event.relative.x * look_sensitivity) 

				
				camera.rotate_object_local(Vector3.RIGHT, -event.relative.y * look_sensitivity)
				
				camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(89.0), deg_to_rad(89.0))


func _process(delta):
	if is_simulating_continuously:
		_simulate_circuit()
	
	
	var move_input = Vector3.ZERO
	var fly_delta_speed = fly_speed * delta

	if is_mobile:
		
		
		move_input.z = move_vector.y 
		move_input.x = move_vector.x  
		move_input = move_input.normalized() * move_intensity * fly_delta_speed
	elif is_flying:
		
		if Input.is_action_pressed("move_forward"):
			move_input.z -= fly_delta_speed
		if Input.is_action_pressed("move_backward"):
			move_input.z += fly_delta_speed
		if Input.is_action_pressed("move_left"):
			move_input.x -= fly_delta_speed
		if Input.is_action_pressed("move_right"):
			move_input.x += fly_delta_speed
		
		
		
		
		

	
	camera.global_translate(move_input.rotated(Vector3.UP, camera.global_rotation.y))

	
	if is_mobile:
		var look_delta_speed = look_sensitivity * 500 * delta 
		
		camera.rotate_y(-look_vector.x * look_intensity * look_delta_speed) 
		
		camera.rotate_object_local(Vector3.RIGHT, -look_vector.y * look_intensity * look_delta_speed)
		
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(89.0), deg_to_rad(89.0))

func _raycast_from_camera(screen_pos: Vector2):
	var space_state = get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos) * 1000 
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction)

	
	
	
	query.collision_mask = TERMINAL_COLLISION_LAYER | COMPONENT_BODY_COLLISION_LAYER | GROUND_COLLISION_LAYER | WIRE_COLLISION_LAYER
	query.collide_with_areas = true 
	query.collide_with_bodies = true 

	var result = space_state.intersect_ray(query)
	return result

func _handle_terminal_click(terminal: Area3D):
	print("Clicked terminal: ", terminal.name, " on ", terminal.get_parent().name)
	if current_wire_state == WireState.IDLE and not is_dragging_component: 
		first_selected_terminal = terminal
		_hide_voltage_displays() 
		current_wire_state = WireState.START_SELECTED
		print("First terminal selected. Click another terminal to connect.")
		
		if terminal is TerminalFeedback: 
			terminal.select()
		else:
			printerr("Clicked terminal {term_name} does not have TerminalFeedback script.".format({"term_name": terminal.name}))
	elif current_wire_state == WireState.START_SELECTED:
		if terminal == first_selected_terminal:
			print("Clicked the same terminal again.")
			
			
		elif terminal != first_selected_terminal: 
			
			var second_selected_terminal = terminal
			print("Second terminal selected ({sec_term_name}). Creating wire.".format({"sec_term_name": second_selected_terminal.name}))

			
			if not second_selected_terminal is TerminalFeedback:
				printerr("Second selected terminal {sec_term_name} does not have TerminalFeedback script. Cannot create wire.".format({"sec_term_name": second_selected_terminal.name}))
				_reset_wiring_state() 
				return

			_create_wire(first_selected_terminal, second_selected_terminal)

			
			
			_reset_wiring_state()

func _create_wire(terminal_a: Area3D, terminal_b: Area3D):
	var wire_instance = WireScene.instantiate()
	
	wires_node.add_child(wire_instance) 

	
	var start_pos = terminal_a.global_transform.origin
	var end_pos = terminal_b.global_transform.origin

	wire_instance.set_endpoints(start_pos, end_pos, terminal_a, terminal_b)

	
	circuit_graph.connect_terminals(terminal_a, terminal_b)
			


func _snap_to_grid(pos: Vector3) -> Vector3:
	var snapped_x = round(pos.x / GRID_SIZE) * GRID_SIZE
	var snapped_z = round(pos.z / GRID_SIZE) * GRID_SIZE
	return Vector3(snapped_x, 0.0, snapped_z) 



func _start_component_drag(component: Node3D):
	print('begin')
	if component in components_node.get_children(): 
		print("Starting drag for: {comp_name} at initial position {comp_pos}".format({"comp_name": component.name, "comp_pos": component.global_position}))
		is_dragging_component = true
		dragged_component = component
		_hide_voltage_displays() 
		is_flying = false 
		_reset_wiring_state() 
		
		
		

func _update_dragged_component_position(screen_pos: Vector2):
	
	var space_state = get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos) * 1000
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction)
	query.collision_mask = GROUND_COLLISION_LAYER 
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var result = space_state.intersect_ray(query)
	if result:
		
		
		var snapped_position = _snap_to_grid(result.position)
		dragged_component.global_position = snapped_position
		print("Dragging {drag_comp_name}: screen_pos={scr_pos} -> world_pos={world_pos} -> snapped_pos={snap_pos}".format({"drag_comp_name": dragged_component.name, "scr_pos": screen_pos, "world_pos": result.position, "snap_pos": snapped_position}))

func _stop_component_drag():
	if not is_dragging_component: return 
	print("Stopping drag for: {drag_comp_name} at final position {final_pos}".format({"drag_comp_name": dragged_component.name, "final_pos": dragged_component.global_position}))
	
	
		
	

	
	is_dragging_component = false
	
	dragged_component = null

func _add_component(scene: PackedScene, pos: Vector3):
	var component_instance: Node3D = scene.instantiate()
	components_node.add_child(component_instance) 
	component_instance.global_position = pos
	
	
	circuit_graph.add_component(component_instance)
	_hide_voltage_displays()
	
	if component_instance is Switch3D:
		component_instance.state_changed.connect(_on_switch_state_changed)
	elif component_instance is Potentiometer3D:
		component_instance.wiper_position_changed.connect(_on_potentiometer_component_wiper_changed)
	elif component_instance is Battery3D: 
		component_instance.configuration_changed.connect(_on_battery_config_changed)
	elif component_instance is PolarizedCapacitor3D: 
		component_instance.configuration_changed.connect(_on_polarized_capacitor_config_changed)
	elif component_instance is NonPolarizedCapacitor3D: 
		component_instance.configuration_changed.connect(_on_non_polarized_capacitor_config_changed)
	elif component_instance is Inductor3D: 
		component_instance.configuration_changed.connect(_on_inductor_config_changed)
	elif component_instance is NPNBJT3D: 
		component_instance.configuration_changed.connect(_on_npn_bjt_config_changed)
	elif component_instance is PNPBJT3D: 
		component_instance.configuration_changed.connect(_on_pnp_bjt_config_changed)
	elif component_instance is ZenerDiode3D: 
		component_instance.configuration_changed.connect(_on_zener_diode_config_changed)
	elif component_instance is Relay3D: 
		component_instance.configuration_changed.connect(_on_relay_config_changed)
	elif component_instance is OpAmp3D:
		component_instance.configuration_changed.connect(_on_op_amp_config_changed)
		
		
	return component_instance 
	

func _reset_wiring_state():
	if current_wire_state == WireState.START_SELECTED and is_instance_valid(first_selected_terminal):
		print("Wiring state reset (cancelled or completed).")
		
		if first_selected_terminal is TerminalFeedback:
			first_selected_terminal.deselect()
	current_wire_state = WireState.IDLE
	_hide_voltage_displays() 
	first_selected_terminal = null










func _on_add_component_button_pressed(scene_to_add: PackedScene):
	print("Add component button pressed for scene: {scene_path}".format({"scene_path": scene_to_add.resource_path}))

	
	var initial_position: Vector3
	var space_state = get_world_3d().direct_space_state
	var cam_transform = camera.global_transform
	var ray_origin = cam_transform.origin
	var ray_direction = -cam_transform.basis.z 
	var ray_query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000) 
	ray_query.collision_mask = GROUND_COLLISION_LAYER 
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = false

	var result = space_state.intersect_ray(ray_query)
	if result:
		initial_position = result.position
		print("  Placing initial component at ground raycast hit: {init_pos}".format({"init_pos": initial_position}))
	else:
		
		initial_position = ray_origin + ray_direction * DEFAULT_PLACEMENT_DISTANCE
		initial_position.y = 0.0 
		print("  Placing initial component at fallback position (projected): {init_pos}".format({"init_pos": initial_position}))

	
	var snapped_initial_position = _snap_to_grid(initial_position)
	print("  Snapped initial position to grid: {snap_pos}".format({"snap_pos": snapped_initial_position}))
	
	_hide_voltage_displays() 
	var new_component: Node3D = _add_component(scene_to_add, snapped_initial_position)
	_select_component(new_component) 
	_start_component_drag(new_component)
	_just_added_component = true 


func _perform_simulation_step():
	print("Performing simulation step...")
	
	
	var ground_terminal_set = false
	if circuit_graph.ground_node_id == -1: 
		print("  Attempting to set ground node as none is currently set.")
		for comp_data in circuit_graph.components:
			if comp_data.type == "PowerSource" or comp_data.type == "Battery":
				var neg_terminal = comp_data.terminals.get("NEG", null) 
				if is_instance_valid(neg_terminal):
					circuit_graph.set_ground_node(neg_terminal)
					ground_terminal_set = true 
					break 
		if not ground_terminal_set:
			print("  Warning: Could not automatically find a power source negative terminal to ground for this step.")
	else:
		ground_terminal_set = true 

	if not ground_terminal_set or circuit_graph.ground_node_id == -1:
		printerr("Simulation Error: Cannot simulate because no ground node is set. Add a Power Source or ensure one is grounded.")
		_hide_voltage_displays() 
		return

	if circuit_graph.solve_single_time_step(SIMULATION_TIME_STEP):
		print("  Simulation step successful.")
		_update_led_states()       
		_update_voltage_displays() 
	else:
		print("  Simulation step failed. Check console for errors and circuit configuration.")
		_hide_voltage_displays() 

func _on_simulate_button_pressed():
	is_simulating_continuously = not is_simulating_continuously 
	
	if is_simulating_continuously:
		simulate_button.text = "Stop Simulation"
		print("Starting continuous simulation.")
		
		
		_perform_simulation_step() 
	else:
		simulate_button.text = "Simulate"
		print("Stopping continuous simulation.")
		_hide_voltage_displays() 
		show_voltage_labels = false
		if display_voltage_button: 
			display_voltage_button.button_pressed = false 
			display_voltage_button.text = "Display Voltage Labels"
		
		
func _simulate_circuit():
	
	
	if circuit_graph.ground_node_id == -1:
		
		
		
		
		var temp_ground_set = false
		if circuit_graph.ground_node_id == -1: 
			for comp_data in circuit_graph.components:
				if comp_data.type == "PowerSource" or comp_data.type == "Battery":
					var neg_terminal = comp_data.terminals.get("NEG", null) 
					if is_instance_valid(neg_terminal):
						circuit_graph.set_ground_node(neg_terminal)
						temp_ground_set = true
						break
			if not temp_ground_set:
				
				for comp_data_mos_gnd in circuit_graph.components:
					if comp_data_mos_gnd.type == "NChannelMOSFET":
						var s_terminal = comp_data_mos_gnd.terminals.get("S", null)
						if is_instance_valid(s_terminal):
							circuit_graph.set_ground_node(s_terminal)
							temp_ground_set = true
							print_debug("Continuous simulation: No PS/Battery ground, grounded Source of NChannelMOSFET {n}".format({"n": comp_data_mos_gnd.component_node.name}))
							break
			if not temp_ground_set:
				printerr("Continuous Simulation Error: Ground node not set and could not auto-set. Stopping.")
				is_simulating_continuously = false 
				simulate_button.text = "Simulate"
				_hide_voltage_displays()
		if not temp_ground_set:
			printerr("Continuous Simulation Error: Ground node not set. Stopping.")
			is_simulating_continuously = false 
			simulate_button.text = "Simulate"
			_hide_voltage_displays()
			return


	if circuit_graph.solve_single_time_step(SIMULATION_TIME_STEP):
		_update_led_states()       
		_update_voltage_displays() 
	else:
		
		
		
		
		_hide_voltage_displays(true) 
		pass 



# --- Dynamic UI generation for component bar and property editor ---

func _populate_component_bar():
	var components_to_add = [
		{"name": "Power", "scene": PowerSourceScene},
		{"name": "Resistor", "scene": ResistorScene},
		{"name": "LED", "scene": LEDScene},
		{"name": "Switch", "scene": SwitchScene},
		{"name": "Diode", "scene": DiodeScene},
		{"name": "Pot", "scene": PotentiometerScene},
		{"name": "Battery", "scene": BatteryScene},
		{"name": "Cap P.", "scene": PolarizedCapacitorScene},
		{"name": "Cap NP.", "scene": NonPolarizedCapacitorScene},
		{"name": "Inductor", "scene": InductorScene},
		{"name": "NPN", "scene": NPNBJTScene},
		{"name": "PNP", "scene": PNPBJTScene},
		{"name": "Zener", "scene": ZenerDiodeScene},
		{"name": "N-MOS", "scene": NChannelMOSFETScene},
		{"name": "P-MOS", "scene": PChannelMOSFETScene},
		{"name": "Relay", "scene": RelayScene},
		{"name": "Regulator", "scene": LinearRegulatorScene},
	]
	
	var enable_beta = ProjectSettings.get_setting("mcu_sim/features/enable_beta_components", false)
	if enable_beta:
		components_to_add.append({"name": "Op-Amp", "scene": OpAmpScene})

	for comp_def in components_to_add:
		var btn = Button.new()
		btn.text = comp_def.name
		btn.pressed.connect(_on_add_component_button_pressed.bind(comp_def.scene))
		component_grid.add_child(btn)
	
	# Action buttons
	simulate_button = Button.new()
	simulate_button.text = "Simulate"
	simulate_button.pressed.connect(_on_simulate_button_pressed)
	component_grid.add_child(simulate_button)

	display_voltage_button = Button.new()
	display_voltage_button.text = "Display Voltages"
	display_voltage_button.toggle_mode = true
	display_voltage_button.button_pressed = false
	display_voltage_button.pressed.connect(_on_display_voltage_button_pressed)
	component_grid.add_child(display_voltage_button)


func _clear_properties():
	for child in property_container.get_children():
		child.queue_free()

func _add_line_edit_property(label_text: String, initial_value, change_callable: Callable):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	var line_edit = LineEdit.new()
	line_edit.text = str(initial_value)
	line_edit.text_submitted.connect(func(new_text):
		var new_value: float = NAN
		if new_text.is_valid_float():
			new_value = float(new_text)
			change_callable.call(new_value)
		else:
			# On invalid input, just revert the text
			line_edit.text = str(initial_value)
	)
	hbox.add_child(label)
	hbox.add_child(line_edit)
	property_container.add_child(hbox)

func _add_option_button_property(label_text: String, items: Array[String], selected_index: int, change_callable: Callable):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	var option_btn = OptionButton.new()
	for i in range(items.size()):
		option_btn.add_item(items[i], i)
	option_btn.select(selected_index)
	option_btn.item_selected.connect(change_callable)
	hbox.add_child(label)
	hbox.add_child(option_btn)
	property_container.add_child(hbox)

func _add_slider_property(initial_value: float, change_callable: Callable):
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	_is_updating_pot_slider_programmatically = true
	slider.value = initial_value
	_is_updating_pot_slider_programmatically = false
	slider.value_changed.connect(func(value):
		if not _is_updating_pot_slider_programmatically:
			change_callable.call(value)
	)
	property_container.add_child(slider)

func _add_action_button(text: String, press_callable: Callable):
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(press_callable)
	property_container.add_child(btn)

func _add_label_property(label_text: String, value_text: String):
	var hbox = HBoxContainer.new()
	var label_title = Label.new()
	label_title.text = label_text
	var label_value = Label.new()
	label_value.text = value_text
	label_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(label_title)
	hbox.add_child(label_value)
	property_container.add_child(hbox)

func _select_component(component: Node3D):
	if component == selected_component:
		return
	else:
		if selected_component != null: 
			_deselect_component() 
		selected_component = component 
		print("Selecting new component: {comp_name}".format({"comp_name": component.name}))

	selection_bar.visible = true
	_clear_properties()

	if selected_component is Resistor3D:
		_add_line_edit_property("Resistance (Ω):", selected_component.resistance, func(new_val): selected_component.resistance = new_val)
		
	elif selected_component is PowerSource3D:
		_add_line_edit_property("Target Voltage (V):", selected_component.target_voltage, func(new_val): selected_component.target_voltage = new_val)
		_add_line_edit_property("Current Limit (A):", selected_component.target_current, func(new_val): 
			selected_component.target_current = max(0.0, new_val)
			circuit_graph.component_config_changed(selected_component)
		)

	elif selected_component is Battery3D:
		_add_label_property("Voltage (V):", str(selected_component.target_voltage))
		var cell_items = ["1 (1.5V)", "2 (3.0V)", "3 (4.5V)", "4 (6.0V)"]
		_add_option_button_property("Cells:", cell_items, selected_component.num_cells - 1, func(index): 
			selected_component.set_num_cells(index + 1)
			_select_component(selected_component) # Redraw to update label
		)
		
	elif selected_component is LED3D:
		_add_line_edit_property("Fwd Voltage (V):", selected_component.forward_voltage, func(new_val): selected_component.forward_voltage = new_val)
		
	elif selected_component is Diode3D:
		_add_line_edit_property("Fwd Voltage (V):", selected_component.forward_voltage, func(new_val): selected_component.forward_voltage = new_val)

	elif selected_component is ZenerDiode3D:
		var selected_t : ZenerDiode3D = selected_component
		_add_line_edit_property("Fwd Voltage (Vf):", selected_t.forward_voltage, func(new_val): selected_t.forward_voltage = new_val)
		_add_line_edit_property("Zener Voltage (Vz):", selected_t.zener_voltage, func(new_val): selected_t.zener_voltage = new_val)
		
	elif selected_component is Switch3D:
		var btn_text = "Turn Off" if selected_component.current_state == Switch3D.State.CONNECTED_NO else "Turn On"
		_add_action_button(btn_text, func():
			selected_component.toggle_state()
			_select_component(selected_component) # Redraw to update button text
		)

	elif selected_component is Potentiometer3D:
		_add_line_edit_property("Total R (Ω):", selected_component.total_resistance, func(new_val): selected_component.total_resistance = new_val)
		_add_slider_property(selected_component.wiper_position, func(new_val): selected_component.set_wiper_position(new_val))
		
	elif selected_component is Wire3D:
		pass # No properties to show
		
	elif selected_component is PolarizedCapacitor3D or selected_component is NonPolarizedCapacitor3D:
		_add_line_edit_property("Capacitance (F):", selected_component.capacitance, func(new_val): selected_component.capacitance = new_val)
		_add_line_edit_property("Max Voltage (V):", selected_component.max_voltage, func(new_val): selected_component.max_voltage = new_val)

	elif selected_component is Inductor3D:
		_add_line_edit_property("Inductance (H):", selected_component.inductance, func(new_val): selected_component.inductance = new_val)

	elif selected_component is NPNBJT3D:
		var selected_t : NPNBJT3D = selected_component
		_add_line_edit_property("Beta (Hfe):", selected_t.beta_dc, func(new_val): selected_t.beta_dc = new_val)
		_add_line_edit_property("Vbe On (V):", selected_t.vbe_on, func(new_val): selected_t.vbe_on = new_val)
		
	elif selected_component is PNPBJT3D:
		var selected_t : PNPBJT3D = selected_component
		_add_line_edit_property("Beta (Hfe):", selected_t.beta_dc, func(new_val): selected_t.beta_dc = new_val)
		_add_line_edit_property("Veb On (V):", selected_t.veb_on, func(new_val): selected_t.veb_on = new_val)
		_add_line_edit_property("Vec Sat (V):", selected_t.vec_sat, func(new_val): selected_t.vec_sat = new_val)
	
	elif selected_component is NChannelMOSFET3D:
		var selected_t : NChannelMOSFET3D = selected_component
		_add_line_edit_property("Vt (V):", selected_t.threshold_voltage, func(new_val): selected_t.threshold_voltage = new_val)
		_add_line_edit_property("Kn (A/V^2):", selected_t.transconductance_parameter, func(new_val): selected_t.transconductance_parameter = new_val)

	elif selected_component is Relay3D:
		var selected_t : Relay3D = selected_component
		_add_line_edit_property("Coil Threshold (V):", selected_t.signal_voltage_threshold, func(new_val): selected_t.signal_voltage_threshold = new_val)
		_add_line_edit_property("Coil Resist. (Ω):", selected_t.coil_resistance, func(new_val): selected_t.coil_resistance = new_val)

	elif selected_component is LinearRegulator3D:
		_add_line_edit_property("Regulated (V):", selected_component.regulated_voltage, func(new_val): selected_component.regulated_voltage = new_val)

	elif selected_component is OpAmp3D:
		_add_label_property("Ideal Op-Amp", "(No properties)")

	else:
		printerr("Selected node {comp_name} is not a recognized component type for editing.".format({"comp_name": component.name}))

	selection_bar.get_node("DeleteButton").visible = true

func _deselect_component():
	if selected_component:
		print("Deselecting component: {sel_comp_name}".format({"sel_comp_name": selected_component.name}))

	selected_component = null
	selection_bar.visible = false
	_clear_properties()
	
	_potential_drag_target = null
	selection_bar.get_node("DeleteButton").visible = false
