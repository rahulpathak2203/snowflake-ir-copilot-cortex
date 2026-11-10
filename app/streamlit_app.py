"""
Halvoran Ridge IR Copilot - Streamlit in Snowflake app
Answers investor questions from Fund IV documents using Cortex Search + AI_COMPLETE.

Deploy: Snowsight > Projects > Streamlit > + Streamlit App
        Location: IR_COPILOT.FUND_DOCS   Warehouse: IR_WH
        Replace the sample code with this file and click Run.
No extra packages needed.
"""
import json
import pandas as pd
import streamlit as st
from snowflake.snowpark.context import get_active_session

# ---------------------------------------------------------------- config
SERVICE = "IR_COPILOT.FUND_DOCS.FUND_DOCS_SEARCH"
CHUNKS_TABLE = "IR_COPILOT.FUND_DOCS.DOC_CHUNKS"
MODELS = ["claude-sonnet-4-5", "mistral-large2", "llama3.1-70b"]   # first one available in your region wins
EXAMPLES = [
    "What is Fund IV's net IRR with and without the credit facility?",
    "Why was Ostrava Packaging written down?",
    "Who triggers the key person clause?",
    "What are the ESG exclusions?",
]

st.set_page_config(page_title="IR Copilot", layout="wide")
session = get_active_session()


# ---------------------------------------------------------------- helpers
def safe(text: str) -> str:
    """Make text safe to place inside a $$ ... $$ SQL string."""
    return text.replace("$$", "$ $")


@st.cache_data(ttl=3600)
def filter_options():
    df = session.sql(f"SELECT DISTINCT doc_type, period FROM {CHUNKS_TABLE}").to_pandas()
    return sorted(df["DOC_TYPE"].dropna().unique()), sorted(df["PERIOD"].dropna().unique())


def build_filter(doc_types, periods):
    """Turn sidebar selections into a Cortex Search filter."""
    clauses = []
    if doc_types:
        clauses.append({"@or": [{"@eq": {"doc_type": d}} for d in doc_types]})
    if periods:
        clauses.append({"@or": [{"@eq": {"period": p}} for p in periods]})
    if not clauses:
        return None
    return clauses[0] if len(clauses) == 1 else {"@and": clauses}


def search(question: str, k: int, flt):
    """Retrieve the top-k chunks from Cortex Search."""
    body = {
        "query": question,
        "columns": ["file_name", "chunk_id", "doc_type", "period", "chunk_text"],
        "limit": k,
    }
    if flt:
        body["filter"] = flt
    sql = f"SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW('{SERVICE}', $${safe(json.dumps(body))}$$)"
    raw = session.sql(sql).collect()[0][0]
    return json.loads(raw).get("results", [])


def generate(question: str, results, model: str) -> str:
    """Ask the LLM to answer using only the retrieved chunks."""
    context = "\n\n---\n\n".join(
        f"SOURCE [{i + 1}]: {r['file_name']}\n{r['chunk_text']}" for i, r in enumerate(results)
    )
    prompt = (
        "You are an investor relations assistant for Halvoran Ridge Capital.\n"
        "Answer the question using ONLY the sources below. "
        "After each fact, cite its source number like [1] or [2]. "
        "Be concise and precise with numbers and dates. "
        "If the sources do not contain the answer, say: "
        "'I could not find this in the fund documents.'\n\n"
        f"SOURCES:\n{context}\n\nQUESTION: {question}\n\nANSWER:"
    )
    sql = f"SELECT AI_COMPLETE('{model}', $${safe(prompt)}$$)"
    return session.sql(sql).collect()[0][0]


def ask(question: str, k: int, flt, model: str):
    results = search(question, k, flt)
    if not results:
        return "I could not find anything relevant in the fund documents.", []
    return generate(question, results, model), results


