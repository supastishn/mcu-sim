extends Control

func _on_play_button_pressed():
	get_tree().change_scene_to_file("res://CircuitEditor3D.tscn")

func _on_settings_button_pressed():
	get_tree().change_scene_to_file("res://ui/SettingsMenu.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
