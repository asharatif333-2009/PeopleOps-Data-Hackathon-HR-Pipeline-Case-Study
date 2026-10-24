WITH LatestEmployees AS (
    -- Rule 1: Latest employee record filter karna based on updated_at
    SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
MonthEnds AS (
    -- Hamare export data ke mutabiq 6 mahino ki end dates (April - September 2026)
    SELECT CAST('2026-04-30' AS DATE) AS MonthEnd UNION ALL
    SELECT CAST('2026-05-31' AS DATE) UNION ALL
    SELECT CAST('2026-06-30' AS DATE) UNION ALL
    SELECT CAST('2026-07-31' AS DATE) UNION ALL
    SELECT CAST('2026-08-31' AS DATE) UNION ALL
    SELECT CAST('2026-09-30' AS DATE)
),
HistoricalDept AS (
    -- Rule 3: Target department matching where employee was on the last day of the month
    SELECT 
        m.MonthEnd,
        e.emp_id,
        TRIM(ISNULL(h.dept_id, e.department)) AS dept_id
    FROM MonthEnds m
    CROSS JOIN CleanedEmployees e
    LEFT JOIN employment_history h ON e.emp_id = h.emp_id
        AND h.effective_from <= m.MonthEnd
        AND (h.effective_to IS NULL OR h.effective_to >= m.MonthEnd)
    WHERE e.hire_date <= m.MonthEnd 
      AND (e.separation_date IS NULL OR e.separation_date > m.MonthEnd) -- Only active headcount
),
MonthlyPayrollCost AS (
    -- Rule 21: Summing up all EARNINGS for the month
    SELECT 
        CONVERT(VARCHAR(50), pl.emp_id) AS emp_id,
        EOMONTH(CAST(pl.payroll_month + '-01' AS DATE)) AS Payroll_Month,
        SUM(CAST(pl.amount AS FLOAT)) AS Employee_Total_Cost
    FROM payroll_lines pl
    WHERE TRIM(pl.component_type) = 'EARNING'
    GROUP BY pl.emp_id, pl.payroll_month
),
DepartmentBaseSummary AS (
    -- Combining headcount allocation with exact payroll costs per department per month
    SELECT 
        hd.dept_id AS Department,
        hd.MonthEnd AS Month,
        SUM(ISNULL(mp.Employee_Total_Cost, 0)) AS Total_Dept_Cost,
        COUNT(DISTINCT hd.emp_id) AS Headcount
    FROM HistoricalDept hd
    LEFT JOIN MonthlyPayrollCost mp ON hd.emp_id = mp.emp_id AND hd.MonthEnd = mp.Payroll_Month
    GROUP BY hd.dept_id, hd.MonthEnd
),
CostPerEmployeeCalculation AS (
    -- Calculating average payroll cost per employee
    SELECT 
        Department,
        Month,
        Total_Dept_Cost,
        Headcount,
        CASE 
            WHEN Headcount = 0 THEN 0 
            ELSE Total_Dept_Cost / Headcount 
        END AS Cost_Per_Employee
    FROM DepartmentBaseSummary
),
MoMAnalysis AS (
    -- Window function LAG() usage to capture the previous month's cost per employee
    SELECT 
        Department,
        Month,
        Cost_Per_Employee,
        LAG(Cost_Per_Employee) OVER (PARTITION BY Department ORDER BY Month) AS Previous_Month_Cost
    FROM CostPerEmployeeCalculation
)
SELECT 
    Department AS Department_ID,
    CONVERT(VARCHAR(7), Month, 120) AS Operational_Month, -- Formatting output as YYYY-MM
    CAST(Cost_Per_Employee AS DECIMAL(18,2)) AS Current_Cost_Per_Emp,
    CAST(ISNULL(Cost_Per_Employee - Previous_Month_Cost, 0) AS DECIMAL(18,2)) AS Absolute_Change_PKR,
    CAST(
        CASE 
            WHEN ISNULL(Previous_Month_Cost, 0) = 0 THEN 0 
            ELSE ((Cost_Per_Employee - Previous_Month_Cost) / Previous_Month_Cost) * 100 
        END AS DECIMAL(10,2)
    ) AS MoM_Change_Percentage
FROM MoMAnalysis
ORDER BY Department_ID, Month;
