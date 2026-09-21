-- ============================================================================
-- Undo 26_fix_resume_session_overload.sql.
--
-- READ THIS BEFORE RUNNING IT. Restoring the one-argument overload restores
-- the fault: every p_token-only call goes back to HTTP 300 PGRST203, because
-- two candidates match again. There is no version of this database where
-- having both is better than having one.
--
-- It is here only because a removal should always have a stated way back, and
-- because the body below is a faithful delegate rather than a guess: it calls
-- the three-argument function with its defaults, which is exactly what the
-- surviving function does for a one-argument call anyway.
--
-- If you are reaching for this because something broke, the likelier cause is
-- that the three-argument function does not actually default p_build and
-- p_agent — in which case run PART A of 26 and read A1 again.
-- ============================================================================

create or replace function public.resume_session(p_token uuid)
returns json language sql volatile security definer
set search_path to 'public','extensions','pg_catalog'
as $function$
  select public.resume_session(p_token, null::integer, null::text);
$function$;

grant execute on function public.resume_session(uuid) to anon;
