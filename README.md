# IR Copilot: Investor Relations Q&A on Snowflake Cortex

An AI assistant that answers investor and due-diligence questions about a private equity fund. It combines **document search** (Cortex Search over fund PDFs) with **SQL over fund data** (Cortex Analyst over a semantic view), and a **Cortex Agent** decides which to use for each question, or uses both. It's also available to external AI assistants (Claude, ChatGPT, Cursor) through a **Snowflake-managed MCP server**, and the repo includes a **custom RAG** built without Cortex Search (embeddings + vector similarity) to compare against the managed service. A **portfolio risk monitor** takes it from question-answering to an **agentic workflow**: a scheduled agent flags at-risk companies, investigates why in the documents, and logs alerts for the deal team to review. A **Streamlit in Snowflake** app handles bulk DDQ drafting.

> All documents describe a **fictional** firm (Halvoran Ridge Capital) and fund (Fund IV). Every company, person and figure is invented.

## The business problem

Private markets firms raise money from institutional investors (LPs) such as pension funds and sovereign wealth funds. Every LP sends due-diligence questionnaires (DDQs) and ad-hoc questions about strategy, fees, ESG, valuation and performance. The answers already exist, scattered across fund decks, quarterly letters, policies and past DDQs. Investor Relations teams spend weeks finding them and keeping answers consistent.

**IR Copilot** finds the approved answer in the fund's documents, pulls exact figures from the fund's data, cites its sources and drafts DDQ responses in bulk.

## Architecture

```
PDFs (internal stage)
   │  AI_PARSE_DOCUMENT  (LAYOUT mode → markdown, tables preserved)
   ▼
PARSED_DOCS  ── clean-up (footers, HTML entities)
   │  SPLIT_TEXT_RECURSIVE_CHARACTER  (markdown-aware, 1500 chars, 200 overlap)
   │  + join document metadata (doc_type, period, sector)
   ▼
DOC_CHUNKS ──────────────────────────────┐
   │                                     │  Custom RAG (no Cortex Search):
   │                                     │  AI_EMBED → VECTOR column → cosine
   │                                     │  similarity top-k → AI_COMPLETE
   │                                     ▼  CALL ASK_FUND_DOCS('question')
   │  CREATE CORTEX SEARCH SERVICE  (hybrid: vector + keyword + reranker)
   ▼
FUND_DOCS_SEARCH  ── filter attributes: fund, doc_type, period, sector
   │
   │      FUND_PERFORMANCE · PORTFOLIO_COMPANIES · COMPANY_FINANCIALS
   │         │  CREATE SEMANTIC VIEW  (facts, dimensions, metrics, synonyms)
   │         ▼
   │      FUND_ANALYTICS_SV
   │         │
   ▼         ▼
 Cortex Agent ── routes each question:
   │   "why / what does it say"  → Cortex Search  (documents)
   │   "how much / trend / rank" → Cortex Analyst (SQL)
   │   both in one question      → calls both and combines
   ├── chat in Snowflake Intelligence
   ├── Streamlit app → chat + bulk DDQ drafting with CSV export
   └── Snowflake-managed MCP server  (OAuth, least-privilege role)
          └── Claude / ChatGPT / Cursor call the agent, search and analyst as tools

 Scheduled task (quarterly) ── DATA_AGENT_RUN ──▶ Risk Monitor Agent
   1. get_risk_flags     deterministic SQL threshold check  → Ostrava flagged
   2. fund_docs_search   why did the numbers move?          → lost contract, new CEO
   3. fund_data_analyst  optional trend context
   4. log_risk_alert     write alert → RISK_ALERTS (PENDING_REVIEW) → human confirms / dismisses
```

## Custom RAG without Cortex Search

`sql/05_custom_rag.sql` builds the same retrieval-augmented generation by hand, to show what the managed service does underneath:

1. **Index:** each chunk is embedded with `AI_EMBED` (`snowflake-arctic-embed-l-v2.0`) and stored in a `VECTOR(FLOAT, 1024)` column.
2. **Retrieve:** the question is embedded with the same model; chunks are ranked by `VECTOR_COSINE_SIMILARITY` and the top k kept. Metadata filters are a plain `WHERE`.
3. **Augment:** the top chunks are concatenated into one context, each labelled with its source file.
4. **Generate:** one `AI_COMPLETE` call answers only from that context, with citations.

It's wrapped in a stored procedure: `CALL ASK_FUND_DOCS('question', top_k, doc_type_filter)`.

| | Custom RAG | Cortex Search |
|---|---|---|
| Matching | Meaning only (vectors) | Meaning + keywords + reranker |
| Index refresh | Manual (embed new chunks) | Automatic within target lag |
| Scale | Compares every chunk; fine for hundreds | Built for large-scale serving |
| Control | Full: model, scores, top-k, prompt | Managed |

