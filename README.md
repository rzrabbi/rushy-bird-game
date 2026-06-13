<h1 align="center">Rushy Bird</h1>

<p align="center">
  <a href="#" target="_blank">
    <img src="https://img.shields.io/badge/PLAY_NOW_ON-ITCH.IO-fa5c5c?style=for-the-badge&logo=itch.io&logoColor=white" alt="Play Game on itch.io" height="50" />
  </a>
</p>

<p align="center">
  This is my very first game development project! I've always wanted to explore game development, and I chose Godot as my first engine to learn the ropes. Rushy Bird is my first attempt at building something playable, learning how game programming works, and getting comfortable with Godot. It's a fast-paced, 2D arcade game featuring dynamic speed escalation, persistent high scores, and mobile-friendly touch controls. Developing a smooth game feel and a scaling speed mechanic was a fun challenge for my first project.
</p>

<h2 align="center">Gameplay Preview</h2>

<p align="center">
  <img src="assets/previews/v1.0-beta_gameplay.gif" alt="Gameplay Preview" />
</p>

# Input Controls

- **Keyboard (Desktop):** The **Spacebar** initiates jumps and menu navigation.
- **Touchscreen (Mobile):** Tapping the screen initiates jumps and menu navigation.

# Game Modes

Rushy Bird contains two game modes with independent high-score tracking.

## Classic Mode

- **Speed:** Static `1.0x` base speed.
- **Mechanics:** Constant velocity and spawning intervals with standard obstacle avoidance.

## Escalation Mode

- **Speed Scaling:** Asymptotic speed acceleration capped at a maximum of `2.5x` base speed.
- **Level Progression:**
  - Level duration starts at 30 seconds, incrementing by 5 seconds per level up to a maximum duration of 45 seconds.
  - Each level-up triggers a speed increase, a visual/audio alert, and a health refill (+1 heart).
- **Obstacle Spawning:**
  - Spawning interval scales down from `2.0s` to a minimum cap of `1.6s` as level increases.
  - Spawning interval acceleration rate is set to half of the game speed acceleration rate.
  - Y-axis obstacle offset randomness scales up to a maximum deviation of `8.5` by Level 5.
  - Maximum vertical distance difference between consecutive pipes is dynamically constrained based on current speed.
- **Health & Revive System:**
  - Runs initiate with 3 hearts (maximum capacity).
  - Pipe collisions deduct 1 heart, clear existing obstacles, and trigger a temporary invincibility (blink) state.
  - Ground or top boundary collisions result in instant death.
- **Physics Calibration:** Gravity scales quadratically with speed, capped at `2.0x` speed.
- **Score Multiplier:** Point values scale linearly as `current_level + 1`.

# Developer Console & Instrumentation

The game features an integrated **Developer Console** that pauses gameplay when opened and resumes when closed, facilitating settings adjustment, performance monitoring, and debugging.

## Console Interface & Controls

