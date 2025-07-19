extends Node

const CircuitEditorScene = preload("res://CircuitEditor3D.tscn")  # legacy tests need it
const OpAmpScene = preload("res://components/OpAmp3D.tscn")
const TestInteractions = preload("res://tests/test_interactions.gd")

## Emitted when all tests are completed, carrying the results dictionary.
signal tests_completed(results: Dictionary)

## Godot's ready function.
func _ready():
	run_from_cli()

## Runs all tests when the script is executed from the command line and then quits.
func run_from_cli():
	print_rich("[b]Starting Circuit Simulation Tests...[/b]")
	var results = await run_all_tests()
	print_rich("[b]All tests completed.[/b]")
	print_rich("[b]Summary: {p}/{t} tests passed.[/b]".format({"p": results.passed, "t": results.total}))

	if results.passed == results.total:
		print_rich("[color=green]All tests successful![/color]")
	else:
		printerr("\n[b][color=red]----- FAILED TESTS ----- [/color][/b]")
		for failed_test_name in results.failed_names:
			printerr("  - {name}".format({"name": failed_test_name}))
		printerr("\n{f} test(s) failed overall.".format({"f": results.total - results.passed}))

	get_tree().quit()

## Runs all tests and emits a signal with the results, intended for use with the UI.
func run_tests_from_ui():
	var results = await run_all_tests()
	emit_signal("tests_completed", results)

## Main test runner function that executes all individual test cases.
func run_all_tests() -> Dictionary:
	var local_total_tests = 0
	var local_passed_tests = 0
	var local_failed_test_names: Array[String] = []

	var all_tests = [
		{"name": "Test: Simple PowerSupply, Resistor, LED Circuit", "func": test_simple_powersupply_resistor_led_circuit},
		{"name": "Test: LED Burnout Scenario", "func": test_led_burnout},
		{"name": "Test: LED Not Lighting (High Resistance)", "func": test_led_not_lighting},
		{"name": "Test: Switch NC and NO Operation", "func": test_switch_behavior},
		{"name": "Test: Diode Forward and Reverse Bias", "func": test_diode_behavior},
		{"name": "Test: Potentiometer Wiper Voltage Division", "func": test_potentiometer_behavior},
		{"name": "Test: Battery Voltage Output with Different Cell Counts", "func": test_battery_behavior},
		{"name": "Test: Polarized Capacitor Charging and Explosion", "func": test_polarized_capacitor_behavior},
		{"name": "Test: Non-Polarized Capacitor Charging", "func": test_non_polarized_capacitor_behavior},
		{"name": "Test: Inductor Current Behavior", "func": test_inductor_behavior},
		{"name": "Test: NPN BJT Operating Regions", "func": test_npn_bjt_regions},
		{"name": "Test: PNP BJT Operating Regions", "func": test_pnp_bjt_regions},
		{"name": "Test: Zener Diode Forward, Reverse, and Breakdown", "func": test_zener_diode_behavior},
		{"name": "Test: N-Channel MOSFET Operating Regions", "func": test_nmosfet_regions},
		{"name": "Test: P-Channel MOSFET Operating Regions", "func": test_pmosfet_regions},
		{"name": "Test: Relay Energized and De-energized States", "func": test_relay_behavior},
		{"name": "Test: Linear Regulator Normal Operation", "func": test_linear_regulator_normal},
		{"name": "Test: Linear Regulator Dropout Scenario", "func": test_linear_regulator_dropout},
		{"name": "Test: Op-Amp Inverting Amplifier", "func": test_op_amp_inverting_amplifier},
	]

	var interactions_test_runner = TestInteractions.new()
	add_child(interactions_test_runner)
	all_tests.append_array(interactions_test_runner.get_tests())

	for test_case in all_tests:
		print_rich("\n[b]{name}[/b]".format({"name": test_case.name}))
		local_total_tests += 1
		if await test_case.func.call():
			local_passed_tests += 1
		else:
			local_failed_test_names.push_back(test_case.name)

	interactions_test_runner.queue_free()
	return { "total": local_total_tests, "passed": local_passed_tests, "failed_names": local_failed_test_names }


## Tests a basic circuit with a power supply, resistor, and LED to verify fundamental calculations.
func test_simple_powersupply_resistor_led_circuit() -> bool:
	var overall_test_passed = true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var g = rig.graph
	var ed = rig.editor

	var ps_node : PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,0))
	var res_node : Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var led_node : LED3D = rig.add(ed.LEDScene, Vector3(2,0,0))

	ps_node.target_voltage = 5.0
	ps_node.target_current = 0.1 
	rig.cfg(ps_node)

	res_node.resistance = 220.0
	rig.cfg(res_node)

	led_node.saturation_current = 1e-12
	led_node.ideality_factor = 1.5
	led_node.min_current_to_light = 0.001
	led_node.max_current_before_burn = 0.020
	rig.cfg(led_node)
	
	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, led_node.terminal_anode)
	rig.wire(led_node.terminal_kathode, ps_node.terminal_neg)

	rig.ground(ps_node.terminal_neg)

	var solve_success: bool = rig.solve()
	if not TestUtils.assert_true(solve_success, "Simulation solve_single_time_step successful"): overall_test_passed = false

	if solve_success:
		# Approximate LED forward voltage drop around 2.0V for this test's parameters
		var expected_current = (5.0 - 2.0) / 220.0
		var tolerance = 0.001 

		var res_results = rig.results(res_node)
		var res_current = res_results.get("current", NAN)
		if not TestUtils.assert_not_nan(res_current, "Resistor current is not NaN"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(res_current, expected_current, tolerance, "Resistor current matches expected"): overall_test_passed = false
		
		var led_results = rig.results(led_node)
		var led_current = led_results.get("current", NAN)
		if not TestUtils.assert_not_nan(led_current, "LED current is not NaN"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(led_current, expected_current, tolerance, "LED current matches expected"): overall_test_passed = false

		var led_graph_data = g.component_node_map.get(led_node)
		
		if led_graph_data:
			if not TestUtils.assert_false(led_graph_data.get("is_burned", true), "LED is NOT burned"): overall_test_passed = false
		else:
			printerr("  ASSERT FAIL: Could not find LED graph data.")
			overall_test_passed = false
			
		var ps_results = rig.results(ps_node)
		var ps_op_mode = ps_results.get("operating_mode", "ERROR")
		if not TestUtils.assert_equals(ps_op_mode, "CV", "Power Supply is in CV mode"): overall_test_passed = false

	rig.cleanup()
	return overall_test_passed

## Tests the Op-Amp model in various configurations: inverting amplifier in linear and saturation regions.
func test_op_amp_inverting_amplifier() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	print("  Op-Amp Test: Inverting Amplifier (Linear Region)")
	var ps_vcc: PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,2))
	var ps_vee: PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,3))
	var ps_vin: PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,4))
	var opamp: OpAmp3D = rig.add(OpAmpScene, Vector3(1,0,0))
	var r_in: Resistor3D = rig.add(ed.ResistorScene, Vector3(0,0,-1))
	var r_f: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,-1))

	ps_vcc.target_voltage = 15.0; rig.cfg(ps_vcc)
	ps_vee.target_voltage = 15.0; rig.cfg(ps_vee)
	ps_vin.target_voltage = 1.0; rig.cfg(ps_vin)
	opamp.open_loop_gain = 200000
	rig.cfg(opamp)
	r_in.resistance = 1000.0; rig.cfg(r_in)
	r_f.resistance = 10000.0; rig.cfg(r_f)
	
	# Powering the Op-Amp
	rig.wire(opamp.terminal_vcc, ps_vcc.terminal_pos)
	rig.wire(opamp.terminal_vee, ps_vee.terminal_neg) # Connect to negative terminal of VEE source

	# Feedback loop and input signal
	rig.wire(ps_vin.terminal_pos, r_in.terminal1)
	rig.wire(r_in.terminal2, opamp.terminal_vn)
	rig.wire(opamp.terminal_vn, r_f.terminal1)
	rig.wire(r_f.terminal2, opamp.terminal_vout)
	
	# Ground connections
	# Centralize ground on op-amp's non-inverting input for clarity
	rig.ground(opamp.terminal_vp)
	rig.wire(ps_vcc.terminal_neg, opamp.terminal_vp)
	rig.wire(ps_vee.terminal_pos, opamp.terminal_vp)
	rig.wire(ps_vin.terminal_neg, opamp.terminal_vp)

	if not rig.solve(): ok = false
	if ok:
		var results = rig.results(opamp)
		if not TestUtils.assert_equals(results.get("region"), "LINEAR", "Op-Amp is in LINEAR region"): ok = false
		var expected_vout = - (r_f.resistance / r_in.resistance) * ps_vin.target_voltage
		if not TestUtils.assert_approx_equals(results.get("Vout", NAN), expected_vout, 0.1, "Op-Amp Vout matches expected gain"): ok = false

	print("  Op-Amp Test: Inverting Amplifier (Saturation)")
	ps_vin.target_voltage = 2.0 # This should drive output to -20V, which will saturate
	rig.cfg(ps_vin)
	
	if not rig.solve(): ok = false
	if ok:
		var results_sat = rig.results(opamp)
		if not TestUtils.assert_equals(results_sat.get("region"), "SAT_LOW", "Op-Amp is in SAT_LOW region"): ok = false
		
		var expected_sat_volt = -ps_vee.target_voltage + opamp.rail_saturation_voltage
		if not TestUtils.assert_approx_equals(results_sat.get("Vout", NAN), expected_sat_volt, 0.1, "Op-Amp Vout is saturated low"): ok = false

	print("  Op-Amp Test: Inverting Amplifier (High Saturation)")
	ps_vin.target_voltage = -2.0 # This should drive output to +20V, which will saturate
	rig.cfg(ps_vin)

	if not rig.solve(): ok = false
	if ok:
		var results_sat_high = rig.results(opamp)
		if not TestUtils.assert_equals(results_sat_high.get("region"), "SAT_HIGH", "Op-Amp is in SAT_HIGH region"): ok = false

		var expected_sat_high_volt = ps_vcc.target_voltage - opamp.rail_saturation_voltage
		if not TestUtils.assert_approx_equals(results_sat_high.get("Vout", NAN), expected_sat_high_volt, 0.1, "Op-Amp Vout is saturated high"): ok = false

	rig.cleanup()
	return ok


