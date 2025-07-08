# MCU-Sim Project Conventions

This document outlines the coding and structural conventions used in the MCU-Sim project. Adhering to these conventions helps maintain consistency and readability across the codebase.

## 1. Component Structure (`.tscn` and `.gd`)

Electronic components are implemented as Godot scenes (`.tscn`) with an accompanying GDScript file (`.gd`).

### 1.1. Scene File (`<ComponentName>3D.tscn`)

*   **Root Node:**
    *   Type: `Node3D`.
    *   Name: Matches the component type (e.g., `Resistor3D`, `LED3D`).
    *   Script: Attached script `<ComponentName>3D.gd`.

*   **Visual Representation:**
    *   `MeshInstance3D`: Named `MeshInstance3D` (or a more descriptive name like `Cell1` for batteries) for the main body of the component. Material overrides are common.

*   **Terminals:**
    *   Each electrical terminal is an `Area3D` node.
    *   Naming: `Terminal<SpecificName>` (e.g., `TerminalAnode`, `TerminalPositive`, `Terminal1`, `TerminalCOM`, `TerminalWiper`).
    *   Collision Layer: `2` (`TERMINAL_COLLISION_LAYER` in CircuitEditor3D.gd).
    *   Script: `res://components/TerminalFeedback.gd` attached.
    *   Children of Terminal `Area3D`:
        *   `CollisionShape3D`: Defines the clickable area (e.g., `CapsuleShape3D` named `CollisionShape3D_terminal`).
        *   `MeshInstance3D`: Named `Visualization` for visual feedback (e.g., `SphereMesh` named `SphereMesh_terminal_vis`). Material override usually points to `res://components/Resistor3D.tres` (a semi-transparent green material).
        *   `Label3D`: Named `Label3D` for displaying the terminal's name and voltage.
            *   `visible = false` by default.
            *   `billboard = 1` (BillboardMode.ENABLED).
            *   `text`: Full descriptive name (e.g., "Anode", "Positive", "Terminal 1"). See "Naming and Labeling" section.

*   **Component Body (for Selection/Drag):**
    *   `Area3D`: Named `ComponentBody`.
    *   Collision Layer: Set to `4` (as defined by `COMPONENT_BODY_COLLISION_LAYER` in `CircuitEditor3D.gd`).
    *   Child `CollisionShape3D`: Defines the selection/drag area for the component.

*   **Information Labels:**
    *   `Label3D`: Named appropriately (e.g., `CurrentLabel`, `InfoLabel`, `BurnLabel`) for displaying runtime information like current, voltage, operational state, etc.
    *   `visible = false` by default.
    *   `CurrentLabel` – a `Label3D` (optional). Used by components that display operating current and/or state text (e.g. PowerSource, Resistor, LED).

### 1.2. Script File (`<ComponentName>3D.gd`)

*   **Class Name:** `class_name <ComponentName>3D` (PascalCase, matching the file and root node name).
*   **Exported Variables:**
    *   Use `@export` for configurable parameters (e.g., `resistance`, `forward_voltage`, `capacitance`).
    *   Naming: `snake_case`.
    *   Setters: Often include:
        *   Validation (e.g., `max(min_value, value)`, `clampf()`).
        *   An `is_equal_approx()` check to prevent unnecessary updates or signal emissions if the value hasn't significantly changed.
        *   Emission of a `configuration_changed` signal if the value changes and `is_inside_tree()` is true.
*   **Node References:**
    *   Use `@onready var <node_name>: <NodeType> = $<NodePath>` to get references to child nodes.
*   **Signals:**
    *   `configuration_changed(component_node: Node3D)`: Emitted when an exported property that affects the circuit's electrical behavior is changed (e.g., resistance, capacitance, voltage settings).
    *   Component-specific signals like `state_changed` (for Switch) or `wiper_position_changed` (for Potentiometer).
*   **`_ready()` Function:**
    *   Verify required child nodes exist (e.g., terminals, info labels) using `if not ...: printerr(...)`.
    *   Call `reset_visual_state()` to initialize the component's appearance.
    *   Call setters for exported variables (e.g., `set_capacitance(capacitance)`) to ensure initial values are validated and any associated logic (like signal emission if already in tree, though less common in `_ready`) is triggered.
