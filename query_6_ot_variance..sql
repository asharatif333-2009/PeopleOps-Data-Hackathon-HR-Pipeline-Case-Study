WITH LatestEmployees AS (
    -- Rule 1: Latest employee record filter karna
    SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
RawPunches AS (
    -- Direct biometric punches data clean karna
    SELECT 
        CONVERT(VARCHAR(50), p.device_user_id) AS device_user_id,
        CAST(p.punch_time AS DATE) AS punch_date,
        CAST(p.punch_time AS TIME) AS punch_time
    FROM biometric_punches p
),
DailyPunchesSummary AS (
    -- Rule 10: Check-in aur Check-out nikalna
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
    -- Rules 14 & 15: Overtime hours calculate karna aur half-hour par round down karna
    SELECT 
        ps.device_user_id,
        CASE 
            -- Rule 15: Sunday work
            WHEN DATEPART(WEEKDAY, ps.punch_date) = 1 AND ps.total_punches >= 2 THEN 
                FLOOR(DATEDIFF(MINUTE, ps.check_in, ps.check_out) / 30.0) * 0.5
            
            -- Rule 14: Working day overtime (Standard shift end 17:00:00 ke baad)
            WHEN DATEPART(WEEKDAY, ps.punch_date) <> 1 AND ps.total_punches >= 2 AND ps.check_out > '17:00:00' THEN 
                FLOOR(DATEDIFF(MINUTE, '17:00:00', ps.check_out) / 30.0) * 0.5
            
            ELSE 0 
        END AS Computed_OT_Hours
    FROM DailyPunchesSummary ps
),
ComputedOTTotal AS (
    -- Har department ka kul computed overtime hours
    SELECT 
        TRIM(e.department) AS Department,
        SUM(cot.Computed_OT_Hours) AS Total_Computed_OT
    FROM ComputedOvertimeDaily cot
    JOIN CleanedEmployees e ON (CONVERT(VARCHAR(50), e.emp_id) = cot.device_user_id 
                                OR RIGHT(CONVERT(VARCHAR(50), e.emp_id), 4) = RIGHT(cot.device_user_id, 4))
    GROUP BY e.department
),
PaidOTTotal AS (
    -- Rule 20: payroll_lines table se units = hours paid ka total nikalna
    SELECT 
        TRIM(e.department) AS Department,
        SUM(CAST(pl.units AS FLOAT)) AS Total_Paid_OT
    FROM payroll_lines pl
    JOIN CleanedEmployees e ON CONVERT(VARCHAR(50), pl.emp_id) = CONVERT(VARCHAR(50), e.emp_id)
    WHERE TRIM(pl.component) = 'OVERTIME'
    GROUP BY e.department
)
SELECT 
    c.Department,
    ISNULL(c.Total_Computed_OT, 0) AS Total_Computed_Hours,
    ISNULL(p.Total_Paid_OT, 0) AS Total_Paid_Hours,
    -- Variance Percentage formula
    ((ISNULL(p.Total_Paid_OT, 0) - ISNULL(c.Total_Computed_OT, 0)) / NULLIF(c.Total_Computed_OT, 0)) * 100 AS Variance_Percentage
FROM ComputedOTTotal c
JOIN PaidOTTotal p ON c.Department = p.Department
-- Condition: Paid Overtime exceeds Computed Overtime by MORE THAN 15%
WHERE ISNULL(p.Total_Paid_OT, 0) > (ISNULL(c.Total_Computed_OT, 0) * 1.15)
ORDER BY Variance_Percentage DESC;
