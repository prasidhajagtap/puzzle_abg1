-- ============================================================================
-- Verify 18_player_stats.sql. READS ONLY.
-- ============================================================================

-- 1. The function exists, is SECURITY DEFINER, and is declared STABLE — a
--    stable function cannot write, so this is the guarantee, not a promise.
--    Expect: my_stats | p_token uuid | t | t
select p.proname, pg_get_function_arguments(p.oid) as arguments,
       p.prosecdef                as security_definer,
       p.provolatile = 's'        as declared_stable_so_it_cannot_write
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname='my_stats';

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
--    streak_days counts STRICTLY CONSECUTIVE days and is not the +5 bonus —
--    see the note at the top of 18 for why those are deliberately different.
select p.username,
       count(distinct s.play_date)                     as days_played,
       max(s.play_date)                                as last_played,
       (select count(*)
          from (select d.play_date,
                       row_number() over (order by d.play_date desc) as rn
                  from (select distinct play_date from public.scores
                         where poornata_id = p.poornata_id
                           and play_date <= case when exists (
                                 select 1 from public.scores
                                  where poornata_id = p.poornata_id
                                    and play_date = current_date)
                               then current_date else current_date - 1 end) d) t
         where t.play_date = (case when exists (
                 select 1 from public.scores
                  where poornata_id = p.poornata_id and play_date = current_date)
               then current_date else current_date - 1 end) - (t.rn - 1)::int
       )                                               as streak_days
  from public.players p
  join public.scores s using (poornata_id)
 group by p.poornata_id, p.username
 order by streak_days desc, days_played desc;
