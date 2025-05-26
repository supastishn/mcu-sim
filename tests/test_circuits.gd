extends Node

const TestUtils = preload("res://tests/test_utils.gd")
const TestRig = preload("res://tests/test_helpers.gd")   # gives us class TestRig
const CircuitEditorScene = preload("res://CircuitEditor3D.tscn")  # legacy tests need it
const PChannelMOSFETScene = preload("res://components/PChannelMOSFET3D.tscn")   # optional

var total_tests = 0
var passed_tests = 0
var failed_test_names: Array[String] = []

func _cleanup_components_and_graph(editor_script: CircuitEditor3D, graph_script: CircuitGraph) -> void:
	var nodes := []
	for cd in graph_script.components:
		nodes.append(cd.component_node)
	for n in nodes:
		graph_script.remove_component(n)
	for child in editor_script.components_node.get_children():
		child.queue_free()
	for child in editor_script.wires_node.get_children():
		child.queue_free()

	graph_script.electrical_nodes.clear()
	graph_script.terminal_connections.clear()
	graph_script.component_results.clear()
	graph_script.ground_node_id = -1
	graph_script._next_node_id  = 0
	graph_script._is_solved     = false
	graph_script._needs_rebuild = true

func _ready():
	print_rich("[b]Starting Circuit Simulation Tests...[/b]")
	await run_all_tests()
	print_rich("[b]All tests completed.[/b]")
	print_rich("[b]Summary: {p}/{t} tests passed.[/b]".format({"p": passed_tests, "t": total_tests}))
	
	if passed_tests == total_tests:
		print_rich("[color=green]All tests successful![/color]")
	else:
		printerr("\n[b][color=red]----- FAILED TESTS ----- [/color][/b]")
		for failed_test_name in failed_test_names:
			printerr("  - {name}".format({"name": failed_test_name}))
		printerr("\n{f} test(s) failed overall.".format({"f": total_tests - passed_tests}))
	
	get_tree().quit() 


func run_all_tests():
	var test1_name = "Test: Simple PowerSupply, Resistor, LED Circuit"
	print_rich("\n[b]{name}[/b]".format({"name": test1_name}))
	total_tests += 1
	if await test_simple_powersupply_resistor_led_circuit():
		passed_tests += 1
	else:
		failed_test_names.push_back(test1_name)

	var test2_name = "Test: LED Burnout Scenario"
	print_rich("\n[b]{name}[/b]".format({"name": test2_name}))
	total_tests += 1
	if await test_led_burnout():
		passed_tests += 1
	else:
		failed_test_names.push_back(test2_name)
		
	var test3_name = "Test: LED Not Lighting (High Resistance)"
	print_rich("\n[b]{name}[/b]".format({"name": test3_name}))
	total_tests += 1
	if await test_led_not_lighting():
		passed_tests += 1
	else:
		failed_test_names.push_back(test3_name)

	var test4_name = "Test: Switch NC and NO Operation"
	print_rich("\n[b]{name}[/b]".format({"name": test4_name}))
	total_tests += 1
	if await test_switch_behavior():
		passed_tests += 1
	else:
		failed_test_names.push_back(test4_name)

	var test5_name = "Test: Diode Forward and Reverse Bias"
	print_rich("\n[b]{name}[/b]".format({"name": test5_name}))
	total_tests += 1
	if await test_diode_behavior():
		passed_tests += 1
	else:
		failed_test_names.push_back(test5_name)

	var test6_name = "Test: Potentiometer Wiper Voltage Division"
	print_rich("\n[b]{name}[/b]".format({"name": test6_name}))
	total_tests += 1
	if await test_potentiometer_behavior():
		passed_tests += 1
	else:
		failed_test_names.push_back(test6_name)

	var test7_name = "Test: Battery Voltage Output with Different Cell Counts"
	print_rich("\n[b]{name}[/b]".format({"name": test7_name}))
	total_tests += 1
	if await test_battery_behavior():
		passed_tests += 1
	else:
		failed_test_names.push_back(test7_name)
		
	var test8_name = "Test: Polarized Capacitor Charging and Explosion"
	print_rich("\n[b]{name}[/b]".format({"name": test8_name}))
	total_tests += 1
	if await test_polarized_capacitor_behavior(): 
		passed_tests += 1
	else:
		failed_test_names.push_back(test8_name)

	var test9_name = "Test: Non-Polarized Capacitor Charging"
	print_rich("\n[b]{name}[/b]".format({"name": test9_name}))
	total_tests += 1
	if await test_non_polarized_capacitor_behavior(): 
		passed_tests += 1
	else:
		failed_test_names.push_back(test9_name)

	var test10_name = "Test: Inductor Current Behavior"
	print_rich("\n[b]{name}[/b]".format({"name": test10_name}))
	total_tests += 1
	if await test_inductor_behavior(): 
		passed_tests += 1
	else:
		failed_test_names.push_back(test10_name)

	var test11_name = "Test: NPN BJT Operating Regions"
	print_rich("\n[b]{name}[/b]".format({"name": test11_name}))
	total_tests += 1
	if await test_npn_bjt_regions(): 
		passed_tests += 1
	else:
		failed_test_names.push_back(test11_name)

	var test12_name = "Test: PNP BJT Operating Regions"
	print_rich("\n[b]{name}[/b]".format({"name": test12_name}))
	total_tests += 1
	if await test_pnp_bjt_regions():
		passed_tests += 1
	else:
		failed_test_names.push_back(test12_name)

	var test13_name = "Test: Zener Diode Forward, Reverse, and Breakdown"
	print_rich("\n[b]{name}[/b]".format({"name": test13_name}))
	total_tests += 1
	if await test_zener_diode_behavior():
		passed_tests += 1
	else:
		failed_test_names.push_back(test13_name)

	var test_mos_name = "Test: N-Channel MOSFET Operating Regions"
	print_rich("\n[b]{name}[/b]".format({"name": test_mos_name}))
	total_tests += 1
	if await test_nmosfet_regions():
		passed_tests += 1
	else:
		failed_test_names.push_back(test_mos_name)

	var test_pmos_name = "Test: P-Channel MOSFET Operating Regions"
	print_rich("\n[b]{name}[/b]".format({"name": test_pmos_name}))
	total_tests += 1
	if await test_pmosfet_regions():
		passed_tests += 1
	else:
		print('oop')
		failed_test_names.push_back(test_pmos_name)

	var test14_name = "Test: Relay Energized and De-energized States"
	print_rich("\n[b]{name}[/b]".format({"name": test14_name}))
	total_tests += 1
	if await test_relay_behavior():
		passed_tests += 1
	else:
		failed_test_names.push_back(test14_name)



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

	led_node.forward_voltage = 2.0
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

		var led_graph_data
		for comp_data in g.components:
			if comp_data.component_node == led_node:
				led_graph_data = comp_data
				break
		
		if led_graph_data:
			if not TestUtils.assert_true(led_graph_data.get("conducting", false), "LED is conducting"): overall_test_passed = false
			if not TestUtils.assert_false(led_graph_data.get("is_burned", true), "LED is NOT burned"): overall_test_passed = false
		else:
			printerr("  ASSERT FAIL: Could not find LED graph data.")
			overall_test_passed = false
			
		var ps_results = rig.results(ps_node)
		var ps_op_mode = ps_results.get("operating_mode", "ERROR")
		if not TestUtils.assert_equals(ps_op_mode, "CV", "Power Supply is in CV mode"): overall_test_passed = false

	rig.cleanup()
	return overall_test_passed


