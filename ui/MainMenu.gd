extends Control

## Called when the Play button is pressed. Changes to the main editor scene.
func _on_play_button_pressed():
	get_tree().change_scene_to_file("res://CircuitEditor3D.tscn")

## Called when the Settings button is pressed. Changes to the settings menu scene.
func _on_settings_button_pressed():
	get_tree().change_scene_to_file("res://ui/SettingsMenu.tscn")

## Called when the Quit button is pressed. Exits the application.
func _on_quit_button_pressed():
	get_tree().quit()
