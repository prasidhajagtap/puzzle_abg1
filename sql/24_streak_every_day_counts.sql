-- ============================================================================
-- The Daily Nine — the streak counts calendar days. A day is a day.
--
-- THE RULE, and it is the whole rule: consecutive days played. Every day you
-- play adds one. Miss ANY day and the run is over. There is no weekend, no
-- grace day, no holiday and no exception of any kind.
--
-- THIS IS DELIBERATELY STRICTER THAN THE +5 BONUS. submit_score pays +5 when
-- the previous 48 hours contain a game, so a player can skip a day, still be
-- paid the bonus, and still lose their streak. The two rules are different on
-- purpose: the bonus is generous because it is money, the streak is strict
-- because it is a streak. Nothing here feeds any score.
--
-- HOW THIS ARRIVED, because it changed three times and the history is the
-- argument:
--
--   v1 strict calendar days.
--   v2 working days: a weekend neither counted nor broke a run. Fixed
--      breakage, but eleven of the seventy-four games on record were played
--      at the weekend and earned nothing towards a streak.
--   v3 every day counts, only a missed weekday breaks.
--   v4 strict calendar days again — this file. Requested directly: "day is
--      day, do not stop on weekend."
--
-- WHAT IT COSTS, measured on the live data and stated plainly rather than
-- discovered later: this is by far the harshest of the four. Under v2 the most
-- engaged player in the game showed 6. Under strict calendar days he showed 2,
-- and nobody in the player base held more than 2. That is the trade being
-- made: the number is small and it is unambiguous. It also means a player who
-- takes a Sunday off starts again at 1 on Monday.
--
-- THE ANCHOR is today if today has been played, otherwise yesterday. Today
-- being unplayed is not a break — the day is not over yet. That is what lets
-- the banner say "you are on 6, play today to keep it".
--
-- dn_workday_no IS DROPPED. It existed only to make Friday and Monday
-- adjacent, which no rule needs any more.
--
-- Safe to re-run. Rollback: 99_rollback_streak_every_day.sql (back to v2)
-- Verify: 25_verify_streak_every_day.sql
-- ============================================================================


-- ---------------------------------------------------------------------------
-- The date is a parameter rather than read from the clock, so every day of the
-- week can be tested rather than only the day a test happens to run on.
-- ---------------------------------------------------------------------------
create or replace function public.dn_streak(p_pid text, p_today date)
returns int language plpgsql stable
set search_path to 'public','pg_catalog'
as $function$
declare
  v_anchor date;
  v_streak int;
begin
  if exists (select 1 from public.scores
              where poornata_id = p_pid and play_date = p_today) then
    v_anchor := p_today;
  else
    v_anchor := p_today - 1;
  end if;

  -- Days walked back from the anchor. Each is numbered by how far down the
  -- list it sits, and kept only while its date still lines up with that
  -- position. The first missed day breaks the alignment, and because the dates
  -- fall at least as fast as the counter rises, nothing further back can come
  -- into line again. One gap of any kind ends the run.
  select count(*) into v_streak
    from (
      select d.play_date, row_number() over (order by d.play_date desc) as rn
        from (select distinct play_date
                from public.scores
               where poornata_id = p_pid and play_date <= v_anchor) d
    ) t
   where t.play_date = v_anchor - (t.rn - 1)::int;

  return coalesce(v_streak, 0);
end;
$function$;


-- ---------------------------------------------------------------------------
create or replace function public.my_stats(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_pid text; v_username text;
  v_streak int := 0; v_games int := 0;
  v_best_sec int; v_best_ms int; v_best_sprint int;
  v_played_today boolean := false;
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

  select count(*),
         min(time_sec) filter (where solved),
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
      from leaderboard_today b
     where b.rank = v_rank - 1;
  end if;

  select count(*), (array_agg(username order by rank))[1:3]
    into v_others, v_names
    from leaderboard_today
   where username <> v_username;

  return json_build_object(
    'ok',             true,
    'streak_days',    v_streak,
    'played_today',   v_played_today,
    -- Every day is the same day now, so there is no weekend branch left. These
    -- two are kept in the payload, constant, so a client that has not been
    -- updated yet still renders the plain weekday wording rather than a
    -- weekend message on a Saturday.
    'is_workday',     true,
    'next_play',      'tomorrow',
    -- A run is in danger on ANY day that has not been played yet.
    'at_risk',        (not v_played_today and v_streak > 0),
    'games_played',   v_games,
    'best_time_sec',  v_best_sec,
    'best_time_ms',   v_best_ms,
    'best_sprint',    coalesce(v_best_sprint, 0),
    'rank_today',     v_rank,
    'points_behind',  v_gap,
    'player_ahead',   v_ahead,
    'others_today',   coalesce(v_others, 0),
    'names_today',    coalesce(to_jsonb(v_names), '[]'::jsonb)
  );
end;
$function$;


-- No rule needs Friday and Monday to be adjacent any more.
drop function if exists public.dn_workday_no(date);

-- Shut the helper to the browser. Revoking from PUBLIC alone is NOT enough on
-- Supabase — it separately grants EXECUTE to anon and authenticated on
-- anything created in this schema, and an earlier version of 18 was caught by
-- exactly that: a revoked function answered a request made with the public
-- anon key. All three roles, every time.
revoke execute on function public.dn_streak(text, date) from public, anon, authenticated;

grant execute on function public.my_stats(uuid) to anon;