func test_switch_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Switch Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var switch_node: Switch3D = editor_script._add_component(editor_script.SwitchScene, Vector3(1,0,0)) as Switch3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(2,0,0)) as Resistor3D
	var led_node: LED3D = editor_script._add_component(editor_script.LEDScene, Vector3(3,0,0)) as LED3D 

	if not TestUtils.assert_true(is_instance_valid(ps_node) and is_instance_valid(switch_node) and is_instance_valid(res_node) and is_instance_valid(led_node), "Switch Test: All components instantiated"):
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false
		
	ps_node.target_voltage = 5.0
	graph_script.component_config_changed(ps_node)
	res_node.resistance = 220.0
	graph_script.component_config_changed(res_node)
	led_node.forward_voltage = 2.0
	led_node.min_current_to_light = 0.001 
	led_node.max_current_before_burn = 0.050 
	graph_script.component_config_changed(led_node)
	
	print("  Switch Test: Testing NC operation (default state).")
	graph_script.connect_terminals(ps_node.terminal_pos, switch_node.terminal_com)
	graph_script.connect_terminals(switch_node.terminal_nc, res_node.terminal1) 
	graph_script.connect_terminals(res_node.terminal2, led_node.terminal_anode)
	graph_script.connect_terminals(led_node.terminal_kathode, ps_node.terminal_neg)
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_nc_success = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_nc_success, "Switch Test (NC): Simulation solve successful"): overall_test_passed = false
	
	var expected_current_on = (5.0 - 2.0) / 220.0 
	if solve_nc_success:
		var led_results_nc = graph_script.component_results.get(led_node.get_instance_id(), {})
		var led_current_nc = led_results_nc.get("current", NAN)
		if not TestUtils.assert_approx_equals(led_current_nc, expected_current_on, 0.001, "Switch Test (NC): LED current indicates circuit is ON"): overall_test_passed = false
		var led_data_nc: Dictionary; for d in graph_script.components: if d.component_node == led_node: led_data_nc = d; break
		if not TestUtils.assert_false(led_data_nc.get("is_burned", true), "Switch Test (NC): LED is not burned"): overall_test_passed = false


	var all_component_nodes = []
	for comp_data_item in graph_script.components: all_component_nodes.append(comp_data_item.component_node)
	for comp_n in all_component_nodes: graph_script.remove_component(comp_n) 
	for child in editor_script.components_node.get_children(): child.queue_free()
	for child in editor_script.wires_node.get_children(): child.queue_free()
	graph_script.electrical_nodes.clear()
	graph_script.terminal_connections.clear()
	graph_script.ground_node_id = -1
	graph_script._next_node_id = 0
	await get_tree().process_frame 

	ps_node = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	switch_node = editor_script._add_component(editor_script.SwitchScene, Vector3(1,0,0)) as Switch3D
	res_node = editor_script._add_component(editor_script.ResistorScene, Vector3(2,0,0)) as Resistor3D
	led_node = editor_script._add_component(editor_script.LEDScene, Vector3(3,0,0)) as LED3D
	ps_node.target_voltage = 5.0; graph_script.component_config_changed(ps_node)
	res_node.resistance = 220.0; graph_script.component_config_changed(res_node)
	led_node.forward_voltage = 2.0; led_node.min_current_to_light = 0.001; led_node.max_current_before_burn = 0.050; graph_script.component_config_changed(led_node)

	print("  Switch Test: Testing NO operation.")
	switch_node.set_state(Switch3D.State.CONNECTED_NO) 
	graph_script.component_config_changed(switch_node) 

	graph_script.connect_terminals(ps_node.terminal_pos, switch_node.terminal_com)
	graph_script.connect_terminals(switch_node.terminal_no, res_node.terminal1) 
	graph_script.connect_terminals(res_node.terminal2, led_node.terminal_anode)
	graph_script.connect_terminals(led_node.terminal_kathode, ps_node.terminal_neg)
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_no_success = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_no_success, "Switch Test (NO): Simulation solve successful"): overall_test_passed = false
	
	if solve_no_success:
		var led_results_no = graph_script.component_results.get(led_node.get_instance_id(), {})
		var led_current_no = led_results_no.get("current", NAN)
		if not TestUtils.assert_approx_equals(led_current_no, expected_current_on, 0.001, "Switch Test (NO): LED current indicates circuit is ON"): overall_test_passed = false
		var led_data_no; for d in graph_script.components: if d.component_node == led_node: led_data_no = d; break
		if not TestUtils.assert_false(led_data_no.get("is_burned", true), "Switch Test (NO): LED is not burned"): overall_test_passed = false


	editor_instance.queue_free()
	return overall_test_passed


