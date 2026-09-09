-- ============================================================================
-- The Daily Nine — step two of the tiebreak: the boards start USING the
-- milliseconds that 14 started recording.
--
-- REQUIRES 14_score_tiebreak.sql. If that has not been run, every statement
-- here fails on "column time_ms does not exist" and nothing is changed. That
-- is deliberate — it cannot half-apply.
--
-- >>> WHAT THIS DOES NOT DO <<<
-- No score changes. Not one. These are views: they read the scores table and
-- present it. total_points, word_points, time_points and streak_bonus are
-- written by submit_score and are not touched here, by anything.
--
-- What DOES change is the ORDER of players who were already tied. That is the
-- whole feature. Two players on 342 points used to be separated by whoever
-- pressed submit first; now they are separated by who was actually faster.
--
-- The three view definitions below were read out of the live database with
-- pg_get_viewdef and edited, not rewritten from memory. Everything except the
-- ORDER BY keys is as it was. The rollback file holds the originals verbatim.
--
-- ----------------------------------------------------------------------------
-- WHY time_sec COMES BEFORE time_ms, WHICH IS NOT WHAT 14's NOTE SAID
--
-- 14 suggested ordering by coalesce(time_ms, time_sec*1000) in place of
-- time_sec. That is wrong, and it took reading the real definitions to see it.
--
-- The two columns are clamped independently by submit_score, so a tampered
-- client can send time_sec = 10 with time_ms = 0. Ordered on milliseconds
-- first, that row leaps over an honest 5-second run. Ordered on seconds first,
-- the milliseconds can only ever separate players INSIDE the same second,
-- which is the only job they were added for. The seconds stay the number that
-- decides the board; the milliseconds decide nothing but the tie.
--
-- WHY OLD ROWS FALL BACK TO time_sec*1000 + 500, NOT + 0
--
-- Rows recorded before 14 hold null. Reading a null as "finished exactly on
-- the second" would hand every old row the win over every new row in the same
-- second, permanently, on the all-time board. Reading it as the MIDDLE of the
-- second favours neither: a new run faster than the half-second beats the old
-- row, a slower one loses to it. We do not know where in that second the old
-- run landed, and this is the one value that does not pretend we do.
--
-- WHY attempts IS NOT A TIEBREAK KEY
--
-- 14's note proposed "fewer tries wins". On reflection that is a bad rule for
-- THIS game. The result screen openly invites a player to replay and replace
-- their score. Ranking a replay below a first attempt would punish the exact
-- behaviour the game asks for, and the board does not show attempts, so a
-- player could never work out why they lost. Left out on purpose.
--
-- Safe to re-run. Rollback: 99_rollback_tiebreak_ranking.sql
-- Verify: 17_verify_tiebreak_ranking.sql
-- ============================================================================


-- ------------------------------------------------------------------ today ---
-- Was: order by total_points desc, time_sec, created_at
-- Now: the same, with milliseconds and shuffles slotted in before created_at.
--
-- created_at is KEPT as the second-to-last key. It is what separates two rows
-- today, and dropping it would move ranks for no reason on rows that the
-- milliseconds cannot separate anyway. username is added last so that two rows
-- alike in every single key still come out in the same order on every refresh
-- — without a deterministic final key a player can watch their rank swap
-- between two page loads and reasonably conclude the board is broken.
--
-- ONE COLUMN IS ADDED at the end: time_ms. Nothing reads it yet. The client
-- asks for select=* and picks fields by name, so an extra one is ignored. It
-- is here so the board can one day show "0:40.45" and answer the question
-- this whole change creates: why am I fifth when we both scored 342?
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


-- ------------------------------------------------------------------- week ---
-- Was: order by sum(total_points) desc, min(time_sec)
-- Now: the same, then the player's best millisecond time, then username.
--
-- min(time_sec) and min(time_ms) can only disagree when the seconds are equal,
-- because a player whose fastest game was 40 seconds has no millisecond value
-- below 40000. So the second key still decides, and the third only splits
-- players whose best games landed in the same second.
--
-- The column list is unchanged: best_time_ms is computed for the ordering and
-- deliberately not selected, so nothing that reads this view sees a new field.
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


-- --------------------------------------------------------------- all time ---
-- Was: order by total_points desc, games_solved desc, best_time
-- Now: the same, then best millisecond time, then username.
--
-- best_time here carries "filter (where solved)", so best_time_ms carries the
-- identical filter. Without it the two would be measuring different sets of
-- games and could contradict each other. A player with no solved game has null
-- for both, and nulls sort last in an ascending order exactly as they do now.
--
-- best_time_ms lives in the CTE and is not selected, so the output columns are
-- untouched.
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


-- ---------------------------------------------------------------- grants ---
-- create or replace view keeps existing grants, so these are belt and braces
-- rather than a fix. They are here so that re-running this file after someone
-- has dropped and recreated a view by hand still leaves the browser able to
-- read the boards. The views expose usernames and scores only, never a
-- poornata_id, and a view runs with its owner's rights so RLS on scores is not
-- what is protecting the table — the missing grant to anon is.
grant select on public.leaderboard_today   to anon;
grant select on public.leaderboard_week    to anon;
grant select on public.leaderboard_alltime to anon;


-- ============================================================================
-- THE SPRINT BOARDS ARE NOT TOUCHED, AND THEY HAVE THE SAME PROBLEM
--
-- sprint_scores has no time_ms column — 14 only added one to scores — so there
-- is no millisecond tiebreak to apply here. But the three sprint views have a
-- separate and smaller version of the same complaint:
--
--   leaderboard_sprint_today ranks with rank(), which correctly lets a genuine
--   tie SHARE a place, and then has no ORDER BY of its own. The browser asks
--   for order=rank.asc, so two players sharing rank 1 come back in whatever
--   order the planner picked that second. Their rank number is right and does
--   not move; their position on screen can swap between refreshes.
--
-- Fixing that is one line per view (order by rank, username) and changes no
-- rank number and no score. It is left out here because it is a different
-- thing from the tiebreak that was asked for, and mixing them would mean this
-- file could no longer be described as "daily ranking only". Ask and it is a
-- two-minute change.
-- ============================================================================
