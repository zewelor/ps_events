require "fileutils"
require "test_helper"
require "open3"
require "tmpdir"

class EventSpanMarkupTest < Minitest::Test
  def test_multi_day_event_card_renders_start_and_end_dates
    build_site do |destination|
      html = File.read(File.join(destination, "index.html"))

      assert_match(
        %r{<div class="event-card"[^>]*data-date="2099-03-30"[^>]*data-end-date="2099-04-10"[\s\S]*?<h2[^>]*>[\s\S]*?Férias de Páscoa[\s\S]*?</h2>}m,
        html,
        "Expected the Férias de Páscoa event card to expose both start and end dates"
      )
      refute_match(
        /class="event-card"[^>]*data-end-date=""/,
        html,
        "Expected every event card to expose a non-empty data-end-date attribute"
      )
    end
  end

  def test_event_schema_uses_effective_end_date
    build_site do |destination|
      with_end_time = event_page(destination, "Concerto com hora final")
      without_end_time = event_page(destination, "Concerto sem hora final")

      assert_match(/"startDate": "2099-04-19T18:00"/, with_end_time)
      assert_match(/"endDate": "2099-04-19T20:00"/, with_end_time)
      assert_match(/"startDate": "2099-04-20T18:00"/, without_end_time)
      refute_match(/"endDate":/, without_end_time)
    end
  end

  private

  def event_page(destination, name)
    path = Dir.glob(File.join(destination, "events", "*.html")).find do |candidate|
      File.read(candidate).include?(name)
    end
    assert path, "Expected a generated event page for #{name}"

    File.read(path)
  end

  def build_site
    Dir.mktmpdir do |source_root|
      source = File.join(source_root, "events_listing")
      fixture = File.expand_path("../fixtures/event_span_events.csv", __dir__)

      FileUtils.copy_entry(File.expand_path("../../events_listing", __dir__), source)
      FileUtils.rm_f(File.join(source, "_data", "events.csv"))
      FileUtils.cp(fixture, File.join(source, "_data", "events.csv"))

      Dir.mktmpdir do |destination|
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
end
