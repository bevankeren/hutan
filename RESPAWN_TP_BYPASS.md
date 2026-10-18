# Respawn-TP Bypass — Findings

Idea from the Captain: kill the character, and teleport in the window right after the
new character spawns. Theory: a respawn is a **server-authorised** position change, so
the server resets its movement baseline and a jump inside that window is not treated as
an unauthorised displacement.

Tested live on job `a8261516`. **The theory holds.**

## Direct evidence

### First jump — 1248 studs, held

```
spawnPos  = -89,28,-571
target    = 1148,5,-734        (1248 studs away)
0.2s  d=4    pos=1148,8,-737
1.2s  d=5    pos=1148,8,-737
2.4s  d=5    pos=1148,8,-737
3.6s  d=5    pos=1148,8,-737
4.7s  d=5    pos=1148,8,-737
```

`held = true`, `finalDist = 4`. A 1248-stud jump survived 4.7 seconds with no snapback.
The old `teleport_to` could not do this at any speed.

### Second jump — 653 studs, accepted

```
0.3s  d=2   y=68      <- landed on target
0.5s  d=20  y=50
0.7s  d=29  y=41      <- settled, stayed
4.7s  d=84  y=-14
```

The character stayed at the destination (d=29) and only drifted when it fell, because
the target Y was wrong. No server correction.

### Third jump — 192 studs, clean landing

```
0.29s d=1  y=97
4.96s d=2  y=96
```

`held = true`, `finalDist = 1`, health 100 after five seconds.

## Success rate and the real failure mode

Five trials, alternating targets so a stale position cannot be blamed:

| Target | maxD | Held |
|---|---|---|
| `-40,30,-592` | 1 | yes |
| `-140,30,-520` | 18 | yes |
| `20,40,-700` | 4 | yes |
| `-250,30,-600` | 167 | **no** |
| `100,30,-450` | 2 | yes |

**4/5.** The one failure was not a snapback — a raycast at that spot showed:

```
fail-spot  targetY=30  groundY=-0   part=Terrain   <- seabed, 30 studs below
ok-spot1   targetY=30  groundY=24   part=GrassTopPart
ok-spot2   targetY=30  groundY=30   part=UniqueShape1
```

The jump landed, but the target Y sat 30 studs above the seabed so the character fell
into the water and drifted 167 studs. **Altitude error, not anticheat.**

## Why this works

`teleport_to` moved a character the server was actively simulating. The server had a
position baseline for it and saw a displacement it never authorised — snapback, or on
long runs a physics failure.

A respawn destroys that baseline. The server is placing a brand-new character and has
not yet sampled its position, so the first frames are not compared against anything.
A jump inside that window becomes the character's starting position as far as the
server is concerned.

The window is not instant — a 1.0s delay after spawn also held — so there is slack to
work with.

## Required conditions

1. **Raycast the destination for true ground Y before jumping.** Every failure so far
   traces to a wrong Y, not to the server. Land at `groundY + 3.0`.
2. **Respawn costs the equipped axe.** After respawn the character holds nothing; the
   axe sits in the backpack. Equip through `AxeService:EquipAxe(axeId)` before chopping.
3. **Respawn resets the chop session.** Never teleport mid-chop — cancel first.

## What still needs proving

- Long-run stability: this has not been run inside the farm loop for minutes at a time.
- Whether repeated kills raise any server-side counter. Not observed so far, but the
  sample is small.
- Whether the window holds when the server is under load (many players).

## Comparison

| Method | Distance | Result |
|---|---|---|
| `teleport_to` (CFrame walk) | 280+ | snapback or client crash |
| Walk mode (`MoveTo` + pathfinding) | any | works, but slow (~22-38 stud/s) |
| **Respawn-TP** | 1248 verified | **held, 4/5, failures are altitude bugs** |
