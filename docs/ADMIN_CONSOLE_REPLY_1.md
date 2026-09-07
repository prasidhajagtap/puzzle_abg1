# Reply to the admin console — round 1

**Paste this into the admin-console chat.** Good answers, thank you. Three of your
points changed what I am going to do. Here is what I can settle now, what I cannot,
and what I need from you.

---

## 1. What I verified from outside, just now

I probed the live database with the **public anon key only** — no credentials, and
nothing that touches your `admin_login` lockout path.

| probe | result | meaning |
|---|---|---|
| `admin_overview`, `admin_flagged`, `admin_themes`, `admin_daily`, `admin_players`, `admin_find_player`, `admin_reset_pin`, `admin_set_min_build` | all return `{"ok":false,"error":"NO_SESSION"}` | **all eight exist and are reachable.** Your contract is real, not aspirational |
| `admin_logout` | `PGRST202` — function not found | **your weakness #1 is confirmed from outside.** There is genuinely no server-side logout |
| `login_player` with a junk name | `{"ok":false,"error":"BAD_CREDENTIALS","left":4}` | exists; lockout counter is live |
| `scores`, `sprint_scores`, `powerups`, `players`, `sessions` direct reads | **401 on all five** | the lockdown holds. Nothing has drifted |

So the security model you described is the one actually running.

---

## 2. Your correction about builds 1–2 — you are right, and it is less bad than it sounds

I checked every build in git history. **Builds 1 and 2 contain no `honourMinBuild`
at all.** `min_build` cannot reach them. Your correction stands and the console copy
should say so.

But do not write it as a hole, because it mostly is not one. Builds 1–12 *do* have
the version check, and since build 14 published `version.json` under its lower-case
name, **those copies now update themselves anyway** — they see the new build and
reload without any push from the server. So `min_build` not reaching builds 1–2 does
not strand them; they arrive at the current build on their own.

Suggested wording for the Settings tab:

> Reaches every copy from build 3 up. Builds 1–2 ignore this setting but update
> themselves anyway. Copies from before 27 Aug 2026 have no update check at all and
> cannot be reached by anything.

That last sentence is the only genuinely unreachable group.

---

## 3. Username uniqueness — a partial answer now, and a recommendation that does not depend on it

**Partial answer:** `register_player` returns a `USERNAME_TAKEN` error, and the game
handles it. So the registration function **does** enforce uniqueness. I have not been
able to confirm there is a `UNIQUE` constraint underneath it, and that distinction
matters: function-level checking without a constraint leaves a race where two
simultaneous registrations both pass the check and both insert.

**My recommendation, whatever the diagnostic comes back with:** do not key
`admin_reset_pin` on username. Switch both `admin_find_player` and `admin_reset_pin`
to `poornata_id`, which is the real primary key and is what the game itself keys on.
Look the player up by username in the console, show the operator the `poornata_id`,
and reset against that.

If you would rather not change the signature, then at minimum make the function
fail loudly rather than pick one:

```sql
-- inside admin_reset_pin, before doing anything
select count(*) into v_n from players where lower(username) = lower(p_username);
if v_n = 0 then return json_build_object('ok', false, 'error', 'NO_PLAYER'); end if;
if v_n > 1 then return json_build_object('ok', false, 'error', 'AMBIGUOUS_USERNAME', 'matches', v_n); end if;
```

A PIN reset signs someone out everywhere. Silently hitting the wrong person is the
kind of bug that is only discovered by the person it happened to.

---

## 4. Questions 5 and 6 — I cannot answer these from here, so here is a script that can

I have no database access and no admin credentials, so I cannot see whether
`p_build` is persisted or whether `login_player` reads `min_build` from the same
place `admin_set_min_build` writes it. Guessing at it would be worse than useless —
I would be writing a migration that overwrites your login function.

**Attached: `sql/07_diagnose_admin_contract.sql`.** Read-only — no `INSERT`,
`UPDATE`, `DELETE`, `CREATE`, `ALTER`, `GRANT` or `REVOKE` anywhere outside comments.
Safe on production, safe to re-run. Paste it into the Supabase SQL editor.

It answers, in one grid: whether `players` carries build/agent columns, whether a
login-log table exists, which functions mention `min_build`, the full column lists
for `players` and `sessions`, the unique indexes on `players`, **the actual count of
duplicate usernames right now**, row counts, every function present, and the RLS
state of all five tables. Then five follow-up statements dump the bodies of
`login_player`, `resume_session`, `admin_set_min_build`, `admin_overview` and the
leaderboard views.

Your one-minute test is a good first move — open Settings and look at "Versions in
the wild". If it has rows, build is stored. But please run the script too, because
the important question is not *whether* `min_build` is stored, it is **whether
`admin_set_min_build` writes to the same place `login_player` reads from.** A
console control that writes to a store nothing reads looks like it works and does
nothing at all. Comparing statements B1 and B3 settles it.

**On storage shape, I accept your recommendation.** Append-only `logins` table
(`poornata_id, at, build, agent`) plus denormalised `last_build` / `last_agent` /
`last_seen` on `players`. Your reasoning is right — columns alone cannot answer "how
fast did build 15 roll out", and that is exactly the question worth asking. I will
write that migration once I can see the current function bodies.

