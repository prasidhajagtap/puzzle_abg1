-- ============================================================================
-- Verify 26_fix_resume_session_overload.sql. READS ONLY.
-- ============================================================================

-- 1. Exactly ONE resume_session should remain, the three-argument one, with
--    two of its three arguments defaulted. Expect a single row.
select p.oid::regprocedure              as signature,
       pg_get_function_arguments(p.oid) as arguments,
       p.pronargs                       as arg_count,
       p.pronargdefaults                as args_with_defaults,
       p.prosecdef                      as security_definer
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'resume_session';

-- 2. The browser can still call it. Expect true.
select has_function_privilege('anon','public.resume_session(uuid,integer,text)','EXECUTE')
         as anon_can_call;

-- 3. Postgres itself now resolves a one-argument call. This is the whole fix:
--    before the drop this raised "function is not unique".
--    Expect {"ok": false, "error": "NO_SESSION"} — a clean refusal, not an error.
select public.resume_session('00000000-0000-0000-0000-000000000000'::uuid) as one_arg_call;

-- 4. And the three-argument call the current client makes still behaves.
--    Expect the same clean refusal.
select public.resume_session('00000000-0000-0000-0000-000000000000'::uuid, 27, 'verify')
         as three_arg_call;

-- 5. Nothing else moved. No score, no session, no player was touched by a
--    function drop, but this is here to show it rather than say it.
select (select count(*) from public.scores)         as scores,
       (select count(*) from public.sprint_scores)  as sprint_scores,
       (select count(*) from public.players)        as players,
       (select count(*) from public.sessions)       as live_sessions;
