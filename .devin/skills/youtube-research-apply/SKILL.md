# YouTube Research & Apply

Transcribe a YouTube video, extract actionable lessons, and apply them to the
codebase. Use when the user shares a YouTube link and wants lessons extracted
and integrated into project logic, configs, or documentation.

## Prerequisites

- The `youtube-full` skill must be available (provides TranscriptAPI access)
- `$TRANSCRIPT_API_KEY` must be set (see youtube-full auth setup)

## Workflow

### 1. Fetch the transcript

```bash
curl -s "https://transcriptapi.com/api/v2/youtube/transcript\
?video_url=VIDEO_URL&format=text&include_timestamp=true&send_metadata=true" \
  -H "Authorization: Bearer $TRANSCRIPT_API_KEY" \
  -H "User-Agent: Devin/1.0" \
  -o /tmp/transcript.json -w "%{http_code}"
```

The response JSON has:
- `metadata.title` — video title
- `metadata.author_name` — channel name
- `transcript` — string with `[timestamp] text` segments (when `format=text`)

### 2. Parse and read the transcript

The transcript is a single string with `[Xs] text` segments. Read it in chunks:

```bash
cat /tmp/transcript.json | python3 -c "
import sys,json
d=json.load(sys.stdin)
t = d.get('transcript','')
print(t[0:6000])   # first chunk
print(t[6000:12000])  # second chunk
# ... continue until end
"
```

Also check metadata to understand context:
```bash
cat /tmp/transcript.json | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('TITLE:', d.get('metadata',{}).get('title',''))
print('AUTHOR:', d.get('metadata',{}).get('author_name',''))
print('LENGTH:', len(d.get('transcript','')))
"
```

### 3. Extract lessons

While reading the transcript, identify:
- **Quantitative breakpoints** — specific level numbers, thresholds, ratios
- **Cost/scaling analysis** — exponential walls, flat scaling, UPS impact
- **Tier rankings** — what the expert considers S/A/B/C/D tier and why
- **Formulas** — any mathematical relationships (e.g. ESPM = SPM * multiplier)
- **Practical limits** — where diminishing returns make continued investment futile
- **Comparative analysis** — X costs more than Y because of Z

### 4. Map lessons to codebase

For each lesson, find the corresponding code:
- Use `grep`/`read` to locate relevant config tables, scoring functions, policy logic
- Identify where hardcoded values, caps, or weights exist that should reflect the lessons
- Look for gaps where the codebase is missing awareness of a concept

### 5. Apply changes

- Update config/weights tables with expert-derived values
- Add new constants or helper functions for formulas
- Adjust scoring logic to account for newly identified cost dimensions
- Add practical caps where exponential cost walls exist
- Update test stubs if new fields are added to config modules

### 6. Verify

- Run the project's test suite
- Update DOX (AGENTS.md) if contracts or ownership changed
- Clean up temp files (`/tmp/transcript.json`)

## Key patterns from Factorio megabase research (abucnasty)

These patterns were extracted from ESPM/megabase videos and applied to
LilEinstein's research autopilot:

- **SPM vs ESPM**: Raw production vs effective science after multipliers.
  Formula: `ESPM = raw_SPM * drain * (1 + module_prod + level * per_level)`
- **Practical infinite-tech caps**: Combat techs hit one-shot breakpoints then
  exponential walls. Logistics techs (worker-robot-speed) hit cost walls fast.
  Only mining-productivity and research-productivity are practically infinite.
- **Per-pack UPS cost**: Different science packs have vastly different UPS
  overhead. Promethium (5x) vs automation (1x) is a 5x difference in real cost
  that ingredient count alone doesn't capture.
- **Expert tier rankings**: Weights should reflect actual ROI as understood by
  top players, not just effect-tag inference.

## Notes

- The transcript API returns text with timestamps embedded as `[Xs]`; strip
  these when extracting clean prose
- Videos can be long (30+ min); read the full transcript, don't skip sections
- Always cite the source video and author in code comments when deriving
  values from their analysis
