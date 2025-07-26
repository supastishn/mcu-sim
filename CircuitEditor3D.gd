extends Node3D
class_name CircuitEditor3D

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
var BreadboardScene = preload("res://components/Breadboard3D.tscn")


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
var simulate_button: Button = null

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








## Godot's ready function. Initializes the editor, sets up UI, and prepares for user interaction.
func _ready():
	is_mobile = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
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

## Handles all input events, including mouse clicks for selecting/wiring/dragging and keyboard controls for camera flight.
func _input(event):
	if get_viewport().is_input_handled():
		return

	if selection_bar.visible: 
		var ui_rect = selection_bar.get_global_rect()

		var event_pos: Vector2 = Vector2.INF 
		if event is InputEventMouse:
			event_pos = event.position
		elif event is InputEventScreenTouch:
			event_pos = event.position

		if event_pos != Vector2.INF:
			if ui_rect.has_point(event_pos):
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
					var hit = ComponentInteractionUtils.get_interactive_object_at(camera, mouse_pos, components_node)
					_potential_drag_target = null 

					match hit.type:
						"terminal":
							is_flying = false
							_hide_voltage_displays()
							_deselect_component()
							print("  Hit terminal: {coll_name}".format({"coll_name": hit.node.name}))
							_handle_terminal_click(hit.node)

						"component_body":
							is_flying = false
							print("  Hit component body: {parent_name}".format({"parent_name": hit.node.name}))
							_select_component(hit.node)
							_potential_drag_target = hit.node
							_drag_start_position = event.position

						"wire":
							is_flying = false
							print("  Hit wire: {wire_name}".format({"wire_name": hit.node.name}))
							_select_component(hit.node)

						"ground", "none":
							_hide_voltage_displays()
							print("  Hit ground or nothing. Resetting selection/wiring.")
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


## Godot's process function. Handles continuous simulation steps and camera movement.
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


## Manages the logic for wiring when a component terminal is clicked.
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

## Instantiates and configures a new Wire3D scene to connect two terminals.
func _create_wire(terminal_a: Area3D, terminal_b: Area3D):
	var wire_instance = WireScene.instantiate()
	
	wires_node.add_child(wire_instance) 

	
	var start_pos = terminal_a.global_transform.origin
	var end_pos = terminal_b.global_transform.origin

	wire_instance.set_endpoints(start_pos, end_pos, terminal_a, terminal_b)

	
	circuit_graph.connect_terminals(terminal_a, terminal_b)
			


## Snaps a given 3D position to the editor's grid.
func _snap_to_grid(pos: Vector3) -> Vector3:
	var snapped_x = round(pos.x / GRID_SIZE) * GRID_SIZE
	var snapped_z = round(pos.z / GRID_SIZE) * GRID_SIZE
	return Vector3(snapped_x, 0.0, snapped_z) 



## Begins the process of dragging a component in the 3D view.
func _start_component_drag(component: Node3D):
	print('begin')
	if component in components_node.get_children(): 
		print("Starting drag for: {comp_name} at initial position {comp_pos}".format({"comp_name": component.name, "comp_pos": component.global_position}))
		is_dragging_component = true
		dragged_component = component
		_hide_voltage_displays() 
		is_flying = false 
		_reset_wiring_state()

## Updates the position of the currently dragged component based on mouse/touch screen position.
func _update_dragged_component_position(screen_pos: Vector2):
	
	var space_state = get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos) * 1000
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction)
	query.collision_mask = ComponentInteractionUtils.GROUND_COLLISION_LAYER 
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var result = space_state.intersect_ray(query)
	if result:
		var snapped_position = _snap_to_grid(result.position)
		dragged_component.global_position = snapped_position
		print("Dragging {drag_comp_name}: screen_pos={scr_pos} -> world_pos={world_pos} -> snapped_pos={snap_pos}".format({"drag_comp_name": dragged_component.name, "scr_pos": screen_pos, "world_pos": result.position, "snap_pos": snapped_position}))

## Finalizes the component drag operation.
func _stop_component_drag():
	if not is_dragging_component: return 
	print("Stopping drag for: {drag_comp_name} at final position {final_pos}".format({"drag_comp_name": dragged_component.name, "final_pos": dragged_component.global_position}))
	
	is_dragging_component = false
	
	dragged_component = null

