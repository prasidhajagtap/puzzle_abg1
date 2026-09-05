# The Daily Nine

A daily word-search game. Nine by nine, five words, five minutes.

**Live:** https://prasidhajagtap.github.io/puzzle_abg1/

It is one HTML file. No build step, no bundler, no dependencies to install.
Open `index.html` and it runs. Scores and accounts live in Supabase; without
that it still plays, keeping scores in the browser only.

---

## Two game modes

| | Daily challenge | 10-minute sprint |
|---|---|---|
| Clock | 5 minutes, counts down | 10 minutes, never stops |
| Goal | Find 5 words in one grid | Clear as many grids as you can |
| Scored on | 10 a word, plus every second left once all five are found, plus a +5 streak | Puzzles cleared, then words found, then the shorter run |
| Leaderboard | `leaderboard_today` / week / all time | `leaderboard_sprint_today` |

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
manifest.json PWA manifest, so the game can be installed to a home screen
sw.js         service worker; push notifications only, deliberately no caching
sql/          database migrations, run by hand in the Supabase SQL editor
icon-*.png    app icons, including a maskable one for Android
```

## Deploying

GitHub Pages serves `main`, so **merging to `main` is the deploy**. There is
no separate step.

**Every deploy must bump the build number in two places, to the same value:**

1. `Version.json` → `"build"`
2. `index.html` → `CONFIG.build`

The running copy fetches `Version.json` on load, on resume, and when the
window regains focus, and reloads itself when the file reports a higher
number. If the two disagree, that check misfires.

> Case matters. The file is `Version.json` with a capital V, and GitHub Pages
> is case-sensitive. A fetch of `version.json` returns 404, which is exactly
> the bug that stopped auto-update working for the game's first twelve builds.

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
```

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

## Testing

There is no test runner. Changes here were checked by driving the real game
in a headless browser: playing full games, measuring element rectangles
across 7 screen sizes from 320×568 up, walking ancestors for clipped
tooltips, and measuring rendered colour contrast rather than calculating it.

If you change the layout, the things most likely to break are the 320px-wide
control row and the short-screen word band — those two have accounted for
most of the layout bugs in this game's history.