## Tests the Switch component's behavior in both Normally Closed (NC) and Normally Open (NO) states.
func test_switch_behavior() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	# --- NC Test ---
	print("  Switch Test: Testing NC operation (default state).")
	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var switch_node: Switch3D = rig.add(ed.SwitchScene, Vector3(1,0,0))
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(2,0,0))
	var led_node: LED3D = rig.add(ed.LEDScene, Vector3(3,0,0))

	ps_node.target_voltage = 5.0; rig.cfg(ps_node)
	res_node.resistance = 220.0; rig.cfg(res_node)
	led_node.min_current_to_light = 0.001; led_node.max_current_before_burn = 0.050; rig.cfg(led_node)

	rig.wire(ps_node.terminal_pos, switch_node.terminal_com)
	rig.wire(switch_node.terminal_nc, res_node.terminal1)
	rig.wire(res_node.terminal2, led_node.terminal_anode)
	rig.wire(led_node.terminal_kathode, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	if not rig.solve(): ok = false
	if ok:
		# Approximate LED forward voltage drop around 2.0V for this test's parameters
		var expected_current_on = (5.0 - 2.0) / 220.0
		var led_results = rig.results(led_node)
		if not TestUtils.assert_approx_equals(led_results.get("current", NAN), expected_current_on, 0.001, "Switch Test (NC): LED current indicates circuit is ON"): ok = false

	# --- NO Test ---
	print("  Switch Test: Testing NO operation.")
	rig.reset_graph()
	ps_node = rig.add(ed.PowerSourceScene)
	switch_node = rig.add(ed.SwitchScene, Vector3(1,0,0))
	res_node = rig.add(ed.ResistorScene, Vector3(2,0,0))
	led_node = rig.add(ed.LEDScene, Vector3(3,0,0))

	ps_node.target_voltage = 5.0; rig.cfg(ps_node)
	res_node.resistance = 220.0; rig.cfg(res_node)
	led_node.min_current_to_light = 0.001; led_node.max_current_before_burn = 0.050; rig.cfg(led_node)
	switch_node.set_state(Switch3D.State.CONNECTED_NO); rig.cfg(switch_node)

	rig.wire(ps_node.terminal_pos, switch_node.terminal_com)
	rig.wire(switch_node.terminal_no, res_node.terminal1)
	rig.wire(res_node.terminal2, led_node.terminal_anode)
	rig.wire(led_node.terminal_kathode, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)
	
	if not rig.solve(): ok = false
	if ok:
		# Approximate LED forward voltage drop around 2.0V for this test's parameters
		var expected_current_on = (5.0 - 2.0) / 220.0
		var led_results = rig.results(led_node)
		if not TestUtils.assert_approx_equals(led_results.get("current", NAN), expected_current_on, 0.001, "Switch Test (NO): LED current indicates circuit is ON"): ok = false

	rig.cleanup()
	return ok


## Tests the Diode component in both forward-biased (conducting) and reverse-biased (non-conducting) states.
func test_diode_behavior() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	# --- Forward Bias ---
	print("  Diode Test: Testing Forward Bias.")
	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var diode_node: Diode3D = rig.add(ed.DiodeScene, Vector3(2,0,0))

	ps_node.target_voltage = 5.0; rig.cfg(ps_node)
	res_node.resistance = 220.0; rig.cfg(res_node)
	diode_node.saturation_current = 1e-12
	diode_node.ideality_factor = 1.0
	rig.cfg(diode_node)

	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, diode_node.terminal_anode)
	rig.wire(diode_node.terminal_kathode, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	if not rig.solve(): ok = false
	if ok:
		var diode_results = rig.results(diode_node)
		# Approximate diode forward voltage drop around 0.7V for this test's parameters
		var expected_current = (5.0 - 0.7) / 220.0
		if not TestUtils.assert_approx_equals(diode_results.get("current", NAN), expected_current, 0.001, "Diode Test (Fwd): Current matches expected"): ok = false

	# --- Reverse Bias ---
	print("  Diode Test: Testing Reverse Bias.")
	rig.reset_graph()
	ps_node = rig.add(ed.PowerSourceScene)
	res_node = rig.add(ed.ResistorScene, Vector3(1,0,0))
	diode_node = rig.add(ed.DiodeScene, Vector3(2,0,0))

	ps_node.target_voltage = 5.0; rig.cfg(ps_node)
	res_node.resistance = 220.0; rig.cfg(res_node)
	rig.cfg(diode_node)

	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, diode_node.terminal_kathode)
	rig.wire(diode_node.terminal_anode, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)
	
	if not rig.solve(): ok = false
	if ok:
		var diode_results = rig.results(diode_node)
		if not TestUtils.assert_approx_equals(diode_results.get("current", NAN), 0.0, 1e-6, "Diode Test (Rev): Current is near zero"): ok = false
	
	rig.cleanup()
	return ok


## Tests the Potentiometer as a voltage divider, checking the wiper voltage at various positions.
func test_potentiometer_behavior() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var g = rig.graph
	var ed = rig.editor
	
	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var pot_node: Potentiometer3D = rig.add(ed.PotentiometerScene, Vector3(1,0,0))
	
	ps_node.target_voltage = 10.0; rig.cfg(ps_node)
	pot_node.total_resistance = 1000.0; rig.cfg(pot_node)

	rig.wire(ps_node.terminal_pos, pot_node.terminal1)
	rig.wire(pot_node.terminal2, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)
	
	var test_cases = [
		{"pos": 0.0, "expected_v": 10.0},
		{"pos": 0.25, "expected_v": 7.5},
		{"pos": 0.5, "expected_v": 5.0},
		{"pos": 0.75, "expected_v": 2.5},
		{"pos": 1.0, "expected_v": 0.0}
	]

	for case in test_cases:
		print("  Potentiometer Test: Wiper at {p}".format({"p": case.pos}))
		pot_node.set_wiper_position(case.pos)
		
		if not rig.solve(): ok = false; continue
		
		var wiper_node_id = g.terminal_connections.get(pot_node.terminal_wiper.get_instance_id(), -1)
		if wiper_node_id == -1:
			printerr("  Potentiometer Test: Wiper terminal's node_id not found.")
			ok = false; continue
		
		var wiper_voltage = g.electrical_nodes.get(wiper_node_id, {}).get("voltage", NAN)
		var msg = "Potentiometer Test (Wiper {p}): Voltage matches expected".format({"p": case.pos})
		if not TestUtils.assert_approx_equals(wiper_voltage, case.expected_v, 0.01, msg): ok = false

	rig.cleanup()
	return ok


## Tests the Battery component, ensuring its output voltage and supplied current are correct for different cell counts.
func test_battery_behavior() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	var bat_node: Battery3D = rig.add(ed.BatteryScene)
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	
	res_node.resistance = 1000.0
	rig.cfg(res_node)

	rig.wire(bat_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, bat_node.terminal_neg)
	rig.ground(bat_node.terminal_neg)

	var test_cases = [
		{"cells": 1, "expected_v": 1.5},
		{"cells": 2, "expected_v": 3.0},
		{"cells": 4, "expected_v": 6.0}
	]
	
	for case in test_cases:
		print("  Battery Test: {c} cells".format({"c": case.cells}))
		bat_node.set_num_cells(case.cells)
		
		if not rig.solve(): ok = false; continue
		
		var bat_results = rig.results(bat_node)
		var voltage_across = bat_results.get("voltage", NAN)
		var current_supplied = bat_results.get("current", NAN)
		var expected_current = case.expected_v / res_node.resistance
		
		var v_msg = "Battery Test ({c} cells): Voltage across terminals matches".format({"c": case.cells})
		if not TestUtils.assert_approx_equals(voltage_across, case.expected_v, 0.01, v_msg): ok = false
		
		var i_msg = "Battery Test ({c} cells): Current matches expected".format({"c": case.cells})
		if not TestUtils.assert_approx_equals(current_supplied, expected_current, 0.0001, i_msg): ok = false

	rig.cleanup()
	return ok


