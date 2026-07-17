require "test_helper"
load File.expand_path("../../bin/linguistic_audit", __dir__)

class LinguisticAuditTest < Minitest::Test
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
