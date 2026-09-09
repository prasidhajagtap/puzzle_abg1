-- ============================================================================
-- Undo 22_sprint_one_clock.sql — the ten-minute runs come back onto the sprint
-- week and all-time boards.
--
-- These are the definitions 20_sprint_tiebreak.sql installed, with only the
-- "and s.duration_sec <= 300" line removed. The best-run tiebreak from 20 is
-- KEPT: this rolls back 22 alone, not 20 as well. Use
-- 99_rollback_sprint_tiebreak.sql after this one if you want that gone too.
--
-- No row was ever deleted by 22, so nothing has to be restored — the runs are
-- still in sprint_scores untouched and simply become visible again.
-- ============================================================================

create or replace view public.leaderboard_sprint_week as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        max(s.puzzles_cleared) desc,
                        sum(s.words_found)     desc)      as rank,
  p.username,
  sum(s.puzzles_cleared)::int                             as puzzles_cleared,
  sum(s.words_found)::int                                 as words_found,
  count(*)::int                                           as runs,
  max(s.puzzles_cleared)                                  as best_run,
  bool_or(s.flagged)                                      as flagged
from public.sprint_scores s
join public.players p using (poornata_id)
where s.play_date >= date_trunc('week', current_date)::date
group by p.username
order by 1
limit 100;

create or replace view public.leaderboard_sprint_alltime as
select
  rank() over (order by sum(s.puzzles_cleared) desc,
                        max(s.puzzles_cleared) desc,
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

grant select on public.leaderboard_sprint_week    to anon;
grant select on public.leaderboard_sprint_alltime to anon;
