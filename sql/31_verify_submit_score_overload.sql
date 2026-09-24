-- ============================================================================
-- Verify 30. Run after it. Three checks, all read-only.
-- ============================================================================

-- V1. Exactly ONE submit_score must remain, with 9 arguments and 2 defaults.
select p.oid::regprocedure as signature, p.pronargs, p.pronargdefaults,
       case when count(*) over () = 1 and p.pronargs = 9
            then 'PASS' else 'FAIL — expected one 9-argument function' end as verdict
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname='submit_score';

-- V2. anon can still execute it. FALSE here means nobody can submit a score.
select has_function_privilege('anon',
  'public.submit_score(uuid,text,integer,integer,integer,integer,boolean,integer,integer)',
  'EXECUTE') as anon_can_submit;

-- V3. Nothing else in the schema carries the same fault. Any row returned
--     here is another duplicated overload waiting to do what this one did.
select n.nspname||'.'||p.proname as fn, count(*) as versions,
       string_agg(p.pronargs::text, ' and ' order by p.pronargs) as arg_counts
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prokind = 'f'
 group by 1 having count(*) > 1
 order by 1;
