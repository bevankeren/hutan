# Ouroboros v0.38 — Reverse Engineering Notes

Live capture against Foresters (`PlaceId 117020342702668`) while the hub was actively
farming. Everything below is measured from the running client, not guessed.

---

## 1. Why their chop works and ours failed

The game verifies every chop server-side through `TreeService:FinishChop(tree, done,
perfect, log)`, where `log` is the recorded strike history replayed by
`NotchRules.Replay(params, seed, log)`. Sending the call without a matching log is
rejected with **"That chop didn't go through"**, and the admin panel records it as a
`Rejected` infraction with the literal detail:

> "Said the tree fell, but its strikes don't fell it"

Ouroboros never fabricates that log. It drives the **real minigame**, so the client
builds the log itself and the server accepts it. That is the whole trick.

---

## 2. Movement — the part we got wrong

### What they actually do

Measured on a live walk (`Humanoid.WalkToPoint` sampled every 100 ms):

```
t=0.50 pos=-707,38,267 walkTo=-708,35,265
t=0.60 pos=-708,38,265 walkTo=-709,35,262
t=0.70 pos=-709,38,263 walkTo=-710,35,259
t=1.20 pos=-697,38,238 vel=16
t=1.35 pos=-698,38,235 vel=16
t=1.50 pos=-698,38,232 vel=16
t=1.65 pos=-699,38,229 vel=16
```

- **Speed:** constant `3.3 studs / 0.15 s` = **22 studs/s**, `WalkSpeed` reads `16.32`
  and occasionally `32` on open ground.
- **Mechanism:** `Humanoid:MoveTo(waypoint)` with `WalkToPoint` advancing per waypoint.
  This is genuine physics movement — the server's own locomotion replication.
- **`CanCollide = false`** on every character part for the whole trip (their "Noclip").
- **`Anchored = false`**, `PlatformStand = false` — the humanoid keeps simulating.

### Why this matters

Because it is real walking, there is nothing for the server to flag. Our CFrame
teleport — anchored, chunked, noclip, whatever — is a displacement the server never
authorised. It held for short hops and then either snapped back or killed the physics
solver outright.

The crash we kept seeing was ours, not the anticheat:

```
CrashpadHandlerLog: ReadProcessMemory failed (299)
GPU: NVIDIA GeForce MX350, DedicatedVidMem 2075978976 (2 GB)
```

Anchoring **all** character parts severs the assembly welds, so `CFrame` writes to the
root became no-ops — measured `moved = 0` studs while the loop spun. Anchoring **only**
the root moved 361 studs cleanly, which proved the mechanism, but it is still an
unauthorised displacement.

### Their escape hatch

`Main → Movement Mode → Walk (Beta)`, plus:

| Setting | Value | Meaning |
|---|---|---|
| `Walk: Teleport If Farther Than` | `125` | beyond 125 studs it teleports instead of walking |
| `Strip Map (Walk)` | on | sheds map detail so long walks don't exhaust VRAM |

So the design is: **walk for anything under ~125 studs, teleport only as a fallback.**
That is why their chop never breaks — the normal case never touches displacement.

### They are not perfect either

Watched their walker fail and recover in real time:

```
0.2s  Running  pos=-666,38,167  moved=5.2  stuck=0
1.6s  Running  pos=-693,38,178  moved=4.4  stuck=0
2.0s  Running  pos=-695,38,179  moved=0.0  stuck=1
4.0s  Running  pos=-695,38,179  moved=0.0  stuck=11
6.0s  Running  pos=-695,38,179  moved=0.0  stuck=21
7.8s  Running  pos=-695,38,184  moved=4.1  stuck=0
10.0s Running  pos=-693,38,223  moved=1.2  stuck=0
```

Roughly **4 seconds pinned against geometry**, then it recomputed and carried on.
Separately caught it in `Freefall` with the waypoint at `Y=12` while the character sat
at `Y=45` — a path the terrain solver got wrong, and the status line sat on
`"Recalculating path"` the whole time.

The lesson: a pathfinder gets stuck and self-heals. A CFrame teleport either holds or
kills the client. The pathfinder's failure mode is survivable; ours was not.


---

## 3. The chop loop they use

Server-verified strike path, confirmed by hooking the real remote:

