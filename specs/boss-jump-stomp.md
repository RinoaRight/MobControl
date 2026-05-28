# Spec: Boss "Jump-Stomp" Special Attack (v2 — Dodgeable)

> Target audience: another engine / language reimplementation.
> Source of inspiration: `DoBossSpecial` in [src/server/Enemies.lua](../src/server/Enemies.lua) — but the v2 behavior described here is **new**, not a 1:1 port. See §11 for the mapping back to the reference.

## 1. Overview

A melee boss that chases a target player and periodically commits to a **jump-stomp**: rise into the air spinning, descend onto a *frozen* ground target, and on impact emit a circular shockwave that knocks back and damages any player still inside its radius. The frozen target combined with a deliberate windup gives the player a **dodge window**: leave the marked radius before impact and take no damage. A cooldown gates successive jumps so chain damage is impossible even if the player fails to dodge.

The central design goal: every successful hit must be a player mistake (slow reaction or misread positioning), and every dodge must feel earned (committed movement away from a clearly telegraphed zone).

## 2. The Dodge — Design Pillar

The attack is built around a fair, readable dodge contract:

1. **Commitment is one-sided.** The boss commits when the player enters `JUMP_TRIGGER_RANGE`. Once committed (entering `WINDUP`), the boss will follow through whether or not the player stays close. The player commits *after* seeing the telegraph.
2. **Target is frozen at the end of windup, not at impact.** When `WINDUP` ends and `AIRBORNE` begins, the boss locks onto the player's *current* position. From this moment on, the player can move freely — the boss is committed to that spot on the ground.
3. **A persistent ground telegraph is shown for the entire `AIRBORNE` phase.** The player sees exactly where the shockwave will land. The telegraph is the contract — its outer edge matches `SHOCKWAVE_RADIUS` exactly.
4. **Dodge succeeds iff the player's hitbox center is outside `SHOCKWAVE_RADIUS` at the moment of impact.** No i-frames, no leniency window — pure positional check. (Optional fairness buffer: §6.)
5. **The player is slightly slowed during `WINDUP`.** This is a deliberate "boss presence" pressure: the dodge has to be committed early, not panicked at the last frame. Player movement returns to full speed at `AIRBORNE` entry.
6. **Timing budget must be reachable even with the slow.** The player must be able to clear the radius using normal movement during the time between telegraph appearance and impact. This is a numeric constraint, not a soft goal — see §3.1.

## 3. Tunable Parameters

| Name | Units | Meaning | Suggested |
|---|---|---|---|
| `CHASE_SPEED` | u/s | Boss horizontal speed in `CHASING` | 8 |
| `JUMP_TRIGGER_RANGE` | u | Distance at which boss commits to jumping | 12 |
| `WINDUP_DURATION` | s | Crouch / charge time before takeoff (telegraph visible from start) | 0.4 |
| `WINDUP_PLAYER_SLOW_MULT` | — | Multiplier applied to player horizontal speed during `WINDUP` | 0.6 |
| `JUMP_DURATION` | s | Takeoff to landing | 1.0 |
| `JUMP_PEAK_HEIGHT` | u | Apex height above ground | 14 |
| `SPIN_REVOLUTIONS` | revs | Full Y-axis rotations during `AIRBORNE` | 2 |
| `SHOCKWAVE_RADIUS` | u | Damaging radius around landing point (= telegraph radius) | 6 |
| `STOMP_DAMAGE` | hp | Damage on hit | 25 |
| `KNOCKBACK_DISTANCE` | u | Horizontal displacement of struck players | 20 |
| `KNOCKBACK_VERTICAL` | u | Vertical lift of struck players | 20 |
| `KNOCKBACK_DURATION` | s | Knockback tween length | 0.3 |
| `RECOVERY_DURATION` | s | Grounded recovery before resuming chase | 0.5 |
| `JUMP_COOLDOWN` | s | Min elapsed time between successive `WINDUP` entries | 2.0 |
| `DODGE_GRACE` | u | *(optional)* fairness buffer subtracted from radius at impact check | 0.25 |

### 3.1 Dodge-feasibility constraint (must hold during tuning)

