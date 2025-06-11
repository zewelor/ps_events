require "bundler/setup"
require "minitest/autorun"
require "json"

Bundler.require(:default)

require_relative "../../lib/server/event_ocr_service"

class TestEventOcrService < Minitest::Test
  def setup
    # Provide a dummy chat object for RubyLLM.chat
    @dummy_chat = Object.new
  end

  def with_stubbed_llm
    RubyLLM.stub(:chat, @dummy_chat) { yield }
  end

  def test_parse_valid_json_array
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = '[{"name": "Evento de Teste", "start_date": "15/06/2025", "end_date": "15/06/2025", "location": "Porto", "description": "Um evento de teste válido para os nossos testes", "category": "Música", "organizer": "Organizador Teste"}]'
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
      raw_response = '{"name": "Evento de Teste", "start_date": "15/06/2025", "end_date": "15/06/2025", "location": "Porto", "description": "Um evento de teste válido para os nossos testes", "category": "Música", "organizer": "Organizador Teste"}'
      result = @service.send(:parse_and_validate_response, raw_response)
      assert_kind_of Array, result
      assert_equal 1, result.length
      assert_equal "Evento de Teste", result.first[:name]
    end
  end

  def test_parse_invalid_json
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = "{ invalid json"
      error = assert_raises(RuntimeError) do
        @service.send(:parse_and_validate_response, raw_response)
      end
      assert_includes error.message, "Erro ao analisar JSON"
    end
  end

  def test_parse_valid_json_but_invalid_event_data
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = '[{"name": "AB", "start_date": "invalid-date", "end_date": "15/06/2025", "location": "Porto", "description": "Short desc", "category": "Invalid Category", "organizer": "Organizador Teste"}]'
      error = assert_raises(RuntimeError) do
        @service.send(:parse_and_validate_response, raw_response)
      end
      assert_includes error.message, "Erro de validação no evento"
    end
  end

  def test_parse_multiple_events_mixed_validity
    with_stubbed_llm do
      @service = EventOcrService.new
      raw_response = '[{"name": "Evento Válido", "start_date": "15/06/2025", "end_date": "15/06/2025", "location": "Porto", "description": "Um evento de teste válido para os nossos testes", "category": "Música", "organizer": "Organizador Teste"}, {"name": "AB", "start_date": "invalid-date", "end_date": "15/06/2025", "location": "Porto", "description": "Short desc", "category": "Invalid Category", "organizer": "Organizador Teste"}]'
      error = assert_raises(RuntimeError) do
        @service.send(:parse_and_validate_response, raw_response)
      end
      assert_includes error.message, "Erro de validação no evento"
    end
  end
end
