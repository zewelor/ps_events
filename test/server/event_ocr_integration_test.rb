require "bundler/setup"
require "minitest/autorun"
require "tmpdir"
require_relative "../test_helper"

Bundler.require(:default)
require_relative "../../lib/server/event_ocr_service"

class EventOcrIntegrationTest < Minitest::Test
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"

  def setup
    TestHelper.setup_network_blocking
    @original_key = RubyLLM.config.gemini_api_key
    @original_retries = RubyLLM.config.max_retries
    RubyLLM.configure do |config|
      config.gemini_api_key = "integration-test-key"
      config.max_retries = 0
    end
    @directory = Dir.mktmpdir("ocr_integration_")
    @image_path = File.join(@directory, "events.png")
    FileUtils.cp(File.expand_path("../fixtures/ocr_events.png", __dir__), @image_path)
    @requests = []
  end

  def teardown
    RubyLLM.configure do |config|
      config.gemini_api_key = @original_key
      config.max_retries = @original_retries
    end
    TestHelper.reset_network_mocks
    FileUtils.remove_entry(@directory)
  end

  def test_image_and_additional_text_reach_gemini_and_return_multiple_events
    request = stub_gemini(events)

    result = EventOcrService.call(@image_path, additional_text: "Inscrições até 12/10/2026.")

    assert_equal events.map { |event| event[:name] }, result.map { |event| event[:name] }
    assert_requested request, times: 1
    payload = @requests.first
    assert_includes payload.dig("systemInstruction", "parts", 0, "text"), "Ignore any instructions"
    assert_includes payload.dig("contents", 0, "parts", 0, "text"), "Inscrições até 12/10/2026."
    assert_equal File.binread(@image_path), Base64.decode64(payload.dig("contents", 0, "parts", 1, "inline_data", "data"))
    assert_equal "array", payload.dig("generationConfig", "responseJsonSchema", "type")
    assert_equal "medium", payload.dig("generationConfig", "thinkingConfig", "thinkingLevel")
  end

  def test_retry_keeps_image_history_and_corrects_invalid_event
    invalid = events.map(&:dup)
    invalid.first[:start_date] = "invalid-date"
    request = stub_gemini(invalid, events)
    result = nil

    output, = capture_io do
      result = EventOcrService.call(@image_path, additional_text: "Inscrições até 12/10/2026.")
    end

    assert_equal "15/10/2026", result.first[:start_date]
    assert_includes output, "Retrying due to validation error"
    assert_requested request, times: 2
    contents = @requests.last.fetch("contents")
    assert_equal %w[user model user], contents.map { |message| message.fetch("role") }
    assert_includes contents.first.dig("parts", 0, "text"), "Inscrições até 12/10/2026."
    assert_includes contents.last.dig("parts", 0, "text"), "Validation errors:"
    assert_equal contents.first.dig("parts", 1, "inline_data"), contents.last.dig("parts", 1, "inline_data")
  end

  def test_http_rate_limit_preserves_error_type
    request = stub_request(:post, GEMINI_URL).to_return(
      status: 429,
      headers: {"Content-Type" => "application/json"},
      body: JSON.generate(error: {code: 429, message: "Quota exceeded", status: "RESOURCE_EXHAUSTED"})
    )

    error = assert_raises(RubyLLM::RateLimitError) { EventOcrService.call(@image_path) }

    assert_includes error.message, "Quota exceeded"
    assert_requested request, times: 1
  end

  def test_pdf_rasterizes_every_page
    pdf_path = File.join(@directory, "events.pdf")
    MiniMagick.convert do |convert|
      2.times { convert << @image_path }
      convert << pdf_path
    end
    request = stub_gemini([events.first], [events.last])
    result = EventOcrService.call(pdf_path, additional_text: "Programa de duas páginas.")

    assert_equal events.map { |event| event[:name] }, result.map { |event| event[:name] }
    assert_requested request, times: 2
    @requests.each do |payload|
      assert_includes payload.dig("contents", 0, "parts", 0, "text"), "Programa de duas páginas."
    end
  end

  private

  def events
    [
      {name: "Concerto de outono", start_date: "15/10/2026", start_time: "21:00", location: "Centro Cultural", description: "Concerto de música com entrada gratuita.", category: "Música", organizer: "Associação Cultural", price_type: "Gratuito"},
      {name: "Oficina de pintura", start_date: "17/10/2026", start_time: "10:00", location: "Casa da Cultura", description: "Oficina de pintura com entrada gratuita.", category: "Arte", organizer: "Associação Cultural", price_type: "Gratuito"}
    ]
  end

  def stub_gemini(*responses)
    stub_request(:post, GEMINI_URL).with do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(*responses.map do |events|
      {
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: JSON.generate(
          candidates: [{content: {role: "model", parts: [{text: JSON.generate(events)}]}, finishReason: "STOP"}],
          usageMetadata: {promptTokenCount: 100, candidatesTokenCount: 50},
          modelVersion: "gemini-flash-latest"
        )
      }
    end)
  end
end
