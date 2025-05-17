extends Node3D
class_name CircuitEditor3D
const TERMINAL_COLLISION_LAYER = 2
const COMPONENT_BODY_COLLISION_LAYER = 4
const WIRE_COLLISION_LAYER = 16 # Ensure this matches Project Settings -> Layer Names -> 3D Physics, Layer 16
const GROUND_COLLISION_LAYER = 8 # For placement
const DRAG_PLANE_NORMAL = Vector3.UP # Assume dragging happens on the XY plane (Y=constant)
const GRID_SIZE: float = 0.05 # Snap components to this grid size (in meters)
const DEFAULT_PLACEMENT_DISTANCE = 5.0 # Fallback distance in front of camera
# Preload scenes
var ResistorScene = preload("res://components/Resistor3D.tscn")
var PowerSourceScene = preload("res://components/PowerSource3D.tscn")
var LEDScene = preload("res://components/LED3D.tscn")
var SwitchScene = preload("res://components/Switch3D.tscn")
var DiodeScene = preload("res://components/Diode3D.tscn")
var PotentiometerScene = preload("res://components/Potentiometer3D.tscn")
var WireScene = preload("res://components/Wire3D.tscn")
var BatteryScene = preload("res://components/Battery3D.tscn") # Preload Battery scene
var PolarizedCapacitorScene = preload("res://components/PolarizedCapacitor3D.tscn") # Preload PolarizedCapacitor scene
var NonPolarizedCapacitorScene = preload("res://components/NonPolarizedCapacitor3D.tscn") # Preload NonPolarizedCapacitor scene
var InductorScene = preload("res://components/Inductor3D.tscn") # Preload Inductor scene
var NPNBJTScene = preload("res://components/NPNBJT3D.tscn") # Ensure this path is correct
var PNPBJTScene = preload("res://components/PNPBJT3D.tscn") # Preload PNP BJT scene
var ZenerDiodeScene = preload("res://components/ZenerDiode3D.tscn") # Preload Zener Diode scene
var RelayScene = preload("res://components/Relay3D.tscn") # Preload Relay scene


@onready var camera: Camera3D = $Camera3D
@onready var circuit_graph: CircuitGraph = $CircuitGraph # Add CircuitGraph node

# Wiring state
enum WireState { IDLE, START_SELECTED }
var current_wire_state: WireState = WireState.IDLE
# Store the TerminalFeedback script instance, not just the Area3D
var first_selected_terminal: Area3D = null
# Add a node to hold components for organization
@onready var components_node: Node3D = $Components
@onready var wires_node: Node3D = $Wires # Node to hold wire instances

# Component Selection State
var selected_component: Node3D = null
var _potential_drag_target: Node3D = null # Node clicked on, potentially for dragging
var _drag_start_position: Vector2 = Vector2.ZERO # Screen position where mouse was pressed
# UI elements
@onready var ui_layer: CanvasLayer = $UI
@onready var move_joystick: VirtualJoystick = $UI/MoveJoystick
@onready var look_joystick: VirtualJoystick = $UI/LookJoystick
@onready var add_resistor_button: Button = $UI/ComponentBar/ButtonList/AddResistorButton
@onready var add_power_source_button: Button = $UI/ComponentBar/ButtonList/AddPowerSourceButton
@onready var add_led_button: Button = $UI/ComponentBar/ButtonList/AddLEDButton
@onready var add_switch_button: Button = $UI/ComponentBar/ButtonList/AddSwitchButton
@onready var add_diode_button: Button = $UI/ComponentBar/ButtonList/AddDiodeButton
@onready var add_potentiometer_button: Button = $UI/ComponentBar/ButtonList/AddPotentiometerButton
@onready var add_battery_button: Button = $UI/ComponentBar/ButtonList/AddBatteryButton # Add Battery Button
@onready var add_polarized_capacitor_button: Button = $UI/ComponentBar/ButtonList/AddCapacitorButton # Renamed button reference
@onready var add_non_polarized_capacitor_button: Button = $UI/ComponentBar/ButtonList/AddNonPolarizedCapacitorButton # Add NonPolarizedCapacitor Button
@onready var add_inductor_button: Button = $UI/ComponentBar/ButtonList/AddInductorButton # Add Inductor Button
@onready var add_npn_bjt_button: Button = $UI/ComponentBar/ButtonList/AddNPNBJTButton # Add NPN BJT Button
@onready var add_pnp_bjt_button: Button = $UI/ComponentBar/ButtonList/AddPNPBJTButton # Add PNP BJT Button
@onready var add_zener_diode_button: Button = $UI/ComponentBar/ButtonList/AddZenerDiodeButton # Add Zener Diode button
@onready var add_relay_button: Button = $UI/ComponentBar/ButtonList/AddRelayButton # Add Relay Button
@onready var simulate_button: Button = $UI/ComponentBar/ButtonList/SimulateButton
@onready var selection_bar: VBoxContainer = $UI/SelectionBar
@onready var value_box: HBoxContainer = $UI/SelectionBar/ValueBox # Container for label + edit
@onready var value_label: Label = $UI/SelectionBar/ValueBox/ValueLabel
@onready var value_edit: LineEdit = $UI/SelectionBar/ValueBox/ValueEdit
@onready var zener_voltage_box: HBoxContainer = $UI/SelectionBar/ZenerVoltageBox # For Zener Diode Vz
@onready var zener_voltage_label: Label = $UI/SelectionBar/ZenerVoltageBox/ZenerVoltageLabel # For Zener Diode Vz
@onready var zener_voltage_edit: LineEdit = $UI/SelectionBar/ZenerVoltageBox/ZenerVoltageEdit # For Zener Diode Vz
@onready var current_limit_box: HBoxContainer = $UI/SelectionBar/CurrentLimitBox
@onready var current_limit_label: Label = $UI/SelectionBar/CurrentLimitBox/CurrentLimitLabel
@onready var current_limit_edit: LineEdit = $UI/SelectionBar/CurrentLimitBox/CurrentLimitEdit
@onready var max_voltage_box: HBoxContainer = $UI/SelectionBar/MaxVoltageBox # For Capacitor Max Voltage
@onready var max_voltage_label: Label = $UI/SelectionBar/MaxVoltageBox/MaxVoltageLabel # For Capacitor Max Voltage
@onready var max_voltage_edit: LineEdit = $UI/SelectionBar/MaxVoltageBox/MaxVoltageEdit # For Capacitor Max Voltage
@onready var vbe_on_box: HBoxContainer = $UI/SelectionBar/VbeOnBox # For NPN BJT Vbe_on
@onready var vbe_on_label: Label = $UI/SelectionBar/VbeOnBox/VbeOnLabel # For NPN BJT Vbe_on
@onready var vbe_on_edit: LineEdit = $UI/SelectionBar/VbeOnBox/VbeOnEdit # For NPN BJT Vbe_on
@onready var coil_resistance_box: HBoxContainer = $UI/SelectionBar/CoilResistanceBox # For Relay coil_resistance
@onready var coil_resistance_label: Label = $UI/SelectionBar/CoilResistanceBox/CoilResistanceLabel
@onready var coil_resistance_edit: LineEdit = $UI/SelectionBar/CoilResistanceBox/CoilResistanceEdit
@onready var veb_on_box: HBoxContainer = $UI/SelectionBar/VebOnBox # For PNP BJT Veb_on
@onready var veb_on_label: Label = $UI/SelectionBar/VebOnBox/VebOnLabel # For PNP BJT Veb_on
@onready var veb_on_edit: LineEdit = $UI/SelectionBar/VebOnBox/VebOnEdit # For PNP BJT Veb_on
# @onready var vce_sat_box: HBoxContainer = $UI/SelectionBar/VceSatBox # For NPN BJT Vce_sat (Not yet added to NPN)
# @onready var vce_sat_label: Label = $UI/SelectionBar/VceSatBox/VceSatLabel
# @onready var vce_sat_edit: LineEdit = $UI/SelectionBar/VceSatBox/VceSatEdit
@onready var vec_sat_box: HBoxContainer = $UI/SelectionBar/VecSatBox # For PNP BJT Vec_sat
@onready var vec_sat_label: Label = $UI/SelectionBar/VecSatBox/VecSatLabel
@onready var vec_sat_edit: LineEdit = $UI/SelectionBar/VecSatBox/VecSatEdit
@onready var battery_cell_box: HBoxContainer = $UI/SelectionBar/BatteryCellBox # Battery UI
@onready var battery_cell_option: OptionButton = $UI/SelectionBar/BatteryCellBox/BatteryCellOption # Battery UI
@onready var toggle_power_source_mode_button: Button = $UI/SelectionBar/TogglePowerSourceModeButton
@onready var toggle_switch_button: Button = $UI/SelectionBar/ToggleSwitchButton
@onready var potentiometer_wiper_slider: HSlider = $UI/SelectionBar/PotentiometerWiperSlider

# Camera control variables
var is_flying: bool = false
var is_simulating_continuously: bool = false
var show_voltage_labels: bool = false
var display_voltage_button: Button = null

@export var fly_speed: float = 5.0
@export var look_sensitivity: float = 0.002 # Radians per pixel
# Joystick state
var move_vector: Vector2 = Vector2.ZERO
var look_vector: Vector2 = Vector2.ZERO
var move_intensity: float = 0.0
var look_intensity: float = 0.0

var is_mobile: bool = false

# Drag & Drop state
var is_dragging_component: bool = false
var dragged_component: Node3D = null
var _just_added_component: bool = false # Flag to ignore input right after button add
const DRAG_THRESHOLD: float = 5.0 # Pixels mouse must move before drag starts

