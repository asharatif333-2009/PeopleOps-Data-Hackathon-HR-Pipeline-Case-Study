import os
import pandas as pd
import pyodbc
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

# 1. Apni SSMS details set karen
server_name = 'localhost'  # Agar aapka server name alag hy toh change kar lein
database_name = 'Indus_Weave_Textiles' # Company ke naam ka database

# 2. Pehle check karna aur Database create karna (Master Connection)
master_connection_string = (
    f'Driver={{ODBC Driver 17 for SQL Server}};'
    f'Server={server_name};'
    f'Database=master;'  # Default master DB se connect ho kar naya DB banayenge
    f'Trusted_Connection=yes;'
)

print(f"Connecting to SQL Server to create database '{database_name}'...")
try:
    # Auto-commit mode on rakhna parta hy database create karne ke liye
    conn = pyodbc.connect(master_connection_string, autocommit=True)
    cursor = conn.cursor()
    
    # Check kya database pehle se bana hua hy?
    cursor.execute(f"SELECT database_id FROM sys.databases WHERE name = '{database_name}'")
    exists = cursor.fetchone()
    
    if not exists:
        cursor.execute(f"CREATE DATABASE {database_name}")
        print(f"Success: '{database_name}' database kamyabi se SSMS pe ban gaya hy!")
    else:
        print(f"Database '{database_name}' pehle se mojood hy.")
        
    cursor.close()
    conn.close()
except Exception as e:
    print(f"Database banane mein error aaya: {e}")
    print("Tip: Check karen ke server_name sahi hy aur ODBC Driver 17 installed hy.")
    exit()

# 3. Ab naye bane hue database ka Connection URL banana
target_connection_string = (
    f'Driver={{ODBC Driver 17 for SQL Server}};'
    f'Server={server_name};'
    f'Database={database_name};'
    f'Trusted_Connection=yes;'
)
connection_url = URL.create("mssql+pyodbc", query=dict(odbc_connect=target_connection_string))
engine = create_engine(connection_url)

# 4. Cleaned folder ka path
cleaned_folder_path = r'C:\Users\HP\Desktop\ETL\cleaned'

print("\n--- Data Tables Load Hona Shuru Ho Gaya Hy ---")

# 5. Loop jo har CSV file ko table bana kar load karega
for filename in os.listdir(cleaned_folder_path):
    if filename.endswith('.csv'):
        file_path = os.path.join(cleaned_folder_path, filename)
        table_name = filename.replace('.csv', '')
        
        print(f"Loading table: {table_name}...")
        
        # DataFrame read karna aur SQL mein load karna
        df = pd.read_csv(file_path)
        df.to_sql(name=table_name, con=engine, if_exists='replace', index=False)

print(f"\nKamal ho gaya! Indus Weave Textiles ka database aur saare tables SSMS mein tayyar hain! 🎉")
