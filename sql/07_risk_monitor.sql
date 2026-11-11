-- =====================================================================
-- Halvoran Ridge Capital - Portfolio Risk Monitor (agentic workflow)
-- A scheduled agent that checks portfolio companies against risk thresholds,
-- investigates flagged ones in the documents, drafts an alert and logs it
-- for a human to review. It never sends anything itself.
-- Prerequisites: 01-04 already run (search service, fund tables, semantic view).
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE IR_WH;
USE SCHEMA IR_COPILOT.FUND_DOCS;

-- ---------------------------------------------------------------------
-- STEP 1. Risk thresholds (one row; change values without touching code)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE RISK_THRESHOLDS (
  max_leverage              NUMBER(5,1),   -- flag if net debt / EBITDA is above this
  max_leverage_increase     NUMBER(5,1),   -- flag if leverage rises more than this in one quarter
  max_revenue_decline_pct   NUMBER(5,1),   -- flag if LTM revenue falls more than this % in one quarter
  max_margin_drop_pts       NUMBER(5,1)    -- flag if EBITDA margin falls more than this many points
);
INSERT INTO RISK_THRESHOLDS VALUES (5.5, 0.5, 5.0, 1.0);

-- ---------------------------------------------------------------------
-- STEP 2. Where alerts are stored for human review, and a run log
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE RISK_ALERTS (
  alert_id         STRING    DEFAULT UUID_STRING(),
  created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  company_name     STRING,
  period           STRING,
  rules_triggered  STRING,
  alert_text       STRING,
  sources          STRING,
  status           STRING    DEFAULT 'PENDING_REVIEW',   -- PENDING_REVIEW / CONFIRMED / DISMISSED
  reviewed_by      STRING,
  reviewed_at      TIMESTAMP
);

CREATE OR REPLACE TABLE RISK_MONITOR_RUNS (
  run_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
  response  VARIANT                                    -- the agent's full response, for audit
);

-- ---------------------------------------------------------------------
-- STEP 3. Tool 1 - GET_RISK_FLAGS: deterministic threshold check (plain SQL, no AI)
--   Compares each company's quarter with the previous one.
--   Returns JSON: {"period": ..., "flagged_companies": [{company, metrics, rules_triggered}]}
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE GET_RISK_FLAGS(TARGET_PERIOD STRING DEFAULT NULL)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  p       STRING;
  result  STRING;
BEGIN
  -- Use the requested quarter, or the latest one available
  IF (TARGET_PERIOD IS NOT NULL) THEN
    p := TARGET_PERIOD;
  ELSE
    SELECT MAX(period) INTO :p FROM COMPANY_FINANCIALS;
  END IF;

  WITH f AS (
    SELECT company_name, period,
           ltm_revenue_musd                                      AS rev,
           net_debt_to_ebitda                                    AS lev,
           ltm_ebitda_musd / NULLIF(ltm_revenue_musd, 0) * 100   AS margin,
           LAG(ltm_revenue_musd)   OVER (PARTITION BY company_name ORDER BY quarter_end_date) AS prev_rev,
           LAG(net_debt_to_ebitda) OVER (PARTITION BY company_name ORDER BY quarter_end_date) AS prev_lev,
           LAG(ltm_ebitda_musd / NULLIF(ltm_revenue_musd, 0) * 100)
                                   OVER (PARTITION BY company_name ORDER BY quarter_end_date) AS prev_margin
    FROM COMPANY_FINANCIALS
  ),
  checked AS (
    SELECT f.company_name, f.period, f.rev, f.prev_rev, f.lev, f.prev_lev,
           ROUND(f.margin, 1) AS margin, ROUND(f.prev_margin, 1) AS prev_margin,
           ARRAY_CONSTRUCT_COMPACT(
             IFF(f.lev > t.max_leverage,
                 'Leverage ' || f.lev || 'x is above the ' || t.max_leverage || 'x limit', NULL),
             IFF(f.lev - f.prev_lev > t.max_leverage_increase,
                 'Leverage rose ' || (f.lev - f.prev_lev) || 'x in the quarter (' || f.prev_lev || 'x to ' || f.lev || 'x)', NULL),
             IFF((f.rev - f.prev_rev) / f.prev_rev * 100 < -t.max_revenue_decline_pct,
                 'LTM revenue fell ' || ROUND((f.prev_rev - f.rev) / f.prev_rev * 100, 1) || '% ($' || f.prev_rev || 'm to $' || f.rev || 'm)', NULL),
             IFF(f.margin - f.prev_margin < -t.max_margin_drop_pts,
                 'EBITDA margin fell ' || ROUND(f.prev_margin - f.margin, 1) || ' points (' || ROUND(f.prev_margin, 1) || '% to ' || ROUND(f.margin, 1) || '%)', NULL)
           ) AS rules_triggered
    FROM f CROSS JOIN RISK_THRESHOLDS t
    WHERE f.period = :p
  )
  SELECT TO_JSON(OBJECT_CONSTRUCT(
           'period', :p,
           'flagged_companies', COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT(
               'company_name', company_name,
               'leverage', lev, 'previous_leverage', prev_lev,
               'ltm_revenue_musd', rev, 'previous_ltm_revenue_musd', prev_rev,
               'ebitda_margin_pct', margin, 'previous_ebitda_margin_pct', prev_margin,
               'rules_triggered', rules_triggered)), ARRAY_CONSTRUCT())))
    INTO :result
  FROM checked
  WHERE ARRAY_SIZE(rules_triggered) > 0;

  RETURN result;
