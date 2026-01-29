# MTL Events

Automatically sync event posters from an Are.na channel to Google Calendar using Claude's vision API for extraction.

## How It Works

1. Fetches image blocks from your Are.na channel
2. Sends each image to Claude Sonnet 4 to extract event details (name, date, time, location)
3. Creates Google Calendar events from the extracted data
4. Tracks processed blocks to avoid duplicates

## Setup

### 1. Install Dependencies

```bash
bundle install
```

### 2. Get API Credentials

**Are.na:**
- Go to [dev.are.na](https://dev.are.na) and create an application
- Copy your access token

**Anthropic (Claude):**
- Get an API key from [console.anthropic.com](https://console.anthropic.com)

**Google Calendar:**
1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project and enable the Google Calendar API
3. Create a Service Account (APIs & Services → Credentials → Create Credentials)
4. Download the JSON key file
5. Share your calendar with the service account email (found in the JSON file)
6. Base64 encode the JSON: `base64 -i your-credentials.json`

### 3. Configure Environment

Copy the example file and fill in your values:

```bash
cp .env.example .env
```

Edit `.env`:

```
ARENA_CHANNEL_SLUG=your-channel-slug
ARENA_TOKEN=your-arena-token
ANTHROPIC_API_KEY=your-anthropic-key
GOOGLE_CALENDAR_ID=your-calendar-id@group.calendar.google.com
GOOGLE_CALENDAR_CREDENTIALS=base64-encoded-service-account-json
```

## Usage

### Local Development

```bash
# Dry run - preview what would be created (validates structure, checks duplicates)
bundle exec ruby main.rb --dry-run --verbose

# Process only first N blocks (good for testing)
bundle exec ruby main.rb --dry-run --limit 3

# Reprocess all blocks (ignore cache)
bundle exec ruby main.rb --dry-run --reprocess

# Full run - creates real calendar events
bundle exec ruby main.rb --verbose
```

### CLI Options

| Flag | Description |
|------|-------------|
| `-d, --dry-run` | Preview without creating calendar events (validates event structure and checks for duplicates) |
| `-v, --verbose` | Show detailed output |
| `-r, --reprocess` | Ignore processed.json, reprocess all blocks |
| `-l, --limit N` | Only process N blocks |
| `-h, --help` | Show help message |

## GitHub Actions (Automated)

The app can run automatically via GitHub Actions on a schedule.

### Setup Secrets

In your GitHub repo, go to Settings → Secrets and variables → Actions, and add:

- `ARENA_CHANNEL_SLUG`
- `ARENA_TOKEN`
- `ANTHROPIC_API_KEY`
- `GOOGLE_CALENDAR_ID`
- `GOOGLE_CALENDAR_CREDENTIALS`

### Schedule

The workflow runs at 9am and 6pm UTC by default. Edit `.github/workflows/process_events.yml` to change:

```yaml
on:
  schedule:
    - cron: '0 9,18 * * *'  # Adjust times here
```

### Manual Trigger

You can also trigger the workflow manually from the Actions tab in GitHub.

## State Management

Processed block IDs are stored in `data/processed.json`. This file is auto-committed by the GitHub Action to track which blocks have been processed.

To reprocess everything, either:
- Run with `--reprocess` flag locally
- Clear the `processed_ids` array in `data/processed.json`

## Confidence Levels

Claude assigns a confidence level to each extraction:

- **high**: All details clearly visible
- **medium**: Some details unclear but main info present
- **low**: Significant guessing required → Events prefixed with `[UNVERIFIED]`

## Cost Estimate

Claude Sonnet 4 vision costs ~$0.003-0.01 per image, depending on size.
