<h1 align="center">Rushy Bird</h1>

<p align="center">
  <a href="https://itch.io/embed-upload/17690534?color=4c92ca" target="_blank">
    <img src="https://img.shields.io/badge/PLAY_NOW_ON-ITCH.IO-fa5c5c?style=for-the-badge&logo=itch.io&logoColor=white" alt="Play Game on itch.io" height="50" />
  </a>
</p>

<p align="center">
  This is my very first game development project! I've always wanted to explore game dev, and I chose Godot as my first engine to learn the ropes. Rushy Bird is my first attempt at building something playable, learning how game programming works, and getting comfortable with Godot. It's a fast-paced, 2D arcade game featuring dynamic speed escalation, persistent high scores, and mobile-friendly touch controls. Developing a smooth game feel and a scaling speed mechanic was a fun challenge for my first project.
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

Rushy Bird features two distinct game modes, each tracking its own independent high score to challenge players in different ways:

### Classic Mode

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

If you want to modify or edit the source code, you can easily set it up locally. (If you just want to play the game, you can play it directly in your browser on [itch.io](https://rzrabbi.itch.io/rushy-bird)).

### Prerequisites

You will need **Godot Engine 3.x** (version 3.6 recommended). You can download it for free from [the official Godot website](https://godotengine.org/download/archive/3.6-stable/).

### Steps to Run Locally

1. **Clone the repository**:
   ```bash
   git clone https://github.com/rzrabbi/rushy-bird.git
   ```
2. **Import the project**:
   - Open **Godot Engine**.
   - Click the **Import** button on the right side.
   - Click **Browse** and navigate to your cloned `rushy-bird` folder.
   - Select the `project.godot` file, click **Open**, and then click **Import & Edit**.
3. **Run the game**:
   - Once inside the editor, click the **Play** button in the top-right corner (or press `F5`) to start playing!

### Developer Console & Commands

The game features a **Developer Console** that pauses gameplay when opened and resumes when closed. This console allows you to monitor performance, tweak settings, and trigger cheats on the fly.

### Performance Monitor Panel

The console includes a built-in **Performance Monitor Panel** (toggled by running `performance` or `perf` in the console) that overlays real-time execution statistics at the top of the game screen:
* **Release Mode**: Shows real-time FPS (including **1% Low FPS** to monitor lag/stuttering), current game mode, speed level, progression percentage, speed multiplier, current score, and player health.
* **Debug/Editor Mode**: Shows all Release Mode stats plus memory diagnostics (current & peak static RAM, VRAM usage), engine rendering metrics (draw calls, vertex counts), active nodes count, orphan nodes count, and the game window resolution.

#### Accessing the Console
* **Desktop**: Press the **Tilde/Backtick key (`~` or `` ` ``)** during gameplay to toggle the console open or closed.
* **Mobile (Touchscreens)**: Tap the **top-left corner of the screen 5 times** in quick succession.
* **Closing the Console**: Press the **Escape (ESC)** key or tap/click outside the console input line.

#### Shortcuts & Navigation
* **Tab**: Triggers autocomplete suggestions.
* **Up / Down Arrows**: Cycles through your command history.

> [!WARNING]
> **Cheat Activation & Fair Play**
> Using gameplay cheat commands (`invincible`, `speed`, or `addscore`) will flag the current game session as **cheated**. When active, the score text color will modulate to **coral red** and saving high scores to the local machine is **disabled**.

---

#### 1. System & General Commands

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `help` | None | Displays a quick guide of available commands in the console. |
| `clear` / `cls` | None | Clears the console text history. |
| `performance` / `perf` | None | Toggles the overlay performance monitor at the top of the screen. |
| `controls` | None | Displays a reference guide for game controls. |
| `credits` | None | Displays the development credits. |
| `quit` / `exit` | None | Instantly closes the game application. |

#### 2. Gameplay Commands

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `gamemode` | `[classic \| escalation \| 0 \| 1]` | Sets the active game mode. Classic is `0`, Escalation is `1`. If no argument is provided, queries the current mode. |
| `stats` | None | Prints current run stats and lifetime statistics (total play time, total deaths, high scores, total distance, etc.). |

#### 3. Audio Commands

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `volume` | `[music \| sfx] [0-100]` | Directly sets the volume percentage of music or sound effects (e.g. `volume music 50`). If no arguments are provided, queries current volume. |
| `mute` | None | Mutes all game audio (music and SFX). |
| `unmute` | None | Unmutes the game, restoring all volume levels to 100%. |

#### 4. Cheats (Classic Mode Only)

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `invincible` | None | Toggles God Mode (bird phases through pipes; hitting the ground still results in death). Flags the session as cheated. |
| `speed` | `[multiplier]` | Sets the gameplay speed multiplier (e.g., `speed 1.5`). Querying without a multiplier is free; setting it flags the session as cheated. |
| `addscore` | `[amount]` | Adds points to your score (default is 10). Flags the session as cheated. |

#### 5. Debug-Only Commands (Restricted to Debug Builds & Editor Runs)

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `levelup` / `lvlup` | None | Skips to the next speed level in Escalation mode, accelerating speed and refilling 1 heart. |
| `set_level` / `set_lvl` | `[number]` | Skips directly to a specific difficulty level in Escalation mode (e.g. `set_level 10`). |
| `heal` | None | Restores bird health to full (3 hearts). |
| `kill` | None | Instantly kills the bird, bypassing remaining hearts/revives. |
| `timescale` | `[scale]` | Sets the engine speed scale (e.g. `timescale 0.5` for slow-motion, `timescale 2.0` for fast-forward). |
| `restart` | None | Instantly reloads the current scene. |
| `clear_stats` | `confirm` | Permanently deletes all saved scores, statistics, and settings from the local machine (requires the `confirm` parameter). |

# Special Thanks

A massive thank you to **Johnny Rouddro** for introducing me to the Godot Engine and game development in general. His guidance in setting up the project and helping write the code was invaluable to this first step of my journey.

Many thanks as well to **Borna Barua** for creating the fantastic art and assets for this game.
