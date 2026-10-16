# Earthquake VFX

Everything lives in this folder. Nothing in `City/` was changed.

## Test it

| Scene | What it is |
|---|---|
| `earthquake_test.tscn` | Sandbox: a row of 5 test buildings plus a small block behind them. Safe to wreck. |
| `earthquake_city_test.tscn` | Loads `City/city.tscn` at runtime and runs the effects on the real city. The city file is never touched. Reset or F5 puts everything back. |

Open one and press **F6** (Run Current Scene).

| Key | Action |
|---|---|
| 1 / 2 / 3 / 4 | Quake the target building: Undamaged / Damaged / Razed / Auto (uses `structural_integrity`) |
| C | City-wide quake (magnitude slider, epicenter = target building or the EarthquakeZone) |
| Tab / Shift+Tab | Next / previous target building |
| F / O | Focus camera on target / overview |
| R | Reset everything |
| F5 | Reload the scene |
| RMB + WASD/QE | Fly (Shift = fast) |

## Use it in the game

### One building
```gdscript
# quick one-liner (returns the BuildingQuake so you can reset() it later)
var q := BuildingQuake.play($Districts/OldQuarter/Buildings/building_c, BuildingQuake.Outcome.RAZED)

# or as a node in a scene: add a BuildingQuake node, set `building` in the inspector, then
$BuildingQuake.trigger()                                  # uses the `outcome` export
$BuildingQuake.trigger(BuildingQuake.Outcome.DAMAGED)     # force an outcome
$BuildingQuake.trigger(BuildingQuake.Outcome.AUTO, 1.5)   # start after 1.5 s
$BuildingQuake.reset()                                    # put the building back
```
Signals: `started`, `main_shock`, `part_broke(chunk)`, `collapsed`, `finished(outcome)`.

Outcomes:
- **UNDAMAGED**: it shakes hard, some windows pop, dust sifts off the roof and people run out. The building ends up exactly as it was.
- **DAMAGED**: the windows blow out, real pieces of the building break off and tumble down, and cracks spread. It ends up leaning, dust-coated and smoking. People jump from windows.
- **RAZED**: the top breaks into chunks, the building pancakes into the ground inside a huge dust cloud, and a rubble pile is left behind.
- **AUTO**: picks an outcome from `structural_integrity` metadata × `intensity`. Metadata `quake_outcome` = `"none"`, `"damaged"` or `"razed"` forces one.

Exports let you switch off glass, dust, debris, people, breaking parts, rubble, the ground crack, smoke and camera shake, and scale particle counts.

### Whole city
```gdscript
var quake := CityEarthquake.new()
quake.buildings_root = $City/Districts
add_child(quake)
quake.start_quake(7.5)    # magnitude 4 - 9.5
quake.reset()
```
A shock ring and a wall of dust roll out from the epicenter. Every building and street prop jolts as the wave reaches it, and weak props end up leaning. Fault fissures open, dust haze settles over the city and the camera rumbles. The weakest or closest buildings get damaged or razed (capped by `max_razed` / `max_damaged`), and a few others evacuate.

## Files
- `building_quake.gd`: the single-building effect
- `city_earthquake.gd`: the city-wide effect
- `quake_fx.gd`: dust / glass / debris particle builders
- `quake_person.gd`: the little fleeing / jumping people
- `quake_camera_shake.gd`: camera shake (uses h/v offset + roll, so it doesn't fight `fly_camera.gd`)
- `quake_building.gdshader`: building material during a quake (cracks, dust coat, broken-off pieces)
- `quake_dust.gdshader`, `quake_wave.gdshader`: dust puffs and the ground shock ring
