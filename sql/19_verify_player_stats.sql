-- ============================================================================
-- Verify 18_player_stats.sql. READS ONLY.
-- ============================================================================

-- 1. All three functions exist and none of them can write. STABLE and
--    IMMUTABLE are both enforced by Postgres, so this is the guarantee
--    rather than a promise in a comment.
--    Expect three rows, cannot_write true on every one.
select p.proname, pg_get_function_arguments(p.oid) as arguments,
       p.prosecdef                     as security_definer,
       p.provolatile in ('s','i')      as cannot_write
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public'
   and p.proname in ('my_stats','dn_streak','dn_workday_no')
 order by p.proname;

-- 1b. THE ONE TO ACTUALLY READ. The two helpers must not be callable by the
--     browser, and the first version of 18 failed this: it revoked EXECUTE
--     from PUBLIC only, while Supabase separately grants it to anon and
--     authenticated, so both helpers stayed open. Caught by calling
--     /rest/v1/rpc/dn_workday_no with the public anon key and getting a 200.
--
--     Expect all four false. If any is true, 18 has not been re-run since
--     that was fixed.
select has_function_privilege('anon','public.dn_streak(text,date)','EXECUTE')           as anon_dn_streak,
       has_function_privilege('anon','public.dn_workday_no(date)','EXECUTE')            as anon_workday_no,
       has_function_privilege('authenticated','public.dn_streak(text,date)','EXECUTE')  as auth_dn_streak,
       has_function_privilege('authenticated','public.dn_workday_no(date)','EXECUTE')   as auth_workday_no;

-- 1d. And my_stats, the one that IS meant to be callable. Expect true.
select has_function_privilege('anon','public.my_stats(uuid)','EXECUTE') as anon_can_call_my_stats;

-- 1c. Friday and the Monday after it must be adjacent, and the weekend must
--     collapse onto Friday. Expect Fri/Sat/Sun to share a number and Monday
--     to be exactly one higher.
select d::date, to_char(d,'Dy') as day, public.dn_workday_no(d::date) as workday_no
  from generate_series(date '2026-09-11', date '2026-09-14', interval '1 day') d;

-- 2. The browser role can call it. Expect true.
select has_function_privilege('anon','public.my_stats(uuid)','EXECUTE') as anon_can_call;

-- 3. It must still be shut out of the tables underneath. Expect four falses.
select has_table_privilege('anon','public.scores','SELECT')        as anon_reads_scores,
       has_table_privilege('anon','public.players','SELECT')       as anon_reads_players,
       has_table_privilege('anon','public.sessions','SELECT')      as anon_reads_sessions,
       has_table_privilege('anon','public.sprint_scores','SELECT') as anon_reads_sprint;

-- 4. A bad token gets nothing. Expect {"ok": false, "error": "NO_SESSION"}.
select public.my_stats('00000000-0000-0000-0000-000000000000'::uuid) as must_refuse;

-- 5. Nothing about scoring moved. This file adds a function and touches no
--    other object, so this is here to prove that rather than assume it.
--    Expect three trues, and flag_line = 10.
select
  pg_get_functiondef(p.oid) like '%v_total := v_words + v_time + v_streak%' as total_unchanged,
  pg_get_functiondef(p.oid) like '%v_words := p_words_found * 10%'          as word_points_unchanged,
  pg_get_functiondef(p.oid) like '%greatest(0, v_budget - p_time_sec)%'     as time_points_unchanged,
  case when pg_get_functiondef(p.oid) like '%p_time_sec < 10%' then 10
       when pg_get_functiondef(p.oid) like '%p_time_sec < 20%' then 20 end  as flag_line
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='submit_score';

-- 6. What the streak looks like across your real players. This is the number
--    the banner will show them, so it is worth eyeballing once.
--
--    It counts WORKING days: a weekend neither counts nor breaks a run. The
--    first version of 18 counted strict calendar days and reported 2 for a
--    player who had turned up on 18 of 19 working days, which is why it was
--    changed. It is still NOT the +5 bonus — see the note at the top of 18.
--
--    days_played counts every day including weekends, so a player who plays
--    at the weekend can show more days_played than their streak. That is
--    correct, not a discrepancy.
select p.username,
       count(distinct s.play_date)                     as days_played,
       max(s.play_date)                                as last_played,
       count(distinct s.play_date) filter (
              where extract(isodow from s.play_date) < 6)  as working_days_played,
       public.dn_streak(p.poornata_id, current_date)       as streak_days
  from public.players p
  join public.scores s using (poornata_id)
 group by p.poornata_id, p.username
 order by streak_days desc, days_played desc;