## Adds a new component instance to the scene and the circuit graph.
func _add_component(scene: PackedScene, pos: Vector3, p_name: String = ""):
	var component_instance: Node3D = scene.instantiate()
	if not p_name.is_empty():
		component_instance.name = p_name
	else:
		component_instance.name = _generate_unique_name(component_instance.get_class())
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
	elif component_instance is NChannelMOSFET3D:
		component_instance.configuration_changed.connect(_on_n_channel_mosfet_config_changed)
	elif component_instance is PChannelMOSFET3D:
		component_instance.configuration_changed.connect(_on_p_channel_mosfet_config_changed)
	elif component_instance is Relay3D: 
		component_instance.configuration_changed.connect(_on_relay_config_changed)
	elif component_instance is OpAmp3D:
		component_instance.configuration_changed.connect(_on_op_amp_config_changed)
		
		
	return component_instance 
	

## Resets the wire creation state machine to its idle state.
func _reset_wiring_state():
	if current_wire_state == WireState.START_SELECTED and is_instance_valid(first_selected_terminal):
		print("Wiring state reset (cancelled or completed).")
		
		if first_selected_terminal is TerminalFeedback:
			first_selected_terminal.deselect()
	current_wire_state = WireState.IDLE
	_hide_voltage_displays() 
	first_selected_terminal = null


## Callback for the 'Add Component' button, initiating the component placement process.
func _on_add_component_button_pressed(scene_to_add: PackedScene):
	print("Add component button pressed for scene: {scene_path}".format({"scene_path": scene_to_add.resource_path}))

	
	var initial_position: Vector3
	var space_state = get_world_3d().direct_space_state
	var cam_transform = camera.global_transform
	var ray_origin = cam_transform.origin
	var ray_direction = -cam_transform.basis.z 
	var ray_query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000) 
	ray_query.collision_mask = ComponentInteractionUtils.GROUND_COLLISION_LAYER 
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


## Performs a single step of the circuit simulation.
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
		_update_component_visuals()       
		_update_voltage_displays() 
	else:
		print("  Simulation step failed. Check console for errors and circuit configuration.")
		_hide_voltage_displays() 

## Callback for the main 'Simulate' button, toggling continuous simulation.
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
		
## Called every frame when continuous simulation is active.
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
		_update_component_visuals()       
		_update_voltage_displays() 
	else:
		_hide_voltage_displays() 
		pass 


# --- Dynamic UI generation for component bar and property editor ---

## Dynamically creates and adds buttons for each available component to the component bar UI.
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
		{"name": "Breadboard", "scene": BreadboardScene},
		{"name": "Op-Amp", "scene": OpAmpScene},
	]
	
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

	var save_button = Button.new()
	save_button.text = "Save Circuit"
	save_button.pressed.connect(_on_save_button_pressed)
	component_grid.add_child(save_button)

	var load_button = Button.new()
	load_button.text = "Load Circuit"
	load_button.pressed.connect(_on_load_button_pressed)
	component_grid.add_child(load_button)


## Removes all dynamically generated property editors from the selection bar.
func _clear_properties():
	for child in property_container.get_children():
		child.queue_free()

## Adds a property editor with a label and a LineEdit to the selection bar.
func _add_line_edit_property(label_text: String, initial_value, change_callable: Callable):
	var hbox = HBoxContainer.new()
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line_edit = LineEdit.new()
	line_edit.text = str(initial_value)
	line_edit.text_submitted.connect(func(new_text):
		if new_text.is_valid_float():
			var new_value = float(new_text)
			change_callable.call(new_value)
		else:
			# On invalid input, just revert the text
			line_edit.text = str(initial_value)
	)
	hbox.add_child(label)
	hbox.add_child(line_edit)
	property_container.add_child(hbox)

## Adds a property editor with a label and an OptionButton to the selection bar.
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

## Adds a property editor with a HSlider to the selection bar.
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

## Adds a simple button to the selection bar.
func _add_action_button(text: String, press_callable: Callable):
	var btn = Button.new()
	btn.text = text
	btn.pressed.connect(press_callable)
	property_container.add_child(btn)

## Adds a non-editable label and value text to the selection bar.
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