## Tests the Polarized Capacitor, verifying its charging behavior and that it correctly "explodes" when over-voltaged.
func test_polarized_capacitor_behavior() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var g = rig.graph
	var ed = rig.editor

	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var cap_node: PolarizedCapacitor3D = rig.add(ed.PolarizedCapacitorScene, Vector3(2,0,0))

	print("  Polarized Capacitor Test: Charging.")
	ps_node.target_voltage = 10.0; rig.cfg(ps_node)
	res_node.resistance = 1000.0; rig.cfg(res_node)
	cap_node.capacitance = 100e-6; cap_node.max_voltage = 16.0; rig.cfg(cap_node)

	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, cap_node.terminal1)
	rig.wire(cap_node.terminal2, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	var cap_voltage = 0.0
	var dt = 0.02 # Time constant is R*C = 1k * 100uF = 0.1s. 5 steps of 0.02s is 0.1s.
	for i in range(5):
		if not rig.solve(dt): ok = false; break
		var cap_results = rig.results(cap_node)
		cap_voltage = cap_results.get("voltage_across", NAN)
	
	if ok:
		var expected_voltage_after_1tc = 10.0 * (1.0 - exp(-1.0)) # ~6.32V
		if not TestUtils.assert_approx_equals(cap_voltage, expected_voltage_after_1tc, 0.5, "Polarized Capacitor Test (Charging): Voltage after ~1 TC is correct"): ok = false
		var cap_graph_data = g.component_node_map.get(cap_node)
		if not TestUtils.assert_false(cap_graph_data.get("is_exploded", true), "Polarized Capacitor Test (Charging): Capacitor is NOT exploded"): ok = false

	print("  Polarized Capacitor Test: Explosion (Overvoltage).")
	ps_node.target_voltage = 20.0; rig.cfg(ps_node)
	
	var exploded = false
	for i in range(15):
		if not rig.solve(dt): ok = false; break
		var cap_graph_data = g.component_node_map.get(cap_node)
		if cap_graph_data.get("is_exploded", false):
			exploded = true
			break
	
	if not TestUtils.assert_true(exploded, "Polarized Capacitor Test (Overvoltage): Capacitor IS exploded"): ok = false

	rig.cleanup()
	return ok


## Tests the Non-Polarized Capacitor, verifying its charging behavior in an RC circuit.
func test_non_polarized_capacitor_behavior() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var cap_node: NonPolarizedCapacitor3D = rig.add(ed.NonPolarizedCapacitorScene, Vector3(2,0,0))

	ps_node.target_voltage = 10.0; rig.cfg(ps_node)
	res_node.resistance = 1000.0; rig.cfg(res_node)
	cap_node.capacitance = 10e-6; cap_node.max_voltage = 50.0; rig.cfg(cap_node)

	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, cap_node.terminal1)
	rig.wire(cap_node.terminal2, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	var cap_voltage = 0.0
	# Time constant is R*C = 1k * 10uF = 0.01s. 5 steps of 0.002s is 0.01s (1 TC).
	var dt = 0.002
	for i in range(5):
		if not rig.solve(dt): ok = false; break
		var cap_results = rig.results(cap_node)
		cap_voltage = cap_results.get("voltage_across", NAN)

	if ok:
		var expected_voltage = 10.0 * (1.0 - exp(-1.0)) # ~6.32V
		if not TestUtils.assert_approx_equals(cap_voltage, expected_voltage, 0.5, "Non-Polarized Capacitor Test: Voltage after ~1 TC is correct"): ok = false

	rig.cleanup()
	return ok


## Tests the Inductor, verifying its current-ramping behavior in an RL circuit.
func test_inductor_behavior() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var ind_node: Inductor3D = rig.add(ed.InductorScene, Vector3(2,0,0))

	ps_node.target_voltage = 10.0; rig.cfg(ps_node)
	res_node.resistance = 100.0; rig.cfg(res_node)
	ind_node.inductance = 10e-3; rig.cfg(ind_node)

	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, ind_node.terminal1)
	rig.wire(ind_node.terminal2, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	var inductor_current = 0.0
	# Time constant is L/R = 10mH / 100R = 0.0001s (100us). 5 steps of 20us is 100us.
	var dt = 0.00002
	for i in range(5):
		if not rig.solve(dt): ok = false; break
		var ind_results = rig.results(ind_node)
		inductor_current = ind_results.get("current", NAN)

	if ok:
		var expected_current = (10.0 / 100.0) * (1.0 - exp(-1.0)) # ~0.0632A
		if not TestUtils.assert_approx_equals(inductor_current, expected_current, 0.01, "Inductor Test: Current after ~1 TC is correct"): ok = false

	rig.cleanup()
	return ok


## Tests the NPN BJT model in its three main operating regions: Cutoff, Active, and Saturation.
func test_npn_bjt_regions() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var g = rig.graph
	var ed = rig.editor

	# --- Cutoff Region ---
	print("  NPN BJT Test: Cutoff Region.")
	var ps_cutoff: PowerSource3D = rig.add(ed.PowerSourceScene)
	var rc_cutoff: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var bjt_cutoff: NPNBJT3D = rig.add(ed.NPNBJTScene, Vector3(2,0,0))

	ps_cutoff.target_voltage = 10.0; rig.cfg(ps_cutoff)
	rc_cutoff.resistance = 1000.0; rig.cfg(rc_cutoff)
	bjt_cutoff.saturation_current = 1e-15; bjt_cutoff.alpha_forward = 0.99; bjt_cutoff.alpha_reverse = 0.5; rig.cfg(bjt_cutoff)

	rig.wire(ps_cutoff.terminal_pos, rc_cutoff.terminal1)
	rig.wire(rc_cutoff.terminal2, bjt_cutoff.terminal_c)
	rig.wire(bjt_cutoff.terminal_e, ps_cutoff.terminal_neg)
	rig.wire(bjt_cutoff.terminal_b, ps_cutoff.terminal_neg)
	rig.ground(ps_cutoff.terminal_neg)

	if not rig.solve(): ok = false
	if ok:
		var results = rig.results(bjt_cutoff)
		if not TestUtils.assert_equals(results.get("region", "ERROR"), "OFF", "NPN BJT Test (Cutoff): Region is OFF"): ok = false
		if not TestUtils.assert_approx_equals(results.get("Ic", NAN), 0.0, 1e-6, "NPN BJT Test (Cutoff): Collector current is near zero"): ok = false

	# --- Active Region ---
	print("  NPN BJT Test: Active Region.")
	await rig.reset_graph()
	var ps_active_vcc: PowerSource3D = rig.add(ed.PowerSourceScene)
	var ps_active_vbb: PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,1))
	var rc_active: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var rb_active: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,1))
	var bjt_active: NPNBJT3D = rig.add(ed.NPNBJTScene, Vector3(2,0,0))

	ps_active_vcc.target_voltage = 10.0; rig.cfg(ps_active_vcc)
	ps_active_vbb.target_voltage = 2.0; rig.cfg(ps_active_vbb)
	rc_active.resistance = 1000.0; rig.cfg(rc_active)
	rb_active.resistance = 27000.0; rig.cfg(rb_active) # Changed from 10k to ensure active
	bjt_active.alpha_forward = 0.99; rig.cfg(bjt_active) # beta ~99

	rig.wire(ps_active_vcc.terminal_pos, rc_active.terminal1)
	rig.wire(rc_active.terminal2, bjt_active.terminal_c)
	rig.wire(bjt_active.terminal_e, ps_active_vcc.terminal_neg)
	rig.wire(ps_active_vbb.terminal_pos, rb_active.terminal1)
	rig.wire(rb_active.terminal2, bjt_active.terminal_b)
	rig.wire(ps_active_vbb.terminal_neg, ps_active_vcc.terminal_neg)
	rig.ground(ps_active_vcc.terminal_neg)

	if not rig.solve(): ok = false
	if ok:
		var results = rig.results(bjt_active)
		var ic = results.get("Ic", NAN)
		var ib = results.get("Ib", NAN)
		var beta = bjt_active.alpha_forward / (1.0 - bjt_active.alpha_forward)
		
		if not TestUtils.assert_equals(results.get("region", "ERROR"), "ACTIVE", "NPN BJT Test (Active): Region is ACTIVE"): ok = false
		# Vbe is not fixed, but should be ~0.7V. Ib = (2.0-0.7)/27k = ~48uA
		if not TestUtils.assert_approx_equals(ib, 4.8e-5, 1e-5, "NPN BJT Test (Active): Base current is in expected range"): ok = false
		if not TestUtils.assert_approx_equals(ic, beta * ib, 5e-4, "NPN BJT Test (Active): Collector current is beta * Ib"): ok = false

	# --- Saturation Region ---
	print("  NPN BJT Test: Saturation Region.")
	await rig.reset_graph()
	var ps_sat_vcc: PowerSource3D = rig.add(ed.PowerSourceScene)
	var ps_sat_vbb: PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,1))
	var rc_sat: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var rb_sat: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,1))
	var bjt_sat: NPNBJT3D = rig.add(ed.NPNBJTScene, Vector3(2,0,0))

	ps_sat_vcc.target_voltage = 10.0; rig.cfg(ps_sat_vcc)
	ps_sat_vbb.target_voltage = 5.0; rig.cfg(ps_sat_vbb)
	rc_sat.resistance = 1000.0; rig.cfg(rc_sat)
	rb_sat.resistance = 10000.0; rig.cfg(rb_sat)
	bjt_sat.alpha_forward = 0.99; rig.cfg(bjt_sat)
	
	rig.wire(ps_sat_vcc.terminal_pos, rc_sat.terminal1)
	rig.wire(rc_sat.terminal2, bjt_sat.terminal_c)
	rig.wire(bjt_sat.terminal_e, ps_sat_vcc.terminal_neg)
	rig.wire(ps_sat_vbb.terminal_pos, rb_sat.terminal1)
	rig.wire(rb_sat.terminal2, bjt_sat.terminal_b)
	rig.wire(ps_sat_vbb.terminal_neg, ps_sat_vcc.terminal_neg)
	rig.ground(ps_sat_vcc.terminal_neg)

	if not rig.solve(): ok = false
	if ok:
		var results = rig.results(bjt_sat)
		var vce = results.get("Vds", NAN) # Vds for MOSFET, but test reuses
		var ic = results.get("Ic", NAN)
		var ib = results.get("Ib", NAN)
		
		var node_c_id = g.terminal_connections.get(bjt_sat.terminal_c.get_instance_id(),-1)
		var node_e_id = g.terminal_connections.get(bjt_sat.terminal_e.get_instance_id(),-1)
		var vc = g.electrical_nodes.get(node_c_id, {}).get("voltage", NAN)
		var ve = g.electrical_nodes.get(node_e_id, {}).get("voltage", NAN)
		vce = vc - ve
		
		if not TestUtils.assert_equals(results.get("region", "ERROR"), "SATURATION", "NPN BJT Test (Saturation): Region is SATURATION"): ok = false
		if not TestUtils.assert_true(vce < 0.4, "NPN BJT Test (Saturation): Vce is small (<0.4V)"): ok = false
		if not TestUtils.assert_approx_equals(ic, (ps_sat_vcc.target_voltage - vce) / rc_sat.resistance, 1e-3, "NPN BJT Test (Saturation): Ic is limited by Rc"): ok = false
		# Vbe is not fixed, ~0.7-0.8V. Ib = (5.0-0.75)/10k = ~425uA
		if not TestUtils.assert_approx_equals(ib, 4.25e-4, 5e-5, "NPN BJT Test (Saturation): Ib is in expected range"): ok = false

	rig.cleanup()
	return ok


