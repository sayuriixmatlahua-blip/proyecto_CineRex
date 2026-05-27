import pymysql
from pymongo import MongoClient
from datetime import datetime
from decimal import Decimal
import datetime
import sys


MYSQL_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "Sayury2026.",
}

MYSQL_DB_NAME = "cinerex"
MONGO_DB_NAME = "cinerex"
MONGO_URI = "mongodb://localhost:27017/"



def connect_databases():

    mysql_conn = pymysql.connect(**MYSQL_CONFIG)
    mongo_client = MongoClient(MONGO_URI)
    print("✔ Connections established.")
    return mysql_conn, mongo_client


def validate_databases(mysql_conn, mongo_client):

    with mysql_conn.cursor() as cursor:
        cursor.execute("SHOW DATABASES")
        available_dbs = [row[0] for row in cursor.fetchall()]

    if MYSQL_DB_NAME not in available_dbs:
        print(f"❌ MySQL database '{MYSQL_DB_NAME}' does not exist.")
        sys.exit(1)

    mysql_conn.select_db(MYSQL_DB_NAME)
    print(f"✔ Connected to MySQL database: '{MYSQL_DB_NAME}'")

    # MongoDB
    mongo_db = mongo_client[MONGO_DB_NAME]
    print(f"✔ Connected to MongoDB database: '{MONGO_DB_NAME}'")

    return mongo_db

def get_all_tables(mysql_conn):
    with mysql_conn.cursor() as cursor:
        cursor.execute("SHOW TABLES")
        return [row[0] for row in cursor.fetchall()]


def serialize_row(row: dict) -> dict:

    clean = {}
    for key, value in row.items():
        if isinstance(value, Decimal):
            clean[key] = float(value)
        elif isinstance(value, (datetime.datetime, datetime.date)):
            clean[key] = str(value)
        else:
            clean[key] = value
    return clean


def migrate_table(mysql_conn, mongo_db, table_name, use_sp=False):

    try:
        with mysql_conn.cursor(pymysql.cursors.DictCursor) as cursor:

            if use_sp:
                sp_name = f"getAll{table_name.capitalize()}"
                cursor.callproc(sp_name)
            else:
                cursor.execute(f"SELECT * FROM `{table_name}`")

            rows = cursor.fetchall()

        if not rows:
            print(f"⚠  No data found in '{table_name}' — skipping.")
            return


        mongo_db[table_name].drop()

        clean_rows = [serialize_row(row) for row in rows]
        mongo_db[table_name].insert_many(clean_rows)
        print(f"✔ Migrated '{table_name}' → {len(clean_rows)} documents inserted.")

    except Exception as e:
        print(f"❌ Error migrating '{table_name}': {e}")




def run_migration(mysql_conn, mongo_db):

    print("\n" + "=" * 55)
    print("  STARTING MIGRATION: MySQL → MongoDB")
    print("=" * 55)

    tables = get_all_tables(mysql_conn)
    print(f"Tables detected: {tables}\n")

    for table in tables:
        migrate_table(mysql_conn, mongo_db, table, use_sp=False)

    print("\n✔ Migration complete!\n")


if __name__ == "__main__":
    mysql_conn = None
    mongo_client = None

    try:
        mysql_conn, mongo_client = connect_databases()
        mongo_db = validate_databases(mysql_conn, mongo_client)
        run_migration(mysql_conn, mongo_db)

    except Exception as e:
        print(f"❌ Unexpected error: {e}")

    finally:
        if mysql_conn:
            mysql_conn.close()
        if mongo_client:
            mongo_client.close()
        print("\n✔ All connections closed. Script finished successfully.")
        print("=" * 55)