var _is_updating_pot_slider_programmatically: bool = false

const SIMULATION_TIME_STEP: float = 0.01 # Example: 10ms time step for transient simulation


# Main script for the 3D circuit editor.
# Will handle component placement, wiring, and initiating simulation.

# Make sure these actions are defined in Project -> Project Settings -> Input Map
# move_forward, move_backward, move_left, move_right, move_up, move_down

func _ready():
	# Check platform and setup UI/Input accordingly
	is_mobile = OS.has_feature("mobile")
	if is_mobile:
		print("Mobile platform detected. Enabling virtual joysticks.")
		# Use VISIBLE mode even on mobile for better UI interaction (LineEdit focus, buttons)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# Connect joystick signals
		move_joystick.joystick_updated.connect(_on_move_joystick_updated)
		move_joystick.joystick_released.connect(_on_move_joystick_released)
		look_joystick.joystick_updated.connect(_on_look_joystick_updated)
		look_joystick.joystick_released.connect(_on_look_joystick_released)
	else:
		print("Desktop platform detected. Hiding virtual joysticks.")
		move_joystick.visible = false
		look_joystick.visible = false
		# Default to visible cursor on desktop
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Connect component add buttons regardless of platform
	# Use bind to pass the scene to load without creating extra functions
	add_resistor_button.pressed.connect(_on_add_component_button_pressed.bind(ResistorScene))
	add_power_source_button.pressed.connect(_on_add_component_button_pressed.bind(PowerSourceScene))
	add_led_button.pressed.connect(_on_add_component_button_pressed.bind(LEDScene))
	add_switch_button.pressed.connect(_on_add_component_button_pressed.bind(SwitchScene))
	add_diode_button.pressed.connect(_on_add_component_button_pressed.bind(DiodeScene))
	add_potentiometer_button.pressed.connect(_on_add_component_button_pressed.bind(PotentiometerScene))
	add_battery_button.pressed.connect(_on_add_component_button_pressed.bind(BatteryScene)) # Connect Add Battery button
	add_polarized_capacitor_button.pressed.connect(_on_add_component_button_pressed.bind(PolarizedCapacitorScene)) # Connect Add PolarizedCapacitor button
	add_non_polarized_capacitor_button.pressed.connect(_on_add_component_button_pressed.bind(NonPolarizedCapacitorScene)) # Connect Add NonPolarizedCapacitor button
	add_inductor_button.pressed.connect(_on_add_component_button_pressed.bind(InductorScene)) # Connect Add Inductor button
	add_npn_bjt_button.pressed.connect(_on_add_component_button_pressed.bind(NPNBJTScene)) # Ensure NPNBJTScene is correct
	add_pnp_bjt_button.pressed.connect(_on_add_component_button_pressed.bind(PNPBJTScene)) # Connect Add PNP BJT
	add_zener_diode_button.pressed.connect(_on_add_component_button_pressed.bind(ZenerDiodeScene)) # Connect Add Zener Diode button
	add_relay_button.pressed.connect(_on_add_component_button_pressed.bind(RelayScene)) # Connect Add Relay button
	simulate_button.pressed.connect(_on_simulate_button_pressed)
	# toggle_power_source_mode_button.pressed.connect(_on_toggle_power_source_mode_button_pressed) # This button and method were removed
	toggle_switch_button.pressed.connect(_on_toggle_switch_button_pressed)
	potentiometer_wiper_slider.value_changed.connect(_on_potentiometer_wiper_slider_value_changed)
	current_limit_edit.text_submitted.connect(_on_current_limit_value_changed)
	max_voltage_edit.text_submitted.connect(_on_max_voltage_value_changed) # Connect capacitor max voltage edit
	vbe_on_edit.text_submitted.connect(_on_vbe_on_value_changed) # Connect NPN BJT Vbe_on edit
	battery_cell_option.item_selected.connect(_on_battery_cell_option_selected) # Connect battery cell selection
	selection_bar.get_node("DeleteButton").pressed.connect(_on_delete_button_pressed)
	value_edit.text_submitted.connect(_on_selected_value_changed) # For primary value (e.g. Vf for Zener)
	zener_voltage_edit.text_submitted.connect(_on_zener_voltage_value_changed) # For Zener voltage
	coil_resistance_edit.text_submitted.connect(_on_coil_resistance_value_changed) # For Relay coil resistance
	veb_on_edit.text_submitted.connect(_on_veb_on_value_changed) # Connect PNP BJT Veb_on edit
	vec_sat_edit.text_submitted.connect(_on_vec_sat_value_changed) # Connect PNP BJT Vec_sat edit
	
	# Hide selection bar initially
	_deselect_component()
	_hide_voltage_displays() # Ensure labels are hidden on start (resets LEDs too)

	# Add display voltage labels toggle button
	display_voltage_button = Button.new()
	display_voltage_button.text = "Display Voltage Labels"
	display_voltage_button.toggle_mode = true
	display_voltage_button.button_pressed = false # Explicitly set initial pressed state
	ui_layer.get_node("ComponentBar/ButtonList").add_child(display_voltage_button)
	display_voltage_button.pressed.connect(_on_display_voltage_button_pressed)

	show_voltage_labels = false # Ensure consistent initial state

func _input(event):
	#print("--- _input entered --- event: {evt_class}".format({"evt_class": event.get_class()})) # DEBUG: New print 1 (Can be noisy, enable if needed)
	# If the event was already handled by the GUI (e.g., clicking a button),
	if get_viewport().is_input_handled():
		print("--- _input: event already handled by GUI, returning. ---") # DEBUG: New print 2
		return

	# Note: The VirtualJoystick script now calls set_input_as_handled(),
	# so joystick input should also be stopped here, preventing raycasts during joystick use.
	# The Button and LineEdit controls handle this automatically.


	# --- Workaround for is_input_handled() issue ---
	# Manually check if the mouse/touch event occurred over the SelectionBar UI element.
	if selection_bar.visible: # Check visibility first
		var ui_rect = selection_bar.get_global_rect()
		print("  Workaround check: SelectionBar visible. Rect: {rect}".format({"rect": ui_rect})) # DEBUG

		var event_pos: Vector2 = Vector2.INF # Initialize with invalid value
		var is_mouse_event: bool = false
		var is_touch_event: bool = false

		if event is InputEventMouse:
			event_pos = event.position
			is_mouse_event = true
			print("    Event is Mouse. Position: {pos}".format({"pos": event_pos})) # DEBUG
		elif event is InputEventScreenTouch:
			event_pos = event.position
			is_touch_event = true
			print("    Event is Touch. Position: {pos}".format({"pos": event_pos})) # DEBUG

		# Proceed only if it's a mouse or touch event with a valid position
		if (is_mouse_event or is_touch_event) and event_pos != Vector2.INF:
			var hit_ui = ui_rect.has_point(event_pos)
			print("    Rect.has_point(event_pos)? {hit}".format({"hit": hit_ui})) # DEBUG
			if hit_ui:
				print("--- _input: event occurred over SelectionBar, manually stopping propagation. ---")
				return # Prevent 3D interaction if clicking on the selection UI
			else:
				print("  Workaround check: Event position is NOT inside SelectionBar rect.") # DEBUG

	elif false: # Keep the old combined check logic structure here just in case, but make it unreachable
		print("--- _input: event occurred over SelectionBar, manually stopping propagation. ---")
		return # Prevent 3D interaction if clicking on the selection UI
	# --- End Workaround ---

	if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					# Hide results if any interaction starts
					# GUI clicks (like on SelectionBar) are now handled by setting mouse_filter = MOUSE_FILTER_STOP
					# on the respective UI elements in the scene file (.tscn).
					# This prevents the event from even reaching this _input function if it was on the UI.

					print("Left Mouse Button Pressed at: {pos}".format({"pos": event.position}))

					# If a component was just added via button, ignore this press event in _input
					# to prevent immediate raycast/reset interference with the drag start.
					if _just_added_component:
						print("  Ignoring input event immediately after component add button press.")
						_just_added_component = false # Reset flag for next input
						return # Stop processing this specific event here

					var mouse_pos = event.position
					var result = _raycast_from_camera(mouse_pos)
					_potential_drag_target = null # Reset potential drag target

					if result:
						var collider = result.collider
						# Clicked a terminal? -> Start wiring (only if not already dragging)
						if collider is Area3D and collider.collision_layer == TERMINAL_COLLISION_LAYER and not is_dragging_component:
							is_flying = false
							_hide_voltage_displays() # Hide results when starting wiring
							_deselect_component() # Deselect any component when starting wiring
							print("  Raycast hit terminal: {coll_name}".format({"coll_name": collider.name}))
							_handle_terminal_click(collider)
						# Clicked a component body? -> Select, maybe start drag later
						elif collider is Area3D and collider.collision_layer == COMPONENT_BODY_COLLISION_LAYER:
							is_flying = false
							print("  Raycast hit component body: {parent_name}".format({"parent_name": collider.get_parent().name}))
							# Handle switch toggle directly in Switch3D via input_event signal
							# If the click was handled by the switch's _on_body_input_event,
							# get_viewport().is_input_handled() will be true, and we might not even get here.
							# If we *do* get here, it means the switch didn't handle it, so proceed with selection/drag.

							# Don't hide voltage display here, only select. Drag start will hide it.
							var component_node = collider.get_parent() # Parent Node3D is the component
							_select_component(component_node)
							_potential_drag_target = component_node # Mark for potential drag
							_drag_start_position = event.position
						# Clicked a wire? -> Select
						elif collider is CSGPolygon3D and collider.collision_layer == WIRE_COLLISION_LAYER:
							is_flying = false
							var wire_node = collider.get_parent() # Parent Path3D is the wire
							if wire_node is Wire3D:
								print("  Raycast hit wire: {wire_name}".format({"wire_name": wire_node.name}))
								# Don't hide voltage display here, only select. Delete will hide it.
								_select_component(wire_node)
								# Wires are not draggable, so don't set _potential_drag_target
							else:
								print("  Raycast hit wire collision shape, but parent is not Wire3D?")
								_hide_voltage_displays()
								_deselect_component()
						# Clicked ground or other area
						else: # Clicked ground or other area
							_hide_voltage_displays()
							print("  Raycast hit ground or other object. Resetting selection/wiring.")
							_deselect_component()
							_reset_wiring_state()

					else: # Clicked empty space
						print("!!! Raycast missed in _input, deselecting component !!!") # <-- Add this line
						print("  Raycast missed. Resetting selection/wiring.")
						_hide_voltage_displays()
						_deselect_component()
						_reset_wiring_state() # Cancel wiring


				elif not event.pressed: # Mouse Button Released
					print("Left Mouse Button Released at: {0}".format([event.position]))


					if is_dragging_component and dragged_component: # Ensure we are dragging something
						print("  Was dragging component. Stopping drag.")
						_stop_component_drag() # Resets is_dragging_component flag
					# Always reset potential drag target on release
					_potential_drag_target = null

			# --- Desktop Fly Camera Toggle (Right Mouse Button) ---
			elif event.button_index == MOUSE_BUTTON_RIGHT and not is_dragging_component: # Don't fly while dragging
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
			# print("Mouse Motion while dragging: pos={pos}, relative={rel}".format({"pos": event.position, "rel": event.relative})) # Can be very noisy
			# Update dragged component position based on mouse motion
			_update_dragged_component_position(event.position)
		# Check if we should START dragging
		elif event.button_mask & MOUSE_BUTTON_LEFT and _potential_drag_target != null:
			# Check if the potential target is actually draggable (not a wire)
			if not _potential_drag_target is Wire3D:
				var distance_moved = (event.position - _drag_start_position).length()
				if distance_moved > DRAG_THRESHOLD:
					print("Drag threshold exceeded for {target_name}. Starting drag.".format({"target_name": _potential_drag_target.name}))
					# Need to ensure it's the *selected* component we are starting to drag
					if _potential_drag_target == selected_component:
						_start_component_drag(_potential_drag_target)
						_update_dragged_component_position(event.position) # Update immediately
						_potential_drag_target = null # Drag started, clear potential target
		elif is_flying and not is_mobile: # Only handle mouse look if flying on desktop

				# print("Mouse Motion while flying: relative={rel}".format({"rel": event.relative})) # Can be very noisy
				# Handle mouse look for desktop fly-cam
				# Yaw: Rotate around global Y axis
				camera.rotate_y(-event.relative.x * look_sensitivity) # rotate_y rotates around parent's Y, which is global Y here

				# Pitch: Rotate around camera's local X axis
				camera.rotate_object_local(Vector3.RIGHT, -event.relative.y * look_sensitivity)
				# Clamp vertical rotation - prevent camera from flipping over
				camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(89.0), deg_to_rad(89.0))


