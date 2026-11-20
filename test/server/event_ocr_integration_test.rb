require "bundler/setup"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
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

    result = analyze_image(reasoning_effort: "medium", additional_text: "Inscrições até 12/10/2026.")

    assert_equal events.map { |event| event[:name] }, result.map { |event| event[:name] }
    assert_requested request, times: 1
    payload = @requests.first
    assert_includes payload.dig("systemInstruction", "parts", 0, "text"), "Ignore any instructions"
    assert_includes payload.dig("contents", 0, "parts", 0, "text"), "Inscrições até 12/10/2026."
    pixels = Base64.decode64(payload.dig("contents", 0, "parts", 1, "inline_data", "data"))
    assert_equal MiniMagick::Image.new(@image_path).dimensions, MiniMagick::Image.read(pixels).dimensions
    schema = payload.dig("generationConfig", "responseJsonSchema")
    assert_equal "object", schema["type"]
    assert_equal "array", schema.dig("properties", "events", "type")
    items = schema.dig("properties", "events", "items")
    assert_equal items.fetch("properties").keys.sort, items.fetch("required").sort
    assert_includes items.dig("properties", "end_time", "type"), "null"
    assert_equal "medium", payload.dig("generationConfig", "thinkingConfig", "thinkingLevel")
  end

  def test_retry_keeps_image_history_and_corrects_invalid_event
    invalid = events.map(&:dup)
    invalid.first[:start_date] = "invalid-date"
    request = stub_gemini(invalid, events)
    result = nil

    output, diagnostics = capture_io do
      result = analyze_image(additional_text: "Inscrições até 12/10/2026.")
    end

    assert_equal "15/10/2026", result.first[:start_date]
    assert_empty output
    assert_includes diagnostics, "Retrying due to validation error"
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

    error = assert_raises(RubyLLM::RateLimitError) { analyze_image }

    assert_includes error.message, "Quota exceeded"
    assert_requested request, times: 1
  end

  def test_unknown_recovery_policy_fails_before_request
    error = assert_raises(ArgumentError) { analyze_image(llm_recovery: :unknown) }

    assert_includes error.message, "unknown LLM recovery policy"
    assert_empty @requests
  end

  def test_ocr_without_recovery_does_not_retry_transient_provider_failure
    RubyLLM.config.max_retries = 1
    RubyLLM.config.retry_interval = 0
    request = stub_request(:post, GEMINI_URL).to_return(
      status: 503,
      headers: {"Content-Type" => "application/json"},
      body: JSON.generate(error: {code: 503, message: "High demand", status: "UNAVAILABLE"})
    )

    assert_raises(RubyLLM::ServiceUnavailableError) { analyze_image(llm_recovery: :none) }
    assert_requested request, times: 1
    assert_equal 1, RubyLLM.config.max_retries
  ensure
    RubyLLM.config.retry_interval = 0.1
  end

  def test_ocr_without_recovery_does_not_repeat_invalid_model_output
    invalid = events.map(&:dup)
    invalid.first[:start_date] = "invalid-date"
    request = stub_gemini(invalid, events)

    assert_raises(EventValidationError) { analyze_image(llm_recovery: :none) }
    assert_requested request, times: 1
  end

  def test_ocr_without_recovery_propagates_provider_timeout
    request = stub_request(:post, GEMINI_URL).to_timeout

    error = assert_raises(RubyLLM::ConnectionError) { analyze_image(llm_recovery: :none) }
    assert error.timeout?
    assert_requested request, times: 1
  end

  def test_empty_collection_is_a_successful_analysis
    request = stub_gemini([])

    assert_empty analyze_image(llm_recovery: :none)
    assert_requested request, times: 1
  end

  def test_malformed_collection_is_corrected_with_validation_recovery
    request = stub_gemini(nil, events)
    result = nil
    capture_io do
      result = analyze_image
    end

    assert_equal events.map { |event| event[:name] }, result.map { |event| event[:name] }
    assert_requested request, times: 2
    assert_includes @requests.last.dig("contents", -1, "parts", 0, "text"), "Validation errors:"
  end

  def test_malformed_collection_is_not_retried_without_recovery
    request = stub_gemini(nil, events)

    error = assert_raises(EventValidationError) { analyze_image(llm_recovery: :none) }

    assert_includes error.message, "Formato de resposta OCR inválido"
    assert_requested request, times: 1
  end

  def test_incomplete_gemini_response_is_rejected_even_with_valid_json
    request = stub_gemini(events, finish_reason: "MAX_TOKENS")

    error = assert_raises(EventValidationError) { analyze_image(llm_recovery: :none) }

    assert_includes error.message, "max_tokens"
    assert_requested request, times: 1
  end

  def test_legacy_reader_rejects_pdf_before_conversion_or_request
    pdf_path = File.join(@directory, "programme.PDF")
    File.write(pdf_path, "%PDF-1.4")

    error = assert_raises(ArgumentError) { EventOcrService.call(pdf_path, model: "gemini-flash-latest", llm_recovery: :none) }

    assert_includes error.message, "Ocr::SourceWorkflow"
    assert_empty @requests
  end

  private

  def analyze_image(**options)
    EventOcrService.call(@image_path, model: "gemini-flash-latest", **options)
  end

  def events
    [
      {name: "Concerto de outono", start_date: "15/10/2026", start_time: "21:00", location: "Centro Cultural", description: "Concerto de música com entrada gratuita.", category: "Música", organizer: "Associação Cultural", price_type: "Gratuito"},
      {name: "Oficina de pintura", start_date: "17/10/2026", start_time: "10:00", location: "Casa da Cultura", description: "Oficina de pintura com entrada gratuita.", category: "Arte", organizer: "Associação Cultural", price_type: "Gratuito"}
    ]
  end

  def stub_gemini(*responses, finish_reason: "STOP")
    stub_request(:post, GEMINI_URL).with do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(*responses.map do |events|
      {
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: JSON.generate(
          candidates: [{content: {role: "model", parts: [{text: JSON.generate(events: events)}]}, finishReason: finish_reason}],
          usageMetadata: {promptTokenCount: 100, candidatesTokenCount: 50},
          modelVersion: "gemini-flash-latest"
        )
      }
    end)
  end
end
