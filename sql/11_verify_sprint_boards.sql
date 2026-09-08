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

-- 4. Do the two "this week" windows agree? The daily view was read out of the
--    database and uses a calendar week starting Monday; 10 copies that. This
--    asserts it rather than trusting the comment. Expect true, true.
select
  pg_get_viewdef('public.leaderboard_week'::regclass, true)
    like '%date_trunc(''week''%'                        as daily_uses_calendar_week,
  pg_get_viewdef('public.leaderboard_sprint_week'::regclass, true)
    like '%date_trunc(''week''%'                        as sprint_uses_calendar_week;

-- 5. The same thing by eye, if you would rather look than trust a LIKE.
select 'daily'  as board, pg_get_viewdef('public.leaderboard_week'::regclass, true)        as definition
union all
select 'sprint',          pg_get_viewdef('public.leaderboard_sprint_week'::regclass, true);

-- 6. How many sprint rows fall inside the week window, and in total.
select 'sprint rows this week' as which, count(*) as rows
  from public.sprint_scores
 where play_date >= date_trunc('week', current_date)::date
union all
select 'sprint rows all time', count(*) from public.sprint_scores;
