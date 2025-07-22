class_name TestUtils

static func _log(success: bool, message: String) -> void:
	var color = "[color=green]" if success else "[color=red]"
	var status = "PASSED" if success else "FAILED"
	print_rich(color + status + ": " + message + "[/color]")

## Asserts that a condition is true.
static func assert_true(condition: bool, message: String = "", context = null) -> bool:
	var base_msg = message if not message.is_empty() else "Condition expected to be true, but was false"
	if not condition:
		var err_msg = "FAILED: {msg}".format({"msg": base_msg})
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		_log(condition, base_msg)
		assert(condition, err_msg)
	else:
		_log(condition, base_msg)
	return condition

## Asserts that a condition is false.
static func assert_false(condition: bool, message: String = "", context = null) -> bool:
	var base_msg = message if not message.is_empty() else "Condition expected to be false, but was true"
	if condition:
		var err_msg = "FAILED: {msg}".format({"msg": base_msg})
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		_log(not condition, base_msg)
		assert(not condition, err_msg)
	else:
		_log(true, base_msg)
	return not condition

## Asserts that two float values are approximately equal within a given tolerance.
static func assert_approx_equals(actual: float, expected: float, tolerance: float, message: String = "", context = null) -> bool:
	var are_equal = abs(actual - expected) <= tolerance
	var msg_prefix = "Value approx. equals"
	if not message.is_empty():
		msg_prefix = message
	
	var msg = "{pfx} (Actual: {act}, Expected: {exp}, Tolerance: {tol}) - Difference: {diff}".format({"pfx": msg_prefix, "act": actual, "exp": expected, "tol": tolerance, "diff": abs(actual - expected)})
	if not are_equal:
		var err_msg = "FAILED: " + msg
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		_log(are_equal, msg)
		assert(are_equal, err_msg)
	else:
		_log(are_equal, msg)
	return are_equal

## Asserts that two values are equal.
static func assert_equals(actual, expected, message: String = "", context = null) -> bool:
	var are_equal = actual == expected
	var msg_prefix = "Value equals"
	if not message.is_empty():
		msg_prefix = message
	
	var msg = "{pfx} (Actual: {act}, Expected: {exp})".format({"pfx": msg_prefix, "act": actual, "exp": expected})
	if not are_equal:
		var err_msg = "FAILED: " + msg
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		_log(are_equal, msg)
		assert(are_equal, err_msg)
	else:
		_log(are_equal, msg)
	return are_equal

## Asserts that a float value is not NaN (Not a Number).
static func assert_not_nan(value: float, message: String = "", context = null) -> bool:
	var is_not_nan = not is_nan(value)
	var msg_prefix = "Value is not NaN"
	if not message.is_empty():
		msg_prefix = message
	
	var msg = "{pfx} (Actual: {act})".format({"pfx": msg_prefix, "act": value})
	if not is_not_nan:
		var err_msg = "FAILED: " + msg
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		_log(is_not_nan, msg)
		assert(is_not_nan, err_msg)
	else:
		_log(is_not_nan, msg)
	return is_not_nan
