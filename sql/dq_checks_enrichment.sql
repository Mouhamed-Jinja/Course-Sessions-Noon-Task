CREATE OR REPLACE VIEW fallaged_dq_issues AS
WITH
  SourceData AS (
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
      teaching_time,                       
      course_session_status,               
      created_at                           
    FROM "LZ"."sessions_raw"
  ),

  FlaggedDeDup AS (
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
      teaching_time,
      course_session_status,
      created_at,
      -- flag duplicate session IDs
      (COUNT(*) OVER (PARTITION BY course_session_id) > 1) AS dq_issue_dedup
    FROM SourceData
  ),

  Stats AS (
    SELECT
      PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY teaching_time) AS q1,
      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY teaching_time) AS q3
    FROM FlaggedDeDup
  ),

  finalV AS (
    SELECT
      caf.course_session_id,
      caf.course_id,
      caf.course_session_name,
      caf.course_session_type,
      caf.course_teacher_id,
      caf.course_session_scheduled_start_time,
      caf.course_session_scheduled_end_time,
      caf.teacher_start_time,
      caf.teacher_end_time,
      caf.teaching_time,
      caf.course_session_status,
      caf.created_at,

      caf.dq_issue_dedup,

      -- IQR‐based outlier flag
      CASE
        WHEN caf.teaching_time IS NOT NULL
         AND (
              caf.teaching_time <  (s.q1 - 1.5 * (s.q3 - s.q1))
           OR caf.teaching_time >  (s.q3 + 1.5 * (s.q3 - s.q1))
         )
        THEN TRUE
        ELSE FALSE
      END AS dq_issue_teaching_time_outlier,

      -- missing‐value flag
      CASE
        WHEN caf.course_session_type                IS NULL
          OR caf.course_teacher_id                  IS NULL
          OR caf.course_session_scheduled_start_time IS NULL
          OR caf.course_session_scheduled_end_time   IS NULL
          OR caf.teacher_start_time                 IS NULL
          OR caf.teacher_end_time                   IS NULL
          OR caf.teaching_time                      IS NULL
        THEN TRUE
        ELSE FALSE
      END AS dq_issue_missing_values,

      -- Difference in minutes: actual start vs. scheduled start
      EXTRACT(
        EPOCH 
          FROM (caf.teacher_start_time - caf.course_session_scheduled_start_time)
      ) / 60 AS diff_start_minutes,

      -- Difference in minutes: actual end vs. scheduled end
      EXTRACT(
        EPOCH 
          FROM (caf.teacher_end_time - caf.course_session_scheduled_end_time)
      ) / 60 AS diff_end_minutes

    FROM FlaggedDeDup caf
    CROSS JOIN Stats s
  )

SELECT *
FROM finalV;


-- Example: pull only the problematic rows, now including the two new diff columns
SELECT *
FROM fallaged_dq_issues
WHERE dq_issue_missing_values
   OR dq_issue_dedup
   OR dq_issue_teaching_time_outlier
ORDER BY course_session_id;
