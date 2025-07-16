
Welcome to MCU-Sim!

This is a 3D circuit editor and simulator built with the Godot Engine. It's a fun way to build circuits in a 3D space and see how they work.

## What it can do

- Build in 3D: Place and wire components in a 3D world.
- A good box of parts: Includes common components like resistors, power sources, LEDs, switches, transistors, and more.
- Easy wiring: Click between terminals to connect parts.
- Live simulation: See your circuit work in real-time.
- Visual feedback: Watch LEDs light up, see current values, and check voltages. Some parts even break if you push them too hard!
- Fly around: Move the camera with WASD and the mouse (on desktop) or with virtual joysticks (on mobile).
- Edit on the fly: Click a component to change its properties, like resistance or voltage.

## Components you can use

- Power Source
- Resistor
- LED (Light Emitting Diode)
- Switch
- Diode
- Zener Diode
- Potentiometer
- Battery
- Polarized Capacitor
- Non-Polarized Capacitor
- Inductor
- NPN Bipolar Junction Transistor (BJT)
- PNP Bipolar Junction Transistor (BJT)
- N-Channel MOSFET
- P-Channel MOSFET
- Relay
- Wire
- Breadboard

## How to get started

1.  Open the project: You'll need Godot Engine 4.x. Open the `CircuitEditor3D.tscn` scene to start.
2.  Add components: Use the buttons at the top to add parts to your scene. They'll show up in the middle of your view, ready to be dragged around.
3.  Move things: Click and drag a component's body to move it. It will snap to the grid.
4.  Wire it up: Click on a component's terminal (the little sphere), then click on another terminal to create a wire between them.
5.  Select and edit: Click on any component or wire to select it. A panel will show up on the right where you can:
    - Change values like resistance or voltage.
    - Flip switches or adjust potentiometers.
    - Delete the selected part.
6.  Control the camera:
    - On desktop: Use W, A, S, D to move. Hold the right mouse button and move the mouse to look around.
    - On mobile: Use the two virtual joysticks on the screen.
7.  Run the simulation:
    - You need a ground reference for the simulation to work. Just make sure you've used a Power Source or Battery, and it will automatically ground the negative terminal.
    - Click the "Simulate" button to start and stop the simulation.
    - While it's running, you can click "Display Voltages" to see the voltage at each terminal and the current through each component.

## A peek at the project files

- `CircuitEditor3D.tscn`: This is the main scene.
- `CircuitEditor3D.gd`: This script runs the editor, UI, and input.
- `CircuitGraph.gd`: This handles the circuit logic and simulation.
- `LinearSolver.gd`: A simple solver for the linear equations used in the simulation.
- `components/`: You'll find all the scenes and scripts for the electronic components here.
- `ui/`: This folder contains UI scenes and scripts, like the virtual joystick.
- `project.godot`: The main Godot project file.

## How to run the project

1.  Make sure you have Godot Engine 4.x.
2.  Download or clone this project.
3.  In the Godot Project Manager, click "Import" and find this project's folder.
4.  Select "MCU-Sim" from the project list and click "Edit".
5.  Open the `CircuitEditor3D.tscn` scene and press F5 to run it.
