# Data Analyst & Engineering
End-to-end CLV analytics project: Python and SQL ETL pipeline, EDA, a predictive CLV model, Airflow orchestration and Power BI, Tableau and Excel dashboards for customer segmentation.

End-to-end analytics project: an ETL pipeline in Python and SQL processes customer transaction data, a predictive model estimates each customer's next 6-month value and Power BI / Tableau / Excel dashboards turn the results into customer segments.

## Tech stack
Python · Pandas · NumPy · SciPy · Scikit-learn · Statsmodels · Matplotlib · Seaborn · MySQL 8 · Apache Airflow · Power BI · Tableau · Excel (openpyxl) · Google Colab

## Pipeline
```
Raw CSVs -> Extract -> Clean & Validate -> RFM features -> MySQL (star schema)
                                                |
                         EDA  ->  CLV model (6-month holdout)  ->  Segments
                                                |
                       Airflow (daily)  ->  Excel / Tableau / Power BI
