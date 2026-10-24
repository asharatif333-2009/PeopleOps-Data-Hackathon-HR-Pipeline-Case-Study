WITH LatestEmployees AS (
    -- Rule 1: Duplicate employees hatana updated_at use kar ke
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn 
    FROM employees
),
CleanedEmployees AS (
    -- Sirf un employees ko uthana jo company chor chuke hain (Separated)
    SELECT * 
    FROM LatestEmployees 
    WHERE rn = 1 AND separation_date IS NOT NULL
),
MonthlyEarnings AS (
    -- Rule 21: Har employee ki monthly total earnings sum karna
    SELECT 
        CONVERT(VARCHAR(50), pl.emp_id) AS emp_id,
        EOMONTH(CAST(pl.payroll_month + '-01' AS DATE)) AS Payroll_Month_End,
        pl.payroll_month AS Payroll_Month,
        SUM(CAST(pl.amount AS FLOAT)) AS Total_Earnings
    FROM payroll_lines pl
    WHERE TRIM(pl.component_type) = 'EARNING'
    GROUP BY pl.emp_id, pl.payroll_month
)
SELECT 
    e.emp_id AS Employee_ID,
    e.full_name AS Employee_Name,
    TRIM(e.department) AS Department,
    e.separation_date AS Separation_Date,
    p.Payroll_Month AS Payroll_Month_Paid,
    p.Total_Earnings AS Amount_Paid
FROM MonthlyEarnings p
JOIN CleanedEmployees e ON p.emp_id = CONVERT(VARCHAR(50), e.emp_id)
-- Condition: Jis mahine ka payroll pay hua, us mahine ka end date separation date se BADA hona chahiye
-- Taake separation wale mahine ki final settlement ke BAAD wale mahine pakde ja skein
WHERE p.Payroll_Month_End > EOMONTH(CAST(e.separation_date AS DATE))
  AND p.Total_Earnings > 0
ORDER BY Employee_ID, p.Payroll_Month;
