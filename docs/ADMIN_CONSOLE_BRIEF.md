# The Daily Nine — front-end handover for the admin console

**Paste this whole file into the chat that owns the admin console repo.**

You are working on the admin console for a game called **The Daily Nine**. I own
both sides. This file is the current, verified state of the **game front end** and
the **database contract** it uses, so the console can be built or updated against
facts rather than guesses.

Everything below was read out of the live code and the applied migrations. Where I
do not know something about your side, it is listed as a question at the end.

---

## 1. What the game is

- A daily word-search game. 9×9 grid, 5 words, 5 minutes.
- **One single HTML file** — markup, styles and script together. No build step,
  no bundler, no framework.
- Hosted on **GitHub Pages**, deployed from `main`. Merging to `main` *is* the deploy.
- Live: `https://prasidhajagtap.github.io/puzzle_abg1/`
- Repo: `prasidhajagtap/puzzle_abg1`
- Backend: **Supabase** (Postgres + PostgREST).
- The browser holds only the **public anon key**. It can reach nothing directly
  except the leaderboard views. Every write goes through a `SECURITY DEFINER`
  function that checks a session token first.

The admin console is a **separate repo and a separate app**. It talks to the same
Supabase project, but it must use a different, privileged path (see §6).

---

## 2. Two game modes

| | Daily challenge | 10-minute sprint |
|---|---|---|
| Clock | 300 s, counts down | 600 s, never stops |
| Goal | Find 5 words in one grid | Clear as many grids as possible |
| Scored on | 10/word + seconds left (only if all 5 found) + flat 5 streak bonus | Puzzles cleared, then words found, then shorter duration |
| Table | `scores` | `sprint_scores` |
| Board view | `leaderboard_today` / `_week` / `_alltime` | `leaderboard_sprint_today` |

**These are two separate leaderboards. Do not merge them in the console.**

---

## 3. What changed on the front end (builds 12 → 15)

This is what the console may now need to reflect. Grouped by what it means for you.

### 3.1 One play per day was REMOVED — the last submitted score wins

Previously the first score of the day was final and a second attempt was rejected
with `ALREADY_PLAYED_TODAY`. That is gone.

- A player can now play **unlimited times a day** in either mode.
- A finished game is held **locally** and is NOT recorded until the player taps
  submit. Playing again without submitting changes nothing.
- Submitting again **overwrites** the day's row (`ON CONFLICT … DO UPDATE`).
- **The last score a player submits is their score for that day.**

**Console impact:**
- `scores` and `sprint_scores` still hold **exactly one row per player per day**
  (`UNIQUE (poornata_id, play_date)`). Do not build UI that expects many rows per
  player per day.
- The `attempts` column is the count of games that player played that day before
  submitting. It uses `greatest(existing, incoming)` so a refresh can never lower
  it. **`attempts` is the only visibility you have into games played but not
  submitted** — the losing attempts themselves are never sent to the server.
- `ALREADY_PLAYED_TODAY` can no longer be returned. If any console code or docs
  still reference it, remove them.

### 3.2 Power-ups (server-enforced)

- A power-up reveals the first letter of every word still to find.
- **2 per player per day.** The cap is enforced in the database, not the browser,
  so clearing site data or switching phones does not grant more.
- Table `powerups (poornata_id, play_date, used)`, capped at 2 by a conditional
  `ON CONFLICT … WHERE used < 2`.
- Using one is recorded, not penalised. `scores` does **not** carry a powerups
  column; `sprint_scores.powerups_used` does.

**Console impact:** power-up consumption per player per day is queryable and is a
good engagement signal. There is currently **no admin control to grant, reset or
change the allowance** — see the questions.

### 3.3 Sprint mode and its own leaderboard

New table `sprint_scores`, new view `leaderboard_sprint_today`, new RPCs. Same
"last submitted wins" rule.

### 3.4 The trivia pop-up was removed

The per-word trivia pop-up is gone entirely (it covered the word animation). The
facts still appear on the score page. If the console had any content management
for trivia, it is now unused.

### 3.5 Auto-update was broken for the game's entire life — now fixed

This matters to the console because **build number is a real dimension in your data.**

- Builds 1–12 fetched `version.json` in lower case while the file on disk was
  `Version.json`. GitHub Pages is case-sensitive, so **every version check
  returned 404** and nobody ever auto-updated. Verified against the live site.