## Tests the PNP BJT model in its three main operating regions: Cutoff, Active, and Saturation.
func test_pnp_bjt_regions() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: PNP BJT Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	print("  PNP BJT Test: Cutoff Region.")
	var ps_pnp_cutoff: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var rc_pnp_cutoff: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var bjt_pnp_cutoff: PNPBJT3D = editor_script._add_component(editor_script.PNPBJTScene, Vector3(2,0,0)) as PNPBJT3D

	ps_pnp_cutoff.target_voltage = 10.0 
	graph_script.component_config_changed(ps_pnp_cutoff)
	rc_pnp_cutoff.resistance = 1000.0 
	graph_script.component_config_changed(rc_pnp_cutoff)
	graph_script.component_config_changed(bjt_pnp_cutoff)

	graph_script.connect_terminals(bjt_pnp_cutoff.terminal_e, ps_pnp_cutoff.terminal_pos) 
	graph_script.connect_terminals(bjt_pnp_cutoff.terminal_c, rc_pnp_cutoff.terminal1)   
	graph_script.connect_terminals(rc_pnp_cutoff.terminal2, ps_pnp_cutoff.terminal_neg) 
	graph_script.connect_terminals(bjt_pnp_cutoff.terminal_b, ps_pnp_cutoff.terminal_pos) 
	graph_script.set_ground_node(ps_pnp_cutoff.terminal_neg)

	var solve_pnp_cutoff = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_pnp_cutoff, "PNP BJT Test (Cutoff): Solve successful"): overall_test_passed = false
	if solve_pnp_cutoff:
		var bjt_results_pnp_cutoff = graph_script.component_results.get(bjt_pnp_cutoff.get_instance_id(), {})
		var ic_pnp_cutoff = bjt_results_pnp_cutoff.get("Ic", NAN) 
		var region_pnp_cutoff = bjt_results_pnp_cutoff.get("region", "ERROR")
		if not TestUtils.assert_equals(region_pnp_cutoff, "OFF", "PNP BJT Test (Cutoff): Region is OFF"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ic_pnp_cutoff, 0.0, 1e-6, "PNP BJT Test (Cutoff): Collector current is near zero"): overall_test_passed = false
	
	await _cleanup_components_and_graph(editor_script, graph_script)

	print("  PNP BJT Test: Active Region.")
	var ps_pnp_active_vcc: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var ps_pnp_active_vb_supply: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,1)) as PowerSource3D
	var rc_pnp_active: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var rb_pnp_active: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,1)) as Resistor3D
	var bjt_pnp_active: PNPBJT3D = editor_script._add_component(editor_script.PNPBJTScene, Vector3(2,0,0)) as PNPBJT3D
	
	ps_pnp_active_vcc.target_voltage = 10.0
	graph_script.component_config_changed(ps_pnp_active_vcc)
	ps_pnp_active_vb_supply.target_voltage = 8.0 
	graph_script.component_config_changed(ps_pnp_active_vb_supply)
	rc_pnp_active.resistance = 1000.0
	graph_script.component_config_changed(rc_pnp_active)
	rb_pnp_active.resistance = 27000.0 
	graph_script.component_config_changed(rb_pnp_active)
	bjt_pnp_active.saturation_current = 1e-15
	bjt_pnp_active.alpha_forward = 0.99 # Corresponds to beta ~99
	bjt_pnp_active.alpha_reverse = 0.5
	graph_script.component_config_changed(bjt_pnp_active)

	graph_script.connect_terminals(bjt_pnp_active.terminal_e, ps_pnp_active_vcc.terminal_pos) 
	graph_script.connect_terminals(bjt_pnp_active.terminal_c, rc_pnp_active.terminal1)   
	graph_script.connect_terminals(rc_pnp_active.terminal2, ps_pnp_active_vcc.terminal_neg) 
	graph_script.connect_terminals(bjt_pnp_active.terminal_b, rb_pnp_active.terminal1)   
	graph_script.connect_terminals(rb_pnp_active.terminal2, ps_pnp_active_vb_supply.terminal_pos) 
	graph_script.connect_terminals(ps_pnp_active_vb_supply.terminal_neg, ps_pnp_active_vcc.terminal_neg) 
	graph_script.set_ground_node(ps_pnp_active_vcc.terminal_neg)

	var solve_pnp_active = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_pnp_active, "PNP BJT Test (Active): Solve successful"): overall_test_passed = false
	if solve_pnp_active:
		var bjt_results_pnp_active = graph_script.component_results.get(bjt_pnp_active.get_instance_id(), {})
		var ic_pnp_active = bjt_results_pnp_active.get("Ic", NAN)
		var ib_pnp_active = bjt_results_pnp_active.get("Ib", NAN)
		var region_pnp_active = bjt_results_pnp_active.get("region", "ERROR")
		var beta = bjt_pnp_active.alpha_forward / (1.0 - bjt_pnp_active.alpha_forward)

		if not TestUtils.assert_equals(region_pnp_active, "ACTIVE", "PNP BJT Test (Active): Region is ACTIVE"): overall_test_passed = false
		# Veb is ~0.7V. Vb is 8V. Ve is 10V. Veb=2V is wrong. Ah, Vb is connected to a supply.
		# Ib = (Ve - Veb - Vb_supply) / Rb = (10 - 0.7 - 8.0) / 27k = 1.3/27k = ~48uA.
		if not TestUtils.assert_approx_equals(ib_pnp_active, 4.8e-5, 1e-5, "PNP BJT Test (Active): Base current is in expected range"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(abs(ic_pnp_active), beta * ib_pnp_active, 5e-4, "PNP BJT Test (Active): Collector current is beta * Ib"): overall_test_passed = false

	await _cleanup_components_and_graph(editor_script, graph_script)

	print("  PNP BJT Test: Saturation Region.")
	var ps_pnp_sat_vcc: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var ps_pnp_sat_vb_supply: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,1)) as PowerSource3D
	var rc_pnp_sat: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var rb_pnp_sat: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,1)) as Resistor3D
	var bjt_pnp_sat: PNPBJT3D = editor_script._add_component(editor_script.PNPBJTScene, Vector3(2,0,0)) as PNPBJT3D

	ps_pnp_sat_vcc.target_voltage = 10.0
	graph_script.component_config_changed(ps_pnp_sat_vcc)
	ps_pnp_sat_vb_supply.target_voltage = 5.0
	graph_script.component_config_changed(ps_pnp_sat_vb_supply)
	rc_pnp_sat.resistance = 1000.0
	graph_script.component_config_changed(rc_pnp_sat)
	rb_pnp_sat.resistance = 10000.0
	graph_script.component_config_changed(rb_pnp_sat)
	bjt_pnp_sat.alpha_forward = 0.99 # Corresponds to beta ~99
	graph_script.component_config_changed(bjt_pnp_sat)
	
	graph_script.connect_terminals(bjt_pnp_sat.terminal_e, ps_pnp_sat_vcc.terminal_pos)
	graph_script.connect_terminals(bjt_pnp_sat.terminal_c, rc_pnp_sat.terminal1)
	graph_script.connect_terminals(rc_pnp_sat.terminal2, ps_pnp_sat_vcc.terminal_neg)
	graph_script.connect_terminals(bjt_pnp_sat.terminal_b, rb_pnp_sat.terminal1)
	graph_script.connect_terminals(rb_pnp_sat.terminal2, ps_pnp_sat_vb_supply.terminal_pos)
	graph_script.connect_terminals(ps_pnp_sat_vb_supply.terminal_neg, ps_pnp_sat_vcc.terminal_neg)
	graph_script.set_ground_node(ps_pnp_sat_vcc.terminal_neg)

	var solve_pnp_sat = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_pnp_sat, "PNP BJT Test (Saturation): Solve successful"): overall_test_passed = false
	if solve_pnp_sat:
		var bjt_results_pnp_sat = graph_script.component_results.get(bjt_pnp_sat.get_instance_id(), {})
		var ic_pnp_sat = bjt_results_pnp_sat.get("Ic", NAN)
		var region_pnp_sat = bjt_results_pnp_sat.get("region", "ERROR")

		var Ve_pnp_sat_node = graph_script.electrical_nodes.get(graph_script.terminal_connections.get(bjt_pnp_sat.terminal_e.get_instance_id()), {}).get("voltage", NAN)
		var Vc_pnp_sat_node = graph_script.electrical_nodes.get(graph_script.terminal_connections.get(bjt_pnp_sat.terminal_c.get_instance_id()), {}).get("voltage", NAN)
		var Vec_actual_pnp_sat = NAN
		if not is_nan(Ve_pnp_sat_node) and not is_nan(Vc_pnp_sat_node): Vec_actual_pnp_sat = Ve_pnp_sat_node - Vc_pnp_sat_node

		if not TestUtils.assert_equals(region_pnp_sat, "SATURATION", "PNP BJT Test (Saturation): Region is SATURATION"): overall_test_passed = false
		# Vec_sat is not a param. Should be small, e.g. < 0.4V
		if not TestUtils.assert_true(Vec_actual_pnp_sat < 0.4, "PNP BJT Test (Saturation): Vec is small (<0.4V)"): overall_test_passed = false
		var expected_ic_sat_pnp = (ps_pnp_sat_vcc.target_voltage - Vec_actual_pnp_sat) / rc_pnp_sat.resistance 
		if not TestUtils.assert_approx_equals(abs(ic_pnp_sat), expected_ic_sat_pnp, 1e-3, "PNP BJT Test (Saturation): Ic is limited by Rc and Vec_sat"): overall_test_passed = false

	await _cleanup_components_and_graph(editor_script, graph_script)
	editor_instance.queue_free()
	return overall_test_passed


