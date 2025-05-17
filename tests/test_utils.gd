# Helper functions for assertions in tests.
class_name TestUtils

static func assert_true(condition: bool, message: String = "") -> bool:
	if condition:
		print("  PASSED: {msg}".format({"msg": message if message else "Condition is true"}))
	else:
		printerr("  FAILED: {msg}".format({"msg": message if message else "Condition expected to be true, but was false"}))
	return condition

static func assert_false(condition: bool, message: String = "") -> bool:
	if not condition:
		print("  PASSED: {msg}".format({"msg": message if message else "Condition is false"}))
	else:
		printerr("  FAILED: {msg}".format({"msg": message if message else "Condition expected to be false, but was true"}))
	return not condition

static func assert_approx_equals(actual: float, expected: float, tolerance: float, message: String = "") -> bool:
	var are_equal = abs(actual - expected) <= tolerance
	var msg_prefix = "Value approx. equals"
	if not message.is_empty():
		msg_prefix = message
	
	if are_equal:
		print("  PASSED: {pfx} (Actual: {act}, Expected: {exp}, Tolerance: {tol})".format({"pfx": msg_prefix, "act": actual, "exp": expected, "tol": tolerance}))
	else:
		printerr("  FAILED: {pfx} (Actual: {act}, Expected: {exp}, Tolerance: {tol}) - Difference: {diff}".format({"pfx": msg_prefix, "act": actual, "exp": expected, "tol": tolerance, "diff": abs(actual - expected)}))
	return are_equal

static func assert_equals(actual, expected, message: String = "") -> bool:
	var are_equal = actual == expected
	var msg_prefix = "Value equals"
	if not message.is_empty():
		msg_prefix = message
	
	if are_equal:
		print("  PASSED: {pfx} (Actual: {act}, Expected: {exp})".format({"pfx": msg_prefix, "act": actual, "exp": expected}))
	else:
		printerr("  FAILED: {pfx} (Actual: {act}, Expected: {exp})".format({"pfx": msg_prefix, "act": actual, "exp": expected}))
	return are_equal

static func assert_not_nan(value: float, message: String = "") -> bool:
	var is_not_nan = not is_nan(value)
	var msg_prefix = "Value is not NaN"
	if not message.is_empty():
		msg_prefix = message
	
	if is_not_nan:
		print("  PASSED: {pfx} (Actual: {act})".format({"pfx": msg_prefix, "act": value}))
	else:
		printerr("  FAILED: {pfx} (Actual: {act})".format({"pfx": msg_prefix, "act": value}))
	return is_not_nan
