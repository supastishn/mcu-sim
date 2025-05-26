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
var RelayScene = preload("res://components/Relay3D.tscn") 


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
@onready var add_resistor_button: Button = $UI/ComponentBar/ButtonList/AddResistorButton
@onready var add_power_source_button: Button = $UI/ComponentBar/ButtonList/AddPowerSourceButton
@onready var add_led_button: Button = $UI/ComponentBar/ButtonList/AddLEDButton
@onready var add_switch_button: Button = $UI/ComponentBar/ButtonList/AddSwitchButton
@onready var add_diode_button: Button = $UI/ComponentBar/ButtonList/AddDiodeButton
@onready var add_potentiometer_button: Button = $UI/ComponentBar/ButtonList/AddPotentiometerButton
@onready var add_battery_button: Button = $UI/ComponentBar/ButtonList/AddBatteryButton 
@onready var add_polarized_capacitor_button: Button = $UI/ComponentBar/ButtonList/AddCapacitorButton 
@onready var add_non_polarized_capacitor_button: Button = $UI/ComponentBar/ButtonList/AddNonPolarizedCapacitorButton 
@onready var add_inductor_button: Button = $UI/ComponentBar/ButtonList/AddInductorButton 
@onready var add_npn_bjt_button: Button = $UI/ComponentBar/ButtonList/AddNPNBJTButton 
@onready var add_pnp_bjt_button: Button = $UI/ComponentBar/ButtonList/AddPNPBJTButton 
@onready var add_zener_diode_button: Button = $UI/ComponentBar/ButtonList/AddZenerDiodeButton 
@onready var add_nchannelmosfet_button: Button = $UI/ComponentBar/ButtonList/AddNChannelMOSFETButton
@onready var add_relay_button: Button = $UI/ComponentBar/ButtonList/AddRelayButton 
@onready var simulate_button: Button = $UI/ComponentBar/ButtonList/SimulateButton
@onready var selection_bar: VBoxContainer = $UI/SelectionBar
@onready var value_box: HBoxContainer = $UI/SelectionBar/ValueBox 
@onready var value_label: Label = $UI/SelectionBar/ValueBox/ValueLabel
@onready var value_edit: LineEdit = $UI/SelectionBar/ValueBox/ValueEdit
@onready var zener_voltage_box: HBoxContainer = $UI/SelectionBar/ZenerVoltageBox 
@onready var zener_voltage_label: Label = $UI/SelectionBar/ZenerVoltageBox/ZenerVoltageLabel 
@onready var zener_voltage_edit: LineEdit = $UI/SelectionBar/ZenerVoltageBox/ZenerVoltageEdit 
@onready var current_limit_box: HBoxContainer = $UI/SelectionBar/CurrentLimitBox
@onready var current_limit_label: Label = $UI/SelectionBar/CurrentLimitBox/CurrentLimitLabel
@onready var current_limit_edit: LineEdit = $UI/SelectionBar/CurrentLimitBox/CurrentLimitEdit
@onready var max_voltage_box: HBoxContainer = $UI/SelectionBar/MaxVoltageBox 
@onready var max_voltage_label: Label = $UI/SelectionBar/MaxVoltageBox/MaxVoltageLabel 
@onready var max_voltage_edit: LineEdit = $UI/SelectionBar/MaxVoltageBox/MaxVoltageEdit 
@onready var vbe_on_box: HBoxContainer = $UI/SelectionBar/VbeOnBox 
@onready var vbe_on_label: Label = $UI/SelectionBar/VbeOnBox/VbeOnLabel 
@onready var vbe_on_edit: LineEdit = $UI/SelectionBar/VbeOnBox/VbeOnEdit 
@onready var coil_resistance_box: HBoxContainer = $UI/SelectionBar/CoilResistanceBox 
@onready var coil_resistance_label: Label = $UI/SelectionBar/CoilResistanceBox/CoilResistanceLabel
@onready var coil_resistance_edit: LineEdit = $UI/SelectionBar/CoilResistanceBox/CoilResistanceEdit
@onready var veb_on_box: HBoxContainer = $UI/SelectionBar/VebOnBox 
@onready var veb_on_label: Label = $UI/SelectionBar/VebOnBox/VebOnLabel 
@onready var veb_on_edit: LineEdit = $UI/SelectionBar/VebOnBox/VebOnEdit 



