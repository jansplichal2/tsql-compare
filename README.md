# tsql-compare
Download stored procedures and functions from MSSQL server

## Install
```bash
pip install -r requirements.txt
```

Install ODBC drivers on Mac
```bash
# Tap the Microsoft repository (if you haven't already)
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release

# Update brew and install the driver and command-line tools
brew update
brew install msodbcsql18 mssql-tools18
```

## Configuration
Edit `config/default_config.toml`:
```toml

[defaults]
output_dir = "./out"

[database]
server = "localhost"
port = 1433
user = "my_user"
password = "my_password"
database = "my_database"
driver = "ODBC Driver 18 for SQL Server"
trust_server_certificate = true
```


## How it works

Download the stored procedures and function from the databases specified by the user on the command line.

For example for these MSSQL databases - warehouse, reporting, relations - it will create a directory structure like the one bellow:

.
├── out
│   ├── warehouse
│   │   ├── procedures
│   │   │   ├── addPaymentObligation.sql
│   │   │   ├── adjustCreditMemo.sql
│   │   ├── functions
│   │   │   ├── formatTask.sql
│   │   │   ├── getEntityName.sql
│   ├── reporting
│   │   ├── procedures
│   │   │   ├── runRemittanceReport.sql
│   │   │   ├── runSupplierReport.sql
│   │   │   ├── runBuyerReport.sql
│   ├── relations
│   │   ├── procedures
│   │   │   ├── addUser.sql
│   │   │   ├── removeUser.sql
│   │   │   ├── getUser.sql

The files contain the full source code of the stored procedure/function.
They can be compared with tools like Beyond Compare to inspect differences between different instances of SQL server.

## License
MIT