Let `PLAYER_SPEED` be the player's nominal horizontal speed. Because the player is slowed during windup, the effective travel budget across the full pre-impact window is:

```
budget = PLAYER_SPEED · WINDUP_PLAYER_SLOW_MULT · WINDUP_DURATION
       + PLAYER_SPEED · JUMP_DURATION
```

The constraint:

```
budget ≥ SHOCKWAVE_RADIUS + SAFETY
```

with `SAFETY ≈ 1–2` units. With the suggested defaults and `PLAYER_SPEED = 16`:
`16 · 0.6 · 0.4 + 16 · 1.0 = 3.84 + 16 = 19.84 ≥ 6 + 2 = 8` ✓ (comfortable; the player has roughly 2.5× the budget needed, even with the windup slow).

If designers tighten `WINDUP_DURATION`, grow `SHOCKWAVE_RADIUS`, or lower `WINDUP_PLAYER_SLOW_MULT`, recheck this inequality. Violating it means the attack is undodgeable by definition — a bug, not a difficulty setting.

## 4. Actor State Machine

| State | Entry | Exit |
|---|---|---|
| `CHASING` | Default; or from `RECOVERY` | Player within `JUMP_TRIGGER_RANGE` **and** `cooldownTimer ≤ 0` → `WINDUP` |
| `WINDUP` | From `CHASING`; apply player slow | `windupTimer ≤ 0` → `AIRBORNE` *(target frozen here; player slow lifted)* |
| `AIRBORNE` | From `WINDUP` | Arc parameter reaches 1 → `IMPACT` |
| `IMPACT` | From `AIRBORNE` | Single-frame; always → `RECOVERY` |
| `RECOVERY` | From `IMPACT`; starts `cooldownTimer = JUMP_COOLDOWN` | `recoveryTimer ≤ 0` → `CHASING` |

Key invariants:

