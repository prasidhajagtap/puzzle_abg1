-- ============================================================================
-- Rollback for 30.
--
-- There is nothing to put back. 30 drops a function that could never be
-- reached unambiguously through PostgREST, and the function that remains
-- answers every call the dropped one did, because p_time_ms defaults to null.
--
-- If the eight-argument version is genuinely wanted again, it must be
-- recreated from its original body — take it from a backup, not from here.
-- Writing it out from memory is how the two drifted apart in the first place.
--
-- The only thing worth restating is the grant, in case it was disturbed:
-- ============================================================================
grant execute on function public.submit_score(
  uuid, text, integer, integer, integer, integer, boolean, integer, integer)
  to anon, authenticated;
