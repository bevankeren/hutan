# Instant Chop — what the server actually checks

Goal: skip the minigame entirely for fast (Secret) trees, without low frame rate
killing the timing.

## What the real client sends

Captured by wrapping `TreeService.ChopStrike.Fire` and `TreeService.FinishChop`
during a genuine chop. The exact tuples:

```
ChopStrike(tree, elapsed, wallSinceOpen)

  1.1630274960771203 | 1.1575013010005932
  1.4471074445173144 | 1.441627239000809
  1.7372458316385746 | 1.7288674470000842
```

The two numbers are **close but not equal** — a few milliseconds apart. `elapsed` is
the simulation clock, `wallSinceOpen` is `os.clock() - opened`. They travel together.

```
FinishChop(tree, true, false, log46)

  argc=4
  arg1  Instance  MoonwellBaobab
  arg2  boolean   true     <- felled
  arg3  boolean   false    <- perfect
  arg4  table     46       <- the log
```

**Arg 3 is `false`.** The client does not claim perfect. Every attempt so far sent
`true`, which is a claim the log has to back up.

## Why low FPS broke it

`NotchRules.MaxStep = 0.05`. The simulation advances at most 50 ms per frame:

```lua
local v2 = math.min(dt, MaxStep)
elapsed = elapsed + v2
```

On the phone the frame delta was 16.6 ms average, 29.3 ms max — still inside the
clamp, so the sim runs. On the PC at 9–14 FPS the delta was 69–110 ms, which the
clamp cuts to 50 ms per frame. The simulation clock then falls behind wall time
without bound, so any schedule built on `os.clock()` diverges and every strike lands
in the wrong zone.

## The plan that Replay accepts

Built offline against the session's own params and seed:

```
strikes  45
felled   true
perfect  true
fellAt   13.9831
```

Sequence is mechanical once `tune.Approach`, `LockSeconds` and `Recover` are known:

```
K        = (1 - Target) * Approach        -- target offset, 0.2712 for this tune
hit[n]   = LockSeconds + n*K + (n-1)*Recover
entry[n] = {"S", hit[n], "A", 0}
```

For the Secret tune: `Approach 0.3874`, `Recover 0.02`, `K 0.2712`.
Perfect window is `2 * tune.Perfect * Approach` = 21.45 ms.

## Status: not yet accepted

Sending the log with 45 paced `ChopStrike` fires and then
`FinishChop(tree, true, true, log)` returns **"That chop didn't go through"**.

Two mismatches identified from the capture and not yet tested together:

1. **Arg 3 must be `false`.** Sending `true` claims a perfect run.
2. **`wallSinceOpen` must track real time since `StartChop`**, not since the strike
   loop began. The loop starts ~800 ms after the session opens, so every wall value
   was short by that much, and the pair `(elapsed, wall)` no longer resembled what a
   real client produces.

Both are corrected in the next attempt. The tree that was targeted got felled by
another player before the retest, so it is untested as of this note.

## Fallback if it stays rejected

The server also enforces `MinDuration` (6.64 s for this Secret) in real time, so there
is no true instant path — the shortest possible chop is `MinDuration` regardless. If
the log replay will not pass, the remaining option is driving the real minigame
accurately: read the ring, derive the simulation clock from it, and fire on that
clock rather than on wall time.