```
ReplicatedStorage.Packages._Index.sleitnick_knit@1.4.7.knit.Services.TreeService.RE.ChopStrike
```

Captured payloads from a successful fell:

```
Inst:OakTree , 1.6174439378082752 , 1.603540800000701
Inst:OakTree , 2.5950204003602266 , 2.5829575000007026
Inst:OakTree , 3.5687111180275677 , 3.5608936000007816
```

Signature: `(tree, elapsed, os.clock() - opened)`. The client emits one per strike and
the server replays the whole sequence when `FinishChop` arrives.

The minigame itself:

1. `ChopController:BeginWindup(axeTool, screenPos)` — `screenPos` must be the trunk's
   on-screen position (`Camera:WorldToViewportPoint(trunk.Position) - GuiService:GetGuiInset()`).
2. `ChopController:ReleaseWindup()` opens the session.
3. Dots mount under `PlayerGui.ReactWorld.Dot1..N`, each with
   `Area.Ring.Square.Ring.Stroke`.
4. Strike when that `UIStroke.Color` is the perfect green `(0.61, 0.89, 0.48)`
   (`Theme.NotchPerfect`), by firing `InputBegan` on `Dot.Hit` with a
   `MouseButton1` input.
5. Never abandon a session — a dangling session is what produces the `Rejected`
   infraction. Always `ChopController:Cancel()` when bailing.

---

## 4. What to take

| Insight | Action for our hub |
|---|---|
| Real walking is unflaggable | Replace `teleport_to` CFrame writes with `Humanoid:MoveTo` + `CanCollide=false` |
| 125-stud teleport threshold | Only teleport past a distance the walker can't cover cheaply |
| Root-only anchor works, all-parts doesn't | Keep as documented fallback, never anchor every part |
| `ChopStrike` carries `(tree, elapsed, openedAt)` | Already emitted by the real minigame — don't fabricate it |
| `Strip Map (Walk)` exists | Long trips need the map stripped or VRAM dies on 2 GB cards |
| Dangling sessions raise infractions | Always cancel |

---

## 5. Their feature surface (7 tabs, 67 features)

`Home · Main · Shop · Teleport · Visuals · Webhook · Player · Settings`

Relevant to farming:

- **Main:** Auto Chop Trees, Auto Perfect Saw, Saw Rarities, Auto Pick Up Logs,
  Sell (Zone Island / backpack value / every N minutes), Auto Bargain, Keep filters
  (rarities, sizes, mutated, min value), Movement Mode, Walk threshold, Strip Map.
- **Shop:** Axes To Buy, Equip Bought Axe, Auto Buy Axes, Auto Roll Bloodline.
- **Teleport:** Zone, NPC, Wanderer, Travelling Merchant.
- **Visuals:** ESP for trees/NPCs/wanderers/zones/players with per-type colours.
- **Webhook:** Discord push per chopped tree, rarity filters, mutation filter, pings.
- **Player:** WalkSpeed, Infinite Jump, Noclip, Instant ProximityPrompt,
  No Gameplay Paused, Auto Reconnect on Kick, Disable 3D Rendering, Anti AFK.
- **Settings:** configs with autoload, share/import codes, themes, weather, UI scale.

They also ship an **Auto Reconnect on Kick** toggle — they expect to be kicked and
just come back, which is the opposite of trying to be invisible.

---

## 6. Verified environment facts

| Item | Value |
|---|---|
| Place | `117020342702668` (Foresters 🌳 [RELEASE]) |
| GameId | `10768565587` |
| Teleport marker seen on rejoin | `AnticheatHop=true` |
| Anticheat services | `AnticheatService`, `MovementGuardService`, `PaceService` (no client remotes) |
| Ban path | `BanService.Banned` RemoteEvent → chat broadcast |
| Chop remotes | `RF.StartChop`, `RE.ChopStrike`, `RF.FinishChop` |
| Reach limit | `ChopTuning.ReachStuds = 14` |
| Perfect colour | `Theme.NotchPerfect = (0.608, 0.886, 0.478)` |
| Islands | Oak `(84.5,-562.1)`, Birch `(711.9,-569.2)`, Crescent `(104.1,145.9)`, Snowy `(1361.1,-626.4)`, Dusty `(-626.1,341.1)`, Redwood `(-8.9,-1216.7)` |
