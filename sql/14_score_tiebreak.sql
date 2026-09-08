-- ============================================================================
-- The Daily Nine — a tiebreak that does not change a single score
--
-- WHY: for a solved game the score IS the time —
--     total_points = 50 + (300 - time_sec) + streak
-- so two players finishing in the same second tie EXACTLY. It is arithmetic,
-- not bad luck. And time_sec is floored to whole seconds, so 40.1s and 40.9s
-- both record 40. Measured on the live boards: two ties already exist, and
-- with eleven players finishing inside a ~30-second band the chance of at
-- least one tie is about 88%.
--
-- The client has had millisecond precision all along and was throwing it away.
-- This keeps it, purely as a tiebreak.
--
-- >>> WHAT THIS DOES NOT DO <<<
-- It does not change any score, anywhere, ever. time_ms is not an input to
-- word_points, time_points, streak_bonus or total_points. Every existing row
-- keeps the exact number it has now. Nothing is recalculated, nothing is
-- rewritten, nothing is deleted.
--
-- SAFETY, in the order the concerns actually bite:
--
-- 1. Adding the column cannot fail on existing data. It is nullable with no
--    default, which Postgres records as metadata only — no table rewrite, no
--    constraint to violate, and the eleven existing rows are untouched. They
--    simply hold null, meaning "this run predates millisecond timing".
--
-- 2. Old clients keep working. p_time_ms has a DEFAULT, so a call that omits
--    it still resolves and behaves exactly as before.
--
-- 3. New clients work against an un-migrated database too. PostgREST resolves
--    a function by its parameter NAMES, so a client sending p_time_ms to the
--    old function gets HTTP 404 and the score would be LOST. That was verified
--    against the live API rather than assumed. The build-20 client therefore
--    retries without p_time_ms on a 404, so the two halves can be deployed in
--    either order and no score is ever dropped over a tiebreak.
--
-- 4. The function body is otherwise byte-identical to 08, which is what is
--    running now. It was generated from that file rather than retyped, so the
--    only differences are the ones listed above. 15_verify_tiebreak.sql proves
--    that.
--
-- The leaderboard views are NOT touched here — see the note at the bottom.
--
-- Safe to re-run. Rollback: 99_rollback_tiebreak.sql
-- Verify: 15_verify_tiebreak.sql
-- ============================================================================

-- Nullable, no default: metadata-only in Postgres, instant, no rewrite.
alter table public.scores add column if not exists time_ms integer;

comment on column public.scores.time_ms is
  'Milliseconds taken, for breaking ties only. Never used to compute points. Null for runs recorded before this column existed.';

CREATE OR REPLACE FUNCTION public.submit_score(
  p_token uuid, p_theme text, p_words_found integer, p_words_total integer,
  p_time_sec integer, p_shuffles integer, p_solved boolean,
  p_attempts integer DEFAULT 1,
  p_time_ms integer DEFAULT NULL)
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
  -- The tiebreak, clamped the same way. Null when an older client did not send
  -- it, which the views fall back from. It is deliberately NOT used to compute
  -- any points: the score a player sees must not change.
  if p_time_ms is not null then
    p_time_ms := greatest(0, least(v_budget * 1000, p_time_ms));
  end if;
  -- Real players finish in 13 to 18 seconds, so the old 20-second line was
  -- flagging the best of them for being good at the game. 10 seconds is the
  -- point where a run stops being fast and starts being implausible.
  -- Anything faster is recorded but flagged, so a prize list can be audited.
  -- NOTE: this does not make cheating impossible. With a client-side game
  -- and a random grid the server cannot replay the puzzle. If prizes ride
  -- on this, move puzzle generation to the server and verify the answer.
  if p_solved and p_time_sec < 10 then
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
                      flagged, scoring_version, attempts, time_ms)
  values (v_pid, current_date, p_theme, p_words_found, p_words_total,
          p_time_sec, p_shuffles, p_solved, v_words, v_time, v_streak, v_total,
          v_flag, 4, greatest(1, least(500, coalesce(p_attempts,1))), p_time_ms)
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
         attempts        = greatest(scores.attempts, excluded.attempts),
         time_ms         = excluded.time_ms;
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


-- ============================================================================
-- WHAT IS STILL TO DO, AND WHY IT IS NOT HERE
--
-- Recording the milliseconds is step one; ranking by them is step two. The
-- ranking lives in the leaderboard views, and changing a view means replacing
-- its whole definition. The definition of leaderboard_week was read out of the
-- database, but leaderboard_today and leaderboard_alltime were not, and
-- rewriting a view from a guess is exactly how a board quietly starts meaning
-- something else.
--
-- So this file only starts collecting the data, which is the right order
-- anyway: by the time the views use time_ms there will be values in it rather
-- than a column of nulls.
--
-- To finish, run this and send back all three definitions:
--
--   select table_name, pg_get_viewdef(('public.'||table_name)::regclass, true)
--     from information_schema.views
--    where table_schema='public' and table_name like 'leaderboard%'
--    order by table_name;
--
-- The change to each is one line — adding to the ORDER BY, after the existing
-- keys so nothing already correct is disturbed:
--
--   order by total_points desc,
--            coalesce(time_ms, time_sec * 1000) asc,   -- old rows fall back
--            attempts asc,                             -- fewer tries wins
--            shuffles asc,                             -- fewer reshuffles wins
--            poornata_id asc                           -- arbitrary but STABLE
--
-- That last key matters more than it looks: without something deterministic at
-- the end, two fully tied rows are ordered by whatever the query planner feels
-- like, and a player can watch their rank move between refreshes.
-- ============================================================================
