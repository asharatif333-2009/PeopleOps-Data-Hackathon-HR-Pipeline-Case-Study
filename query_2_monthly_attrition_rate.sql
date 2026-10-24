WITH LatestEmployees AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
MonthBounds AS (
    SELECT CAST('2026-04-01' AS DATE) AS StartDate, CAST('2026-04-30' AS DATE) AS EndDate UNION ALL
    SELECT CAST('2026-05-01' AS DATE), CAST('2026-05-31' AS DATE) UNION ALL
    SELECT CAST('2026-06-01' AS DATE), CAST('2026-06-30' AS DATE) UNION ALL
    SELECT CAST('2026-07-01' AS DATE), CAST('2026-07-31' AS DATE) UNION ALL
    SELECT CAST('2026-08-01' AS DATE), CAST('2026-08-31' AS DATE) UNION ALL
    SELECT CAST('2026-09-01' AS DATE), CAST('2026-09-30' AS DATE)
),
MonthlyStats AS (
    SELECT 
        mb.StartDate AS Month,
        h.dept_id,
        COUNT(CASE WHEN ce.hire_date <= mb.StartDate AND (ce.separation_date IS NULL OR ce.separation_date >= mb.StartDate) THEN ce.emp_id END) AS Start_HC,
        COUNT(CASE WHEN ce.hire_date <= mb.EndDate AND (ce.separation_date IS NULL OR ce.separation_date > mb.EndDate) THEN ce.emp_id END) AS End_HC,
        COUNT(CASE WHEN ce.separation_date BETWEEN mb.StartDate AND mb.EndDate THEN ce.emp_id END) AS Separations
    FROM MonthBounds mb
    CROSS JOIN CleanedEmployees ce
    LEFT JOIN employment_history h ON ce.emp_id = h.emp_id 
        AND h.effective_from <= mb.EndDate 
        AND (h.effective_to IS NULL OR h.effective_to >= mb.EndDate)
    GROUP BY mb.StartDate, h.dept_id
)
SELECT 
    Month,
    dept_id AS Department_ID,
    Separations,
    ((Start_HC + End_HC) / 2.0) AS Avg_Headcount,
    CASE 
        WHEN ((Start_HC + End_HC) / 2.0) = 0 THEN 0
        ELSE (Separations / ((Start_HC + End_HC) / 2.0)) * 100 
    END AS Attrition_Rate_Percentage
FROM MonthlyStats
ORDER BY Month, Department_ID;