func _process(delta):
	if is_simulating_continuously:
		_simulate_circuit()
	
	# --- Camera Movement (Desktop FlyCam & Mobile Joystick) ---
	var move_input = Vector3.ZERO
	var fly_delta_speed = fly_speed * delta

	if is_mobile:
		# Mobile Joystick Movement
		# Reversed: Joystick Y positive (down) moves camera forward (negative Z)
		move_input.z = move_vector.y # Invert the relationship between joystick Y and camera Z movement
		move_input.x = move_vector.x  # Joystick X is screen X (left/right) -> Camera X (left/right strafe)
		move_input = move_input.normalized() * move_intensity * fly_delta_speed
	elif is_flying:
		# Desktop WASD Fly Movement
		if Input.is_action_pressed("move_forward"):
			move_input.z -= fly_delta_speed
		if Input.is_action_pressed("move_backward"):
			move_input.z += fly_delta_speed
		if Input.is_action_pressed("move_left"):
			move_input.x -= fly_delta_speed
		if Input.is_action_pressed("move_right"):
			move_input.x += fly_delta_speed
		# Optional Up/Down movement
		#if Input.is_action_pressed("move_up"):
		#	move_input.y += fly_delta_speed
		#if Input.is_action_pressed("move_down"):
		#	move_input.y -= fly_delta_speed

	# Apply movement relative to camera's orientation
	camera.global_translate(move_input.rotated(Vector3.UP, camera.global_rotation.y))

	# --- Camera Rotation (Mobile Joystick) ---
	if is_mobile:
		var look_delta_speed = look_sensitivity * 500 * delta # Adjust multiplier as needed
		# Yaw: Rotate around global Y axis
		camera.rotate_y(-look_vector.x * look_intensity * look_delta_speed) # rotate_y rotates around parent's Y, which is global Y here
		# Pitch: Rotate around camera's local X axis
		camera.rotate_object_local(Vector3.RIGHT, -look_vector.y * look_intensity * look_delta_speed)
		# Clamp vertical rotation - prevent camera from flipping over
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(89.0), deg_to_rad(89.0))

func _raycast_from_camera(screen_pos: Vector2):
	var space_state = get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos) * 1000 # Ray length
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction)

	# Query mask checks terminals (2), component bodies (4), and ground (8)
	# This mask is for the initial click detection (_input function)
	# Also check wires (16)
	query.collision_mask = TERMINAL_COLLISION_LAYER | COMPONENT_BODY_COLLISION_LAYER | GROUND_COLLISION_LAYER | WIRE_COLLISION_LAYER
	query.collide_with_areas = true # Needed for terminals (Area3D) and component bodies (Area3D)
	query.collide_with_bodies = true # Needed for ground (StaticBody3D)

	var result = space_state.intersect_ray(query)
	return result

func _handle_terminal_click(terminal: Area3D):
	print("Clicked terminal: ", terminal.name, " on ", terminal.get_parent().name)
	if current_wire_state == WireState.IDLE and not is_dragging_component: # Don't start wiring if dragging
		first_selected_terminal = terminal
		_hide_voltage_displays() # Hide results when wiring starts
		current_wire_state = WireState.START_SELECTED
		print("First terminal selected. Click another terminal to connect.")
		# Activate visual feedback via the terminal's script
		if terminal is TerminalFeedback: # Check if it has the script
			terminal.select()
		else:
			printerr("Clicked terminal {term_name} does not have TerminalFeedback script.".format({"term_name": terminal.name}))
	elif current_wire_state == WireState.START_SELECTED:
		if terminal == first_selected_terminal:
			print("Clicked the same terminal again.")
			# Optional: Deselect if clicking the same one again?
			# _reset_wiring_state()
		elif terminal != first_selected_terminal: # Ensure it's a different terminal
			# Second terminal selected, create the wire
			var second_selected_terminal = terminal
			print("Second terminal selected ({sec_term_name}). Creating wire.".format({"sec_term_name": second_selected_terminal.name}))

			# Ensure the second terminal also has the feedback script before proceeding
			if not second_selected_terminal is TerminalFeedback:
				printerr("Second selected terminal {sec_term_name} does not have TerminalFeedback script. Cannot create wire.".format({"sec_term_name": second_selected_terminal.name}))
				_reset_wiring_state() # Reset state including deselecting the first terminal
				return

			_create_wire(first_selected_terminal, second_selected_terminal)

			# Reset state (which also handles deselecting the first terminal visually)
			# Reset state
			_reset_wiring_state()

func _create_wire(terminal_a: Area3D, terminal_b: Area3D):
	var wire_instance = WireScene.instantiate()
	# Add wire as a child of the main scene or a dedicated "Wires" node
	wires_node.add_child(wire_instance) # Add to the Wires node

	# Get global positions of terminals
	var start_pos = terminal_a.global_transform.origin
	var end_pos = terminal_b.global_transform.origin

	wire_instance.set_endpoints(start_pos, end_pos, terminal_a, terminal_b)

	# Update the logical circuit graph
	circuit_graph.connect_terminals(terminal_a, terminal_b)
	circuit_graph.print_graph_state() # Debug print
			# No need to manually update CSGPolygon, path_node property handles it.

## Snaps a 3D position to the nearest grid point on the Y=0 plane.
func _snap_to_grid(pos: Vector3) -> Vector3:
	var snapped_x = round(pos.x / GRID_SIZE) * GRID_SIZE
	var snapped_z = round(pos.z / GRID_SIZE) * GRID_SIZE
	return Vector3(snapped_x, 0.0, snapped_z) # Assume Y=0 for the grid plane

# --- Drag and Drop ---

func _start_component_drag(component: Node3D):
	print('begin')
	if component in components_node.get_children(): # Ensure it's a component we manage
		print("Starting drag for: {comp_name} at initial position {comp_pos}".format({"comp_name": component.name, "comp_pos": component.global_position}))
		is_dragging_component = true
		dragged_component = component
		_hide_voltage_displays() # Hide results when starting drag
		is_flying = false # Ensure flying stops while dragging
		_reset_wiring_state() # Ensure not in wiring mode
		# Optional: Slightly change appearance (e.g., modulate color)
		# if dragged_component.has_node("MeshInstance3D"):
		#	 dragged_component.get_node("MeshInstance3D").material_override.albedo_color = Color.YELLOW

