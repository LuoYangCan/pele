# Turn checkpoint: ask at 3 turns / realign at 7

When consecutive turns on the same request reach the threshold and expectations are still unmet, stop and run a checkpoint.

## 3-turn checkpoint: stop and ask

More than **3 consecutive turns** on the same request and the user still has not clearly signaled satisfaction (still repeatedly pointing out problems / repeatedly revising / expressing dissatisfaction) → you must stop and clarify with [the host question tool](host-adapter.md) before continuing.

What to clarify:

- How does the goal I currently understand differ from what you expect?
- Which specific judgments of mine went off track in the past few turns?
- What information am I still missing that I need to ask you, to get the next step right?

## 7-turn checkpoint: realign the direction before adjusting

If expectations are still unmet after **more than 7 turns**, switch from "blind iteration" to "realignment":

1. Re-read the text of the user's **original request**
2. List the approaches already tried + the specific reason each one failed
3. Diagnose the root cause: misread requirement / wrong technical approach / wrong execution detail?
4. Use [the host question tool](host-adapter.md) to align the new direction and assumptions with the user
5. After aligning, re-evaluate the existing code: what to keep, what to rewrite. **Do not discard everything automatically**; rewrite wholesale only when the user explicitly says "start over completely"

For coding tasks running `plan-first-delivery`, steps 4–5 land as going back to DISCOVER/PLAN_READY to produce a replacement plan; do not build a second alignment process.

## How to count turns

- Count from when the user **first raised this request**, not from the session start
- Same request = no topic switch / no change of core goal
- The user moves to another topic → the counter resets to zero
- 1 user message + 1 agent response = 1 turn
- The user says "OK / done / never mind" or another stop signal → this request ends, stop counting

## Does not trigger a checkpoint

- The user has already signaled satisfaction or completion
- **Minor tweaks** within the same request (small additions, core goal unchanged)
- Pure Q&A / explanatory conversation with no goal to converge on
- The user explicitly says "keep trying / try a few more times"
