# Word Vibe

**Beat the clock. Catch the vibe.**

A daily word-search game for a team. Five words hidden in a nine-by-nine grid,
five minutes on the clock, and every second you save is a point.

- **Play:** https://prasidhajagtap.github.io/puzzle_abg1/
- **Admin console:** https://prasidhajagtap.github.io/streak_Admin/ ([repo](https://github.com/prasidhajagtap/streak_Admin))

The whole game is **one HTML file**: no framework, no build step, and no
third-party scripts. Open `index.html` and it runs. Scores, streaks and
leaderboards live in Supabase (Postgres); without it the game still plays and
keeps scores in the browser.

---

## At a glance

| | |
|---|---|
| **Built** | 14 August – 28 September 2026: 46 builds, 127 commits |
| **Size** | one file, about 290 KB, with 0 external scripts |
| **Words** | 86 words in 7 packs, all from word-of-the-year and most-looked-up lists, 2020–2025 |
| **Modes** | Daily challenge (Trending words, or a custom Theme) and a 5-minute Sprint |
| **Boards** | 6 leaderboards: 2 modes × today, this week and all time |
| **Backend** | Supabase: 33 numbered migrations, each with a verify script, and rollbacks for the risky ones |
| **Access** | every colour pair measured against WCAG AA, 44px tap targets, reduced motion respected |
| **Installs** | as a home-screen app (PWA), and updates itself |

---

## How to play

1. **Find five words** hidden in a 9×9 grid. Drag from the first letter to the last.
2. Words run **across, down and diagonally**, and one is always **backwards**.
3. Each word is **10 points**. Find all five and **every second left on the clock is 1 more point**, so speed matters.
4. Play on consecutive days for a **streak**, worth **+5** a game.
5. Stuck? The 💡 button **reveals the first letter** of every word still missing. You get **2 a day**, counted by the server, and **3 shuffles** per game.

Play as often as you like. **Only a score you submit counts, and the last one
you submit is your score for the day.**

## Two modes

| | Daily challenge | 5-minute sprint |
|---|---|---|
| **Words from** | Trending words, or a custom Theme when one is live | Trending words |
| **Clock** | 5 minutes, counts down | 5 minutes that never stop |
| **Goal** | Find 5 words in one grid | Clear as many grids as you can |
| **Scored on** | 10 a word + every second left + a +5 streak bonus | Puzzles cleared; ties go to the best run, then words found |
| **Leaderboards** | today · this week · all time | today · this week · all time |

## Features

- **Streaks** that count consecutive days, shown on the menu with who else played today.
- **Personal bests** on every mode card, and a before/after view when you
  replace your score for the day.
- **Share your score** as plain text, a different message for each mode.
- **Scoring explained where it happens.** A small `?` beside every score opens
  the rules for the mode you just played.
- **"What's new" cards** the first time a returning player opens a new build.
- **Updates itself.** A player on an old copy is moved to the latest build at
  a safe moment, never in the middle of a game. See *Getting everyone onto the
  latest build* below.
- **Custom themes.** An admin uploads a spreadsheet and switches it on, and
  every player gets a Themes tab. See the next section.

---

## Custom themes: from a spreadsheet to every player

The newest feature, and the one that touches every part of the system.

1. **Upload.** In the admin console's *Custom themes* tab, the admin uploads a
   spreadsheet (`.xlsx`, `.csv` or `.tsv`) with two columns: a **word**, and a
   one-line **fact** that players see when they find it.
2. **Check before saving.** The console reads the file in the browser and shows:
   - how many words are usable (out of 50)
   - how many different puzzles those words can make
   - every word and fact exactly as it will be stored
   - every skipped row, with the reason ("longer than 9 letters", "only A–Z", "already used on line 3")
3. **Save, then Activate.** Activating makes it live for every player straight
   away, with no reload needed on their side.
4. **Play.** The game's locked *Themes* card turns lime. Players pick a theme
   and play the daily challenge on its words, scored and ranked like any daily
   game.

**The limits are measured, not guessed.** Every one was tested against the
game's own puzzle builder:

