require "net/http"
require "uri"
require "json"
require "base64"

class GitHubService
  def self.upload_image(file_path)
    new.upload_image(file_path)
  end

  # Initialize with environment variables

  def initialize(branch: "main")
    @token = ENV.fetch("GH_TOKEN")
    @repo = ENV.fetch("GH_REPO")
    @branch = branch
  end

  def upload_image(file_path)
    return nil unless File.exist?(file_path)

    # Extract filename from file path
    filename = File.basename(file_path)

    # GitHub path
    github_path = "events_listing/assets/images/#{filename}"

    # Prepare the payload
    payload = {
      message: "Add #{filename}",
      branch: @branch,
      content: Base64.strict_encode64(File.read(file_path))
    }

    # Make the request
    uri = URI("https://api.github.com/repos/#{@repo}/contents/#{URI.encode_www_form_component(github_path)}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Put.new(uri)
    request["Authorization"] = "token #{@token}"
    request["User-Agent"] = "Events-Server-Ruby"
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    begin
      response = http.request(request)

      if [200, 201].include?(response.code.to_i)
        puts "✅ Image uploaded to GitHub: #{github_path}"
        true
      else
        puts "❌ GitHub upload failed: #{response.code} #{response.body}"
        nil
      end
    rescue => e
      puts "❌ GitHub upload error: #{e.message}"
      nil
    end
  end
end
