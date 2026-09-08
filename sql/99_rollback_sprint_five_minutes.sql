-- ============================================================================
-- Rollback for 12_sprint_five_minutes.sql — puts the sprint window back to
-- 600 seconds. This is submit_sprint_score exactly as 03 created it, which is
-- the version that was applied before 12.
--
-- Note: scoring_version goes back to 1 as well, so rows written after a
-- rollback are indistinguishable from the original ten-minute ones.
-- ============================================================================

create or replace function public.submit_sprint_score(
  p_token uuid, p_puzzles_cleared int, p_words_found int,
  p_duration_sec int, p_powerups_used int default 0, p_attempts int default 1)
returns json language plpgsql security definer
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_window constant int := 600;     -- 10 minutes
  v_pid text; v_username text; v_rank int; v_flag boolean := false;
begin
  select s.poornata_id, p.username into v_pid, v_username
    from sessions s join players p using (poornata_id)
   where s.token = p_token and s.expires_at > now();

  if v_pid is null then
    return json_build_object('ok', false, 'error', 'NO_SESSION');
  end if;

  -- clamp everything the browser sends
  p_puzzles_cleared := greatest(0, least(100, coalesce(p_puzzles_cleared, 0)));
  p_words_found     := greatest(0, least(500, coalesce(p_words_found, 0)));
  p_duration_sec    := greatest(0, least(v_window, coalesce(p_duration_sec, v_window)));
  p_powerups_used   := greatest(0, least(2,   coalesce(p_powerups_used, 0)));

  -- A cleared 9x9 grid takes a person roughly 30 seconds at best, so more
  -- than 20 in ten minutes is recorded but flagged for audit. Same spirit,
  -- and the same limits, as the 20-second flag in submit_score: the grid is
  -- generated in the browser, so the server cannot replay it. If prizes ride
  -- on this board, move puzzle generation server-side and verify answers.
  if p_puzzles_cleared > 20 then
    v_flag := true;
  end if;
  -- five words to a puzzle: more words than that many is impossible
  if p_words_found > p_puzzles_cleared * 5 + 4 then
    v_flag := true;
  end if;

  insert into sprint_scores (poornata_id, play_date, puzzles_cleared, words_found,
                             duration_sec, powerups_used, flagged, scoring_version, attempts)
  values (v_pid, current_date, p_puzzles_cleared, p_words_found,
          p_duration_sec, p_powerups_used, v_flag, 1,
          greatest(1, least(500, coalesce(p_attempts, 1))))
  on conflict (poornata_id, play_date) do update
     set puzzles_cleared = excluded.puzzles_cleared,
         words_found     = excluded.words_found,
         duration_sec    = excluded.duration_sec,
         powerups_used   = excluded.powerups_used,
         flagged         = excluded.flagged,
         scoring_version = excluded.scoring_version,
         attempts        = greatest(sprint_scores.attempts, excluded.attempts),
         updated_at      = now();

  select rank into v_rank from leaderboard_sprint_today where username = v_username;

  return json_build_object('ok', true,
                           'puzzles_cleared', p_puzzles_cleared,
                           'words_found',     p_words_found,
                           'duration_sec',    p_duration_sec,
                           'powerups_used',   p_powerups_used,
                           'rank',            v_rank);
end;
$function$;
