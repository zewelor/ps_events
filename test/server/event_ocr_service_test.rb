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

  def test_analyze_normalizes_single_json_object_to_array
    with_stubbed_llm do
      @service = EventOcrService.new
      event = {
        name: "Evento de Teste",
        start_date: "15/06/2025",
        end_date: "15/06/2025",
        location: "Porto",
        description: "Um evento de teste válido para os nossos testes",
        category: "Música",
        organizer: "Organizador Teste"
      }
      @service.instance_variable_get(:@chat).define_singleton_method(:ask) do |_message = nil, with:|
        OpenStruct.new(content: JSON.generate(event))
      end

      result = @service.analyze("/fake/image/path", retry_sleep: 0)

      assert_equal ["Evento de Teste"], result.map { |item| item[:name] }
    end
  end

  def test_analyze_rejects_array_with_mixed_validity
    with_stubbed_llm do
      @service = EventOcrService.new
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
        OpenStruct.new(content: JSON.generate(events))
      end

      error = nil
      retry_delays = []
      original_retry = Retryable.method(:retryable)
      capture_io do
        Retryable.stub :retryable, lambda { |**options, &block|
          retry_delays << options.fetch(:sleep)
          original_retry.call(**options.merge(sleep: 0), &block)
        } do
          error = assert_raises(RuntimeError) do
            @service.analyze("/fake/image/path", retry_sleep: 2)
          end
        end
      end

      assert_includes error.message, "Erro ao analisar imagem:"
      assert_operator call_count, :>, 1
      assert_equal [2], retry_delays
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

      @service.define_singleton_method(:analyze_image) do |path, retry_sleep:, additional_text:|
        [{name: "Evento de #{File.basename(path)}", retry_sleep: retry_sleep, additional_text: additional_text}]
      end

      result = @service.analyze("/tmp/sample.pdf", retry_sleep: 1, additional_text: "Texto do post")

      assert_equal 2, result.length
      assert_equal "Evento de page-0001.png", result[0][:name]
      assert_equal "Evento de page-0002.png", result[1][:name]
      assert_equal 1, result[0][:retry_sleep]
      assert_equal "Texto do post", result[0][:additional_text]
      refute Dir.exist?(temp_dir)
    end
  end
end
