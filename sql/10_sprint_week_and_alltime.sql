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
-- >>> ONE THING TO CHECK <<<
-- The window below is a rolling 7 days: today and the six days before it.
-- I could not read the definition of leaderboard_week from outside the
-- database, so I could not confirm that daily uses the same window. If daily
-- uses something else — a calendar week, or 7 days rather than 6 — then
-- "This week" would quietly mean two different things on the two boards.
-- Run B5 in 07_diagnose_admin_contract.sql to see the daily definition, and
-- if it differs, change the one predicate marked WINDOW below to match. It is
-- a single line in each view.
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
where s.play_date >= current_date - 6        -- WINDOW: rolling 7 days
  and s.play_date <= current_date
group by p.username;


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
group by p.username;


-- ---------------------------------------------------------------- grants ---
-- The browser reads these directly, exactly as it already reads
-- leaderboard_sprint_today. They expose usernames and scores only — never a
-- poornata_id. A view runs with its owner's rights, so RLS on sprint_scores
-- does not block it, and anon still cannot touch the table underneath.
grant select on public.leaderboard_sprint_week    to anon;
grant select on public.leaderboard_sprint_alltime to anon;