- **Desktop Activation:** Toggled using the **Tilde/Backtick key (`~` or `` ` ``)** during gameplay.
- **Mobile Activation (Touchscreens):** Toggled by tapping the **top-left corner of the screen 5 times** in quick succession.
- **Deactivation:** Dismissed using the **Escape (ESC)** key or by clicking/tapping outside the console input region.
- **Shortcuts & Navigation:**
  - **`Tab`**: Triggers autocomplete suggestions.
  - **`Up / Down Arrows`**: Cycles through entered command history.

## Key Console Commands

A full list of console commands can be queried using the `help` command. Primary commands include:

- **`help`**: Displays a quick reference guide of all available console commands.
- **`performance` / `perf`**: Toggles a real-time telemetry overlay at the top of the screen showing FPS, active game settings, and system diagnostics.
- **`status`**: Displays system statistics, active game state, network/authentication status, and cloud sync reports.
- **`gamemode [classic|escalation]`**: Queries or sets the active game mode.
- **`link`**: Opens the profile claiming/linking panel to associate the guest session with a permanent account.
- **`logout`**: Logs out of the current authenticated user session and returns to an anonymous guest profile.
- **`delete_guest [confirm]`**: Wipes local stats, deletes user data from all Firestore collections, and deletes the associated Firebase Auth account (requires typing `delete_guest confirm` to run).

_Note: Additional commands are available for audio controls (`volume`, `mute`), gameplay statistics (`stats`), debug utility commands (`levelup`, `heal`, `kill`, `timescale`, `profile`, `reset_guest`), and gameplay cheats._

# Development Setup

The source codebase is open for local compilation, modification, and execution. A hosted web build will be available for direct play on [itch.io](#) (coming soon).

## Prerequisites

- **Godot Engine 3.x** (Version 3.6 is recommended) is required. Downloads are available via [the official Godot website](https://godotengine.org/download/archive/3.6-stable/).

## Workspace Configuration

- **Repository Cloning:** Source coordinates: `https://github.com/rzrabbi/rushy-bird.git`
- **Godot Project Import:** The project workspace is opened by importing the [project.godot](project.godot) settings file located at the root of the repository.
- **Firebase Configuration:** Local builds utilize a settings file named `.env` at the directory `res://addons/godot-firebase/.env` for credentials. The template layout is defined in [example.env](addons/godot-firebase/example.env).
- **Execution:** The default scene is run from the editor using the **Play** button or the `F5` hotkey.

# Leaderboards & Cloud Synchronization

Rushy Bird features real-time leaderboard tracking and persistent player profile synchronization powered by **Firebase Auth** and **Cloud Firestore**.

## Leaderboard Tracking

- **Eligible Mode:** Only scores achieved in **Escalation Mode** are submitted to the global leaderboards.
- **Dual Boards:** The game maintains two separate leaderboards:
  - **All-Time Leaderboard:** Tracks the highest scores achieved in the game since inception.
  - **Seasonal Leaderboard:** Resets automatically on the first day of each calendar month (tracked under monthly periods, e.g., `YYYY-MM`).
- **Read Request Caching:** To minimize Firestore document read consumption, `FirebaseManager` implements an in-memory cache. Subsequent leaderboard requests are served directly from the cached datasets unless a force-refresh is requested (such as after score submission) or an active fetch operation is already in progress.

## Firebase Cloud Storage & Profiles

The game leverages Firebase Authentication and Cloud Firestore to store and synchronize player profiles and leaderboard entries:

- **Anonymous Sessions:** When running the game for the first time, an anonymous Firebase session is created in the background. Players receive a unique Firebase UID allowing their scores, distance, playtime, and statistics to sync immediately without requiring any signup.
- **Profile Linking & Claiming:** Guest players can link/claim their profile using **Google Sign-In** or **Email/Password** credentials from the profile panel.
  - **Conflict Resolution:** If a player links a guest session to a permanent account that already has cloud data, the game prompts them to resolve the conflict by either overwriting the cloud data with guest progress, discarding the guest progress to load cloud data, or cancelling.
- **Firestore Collections Structure:**
  - `leaderboard_rushybird_alltime`: Stores public high scores mapping player names and scores to Firebase UIDs.
  - `leaderboard_rushybird_seasonal`: Identical to all-time, but stores monthly seasonal high scores segmented by the active time period.
  - `player_data_rushybird`: Stores detailed user statistics including total games, lifetime deaths, revives, distance, playtime, and mode-specific high scores.

## Firestore Security & Anti-Cheat Rules

To prevent cheating and protect leaderboard integrity, the database uses strict validation rules defined in [firestore.rules](firestore.rules):

- **Anti-Cheat Validation:** Score submissions are checked by the `isRealisticScore()` rule, enforcing that scores must be integers between 0 and 9,999 to reject impossible or hacked scores.
- **Level Validation:** Leaderboard submissions and player profile stats validate the level using the `isRealisticLevel()` rule, enforcing that the level must be an integer between 1 and 1,000 to reject impossible or hacked level stats.
- **Strict User Ownership:** Write operations (create, update, delete) are permitted only if the user is authenticated and writing to their own document (`request.auth.uid == userId`), preventing players from tampering with others' data.
- **Upward-Only Score Progress:** Leaderboard updates are only allowed if the new score is greater than or equal to the current high score (`request.resource.data.score >= resource.data.score`), preventing score resets.
- **Data Integrity Constraints:** Direct type and constraint validations are enforced, including character length limits (maximum 20 characters for player names) and specific data types for all properties.

## Firebase Guest Cleanup & Maintenance (GitHub Actions)

- **Firebase Auth Auto-Cleanup:** Automatically deletes anonymous/guest auth accounts older than 30 days via Firebase native settings.
- **Manual Firebase Guest Purge ([manual-firebase-guest-purge.yml](.github/workflows/manual-firebase-guest-purge.yml)):** Manual workflow (`workflow_dispatch`) to delete all anonymous guest accounts from Firebase Auth as well as their corresponding Firestore database documents, regardless of age.
- **Scheduled Firestore Database Pruning ([scheduled-firestore-pruning.yml](.github/workflows/scheduled-firestore-pruning.yml)):** Scheduled workflow running monthly (also manual-triggerable) to clean up Firestore documents (leaderboards/stats) of users whose accounts no longer exist in Firebase Authentication (due to guest account expiration or deletion).

## Local Configuration

- **Game Config:** Firebase authentication and project settings are read from `.env` located at `res://addons/godot-firebase/.env`. If this file is missing, execution falls back to offline mode with local save data. An [example.env](addons/godot-firebase/example.env) is included as a reference.
- **Export Packaging:** The `.env` configuration file is automatically packaged into the exported PCK archive during builds using the built-in non-resource export filters (`include_filter="*.env"`) defined in `export_presets.cfg`. This ensures Firebase configurations are securely bundled with the game binary for production exports without needing custom packaging scripts.

# Special Thanks

A massive thank you to **Johnny Rouddro** for introducing me to the Godot Engine and game development in general. His guidance in setting up the project and helping write initial and early prototype code was invaluable to this first step of my journey.

Many thanks as well to **Borna Barua** for creating the fantastic art and assets for this game.
