"""
Public, read-only "browse the curated data" GUI. Runs one fixed Athena
query (no user input reaches the SQL, so there's no injection surface)
and renders the result as an HTML table - open the Function URL in a
browser and you're looking at query results, no console or CLI needed.
"""

import os
import time

import boto3

athena = boto3.client("athena")

DATABASE = os.environ["GLUE_DATABASE"]
TABLE = os.environ["CURATED_TABLE"]
WORKGROUP = os.environ["ATHENA_WORKGROUP"]
QUERY = f"SELECT * FROM {TABLE} ORDER BY order_date DESC LIMIT 50"


def run_query():
    start = athena.start_query_execution(
        QueryString=QUERY,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
    )
    query_id = start["QueryExecutionId"]

    for _ in range(30):  # ~30s max wait
        status = athena.get_query_execution(QueryExecutionId=query_id)
        state = status["QueryExecution"]["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1)
    else:
        return None, "Query timed out after 30s."

    if state != "SUCCEEDED":
        reason = status["QueryExecution"]["Status"].get("StateChangeReason", "unknown error")
        return None, f"Query {state}: {reason}"

    results = athena.get_query_results(QueryExecutionId=query_id)
    return results["ResultSet"]["Rows"], None


def render_html(rows, error):
    if error:
        body = f"<p style='color:#b00'>Error: {error}</p><p>Has the pipeline run at least once yet? Upload a CSV to the raw bucket to trigger it.</p>"
    elif not rows:
        body = "<p>No rows returned.</p>"
    else:
        header, *data_rows = rows
        header_html = "".join(f"<th>{c.get('VarCharValue', '')}</th>" for c in header["Data"])
        rows_html = "".join(
            "<tr>" + "".join(f"<td>{c.get('VarCharValue', '')}</td>" for c in row["Data"]) + "</tr>"
            for row in data_rows
        )
        body = f"<table><thead><tr>{header_html}</tr></thead><tbody>{rows_html}</tbody></table>"

    return f"""<!DOCTYPE html>
<html>
<head>
  <title>Curated orders</title>
  <style>
    body {{ font-family: -apple-system, sans-serif; margin: 3%; color: #222; }}
    h1 {{ color: #ff9900; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #ddd; padding: 6px 10px; text-align: left; font-size: 14px; }}
    th {{ background: #fafafa; }}
  </style>
</head>
<body>
  <h1>Curated orders (latest 50)</h1>
  {body}
</body>
</html>"""


def lambda_handler(event, context):
    rows, error = run_query()
    html = render_html(rows, error)
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": html,
    }
