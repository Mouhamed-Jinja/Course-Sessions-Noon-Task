#!/usr/bin/env python3
import os
import pandas as pd
from sqlalchemy import create_engine, text

def transform_chunk(df: pd.DataFrame) -> pd.DataFrame:
    """
    Apply basic transformations:
      - Convert literal 'NaT' to actual nulls
      - Parse numeric columns into numbers
      - Parse datetime columns into pandas datetime
    """
    # Replace 'NaT' strings with actual pandas NA
    df = df.replace('NaT', pd.NA)

    # Define columns for type conversion
    numeric_cols = [
        'course_session_id',
        'course_id',
        'course_teacher_id',
        'teaching_time'
    ]
    datetime_cols = [
        'course_session_scheduled_start_time',
        'course_session_scheduled_end_time',
        'teacher_start_time',
        'teacher_end_time',
        'created_at'
    ]

    # Convert numeric columns
    for col in numeric_cols:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors='coerce')

    # Convert datetime columns
    for col in datetime_cols:
        if col in df.columns:
            # Try ISO formats first, coerce errors
            df[col] = pd.to_datetime(df[col], errors='coerce')

    return df


def csv_to_postgres_via_sqlalchemy(
    csv_path: str,
    table_name: str,
    schema: str = "public",
    user: str = "postgres",
    password: str = "postgres",
    host: str = "localhost",
    port: int = 5432,
    dbname: str = "sessions",
    if_exists: str = "replace",
    chunksize: int = 10_000
):
    """
    Load a raw CSV into Postgres using SQLAlchemy + pandas, into a specific schema,
    applying simple transformations for dtype correction and null coercion.
    """
    # build the SQLAlchemy URL
    conn_str = f"postgresql://{user}:{password}@{host}:{port}/{dbname}"
    engine = create_engine(conn_str, echo=False)

    # ensure (quoted) schema exists
    with engine.begin() as conn:
        conn.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{schema}"'))

    # read+write in chunks
    chunk_iter = pd.read_csv(csv_path, chunksize=chunksize, iterator=True)
    first = True
    for raw_chunk in chunk_iter:
        # apply transformation
        chunk = transform_chunk(raw_chunk)

        # write to database
        chunk.to_sql(
            name=table_name,
            con=engine,
            schema=schema,
            if_exists="replace" if first and if_exists=="replace" else "append",
            index=False
        )
        first = False
        print(f"→ Loaded chunk with {len(chunk)} rows into {schema}.{table_name}")

    print(f"✅ Done. `{schema}.{table_name}` now contains your CSV data.")


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser(
        description="Load a CSV into a Postgres table via SQLAlchemy + pandas with basic dtype corrections"
    )
    p.add_argument("csv",       help="Path to your CSV file")
    p.add_argument("table",     help="Target Postgres table name (no schema)")
    p.add_argument(
        "--schema",
        default="public",
        help="Target schema (will be created if needed)"
    )
    p.add_argument("--host",    default="localhost", help="Postgres host")
    p.add_argument("--port",    default=5432,       type=int, help="Postgres port")
    p.add_argument("--db",      default="sessions", help="Postgres database name")
    p.add_argument("--user",    default="postgres", help="Postgres user")
    p.add_argument("--pwd",     default="postgres", help="Postgres password")
    p.add_argument(
        "--if_exists",
        choices=("replace", "append"),
        default="replace",
        help="What to do if table already exists"
    )
    p.add_argument(
        "--chunksize",
        type=int,
        default=10000,
        help="Number of rows per batch"
    )
    args = p.parse_args()

    csv_to_postgres_via_sqlalchemy(
        csv_path=args.csv,
        table_name=args.table,
        schema=args.schema,
        user=args.user,
        password=args.pwd,
        host=args.host,
        port=args.port,
        dbname=args.db,
        if_exists=args.if_exists,
        chunksize=args.chunksize
    )
