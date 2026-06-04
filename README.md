<h1 align="center">Flappy Bird: Rush</h1>

<p align="center">
  <a href="https://itch.io/embed-upload/17690534?color=4c92ca" target="_blank">
    <img src="https://img.shields.io/badge/PLAY_NOW_ON-ITCH.IO-fa5c5c?style=for-the-badge&logo=itch.io&logoColor=white" alt="Play Game on itch.io" height="50" />
  </a>
</p>

<p align="center">
  This is my very first game development project! I've always wanted to explore game dev, and I chose Godot as my first engine to learn the ropes. Flappy Bird: Rush is my first attempt at building something playable, learning how game programming works, and getting comfortable with Godot. It's a fast-paced, 2D arcade game featuring dynamic speed escalation, persistent high scores, and mobile-friendly touch controls. Developing a smooth game feel and a scaling speed mechanic was a fun challenge for my first project.
</p>

<h2 align="center">Gameplay Preview</h2>

<p align="center">
  <a href="https://itch.io/embed-upload/17690534?color=4c92ca">
    <img src="assets/previews/v0.1_gameplay.gif" alt="Gameplay Preview" />
  </a>
</p>

# How to play

The game is controlled using the **Spacebar** on a keyboard. If you are playing on a touchscreen device, you can simply **tap the screen** to jump and navigate the bird through the pipes.

# Game Modes

Flappy Bird: Rush features two distinct game modes, each tracking its own independent high score to challenge players in different ways:

### OG Mode

- **The Experience:** Classic rules, pure skill.
- **Speed:** A constant, static **1.0x** speed.
- **Focus:** Perfect for developing rhythmic tapping memory and focusing on clean, consistent execution without the stress of acceleration.

### Escalation Mode

- **The Experience:** An adrenaline-fueled, infinite progression challenge where the game speeds up over time.
- **Asymptotic Speed Scaling:** The game speed smoothly accelerates over time according to an asymptotic curve, tapering off safely as it approaches a hard cap of **2.5x** speed. The acceleration rate is deliberately gentle, giving players time to adjust to each speed increment.
- **Infinite Levels:**
  - The level duration starts at **30 seconds** and increases by **5 seconds** per level up (capped at **45 seconds** per level) to prevent late-game fatigue.
  - Every level-up triggers a visual speed alert, a level-up sound effect, and a **health refill** (+1 heart).
- **Adaptive Obstacle Spawning:**
  - **Dynamic Intervals:** Pipes squeeze closer together as the level increases, reducing the spawning interval from a leisurely 2.0s down to a tight **1.6s**.
  - **Partially Decoupled Timing:** The spawn timer is partially linked to game speed — pipes arrive slightly faster at higher speeds, but at half the acceleration rate, keeping the experience smooth instead of overwhelming.
  - **Progressive Randomness:** Random Y-offset variance is limited in early levels to make them easier to learn, unlocking the full vertical deviation of **8.5** by Level 5.
  - **Jump Restraint:** To keep extremely fast levels fair, the maximum vertical height difference between consecutive pipes is dynamically restrained based on the current game speed.
- **Health & Revive System:**
  - You start with **3 hearts** (maximum capacity of 3).
  - Colliding with a pipe consumes 1 heart, clears existing pipes, and triggers a brief **blink/invincibility phase** to let you recover.
  - Colliding with the ground or flying too high results in instant death, bypassing the revive system.
- **Gravity Soft Cap:** Bird gravity scales quadratically with speed to preserve jump arcs, but is soft-capped at 2.0x speed for better playability at extreme velocities.
- **Dynamic Score Multiplier:** Points earned per pipe scale directly with the current difficulty level (`current_level + 1`), heavily rewarding players who manage to survive deep into the run.

# Running from Source

If you want to modify or edit the source code, you can easily set it up locally. (If you just want to play the game, you can play it directly in your browser on [itch.io](https://rzrabbi.itch.io/flappy-bird-rush)).

### Prerequisites

You will need **Godot Engine 3.x** (version 3.6 recommended). You can download it for free from [the official Godot website](https://godotengine.org/download/archive/3.6-stable/).

### Steps to Run Locally

1. **Clone the repository**:
   ```bash
   git clone https://github.com/rzrabbi/flappy-bird-rush.git
   ```
2. **Import the project**:
   - Open **Godot Engine**.
   - Click the **Import** button on the right side.
   - Click **Browse** and navigate to your cloned `flappy-bird-rush` folder.
   - Select the `project.godot` file, click **Open**, and then click **Import & Edit**.
3. **Run the game**:
   - Once inside the editor, click the **Play** button in the top-right corner (or press `F5`) to start playing!

### Developer Monitor & Debugger

When running the project from source (a debug build), you can access the built-in **Developer Monitor** to inspect game stats and trigger debug options.

- Press **F1** during gameplay to toggle the **Developer Monitor** overlay.
- While the monitor is active and a game is running, you can use the following debug commands:
  - **`L`**: **Level Up** - Instantly skips to the next level. This mathematically simulates the speed acceleration over the skipped time, advances the level, and refills 1 heart.
  - **`H`**: **Heal** - Manually restores 1 health point (adds a heart and triggers the refill animation).
  - **`C`**: **Add Score** - Directly adds score points (+5x the current level's point value).
  - **`I`**: **God Mode (Invincibility)** - Toggles bird invincibility, allowing the bird to phase through pipes entirely (does not protect against hitting the floor).

# Special Thanks

A massive thank you to **Johnny Rouddro** for introducing me to the Godot Engine and game development in general. His guidance in setting up the project and helping write the code was invaluable to this first step of my journey.

Many thanks as well to **Borna Barua** for creating the fantastic 2D art and assets for this game.
