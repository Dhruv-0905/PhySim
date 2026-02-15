# **PhySim:**

A Godot 4.x-based physics simulation environment inspired by tools like Endorphin, focused on interactive runtime editing, ragdoll experimentation, and extensible simulation “world states” (e.g., vacuum vs atmosphere). The long-term goal is to integrate AI-driven optimization strategies to reduce CPU workload while preserving believable motion.

### **Project status:**

This project is under active development. Core interaction, selection, UI tooling, and ragdoll workflows are in place, with larger simulation systems (fluids, soft bodies, procedural animation) planned.

### **Key features:**

* **Blender-like editor workflow:**
Outliner + object properties panel, runtime editing, scene-style organization

* **3D viewport interaction:**
Select objects via mouse click directly in 3D space

* **Runtime physics authoring for basic rigid bodies**
Edit common properties at runtime for primitives (cube, sphere, etc.), including:

    * Mass

    * Gravity scale

    * Friction

    * Absorbent

    * Rough

    * Bounce

    * Angular damping

    * Linear damping

* **Ragdolls with per-bone control:**
Ragdolls are implemented and support runtime editing per bone, including:

    * Mass (per bone)

    * Gravity scale (per bone)

    * Angular damping (per bone)

    * Linear damping (per bone)

* **Switchable environment states:**
Multiple simulation modes that affect external forces and resistance, including:

    * Vacuum (no external drag/resistance)

    * Atmosphere (air drag/resistance)

### **Why this exists**
Most game engines provide solid physics, but experimentation-heavy simulation workflows often need:

* Fast iteration with live parameter tuning

* Clear per-part control (especially for ragdolls)

* Simple toggles for world “conditions” (vacuum/air, etc.)

* A path toward smarter performance strategies beyond brute-force CPU stepping

*This project aims to become a focused sandbox for that style of work—eventually with AI-assisted optimization.*

### **Planned features**
* **AI-driven performance optimization**
Techniques under consideration include adaptive stepping, sleeping/activation heuristics, LOD-like simulation fidelity, constraint simplification, and scenario-specific approximations

* **Fluid dynamics**
Research + prototyping planned (approach TBD)

* **Soft body physics**
Deformable bodies and constraints (approach TBD)

* **Procedural animation**
Layered procedural controllers that can complement physics-driven motion

## **Getting started**
**Requirements:**
Godot Engine 4.x

**Run locally**
Clone the repository:

git clone <repo-url>

Open the project in Godot:

Import the folder containing project.godot

Press Play to run the simulation environment

## **Design notes (high level)**

* Physics parameters are intended to be hot-editable for rapid iteration

* World “states” act like presets or profiles that modify external forces and resistance consistently across the scene

## **Screenshots / demos**

<<img width="1720" height="980" alt="image" src="https://github.com/user-attachments/assets/1eb0800f-7324-4e65-94ba-cee6210c1b53" />

![Recording 2026-02-14 151916](https://github.com/user-attachments/assets/25bd2714-cf54-4462-a265-bfea41e948b8)




## **Contributing**
Contributions are welcome, especially in these areas:

* UI/UX polish for editor-like workflows

* Stability improvements for ragdolls and constraints

* Performance profiling and benchmarking tooling

*Environment state system (more modes, better parameterization)

* Research prototypes for fluids/soft bodies

## **Roadmap (suggested milestones)**

**Milestone 1: Simulation scalability**

* Stress-test scenes with many objects/ragdolls

* Add scalable simulation controls (quality tiers, selective activation)

**Milestone 2: AI optimization layer**

* Collect telemetry from simulation runs

* Train or tune heuristics to reduce compute while maintaining motion quality

* Add “optimize scene” suggestions (sleep thresholds, solver settings, etc.)

**Milestone 3: New physics domains**

* Fluids prototype

* Soft bodies prototype

* Procedural animation layer