| rule | why |
|---|---|
| **5 words minimum** | with 4, the builder fails every time |
| **12 or more recommended** | 12 words give 792 different puzzles; 5 give exactly one |
| **50 maximum** | 50 was measured to lay out cleanly |
| **3–9 letters, A–Z only** | the grid is 9×9, and a longer word can never be placed |
| **facts up to 160 characters** | a longer fact overflows its card |

**Nothing is trusted on the way through.**
- The database repeats every one of these checks itself.
- The game checks each theme again when it arrives.
- The spreadsheet reader uses no library, because the console holds the
  project key. It refuses files over 2 MB and stops any workbook that expands
  past 16 MB, so a 25 KB "zip bomb" is rejected rather than freezing the tab.
- Script injected into a fact is shown as plain text everywhere.

---

## Design

- **Palette** taken from a reference image by sampling its pixels: a near-black
  ground, a brand purple, a lime accent, and yellow, blue, red and pink.
  **The purple is only ever a fill, never text.** As text on the dark ground it
  measures 2.68:1, far below the 4.5:1 readable minimum.
- **Font:** *Caveat Brush* by Impallari Type, under the SIL Open Font License.
  It is hosted with the game in `fonts/caveat-brush/`, with its licence beside
  it. It is scaled 115.6% by `size-adjust` so its capitals match the height of
  the previous face, which means the switch moved nothing on screen. The grid
  letters stay in a monospace face on purpose, so O and Q, and I and L, can't
  be mistaken for each other.
- **The board** has two dark chequered tones. A word being traced is purple, a
  found word is lime with a dark letter, so the change also shows without colour.
- **Accessibility:**
  - Every text and background pair meets WCAG AA. `tools/css_contrast_audit.py`
    checks all ~500 CSS rules, including gradients and states that are hidden
    at rest.
  - Every control has at least a 44×44 tap area.
  - Motion respects the phone's "reduce motion" setting.

---

## Things we learned building it

These are short versions. The full detail is further down.

- **A capital letter broke auto-update for twelve builds.** The game asked for
  `version.json`; the file was `Version.json`. GitHub Pages is case-sensitive,
  so every check failed quietly. Both names are published now, so even the
  oldest copies update themselves.
- **Revoking access from "PUBLIC" is not enough on Supabase.** It grants
  `anon` and `authenticated` separately, so a function locked that way still
  answered the public key. Every lockdown here names all three roles, and a
  verify script checks it.
- **`CREATE OR REPLACE` with new arguments makes a *second* function.** It
  happened twice: once in `submit_score` and once in `login_player`.
  PostgREST then couldn't choose between the two and returned HTTP 300.
- **A colour token changing meaning turned a tooltip white on white.** The
  live contrast scanner never saw it, because a hidden tooltip is invisible to
  it. That is why the static audit now reads every CSS rule, whether it is on
  screen or not.
- **Testing against the real SQL found three bugs in the uploader** before any
  player did. The worst: after the *first* upload, Activate did nothing, because
  the table it listened on was replaced when the list was empty.
- **The streak rule took four tries.** The final rule is the simplest: a day is
  a day, and missing any day ends the streak.
- **A font's licence matters before its looks.** The first font chosen was free
  for personal use only and forbade uploading it to the internet, which a
  website has to do. Caveat Brush is under the Open Font License.

---

## The files

```
index.html    the whole game: markup, styles and script in one file
Version.json  the build number the running copy compares itself against
version.json  the same file under its lower-case name. Do not delete it.
manifest.json PWA manifest, so the game can be installed to a home screen
sw.js         service worker, deliberately no caching. It can show a push message,
              but nothing subscribes players or sends one yet
fonts/        Caveat Brush (woff2) and its licence, OFL.txt
sql/          database migrations, run by hand in the Supabase SQL editor
tools/        check-build.sh, css_contrast_audit.py, palette_audit.py
icon-*.png    app icons, including a maskable one for Android
```

## Deploying

GitHub Pages serves `main`, so **merging to `main` is the deploy**. There is
no separate step.

**Every deploy bumps the build number in three places, to the same value:**