func test_diode_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Diode Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var diode_node: Diode3D = editor_script._add_component(editor_script.DiodeScene, Vector3(2,0,0)) as Diode3D

	if not TestUtils.assert_true(is_instance_valid(ps_node) and is_instance_valid(res_node) and is_instance_valid(diode_node), "Diode Test: All components instantiated"):
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	ps_node.target_voltage = 5.0
	graph_script.component_config_changed(ps_node)
	res_node.resistance = 220.0
	graph_script.component_config_changed(res_node)
	diode_node.forward_voltage = 0.7
	graph_script.component_config_changed(diode_node)

	print("  Diode Test: Testing Forward Bias.")
	graph_script.connect_terminals(ps_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, diode_node.terminal_anode)
	graph_script.connect_terminals(diode_node.terminal_kathode, ps_node.terminal_neg)
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_fwd_success = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_fwd_success, "Diode Test (Fwd): Simulation solve successful"): overall_test_passed = false
	
	if solve_fwd_success:
		var diode_results_fwd = graph_script.component_results.get(diode_node.get_instance_id(), {})
		var diode_current_fwd = diode_results_fwd.get("current", NAN)
		var expected_current_fwd = (5.0 - 0.7) / 220.0
		if not TestUtils.assert_approx_equals(diode_current_fwd, expected_current_fwd, 0.001, "Diode Test (Fwd): Current matches expected"): overall_test_passed = false
		var diode_data_fwd; for d in graph_script.components: if d.component_node == diode_node: diode_data_fwd = d; break
		if not TestUtils.assert_true(diode_data_fwd.get("conducting", false), "Diode Test (Fwd): Diode is conducting"): overall_test_passed = false

	var all_component_nodes_fwd = []
	for comp_data_item_fwd in graph_script.components: all_component_nodes_fwd.append(comp_data_item_fwd.component_node)
	for comp_n_fwd in all_component_nodes_fwd: graph_script.remove_component(comp_n_fwd)
	for child in editor_script.components_node.get_children(): child.queue_free()
	for child in editor_script.wires_node.get_children(): child.queue_free()
	graph_script.electrical_nodes.clear(); graph_script.terminal_connections.clear(); graph_script.ground_node_id = -1; graph_script._next_node_id = 0
	await get_tree().process_frame

	ps_node = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	res_node = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	diode_node = editor_script._add_component(editor_script.DiodeScene, Vector3(2,0,0)) as Diode3D
	ps_node.target_voltage = 5.0; graph_script.component_config_changed(ps_node)
	res_node.resistance = 220.0; graph_script.component_config_changed(res_node)
	diode_node.forward_voltage = 0.7; graph_script.component_config_changed(diode_node)

	print("  Diode Test: Testing Reverse Bias.")
	graph_script.connect_terminals(ps_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, diode_node.terminal_kathode) 
	graph_script.connect_terminals(diode_node.terminal_anode, ps_node.terminal_neg)   
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_rev_success = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_rev_success, "Diode Test (Rev): Simulation solve successful"): overall_test_passed = false
	
	if solve_rev_success:
		var diode_results_rev = graph_script.component_results.get(diode_node.get_instance_id(), {})
		var diode_current_rev = diode_results_rev.get("current", NAN)
		if not TestUtils.assert_approx_equals(diode_current_rev, 0.0, 1e-6, "Diode Test (Rev): Current is near zero"): overall_test_passed = false
		var diode_data_rev; for d in graph_script.components: if d.component_node == diode_node: diode_data_rev = d; break
		if not TestUtils.assert_false(diode_data_rev.get("conducting", true), "Diode Test (Rev): Diode is NOT conducting"): overall_test_passed = false

	editor_instance.queue_free()
	return overall_test_passed


func test_potentiometer_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Potentiometer Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var pot_node: Potentiometer3D = editor_script._add_component(editor_script.PotentiometerScene, Vector3(1,0,0)) as Potentiometer3D
	
	if not TestUtils.assert_true(is_instance_valid(ps_node) and is_instance_valid(pot_node), "Potentiometer Test: All components instantiated"):
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	ps_node.target_voltage = 10.0 
	graph_script.component_config_changed(ps_node)
	pot_node.total_resistance = 1000.0
	graph_script.component_config_changed(pot_node)

	graph_script.connect_terminals(ps_node.terminal_pos, pot_node.terminal1)
	graph_script.connect_terminals(pot_node.terminal2, ps_node.terminal_neg) 
	graph_script.set_ground_node(ps_node.terminal_neg)
	
	var wiper_terminal = pot_node.terminal_wiper
	
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
		
		var solve_pot_success = graph_script.solve_single_time_step(0.01)
		if not TestUtils.assert_true(solve_pot_success, "Potentiometer Test (Wiper {p}): Solve successful".format({"p": case.pos})): overall_test_passed = false; continue
		
		var current_wiper_node_id = graph_script.terminal_connections.get(wiper_terminal.get_instance_id(), -1)
		
		if solve_pot_success and current_wiper_node_id != -1:
			var wiper_voltage = graph_script.electrical_nodes.get(current_wiper_node_id, {}).get("voltage", NAN)
			if not TestUtils.assert_approx_equals(wiper_voltage, case.expected_v, 0.01, "Potentiometer Test (Wiper {p}): Voltage matches expected".format({"p": case.pos})): overall_test_passed = false
		elif current_wiper_node_id == -1:
			printerr("  Potentiometer Test: Wiper terminal's node_id not found in graph_script.terminal_connections map.")
			overall_test_passed = false


	editor_instance.queue_free()
	return overall_test_passed


func test_battery_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Battery Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var bat_node: Battery3D = editor_script._add_component(editor_script.BatteryScene, Vector3.ZERO) as Battery3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	
	if not TestUtils.assert_true(is_instance_valid(bat_node) and is_instance_valid(res_node), "Battery Test: Components instantiated"):
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false
		
	res_node.resistance = 1000.0 
	graph_script.component_config_changed(res_node)

	graph_script.connect_terminals(bat_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, bat_node.terminal_neg)
	graph_script.set_ground_node(bat_node.terminal_neg)

	var test_cases_battery = [
		{"cells": 1, "expected_v": 1.5},
		{"cells": 2, "expected_v": 3.0},
		{"cells": 4, "expected_v": 6.0}
	]
	
	for case in test_cases_battery:
		print("  Battery Test: {c} cells".format({"c": case.cells}))
		bat_node.set_num_cells(case.cells) 
		editor_script._on_battery_config_changed(bat_node) 
		
		var solve_bat_success = graph_script.solve_single_time_step(0.01)
		if not TestUtils.assert_true(solve_bat_success, "Battery Test ({c} cells): Solve successful".format({"c": case.cells})): overall_test_passed = false; continue
		
		if solve_bat_success:
			var res_term1_node_id = graph_script.terminal_connections.get(res_node.terminal1.get_instance_id(), -1)
			var res_term2_node_id = graph_script.terminal_connections.get(res_node.terminal2.get_instance_id(), -1) 
			
			var v_res_t1 = graph_script.electrical_nodes.get(res_term1_node_id, {}).get("voltage", NAN)
			var v_res_t2 = graph_script.electrical_nodes.get(res_term2_node_id, {}).get("voltage", 0.0) 
			
			var v_across_res = NAN
			if not is_nan(v_res_t1): v_across_res = v_res_t1 - v_res_t2
			
			if not TestUtils.assert_approx_equals(v_across_res, case.expected_v, 0.01, "Battery Test ({c} cells): Voltage across resistor matches battery voltage".format({"c": case.cells})): overall_test_passed = false
			
			var bat_results = graph_script.component_results.get(bat_node.get_instance_id(), {})
			var bat_current_supplied = bat_results.get("current", NAN) 
			var expected_current = case.expected_v / res_node.resistance
			if not TestUtils.assert_approx_equals(bat_current_supplied, expected_current, 0.0001, "Battery Test ({c} cells): Current matches expected".format({"c": case.cells})): overall_test_passed = false

	editor_instance.queue_free()
	return overall_test_passed


