extends Control

var is_loading := false
var selected_slot := 0

@onready var main_menu_container = $VBoxContainer
@onready var save_slots_container = $SaveSlotsContainer

## Called when the Play button is pressed. Changes to the main editor scene.
func _on_play_button_pressed():
	get_tree().change_scene_to_file("res://CircuitEditor3D.tscn")

## Called when the Load button is pressed. Shows save slots.
func _on_load_button_pressed():
	is_loading = true
	main_menu_container.hide()
	save_slots_container.show()

## Called when the Settings button is pressed. Changes to the settings menu scene.
func _on_settings_button_pressed():
	get_tree().change_scene_to_file("res://ui/SettingsMenu.tscn")

## Called when the Quit button is pressed. Exits the application.
func _on_quit_button_pressed():
	get_tree().quit()

## Called when a save slot button is pressed.
func _on_slot_button_pressed(button: Button):
	if button == $SaveSlotsContainer/Slot1Button:
		selected_slot = 1
	elif button == $SaveSlotsContainer/Slot2Button:
		selected_slot = 2
	elif button == $SaveSlotsContainer/Slot3Button:
		selected_slot = 3
	elif button == $SaveSlotsContainer/Slot4Button:
		selected_slot = 4
	
	if is_loading:
		load_circuit(selected_slot)
	else:
		# This would be for saving, but we handle that in the editor
		pass

## Called when the Back button is pressed.
func _on_back_button_pressed():
	main_menu_container.show()
	save_slots_container.hide()
	is_loading = false

## Loads a circuit from the specified slot.
func load_circuit(slot: int):
	var save_path = "user://circuit_save_" + str(slot) + ".save"
	if FileAccess.file_exists(save_path):
		# Pass the save file path to the editor scene
		var editor_scene = preload("res://CircuitEditor3D.tscn")
		var editor_instance = editor_scene.instantiate()
		get_tree().root.add_child(editor_instance)
		editor_instance.load_circuit_from_file(save_path)
		queue_free()  # Remove main menu
	else:
		# Show error or handle missing save
		print("No save file found in slot ", slot)
