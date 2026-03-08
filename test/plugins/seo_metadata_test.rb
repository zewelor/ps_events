require "test_helper"
require "open3"
require "tmpdir"

class SeoMetadataTest < Minitest::Test
  def test_homepage_build_includes_pxo_pulse_metadata
    build_site do |destination|
      html = File.read(File.join(destination, "index.html"))

      assert_match(/<html[^>]+lang="pt-PT"/, html)
      assert_match(/<title>[^<]*PXO Pulse[^<]*<\/title>/, html)
      assert_match(/<meta name="description" content="[^"]*pxopulse[^"]*"/i, html)
      assert_match(/<meta name="keywords" content="[^"]*pxopulse[^"]*"/i, html)
      assert_match(/<p[^>]*>\s*O <strong>pxopulse<\/strong> é a agenda do Porto Santo/m, html)
    end
  end

  private

  def build_site
    Dir.mktmpdir do |destination|
      source = File.expand_path("../../events_listing", __dir__)
      command = [
        "bundle", "exec", "jekyll", "build",
        "--source", source,
        "--destination", destination
      ]
      stdout, stderr, status = Open3.capture3(*command)

      assert status.success?, "Jekyll build failed:\n#{stdout}\n#{stderr}"

      yield destination
    end
  end
end