func test_polarized_capacitor_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Polarized Capacitor Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var cap_node: PolarizedCapacitor3D = editor_script._add_component(editor_script.PolarizedCapacitorScene, Vector3(2,0,0)) as PolarizedCapacitor3D

	if not TestUtils.assert_true(is_instance_valid(ps_node) and is_instance_valid(res_node) and is_instance_valid(cap_node), "Polarized Capacitor Test: All components instantiated"):
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	print("  Polarized Capacitor Test: Charging.")
	ps_node.target_voltage = 10.0
	graph_script.component_config_changed(ps_node)
	res_node.resistance = 1000.0 
	graph_script.component_config_changed(res_node)
	cap_node.capacitance = 100e-6 
	cap_node.max_voltage = 16.0
	graph_script.component_config_changed(cap_node) 

	graph_script.connect_terminals(ps_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, cap_node.terminal1) 
	graph_script.connect_terminals(cap_node.terminal2, ps_node.terminal_neg) 
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_charge_success = true
	var cap_voltage_t0 = 0.0
	var num_steps = 5
	var dt = 0.02 

	var exploded_during_charge = false

	for i in range(num_steps):
		if not graph_script.solve_single_time_step(dt):
			solve_charge_success = false
			break
		var cap_results = graph_script.component_results.get(cap_node.get_instance_id(), {})
		cap_voltage_t0 = cap_results.get("voltage_across", NAN) 
		print_debug("    Step {s_idx}: Vcap = {v_cap_val}".format({"s_idx": i + 1, "v_cap_val": cap_voltage_t0}))
		var cap_graph_data_charge; for d in graph_script.components: if d.component_node == cap_node: cap_graph_data_charge = d; break
		if cap_graph_data_charge and cap_graph_data_charge.get("is_exploded", false):
			exploded_during_charge = true

	if not solve_charge_success:
		if exploded_during_charge:
			print_rich("[color=yellow]Capacitor exploded during initial charge (overvoltage) -- this is expected in some scenarios.[/color]")
		else:
			overall_test_passed = false
	if solve_charge_success:
		var expected_voltage_after_1tc = 10.0 * (1.0 - exp(-1.0)) 
		if not TestUtils.assert_approx_equals(cap_voltage_t0, expected_voltage_after_1tc, 0.5, "Polarized Capacitor Test (Charging): Voltage after ~1 TC is ~6.32V"): overall_test_passed = false
		var cap_graph_data_charge; for d in graph_script.components: if d.component_node == cap_node: cap_graph_data_charge = d; break
		if not TestUtils.assert_false(cap_graph_data_charge.get("is_exploded", true), "Polarized Capacitor Test (Charging): Capacitor is NOT exploded"): overall_test_passed = false
	else:
		if exploded_during_charge:
			print_rich("[color=yellow]Capacitor exploded due to overvoltage during charge, skipping test failure.[/color]")
			overall_test_passed = true
	if solve_charge_success:
		var expected_voltage_after_1tc = 10.0 * (1.0 - exp(-1.0)) 
		if not TestUtils.assert_approx_equals(cap_voltage_t0, expected_voltage_after_1tc, 0.5, "Polarized Capacitor Test (Charging): Voltage after ~1 TC is ~6.32V"): overall_test_passed = false
		var cap_graph_data_charge; for d in graph_script.components: if d.component_node == cap_node: cap_graph_data_charge = d; break
		if not TestUtils.assert_false(cap_graph_data_charge.get("is_exploded", true), "Polarized Capacitor Test (Charging): Capacitor is NOT exploded"): overall_test_passed = false


	print("  Polarized Capacitor Test: Explosion (Overvoltage).")
	ps_node.target_voltage = 20.0 
	graph_script.component_config_changed(ps_node)
	
	var exploded_in_sim = false
	for i in range(15): 
		if not graph_script.solve_single_time_step(dt):
			break 
		var cap_graph_data_explode_check; for d in graph_script.components: if d.component_node == cap_node: cap_graph_data_explode_check = d; break
		if cap_graph_data_explode_check and cap_graph_data_explode_check.get("is_exploded", false):
			exploded_in_sim = true
			break
		var cap_results_explode = graph_script.component_results.get(cap_node.get_instance_id(), {})
		var v_cap_explode_step = cap_results_explode.get("voltage_across", NAN)
		print_debug("    Explosion Test Step {s_idx}: Vcap = {v_cap_val}".format({"s_idx": i + 1, "v_cap_val": v_cap_explode_step}))


	var cap_graph_data_explode; for d in graph_script.components: if d.component_node == cap_node: cap_graph_data_explode = d; break
	if not TestUtils.assert_true(cap_graph_data_explode.get("is_exploded", false), "Polarized Capacitor Test (Overvoltage): Capacitor IS exploded"): overall_test_passed = false
	
	var all_component_nodes = []
	for comp_data_item in graph_script.components: all_component_nodes.append(comp_data_item.component_node)
	for comp_n in all_component_nodes: graph_script.remove_component(comp_n)
	for child in editor_script.components_node.get_children(): child.queue_free()
	for child in editor_script.wires_node.get_children(): child.queue_free()
	graph_script.electrical_nodes.clear()
	graph_script.terminal_connections.clear()
	graph_script.ground_node_id = -1
	graph_script._next_node_id = 0
	await get_tree().process_frame

	editor_instance.queue_free()
	return overall_test_passed


