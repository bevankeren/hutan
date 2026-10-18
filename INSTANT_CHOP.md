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

## Status: the tree was felled, but NOT by this method

After the capture above, the Captain reported the tree was felled — a Secret
`MoonwellBaobab` dropped. **The minigame still ran**, so the chop went through the
normal path, not through log replay. This file previously recorded that as "worked";
that was wrong and is corrected here.

The lesson is worth keeping: the tree falling does not prove the replay was accepted.
Only `FinishChop` returning `Ok` does.

## What is still untested

Two mismatches were identified from the capture. Both were changed together in one
attempt, and that attempt was rejected, so neither is validated:

1. **Arg 3 must be `false`.** Sending `true` claims a perfect run, which the log has
   to back up. The real client sends `false`.
2. **`wallSinceOpen` must track real time since `StartChop`**, not since the strike
   loop began. The loop starts ~800 ms after the session opens, so every wall value
   was short by that much and the pair `(elapsed, wall)` stopped resembling a real
   client's output.

The next step is to isolate them rather than change both at once:

```
A: arg3=false + OLD wall clock   -> if this passes, the wall fix is unnecessary
B: arg3=false + NEW wall clock   -> comparison
```

Run each until `FinishChop` returns `Ok=true`. Anything less is guesswork.

## MinDuration is a hard floor

The server enforces `MinDuration` (6.64 s for this Secret) in real time, so no chop is
truly instant. The shortest possible is `MinDuration`; what log replay would remove is
the *difficulty* of the minigame, not the clock.

## Fallback

If replay keeps being rejected, the remaining option is driving the real minigame
accurately: read the ring, derive the simulation clock from it, and fire on that
clock rather than on wall time. `MaxStep` clamping means wall time and sim time
diverge whenever a frame exceeds 50 ms, which is exactly what happens on the PC.


