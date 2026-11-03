require "net/http"
require "uri"
require "json"
require "base64"
require "digest"

class GitHubService
  def self.upload_image(file_path)
    new.upload_image(file_path)
  end

  def self.ensure_image(file_path)
    new.ensure_image(file_path)
  end

  # Initialize with environment variables

  def initialize(branch: "main")
    @token = ENV.fetch("GH_TOKEN")
    @repo = ENV.fetch("GH_REPO")
    @branch = branch
  end

  def ensure_image(file_path)
    raise "Processed image must be a regular file" if File.symlink?(file_path) || (File.exist?(file_path) && !File.file?(file_path))

    bytes = File.binread(file_path) if File.file?(file_path)
    local_sha = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0#{bytes}") if bytes
    remote = remote_image(file_path)
    if remote
      raise "Published image differs from the processed flyer" if local_sha && remote.fetch("sha") != local_sha

      return true
    end
    raise "Processed image is unavailable; upload the source again" unless bytes
    return true if upload_image(file_path)

    # A lost create response or concurrent create can still leave the file saved.
    remote = remote_image(file_path)
    raise "Cannot confirm image publication" unless remote && remote.fetch("sha") == local_sha

    true
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

  private

  def remote_image(file_path)
    github_path = "events_listing/assets/images/#{File.basename(file_path)}"
    uri = URI("https://api.github.com/repos/#{@repo}/contents/#{URI.encode_www_form_component(github_path)}")
    uri.query = URI.encode_www_form(ref: @branch)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "token #{@token}"
    request["User-Agent"] = "Events-Server-Ruby"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    return if response.code == "404"

    raise "Cannot verify published image: HTTP #{response.code}" unless response.code == "200"

    image = JSON.parse(response.body)
    unless image.is_a?(Hash) && image["type"] == "file" && image["path"] == github_path && /\A[0-9a-f]{40}\z/.match?(image["sha"].to_s)
      raise "Invalid published image response"
    end

    image
  end
end
