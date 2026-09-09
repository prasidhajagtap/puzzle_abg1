-- ============================================================================
-- The Daily Nine — one read-only call that feeds the "come back tomorrow"
-- screens: streak length, personal bests, and who else has played today.
--
-- WHY A NEW FUNCTION AND NOT A CHANGE TO login_player:
-- login_player and resume_session are the authentication path. Everything a
-- player owns is behind them. Adding fields there to power a decorative
-- banner would put cosmetic code on the one path that must never break, and
-- it would make every sign-in slower for a number the sign-in screen does not
-- show. This is additive: nothing that exists is altered.
--
-- IT WRITES NOTHING. No insert, no update, no delete. Both functions are
-- declared STABLE, which is the database's own guarantee rather than a
-- promise in a comment: Postgres refuses to let a stable function write.
--
-- ----------------------------------------------------------------------------
-- THE STREAK COUNTS WORKING DAYS, AND THAT IS THE WHOLE POINT
--
-- The first version of this file counted strictly consecutive calendar days.
-- It was correct and it was useless. Measured against the live data on
-- 9 September 2026:
--
--     OmkarB had played 18 of the 19 working days since launch — 95% — and
--     a strict streak called it 2.
--
-- There had been 8 weekend days in that window. This is a game played from a
-- desk, so a strict daily streak breaks every Saturday and nobody can ever
-- build one. A badge that tells the most loyal player in the game he is on a
-- two-day run does the opposite of what a streak is for.
--
-- So Saturday and Sunday neither COUNT nor BREAK a run. Friday and the
-- following Monday are adjacent. A genuinely missed working day still breaks
-- it, so the number stays honest.
--
-- Measured on four fabricated patterns before this was written:
--     plays every weekday, never weekends   strict 3   working days 20
--     plays literally every day             strict 28  working days 20
--     weekdays but missed one Tuesday       strict 3   working days  6
--     weekends only                         strict 0   working days  0
--
-- WHAT WAS RULED OUT: matching the +5 bonus, which forgives a one-day gap.
-- A weekend is a TWO-day gap, so that rule would still break every Saturday.
-- It sounds like the fix and is not.
--
-- WEEKEND-ONLY PLAYERS get a streak of 0 and always will. That is a real
-- limitation, accepted deliberately: this is a workplace game, and the four
-- patterns above show the cost falls only on someone who never plays a
-- working day.
--
-- PUBLIC HOLIDAYS are NOT handled. Someone who takes Diwali off loses their
-- run. The fix, if it ever bites, is one forgiven working day per week rather
-- than a holiday calendar to maintain. Left out until it is seen to happen.
--
-- THIS IS STILL NOT THE +5 BONUS. The bonus in submit_score is unchanged and
-- nothing here feeds any score. A player can lose the fire and still earn +5.
--
-- Safe to re-run. Rollback: 99_rollback_player_stats.sql
-- Verify: 19_verify_player_stats.sql
-- ============================================================================


-- ---------------------------------------------------------------------------
-- A "working day number": Friday and the Monday after it differ by 1.
--
-- 2001-01-01 was a Monday, so days-since-then divided by 7 is the number of
-- whole weeks, and two days are dropped for each. Saturday and Sunday fall
-- back onto the preceding Friday's number, which is why callers filter them
-- out before counting — they must not be counted, only ignored.
-- ---------------------------------------------------------------------------
create or replace function public.dn_workday_no(d date)
returns int language sql immutable
as $function$
  select (d - date '2001-01-01')
       - 2 * ((d - date '2001-01-01') / 7)
       - (case extract(isodow from d) when 6 then 1 when 7 then 2 else 0 end);
$function$;


-- ---------------------------------------------------------------------------
-- The streak itself, with the date passed in rather than read from the clock.
--
-- That is not an accident: a function that reads current_date can only ever
-- be tested on whatever day the test happens to run, and the interesting
-- cases here are Saturday and Monday. Passing the day in means all seven can
-- be proved. my_stats calls it with current_date and nothing else does.
-- ---------------------------------------------------------------------------
create or replace function public.dn_streak(p_pid text, p_today date)
returns int language plpgsql stable
set search_path to 'public','pg_catalog'
as $function$
declare
  v_today_no int := public.dn_workday_no(p_today);
  v_anchor   int;
  v_streak   int;