- **No cancellation after `WINDUP` begins.** The player leaving range during windup does *not* abort the jump. This is intentional: it preserves boss commitment and makes the dodge meaningful.
- **No re-targeting after `AIRBORNE` begins.** The landing point is frozen for the duration of the arc.
- **No simultaneous attacks.** While not in `CHASING`, the boss cannot enter `WINDUP` again.
- **Player slow scope.** `WINDUP_PLAYER_SLOW_MULT` applies *only* during `WINDUP`. It is applied on `WINDUP` entry and lifted on `AIRBORNE` entry. The slow applies to every player the boss has aggro on (or all players in a co-op fight — engine's choice; document whichever).

## 5. Per-Tick Behavior (Δt = `dt`)

```
on tick(dt):
    cooldownTimer = max(0, cooldownTimer - dt)
    if state != AIRBORNE:
        faceTowards(player)        # see §7

    switch state:
      CHASING:
          moveHorizontalTowards(player, CHASE_SPEED * dt)
          if distance2D(boss, player) <= JUMP_TRIGGER_RANGE and cooldownTimer == 0:
              windupTimer = WINDUP_DURATION
              showTelegraph(player.position, SHOCKWAVE_RADIUS)   # see §6
              applyPlayerSlow(WINDUP_PLAYER_SLOW_MULT)            # see §2 #5
              enter WINDUP

      WINDUP:
          windupTimer -= dt
          updateTelegraph(player.position)                       # tracks player during windup
          # boss does not translate
          if windupTimer <= 0:
              landingTarget = player.position                    # FROZEN
              lockTelegraph(landingTarget)                       # telegraph stops tracking
              clearPlayerSlow()                                   # player back to full speed
              takeoffPos  = boss.position
              takeoffYaw  = boss.yaw
              jumpElapsed = 0
              enter AIRBORNE

      AIRBORNE:
          jumpElapsed += dt
          t = clamp(jumpElapsed / JUMP_DURATION, 0, 1)
          horizontal = lerp(takeoffPos, landingTarget, t)
          vertical   = 4 * JUMP_PEAK_HEIGHT * t * (1 - t)        # parabola, 0..H..0
          boss.position = (horizontal.x, ground + vertical, horizontal.z)
          boss.yaw     = takeoffYaw + SPIN_REVOLUTIONS * 360° * t
          if t >= 1:
              enter IMPACT

      IMPACT:
          hideTelegraph()
          resolveShockwave(landingTarget)                        # see §6
          recoveryTimer = RECOVERY_DURATION
          cooldownTimer = JUMP_COOLDOWN
          enter RECOVERY

      RECOVERY:
          recoveryTimer -= dt
          if recoveryTimer <= 0:
              enter CHASING
```

Defensive cleanup: if the boss dies or is force-removed in any non-`CHASING` state, `clearPlayerSlow()` and `hideTelegraph()` must run as part of teardown. Don't leak the slow onto the player.

## 6. Telegraph & Shockwave Resolution

### 6.1 Telegraph (visual contract with the player)

- Appears on `WINDUP` entry as a ground decal centered on the player's current position, with radius **exactly** `SHOCKWAVE_RADIUS`.
- During `WINDUP`, the telegraph **tracks** the player's horizontal position. (Optional: fade-in over the first 25% of `WINDUP_DURATION` to avoid pop-in.)
- At `AIRBORNE` entry, the telegraph **locks** in place and stays visible for the entire airborne phase. This locked state is the only honest signal the player has — its position is the source of truth for the dodge.
- The telegraph is purely cosmetic on the client; the server's `landingTarget` is authoritative for damage. Client and server must compute the lock at the same logical moment (server emits the event; client renders from it — see §8).

### 6.2 Shockwave (damage resolution at `IMPACT`)

For each player `p` in the world:

```
d = distance2D(p.position, landingTarget)
if d > SHOCKWAVE_RADIUS - DODGE_GRACE:
    continue                                  # dodged
if not p.isAlive:
    continue
applyKnockback(p, landingTarget)              # §6.3
scheduleDamage(p, STOMP_DAMAGE, atTime = now + KNOCKBACK_DURATION)
```

A single jump resolves shockwave **once** per player. Re-entry into the radius after `IMPACT` does not retrigger damage from the same jump.

### 6.3 Knockback

```
dir = normalize(p.position - landingTarget)
if d == 0: dir = boss.facingDir   # fallback for exact-center case
target = (
    p.x + dir.x * KNOCKBACK_DISTANCE,
    p.y + KNOCKBACK_VERTICAL,
    p.z + dir.z * KNOCKBACK_DISTANCE,
)
tween(p, p.position → target, duration = KNOCKBACK_DURATION, easing = SineOut)
```

Player control resumes when the tween completes; HP is deducted at the same moment.

## 7. Facing

In `CHASING`, `WINDUP`, and `RECOVERY`, the boss yaws toward the player on the horizontal plane. Yaw may be instant or eased (suggested angular velocity ~6 rad/s for `CHASING`, near-instant for `WINDUP` so the windup pose reads).

In `AIRBORNE`, yaw is driven by the spin animation and **ignores** the player — this also visually communicates that the boss can no longer re-target.

## 8. Authority & Synchronization

- Server-authoritative: state transitions, timers, `landingTarget`, damage, knockback, and the player slow.
- Server broadcasts: `onWindupStart(initialTargetPos, slowMult)`, `onAirborneStart(landingTarget, takeoffPos, takeoffYaw, jumpDuration, peakHeight, spinRevolutions)`, `onImpact(landingTarget, affectedPlayers[])`, `onRecoveryEnd()`.
- Clients reproduce the arc, spin, and telegraph locally from these anchors. The arc is deterministic given `(takeoffPos, landingTarget, jumpDuration, peakHeight)` and `t = elapsed/jumpDuration`, so no per-frame transform streaming is required.
- The telegraph **must** be rendered from the server-broadcast `landingTarget` at `onAirborneStart`, not from the local player's position — otherwise client/server drift makes dodging unfair.
- The slow can be applied client-side for responsiveness, but the server is the authority on its start/end times.

## 9. Cancellation & Edge Cases

| Situation | Behavior |
|---|---|
| Player exits `JUMP_TRIGGER_RANGE` during `CHASING` | Stay in `CHASING`; no jump |
| Player exits `SHOCKWAVE_RADIUS` during `WINDUP` | Telegraph follows them; jump *not* triggered until windup ends. If player is outside radius at the *end of windup*, target locks on their (now far) position anyway — this is fine: boss commits to where the player was at the lock instant |
| Player exits `SHOCKWAVE_RADIUS` during `AIRBORNE` | Jump proceeds; player takes no damage at impact (**this is the dodge**) |
| Player re-enters radius mid-`AIRBORNE` after dodging out | Player takes damage at impact (positional check is at impact only, not continuous) |
| Player dies mid-`AIRBORNE` | Jump resolves; dead player skipped in §6.2 |
| Boss dies mid-state | Cancel all timers, clear player slow, hide telegraph, despawn |
| Multiple players inside radius at impact | Each resolved independently per §6 |
| `JUMP_COOLDOWN` > 0 when player enters range | Boss continues chasing without jumping until cooldown elapses |
| Player exactly on landing point (d = 0) | Knockback direction fallback per §6.3 |
| Player standing on terrain higher than ground at impact | `distance2D` ignores Y — they are still hit. (If verticality matters in your engine, gate the check with a max-vertical-offset, e.g. ±4 units, and document it.) |
| Player has a movement-modifier stacking system | The windup slow stacks multiplicatively with other modifiers; lifting the slow on `AIRBORNE` entry must not clear other unrelated modifiers |

## 10. Tuning & Playtest Checklist

- [ ] Confirm dodge-feasibility inequality (§3.1) holds for the slowest movement mode the player will realistically be in during a fight, **with the windup slow applied**.
- [ ] Confirm the telegraph is visible *before* the player must commit to dodging (i.e. appears at `WINDUP` start, not at `AIRBORNE` start).
- [ ] Confirm that committing to a dodge in the **first 50% of `WINDUP_DURATION`** is sufficient to clear the radius (otherwise the windup is too short for visual recognition + reaction).
- [ ] Confirm `JUMP_COOLDOWN ≥ WINDUP_DURATION + JUMP_DURATION + RECOVERY_DURATION` so the boss visibly recovers between attempts — otherwise the throttle is invisible to the player.
- [ ] If `DODGE_GRACE > 0`, confirm it does not exceed ~5% of `SHOCKWAVE_RADIUS` (otherwise the telegraph lies about its effective size).
- [ ] Confirm the windup slow is *felt* but not *crippling* — at the suggested 0.6 it should read as pressure, not paralysis. If the slow feels punitive in playtest, raise the multiplier toward 0.75; if the dodge feels too easy, lower toward 0.5 (but recheck §3.1).

## 11. Mapping Back to the Reference Code (`DoBossSpecial`)

| Reference | Spec equivalent |
|---|---|
| `S.Enemy[id].specialAttackRange` | `JUMP_TRIGGER_RANGE` |
| `S.Enemy[id].tte` (time-to-event) | `JUMP_COOLDOWN` |
| `S.Enemy[id].animationDur` | `WINDUP_DURATION + JUMP_DURATION` |
| `S.Enemy[id].ultDamage` | `STOMP_DAMAGE` |
| `getTweenForKnockback` (n=20, y=20, 0.3s, SineOut) | `KNOCKBACK_DISTANCE`, `KNOCKBACK_VERTICAL`, `KNOCKBACK_DURATION`, easing |
| `PERFORM_SPECIAL_ATTACK` (per-enemy) | "boss in WINDUP/AIRBORNE/IMPACT/RECOVERY" |
| `BOSS_ULT_APPLIED` (per-player) | "shockwave resolved for this player on this jump" |
| `overwriteRotation` | §7 Facing |
| *(no equivalent)* | `WINDUP_PLAYER_SLOW_MULT` — new in v2 |
| *(no equivalent)* | Ground telegraph — new in v2 |
| *(no equivalent)* | Parabolic airborne translation — new in v2 |

**Divergence from reference:** the reference applies knockback unconditionally to whichever player is in range when the attack triggers — no airborne arc, no positional dodge check, no telegraph, no windup slow. The v2 spec adds: airborne translation along a parabola, frozen landing target, ground telegraph, windup-only player slow, and a radius check **at impact** rather than at trigger. The dodge mechanic is the whole point of the new behavior.