## Selects a component, showing its properties in the selection bar.
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
		_add_line_edit_property("Sat. Current (A):", selected_component.saturation_current, func(new_val): selected_component.saturation_current = new_val)
		_add_line_edit_property("Ideality Factor:", selected_component.ideality_factor, func(new_val): selected_component.ideality_factor = new_val)
		
	elif selected_component is Diode3D:
		_add_line_edit_property("Sat. Current (A):", selected_component.saturation_current, func(new_val): selected_component.saturation_current = new_val)
		_add_line_edit_property("Ideality Factor:", selected_component.ideality_factor, func(new_val): selected_component.ideality_factor = new_val)

	elif selected_component is ZenerDiode3D:
		var selected_t : ZenerDiode3D = selected_component
		_add_line_edit_property("Sat. Current (A):", selected_t.saturation_current, func(new_val): selected_t.saturation_current = new_val)
		_add_line_edit_property("Ideality Factor:", selected_t.ideality_factor, func(new_val): selected_t.ideality_factor = new_val)
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
		pass
		
	elif selected_component is PolarizedCapacitor3D or selected_component is NonPolarizedCapacitor3D:
		_add_line_edit_property("Capacitance (F):", selected_component.capacitance, func(new_val): selected_component.capacitance = new_val)
		_add_line_edit_property("Max Voltage (V):", selected_component.max_voltage, func(new_val): selected_component.max_voltage = new_val)
		_add_line_edit_property("ESR (Ohms):", selected_component.equivalent_series_resistance, func(new_val): selected_component.equivalent_series_resistance = new_val)

	elif selected_component is Inductor3D:
		_add_line_edit_property("Inductance (H):", selected_component.inductance, func(new_val): selected_component.inductance = new_val)
		_add_line_edit_property("DCR (Ohms):", selected_component.dc_resistance, func(new_val): selected_component.dc_resistance = new_val)

	elif selected_component is NPNBJT3D:
		var selected_t : NPNBJT3D = selected_component
		_add_line_edit_property("Is (A):", selected_t.saturation_current, func(new_val): selected_t.set("saturation_current", new_val))
		_add_line_edit_property("Alpha Fwd:", selected_t.alpha_forward, func(new_val): selected_t.set("alpha_forward", new_val))
		_add_line_edit_property("Alpha Rev:", selected_t.alpha_reverse, func(new_val): selected_t.set("alpha_reverse", new_val))
		
	elif selected_component is PNPBJT3D:
		var selected_t : PNPBJT3D = selected_component
		_add_line_edit_property("Is (A):", selected_t.saturation_current, func(new_val): selected_t.set("saturation_current", new_val))
		_add_line_edit_property("Alpha Fwd:", selected_t.alpha_forward, func(new_val): selected_t.set("alpha_forward", new_val))
		_add_line_edit_property("Alpha Rev:", selected_t.alpha_reverse, func(new_val): selected_t.set("alpha_reverse", new_val))
	
	elif selected_component is NChannelMOSFET3D:
		var selected_t : NChannelMOSFET3D = selected_component
		_add_line_edit_property("Vt (V):", selected_t.threshold_voltage, func(new_val): selected_t.threshold_voltage = new_val)
		_add_line_edit_property("Kn (A/V^2):", selected_t.transconductance_parameter, func(new_val): selected_t.transconductance_parameter = new_val)
		_add_line_edit_property("Lambda:", selected_t.lambda, func(new_val): selected_t.lambda = new_val)

	elif selected_component is PChannelMOSFET3D:
		var selected_t : PChannelMOSFET3D = selected_component
		_add_line_edit_property("|Vtp| (V):", selected_t.threshold_voltage, func(new_val): selected_t.threshold_voltage = new_val)
		_add_line_edit_property("Kp (A/V^2):", selected_t.transconductance_parameter, func(new_val): selected_t.transconductance_parameter = new_val)
		_add_line_edit_property("Lambda:", selected_t.lambda, func(new_val): selected_t.lambda = new_val)

	elif selected_component is Relay3D:
		var selected_t : Relay3D = selected_component
		_add_line_edit_property("Coil Threshold (V):", selected_t.signal_voltage_threshold, func(new_val): selected_t.signal_voltage_threshold = new_val)
		_add_line_edit_property("Coil Resist. (Ω):", selected_t.coil_resistance, func(new_val): selected_t.coil_resistance = new_val)

	elif selected_component is LinearRegulator3D:
		_add_line_edit_property("Regulated (V):", selected_component.regulated_voltage, func(new_val): selected_component.regulated_voltage = new_val)

	elif selected_component is OpAmp3D:
		var selected_t : OpAmp3D = selected_component
		_add_line_edit_property("Input R (Ω):", selected_t.input_resistance, func(new_val): selected_t.input_resistance = new_val)
		_add_line_edit_property("Output R (Ω):", selected_t.output_resistance, func(new_val): selected_t.output_resistance = new_val)

	else:
		printerr("Selected node {comp_name} is not a recognized component type for editing.".format({"comp_name": component.name}))

	selection_bar.get_node("DeleteButton").visible = true

## Deselects the currently selected component and hides the property editor.
func _deselect_component():
	if selected_component:
		print("Deselecting component: {sel_comp_name}".format({"sel_comp_name": selected_component.name}))

	selected_component = null
	selection_bar.visible = false
	_clear_properties()
	
	_potential_drag_target = null
	selection_bar.get_node("DeleteButton").visible = false

