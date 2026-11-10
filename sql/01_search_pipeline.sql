-- =====================================================================
-- Halvoran Ridge Capital - Investor Relations Copilot
-- Cortex Search pipeline: PDFs -> parse -> chunk -> search service -> RAG
-- Run top to bottom in a Snowsight SQL worksheet.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 0. Setup
-- ---------------------------------------------------------------------
USE ROLE SYSADMIN;   -- needs a role with CREATE DATABASE + SNOWFLAKE.CORTEX_USER

CREATE DATABASE IF NOT EXISTS IR_COPILOT;
CREATE SCHEMA   IF NOT EXISTS IR_COPILOT.FUND_DOCS;
USE SCHEMA IR_COPILOT.FUND_DOCS;

CREATE WAREHOUSE IF NOT EXISTS IR_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
USE WAREHOUSE IR_WH;

-- Server-side encryption + directory table are required for AI_PARSE_DOCUMENT
CREATE STAGE IF NOT EXISTS FUND_PDFS
  DIRECTORY  = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

-- ---------------------------------------------------------------------
-- STEP 1. Upload the 10 PDFs
--   Easiest: Snowsight > Data > IR_COPILOT > FUND_DOCS > Stages > FUND_PDFS
--            > "+ Files" and drag all 10 PDFs in.
--   Or SnowSQL / Snowflake CLI:
--   PUT file:///path/to/halvoran_ridge_docs/*.pdf @FUND_PDFS AUTO_COMPRESS = FALSE;
-- ---------------------------------------------------------------------
ALTER STAGE FUND_PDFS REFRESH;
SELECT relative_path, size FROM DIRECTORY(@FUND_PDFS);   -- expect 10 rows

-- ---------------------------------------------------------------------
-- STEP 2. Document metadata (same content as document_manifest.csv)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DOC_METADATA (
  file_name STRING, fund STRING, doc_type STRING, period STRING, sector STRING, description STRING
);
INSERT INTO DOC_METADATA VALUES
 ('01_Fund_IV_Overview.pdf','Fund IV','fund_overview','2026-Q3','All','Firm overview, Fund IV terms, strategy, track record, team'),
 ('02_Fund_IV_Q4_2025_Investor_Letter.pdf','Fund IV','quarterly_letter','2025-Q4','All','Q4 2025 performance, portfolio highlights, outlook'),
 ('03_Fund_IV_Q1_2026_Investor_Letter.pdf','Fund IV','quarterly_letter','2026-Q1','All','Q1 2026 performance, portfolio highlights, outlook'),
 ('04_Fund_IV_Q2_2026_Investor_Letter.pdf','Fund IV','quarterly_letter','2026-Q2','All','Q2 2026 performance, portfolio highlights, outlook'),
 ('05_Fund_IV_Q3_2026_Investor_Letter.pdf','Fund IV','quarterly_letter','2026-Q3','All','Q3 2026 performance, portfolio highlights, outlook'),
 ('06_ESG_Responsible_Investment_Policy.pdf','Fund IV','policy_esg','2026','All','ESG governance, exclusions, climate targets, DEI, reporting'),
 ('07_Valuation_Policy.pdf','Fund IV','policy_valuation','2025','All','Fair value methods, governance, controls, disclosure'),
 ('08_Fund_IV_Fee_and_Expense_Summary.pdf','Fund IV','fees_terms','2023','All','Management fee, carry, waterfall, offsets, expenses, key person'),
 ('09_Fund_IV_Portfolio_Company_Profiles.pdf','Fund IV','portfolio_profiles','2026-Q3','Healthcare; Infrastructure; Software','Profiles of Tessaline, Corvane, Pellucid, Meridale'),
 ('10_Due_Diligence_Questionnaire_Responses.pdf','Fund IV','ddq','2026-Q2','All','Standard ILPA DDQ answers: organisation, process, risk, ESG, reporting');

-- ---------------------------------------------------------------------
-- STEP 3. Parse PDFs (LAYOUT mode keeps tables + headings as markdown)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE PARSED_DOCS AS
SELECT
  relative_path AS file_name,
  AI_PARSE_DOCUMENT(
      TO_FILE('@FUND_PDFS', relative_path),
      {'mode': 'LAYOUT'}
  ):content::STRING AS doc_text
FROM DIRECTORY(@FUND_PDFS)
WHERE relative_path ILIKE '%.pdf';

