-- ============================================================================
-- The Daily Nine — the sprint week and all-time boards stop deciding ties on
-- a stray word, and decide them on the best run instead.
--
-- WHAT WAS WRONG. Both views ranked on:
--     sum(puzzles_cleared) desc, sum(words_found) desc, max(puzzles_cleared) desc
--
-- words_found is about five times puzzles_cleared plus whatever was found on
-- the grid that ran out of time, so between two players on the same total it
-- is very nearly noise — and it was being asked FIRST, before the number that
-- actually says something.
--
-- Read off the live all-time board on 9 September 2026:
--
--     #2  prasidha   18 cleared   3 runs   best run  8   93 words
--     #3  Jitu       18 cleared   1 run    best run 18   92 words
--
-- Jitu cleared eighteen puzzles in a single five-minute sprint. prasidha
-- needed three sittings to reach the same total. prasidha was ranked higher,
-- and the entire margin was one word.
--
-- WHAT CHANGES. The second and third keys swap:
--     sum(puzzles_cleared) desc, max(puzzles_cleared) desc, sum(words_found) desc
--
-- Totals still come first, so the decision made in 10_sprint_week_and_alltime
-- stands: a player who sprints every day still out-ranks one who sprinted
-- once. Only the tie is settled differently, and it is now settled on the best
-- run rather than on a rounding error. words_found stays as the third key
-- because it does carry something real — the words found on the puzzle the
-- clock ran out on — it just should not outrank a whole extra run.
--
-- WHO MOVES. Jitu and prasidha swap places on the all-time board. That is the
-- point of the change, not a side effect. Nobody else moves and no score is
-- touched.
--
-- WHAT DOES NOT CHANGE, deliberately:
--
--   leaderboard_sprint_today is left exactly as it is. It holds one row per
--   player per day, so there is no "best run" to rank on, and there words_found
--   IS the meaningful tiebreak: above five per cleared puzzle it is progress
--   on the grid the clock ran out on. Its last key, duration_sec, is dead —
--   the sprint runs a fixed clock and nobody stops early, so every row reads
--   300 — but a dead key at the end of the list costs nothing and removing it
--   would be churn.
--
--   rank() is kept, so a genuine tie still SHARES a place rather than being
--   split arbitrarily. Which of two tied rows is drawn first is a display
--   question, and it is fixed in the browser rather than here: the client asks
--   PostgREST for order=rank.asc, and PostgREST applies its own ORDER BY over
--   the view, so an ORDER BY written into a view does not survive to decide
--   it. Build 24 asks for order=rank.asc,username.asc instead.
--
--   The ten-minute runs from before 12_sprint_five_minutes are still on these
--   boards, mixed in with five-minute ones. That is a separate and larger
--   question, still open, and this file does not pretend to answer it.
--
-- ADDITIVE TO NOTHING ELSE. Two views are replaced. No table, no function, no
-- score. The column lists are unchanged, so the game reads them as before.
--
-- Safe to re-run. Rollback: 99_rollback_sprint_tiebreak.sql
-- Verify: 21_verify_sprint_tiebreak.sql
-- ============================================================================


-- ---------------------------------------------------------------- week ---

create or replace view public.leaderboard_sprint_week as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        max(s.puzzles_cleared) desc,   -- the best single run
                        sum(s.words_found)     desc)      as rank,
  p.username,
  sum(s.puzzles_cleared)::int                             as puzzles_cleared,
  sum(s.words_found)::int                                 as words_found,
  count(*)::int                                           as runs,
  max(s.puzzles_cleared)                                  as best_run,
  bool_or(s.flagged)                                      as flagged
from public.sprint_scores s
join public.players p using (poornata_id)
-- WINDOW: copied from leaderboard_week. Calendar week, starting Monday.
where s.play_date >= date_trunc('week', current_date)::date
group by p.username
order by 1
limit 100;


-- ------------------------------------------------------------- all time ---

create or replace view public.leaderboard_sprint_alltime as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        max(s.puzzles_cleared) desc,   -- the best single run
                        sum(s.words_found)     desc)      as rank,
  p.username,
  sum(s.puzzles_cleared)::int                             as puzzles_cleared,
  sum(s.words_found)::int                                 as words_found,
  count(*)::int                                           as runs,
  max(s.puzzles_cleared)                                  as best_run,
  max(s.play_date)                                        as last_played,
  bool_or(s.flagged)                                      as flagged
from public.sprint_scores s
join public.players p using (poornata_id)
group by p.username
order by 1
limit 100;


-- ---------------------------------------------------------------- grants ---
-- create or replace keeps existing grants; these are belt and braces so that
-- re-running after someone has dropped a view by hand still leaves the
-- browser able to read the boards. They expose usernames and scores only,
-- never a poornata_id.
grant select on public.leaderboard_sprint_week    to anon;
grant select on public.leaderboard_sprint_alltime to anon;
