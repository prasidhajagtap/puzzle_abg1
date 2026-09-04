-- ============================================================================
-- ROLLBACK — restores submit_score exactly as it was before the override
-- migration: the FIRST score of the day becomes final again.
-- Reproduced verbatim from the live definition captured before the change.
-- Rows already written are not touched; only future submissions change.
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
  if p_solved and p_time_sec < 20 then
    v_flag := true;
  end if;
  p_words_found := greatest(0, coalesce(p_words_found, 0));
  p_words_total := greatest(1, coalesce(p_words_total, 5));
  p_shuffles    := greatest(0, least(5, coalesce(p_shuffles, 0)));
  if p_words_found > p_words_total then p_words_found := p_words_total; end if;
  if p_words_found < p_words_total then p_solved := false; end if;

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
  on conflict (poornata_id, play_date) do nothing;

  if not found then
    return json_build_object('ok', false, 'error', 'ALREADY_PLAYED_TODAY');
  end if;

  select rank into v_rank from leaderboard_today where username = v_username;

  return json_build_object('ok', true,
                           'word_points',  v_words,
                           'time_points',  v_time,
                           'streak_bonus', v_streak,
                           'total_points', v_total, 'rank', v_rank);
end;
$function$;
