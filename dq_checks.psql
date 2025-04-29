-- SQL Dialect: PostgreSQL
-- Final adjusted query with IQR-based outlier logic on teaching_time
-- and a missing-value DQ flag

WITH SourceData AS (
    -- Step 0: Select all columns from the source table.
    SELECT 
        course_session_id,                   -- int8
        course_id,                           -- int8
        course_session_name,                 -- text
        course_session_type,                 -- text
        course_teacher_id,                   -- float8
        course_session_scheduled_start_time, -- timestamp
        course_session_scheduled_end_time,   -- timestamp
        teacher_start_time,                  -- timestamp
        teacher_end_time,                    -- timestamp
        teaching_time,                       -- int8
        course_session_status,               -- text
        created_at                           -- timestamp
    FROM "LZ"."sessions_raw"
),

CorrectedAndFlagged AS (
    -- Step 1: Apply corrections and add DQ flag for duplicate IDs
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
        teaching_time               AS original_teaching_time,
        course_session_status,
        created_at,

        -- If either timestamp is NULL, nullify teaching_time; otherwise keep original
        CASE
            WHEN teacher_start_time IS NULL
              OR teacher_end_time IS NULL
            THEN NULL
            ELSE teaching_time
        END AS corrected_teaching_time,  -- int8 or NULL

        -- Flag NULL or duplicate session IDs
        CASE
            WHEN course_session_id IS NULL THEN TRUE
            WHEN COUNT(*) OVER (PARTITION BY course_session_id) > 1 THEN TRUE
            ELSE FALSE
        END AS dq_issue_course_session_id  -- boolean
    FROM SourceData
),

Stats AS (
    -- Step 2: Compute the IQR boundaries on corrected_teaching_time
    SELECT
      PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY corrected_teaching_time) AS q1,
      PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY corrected_teaching_time) AS q3
    FROM CorrectedAndFlagged
)

-- Final Step: Select everything plus the outlier and missing-value flags
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
    caf.original_teaching_time     AS teaching_time,
    caf.course_session_status,
    caf.created_at,

    -- corrected teaching time and duplicate-ID flag
    caf.corrected_teaching_time,
    caf.dq_issue_course_session_id,

    -- IQR-based outlier flag
    CASE
      WHEN caf.corrected_teaching_time IS NOT NULL
       AND (
            caf.corrected_teaching_time <  (s.q1 - 1.5 * (s.q3 - s.q1))
         OR caf.corrected_teaching_time >  (s.q3 + 1.5 * (s.q3 - s.q1))
           )
      THEN TRUE
      ELSE FALSE
    END AS dq_issue_teaching_time_outlier,

    -- Missing-value DQ flag for key columns
    CASE
      WHEN caf.course_session_type IS NULL
        OR caf.course_teacher_id IS NULL
        OR caf.course_session_scheduled_start_time IS NULL
        OR caf.course_session_scheduled_end_time IS NULL
        OR caf.teacher_start_time IS NULL
        OR caf.teacher_end_time IS NULL
        OR caf.original_teaching_time IS NULL
      THEN TRUE
      ELSE FALSE
    END AS dq_issue_missing_values

FROM CorrectedAndFlagged caf
CROSS JOIN Stats s

ORDER BY
    caf.course_session_id NULLS LAST,
    caf.created_at        NULLS LAST;
