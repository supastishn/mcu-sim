extends Node3D

class_name NChannelMOSFET3D

## Signal emitted when a configuration value (Vth, K_n) changes.
signal configuration_changed(component_node: Node3D)

## Threshold Voltage (Vth) in Volts (V).
@export var vth: float = 1.0 : set = set_vth
## Transconductance parameter (K_n) in Amps/Volt^2 (A/V^2).
@export var k_n: float = 0.1 : set = set_k_n # Example: 100 mA/V^2 if units are scaled

@onready var terminal_d: Area3D = $TerminalD # Drain
@onready var terminal_g: Area3D = $TerminalG # Gate
@onready var terminal_s: Area3D = $TerminalS # Source
@onready var info_label: Label3D = $InfoLabel

func _ready():
	if not terminal_d or not terminal_g or not terminal_s:
		printerr("NChannelMOSFET3D requires child Area3D nodes named 'TerminalD', 'TerminalG', and 'TerminalS'.")
	if not info_label:
		printerr("NChannelMOSFET3D requires a child Label3D named 'InfoLabel'.")
	
	reset_visual_state()
	# Ensure initial values are validated and signals potentially emitted by setters
	set_vth(vth)
	set_k_n(k_n)

func set_vth(value: float):
	# Vth can be positive or negative for enhancement/depletion, allow a reasonable range.
	var new_vth = value 
	if not is_equal_approx(vth, new_vth):
		vth = new_vth
		print("NChannelMOSFET {mosfet_name} Vth set to: {vth_str} V".format({"mosfet_name": name, "vth_str": String.num(vth, 2)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif vth != new_vth: # Handles initial NaN
		vth = new_vth

func set_k_n(value: float):
	var new_k_n = max(1e-6, value) # K_n must be positive, practical minimum
	if not is_equal_approx(k_n, new_k_n):
		k_n = new_k_n
		print("NChannelMOSFET {mosfet_name} K_n set to: {kn_str} A/V^2".format({"mosfet_name": name, "kn_str": String.num_scientific(k_n)}))
		if is_inside_tree():
			emit_signal("configuration_changed", self)
	elif k_n != new_k_n: # Handles initial NaN or if value was outside max()
		k_n = new_k_n

## Shows Id, Vgs, Vds, and operating region.
## results: Dictionary { "Id": float, "Vgs": float, "Vds": float, "region": String }
func show_info(results: Dictionary):
	if not info_label: return
	info_label.modulate = Color.WHITE # Default color

	var id_str = "Id: N/A"
	if results.has("Id") and not is_nan(results.Id):
		id_str = "Id: {val_str}".format({"val_str": _format_current(results.Id)})
	
	var vgs_str = "Vgs: N/A"
	if results.has("Vgs") and not is_nan(results.Vgs):
		vgs_str = "Vgs: {val_str} V".format({"val_str": String.num(results.Vgs, 2)})

	var vds_str = "Vds: N/A"
	if results.has("Vds") and not is_nan(results.Vds):
		vds_str = "Vds: {val_str} V".format({"val_str": String.num(results.Vds, 2)})
		
	var region_str = "Region: N/A"
	if results.has("region"):
		region_str = "Region: {reg}".format({"reg": results.region})
		
	info_label.text = "{r_str}\n{id}\nVgs: {vgs}\nVds: {vds}".format({
		"r_str": region_str, 
		"id": id_str, 
		"vgs": vgs_str.replace("Vgs: ", ""), # Remove redundant label for compactness
		"vds": vds_str.replace("Vds: ", "")  # Remove redundant label
	})
	info_label.visible = true

func _format_current(current_value: float) -> String:
	if abs(current_value) < 1e-6 and abs(current_value) > 1e-15 : # nA to µA (very small)
		return "{val_str} nA".format({"val_str": String.num(current_value * 1e9, 2)})
	elif abs(current_value) < 1e-3 and abs(current_value) >= 1e-12: # µA to mA
		return "{val_str} µA".format({"val_str": String.num(current_value * 1e6, 2)})
	elif abs(current_value) < 1.0: # mA to A
		return "{val_str} mA".format({"val_str": String.num(current_value * 1e3, 2)})
	else: # A
		return "{val_str} A".format({"val_str": String.num(current_value, 2)})

## Hides all info display.
func hide_info():
	if not info_label: return
	info_label.visible = false
	info_label.text = "" # Clear text

## Resets the visual state of the MOSFET (info hidden).
func reset_visual_state():
	hide_info()
