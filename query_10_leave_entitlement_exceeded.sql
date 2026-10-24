WITH LatestEmployees AS (
    -- Rule 1: Filtering latest employee record based on updated_at
    SELECT *, ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY updated_at DESC) as rn FROM employees
),
CleanedEmployees AS (
    SELECT * FROM LatestEmployees WHERE rn = 1
),
CalendarDates AS (
    -- April se September 2026 tak ki saari dates generate karne ka recursive logic
    SELECT CAST('2026-04-01' AS DATE) AS CalendarDate
    UNION ALL
    SELECT DATEADD(DAY, 1, CalendarDate)
    FROM CalendarDates
    WHERE CalendarDate < '2026-09-30'
),
ValidLeaveDays AS (
    -- Rules 16 & 17: Flattened JSON column names (leave_from, leave_to, leave_type) ko map karna
    SELECT 
        CONVERT(VARCHAR(50), lr.emp_id) AS emp_id,
        c.CalendarDate AS leave_date
    FROM leave_requests lr
    -- JSON structure flat hone ke baad columns aam tor par 'leave_from' aur 'leave_to' ban jate hain
    INNER JOIN CalendarDates c ON c.CalendarDate BETWEEN 
        CAST(ISNULL(lr.leave_from, lr.[from]) AS DATE) AND 
        CAST(ISNULL(lr.leave_to, lr.[to]) AS DATE)
    WHERE TRIM(ISNULL(lr.leave_type, lr.component)) = 'Annual'
      -- Rule 16: Cancelled leaves ko remove karna
      AND (lr.cancelled_at IS NULL OR lr.cancelled_at = '')
      -- Rule 17: Sundays ko leave days se nikalna
      AND DATEPART(WEEKDAY, c.CalendarDate) <> 1
),
LeaveCountsPerEmployee AS (
    SELECT 
        emp_id,
        COUNT(DISTINCT leave_date) AS Total_Leaves_Taken
    FROM ValidLeaveDays
    GROUP BY emp_id
)
SELECT 
    e.emp_id AS Employee_ID,
    e.full_name AS Employee_Name,
    TRIM(e.department) AS Department,
    e.annual_leave_entitlement AS Full_Year_Entitlement,
    l.Total_Leaves_Taken AS Leaves_Taken_In_6_Months,
    (l.Total_Leaves_Taken - e.annual_leave_entitlement) AS Exceeded_Days
FROM LeaveCountsPerEmployee l
JOIN CleanedEmployees e ON l.emp_id = CONVERT(VARCHAR(50), e.emp_id)
-- Condition: 6 mahine ki leaves pure saal ke quota se exceed kar gayi hon (Rule 18)
WHERE l.Total_Leaves_Taken > e.annual_leave_entitlement
ORDER BY Exceeded_Days DESC
OPTION (MAXRECURSION 200);

