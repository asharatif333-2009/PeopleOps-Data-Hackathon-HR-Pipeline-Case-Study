import os
import json
import pandas as pd

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(BASE_DIR, "cleaned")
os.makedirs(OUTPUT_DIR, exist_ok=True)


def transform_data():
    # 1. Load raw files
    employees = pd.read_csv(os.path.join(BASE_DIR, "employees.csv"))
    history = pd.read_csv(os.path.join(BASE_DIR, "employment_history.csv"))
    departments = pd.read_csv(os.path.join(BASE_DIR, "departments.csv"))
    roster = pd.read_csv(os.path.join(BASE_DIR, "shift_roster.csv"))
    mapping = pd.read_csv(os.path.join(BASE_DIR, "device_mapping.csv"))
    punches = pd.read_csv(os.path.join(BASE_DIR, "biometric_punches.csv"))
    overtime = pd.read_csv(os.path.join(BASE_DIR, "overtime_requests.csv"))
    payroll = pd.read_csv(os.path.join(BASE_DIR, "payroll_lines.csv"))

    with open(os.path.join(BASE_DIR, "leave_requests.json"),
              "r", encoding="utf-8") as f:
        leave_data = json.load(f)

    # 2. Clean employees
    for col in ["hire_date", "separation_date", "date_of_birth"]:
        employees[col] = pd.to_datetime(
            employees[col], format="mixed", dayfirst=True, errors="coerce"
        )

    employees["updated_at"] = pd.to_datetime(
        employees["updated_at"], errors="coerce"
    )

    employees = (
        employees.sort_values("updated_at")
        .drop_duplicates(subset="emp_id", keep="last")
        .copy()
    )

    for col in ["plant", "department", "full_name"]:
        employees[col] = employees[col].astype("string").str.strip()

    employees["department"] = employees["department"].str.lower()

    # 3. Clean department names and create old-name mapping
    for col in ["dept_name", "previous_name", "plant"]:
        departments[col] = departments[col].astype("string").str.strip()

    departments["dept_name"] = departments["dept_name"].str.lower()
    departments["previous_name"] = departments["previous_name"].str.lower()

    department_map = {}

    for _, row in departments.iterrows():
        department_map[row["dept_name"]] = row["dept_id"]

        if pd.notna(row["previous_name"]) and row["previous_name"]:
            department_map[row["previous_name"]] = row["dept_id"]

    # 4. Fix employment history effective dates
    history["effective_from"] = pd.to_datetime(
        history["effective_from"], errors="coerce"
    )
    history["effective_to"] = pd.to_datetime(
        history["effective_to"], errors="coerce"
    )

    history = history.sort_values(["emp_id", "effective_from"]).copy()

    history["effective_to"] = (
        history.groupby("emp_id")["effective_from"].shift(-1)
        - pd.Timedelta(days=1)
    )

    # Latest history record has no end date
    history["effective_to"] = history["effective_to"].where(
        history["effective_to"].notna(), pd.NaT
    )

    # 5. Fill missing roster weeks with previous shift
    roster["week_start"] = pd.to_datetime(
        roster["week_start"], errors="coerce"
    )

    roster = roster.sort_values(["emp_id", "week_start"]).copy()

    roster["shift_code"] = (
        roster.groupby("emp_id")["shift_code"].ffill()
    )

    # 6. Map biometric punches to employees
    mapping["device_id"] = mapping["device_id"].astype("string")
    mapping["device_user_id"] = mapping["device_user_id"].astype("string")
    punches["device_id"] = punches["device_id"].astype("string")
    punches["device_user_id"] = punches["device_user_id"].astype("string")

    punches["punch_time"] = pd.to_datetime(
        punches["punch_time"], errors="coerce"
    )

    punches = punches.merge(
        mapping[["device_id", "device_user_id", "emp_id"]],
        on=["device_id", "device_user_id"],
        how="left",
        validate="many_to_one"
    )

    rejected_punches = punches[punches["emp_id"].isna()].copy()
    valid_punches = punches[punches["emp_id"].notna()].copy()

    valid_punches = valid_punches.sort_values(
        ["emp_id", "punch_time"]
    )

    # Two punches within 2 minutes count as one
    time_diff = (
        valid_punches.groupby("emp_id")["punch_time"].diff()
    )

    valid_punches = valid_punches[
        time_diff.isna() | (time_diff > pd.Timedelta(minutes=2))
    ].copy()

    # 7. Clean overtime requests
    overtime["ot_date"] = pd.to_datetime(
        overtime["ot_date"], errors="coerce"
    )

    approved_overtime = overtime[
        overtime["status"].astype("string").str.strip().str.lower()
        == "approved"
    ].copy()

    # 8. Process leave approvals
    leave_rows = []

    for request in leave_data:
        approvals = request.get("approvals", [])

        manager_approved = any(
            a.get("approver_role", "").strip().lower() == "manager"
            and a.get("action", "").strip().lower() == "approved"
            for a in approvals
        )

        hr_approved = any(
            a.get("approver_role", "").strip().lower() == "hr"
            and a.get("action", "").strip().lower() == "approved"
            for a in approvals
        )

        leave_rows.append({
            "request_id": request.get("request_id"),
            "emp_id": request.get("employee", {}).get("emp_id"),
            "plant": request.get("employee", {}).get("plant"),
            "leave_type": request.get("leave", {}).get("type"),
            "leave_from": request.get("leave", {}).get("from"),
            "leave_to": request.get("leave", {}).get("to"),
            "manager_approved": manager_approved,
            "hr_approved": hr_approved,
            "cancelled_at": request.get("cancelled_at"),
            "is_approved": (
                manager_approved
                and hr_approved
                and not request.get("cancelled_at")
            )
        })

    leave = pd.DataFrame(leave_rows)

    for col in ["leave_from", "leave_to"]:
        leave[col] = pd.to_datetime(
            leave[col], errors="coerce"
        )

    approved_leave = leave[leave["is_approved"]].copy()

    # 9. Calculate payroll cost
    payroll["amount"] = pd.to_numeric(
        payroll["amount"], errors="coerce"
    )

    payroll["component_type"] = (
        payroll["component_type"].astype("string").str.strip().str.upper()
    )

    payroll_cost = payroll[
        payroll["component_type"] == "EARNING"
    ].copy()

    # 10. Save transformed data separately
    output_tables = {
        "employees": employees,
        "employment_history": history,
        "departments": departments,
        "shift_roster": roster,
        "biometric_punches": valid_punches,
        "rejected_punches": rejected_punches,
        "overtime_requests": overtime,
        "approved_overtime": approved_overtime,
        "leave_requests": leave,
        "approved_leave": approved_leave,
        "payroll_lines": payroll,
        "payroll_cost_lines": payroll_cost
    }

    for name, df in output_tables.items():
        df.to_csv(
            os.path.join(OUTPUT_DIR, f"{name}.csv"),
            index=False
        )

    print("Transformation complete!")
    print("Output folder:", OUTPUT_DIR)

    for name, df in output_tables.items():
        print(f"{name}: {len(df)} rows")


if __name__ == "__main__":
    transform_data()

    