# --- Signal Callbacks ---

## Callback for joystick movement updates.
func _on_move_joystick_updated(direction: Vector2, intensity: float):
	move_vector = direction
	move_intensity = intensity

## Callback for joystick movement release.
func _on_move_joystick_released():
	move_vector = Vector2.ZERO
	move_intensity = 0.0

## Callback for joystick look updates.
func _on_look_joystick_updated(direction: Vector2, intensity: float):
	look_vector = direction
	look_intensity = intensity

## Callback for joystick look release.
func _on_look_joystick_released():
	look_vector = Vector2.ZERO
	look_intensity = 0.0

## Callback for when the "Delete" button is pressed for the selected component.
func _on_delete_button_pressed():
	if not is_instance_valid(selected_component):
		return

	var component_to_delete = selected_component
	_deselect_component()

	if component_to_delete is Wire3D:
		component_to_delete.queue_free()
		_rebuild_graph_from_scene()
	else:
		circuit_graph.remove_component(component_to_delete)
		component_to_delete.queue_free()

	_hide_voltage_displays()

## Saves the current circuit to a file.
func save_circuit_to_file(file_path: String) -> void:
	print("--- Saving circuit to file: {p} ---".format({"p": file_path}))
	var save_data = {}
	
	# Save components
	var components_data = []
	for component in components_node.get_children():
		if component is Wire3D:
			continue  # Wires are reconstructed from connections
			
		var comp_data = {
			"name": component.name,
			"type": "" if component.scene_file_path.is_empty() else component.scene_file_path.get_file().get_basename(),
			"position": {
				"x": component.global_position.x,
				"y": component.global_position.y,
				"z": component.global_position.z
			},
			"properties": {}
		}
		
		# Save component-specific properties
		if component is Resistor3D:
			comp_data["properties"]["resistance"] = component.resistance
		elif component is PowerSource3D:
			comp_data["properties"]["target_voltage"] = component.target_voltage
			comp_data["properties"]["target_current"] = component.target_current
		elif component is LED3D:
			comp_data["properties"]["saturation_current"] = component.saturation_current
			comp_data["properties"]["ideality_factor"] = component.ideality_factor
		elif component is Switch3D:
			comp_data["properties"]["current_state"] = component.current_state
		elif component is Diode3D:
			comp_data["properties"]["saturation_current"] = component.saturation_current
			comp_data["properties"]["ideality_factor"] = component.ideality_factor
		elif component is Potentiometer3D:
			comp_data["properties"]["total_resistance"] = component.total_resistance
			comp_data["properties"]["wiper_position"] = component.wiper_position
		elif component is Battery3D:
			comp_data["properties"]["num_cells"] = component.num_cells
		elif component is PolarizedCapacitor3D:
			comp_data["properties"]["capacitance"] = component.capacitance
			comp_data["properties"]["max_voltage"] = component.max_voltage
			comp_data["properties"]["equivalent_series_resistance"] = component.equivalent_series_resistance
		elif component is NonPolarizedCapacitor3D:
			comp_data["properties"]["capacitance"] = component.capacitance
			comp_data["properties"]["max_voltage"] = component.max_voltage
			comp_data["properties"]["equivalent_series_resistance"] = component.equivalent_series_resistance
		elif component is Inductor3D:
			comp_data["properties"]["inductance"] = component.inductance
			comp_data["properties"]["dc_resistance"] = component.dc_resistance
		elif component is NPNBJT3D:
			comp_data["properties"]["saturation_current"] = component.saturation_current
			comp_data["properties"]["alpha_forward"] = component.alpha_forward
			comp_data["properties"]["alpha_reverse"] = component.alpha_reverse
		elif component is PNPBJT3D:
			comp_data["properties"]["saturation_current"] = component.saturation_current
			comp_data["properties"]["alpha_forward"] = component.alpha_forward
			comp_data["properties"]["alpha_reverse"] = component.alpha_reverse
		elif component is ZenerDiode3D:
			comp_data["properties"]["saturation_current"] = component.saturation_current
			comp_data["properties"]["ideality_factor"] = component.ideality_factor
			comp_data["properties"]["zener_voltage"] = component.zener_voltage
		elif component is NChannelMOSFET3D:
			comp_data["properties"]["threshold_voltage"] = component.threshold_voltage
			comp_data["properties"]["transconductance_parameter"] = component.transconductance_parameter
			comp_data["properties"]["lambda"] = component.lambda
		elif component is PChannelMOSFET3D:
			comp_data["properties"]["threshold_voltage"] = component.threshold_voltage
			comp_data["properties"]["transconductance_parameter"] = component.transconductance_parameter
			comp_data["properties"]["lambda"] = component.lambda
		elif component is Relay3D:
			comp_data["properties"]["signal_voltage_threshold"] = component.signal_voltage_threshold
			comp_data["properties"]["coil_resistance"] = component.coil_resistance
		elif component is LinearRegulator3D:
			comp_data["properties"]["regulated_voltage"] = component.regulated_voltage
		elif component is OpAmp3D:
			comp_data["properties"]["open_loop_gain"] = component.open_loop_gain
			comp_data["properties"]["input_resistance"] = component.input_resistance
			comp_data["properties"]["output_resistance"] = component.output_resistance
			
		components_data.append(comp_data)
	
	save_data["components"] = components_data
	
	# Save wire connections (terminal pairs)
	var wire_data = []
	for wire in wires_node.get_children():
		if wire is Wire3D and is_instance_valid(wire.terminal_start) and is_instance_valid(wire.terminal_end):
			# Store component names and terminal names for reconstruction
			var start_parent = wire.terminal_start.get_parent()
			var end_parent = wire.terminal_end.get_parent()
			
			if start_parent and end_parent:
				wire_data.append({
					"start_component": start_parent.name,
					"start_terminal": wire.terminal_start.name,
					"end_component": end_parent.name,
					"end_terminal": wire.terminal_end.name
				})
	
	save_data["wires"] = wire_data
	
	# Save ground connection
	if circuit_graph.ground_node_id != -1:
		for node_id in circuit_graph.electrical_nodes:
			var node_data = circuit_graph.electrical_nodes[node_id]
			if node_id == circuit_graph.ground_node_id and not node_data.terminals.is_empty():
				var ground_terminal = node_data.terminals[0]
				var ground_parent = ground_terminal.get_parent()
				if ground_parent:
					save_data["ground"] = {
						"component": ground_parent.name,
						"terminal": ground_terminal.name
					}
				break
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_data, "  ", true) # Pretty print
		print("Saving data:\n" + json_string)
		file.store_string(json_string)
		file.close()
		print("--- Circuit successfully saved to: {p} ---".format({"p": file_path}))
	else:
		printerr("Failed to save circuit to: {p}".format({"p": file_path}))

