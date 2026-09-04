-- ============================================================================
-- The Daily Nine — allow a player to replace their score for the day
--
-- WHAT CHANGES: exactly one block. The INSERT used to end with
--     on conflict (poornata_id, play_date) do nothing;
--     if not found then return ... 'ALREADY_PLAYED_TODAY' ...
-- which made the FIRST score of the day final. It now overwrites, so the
-- LAST score a player submits is the one that stands.
--
-- WHAT DOES NOT CHANGE: the scoring maths, the streak rule, the 20-second
-- flag, the clamps, the rank lookup, SECURITY DEFINER and search_path are
-- all reproduced exactly as they are today.
--
-- The UNIQUE (poornata_id, play_date) constraint STAYS. It is what makes
-- "one row per player per day" true and what ON CONFLICT keys on. Do not
-- drop it.
--
-- Safe to re-run. Rollback: 99_rollback_submit_score.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.submit_score(
  p_token uuid, p_theme text, p_words_found integer, p_words_total integer,
  p_time_sec integer, p_shuffles integer, p_solved boolean,
  p_attempts integer DEFAULT 1)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_catalog'
AS $function$
declare
  v_budget constant int := 300;      -- 5 minutes
  v_pid text; v_username text;
  v_words int; v_time int; v_streak int := 0; v_total int; v_rank int;
  v_flag boolean := false;
begin
  select s.poornata_id, p.username into v_pid, v_username
    from sessions s join players p using (poornata_id)
   where s.token = p_token and s.expires_at > now();

  if v_pid is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  p_time_sec    := greatest(0, least(v_budget, coalesce(p_time_sec, v_budget)));
  -- A human cannot find five words in a 9x9 grid in under ~20 seconds.
  -- Anything faster is recorded but flagged, so a prize list can be audited.
  -- NOTE: this does not make cheating impossible. With a client-side game
  -- and a random grid the server cannot replay the puzzle. If prizes ride
  -- on this, move puzzle generation to the server and verify the answer.
  if p_solved and p_time_sec < 20 then
    v_flag := true;
  end if;
  p_words_found := greatest(0, coalesce(p_words_found, 0));
  p_words_total := greatest(1, coalesce(p_words_total, 5));
  p_shuffles    := greatest(0, least(5, coalesce(p_shuffles, 0)));
  if p_words_found > p_words_total then p_words_found := p_words_total; end if;
  if p_words_found < p_words_total then p_solved := false; end if;

  /* ---- SCORING ------------------------------------------------------
     Words : 10 per word found                    -> 0 .. 50
     Time  : 1 point for every SECOND left on the
             300-second clock                      -> 0 .. 300
             Awarded ONLY when every word is found. Without that rule a
             player who finds two words and quits immediately would beat
             someone who actually finished, so giving up would be the
             winning move. Speed therefore dominates, which is intended.
     Streak: flat +5 while the previous 48 hours contain a game. It never
             compounds — it is +5 on day 2, +5 on day 3, and so on.
             The window looks at days BEFORE today, so replacing today's
             score cannot inflate or break a streak.
     -------------------------------------------------------------------- */
  v_words := p_words_found * 10;
  v_time  := case when p_solved
                  then greatest(0, v_budget - p_time_sec)
                  else 0 end;

  if exists (select 1 from scores
              where poornata_id = v_pid
                and play_date >= current_date - 2
                and play_date <  current_date) then
    v_streak := 5;
  end if;

  v_total := v_words + v_time + v_streak;

  insert into scores (poornata_id, play_date, theme, words_found, words_total,
                      time_sec, shuffles, solved,
                      word_points, time_points, streak_bonus, total_points,
                      flagged, scoring_version, attempts)
  values (v_pid, current_date, p_theme, p_words_found, p_words_total,
          p_time_sec, p_shuffles, p_solved, v_words, v_time, v_streak, v_total,
          v_flag, 4, greatest(1, least(500, coalesce(p_attempts,1))))
  -- ---- THE ONE CHANGE -------------------------------------------------
  -- Was: do nothing (first score of the day was final).
  -- Now: overwrite, so the last score the player submits is the one kept.
  on conflict (poornata_id, play_date) do update
     set theme           = excluded.theme,
         words_found     = excluded.words_found,
         words_total     = excluded.words_total,
         time_sec        = excluded.time_sec,
         shuffles        = excluded.shuffles,
         solved          = excluded.solved,
         word_points     = excluded.word_points,
         time_points     = excluded.time_points,
         streak_bonus    = excluded.streak_bonus,
         total_points    = excluded.total_points,
         flagged         = excluded.flagged,
         scoring_version = excluded.scoring_version,
         -- keep the higher count, so a page refresh cannot lower it
         attempts        = greatest(scores.attempts, excluded.attempts);
  -- The ALREADY_PLAYED_TODAY branch that stood here is gone: with DO UPDATE
  -- the insert always affects a row, so it could never fire again.
  -- ---------------------------------------------------------------------

  select rank into v_rank from leaderboard_today where username = v_username;

  return json_build_object('ok', true,
                           'word_points',  v_words,
                           'time_points',  v_time,
                           'streak_bonus', v_streak,
                           'total_points', v_total, 'rank', v_rank);
end;
$function$;
