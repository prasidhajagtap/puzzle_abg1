-- ============================================================================
-- Undo 24_streak_every_day_counts.sql — back to the working-day streak that
-- 18_player_stats installed.
--
-- After this, weekend games stop counting towards the streak again (they still
-- score points and still appear on every board — that was never affected).
-- dn_workday_no is recreated because the v2 rule needs it.
--
-- Order matters: the helper has to exist before dn_streak refers to it.
-- Nothing here touches a score.
-- ============================================================================

create or replace function public.dn_workday_no(d date)
returns int language sql immutable
as $function$
  select (d - date '2001-01-01')
       - 2 * ((d - date '2001-01-01') / 7)
       - (case extract(isodow from d) when 6 then 1 when 7 then 2 else 0 end);
$function$;

create or replace function public.dn_streak(p_pid text, p_today date)
returns int language plpgsql stable
set search_path to 'public','pg_catalog'
as $function$
declare
  v_today_no int := public.dn_workday_no(p_today);
  v_anchor   int;
  v_streak   int;
begin
  if exists (select 1 from public.scores
              where poornata_id = p_pid
                and extract(isodow from play_date) < 6
                and public.dn_workday_no(play_date) = v_today_no) then
    v_anchor := v_today_no;
  else
    v_anchor := v_today_no - 1;
  end if;

  select count(*) into v_streak
    from (
      select d.no, row_number() over (order by d.no desc) as rn
        from (select distinct public.dn_workday_no(play_date) as no
                from public.scores
               where poornata_id = p_pid
                 and extract(isodow from play_date) < 6
                 and public.dn_workday_no(play_date) <= v_anchor) d
    ) t
   where t.no = v_anchor - (t.rn - 1);

  return coalesce(v_streak, 0);
end;
$function$;

-- my_stats is left as 24 wrote it apart from next_play, which under the v2
-- rule has to name the next WORKING day rather than always saying tomorrow.
create or replace function public.my_stats(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_pid text; v_username text;
  v_streak int := 0; v_games int := 0;
  v_best_sec int; v_best_ms int; v_best_sprint int;
  v_played_today boolean := false;
  v_is_workday boolean := extract(isodow from current_date) < 6;
  v_next date; v_next_label text;
  v_rank int; v_gap int; v_ahead text;
  v_others int := 0; v_names text[];
begin
  select s.poornata_id, p.username into v_pid, v_username
    from sessions s join players p using (poornata_id)
   where s.token = p_token and s.expires_at > now();
  if v_pid is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  select exists (select 1 from scores
                  where poornata_id = v_pid and play_date = current_date)
    into v_played_today;
  v_streak := public.dn_streak(v_pid, current_date);

  v_next := current_date + 1;
  while extract(isodow from v_next) >= 6 loop v_next := v_next + 1; end loop;
  v_next_label := case when v_next = current_date + 1 then 'tomorrow'
                       else trim(to_char(v_next, 'Day')) end;

  select count(*), min(time_sec) filter (where solved),
         min(coalesce(time_ms, time_sec * 1000 + 500)) filter (where solved)
    into v_games, v_best_sec, v_best_ms
    from scores where poornata_id = v_pid;
  select max(puzzles_cleared) into v_best_sprint
    from sprint_scores where poornata_id = v_pid;

  select rank into v_rank from leaderboard_today where username = v_username;
  if v_rank is not null and v_rank > 1 then
    select b.username,
           b.total_points - (select total_points from leaderboard_today
                              where username = v_username)
      into v_ahead, v_gap
      from leaderboard_today b where b.rank = v_rank - 1;
  end if;

  select count(*), (array_agg(username order by rank))[1:3]
    into v_others, v_names
    from leaderboard_today where username <> v_username;

  return json_build_object(
    'ok', true, 'streak_days', v_streak, 'played_today', v_played_today,
    'is_workday', v_is_workday,
    'at_risk', (v_is_workday and not v_played_today and v_streak > 0),
    'next_play', v_next_label,
    'games_played', v_games, 'best_time_sec', v_best_sec, 'best_time_ms', v_best_ms,
    'best_sprint', coalesce(v_best_sprint, 0), 'rank_today', v_rank,
    'points_behind', v_gap, 'player_ahead', v_ahead,
    'others_today', coalesce(v_others, 0),
    'names_today', coalesce(to_jsonb(v_names), '[]'::jsonb));
end;
$function$;

revoke execute on function public.dn_workday_no(date)  from public, anon, authenticated;
revoke execute on function public.dn_streak(text, date) from public, anon, authenticated;
grant execute on function public.my_stats(uuid) to anon;