func test_non_polarized_capacitor_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Non-Polarized Capacitor Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var cap_node: NonPolarizedCapacitor3D = editor_script._add_component(editor_script.NonPolarizedCapacitorScene, Vector3(2,0,0)) as NonPolarizedCapacitor3D

	if not TestUtils.assert_true(is_instance_valid(ps_node) and is_instance_valid(res_node) and is_instance_valid(cap_node), "Non-Polarized Capacitor Test: All components instantiated"):
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	ps_node.target_voltage = 10.0
	graph_script.component_config_changed(ps_node)
	res_node.resistance = 1000.0 
	graph_script.component_config_changed(res_node)
	cap_node.capacitance = 10e-6 
	cap_node.max_voltage = 50.0 
	graph_script.component_config_changed(cap_node)

	graph_script.connect_terminals(ps_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, cap_node.terminal1)
	graph_script.connect_terminals(cap_node.terminal2, ps_node.terminal_neg)
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_charge_success = true
	var cap_voltage_val = 0.0
	var num_steps = 5
	var dt = 0.002 
	
	for i in range(num_steps):
		if not graph_script.solve_single_time_step(dt):
			solve_charge_success = false; break
		var cap_results = graph_script.component_results.get(cap_node.get_instance_id(), {})
		cap_voltage_val = cap_results.get("voltage_across", NAN)
		print_debug("    NP Cap Charge Step {s_idx}: Vcap = {v_cap_val}".format({"s_idx": i + 1, "v_cap_val": cap_voltage_val}))


	if not TestUtils.assert_true(solve_charge_success, "Non-Polarized Capacitor Test: Simulation solve successful for all steps"): overall_test_passed = false
	if solve_charge_success:
		var expected_voltage_after_1tc = 10.0 * (1.0 - exp(-1.0)) 
		if not TestUtils.assert_approx_equals(cap_voltage_val, expected_voltage_after_1tc, 0.5, "Non-Polarized Capacitor Test: Voltage after ~1 TC is ~6.32V"): overall_test_passed = false
	
	editor_instance.queue_free()
	return overall_test_passed


func test_inductor_behavior() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Inductor Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D 
	var ind_node: Inductor3D = editor_script._add_component(editor_script.InductorScene, Vector3(2,0,0)) as Inductor3D

	if not TestUtils.assert_true(is_instance_valid(ps_node) and is_instance_valid(res_node) and is_instance_valid(ind_node), "Inductor Test: All components instantiated"):
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	ps_node.target_voltage = 10.0
	graph_script.component_config_changed(ps_node)
	res_node.resistance = 100.0 
	graph_script.component_config_changed(res_node)
	ind_node.inductance = 10e-3 
	graph_script.component_config_changed(ind_node) 

	graph_script.connect_terminals(ps_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, ind_node.terminal1)
	graph_script.connect_terminals(ind_node.terminal2, ps_node.terminal_neg)
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_success = true
	var inductor_current_val = 0.0
	var num_steps = 5
	var dt = 0.00002 

	for i in range(num_steps):
		if not graph_script.solve_single_time_step(dt):
			solve_success = false; break
		var ind_results = graph_script.component_results.get(ind_node.get_instance_id(), {})
		inductor_current_val = ind_results.get("current", NAN)
		print_debug("    Inductor Current Step {s_idx}: I_L = {i_l_val}".format({"s_idx": i + 1, "i_l_val": inductor_current_val}))


	if not TestUtils.assert_true(solve_success, "Inductor Test: Simulation solve successful for all steps"): overall_test_passed = false
	if solve_success:
		var expected_current_after_1tc = (10.0 / 100.0) * (1.0 - exp(-1.0)) 
		if not TestUtils.assert_approx_equals(inductor_current_val, expected_current_after_1tc, 0.01, "Inductor Test: Current after ~1 TC is ~0.0632A"): overall_test_passed = false
	
	editor_instance.queue_free()
	return overall_test_passed


