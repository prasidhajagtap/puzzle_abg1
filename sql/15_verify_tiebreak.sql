-- ============================================================================
-- Verify 14_score_tiebreak.sql. READS ONLY.
-- The point of these checks is to prove nothing was disturbed, not just that
-- the new thing exists.
-- ============================================================================

-- 1. The column is there, nullable, and needs no default. Expect YES / null.
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema='public' and table_name='scores' and column_name='time_ms';

-- 2. The function takes the new argument AND still has its old defaults, so a
--    caller that omits p_time_ms still resolves. Expect the full arg list with
--    "DEFAULT 1" and "DEFAULT NULL" showing.
select pg_get_function_arguments(p.oid) as arguments,
       p.prosecdef                      as still_security_definer
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='submit_score';

-- 3. NOTHING ABOUT SCORING MOVED. All three must be true.
select
  pg_get_functiondef(p.oid) like '%v_words := p_words_found * 10%'          as word_points_unchanged,
  pg_get_functiondef(p.oid) like '%greatest(0, v_budget - p_time_sec)%'     as time_points_unchanged,
  pg_get_functiondef(p.oid) like '%v_total := v_words + v_time + v_streak%' as total_unchanged
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='submit_score';

-- 4. time_ms must not appear anywhere in the scoring maths — only in the
--    clamp and the insert. Expect false.
select pg_get_functiondef(p.oid) like '%v_total%p_time_ms%'
    or pg_get_functiondef(p.oid) like '%v_time%:=%p_time_ms%' as time_ms_leaked_into_scoring
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='submit_score';

-- 5. Every existing row still holds the score it held before, and the formula
--    still explains it. Expect 0 mismatches, and every old row null.
select count(*)                                          as rows_total,
       count(time_ms)                                    as rows_with_ms,
       count(*) filter (where time_ms is null)           as rows_without_ms,
       count(*) filter (
         where total_points <> word_points + time_points + streak_bonus
       )                                                 as formula_mismatches
  from public.scores;

-- 6. The 10-second flag from 08 is still in place. Expect 10 and false.
select
  case when pg_get_functiondef(p.oid) like '%p_time_sec < 10%' then 10
       when pg_get_functiondef(p.oid) like '%p_time_sec < 20%' then 20 end as flag_line,
  pg_get_functiondef(p.oid) like '%p_time_sec < 20%'                       as old_flag_back
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='submit_score';

-- 7. The table is still shut to the browser role. Expect false, false.
select has_table_privilege('anon','public.scores','SELECT') as anon_reads,
       has_table_privilege('anon','public.scores','INSERT') as anon_writes;

-- 8. For step two: the three daily view definitions. Send these back and the
--    ranking half can be written without guessing.
select table_name, pg_get_viewdef(('public.'||table_name)::regclass, true) as definition
  from information_schema.views
 where table_schema='public' and table_name like 'leaderboard%'
 order by table_name;
