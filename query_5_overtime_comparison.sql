WITH LatestEmployees AS (
    -- Rule 1: Latest employee record filter karna
    SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
RawPunches AS (
    -- Direct biometric punches data clean aur standardize karna
    SELECT 
        CONVERT(VARCHAR(50), p.device_user_id) AS device_user_id,
        CAST(p.punch_time AS DATE) AS punch_date,
        CAST(p.punch_time AS TIME) AS punch_time
    FROM biometric_punches p
),
DailyPunchesSummary AS (
    -- Rule 10: Har employee ke din ka check-in (min) aur check-out (max) nikalna
    SELECT 
        device_user_id,
        punch_date,
        MIN(punch_time) AS check_in,
        MAX(punch_time) AS check_out,
        COUNT(*) AS total_punches
    FROM RawPunches
    GROUP BY device_user_id, punch_date
),
ComputedOvertimeDaily AS (
    -- Rules 14 & 15: Overtime minutes calculate karna shift time ke mutabiq
    SELECT 
        ps.device_user_id,
        ps.punch_date,
        EOMONTH(ps.punch_date) AS Month,
        CASE 
            -- Rule 15: Sunday ko kaam poora overtime hy (Check-out - Check-in)
            WHEN DATEPART(WEEKDAY, ps.punch_date) = 1 AND ps.total_punches >= 2 THEN 
                FLOOR(DATEDIFF(MINUTE, ps.check_in, ps.check_out) / 30.0) * 0.5
            
            -- Rule 14: Working day par shift end (Assuming standard 17:00:00 end) ke baad ka time
            WHEN DATEPART(WEEKDAY, ps.punch_date) <> 1 AND ps.total_punches >= 2 AND ps.check_out > '17:00:00' THEN 
                FLOOR(DATEDIFF(MINUTE, '17:00:00', ps.check_out) / 30.0) * 0.5
            
            ELSE 0 
        END AS Computed_OT_Hours
    FROM DailyPunchesSummary ps
),
ComputedOTMonthly AS (
    -- Monthly base par computed overtime sum karna
    SELECT 
        CONVERT(VARCHAR(50), e.emp_id) AS emp_id,
        TRIM(e.department) AS Department,
        cot.Month,
        SUM(cot.Computed_OT_Hours) AS Total_Computed_OT
    FROM ComputedOvertimeDaily cot
    JOIN CleanedEmployees e ON (CONVERT(VARCHAR(50), e.emp_id) = cot.device_user_id 
                                OR RIGHT(CONVERT(VARCHAR(50), e.emp_id), 4) = RIGHT(cot.device_user_id, 4))
    GROUP BY e.emp_id, e.department, cot.Month
),
ApprovedOTMonthly AS (
    -- Rule 19: Only approved status overtime requests
    SELECT 
        CONVERT(VARCHAR(50), ao.emp_id) AS emp_id,
        TRIM(e.department) AS Department,
        EOMONTH(CAST(ao.ot_date AS DATE)) AS Month,
        SUM(CAST(ao.approved_hours AS FLOAT)) AS Total_Approved_OT
    FROM overtime_requests ao
    JOIN CleanedEmployees e ON CONVERT(VARCHAR(50), ao.emp_id) = CONVERT(VARCHAR(50), e.emp_id)
    WHERE TRIM(ao.status) = 'Approved'
    GROUP BY ao.emp_id, e.department, EOMONTH(CAST(ao.ot_date AS DATE))
),
PaidOTMonthly AS (
    -- Rule 20: payroll_lines table se units = hours paid nikalna
    SELECT 
        CONVERT(VARCHAR(50), pl.emp_id) AS emp_id,
        TRIM(e.department) AS Department,
        EOMONTH(CAST(pl.payroll_month + '-01' AS DATE)) AS Month,
        SUM(CAST(pl.units AS FLOAT)) AS Total_Paid_OT
    FROM payroll_lines pl
    JOIN CleanedEmployees e ON CONVERT(VARCHAR(50), pl.emp_id) = CONVERT(VARCHAR(50), e.emp_id)
    WHERE TRIM(pl.component) = 'OVERTIME'
    GROUP BY pl.emp_id, e.department, pl.payroll_month
),
AllCombinations AS (
    -- Tamam active paths ko completely clean jor diya bina multi-part issue ke
    SELECT emp_id, Department, Month FROM ComputedOTMonthly UNION
    SELECT emp_id, Department, Month FROM ApprovedOTMonthly UNION
    SELECT emp_id, Department, Month FROM PaidOTMonthly
)
SELECT 
    ac.Department,
    ac.Month,
    SUM(ISNULL(c.Total_Computed_OT, 0)) AS Computed_Overtime_Hours,
    SUM(ISNULL(a.Total_Approved_OT, 0)) AS Approved_Overtime_Hours,
    SUM(ISNULL(p.Total_Paid_OT, 0)) AS Paid_Overtime_Hours
FROM AllCombinations ac
LEFT JOIN ComputedOTMonthly c ON ac.emp_id = c.emp_id AND ac.Month = c.Month
LEFT JOIN ApprovedOTMonthly a ON ac.emp_id = a.emp_id AND ac.Month = a.Month
LEFT JOIN PaidOTMonthly p ON ac.emp_id = p.emp_id AND ac.Month = p.Month
GROUP BY ac.Department, ac.Month
ORDER BY ac.Department, ac.Month;
