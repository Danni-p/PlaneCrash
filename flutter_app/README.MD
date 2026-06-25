# PlaneCrash

PlaneCrash is a cooperative physical party game. A tablet acts as the **Cockpit** of a sinking
plane and runs the flight simulation, while one or more phones act as **Controllers** that steer
the cabin in real time. Players perform physical exercises in the real world; game masters track
how many people are active with simple `+` / `-` counters. The more active players, the slower the
plane descends.

There is **no lose state**. A run ends when altitude reaches zero. Success is measured by how close
the plane reached the target island. Zero metres is a perfect landing; any remaining distance is the
crew's swim distance in a follow-up game that is outside the scope of this app.

## Devices and roles

| Role       | Device                              | Orientation | Responsibility                                            |
| ---------- | ----------------------------------- | ----------- | --------------------------------------------------------- |
| Cockpit    | Tablet (Android primary, iPad too)  | Landscape   | Create room, run the simulation, show visuals, end session |
| Controller | Smartphone                          | Portrait    | Join by room code, control cabin aspects, advance phases  |

### Session model

- One Cockpit opens exactly one room, identified by a readable word-pair code (for example `eagle-island`).
- Multiple Controllers can join the same room and control different aspects (left counter, right counter, weather, settings).
- Several Cockpits can run independent rooms at the same time without interfering.
- There is **no authentication** — access is room-code based only.
- If the Cockpit ends the session, Controllers are disconnected and must re-enter the room code (a Controller is useless without a Cockpit).

## Game phases

The game is cinematic: it does not start falling immediately. It walks through an intro before the
emergency gameplay begins.

```
Waiting ──(Flug starten)──▶ Cruise ──(Triebwerksausfall)──▶ Malfunction
                                                                 │ auto
                                                                 ▼
Success ◀──(altitude = 0)── Emergency ◀──(Notlandung starten)── Briefing
```

- **Waiting**: The Cockpit shows the room code and waits for Controllers. No physics runs.
- **Cruise**: Altitude is stable (5000 m). A distant landmass slowly approaches at a fixed cosmetic speed. Cabin controls are visible but inactive.
- **Malfunction**: An alarm and a German computer voice announce the emergency and reveal the target island. `distanceToIsland` is set to 3000 m, but the plane does not sink yet.
- **Briefing**: A static screen while real-world instructors explain the rules. Waits for a Controller to start.
- **Emergency**: The 1 Hz physics loop runs, all controls are live, and the plane begins to sink. The run ends when altitude reaches 0.
- **Finished**: The success screen shows the distance to the island as the primary score.

Any joined Controller can trigger the phase-advancing buttons.

## Game rules

### Counters

- `counterLeft` and `counterRight` represent actively exercising people on each side of the cabin.
- Range is 0 to (practically) about 10–20; values never go below 0.

### Altitude and ending

There is **no countdown timer**. Altitude is the only time pressure. The run is active while the
phase is Emergency and `currentAltitude > 0`. When altitude reaches 0 the game ends and the success
screen is shown.

### Sink rate

More total active players means a slower descent (constants are tunable):

```
activeTotal           = counterLeft + counterRight
altitudeLossPerSecond = max(2.0, 15.0 - activeTotal * 1.3) + stormBonus
```

`stormBonus` is up to +10 m/s, scaled by the ramped thunderstorm intensity.

### Distance to island

- Starts at 3000 m when the malfunction reveals the island.
- Decreases every tick at a Controller-adjustable approach speed (default 15 m/s).
- At altitude 0, the remaining distance is the score (0 m = perfect landing).

### Bank angle

```
windEffect = windDirection * (windStrength / 100) * 15
bankAngle  = (counterLeft - counterRight) * 4 + windEffect
```

The displayed bank angle is interpolated smoothly between the 1 Hz physics ticks.

## Weather

Weather effects are independent toggles and can be combined. They can be pre-set before the emergency
but only take effect once the Emergency phase begins.

| Effect          | Behaviour at full intensity                                      |
| --------------- | --------------------------------------------------------------- |
| Wind left/right | Bank bias of `±(windStrength / 100) * 15°`                       |
| Thunderstorm    | +10 m/s extra altitude loss; flicker + screen shake             |

Wind strength is set in discrete steps: light breeze (25), moderate (50), strong (75), severe storm (100).

### Gradual ramp

Controller changes set a **target intensity**; the Cockpit ramps the **current intensity** toward it
over time rather than snapping. Wind reaches about 90% of target in roughly 8 seconds, thunderstorm in
roughly 12 seconds. Deactivation ramps back down the same way.

## Architecture

All synchronisation uses **Supabase Realtime Broadcast** only — no database tables, no auth. Each room
maps to a channel named `room-{code}`. The Cockpit holds the authoritative `GameState` and merges
partial updates from Controllers, identified by a `source` field, so two Controllers never overwrite
each other.

Broadcast event types:

- `counter_update` — left and/or right counter
- `weather_update` — toggles and wind strength
- `settings_update` — approach (distance) speed
- `phase_action` — `start_cruise`, `engine_malfunction`, `start_emergency`
- `session_cancel` — Cockpit ended the session

## Project setup

1. Install Flutter (3.38+).
2. Copy `.env.example` to `.env` and fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY` from your Supabase project.
3. Fetch dependencies and run:

   ```bash
   flutter pub get
   flutter run
   ```

### Project structure

```
flutter_app/
  .env.example          # template for Supabase credentials
  l10n.yaml             # localization config (German default, English fallback)
  lib/
    l10n/               # ARB translation sources (app_de.arb, app_en.arb)
    main.dart           # app entry: load .env, init Supabase, routing
    models/             # game_phase, game_state, weather_inputs, broadcast_message
    services/           # supabase_service, room_code_generator, audio_service
    engine/             # physics_engine, weather_ramp, bank_interpolator
    screens/            # home, cockpit, controller, success
    widgets/            # artificial_horizon, neon_display, phase_scenery
  assets/
    audio/              # engine hum, alarms, thunder (optional)
    images/             # distant land, island sprites (optional)
```

## Localization

The default UI language is German. Strings live in `lib/l10n/*.arb` and are generated into
`AppLocalizations` via `flutter gen-l10n`. English is provided as a fallback so the language can be
switched later without code changes.

## Out of scope (v1)

- The follow-up swim game
- User authentication
- Database persistence and leaderboards
- iOS-specific polish beyond basic support
