class_name StringUtils

## Formats a float current value into a human-readable string with appropriate units (A, mA, µA, nA, pA).
static func format_current(current_value: float) -> String:
	if is_nan(current_value):
		return "N/A"
	
	var abs_current = abs(current_value)

	# Using a small epsilon for zero check to handle floating point inaccuracies
	if abs_current < 1e-15:
		return "0.00 pA"

	if abs_current < 1e-9: # picoAmps
		return "{val_str} pA".format({"val_str": String.num(current_value * 1e12, 2)})
	elif abs_current < 1e-6: # nanoAmps
		return "{val_str} nA".format({"val_str": String.num(current_value * 1e9, 2)})
	elif abs_current < 1e-3: # microAmps
		return "{val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
	elif abs_current < 1.0: # milliAmps
		return "{val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
	else: # Amps
		return "{val_str} A".format({"val_str": String.num(current_value, 2)})