func _update_dragged_component_position(screen_pos: Vector2):
	# Raycast specifically against the ground plane (layer 8) to find the 3D position
	var space_state = get_world_3d().direct_space_state
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos) * 1000
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction)
	query.collision_mask = GROUND_COLLISION_LAYER # Only hit the ground
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var result = space_state.intersect_ray(query)
	if result:
		# Keep component on the ground plane (Y=0 assumed here)
		# Snap the position to the grid
		var snapped_position = _snap_to_grid(result.position)
		dragged_component.global_position = snapped_position
		print("Dragging {drag_comp_name}: screen_pos={scr_pos} -> world_pos={world_pos} -> snapped_pos={snap_pos}".format({"drag_comp_name": dragged_component.name, "scr_pos": screen_pos, "world_pos": result.position, "snap_pos": snapped_position}))

func _stop_component_drag():
	if not is_dragging_component: return # Prevent stopping if not dragging
	print("Stopping drag for: {drag_comp_name} at final position {final_pos}".format({"drag_comp_name": dragged_component.name, "final_pos": dragged_component.global_position}))
	# Optional: Restore original appearance
	# if dragged_component.has_node("MeshInstance3D") and dragged_component.get_node("MeshInstance3D").material_override:
		# Careful here, might need to store original material or reset differently
	#	 dragged_component.get_node("MeshInstance3D").material_override = null # Or restore original

	# Reset drag state
	is_dragging_component = false
	# Don't null dragged_component here, it might be needed if drag stopped but component remains selected
	dragged_component = null

func _add_component(scene: PackedScene, pos: Vector3):
	var component_instance: Node3D = scene.instantiate()
	components_node.add_child(component_instance) # Add to Components node
	component_instance.global_position = pos
	# component_instance.add_to_group("components") # Adding group via scene now
	# Register with the graph
	circuit_graph.add_component(component_instance)
	_hide_voltage_displays()
	# Connect signals for components that have them
	if component_instance is Switch3D:
		component_instance.state_changed.connect(_on_switch_state_changed)
	elif component_instance is Potentiometer3D:
		component_instance.wiper_position_changed.connect(_on_potentiometer_component_wiper_changed)
	elif component_instance is Battery3D: # Connect Battery signal
		component_instance.configuration_changed.connect(_on_battery_config_changed)
	elif component_instance is PolarizedCapacitor3D: # Connect PolarizedCapacitor signal
		component_instance.configuration_changed.connect(_on_polarized_capacitor_config_changed)
	elif component_instance is NonPolarizedCapacitor3D: # Connect NonPolarizedCapacitor signal
		component_instance.configuration_changed.connect(_on_non_polarized_capacitor_config_changed)
	elif component_instance is Inductor3D: # Connect Inductor signal
		component_instance.configuration_changed.connect(_on_inductor_config_changed)
	elif component_instance is NPNBJT3D: # Connect NPNBJT signal (ensure NPNBJT3D has this signal)
		component_instance.configuration_changed.connect(_on_npn_bjt_config_changed)
	elif component_instance is PNPBJT3D: # Connect PNPBJT signal
		component_instance.configuration_changed.connect(_on_pnp_bjt_config_changed)
	elif component_instance is ZenerDiode3D: # Connect ZenerDiode signal
		component_instance.configuration_changed.connect(_on_zener_diode_config_changed)
	elif component_instance is Relay3D: # Connect Relay signal
		component_instance.configuration_changed.connect(_on_relay_config_changed)
		# Relay state (energized/de-energized) is determined by CircuitGraph, not user interaction.
		# So, no 'state_changed' signal from Relay3D to connect here for that purpose.
	return component_instance # Return the instance
	

func _reset_wiring_state():
	if current_wire_state == WireState.START_SELECTED and is_instance_valid(first_selected_terminal):
		print("Wiring state reset (cancelled or completed).")
		# Deactivate visual feedback on the previously selected terminal
		if first_selected_terminal is TerminalFeedback:
			first_selected_terminal.deselect()
	current_wire_state = WireState.IDLE
	_hide_voltage_displays() # Hide results if wiring is cancelled/completed
	first_selected_terminal = null

# --- Component Selection ---

func _select_component(component: Node3D):
	if component == selected_component:
		# If it's the same component, only proceed if it's a PowerSource (to refresh its CV/CC UI).
		# Otherwise, for other component types, no UI change is needed if re-selected.
		if not (component is PowerSource3D):
			print("Component {comp_name} already selected (and not PowerSource); no UI refresh needed.".format({"comp_name": component.name}))
			return
		# If it is a PowerSource and already selected, fall through to refresh its UI.
		# 'selected_component' is already correct in this case.
		print("Refreshing UI for already selected PowerSource {comp_name}".format({"comp_name": component.name}))
	else:
		# A different component is being selected, or no component was selected before.
		# Deselect previous one if any.
		if selected_component != null: # Ensure there's something to deselect
			_deselect_component() # This will set selected_component to null.
		selected_component = component # Now select the new component.
		print("Selecting new component: {comp_name}".format({"comp_name": component.name}))

	# Common UI setup for a new selection or a PowerSource UI refresh.
	# 'selected_component' correctly refers to 'component' at this point.
	selection_bar.visible = true
	value_edit.editable = true # Default to editable, specific components can override
	value_box.visible = false # Hide by default
	zener_voltage_box.visible = false # Hide Zener voltage box by default
	current_limit_box.visible = false # Hide by default
	max_voltage_box.visible = false # Hide MaxVoltageBox by default
	vbe_on_box.visible = false # Hide NPN VbeOnBox by default
	veb_on_box.visible = false # Hide PNP VebOnBox by default
	#vce_sat_box.visible = false # Hide NPN VceSatBox by default
	coil_resistance_box.visible = false # Hide Relay coil resistance box by default
	vec_sat_box.visible = false # Hide PNP VecSatBox by default
	battery_cell_box.visible = false # Hide Battery UI by default
	toggle_power_source_mode_button.visible = false # This button will be removed / always hidden
	toggle_switch_button.visible = false # Hide by default
	potentiometer_wiper_slider.visible = false # Hide by default

	# Configure value editor based on type
	if selected_component is Resistor3D:
		value_box.visible = true
		value_label.text = "Resistance (Ω):"
		value_edit.text = str(selected_component.resistance)
		# TODO: Add visual highlight
	elif selected_component is PowerSource3D:
		value_box.visible = true
		value_label.text = "Target Voltage (V):"
		value_edit.text = str(selected_component.target_voltage)
		
		current_limit_box.visible = true
		current_limit_label.text = "Current Limit (A):"
		current_limit_edit.text = str(selected_component.target_current)
		# toggle_power_source_mode_button is no longer used.
		# TODO: Add visual highlight
	elif selected_component is Battery3D:
		value_box.visible = true # Show the voltage display box (read-only)
		value_label.text = "Voltage (V):"
		value_edit.text = str(selected_component.target_voltage)
		value_edit.editable = false # Make voltage display read-only for battery
		
		battery_cell_box.visible = true
		# Set OptionButton selected index based on component's num_cells (0-indexed for items)
		battery_cell_option.select(selected_component.num_cells - 1) 
		# TODO: Add visual highlight
	elif selected_component is LED3D:
		value_box.visible = true
		value_label.text = "Fwd Voltage (V):"
		value_edit.text = str(selected_component.forward_voltage)
		# TODO: Add visual highlight
	elif selected_component is Diode3D:
		value_box.visible = true
		value_label.text = "Fwd Voltage (V):"
		value_edit.text = str(selected_component.forward_voltage)
		# TODO: Add visual highlight
	elif selected_component is ZenerDiode3D:
		value_box.visible = true
		value_label.text = "Fwd Voltage (Vf):"
		value_edit.text = str(selected_component.forward_voltage)
		zener_voltage_box.visible = true
		zener_voltage_label.text = "Zener Voltage (Vz):"
		zener_voltage_edit.text = str(selected_component.zener_voltage)
		# TODO: Add visual highlight
	elif selected_component is Switch3D:
		value_box.visible = false # Switches don't have a numeric value to edit
		toggle_switch_button.visible = true
		toggle_switch_button.text = "Turn Off" if selected_component.current_state == Switch3D.State.CONNECTED_NO else "Turn On"
		# TODO: Add visual highlight
	elif selected_component is Potentiometer3D:
		value_box.visible = true
		value_label.text = "Total R (Ω):"
		value_edit.text = str(selected_component.total_resistance)
		potentiometer_wiper_slider.visible = true
		# Prevent feedback loop when setting slider value from component state
		_is_updating_pot_slider_programmatically = true
		potentiometer_wiper_slider.value = selected_component.wiper_position
		_is_updating_pot_slider_programmatically = false
		# TODO: Add visual highlight
	elif selected_component is Wire3D:
		value_box.visible = false # Wires don't have a single value to edit
		# TODO: Add visual highlight (maybe change color?)
	elif selected_component is PolarizedCapacitor3D:
		value_box.visible = true
		value_label.text = "Capacitance (F):"
		value_edit.text = str(selected_component.capacitance)
		
		max_voltage_box.visible = true
		max_voltage_label.text = "Max Voltage (V):"
		max_voltage_edit.text = str(selected_component.max_voltage)
		# TODO: Add visual highlight
	elif selected_component is NonPolarizedCapacitor3D:
		value_box.visible = true
		value_label.text = "Capacitance (F):"
		value_edit.text = str(selected_component.capacitance)
		
		max_voltage_box.visible = true
		max_voltage_label.text = "Max Voltage (V):"
		max_voltage_edit.text = str(selected_component.max_voltage)
		# TODO: Add visual highlight
	elif selected_component is Inductor3D:
		value_box.visible = true
		value_label.text = "Inductance (H):"
		value_edit.text = str(selected_component.inductance)
		# TODO: Add visual highlight
	elif selected_component is NPNBJT3D:
		value_box.visible = true # Using ValueBox for Beta for now.
		value_label.text = "Beta (Hfe):"
		value_edit.text = str(selected_component.beta_dc)
		
		vbe_on_box.visible = true # Show Vbe_on box for NPN BJT
		vbe_on_label.text = "Vbe On (V):" # Set label text
		vbe_on_edit.text = str(selected_component.vbe_on) # Set current Vbe_on value
		# Vce_sat could be added similarly if needed for NPN.
		# TODO: Add visual highlight
	elif selected_component is PNPBJT3D:
		value_box.visible = true # Using ValueBox for Beta for PNP.
		value_label.text = "Beta (Hfe):"
		value_edit.text = str(selected_component.beta_dc)
		
		veb_on_box.visible = true # Show Veb_on box for PNP BJT
		veb_on_label.text = "Veb On (V):" 
		veb_on_edit.text = str(selected_component.veb_on)
		
		vec_sat_box.visible = true # Show Vec_sat box for PNP BJT
		vec_sat_label.text = "Vec Sat (V):"
		vec_sat_edit.text = str(selected_component.vec_sat)
		# TODO: Add visual highlight
	elif selected_component is Relay3D:
		value_box.visible = true
		value_label.text = "Coil Threshold (V):"
		value_edit.text = str(selected_component.coil_voltage_threshold)
		coil_resistance_box.visible = true
		coil_resistance_label.text = "Coil Resist. (Ω):"
		coil_resistance_edit.text = str(selected_component.coil_resistance)
		# TODO: Add visual highlight
	else:
		value_box.visible = false # Hide editor for unknown types
		printerr("Selected node {comp_name} is not a recognized component type for editing.".format({"comp_name": component.name}))

	# Ensure delete button is always visible when something is selected
	# if selected_component : value_edit.editable = true # This line is removed as editability is handled above and in _deselect_component
	selection_bar.get_node("DeleteButton").visible = true


