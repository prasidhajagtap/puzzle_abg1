# The Daily Nine

A daily word-search game. Nine by nine, five words, five minutes.

**Live:** https://prasidhajagtap.github.io/puzzle_abg1/

It is one HTML file. No build step, no bundler, no dependencies to install.
Open `index.html` and it runs. Scores and accounts live in Supabase; without
that it still plays, keeping scores in the browser only.

---

## Two game modes

| | Daily challenge | 5-minute sprint |
|---|---|---|
| Clock | 5 minutes, counts down | 5 minutes, never stops |
| Goal | Find 5 words in one grid | Clear as many grids as you can |
| Scored on | 10 a word, plus every second left once all five are found, plus a +5 streak | Puzzles cleared, then words found, then the shorter run |
| Leaderboard | `leaderboard_today` / `_week` / `_alltime` | `leaderboard_sprint_today` / `_week` / `_alltime` |

Play as often as you like in either mode. **Only a score you submit counts,
and the last one you submit is your score for the day.** Submitting again
replaces the previous score rather than being rejected.

**Power-ups** reveal the first letter of every word still missing. Two a day,
counted by the server so clearing browser data does not hand out more. Free to
use; a run that used one is recorded, not penalised.

---

## The files

```
index.html    the whole game — markup, styles and script in one file
Version.json  the build number the running copy compares itself against
version.json  the same file under its lower-case name — do not delete it
manifest.json PWA manifest, so the game can be installed to a home screen
sw.js         service worker; push notifications only, deliberately no caching
sql/          database migrations, run by hand in the Supabase SQL editor
tools/        check-build.sh, which proves the build number is consistent
icon-*.png    app icons, including a maskable one for Android
```

## Deploying

GitHub Pages serves `main`, so **merging to `main` is the deploy**. There is
no separate step.

**Every deploy must bump the build number in three places, to the same value:**

1. `index.html` → `CONFIG.build`
2. `Version.json` → `"build"`
3. `version.json` → `"build"`

Then prove it:

```bash
sh tools/check-build.sh            # the working copy
sh tools/check-build.sh --live     # and what Pages is actually serving
```

If the numbers disagree, either players are told to update to a build that is
not there, or a new build ships and nobody is told about it.

## Getting everyone onto the latest build

A player can sit on a copy from weeks ago and never know. Four things move
them forward, and they are all automatic — none of them asks the player to
refresh.

**1. The version check.** The running copy fetches the build file with a
changing query string, so it can never be served from a cache. A higher
number there means a newer build exists.

**2. When it checks.** On load, on `visibilitychange` back to visible, on
`pageshow` from the back/forward cache, and on window `focus`, throttled to
once a minute. That last group matters most: a home-screen app is usually
*resumed*, not reloaded, so a check that only ran at startup could go days
without firing.

**3. How it reloads.** `location.replace(pathname + "?v=<build>")`. The query
string makes it a url the browser has never seen, so it must fetch it fresh
rather than serve the copy it is holding. It only does this at a safe moment
— never while the clock is running, and never while an unsubmitted score is
on screen. Otherwise a banner appears and the player picks the moment.

Each target build gets two silent reload attempts, counted in
`sessionStorage`. If a cache in the middle keeps returning the old file, the
game stops looping and shows the banner instead.

**4. `min_build`.** `login_player` and `resume_session` may return a
`min_build`. Anything below it is treated exactly as if a newer build
existed, so the same safe-moment rules apply. This is the lever to pull when
a build must not stay in the wild — a broken score calculation, say. Builds 3
and up honour it.

### Why `version.json` exists twice

Builds 1 to 12 shipped asking for `version.json` in **lower case**, while the
file in the repo was `Version.json` with a capital V. GitHub Pages is
case-sensitive, so every one of those checks returned 404 and the auto-update
never ran once in the game's first twelve builds — the only way anyone got a
new build was reloading by hand.

Publishing both names fixes that copy of the bug retroactively: an old client
asks for the lower-case name, now gets a real answer, sees a higher build and
reloads itself. Build 14 and later read whichever name answers first, so
renaming either file cannot strand anyone again.

**Do not delete `version.json`.** It is the only thing that reaches those old
copies.

Copies from before build 1 (26 August 2026 and earlier) contain no version
check at all and no `min_build` handling. Nothing on the server or in the
repo can reach them; those players need one manual reload, once.

## Database

Supabase. The browser holds only the public anon key and can reach **nothing
directly except the leaderboard views** — every write goes through a
`SECURITY DEFINER` function that checks the caller's session token first.

Run the scripts in `sql/` in numeric order in the Supabase SQL editor. Each
`0N_*` script has a matching verify script, and the destructive ones have a
`99_rollback_*` twin.

```
01_migrate_submit_score_override.sql   last submitted score wins for the day
02_verify.sql
03_sprint_and_powerups.sql             sprint_scores, powerups, sprint board
04_verify_sprint.sql
05_lock_down_sprint_tables.sql         REQUIRED after 03 — see below
06_verify_lockdown.sql
07_diagnose_admin_contract.sql         read-only; answers what the admin console cannot see
08_lower_flag_threshold.sql            cheat flag moved from 20 seconds to 10
09_verify_flag_threshold.sql           part A reads, part B optionally clears stale flags
10_sprint_week_and_alltime.sql         the two sprint boards that never existed
11_verify_sprint_boards.sql
12_sprint_five_minutes.sql             sprint clock 10 min -> 5 min, server side
13_verify_sprint_window.sql
14_score_tiebreak.sql                  records time_ms; changes no score
15_verify_tiebreak.sql                 statement 8 returns the view definitions 16 needs
16_tiebreak_ranking.sql                the boards start USING time_ms; changes no score
17_verify_tiebreak_ranking.sql
```