@onready var vec_sat_box: HBoxContainer = $UI/SelectionBar/VecSatBox 
@onready var vec_sat_label: Label = $UI/SelectionBar/VecSatBox/VecSatLabel
@onready var vec_sat_edit: LineEdit = $UI/SelectionBar/VecSatBox/VecSatEdit
@onready var MOSFETVtBox:    HBoxContainer = $UI/SelectionBar/MOSFETVtBox
@onready var MOSFETVtLabel:  Label         = $UI/SelectionBar/MOSFETVtBox/MOSFETVtLabel
@onready var MOSFETVtEdit:   LineEdit      = $UI/SelectionBar/MOSFETVtBox/MOSFETVtEdit
@onready var MOSFETKnBox:    HBoxContainer = $UI/SelectionBar/MOSFETKnBox
@onready var MOSFETKnLabel:  Label         = $UI/SelectionBar/MOSFETKnBox/MOSFETKnLabel
@onready var MOSFETKnEdit:   LineEdit      = $UI/SelectionBar/MOSFETKnBox/MOSFETKnEdit
@onready var battery_cell_box: HBoxContainer = $UI/SelectionBar/BatteryCellBox 
@onready var battery_cell_option: OptionButton = $UI/SelectionBar/BatteryCellBox/BatteryCellOption 
@onready var toggle_power_source_mode_button: Button = $UI/SelectionBar/TogglePowerSourceModeButton
@onready var toggle_switch_button: Button = $UI/SelectionBar/ToggleSwitchButton
@onready var potentiometer_wiper_slider: HSlider = $UI/SelectionBar/PotentiometerWiperSlider


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

	
	
	add_resistor_button.pressed.connect(_on_add_component_button_pressed.bind(ResistorScene))
	add_power_source_button.pressed.connect(_on_add_component_button_pressed.bind(PowerSourceScene))
	add_led_button.pressed.connect(_on_add_component_button_pressed.bind(LEDScene))
	add_switch_button.pressed.connect(_on_add_component_button_pressed.bind(SwitchScene))
	add_diode_button.pressed.connect(_on_add_component_button_pressed.bind(DiodeScene))
	add_potentiometer_button.pressed.connect(_on_add_component_button_pressed.bind(PotentiometerScene))
	add_battery_button.pressed.connect(_on_add_component_button_pressed.bind(BatteryScene)) 
	add_polarized_capacitor_button.pressed.connect(_on_add_component_button_pressed.bind(PolarizedCapacitorScene)) 
	add_non_polarized_capacitor_button.pressed.connect(_on_add_component_button_pressed.bind(NonPolarizedCapacitorScene)) 
	add_inductor_button.pressed.connect(_on_add_component_button_pressed.bind(InductorScene)) 
	add_npn_bjt_button.pressed.connect(_on_add_component_button_pressed.bind(NPNBJTScene)) 
	add_pnp_bjt_button.pressed.connect(_on_add_component_button_pressed.bind(PNPBJTScene)) 
	add_zener_diode_button.pressed.connect(_on_add_component_button_pressed.bind(ZenerDiodeScene)) 
	add_nchannelmosfet_button.pressed.connect(_on_add_component_button_pressed.bind(NChannelMOSFETScene))
	add_relay_button.pressed.connect(_on_add_component_button_pressed.bind(RelayScene)) 
	simulate_button.pressed.connect(_on_simulate_button_pressed)
	
	toggle_switch_button.pressed.connect(_on_toggle_switch_button_pressed)
	potentiometer_wiper_slider.value_changed.connect(_on_potentiometer_wiper_slider_value_changed)
	current_limit_edit.text_submitted.connect(_on_current_limit_value_changed)
	max_voltage_edit.text_submitted.connect(_on_max_voltage_value_changed) 
	vbe_on_edit.text_submitted.connect(_on_vbe_on_value_changed) 
	battery_cell_option.item_selected.connect(_on_battery_cell_option_selected) 
	selection_bar.get_node("DeleteButton").pressed.connect(_on_delete_button_pressed)
	value_edit.text_submitted.connect(_on_selected_value_changed) 
	zener_voltage_edit.text_submitted.connect(_on_zener_voltage_value_changed) 
	coil_resistance_edit.text_submitted.connect(_on_coil_resistance_value_changed) 
	veb_on_edit.text_submitted.connect(_on_veb_on_value_changed) 
	vec_sat_edit.text_submitted.connect(_on_vec_sat_value_changed) 
	
	
	_deselect_component()
	_hide_voltage_displays() 

	
	display_voltage_button = Button.new()
	display_voltage_button.text = "Display Voltage Labels"
	display_voltage_button.toggle_mode = true
	display_voltage_button.button_pressed = false 
	ui_layer.get_node("ComponentBar/ButtonList").add_child(display_voltage_button)
	display_voltage_button.pressed.connect(_on_display_voltage_button_pressed)

	show_voltage_labels = false 

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
		
		
	return component_instance 
	

func _reset_wiring_state():
	if current_wire_state == WireState.START_SELECTED and is_instance_valid(first_selected_terminal):
		print("Wiring state reset (cancelled or completed).")
		
		if first_selected_terminal is TerminalFeedback:
			first_selected_terminal.deselect()
	current_wire_state = WireState.IDLE
	_hide_voltage_displays() 
	first_selected_terminal = null



