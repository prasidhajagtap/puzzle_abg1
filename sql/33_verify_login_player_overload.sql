-- ============================================================================
-- Verify 32. Run after it. All read-only.
-- ============================================================================

-- V1. Exactly ONE login_player must remain, with 4 arguments and 2 defaults.
select p.oid::regprocedure as signature, p.pronargs, p.pronargdefaults,
       case when count(*) over () = 1 and p.pronargs = 4 and p.pronargdefaults = 2
            then 'PASS' else 'FAIL — expected one 4-argument function with 2 defaults' end as verdict
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname='login_player';

-- V2. anon can still execute it. FALSE here means NOBODY CAN SIGN IN.
select has_function_privilege('anon',
  'public.login_player(text,text,integer,text)', 'EXECUTE') as anon_can_sign_in;

-- V3. The whole-schema sweep again. This is the one that found login_player.
--     After 26, 30 and 32 it should return NO ROWS. Any row here is another
--     duplicated function waiting to break a client that calls the short form.
select n.nspname||'.'||p.proname as fn, count(*) as versions,
       string_agg(p.pronargs::text, ' and ' order by p.pronargs) as arg_counts
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f'
 group by 1 having count(*) > 1
 order by 1;
