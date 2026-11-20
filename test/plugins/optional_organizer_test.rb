require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "test_helper"
require "tmpdir"
require "yaml"

class OptionalOrganizerTest < Minitest::Test
  def test_organizer_and_contacts_on_rendered_pages
    cases = {
      "missing" => {"location" => nil, "email" => "one@example.com", "phone" => "291 123 456", "image" => "/assets/flyer.webp"},
      "nil" => {"organizer" => nil, "email" => "one@example.com", "phone" => ""},
      "empty" => {"organizer" => "", "email" => "", "phone" => "291 123 456"},
      "whitespace" => {"organizer" => "  \t ", "email" => "", "phone" => ""},
      "present" => {"organizer" => 'Clube & "Amigos" </script><script>alert(1)</script>', "email" => "one@example.com", "phone" => "291 123 456"},
      "present-image" => {"organizer" => 'Clube & "Amigos" </script><script>alert(1)</script>', "email" => "", "phone" => "", "image" => "/assets/flyer.webp"}
    }

    build_site(cases) do |destination|
      pages = cases.to_h { |key, _| [key, File.read(File.join(destination, "organizer-#{key}.html"))] }

      refute_match(/<strong[^>]*>Onde:<\/strong>/, pages.fetch("missing"))
      refute event_schema(pages.fetch("missing")).key?("location")
      assert_equal "Porto Santo", event_schema(pages.fetch("present")).fetch("location").fetch("name")

      %w[missing nil empty whitespace].each do |key|
        refute_match(/<strong[^>]*>Organizador:<\/strong>/, pages.fetch(key))
        refute event_schema(pages.fetch(key)).key?("organizer")
      end
      %w[missing nil empty].each do |key|
        assert_match(/<strong[^>]*>Contactos:<\/strong>/, pages.fetch(key))
      end
      assert_includes pages.fetch("missing"), 'href="mailto:one@example.com"'
      assert_includes pages.fetch("missing"), "291 123 456"
      assert_includes pages.fetch("nil"), 'href="mailto:one@example.com"'
      assert_includes pages.fetch("empty"), "291 123 456"
      refute_match(/<strong[^>]*>Contactos:<\/strong>/, pages.fetch("whitespace"))
      %w[present present-image].each do |key|
        assert_match(/<strong[^>]*>Organizador:<\/strong>/, pages.fetch(key))
        assert_includes pages.fetch(key), "Clube &amp; &quot;Amigos&quot;"
        refute_includes pages.fetch(key), "</script><script>alert(1)</script>"
        assert_equal 'Clube & "Amigos" </script><script>alert(1)</script>',
          event_schema(pages.fetch(key)).fetch("organizer").fetch("name")
      end
      assert_includes pages.fetch("present"), 'href="mailto:one@example.com"'
      assert_includes pages.fetch("present"), "291 123 456"
      organizer_line = pages.fetch("present-image").match(%r{<p[^>]*>\s*<strong[^>]*>Organizador:</strong>.*?</p>}m)
      refute_nil organizer_line
      refute_match(/\(\s*\)/, organizer_line[0])
      %w[missing present-image].each { |key| assert event_schema(pages.fetch(key)).key?("image") }
      %w[nil empty whitespace present].each { |key| refute event_schema(pages.fetch(key)).key?("image") }

      form = File.read(File.join(destination, "add_event", "index.html"))
      label = form.match(%r{<label\b[^>]*for="organizer"[^>]*>(.*?)</label>}m)
      input = form.match(/<input\b[^>]*\bid="organizer"[^>]*>/m)
      refute_nil label
      refute_includes label[1], "*"
      refute_nil input
      refute_match(/\brequired\b/, input[0])
      location_input = form.match(%r{<input\b[^>]*\bid="location"[^>]*>}m)
      refute_nil location_input
      refute_match(/\brequired\b/, location_input[0])
    end
  end

  private

  def event_schema(html)
    scripts = html.scan(%r{<script type="application/ld\+json">\s*(.*?)\s*</script>}m).flatten
    scripts.map { |script| JSON.parse(script) }.find { |schema| schema["@type"] == "Event" } || flunk("Missing event JSON-LD")
  end

  def build_site(cases)
    Dir.mktmpdir do |source_root|
      source = File.join(source_root, "events_listing")
      FileUtils.copy_entry(File.expand_path("../../events_listing", __dir__), source)
      FileUtils.rm_f(File.join(source, "_data", "events.csv"))
      FileUtils.cp(File.expand_path("../fixtures/event_span_events.csv", __dir__), File.join(source, "_data", "events.csv"))
      cases.each do |key, attributes|
        data = {
          "layout" => "event", "_name" => "Organizer #{key}", "start_date" => "19/04/2099",
          "start_time" => "18:00", "location" => "Porto Santo", "description" => "Evento de teste"
        }.merge(attributes)
        File.write(File.join(source, "organizer-#{key}.html"), "#{data.to_yaml}---\n")
      end
      Dir.mktmpdir do |destination|
        stdout, stderr, status = Open3.capture3("bundle", "exec", "jekyll", "build", "--source", source, "--destination", destination)
        assert status.success?, "Jekyll build failed:\n#{stdout}\n#{stderr}"
        yield destination
      end
    end
  end
end
