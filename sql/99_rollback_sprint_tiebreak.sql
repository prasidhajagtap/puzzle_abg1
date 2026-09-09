-- ============================================================================
-- Undo 20_sprint_tiebreak.sql — the sprint week and all-time boards go back to
-- deciding a tie on words found rather than on the best run.
--
-- These are the live definitions, read out of the database with
-- pg_get_viewdef on 9 September 2026 and pasted here unedited. They are not a
-- reconstruction. Note the key order: sum(words_found) BEFORE
-- max(puzzles_cleared), which is exactly what 20 swaps.
--
-- Both are "create or replace", so no grant is lost and nothing else needs
-- reissuing. Nothing here touches a score.
-- ============================================================================

create or replace view public.leaderboard_sprint_week as
 SELECT rank() OVER (ORDER BY (sum(s.puzzles_cleared)) DESC, (sum(s.words_found)) DESC, (max(s.puzzles_cleared)) DESC) AS rank,
    p.username,
    sum(s.puzzles_cleared)::integer AS puzzles_cleared,
    sum(s.words_found)::integer AS words_found,
    count(*)::integer AS runs,
    max(s.puzzles_cleared) AS best_run,
    bool_or(s.flagged) AS flagged
   FROM sprint_scores s
     JOIN players p USING (poornata_id)
  WHERE s.play_date >= date_trunc('week'::text, CURRENT_DATE::timestamp with time zone)::date
  GROUP BY p.username
  ORDER BY (rank() OVER (ORDER BY (sum(s.puzzles_cleared)) DESC, (sum(s.words_found)) DESC, (max(s.puzzles_cleared)) DESC))
 LIMIT 100;

create or replace view public.leaderboard_sprint_alltime as
 SELECT rank() OVER (ORDER BY (sum(s.puzzles_cleared)) DESC, (sum(s.words_found)) DESC, (max(s.puzzles_cleared)) DESC) AS rank,
    p.username,
    sum(s.puzzles_cleared)::integer AS puzzles_cleared,
    sum(s.words_found)::integer AS words_found,
    count(*)::integer AS runs,
    max(s.puzzles_cleared) AS best_run,
    max(s.play_date) AS last_played,
    bool_or(s.flagged) AS flagged
   FROM sprint_scores s
     JOIN players p USING (poornata_id)
  GROUP BY p.username
  ORDER BY (rank() OVER (ORDER BY (sum(s.puzzles_cleared)) DESC, (sum(s.words_found)) DESC, (max(s.puzzles_cleared)) DESC))
 LIMIT 100;

grant select on public.leaderboard_sprint_week    to anon;
grant select on public.leaderboard_sprint_alltime to anon;