1. `index.html` → `CONFIG.build`
2. `Version.json` → `"build"`
3. `version.json` → `"build"`

Then check it:

```bash
sh tools/check-build.sh            # the working copy
sh tools/check-build.sh --live     # and what Pages is actually serving
```

If the numbers disagree, either players are told to update to a build that
isn't there, or a new build ships and nobody is told about it.

## Getting everyone onto the latest build

A player can sit on a copy from weeks ago and never know. Four things move
them forward, and all of them are automatic. None asks the player to refresh.

**1. The version check.** The running copy fetches the build file with a
changing query string, so it is never served from a cache. A higher number
there means a newer build exists.

**2. When it checks.** On load, on `visibilitychange` back to visible, on
`pageshow` from the back/forward cache, and on window `focus`, at most once a
minute. That last group matters most: a home-screen app is usually *resumed*,
not reloaded, so a check that only ran at startup could go days without firing.

**3. How it reloads.** `location.replace(pathname + "?v=<build>")`. The query
string makes it a URL the browser has never seen, so it must fetch a fresh
copy. It only does this at a safe moment: never while the clock is running,
and never while an unsubmitted score is on screen. Otherwise a banner appears
and the player picks the moment.

Each target build gets two silent reload attempts, counted in
`sessionStorage`. If a cache in the middle keeps returning the old file, the
game stops looping and shows the banner instead.

**4. `min_build`.** `login_player` and `resume_session` may return a
`min_build`. Anything below it is treated exactly as if a newer build existed,
so the same safe-moment rules apply. This is the lever to pull when a build
must not stay in the wild. The admin console's Settings tab sets it.

### Why `version.json` exists twice

Builds 1 to 12 asked for `version.json` in **lower case**, while the file in
the repo was `Version.json` with a capital V. GitHub Pages is case-sensitive,
so every one of those checks returned 404, and auto-update never ran once in
the game's first twelve builds.

Publishing both names fixes those old copies after the fact: an old client asks
for the lower-case name, now gets a real answer, sees a higher build and
reloads itself. Build 14 and later read whichever name answers first, so
renaming either file cannot strand anyone again.

**Do not delete `version.json`.** It is the only thing that reaches those old
copies.

## Database

Supabase. The browser holds only the public anon key. It can reach **nothing
directly except the leaderboard views**: every write goes through a
`SECURITY DEFINER` function that checks the caller's session token first.

Run the scripts in `sql/` in numeric order in the Supabase SQL editor. Each
change has a matching verify script, and the risky ones have a
`99_rollback_*` twin. **The SQL editor shows only the last result in a file**,
so the newer verify scripts end with a single checklist table.

```
01_migrate_submit_score_override.sql   last submitted score wins for the day
02_verify.sql
03_sprint_and_powerups.sql             sprint_scores, powerups, sprint board
04_verify_sprint.sql
05_lock_down_sprint_tables.sql         REQUIRED after 03, see below
06_verify_lockdown.sql
07_diagnose_admin_contract.sql         read-only; answers what the admin console cannot see
08_lower_flag_threshold.sql            cheat flag moved from 20 seconds to 10
09_verify_flag_threshold.sql
10_sprint_week_and_alltime.sql         the two sprint boards that never existed
11_verify_sprint_boards.sql
12_sprint_five_minutes.sql             sprint clock 10 min -> 5 min, server side
13_verify_sprint_window.sql
14_score_tiebreak.sql                  records time_ms; changes no score
15_verify_tiebreak.sql
16_tiebreak_ranking.sql                the boards start USING time_ms; changes no score
17_verify_tiebreak_ranking.sql
18_player_stats.sql                    my_stats: streak, bests, who played today
19_verify_player_stats.sql
20_sprint_tiebreak.sql                 sprint ties decided on the best run
21_verify_sprint_tiebreak.sql
22_sprint_one_clock.sql                sprint boards stop mixing 10- and 5-minute runs
23_verify_sprint_one_clock.sql
24_streak_every_day_counts.sql         streak = consecutive calendar days
25_verify_streak_every_day.sql
26_fix_resume_session_overload.sql     removes a duplicate that broke old clients
27_verify_resume_session.sql
30_fix_submit_score_overload.sql       the same fault, in submit_score
31_verify_submit_score_overload.sql    includes a whole-schema sweep for duplicates
32_fix_login_player_overload.sql       ...which found it once more, in login_player
33_verify_login_player_overload.sql
```

