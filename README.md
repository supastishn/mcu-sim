# MCU-Sim - 3D Circuit Simulator

MCU-Sim is a 3D circuit editor and simulator built with the Godot Engine. It allows users to visually construct electronic circuits in a 3D environment and observe their behavior through simulation.

## Features

*   **3D Circuit Construction:** Place and wire components in a 3D space.
*   **Component Library:** Includes common electronic components like resistors, power sources, LEDs, switches, diodes, potentiometers, capacitors (polarized and non-polarized), inductors, and batteries.
*   **Wiring System:** Connect component terminals using wires.
*   **Interactive Simulation:**
    *   Solve circuit behavior using Modified Nodal Analysis (MNA).
    *   View calculated voltage at terminals.
    *   Display current flowing through components.
    *   Visualize LED illumination and burn-out state.
    *   Simulate capacitor explosion (for polarized capacitors) and over-voltage warnings (for non-polarized).
    *   Interactive components like switches and potentiometers.
*   **Camera Controls:**
    *   Desktop: WASD for movement, Right-click + Mouse for look.
    *   Mobile: Virtual joysticks for movement and look.
*   **Component Interaction:**
    *   Select components to view/edit their properties (resistance, voltage, capacitance, etc.).
    *   Drag and drop components on a grid.
    *   Delete components and wires.
*   **UI:**
    *   Component addition bar.
    *   Selection bar for editing component properties.
    *   Simulation control and voltage display toggles.

## Components Available

*   Power Source (Voltage Source with Current Limiting)
*   Resistor
*   LED (Light Emitting Diode)
*   Switch (SPDT)
*   Diode
*   Potentiometer
*   Battery (configurable number of cells)
*   Polarized Capacitor
*   Non-Polarized Capacitor
*   Inductor
*   NPN Bipolar Junction Transistor (BJT)
*   PNP Bipolar Junction Transistor (BJT)
*   Wire

## How to Use

1.  **Launch the Project:** Open the project in the Godot Engine (version 4.x compatible with "Forward Plus" rendering and "gl_compatibility" for mobile). The main scene is `CircuitEditor3D.tscn`.
2.  **Adding Components:**
    *   Click buttons on the top "ComponentBar" (e.g., "Add Resistor", "Add Power Source") to add components to the scene.
    *   The component will appear near the center of the view and will be automatically selected for dragging.
3.  **Moving Components:**
    *   Click and drag a component's body to move it. Components snap to a grid.
4.  **Wiring:**
    *   Click on a component's terminal (visualized as a sphere). The terminal will highlight.
    *   Click on another component's terminal to create a wire between them.
5.  **Selecting & Editing Components:**
    *   Click on a component's body or a wire to select it.
    *   The "SelectionBar" on the right will appear, allowing you to:
        *   **Edit Values:** Change properties like resistance, voltage, capacitance, etc., in the `LineEdit` fields. Press Enter to submit.
        *   **Toggle Switch:** For switches, a button will appear to toggle its state.
        *   **Adjust Potentiometer:** For potentiometers, a slider will appear to change the wiper position.
        *   **Configure Battery:** For batteries, select the number of cells.
        *   **Delete:** Click the "Delete" button to remove the selected component or wire.
6.  **Camera Controls:**
    *   **Desktop:**
        *   `W, A, S, D`: Move the camera.
        *   Hold `Right Mouse Button` + Move Mouse: Look around.
    *   **Mobile:**
        *   Use the on-screen virtual joysticks (left for movement, right for look).
7.  **Simulation:**
    *   **Ground:** For a simulation to run, at least one power source (PowerSource3D or Battery3D) negative terminal must be part of the circuit, which will be implicitly grounded.
    *   Click the "Simulate" button to start/stop continuous simulation.
    *   When simulating:
        *   LEDs will light up or show as burned based on current.
        *   Capacitors may show as "EXPLODED!" if their voltage limits are exceeded (polarized) or display warnings (non-polarized).
        *   The "Display Voltage Labels" button (appears after first simulation) can be toggled to show/hide voltage values at each terminal and current values on components.

## Project Structure

*   `CircuitEditor3D.tscn`: Main scene for the editor.
*   `CircuitEditor3D.gd`: Main script handling editor logic, UI, input, and simulation orchestration.
*   `CircuitGraph.gd`: Manages the logical representation of the circuit, component data, and MNA solving.
*   `LinearSolver.gd`: Provides a static function for solving systems of linear equations (Ax=b).
*   `components/`: Contains scenes (.tscn) and scripts (.gd) for each electronic component.
    *   `TerminalFeedback.gd`: Script attached to terminal `Area3D` nodes for visual feedback and label display.
*   `ui/`: Contains UI related scenes and scripts.
    *   `VirtualJoystick.tscn`/`.gd`: Implements the on-screen joystick for mobile.
*   `default_env.tres`: Default Godot environment resource.
*   `project.godot`: Godot project configuration file.

## To Run

1.  Ensure you have Godot Engine 4.x installed.
2.  Download or clone this project.
3.  Open the Godot Project Manager.
4.  Click "Import" and navigate to the project's root folder (the one containing `project.godot`).
5.  Once imported, select the "MCU-Sim" project and click "Edit".
6.  In the Godot editor, open the `CircuitEditor3D.tscn` scene.
7.  Press F5 (or the "Play" button) to run the main scene.

---

This README provides a basic overview. Further details on specific MNA implementation, component models, and advanced features can be found by examining the GDScript code.
