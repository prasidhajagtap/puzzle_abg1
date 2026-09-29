# Word Vibe — notes for Claude

Read this first. It is the memory of how this project works and what has been
done, so a new session does not have to rediscover it. Last updated 29 Sep 2026.

## The project

- **Game:** this repo, `prasidhajagtap/word_vibe`. One file, `index.html`
  (~290 KB, no framework, no build step). Live at
  https://prasidhajagtap.github.io/word_vibe/ — **merging to `main` is the deploy**
  (GitHub Pages, live in about a minute).
- **Renamed 28 Sep 2026** from `puzzle_abg1`. GitHub Pages does not redirect,
  so `…/puzzle_abg1/` is a 404. The owner chose to send players the new link
  rather than publish a redirect repo.
- **Admin console:** `prasidhajagtap/streak_Admin`. The Pages URL has a
  **capital A**: https://prasidhajagtap.github.io/streak_Admin/ . The owner
  keeps that link to themselves. It has its own `CLAUDE.md`.
- **Database:** one shared Supabase project, **free plan** (500 MB, 5 GB
  egress/month). Game scripts are `sql/NN_*.sql` here; admin scripts are
  `sql/ANN_*.sql` in streak_Admin.
- **Audience:** opened to the general public on 29 Sep 2026. Mostly Indian
  players. No prizes.

## How the owner wants to work

- Simple words, short sentences. No hard English.
- Check facts online when accuracy matters; do not guess.
- Disagree politely when something is wrong. Offer options, give a pick.
- Ask when the request is unclear.
- **Never merge until the owner says "merge".** Push to a branch, show what
  changed, ask. Merges are squash merges through a PR.
- Do not open a PR unless asked (the "merge" instruction counts as asking).

## Hard rules

- The Supabase **service-role / secret key must never reach a browser.** Only
  the public anon key is in `index.html`.
- **Never grant `anon` direct table access** to add a feature. Use a view or a
  `SECURITY DEFINER` function with `set search_path`.
- Testing a locked table: **only HTTP 401 proves it is locked.** A 400 means a
  permissions hole.
- Revoking `EXECUTE` from `PUBLIC` is not enough on Supabase: revoke from
  `public, anon, authenticated`.
- **Never rename the `dailynine.*` localStorage keys** — it logs everyone out.
- **Never commit the Blaze Brush font** (its licence forbids web use). The
  game uses Caveat Brush (SIL OFL), self-hosted in `fonts/caveat-brush/`.
- No model names in commits, PRs or code.
- Never disable TLS checks or unset `HTTPS_PROXY`.

## Things that are easy to get wrong

- **The Supabase SQL editor shows only the LAST result of a file.** So every
  new script ends in one checklist table (`check_name, expected, actual, ok`).
  Rows marked `(info)` leave `ok` blank.
- Scripts that replace views run in **one transaction with a guard** that
  compares the live columns first and stops, changing nothing, on a mismatch
  (see `35_fair_boards.sql`). Each risky script has a `99_rollback_*` twin.
- `CREATE OR REPLACE` with new arguments makes a **second** function and
  PostgREST then answers HTTP 300. Check for duplicates (launch check row 9).
- **Build number** lives in three places: `CONFIG.build` in `index.html`,
  `Version.json` and `version.json` (both needed; builds 1–12 ask for the
  lower-case one). `tools/check-build.sh` checks they agree (`--live` checks
  the site). **Bumping the build shows the What's new cards to returning
  players**, so only bump when there are new cards for them; otherwise players
  get the new file anyway on their next visit (Pages caches for 10 minutes, the
  service worker caches nothing).
- The bodies of `login_player`, `register_player`, `reset_pin` and most
  `admin_*` functions came from an early setup script that is **not in either
  repo**. Read them live with `select pg_get_functiondef('public.x'::regproc);`
  (the owner runs it and pastes the result) before changing them.
- Leaderboard views are read with `&limit=100` by the game. The views
  themselves have no row limit so server functions can rank past 100.

## Current state (29 Sep 2026)

- **Build 46** live. All game scripts `01`–`35` run; admin `A01`–`A09` run.
- `34_launch_check.sql` passed every row. RLS on every table, no table open to
  the public key, sign-in and PIN reset lock after wrong tries, database 12 MB.
  Counts then: 15 players, 117 scores, 31 sprint runs.
- **Open decision:** `register_player` has **no rate limit** (a bot could
  create many accounts). Owner has not chosen yet. Option offered: a trigger
  refusing sign-ups above ~20 a minute (cost: a rush of real sign-ups could
  see an error).

## Done in the last sessions (newest first)

- **Fair boards for public launch** (#40, streak_Admin #14):
  `35_fair_boards.sql` — name check trigger on `players` (word list in table
  `blocked_name_words`, `how` = `part` or `word`; checked against 270 common
  Indian names, none blocked — watch for names like Poornima, Boobalan,
  Gandule, Ashita, Nazia when adding words), `players.hidden`, every board
  drops flagged results and hidden players, no 100-row cap inside views,
  `play_date` indexes. `name_allowed()` lets the game explain a refusal.
  Admin Players tab: "Hide a player" card (A09).
- **Launch check** `34_launch_check.sql` (read-only).
- **Share link** points to the new address (#39); verified live for daily and
  sprint share text.
- **READMEs** rewritten for both repos (#38); old handover docs and ABG
  references removed. ABG/Birla names remain only inside admin SQL retired
  lists, on purpose (old scores still carry those theme names), and in git
  history.
- **Custom themes** (build 46): admin uploads a spreadsheet, switches it on,
  the game's Themes tab unlocks. Result screen button spacing fixed.
- **Header and font**: Caveat Brush with `size-adjust:115.6%` (family name
  `'WV Caveat Brush'` so a local copy is never used); tighter header with a
  tile strip.
- A LinkedIn feature image (bento layout, light and dark) was made; not in
  the repo.

## Known small items, not started

- First-load long task is borderline (~200 ms at 4× CPU throttle).
- Long usernames end in "…" in the header.
- Some blank space under the word chooser.
- The word list is 86 words, not 100.
- `manifest.json` still has old colours (`#F4EDE0`, `#0F7C8A`) from the light
  theme; the game is now dark.

## Testing approach

Tests ran from a scratch folder that does not survive the session, so rebuild
as needed:
- Playwright with the pre-installed Chromium
  (`/opt/pw-browsers/...`, never `playwright install`), serving this folder
  over a tiny local HTTP server.
- A local Postgres 16 that mimics Supabase (roles `anon`, `authenticated`,
  RLS on, grants revoked), plus a small bridge that answers the page's
  `/rest/v1/rpc/*` and view reads from that database as `anon`.
- `tools/css_contrast_audit.py index.html` and `tools/palette_audit.py`;
  `tools/check-build.sh`.
- Check phone width (390 px, 320 px): no sideways scroll, tap targets ≥ 44 px.