## Tests the Zener Diode in its three main states: Forward-biased, reverse-biased (off), and Zener breakdown.
func test_zener_diode_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Zener Diode Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var Vf_test = 0.7
	var Vz_test = 5.1
	var R_series_val = 100.0 

	print("  Zener Diode Test: Forward Bias.")
	var ps_fwd: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_fwd: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var zener_fwd: ZenerDiode3D = editor_script._add_component(editor_script.ZenerDiodeScene, Vector3(2,0,0)) as ZenerDiode3D

	ps_fwd.target_voltage = 5.0
	graph_script.component_config_changed(ps_fwd)
	res_fwd.resistance = R_series_val
	graph_script.component_config_changed(res_fwd)
	zener_fwd.zener_voltage = Vz_test
	zener_fwd.saturation_current = 1e-12
	zener_fwd.ideality_factor = 1.0
	graph_script.component_config_changed(zener_fwd)

	graph_script.connect_terminals(ps_fwd.terminal_pos, res_fwd.terminal1)
	graph_script.connect_terminals(res_fwd.terminal2, zener_fwd.terminal_anode)
	graph_script.connect_terminals(zener_fwd.terminal_kathode, ps_fwd.terminal_neg)
	graph_script.set_ground_node(ps_fwd.terminal_neg)

	var solve_fwd_z = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_fwd_z, "Zener Test (Fwd): Solve successful"): overall_test_passed = false
	if solve_fwd_z:
		var results_fwd = graph_script.component_results.get(zener_fwd.get_instance_id(), {})
		var current_fwd = results_fwd.get("current", NAN)
		var state_fwd = results_fwd.get("state", "ERROR")
		# Approximate diode forward voltage drop around 0.7V for this test's parameters
		var expected_current_fwd = (ps_fwd.target_voltage - Vf_test) / R_series_val
		if not TestUtils.assert_approx_equals(current_fwd, expected_current_fwd, 0.001, "Zener Test (Fwd): Current matches expected"): overall_test_passed = false
		if not TestUtils.assert_equals(state_fwd, "FORWARD", "Zener Test (Fwd): State is FORWARD"): overall_test_passed = false
	
	await _cleanup_components_and_graph(editor_script, graph_script)

	print("  Zener Diode Test: Reverse Bias (OFF).")
	var ps_rev_off: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_rev_off: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var zener_rev_off: ZenerDiode3D = editor_script._add_component(editor_script.ZenerDiodeScene, Vector3(2,0,0)) as ZenerDiode3D

	ps_rev_off.target_voltage = 3.0 
	graph_script.component_config_changed(ps_rev_off)
	res_rev_off.resistance = R_series_val
	graph_script.component_config_changed(res_rev_off)
	zener_rev_off.zener_voltage = Vz_test
	graph_script.component_config_changed(zener_rev_off)

	graph_script.connect_terminals(ps_rev_off.terminal_pos, res_rev_off.terminal1)
	graph_script.connect_terminals(res_rev_off.terminal2, zener_rev_off.terminal_kathode)
	graph_script.connect_terminals(zener_rev_off.terminal_anode, ps_rev_off.terminal_neg)
	graph_script.set_ground_node(ps_rev_off.terminal_neg)

	var solve_rev_off_z = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_rev_off_z, "Zener Test (Rev OFF): Solve successful"): overall_test_passed = false
	if solve_rev_off_z:
		var results_rev_off = graph_script.component_results.get(zener_rev_off.get_instance_id(), {})
		var current_rev_off = results_rev_off.get("current", NAN) 
		var state_rev_off = results_rev_off.get("state", "ERROR")
		if not TestUtils.assert_approx_equals(current_rev_off, 0.0, 1e-6, "Zener Test (Rev OFF): Current is near zero"): overall_test_passed = false
		if not TestUtils.assert_equals(state_rev_off, "OFF", "Zener Test (Rev OFF): State is OFF"): overall_test_passed = false
	
	await _cleanup_components_and_graph(editor_script, graph_script)

	print("  Zener Diode Test: Reverse Bias (ZENER Breakdown).")
	var ps_breakdown: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_breakdown: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var zener_breakdown: ZenerDiode3D = editor_script._add_component(editor_script.ZenerDiodeScene, Vector3(2,0,0)) as ZenerDiode3D

	ps_breakdown.target_voltage = 10.0 
	graph_script.component_config_changed(ps_breakdown)
	res_breakdown.resistance = R_series_val
	graph_script.component_config_changed(res_breakdown)
	zener_breakdown.zener_voltage = Vz_test
	graph_script.component_config_changed(zener_breakdown)

	graph_script.connect_terminals(ps_breakdown.terminal_pos, res_breakdown.terminal1)
	graph_script.connect_terminals(res_breakdown.terminal2, zener_breakdown.terminal_kathode)
	graph_script.connect_terminals(zener_breakdown.terminal_anode, ps_breakdown.terminal_neg)
	graph_script.set_ground_node(ps_breakdown.terminal_neg)

	var solve_breakdown_z = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_breakdown_z, "Zener Test (Breakdown): Solve successful"): overall_test_passed = false
	if solve_breakdown_z:
		var results_breakdown = graph_script.component_results.get(zener_breakdown.get_instance_id(), {})
		var current_breakdown = results_breakdown.get("current", NAN) 
		var vak_breakdown = results_breakdown.get("voltage_ak", NAN) 
		var state_breakdown = results_breakdown.get("state", "ERROR")
		
		var expected_current_breakdown = - ( (ps_breakdown.target_voltage - Vz_test) / R_series_val )
		
		if not TestUtils.assert_approx_equals(vak_breakdown, -Vz_test, 0.1, "Zener Test (Breakdown): Voltage Vak is approx -Vz"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(current_breakdown, expected_current_breakdown, 0.001, "Zener Test (Breakdown): Current matches expected"): overall_test_passed = false
		if not TestUtils.assert_equals(state_breakdown, "ZENER", "Zener Test (Breakdown): State is ZENER"): overall_test_passed = false

	await _cleanup_components_and_graph(editor_script, graph_script)
	editor_instance.queue_free()
	return overall_test_passed


## Tests the Relay component, verifying that the correct switch path (NC or NO) is active when de-energized and energized.
func test_relay_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Relay Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var relay_signal_voltage_threshold_v = 5.0 
	var relay_coil_resistance_val = 100.0 
	var load_led_vf = 1.8
	var load_led_min_i = 0.001
	var load_led_max_i = 0.020
	var load_res_val = 220.0
	var load_ps_v = 5.0 
	var signal_supply_v_off = 3.0 
	var signal_supply_v_on = 6.0  

	print("  Relay Test: De-energized (NC path active).")
	var ps_signal_supply_off: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,-1)) as PowerSource3D 
	var relay_node_off: Relay3D = editor_script._add_component(editor_script.RelayScene, Vector3.ZERO) as Relay3D
	var ps_load_off: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,1)) as PowerSource3D
	var res_nc_off: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,1)) as Resistor3D
	var led_nc_off: LED3D = editor_script._add_component(editor_script.LEDScene, Vector3(2,0,1)) as LED3D
	var res_no_off: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,1,1)) as Resistor3D 
	var led_no_off: LED3D = editor_script._add_component(editor_script.LEDScene, Vector3(2,1,1)) as LED3D       

	ps_signal_supply_off.target_voltage = signal_supply_v_off 
	graph_script.component_config_changed(ps_signal_supply_off)
	relay_node_off.signal_voltage_threshold = relay_signal_voltage_threshold_v 
	relay_node_off.coil_resistance = relay_coil_resistance_val 
	graph_script.component_config_changed(relay_node_off)
	ps_load_off.target_voltage = load_ps_v
	graph_script.component_config_changed(ps_load_off)
	res_nc_off.resistance = load_res_val; graph_script.component_config_changed(res_nc_off)
	led_nc_off.min_current_to_light = load_led_min_i; led_nc_off.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_nc_off)
	res_no_off.resistance = load_res_val; graph_script.component_config_changed(res_no_off)
	led_no_off.min_current_to_light = load_led_min_i; led_no_off.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_no_off)

	graph_script.set_ground_node(ps_load_off.terminal_neg)

	graph_script.connect_terminals(ps_signal_supply_off.terminal_pos, relay_node_off.terminal_signal)
	graph_script.connect_terminals(ps_signal_supply_off.terminal_neg, ps_load_off.terminal_neg) 

	graph_script.connect_terminals(ps_load_off.terminal_pos, relay_node_off.terminal_vcc) 
	graph_script.connect_terminals(relay_node_off.terminal_gnd, ps_load_off.terminal_neg) 
	
	graph_script.connect_terminals(ps_load_off.terminal_pos, relay_node_off.terminal_com)
	graph_script.connect_terminals(relay_node_off.terminal_nc, res_nc_off.terminal1)
	graph_script.connect_terminals(res_nc_off.terminal2, led_nc_off.terminal_anode)
	graph_script.connect_terminals(led_nc_off.terminal_kathode, ps_load_off.terminal_neg) 
	graph_script.connect_terminals(relay_node_off.terminal_no, res_no_off.terminal1) 
	graph_script.connect_terminals(res_no_off.terminal2, led_no_off.terminal_anode)
	graph_script.connect_terminals(led_no_off.terminal_kathode, ps_load_off.terminal_neg) 


	var solve_off_state = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_off_state, "Relay Test (De-energized): Solve successful"): overall_test_passed = false
	
	if solve_off_state:
		var relay_results_off = graph_script.component_results.get(relay_node_off.get_instance_id(), {})
		var is_energized_off = relay_results_off.get("is_energized", true) 
		if not TestUtils.assert_false(is_energized_off, "Relay Test (De-energized): Relay is_energized is false"): overall_test_passed = false

		var led_nc_results_off = graph_script.component_results.get(led_nc_off.get_instance_id(), {})
		var led_nc_current_off = led_nc_results_off.get("current", NAN)
		# Approximate LED forward voltage drop around 1.8V for this test's parameters
		var expected_load_current_on = (load_ps_v - load_led_vf) / load_res_val
		if not TestUtils.assert_approx_equals(led_nc_current_off, expected_load_current_on, 0.001, "Relay Test (De-energized): NC LED current is ON"): overall_test_passed = false

		var led_no_results_off = graph_script.component_results.get(led_no_off.get_instance_id(), {})
		var led_no_current_off = led_no_results_off.get("current", NAN)
		if not TestUtils.assert_approx_equals(led_no_current_off, 0.0, 1e-6, "Relay Test (De-energized): NO LED current is OFF"): overall_test_passed = false

	await _cleanup_components_and_graph(editor_script, graph_script)

	print("  Relay Test: Energized (NO path active).")
	var ps_signal_supply_on: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,-1)) as PowerSource3D 
	var relay_node_on: Relay3D = editor_script._add_component(editor_script.RelayScene, Vector3.ZERO) as Relay3D
	var ps_load_on: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,1)) as PowerSource3D
	var res_nc_on: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,1)) as Resistor3D 
	var led_nc_on: LED3D = editor_script._add_component(editor_script.LEDScene, Vector3(2,0,1)) as LED3D       
	var res_no_on: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,1,1)) as Resistor3D
	var led_no_on: LED3D = editor_script._add_component(editor_script.LEDScene, Vector3(2,1,1)) as LED3D

	ps_signal_supply_on.target_voltage = signal_supply_v_on 
	graph_script.component_config_changed(ps_signal_supply_on)
	relay_node_on.signal_voltage_threshold = relay_signal_voltage_threshold_v 
	relay_node_on.coil_resistance = relay_coil_resistance_val 
	graph_script.component_config_changed(relay_node_on)
	ps_load_on.target_voltage = load_ps_v 
	graph_script.component_config_changed(ps_load_on)
	res_nc_on.resistance = load_res_val; graph_script.component_config_changed(res_nc_on)
	led_nc_on.min_current_to_light = load_led_min_i; led_nc_on.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_nc_on)
	res_no_on.resistance = load_res_val; graph_script.component_config_changed(res_no_on)
	led_no_on.min_current_to_light = load_led_min_i; led_no_on.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_no_on)

	graph_script.set_ground_node(ps_load_on.terminal_neg)

	graph_script.connect_terminals(ps_signal_supply_on.terminal_pos, relay_node_on.terminal_signal)
	graph_script.connect_terminals(ps_signal_supply_on.terminal_neg, ps_load_on.terminal_neg) 

	graph_script.connect_terminals(ps_load_on.terminal_pos, relay_node_on.terminal_vcc) 
	graph_script.connect_terminals(relay_node_on.terminal_gnd, ps_load_on.terminal_neg) 

	graph_script.connect_terminals(ps_load_on.terminal_pos, relay_node_on.terminal_com) 
	graph_script.connect_terminals(relay_node_on.terminal_nc, res_nc_on.terminal1)
	graph_script.connect_terminals(res_nc_on.terminal2, led_nc_on.terminal_anode)
	graph_script.connect_terminals(led_nc_on.terminal_kathode, ps_load_on.terminal_neg) 
	graph_script.connect_terminals(relay_node_on.terminal_no, res_no_on.terminal1) 
	graph_script.connect_terminals(res_no_on.terminal2, led_no_on.terminal_anode)
	graph_script.connect_terminals(led_no_on.terminal_kathode, ps_load_on.terminal_neg) 


	var solve_on_state = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_on_state, "Relay Test (Energized): Solve successful"): overall_test_passed = false
	
	if solve_on_state:
		var relay_results_on = graph_script.component_results.get(relay_node_on.get_instance_id(), {})
		var is_energized_on = relay_results_on.get("is_energized", false) 
		if not TestUtils.assert_true(is_energized_on, "Relay Test (Energized): Relay is_energized is true"): overall_test_passed = false

		var led_no_results_on = graph_script.component_results.get(led_no_on.get_instance_id(), {})
		var led_no_current_on = led_no_results_on.get("current", NAN)
		# Approximate LED forward voltage drop around 1.8V for this test's parameters
		var expected_load_current_on = (load_ps_v - load_led_vf) / load_res_val 
		if not TestUtils.assert_approx_equals(led_no_current_on, expected_load_current_on, 0.001, "Relay Test (Energized): NO LED current is ON"): overall_test_passed = false

		var led_nc_results_on = graph_script.component_results.get(led_nc_on.get_instance_id(), {})
		var led_nc_current_on = led_nc_results_on.get("current", NAN)
		if not TestUtils.assert_approx_equals(led_nc_current_on, 0.0, 1e-6, "Relay Test (Energized): NC LED current is OFF"): overall_test_passed = false

	await _cleanup_components_and_graph(editor_script, graph_script)
	editor_instance.queue_free()
	return overall_test_passed


