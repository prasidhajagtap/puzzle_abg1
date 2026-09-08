-- ============================================================================
-- Verify 10_sprint_week_and_alltime.sql. Reads only.
-- ============================================================================

-- 1. Both views exist and anon can read them. Expect two rows, both true.
select c.relname                                   as view_name,
       has_table_privilege('anon', c.oid,'SELECT') as anon_can_read
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public'
   and c.relname in ('leaderboard_sprint_week','leaderboard_sprint_alltime')
 order by c.relname;

-- 2. The table underneath must stay shut to anon. Expect false, false.
select has_table_privilege('anon','public.sprint_scores','SELECT') as anon_reads_table,
       has_table_privilege('anon','public.sprint_scores','INSERT') as anon_writes_table;

-- 3. What the two new boards actually return.
select * from public.leaderboard_sprint_week    order by rank limit 20;
select * from public.leaderboard_sprint_alltime order by rank limit 20;

-- 4. Does the week window match the daily one? Compare these two counts for
--    the same player set. If daily counts a day that sprint does not (or the
--    other way round), the windows disagree and the WINDOW line in 10 needs
--    changing. Paste the output back if the numbers look odd.
select 'sprint rows in window' as which, count(*) as rows
  from public.sprint_scores
 where play_date >= current_date - 6 and play_date <= current_date
union all
select 'sprint rows all time', count(*) from public.sprint_scores;

-- 5. The daily week view's definition, so the two windows can be compared
--    directly. This is the one thing I could not read from outside.
select pg_get_viewdef('public.leaderboard_week'::regclass, true) as daily_week_definition;
