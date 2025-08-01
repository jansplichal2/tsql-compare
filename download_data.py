import pyodbc
import tomli
import sys
import csv
import argparse
from pathlib import Path


def load_config(config_path="config/default_config.toml"):
    """Load configuration from TOML file."""
    try:
        with open(config_path, "rb") as f:
            return tomli.load(f)
    except FileNotFoundError:
        print(f"Configuration file {config_path} not found.")
        sys.exit(1)
    except Exception as e:
        print(f"Error loading configuration: {e}")
        sys.exit(1)


def create_connection(config, database_name):
    """Create database connection."""
    db_config = config["database"]
    connection_string = (
        f"DRIVER={{{db_config['driver']}}};"
        f"SERVER={db_config['server']},{db_config['port']};"
        f"DATABASE={database_name};"
        f"UID={db_config['user']};"
        f"PWD={db_config['password']};"
    )
    
    if db_config.get("trust_server_certificate", False):
        connection_string += "TrustServerCertificate=yes;"
    
    try:
        return pyodbc.connect(connection_string)
    except Exception as e:
        print(f"Error connecting to database {database_name}: {e}")
        return None


def dump_schema_to_csv(
    connection,
    sql_file: str
):

    sql_file = Path(sql_file)
    sql = sql_file.read_text(encoding="utf-8")

    with connection.cursor() as cur:
        cur.execute("SET NOCOUNT ON;")
        cur.execute(sql)

        cols = [col[0] for col in cur.description]
        rows = cur.fetchall()

    return cols, rows


def get_stored_procedures(connection):
    """Get all stored procedures from the database."""
    query = """
    SELECT 
        p.name AS procedure_name,
        m.definition AS procedure_definition
    FROM sys.procedures p
    INNER JOIN sys.sql_modules m ON p.object_id = m.object_id
    WHERE p.type = 'P'
    ORDER BY p.name
    """
    
    try:
        cursor = connection.cursor()
        cursor.execute(query)
        return cursor.fetchall()
    except Exception as e:
        print(f"Error fetching stored procedures: {e}")
        return []


def get_functions(connection):
    """Get all functions from the database."""
    query = """
    SELECT 
        o.name AS function_name,
        m.definition AS function_definition
    FROM sys.objects o
    INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
    WHERE o.type IN ('FN', 'IF', 'TF')
    ORDER BY o.name
    """
    
    try:
        cursor = connection.cursor()
        cursor.execute(query)
        return cursor.fetchall()
    except Exception as e:
        print(f"Error fetching functions: {e}")
        return []


def create_directory_structure(output_dir, database_name):
    """Create directory structure for database, procedures, and functions."""
    base_path = Path(output_dir) / database_name
    procedures_path = base_path / "procedures"
    functions_path = base_path / "functions"
    schema_path = base_path / "schema"
    
    procedures_path.mkdir(parents=True, exist_ok=True)
    functions_path.mkdir(parents=True, exist_ok=True)
    schema_path.mkdir(parents=True, exist_ok=True)
    
    return procedures_path, functions_path, schema_path


def save_sql_object(file_path, name, definition):
    """Save SQL object definition to file."""
    try:
        # Trim leading/trailing whitespace and trailing semicolon to reduce false positives in comparisons
        trimmed_definition = definition.strip()
        if trimmed_definition.endswith(';'):
            trimmed_definition = trimmed_definition[:-1].rstrip()
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(trimmed_definition)
        print(f"Saved: {file_path}")
    except Exception as e:
        print(f"Error saving {name}: {e}")


def download_database_objects(config, database_name):
    """Download stored procedures and functions for a database."""
    print(f"Processing database: {database_name}")
    
    connection = create_connection(config, database_name)
    if not connection:
        return False
    
    try:
        output_dir = config["defaults"]["output_dir"]
        procedures_path, functions_path, schema_path = create_directory_structure(output_dir, database_name)
        
        # Download stored procedures
        procedures = get_stored_procedures(connection)
        print(f"Found {len(procedures)} stored procedures")
        for proc_name, proc_definition in procedures:
            if proc_definition:
                file_path = procedures_path / f"{proc_name}.sql"
                save_sql_object(file_path, proc_name, proc_definition)
        
        # Download functions
        functions = get_functions(connection)
        print(f"Found {len(functions)} functions")
        for func_name, func_definition in functions:
            if func_definition:
                file_path = functions_path / f"{func_name}.sql"
                save_sql_object(file_path, func_name, func_definition)

        cols, rows = dump_schema_to_csv(connection, "sql/simple_schema_dump.sql")

        csv_file = Path(schema_path) / f"schema.csv"
        # --- write CSV -----------------------------------------------------
        with csv_file.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(cols)
            writer.writerows(rows)
        
        return True
    
    except Exception as e:
        print(f"Error processing database {database_name}: {e}")
        return False
    
    finally:
        connection.close()


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description='Download stored procedures and functions from MSSQL databases')
    parser.add_argument('databases', nargs='+', help='Database names to process')
    parser.add_argument('--config', default='config/default_config.toml', help='Configuration file path')
    
    args = parser.parse_args()
    
    config = load_config(args.config)
    
    success_count = 0
    total_count = len(args.databases)
    
    for database_name in args.databases:
        if download_database_objects(config, database_name):
            success_count += 1
        print()  # Empty line for readability
    
    print(f"Completed: {success_count}/{total_count} databases processed successfully")


if __name__ == "__main__":
    main()