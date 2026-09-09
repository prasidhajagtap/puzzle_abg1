-- ============================================================================
-- Verify 24_streak_every_day_counts.sql. READS ONLY.
-- ============================================================================

-- 1. Both functions exist and neither can write. STABLE is enforced by
--    Postgres, so this is the guarantee rather than a promise in a comment.
--    Expect two rows, cannot_write true on both, my_stats SECURITY DEFINER.
select p.proname, pg_get_function_arguments(p.oid) as arguments,
       p.prosecdef                as security_definer,
       p.provolatile in ('s','i') as cannot_write
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname in ('my_stats','dn_streak')
 order by p.proname;

-- 2. dn_workday_no is gone — the new rule never needs Friday and Monday to be
--    adjacent. Expect 0.
select count(*) as workday_no_should_be_gone
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='dn_workday_no';

-- 3. THE ONE TO READ. The helper must not be callable by the browser.
--    Revoking from PUBLIC alone is not enough on Supabase — it grants EXECUTE
--    to anon and authenticated separately, and an earlier version of 18 was
--    caught by exactly that. Expect false, false. my_stats expect true.
select has_function_privilege('anon','public.dn_streak(text,date)','EXECUTE')          as anon_dn_streak,
       has_function_privilege('authenticated','public.dn_streak(text,date)','EXECUTE') as auth_dn_streak,
       has_function_privilege('anon','public.my_stats(uuid)','EXECUTE')                as anon_my_stats;

-- 4. The tables stay shut. Expect four falses.
select has_table_privilege('anon','public.scores','SELECT')        as anon_scores,
       has_table_privilege('anon','public.players','SELECT')       as anon_players,
       has_table_privilege('anon','public.sessions','SELECT')      as anon_sessions,
       has_table_privilege('anon','public.sprint_scores','SELECT') as anon_sprint;

-- 5. A bad token gets nothing. Expect {"ok": false, "error": "NO_SESSION"}.
select public.my_stats('00000000-0000-0000-0000-000000000000'::uuid) as must_refuse;

-- 6. NO SCORE MOVED. This file adds no column and touches no table, so this is
--    here to prove that rather than assume it. Expect 0 mismatches.
select count(*) as rows_total,
       count(*) filter (
         where total_points <> word_points + time_points + streak_bonus
       )        as formula_mismatches
  from public.scores;

-- 7. The +5 bonus is untouched and is still a different rule from the streak.
--    Expect true (the 48-hour window is still there) and flag_line 10.
select
  pg_get_functiondef(p.oid) like '%play_date >= current_date - 2%'          as bonus_window_unchanged,
  pg_get_functiondef(p.oid) like '%v_total := v_words + v_time + v_streak%' as scoring_unchanged,
  case when pg_get_functiondef(p.oid) like '%p_time_sec < 10%' then 10
       when pg_get_functiondef(p.oid) like '%p_time_sec < 20%' then 20 end  as flag_line
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='submit_score';

-- 8. THE INTERESTING ONE. Every player's streak under the new rule.
--
--    Expect these to be SMALL. Consecutive calendar days is the strictest of
--    the rules this game has tried: a single missed day of any kind, weekend
--    included, ends a run. Measured before the change, nobody in the player
--    base held more than 2. That is the trade — the number is small and it is
--    unambiguous.
--
--    days_played counts every game ever, so it will usually be much larger
--    than the streak. That is correct, not a discrepancy.
select p.username,
       count(distinct s.play_date)                                        as days_played,
       count(distinct s.play_date) filter (
              where extract(isodow from s.play_date) >= 6)                as weekend_games,
       public.dn_streak(p.poornata_id, current_date)                      as streak_now,
       max(s.play_date)                                                   as last_played
  from public.players p
  join public.scores s using (poornata_id)
 group by p.poornata_id, p.username
 order by streak_now desc, days_played desc;