## Tests that an LED correctly enters the "burned" state when subjected to excessive current.
func test_led_burnout() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var g = rig.graph
	var ed = rig.editor

	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var led_node: LED3D = rig.add(ed.LEDScene, Vector3(2,0,0))

	ps_node.target_voltage = 5.0; ps_node.target_current = 0.5; rig.cfg(ps_node)
	res_node.resistance = 10.0; rig.cfg(res_node)
	led_node.max_current_before_burn = 0.020; rig.cfg(led_node)
	led_node.saturation_current = 1e-12
	led_node.ideality_factor = 1.5

	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, led_node.terminal_anode)
	rig.wire(led_node.terminal_kathode, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)
	
	if not rig.solve(): ok = false
	if ok:
		var led_graph_data = g.component_node_map.get(led_node)
		if led_graph_data:
			if not TestUtils.assert_true(led_graph_data.get("is_burned", false), "LED is burned"): ok = false
		else:
			printerr("  ASSERT FAIL: Could not find LED graph data for burnout test.")
			ok = false
	
	rig.cleanup()
	return ok

## Tests that an LED does not visibly light up when the current is below its minimum threshold.
func test_led_not_lighting() -> bool:
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene)
	var res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(1,0,0))
	var led_node: LED3D = rig.add(ed.LEDScene, Vector3(2,0,0))

	ps_node.target_voltage = 5.0; rig.cfg(ps_node)
	res_node.resistance = 10000.0; rig.cfg(res_node)
	led_node.min_current_to_light = 0.005; rig.cfg(led_node)

	rig.wire(ps_node.terminal_pos, res_node.terminal1)
	rig.wire(res_node.terminal2, led_node.terminal_anode)
	rig.wire(led_node.terminal_kathode, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	if not rig.solve(): ok = false
	if ok:
		var led_results = rig.results(led_node)
		var led_current = led_results.get("current", NAN)
		# Approximate LED forward voltage drop around 2.0V for this test's parameters
		if not TestUtils.assert_approx_equals(led_current, (5.0-2.0)/10000.0, 0.0001, "LED current (low) matches expected"): ok = false
		if not led_current < led_node.min_current_to_light:
			TestUtils.assert_false(true, "LED current should be below min_current_to_light")
			ok = false
	
	rig.cleanup()
	return ok


## Tests the N-Channel MOSFET model in its three main operating regions: OFF, TRIODE, and SATURATION.
func test_nmosfet_regions() -> bool:
	var ok := true
	var ed_inst : Node3D = CircuitEditorScene.instantiate()
	add_child(ed_inst)
	await get_tree().process_frame
	var ed : CircuitEditor3D = ed_inst
	var g  : CircuitGraph   = ed.circuit_graph
	if not (is_instance_valid(ed) and is_instance_valid(g)):
		printerr("  SETUP FAIL: N-MOSFET Test – editor/graph invalid.")
		if is_instance_valid(ed_inst): ed_inst.queue_free()
		return false

	# ---------- OFF (cut-off) ----------
	print("  N-MOSFET Test: OFF region.")
	var ps_d_off  : PowerSource3D     = ed._add_component(ed.PowerSourceScene, Vector3.ZERO)
	var ps_g_off  : PowerSource3D     = ed._add_component(ed.PowerSourceScene, Vector3(0,0,1))
	var r_off     : Resistor3D        = ed._add_component(ed.ResistorScene,     Vector3(1,0,0))
	var mos_off   : NChannelMOSFET3D  = ed._add_component(ed.NChannelMOSFETScene, Vector3(2,0,0))

	ps_d_off.target_voltage = 5.0 ; g.component_config_changed(ps_d_off)
	ps_g_off.target_voltage = 0.0 ; g.component_config_changed(ps_g_off)
	r_off.resistance        = 1000.0 ; g.component_config_changed(r_off)

	g.connect_terminals(ps_d_off.terminal_pos, r_off.terminal1)
	g.connect_terminals(r_off.terminal2, mos_off.terminal_d)
	g.connect_terminals(mos_off.terminal_g,  ps_g_off.terminal_pos)
	g.connect_terminals(mos_off.terminal_s,  ps_d_off.terminal_neg) # common GND
	g.connect_terminals(ps_g_off.terminal_neg, ps_d_off.terminal_neg)
	g.set_ground_node(ps_d_off.terminal_neg)

	var solved := g.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solved, "NMOS Test (OFF): Solve successful"): ok = false
	if solved:
		var res = g.component_results.get(mos_off.get_instance_id(), {})
		if not TestUtils.assert_equals(res.get("region",""), "OFF", "NMOS Test (OFF): Region is OFF"): ok = false
		if not TestUtils.assert_approx_equals(res.get("Id", NAN), 0.0, 1e-6, "NMOS Test (OFF): Id ~ 0"): ok = false

	await _cleanup_components_and_graph(ed, g)

	# ---------- TRIODE ----------
	print("  N-MOSFET Test: TRIODE region.")
	var ps_d_tri : PowerSource3D     = ed._add_component(ed.PowerSourceScene, Vector3.ZERO)
	var ps_g_tri : PowerSource3D     = ed._add_component(ed.PowerSourceScene, Vector3(0,0,1))
	var mos_tri  : NChannelMOSFET3D  = ed._add_component(ed.NChannelMOSFETScene, Vector3(2,0,0))

	ps_d_tri.target_voltage = 2.0 ; g.component_config_changed(ps_d_tri)
	ps_g_tri.target_voltage = 5.0 ; g.component_config_changed(ps_g_tri)

	g.connect_terminals(ps_d_tri.terminal_pos, mos_tri.terminal_d)
	g.connect_terminals(mos_tri.terminal_g,  ps_g_tri.terminal_pos)
	g.connect_terminals(mos_tri.terminal_s,  ps_d_tri.terminal_neg)
	g.connect_terminals(ps_g_tri.terminal_neg, ps_d_tri.terminal_neg)
	g.set_ground_node(ps_d_tri.terminal_neg)

	solved = g.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solved, "NMOS Test (TRI): Solve successful"): ok = false
	if solved:
		var res_tri = g.component_results.get(mos_tri.get_instance_id(), {})
		var region  = res_tri.get("region", "")
		var Id_tri  = res_tri.get("Id", NAN)
		if not TestUtils.assert_equals(region, "TRIODE", "NMOS Test (TRI): Region is TRIODE"): ok = false

		var Vd = g.electrical_nodes.get(g.terminal_connections.get(mos_tri.terminal_d.get_instance_id(), -1), {}).get("voltage", NAN)
		var Vgs := ps_g_tri.target_voltage
		var Vds = Vd
		var kn  := mos_tri.transconductance_parameter
		var vt  := mos_tri.threshold_voltage
		var Id_expect = kn * ( (Vgs - vt) * Vds - 0.5 * pow(Vds, 2) )
		if Id_expect < 0: Id_expect = 0
		if not TestUtils.assert_approx_equals(Id_tri, Id_expect, 0.01, "NMOS Test (TRI): Id matches expected"): ok = false

	await _cleanup_components_and_graph(ed, g)

	# ---------- SATURATION ----------
	print("  N-MOSFET Test: SATURATION region.")
	var ps_d_sat : PowerSource3D     = ed._add_component(ed.PowerSourceScene, Vector3.ZERO)
	var ps_g_sat : PowerSource3D     = ed._add_component(ed.PowerSourceScene, Vector3(0,0,1))
	var mos_sat  : NChannelMOSFET3D  = ed._add_component(ed.NChannelMOSFETScene, Vector3(2,0,0))

	ps_d_sat.target_voltage = 10.0 ; g.component_config_changed(ps_d_sat)
	ps_g_sat.target_voltage = 5.0  ; g.component_config_changed(ps_g_sat)

	g.connect_terminals(ps_d_sat.terminal_pos, mos_sat.terminal_d)
	g.connect_terminals(mos_sat.terminal_g,  ps_g_sat.terminal_pos)
	g.connect_terminals(mos_sat.terminal_s,  ps_d_sat.terminal_neg)
	g.connect_terminals(ps_g_sat.terminal_neg, ps_d_sat.terminal_neg)
	g.set_ground_node(ps_d_sat.terminal_neg)

	solved = g.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solved, "NMOS Test (SAT): Solve successful"): ok = false
	if solved:
		var res_sat = g.component_results.get(mos_sat.get_instance_id(), {})
		if not TestUtils.assert_equals(res_sat.get("region",""), "SATURATION", "NMOS Test (SAT): Region is SATURATION"): ok = false
		var Id_sat = res_sat.get("Id", NAN)
		var Id_expected_sat := 0.5 * mos_sat.transconductance_parameter * pow(ps_g_sat.target_voltage - mos_sat.threshold_voltage, 2)
		if not TestUtils.assert_approx_equals(Id_sat, Id_expected_sat, 0.01, "NMOS Test (SAT): Id matches expected"): ok = false

	await _cleanup_components_and_graph(ed, g)
	ed_inst.queue_free()
	return ok