func _select_component(component: Node3D):
	if component == selected_component:
		
		
		if not (component is PowerSource3D):
			print("Component {comp_name} already selected (and not PowerSource); no UI refresh needed.".format({"comp_name": component.name}))
			return
		
		
		print("Refreshing UI for already selected PowerSource {comp_name}".format({"comp_name": component.name}))
	else:
		
		
		if selected_component != null: 
			_deselect_component() 
		selected_component = component 
		print("Selecting new component: {comp_name}".format({"comp_name": component.name}))

	
	
	selection_bar.visible = true
	value_edit.editable = true 
	value_box.visible = false 
	zener_voltage_box.visible = false 
	current_limit_box.visible = false 
	max_voltage_box.visible = false 
	vbe_on_box.visible = false 
	veb_on_box.visible = false 
	
	coil_resistance_box.visible = false 
	vec_sat_box.visible = false 
	battery_cell_box.visible = false 
	toggle_power_source_mode_button.visible = false 
	toggle_switch_button.visible = false 
	potentiometer_wiper_slider.visible = false 

	
	if selected_component is Resistor3D:
		value_box.visible = true
		value_label.text = "Resistance (Ω):"
		value_edit.text = str(selected_component.resistance)
		
	elif selected_component is PowerSource3D:
		value_box.visible = true
		value_label.text = "Target Voltage (V):"
		value_edit.text = str(selected_component.target_voltage)
		
		current_limit_box.visible = true
		current_limit_label.text = "Current Limit (A):"
		current_limit_edit.text = str(selected_component.target_current)
		
		
	elif selected_component is Battery3D:
		value_box.visible = true 
		value_label.text = "Voltage (V):"
		value_edit.text = str(selected_component.target_voltage)
		value_edit.editable = false 
		
		battery_cell_box.visible = true
		
		battery_cell_option.select(selected_component.num_cells - 1) 
		
	elif selected_component is LED3D:
		value_box.visible = true
		value_label.text = "Fwd Voltage (V):"
		value_edit.text = str(selected_component.forward_voltage)
		
	elif selected_component is Diode3D:
		value_box.visible = true
		value_label.text = "Fwd Voltage (V):"
		value_edit.text = str(selected_component.forward_voltage)
		
	elif selected_component is ZenerDiode3D:
		value_box.visible = true
		value_label.text = "Fwd Voltage (Vf):"
		value_edit.text = str(selected_component.forward_voltage)
		zener_voltage_box.visible = true
		zener_voltage_label.text = "Zener Voltage (Vz):"
		zener_voltage_edit.text = str(selected_component.zener_voltage)
		
	elif selected_component is Switch3D:
		value_box.visible = false 
		toggle_switch_button.visible = true
		toggle_switch_button.text = "Turn Off" if selected_component.current_state == Switch3D.State.CONNECTED_NO else "Turn On"
		
	elif selected_component is Potentiometer3D:
		value_box.visible = true
		value_label.text = "Total R (Ω):"
		value_edit.text = str(selected_component.total_resistance)
		potentiometer_wiper_slider.visible = true
		
		_is_updating_pot_slider_programmatically = true
		potentiometer_wiper_slider.value = selected_component.wiper_position
		_is_updating_pot_slider_programmatically = false
		
	elif selected_component is Wire3D:
		value_box.visible = false 
		
	elif selected_component is PolarizedCapacitor3D:
		value_box.visible = true
		value_label.text = "Capacitance (F):"
		value_edit.text = str(selected_component.capacitance)
		
		max_voltage_box.visible = true
		max_voltage_label.text = "Max Voltage (V):"
		max_voltage_edit.text = str(selected_component.max_voltage)
		
	elif selected_component is NonPolarizedCapacitor3D:
		value_box.visible = true
		value_label.text = "Capacitance (F):"
		value_edit.text = str(selected_component.capacitance)
		
		max_voltage_box.visible = true
		max_voltage_label.text = "Max Voltage (V):"
		max_voltage_edit.text = str(selected_component.max_voltage)
		
	elif selected_component is Inductor3D:
		value_box.visible = true
		value_label.text = "Inductance (H):"
		value_edit.text = str(selected_component.inductance)
		
	elif selected_component is NPNBJT3D:
		value_box.visible = true 
		value_label.text = "Beta (Hfe):"
		value_edit.text = str(selected_component.beta_dc)
		
		vbe_on_box.visible = true 
		vbe_on_label.text = "Vbe On (V):" 
		vbe_on_edit.text = str(selected_component.vbe_on) 
		
		
	elif selected_component is PNPBJT3D:
		value_box.visible = true 
		value_label.text = "Beta (Hfe):"
		value_edit.text = str(selected_component.beta_dc)
		
		veb_on_box.visible = true 
		veb_on_label.text = "Veb On (V):" 
		veb_on_edit.text = str(selected_component.veb_on)
		
		vec_sat_box.visible = true 
		vec_sat_label.text = "Vec Sat (V):"
		vec_sat_edit.text = str(selected_component.vec_sat)
		
	
	elif selected_component is NChannelMOSFET3D:
		value_box.visible   = false
		MOSFETVtBox.visible = true
		MOSFETVtLabel.text  = "Vt (V):"
		MOSFETVtEdit.text   = str(selected_component.threshold_voltage)
		MOSFETKnBox.visible = true
		MOSFETKnLabel.text  = "Kn (A/V²):"
		MOSFETKnEdit.text   = str(selected_component.transconductance_parameter)
		
	elif selected_component is Relay3D:
		value_box.visible = true
		value_label.text = "Coil Threshold (V):"
		value_edit.text = str(selected_component.coil_voltage_threshold)
		coil_resistance_box.visible = true
		coil_resistance_label.text = "Coil Resist. (Ω):"
		coil_resistance_edit.text = str(selected_component.coil_resistance)
		
	else:
		value_box.visible = false 
		printerr("Selected node {comp_name} is not a recognized component type for editing.".format({"comp_name": component.name}))

	
	
	selection_bar.get_node("DeleteButton").visible = true


