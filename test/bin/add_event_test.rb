require "minitest/autorun"
require "json"
require "open3"

class AddEventCliTest < Minitest::Test
  def test_invalid_event_is_rejected_before_services_or_image_processing
    event = {
      name: "Concerto de teste",
      start_date: "09/10/2026junk",
      location: "Largo do Pelourinho",
      description: "Concerto de teste com entrada gratuita.",
      category: "Música",
      organizer: "Organização de teste"
    }
    environment = {
      "GOOGLE_SPREADSHEET_ID" => nil,
      "EVENTS_SHEET_RANGE" => nil,
      "GOOGLE_SERVICE_ACCOUNT_JSON_BASE64" => nil
    }
    command = [
      "bundle", "exec", "ruby",
      File.expand_path("../../bin/add_event", __dir__),
      File.expand_path("../fixtures/ocr_events.png", __dir__),
      JSON.generate(event)
    ]

    stdout, stderr, status = Open3.capture3(environment, *command)

    refute status.success?
    assert_includes stderr, "invalid event"
    assert_includes stderr, "start_date"
    refute_includes stdout, "Processing image"
  end
end