func _deselect_component():
	if selected_component:
		print("Deselecting component: {sel_comp_name}".format({"sel_comp_name": selected_component.name}))
		# Ensure value_edit is re-enabled if it was disabled for Battery
		value_edit.editable = true 
		# TODO: Remove visual highlight
		if selected_component is Resistor3D:
			pass # Remove highlight
		elif selected_component is PowerSource3D:
			pass # Remove highlight
		elif selected_component is Battery3D: # Battery specific deselect
			pass # Remove highlight
		elif selected_component is LED3D:
			pass # Remove highlight
		elif selected_component is Diode3D:
			pass # Remove highlight
		elif selected_component is Switch3D:
			pass # Remove highlight
		elif selected_component is Wire3D:
			pass # Remove highlight
		elif selected_component is PolarizedCapacitor3D:
			pass # Remove highlight
		elif selected_component is NonPolarizedCapacitor3D:
			pass # Remove highlight
		elif selected_component is Inductor3D:
			pass # Remove highlight
		elif selected_component is NPNBJT3D: # Ensure NPNBJT is handled
			pass # Remove highlight
		elif selected_component is PNPBJT3D: # Ensure PNPBJT is handled
			pass # Remove highlight
		elif selected_component is ZenerDiode3D:
			pass # Remove highlight
		elif selected_component is Relay3D:
			pass # Remove highlight

	selected_component = null
	print("!!! _deselect_component: selected_component set to null !!!") # Add this print
	selection_bar.visible = false
	value_box.visible = false
	zener_voltage_box.visible = false # Hide Zener voltage UI
	current_limit_box.visible = false
	max_voltage_box.visible = false # Hide capacitor max voltage UI
	vbe_on_box.visible = false # Hide NPN BJT Vbe_on UI
	veb_on_box.visible = false # Hide PNP BJT Veb_on UI
	#vce_sat_box.visible = false # Hide NPN BJT Vce_sat UI
	coil_resistance_box.visible = false # Hide Relay coil resistance UI
	vec_sat_box.visible = false # Hide PNP BJT Vec_sat UI
	battery_cell_box.visible = false # Hide battery UI
	toggle_power_source_mode_button.visible = false
	toggle_switch_button.visible = false
	potentiometer_wiper_slider.visible = false
	# Clear potential drag target if we deselect
	_potential_drag_target = null
	# Clear value editor text
	value_edit.text = ""
	current_limit_edit.text = ""
	# Make sure the whole bar is hidden, not just parts of it
	selection_bar.get_node("DeleteButton").visible = false

# --- Component Button Handler ---


# --- UI Element Handlers ---
func _on_add_component_button_pressed(scene_to_add: PackedScene):
	print("Add component button pressed for scene: {scene_path}".format({"scene_path": scene_to_add.resource_path}))

	# --- Determine initial placement position in front of camera ---
	var initial_position: Vector3
	var space_state = get_world_3d().direct_space_state
	var cam_transform = camera.global_transform
	var ray_origin = cam_transform.origin
	var ray_direction = -cam_transform.basis.z # Camera forward direction
	var ray_query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000) # Long ray
	ray_query.collision_mask = GROUND_COLLISION_LAYER # Only check against ground
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = false

	var result = space_state.intersect_ray(ray_query)
	if result:
		initial_position = result.position
		print("  Placing initial component at ground raycast hit: {init_pos}".format({"init_pos": initial_position}))
	else:
		# Raycast missed (e.g., looking up). Place at a default distance projected onto Y=0 plane.
		initial_position = ray_origin + ray_direction * DEFAULT_PLACEMENT_DISTANCE
		initial_position.y = 0.0 # Project onto Y=0
		print("  Placing initial component at fallback position (projected): {init_pos}".format({"init_pos": initial_position}))

	# Snap the initial position to the grid
	var snapped_initial_position = _snap_to_grid(initial_position)
	print("  Snapped initial position to grid: {snap_pos}".format({"snap_pos": snapped_initial_position}))
	# --- Add component and start dragging ---
	_hide_voltage_displays() # Hide old results
	var new_component: Node3D = _add_component(scene_to_add, snapped_initial_position)
	_select_component(new_component) # Select the newly added component
	_start_component_drag(new_component)
	_just_added_component = true # Set the flag

# Helper function to perform a single simulation step including ground setup
func _perform_simulation_step():
	print("Performing simulation step...")
	# --- Set Ground (Example: Ground the negative terminal of the first power source found) ---
	# In a real application, you might have a dedicated ground symbol or tool.
	var ground_terminal_set = false
	if circuit_graph.ground_node_id == -1: # Only try to set ground if not already set or explicitly cleared
		print("  Attempting to set ground node as none is currently set.")
		for comp_data in circuit_graph.components:
			if comp_data.type == "PowerSource" or comp_data.type == "Battery":
				var neg_terminal = comp_data.terminals.get("NEG", null) # Both PowerSource and Battery use "NEG"
				if is_instance_valid(neg_terminal):
					circuit_graph.set_ground_node(neg_terminal)
					ground_terminal_set = true # Graph will print success
					break 
		if not ground_terminal_set:
			print("  Warning: Could not automatically find a power source negative terminal to ground for this step.")
	else:
		ground_terminal_set = true # Assume existing ground is valid

	if not ground_terminal_set or circuit_graph.ground_node_id == -1:
		printerr("Simulation Error: Cannot simulate because no ground node is set. Add a Power Source or ensure one is grounded.")
		_hide_voltage_displays() # Full reset including LEDs on critical failure
		return

	if circuit_graph.solve_single_time_step(SIMULATION_TIME_STEP):
		print("  Simulation step successful.")
		circuit_graph.print_graph_state()
		_update_led_states()       # Always update LED actual state
		_update_voltage_displays() # Update terminal voltage labels (if show_voltage_labels is true)
	else:
		print("  Simulation step failed. Check console for errors and circuit configuration.")
		_hide_voltage_displays() # Full reset including LEDs on failure

func _on_simulate_button_pressed():
	is_simulating_continuously = not is_simulating_continuously # Toggle state
	
	if is_simulating_continuously:
		simulate_button.text = "Stop Simulation"
		print("Starting continuous simulation.")
		# Perform an initial simulation step when continuous mode starts.
		# Subsequent steps will be handled by _process -> _simulate_circuit.
		_perform_simulation_step() 
	else:
		simulate_button.text = "Simulate"
		print("Stopping continuous simulation.")
		_hide_voltage_displays() # Full hide, including resetting LEDs
		show_voltage_labels = false
		if display_voltage_button: # Ensure button is valid before accessing
			display_voltage_button.button_pressed = false 
			display_voltage_button.text = "Display Voltage Labels"
		# When stopping, we do NOT perform another simulation step.
		