-- Clean-up: remove repeated page footers and HTML entities left by parsing
UPDATE PARSED_DOCS
SET doc_text =
  REPLACE(REPLACE(REPLACE(doc_text,
    'Halvoran Ridge Capital | Confidential - Limited Partner use only', ''),
    'FICTIONAL SAMPLE DOCUMENT created for a demo project. Firm, fund, companies and figures are invented.', ''),
    '&amp;', '&');

-- Sanity check: every doc should have a few thousand characters
SELECT file_name, LENGTH(doc_text) AS chars, LEFT(doc_text, 300) AS preview
FROM PARSED_DOCS ORDER BY file_name;

-- ---------------------------------------------------------------------
-- STEP 4. Chunk + attach metadata
--   ~1,500 chars per chunk with 200 overlap; markdown-aware splitting.
--   File name is prefixed to each chunk so the retriever "knows" the source.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE DOC_CHUNKS AS
SELECT
  p.file_name,
  m.fund, m.doc_type, m.period, m.sector,
  c.index                                         AS chunk_id,
  p.file_name || '#' || c.index                   AS chunk_uid,   -- unique id across all docs
  '[' || REPLACE(p.file_name, '.pdf', '') || '] ' || c.value::STRING AS chunk_text
FROM PARSED_DOCS p
JOIN DOC_METADATA m ON m.file_name = p.file_name,
LATERAL FLATTEN(
  input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(p.doc_text, 'markdown', 1500, 200)
) c;

SELECT doc_type, COUNT(*) AS chunks FROM DOC_CHUNKS GROUP BY doc_type ORDER BY 1;

-- ---------------------------------------------------------------------
-- STEP 5. Create the Cortex Search service
--   ATTRIBUTES = columns you can filter on at query time
-- ---------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE FUND_DOCS_SEARCH
  ON chunk_text
  ATTRIBUTES fund, doc_type, period, sector
  WAREHOUSE = IR_WH
  TARGET_LAG = '1 day'
  AS (
    SELECT chunk_text, file_name, chunk_id, chunk_uid, fund, doc_type, period, sector
    FROM DOC_CHUNKS
  );

SHOW CORTEX SEARCH SERVICES;   -- wait until indexing_state = ACTIVE

-- ---------------------------------------------------------------------
-- STEP 6. Test retrieval
-- ---------------------------------------------------------------------
-- 6a. Plain question
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH',
    '{"query": "What is the net IRR without the subscription credit facility?",
      "columns": ["file_name","chunk_text"], "limit": 3}'
  )
):results AS results;

-- 6b. With a metadata filter: only the Q3 2026 letter
SELECT PARSE_JSON(
  SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH',
    '{"query": "Why was a portfolio company written down?",
      "columns": ["file_name","chunk_text"],
      "filter": {"@and": [{"@eq": {"doc_type": "quarterly_letter"}}, {"@eq": {"period": "2026-Q3"}}]},
      "limit": 3}'
  )
):results AS results;

-- ---------------------------------------------------------------------
-- STEP 7. Full RAG answer in SQL (retrieve -> generate with citations)
--   Swap the model for one enabled in your region if needed
--   (e.g. 'claude-sonnet-4-5', 'mistral-large2', 'llama3.1-70b').
-- ---------------------------------------------------------------------
SET question = 'Who triggers the key person clause and what happens if it is triggered?';

WITH hits AS (
  SELECT r.value:file_name::STRING AS file_name,
         r.value:chunk_text::STRING AS chunk_text
  FROM TABLE(FLATTEN(
    PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
      'IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH',
      -- SEARCH_PREVIEW needs a constant string: keep this query text in sync with $question
      '{"query": "Who triggers the key person clause and what happens if it is triggered?",
        "columns": ["file_name","chunk_text"], "limit": 4}'
    )):results
  )) r
),
ctx AS (
  SELECT LISTAGG('SOURCE: ' || file_name || '\n' || chunk_text, '\n\n---\n\n') AS context,
         ARRAY_AGG(DISTINCT file_name) AS sources
  FROM hits
)
SELECT
  AI_COMPLETE(
    'claude-sonnet-4-5',
    'You are an investor relations assistant for Halvoran Ridge Capital. '
    || 'Answer ONLY from the context below. Cite the SOURCE file name for each fact. '
    || 'If the answer is not in the context, say you could not find it.\n\n'
    || 'CONTEXT:\n' || context || '\n\nQUESTION: ' || $question
  ) AS answer,
  sources
FROM ctx;
