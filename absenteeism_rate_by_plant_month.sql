WITH LatestEmployees AS (
    -- Rule 1: Filtering latest employee record based on updated_at
    SELECT *, 
           ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn 
    FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
DailyPunches AS (
    -- Direct biometric punches se string based counting karna
    SELECT 
        CONVERT(VARCHAR(50), p.device_user_id) AS device_user_id,
        CAST(p.punch_time AS DATE) AS punch_date,
        COUNT(*) AS punch_count
    FROM biometric_punches p
    GROUP BY CONVERT(VARCHAR(50), p.device_user_id), CAST(p.punch_time AS DATE)
),
CalendarDays AS (
    -- 6 Mahino ke tamam unique active dates banana data se
    SELECT DISTINCT CAST(punch_time AS DATE) AS calendar_date, EOMONTH(punch_time) AS Month
    FROM biometric_punches
),
EmployeeAttendanceBase AS (
    SELECT 
        CONVERT(VARCHAR(50), e.emp_id) AS emp_id,
        TRIM(e.plant) AS plant,
        c.calendar_date,
        c.Month,
        ISNULL(dp.punch_count, 0) AS daily_punches
    FROM CleanedEmployees e
    CROSS JOIN CalendarDays c
    -- Strict string matching lagayi hy taake bigint wala error bilkul khatam ho jaye
    LEFT JOIN DailyPunches dp ON CONVERT(VARCHAR(50), e.emp_id) = dp.device_user_id
    WHERE c.calendar_date >= CAST(e.hire_date AS DATE)
      AND (e.separation_date IS NULL OR c.calendar_date <= CAST(e.separation_date AS DATE))
),
DailyStatus AS (
    -- Rule 12: Status tags set karna
    SELECT 
        plant,
        Month,
        CASE 
            WHEN DATEPART(WEEKDAY, calendar_date) = 1 AND daily_punches = 0 THEN 'Weekly Off'
            WHEN daily_punches >= 2 THEN 'Present'
            WHEN daily_punches = 1 THEN 'Missing Punch'
            ELSE 'Absent'
        END AS attendance_status
    FROM EmployeeAttendanceBase
)
SELECT 
    plant AS Plant,
    Month,
    COUNT(CASE WHEN attendance_status = 'Absent' THEN 1 END) AS Absent_Days,
    COUNT(CASE WHEN attendance_status IN ('Present', 'Missing Punch', 'Absent') THEN 1 END) AS Total_Working_Days,
    CASE 
        WHEN COUNT(CASE WHEN attendance_status IN ('Present', 'Missing Punch', 'Absent') THEN 1 END) = 0 THEN 0
        ELSE (CAST(COUNT(CASE WHEN attendance_status = 'Absent' THEN 1 END) AS FLOAT) / 
              NULLIF(COUNT(CASE WHEN attendance_status IN ('Present', 'Missing Punch', 'Absent') THEN 1 END), 0)) * 100 
    END AS Absenteeism_Rate_Percentage
FROM DailyStatus
GROUP BY plant, Month
ORDER BY Plant, Month;