## Loads a circuit from a file.
func load_circuit_from_file(file_path: String) -> void:
	print("--- Loading circuit from file: {p} ---".format({"p": file_path}))
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		printerr("Failed to load circuit from: {p}".format({"p": file_path}))
		return
	
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(content)
	if parse_result != OK:
		print("Failed to parse save file: ", file_path)
		return
	
	var save_data = json.data
	if typeof(save_data) != TYPE_DICTIONARY:
		printerr("Invalid save data format in file: {p}".format({"p": file_path}))
		return
	
	var json_string = JSON.stringify(save_data, "  ", true)
	print("Loaded data:\n" + json_string)
	
	# Clear existing circuit
	_clear_circuit()
	
	# Load components
	var component_map = {}  # Map component names to instances
	if save_data.has("components"):
		for comp_data in save_data["components"]:
			var scene = _get_component_scene(comp_data["type"])
			if scene:
				var component_name = comp_data.get("name", "")
				var pos_data = comp_data["position"]
				var position = Vector3(pos_data["x"], pos_data["y"], pos_data["z"])
				var component = _add_component(scene, position, component_name)
				component_map[component.name] = component
				
				# Restore properties
				if comp_data["properties"].has("resistance"):
					component.resistance = comp_data["properties"]["resistance"]
				if comp_data["properties"].has("target_voltage"):
					component.target_voltage = comp_data["properties"]["target_voltage"]
				if comp_data["properties"].has("target_current"):
					component.target_current = comp_data["properties"]["target_current"]
				if comp_data["properties"].has("saturation_current"):
					component.saturation_current = comp_data["properties"]["saturation_current"]
				if comp_data["properties"].has("ideality_factor"):
					component.ideality_factor = comp_data["properties"]["ideality_factor"]
				if comp_data["properties"].has("current_state"):
					component.set_state(comp_data["properties"]["current_state"])
				if comp_data["properties"].has("wiper_position"):
					component.set_wiper_position(comp_data["properties"]["wiper_position"])
				if comp_data["properties"].has("num_cells"):
					component.set_num_cells(comp_data["properties"]["num_cells"])
				if comp_data["properties"].has("capacitance"):
					component.capacitance = comp_data["properties"]["capacitance"]
				if comp_data["properties"].has("max_voltage"):
					component.max_voltage = comp_data["properties"]["max_voltage"]
				if comp_data["properties"].has("inductance"):
					component.inductance = comp_data["properties"]["inductance"]
				if comp_data["properties"].has("alpha_forward"):
					component.alpha_forward = comp_data["properties"]["alpha_forward"]
				if comp_data["properties"].has("alpha_reverse"):
					component.alpha_reverse = comp_data["properties"]["alpha_reverse"]
				if comp_data["properties"].has("zener_voltage"):
					component.zener_voltage = comp_data["properties"]["zener_voltage"]
				if comp_data["properties"].has("threshold_voltage"):
					component.threshold_voltage = comp_data["properties"]["threshold_voltage"]
				if comp_data["properties"].has("transconductance_parameter"):
					component.transconductance_parameter = comp_data["properties"]["transconductance_parameter"]
				if comp_data["properties"].has("signal_voltage_threshold"):
					component.signal_voltage_threshold = comp_data["properties"]["signal_voltage_threshold"]
				if comp_data["properties"].has("coil_resistance"):
					component.coil_resistance = comp_data["properties"]["coil_resistance"]
				if comp_data["properties"].has("regulated_voltage"):
					component.regulated_voltage = comp_data["properties"]["regulated_voltage"]
				if comp_data["properties"].has("open_loop_gain"):
					component.open_loop_gain = comp_data["properties"]["open_loop_gain"]
				if comp_data["properties"].has("equivalent_series_resistance"):
					component.equivalent_series_resistance = comp_data["properties"]["equivalent_series_resistance"]
				if comp_data["properties"].has("dc_resistance"):
					component.dc_resistance = comp_data["properties"]["dc_resistance"]
				if comp_data["properties"].has("lambda"):
					component.lambda = comp_data["properties"]["lambda"]
				if comp_data["properties"].has("input_resistance"):
					component.input_resistance = comp_data["properties"]["input_resistance"]
				if comp_data["properties"].has("output_resistance"):
					component.output_resistance = comp_data["properties"]["output_resistance"]
				
				circuit_graph.component_config_changed(component)
	
	# Load wires
	if save_data.has("wires"):
		for wire_info in save_data["wires"]:
			var start_component = component_map.get(wire_info["start_component"])
			var end_component = component_map.get(wire_info["end_component"])
			
			if start_component and end_component:
				var start_terminal = start_component.get_node_or_null(wire_info["start_terminal"])
				var end_terminal = end_component.get_node_or_null(wire_info["end_terminal"])
				
				if start_terminal and end_terminal and start_terminal is Area3D and end_terminal is Area3D:
					_create_wire(start_terminal, end_terminal)
	
	# Load ground connection
	if save_data.has("ground"):
		var ground_info = save_data["ground"]
		var ground_component = component_map.get(ground_info["component"])
		if ground_component:
			var ground_terminal = ground_component.get_node_or_null(ground_info["terminal"])
			if ground_terminal and ground_terminal is Area3D:
				circuit_graph.set_ground_node(ground_terminal)
	
	print("--- Circuit successfully loaded from: {p} ---".format({"p": file_path}))

