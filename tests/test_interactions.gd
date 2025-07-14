extends Node

# This script holds tests related to user interaction with components.

func get_tests() -> Array[Dictionary]:
	return [
		{"name": "Test: ComponentInteractionUtils get_closest_terminal", "func": test_get_closest_terminal},
	]

## Tests the ComponentInteractionUtils's get_closest_terminal function.
func test_get_closest_terminal() -> bool:
	var ok := true
	var ResistorScene = preload("res://components/Resistor3D.tscn")
	var resistor = ResistorScene.instantiate()
	add_child(resistor)
	resistor.global_position = Vector3(10, 2, -5)

	await get_tree().process_frame

	var terminal1 = resistor.terminal1
	var terminal2 = resistor.terminal2

	if not is_instance_valid(terminal1) or not is_instance_valid(terminal2):
		printerr("  FAILED: Terminals are not valid instances.")
		resistor.queue_free()
		return false

	# Test 1: Hit position exactly on terminal 1
	var hit_pos_1 = terminal1.global_position
	var closest_1 = ComponentInteractionUtils.get_closest_terminal(resistor, hit_pos_1)
	if not TestUtils.assert_equals(closest_1, terminal1, "get_closest_terminal: Hit on Terminal 1"):
		ok = false

	# Test 2: Hit position exactly on terminal 2
	var hit_pos_2 = terminal2.global_position
	var closest_2 = ComponentInteractionUtils.get_closest_terminal(resistor, hit_pos_2)
	if not TestUtils.assert_equals(closest_2, terminal2, "get_closest_terminal: Hit on Terminal 2"):
		ok = false

	# Test 3: Hit position close to terminal 1 (inside radius)
	var hit_pos_3 = terminal1.global_position + Vector3(0.1, 0, 0) # INTERACTION_RADIUS is 0.15
	var closest_3 = ComponentInteractionUtils.get_closest_terminal(resistor, hit_pos_3)
	if not TestUtils.assert_equals(closest_3, terminal1, "get_closest_terminal: Hit near Terminal 1"):
		ok = false

	# Test 4: Hit position far from any terminal
	var hit_pos_4 = resistor.global_position
	var closest_4 = ComponentInteractionUtils.get_closest_terminal(resistor, hit_pos_4)
	if not TestUtils.assert_equals(closest_4, null, "get_closest_terminal: Hit far from terminals"):
		ok = false

	# Test 5: Hit position just outside terminal 1's radius
	var hit_pos_5 = terminal1.global_position + Vector3(ComponentInteractionUtils.INTERACTION_RADIUS + 0.01, 0, 0)
	var closest_5 = ComponentInteractionUtils.get_closest_terminal(resistor, hit_pos_5)
	if not TestUtils.assert_equals(closest_5, null, "get_closest_terminal: Hit outside Terminal 1 radius"):
		ok = false

	# Test 6: Invalid component node
	var closest_6 = ComponentInteractionUtils.get_closest_terminal(null, Vector3.ZERO)
	if not TestUtils.assert_equals(closest_6, null, "get_closest_terminal: Null component returns null"):
		ok = false

	resistor.queue_free()
	return ok