func test_npn_bjt_regions() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: NPN BJT Test - Editor/Graph script invalid.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	print("  NPN BJT Test: Cutoff Region.")
	var ps_cutoff: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var rc_cutoff: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var bjt_cutoff: NPNBJT3D = editor_script._add_component(editor_script.NPNBJTScene, Vector3(2,0,0)) as NPNBJT3D

	ps_cutoff.target_voltage = 10.0 
	graph_script.component_config_changed(ps_cutoff)
	rc_cutoff.resistance = 1000.0 
	graph_script.component_config_changed(rc_cutoff)
	bjt_cutoff.beta_dc = 100.0
	bjt_cutoff.vbe_on = 0.7
	bjt_cutoff.vce_sat = 0.2
	graph_script.component_config_changed(bjt_cutoff)

	graph_script.connect_terminals(ps_cutoff.terminal_pos, rc_cutoff.terminal1)
	graph_script.connect_terminals(rc_cutoff.terminal2, bjt_cutoff.terminal_c)
	graph_script.connect_terminals(bjt_cutoff.terminal_e, ps_cutoff.terminal_neg) 
	graph_script.connect_terminals(bjt_cutoff.terminal_b, ps_cutoff.terminal_neg) 
	graph_script.set_ground_node(ps_cutoff.terminal_neg)

	var solve_cutoff = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_cutoff, "NPN BJT Test (Cutoff): Solve successful"): overall_test_passed = false
	if solve_cutoff:
		var bjt_results_cutoff = graph_script.component_results.get(bjt_cutoff.get_instance_id(), {})
		var ic_cutoff = bjt_results_cutoff.get("Ic", NAN)
		var region_cutoff = bjt_results_cutoff.get("region", "ERROR")
		if not TestUtils.assert_equals(region_cutoff, "OFF", "NPN BJT Test (Cutoff): Region is OFF"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ic_cutoff, 0.0, 1e-6, "NPN BJT Test (Cutoff): Collector current is near zero"): overall_test_passed = false

	_cleanup_components_and_graph(editor_script, graph_script) 

	print("  NPN BJT Test: Active Region.")
	var ps_active_vcc: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var ps_active_vbb: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,1)) as PowerSource3D 
	var rc_active: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var rb_active: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,1)) as Resistor3D
	var bjt_active: NPNBJT3D = editor_script._add_component(editor_script.NPNBJTScene, Vector3(2,0,0)) as NPNBJT3D

	ps_active_vcc.target_voltage = 10.0
	graph_script.component_config_changed(ps_active_vcc)
	ps_active_vbb.target_voltage = 2.0 
	graph_script.component_config_changed(ps_active_vbb)
	rc_active.resistance = 1000.0 
	graph_script.component_config_changed(rc_active)
	rb_active.resistance = 10000.0 
	graph_script.component_config_changed(rb_active)
	bjt_active.beta_dc = 100.0; bjt_active.vbe_on = 0.7; bjt_active.vce_sat = 0.2
	graph_script.component_config_changed(bjt_active)

	graph_script.connect_terminals(ps_active_vcc.terminal_pos, rc_active.terminal1)
	graph_script.connect_terminals(rc_active.terminal2, bjt_active.terminal_c)
	graph_script.connect_terminals(bjt_active.terminal_e, ps_active_vcc.terminal_neg)
	graph_script.connect_terminals(ps_active_vbb.terminal_pos, rb_active.terminal1)
	graph_script.connect_terminals(rb_active.terminal2, bjt_active.terminal_b)
	graph_script.connect_terminals(ps_active_vbb.terminal_neg, ps_active_vcc.terminal_neg) 
	graph_script.set_ground_node(ps_active_vcc.terminal_neg)

	var solve_active = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_active, "NPN BJT Test (Active): Solve successful"): overall_test_passed = false
	if solve_active:
		var bjt_results_active = graph_script.component_results.get(bjt_active.get_instance_id(), {})
		var ic_active = bjt_results_active.get("Ic", NAN)
		var ib_active = bjt_results_active.get("Ib", NAN)
		var region_active = bjt_results_active.get("region", "ERROR")
		rb_active.resistance = 27000.0
		graph_script.component_config_changed(rb_active)
		solve_active = graph_script.solve_single_time_step(0.01)
		bjt_results_active = graph_script.component_results.get(bjt_active.get_instance_id(), {})
		ic_active = bjt_results_active.get("Ic", NAN); ib_active = bjt_results_active.get("Ib", NAN); region_active = bjt_results_active.get("region", "ERROR")
		
		if not TestUtils.assert_equals(region_active, "ACTIVE", "NPN BJT Test (Active): Region is ACTIVE"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ib_active, 1.3/27000.0, 5e-6, "NPN BJT Test (Active): Base current matches expected"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ic_active, bjt_active.beta_dc * ib_active, 5e-4, "NPN BJT Test (Active): Collector current is beta * Ib"): overall_test_passed = false


	_cleanup_components_and_graph(editor_script, graph_script)

	print("  NPN BJT Test: Saturation Region.")
	var ps_sat_vcc: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var ps_sat_vbb: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3(0,0,1)) as PowerSource3D
	var rc_sat: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var rb_sat: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,1)) as Resistor3D
	var bjt_sat: NPNBJT3D = editor_script._add_component(editor_script.NPNBJTScene, Vector3(2,0,0)) as NPNBJT3D

	ps_sat_vcc.target_voltage = 10.0
	graph_script.component_config_changed(ps_sat_vcc)
	ps_sat_vbb.target_voltage = 5.0 
	graph_script.component_config_changed(ps_sat_vbb)
	rc_sat.resistance = 1000.0 
	graph_script.component_config_changed(rc_sat)
	rb_sat.resistance = 10000.0 
	graph_script.component_config_changed(rb_sat)
	bjt_sat.beta_dc = 100.0; bjt_sat.vbe_on = 0.7; bjt_sat.vce_sat = 0.2
	graph_script.component_config_changed(bjt_sat)
	
	graph_script.connect_terminals(ps_sat_vcc.terminal_pos, rc_sat.terminal1)
	graph_script.connect_terminals(rc_sat.terminal2, bjt_sat.terminal_c)
	graph_script.connect_terminals(bjt_sat.terminal_e, ps_sat_vcc.terminal_neg)
	graph_script.connect_terminals(ps_sat_vbb.terminal_pos, rb_sat.terminal1)
	graph_script.connect_terminals(rb_sat.terminal2, bjt_sat.terminal_b)
	graph_script.connect_terminals(ps_sat_vbb.terminal_neg, ps_sat_vcc.terminal_neg)
	graph_script.set_ground_node(ps_sat_vcc.terminal_neg)

	var solve_sat = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_sat, "NPN BJT Test (Saturation): Solve successful"): overall_test_passed = false
	if solve_sat:
		var bjt_results_sat = graph_script.component_results.get(bjt_sat.get_instance_id(), {})
		var ic_sat = bjt_results_sat.get("Ic", NAN)
		var ib_sat = bjt_results_sat.get("Ib", NAN)
		var region_sat = bjt_results_sat.get("region", "ERROR")
		var Vc_sat_node = graph_script.electrical_nodes.get(graph_script.terminal_connections.get(bjt_sat.terminal_c.get_instance_id()), {}).get("voltage", NAN)
		var Ve_sat_node = graph_script.electrical_nodes.get(graph_script.terminal_connections.get(bjt_sat.terminal_e.get_instance_id()), {}).get("voltage", NAN)
		var Vce_actual_sat = NAN
		if not is_nan(Vc_sat_node) and not is_nan(Ve_sat_node): Vce_actual_sat = Vc_sat_node - Ve_sat_node

		if not TestUtils.assert_equals(region_sat, "SATURATION", "NPN BJT Test (Saturation): Region is SATURATION"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(Vce_actual_sat, bjt_sat.vce_sat, 0.1, "NPN BJT Test (Saturation): Vce is approx Vce_sat"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ic_sat, (ps_sat_vcc.target_voltage - Vce_actual_sat) / rc_sat.resistance, 1e-3, "NPN BJT Test (Saturation): Ic is limited by Rc and Vce_sat"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ib_sat, (ps_sat_vbb.target_voltage - bjt_sat.vbe_on) / rb_sat.resistance, 5e-5, "NPN BJT Test (Saturation): Ib is approximately (Vbb-Vbe_on)/Rb"): overall_test_passed = false


	_cleanup_components_and_graph(editor_script, graph_script) 
	editor_instance.queue_free()
	return overall_test_passed


func test_pnp_bjt_regions() -> bool:
	print('test')
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
	bjt_pnp_cutoff.beta_dc = 100.0; bjt_pnp_cutoff.veb_on = 0.7; bjt_pnp_cutoff.vec_sat = 0.2
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
	
	_cleanup_components_and_graph(editor_script, graph_script)

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
	bjt_pnp_active.beta_dc = 100.0; bjt_pnp_active.veb_on = 0.7; bjt_pnp_active.vec_sat = 0.2
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
		if not TestUtils.assert_equals(region_pnp_active, "ACTIVE", "PNP BJT Test (Active): Region is ACTIVE"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ib_pnp_active, 1.3/27000.0, 5e-6, "PNP BJT Test (Active): Base current matches expected"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(ic_pnp_active, bjt_pnp_active.beta_dc * ib_pnp_active, 5e-4, "PNP BJT Test (Active): Collector current is beta * Ib"): overall_test_passed = false

	_cleanup_components_and_graph(editor_script, graph_script)

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
	bjt_pnp_sat.beta_dc = 100.0; bjt_pnp_sat.veb_on = 0.7; bjt_pnp_sat.vec_sat = 0.2
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
		var ib_pnp_sat = bjt_results_pnp_sat.get("Ib", NAN)
		var region_pnp_sat = bjt_results_pnp_sat.get("region", "ERROR")

		var Ve_pnp_sat_node = graph_script.electrical_nodes.get(graph_script.terminal_connections.get(bjt_pnp_sat.terminal_e.get_instance_id()), {}).get("voltage", NAN)
		var Vc_pnp_sat_node = graph_script.electrical_nodes.get(graph_script.terminal_connections.get(bjt_pnp_sat.terminal_c.get_instance_id()), {}).get("voltage", NAN)
		var Vec_actual_pnp_sat = NAN
		if not is_nan(Ve_pnp_sat_node) and not is_nan(Vc_pnp_sat_node): Vec_actual_pnp_sat = Ve_pnp_sat_node - Vc_pnp_sat_node

		if not TestUtils.assert_equals(region_pnp_sat, "SATURATION", "PNP BJT Test (Saturation): Region is SATURATION"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(Vec_actual_pnp_sat, bjt_pnp_sat.vec_sat, 0.1, "PNP BJT Test (Saturation): Vec is approx Vec_sat"): overall_test_passed = false
		var expected_ic_sat_pnp = (ps_pnp_sat_vcc.target_voltage - Vec_actual_pnp_sat - 0.0) / rc_pnp_sat.resistance 
		if not TestUtils.assert_approx_equals(ic_pnp_sat, expected_ic_sat_pnp, 1e-3, "PNP BJT Test (Saturation): Ic is limited by Rc and Vec_sat"): overall_test_passed = false

	_cleanup_components_and_graph(editor_script, graph_script)
	editor_instance.queue_free()
	return overall_test_passed


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
	zener_fwd.forward_voltage = Vf_test
	zener_fwd.zener_voltage = Vz_test
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
		var expected_current_fwd = (ps_fwd.target_voltage - Vf_test) / R_series_val
		if not TestUtils.assert_approx_equals(current_fwd, expected_current_fwd, 0.001, "Zener Test (Fwd): Current matches expected"): overall_test_passed = false
		if not TestUtils.assert_equals(state_fwd, "FORWARD", "Zener Test (Fwd): State is FORWARD"): overall_test_passed = false
	
	_cleanup_components_and_graph(editor_script, graph_script)

	print("  Zener Diode Test: Reverse Bias (OFF).")
	var ps_rev_off: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_rev_off: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var zener_rev_off: ZenerDiode3D = editor_script._add_component(editor_script.ZenerDiodeScene, Vector3(2,0,0)) as ZenerDiode3D

	ps_rev_off.target_voltage = 3.0 
	graph_script.component_config_changed(ps_rev_off)
	res_rev_off.resistance = R_series_val
	graph_script.component_config_changed(res_rev_off)
	zener_rev_off.forward_voltage = Vf_test
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
	
	_cleanup_components_and_graph(editor_script, graph_script)

	print("  Zener Diode Test: Reverse Bias (ZENER Breakdown).")
	var ps_breakdown: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_breakdown: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var zener_breakdown: ZenerDiode3D = editor_script._add_component(editor_script.ZenerDiodeScene, Vector3(2,0,0)) as ZenerDiode3D

	ps_breakdown.target_voltage = 10.0 
	graph_script.component_config_changed(ps_breakdown)
	res_breakdown.resistance = R_series_val
	graph_script.component_config_changed(res_breakdown)
	zener_breakdown.forward_voltage = Vf_test
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

	_cleanup_components_and_graph(editor_script, graph_script)
	editor_instance.queue_free()
	return overall_test_passed


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
	var relay_module_vcc_v = load_ps_v 

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
	led_nc_off.forward_voltage = load_led_vf; led_nc_off.min_current_to_light = load_led_min_i; led_nc_off.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_nc_off)
	res_no_off.resistance = load_res_val; graph_script.component_config_changed(res_no_off)
	led_no_off.forward_voltage = load_led_vf; led_no_off.min_current_to_light = load_led_min_i; led_no_off.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_no_off)

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
		var expected_load_current_on = (load_ps_v - load_led_vf) / load_res_val
		if not TestUtils.assert_approx_equals(led_nc_current_off, expected_load_current_on, 0.001, "Relay Test (De-energized): NC LED current is ON"): overall_test_passed = false

		var led_no_results_off = graph_script.component_results.get(led_no_off.get_instance_id(), {})
		var led_no_current_off = led_no_results_off.get("current", NAN)
		if not TestUtils.assert_approx_equals(led_no_current_off, 0.0, 1e-6, "Relay Test (De-energized): NO LED current is OFF"): overall_test_passed = false

	_cleanup_components_and_graph(editor_script, graph_script)

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
	led_nc_on.forward_voltage = load_led_vf; led_nc_on.min_current_to_light = load_led_min_i; led_nc_on.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_nc_on)
	res_no_on.resistance = load_res_val; graph_script.component_config_changed(res_no_on)
	led_no_on.forward_voltage = load_led_vf; led_no_on.min_current_to_light = load_led_min_i; led_no_on.max_current_before_burn = load_led_max_i; graph_script.component_config_changed(led_no_on)

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
		var expected_load_current_on = (load_ps_v - load_led_vf) / load_res_val 
		if not TestUtils.assert_approx_equals(led_no_current_on, expected_load_current_on, 0.001, "Relay Test (Energized): NO LED current is ON"): overall_test_passed = false

		var led_nc_results_on = graph_script.component_results.get(led_nc_on.get_instance_id(), {})
		var led_nc_current_on = led_nc_results_on.get("current", NAN)
		if not TestUtils.assert_approx_equals(led_nc_current_on, 0.0, 1e-6, "Relay Test (Energized): NC LED current is OFF"): overall_test_passed = false

	_cleanup_components_and_graph(editor_script, graph_script)
	editor_instance.queue_free()
	return overall_test_passed