func _simulate_circuit():
	# Shared simulation logic that is called every frame if is_simulating_continuously is true
	# Ground should have been set when continuous simulation started.
	if circuit_graph.ground_node_id == -1:
		# print_debug("Continuous simulation: Ground not set, attempting to set.")
		# Attempt to set ground again, this might be needed if components were changed
		# This part of _perform_simulation_step can be inlined or called.
		# For simplicity, just check and warn. Major graph changes should ideally stop continuous sim.
		var temp_ground_set = false
		if circuit_graph.ground_node_id == -1: # Only try to set if not already set
			for comp_data in circuit_graph.components:
				if comp_data.type == "PowerSource" or comp_data.type == "Battery":
					var neg_terminal = comp_data.terminals.get("NEG", null) # Both PowerSource and Battery use "NEG"
					if is_instance_valid(neg_terminal):
						circuit_graph.set_ground_node(neg_terminal)
						temp_ground_set = true
						break
			if not temp_ground_set:
				# Attempt to ground the source terminal of the first NChannelMOSFET if no PS/Battery found
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
				is_simulating_continuously = false # Stop simulation
				simulate_button.text = "Simulate"
				_hide_voltage_displays()
		if not temp_ground_set:
			printerr("Continuous Simulation Error: Ground node not set. Stopping.")
			is_simulating_continuously = false # Stop simulation
			simulate_button.text = "Simulate"
			_hide_voltage_displays()
			return


	if circuit_graph.solve_single_time_step(SIMULATION_TIME_STEP):
		_update_led_states()       # Always update LED actual state
		_update_voltage_displays() # Update terminal voltage labels (if show_voltage_labels is true)
	else:
		# If solve_dc fails continuously, CircuitGraph prints errors.
		# Visuals might show last valid state or get cleared by _hide_voltage_displays
		# in _update_voltage_displays if _is_solved becomes false.
		# Optionally, force a visual reset here too if preferred.
		_hide_voltage_displays(true) # Aggressively reset visuals on fail
		pass # For now, let the existing logic in update/hide handle visual state

# --- Selection UI Handlers ---

func _on_selected_value_changed(new_text: String):
	if not selected_component: return

	_hide_voltage_displays() # Hide old results when value changes
	# Try to parse the input value
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid value entered: '{txt}'. Reverting.".format({"txt": new_text}))
		# Revert the text edit to the current value
		if selected_component is Resistor3D:
			value_edit.text = str(selected_component.resistance)
		elif selected_component is PowerSource3D:
			# This handler is for the primary value_edit, which is Voltage for PowerSource
			value_edit.text = str(selected_component.target_voltage)
		elif selected_component is LED3D:
			value_edit.text = str(selected_component.forward_voltage)
		elif selected_component is ZenerDiode3D: # Primary edit is Vf for Zener
			value_edit.text = str(selected_component.forward_voltage)
			zener_voltage_edit.text = str(selected_component.zener_voltage) # Also fill Vz
		elif selected_component is Diode3D:
			value_edit.text = str(selected_component.forward_voltage)
		elif selected_component is Potentiometer3D:
			value_edit.text = str(selected_component.total_resistance)
		elif selected_component is PolarizedCapacitor3D:
			value_edit.text = str(selected_component.capacitance) # Primary value edit is capacitance
			max_voltage_edit.text = str(selected_component.max_voltage) # Also fill max_voltage_edit
		elif selected_component is NonPolarizedCapacitor3D:
			value_edit.text = str(selected_component.capacitance) # Primary value edit is capacitance
			max_voltage_edit.text = str(selected_component.max_voltage) # Also fill max_voltage_edit
		elif selected_component is Inductor3D:
			value_edit.text = str(selected_component.inductance)
		elif selected_component is NPNBJT3D: # For Beta (Hfe)
			value_edit.text = str(selected_component.beta_dc)
		elif selected_component is PNPBJT3D: # For Beta (Hfe) for PNP
			value_edit.text = str(selected_component.beta_dc)
		elif selected_component is Relay3D: # Primary edit is coil_voltage_threshold for Relay
			value_edit.text = str(selected_component.coil_voltage_threshold)
			coil_resistance_edit.text = str(selected_component.coil_resistance) # Also fill coil_resistance
		# NChannelMOSFET Vth/Kn are handled by their own LineEdit handlers, not this primary one.
		else:
			value_edit.text = "" # Should not happen if UI is managed correctly
		return

	# Update the component's property and the graph
	print("Updating {sel_comp_name} value (via primary ValueEdit) to {val}".format({"sel_comp_name": selected_component.name, "val": new_value}))
	if selected_component is Resistor3D:
		selected_component.resistance = new_value
	elif selected_component is PowerSource3D:
		# This is specifically for target_voltage as it's from the main value_edit
		selected_component.target_voltage = new_value
	elif selected_component is LED3D:
		selected_component.forward_voltage = new_value
		# _hide_voltage_displays() will be called by simulate or other actions,
		# which in turn calls reset_visual_state on the LED node.
	elif selected_component is ZenerDiode3D: # Vf is primary for Zener
		selected_component.forward_voltage = new_value # Setter in ZenerDiode3D.gd handles signal
	elif selected_component is Diode3D:
		selected_component.forward_voltage = new_value
	elif selected_component is Potentiometer3D:
		selected_component.total_resistance = new_value
	elif selected_component is PolarizedCapacitor3D:
		# This handler is for the primary value_edit (Capacitance)
		selected_component.capacitance = new_value # Setter in PolarizedCapacitor3D.gd handles signal
	elif selected_component is Inductor3D:
		selected_component.inductance = new_value # Setter in Inductor3D.gd handles signal
	elif selected_component is NPNBJT3D: # For Beta (Hfe)
		selected_component.beta_dc = new_value # Setter in NPNBJT3D.gd handles signal
	elif selected_component is PNPBJT3D: # For Beta (Hfe) for PNP
		selected_component.beta_dc = new_value # Setter in PNPBJT3D.gd handles signal
	elif selected_component is Relay3D: # Primary edit is coil_voltage_threshold for Relay
		selected_component.coil_voltage_threshold = new_value # Setter in Relay3D.gd handles signal
	
	# Notify CircuitGraph that component configuration has changed.
	# This is called when the primary ValueEdit field is submitted.
	# For components/properties that have their own 'configuration_changed' signal connected
	# (e.g., PolarizedCapacitor's/NonPolarizedCapacitor's capacitance via set_capacitance -> respective _on_..._config_changed),
	# the graph update is handled by that signal's callback.
	# For other components or properties not covered by such signals, call component_config_changed directly.
	if selected_component:
		if selected_component is PolarizedCapacitor3D or selected_component is NonPolarizedCapacitor3D:
			# Capacitance change for Capacitors (from the primary ValueEdit) is handled by their
			# 'configuration_changed' signal, triggered by 'selected_component.capacitance = new_value' further above
			# in this function (_on_selected_value_changed).
			# The signal calls their respective config_changed handlers, which updates the graph.
			# So, no direct call to circuit_graph.component_config_changed here for this specific property change.
			pass
		elif selected_component is Inductor3D:
			# Inductance change for Inductor (from primary ValueEdit) is handled by its 'configuration_changed' signal.
			pass
		elif selected_component is NPNBJT3D or selected_component is PNPBJT3D:
			# Beta change for BJTs (from primary ValueEdit) is handled by their 'configuration_changed' signal.
			pass
		elif selected_component is ZenerDiode3D:
			# Vf change for Zener Diode (from primary ValueEdit) is handled by its 'configuration_changed' signal.
			pass
		elif selected_component is Relay3D:
			# coil_voltage_threshold change for Relay (from primary ValueEdit) is handled by its 'configuration_changed' signal.
			pass
		else:
			# For other components, or properties not managed by a specific signal path for this ValueEdit,
			# call component_config_changed directly.
			circuit_graph.component_config_changed(selected_component)

func _on_delete_button_pressed():
	print("!!! _on_delete_button_pressed: Entered. selected_component is: {sel_comp}".format({"sel_comp": selected_component})) # Add this print
	if not selected_component:
		_hide_voltage_displays() # Clear any visible results if delete is pressed with nothing selected
		print("Delete button pressed, but nothing selected.")
		return

	print("Delete button pressed for: {sel_comp_name}".format({"sel_comp_name": selected_component.name}))

	if selected_component is Wire3D:
		# Just delete the wire node visually. Graph connection persists implicitly.
		_hide_voltage_displays() # Hide results
		var wire_to_delete = selected_component # Store ref before deselecting
		_deselect_component() # Deselect first
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
		 selected_component is Relay3D:
		var component_to_delete = selected_component # Store ref
		var terminals_to_check = []
		if component_to_delete is Resistor3D:
			terminals_to_check = [component_to_delete.terminal1, component_to_delete.terminal2]
		elif component_to_delete is PowerSource3D:
			terminals_to_check = [component_to_delete.terminal_pos, component_to_delete.terminal_neg]
		elif component_to_delete is Battery3D: # Battery terminals
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
			terminals_to_check = [component_to_delete.terminal_e, component_to_delete.terminal_b, component_to_delete.terminal_c] # EBC for PNP
		elif component_to_delete is Relay3D:
			terminals_to_check = [
				component_to_delete.terminal_coil_p, component_to_delete.terminal_coil_n,
				component_to_delete.terminal_com, component_to_delete.terminal_no, component_to_delete.terminal_nc
			]

		# Find and delete connected wires first
		for wire_node in wires_node.get_children():
			if wire_node is Wire3D:
				if wire_node.terminal_start in terminals_to_check or wire_node.terminal_end in terminals_to_check:
					print("  Deleting connected wire: {wire_name}".format({"wire_name": wire_node.name}))
					wire_node.queue_free()

		# Update graph and delete component node
		_hide_voltage_displays() # Hide results
		circuit_graph.remove_component(component_to_delete)
		_deselect_component() # Deselect before freeing
		component_to_delete.queue_free()
		print("  Deleted component node and associated wires.")
	else:
		_hide_voltage_displays() # Hide results
		printerr("Delete requested for unknown selected object type.")
		_deselect_component() # Deselect anyway

