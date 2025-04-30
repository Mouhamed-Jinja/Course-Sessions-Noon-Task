WITH 
  -- 1. Base view
  raw AS (
    SELECT * 
    FROM "LZ".fallaged_dq_issues
  ),

  -- 2. Filter out missing/value issues and planned sessions
  filtered AS (
    SELECT *
    FROM raw
    WHERE NOT dq_issue_missing_values
      AND course_session_status <> 'planned'
  ),

  -- 3. Compute global average teaching_time for replacement
  avg_tt AS (
    SELECT ceil(AVG(teaching_time)) AS avg_teaching_time
    FROM filtered
    WHERE NOT dq_issue_teaching_time_outlier
  ),

  -- 4. Replace outliers with the average
  replaced AS (
    SELECT
      f.*,
      CASE
        WHEN f.dq_issue_teaching_time_outlier
        THEN at.avg_teaching_time
        ELSE f.teaching_time
      END AS final_teaching_time
    FROM filtered f
    CROSS JOIN avg_tt at
  ),

  -- 5. Deduplicate: keep only the latest by created_at
  deduped AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY course_session_id 
        ORDER BY created_at DESC
      ) AS rn
    FROM replaced
  )

-- 6. Final output
SELECT
  course_session_id,
  course_id,
  course_session_name,
  course_session_type,
  course_teacher_id,
  course_session_scheduled_start_time,
  course_session_scheduled_end_time,
  teacher_start_time,
  teacher_end_time,
  final_teaching_time   AS teaching_time,
  course_session_status,
  created_at
FROM deduped
WHERE rn = 1
ORDER BY course_session_id;
