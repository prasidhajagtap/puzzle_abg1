-- ============================================================================
-- Word Vibe - launch check, before opening the game to the general public.
--
-- READ ONLY. It changes nothing: no table, no function, no grant, no row.
-- Safe to run as often as you like.
--
-- THE LAST QUERY IS A CHECKLIST. The SQL editor shows only the last result
-- of a file, so everything is one table: each check, what it should say,
-- what it says, and ok. A row with ok = false is something to look at before
-- launch. Rows marked (info) have no right answer; they are there so you
-- know the numbers, and their ok is left blank.
--
-- The login, reset and sign-up functions were created by the original setup
-- script, which is not in this repo, so their bodies cannot be checked from
-- the code. Checks 6 to 8 read the live function text and look for an
-- attempt limit. They are a heuristic: if one says false, run the query at
-- the very bottom (commented out) and read the function yourself.
-- ============================================================================

with
tbl as (   -- ordinary tables in public
  select c.oid, c.relname, c.relrowsecurity
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p')
),
fn as (    -- functions in public
  select p.oid, p.proname, p.prosecdef, p.proconfig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
),
anon_fn as (
  select proname from fn where has_function_privilege('anon', oid, 'EXECUTE')
),
expected_anon_fn(proname) as (values
  -- the game
  ('login_player'),('register_player'),('resume_session'),('end_session'),
  ('my_stats'),('my_history'),('my_powerups'),('use_powerup'),
  ('submit_score'),('submit_sprint_score'),('reset_pin'),('ack_secret'),
  ('live_custom_themes'),
  -- the admin console (each one checks an admin session token itself)
  ('admin_login'),('admin_logout'),('admin_overview'),('admin_daily'),
  ('admin_players'),('admin_find_player'),('admin_flagged'),('admin_reset_pin'),
  ('admin_segments'),('admin_set_min_build'),('admin_sprint'),('admin_streaks'),
  ('admin_themes'),('admin_custom_theme_save'),('admin_custom_theme_list'),
  ('admin_custom_theme_set_status'),('admin_custom_theme_delete'),
  ('admin_hide_player'),('admin_hidden_players'),
  -- 35_fair_boards: the sign-up name check
  ('name_allowed')
),
first_col_index as (   -- tables with an index whose FIRST column is play_date
  select distinct c.relname
    from pg_index i
    join pg_class c on c.oid = i.indrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid and a.attnum = i.indkey[0]
   where n.nspname = 'public' and a.attname = 'play_date'
),
src as (
  select proname, string_agg(prosrc, ' ') as body from fn
   where proname in ('login_player','reset_pin','register_player')
   group by proname
)
select n as "#", check_name, expected, actual,
       case when check_name like '%(info)' then null else (expected = actual) end as ok
  from (

  select 1 as n, 'tables with row level security OFF' as check_name, 'none' as expected,
         coalesce((select string_agg(relname, ', ' order by relname) from tbl where not relrowsecurity), 'none') as actual

  union all
  select 2, 'tables the public key can read or write directly', 'none',
         coalesce((select string_agg(relname, ', ' order by relname) from tbl
                    where has_table_privilege('anon', oid, 'SELECT')
                       or has_table_privilege('anon', oid, 'INSERT')
                       or has_table_privilege('anon', oid, 'UPDATE')
                       or has_table_privilege('anon', oid, 'DELETE')), 'none')

  union all
  select 3, 'views the public key can read (the 6 leaderboards)', '6',
         (select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('v','m')
             and has_table_privilege('anon', c.oid, 'SELECT'))

  union all
  select 4, 'functions the public key can call that are NOT on the expected list', 'none',
         coalesce((select string_agg(distinct proname, ', ') from anon_fn
                    where proname not in (select proname from expected_anon_fn)), 'none')

  union all
  select 5, 'SECURITY DEFINER functions without a fixed search_path', 'none',
         coalesce((select string_agg(distinct proname, ', ') from fn
                    where prosecdef and not exists (
                      select 1 from unnest(coalesce(proconfig, '{}')) s where s like 'search_path=%')), 'none')

  union all
  select 6, 'login_player limits wrong PIN attempts', 'true',
         coalesce((select (body ~* 'lock')::text from src where proname = 'login_player'), 'function missing')

  union all
  select 7, 'reset_pin limits wrong attempts', 'true',
         coalesce((select (body ~* '(lock|attempt|fail)')::text from src where proname = 'reset_pin'), 'function missing')

  union all
  select 8, 'register_player has any rate limit (info)', 'true',
         coalesce((select (body ~* '(interval|rate|too many|limit)')::text from src where proname = 'register_player'), 'function missing')

  union all
  select 9, 'functions that exist in more than one version', 'none',
         coalesce((select string_agg(proname, ', ') from (
                    select proname from fn group by proname having count(*) > 1) d), 'none')

  union all
  select 10, 'scores has an index starting with play_date', 'true',
         (exists (select 1 from first_col_index where relname = 'scores'))::text

  union all
  select 11, 'sprint_scores has an index starting with play_date', 'true',
         (exists (select 1 from first_col_index where relname = 'sprint_scores'))::text

  union all
  select 12, 'database size, free plan allows 500 MB', 'under 400 MB',
         case when pg_database_size(current_database()) < 400 * 1024 * 1024
              then 'under 400 MB' else pg_size_pretty(pg_database_size(current_database())) end

  union all
  select 13, 'database size (info)', pg_size_pretty(pg_database_size(current_database())),
         pg_size_pretty(pg_database_size(current_database()))

  union all
  select 14, 'players / scores / sprint runs / sessions (info)', 'numbers',
         (select count(*) from public.players)::text || ' / ' ||
         (select count(*) from public.scores)::text || ' / ' ||
         (select count(*) from public.sprint_scores)::text || ' / ' ||
         (select count(*) from public.sessions)::text

  union all
  select 15, 'flagged scores on today''s public board (info)', '0',
         (select count(*)::text from public.scores
           where play_date = current_date and flagged)

) c
order by n;

-- If check 6, 7 or 8 says false, read the function itself (one at a time):
-- select pg_get_functiondef('public.reset_pin'::regproc);
