WITH LatestEmployees AS (
    -- Rule 1: Latest employee record filter karna based on updated_at
    SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
MonthlyPunches AS (
    -- Har employee ke har mahine ke total punches count karna direct table se
    SELECT 
        CONVERT(VARCHAR(50), p.device_user_id) AS device_user_id,
        EOMONTH(CAST(p.punch_time AS DATE)) AS Punch_Month,
        COUNT(*) AS Total_Punches
    FROM biometric_punches p
    GROUP BY CONVERT(VARCHAR(50), p.device_user_id), EOMONTH(CAST(p.punch_time AS DATE))
),
MonthlyEarningsPaid AS (
    -- Rule 21: Jo earnings lines pay ki gayi hain unka total nikalna per month
    SELECT 
        CONVERT(VARCHAR(50), pl.emp_id) AS emp_id,
        EOMONTH(CAST(pl.payroll_month + '-01' AS DATE)) AS Payroll_Month,
        SUM(CAST(pl.amount AS FLOAT)) AS Total_Earnings
    FROM payroll_lines pl
    WHERE TRIM(pl.component_type) = 'EARNING'
    GROUP BY pl.emp_id, pl.payroll_month
)
SELECT 
    e.emp_id AS Employee_ID,
    e.full_name AS Employee_Name,
    TRIM(e.department) AS Department,
    CONVERT(VARCHAR(7), ep.Payroll_Month, 120) AS Month, -- Output format YYYY-MM
    ep.Total_Earnings AS Earnings_Paid,
    ISNULL(mp.Total_Punches, 0) AS Total_Attendance_Punches
FROM MonthlyEarningsPaid ep
JOIN CleanedEmployees e ON ep.emp_id = CONVERT(VARCHAR(50), e.emp_id)
-- Punches table ke sath right side character/string join lagaya missing device_mapping ke liye
LEFT JOIN MonthlyPunches mp ON (ep.emp_id = mp.device_user_id OR RIGHT(ep.emp_id, 4) = RIGHT(mp.device_user_id, 4))
    AND ep.Payroll_Month = mp.Punch_Month
-- Condition: Salary mili ho (> 0) lekin punches bilkul 0 (ya NULL) hon
WHERE ep.Total_Earnings > 0 
  AND ISNULL(mp.Total_Punches, 0) = 0
ORDER BY Month, Employee_ID;