## Tests the P-Channel MOSFET model in its three main operating regions: OFF, TRIODE, and SATURATION.
func test_pmosfet_regions() -> bool:
	print("  P-MOSFET Test: starting")
	var ok := true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var g = rig.graph
	var ed = rig.editor

	# ---- OFF ----
	var ps_s_off : PowerSource3D    = rig.add(ed.PowerSourceScene)
	var ps_g_off : PowerSource3D    = rig.add(ed.PowerSourceScene, Vector3(0,0,1))
	var pmos_off : PChannelMOSFET3D = rig.add(ed.PChannelMOSFETScene, Vector3(2,0,0))

	ps_s_off.target_voltage = 10.0          # Source @ +10 V
	ps_g_off.target_voltage = 10.0          # Gate same ⇒ Vsg = 0 ⇒ OFF
	rig.cfg(ps_s_off); rig.cfg(ps_g_off)

	g.connect_terminals(pmos_off.terminal_s, ps_s_off.terminal_pos)
	g.connect_terminals(pmos_off.terminal_d, ps_s_off.terminal_neg) # Drain to GND
	g.connect_terminals(pmos_off.terminal_g, ps_g_off.terminal_pos)
	g.connect_terminals(ps_g_off.terminal_neg, ps_s_off.terminal_neg)
	rig.ground(ps_s_off.terminal_neg)

	if not rig.solve(): ok = false
	var res = rig.results(pmos_off)
	var region_str = res.get("region", "N/A")
	var id_val = res.get("Id", NAN)
	print_debug("    OFF solve → region=" + region_str + " , Id=" + str(id_val))
	if not TestUtils.assert_equals(res.get("region",""), "OFF", "PMOS Test (OFF): Region is OFF"): ok = false
	if not TestUtils.assert_approx_equals(res.get("Id",0.0), 0.0, 1e-6, "PMOS Test (OFF): Id ~ 0"): ok = false
	# ---- TRIODE ----
	rig.reset_graph()
	var ps_s_tr : PowerSource3D     = rig.add(ed.PowerSourceScene)
	var ps_g_tr : PowerSource3D     = rig.add(ed.PowerSourceScene, Vector3(0,0,1))
	var ps_d_tr : PowerSource3D     = rig.add(ed.PowerSourceScene, Vector3(0,0,2))   # NEW
	var pmos_tr : PChannelMOSFET3D  = rig.add(ed.PChannelMOSFETScene, Vector3(2,0,0))

	ps_s_tr.target_voltage = 5.0
	ps_g_tr.target_voltage = 2.0          # Vsg = 3 V  (> |Vtp|)
	ps_d_tr.target_voltage = 4.0          # Drain at +4 V  ⇒  Vsd = 1 V   (≤ Vsg–Vtp) → TRIODE
	rig.cfg(ps_s_tr); rig.cfg(ps_g_tr); rig.cfg(ps_d_tr)

	g.connect_terminals(pmos_tr.terminal_s, ps_s_tr.terminal_pos)
	g.connect_terminals(pmos_tr.terminal_d, ps_d_tr.terminal_pos)        # CHANGED
	g.connect_terminals(pmos_tr.terminal_g, ps_g_tr.terminal_pos)
	g.connect_terminals(ps_g_tr.terminal_neg, ps_s_tr.terminal_neg)
	g.connect_terminals(ps_d_tr.terminal_neg, ps_s_tr.terminal_neg)      # NEW
	rig.ground(ps_s_tr.terminal_neg)

	if not rig.solve(): ok = false
	res = rig.results(pmos_tr)
	region_str = res.get("region", "N/A")
	id_val = res.get("Id", NAN)
	print_debug("    TRIODE solve → region=" + region_str + " , Id=" + str(id_val))
	if not TestUtils.assert_equals(res.get("region",""), "TRIODE", "PMOS Test (TRI): Region is TRIODE"): ok = false
	var Vsg_tri = res.get("Vgs", NAN) * -1.0
	var Vsd_tri = res.get("Vds", NAN) * -1.0
	var kp_tri = pmos_tr.transconductance_parameter
	var vt_tri = pmos_tr.threshold_voltage
	var expected_id_tri = kp_tri * ( (Vsg_tri - vt_tri) * Vsd_tri - 0.5 * pow(Vsd_tri, 2) )
	if not TestUtils.assert_approx_equals(id_val, expected_id_tri, 0.01, "PMOS Test (TRI): Id matches expected"): ok = false
	# ---- SATURATION ----
	rig.reset_graph()
	var ps_s_sat : PowerSource3D     = rig.add(ed.PowerSourceScene)
	var ps_g_sat : PowerSource3D     = rig.add(ed.PowerSourceScene, Vector3(0,0,1))
	var pmos_sat : PChannelMOSFET3D  = rig.add(ed.PChannelMOSFETScene, Vector3(2,0,0))

	ps_s_sat.target_voltage = 10.0
	ps_g_sat.target_voltage = 5.0     # Vsg = 5  (>|Vt|)
	rig.cfg(ps_s_sat); rig.cfg(ps_g_sat)

	g.connect_terminals(pmos_sat.terminal_s, ps_s_sat.terminal_pos)
	g.connect_terminals(pmos_sat.terminal_d, ps_s_sat.terminal_neg)
	g.connect_terminals(pmos_sat.terminal_g, ps_g_sat.terminal_pos)
	g.connect_terminals(ps_g_sat.terminal_neg, ps_s_sat.terminal_neg)
	rig.ground(ps_s_sat.terminal_neg)
	if not rig.solve(): ok = false
	res = rig.results(pmos_sat)
	region_str = res.get("region", "N/A")
	id_val = res.get("Id", NAN)
	print_debug("    SAT solve → region=" + region_str + " , Id=" + str(id_val))
	if not TestUtils.assert_equals(res.get("region",""), "SATURATION", "PMOS Test (SAT): Region is SATURATION"): ok = false
	var Vsg_sat = res.get("Vgs", NAN) * -1.0
	var kp_sat = pmos_sat.transconductance_parameter
	var vt_sat = pmos_sat.threshold_voltage
	var expected_id_sat = 0.5 * kp_sat * pow(Vsg_sat - vt_sat, 2)
	if not TestUtils.assert_approx_equals(id_val, expected_id_sat, 0.01, "PMOS Test (SAT): Id matches expected"): ok = false
	rig.cleanup()
	return ok

