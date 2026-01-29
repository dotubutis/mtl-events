# frozen_string_literal: true

# Represents an event extracted from an Are.na block
class Event
  attr_reader :name, :date, :time, :end_time, :location, :description, :confidence, :block_id, :image_url

  def initialize(attrs = {})
    @name = attrs[:name] || attrs["name"]
    @date = attrs[:date] || attrs["date"]
    @time = attrs[:time] || attrs["time"]
    @end_time = attrs[:end_time] || attrs["end_time"]
    @location = attrs[:location] || attrs["location"]
    @description = attrs[:description] || attrs["description"]
    @confidence = attrs[:confidence] || attrs["confidence"] || "low"
    @block_id = attrs[:block_id] || attrs["block_id"]
    @image_url = attrs[:image_url] || attrs["image_url"]
  end

  # Check if the event has minimum required data to create a calendar event
  def valid?
    !name.nil? && !name.empty? && !date.nil? && !date.empty?
  end

  # Check if extraction confidence is low
  def low_confidence?
    confidence&.downcase == "low"
  end

  # Returns the event title, prefixed if low confidence
  def display_name
    low_confidence? ? "[UNVERIFIED] #{name}" : name
  end

  # Parse date string to Date object
  def parsed_date
    Date.parse(date) if date
  rescue ArgumentError
    nil
  end

  # Parse time string to hour/minute components
  def parsed_time
    return nil unless time
    return nil if time.strip.empty? || time.include?("null")

    parts = time.split(":")
    return nil if parts.length != 2
    
    hour = parts[0].to_i
    minute = parts[1].to_i
    
    # Validate hour and minute ranges
    return nil if hour < 0 || hour > 23 || minute < 0 || minute > 59
    
    { hour: hour, minute: minute }
  rescue StandardError
    nil
  end

  # Parse end_time string to hour/minute components
  def parsed_end_time
    return nil unless end_time
    return nil if end_time.strip.empty? || end_time.include?("null")

    parts = end_time.split(":")
    return nil if parts.length != 2
    
    hour = parts[0].to_i
    minute = parts[1].to_i
    
    # Validate hour and minute ranges
    return nil if hour < 0 || hour > 23 || minute < 0 || minute > 59
    
    { hour: hour, minute: minute }
  rescue StandardError
    nil
  end

  def to_h
    {
      name: name,
      date: date,
      time: time,
      end_time: end_time,
      location: location,
      description: description,
      confidence: confidence,
      block_id: block_id,
      image_url: image_url
    }
  end

  def to_s
    parts = [display_name]
    parts << "on #{date}" if date
    parts << "at #{time}" if time
    parts << "(#{location})" if location
    parts.join(" ")
  end
end
