-- ============================================================================
-- Verify 22_sprint_one_clock.sql. READS ONLY.
-- ============================================================================

-- 1. Both boards exist, the browser can still read them, and THE COLUMN LISTS
--    ARE UNCHANGED. That last part is what makes this a server-only change:
--    the game reads fields by name, so identical columns means no front-end
--    work. Expect two rows, anon_can_read true, and the same columns as before.
select table_name,
       has_table_privilege('anon', ('public.'||table_name)::regclass,'SELECT') as anon_can_read,
       (select string_agg(column_name, ', ' order by ordinal_position)
          from information_schema.columns c
         where c.table_schema='public' and c.table_name=v.table_name)          as columns
  from information_schema.views v
 where table_schema='public'
   and table_name in ('leaderboard_sprint_week','leaderboard_sprint_alltime')
 order by table_name;

-- 2. The filter is really on both. Expect true, true.
select table_name,
       pg_get_viewdef(('public.'||table_name)::regclass, true) like '%duration_sec <= 300%'
         as one_clock_only
  from information_schema.views
 where table_schema='public'
   and table_name in ('leaderboard_sprint_week','leaderboard_sprint_alltime')
 order by table_name;

-- 3. The best-run tiebreak from 20 survived. Expect true, true.
select table_name,
       strpos(pg_get_viewdef(('public.'||table_name)::regclass, true), 'max(s.puzzles_cleared)) DESC')
         < strpos(pg_get_viewdef(('public.'||table_name)::regclass, true), 'sum(s.words_found)) DESC')
         as best_run_still_outranks_words
  from information_schema.views
 where table_schema='public'
   and table_name in ('leaderboard_sprint_week','leaderboard_sprint_alltime')
 order by table_name;

-- 4. Today's board was NOT touched. Expect false.
select pg_get_viewdef('public.leaderboard_sprint_today'::regclass, true)
         like '%duration_sec <= 300%' as today_was_filtered_it_should_not_be;

-- 5. NOTHING WAS DELETED. Every run is still in the table with its real
--    numbers; some of them simply no longer appear on two boards.
--    hidden_runs is how many are filtered out, not how many were lost.
select count(*)                                        as runs_still_stored,
       count(*) filter (where duration_sec <= 300)     as shown_on_boards,
       count(*) filter (where duration_sec >  300)     as hidden_runs,
       sum(puzzles_cleared)                            as cleared_still_stored
  from public.sprint_scores;

-- 6. The board as a player now sees it. Every row is a five-minute run, so
--    the numbers are finally comparable to each other.
select rank, username, puzzles_cleared, best_run, runs, words_found, last_played
  from public.leaderboard_sprint_alltime
 order by rank;

-- 7. And this week.
select rank, username, puzzles_cleared, best_run, runs, words_found
  from public.leaderboard_sprint_week
 order by rank;
