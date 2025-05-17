# What You Can Learn from MCU-Sim

MCU-Sim is not just a circuit simulator; it's a comprehensive project that touches upon various aspects of electronics, game development, and software engineering. Contributing to or studying this project can provide valuable learning experiences.

## 1. Electronics Concepts

*   **Basic Circuit Theory:**
    *   Understand how fundamental components like resistors, capacitors, inductors, diodes, LEDs, switches, and power sources behave in a circuit.
    *   Observe Ohm's Law (V=IR) and Kirchhoff's Laws (implicitly through the MNA solver) in action.
    *   Learn about voltage, current, resistance, capacitance, and inductance.
*   **Component Characteristics:**
    *   **Resistors:** Voltage division, current limiting.
    *   **Capacitors (Polarized & Non-Polarized):** Charging/discharging behavior, energy storage, time-dependent voltage (related to I = C * dv/dt). Learn about max voltage ratings and the consequences of exceeding them (explosion for polarized, warnings for non-polarized).
    *   **Inductors:** Current smoothing, energy storage, time-dependent current (related to V = L * di/dt).
    *   **Diodes & LEDs:** Unidirectional current flow, forward voltage drop, LED illumination, and burn-out conditions.
    *   **Switches:** Basic circuit control, normally open (NO) vs. normally closed (NC) concepts.
    *   **Potentiometers:** Variable resistance, voltage division.
    *   **Batteries:** Simple voltage sources, effect of multiple cells.
    *   **Power Sources:** Ideal voltage sources with current limiting (CV/CC modes).
    *   **Bipolar Junction Transistors (NPN & PNP):** Basic transistor theory, operating regions (Cutoff, Active, Saturation), current gain (Beta/Hfe), turn-on voltages (Vbe_on/Veb_on), and saturation voltages (Vce_sat/Vec_sat).
*   **Circuit Analysis:**
    *   Gain a conceptual understanding of how circuits are analyzed, even if the mathematical details of MNA are complex.
    *   See how component parameters affect overall circuit behavior.

## 2. Circuit Simulation Principles

*   **Modified Nodal Analysis (MNA):**
    *   Get an introduction to a powerful systematic method for analyzing electronic circuits.
    *   See how component models (stamps) are integrated into a system of linear equations (Ax=b).
    *   Understand the concept of electrical nodes and ground reference.
*   **Solving Linear Systems:**
    *   The `LinearSolver.gd` script demonstrates Gaussian elimination with partial pivoting to solve Ax=b, a fundamental numerical method.
*   **Non-Linear Components:**
    *   Observe how iterative solving is used to handle non-linear components like diodes, LEDs, and BJTs, where their behavior changes based on the circuit conditions.
*   **Transient Analysis:**
    *   Understand the concept of discrete time steps (`delta_time`) in simulation, especially for stateful components like capacitors and inductors.
    *   See how previous state (e.g., `voltage_across_cap_prev_dt`, `current_through_L_prev_dt`) influences the current state.

## 3. Godot Engine & Game Development

*   **GDScript Programming:**
    *   Extensive examples of GDScript usage, including classes (`class_name`), signals, exported variables (`@export`), `@onready` node references, and various built-in functions.
    *   Object-oriented programming principles in practice.
*   **Scene Management:**
    *   Organizing a project with multiple scenes (`.tscn` files) for components, UI elements, and the main editor.
    *   Instantiating scenes at runtime (`scene.instantiate()`).
*   **3D Environment:**
    *   Working with `Node3D` and its transformations (position, rotation).
    *   Using `Camera3D` for viewpoint control.
    *   Basic 3D mesh manipulation (`MeshInstance3D`, `CSGPolygon3D`).
    *   Materials (`StandardMaterial3D`) and visual customization.
*   **User Interface (UI) Development:**
    *   Using `CanvasLayer` for UI.
    *   Working with various UI controls like `Button`, `LineEdit`, `Label`, `HSlider`, `OptionButton`, `ScrollContainer`, `VBoxContainer`, `HBoxContainer`.
    *   Connecting UI element signals (e.g., `pressed`, `text_submitted`, `value_changed`) to GDScript functions.
    *   Dynamic UI updates based on selection and simulation state.
*   **Input Handling:**
    *   Processing mouse input (`InputEventMouseButton`, `InputEventMouseMotion`) and touch input (`InputEventScreenTouch`, `InputEventScreenDrag`).
    *   Managing input for different modes (flying camera, component dragging, UI interaction).
    *   Using `get_viewport().is_input_handled()` and `get_viewport().set_input_as_handled()` for input propagation control.
*   **Physics and Collision:**
    *   Using `Area3D` and `CollisionShape3D` for detecting clicks on terminals and component bodies.
    *   Understanding collision layers and masks for selective interaction.
    *   Raycasting (`PhysicsRayQueryParameters3D`, `intersect_ray`) for object selection and placement on a ground plane.
*   **Custom Resources:**
    *   Using `.tres` files for shared resources like materials (`Resistor3D.tres`) and environment settings (`default_env.tres`).
*   **Signals and Callbacks:**
    *   Extensive use of Godot's signal system for communication between nodes (e.g., a component's `configuration_changed` signal notifying the `CircuitEditor3D` or `CircuitGraph`).

## 4. Software Engineering Practices

*   **Modular Design:**
    *   Each electronic component is a self-contained scene and script, promoting reusability and maintainability.
    *   Separation of concerns (e.g., `CircuitEditor3D` for UI and interaction, `CircuitGraph` for simulation logic).
*   **Code Organization:**
    *   Following naming conventions (see `CONVENTIONS.md`).
    *   Structuring scripts with clear functions and variable names.
*   **Debugging:**
    *   Using `print()`, `printerr()`, and `print_debug()` for tracing execution and diagnosing issues.
*   **Version Control:**
    *   The project is managed with Git, as indicated by `.gitignore` and `.gitattributes`. Understanding these files is part of using version control effectively.
*   **Defensive Programming:**
    *   Checks for node validity (`is_instance_valid()`) before use.
    *   Error handling and logging (`printerr`).
    *   Input validation for user-editable fields.

## 5. Mathematics in Simulation

*   **Linear Algebra:** The core of the MNA solver involves setting up and solving a system of linear equations (Ax=b).
*   **Basic Calculus Concepts:**
    *   The models for capacitors (I = C * dV/dt) and inductors (V = L * dI/dt) are based on derivatives, which are approximated using discrete time steps in the simulation (e.g., dV/dt ≈ (Vc(t) - Vc(t-dt)) / delta_t).

By exploring and contributing to MCU-Sim, you can gain practical experience in these diverse areas, bridging the gap between theoretical knowledge and real-world application in an engaging 3D environment.
