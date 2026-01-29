#!/usr/bin/env ruby
# frozen_string_literal: true

require "dotenv/load"
require "json"
require "optparse"
require "time"

require_relative "lib/arena_client"
require_relative "lib/vision_extractor"
require_relative "lib/calendar_client"
require_relative "lib/event"

# Main orchestrator for processing Are.na event posters
class EventProcessor
  DATA_FILE = File.join(__dir__, "data", "processed.json")

  def initialize(options = {})
    @dry_run = options[:dry_run] || false
    @verbose = options[:verbose] || false
    @reprocess = options[:reprocess] || false
    @limit = options[:limit]

    @arena = ArenaClient.new
    @vision = VisionExtractor.new(verbose: @verbose)
    @calendar = CalendarClient.new(dry_run: @dry_run)
  end

  def run
    log "Starting event processor..."
    log "Mode: #{@dry_run ? 'DRY RUN' : 'LIVE'}"

    # Load processed IDs
    processed_data = load_processed_data
    processed_ids = @reprocess ? [] : processed_data["processed_ids"]
    log "Previously processed: #{processed_ids.length} blocks"

    # Fetch blocks from Are.na
    log "Fetching blocks from Are.na..."
    blocks = @arena.fetch_image_blocks
    log "Found #{blocks.length} image blocks"

    # Filter to unprocessed blocks
    new_blocks = blocks.reject { |b| processed_ids.include?(b[:id]) }
    log "New blocks to process: #{new_blocks.length}"

    # Apply limit if specified
    new_blocks = new_blocks.first(@limit) if @limit
    log "Processing #{new_blocks.length} blocks (limit: #{@limit || 'none'})" if @limit

    # Process each block
    results = { success: 0, skipped: 0, failed: 0 }
    newly_processed = []

    new_blocks.each_with_index do |block, index|
      log "\n[#{index + 1}/#{new_blocks.length}] Processing block #{block[:id]}..."
      log "  Image: #{block[:image_url]}" if @verbose
      # Extract event data (returns array of events)
      events = @vision.extract(image_url: block[:image_url], block_id: block[:id])

      if events.empty?
        log "  ❌ Failed to extract event data"
        results[:failed] += 1
        next
      end

      log "  📅 Extracted #{events.length} event(s) from image"

      # Track if at least one event was successfully processed
      block_success = false
      
      # Process each event from the image
      events.each_with_index do |event, event_index|
        log "  [Event #{event_index + 1}/#{events.length}] #{event}" if events.length > 1

        unless event.valid?
          log "    ⚠️  Invalid event (missing name or date), skipping"
          results[:skipped] += 1
          next
        end

        # Check for duplicates
        if @calendar.event_exists?(event)
          log "    ⏭️  Event already exists in calendar, skipping"
          results[:skipped] += 1
          next
        end

        # Create calendar event (or validate in dry run mode)
        event_id = @calendar.create_event(event)

        if event_id
          if @dry_run
            log "    🔍 DRY RUN: Calendar event validated successfully"
            log "       #{event.to_h.to_json}" if @verbose
          else
            log "    ✅ Created calendar event: #{event_id}"
          end
          results[:success] += 1
          block_success = true
        else
          log "    ❌ Failed to #{@dry_run ? 'validate' : 'create'} calendar event"
          results[:failed] += 1
        end
      end

      # Mark block as processed if at least one event succeeded or if in dry run mode
      newly_processed << block[:id] if block_success || @dry_run
    end

    # Save updated processed IDs
    unless @dry_run
      save_processed_data(processed_ids + newly_processed)
    end

    # Summary
    log "\n" + "=" * 50
    log "Processing complete!"
    log "  ✅ Success: #{results[:success]}"
    log "  ⏭️  Skipped: #{results[:skipped]}"
    log "  ❌ Failed: #{results[:failed]}"

    results
  end

  private

  def load_processed_data
    return { "processed_ids" => [], "last_run" => nil } unless File.exist?(DATA_FILE)

    JSON.parse(File.read(DATA_FILE))
  rescue JSON::ParserError
    { "processed_ids" => [], "last_run" => nil }
  end

  def save_processed_data(processed_ids)
    data = {
      "processed_ids" => processed_ids.uniq,
      "last_run" => Time.now.utc.iso8601
    }
    File.write(DATA_FILE, JSON.pretty_generate(data) + "\n")
    log "Saved #{processed_ids.length} processed IDs"
  end

  def log(message)
    puts message
  end
end

# CLI argument parsing
options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby main.rb [options]"

  opts.on("-d", "--dry-run", "Preview what would be created without making changes") do
    options[:dry_run] = true
  end

  opts.on("-v", "--verbose", "Show detailed output") do
    options[:verbose] = true
  end

  opts.on("-r", "--reprocess", "Reprocess all blocks (ignore processed.json)") do
    options[:reprocess] = true
  end

  opts.on("-l", "--limit N", Integer, "Limit number of blocks to process") do |n|
    options[:limit] = n
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Run the processor
processor = EventProcessor.new(options)
processor.run