END;
$$;

-- Test the tool on its own (expect only Ostrava Packaging for 2026-Q3)
CALL GET_RISK_FLAGS('2026-Q3');

-- ---------------------------------------------------------------------
-- STEP 4. Tool 2 - LOG_RISK_ALERT: the only action the agent can take
--   Writes one row for human review. Skips duplicates, so re-runs are safe.
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE LOG_RISK_ALERT(
    COMPANY_NAME     STRING,
    PERIOD           STRING,
    RULES_TRIGGERED  STRING,
    ALERT_TEXT       STRING,
    SOURCES          STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
  existing INTEGER;
BEGIN
  SELECT COUNT(*) INTO :existing
  FROM RISK_ALERTS
  WHERE company_name = :COMPANY_NAME AND period = :PERIOD;

  IF (existing > 0) THEN
    RETURN 'Alert already logged for ' || COMPANY_NAME || ' (' || PERIOD || '); nothing added.';
  END IF;

  INSERT INTO RISK_ALERTS (company_name, period, rules_triggered, alert_text, sources)
  VALUES (:COMPANY_NAME, :PERIOD, :RULES_TRIGGERED, :ALERT_TEXT, :SOURCES);

  RETURN 'Alert logged for ' || COMPANY_NAME || ' (' || PERIOD || '), status PENDING_REVIEW.';
END;
$$;

-- ---------------------------------------------------------------------
-- STEP 5. The risk monitor agent: 4 tools and a step-by-step workflow
--   Separate from IR Copilot, which stays read-only for investor questions.
--   If the custom tool YAML is rejected in your account, add the two procedures
--   as custom tools in Snowsight instead (AI & ML > Agents > edit > Tools > Custom tools).
-- ---------------------------------------------------------------------
CREATE OR REPLACE AGENT IR_COPILOT.FUND_DOCS.IR_RISK_MONITOR_AGENT
  COMMENT = 'Quarterly portfolio risk review: flags companies, investigates causes, logs alerts for human review'
  PROFILE = '{"display_name": "Portfolio Risk Monitor"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto
instructions:
  system: |
    You are a portfolio risk analyst for Halvoran Ridge Capital Fund IV.
    Your job is to review portfolio companies after each quarter, explain any risks you find using the fund's documents,
    and log alerts for the deal team to review. You never send messages or take any other action than logging alerts.
  orchestration: |
    Follow these steps in order:
    1. Call get_risk_flags. Pass target_period only if the request names a quarter; otherwise leave it empty to use the latest quarter.
    2. If no companies are flagged, report that no alerts are needed and stop. Do not log anything.
    3. For EACH flagged company:
       a. Call fund_docs_search with the company name and the period to find why its numbers moved
          (e.g. "<company> <period> reason write-down contract revenue").
       b. Judge the result. If it does not explain the movement, search once more with different wording
          (e.g. the company name with "outlook", "CEO", "customer"). If there is still no explanation,
          state "No explanation found in the fund documents."
       c. Optionally call fund_data_analyst for the company's quarterly revenue, EBITDA and leverage trend.
       d. Write an alert of at most 120 words: the rules triggered with the numbers, the likely cause with its source document,
          and one suggested next step for the deal team, phrased as a suggestion.
       e. Call log_risk_alert exactly once for the company, with the rules triggered, the alert text and the source document names.
    4. Finish with a short summary listing each company reviewed and whether an alert was logged.
  response: |
    Be factual and concise. Use only numbers from get_risk_flags or fund_data_analyst and reasons from fund_docs_search.
    Never invent a cause. Never log alerts for companies that get_risk_flags did not flag.
tools:
  - tool_spec:
      type: generic
      name: get_risk_flags
      description: "Checks every portfolio company's latest quarter against the fund's risk thresholds (leverage level, leverage increase, revenue decline, EBITDA margin drop) and returns the flagged companies with their numbers and the rules they triggered."
      input_schema:
        type: object
        properties:
          target_period:
            type: string
            description: "Quarter to check, in the format YYYY-QN (e.g. 2026-Q3). Leave empty for the latest quarter."
  - tool_spec:
      type: cortex_search
      name: fund_docs_search
      description: "Searches Fund IV documents: quarterly investor letters, portfolio company profiles, policies and DDQ responses. Use it to find the reasons behind a company's performance."
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: fund_data_analyst
      description: "Answers numeric questions with SQL over Fund IV data, including each portfolio company's quarterly LTM revenue, EBITDA, margin and leverage."
  - tool_spec:
      type: generic
      name: log_risk_alert
      description: "Saves one risk alert for human review (status PENDING_REVIEW). This is the only action available. Call it once per flagged company."
      input_schema:
        type: object
        properties:
          company_name:
            type: string
            description: "Portfolio company name exactly as returned by get_risk_flags"
          period:
            type: string
            description: "Quarter, e.g. 2026-Q3"
          rules_triggered:
            type: string
            description: "The rules triggered, with numbers, separated by semicolons"
          alert_text:
            type: string
            description: "The alert for the deal team, at most 120 words"
          sources:
            type: string
            description: "Source document file names used, separated by commas"
        required: [company_name, period, rules_triggered, alert_text, sources]
tool_resources:
  get_risk_flags:
    type: procedure
    identifier: IR_COPILOT.FUND_DOCS.GET_RISK_FLAGS
    execution_environment:
      type: warehouse
      warehouse: IR_WH
  fund_docs_search:
    search_service: IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH
    id_column: chunk_uid
    title_column: file_name
    max_results: 5
  fund_data_analyst:
    semantic_view: IR_COPILOT.FUND_DOCS.FUND_ANALYTICS_SV
    execution_environment:
      type: warehouse
      warehouse: IR_WH
  log_risk_alert:
    type: procedure
    identifier: IR_COPILOT.FUND_DOCS.LOG_RISK_ALERT
    execution_environment:
      type: warehouse
      warehouse: IR_WH
$$;

-- ---------------------------------------------------------------------
-- STEP 6. Run it once now (no one types a question in a chat: SQL starts the agent)
-- ---------------------------------------------------------------------
INSERT INTO RISK_MONITOR_RUNS (response)
SELECT TRY_PARSE_JSON(
  SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'IR_COPILOT.FUND_DOCS.IR_RISK_MONITOR_AGENT',
    $${"messages": [{"role": "user", "content": [{"type": "text",
        "text": "Run the quarterly portfolio risk review for the latest quarter."}]}]}$$
  )
);

