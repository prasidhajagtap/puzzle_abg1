-- ============================================================================
-- Undo 16_tiebreak_ranking.sql. Puts the three daily boards back exactly as
-- they were before the millisecond tiebreak.
--
-- These definitions are the live ones, read out of the database with
-- pg_get_viewdef on 9 September 2026 and pasted here unedited. They are not a
-- reconstruction.
--
-- WHAT THIS DOES NOT UNDO: 14_score_tiebreak.sql. The scores.time_ms column
-- and the submit_score that fills it are left alone, so nothing that has been
-- recorded is lost and the game keeps working. Use 99_rollback_tiebreak.sql if
-- you want that gone too, and run it AFTER this one — dropping the column
-- while these views order by it will fail.
--
-- WHY leaderboard_today IS DROPPED AND NOT REPLACED: 16 appended a time_ms
-- column to it. "create or replace view" can add a column at the end but
-- cannot take one away, so going back means dropping it. The grant is
-- reissued immediately below, because a dropped view takes its grants with it
-- and without that line the browser would get 401 on every daily board.
--
-- Nothing here touches a score.
-- ============================================================================

drop view if exists public.leaderboard_today;

create view public.leaderboard_today as
 select row_number() over (order by s.total_points desc, s.time_sec, s.created_at) as rank,
    p.username,
    s.total_points,
    s.word_points,
    s.time_points,
    s.streak_bonus,
    s.time_sec,
    s.words_found,
    s.words_total,
    s.solved,
    s.theme
   from scores s
     join players p using (poornata_id)
  where s.play_date = CURRENT_DATE
  order by (row_number() over (order by s.total_points desc, s.time_sec, s.created_at))
 limit 100;

grant select on public.leaderboard_today to anon;


create or replace view public.leaderboard_week as
 select row_number() over (order by (sum(s.total_points)) desc, (min(s.time_sec))) as rank,
    p.username,
    sum(s.total_points)::integer as total_points,
    count(*)::integer as games_played,
    count(*) filter (where s.solved)::integer as games_solved,
    min(s.time_sec) as best_time
   from scores s
     join players p using (poornata_id)
  where s.play_date >= date_trunc('week'::text, CURRENT_DATE::timestamp with time zone)::date
  group by p.username
  order by (row_number() over (order by (sum(s.total_points)) desc, (min(s.time_sec))))
 limit 100;


create or replace view public.leaderboard_alltime as
 with agg as (
   select scores.poornata_id,
      sum(scores.total_points)::integer as total_points,
      count(*)::integer as games_played,
      count(*) filter (where scores.solved)::integer as games_solved,
      min(scores.time_sec) filter (where scores.solved) as best_time,
      max(scores.play_date) as last_played
     from scores
    group by scores.poornata_id
 )
 select row_number() over (order by a.total_points desc, a.games_solved desc, a.best_time) as rank,
    p.username,
    a.total_points,
    a.games_played,
    a.games_solved,
    a.best_time,
    a.last_played
   from agg a
     join players p using (poornata_id)
  order by (row_number() over (order by a.total_points desc, a.games_solved desc, a.best_time))
 limit 100;

grant select on public.leaderboard_week    to anon;
grant select on public.leaderboard_alltime to anon;
