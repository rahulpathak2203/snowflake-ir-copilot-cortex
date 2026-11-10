-- =====================================================================
-- Do-it-yourself RAG in Snowflake - WITHOUT Cortex Search
-- Embeddings (AI_EMBED) + VECTOR column + cosine similarity + AI_COMPLETE
-- Prerequisite: DOC_CHUNKS from 01_search_pipeline.sql (Steps 0-4)
-- =====================================================================
USE ROLE SYSADMIN;
USE WAREHOUSE IR_WH;
USE SCHEMA IR_COPILOT.FUND_DOCS;

-- ---------------------------------------------------------------------
-- STEP 1. Embed every chunk once and store the vectors
--   Model snowflake-arctic-embed-l-v2.0 outputs 1024 numbers per text,
--   so the column type is VECTOR(FLOAT, 1024).
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CHUNK_EMBEDDINGS (
  chunk_uid   STRING,
  file_name   STRING,
  doc_type    STRING,
  period      STRING,
  sector      STRING,
  chunk_text  STRING,
  embedding   VECTOR(FLOAT, 1024)
);

INSERT INTO CHUNK_EMBEDDINGS
SELECT chunk_uid, file_name, doc_type, period, sector, chunk_text,
       AI_EMBED('snowflake-arctic-embed-l-v2.0', chunk_text)
FROM DOC_CHUNKS;

SELECT COUNT(*) AS chunks_embedded FROM CHUNK_EMBEDDINGS;   -- should equal rows in DOC_CHUNKS

-- ---------------------------------------------------------------------
-- STEP 2. Retrieval: embed the question with the SAME model,
--         then rank chunks by cosine similarity (1 = same meaning)
-- ---------------------------------------------------------------------
SET question = 'What is the net IRR without the subscription credit facility?';

WITH q AS (
  SELECT AI_EMBED('snowflake-arctic-embed-l-v2.0', $question) AS qv
)
SELECT e.file_name,
       ROUND(VECTOR_COSINE_SIMILARITY(e.embedding, q.qv), 4) AS similarity,
       LEFT(e.chunk_text, 200) AS preview
FROM CHUNK_EMBEDDINGS e, q
ORDER BY similarity DESC
LIMIT 5;

-- 2b. Same search, restricted with metadata (a plain WHERE clause)
SET question = 'Why was a portfolio company written down?';

WITH q AS (
  SELECT AI_EMBED('snowflake-arctic-embed-l-v2.0', $question) AS qv
)
SELECT e.file_name,
       ROUND(VECTOR_COSINE_SIMILARITY(e.embedding, q.qv), 4) AS similarity,
       LEFT(e.chunk_text, 200) AS preview
FROM CHUNK_EMBEDDINGS e, q
WHERE e.doc_type = 'quarterly_letter'
  AND e.period   = '2026-Q3'
ORDER BY similarity DESC
LIMIT 3;

-- ---------------------------------------------------------------------
-- STEP 3. Full RAG in one query: retrieve top 4 -> build context -> generate
--   Swap the model if not available in your region (e.g. 'mistral-large2').
-- ---------------------------------------------------------------------
SET question = 'Who triggers the key person clause and what happens if it is triggered?';

WITH q AS (
  SELECT AI_EMBED('snowflake-arctic-embed-l-v2.0', $question) AS qv
),
hits AS (
  SELECT e.file_name, e.chunk_text,
         VECTOR_COSINE_SIMILARITY(e.embedding, q.qv) AS similarity
  FROM CHUNK_EMBEDDINGS e, q
  ORDER BY similarity DESC
  LIMIT 4
),
ctx AS (
  SELECT LISTAGG('SOURCE: ' || file_name || '\n' || chunk_text, '\n\n---\n\n')
           WITHIN GROUP (ORDER BY similarity DESC) AS context,
         ARRAY_AGG(DISTINCT file_name) AS sources
  FROM hits
)
SELECT
  AI_COMPLETE(
    'claude-sonnet-4-5',
    'You are an investor relations assistant for Halvoran Ridge Capital. '
    || 'Answer ONLY from the context below and cite the SOURCE file name for each fact. '
    || 'If the answer is not in the context, say you could not find it.\n\n'
    || 'CONTEXT:\n' || context || '\n\nQUESTION: ' || $question
  ) AS answer,
  sources
FROM ctx;

-- ---------------------------------------------------------------------
-- STEP 4. Reusable procedure: CALL ASK_FUND_DOCS('your question');
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ASK_FUND_DOCS(
    QUESTION         STRING,
    TOP_K            INT    DEFAULT 4,
    DOC_TYPE_FILTER  STRING DEFAULT NULL     -- e.g. 'ddq', 'quarterly_letter'
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
  ctx     STRING;
  srcs    ARRAY;
  prompt  STRING;
  answer  STRING;
BEGIN
  -- Retrieve: top-k most similar chunks (optionally filtered by doc_type)
  WITH q AS (
    SELECT AI_EMBED('snowflake-arctic-embed-l-v2.0', :QUESTION) AS qv
  ),
  hits AS (
    SELECT e.file_name, e.chunk_text,
           VECTOR_COSINE_SIMILARITY(e.embedding, q.qv) AS similarity
    FROM CHUNK_EMBEDDINGS e, q
    WHERE :DOC_TYPE_FILTER IS NULL OR e.doc_type = :DOC_TYPE_FILTER
    QUALIFY ROW_NUMBER() OVER (ORDER BY similarity DESC) <= :TOP_K
  )
  SELECT LISTAGG('SOURCE: ' || file_name || '\n' || chunk_text, '\n\n---\n\n')
           WITHIN GROUP (ORDER BY similarity DESC),
         ARRAY_AGG(DISTINCT file_name)
    INTO :ctx, :srcs
  FROM hits;

  IF (ctx IS NULL) THEN
    RETURN OBJECT_CONSTRUCT('answer', 'No matching documents found.', 'sources', ARRAY_CONSTRUCT());
  END IF;

  -- Generate: answer only from the retrieved chunks
  prompt := 'You are an investor relations assistant for Halvoran Ridge Capital. '
         || 'Answer ONLY from the context below and cite the SOURCE file name for each fact. '
         || 'If the answer is not in the context, say you could not find it.\n\n'
         || 'CONTEXT:\n' || ctx || '\n\nQUESTION: ' || QUESTION;

  SELECT AI_COMPLETE('claude-sonnet-4-5', :prompt) INTO :answer;

  RETURN OBJECT_CONSTRUCT('answer', answer, 'sources', srcs);
END;
$$;

-- Try it
CALL ASK_FUND_DOCS('Who triggers the key person clause?');
CALL ASK_FUND_DOCS('What are the ESG exclusions?');
CALL ASK_FUND_DOCS('What is the management fee?', 3, 'fees_terms');

-- ---------------------------------------------------------------------
-- STEP 5. Keep it up to date: embed only chunks not embedded yet
--   (run after new documents are parsed and chunked)
-- ---------------------------------------------------------------------
INSERT INTO CHUNK_EMBEDDINGS
SELECT d.chunk_uid, d.file_name, d.doc_type, d.period, d.sector, d.chunk_text,
       AI_EMBED('snowflake-arctic-embed-l-v2.0', d.chunk_text)
FROM DOC_CHUNKS d
WHERE d.chunk_uid NOT IN (SELECT chunk_uid FROM CHUNK_EMBEDDINGS);