func _deselect_component():
	if selected_component:
		print("Deselecting component: {sel_comp_name}".format({"sel_comp_name": selected_component.name}))
		
		value_edit.editable = true 
		
		if selected_component is Resistor3D:
			pass 
		elif selected_component is PowerSource3D:
			pass 
		elif selected_component is Battery3D: 
			pass 
		elif selected_component is LED3D:
			pass 
		elif selected_component is Diode3D:
			pass 
		elif selected_component is Switch3D:
			pass 
		elif selected_component is Wire3D:
			pass 
		elif selected_component is PolarizedCapacitor3D:
			pass 
		elif selected_component is NonPolarizedCapacitor3D:
			pass 
		elif selected_component is Inductor3D:
			pass 
		elif selected_component is NPNBJT3D: 
			pass 
		elif selected_component is PNPBJT3D: 
			pass 
		elif selected_component is ZenerDiode3D:
			pass 
		elif selected_component is Relay3D:
			pass 

	selected_component = null
	print("!!! _deselect_component: selected_component set to null !!!") 
	selection_bar.visible = false
	value_box.visible = false
	zener_voltage_box.visible = false 
	current_limit_box.visible = false
	max_voltage_box.visible = false 
	vbe_on_box.visible = false 
	veb_on_box.visible = false 
	
	coil_resistance_box.visible = false 
	vec_sat_box.visible = false 
	battery_cell_box.visible = false 
	toggle_power_source_mode_button.visible = false
	toggle_switch_button.visible = false
	potentiometer_wiper_slider.visible = false
	
	_potential_drag_target = null
	
	value_edit.text = ""
	current_limit_edit.text = ""
	
	selection_bar.get_node("DeleteButton").visible = false





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



func _on_selected_value_changed(new_text: String):
	if not selected_component: return

	_hide_voltage_displays() 
	
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid value entered: '{txt}'. Reverting.".format({"txt": new_text}))
		
		if selected_component is Resistor3D:
			value_edit.text = str(selected_component.resistance)
		elif selected_component is PowerSource3D:
			
			value_edit.text = str(selected_component.target_voltage)
		elif selected_component is LED3D:
			value_edit.text = str(selected_component.forward_voltage)
		elif selected_component is ZenerDiode3D: 
			value_edit.text = str(selected_component.forward_voltage)
			zener_voltage_edit.text = str(selected_component.zener_voltage) 
		elif selected_component is Diode3D:
			value_edit.text = str(selected_component.forward_voltage)
		elif selected_component is Potentiometer3D:
			value_edit.text = str(selected_component.total_resistance)
		elif selected_component is PolarizedCapacitor3D:
			value_edit.text = str(selected_component.capacitance) 
			max_voltage_edit.text = str(selected_component.max_voltage) 
		elif selected_component is NonPolarizedCapacitor3D:
			value_edit.text = str(selected_component.capacitance) 
			max_voltage_edit.text = str(selected_component.max_voltage) 
		elif selected_component is Inductor3D:
			value_edit.text = str(selected_component.inductance)
		elif selected_component is NPNBJT3D: 
			value_edit.text = str(selected_component.beta_dc)
		elif selected_component is PNPBJT3D: 
			value_edit.text = str(selected_component.beta_dc)
		elif selected_component is Relay3D: 
			value_edit.text = str(selected_component.coil_voltage_threshold)
			coil_resistance_edit.text = str(selected_component.coil_resistance) 
		
		else:
			value_edit.text = "" 
		return

	
	print("Updating {sel_comp_name} value (via primary ValueEdit) to {val}".format({"sel_comp_name": selected_component.name, "val": new_value}))
	if selected_component is Resistor3D:
		selected_component.resistance = new_value
	elif selected_component is PowerSource3D:
		
		selected_component.target_voltage = new_value
	elif selected_component is LED3D:
		selected_component.forward_voltage = new_value
		
		
	elif selected_component is ZenerDiode3D: 
		selected_component.forward_voltage = new_value 
	elif selected_component is Diode3D:
		selected_component.forward_voltage = new_value
	elif selected_component is Potentiometer3D:
		selected_component.total_resistance = new_value
	elif selected_component is PolarizedCapacitor3D:
		
		selected_component.capacitance = new_value 
	elif selected_component is Inductor3D:
		selected_component.inductance = new_value 
	elif selected_component is NPNBJT3D: 
		selected_component.beta_dc = new_value 
	elif selected_component is PNPBJT3D: 
		selected_component.beta_dc = new_value 
	elif selected_component is Relay3D: 
		selected_component.coil_voltage_threshold = new_value 
	
	
	
	
	
	
	
	if selected_component:
		if selected_component is PolarizedCapacitor3D or selected_component is NonPolarizedCapacitor3D:
			
			
			
			
			
			pass
		elif selected_component is Inductor3D:
			
			pass
		elif selected_component is NPNBJT3D or selected_component is PNPBJT3D:
			
			pass
		elif selected_component is ZenerDiode3D:
			
			pass
		elif selected_component is Relay3D:
			
			pass
		else:
			
			
			circuit_graph.component_config_changed(selected_component)

