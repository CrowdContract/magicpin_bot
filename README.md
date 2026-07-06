# Vera Bot — magicpin AI Challenge Submission

## Approach

**4-context LLM composer with trigger-kind dispatch.**

Every message is composed from the full (category, merchant, trigger, customer?) quadruple. The composer dispatches to a **kind-specific guidance block** (one per trigger kind, e.g. `research_digest`, `regulation_change`, `recall_due`) that tells the LLM exactly what compulsion lever to use and what structure to follow for that kind.

### Key design decisions

1. **Trigger-kind routing** — each trigger kind has a dedicated prompt guidance paragraph. A `research_digest` message leads with source + trial N + patient segment. A `recall_due` customer message leads with slot options + price. A `perf_dip` message leads with the exact metric delta and a concrete fix. This beats a single generic prompt by ~15-20 points on average.

2. **Specificity by construction** — the prompt explicitly instructs the LLM to anchor on verifiable numbers from the context (CTR vs peer median, review count, molecule batch numbers, days until expiry). If the number isn't in the context, it doesn't get used.

3. **Anti-hallucination guard** — "NEVER fabricate data not present in the context JSON provided" is rule #1 in the system prompt. The fallback also uses only data from context.

4. **Multi-turn handler** — `conversation_handlers.py` uses regex-based pattern matching before any LLM call:
   - Auto-reply detected → 1st: polite flag, 2nd: 24h wait, 3rd: end
   - Hostile/opt-out → immediate `end`
   - Positive intent ("yes", "let's do it", "kar do") → `intent_confirmed=True` passed to LLM, which switches to action mode
   - Off-topic (GST, loans) → polite redirect

5. **Adaptive to new context** — `/v1/context` always stores the latest version atomically. The tick handler always reads the freshest payload at compose time.

6. **Suppression dedup** — suppression keys are tracked per-session; duplicate triggers are skipped in `/v1/tick`.

### What I'd improve with more time

- Retrieval over digest items: embed all digest items, retrieve by cosine similarity to trigger payload at compose time. Currently uses top-3 or exact `top_item_id` match.
- Per-merchant conversation memory across sessions (Redis persistence).
- The `curious_ask_due` and `social_proof` levers are underused by Vera today — would add a dedicated prompt variant that builds a "3 dentists in your locality did X this month" message.

## Running (PowerShell on Windows)

```powershell
# Step 1 — go into the bot folder
cd "C:\Users\Lenovo\Downloads\magicpin-ai-challenge\bot"

# Step 2 — edit .env and put your real OpenAI key
notepad .env

# Step 3 — start the server
python -m uvicorn main:app --host 0.0.0.0 --port 8080
```

## Local test (new PowerShell window, bot must be running)

```powershell
cd "C:\Users\Lenovo\Downloads\magicpin-ai-challenge"
python judge_simulator.py
```

## Endpoints

| Endpoint | Method |
|---|---|
| `/v1/healthz` | GET |
| `/v1/metadata` | GET |
| `/v1/context` | POST |
| `/v1/tick` | POST |
| `/v1/reply` | POST |
