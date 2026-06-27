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
- **Cruise**: Altitude is stable (17 500 m). A distant landmass slowly approaches at a fixed cosmetic speed. Cabin controls are visible but inactive.
- **Malfunction**: A looping danger alarm plays for 8 seconds. The plane does not sink yet and the target island is not shown.
- **Briefing**: A static screen while real-world instructors explain the rules; a German voice-over plays once. Waits for a Controller to start.
- **Emergency**: Per-frame physics run, all controls are live, and the plane begins to sink. The island is spawned at a random bearing 13 500 m away and rendered on the horizon. The run ends when altitude reaches 0.
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
altitudeLossPerSecond = max(5.0, 25.0 - activeTotal * 1.3) + stormBonus
```

`stormBonus` is up to +10 m/s, scaled by the ramped thunderstorm intensity.

### Timing design

Constants are tuned so a **straight-line** approach at the default 15 m/s ground speed reaches the
island in about 15 minutes. Random island bearing and off-course banking mean real runs are often
longer.

| Crew (straight, no storm) | Sink (m/s) | Time to island | Altitude at island |
| ------------------------- | ---------- | -------------- | ------------------ |
| 0                         | 25         | N/A (ground ~11.7 min) | —            |
| 5                         | 18.5       | ~15 min        | ~850 m             |
| 10                        | 12         | ~15 min        | ~6 700 m           |
| 16+                       | 5          | ~15 min        | ~11 000 m          |

With ~5 active crew on a straight heading, the plane should pass over the island with roughly
850 m of altitude remaining — about three more minutes at minimum sink rate before touchdown.

### Navigation and distance to island

The plane flies on a 2D map (north-up coordinates) instead of counting a scalar down.

- When the emergency landing starts, the island is placed at a random bearing 13 500 m from the plane. It can be anywhere in the full circle, including behind the plane.
- The plane moves at a constant ground speed (the Controller-adjustable approach speed, default 15 m/s) along its current heading. Speed is unaffected by turns.
- Bank angle is the only thing that turns the plane: `heading += bankAngle * turnRate`. The crew must keep the cabin balanced to fly straight; nothing auto-corrects the heading.
- `distanceToIsland` is the true straight-line distance, so steering away genuinely increases it and a bad path costs distance.
- At altitude 0, the remaining straight-line distance is the score (0 m = perfect landing). Reaching the island while still high simply means flying over it; the plane must circle back down.

The island is drawn heading-up: centered when it is dead ahead, sliding left or right as the plane turns, and replaced by a chevron on the screen edge once it leaves the field of view. The arrow side follows the island's bearing and flips edges as the bearing wraps past ±180°. Island **visual** size uses inverse-distance scaling so it stays small while far and grows quickly when close; the distance readout and score remain true straight-line metres.

### Bank angle

```
windEffect  = windDirection * (windStrength / 100) * windRamp * gustMultiplier * 15
stormEffect = (randomBase[-2..2] + randomJitter[base±0.2]) * stormIntensity
crewBank    = (counterRight - counterLeft) * bankPerPerson
bankAngle   = clamp(crewBank + windEffect + stormEffect, -90, 90)
```

`gustMultiplier` is a mid-biased random value in `0..1` that eases toward a new target every 6 seconds. At light breeze the peak bank is `0.25 * 15° = 3.75°`; gusts can be anywhere from calm (0) up to that maximum.

`bankPerPerson` defaults to 2° and is adjustable on the Controller (0.5–8° in 0.5° steps) so small and large crews can tune turn sensitivity.

The displayed bank angle is interpolated smoothly each frame and drives both the artificial horizon and the navigation turn rate.

Storm bank timers (3 s base roll, 1 s jitter roll) run only while ramped thunderstorm intensity is above zero; they pause when intensity returns to zero.

Wind gust timers (6 s target roll, 6 s ease) run only while ramped wind intensity is above zero; they pause when intensity returns to zero.

## Weather

Weather effects are independent toggles and can be combined. Controller weather toggles are only
available during the Emergency phase; effects ramp in once activated.

| Effect          | Behaviour at full intensity                                      |
| --------------- | --------------------------------------------------------------- |
| Wind left/right | Gusty bank bias up to `±(windStrength / 100) * 15°`; cockpit shows strength and direction |
| Thunderstorm    | +10 m/s extra altitude loss; random bank bias up to ±2° (±0.2° jitter); flicker + screen shake |

Wind strength is set in discrete steps: light breeze (25), moderate (50), strong (75), severe storm (100). Gust targets are drawn mid-biased (clustered around half strength) so wind feels variable but not chaotic; strength can drop to zero between gusts.

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
- `settings_update` — approach speed and bank-per-person sensitivity
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
    engine/             # physics_engine, weather_ramp, bank_interpolator, storm_bank
    screens/            # home, cockpit, controller, success
    widgets/            # artificial_horizon, neon_display, phase_scenery
  assets/
    audio/              # cabine-noise, danger, warningSpeach, thunderstorm, wind, water-impact
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




curl -v \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNmZGZ6b2NzeW5mdnZqc3lvd294Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIzMDY3MTQsImV4cCI6MjA5Nzg4MjcxNH0.y75gQDIsPCPYDpuZGMa89ZnD3fVl2XDFcu4tX8Y-HtA" \
  -H "Content-Type: application/json" \
  --data-raw '{"action":"startCruise","source":"curl-test"}' \
  "https://cfdfzocsynfvvjsyowox.supabase.co/realtime/v1/api/broadcast/room-rakete-strand/events/phase_action"