- Build 13 fixed the spelling. Build 14 publishes the file under **both** names,
  which retroactively rescues every build 1–12 copy: it asks for the lower-case
  name, finally gets an answer, and reloads itself to the current build.
- Build 14+ reads whichever name answers first, and limits itself to two silent
  reload attempts per target build before showing a banner instead (guards against
  a reload loop if a cache serves a stale file).
- The check runs on load, on `visibilitychange` back to visible, on `pageshow`
  from the back/forward cache, and on window focus, throttled to once a minute.
- **Copies from before build 1 (26 Aug 2026 and earlier) have no version check at
  all.** Nothing can reach them; those players need one manual reload.

**The lever the console should expose:** `login_player` and `resume_session` may
return a **`min_build`**. The client already honours it — anything below that
number is treated exactly as if a newer build existed, with the same safe-moment
rules (never mid-game, never with an unsubmitted score on screen). **Builds 3 and
up honour it.** This is a server-side kill switch for a bad build and it is
already wired on the front end. See the questions.

### 3.6 The client reports its build and user agent on every sign-in

`login_player` and `resume_session` are both called with:

```
p_build : integer   -- CONFIG.build of the running copy
p_agent : text      -- navigator.userAgent
```

**If the server stores these, the console can show build adoption and device mix
for free.** I do not know whether the current functions persist them — see the
questions.

### 3.7 Installable to a phone (PWA)

