require "bundler/setup"
require "minitest/autorun"
require "stringio"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/event_ocr_service"

class TestEventOcrService < Minitest::Test
  include TestHelper

  def setup
    TestHelper.setup_network_blocking

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
    EventOcrService.stub(:llm_client, RubyLLM) do
      RubyLLM.stub(:chat, @dummy_chat) { yield }
    end
  end

  def test_analyze_returns_single_event_from_collection
    with_stubbed_llm do
      @service = EventOcrService.new(model: "gemini-flash-latest", llm_recovery: :none)
      event = {
        name: "Evento de Teste",
        start_date: "15/06/2025",
        end_date: "15/06/2025",
        location: "Porto",
        description: "Um evento de teste válido para os nossos testes",
        category: "Música",
        organizer: nil
      }
      @service.instance_variable_get(:@chat).define_singleton_method(:ask) do |_message = nil, with:|
        RubyLLM::Message.new(role: :assistant, content: JSON.generate(events: [event]), finish_reason: :stop)
      end

      result = @service.analyze(File.expand_path("../fixtures/ocr_events.png", __dir__), retry_sleep: 0)

      assert_equal ["Evento de Teste"], result.map { |item| item[:name] }
      refute result.first.key?(:organizer)
    end
  end

  def test_analyze_rejects_array_with_mixed_validity
    with_stubbed_llm do
      @service = EventOcrService.new(model: "gemini-flash-latest")
      events = [
        {
          name: "Evento Válido",
          start_date: "15/06/2025",
          end_date: "15/06/2025",
          location: "Porto",
          description: "Um evento de teste válido para os nossos testes",
          category: "Música",
          organizer: "Organizador Teste"
        },
        {
          name: "AB",
          start_date: "15/06/2025",
          end_date: "15/06/2025",
          location: "Porto",
          description: "Um evento de teste válido para os nossos testes",
          category: "Música",
          organizer: "Organizador Teste"
        }
      ]
      call_count = 0
      @service.instance_variable_get(:@chat).define_singleton_method(:ask) do |_message = nil, with:|
        call_count += 1
        RubyLLM::Message.new(role: :assistant, content: JSON.generate(events: events), finish_reason: :stop)
      end

      error = nil
      retry_delays = []
      original_retry = Retryable.method(:retryable)
      capture_io do
        Retryable.stub :retryable, lambda { |**options, &block|
          retry_delays << options.fetch(:sleep)
          original_retry.call(**options.merge(sleep: 0), &block)
        } do
          error = assert_raises(EventValidationError) do
            @service.analyze(File.expand_path("../fixtures/ocr_events.png", __dir__), retry_sleep: 2)
          end
        end
      end

      assert_kind_of Hash, error.validation_errors
      assert_kind_of Array, error.event_data
      assert_operator call_count, :>, 1
      assert_equal [2], retry_delays
    end
  end
end
