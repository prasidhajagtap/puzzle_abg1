-- ============================================================================
-- Rollback for 35_fair_boards.sql
--
-- Puts the six boards back exactly as 16_tiebreak_ranking.sql,
-- 03_sprint_and_powerups.sql and 22_sprint_one_clock.sql left them (flagged
-- results and hidden players shown again, 100-row limit back), and removes the
-- name check.
--
-- KEPT on purpose:
--   players.hidden / hidden_at / hidden_by - dropping them would forget who
--     the admin hid. With the old boards they simply have no effect.
--   blocked_name_words - the word list. Unused once the check is gone.
--   the two play_date indexes - they only make reads faster.
--
-- Run streak_Admin sql/A99_rollback_hide_players.sql FIRST if A09 was run,
-- because its functions use players.hidden.
-- ============================================================================

begin;

drop trigger if exists players_name_guard on public.players;
drop function if exists public.dn_players_name_guard();
drop function if exists public.name_allowed(text);
drop function if exists public.dn_name_problem(text);

create or replace view public.leaderboard_today as
 select row_number() over (
          order by s.total_points desc,
                   s.time_sec,
                   coalesce(s.time_ms, s.time_sec * 1000 + 500),
                   s.shuffles,
                   s.created_at,
                   p.username) as rank,
    p.username,
    s.total_points,
    s.word_points,
    s.time_points,
    s.streak_bonus,
    s.time_sec,
    s.words_found,
    s.words_total,
    s.solved,
    s.theme,
    s.time_ms
   from scores s
     join players p using (poornata_id)
  where s.play_date = CURRENT_DATE
  order by 1
 limit 100;

create or replace view public.leaderboard_week as
 select row_number() over (
          order by sum(s.total_points) desc,
                   min(s.time_sec),
                   min(coalesce(s.time_ms, s.time_sec * 1000 + 500)),
                   p.username) as rank,
    p.username,
    sum(s.total_points)::integer as total_points,
    count(*)::integer as games_played,
    count(*) filter (where s.solved)::integer as games_solved,
    min(s.time_sec) as best_time
   from scores s
     join players p using (poornata_id)
  where s.play_date >= date_trunc('week'::text, CURRENT_DATE::timestamp with time zone)::date
  group by p.username
  order by 1
 limit 100;

create or replace view public.leaderboard_alltime as
 with agg as (
   select scores.poornata_id,
      sum(scores.total_points)::integer as total_points,
      count(*)::integer as games_played,
      count(*) filter (where scores.solved)::integer as games_solved,
      min(scores.time_sec) filter (where scores.solved) as best_time,
      min(coalesce(scores.time_ms, scores.time_sec * 1000 + 500))
        filter (where scores.solved) as best_time_ms,
      max(scores.play_date) as last_played
     from scores
    group by scores.poornata_id
 )
 select row_number() over (
          order by a.total_points desc,
                   a.games_solved desc,
                   a.best_time,
                   a.best_time_ms,
                   p.username) as rank,
    p.username,
    a.total_points,
    a.games_played,
    a.games_solved,
    a.best_time,
    a.last_played
   from agg a
     join players p using (poornata_id)
  order by 1
 limit 100;

create or replace view public.leaderboard_sprint_today as
select
  rank() over (order by s.puzzles_cleared desc, s.words_found desc, s.duration_sec asc) as rank,
  p.username,
  s.puzzles_cleared,
  s.words_found,
  s.duration_sec,
  s.powerups_used,          -- shown as a small marker; a used power-up is visible, not punished
  s.flagged
from public.sprint_scores s
join public.players p using (poornata_id)
where s.play_date = current_date;

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

grant select on public.leaderboard_today, public.leaderboard_week, public.leaderboard_alltime,
                public.leaderboard_sprint_today, public.leaderboard_sprint_week,
                public.leaderboard_sprint_alltime to anon;

commit;

select 'rolled back' as status,
       (select count(*) from pg_trigger where tgname = 'players_name_guard') as name_guard_left,
       (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname like 'leaderboard\_%'
           and pg_get_viewdef(c.oid) ~* 'hidden') as boards_still_filtering;