# --- Voltage Display ---

# Iterates through all components and finds their terminals to show voltages from the graph
func _update_voltage_displays():
	# This function handles displaying text voltage labels on terminals
	# AND current labels on components.
	# LED visual states (lit/burn) are handled by _update_led_states().
	
	if not show_voltage_labels: # If global flag is false, hide all these labels
		_hide_voltage_displays(false) # Hide terminals (LEDs visual state not reset by this call)
		# Explicitly hide component currents if the main flag is off
		for component_node in components_node.get_children():
			if component_node.has_method("hide_current"):
				component_node.hide_current()
			if component_node.has_method("hide_info"): # For PolarizedCapacitor, NonPolarizedCapacitor, Inductor, or ZenerDiode
				component_node.hide_info()

		# Also for any components in graph but not direct children (less common)
		for comp_data_graph in circuit_graph.components:
			var c_node_graph = comp_data_graph.component_node
			if is_instance_valid(c_node_graph) and not c_node_graph in components_node.get_children():
				if c_node_graph.has_method("hide_current"):
					c_node_graph.hide_current()
				if c_node_graph.has_method("hide_info"): # For PolarizedCapacitor, NonPolarizedCapacitor or Inductor
					c_node_graph.hide_info()
		return

	print("Updating voltage and current displays...")
	if not circuit_graph._is_solved:
		print("  Circuit not solved, hiding terminal displays.")
		# Hide terminal labels, but DO NOT reset LED states here.
		_hide_voltage_displays(false) 
		return

	for node_id in circuit_graph.electrical_nodes:
		var voltage = circuit_graph.electrical_nodes[node_id].voltage
		if is_nan(voltage): continue # Skip if voltage is somehow NaN after solving

		for terminal_area in circuit_graph.electrical_nodes[node_id].terminals:
			if is_instance_valid(terminal_area) and terminal_area is TerminalFeedback:
				terminal_area.show_voltage(voltage)
	
	# Update component current displays
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
			var cap_exploded = results.get("is_exploded", false) # PolarizedCapacitor specific
			component_node.show_info(cap_current, cap_voltage, cap_exploded)
		elif component_node.has_method("show_info") and comp_data.type == "NonPolarizedCapacitor":
			var np_cap_current = results.get("current", NAN)
			var np_cap_voltage = results.get("voltage_across", NAN)
			# NonPolarizedCapacitor's show_info doesn't take is_exploded
			component_node.show_info(np_cap_current, np_cap_voltage) 
		elif component_node.has_method("show_info") and comp_data.type == "Inductor":
			var ind_current = results.get("current", NAN)
			var ind_voltage = results.get("voltage_across", NAN)
			component_node.show_info(ind_current, ind_voltage)
		elif component_node.has_method("show_info") and \
			(comp_data.type == "NPNBJT" or comp_data.type == "PNPBJT" or comp_data.type == "ZenerDiode" or comp_data.type == "Relay"):
			# Transistors, Zener Diodes, and Relays expect a dictionary of results
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
					"current": results.get("current", NAN), # Current A->K
					"voltage_ak": results.get("voltage_ak", NAN), # Voltage A-K
					"state": results.get("state", "N/A")
				}
			elif comp_data.type == "Relay":
				info_results_dict = {
					"coil_voltage": results.get("coil_voltage", NAN),
					"is_energized": results.get("is_energized", false),
					"coil_threshold": comp_data.properties.get("coil_voltage_threshold", NAN), # Get threshold from component data
					"coil_current": results.get("coil_current", NAN) # Optional coil current
				}
			component_node.show_info(info_results_dict)
		elif component_node.has_method("show_current"): # Handle other components (Resistor, Diode, LED, Switch, PowerSource, Battery)
			if comp_data.type == "Potentiometer":
				var current1_w = results.get("current_T1_W", NAN)
				var current_w_t2 = results.get("current_W_T2", NAN)
				component_node.show_current(current1_w, current_w_t2)
			elif comp_data.type == "PowerSource": # Pass mode for PowerSource
				var actual_current_ps = results.get("current", NAN)
				var actual_voltage_ps = results.get("voltage", NAN)
				var op_mode_ps = results.get("operating_mode", "CV") # Default to CV if not found
				component_node.show_current(actual_current_ps, actual_voltage_ps, op_mode_ps)
			elif comp_data.type == "Battery": # Battery doesn't need op_mode explicitly passed like PS
				var actual_current_bat = results.get("current", NAN)
				var actual_voltage_bat = results.get("voltage", NAN) 
				component_node.show_current(actual_current_bat, actual_voltage_bat)
			else: # Resistor, LED, Diode, Switch
				var current_val = results.get("current", NAN)
				component_node.show_current(current_val)
		# else: print_debug("Component %s of type %s has no show_current/show_current_voltage method." % [component_node.name, comp_data.type])


# This function updates the visual state of all LEDs based on simulation results.
# It's called after a successful circuit solve, regardless of show_voltage_labels.
func _update_led_states():
	print("Updating LED states...")
	for comp_data in circuit_graph.components:
		if comp_data.type == "LED" and is_instance_valid(comp_data.component_node):
			var led_node: LED3D = comp_data.component_node
			var comp_id = led_node.get_instance_id()
			
			var current: float = circuit_graph.component_results.get(comp_id, {}).get("current", 0.0)
			if is_nan(current): current = 0.0 # Treat NaN current as zero for visual purposes
			
			var is_logically_burned: bool = comp_data.get("is_burned", false)
			
			led_node.update_visual_state(current, is_logically_burned)
		elif comp_data.type == "LED" and not is_instance_valid(comp_data.component_node):
			printerr("CircuitEditor: Found LED component_data with invalid component_node during _update_led_states.")


# Iterates through all components and finds their terminals to hide voltages
func _hide_voltage_displays(leds: bool = true):
	# print("Hiding voltage displays...") #This print can be very noisy, enable if debugging display issues
	# Iterate through all components and their terminals
	for component_node in components_node.get_children(): # These are components in the scene
		# Hide terminal voltage labels
		for child in component_node.get_children():
			if child is TerminalFeedback:
				child.hide_voltage()
		
		# Hide component current labels
		if component_node.has_method("hide_current"):
			component_node.hide_current()
		if component_node.has_method("hide_info"): # For Capacitors, Inductor, Transistors, or Zener
			component_node.hide_info()
		if component_node is PolarizedCapacitor3D and leds: # Use 'leds' flag broadly for full reset
			component_node.reset_visual_state() # Reset exploded state visually
		if component_node is NonPolarizedCapacitor3D and leds:
			component_node.reset_visual_state()
		if component_node is Inductor3D and leds: # Use 'leds' flag broadly for full reset
			component_node.reset_visual_state()
		if component_node is NPNBJT3D and leds: 
			component_node.reset_visual_state()
		if component_node is PNPBJT3D and leds: 
			component_node.reset_visual_state()
		if component_node is ZenerDiode3D and leds: # Reset Zener Diode visual state
			component_node.reset_visual_state()
		if component_node is Relay3D and leds: # Reset Relay visual state
			component_node.reset_visual_state()
			
		# Reset LED visual state if requested (this handles lit/burn state, separate from current display)
		if component_node is LED3D and leds: # `leds` flag specifically for LED light/burn reset
			component_node.reset_visual_state()
	
	# Iterate through graph components for any not directly under components_node (e.g. if structure changes)
	# This part is mainly for LED reset if `leds` is true. Current/voltage/info hiding for these
	# should ideally be handled if `show_voltage_labels` is toggled or sim stops.
	for comp_data_graph in circuit_graph.components:
		var c_node = comp_data_graph.component_node
		if is_instance_valid(c_node) and not c_node in components_node.get_children():
			# Hide current/info for these too if they exist
			if c_node.has_method("hide_current"):
				c_node.hide_current()
			if c_node.has_method("hide_info"): # For Capacitors, Inductor, Transistors, or Zener
				c_node.hide_info()
			if leds and c_node is PolarizedCapacitor3D: # Reset PolarizedCapacitor visual state
				c_node.reset_visual_state()
			if leds and c_node is NonPolarizedCapacitor3D:
				c_node.reset_visual_state()
			if leds and c_node is Inductor3D: # Reset Inductor visual state
				c_node.reset_visual_state()
			if leds and c_node is NPNBJT3D: 
				c_node.reset_visual_state()
			if leds and c_node is PNPBJT3D: 
				c_node.reset_visual_state()
			if leds and c_node is ZenerDiode3D: # Reset Zener Diode visual state
				c_node.reset_visual_state()
			if leds and c_node is Relay3D: # Reset Relay visual state
				c_node.reset_visual_state()
			# Reset LED visual state if requested
			if leds and c_node is LED3D:
				c_node.reset_visual_state()

func _on_potentiometer_wiper_slider_value_changed(value: float):
	if _is_updating_pot_slider_programmatically:
		return # Value was set by code, not user interaction

	if selected_component is Potentiometer3D:
		print("Potentiometer UI Slider changed to: {val_str}".format({"val_str": String.num(value, 2)}))
		selected_component.set_wiper_position(value) # This will trigger the component's signal
		# The component's signal `wiper_position_changed` is connected in _add_component
		# to _on_potentiometer_component_wiper_changed, which updates the graph.
		_hide_voltage_displays() # Value changed, hide old simulation results