func _on_delete_button_pressed():
	print("!!! _on_delete_button_pressed: Entered. selected_component is: {sel_comp}".format({"sel_comp": selected_component})) 
	if not selected_component:
		_hide_voltage_displays() 
		print("Delete button pressed, but nothing selected.")
		return

	print("Delete button pressed for: {sel_comp_name}".format({"sel_comp_name": selected_component.name}))

	if selected_component is Wire3D:
		
		_hide_voltage_displays() 
		var wire_to_delete = selected_component 
		_deselect_component() 
		wire_to_delete.queue_free()
		print("  Deleted Wire node.")
	elif selected_component is Switch3D or \
		 selected_component is Resistor3D or \
		 selected_component is PowerSource3D or \
		 selected_component is LED3D or \
		 selected_component is Diode3D or \
		 selected_component is Potentiometer3D or \
		 selected_component is Battery3D or \
		 selected_component is PolarizedCapacitor3D or \
		 selected_component is NonPolarizedCapacitor3D or \
		 selected_component is Inductor3D or \
		 selected_component is NPNBJT3D or \
		 selected_component is PNPBJT3D or \
		 selected_component is ZenerDiode3D or \
		 selected_component is NChannelMOSFET3D or \
		 selected_component is Relay3D:
		var component_to_delete = selected_component 
		var terminals_to_check = []
		if component_to_delete is Resistor3D:
			terminals_to_check = [component_to_delete.terminal1, component_to_delete.terminal2]
		elif component_to_delete is PowerSource3D:
			terminals_to_check = [component_to_delete.terminal_pos, component_to_delete.terminal_neg]
		elif component_to_delete is Battery3D: 
			terminals_to_check = [component_to_delete.terminal_pos, component_to_delete.terminal_neg]
		elif component_to_delete is LED3D:
			terminals_to_check = [component_to_delete.terminal_anode, component_to_delete.terminal_kathode]
		elif component_to_delete is Diode3D:
			terminals_to_check = [component_to_delete.terminal_anode, component_to_delete.terminal_kathode]
		elif component_to_delete is ZenerDiode3D:
			terminals_to_check = [component_to_delete.terminal_anode, component_to_delete.terminal_kathode]
		elif component_to_delete is Switch3D:
			terminals_to_check = [component_to_delete.terminal_com, component_to_delete.terminal_nc, component_to_delete.terminal_no]
		elif component_to_delete is Potentiometer3D:
			terminals_to_check = [component_to_delete.terminal1, component_to_delete.terminal2, component_to_delete.terminal_wiper]
		elif component_to_delete is PolarizedCapacitor3D:
			terminals_to_check = [component_to_delete.terminal1, component_to_delete.terminal2]
		elif component_to_delete is NonPolarizedCapacitor3D:
			terminals_to_check = [component_to_delete.terminal1, component_to_delete.terminal2]
		elif component_to_delete is Inductor3D:
			terminals_to_check = [component_to_delete.terminal1, component_to_delete.terminal2]
		elif component_to_delete is NPNBJT3D:
			terminals_to_check = [component_to_delete.terminal_c, component_to_delete.terminal_b, component_to_delete.terminal_e]
		elif component_to_delete is PNPBJT3D:
			terminals_to_check = [component_to_delete.terminal_e, component_to_delete.terminal_b, component_to_delete.terminal_c] 
		elif component_to_delete is NChannelMOSFET3D:
			terminals_to_check = [
				component_to_delete.terminal_d,
				component_to_delete.terminal_g,
				component_to_delete.terminal_s
			]
		elif component_to_delete is Relay3D:
			terminals_to_check = [
				component_to_delete.terminal_coil_p, component_to_delete.terminal_coil_n,
				component_to_delete.terminal_com, component_to_delete.terminal_no, component_to_delete.terminal_nc
			]

		
		for wire_node in wires_node.get_children():
			if wire_node is Wire3D:
				if wire_node.terminal_start in terminals_to_check or wire_node.terminal_end in terminals_to_check:
					print("  Deleting connected wire: {wire_name}".format({"wire_name": wire_node.name}))
					wire_node.queue_free()

		
		_hide_voltage_displays() 
		circuit_graph.remove_component(component_to_delete)
		_deselect_component() 
		component_to_delete.queue_free()
		print("  Deleted component node and associated wires.")
	else:
		_hide_voltage_displays() 
		printerr("Delete requested for unknown selected object type.")
		_deselect_component() 