## Clears the current circuit.
func _clear_circuit() -> void:
	# Remove all components
	for component in components_node.get_children():
		if component != null:
			component.queue_free()
	
	# Remove all wires
	for wire in wires_node.get_children():
		if wire != null:
			wire.queue_free()
	
	# Reset circuit graph
	circuit_graph.components.clear()
	circuit_graph.component_node_map.clear()
	circuit_graph.electrical_nodes.clear()
	circuit_graph.terminal_connections.clear()
	circuit_graph.ground_node_id = -1
	circuit_graph._next_node_id = 0
	circuit_graph._is_solved = false
	circuit_graph._needs_rebuild = true
	circuit_graph._cached_system = {}

## Gets the appropriate scene for a component type.
func _get_component_scene(type_name: String):
	match type_name:
		"Resistor3D":
			return ResistorScene
		"PowerSource3D":
			return PowerSourceScene
		"LED3D":
			return LEDScene
		"Switch3D":
			return SwitchScene
		"Diode3D":
			return DiodeScene
		"Potentiometer3D":
			return PotentiometerScene
		"Battery3D":
			return BatteryScene
		"PolarizedCapacitor3D":
			return PolarizedCapacitorScene
		"NonPolarizedCapacitor3D":
			return NonPolarizedCapacitorScene
		"Inductor3D":
			return InductorScene
		"NPNBJT3D":
			return NPNBJTScene
		"PNPBJT3D":
			return PNPBJTScene
		"ZenerDiode3D":
			return ZenerDiodeScene
		"NChannelMOSFET3D":
			return NChannelMOSFETScene
		"PChannelMOSFET3D":
			return PChannelMOSFETScene
		"Relay3D":
			return RelayScene
		"LinearRegulator3D":
			return LinearRegulatorScene
		"OpAmp3D":
			return OpAmpScene
		_:
			return null

