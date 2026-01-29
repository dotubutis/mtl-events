# frozen_string_literal: true

require "httparty"
require "json"

# Client for interacting with the Are.na API
class ArenaClient
  BASE_URL = "https://api.are.na/v2"

  def initialize(token: nil, channel_slug: nil)
    @token = token || ENV.fetch("ARENA_TOKEN")
    @channel_slug = channel_slug || ENV.fetch("ARENA_CHANNEL_SLUG")
  end

  # Fetch all image blocks from the channel
  # Returns array of hashes with :id, :image_url, :title, :created_at
  def fetch_image_blocks
    blocks = []
    page = 1
    per_page = 100

    loop do
      response = fetch_channel_contents(page: page, per_page: per_page)
      contents = response["contents"] || []

      break if contents.empty?

      # Filter for image blocks only
      image_blocks = contents.select { |block| block["class"] == "Image" }

      image_blocks.each do |block|
        blocks << {
          id: block["id"].to_s,
          image_url: extract_image_url(block),
          title: block["title"],
          description: block["description"],
          created_at: block["created_at"],
          source_url: block["source"]&.dig("url")
        }
      end
      # Check if there are more pages
      total_pages = response["total_pages"] || 1
      break if page >= total_pages

      page += 1
    end

    blocks
  end

  private

  def fetch_channel_contents(page:, per_page:)
    url = "#{BASE_URL}/channels/#{@channel_slug}/contents"

    response = HTTParty.get(
      url,
      headers: headers,
      query: { page: page, per: per_page }
    )

    unless response.success?
      raise "Are.na API error: #{response.code} - #{response.body}"
    end

    response.parsed_response
  end

  def headers
    {
      "Authorization" => "Bearer #{@token}",
      "Content-Type" => "application/json"
    }
  end

  def extract_image_url(block)
    # Prefer original size, fall back to large, then display
    block.dig("image", "original", "url") ||
      block.dig("image", "large", "url") ||
      block.dig("image", "display", "url")
  end
end