func _update_voltage_displays():
	
	
	
	
	if not show_voltage_labels: 
		_hide_voltage_displays(false) 
		
		for component_node in components_node.get_children():
			if component_node.has_method("hide_current"):
				component_node.hide_current()
			if component_node.has_method("hide_info"): 
				component_node.hide_info()

		
		for comp_data_graph in circuit_graph.components:
			var c_node_graph = comp_data_graph.component_node
			if is_instance_valid(c_node_graph) and not c_node_graph in components_node.get_children():
				if c_node_graph.has_method("hide_current"):
					c_node_graph.hide_current()
				if c_node_graph.has_method("hide_info"): 
					c_node_graph.hide_info()
		return

	print("Updating voltage and current displays...")
	if not circuit_graph._is_solved:
		print("  Circuit not solved, hiding terminal displays.")
		
		_hide_voltage_displays(false) 
		return

	for node_id in circuit_graph.electrical_nodes:
		var voltage = circuit_graph.electrical_nodes[node_id].voltage
		if is_nan(voltage): continue 

		for terminal_area in circuit_graph.electrical_nodes[node_id].terminals:
			if is_instance_valid(terminal_area) and terminal_area is TerminalFeedback:
				terminal_area.show_voltage(voltage)
	
	
	for comp_data in circuit_graph.components:
		if not is_instance_valid(comp_data.component_node):
			printerr("CircuitEditor: Found component_data with invalid component_node during current display.")
			continue
			
		var component_node = comp_data.component_node
		var comp_id = component_node.get_instance_id()
		var results = circuit_graph.component_results.get(comp_id, {})
		
		if component_node.has_method("show_info") and comp_data.type == "PolarizedCapacitor":
			var cap_current = results.get("current", NAN)
			var cap_voltage = results.get("voltage_across", NAN)
			var cap_exploded = results.get("is_exploded", false) 
			component_node.show_info(cap_current, cap_voltage, cap_exploded)
		elif component_node.has_method("show_info") and comp_data.type == "NonPolarizedCapacitor":
			var np_cap_current = results.get("current", NAN)
			var np_cap_voltage = results.get("voltage_across", NAN)
			
			component_node.show_info(np_cap_current, np_cap_voltage) 
		elif component_node.has_method("show_info") and comp_data.type == "Inductor":
			var ind_current = results.get("current", NAN)
			var ind_voltage = results.get("voltage_across", NAN)
			component_node.show_info(ind_current, ind_voltage)
		elif component_node.has_method("show_info") and \
			(comp_data.type == "NPNBJT" or comp_data.type == "PNPBJT" or comp_data.type == "ZenerDiode" or comp_data.type == "Relay"):
			
			var info_results_dict = {}
			if comp_data.type == "NPNBJT" or comp_data.type == "PNPBJT":
				info_results_dict = {
					"Ic": results.get("Ic", NAN),
					"Ib": results.get("Ib", NAN),
					"Ie": results.get("Ie", NAN),
					"region": results.get("region", "N/A")
				}
			elif comp_data.type == "ZenerDiode":
				info_results_dict = {
					"current": results.get("current", NAN), 
					"voltage_ak": results.get("voltage_ak", NAN), 
					"state": results.get("state", "N/A")
				}
			elif comp_data.type == "Relay":
				info_results_dict = {
					"coil_voltage": results.get("coil_voltage", NAN),
					"is_energized": results.get("is_energized", false),
					"coil_threshold": comp_data.properties.get("coil_voltage_threshold", NAN), 
					"coil_current": results.get("coil_current", NAN) 
				}
			component_node.show_info(info_results_dict)
		elif component_node.has_method("show_current"): 
			if comp_data.type == "Potentiometer":
				var current1_w = results.get("current_T1_W", NAN)
				var current_w_t2 = results.get("current_W_T2", NAN)
				component_node.show_current(current1_w, current_w_t2)
			elif comp_data.type == "PowerSource": 
				var actual_current_ps = results.get("current", NAN)
				var actual_voltage_ps = results.get("voltage", NAN)
				var op_mode_ps = results.get("operating_mode", "CV") 
				component_node.show_current(actual_current_ps, actual_voltage_ps, op_mode_ps)
			elif comp_data.type == "Battery": 
				var actual_current_bat = results.get("current", NAN)
				var actual_voltage_bat = results.get("voltage", NAN) 
				component_node.show_current(actual_current_bat, actual_voltage_bat)
			else: 
				var current_val = results.get("current", NAN)
				component_node.show_current(current_val)
		




func _update_led_states():
	print("Updating LED states...")
	for comp_data in circuit_graph.components:
		if comp_data.type == "LED" and is_instance_valid(comp_data.component_node):
			var led_node: LED3D = comp_data.component_node
			var comp_id = led_node.get_instance_id()
			
			var current: float = circuit_graph.component_results.get(comp_id, {}).get("current", 0.0)
			if is_nan(current): current = 0.0 
			
			var is_logically_burned: bool = comp_data.get("is_burned", false)
			
			led_node.update_visual_state(current, is_logically_burned)
		elif comp_data.type == "LED" and not is_instance_valid(comp_data.component_node):
			printerr("CircuitEditor: Found LED component_data with invalid component_node during _update_led_states.")



func _hide_voltage_displays(leds: bool = true):
	
	
	for component_node in components_node.get_children(): 
		
		for child in component_node.get_children():
			if child is TerminalFeedback:
				child.hide_voltage()
		
		
		if component_node.has_method("hide_current"):
			component_node.hide_current()
		if component_node.has_method("hide_info"): 
			component_node.hide_info()
		if component_node is PolarizedCapacitor3D and leds: 
			component_node.reset_visual_state() 
		if component_node is NonPolarizedCapacitor3D and leds:
			component_node.reset_visual_state()
		if component_node is Inductor3D and leds: 
			component_node.reset_visual_state()
		if component_node is NPNBJT3D and leds: 
			component_node.reset_visual_state()
		if component_node is PNPBJT3D and leds: 
			component_node.reset_visual_state()
		if component_node is ZenerDiode3D and leds: 
			component_node.reset_visual_state()
		if component_node is Relay3D and leds: 
			component_node.reset_visual_state()
			
		
		if component_node is LED3D and leds: 
			component_node.reset_visual_state()
	
	
	
	
	for comp_data_graph in circuit_graph.components:
		var c_node = comp_data_graph.component_node
		if is_instance_valid(c_node) and not c_node in components_node.get_children():
			
			if c_node.has_method("hide_current"):
				c_node.hide_current()
			if c_node.has_method("hide_info"): 
				c_node.hide_info()
			if leds and c_node is PolarizedCapacitor3D: 
				c_node.reset_visual_state()
			if leds and c_node is NonPolarizedCapacitor3D:
				c_node.reset_visual_state()
			if leds and c_node is Inductor3D: 
				c_node.reset_visual_state()
			if leds and c_node is NPNBJT3D: 
				c_node.reset_visual_state()
			if leds and c_node is PNPBJT3D: 
				c_node.reset_visual_state()
			if leds and c_node is ZenerDiode3D: 
				c_node.reset_visual_state()
			if leds and c_node is Relay3D: 
				c_node.reset_visual_state()
			
			if leds and c_node is LED3D:
				c_node.reset_visual_state()