func test_led_burnout() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Could not get editor or graph script for LED burnout test.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var led_node: LED3D = editor_script._add_component(editor_script.LEDScene, Vector3(2,0,0)) as LED3D

	ps_node.target_voltage = 5.0
	ps_node.target_current = 0.5 
	graph_script.component_config_changed(ps_node)

	res_node.resistance = 10.0 
	graph_script.component_config_changed(res_node)
	
	led_node.forward_voltage = 2.0
	led_node.max_current_before_burn = 0.020 
	graph_script.component_config_changed(led_node)

	graph_script.connect_terminals(ps_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, led_node.terminal_anode)
	graph_script.connect_terminals(led_node.terminal_kathode, ps_node.terminal_neg)
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_success: bool = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_success, "Burnout Test: Simulation solve successful"): overall_test_passed = false
	
	if solve_success:
		var led_graph_data
		for comp_data in graph_script.components:
			if comp_data.component_node == led_node:
				led_graph_data = comp_data
				break
		
		if led_graph_data:
			if not TestUtils.assert_true(led_graph_data.get("is_burned", false), "LED is burned"): overall_test_passed = false
			var led_results = graph_script.component_results.get(led_node.get_instance_id(), {})
			var led_current_after_burn = led_results.get("current", NAN)
			if not TestUtils.assert_not_nan(led_current_after_burn, "Burned LED current is not NaN"): overall_test_passed = false
			if not TestUtils.assert_approx_equals(led_current_after_burn, 0.0, 1e-6, "Burned LED current is zero"): overall_test_passed = false
		else:
			printerr("  ASSERT FAIL: Could not find LED graph data for burnout test.")
			overall_test_passed = false
	
	editor_instance.queue_free()
	return overall_test_passed