-- What did it do?
SELECT company_name, period, rules_triggered, alert_text, sources, status
FROM RISK_ALERTS ORDER BY created_at DESC;

SELECT run_at, response FROM RISK_MONITOR_RUNS ORDER BY run_at DESC LIMIT 1;   -- full trace

-- ---------------------------------------------------------------------
-- STEP 7. Schedule it: runs automatically after each quarter
--   Tasks need the EXECUTE TASK privilege; ACCOUNTADMIN grants it once.
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE SYSADMIN;
USE ROLE SYSADMIN;

CREATE OR REPLACE TASK IR_COPILOT.FUND_DOCS.QUARTERLY_RISK_REVIEW
  WAREHOUSE = IR_WH
  SCHEDULE  = 'USING CRON 0 9 15 1,4,7,10 * Asia/Kolkata'   -- 09:00 on the 15th of Jan, Apr, Jul, Oct
  COMMENT   = 'Runs the portfolio risk monitor agent after each quarter'
AS
  INSERT INTO IR_COPILOT.FUND_DOCS.RISK_MONITOR_RUNS (response)
  SELECT TRY_PARSE_JSON(
    SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
      'IR_COPILOT.FUND_DOCS.IR_RISK_MONITOR_AGENT',
      $${"messages": [{"role": "user", "content": [{"type": "text",
          "text": "Run the quarterly portfolio risk review for the latest quarter."}]}]}$$
    )
  );

ALTER TASK IR_COPILOT.FUND_DOCS.QUARTERLY_RISK_REVIEW RESUME;   -- tasks are created suspended

-- Demo: trigger it now instead of waiting for the schedule, then check its history
EXECUTE TASK IR_COPILOT.FUND_DOCS.QUARTERLY_RISK_REVIEW;
SELECT name, state, error_message, scheduled_time, completed_time
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(TASK_NAME => 'QUARTERLY_RISK_REVIEW'))
ORDER BY scheduled_time DESC;

-- To stop the schedule: ALTER TASK IR_COPILOT.FUND_DOCS.QUARTERLY_RISK_REVIEW SUSPEND;

-- ---------------------------------------------------------------------
-- STEP 8. Human review: the deal team confirms or dismisses each alert
-- ---------------------------------------------------------------------
SELECT alert_id, company_name, period, rules_triggered, alert_text
FROM RISK_ALERTS WHERE status = 'PENDING_REVIEW';

-- UPDATE RISK_ALERTS
-- SET status = 'CONFIRMED', reviewed_by = CURRENT_USER(), reviewed_at = CURRENT_TIMESTAMP()
-- WHERE alert_id = '<alert_id>';