func _on_potentiometer_wiper_slider_value_changed(value: float):
	if _is_updating_pot_slider_programmatically:
		return 

	if selected_component is Potentiometer3D:
		print("Potentiometer UI Slider changed to: {val_str}".format({"val_str": String.num(value, 2)}))
		selected_component.set_wiper_position(value) 
		
		
		_hide_voltage_displays() 

func _on_potentiometer_component_wiper_changed(component_node: Potentiometer3D, new_position: float):
	print("CircuitEditor notified of Potentiometer {comp_name} wiper change to: {pos_str}".format({"comp_name": component_node.name, "pos_str": String.num(new_position, 2)}))
	
	
	circuit_graph.component_config_changed(component_node)
	_hide_voltage_displays(true) 

func _on_display_voltage_button_pressed():
	
	
	show_voltage_labels = display_voltage_button.is_pressed() 

	if show_voltage_labels:
		display_voltage_button.text = "Hide Voltage Labels"
		
		
		if circuit_graph._is_solved:
			_update_voltage_displays() 
	else:
		display_voltage_button.text = "Display Voltage Labels"
		
		_hide_voltage_displays(false) 

func _on_move_joystick_updated(direction: Vector2, intensity: float):
	move_vector = direction
	move_intensity = intensity

func _on_move_joystick_released():
	move_vector = Vector2.ZERO
	move_intensity = 0.0

func _on_look_joystick_updated(direction: Vector2, intensity: float):
	look_vector = direction
	look_intensity = intensity

func _on_look_joystick_released():
	look_vector = Vector2.ZERO
	look_intensity = 0.0

