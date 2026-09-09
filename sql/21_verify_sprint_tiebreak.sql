-- ============================================================================
-- Verify 20_sprint_tiebreak.sql. READS ONLY.
-- ============================================================================

-- 1. Both boards still exist, still readable by the browser, and their column
--    lists are unchanged — the game reads fields by name, so that is the
--    contract. Expect two rows, anon_can_read true.
select table_name,
       has_table_privilege('anon', ('public.'||table_name)::regclass,'SELECT') as anon_can_read,
       (select string_agg(column_name, ', ' order by ordinal_position)
          from information_schema.columns c
         where c.table_schema='public' and c.table_name=v.table_name)          as columns
  from information_schema.views v
 where table_schema='public'
   and table_name in ('leaderboard_sprint_week','leaderboard_sprint_alltime')
 order by table_name;

-- 2. The keys really did swap. In the new definition max(puzzles_cleared) must
--    appear BEFORE sum(words_found) inside the ORDER BY.
--    Expect true for both.
select table_name,
       strpos(pg_get_viewdef(('public.'||table_name)::regclass, true), 'max(s.puzzles_cleared)) DESC')
         < strpos(pg_get_viewdef(('public.'||table_name)::regclass, true), 'sum(s.words_found)) DESC')
         as best_run_now_outranks_words
  from information_schema.views
 where table_schema='public'
   and table_name in ('leaderboard_sprint_week','leaderboard_sprint_alltime')
 order by table_name;

-- 3. leaderboard_sprint_today must NOT have been touched. It holds one row per
--    player per day, so it has no best run to rank on. Expect false.
select pg_get_viewdef('public.leaderboard_sprint_today'::regclass, true)
         like '%max(s.puzzles_cleared)%' as today_was_changed_it_should_not_be;

-- 4. NO SCORE MOVED. A view cannot write, so this is really asking whether
--    anything else went near the table. Expect the same totals as before.
select count(*)                as sprint_rows,
       sum(puzzles_cleared)    as total_cleared,
       sum(words_found)        as total_words,
       count(*) filter (where scoring_version = 1) as ten_minute_runs,
       count(*) filter (where scoring_version = 2) as five_minute_runs
  from public.sprint_scores;

-- 5. THE ONE TO LOOK AT. The all-time board as it now stands, with the numbers
--    the tie is decided on. Read it as: for two players on the same
--    puzzles_cleared, the one with the higher best_run must come first.
select rank, username, puzzles_cleared, best_run, runs, words_found, last_played
  from public.leaderboard_sprint_alltime
 order by rank;

-- 6. And the same board scored by RATE rather than total, which is the fair
--    comparison across the two clocks. This changes nothing — it is here to
--    inform the still-open question of what to do about the ten-minute runs
--    that predate 12_sprint_five_minutes.
select p.username, s.play_date, s.scoring_version,
       case s.scoring_version when 1 then '10-minute clock'
                              when 2 then '5-minute clock' end   as era,
       s.puzzles_cleared, s.duration_sec,
       round(s.puzzles_cleared::numeric / nullif(s.duration_sec,0) * 60, 2) as puzzles_per_minute
  from public.sprint_scores s
  join public.players p using (poornata_id)
 order by puzzles_per_minute desc nulls last;
