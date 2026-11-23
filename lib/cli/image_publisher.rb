require "fileutils"
require_relative "../server/github_service"

module ImagePublisher
  def self.publish(processed_path)
    uuid = File.basename(processed_path, ".*")
    local_dest = File.expand_path("../../events_listing/assets/images/#{uuid}.webp", __dir__)
    FileUtils.mkdir_p(File.dirname(local_dest))
    FileUtils.cp(processed_path, local_dest)
    puts "Saved image locally to: #{local_dest}"

    if ENV["GH_TOKEN"].to_s.strip.empty? || ENV["GH_REPO"].to_s.strip.empty?
      puts "Warning: GH_TOKEN or GH_REPO not found. Skipping GitHub API upload."
    else
      puts "Uploading image to GitHub..."
      if GitHubService.upload_image(processed_path)
        puts "Uploaded successfully to GitHub!"
      else
        puts "Warning: GitHub API upload failed. Image was still saved locally."
      end
    end
  end
end