## Agentic workflow: portfolio risk monitor

IR Copilot answers questions when asked. The risk monitor works **on its own**: a scheduled task starts an agent after each quarter with `SNOWFLAKE.CORTEX.DATA_AGENT_RUN`, and the agent works through a goal step by step.

1. **Check:** `get_risk_flags` compares every company with the previous quarter against configurable thresholds in `RISK_THRESHOLDS` (leverage above 5.5x, leverage up more than 0.5x, revenue down more than 5%, EBITDA margin down more than 1 point).
2. **Investigate:** for each flagged company, the agent writes its own search queries to find out why, judges whether the result explains the movement, and retries with different wording if it doesn't.
3. **Draft:** it writes a short alert with the numbers, the likely cause with its source, and a suggested next step.
4. **Act:** it calls `log_risk_alert`, which writes one row to `RISK_ALERTS` with status `PENDING_REVIEW`. The deal team confirms or dismisses it.

On the demo data, only **Ostrava Packaging** is flagged, on all four rules (leverage 5.0x → 5.9x, revenue −8.1%, margin 13.8% → 12.6%), and the agent links it to the lost customer contract described in the Q3 2026 letter.

Design choices:
- **Rules in SQL, judgement in the LLM:** threshold checks must give the same answer every time, so they're deterministic SQL. The agent handles what needs judgement: finding and checking explanations, and writing the alert.
- **One narrow action:** the agent's only action is logging an alert through a specific procedure. It can't send messages or change other data.
- **Human in the loop:** alerts wait for review; people stay accountable for decisions.
- **Safe to re-run:** `log_risk_alert` skips a company already logged for that quarter, so a retried task doesn't create duplicates. Every run's full response is kept in `RISK_MONITOR_RUNS` for audit.

## Access from AI assistants (MCP)

`sql/06_mcp_server.sql` exposes IR Copilot through a **Snowflake-managed MCP server** with three tools: the Cortex Agent, Cortex Search and Cortex Analyst. An IR analyst can ask questions from Claude (or any MCP client) without opening Snowflake, while Snowflake still governs every call:

- a dedicated role (`IR_MCP_ROLE`) with only the grants these tools need
- an OAuth integration restricted to that role, with secondary roles disabled; users sign in on Snowflake's own page
- each call runs as the analyst's own Snowflake user, so it's recorded in query history for audit

## Repository contents

| Path | What it is |
|---|---|
| `sql/01_search_pipeline.sql` | Stage → parse → clean → chunk → search service → retrieval tests → RAG answer in SQL |
| `sql/02_fund_data.sql` | Structured fund data: quarterly performance, portfolio companies, company financials |
| `sql/03_semantic_view.sql` | Semantic view that tells Cortex Analyst what each table, column and metric means |
| `sql/04_create_agent.sql` | Cortex Agent with both tools (Search + Analyst) and routing instructions |
| `sql/05_custom_rag.sql` | The same RAG built by hand: AI_EMBED + VECTOR column + cosine similarity + AI_COMPLETE, wrapped in a procedure |
| `sql/06_mcp_server.sql` | Snowflake-managed MCP server exposing the agent, search and analyst to external AI assistants (Claude, ChatGPT, Cursor), with a least-privilege role and OAuth |
| `sql/07_risk_monitor.sql` | Agentic workflow: risk thresholds, two custom tools (flag check, alert logging), a risk monitor agent, and a quarterly scheduled task |
| `app/streamlit_app.py` | Streamlit in Snowflake app: chat with sources, metadata filters, bulk DDQ drafting |
| `sample_data/` | 10 fictional fund PDFs (21 pages), `document_manifest.csv` with each PDF's metadata, and `generate_sample_docs.py` that generates them |
| `docs/screenshots/` | Screenshots of the agent, Snowflake Intelligence and Claude via MCP |

### Sample documents
Fund overview · 4 quarterly investor letters (Q4 2025 – Q3 2026) · ESG policy · Valuation policy · Fee & expense summary · Portfolio company profiles · Standard DDQ responses.

Figures are consistent across documents, so cross-document questions have real answers. For example, net IRR moves 12.1% → 12.8% → 13.4% → 14.0% across the four letters.

## How to run

1. Run `sql/01_search_pipeline.sql` step by step in a Snowsight worksheet. Your role needs the `SNOWFLAKE.CORTEX_USER` database role.
2. Upload the 10 PDFs from `sample_data/` to the `FUND_PDFS` stage (Snowsight: stage → **+ Files**).
3. Wait for the search service to show `ACTIVE` (`SHOW CORTEX SEARCH SERVICES`).
4. Run `sql/02_fund_data.sql`, then `sql/03_semantic_view.sql`.
5. **Agent:** run `sql/04_create_agent.sql`, then chat with *IR Copilot* in Snowflake Intelligence.
6. **Custom RAG (optional):** run `sql/05_custom_rag.sql`, then `CALL ASK_FUND_DOCS('your question');`
7. **MCP (optional):** run `sql/06_mcp_server.sql`, then add the endpoint as a custom connector in Claude.
8. **Risk monitor (optional):** run `sql/07_risk_monitor.sql`, then check `RISK_ALERTS` for the logged alert.
9. **App (optional):** create a Streamlit app in `IR_COPILOT.FUND_DOCS` and paste in `app/streamlit_app.py`.

