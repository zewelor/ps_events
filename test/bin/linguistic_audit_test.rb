require "bundler/setup"
require "minitest/autorun"
require "test_helper"
load File.expand_path("../../bin/linguistic_audit", __dir__)

class LinguisticAuditTest < Minitest::Test
  def test_custom_endpoint_uses_chat_completions
    options = %i[openai_api_key openai_api_base openai_use_system_role]
    original_config = options.to_h { |key| [key, RubyLLM.config.public_send(key)] }
    original_key = ENV["AMALIA_API_KEY"]
    ENV["AMALIA_API_KEY"] = "integration-test-key"
    original_url = ENV["AMALIA_API_URL"]
    ENV["AMALIA_API_URL"] = "https://amalia.example/v1"
    request = stub_request(:post, "https://amalia.example/v1/chat/completions")
      .with { |req| JSON.parse(req.body).dig("messages", 0, "role") == "user" }
      .to_return(
        headers: {"Content-Type" => "application/json"},
        body: JSON.generate(choices: [{message: {role: "assistant", content: "Texto correto."}, finish_reason: "stop"}], usage: {prompt_tokens: 10, completion_tokens: 5})
      )

    assert_equal "Texto correto.", build_chat.ask("Verifica este texto.").content
    assert_requested request, times: 1
  ensure
    ENV["AMALIA_API_URL"] = original_url
    ENV["AMALIA_API_KEY"] = original_key
    RubyLLM.configure do |config|
      original_config.each { |key, value| config.public_send("#{key}=", value) }
    end
  end

  def test_clean_html_does_not_add_spaces_before_punctuation
    html = "<p>No <strong>PXO Pulse</strong>, escreva para <a>info@pxopulse.com</a>.</p>"

    assert_equal "No PXO Pulse, escreva para info@pxopulse.com.", clean_html(html)
  end

  def test_run_audit_reports_failure_when_api_request_fails
    chat = Object.new
    chat.define_singleton_method(:ask) { raise StandardError, "quota exceeded" }

    result = nil
    output, = capture_io do
      result = run_audit(files: [__FILE__], chat_factory: -> { chat })
    end

    refute result
    assert_includes output, "Erro na comunicação com a API da Amália"
  end
end
