require "bundler/setup"
require "minitest/autorun"
require "stringio"
require "ostruct"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/event_ocr_service"

class TestEventOcrService < Minitest::Test
  include TestHelper

  def setup
    TestHelper.setup_network_blocking

    # Provide a dummy chat object for RubyLLM.chat
    @dummy_chat = Object.new
    def @dummy_chat.with_schema(_schema)
      self
    end

    def @dummy_chat.with_thinking(_opts)
      self
    end
  end

  def teardown
    TestHelper.reset_network_mocks
  end

  def with_stubbed_llm
    RubyLLM.stub(:chat, @dummy_chat) { yield }
  end

  def test_parse_valid_json_array
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = [{name: "Evento de Teste", start_date: "15/06/2025", end_date: "15/06/2025", location: "Porto", description: "Um evento de teste válido para os nossos testes", category: "Música", organizer: "Organizador Teste"}]
      result = @service.send(:parse_and_validate_response, raw_response)
      assert_kind_of Array, result
      assert_equal 1, result.length
      assert_equal "Evento de Teste", result.first[:name]
      assert_equal "15/06/2025", result.first[:start_date]
    end
  end

  def test_parse_valid_json_single_object_converts_to_array
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = {name: "Evento de Teste", start_date: "15/06/2025", end_date: "15/06/2025", location: "Porto", description: "Um evento de teste válido para os nossos testes", category: "Música", organizer: "Organizador Teste"}
      result = @service.send(:parse_and_validate_response, raw_response)
      assert_kind_of Array, result
      assert_equal 1, result.length
      assert_equal "Evento de Teste", result.first[:name]
    end
  end

  def test_parse_valid_json_but_invalid_event_data
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = [{name: "AB", start_date: "invalid-date", end_date: "15/06/2025", location: "Porto", description: "Short desc", category: "Invalid Category", organizer: "Organizador Teste"}]
      error = assert_raises(EventValidationError) do
        @service.send(:parse_and_validate_response, raw_response)
      end
      assert_includes error.message, "Erro de validação no evento"
    end
  end

  def test_parse_multiple_events_mixed_validity
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = [{name: "Evento Válido", start_date: "15/06/2025", end_date: "15/06/2025", location: "Porto", description: "Um evento de teste válido para os nossos testes", category: "Música", organizer: "Organizador Teste"}, {name: "AB", start_date: "invalid-date", end_date: "15/06/2025", location: "Porto", description: "Short desc", category: "Invalid Category", organizer: "Organizador Teste"}]
      error = assert_raises(EventValidationError) do
        @service.send(:parse_and_validate_response, raw_response)
      end
      assert_includes error.message, "Erro de validação no evento"
    end
  end

  def test_retry_on_validation_error_with_captured_output
    with_stubbed_llm do
      @service = EventOcrService.new

      # Mock the chat object to return different responses on each call
      call_count = 0
      @service.instance_variable_get(:@chat).define_singleton_method(:with_instructions) do |instructions|
        @instructions = instructions
        self
      end

      @service.instance_variable_get(:@chat).define_singleton_method(:ask) do |message = nil, with:|
        call_count += 1
        case call_count
        when 1
          # First call - return valid JSON but invalid event data
          OpenStruct.new(content: [{name: "AB", start_date: "invalid-date", end_date: "15/06/2025", location: "Porto", description: "Short desc", category: "Invalid Category", organizer: "Organizador Teste"}])
        when 2
          # Second call - return valid event data
          OpenStruct.new(content: [{name: "Evento Teste", start_date: "15/06/2025", end_date: "15/06/2025", location: "Porto", description: "Um evento de teste válido para os nossos testes", category: "Música", organizer: "Organizador Teste"}])
        end
      end

      # Capture stdout to verify debug messages
      stdout, _stderr = capture_io do
        result = @service.analyze("/fake/image/path", retry_sleep: 0)
        assert_equal 1, result.length
        assert_equal "Evento Teste", result.first[:name]
      end

      # Verify retry debug messages are present
      assert_includes stdout, "🔄 Retrying due to validation error"
      assert_includes stdout, "🔄 Retry attempt 0"
      assert_includes stdout, "📋 Original error message"
      assert_equal 2, call_count
    end
  end

  def test_successful_first_attempt_no_retry_messages
    with_stubbed_llm do
      @service = EventOcrService.new

      # Mock the chat object to return valid data on first attempt
      call_count = 0
      @service.instance_variable_get(:@chat).define_singleton_method(:with_instructions) do |instructions|
        @instructions = instructions
        self
      end

      @service.instance_variable_get(:@chat).define_singleton_method(:ask) do |message = nil, with:|
        call_count += 1
        # Return valid event data on first attempt
        OpenStruct.new(content: [{name: "Evento Teste", start_date: "15/06/2025", end_date: "15/06/2025", location: "Porto", description: "Um evento de teste válido para os nossos testes", category: "Música", organizer: "Organizador Teste"}])
      end

      # Capture stdout to verify no retry messages
      stdout, _stderr = capture_io do
        result = @service.analyze("/fake/image/path", retry_sleep: 0)
        assert_equal 1, result.length
        assert_equal "Evento Teste", result.first[:name]
      end

      # Verify no retry messages are present
      refute_includes stdout, "🔄 Retrying due to validation error"
      refute_includes stdout, "🔄 Retry attempt"
      refute_includes stdout, "📋 Original error message"
      assert_equal 1, call_count
    end
  end

  def test_no_network_requests_made_during_tests
    # This test verifies that our mocking is working and no real network calls are made
    with_stubbed_llm do
      @service = EventOcrService.new

      # Mock the chat object
      @service.instance_variable_get(:@chat).define_singleton_method(:with_instructions) do |instructions|
        @instructions = instructions
        self
      end

      @service.instance_variable_get(:@chat).define_singleton_method(:ask) do |message = nil, with:|
        # Return valid event data
        OpenStruct.new(content: [{name: "Evento Teste", start_date: "15/06/2025", end_date: "15/06/2025", location: "Porto", description: "Um evento de teste válido para os nossos testes", category: "Música", organizer: "Organizador Teste"}])
      end

      # This should work without any network requests
      result = @service.analyze("/fake/image/path", retry_sleep: 0)
      assert_equal 1, result.length
      assert_equal "Evento Teste", result.first[:name]

      # WebMock will raise an error if any HTTP requests were attempted
      # The fact that we reach this point means no network requests were made
      assert true, "No network requests were made during the test"
    end
  end

  def test_webmock_blocks_real_network_requests
    # This test demonstrates that WebMock is actually working
    # If we try to make a real HTTP request, it should be blocked

    error = assert_raises(WebMock::NetConnectNotAllowedError) do
      # Try to make a real HTTP request - this should be blocked by WebMock
      require "net/http"
      Net::HTTP.get(URI("https://api.gemini.google.com/test"))
    end

    assert_includes error.message, "Real HTTP connections are disabled"
  end
end