*   **Standard / Optional Methods (implemented when relevant)**
    *   `show_current(actual_current: float, …)` / `hide_current()`
    *   `show_info(data: …)`        / `hide_info()`
    *   `reset_visual_state()`
    *   `update_nonlinear_state(circuit: CircuitGraph, comp_data: Dictionary, x_iter: Array, vs_map_iter: Dictionary) -> bool` – for components that switch models (LED, PowerSource, BJTs, MOSFETs, etc.). Return `true` when the state toggles during an iteration.
    *   `stamp(A, b, node_map, vs_map, inductor_map, terminal_connections, comp_data, delta_time)` – build the component’s MNA contribution.
    *   `gather_sim_results(circuit, comp_data, x, node_map, vs_map, inductor_map, delta_time)` – pull final voltages / currents into `circuit.component_results`.
*   **String Formatting for Display:**
    *   Format numerical values (current, voltage) appropriately for user display, including units (µA, mA, A, V, F, H, Ω). Use `String.num()` / `String.num_scientific()` and always append the unit (µA, mA, A, V, Ω, …); current is shown positive in the conventional flow direction, voltage drop is shown ‘POS – NEG’.

## 2. Naming and Labeling Conventions

*   **File Names:**
    *   Component scenes: `<ComponentName>3D.tscn` (e.g., `Resistor3D.tscn`).
    *   Component scripts: `<ComponentName>3D.gd` (e.g., `Resistor3D.gd`).
*   **Node Names (in `.tscn`):**
    *   Follow the structure outlined in Section 1.1.
    *   Be descriptive (e.g., `TerminalAnode`, `ComponentBody`, `InfoLabel`).
*   **GDScript Class Names:** `PascalCase` (e.g., `Resistor3D`, `CircuitGraph`).
*   **GDScript Variables and Functions:** `snake_case` (e.g., `target_voltage`, `_update_visual_state()`).
*   **User-Visible Labels (e.g., Terminal `Label3D` text):**
    *   **No Abbreviations:** Use full, descriptive names.
        *   "Positive" instead of "POS" or "+".
        *   "Negative" instead of "NEG" or "-".
        *   "Anode" instead of "A".
        *   "Kathode" instead of "K".
        *   "Terminal 1" instead of "T1".
        *   "Collector", "Base", "Emitter" instead of "C", "B", "E".
        *   "Wiper" instead of "W".
        *   "Common", "Normally Open", "Normally Closed" for switches.
    *   For LEDs and diodes, use “Kathode” (German K) instead of “Cathode” to avoid the “C” clash with Collector/Capacitor nodes used elsewhere in the project.

### LinearRegulator3D
* **Terminals:** Vin (input), Vout (output), GND (ground reference)
* **Properties:** 
  - `regulated_voltage` - Target output voltage
  - `dropout_voltage` - Minimum Vin-Vout difference
  - `max_current` - Maximum output current

### OpAmp3D
*   **Terminals:** Vp (Non-inverting Input), Vn (Inverting Input), Vout (Output), Vcc (Positive Supply), Vee (Negative Supply).
*   **Properties:**
    -   `open_loop_gain`: The amplification factor of the op-amp in its linear region.
    -   `rail_saturation_voltage`: The voltage difference from the supply rails where the output clips.
*   **Behavior:** Models an ideal op-amp with high gain, high input impedance, and output voltage saturation at the supply rails. It is treated as a non-linear component with three states: `LINEAR`, `SAT_HIGH`, `SAT_LOW`.

## 3. GDScript Coding Style

*   Constants are UPPER_SNAKE_CASE (e.g. `TERMINAL_COLLISION_LAYER`, `R_LED_ON`).
*   **Comments:** Use comments to explain complex logic or non-obvious decisions.
*   **Error Handling:** Use `printerr()` for critical errors. Use `print()` or `print_debug()` (less common) for informational messages during development.
*   **Validation:** Validate input values, especially for exported properties and user inputs from UI elements.
*   **Signal Emission:** Emit signals only when a value has genuinely changed and the node is part of the scene tree (`is_inside_tree()`).
*   When a component has a nonlinear or state-dependent model, its `update_nonlinear_state()` must return a boolean indicating whether the state changed; CircuitGraph relies on this to iterate until convergence.
*   **Constants:** Define constants for magic numbers or frequently used strings where appropriate (e.g., collision layer numbers).
*   **Defensive Programming:** Use `is_instance_valid()` to check node references before use, especially if they could have been freed or are passed as arguments.