The admin console's own scripts (`A01`–`A08`: word packs, its panels, custom
themes) live in [its repo](https://github.com/prasidhajagtap/streak_Admin/tree/main/sql).

> **`resume_session` was overloaded, and PostgREST could not choose.** Two
> functions shared the name — `(p_token)` and `(p_token, p_build, p_agent)` —
> and a call carrying only `p_token` matched both, so it answered
> `HTTP 300 PGRST203`. The client sends all three arguments since 28 August, so
> the current build was never affected; anything older sent one, got the 300,
> and `rpc()` threw, which the caller catches as "offline". Such a player kept
> a stale session — no streak refresh, no played-today state, and
> `honourMinBuild()` never ran, which is the lever for forcing an update.
>
> **The fix needed no function body**, which is worth knowing. PostgREST only
> offered the three-argument version as a candidate for a one-argument call,
> and it could only do that if `p_build` and `p_agent` already carried
> defaults. So the three-argument version could already serve every call the
> one-argument version served, and since every `p_token`-only call was
> ambiguous, the one-argument version was **unreachable through the API** —
> dead weight that broke its own sibling. `26` drops it; the survivor keeps its
> exact body and a one-argument call now resolves to it with nulls.
>
> Do not run `99_rollback_resume_overload.sql` to "restore" anything: putting
> the overload back restores the fault.

> **The sprint boards were ranking two different games against each other.**
> Until `12` the sprint ran ten minutes; it now runs five, and both kinds of run
> sat on the same boards ranked by puzzles cleared — so an old run carried
> roughly twice the advantage for the same skill. `22` adds one line,
> `where s.duration_sec <= 300`, to the week and all-time views.
>
> **Nothing is deleted.** Every run stays in `sprint_scores` with its real
> numbers; two boards simply stop showing the long ones. Remove the line and
> they are all back.
>
> **Filtered on `duration_sec`, not `scoring_version`.** They differ in the case
> that matters: someone who quit a ten-minute sprint after four minutes is
> version 1, but four minutes *is* comparable to five, so they keep their place.
> Version would throw them out for a clock they never used.
>
> **Not ranked by rate.** Puzzles per minute looks like the fair comparison and
> is not — the client sends `Math.min(elapsed, modeBudget())`, so a run can
> legitimately end early and a player who cleared one puzzle in twenty seconds
> would rate at three a minute and top the board. Rate is only safe on a fixed
> denominator, which is what the filter restores.
>
> **No front-end change.** Only rows are filtered; both column lists are
> identical, so the game reads these boards exactly as before. `22` PART A is
> read-only and shows exactly who drops off before PART B changes anything.

> **The sprint week and all-time boards used to decide a tie on words found.**
> That number is roughly five times puzzles cleared, so between two players on
> the same total it is nearly noise — and it was asked *before* the best single
> run. Live example: prasidha (18 cleared over **3** runs, best **8**) outranked
> Jitu (18 cleared in **1** run, best **18**) by one word. `20` swaps the second
> and third keys so the best run decides. Totals still come first, so `10`'s
> decision stands: sprinting every day still beats sprinting once.
>
> `leaderboard_sprint_today` is deliberately untouched — one row per player per
> day means there is no best run to rank on, and there `words_found` above five
> per cleared puzzle is real progress on the grid the clock ran out on.
>
> **Tied rows are stabilised in the client, not the view.** The sprint boards
> use `rank()`, so a genuine tie shares a place — correct — but leaves two rows
> on the same number with nothing saying which draws first. An `ORDER BY` in the
> view cannot fix it: PostgREST applies its own over the top. Build 24 asks for
> `order=rank.asc,username.asc`, which stabilises all six boards.

> **`my_stats` is optional.** It feeds the streak strip on the mode screen and
> the personal-best lines. The client treats a missing `my_stats` as "nothing
> to show" and hides the strip, so build 23 runs correctly against a database
> that has not had `18` applied — the screen simply looks like build 22. Same
> rule as the millisecond tiebreak: a new screen must never break an old
> database.
>
> **`streak_days` counts consecutive CALENDAR days. A day is a day.** Every
> day played adds one; missing any day — weekend included — ends the run. There
> is no weekend rule, no grace day and no holiday handling.
>
> It took four attempts to land there, and the history is the argument:
>
> | | rule | why it moved on |
> |---|---|---|
> | v1 | strict calendar days | correct, but the most engaged player showed **2** |
> | v2 | working days only | fixed that, but 11 of 74 games were played at weekends and earned nothing |
> | v3 | every day counts, only a missed weekday breaks | built, never shipped |
> | **v4** | **strict calendar days** | requested directly: *"day is day, do not stop on weekend"* |
>
> **This is the harshest of the four and that is the point.** The number is
> small and it is unambiguous. A player who takes a Sunday off starts again at
> 1 on Monday.
>
> **It is deliberately stricter than the +5 bonus.** `submit_score` pays +5 when
> the previous 48 hours contain a game, so a player can skip a day, still be
> paid, and still lose the fire. The bonus is generous because it is points;
> the streak is strict because it is a streak. Nothing about `my_stats` feeds
> any score.
>
> **Weekend play was never restricted.** Games at the weekend have always
> earned points and always appeared on every board — `getDay()` appears zero
> times in the client and no board filters by weekday. The only day-of-week
> logic the system ever had lived inside `dn_streak`, and `24` removes even
> that.
>
> `dn_streak` takes the date as an argument rather than reading the clock, so
> all seven days can be tested. `dn_workday_no` is dropped — no rule needs
> Friday and Monday to be adjacent any more.
>
> **Revoking `EXECUTE` from `PUBLIC` is not enough on Supabase.** It separately
> grants EXECUTE to `anon` and `authenticated` for anything created in this
> schema, so removing PUBLIC's grant leaves those standing. An earlier version
> of `18` was caught by exactly that — a revoked function answering a request
> made with the public anon key. All three roles, every time, and `25`
> statement 3 checks it with `has_function_privilege`. A `REVOKE` running
> without error proves nothing.

> **The leaderboard is two modes crossed with three periods**, so it needs six
> views. Daily always had three; sprint only ever had `leaderboard_sprint_today`,
> which is what `10` fixes. If a view is missing the game says so on the board
> rather than showing an empty list — a missing board and a quiet one are not
> the same thing.

> **Sprint runs from before `12` were played on a ten-minute clock.** They carry
> `scoring_version = 1`; five-minute runs carry `2`. The sprint week and
> all-time boards therefore mix the two formats, and the older runs have a real
> advantage. **They were kept on purpose** (8 Sep 2026): nobody had been told
> the sprint was ten minutes, so no player is comparing against a promised
> number, and deleting real scores to tidy a board is a poor trade. The week
> board clears every Monday; all-time keeps the mix, but both boards sum across
> runs, so two five-minute runs already match one ten-minute run.

> **The cheat flag is not proof.** `scores.flagged` marks a run as
> statistically implausible so a human can look at it — it has never blocked
> anything. The line sat at 20 seconds until real players turned out to solve
> in 13 to 18, which meant the best players were being flagged for being good.
> `08` moves it to 10. The grid is generated in the browser, so the server
> cannot replay the puzzle and cannot prove a score either way; if prizes ever
> ride on these boards, generate the puzzle server-side and verify the answer.
> No threshold substitutes for that.

> **Run `05` immediately after `03`.** Supabase's default privileges grant
> `anon` full access to any new table in the `public` schema, so creating
> `sprint_scores` and `powerups` opened both to the public key until `05`
> revoked it, enabled RLS and narrowed the default privileges. `06` asserts
> `anon` has no `SELECT`, `INSERT` or `DELETE` on either table.

To confirm the lockdown from outside, with the anon key from `index.html`:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  "$SUPABASE_URL/rest/v1/sprint_scores?select=*&limit=1"     # expect 401
```

A `400` there would mean the request reached the table and failed on a
constraint — that is a permissions hole, not a pass.

## Puzzle content

**86 words in 7 packs**, every one taken from a word-of-the-year or
most-looked-up list published between 2020 and 2025 by Merriam-Webster, Oxford,
Collins, Cambridge, Dictionary.com, Macquarie or the American Dialect Society.
Each word carries a one-line fact that players see when they find it.

| pack | years | a few of its words |
|---|---|---|
| The Virus Years | 2020–22 | pandemic · lockdown · covid · boosted |
| Jabs and Jargon | 2020–21 | vax · woke · allyship · nomad |
| Words That Spiked | 2022 | oligarch · omicron · sentient · redact |
| Looked Up in 2022 | 2022 | caulk · bayou · knoll · goblin |
| The AI Turn | 2023–25 | authentic · rizz · deepfake · dystopian |
| Very Online | 2021–24 | brainrot · brat · demure · romantasy |
| Newest Words | 2024–25 | slop · tariff · conclave · cognitive |

- **Every word is 3–9 letters.** The grid is `CONFIG.gridSize` (9), and a
  longer word can never be placed. Some famous words were left out for that
  reason alone: *gaslighting*, *permacrisis*, *hallucinate*. That is why the
  list is 86 and not a round 100.
- **Daily and Sprint draw from one pool.** A Sprint runs grid after grid, and
  pinning it to one pack would repeat inside a single run.
- **Custom themes** add to this, but only for the daily challenge, and only
  while one is switched on. See *Custom themes* above.

The game is an independent project. It carries no company marks and is not
connected to, endorsed by or associated with any organisation.

## Working on it

There is nothing to install. Serve the folder and open it:

```bash
python3 -m http.server 8899     # then http://127.0.0.1:8899/
```

To play without touching the live database, blank `SUPA.url` in `index.html`.
The game falls back to browser-only scores and says so on screen.

Things worth knowing before you edit:

- **Two CSS override blocks must stay last in the stylesheet**
  (`@media (max-width:400px)` and `@media (max-height:700px)`). A media query
  adds no specificity, so they only win by coming after the rules they override.
- **`cellEl()` indexes `#grid.children` by position**, so anything added
  inside `#grid` shifts every cell lookup.
- **On iOS, a home-screen app has its own `localStorage`**, separate from
  Safari's. Cache Storage is shared, so the account is mirrored there and read
  back when local storage comes up empty.
- **Never rename a `dailynine.*` storage key.** They hold every player's
  account, streak and history on their own device; renaming one signs
  everybody out. Add a new key instead.
- **`show()` paints the "signed in as" box**, not the individual screens, so a
  new screen gets it for free.
- **The Sign-out tap area is an invisible pad (`::after`)**, not padding. It
  reaches exactly as far up as the gap above it, so a tap on the name can
  never sign you out.
- **The clock's width is measured once, from the font that actually loaded.**
  The brush face has no fixed-width digits, and without it the Found counter
  next to the clock would shift every second.
- **`--ink` is the light text colour.** It used to be the dark one. Never use
  it as a fill: that is how the white-on-white tooltip happened.

## Testing

There is no test runner in the repo. Changes were checked by driving the real
game in a headless browser: playing full games, measuring layout at seven
screen sizes from 320×568 up, checking every button's text is centred from its
pixels, and measuring rendered colour contrast rather than calculating it. The
custom-themes feature was tested end to end against its real SQL, on a local
Postgres set up like Supabase.

Run these before every deploy:

```bash
sh tools/check-build.sh                      # the build number agrees everywhere
python3 tools/css_contrast_audit.py index.html   # every CSS colour pair passes WCAG AA
python3 tools/palette_audit.py index.html        # every colour is in the palette
```

## Credits

Designed and developed by **Prasidha Jagtap**.

Font: [Caveat Brush](https://fonts.google.com/specimen/Caveat+Brush) by
Impallari Type, SIL Open Font License 1.1. Archivo and Roboto Mono are served
by Google Fonts.