func _on_potentiometer_component_wiper_changed(component_node: Potentiometer3D, new_position: float):
	print("CircuitEditor notified of Potentiometer {comp_name} wiper change to: {pos_str}".format({"comp_name": component_node.name, "pos_str": String.num(new_position, 2)}))
	# The Potentiometer3D node's wiper_position property is already updated by its own setter.
	# We just need to notify the graph that this component's configuration has changed.
	circuit_graph.component_config_changed(component_node)
	_hide_voltage_displays(true) # Wiper position (a parameter) changed, hide old simulation results including LED states if any

func _on_display_voltage_button_pressed():
	# display_voltage_button is a toggle button.
	# Its `is_pressed()` state reflects its new state *after* the press.
	show_voltage_labels = display_voltage_button.is_pressed() 

	if show_voltage_labels:
		display_voltage_button.text = "Hide Voltage Labels"
		# If circuit is solved, update the terminal voltage displays.
		# LED states are managed independently by simulation steps and _update_led_states().
		if circuit_graph._is_solved:
			_update_voltage_displays() # This function now only handles terminal labels
	else:
		display_voltage_button.text = "Display Voltage Labels"
		# Hide terminal voltage displays. LED states (lit/burn) remain untouched by this action.
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

	_hide_voltage_displays() # Hide old results when value changes
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
		if new_value < 0: new_value = 0.0 # Current limit cannot be negative, ensure it's float
	else:
		print("Invalid current limit entered: '{txt}'. Reverting.".format({"txt": new_text}))
		current_limit_edit.text = str(selected_component.target_current)
		return

	print("Updating {sel_comp_name} target_current to {val}".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.target_current = new_value
	circuit_graph.component_config_changed(selected_component)

func _on_max_voltage_value_changed(new_text: String):
	if not selected_component or not (selected_component is PolarizedCapacitor3D or selected_component is NonPolarizedCapacitor3D): return

	_hide_voltage_displays(true) # Hide old results when value changes, reset visuals
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid max voltage entered: '{txt}'. Reverting.".format({"txt": new_text}))
		max_voltage_edit.text = str(selected_component.max_voltage)
		return

	print("Updating {sel_comp_name} max_voltage to {val}V".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.max_voltage = new_value # Setter in Capacitor GDScripts handles signal to graph
	# circuit_graph.component_config_changed(selected_component) # Signal handler will do this

func _on_vbe_on_value_changed(new_text: String):
	if not selected_component or not selected_component is NPNBJT3D: return

	_hide_voltage_displays(true) # Hide old results when value changes, reset visuals
	var new_value: float = NAN
	if new_text.is_valid_float():
		new_value = float(new_text)
	else:
		print("Invalid Vbe_on entered: '{txt}'. Reverting.".format({"txt": new_text}))
		vbe_on_edit.text = str(selected_component.vbe_on) # Revert to current value
		return

	print("Updating {sel_comp_name} vbe_on to {val}V".format({"sel_comp_name": selected_component.name, "val": new_value}))
	selected_component.vbe_on = new_value # Setter in NPNBJT3D.gd handles signal to graph (_on_npn_bjt_config_changed)

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
	selected_component.zener_voltage = new_value # Setter in ZenerDiode3D.gd handles signal

func _on_veb_on_value_changed(new_text: String): # For PNP BJT
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
	selected_component.veb_on = new_value # Setter in PNPBJT3D.gd handles signal

func _on_coil_resistance_value_changed(new_text: String): # For Relay coil resistance
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
	selected_component.coil_resistance = new_value # Setter in Relay3D.gd handles signal

# func _on_vce_sat_value_changed(new_text: String): # For NPN BJT Vce_sat (if added)
	# Similar logic if NPN gets Vce_sat editable

func _on_vec_sat_value_changed(new_text: String): # For PNP BJT Vec_sat
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
	selected_component.vec_sat = new_value # Setter in PNPBJT3D.gd handles signal

# _on_toggle_power_source_mode_button_pressed can be removed as the button is gone.

func _on_non_polarized_capacitor_config_changed(capacitor_node: NonPolarizedCapacitor3D):
	print("CircuitEditor notified of NonPolarizedCapacitor {cap_name} config change. New C: {cap_str}F, MaxV: {max_v_str}V".format({"cap_name": capacitor_node.name, "cap_str": String.num_scientific(capacitor_node.capacitance), "max_v_str": String.num(capacitor_node.max_voltage, 2)}))
	circuit_graph.component_config_changed(capacitor_node)
	_hide_voltage_displays(true) # Config changed, hide old results, reset visuals

func _on_battery_cell_option_selected(index: int):
	if selected_component is Battery3D:
		var num_cells_selected = index + 1 # OptionButton index is 0-based
		print("Battery UI cell option selected: {num_cells} cells".format({"num_cells": num_cells_selected}))
		selected_component.set_num_cells(num_cells_selected) # This will trigger signal if changed
		# Update the read-only voltage display in the UI
		value_edit.text = str(selected_component.target_voltage) 
		_hide_voltage_displays() # Config changed, hide old results
	# The component's 'configuration_changed' signal (connected in _add_component)
	# will call _on_battery_config_changed, which updates the graph.

func _on_battery_config_changed(battery_node: Battery3D):
	print("CircuitEditor notified of Battery {batt_name} config change. New voltage: {volt_str}V".format({"batt_name": battery_node.name, "volt_str": String.num(battery_node.target_voltage, 2)}))
	circuit_graph.component_config_changed(battery_node)
	_hide_voltage_displays(true) # Config changed, hide old results, reset LEDs

func _on_polarized_capacitor_config_changed(capacitor_node: PolarizedCapacitor3D):
	print("CircuitEditor notified of PolarizedCapacitor {cap_name} config change. New C: {cap_str}F, MaxV: {max_v_str}V".format({"cap_name": capacitor_node.name, "cap_str": String.num_scientific(capacitor_node.capacitance), "max_v_str": String.num(capacitor_node.max_voltage, 2)}))
	circuit_graph.component_config_changed(capacitor_node) # This will also reset its 'is_exploded' state in the graph
	_hide_voltage_displays(true) # Config changed, hide old results, reset LEDs and capacitor visual state

func _on_inductor_config_changed(inductor_node: Inductor3D):
	print("CircuitEditor notified of Inductor {ind_name} config change. New L: {l_str}H".format({"ind_name": inductor_node.name, "l_str": String.num_scientific(inductor_node.inductance)}))
	circuit_graph.component_config_changed(inductor_node)
	_hide_voltage_displays(true) # Config changed, hide old results, reset LEDs etc.

func _on_npn_bjt_config_changed(bjt_node: NPNBJT3D):
	print("CircuitEditor notified of NPNBJT {bjt_name} config change. Beta: {beta_val}, Vbe_on: {vbe_val}V, Vce_sat: {vce_val}V".format({
		"bjt_name": bjt_node.name, 
		"beta_val": String.num(bjt_node.beta_dc, 1),
		"vbe_val": String.num(bjt_node.vbe_on, 2),
		"vce_val": String.num(bjt_node.vce_sat, 2)
		}))
	circuit_graph.component_config_changed(bjt_node)
	_hide_voltage_displays(true) # Config changed, hide old results, reset visuals

func _on_pnp_bjt_config_changed(bjt_node: PNPBJT3D):
	print("CircuitEditor notified of PNPBJT {bjt_name} config change. Beta: {beta_val}, Veb_on: {veb_val}V, Vec_sat: {vec_val}V".format({
		"bjt_name": bjt_node.name, 
		"beta_val": String.num(bjt_node.beta_dc, 1),
		"veb_val": String.num(bjt_node.veb_on, 2), # Veb for PNP
		"vec_val": String.num(bjt_node.vec_sat, 2)  # Vec for PNP
		}))
	circuit_graph.component_config_changed(bjt_node)
	_hide_voltage_displays(true) # Config changed, hide old results, reset visuals

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


# func _on_toggle_power_source_mode_button_pressed():
#	if selected_component is PowerSource3D:
#		var ps_node: PowerSource3D = selected_component
#		if ps_node.current_mode == PowerSource3D.Mode.CV:
#			ps_node.current_mode = PowerSource3D.Mode.CC
#		else:
#			ps_node.current_mode = PowerSource3D.Mode.CV
#		
#		print("PowerSource {0} mode changed to {1}".format([ps_node.name, "CC" if ps_node.current_mode == PowerSource3D.Mode.CC else "CV"]))
#		circuit_graph.component_config_changed(ps_node)
#		_hide_voltage_displays()
#		# Re-select to update UI fields correctly
#		_select_component(ps_node)


# --- Component Signal Handlers ---

func _on_switch_state_changed(switch_node: Node3D, new_state: int):
	# _select_component(switch_node) # Selecting might steal focus or be undesired if state changed by non-UI means
	print("CircuitEditor notified of switch state change to: {state_key}".format({"state_key": Switch3D.State.keys()[new_state]}))
	# Invalidate simulation results
	circuit_graph.component_config_changed(switch_node) # Generic config change
	_hide_voltage_displays()

func _on_toggle_switch_button_pressed():
	if selected_component is Switch3D:
		var switch_node: Switch3D = selected_component
		# Toggle the switch’s state
		switch_node.toggle_state() # This emits state_changed, which calls component_config_changed
		# _hide_voltage_displays() # Done by state_changed handler path
		toggle_switch_button.text = "Turn Off" if switch_node.current_state == Switch3D.State.CONNECTED_NO else "Turn On"
