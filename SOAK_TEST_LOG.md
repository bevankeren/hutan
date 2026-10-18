# Soak Test Log — disconnect code 285

Five separate attempts to run a 5-minute farm soak. Every one ended the same way.

## The evidence

```
2026-10-18T06:52:09  Player: 285 (DisconnectClientInitiated)
2026-10-18T07:01:12  Player: 285 (DisconnectClientInitiated)
2026-10-18T07:17:07  Player: 285 (DisconnectClientInitiated)
2026-10-18T07:32:01  Player: 285 (DisconnectClientInitiated)
2026-10-18T07:35:59  Player: 285 (DisconnectClientInitiated)
2026-10-18T07:46:54  Player: 285 (DisconnectClientInitiated)
```

Every disconnect carries the identical code. Gaps between them are irregular:
543s, 955s, 895s, 238s, 655s.

## What it is not

| Suspected cause | Ruled out by |
|---|---|
| Client crash | No `CrashpadHandler` / `ReadProcessMemory` lines. The Roblox process stayed alive throughout (7958s CPU, 654 MB, Responding=True, still rendering 2.7s CPU per 3s). |
| Anticheat kick | No `Banned` event, no kick message, no `AnticheatHop` payload on these reconnects. |
| Our teleport code | `TeleportService` reference count in `farm_hub.lua` is **0**. |
| Our walker | One disconnect (07:17) happened with no hub loaded at all. |

`DisconnectClientInitiated` is the client SDK reporting that the server closed the
session — it is the game's own teardown, not a reaction to anything we send.

## What is still unproven

The walker itself has only one clean end-to-end result:

```
job bc8115f3, single run
  walk      294 studs, walkOk = true
  arrival   5 studs from the tree
  chop      10 perfect strikes
  result    Felled, health 100, state Running
  jobId     unchanged (no hop)
```

That is a real success, but it is **one** run. No session has survived five minutes
with the farm running, so long-run stability is not established.

## Next step

Re-run the soak on a fresh session and log per-15s samples. If it survives five
minutes, the disconnects were server-side and the walker is fine. If it drops again
at the same code, the trigger is something the farm loop does and the loop needs
narrowing — start by disabling auto-sell and the quest pass, then re-test.
