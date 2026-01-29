# MTL Events - Are.na to Google Calendar Sync

A Ruby application that monitors an Are.na channel for event posters, extracts event details using Claude's vision API, and adds them to Google Calendar.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Are.na API    │────▶│  GitHub Action  │────▶│ Google Calendar │
│  (get blocks)   │     │     (Ruby)      │     │      API        │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │  Claude Vision  │
                        │   (Sonnet 4)    │
                        └─────────────────┘
```

## Project Structure

```
mtl-events/
├── .github/
│   └── workflows/
│       └── process_events.yml    # Cron schedule (9am & 6pm UTC)
├── lib/
│   ├── arena_client.rb           # Fetch blocks from Are.na channel
│   ├── vision_extractor.rb       # Extract event data via Claude
│   ├── calendar_client.rb        # Create Google Calendar events
│   └── event.rb                  # Event data structure
├── data/
│   └── processed.json            # List of processed block IDs
├── main.rb                       # Entry point / orchestrator
├── Gemfile                       # Ruby dependencies
├── Gemfile.lock
├── .env.example                  # Template for environment variables
└── plan.md                       # This file
```

## Dependencies (Gemfile)

| Gem | Purpose |
|-----|---------|
| `httparty` | HTTP client for Are.na API |
| `anthropic` | Claude API SDK |
| `google-apis-calendar_v3` | Google Calendar API |
| `dotenv` | Load environment variables (local dev) |
| `json` | JSON parsing (stdlib) |

## Environment Variables

```
ARENA_CHANNEL_SLUG=your-channel-slug
ARENA_TOKEN=your-arena-token
ANTHROPIC_API_KEY=your-anthropic-key
GOOGLE_CALENDAR_ID=your-calendar-id
GOOGLE_CALENDAR_CREDENTIALS=base64-encoded-service-account-json
```

## Implementation Steps

### Step 1: Project Setup
- [ ] Create `Gemfile` with dependencies
- [ ] Create `.env.example` template
- [ ] Create basic directory structure

### Step 2: Are.na Client (`lib/arena_client.rb`)
- [ ] Fetch channel blocks via Are.na API
- [ ] Filter for image blocks only
- [ ] Return block ID, image URL, and metadata

### Step 3: Vision Extractor (`lib/vision_extractor.rb`)
- [ ] Send image to Claude Sonnet 4 with extraction prompt
- [ ] Parse JSON response into Event struct
- [ ] Handle extraction failures gracefully

### Step 4: Calendar Client (`lib/calendar_client.rb`)
- [ ] Authenticate with Google Calendar API (service account)
- [ ] Create calendar events from Event objects
- [ ] Handle duplicate detection (by event name + date)

### Step 5: Main Orchestrator (`main.rb`)
- [ ] Load processed block IDs from `data/processed.json`
- [ ] Fetch new blocks from Are.na
- [ ] For each unprocessed block:
  - Extract event details via Claude
  - Create Google Calendar event
  - Mark block as processed
- [ ] Save updated processed IDs

### Step 6: GitHub Actions Workflow
- [ ] Create workflow file with cron schedule
- [ ] Configure secrets
- [ ] Auto-commit updated `processed.json`

## API Details

### Are.na API
- Endpoint: `GET https://api.are.na/v2/channels/{slug}/contents`
- Auth: Bearer token in header
- Docs: https://dev.are.na/documentation

### Claude Vision API
- Model: `claude-sonnet-4-20250514`
- Estimated cost: ~$0.003-0.01 per image
- Prompt template:
```
Extract event details from this poster as JSON:
{
  "name": "event name",
  "date": "YYYY-MM-DD",
  "time": "HH:MM (24h)",
  "end_time": "HH:MM or null",
  "location": "venue name and/or address",
  "description": "brief description if visible",
  "confidence": "high/medium/low"
}
If info is missing or unclear, use null.
```

### Google Calendar API
- Using service account authentication
- Scopes: `https://www.googleapis.com/auth/calendar.events`
- Docs: https://developers.google.com/calendar/api

## State Management

Processed blocks stored in `data/processed.json`:
```json
{
  "processed_ids": ["block-id-1", "block-id-2"],
  "last_run": "2026-01-28T12:00:00Z"
}
```

## GitHub Actions Workflow

```yaml
name: Process Are.na Events
on:
  schedule:
    - cron: '0 9,18 * * *'  # 9am and 6pm UTC
  workflow_dispatch:        # Manual trigger for testing

jobs:
  process:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true
      - run: bundle exec ruby main.rb
        env:
          ARENA_CHANNEL_SLUG: ${{ secrets.ARENA_CHANNEL_SLUG }}
          ARENA_TOKEN: ${{ secrets.ARENA_TOKEN }}
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GOOGLE_CALENDAR_ID: ${{ secrets.GOOGLE_CALENDAR_ID }}
          GOOGLE_CALENDAR_CREDENTIALS: ${{ secrets.GOOGLE_CALENDAR_CREDENTIALS }}
      - uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: "Update processed blocks"
          file_pattern: "data/processed.json"
```

## Error Handling

- **Are.na API failures**: Log and retry on next run
- **Claude extraction failures**: Log, skip block, don't mark as processed
- **Low confidence extractions**: Create event but add "[UNVERIFIED]" prefix
- **Google Calendar failures**: Log, don't mark as processed (retry next run)
- **Missing date/time**: Skip event creation, log warning

## Future Enhancements (Out of Scope)

- Web UI for manual corrections
- Slack/Discord notifications for new events
- Support for multiple Are.na channels
- Event deduplication across channels