## 4. CircuitGraph (`CircuitGraph.gd`)

*   Maintains the logical representation of the circuit.
*   `add_component()`: Populates a `component_data` dictionary. This dictionary stores:
    *   `component_node`: Reference to the component's Node3D instance.
    *   `type`: String identifier (e.g., "Resistor", "LED").
    *   `properties`: Dictionary of electrical parameters (e.g., resistance, forward_voltage, capacitance, current_operating_mode for PowerSource, Vc_prev_dt for Capacitor).
    *   `terminals`: Dictionary mapping terminal functional names (e.g., "T1", "POS", "A") to their `Area3D` node instances.
    *   State variables like `conducting` (for Diodes/LEDs), `is_burned` (for LEDs), `is_exploded` (for PolarizedCapacitors), `operating_region` (for BJTs).
    *   `current_operating_mode`, `cc_current_direction_sign` for PowerSource  
    *   `operating_region` for BJTs and MOSFETs  
    *   `is_energized` for Relay, `operating_state` for Zener, `conducting` for Diode/LED, etc.
*   `component_config_changed()`: Called when a component's parameters are updated. Reloads properties from the component node into the graph's `component_data`. Resets relevant states (e.g., `is_exploded`, `operating_region`).
*   `solve_single_time_step()`:
    *   Iteratively solves the MNA system, handling non-linear components (Diodes, LEDs, BJTs) and stateful components (PowerSource mode switching).
    *   Calls `_build_mna_system()` to construct matrices.
    *   Calls `_calculate_passive_component_currents()` after solving to determine currents and update states for the next time step (e.g., `voltage_across_cap_prev_dt`, `current_through_L_prev_dt`).
*   Component models in `_build_mna_system()` and `_calculate_passive_component_currents()` should be consistent.

## 5. CircuitEditor (`CircuitEditor3D.gd`)

*   Manages user interaction, component placement, wiring, and simulation control.
*   Preloads component scenes (e.g., `var ResistorScene = preload(...)`).
*   Connects component signals (e.g., `configuration_changed`, `state_changed`) to handler methods (e.g., `_on_resistor_config_changed`, `_on_switch_state_changed`). These handlers typically call `circuit_graph.component_config_changed()` or specific update methods in `CircuitGraph`.
*   Manages the UI, including the component addition bar and the selection bar for editing properties.
*   `_hide_voltage_displays()`: Resets visual feedback (voltage labels, current labels, LED states) when the circuit changes or simulation stops/fails.
*   `_update_voltage_displays()` and `_update_led_states()`: Apply simulation results to the visual components.

## 6. Project Setup

*   **Godot Version:** Compatible with Godot 4.x.
*   **Rendering:** Uses "gl_compatibility" rendering method for broader device support.
*   **Physics Layers:**
    *   Layer 2: Terminals (`TERMINAL_COLLISION_LAYER`)
    *   Layer 4: Component Bodies (`COMPONENT_BODY_COLLISION_LAYER`)
    *   Layer 8: Ground Plane (`GROUND_COLLISION_LAYER`)
    *   Layer 16: Wires (`WIRE_COLLISION_LAYER`)
*   **Version Control:**
    *   `.gitignore` includes `.godot/` and `/android/`.
    *   `.gitattributes` enforces `* text=auto eol=lf`.
    *   `.editorconfig` sets `charset = utf-8`.

## 7. General

*   Strive for clarity and simplicity in code.
*   When adding new components, follow the established structure and patterns.
*   Ensure UI elements in the `CircuitEditor3D.tscn` that interact with component properties (e.g., `ValueEdit`, `MaxVoltageEdit`) are correctly wired up and handled in `CircuitEditor3D.gd`.
*   Keep component-specific logic within the component's script where possible, emitting signals for changes that affect the broader circuit simulation.
