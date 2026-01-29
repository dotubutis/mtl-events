# frozen_string_literal: true

require "google/apis/calendar_v3"
require "googleauth"
require "json"
require "base64"
require "stringio"

# Client for creating events in Google Calendar
class CalendarClient
  SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR_EVENTS

  def initialize(calendar_id: nil, credentials: nil, dry_run: false)
    @calendar_id = calendar_id || ENV.fetch("GOOGLE_CALENDAR_ID")
    @credentials_json = credentials || decode_credentials(ENV.fetch("GOOGLE_CALENDAR_CREDENTIALS"))
    @dry_run = dry_run
    @service = build_service
  end

  # Create a calendar event from an Event object
  # Returns the created event ID or nil if failed
  # In dry run mode, validates the event structure without creating it
  def create_event(event)
    return nil unless event.valid?

    google_event = build_google_event(event)

    if @dry_run
      # Validate the event structure without creating it
      puts "DRY RUN: Would create calendar event:"
      puts "  Summary: #{google_event.summary}"
      puts "  Location: #{google_event.location}" if google_event.location
      puts "  Start: #{google_event.start.date_time || google_event.start.date}"
      puts "  End: #{google_event.end.date_time || google_event.end.date}"
      puts "  Description: #{google_event.description&.lines&.first&.strip}..." if google_event.description
      return "dry-run-#{Time.now.to_i}"
    end

    result = @service.insert_event(@calendar_id, google_event)
    puts "Created calendar event: #{result.summary} (#{result.id})"
    result.id
  rescue Google::Apis::ClientError => e
    warn "Google Calendar API error: #{e.message}"
    nil
  rescue StandardError => e
    warn "Calendar error: #{e.message}"
    nil
  end

  # Check if an event already exists (by name and date)
  def event_exists?(event)
    return false unless event.valid?

    date = event.parsed_date
    return false unless date

    # Search for events on the same day with similar name
    time_min = DateTime.new(date.year, date.month, date.day, 0, 0, 0)
    time_max = DateTime.new(date.year, date.month, date.day, 23, 59, 59)

    events = @service.list_events(
      @calendar_id,
      time_min: time_min.rfc3339,
      time_max: time_max.rfc3339,
      q: event.name,
      single_events: true
    )

    events.items&.any? { |e| e.summary&.include?(event.name) }
  rescue StandardError => e
    warn "Error checking for existing event: #{e.message}"
    false
  end

  private

  def decode_credentials(base64_credentials)
    JSON.parse(Base64.decode64(base64_credentials))
  rescue StandardError
    # If not base64, assume it's already JSON
    JSON.parse(base64_credentials)
  end

  def build_service
    service = Google::Apis::CalendarV3::CalendarService.new
    service.client_options.application_name = "MTL Events"

    # Create credentials from service account JSON
    credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(@credentials_json.to_json),
      scope: SCOPE
    )

    service.authorization = credentials
    service
  end

  def build_google_event(event)
    google_event = Google::Apis::CalendarV3::Event.new(
      summary: event.display_name,
      location: event.location,
      description: build_description(event)
    )

    date = event.parsed_date
    time_info = event.parsed_time
    end_time_info = event.parsed_end_time

    if time_info
      # Event with specific time - create as Montreal time zone
      # Use offset for Eastern Time (handles EST/EDT automatically)
      start_datetime = DateTime.new(
        date.year, date.month, date.day,
        time_info[:hour], time_info[:minute], 0,
        '-05:00'  # Eastern Time offset
      )

      end_datetime = if end_time_info
                       # Create end datetime
                       end_dt = DateTime.new(
                         date.year, date.month, date.day,
                         end_time_info[:hour], end_time_info[:minute], 0,
                         '-05:00'  # Eastern Time offset
                       )
                       # If end time is earlier than start time, event goes past midnight
                       end_dt += 1 if end_dt <= start_datetime
                       end_dt
                     else
                       # Default to 2 hours duration
                       start_datetime + Rational(2, 24)
                     end

      google_event.start = Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_datetime.rfc3339,
        time_zone: "America/Montreal"
      )
      google_event.end = Google::Apis::CalendarV3::EventDateTime.new(
        date_time: end_datetime.rfc3339,
        time_zone: "America/Montreal"
      )
    else
      # All-day event
      google_event.start = Google::Apis::CalendarV3::EventDateTime.new(date: date.to_s)
      google_event.end = Google::Apis::CalendarV3::EventDateTime.new(date: (date + 1).to_s)
    end

    google_event
  end

  def build_description(event)
    parts = []
    parts << event.description if event.description
    parts << "\n---\nSource: Are.na block #{event.block_id}" if event.block_id
    parts << "Image: #{event.image_url}" if event.image_url
    parts << "Confidence: #{event.confidence}" if event.confidence
    parts.join("\n")
  end
end