## Tests the Linear Regulator model under normal operating conditions where Vin is well above Vout + dropout.
func test_linear_regulator_normal() -> bool:
	var overall_test_passed = true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var ed = rig.editor

	# Setup components
	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,0))
	var reg_node: LinearRegulator3D = rig.add(ed.LinearRegulatorScene, Vector3(1,0,0))
	var load_res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(2,0,0))

	# Configure components
	ps_node.target_voltage = 12.0
	rig.cfg(ps_node)

	reg_node.regulated_voltage = 5.0
	reg_node.dropout_voltage = 2.0
	reg_node.max_current = 1.0
	rig.cfg(reg_node)

	load_res_node.resistance = 100.0
	rig.cfg(load_res_node)

	# Wiring
	rig.wire(ps_node.terminal_pos, reg_node.terminal_vin)
	rig.wire(reg_node.terminal_vout, load_res_node.terminal1)
	rig.wire(load_res_node.terminal2, reg_node.terminal_gnd)
	rig.wire(reg_node.terminal_gnd, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	# Solve
	var solve_success: bool = rig.solve()
	if not TestUtils.assert_true(solve_success, "Simulation solve_single_time_step successful"):
		rig.cleanup()
		return false

	# Verify results
	var expected_vout = 5.0
	if solve_success:
		# Use stored results instead of electrical nodes
		var reg_results = rig.results(reg_node)
		var vout = reg_results.get("voltage", NAN)
		var status = reg_results.get("status", "UNKNOWN")
		
		# Increase voltage tolerance to 0.05
		if not TestUtils.assert_approx_equals(vout, expected_vout, 0.05, "Output voltage is regulated"):
			overall_test_passed = false
		if not TestUtils.assert_equals(status, "REGULATED", "Regulator status is REGULATED"):
			overall_test_passed = false

	rig.cleanup()
	return overall_test_passed

## Tests the Linear Regulator model in a dropout scenario where Vin is too low for proper regulation.
func test_linear_regulator_dropout() -> bool:
	var overall_test_passed = true
	var rig := TestRig.new()
	add_child(rig)
	await rig.init()
	var g = rig.graph
	var ed = rig.editor

	# Setup components
	var ps_node: PowerSource3D = rig.add(ed.PowerSourceScene, Vector3(0,0,0))
	var reg_node: LinearRegulator3D = rig.add(ed.LinearRegulatorScene, Vector3(1,0,0))
	var load_res_node: Resistor3D = rig.add(ed.ResistorScene, Vector3(2,0,0))

	# Configure components - Vin only 1V above required
	ps_node.target_voltage = 6.0  # 5V regulated + 1V (less than 2V dropout)
	rig.cfg(ps_node)

	reg_node.regulated_voltage = 5.0
	reg_node.dropout_voltage = 2.0
	reg_node.max_current = 1.0
	rig.cfg(reg_node)

	load_res_node.resistance = 100.0
	rig.cfg(load_res_node)

	# Wiring
	rig.wire(ps_node.terminal_pos, reg_node.terminal_vin)
	rig.wire(reg_node.terminal_vout, load_res_node.terminal1)
	rig.wire(load_res_node.terminal2, reg_node.terminal_gnd)
	rig.wire(reg_node.terminal_gnd, ps_node.terminal_neg)
	rig.ground(ps_node.terminal_neg)

	# Solve
	var solve_success: bool = rig.solve()
	if not TestUtils.assert_true(solve_success, "Simulation solve_single_time_step successful"):
		rig.cleanup()
		return false

	# Verify results
	if solve_success:
		# Use stored results instead of electrical nodes
		var reg_results = rig.results(reg_node)
		var vout = reg_results.get("voltage", NAN)
		var status = reg_results.get("status", "UNKNOWN")
		
		# Expected Vout = Vin - dropout_voltage (property behavior)
		var vin = g.electrical_nodes.get(g.terminal_connections.get(reg_node.terminal_vin.get_instance_id()), {}).get("voltage", NAN)
		var delta_expected = reg_node.dropout_voltage
		var expected_vout = vin - delta_expected
		
		# Increase voltage tolerance to 0.05
		if not TestUtils.assert_approx_equals(vout, expected_vout, 0.05, "Output voltage in dropout matches expected"):
			overall_test_passed = false
		if not TestUtils.assert_equals(status, "DROPOUT", "Regulator status is DROPOUT"):
			overall_test_passed = false

	rig.cleanup()
	return overall_test_passed
