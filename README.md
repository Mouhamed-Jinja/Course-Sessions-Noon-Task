# Data Quality Analysis and Cleansing: Sessions Dataset

## 1. Introduction

This document details the process undertaken to analyze and cleanse the provided sessions dataset. The primary objective was to identify data quality issues, implement appropriate solutions, and produce a reliable dataset suitable for downstream analysis. The process involved using Python for initial data loading and transformation, and PostgreSQL for executing data quality checks and cleansing logic.

## 2. Workflow Overview

The data cleansing process followed these general steps:
![Image](https://github.com/user-attachments/assets/850788f8-e9e8-4f81-bd89-c036797951ee)

1.  **Extraction & Initial Transformation:** Raw data was extracted from a CSV file using a Python script (`Extract.py`). Basic transformations, such as handling `NaT` values and enforcing data types, were applied during this stage.
2.  **Loading:** The transformed data was loaded into a landing zone table (`LZ.sessions_raw`) in a PostgreSQL database.
3.  **Data Quality Flagging:** An SQL script (`dq_issues_flags.sql`) was executed to analyze the raw data and create a view (`LZ.fallaged_dq_issues`) that flags records with potential quality issues (duplicates, outliers, missing values).
4.  **Data Cleansing & Decision Making:** A final SQL query (`cleansing_decisions.sql`) was used to apply cleansing rules based on the flags, addressing the identified issues and selecting the final, cleaned data.

*(Refer to the `WorkFlow.drawio.png` diagram for a visual representation of this process.)*

## 3. Task Requirements Addressed

This analysis and the resulting documentation address the following specific requirements:

1.  **What potential issues do you notice in the data?** (See Section 4.1)
2.  **What solutions would you recommend for each issue?** (See Section 4.2)
3.  **Write a query that returns the original table (with all columns) and adds a new column only for issues that are applicable. If a new column is added, ensure it displays the corrected value. [Please specify which SQL dialect you are using]** (See Section 5)

## 4. Detailed Analysis and Solutions

### 4.1 Potential Issues Identified (Task Point 1)

The following data quality issues were identified in the `LZ.sessions_raw` table using the logic defined in `dq_issues_flags.sql`:

*   **Duplicate Records (`dq_issue_dedup` flag):**
    *   **Detection:** Multiple records were found sharing the same `course_session_id`. This was identified using a window function `COUNT(*) OVER (PARTITION BY course_session_id) > 1`.
    *   **Impact:** Duplicates can lead to inflated counts and incorrect aggregations.

*   **Outliers in `teaching_time` (`dq_issue_teaching_time_outlier` flag):**
    *   **Detection:** Values in the `teaching_time` column were flagged as outliers if they fell below Q1 - 1.5*IQR or above Q3 + 1.5*IQR (Interquartile Range).
    *   **Impact:** Extreme values can significantly skew statistical measures like averages and affect model performance.

*   **Missing Values (`dq_issue_missing_values` flag):**
    *   **Detection:** Records were flagged if `NULL` values were present in any of the following critical columns: `course_session_type`, `course_teacher_id`, `course_session_scheduled_start_time`, `course_session_scheduled_end_time`, `teacher_start_time`, `teacher_end_time`, `teaching_time`.
    *   **Impact:** Missing values can lead to incomplete analysis or require imputation, which might introduce bias.

*   **Data Type Integrity & Consistency:**
    *   **Detection:** While not explicitly flagged by the SQL, the initial Python script (`Extract.py`) handles basic type conversions (numeric, datetime). The database schema itself enforces data types upon loading.
    *   **Impact:** Incorrect data types can cause errors in calculations or comparisons.

*   **Timestamp Standardization:**
    *   **Detection:** Handled during the Python loading phase (`pd.to_datetime`) to ensure a consistent format.
    *   **Impact:** Inconsistent timestamp formats prevent proper sorting, filtering, and time-based calculations.

### 4.2 Recommended Solutions Implemented (Task Point 2)

The following solutions were implemented in the `cleansing_decisions.sql` query to address the identified issues:

*   **Handling Missing Values & Planned Sessions:**
    *   **Action:** Records flagged with `dq_issue_missing_values = TRUE` were excluded from the final dataset. Additionally, records where `course_session_status = 'planned'` were also excluded, as they represent future or incomplete sessions lacking actual operational data.
    *   **Rationale:** Ensures that the final dataset only contains complete and relevant session records.
    *   **Implementation:** Achieved via the `WHERE NOT dq_issue_missing_values AND course_session_status <> 'planned'` clause in the `filtered` CTE.

*   **Outlier Correction (`teaching_time`):**
    *   **Action:** Records flagged with `dq_issue_teaching_time_outlier = TRUE` had their `teaching_time` value replaced.
    *   **Replacement Value:** The calculated average `teaching_time` (using `ceil(AVG(teaching_time))`) derived from the *valid* (non-missing, non-outlier, non-planned) records.
    *   **Rationale:** Mitigates the impact of extreme values on analysis while retaining the session record.
    *   **Implementation:** Achieved using a `CASE` statement in the `replaced` CTE, referencing the average calculated in the `avg_tt` CTE.

*   **Deduplication:**
    *   **Action:** For records sharing the same `course_session_id`, only one record was kept.
    *   **Selection Criteria:** The record with the latest `created_at` timestamp was retained.
    *   **Rationale:** Assumes the latest record represents the most up-to-date information for a given session.
    *   **Implementation:** Achieved using the `ROW_NUMBER() OVER (PARTITION BY course_session_id ORDER BY created_at DESC)` window function in the `deduped` CTE and filtering for `rn = 1` in the final `SELECT` statement.

## 5. Final Query for Cleaned Data (Task Point 3)

**SQL Dialect:** PostgreSQL

The following query integrates the cleansing logic described above. It returns the original table structure (all columns relevant after cleansing) for the valid, deduplicated records. The `teaching_time` column in the output reflects the corrected value where outliers were replaced.

```sql
-- cleansing_decisions.sql -> Final Query Producing Cleaned Data
WITH 
  -- 1. Base view containing DQ flags
  raw AS (
    SELECT * 
    FROM "LZ".fallaged_dq_issues -- Assumes this view is created by dq_issues_flags.sql
  ),

  -- 2. Filter out records with missing values and 'planned' sessions
  filtered AS (
    SELECT *
    FROM raw
    WHERE NOT dq_issue_missing_values
      AND course_session_status <> 'planned'
  ),

  -- 3. Compute average teaching_time (excluding outliers) for replacement
  avg_tt AS (
    SELECT ceil(AVG(teaching_time)) AS avg_teaching_time
    FROM filtered
    WHERE NOT dq_issue_teaching_time_outlier -- Ensure average is not skewed by outliers
  ),

  -- 4. Replace teaching_time outliers with the computed average
  replaced AS (
    SELECT
      f.*,
      -- Use average time if it's an outlier, otherwise keep original
      CASE
        WHEN f.dq_issue_teaching_time_outlier
        THEN at.avg_teaching_time
        ELSE f.teaching_time
      END AS final_teaching_time -- This column holds the original or corrected value
    FROM filtered f
    CROSS JOIN avg_tt at -- Join to get the average value
  ),

  -- 5. Deduplicate by keeping the latest record per session ID
  deduped AS (
    SELECT
      *,
      -- Assign row number within each session group, ordered by creation date descending
      ROW_NUMBER() OVER (
        PARTITION BY course_session_id 
        ORDER BY created_at DESC
      ) AS rn
    FROM replaced
  )

-- 6. Select final columns, taking only the latest record (rn=1)
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
  final_teaching_time   AS teaching_time, -- Output corrected value under the original column name
  course_session_status,
  created_at
FROM deduped
WHERE rn = 1 -- Keep only the latest record for each session_id
ORDER BY course_session_id;

```

**Explanation:** This query sequentially filters invalid data, calculates a replacement value for outliers, applies the replacement, and finally removes duplicates, resulting in a cleaned dataset where the `teaching_time` column contains either the original value or the corrected average value for former outliers.

## 6. Implementation Details

*   **Data Loading:** `Extract.py` (Python script using pandas and SQLAlchemy).
*   **DQ Flagging:** `dq_issues_flags.sql` (PostgreSQL script creating a view).
*   **Cleansing:** `cleansing_decisions.sql` (PostgreSQL query).

## 7. Conclusion

By applying these data quality checks and cleansing steps, the sessions dataset has been refined to address issues of duplication, outliers, and missing values. The resulting dataset, generated by the final SQL query, provides a more reliable foundation for subsequent analysis and reporting.