> **Ties are arithmetic, not bad luck.** For a solved game
> `total_points = 50 + (300 - time_sec) + streak`, so the score *is* the time,
> and `time_sec` is floored to whole seconds — two players finishing 0.8s apart
> record the same number and tie exactly. `14` starts recording `time_ms` as a
> tiebreak. **It changes no score**: `time_ms` is never an input to any points
> calculation, and existing rows keep null.
>
> Ranking by it is `16`, and it is views only — a view cannot change a score.
> Two rules in it are not obvious and were both arrived at the hard way:
>
> - **`time_sec` is ordered before `time_ms`, not replaced by it.** The two
>   columns are clamped independently, so a tampered client could send
>   `time_sec = 10` with `time_ms = 0`. Seconds first means the milliseconds
>   can only ever separate players *inside the same second*, which is the only
>   job they have.
> - **Rows from before `14` fall back to `time_sec * 1000 + 500`**, the middle
>   of the second. Reading a null as "finished exactly on the second" would
>   hand every old row the win over every new one in the same second, for good,
>   on the all-time board.
>
> `attempts` is deliberately *not* a tiebreak key. The result screen invites a
> player to replay and replace their score, so ranking a replay below a first
> try would punish the thing the game asks for.

> **The daily clock was 10 minutes until 21 August, then 5.** Scores from
> before that are worth more for the same play, because both eras award
> `300 points x the fraction of the clock left` and only the clock changed —
> a second used to cost half a point, now it costs a full one. A 134-second
> game on 19 August scored 283; the same game today scores 166. `scoring_version`
> was never bumped, so it reads 4 in both eras and only the arithmetic tells
> them apart: an old row satisfies `time_points = (600 - time_sec) / 2`, a new
> one `time_points = 300 - time_sec`.
>
> **Decided 9 September 2026: nothing is being changed.** The affected rows are
> a handful from the game's first week. This is written down because it looks
> exactly like a bug and is not — it is what explains a real report of a
> 26-second run scoring 342 while a later 18-second run scored 337. Both are
> correct under the rules that were running at the time.

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

39 themes, 8 words each: 24 hire-to-retire HR themes and 15 Aditya Birla
Group themes. `CONFIG.hrShare` (0.8) picks the group first and then a theme
inside it, so the split holds however many themes sit on either side. Set it
to `1` to retire the Birla themes.

**Word packs.** The daily game lets a player choose where today's words come
from: *About ABG* (15 themes), *Hire to Retire* (24 themes), or *Mixed*.
**Mixed is the default and has no pool of its own** — it falls through to the
weighted `CONFIG.hrShare` draw the game has always used, so a player who never
opens the screen gets exactly the game they had before. The choice is
remembered per device and can be changed before any game.

**Sprint ignores the pack entirely** and always uses the weighted mix, because
a sprint runs grid after grid and pinning it to one pack would repeat inside a
single run. The button that changes the pack hides itself in sprint.

Nothing else changes with the pack: same scoring, same clock, same leaderboard.

> **The packs differ slightly in word length, and it matters less than it
> sounds.** Measured over 20,000 draws: an ABG grid averages 33.0 letters, an
> HR grid 35.1 — a gap of 2.1. But the spread *within* each pack is 3.3, so
> which grid you happen to draw already varies more than which pack you chose.
> Length is also only a proxy: whether it predicts solve time needs real play
> data, and `scores.theme` records the theme but not the pack.

**Every word must be 9 letters or fewer** — the grid is `CONFIG.gridSize`
(9), and a longer word can never be placed. Grow the grid before adding one.

The game is an independent project. It carries no company marks and is not
connected to, endorsed by or associated with any organisation named inside
the puzzles.

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
  carries no extra specificity, so they only win by coming after the rules
  they override. One of them sat near the top once and silently did nothing.
- **Watch shorthand properties in those blocks.** A `padding:` shorthand there
  once reset the `padding-right` lane that keeps word chips out from under the
  power-up button, and the button started covering words again.
- **`cellEl()` indexes `#grid.children` by position**, so anything added
  inside `#grid` shifts every cell lookup. The selection trail is a sibling
  for that reason.
- **On iOS, a home-screen app has its own `localStorage`**, separate from
  Safari's. Cache Storage is shared, so the account is mirrored there and
  read back when local storage comes up empty.
- **`show()` paints the "signed in as" bar**, not the individual screens. Add
  a screen and it gets the bar for free; it hides itself on the sign-in
  screen and during a game. Screens used to set the name themselves, and
  every screen except the results page was simply missed.
- **"Sign out" carries a negative margin** so its 44px tap target does not
  stretch the bar. The row gap has to stay larger than that margin, or a long
  wrapped name puts the target over the name and a tap there signs you out.
- **The leaderboard remembers where it was opened from** (`boardFrom`), so its
  back button returns to the mode picker or to the score screen. Anything new
  that opens the board must pass that in.

## Testing

There is no test runner. Changes here were checked by driving the real game
in a headless browser: playing full games, measuring element rectangles
across 7 screen sizes from 320×568 up, walking ancestors for clipped
tooltips, and measuring rendered colour contrast rather than calculating it.

If you change the layout, the things most likely to break are the 320px-wide
control row and the short-screen word band — those two have accounted for
most of the layout bugs in this game's history.
