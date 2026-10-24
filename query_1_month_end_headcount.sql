WITH LatestEmployees AS (
    -- Rule 1: Filtering latest employee record based on updated_at
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn
    FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
MonthEnds AS (
    -- April to September 2026 dates
    SELECT CAST('2026-04-30' AS DATE) AS MonthEnd UNION ALL
    SELECT CAST('2026-05-31' AS DATE) UNION ALL
    SELECT CAST('2026-06-30' AS DATE) UNION ALL
    SELECT CAST('2026-07-31' AS DATE) UNION ALL
    SELECT CAST('2026-08-31' AS DATE) UNION ALL
    SELECT CAST('2026-09-30' AS DATE)
),
HistoricalDept AS (
    -- Rule 2 & 3: Finding exact department on month end using effective dates
    SELECT 
        m.MonthEnd,
        e.emp_id,
        TRIM(e.plant) AS plant, -- Yahan TRIM lagaya fuzool spaces khatam karne ke liye
        TRIM(h.dept_id) AS dept_id -- Yahan bhi TRIM lagaya
    FROM MonthEnds m
    CROSS JOIN CleanedEmployees e
    LEFT JOIN employment_history h ON e.emp_id = h.emp_id
        AND h.effective_from <= m.MonthEnd
        AND (h.effective_to IS NULL OR h.effective_to >= m.MonthEnd)
    WHERE e.hire_date <= m.MonthEnd 
      AND (e.separation_date IS NULL OR e.separation_date > m.MonthEnd) -- Rule 4
)
SELECT 
    EOMONTH(MonthEnd) AS Month,
    plant AS Plant,
    dept_id AS Department_ID,
    COUNT(emp_id) AS Headcount
FROM HistoricalDept
GROUP BY MonthEnd, plant, dept_id
ORDER BY Month, Plant, Department_ID;
