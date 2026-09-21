-- ============================================================================
-- The Daily Nine — remove the duplicate resume_session so old clients can
-- resume again.
--
-- THE FAULT. Two functions share the name:
--     public.resume_session(p_token uuid)
--     public.resume_session(p_token uuid, p_build integer, p_agent text)
--
-- PostgREST resolves a function by its parameter NAMES. A call carrying only
-- p_token matches BOTH, so it cannot choose, and answers:
--     HTTP 300  PGRST203  "Could not choose the best candidate function
--               between: public.resume_session(p_token => uuid),
--               public.resume_session(p_token => uuid, p_build => integer,
--               p_agent => text)"
-- Verified against the live API on 21 September 2026.
--
-- WHO THIS HITS. The client started sending p_build and p_agent on 28 August
-- (telemetry: which build each player is on). Anything older sends p_token
-- alone and gets the 300. rpc() treats any non-2xx as a throw, and the caller
-- catches it as "offline: fall through and play locally" — so such a player
-- silently keeps a stale session: no streak refresh, no played-today state,
-- and honourMinBuild() never runs, which is the lever for forcing an update.
-- The separate version check still pulls them to the current build on the same
-- load, so it self-heals; it should still not be broken in the first place.
--
-- WHY THIS NEEDS NO FUNCTION BODY, which is the point worth reading.
-- PostgREST only offered the THREE-argument version as a candidate for a
-- one-argument call. It could only do that if p_build and p_agent already
-- carry defaults. So the three-argument version can already serve every call
-- the one-argument version serves — and since every p_token-only call is
-- ambiguous, the one-argument version is currently UNREACHABLE through the
-- API. It is dead weight that breaks its own sibling.
--
-- Dropping it therefore needs nothing rewritten and nothing guessed: the
-- remaining function keeps its exact body, and a p_token-only call starts
-- resolving to it with p_build and p_agent null.
--
-- WHAT DOES NOT CHANGE. The current client sends all three arguments and has
-- always resolved correctly; it is untouched. No score, no session, no table.
--
-- PART A reads and proves the above. PART B drops. Run A first.
-- Rollback: 99_rollback_resume_overload.sql — and read its warning.
-- Verify: 27_verify_resume_session.sql
-- ============================================================================


-- ===========================================================================
-- PART A — READ ONLY. Confirm the picture before changing anything.
-- ===========================================================================

-- A1. Both signatures, and whether each argument has a default.
--     EXPECT two rows. The three-argument row must show "DEFAULT" against
--     p_build and p_agent. If it does NOT, stop: PART B would break the
--     one-argument callers instead of fixing them, and the proper fix is then
--     to re-create the three-argument version with defaults, which does need
--     its body.
select p.oid::regprocedure                    as signature,
       pg_get_function_arguments(p.oid)       as arguments,
       p.pronargs                             as arg_count,
       p.pronargdefaults                      as args_with_defaults,
       p.prosecdef                            as security_definer
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'resume_session'
 order by p.pronargs;

-- A2. Does anything inside the database call the one-argument version?
--     EXPECT zero rows. A function body mentioning "resume_session(" with a
--     single argument would be a reason not to drop it.
select p.proname as calling_function,
       n.nspname as schema
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   -- prokind 'f' is a plain function. Without this the query dies on the
   -- first aggregate it meets: pg_get_functiondef() refuses aggregates and
   -- window functions, and it fails the whole statement rather than the row.
   and p.prokind = 'f'
   and p.proname <> 'resume_session'
   and pg_get_functiondef(p.oid) ~* 'resume_session\s*\('
 order by 1;

-- A3. Who can execute each one today, so the grant can be compared after.
select p.oid::regprocedure                                        as signature,
       has_function_privilege('anon', p.oid, 'EXECUTE')           as anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE')  as authenticated
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'resume_session'
 order by p.pronargs;


-- ===========================================================================
-- PART B — the change. One statement.
--
-- The signature is spelled out so this can only ever remove the one-argument
-- version. "drop function resume_session" without an argument list would be
-- ambiguous and Postgres would refuse it, which is the behaviour we want.
-- ===========================================================================

drop function if exists public.resume_session(uuid);

-- The surviving three-argument function is untouched: same body, same grants,
-- same behaviour for the current client. It simply becomes the only candidate,
-- so a p_token-only call now resolves to it instead of failing.
