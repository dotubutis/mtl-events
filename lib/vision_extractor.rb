# frozen_string_literal: true

require "anthropic"
require "json"
require "open-uri"
require "openssl"
require "base64"
require "mini_magick"
require "tempfile"
require_relative "event"

# Extracts event information from images using Claude's vision API
class VisionExtractor
  MODEL = "claude-sonnet-4-5-20250929"

  EXTRACTION_PROMPT = <<~PROMPT
    Extract event details from this poster. Return structured data with the following fields:
    - name: event name
    - date: YYYY-MM-DD format
    - time: HH:MM in 24-hour format
    - end_time: HH:MM in 24-hour format, or null if not specified
    - location: venue name and/or address
    - description: brief description if visible, or null
    - confidence: "high", "medium", or "low"

    Guidelines:
    - If the year is not specified, assume #{Date.today.year}. Events are highly unlikely to be earlier than 2025.
    - Use 24-hour time format (e.g., "21:00" not "9:00 PM")
    - If info is missing or unclear, use null for that field
    - Set confidence to "low" if you had to guess or infer significant details
    - Set confidence to "medium" if some details were unclear but the main info is there
    - Set confidence to "high" if all details are clearly visible
    - If you encounter an image that specifies multiple events, then extract the first event and describe the other events in the description field. If the events are in multiple cities, always prioritize Montreal to be the first event to extract.
  PROMPT

  def initialize(api_key: nil, verbose: false)
    @api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY")
    @verbose = verbose
    @client = Anthropic::Client.new(api_key: @api_key)
  end

  # Extract event details from an image URL
  # Returns an Event object or nil if extraction failed
  def extract(image_url:, block_id: nil)
    puts "  [DEBUG] Fetching image..." if @verbose
    image_data = fetch_image_as_base64(image_url)
    unless image_data
      warn "  [DEBUG] Image fetch failed" if @verbose
      return nil
    end
    puts "  [DEBUG] Image fetched successfully (#{image_data[:data].length} bytes base64)" if @verbose

    puts "  [DEBUG] Calling Claude API..." if @verbose
    event_data = call_claude(image_data)
    unless event_data
      warn "  [DEBUG] Claude API call failed (no response)" if @verbose
      return nil
    end
    puts "  [DEBUG] Claude response received with structured output" if @verbose

    Event.new(event_data.merge("block_id" => block_id, "image_url" => image_url))
  rescue StandardError => e
    warn "Vision extraction error: #{e.message}"
    warn "Backtrace: #{e.backtrace.first(3).join("\n")}"
    nil
  end

  private

  def fetch_image_as_base64(url)
    # Use URI.open with SSL verification disabled for CDN images
    # This is necessary because some CDN certificates have CRL verification issues
    uri = URI.parse(url)
    response_body = URI.open(
      url, 
      ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE,
      "User-Agent" => "Mozilla/5.0 (compatible; EventBot/1.0)"
    ).read
    
    if response_body.nil? || response_body.empty?
      warn "Image body is empty"
      return nil
    end
    
    # Determine content type from URL or default to jpeg
    content_type = case uri.path
    when /\.png$/i then "image/png"
    when /\.gif$/i then "image/gif"
    when /\.webp$/i then "image/webp"
    else "image/jpeg"
    end

    # Check if we need to compress the image
    base64_data = Base64.strict_encode64(response_body)
    max_size = 5_242_880 # 5 MB in bytes
    
    if base64_data.bytesize > max_size
      puts "  [DEBUG] Image too large (#{base64_data.bytesize} bytes), compressing..." if @verbose
      compressed_body = compress_image(response_body, max_size)
      if compressed_body
        base64_data = Base64.strict_encode64(compressed_body)
        puts "  [DEBUG] Image compressed to #{base64_data.bytesize} bytes" if @verbose
      else
        warn "  [WARNING] Failed to compress image, using original" if @verbose
      end
    end

    {
      data: base64_data,
      media_type: content_type
    }
  rescue StandardError => e
    warn "Error fetching image: #{e.message}"
    nil
  end

  # Compress image to fit within max_base64_size bytes when base64 encoded
  def compress_image(image_data, max_base64_size)
    Tempfile.create(["image", ".jpg"]) do |temp_file|
      temp_file.binmode
      temp_file.write(image_data)
      temp_file.flush
      
      image = MiniMagick::Image.open(temp_file.path)
      original_width = image.width
      original_height = image.height
      
      # Try different compression strategies
      quality = 85
      scale = 1.0
      
      loop do
        # Reset to original
        image = MiniMagick::Image.open(temp_file.path)
        
        # Apply scaling if needed
        if scale < 1.0
          new_width = (original_width * scale).to_i
          new_height = (original_height * scale).to_i
          image.resize "#{new_width}x#{new_height}"
        end
        
        # Apply quality compression
        image.format "jpeg"
        image.quality quality.to_s
        
        # Write to temporary output
        Tempfile.create(["compressed", ".jpg"]) do |output_file|
          image.write(output_file.path)
          compressed_data = File.binread(output_file.path)
          base64_size = Base64.strict_encode64(compressed_data).bytesize
          
          # Check if it fits
          if base64_size <= max_base64_size
            return compressed_data
          end
          
          # Adjust compression parameters
          if quality > 60
            quality -= 10
          elsif scale > 0.5
            scale -= 0.1
            quality = 85 # Reset quality when changing scale
          else
            # Can't compress further
            warn "  [WARNING] Unable to compress image below #{max_base64_size} bytes" if @verbose
            return compressed_data # Return best effort
          end
        end
      end
    end
  rescue StandardError => e
    warn "Error compressing image: #{e.message}"
    nil
  end

  def call_claude(image_data)
    response = @client.beta.messages.create(
      model: MODEL,
      max_tokens: 1024,
      betas: ["structured-outputs-2025-11-13"],
      messages: [
        {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: image_data[:media_type],
                data: image_data[:data]
              }
            },
            {
              type: "text",
              text: EXTRACTION_PROMPT
            }
          ]
        }
      ],
      output_format: {
        type: "json_schema",
        schema: {
          type: "object",
          properties: {
            name: { type: "string" },
            date: { type: "string" },
            time: { type: ["string", "null"] },
            end_time: { type: ["string", "null"] },
            location: { type: ["string", "null"] },
            description: { type: ["string", "null"] },
            confidence: { type: "string", enum: ["high", "medium", "low"] }
          },
          required: ["name", "date", "confidence"],
          additionalProperties: false
        }
      }
    )

    # Extract structured JSON output from response
    # The beta API returns JSON as text content, which we parse directly
    text_block = response.content.find { |block| block.respond_to?(:type) && block.type == :text }
    text_block&.text ? JSON.parse(text_block.text, symbolize_names: true) : nil
  rescue JSON::ParserError => e
    warn "Failed to parse structured JSON response: #{e.message}"
    nil
  rescue StandardError => e
    warn "Claude API error: #{e.class}: #{e.message}"
    warn "Backtrace: #{e.backtrace.first(5).join("\n")}"
    nil
  end

end
