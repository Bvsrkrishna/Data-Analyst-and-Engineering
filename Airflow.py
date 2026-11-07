"""
08_airflow_dag.py - Orchestrates the CLV pipeline (Airflow 2.4+)
Place this file and the numbered scripts 01, 06, 07, 11, 12, 14 in  $AIRFLOW_HOME/dags/clv_project/
Flow: generate/extract -> ETL -> data-quality gate -> model -> refresh BI extracts -> notify
"""
from datetime import datetime, timedelta
from pathlib import Path
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.operators.empty import EmptyOperator

PROJECT = Path(__file__).resolve().parent          # folder containing the numbered scripts
PROC = PROJECT / "data" / "processed"

default_args = {
    "owner": "analytics", "retries": 2, "retry_delay": timedelta(minutes=5),
    "email_on_failure": False, "execution_timeout": timedelta(minutes=30)}

def quality_gate(**_):
    """Fail the run (and stop downstream tasks) if outputs look wrong."""
    import pandas as pd
    tx = pd.read_csv(PROC / "transactions_clean.csv")
    assert len(tx) > 1000, "too few rows"
    assert tx.line_revenue.gt(0).all(), "non-positive revenue"
    assert not tx.duplicated().any(), "duplicates"
    return len(tx)

def export_summary(**_):
    import pandas as pd
    p = pd.read_csv(PROC / "clv_predictions.csv")
    s = p.groupby("clv_segment").agg(customers=("customer_id", "count"), pred_clv=("predicted_clv_6m", "sum"))
    s.to_csv(PROC / "segment_summary.csv"); print(s)

with DAG(
    dag_id="clv_pipeline", description="Customer Lifetime Value ETL + model + BI refresh",
    default_args=default_args, start_date=datetime(2026, 1, 1),
    schedule="0 2 * * *",                       # daily 02:00
    catchup=False, max_active_runs=1, tags=["clv", "etl", "ml"],
) as dag:

    start = EmptyOperator(task_id="start")
    extract = BashOperator(task_id="generate_or_extract_raw",
                           bash_command=f"cd {PROJECT} && python 01_generate_data.py")
    etl = BashOperator(task_id="run_etl", bash_command=f"cd {PROJECT} && python 11_etl_pipeline.py",
                       env={"MYSQL_URL": "{{ var.value.get('mysql_url', '') }}"}, append_env=True)
    dq = PythonOperator(task_id="data_quality_gate", python_callable=quality_gate)
    eda = BashOperator(task_id="refresh_eda_charts", bash_command=f"cd {PROJECT} && python 06_eda_intermediate.py")
    eda_adv = BashOperator(task_id="refresh_eda_advanced", bash_command=f"cd {PROJECT} && python 07_eda_advanced.py")
    model = BashOperator(task_id="train_and_score", bash_command=f"cd {PROJECT} && python 12_clv_model.py")
    summary = PythonOperator(task_id="export_segment_summary", python_callable=export_summary)
    bi = BashOperator(task_id="refresh_bi_extracts",
                      bash_command=f"cd {PROJECT} && python 14_build_excel_report.py && echo 'Power BI/Tableau read data/processed/clv_predictions.csv'")
    end = EmptyOperator(task_id="end", trigger_rule="all_done")

    start >> extract >> etl >> dq >> [eda, model]
    eda >> eda_adv >> end
    model >> summary >> bi >> end

# Run locally:   airflow standalone     |  Test one task: airflow tasks test clv_pipeline run_etl 2026-01-01