## Design decisions

- **LAYOUT parsing:** fund documents are table-heavy (IRR, fees, portfolio). Layout mode keeps tables as markdown, so values stay attached to their labels.
- **Markdown-aware chunking (1500 / 200):** chunks follow headings, so a section stays together. The size is about 375 tokens, within Cortex Search's recommended limit of roughly 512 tokens. Overlap carries whole paragraphs across cuts.
- **Source label in each chunk:** every chunk starts with `[document name]`, so retrieval and the LLM always know which document and quarter a fact came from.
- **Metadata filters:** `doc_type` and `period` let users restrict answers, e.g. "Q3 2026 letter only".
- **Cleaning before chunking:** repeated page footers were polluting chunks and retrieval, so they're stripped after parsing.
- **Two tools, one agent:** text search is good at explanations but poor at arithmetic across documents (e.g. summing four letters). Numeric, trend and ranking questions go to Cortex Analyst, which writes SQL against a semantic view; the agent's orchestration instructions define the routing.
- **Structured data matches the documents:** fund-level figures and invested amounts equal those in the PDFs, so the two tools never contradict each other.
- **Semantic view with synonyms:** IRR, TVPI, DPI, NAV and leverage carry business synonyms and comments, so questions in investor language map to the right columns. Metrics that must not be summed across quarters (NAV, LTM figures) say so in their comments.

- **MCP access with least privilege:** external assistants connect through OAuth restricted to a dedicated role (`IR_MCP_ROLE`) with secondary roles disabled. Access to the MCP server doesn't unlock its tools; each underlying object has its own grant.
- **Lessons from the MCP rollout:** Snowflake doesn't support automatic OAuth client registration, so the client ID is entered in the connector manually. Outside Snowsight there's no session warehouse, so the agent's analyst tool needs an explicit `execution_environment`. `CREATE OR REPLACE` drops grants, so the agent script re-grants MCP access.

## Results

Agent answers checked against the source documents:

| Question | Result |
|---|---|
| Net IRR with and without the credit facility? | ✅ 13.4% / 12.6%. Combined 3 documents and noted no without-facility figure exists for Q3 |
| Why was Ostrava Packaging written down? | ✅ 15% in Q3 2026 after losing a major contract; new CEO. Stated what the documents don't say |
| Who triggers the key person clause? | ✅ Two of three named partners → investment period suspended |
| What are the ESG exclusions? | ✅ All 5 categories and the 10% revenue threshold |

**Retrieval test** (`SEARCH_PREVIEW`, "net IRR without the subscription credit facility"): the answer chunk ranked #2, behind a DDQ chunk that matched the question's keywords more closely. DDQ chunks hold several Q&As each, which dilutes a single answer. Smaller chunks for Q&A-style documents should move it to #1.

### Routing test set (Search + Analyst)
| Question | Expected tool | Expected answer |
|---|---|---|
| How has net IRR changed over the last four quarters? | Analyst | 12.1% → 12.8% → 13.4% → 14.0% |
| How much has Fund IV invested in healthcare companies? | Analyst | $930m (Tessaline $620m + Meridale $310m) |
| Which company had the highest EBITDA margin in 2026-Q3? | Analyst | Meridale 26.1%, Pellucid close at 25.9% |
| Total distributions to LPs so far? | Analyst | $910m |
| What are the ESG exclusions? | Search | 5 categories, 10% revenue threshold |
| Why was Ostrava written down, and how have its revenue and EBITDA trended? | **Both** | Lost major contract, 15% write-down, new CEO · revenue $410m → $372m, EBITDA $58m → $47m, leverage 4.8x → 5.9x |
| How much cash has Corvane returned, and from what? | **Both** | $650m · $130m dividend recap (Q1 2026) + $520m Canadian division sale (Q2 2026) |
| Net IRR without the facility for 2026-Q3? | Both | Not disclosed (only 12.6% for 2026-Q2) |
| Target size of Fund V? | Search | Not found (only "fundraising expected 2027") |
| Why was Pellucid written down? | Search / Analyst | It wasn't; ARR grew to $172m |

## Roadmap
- Neighbour-chunk expansion to recover context lost at chunk boundaries
- Automated retrieval evaluation (hit rate @k) across chunking settings
