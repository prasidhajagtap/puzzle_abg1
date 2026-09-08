-- ============================================================================
-- The Daily Nine — the sprint clock drops from 10 minutes to 5
--
-- The game now runs a 300-second sprint. This brings the server's own idea of
-- the window into line with it.
--
-- WHAT CHANGES: one constant inside submit_sprint_score.
--     was:  v_window constant int := 600;     -- 10 minutes
--     now:  v_window constant int := 300;     -- 5 minutes
-- That constant is the clamp on p_duration_sec. Left at 600 it would still
-- work, because a 5-minute client never sends more than 300 — but it would
-- also let a tampered client claim a 600-second run, which the game can no
-- longer produce. This closes that.
--
-- WHAT DOES NOT CHANGE, and why each one is deliberate:
--
-- 1. The table's CHECK on duration_sec stays at <= 600.
--    Tightening it to 300 would fail outright: rows already in the table hold
--    genuine 600-second runs from when the sprint really was ten minutes. A
--    constraint has to be true of every existing row, so tightening it would
--    mean rewriting history first. The column keeps the wider bound; the
--    function is what enforces today's rule.
--
-- 2. The cheat flag stays at "more than 20 puzzles cleared".
--    It is tempting to halve it with the clock, and that would be wrong. The
--    only real sprint on record cleared 16 in 600 seconds — about 38 seconds a
--    puzzle — which in 300 seconds would be roughly 8. A flag at 10 would
--    catch a merely strong player. At 20 in five minutes a player would need
--    15 seconds a puzzle sustained, which is not credible, so the old number
--    is a *better* line for the shorter clock than it was for the longer one.
--    This is the same mistake the 20-second solve flag made, and it is not
--    worth repeating: see 08_lower_flag_threshold.sql.
--
-- 3. The words-per-puzzle sanity check is untouched. Five words to a grid does
--    not depend on how long the clock runs.
--
-- >>> ONE THING TO DECIDE, WHICH THIS FILE DOES NOT DO FOR YOU <<<
-- Sprint runs already on the board were played against a ten-minute clock.
-- leaderboard_sprint_week and leaderboard_sprint_alltime will therefore mix
-- ten-minute and five-minute runs, and the older ones have a real advantage.
-- Nothing here deletes or edits a single row, because that is your call:
--   * leave it, and the boards even out on their own within a week; or
--   * clear the sprint history and start the shorter format clean:
--         delete from public.sprint_scores;   -- NOT run by this file
-- Today's board is unaffected either way from tomorrow.
--
-- Safe to re-run. Rollback: 99_rollback_sprint_five_minutes.sql
-- Verify: 13_verify_sprint_window.sql
-- ============================================================================

create or replace function public.submit_sprint_score(
  p_token uuid, p_puzzles_cleared int, p_words_found int,
  p_duration_sec int, p_powerups_used int default 0, p_attempts int default 1)
returns json language plpgsql security definer
set search_path to 'public','extensions','pg_catalog'
as $function$
declare
  v_window constant int := 300;     -- 5 minutes
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

  -- More than 20 cleared is recorded but flagged for audit. See the note at
  -- the top of this file for why that number did not move with the clock.
  -- The grid is generated in the browser, so the server cannot replay it. If
  -- prizes ride on this board, move puzzle generation server-side and verify
  -- the answer; no threshold substitutes for that.
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
          p_duration_sec, p_powerups_used, v_flag, 2,
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

-- scoring_version moves 1 -> 2, so a row can be told apart later: version 1
-- rows were played against a ten-minute clock, version 2 against five.