func _on_current_limit_value_changed(new_text: String):
	if not selected_component or not selected_component is PowerSource3D: return

	_hide_voltage_displays() 
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
		if new_value < 0: new_value = 0.0 
	else:
		print("Invalid current limit entered: '{txt}'. Reverting.".format({"txt": new_text}))
		current_limit_edit.text = str(selected_component.target_current)
		return

	print("Updating {sel_comp_name} target_current to {val}".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.target_current = new_value
	circuit_graph.component_config_changed(selected_component)

func _on_max_voltage_value_changed(new_text: String):
	if not selected_component or not (selected_component is PolarizedCapacitor3D or selected_component is NonPolarizedCapacitor3D): return

	_hide_voltage_displays(true) 
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid max voltage entered: '{txt}'. Reverting.".format({"txt": new_text}))
		max_voltage_edit.text = str(selected_component.max_voltage)
		return

	print("Updating {sel_comp_name} max_voltage to {val}V".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.max_voltage = new_value 
	

func _on_vbe_on_value_changed(new_text: String):
	if not selected_component or not selected_component is NPNBJT3D: return

	_hide_voltage_displays(true) 
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid Vbe_on entered: '{txt}'. Reverting.".format({"txt": new_text}))
		vbe_on_edit.text = str(selected_component.vbe_on) 
		return

	print("Updating {sel_comp_name} vbe_on to {val}V".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.vbe_on = new_value 

func _on_zener_voltage_value_changed(new_text: String):
	if not selected_component or not selected_component is ZenerDiode3D: return

	_hide_voltage_displays(true)
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid Zener voltage entered: '{txt}'. Reverting.".format({"txt": new_text}))
		zener_voltage_edit.text = str(selected_component.zener_voltage)
		return
	print("Updating {sel_comp_name} zener_voltage to {val}V".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.zener_voltage = new_value 

func _on_veb_on_value_changed(new_text: String): 
	if not selected_component or not selected_component is PNPBJT3D: return

	_hide_voltage_displays(true)
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid Veb_on entered: '{txt}'. Reverting.".format({"txt": new_text}))
		veb_on_edit.text = str(selected_component.veb_on)
		return
	print("Updating {sel_comp_name} veb_on to {val}V".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.veb_on = new_value 

func _on_coil_resistance_value_changed(new_text: String): 
	if not selected_component or not selected_component is Relay3D: return

	_hide_voltage_displays(true)
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid coil resistance entered: '{txt}'. Reverting.".format({"txt": new_text}))
		coil_resistance_edit.text = str(selected_component.coil_resistance)
		return
	print("Updating {sel_comp_name} coil_resistance to {val}Ω".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.coil_resistance = new_value 


	

func _on_vec_sat_value_changed(new_text: String): 
	if not selected_component or not selected_component is PNPBJT3D: return

	_hide_voltage_displays(true)
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid Vec_sat entered: '{txt}'. Reverting.".format({"txt": new_text}))
		vec_sat_edit.text = str(selected_component.vec_sat)
		return
	print("Updating {sel_comp_name} vec_sat to {val}V".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.vec_sat = new_value 



func _on_non_polarized_capacitor_config_changed(capacitor_node: NonPolarizedCapacitor3D):
	print("CircuitEditor notified of NonPolarizedCapacitor {cap_name} config change. New C: {cap_str}F, MaxV: {max_v_str}V".format({"cap_name": capacitor_node.name, "cap_str": String.num_scientific(capacitor_node.capacitance), "max_v_str": String.num(capacitor_node.max_voltage, 2)}))
	circuit_graph.component_config_changed(capacitor_node)
	_hide_voltage_displays(true) 

func _on_battery_cell_option_selected(index: int):
	if selected_component is Battery3D:
		var num_cells_selected = index + 1 
		print("Battery UI cell option selected: {num_cells} cells".format({"num_cells": num_cells_selected}))
		selected_component.set_num_cells(num_cells_selected) 
		
		value_edit.text = str(selected_component.target_voltage) 
		_hide_voltage_displays() 
	
	

func _on_battery_config_changed(battery_node: Battery3D):
	print("CircuitEditor notified of Battery {batt_name} config change. New voltage: {volt_str}V".format({"batt_name": battery_node.name, "volt_str": String.num(battery_node.target_voltage, 2)}))
	circuit_graph.component_config_changed(battery_node)
	_hide_voltage_displays(true) 

func _on_polarized_capacitor_config_changed(capacitor_node: PolarizedCapacitor3D):
	print("CircuitEditor notified of PolarizedCapacitor {cap_name} config change. New C: {cap_str}F, MaxV: {max_v_str}V".format({"cap_name": capacitor_node.name, "cap_str": String.num_scientific(capacitor_node.capacitance), "max_v_str": String.num(capacitor_node.max_voltage, 2)}))
	circuit_graph.component_config_changed(capacitor_node) 
	_hide_voltage_displays(true) 

func _on_inductor_config_changed(inductor_node: Inductor3D):
	print("CircuitEditor notified of Inductor {ind_name} config change. New L: {l_str}H".format({"ind_name": inductor_node.name, "l_str": String.num_scientific(inductor_node.inductance)}))
	circuit_graph.component_config_changed(inductor_node)
	_hide_voltage_displays(true) 

func _on_npn_bjt_config_changed(bjt_node: NPNBJT3D):
	print("CircuitEditor notified of NPNBJT {bjt_name} config change. Beta: {beta_val}, Vbe_on: {vbe_val}V, Vce_sat: {vce_val}V".format({
		"bjt_name": bjt_node.name, 
		"beta_val": String.num(bjt_node.beta_dc, 1),
		"vbe_val": String.num(bjt_node.vbe_on, 2),
		"vce_val": String.num(bjt_node.vce_sat, 2)
		}))
	circuit_graph.component_config_changed(bjt_node)
	_hide_voltage_displays(true) 

func _on_pnp_bjt_config_changed(bjt_node: PNPBJT3D):
	print("CircuitEditor notified of PNPBJT {bjt_name} config change. Beta: {beta_val}, Veb_on: {veb_val}V, Vec_sat: {vec_val}V".format({
		"bjt_name": bjt_node.name, 
		"beta_val": String.num(bjt_node.beta_dc, 1),
		"veb_val": String.num(bjt_node.veb_on, 2), 
		"vec_val": String.num(bjt_node.vec_sat, 2)  
		}))
	circuit_graph.component_config_changed(bjt_node)
	_hide_voltage_displays(true) 

func _on_zener_diode_config_changed(zener_node: ZenerDiode3D):
	print("CircuitEditor notified of ZenerDiode {name} config change. Vf: {vf_str}V, Vz: {vz_str}V".format({
		"name": zener_node.name, 
		"vf_str": String.num(zener_node.forward_voltage, 2),
		"vz_str": String.num(zener_node.zener_voltage, 2)
		}))
	circuit_graph.component_config_changed(zener_node)
	_hide_voltage_displays(true)

func _on_relay_config_changed(relay_node: Relay3D):
	print("CircuitEditor notified of Relay {name} config change. Threshold: {thresh_str}V, CoilR: {coilr_str}Ω".format({
		"name": relay_node.name,
		"thresh_str": String.num(relay_node.coil_voltage_threshold, 2),
		"coilr_str": String.num(relay_node.coil_resistance, 1)
		}))
	circuit_graph.component_config_changed(relay_node)
	_hide_voltage_displays(true)



















func _on_switch_state_changed(switch_node: Node3D, new_state: int):
	
	print("CircuitEditor notified of switch state change to: {state_key}".format({"state_key": Switch3D.State.keys()[new_state]}))
	
	circuit_graph.component_config_changed(switch_node) 
	_hide_voltage_displays()

func _on_toggle_switch_button_pressed():
	if selected_component is Switch3D:
		var switch_node: Switch3D = selected_component
		
		switch_node.toggle_state() 
		
		toggle_switch_button.text = "Turn Off" if switch_node.current_state == Switch3D.State.CONNECTED_NO else "Turn On"
