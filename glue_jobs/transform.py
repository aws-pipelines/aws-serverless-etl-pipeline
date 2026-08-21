"""
Glue ETL job: reads raw order CSVs from the raw zone, casts types, adds a
partition column, and writes partitioned Parquet to the curated zone.

Invoked by the Step Functions state machine as a StartJobRun.sync task, so
Step Functions blocks on this job's actual success/failure rather than
just "did the API call succeed."
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql.functions import col, to_date, year, month

args = getResolvedOptions(sys.argv, ["JOB_NAME", "RAW_PATH", "CURATED_PATH"])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

raw_df = spark.read.option("header", True).csv(args["RAW_PATH"])

curated_df = (
    raw_df.withColumn("amount", col("amount").cast("double"))
    .withColumn("order_date", to_date(col("order_date")))
    .withColumn("order_year", year(col("order_date")))
    .withColumn("order_month", month(col("order_date")))
)

curated_df.write.mode("overwrite").partitionBy("order_year", "order_month").parquet(
    args["CURATED_PATH"]
)

job.commit()
