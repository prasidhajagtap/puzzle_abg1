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
-- IT WRITES NOTHING. No insert, no update, no delete. It cannot change a
-- score, a session or a player. Re-running it is free.
--
-- ----------------------------------------------------------------------------
-- WHAT "STREAK" MEANS HERE, AND WHY IT IS NOT THE +5 BONUS
--
-- These are two different things and it is worth being plain about it.
--
--   The +5 bonus, in submit_score, is granted when the previous 48 hours
--   contain a game. That tolerates a one-day gap: play Monday and Wednesday
--   and Wednesday still pays +5. That rule is NOT changed by this file, and
--   nothing here feeds into any score.
--
--   streak_days, below, counts STRICTLY CONSECUTIVE days. That is what a
--   player means by a streak, and it is what every game that shows one does.
--   Skip a day and the number goes back to 1.
--
-- So a player can lose their visible streak and still earn +5. That is the
-- honest way round: the number on screen is the strict one, so it never
-- promises a run the player has not actually made. If you would rather the
-- fire matched the bonus exactly, change the anchor below to allow a gap —
-- but then the streak is claiming days that were not played.
--
-- Safe to re-run. Rollback: 99_rollback_player_stats.sql
-- Verify: 19_verify_player_stats.sql
-- ============================================================================

create or replace function public.my_stats(p_token uuid)
returns json language plpgsql security definer stable
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_pid text; v_username text;
  v_anchor date;
  v_streak int := 0;
  v_games int := 0;
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

  -- The streak is counted back from today if today has been played, and from
  -- yesterday if it has not. Anchoring on yesterday is what lets the banner
  -- say "you are on 6 days, play today to keep it" — the run is still alive
  -- and unplayed, which is the only moment the message has any force.
  v_anchor := case when v_played_today then current_date else current_date - 1 end;

  -- Consecutive days, walking back from the anchor. Each row is numbered by
  -- how far down the list it is, and kept only while its date still lines up
  -- with that position. The first gap breaks the alignment, and because the
  -- dates fall at least as fast as the numbering rises, nothing further down
  -- can ever come back into line. So this counts the run and stops, without
  -- a recursive query.
  select count(*) into v_streak
    from (
      select d.play_date,
             row_number() over (order by d.play_date desc) as rn
        from (select distinct play_date
                from scores
               where poornata_id = v_pid and play_date <= v_anchor) d
    ) t
   where t.play_date = v_anchor - (t.rn - 1)::int;

  select count(*),
         min(time_sec) filter (where solved),
         min(coalesce(time_ms, time_sec * 1000 + 500)) filter (where solved)
    into v_games, v_best_sec, v_best_ms
    from scores where poornata_id = v_pid;

  select max(puzzles_cleared) into v_best_sprint
    from sprint_scores where poornata_id = v_pid;

  -- Today's standing, and the one player immediately above. leaderboard_today
  -- already ranks with row_number, so "the row above" is exactly rank - 1.
  select rank into v_rank from leaderboard_today where username = v_username;
  if v_rank is not null and v_rank > 1 then
    select b.username,
           b.total_points - (select total_points from leaderboard_today
                              where username = v_username)
      into v_ahead, v_gap
      from leaderboard_today b
     where b.rank = v_rank - 1;
  end if;

  -- Everyone else who has played today. Usernames only, and only ones that
  -- are already public on the leaderboard — this exposes nothing new.
  select count(*), (array_agg(username order by rank))[1:3]
    into v_others, v_names
    from leaderboard_today
   where username <> v_username;

  return json_build_object(
    'ok',             true,
    'streak_days',    v_streak,
    'played_today',   v_played_today,
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
-- players or sessions directly.
grant execute on function public.my_stats(uuid) to anon;
