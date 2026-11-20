require "bundler/setup"
require "minitest/autorun"
require "base64"
require "tmpdir"
require_relative "../test_helper"
require_relative "../../lib/server/ocr/source_workflow"

class OcrSourceWorkflowTest < Minitest::Test
  def setup
    TestHelper.setup_network_blocking
    @key = RubyLLM.config.openai_api_key
    RubyLLM.configure { |config| config.openai_api_key = "offline-key" }
    @path = File.expand_path("../fixtures/ocr_events.png", __dir__)
    @requests = []
  end

  def teardown
    RubyLLM.configure { |config| config.openai_api_key = @key }
    TestHelper.reset_network_mocks
  end

  def candidate(**overrides)
    {
      name: "Concerto", start_date: "14/11/2026", start_time: nil, end_date: nil, end_time: nil,
      location: "Biblioteca Municipal", description: "Concerto na biblioteca.", category: "Música",
      organizer: nil, contact_email: nil, contact_tel: nil, price_type: "Desconhecido",
      event_link1: nil, event_link2: nil, event_link3: nil, event_link4: nil,
      location_evidence: "Biblioteca Municipal", location_source: "main_text", date_source: "main_text",
      time_source: "none", price_source: "none", review_reason: "none", review_detail: nil
    }.merge(overrides)
  end

  def stub_reader(payload, status: "completed")
    body = {
      id: "response", object: "response", status: status, model: "gpt-6.1-terra",
      output: [{id: "message", type: "message", role: "assistant", content: [{type: "output_text", text: payload.is_a?(String) ? payload : JSON.generate(payload)}]}],
      usage: {input_tokens: 200, output_tokens: 50}
    }
    body[:incomplete_details] = {reason: "max_output_tokens"} if status == "incomplete"
    WebMock.stub_request(:post, "https://api.openai.com/v1/responses").with do |request|
      @requests << JSON.parse(request.body)
      true
    end.to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: JSON.generate(body))
  end

  def payload(candidates)
    {panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: candidates}]}
  end

  def test_multiple_events_and_review_items_use_one_untouched_attachment
    stub_reader(payload([candidate, candidate(name: "Sem local", location: nil, location_evidence: nil, location_source: "none", review_reason: "missing_location"), candidate(name: "Conflito", date_source: "inset", review_reason: "conflicting_inset")]))
    result = Ocr::SourceWorkflow.new.analyze(@path)
    assert_equal 1, result[:events].length
    assert_equal %w[missing_location conflicting_inset], result[:review_items].map { |item| item[:reason] }
    assert_equal 1, @requests.length
    image = @requests.first.fetch("input").flat_map { |item| item["content"].is_a?(Array) ? item["content"] : [] }.find { |part| part["type"] == "input_image" }
    assert_equal File.binread(@path), Base64.decode64(image.fetch("image_url").split(",", 2).last)
    assert_equal ["reader"], result[:calls].map { |call| call[:stage] }
  end

  def test_invalid_event_fields_hold_the_candidate_and_preserve_ready_siblings
    stub_reader(payload([candidate, candidate(name: "Outro concerto", start_date: "31/11/2026")]))

    result = Ocr::SourceWorkflow.new.analyze(@path)

    assert_equal ["Concerto"], result.fetch(:events).map { |event| event[:name] }
    review, = result.fetch(:review_items)
    assert_equal "invalid_event_fields", review.fetch(:reason)
    assert_equal ["Outro concerto", "31/11/2026"], review.fetch(:candidate).values_at(:name, :start_date)
    assert_equal [:start_date], review.fetch(:validation_errors).keys
  end

  def test_attachment_and_hash_use_same_snapshot_if_source_changes
    Dir.mktmpdir do |dir|
      path = File.join(dir, "source.png")
      original_bytes = File.binread(@path)
      File.binwrite(path, original_bytes)
      stub_reader(payload([candidate]))
      attachment_new = RubyLLM::Attachment.method(:new)
      replacement = proc do |snapshot_path, **kwargs|
        File.binwrite(path, "source changed")
        attachment_new.call(snapshot_path, **kwargs)
      end
      result = RubyLLM::Attachment.stub(:new, replacement) { Ocr::SourceWorkflow.new.analyze(path) }
      image = @requests.first.fetch("input").flat_map { |item| item["content"].is_a?(Array) ? item["content"] : [] }.find { |part| part["type"] == "input_image" }
      assert_equal original_bytes, Base64.decode64(image.fetch("image_url").split(",", 2).last)
      assert_equal Digest::SHA256.hexdigest(original_bytes), result.dig(:hashes, :source_sha256)
    end
  end

  def test_full_schema_rejects_unavailable_source_unknown_field_and_wrong_type
    [candidate(location_source: "additional_text"), candidate(extra: "unknown"), candidate(name: 123)].each do |bad|
      stub_reader(payload([bad]))
      workflow = Ocr::SourceWorkflow.new
      assert_raises(Ocr::WorkflowError) { workflow.analyze(@path) }
      assert_equal "reader", workflow.run_evidence[:stage]
      assert_equal 1, workflow.run_evidence[:calls].size
    end
  end

  def test_non_image_rejected_before_api_call
    Dir.mktmpdir do |dir|
      path = File.join(dir, "document.txt")
      File.write(path, "not an image")
      workflow = Ocr::SourceWorkflow.new
      assert_raises(ArgumentError) { workflow.analyze(path) }
      assert_equal "init", workflow.run_evidence[:stage]
      assert_empty workflow.run_evidence[:calls]
      assert_empty WebMock::RequestRegistry.instance.requested_signatures.hash
    end
  end

  def test_nonempty_artifact_directory_is_not_overwritten_or_reused
    Dir.mktmpdir do |dir|
      stub_reader(payload([candidate]))
      Ocr::SourceWorkflow.new.analyze(@path, artifact_dir: dir)
      response_path = File.join(dir, "reader_response.json")
      original = File.binread(response_path)
      workflow = Ocr::SourceWorkflow.new
      assert_raises(ArgumentError) { workflow.analyze(@path, artifact_dir: dir) }
      assert_equal "init", workflow.run_evidence[:stage]
      assert_empty workflow.run_evidence[:calls]
      assert_equal original, File.binread(response_path)
      assert_equal 1, @requests.length
    end
  end

  def test_failed_request_persists_error_in_new_artifact_directory
    Dir.mktmpdir do |dir|
      WebMock.stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 400, body: "bad request")
      assert_raises(StandardError) { Ocr::SourceWorkflow.new.analyze(@path, artifact_dir: dir) }
      response = JSON.parse(File.read(File.join(dir, "reader_response.json")))
      assert_equal "reader", response.fetch("stage")
      assert response.dig("error", "message")
    end
  end

  def test_request_failure_records_the_failed_reader_call
    WebMock.stub_request(:post, "https://api.openai.com/v1/responses").to_return(status: 400, body: "bad request")
    workflow = Ocr::SourceWorkflow.new
    assert_raises(StandardError) { workflow.analyze(@path) }
    call = workflow.run_evidence[:calls].first
    assert_equal "reader", call[:stage]
    assert call.dig(:error, :message)
    assert_equal 1, WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum
  end

  def test_malformed_and_incomplete_responses_preserve_evidence
    [["not json", "completed"], [payload([]), "incomplete"]].each do |data, status|
      stub_reader(data, status: status)
      workflow = Ocr::SourceWorkflow.new
      assert_raises(Ocr::WorkflowError) { workflow.analyze(@path) }
      assert_equal 1, workflow.run_evidence[:calls].size
      assert workflow.run_evidence[:calls].first[:raw_text]
    end
  end
end
