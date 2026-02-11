require "bundler/setup"
require "minitest/autorun"
require "stringio"
require "ostruct"
require "tmpdir"
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

    def @dummy_chat.with_instructions(_instructions)
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

  def test_analyze_routes_pdf_to_pdf_handler
    with_stubbed_llm do
      @service = EventOcrService.new
      called_with = nil

      @service.define_singleton_method(:analyze_pdf) do |path, retry_sleep:|
        called_with = [path, retry_sleep]
        [{name: "Evento PDF"}]
      end

      result = @service.analyze("/tmp/events.pdf", retry_sleep: 3)

      assert_equal [{name: "Evento PDF"}], result
      assert_equal ["/tmp/events.pdf", 3], called_with
    end
  end

  def test_analyze_routes_image_to_image_handler
    with_stubbed_llm do
      @service = EventOcrService.new
      called_with = nil

      @service.define_singleton_method(:analyze_image) do |path, retry_sleep:|
        called_with = [path, retry_sleep]
        [{name: "Evento Imagem"}]
      end

      result = @service.analyze("/tmp/events.png", retry_sleep: 2)

      assert_equal [{name: "Evento Imagem"}], result
      assert_equal ["/tmp/events.png", 2], called_with
    end
  end

  def test_analyze_pdf_aggregates_all_pages_and_cleans_temp_dir
    with_stubbed_llm do
      @service = EventOcrService.new
      temp_dir = Dir.mktmpdir("event_ocr_pdf_test_")
      page_one = File.join(temp_dir, "page-0001.png")
      page_two = File.join(temp_dir, "page-0002.png")
      File.write(page_one, "page1")
      File.write(page_two, "page2")

      @service.define_singleton_method(:extract_pdf_pages_to_images) do |_pdf_path|
        [[page_one, page_two], temp_dir]
      end

      @service.define_singleton_method(:analyze_image) do |path, retry_sleep:|
        [{name: "Evento de #{File.basename(path)}", retry_sleep: retry_sleep}]
      end

      result = @service.send(:analyze_pdf, "/tmp/sample.pdf", retry_sleep: 1)

      assert_equal 2, result.length
      assert_equal "Evento de page-0001.png", result[0][:name]
      assert_equal "Evento de page-0002.png", result[1][:name]
      assert_equal 1, result[0][:retry_sleep]
      refute Dir.exist?(temp_dir)
    end
  end

  def test_extract_pdf_pages_to_images_uses_minimagick_convert
    with_stubbed_llm do
      @service = EventOcrService.new
      temp_dir = Dir.mktmpdir("event_ocr_pdf_convert_test_")
      output_file = File.join(temp_dir, "page-0001.png")
      convert_called = false

      fake_tool = Object.new
      fake_tool.define_singleton_method(:density) { |_value| nil }
      fake_tool.define_singleton_method(:<<) { |_value| nil }

      Dir.stub(:mktmpdir, temp_dir) do
        MiniMagick.stub(:convert, lambda { |&blk|
          convert_called = true
          blk.call(fake_tool)
          File.write(output_file, "png")
        }) do
          page_paths, returned_dir = @service.send(:extract_pdf_pages_to_images, "/tmp/sample.pdf")

          assert convert_called
          assert_equal [output_file], page_paths
          assert_equal temp_dir, returned_dir
        end
      end
    ensure
      @service.send(:cleanup_temp_dir, temp_dir)
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