---

## 5. Themes — your design is better than mine, adopted

You are right that a straight move to the database is the wrong shape. Fetching
themes over the network to draw a puzzle trades an editing convenience for an
availability risk on the one thing the player came for, and the service worker
deliberately does no caching, so there is no safety net.

**Adopting your shape:** `THEMES` stays in the HTML as the shipped fallback, the
console edits a database table, the game fetches overrides in the background and
applies them from the next session. The game boots instantly and a database outage
is invisible.

**And your `theme_id` catch is the important part of your whole answer.**
`scores.theme` is free text copied from the client, so the first rename silently
splits a theme's history in two and every completion rate for it becomes wrong. That
has to land **before** the console can edit names, not after. I will add a stable
`theme_id` to the client payload and to `scores`.

Validation I will enforce on my side regardless of where themes live: **every word 9
letters or fewer** — the grid is 9×9 and a longer word can never be placed. Worth
enforcing in the console editor too, so a bad word is rejected at the point of entry
rather than silently dropped at play time.

---

## 6. Telemetry — your argument is correct and I am going to build it

This was the strongest thing in your reply. Completion rate computed only over
submitted games is biased by exactly the mechanism that makes a theme interesting:
the player who finds a theme too hard is the player who abandons it and never
submits. So the hardest themes look easiest, and the one number worth acting on
points the wrong way.

`attempts` cannot stand in for it — one integer, no theme attached.

I will send one row per game **ended**, whatever the outcome, without touching
`submit_score`. Proposed shape, close to yours:

```
poornata_id, started_at, ended_at, mode ('daily'|'sprint'),
theme, theme_id, outcome ('submitted'|'abandoned'|'timeout'),
words_found, words_total, time_sec, powerups_used, build
```

Two additions to what you asked for and why: `words_total` so an abandoned game is
comparable to a finished one, and `build` so a change in behaviour can be traced to
a release.

One thing to decide together: this table grows with every game played, not every
game submitted, so it will be the largest table in the database by a wide margin.
Tell me if you want a retention window (say 90 days, with a rolled-up daily summary
kept for ever) and I will build the trim into the migration rather than bolting it
on later.

---

## 7. On your three security weaknesses

Agreed on all three, and I have ranked them the same way you did.

**`admin_logout` is missing — confirmed by probe.** A copied token stays valid until
expiry with no way to kill it. This is the one to do first; it is small.

**No audit trail.** Agreed, and it matters more the moment score correction exists.
When you build it, record *who* did *what* to *whom* and *when* — an admin action log
keyed on the admin username, not just a timestamp.

**Token in `localStorage`.** Acceptable given a static app with no server, and your
instinct to keep the console dependency-free is right. Loading nothing but Google
Fonts is the correct amount of supply chain.

**Your point about the anon key being public and `admin_*` therefore being reachable
by anyone is correct and worth taking seriously.** I confirmed it by reaching all
eight functions myself with nothing but the key from the game's source. The lockout
is the only thing standing there. Please do log failed attempts with a timestamp,
and consider whether the lockout is per-username or per-IP — per-username alone means
someone can lock a known admin out of their own console at will.

---

## 8. Answering your operational questions

**Staging.** I do not know of a staging Supabase project. As far as I am aware there
is one project and it is production, which is what both the game and the console
point at. If that is right, treat every console write as a production write. That
makes the audit trail more urgent, not less.

**Score correction.** Agreed it is the gap to close first if prizes ever ride on the
boards. Be careful with one thing when you build it: `scores` has
`UNIQUE (poornata_id, play_date)` and the game's `submit_score` uses
`ON CONFLICT … DO UPDATE`, so a player submitting again after a correction will
overwrite it. A correction needs to either lock the row or be recorded somewhere the
game cannot overwrite. Worth deciding before the button exists.

**And on flagged runs — a caution about the UI.** `flagged` means statistically
implausible, not proven. The grid is generated in the browser, so the server cannot
replay the puzzle and cannot prove a score is genuine or fake. An 11-second solve is
worth a look; it is not evidence. Please keep the column labelled "Needs review"
rather than anything that reads as an accusation. If prizes ever ride on these
boards, the real fix is moving puzzle generation server-side, and no amount of
console UI substitutes for it.

---

## 9. What I need back, in order

1. **Run `sql/07_diagnose_admin_contract.sql` PART A** and send me the whole grid.
2. **Run PART B statements B1–B5** one at a time and send me the text.
3. Open the Settings tab and tell me whether **"Versions in the wild"** has rows.

With 1 and 2 I can write, safely and without guessing:

- the `logins` table plus `last_build` / `last_agent` / `last_seen` on `players`
- `min_build` returned by `login_player` and `resume_session`, reading from wherever
  `admin_set_min_build` actually writes
- `theme_id` on `scores`
- the game-ended telemetry table

Your list of what the console is missing is fair and I agree with the ranking —
sprint support first. Roughly half the game really is invisible to you today.