begin
  -- Where the run has to end for it to still be alive. If the current working
  -- day has been played, the run may reach it; if not, the run can only reach
  -- the working day before — and today is the one still to be won.
  -- On a Saturday or Sunday v_today_no is already Friday's number, so a
  -- weekend simply asks "was Friday played?", which is the right question.
  if exists (select 1 from public.scores
              where poornata_id = p_pid
                and extract(isodow from play_date) < 6
                and public.dn_workday_no(play_date) = v_today_no) then
    v_anchor := v_today_no;
  else
    v_anchor := v_today_no - 1;
  end if;

  -- Working days walked back from the anchor. Each is numbered by how far
  -- down the list it sits and kept only while its number still lines up. The
  -- first gap breaks the alignment, and because the numbers fall at least as
  -- fast as the counter rises, nothing further down can come back into line.
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

-- Shut the two helpers to the browser.
--
-- REVOKING FROM public IS NOT ENOUGH ON SUPABASE, and an earlier version of
-- this file got that wrong. Postgres grants EXECUTE to PUBLIC on every new
-- function, but Supabase ALSO ships a default privilege that grants EXECUTE
-- to anon and authenticated on anything created in this schema. Removing
-- PUBLIC's grant leaves those two standing, so the function stays callable.
--
-- Proved from outside with nothing but the public anon key, after the first
-- version was applied:
--     POST /rest/v1/rpc/dn_workday_no  {"d":"2026-09-09"}  ->  200  6702
-- It had been revoked, and it answered anyway. Hence all three roles below.
--
-- Why it matters: dn_streak takes a poornata_id, so an open one is a way to
-- ask whether an employee id exists. It is additionally protected by not
-- being SECURITY DEFINER — called as anon it cannot read scores at all — but
-- defence in depth is not a reason to leave the front door open.
--
-- my_stats is SECURITY DEFINER and runs as the owner, so it still calls both.
revoke execute on function public.dn_workday_no(date)  from public, anon, authenticated;
revoke execute on function public.dn_streak(text, date) from public, anon, authenticated;


-- ---------------------------------------------------------------------------
create or replace function public.my_stats(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_pid text; v_username text;
  v_streak int := 0;
  v_games int := 0;
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

  -- The next day the streak can be extended, named the way a person would say
  -- it. On a Friday that is "Monday", not "tomorrow", and on a Saturday the
  -- run is not in danger at all — which is why at_risk is computed here and
  -- not guessed at in the browser.
  v_next := current_date + 1;
  while extract(isodow from v_next) >= 6 loop
    v_next := v_next + 1;
  end loop;
  v_next_label := case when v_next = current_date + 1 then 'tomorrow'
                       else trim(to_char(v_next, 'Day')) end;

  select count(*),
         min(time_sec) filter (where solved),
         min(coalesce(time_ms, time_sec * 1000 + 500)) filter (where solved)
    into v_games, v_best_sec, v_best_ms
    from scores where poornata_id = v_pid;

  select max(puzzles_cleared) into v_best_sprint
    from sprint_scores where poornata_id = v_pid;

  -- Today's standing, and the player immediately above. leaderboard_today
  -- ranks with row_number, so "the row above" is exactly rank - 1.
  select rank into v_rank from leaderboard_today where username = v_username;
  if v_rank is not null and v_rank > 1 then
    select b.username,
           b.total_points - (select total_points from leaderboard_today
                              where username = v_username)
      into v_ahead, v_gap
      from leaderboard_today b
     where b.rank = v_rank - 1;
  end if;

  -- Everyone else who has played today. Usernames only, and only ones already
  -- public on the leaderboard — this exposes nothing new.
  select count(*), (array_agg(username order by rank))[1:3]
    into v_others, v_names
    from leaderboard_today
   where username <> v_username;

  return json_build_object(
    'ok',             true,
    'streak_days',    v_streak,
    'played_today',   v_played_today,
    'is_workday',     v_is_workday,
    -- A run is only in danger on a working day that has not been played yet.
    -- On a weekend it is simply safe, and the banner must not nag.
    'at_risk',        (v_is_workday and not v_played_today and v_streak > 0),
    'next_play',      v_next_label,
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

-- The browser calls this with the anon key and its own session token. The
-- token is what proves who the caller is; anon still cannot read scores,
-- players or sessions directly, and cannot call the two helpers above.
grant execute on function public.my_stats(uuid) to anon;