## Generates a unique name for a component.
func _generate_unique_name(base_name: String) -> String:
	var existing_names = []
	for child in components_node.get_children():
		existing_names.append(child.name)
	
	var counter = 1
	var new_name = base_name + str(counter)
	while existing_names.has(new_name):
		counter += 1
		new_name = base_name + str(counter)
	
	return new_name

## Forces a full rebuild of the circuit graph based on the components and wires in the scene.
func _rebuild_graph_from_scene():
	var all_components = components_node.get_children()
	var all_wires = wires_node.get_children()
	var stored_ground_terminal = null
	if circuit_graph.ground_node_id != -1:
		if circuit_graph.electrical_nodes.has(circuit_graph.ground_node_id):
			var ground_node = circuit_graph.electrical_nodes[circuit_graph.ground_node_id]
			if not ground_node.terminals.is_empty():
				stored_ground_terminal = ground_node.terminals[0]

	# Reset graph
	circuit_graph.components.clear()
	circuit_graph.component_node_map.clear()
	circuit_graph.electrical_nodes.clear()
	circuit_graph.terminal_connections.clear()
	circuit_graph.ground_node_id = -1
	circuit_graph._next_node_id = 0

	# --- Invalidate MNA system cache ---
	circuit_graph._cached_system = {}
	
	# Re-add components
	for comp in all_components:
		if not comp is Wire3D:
			circuit_graph.add_component(comp)
	
	# Re-connect wires
	for wire in all_wires:
		if wire is Wire3D and is_instance_valid(wire.terminal_start) and is_instance_valid(wire.terminal_end):
			circuit_graph.connect_terminals(wire.terminal_start, wire.terminal_end)
	
	# Restore ground
	if is_instance_valid(stored_ground_terminal):
		circuit_graph.set_ground_node(stored_ground_terminal)
	
	circuit_graph._needs_rebuild = true
	_hide_voltage_displays()

## Callback for the "Display Voltages" button.
func _on_display_voltage_button_pressed():
	show_voltage_labels = display_voltage_button.button_pressed
	if show_voltage_labels:
		display_voltage_button.text = "Hide Voltages"
		if not circuit_graph._is_solved:
			_perform_simulation_step()
		else:
			_update_voltage_displays()
	else:
		display_voltage_button.text = "Display Voltages"
		_hide_voltage_displays()

## Callback for the "Save Circuit" button.
func _on_save_button_pressed():
	_show_save_slots(false)  # false for saving

## Callback for the "Load Circuit" button.
func _on_load_button_pressed():
	_show_save_slots(true)  # true for loading