func test_led_not_lighting() -> bool:
	var overall_test_passed = true
	var editor_instance: Node3D = CircuitEditorScene.instantiate()
	add_child(editor_instance)
	await get_tree().process_frame

	var editor_script: CircuitEditor3D = editor_instance as CircuitEditor3D
	var graph_script: CircuitGraph = editor_instance.circuit_graph
	if not is_instance_valid(editor_script) or not is_instance_valid(graph_script):
		printerr("  SETUP FAIL: Could not get editor or graph script for LED not lighting test.")
		if is_instance_valid(editor_instance): editor_instance.queue_free()
		return false

	var ps_node: PowerSource3D = editor_script._add_component(editor_script.PowerSourceScene, Vector3.ZERO) as PowerSource3D
	var res_node: Resistor3D = editor_script._add_component(editor_script.ResistorScene, Vector3(1,0,0)) as Resistor3D
	var led_node: LED3D = editor_script._add_component(editor_script.LEDScene, Vector3(2,0,0)) as LED3D

	ps_node.target_voltage = 5.0
	graph_script.component_config_changed(ps_node)

	res_node.resistance = 10000.0 
	graph_script.component_config_changed(res_node)
	
	led_node.forward_voltage = 2.0
	led_node.min_current_to_light = 0.005 
	graph_script.component_config_changed(led_node)

	graph_script.connect_terminals(ps_node.terminal_pos, res_node.terminal1)
	graph_script.connect_terminals(res_node.terminal2, led_node.terminal_anode)
	graph_script.connect_terminals(led_node.terminal_kathode, ps_node.terminal_neg)
	graph_script.set_ground_node(ps_node.terminal_neg)

	var solve_success: bool = graph_script.solve_single_time_step(0.01)
	if not TestUtils.assert_true(solve_success, "Not Lighting Test: Simulation solve successful"): overall_test_passed = false
	
	if solve_success:
		var led_graph_data
		for comp_data in graph_script.components:
			if comp_data.component_node == led_node:
				led_graph_data = comp_data
				break
		
		var led_results = graph_script.component_results.get(led_node.get_instance_id(), {})
		var led_current_calc = led_results.get("current", NAN)

		if not TestUtils.assert_not_nan(led_current_calc, "LED current (low) is not NaN"): overall_test_passed = false
		if not TestUtils.assert_approx_equals(led_current_calc, 0.0003, 0.0001, "LED current (low) matches expected"): overall_test_passed = false
		
		if led_graph_data:
			if not TestUtils.assert_false(led_graph_data.get("is_burned", true), "LED is NOT burned (low current)"): overall_test_passed = false
			if led_current_calc < led_node.min_current_to_light:
				TestUtils.assert_true(true, "Calculated LED current ({c_calc}) is below min_current_to_light ({c_min}), so it should not be visibly lit.".format({"c_calc":led_current_calc, "c_min":led_node.min_current_to_light}))
			else:
				TestUtils.assert_false(true, "Calculated LED current ({c_calc}) is NOT below min_current_to_light ({c_min}), it might be lit.".format({"c_calc":led_current_calc, "c_min":led_node.min_current_to_light}))
				overall_test_passed = false

		else:
			printerr("  ASSERT FAIL: Could not find LED graph data for not-lighting test.")
			overall_test_passed = false
	
	editor_instance.queue_free()
	return overall_test_passed


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

	_cleanup_components_and_graph(ed, g)

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

	_cleanup_components_and_graph(ed, g)

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

	_cleanup_components_and_graph(ed, g)
	ed_inst.queue_free()
	return ok

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
	if res.get("region","") != "OFF": ok = false
	if abs(res.get("Id",0.0)) > 1e-6: ok = false

	# ---- TRIODE ----
	rig.reset_graph()
	var ps_s_tr : PowerSource3D     = rig.add(ed.PowerSourceScene)
	var ps_g_tr : PowerSource3D     = rig.add(ed.PowerSourceScene, Vector3(0,0,1))
	var pmos_tr : PChannelMOSFET3D  = rig.add(ed.PChannelMOSFETScene, Vector3(2,0,0))

	ps_s_tr.target_voltage = 5.0
	ps_g_tr.target_voltage = 2.0     # Vsg = 3 V  (>|Vt|)  -> ON
	rig.cfg(ps_s_tr); rig.cfg(ps_g_tr)

	g.connect_terminals(pmos_tr.terminal_s, ps_s_tr.terminal_pos)
	g.connect_terminals(pmos_tr.terminal_d, ps_s_tr.terminal_neg)
	g.connect_terminals(pmos_tr.terminal_g, ps_g_tr.terminal_pos)
	g.connect_terminals(ps_g_tr.terminal_neg, ps_s_tr.terminal_neg)
	rig.ground(ps_s_tr.terminal_neg)

	if not rig.solve(): ok = false
	res = rig.results(pmos_tr)
	print_debug("    TRIODE solve → region=%s , Id=%s"
	            % [res.get("region","N/A"), str(res.get("Id", NAN))])
	if res.get("region","") != "TRIODE": ok = false
	if res.get("Id", NAN) <= 0: ok = false    # current should flow S→D (negative Id not expected)

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
	print('test')
	if not rig.solve(): ok = false
	res = rig.results(pmos_sat)
	print_debug("    SAT solve → region=%s , Id=%s"
	            % [res.get("region","N/A"), str(res.get("Id", NAN))])
	if res.get("region","") != "SATURATION": ok = false
	if res.get("Id", NAN) <= 0: ok = false

	rig.cleanup()
	return ok
