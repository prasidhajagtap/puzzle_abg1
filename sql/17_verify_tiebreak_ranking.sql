-- ============================================================================
-- Verify 16_tiebreak_ranking.sql. READS ONLY. Nothing here writes.
--
-- The point of these checks is to prove that nothing was disturbed, not just
-- that the new ordering exists. A view cannot change a score — that is
-- arithmetic, not trust — so most of what follows is about the SHAPE of the
-- boards and about whether the ties actually got broken.
-- ============================================================================


-- 1. All three boards still exist and the browser can still read them.
--    Expect three rows, all true.
select table_name,
       has_table_privilege('anon', ('public.'||table_name)::regclass, 'SELECT') as anon_can_read
  from information_schema.views
 where table_schema='public'
   and table_name in ('leaderboard_today','leaderboard_week','leaderboard_alltime')
 order by table_name;


-- 2. The column lists. The client reads fields by NAME, so the names and their
--    order are the contract.
--    Expect: today  = rank, username, total_points, word_points, time_points,
--                     streak_bonus, time_sec, words_found, words_total,
--                     solved, theme, time_ms      <- time_ms appended, new
--            week   = rank, username, total_points, games_played,
--                     games_solved, best_time     <- unchanged
--            alltime= rank, username, total_points, games_played,
--                     games_solved, best_time, last_played   <- unchanged
select table_name, string_agg(column_name, ', ' order by ordinal_position) as columns
  from information_schema.columns
 where table_schema='public'
   and table_name in ('leaderboard_today','leaderboard_week','leaderboard_alltime')
 group by table_name
 order by table_name;


-- 3. The tiebreak is actually in the ordering, on all three.
--    Expect three rows, uses_milliseconds = true.
select table_name,
       pg_get_viewdef(('public.'||table_name)::regclass, true) like '%time_ms%' as uses_milliseconds
  from information_schema.views
 where table_schema='public'
   and table_name in ('leaderboard_today','leaderboard_week','leaderboard_alltime')
 order by table_name;


-- 4. NO SCORE MOVED. The formula that produced every stored total still
--    explains every stored total. Expect formula_mismatches = 0.
--    rows_with_ms grows as people play; rows_without_ms are the runs from
--    before 14, which is what the mid-second fallback is for.
select count(*)                                as rows_total,
       count(time_ms)                          as rows_with_ms,
       count(*) filter (where time_ms is null) as rows_without_ms,
       count(*) filter (
         where total_points <> word_points + time_points + streak_bonus
       )                                       as formula_mismatches
  from public.scores;


-- 5. Ranks are still unique on each board — row_number, not rank, so nobody
--    shares a place. Expect rows = distinct_ranks on all three.
select 'today' as board, count(*) as rows, count(distinct rank) as distinct_ranks
  from public.leaderboard_today
union all
select 'week',   count(*), count(distinct rank) from public.leaderboard_week
union all
select 'alltime',count(*), count(distinct rank) from public.leaderboard_alltime;


-- 6. THE INTERESTING ONE — did the ties get broken on merit?
--    Every group of players on identical points for today, and what now
--    separates them. tie_broken_by says which key did the work:
--      'milliseconds'  the fast one won, which is the whole point
--      'submit order'  both runs predate 14, so there was nothing finer to
--                      use and the old behaviour stands
--    An empty result just means nobody is tied today. That is not a failure.
with today as (
  select rank, username, total_points, time_sec, time_ms,
         count(*)      over (partition by total_points) as tied_players,
         count(time_ms) over (partition by total_points) as with_ms
    from public.leaderboard_today
)
select rank, username, total_points, time_sec, time_ms,
       case when with_ms = tied_players then 'milliseconds'
            when with_ms = 0            then 'submit order (both pre-date 14)'
            else 'mixed: one run has milliseconds, one does not' end as tie_broken_by
  from today
 where tied_players > 1
 order by total_points desc, rank;


-- 7. Today's board as a player sees it. Read down the total_points column:
--    it must never increase as rank increases. If it does, something is
--    wrong with the ordering and the tiebreak is not the cause.
select rank, username, total_points, time_sec, time_ms, solved
  from public.leaderboard_today
 order by rank
 limit 20;


-- 8. All time, same read. best_time is the player's fastest solved game.
select rank, username, total_points, games_played, games_solved, best_time
  from public.leaderboard_alltime
 order by rank
 limit 20;