## Shows the save slots UI.
func _show_save_slots(is_loading: bool) -> void:
	# Create a simple save slot selection dialog
	var dialog = ConfirmationDialog.new()
	dialog.title = "Select Save Slot"
	dialog.dialog_text = "Choose a save slot (1-4):"
	
	var vbox = VBoxContainer.new()
	
	for i in range(1, 5):
		var button = Button.new()
		button.text = "Slot " + str(i)
		button.connect("pressed", _on_save_slot_selected.bind(i, is_loading, dialog))
		vbox.add_child(button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.connect("pressed", func(): dialog.queue_free())
	vbox.add_child(cancel_button)
	
	dialog.add_child(vbox)
	dialog.size = Vector2(200, 200)
	add_child(dialog)
	dialog.popup_centered()

## Handles save slot selection.
func _on_save_slot_selected(slot: int, is_loading: bool, dialog: ConfirmationDialog) -> void:
	dialog.queue_free()
	
	if is_loading:
		_load_from_slot(slot)
	else:
		_save_to_slot(slot)

## Saves the current circuit to the specified slot.
func _save_to_slot(slot: int) -> void:
	var save_path = "user://circuit_save_" + str(slot) + ".save"
	save_circuit_to_file(save_path)
	
	# Show confirmation
	var confirmation = AcceptDialog.new()
	confirmation.dialog_text = "Circuit saved to slot " + str(slot)
	add_child(confirmation)
	confirmation.popup_centered()

## Loads a circuit from the specified slot.
func _load_from_slot(slot: int) -> void:
	var save_path = "user://circuit_save_" + str(slot) + ".save"
	if FileAccess.file_exists(save_path):
		load_circuit_from_file(save_path)
		
		# Show confirmation
		var confirmation = AcceptDialog.new()
		confirmation.dialog_text = "Circuit loaded from slot " + str(slot)
		add_child(confirmation)
		confirmation.popup_centered()
	else:
		# Show error
		var error_dialog = AcceptDialog.new()
		error_dialog.dialog_text = "No saved circuit in slot " + str(slot)
		add_child(error_dialog)
		error_dialog.popup_centered()

## Generic callback for any component configuration change.
func _on_any_component_config_changed(component_node: Node3D):
	circuit_graph.component_config_changed(component_node)
	_hide_voltage_displays()

## Callback for switch state changes.
func _on_switch_state_changed(switch_node: Node3D, _new_state: int):
	_on_any_component_config_changed(switch_node)

## Callback for potentiometer wiper changes.
func _on_potentiometer_component_wiper_changed(pot_node: Node3D, _new_position: float):
	_on_any_component_config_changed(pot_node)
	if selected_component == pot_node:
		var slider = property_container.find_child("HSlider", true, false)
		if slider and slider is HSlider:
			_is_updating_pot_slider_programmatically = true
			slider.value = _new_position
			_is_updating_pot_slider_programmatically = false

func _on_battery_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_polarized_capacitor_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_non_polarized_capacitor_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_inductor_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_npn_bjt_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_pnp_bjt_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_zener_diode_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_relay_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_n_channel_mosfet_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_p_channel_mosfet_config_changed(node: Node3D): _on_any_component_config_changed(node)
func _on_op_amp_config_changed(node: Node3D): _on_any_component_config_changed(node)

# --- Visual Update Functions ---

## Iterates through all components and updates their visual state based on simulation results.
func _update_component_visuals():
	if not circuit_graph._is_solved: return
	for comp_data in circuit_graph.components:
		var comp_node = comp_data.component_node
		if not is_instance_valid(comp_node): continue
		var results = circuit_graph.component_results.get(comp_node.get_instance_id(), {})

		# Always update visual state for components like LEDs (lit/unlit) regardless of labels
		if comp_node.has_method("update_visual_state") and comp_node is LED3D:
			comp_node.update_visual_state(results.get("current", NAN), comp_data.get("is_burned", false))

		if not show_voltage_labels:
			continue # Don't show any info/current labels if not requested

		if results.is_empty() and comp_node.has_method("reset_visual_state"):
			comp_node.reset_visual_state(); continue
		if comp_node.has_method("show_info"):
			if comp_node is PolarizedCapacitor3D: comp_node.show_info(results.get("current", NAN), results.get("voltage_across", NAN), results.get("is_exploded", false))
			elif comp_node is NonPolarizedCapacitor3D or comp_node is Inductor3D: comp_node.show_info(results.get("current", NAN), results.get("voltage_across", NAN))
			else: comp_node.show_info(results)
		elif comp_node.has_method("show_current"):
			if comp_node is PowerSource3D or comp_node is Battery3D: comp_node.show_current(results.get("current", NAN), results.get("voltage", NAN), results.get("operating_mode", "CV"))
			elif comp_node is Potentiometer3D: comp_node.show_current(results.get("current_T1_W", NAN), results.get("current_W_T2", NAN))
			else: comp_node.show_current(results.get("current", NAN))

## Shows voltage labels on all terminals.
func _update_voltage_displays():
	if not show_voltage_labels or not circuit_graph._is_solved: return
	for node_id in circuit_graph.electrical_nodes:
		var node_data = circuit_graph.electrical_nodes[node_id]
		var voltage = node_data.get("voltage", NAN)
		if not is_nan(voltage):
			for terminal in node_data.terminals:
				if is_instance_valid(terminal) and terminal is TerminalFeedback:
					terminal.show_voltage(voltage)

## Hides all voltage labels on terminals and info/current labels on components.
func _hide_voltage_displays():
	for comp_data in circuit_graph.components:
		# Hide terminal voltage labels
		for term_name in comp_data.terminals:
			var terminal = comp_data.terminals[term_name]
			if is_instance_valid(terminal) and terminal is TerminalFeedback and not terminal.is_selected:
				terminal.hide_voltage()
		
		# Hide component info/current labels
		var comp_node = comp_data.component_node
		if is_instance_valid(comp_node):
			if comp_node.has_method("hide_info"):
				comp_node.hide_info()
			if comp_node.has_method("hide_current"):
				comp_node.hide_current()
