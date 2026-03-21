# Metrics Baseline

Rolling snapshots — one column per audit. Metrics are normalised per task where possible so projects of different sizes are comparable.

| Metric | Unit | Source | <!-- date --> | <!-- date --> | <!-- date --> |
|--------|------|--------|--------------|--------------|--------------|
| Tasks — initial | count | manifest.json (phase) | | | |
| Tasks — replan | count | manifest.json (phase) | | | |
| Tasks — fix | count | manifest.json (phase) | | | |
| Tasks — design | count | manifest.json (phase) | | | |
| Fix rate | (fix+design) / total | manifest.json | | | |
| Replan rate | replan / total | manifest.json | | | |
| Agent fail rate | failed / total tasks | run-log.jsonl | | | |
| Cycle rejection rate | rejections / project | run-log.jsonl (RFC-001) | | | |
| Reviewer flag rate | (CRITICAL+HIGH) / tasks | reviewer output | | | |
| Generalist overflow | generalist tasks / total | manifest.json | | | |
| Token usage | tokens in / task (avg) | run-log.jsonl | | | |
| Cost | USD / task (avg) | run-log.jsonl | | | |
| Task duration | minutes / task (avg) | run-log.jsonl | | | |
| User quality score | 1–5 | user feedback | | | |
| Manual interventions | 0 / 1–3 / 4+ band | user feedback | | | |

## Notes

<!-- Add snapshot-specific notes here: unusual project complexity, partial data, missing fields, etc. -->
<!-- Format: [date] — [project] — [note] -->