def show_sources(results):
    with st.expander(f"Sources ({len(results)})"):
        for i, r in enumerate(results):
            score = r.get("@scores", {}).get("reranker_score")
            score_txt = f" · relevance {score:.2f}" if isinstance(score, (int, float)) else ""
            st.markdown(
                f"**[{i + 1}] {r['file_name']}** · {r.get('doc_type', '')} · "
                f"{r.get('period', '')} · chunk {r.get('chunk_id', '')}{score_txt}"
            )
            st.text(r["chunk_text"][:900])


# ---------------------------------------------------------------- sidebar
st.sidebar.title("Settings")
mode = st.sidebar.radio("Mode", ["Ask a question", "Draft DDQ answers"])
model = st.sidebar.selectbox("Model", MODELS)
k = st.sidebar.slider("Chunks to retrieve", 2, 8, 4)

doc_type_opts, period_opts = filter_options()
st.sidebar.subheader("Filters (optional)")
sel_types = st.sidebar.multiselect("Document type", doc_type_opts)
sel_periods = st.sidebar.multiselect("Period", period_opts)
flt = build_filter(sel_types, sel_periods)

if st.sidebar.button("Clear chat"):
    st.session_state.messages = []

# ---------------------------------------------------------------- header
st.title("Halvoran Ridge IR Copilot")
st.caption(
    "Answers investor questions from Fund IV documents, with sources. "
    "Demo built on fictional data."
)

# ---------------------------------------------------------------- mode 1: chat
if mode == "Ask a question":
    if "messages" not in st.session_state:
        st.session_state.messages = []

    if not st.session_state.messages:
        st.write("Try one:")
        cols = st.columns(len(EXAMPLES))
        for col, ex in zip(cols, EXAMPLES):
            if col.button(ex, use_container_width=True):
                st.session_state.pending = ex

    for m in st.session_state.messages:
        with st.chat_message(m["role"]):
            st.markdown(m["content"])
            if m.get("sources"):
                show_sources(m["sources"])

    question = st.chat_input("Ask about Fund IV...") or st.session_state.pop("pending", None)

    if question:
        st.session_state.messages.append({"role": "user", "content": question})
        with st.chat_message("user"):
            st.markdown(question)

        with st.chat_message("assistant"):
            with st.spinner("Searching fund documents..."):
                try:
                    reply, results = ask(question, k, flt, model)
                except Exception as e:
                    reply, results = f"Something went wrong: {e}", []
            st.markdown(reply)
            if results:
                show_sources(results)

        st.session_state.messages.append(
            {"role": "assistant", "content": reply, "sources": results}
        )

# ---------------------------------------------------------------- mode 2: DDQ drafting
else:
    st.subheader("Draft answers for a due diligence questionnaire")
    st.write("Paste one question per line. Each gets a draft answer with its sources.")
    default_qs = "\n".join([
        "Describe the ownership structure of the firm.",
        "What is the management fee during the investment period?",
        "How does the firm manage cybersecurity risk?",
        "What percentage of portfolio company board seats are held by women?",
        "How often are investments valued and who reviews them?",
    ])
    text = st.text_area("Questions", default_qs, height=180)

    if st.button("Draft answers", type="primary"):
        questions = [q.strip() for q in text.splitlines() if q.strip()]
        rows, bar = [], st.progress(0.0)
        for i, q in enumerate(questions):
            try:
                ans, res = ask(q, k, flt, model)
                srcs = ", ".join(sorted({r["file_name"] for r in res}))
            except Exception as e:
                ans, srcs = f"Error: {e}", ""
            rows.append({"Question": q, "Draft answer": ans, "Sources": srcs})
            bar.progress((i + 1) / len(questions))

        df = pd.DataFrame(rows)
        st.dataframe(df, use_container_width=True, hide_index=True)
        st.download_button(
            "Download as CSV",
            df.to_csv(index=False).encode("utf-8"),
            file_name="ddq_draft_answers.csv",
            mime="text/csv",
        )