`manifest.json`, icons, a service worker (`sw.js`, push only, deliberately no
caching), an "Add to phone" flow, and an iOS session bridge via Cache Storage
(on iOS a home-screen app gets its own `localStorage`, separate from Safari's).
The service worker was never actually registered until build 13.

### 3.8 Result screen now compares scores side by side

When a score already stands for the day, the results screen shows the standing
score and the run just played side by side with the difference, before the player
decides. Cosmetic — no data model change.

### 3.9 Signed-in identity is now on every screen, plus author credit

A "Signed in as <username>" bar on every screen except sign-in and mid-game, and a
footer: "Developed by Prasidha J · © 2026 Prasidha Jagtap. All rights reserved."
Cosmetic — no data model change.

### 3.10 Leaderboard reachable from the mode picker

The board can now be opened before playing, and its back button returns to
wherever it was opened from. Cosmetic.

---

## 4. Themes — read this carefully, it constrains the console

**39 themes, 8 words each. They live ONLY in the front-end HTML file. They are
not in the database.**

- **24 HR (hire-to-retire) themes:** Hire To Retire, Talent Hiring, Joining &
  Onboarding, Payroll & Pay, Benefits & Wellbeing, Learning & Growth, Performance,
  Time & Attendance, Employee Relations, HR Systems & Data, HR Shared Services,
  Rewards & Recognition, HR Compliance, Exit & Retire, Workforce Planning,
  Diversity & Inclusion, Employer Brand, Policy & Handbook, Succession & Talent,
  Employee Experience, Health & Safety, Mobility & Transfers, Contract & Gig Work,
  Culture & Values.
- **15 other themes:** Birla Companies, Birla Brands, Metals & Cement, Money &
  Insurance, Fibre & Fabric, The Birla Group, Inside Hindalco, Inside UltraTech,
  Fashion Labels, New Ventures, Around The World, Green & Clean, Life At Birla,
  Giving Back, Birla History.
- `CONFIG.hrShare = 0.8` picks the HR group first ~80% of the time, then a theme
  inside it. Measured at 79.8% over 200,000 picks.
- Every word must be **9 letters or fewer** (the grid is 9×9). A longer word can
  never be placed.

**Consequences for the console:**

1. The only theme data in the database is `scores.theme` — a **free-text string**
   copied from the client at submit time. There is no theme table, no theme id,
   no word list server-side.
2. Theme analytics are therefore possible (which themes get played, average score
   per theme, completion rate per theme) but only for **submitted daily games**.
   Sprint runs do **not** record a theme at all — a sprint run spans many puzzles.
3. **Editing themes or words from the admin console is not possible today.** It
   would require either moving `THEMES` into the database and having the client
   fetch it, or the console writing back into the HTML file in the game repo.
   See the questions — I want your recommendation.

---

## 5. The exact data contract

### 5.1 Tables

**`players`** — one row per registered person. Keyed by `poornata_id` (text).
Carries at least `poornata_id`, `username`, a PIN hash, and a recovery secret.
*(I do not have the original creation script in the game repo — confirm the full
column list from your side.)*

**`sessions`** — `token uuid` primary key, `poornata_id`, `expires_at`.
The token is what every RPC authenticates with.

**`scores`** — daily mode, `UNIQUE (poornata_id, play_date)`:

| column | notes |
|---|---|
| `poornata_id` | text, FK to players |
| `play_date` | date, defaults to `current_date` |
| `theme` | text, free text from the client |
| `words_found` / `words_total` | ints, clamped server-side |
| `time_sec` | int, clamped 0–300 |
| `shuffles` | int, clamped 0–5 |
| `solved` | boolean; forced false if `words_found < words_total` |
| `word_points` | `words_found × 10` |
| `time_points` | `300 − time_sec`, **only when solved**, else 0 |
| `streak_bonus` | flat 5 if a game exists in the 2 days before today, else 0 |
| `total_points` | sum of the three |
| `flagged` | boolean — see §5.4 |
| `scoring_version` | currently `4` |
| `attempts` | games played that day before submitting; `greatest(old, new)` |

**`sprint_scores`** — sprint mode, `UNIQUE (poornata_id, play_date)`:
`id`, `poornata_id`, `play_date`, `puzzles_cleared` (0–100), `words_found`
(0–500), `duration_sec` (0–600), `powerups_used` (0–2), `flagged`,
`scoring_version` (1), `attempts`, `created_at`, `updated_at`.

**`powerups`** — `PRIMARY KEY (poornata_id, play_date)`, `used` (0–2), `updated_at`.

### 5.2 Views the browser reads directly (anon has SELECT)

- `leaderboard_today`, `leaderboard_week`, `leaderboard_alltime`
- `leaderboard_sprint_today` — `rank, username, puzzles_cleared, words_found,
  duration_sec, powerups_used, flagged`, ranked by cleared desc, words desc,
  duration asc, filtered to `play_date = current_date`.

These expose **usernames and scores only — never `poornata_id`.**

### 5.3 RPCs the browser calls

| function | called with |
|---|---|
| `register_player` | `p_poornata_id, p_username, p_pin, p_recovery` |
| `login_player` | `p_username, p_pin, p_build, p_agent` |
| `resume_session` | `p_token, p_build, p_agent` |
| `end_session` | `p_token` |
| `reset_pin` | (recovery flow) |
| `ack_secret` | `p_token, p_recovery` |
| `my_history` | `p_token, p_days` (7) |
| `my_powerups` | `p_token` |
| `use_powerup` | `p_token` |
| `submit_score` | `p_token, p_theme, p_words_found, p_words_total, p_time_sec, p_shuffles, p_solved, p_attempts` |
| `submit_sprint_score` | `p_token, p_puzzles_cleared, p_words_found, p_duration_sec, p_powerups_used, p_attempts` |

`login_player` / `resume_session` return, among other things: `ok, username,
token, streak_active, played_today, needs_ack, secret, today, min_build`.

### 5.4 The `flagged` column — what it actually means

`flagged` marks a **statistically implausible** run for audit. It does not mean
proven cheating and nothing is blocked.

- Daily: `solved` and `time_sec < 20`. A human cannot find five words in a 9×9
  grid faster than about 20 seconds.
- Sprint: `puzzles_cleared > 20`, or `words_found > puzzles_cleared × 5 + 4`.

**Be honest about this in the console UI.** The grid is generated in the browser,
so the server cannot replay the puzzle and cannot prove a score is genuine. If
prizes ever ride on these boards, puzzle generation has to move server-side. Label
the column something like "Needs review", not "Cheat".

### 5.5 Security — the console must not weaken this

Applied migration `05_lock_down_sprint_tables.sql` fixed a real hole: Supabase's
default privileges had silently granted `anon` full access to `sprint_scores` and
`powerups` the moment they were created. Verified from outside with the public key:
`INSERT sprint_scores` returned **400** (a constraint error — meaning the write was
permitted) and `DELETE powerups` returned **204** (it succeeded).

The fix revoked those grants, enabled RLS on both tables, and narrowed
`ALTER DEFAULT PRIVILEGES` so the next table created does not repeat it.

**Rules for the console:**
- Never grant `anon` direct table access to add a console feature.
- The **service role key must never reach a browser**. If the console is a static
  or client-rendered app, admin reads must go through a server route, an edge
  function, or `SECURITY DEFINER` RPCs with a real admin check — not the service
  key in front-end JavaScript.
- A `400` when testing a locked table is a **hole, not a pass**. Only `401` proves
  it is locked.

---

## 6. What I want the admin console to show

Build or extend towards this. Tell me what already exists and what is missing.

### Players
- Total registered, new sign-ups per day/week, active players per day.
- Per player: username, `poornata_id`, registered date, days played, current
  streak, best daily score, best sprint run, total games (`sum(attempts)`),
  power-ups used, last seen, last build seen, device/browser.
- Returning vs one-time players. Drop-off after day 1.

### Themes
- Plays per theme, average score per theme, completion rate (`solved` share) per
  theme, average time per theme.
- **Which themes are hardest** — lowest completion rate is the useful signal.
- HR vs non-HR split actually observed, against the 80/20 target.
- Note: daily mode only; sprint records no theme.

### Games
- Daily submissions per day, sprint submissions per day, both trending.
- Score distribution; solved vs unsolved; average time to solve.
- Attempts per player per day (how many tries before they submit).
- Shuffles used. Power-ups used.
- Flagged runs, listed for review, clearly labelled as "needs review".

### Build and release
- **Build adoption:** how many players are on each build. This is the single most
  useful new panel, given §3.5. Depends on `p_build` being stored.
- A **`min_build` control** — set the minimum build, and every client at or above
  build 3 pulls itself forward at its next safe moment. This is already honoured
  by the front end; it just needs somewhere to set the value.

### Operational
- Leaderboards as the players see them, for all four views.
- The ability to correct or remove a specific score row, with an audit trail.

---

## 7. Questions — please answer these

Answer in order; I will paste your answers back to the game-side chat.

**About what exists now**
1. What does the admin console already do today? List its current screens and what
   each one reads.
2. What repo is it in, what stack, and is it server-rendered or a static
   client-side app?
3. How does it authenticate to Supabase right now — service role key, a dedicated
   admin role, RLS policies, or an API route? Where is that key stored?
4. Is there any admin user model, or is access controlled some other way?

**About data I am not sure exists**
5. Do `login_player` and `resume_session` **persist** `p_build` and `p_agent`
   anywhere, or are they accepted and discarded? If they are stored, in what
   table and column? If not, I will add it on the database side — tell me the
   shape you would want (a `last_build` / `last_agent` column on `players`, or an
   append-only `logins` table with a row per sign-in).
6. Does anything return `min_build` today, or is it always null? If there is no
   place to set it, I would like a single-row settings table plus a console
   control. Propose the shape.
7. Please paste the current definitions of `login_player` and `resume_session`
   (`\sf+ public.login_player`, or from the Supabase SQL editor). I need the exact
   bodies to add `min_build` safely — I will not guess at them.
8. Please paste the full column list of `players` and `sessions`.
9. Do `leaderboard_today`, `leaderboard_week` and `leaderboard_alltime` already
   exist as views, and what are their definitions?

**About decisions I want your recommendation on**
10. **Themes are client-side only.** Do you want them moved into the database so
    the console can edit them, with the client fetching them at load (and caching
    for offline)? That is a real change to how the game boots. Give me the
    trade-off as you see it, and what the console would need.
11. What is the least-risky way for this console to read admin data given §5.5 —
    an API route with the service key server-side, a `SECURITY DEFINER` RPC set
    with an admin check, or RLS policies against an authenticated admin role?
12. Do you want any front-end telemetry that does not exist today — for example a
    row per game *started* rather than only per game *submitted*? Right now only
    submitted scores reach the server, and `attempts` is the only trace of the
    rest. If you want more, tell me exactly which events and fields, and I will
    add them to the game and to the database.

**About operations**
13. Does the console need to write anything back (correct a score, reset a
    player's power-ups, ban or flag a player), or is it read-only today?
14. Do you have a staging Supabase project, or is the console pointed at
    production?

---

## 8. Things not to change from your side

- Do not drop `UNIQUE (poornata_id, play_date)` on either scores table. It is what
  makes "one row per player per day" true and what `ON CONFLICT` keys on.
- Do not grant `anon` table access.
- Do not alter `submit_score`, `submit_sprint_score`, `use_powerup` or
  `my_powerups` without telling me — the game depends on their exact return shapes.
- Do not delete `version.json` (lower case) from the game repo. It is the only
  thing that reaches players still running builds 1–12.
