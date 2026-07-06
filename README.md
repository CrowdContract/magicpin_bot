# Vera Bot — magicpin AI Challenge Submission

## Live Bot URL
```
https://vera-bot-production-7e46.up.railway.app
```
**GitHub:** https://github.com/CrowdContract/magicpin_bot

---

## For the Evaluator

```bash
# Health check
curl https://vera-bot-production-7e46.up.railway.app/v1/healthz

# Run full judge
# Set BOT_URL = "https://vera-bot-production-7e46.up.railway.app" in judge_simulator.py
python judge_simulator.py
```

All 5 endpoints live: `GET /v1/healthz` · `GET /v1/metadata` · `POST /v1/context` · `POST /v1/tick` · `POST /v1/reply`

---

## Approach

### Core idea — 4-context composer with trigger-kind dispatch

Every message is built from the full `(category, merchant, trigger, customer?)` quadruple.
Rather than one generic prompt, the composer dispatches to **20 trigger-kind–specific guidance blocks** —
each telling the LLM exactly what angle, compulsion lever, and structure to use for that trigger type.

```
research_digest   → lead with source citation + trial N + patient segment
regulation_change → lead with deadline + exact action required
recall_due        → lead with slot options + price + language preference
competitor_opened → reframe as opportunity + name the counter-move
perf_dip          → name the exact metric + offer a concrete fix
active_planning   → DO NOT qualify — deliver the artifact immediately
...and 14 more
```

This separation is the biggest driver of scoring. A `research_digest` message that reads like a `recall_due`
message loses on both category fit and trigger relevance simultaneously.

### Specificity by construction

The system prompt rule #1: *"anchor on at least one verifiable number, date, or source citation from the contexts provided. If the data isn't there, don't invent it."*

This prevents hallucination and ensures every message has something the merchant can check — which is
what drives the specificity dimension.

### Multi-turn conversation handler

Three hard rules execute before any LLM call — no token cost, instant response:

| Signal | Detection | Action |
|---|---|---|
| Auto-reply | Regex: "Thank you for contacting…", "automated response", "aapki madad" etc. | Turn 1: polite flag → Turn 2: wait 24h → Turn 3: end |
| Hostile / opt-out | Regex: "stop messaging", "spam", "not interested", "mat bhejo" etc. | Immediate `end` |
| Positive intent | Regex: "yes", "let's do it", "kar do", "go ahead" etc. | `intent_confirmed=True` → LLM told to switch to action mode |

**Key implementation detail:** the judge sends each auto-reply turn on a different `conversation_id`.
Tracking consecutive auto-replies per-conversation would fail. We track at **merchant level**
(`merchant_auto_reply_counts` dict) so the 3-strike pattern is detected correctly regardless.

### Adaptive context

`/v1/context` stores the latest version atomically. The tick handler reads fresh context at compose time —
never from a cache. New digest items or updated performance numbers injected mid-test are used in the
very next composition.

---

## Model Choice

**Current: Groq — `llama-3.3-70b-versatile`**

| Factor | Decision |
|---|---|
| Speed | Groq inference is ~500 tok/sec — well under the 30s timeout even for long contexts |
| Cost | Free tier, no rate limit issues during the test window |
| Quality | 70B Llama 3.3 produces coherent, instruction-following JSON reliably |
| Determinism | `temperature=0` — same input always produces same output |

**Tradeoff vs GPT-4o:** GPT-4o would produce marginally better prose quality and handles edge cases
more gracefully. But at `temperature=0` the gap narrows significantly, and Groq's latency advantage
is real — a 5s response vs a 15s response matters when the judge is running 60 minutes of ticks.

### If using paid models — smart routing strategy

Not all tasks need the same model. The right approach is **two-tier routing**:

**Tier 1 — High quality model (GPT-4o, Claude Sonnet, Gemini 1.5 Pro)**
Use for tasks where message quality directly drives the score:
- `POST /v1/tick` — composing the outbound message (this is what gets scored)
- `POST /v1/reply` — multi-turn responses when merchant is engaged (turns 2-3)
- Complex trigger kinds: `research_digest`, `regulation_change`, `supply_alert`, `active_planning_intent`

These are the moments that determine your score. Spending more tokens here is worth it.

**Tier 2 — Fast/cheap model (GPT-4o-mini, Gemini Flash, Claude Haiku)**
Use for tasks where correctness matters more than prose quality:
- Auto-reply detection (we already do this with regex — zero LLM cost)
- Intent classification (positive/hostile/off-topic — regex handles it)
- `POST /v1/reply` on turn 4-5 (conversation winding down, merchant half-engaged)
- Simple trigger kinds: `dormant_with_vera`, `curious_ask_due`, `milestone_reached`

**Estimated token split in practice:**
```
~70% of LLM calls → Tier 2 (cheap/fast)   — routine replies, simple triggers
~30% of LLM calls → Tier 1 (high quality) — scored outbound messages
```
This cuts cost by ~60% while keeping quality where it counts.

**Implementation in this codebase:**
The `LLM_MODEL` env var can be overridden per trigger kind in `composer.py`.
Set `LLM_MODEL_PREMIUM=gpt-4o` and `LLM_MODEL_FAST=gpt-4o-mini` in `.env`,
then route by `trigger_kind` in `_llm_complete()`.

---

## Tradeoffs

**What we optimized for:**
- Zero operational failures (timeouts, malformed JSON, missing fields)
- Correct behavior on all judge test scenarios (auto-reply, intent, hostile)
- Message quality anchored on real context data

**What we traded off:**
- **Retrieval** — digest items are passed in full to the LLM rather than embedded + retrieved by similarity.
  Works fine for 3-5 digest items; would need RAG if digest grows to 50+ items.
- **Conversation memory across sessions** — in-memory only. A Railway restart wipes state.
  Redis would fix this but adds infrastructure complexity.

---

## Judge Simulator Results (live Railway URL)

```
[PASS] healthz (955ms)
[PASS] metadata — Team: Vera AI, Model: llama-3.3-70b-versatile
[PASS] category/dentists · gyms · pharmacies · restaurants · salons
[PASS] merchant/001 through 005
[PASS] auto_reply  — Turn 1: polite flag → Turn 2: wait 24h → Turn 3: ENDED
[PASS] intent      — action mode on "Ok lets do it. Whats next?"
[PASS] hostile     — ended immediately on "Stop messaging me"

All 4 scenarios: PASS
```

---

## Running Locally

```bash
git clone https://github.com/CrowdContract/magicpin_bot.git
cd magicpin_bot
pip install -r requirements.txt
cp .env.example .env          # add GROQ_API_KEY
python -m uvicorn main:app --host 0.0.0.0 --port 8080
curl http://localhost:8080/v1/healthz
```
