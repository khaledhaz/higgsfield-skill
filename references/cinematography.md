# Cinematography Reference

Loaded by the Creative Director (and image-reviewer) at the start of every run. Shot type, camera angle, and composition vocabulary used in `concept_prompt` text. NBP and Soul models interpret these terms more reliably than vague descriptions like "a view of the facility".

## Shot Types

| Type | What it shows | When to use in news packages |
|---|---|---|
| Extreme wide (EWS) | Vast environment, subject tiny | Scale of infrastructure, geography, isolation |
| Wide (WS) | Full environment + subject | Establishing location, showing spatial relationships |
| Medium (MS) | Subject waist-up or half-object | Standard workhorse — equipment, vehicles, facilities |
| Close-up (CU) | Face-filling or single object detail | `synecdoche` technique, detail shots, emotional weight |
| Extreme close-up (ECU) | Eyes, a dial, a crack, a label | Maximum focus on one critical detail |
| Over-the-shoulder (OTS) | From behind one figure toward another | Implied confrontation, diplomatic scenes |

A `concept_prompt` should open with the shot type, e.g. `"Wide shot of an arid plateau with..."` or `"Close-up of a single damaged centrifuge rotor..."`.

## Camera Angles

| Angle | Effect | News-package use |
|---|---|---|
| Eye-level | Neutral, documentary feel | Default for `literal` technique |
| Low angle | Subject appears powerful, imposing | Military hardware, government buildings, warships |
| High angle / overhead | Subject appears vulnerable, exposed | Aftermath, damage assessment, supply depletion |
| Dutch angle (tilted) | Unease, instability | Cyber warfare, regime instability, crisis |
| Bird's eye / drone | God-view, strategic overview | Satellite-style facility layouts, fleet formations |

Pick the angle that reinforces the claim's editorial weight. Low angle of a warship reads "power"; high angle of the same warship reads "exposure". Use these mismatches deliberately, not by accident.

## Composition Rules

### Rule of thirds

Place key subjects at intersection points, not center. Horizon at upper or lower third, never middle (unless deliberate symmetry for `visual_irony` technique).

### Lead room (look space)

Leave empty space in the direction a subject faces or moves. A warship heading right → place it left-of-center with open water to the right. Subject crammed against the edge they're facing reads as wrong.

### Headroom

Space between top of subject and top of frame. Less in close-ups (tight, intense), more in wide shots (context, scale).

### Depth layering

Foreground / midground / background elements at different distances create depth. Example: `"Foreground: barbed wire fence. Midground: empty guard tower. Background: facility under haze."` This is how a flat AI image starts feeling three-dimensional. Single-plane compositions are the #1 tell of AI-generated imagery.

For Wide and Medium shots, every `concept_prompt` should imply at least 2 depth layers.

## Shot-to-Shot Consistency Rules (adapted from 180-degree rule)

When multiple shots share a scene or subjects:

- If a facility is on the LEFT in shot 2, it stays on the LEFT in shot 5.
- If light comes from the RIGHT in the style notes, all `concept_prompts` maintain right-side key light.
- If a subject faces camera-left in a start frame, they should not suddenly face camera-right in the end frame (unless the morph IS about turning away).
- Vehicles/vessels moving in one direction in shot N keep that direction in shot N+1 (unless the script narrates them turning).

These rules prevent the final stitched video from feeling like disconnected random frames assembled by a stranger. They show up most clearly when a `start_end` morph violates one (subject crosses the centerline mid-morph) — Kling 3.0 will produce a warp artifact.

## Quick lookup for the Creative Director

When writing a `concept_prompt`, end the spatial cue line with all three:

```
<shot_type> from <camera_angle>, <composition_cue with depth layering>
```

Examples:

- `"Close-up from low angle of a single hexagonal F-22 thrust nozzle, foreground edge of nozzle ring, midground turbine blades visible behind, background hazy ramp lighting"`
- `"Wide shot from bird's eye drone angle of a brown-beige plateau, foreground dirt road snaking up, midground centrifuge halls in parallel rows behind double fencing, background distant mountains under haze"`
- `"Medium shot from eye-level of a grey frigate-class vessel left-of-center facing right, foreground churning bow wake, midground full hull broadside, background open water and faint coastline"`

These read as cinematic news plates because they specify shot, angle, and depth — not just a noun and a vibe.
