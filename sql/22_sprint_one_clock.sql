-- ============================================================================
-- The Daily Nine — the sprint week and all-time boards stop mixing two clocks
--
-- THE PROBLEM. Until 12_sprint_five_minutes the sprint ran for TEN minutes.
-- It now runs for five. Both kinds of run are sitting on the same boards, and
-- those boards rank on puzzles cleared, so a ten-minute run carries roughly
-- twice the advantage for the same skill. Six of the nine sprint runs on
-- record were played on the old clock.
--
-- 12 knowingly accepted this and wrote down the cost: "the week board clears
-- itself every Monday, but all-time keeps the mix indefinitely." What it could
-- not know is that the mix would end up at the TOP of the board rather than in
-- a corner of it. This file revisits that, and it is a change to what 12
-- decided, not a continuation of it.
--
-- WHAT THIS DOES. One line added to each of the two views:
--
--     where s.duration_sec <= 300
--
-- and nothing else. Runs longer than five minutes stop appearing on the week
-- and all-time boards.
--
-- NOTHING IS DELETED. Every row stays in sprint_scores exactly as it was, with
-- its real numbers. 12 decided not to delete real people's scores and that
-- still stands — this only stops two different games being ranked against each
-- other on one list. Remove the line and every run is back.
--
-- WHY duration_sec AND NOT scoring_version. Version says which rules were in
-- force; duration says how long the player actually had. They differ in the
-- case that matters: a player who quit a ten-minute sprint after four minutes
-- is version 1, but what they did in four minutes IS comparable to a
-- five-minute run, and they keep their place. Filtering on version would throw
-- them out for a clock they did not use. duration_sec also needs no
-- maintenance — if the clock ever changes again this line is the one thing to
-- revisit, and it will be obvious why.
--
-- WHY NOT RANK BY RATE INSTEAD. Puzzles per minute looks like the fair
-- comparison and is not: the client sends
--     durationSec: Math.min(elapsed, modeBudget())
-- so a run can legitimately end early, and a player who cleared one puzzle in
-- twenty seconds and walked away would rate at three a minute and top the
-- board. Rate is only safe on a fixed denominator, which is exactly what this
-- filter restores.
--
-- >>> NO FRONT-END CHANGE. <<< Only rows are filtered. Both column lists are
-- untouched, so the game reads these boards exactly as it does now. A board
-- that ends up empty already says so ("No sprint runs on this board yet. Be
-- the first.") — that path has existed since the sprint boards were added.
--
-- WHAT IT COSTS, so it is a decision and not a surprise: a player whose only
-- sprints were ten-minute ones disappears from these two boards until they
-- run a five-minute one. PART A below shows exactly who, before you change
-- anything. Read it first.
--
-- leaderboard_sprint_today is NOT touched. It shows one day, the clock has
-- been five minutes for longer than a day, and it will never contain an old
-- run again.
--
-- Safe to re-run. Rollback: 99_rollback_sprint_one_clock.sql
-- Verify: 23_verify_sprint_one_clock.sql
-- ============================================================================


-- ===========================================================================
-- PART A — READ ONLY. Run this first and look at what PART B will do.
-- ===========================================================================

-- A1. Every sprint run, which clock it was played on, and the rate it worked
--     out at. rate_per_min is shown for information only — nothing ranks on
--     it, for the reason given above.
select p.username, s.play_date, s.scoring_version,
       s.duration_sec,
       case when s.duration_sec <= 300 then 'kept'
            else 'drops off the week and all-time boards' end        as effect,
       s.puzzles_cleared, s.words_found,
       round(s.puzzles_cleared::numeric / nullif(s.duration_sec,0) * 60, 2) as rate_per_min
  from public.sprint_scores s
  join public.players p using (poornata_id)
 order by s.duration_sec desc, s.puzzles_cleared desc;

-- A2. The damage, per player. Anyone whose kept_runs is 0 vanishes from the
--     two boards until they sprint again.
select p.username,
       count(*)                                              as runs_total,
       count(*) filter (where s.duration_sec <= 300)         as kept_runs,
       sum(s.puzzles_cleared)                                as cleared_now,
       coalesce(sum(s.puzzles_cleared)
                filter (where s.duration_sec <= 300), 0)     as cleared_after,
       max(s.puzzles_cleared)                                as best_run_now,
       max(s.puzzles_cleared)
         filter (where s.duration_sec <= 300)                as best_run_after
  from public.sprint_scores s
  join public.players p using (poornata_id)
 group by p.username
 order by cleared_after desc, cleared_now desc;

-- A3. The all-time board as it will read after PART B. If this looks wrong,
--     do not run PART B — nothing has changed yet.
select rank() over (order by sum(s.puzzles_cleared) desc,
                             max(s.puzzles_cleared) desc,
                             sum(s.words_found)     desc)  as rank,
       p.username,
       sum(s.puzzles_cleared)::int                         as puzzles_cleared,
       max(s.puzzles_cleared)                              as best_run,
       count(*)::int                                       as runs
  from public.sprint_scores s
  join public.players p using (poornata_id)
 where s.duration_sec <= 300
 group by p.username
 order by rank;


-- ===========================================================================
-- PART B — the change. Two views replaced, one line added to each.
-- Everything else is identical to 20_sprint_tiebreak.sql.
-- ===========================================================================

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
  -- ONE CLOCK: runs longer than five minutes are not comparable and are left
  -- off. The rows stay in sprint_scores; see the note at the top.
  and s.duration_sec <= 300
group by p.username
order by 1
limit 100;


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
-- ONE CLOCK: see above.
where s.duration_sec <= 300
group by p.username
order by 1
limit 100;


grant select on public.leaderboard_sprint_week    to anon;
grant select on public.leaderboard_sprint_alltime to anon;
