WITH LatestEmployees AS (
    -- Rule 1: Filtering latest employee record based on updated_at
    SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
FirstPunches AS (
    -- Direct punches se har user ka din ka pehla punch (Check-in) nikalna
    SELECT 
        CONVERT(VARCHAR(50), p.device_user_id) AS device_user_id,
        CAST(p.punch_time AS DATE) AS punch_date,
        CAST(p.punch_time AS TIME) AS punch_time,
        ROW_NUMBER() OVER (PARTITION BY CONVERT(VARCHAR(50), p.device_user_id), CAST(p.punch_time AS DATE) ORDER BY p.punch_time) as row_num
    FROM biometric_punches p
),
LateCalculations AS (
    SELECT 
        fp.device_user_id,
        fp.punch_date,
        fp.punch_time,
        -- Hum roster table ko bypass karke direct standard shift time (09:00:00) assume kar rahe hain
        CAST('09:00:00' AS TIME) AS shift_start_time
    FROM FirstPunches fp
    WHERE fp.row_num = 1
),
TaggedLatePunches AS (
    SELECT 
        device_user_id,
        punch_date,
        -- Rule 13: Late arrival = check-in > 10 minutes after shift start (09:10 AM)
        CASE 
            WHEN punch_time > '09:10:00' THEN 1 
            ELSE 0 
        END AS IsLate
    FROM LateCalculations
    -- Rule 13: Sundays ko exclude karna hy (Sunday = 1)
    WHERE DATEPART(WEEKDAY, punch_date) <> 1
),
EmployeeLateCounts AS (
    SELECT 
        -- Kuch databases mein employee ID aur device user id thoda alag format mein hote hain
        -- Hum yahan direct match kar rahe hain ya right characters se tie up kar rahe hain
        tl.device_user_id,
        TRIM(e.emp_id) AS emp_id,
        TRIM(e.department) AS Department,
        COUNT(*) AS Late_Arrival_Count,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) as rnk
    FROM TaggedLatePunches tl
    JOIN CleanedEmployees e ON (CONVERT(VARCHAR(50), e.emp_id) = tl.device_user_id 
                                OR RIGHT(CONVERT(VARCHAR(50), e.emp_id), 4) = RIGHT(tl.device_user_id, 4))
    WHERE tl.IsLate = 1
    GROUP BY tl.device_user_id, e.emp_id, e.department
)
SELECT TOP 10 
    emp_id AS Employee_ID,
    Department,
    Late_Arrival_Count
FROM EmployeeLateCounts
WHERE rnk <= 10
ORDER BY Late_Arrival_Count DESC;
