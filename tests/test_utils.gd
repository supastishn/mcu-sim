class_name TestUtils

## Asserts that a condition is true.
static func assert_true(condition: bool, message: String = "", context = null) -> bool:
	if condition:
		print("  PASSED: {msg}".format({"msg": message if message else "Condition is true"}))
	else:
		var err_msg = "FAILED: {msg}".format({"msg": message if message else "Condition expected to be true, but was false"})
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		assert(condition, err_msg)

	return condition

## Asserts that a condition is false.
static func assert_false(condition: bool, message: String = "", context = null) -> bool:
	if not condition:
		print("  PASSED: {msg}".format({"msg": message if message else "Condition is false"}))
	else:
		var err_msg = "FAILED: {msg}".format({"msg": message if message else "Condition expected to be false, but was true"})
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		assert(not condition, err_msg)
	return not condition

## Asserts that two float values are approximately equal within a given tolerance.
static func assert_approx_equals(actual: float, expected: float, tolerance: float, message: String = "", context = null) -> bool:
	var are_equal = abs(actual - expected) <= tolerance
	var msg_prefix = "Value approx. equals"
	if not message.is_empty():
		msg_prefix = message
	
	if are_equal:
		print("  PASSED: {pfx} (Actual: {act}, Expected: {exp}, Tolerance: {tol})".format({"pfx": msg_prefix, "act": actual, "exp": expected, "tol": tolerance}))
	else:
		var err_msg = "FAILED: {pfx} (Actual: {act}, Expected: {exp}, Tolerance: {tol}) - Difference: {diff}".format({"pfx": msg_prefix, "act": actual, "exp": expected, "tol": tolerance, "diff": abs(actual - expected)})
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		assert(are_equal, err_msg)
	return are_equal

## Asserts that two values are equal.
static func assert_equals(actual, expected, message: String = "", context = null) -> bool:
	var are_equal = actual == expected
	var msg_prefix = "Value equals"
	if not message.is_empty():
		msg_prefix = message
	
	if are_equal:
		print("  PASSED: {pfx} (Actual: {act}, Expected: {exp})".format({"pfx": msg_prefix, "act": actual, "exp": expected}))
	else:
		var err_msg = "FAILED: {pfx} (Actual: {act}, Expected: {exp})".format({"pfx": msg_prefix, "act": actual, "exp": expected})
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		assert(are_equal, err_msg)
	return are_equal

## Asserts that a float value is not NaN (Not a Number).
static func assert_not_nan(value: float, message: String = "", context = null) -> bool:
	var is_not_nan = not is_nan(value)
	var msg_prefix = "Value is not NaN"
	if not message.is_empty():
		msg_prefix = message
	
	if is_not_nan:
		print("  PASSED: {pfx} (Actual: {act})".format({"pfx": msg_prefix, "act": value}))
	else:
		var err_msg = "FAILED: {pfx} (Actual: {act})".format({"pfx": msg_prefix, "act": value})
		if context is TestRig and is_instance_valid(context.graph):
			err_msg += "\n" + context.graph.get_solver_debug_info_as_string()
		elif context is CircuitGraph and is_instance_valid(context):
			err_msg += "\n" + context.get_solver_debug_info_as_string()
		assert(is_not_nan, err_msg)
	return is_not_nan
