import pandas as pd
import os
import json

def extract_data():
    data = {}

    for file in os.listdir("."):
        if file.endswith(".csv"):
            data[file.split(".")[0]] = pd.read_csv(file)

        elif file.endswith(".json"):
            with open(file, "r", encoding="utf-8") as f:
                data[file.split(".")[0]] = json.load(f)

    return data


extracted_data = extract_data()

for name, df in extracted_data.items():
    print(name)
    print(df)

    