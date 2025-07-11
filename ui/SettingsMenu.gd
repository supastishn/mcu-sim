extends Control

## Preloaded script for the test runner.
const TestCircuitsScript = preload("res://tests/test_circuits.gd")
## Instance of the test runner node.
var test_runner_instance: Node = null

## Reference to the button that starts the test suite.
@onready var run_tests_button: Button = $VBoxContainer/RunTestsButton
## Reference to the panel that displays test results.
@onready var results_panel: Panel = $ResultsPanel
## Reference to the RichTextLabel inside the results panel.
@onready var results_label: RichTextLabel = $ResultsPanel/MarginContainer/ScrollContainer/ResultsLabel
## Reference to the checkbox for enabling beta components.
@onready var beta_features_check_button: CheckButton = $VBoxContainer/BetaFeaturesCheckButton

## The project setting key for enabling beta components.
const BETA_COMPONENTS_SETTING = "mcu_sim/features/enable_beta_components"

## Called when the node enters the scene tree. Initializes the beta features checkbox.
func _ready():
	beta_features_check_button.button_pressed = ProjectSettings.get_setting(BETA_COMPONENTS_SETTING, false)

## Called when the Back button is pressed. Returns to the main menu.
func _on_back_button_pressed():
	results_panel.visible = false
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")

## Called when the Run Tests button is pressed. Initiates the test suite.
func _on_run_tests_button_pressed():
	run_tests_button.disabled = true
	results_label.clear()
	results_label.add_text("Running tests, please wait...")
	results_panel.visible = true

	if not is_instance_valid(test_runner_instance):
		test_runner_instance = TestCircuitsScript.new()
		test_runner_instance.name = "TestRunner"
		add_child(test_runner_instance)
		test_runner_instance.tests_completed.connect(_on_tests_completed)

	test_runner_instance.run_tests_from_ui()

## Called when the Beta Features checkbox is toggled. Saves the setting.
func _on_beta_features_check_button_toggled(button_pressed: bool):
	ProjectSettings.set_setting(BETA_COMPONENTS_SETTING, button_pressed)
	ProjectSettings.save()

## Callback function for when the test runner completes. Displays the results.
func _on_tests_completed(results: Dictionary):
	var summary_text = ""
	summary_text += "Test run complete.\n"
	summary_text += "Summary: {p}/{t} tests passed.\n\n".format({"p": results.passed, "t": results.total})

	if results.passed == results.total:
		summary_text += "[color=green]All tests successful![/color]"
	else:
		summary_text += "[color=red][b]----- FAILED TESTS ----- [/b][/color]\n"
		for failed_test_name in results.failed_names:
			summary_text += "  - {name}\n".format({"name": failed_test_name})
		summary_text += "\n{f} test(s) failed overall.".format({"f": results.total - results.passed})
	
	results_label.text = summary_text
	run_tests_button.disabled = false
