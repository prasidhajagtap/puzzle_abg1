-- ============================================================================
-- The Daily Nine — sprint boards for "this week" and "all time"
--
-- WHY: the leaderboard is being split into two modes, each with the same three
-- slices. Daily already has all three views. Sprint only ever had
-- leaderboard_sprint_today, so two of the six tabs had nothing behind them.
-- Verified against the live API before writing this:
--     leaderboard_sprint_week     -> 404 PGRST205
--     leaderboard_sprint_alltime  -> 404 PGRST205
--
-- ADDITIVE ONLY. Nothing that exists is altered. No table is touched, no
-- function is replaced, and leaderboard_sprint_today is left exactly as it is.
-- Rollback: 99_rollback_sprint_boards.sql removes only these two views.
--
-- SHAPE: mirrors the daily boards so the two modes read the same way.
--   daily week    -> total_points, games_played, games_solved, best_time
--   sprint week   -> puzzles_cleared, words_found, runs, best_run
-- Daily sums its points across the period, so sprint sums its cleared puzzles.
-- A player who sprints every day should out-rank one who sprinted once.
--
-- THE WINDOW — settled, not guessed.
-- The first draft of this file used a rolling 7 days and flagged that it might
-- not match daily. It did not. leaderboard_week was read out of the database
-- and uses a CALENDAR week:
--     where s.play_date >= date_trunc('week', current_date)::date
-- which in Postgres starts on a Monday. A rolling 7 days would have counted
-- last Thursday and Friday as "this week" on a Tuesday, so the two boards
-- would have disagreed about what a week is for most of every week.
-- The window below is now copied from the daily view verbatim.
--
-- ONE DIFFERENCE LEFT ON PURPOSE: daily ranks with row_number(), so two players
-- on identical scores get different ranks in an arbitrary order. These views
-- use rank(), matching leaderboard_sprint_today, so a genuine tie shares a
-- place. That is the better behaviour and it keeps the three sprint boards
-- consistent with each other. Say the word if you would rather all six matched
-- daily instead — it is one word in each view.
--
-- Safe to re-run.
-- ============================================================================


-- ---------------------------------------------------------------- week ---

create or replace view public.leaderboard_sprint_week as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        sum(s.words_found)     desc,
                        max(s.puzzles_cleared) desc)      as rank,
  p.username,
  sum(s.puzzles_cleared)::int                             as puzzles_cleared,
  sum(s.words_found)::int                                 as words_found,
  count(*)::int                                           as runs,
  max(s.puzzles_cleared)::int                             as best_run,
  bool_or(s.flagged)                                      as flagged
from public.sprint_scores s
join public.players p using (poornata_id)
-- WINDOW: copied from leaderboard_week. Calendar week, starting Monday.
where s.play_date >= date_trunc('week', current_date)::date
group by p.username
order by rank
limit 100;


-- ------------------------------------------------------------- all time ---

create or replace view public.leaderboard_sprint_alltime as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        sum(s.words_found)     desc,
                        max(s.puzzles_cleared) desc)      as rank,
  p.username,
  sum(s.puzzles_cleared)::int                             as puzzles_cleared,
  sum(s.words_found)::int                                 as words_found,
  count(*)::int                                           as runs,
  max(s.puzzles_cleared)::int                             as best_run,
  max(s.play_date)                                        as last_played,
  bool_or(s.flagged)                                      as flagged
from public.sprint_scores s
join public.players p using (poornata_id)
group by p.username
order by rank
limit 100;


-- ---------------------------------------------------------------- grants ---
-- The browser reads these directly, exactly as it already reads
-- leaderboard_sprint_today. They expose usernames and scores only — never a
-- poornata_id. A view runs with its owner's rights, so RLS on sprint_scores
-- does not block it, and anon still cannot touch the table underneath.
grant select on public.leaderboard_sprint_week    to anon;
grant select on public.leaderboard_sprint_alltime to anon;
