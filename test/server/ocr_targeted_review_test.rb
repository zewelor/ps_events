require "bundler/setup"
require "fileutils"
require "minitest/autorun"
require "open3"
require_relative "../test_helper"
require_relative "../../lib/server/ocr/targeted_review"
require "tmpdir"
require "digest"
require "json"

class OcrTargetedReviewTest < Minitest::Test
  IMAGE = File.expand_path("../fixtures/ocr_events.png", __dir__)
  SENT_IMAGE = File.expand_path("../fixtures/ocr/images/pijama_2026_facebook_poster.jpg", __dir__)
  CLI = File.expand_path("../../bin/ocr_review", __dir__)

  def test_questions_preserve_originals_and_batch_by_image
    with_artifact do |dir, source|
      calls = []
      judge = ->(input, questions, image) {
        calls << [input, questions, image]
        questions.to_h { |key, _| [key, {choice: "uncertain"}] }
      }
      report = Ocr::TargetedReview.new(judge: judge).call(dir)
      assert_equal source["events"], report[:events]
      assert_equal source["review_items"], report[:review_items]
      assert_equal 1, calls.size
      assert_equal %w[date_range organizer description_role missing_start_date missing_location], report[:questions].map { |question| question[:field] }
      assert_equal ["uncertain"], report[:questions].map { |question| question.dig(:answer, :choice) }.uniq
    end
  end

  def test_separate_mode_asks_same_questions_and_rejects_hash_mismatch
    with_artifact do |dir, _source|
      calls = []
      judge = ->(_input, questions, _image) {
        calls << questions
        questions.to_h { |key, _| [key, {choice: "supported"}] }
      }
      Ocr::TargetedReview.new(mode: :separate, judge: judge).call(dir)
      assert_equal 5, calls.size
      File.binwrite(File.join(dir, "source.png"), "different")
      assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: judge).call(dir) }
    end
  end

  def test_questions_cover_missing_start_time_and_generic_role_claims
    with_artifact do |dir, source|
      source["events"] = [{"name" => "Concerto", "description" => "Com Porta 33", "end_time" => "23:00",
                           "start_date" => 2026, "end_date" => "03/01/2026"}]
      source["review_items"] = [{"reason" => "ambiguous_venue_policy", "candidate" => {"name" => "Peça"}}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) { questions.to_h { |key, _| [key, {choice: "unsupported"}] } }
      result = Ocr::TargetedReview.new(judge: judge).call(dir)
      assert_equal %w[missing_start_time description_role missing_location], result[:questions].map { |q| q[:field] }
    end
  end

  def test_blank_dates_and_times_count_as_missing
    with_artifact do |dir, source|
      source["events"] = [
        {"name" => "Concerto", "start_date" => "", "end_date" => "03/01/2026", "start_time" => " \t", "end_time" => "23:00"},
        {"name" => "Workshop", "end_date" => " \t", "end_time" => ""}
      ]
      source["review_items"] = []
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) { questions.transform_values { {choice: "unsupported"} } }

      report = Ocr::TargetedReview.new(judge: judge).call(dir)

      assert_equal [["event:1", "missing_start_date"], ["event:1", "missing_start_time"]],
        report.fetch(:questions).map { |question| question.values_at(:record_id, :field) }
    end
  end

  def test_separate_mode_preserves_partial_results_and_same_input
    with_artifact do |dir, _source|
      inputs = []
      judge = lambda do |input, questions, _image|
        inputs << input
        raise "connection failed" if inputs.length == 2

        questions.to_h { |key, _| [key, {choice: "supported"}] }
      end
      report = Ocr::TargetedReview.new(mode: :separate, judge: judge).call(dir)
      assert_equal "technical_failure", report[:status]
      assert_equal 1, inputs.uniq.length
      assert_equal "supported", report[:questions].first.dig(:answer, :choice)
      assert_equal "connection failed", report[:questions][1].dig(:error, :message)
      assert_equal "supported", report[:questions].last.dig(:answer, :choice)
    end
  end

  def test_separate_mode_keeps_using_the_verified_image_after_the_file_changes
    with_artifact do |dir, source|
      hashes = []
      judge = lambda do |_input, questions, image|
        hashes << Digest::SHA256.hexdigest(RubyLLM::Attachment.wrap(image).first.content)
        FileUtils.cp(SENT_IMAGE, File.join(dir, "source.png")) if hashes.one?
        questions.transform_values { {choice: "supported"} }
      end

      report = Ocr::TargetedReview.new(mode: :separate, judge: judge).call(dir)

      assert_operator hashes.length, :>, 1
      assert_equal [source.dig("hashes", "sent_sha256")], hashes.uniq
      assert_equal "advisory", report.fetch(:status)
    end
  end

  def test_review_of_missing_day_and_place_asks_about_both_fields
    with_artifact do |dir, source|
      source["events"] = []
      source["review_items"] = [{"reason" => "missing_start_date", "candidate" => {"name" => "Workshop", "location" => nil}}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) { questions.to_h { |key, _| [key, {choice: "unsupported"}] } }
      report = Ocr::TargetedReview.new(judge: judge).call(dir)
      assert_equal %w[missing_start_date missing_location], report[:questions].map { |q| q[:field] }
    end
  end

  def test_conflicting_location_evidence_asks_about_populated_venue
    with_artifact do |dir, source|
      source["events"] = []
      source["review_items"] = [{"reason" => "conflicting_location_evidence", "candidate" => {"name" => "Workshop", "location" => "Auditório"}}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) { questions.to_h { |key, _| [key, {choice: "supported"}] } }

      report = Ocr::TargetedReview.new(judge: judge).call(dir)

      assert_equal [["review:1", "missing_location"]], report.fetch(:questions).map { |question| question.values_at(:record_id, :field) }
    end
  end

  def test_conflicting_location_on_an_admitted_event_asks_about_that_venue
    with_artifact do |dir, source|
      source["events"] = [{"name" => "Workshop"}, {"name" => "Concerto"}]
      source["review_items"] = []
      source["uncertain_fields_by_index"] = {
        "1" => {"location" => {"candidate" => "Biblioteca Municipal", "evidence" => "Auditório do CCC"}}
      }
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) { questions.transform_values { {choice: "supported"} } }

      report = Ocr::TargetedReview.new(judge: judge).call(dir)

      assert_equal [["event:2", "missing_location"]], report.fetch(:questions).map { |question| question.values_at(:record_id, :field) }
    end
  end

  def test_review_asks_about_populated_start_date_without_source
    with_artifact do |dir, source|
      candidate = {"name" => "Workshop", "start_date" => "03/01/2026"}
      source["events"] = []
      source["review_items"] = [{"reason" => "missing_start_date", "candidate" => candidate}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) { questions.to_h { |key, _| [key, {choice: "unsupported"}] } }

      report = Ocr::TargetedReview.new(judge: judge).call(dir)

      assert_equal [["review:1", "missing_start_date", candidate, "unsupported"]], report[:questions].map { |q| q.values_at(:record_id, :field, :candidate) + [q.dig(:answer, :choice)] }
    end
  end

  def test_review_asks_about_missing_date_even_when_location_is_the_primary_reason
    with_artifact do |dir, source|
      source["events"] = []
      source["review_items"] = [{"reason" => "missing_location", "candidate" => {"name" => "Workshop"}, "trace" => {"date_source" => "none"}}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) { questions.to_h { |key, _| [key, {choice: "unsupported"}] } }

      report = Ocr::TargetedReview.new(judge: judge).call(dir)

      assert_equal %w[missing_start_date missing_location], report.fetch(:questions).map { |question| question[:field] }
    end
  end

  def test_optional_repair_uses_same_capped_image_and_preserves_advisory_records
    with_artifact do |dir, source|
      FileUtils.cp(SENT_IMAGE, File.join(dir, "sent.jpg"))
      source["hashes"]["sent_sha256"] = Digest::SHA256.file(SENT_IMAGE).hexdigest
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(_input, questions, _image) {
        FileUtils.cp(IMAGE, File.join(dir, "sent.jpg"))
        questions.transform_values { {choice: "unsupported"} }
      }
      images = []
      repairer = ->(_input, image) {
        images << Digest::SHA256.hexdigest(image.content)
        {"proposals" => []}
      }
      report = Ocr::TargetedReview.new(judge: judge, repair: true, repairer: repairer).call(dir)
      assert_equal [source.dig("hashes", "sent_sha256")], images
      assert_equal source["events"], report[:events]
      assert_equal "advisory", report.dig(:repair, :status)
    end
  end

  def test_legacy_reader_directory_uses_hash_matched_extensionless_images
    with_artifact do |dir, source|
      reader = File.join(dir, "reader")
      FileUtils.mkdir(reader)
      %w[reader_request.json reader_response.json].each { |name| FileUtils.mv(File.join(dir, name), reader) }
      FileUtils.mv(File.join(dir, "source.png"), File.join(reader, "source"))
      FileUtils.cp(SENT_IMAGE, File.join(reader, "sent"))
      source["hashes"]["sent_sha256"] = Digest::SHA256.file(SENT_IMAGE).hexdigest
      FileUtils.rm(File.join(dir, "result.json"))
      File.write(File.join(dir, "source.json"), JSON.generate(source))
      judge = ->(_input, questions, image) {
        assert_equal source.dig("hashes", "sent_sha256"), Digest::SHA256.hexdigest(image.content)
        questions.to_h { |key, _| [key, {choice: "supported"}] }
      }

      assert_equal "advisory", Ocr::TargetedReview.new(judge: judge).call(dir)[:status]
      File.binwrite(File.join(reader, "sent"), "wrong")
      FileUtils.cp(SENT_IMAGE, File.join(reader, "sent.json"))
      assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: ->(*) { flunk "unexpected judge call" }).call(dir) }
    end
  end

  def test_rejects_inconsistent_reader_artifacts_before_calling_judge
    judge = ->(*) { flunk "inconsistent artifacts must not call the judge" }
    %w[reader_prompt_sha256 reader_request_sha256 reader_schema_sha256].each do |key|
      with_artifact do |dir, source|
        source.fetch("hashes").delete(key)
        File.write(File.join(dir, "result.json"), JSON.generate(source))
        error = assert_raises(KeyError) { Ocr::TargetedReview.new(judge: judge).call(dir) }
        assert_includes error.message, key
      end
    end

    with_artifact do |dir, source|
      path = File.join(dir, "reader_request.json")
      original = File.read(path)
      File.write(path, JSON.generate(JSON.parse(original).merge("prompt" => "different")))
      error = assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: judge).call(dir) }
      assert_match(/reader_request_sha256 mismatch/, error.message)
      File.write(path, original)

      source["calls"] = []
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      error = assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: judge).call(dir) }
      assert_match(/Missing reader call/, error.message)

      source["calls"] = [{"stage" => "reader", "raw_text" => "different"}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      error = assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: judge).call(dir) }
      assert_match(/Reader response differs/, error.message)
    end
  end

  def test_rejects_non_object_records_before_calling_judge
    %w[review_items events].each do |key|
      with_artifact do |dir, source|
        source[key] = ["broken"]
        File.write(File.join(dir, "result.json"), JSON.generate(source))
        judge = ->(*) { flunk "malformed #{key} must not call the judge" }

        error = assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: judge).call(dir) }
        assert_equal "#{key} must contain only objects", error.message
      end
    end
  end

  def test_rejects_non_object_review_candidates_before_calling_judge
    with_artifact do |dir, source|
      source["events"] = []
      source["review_items"] = [{"reason" => "missing_start_date", "candidate" => "broken"}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(*) { flunk "malformed candidates must not call the judge" }

      assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: judge).call(dir) }
    end
  end

  def test_legacy_source_without_sent_hash_can_use_only_the_original_image
    with_artifact("ocr-[review]") do |dir, source|
      source.fetch("hashes").delete("sent_sha256")
      path = File.join(dir, "result.json")
      File.write(path, JSON.generate(source))
      reject = ->(*) { flunk "unverified image must not reach the judge" }
      assert_raises(ArgumentError, KeyError) { Ocr::TargetedReview.new(judge: reject).call(dir) }

      File.rename(path, File.join(dir, "source.json"))
      judge = ->(_input, questions, image) {
        assert_equal source.dig("hashes", "source_sha256"), Digest::SHA256.hexdigest(image.content)
        questions.transform_values { {choice: "uncertain"} }
      }
      report = Ocr::TargetedReview.new(judge: judge).call(dir)
      assert_equal source.dig("hashes", "source_sha256"), report.fetch(:sent_sha256)

      FileUtils.cp(SENT_IMAGE, File.join(dir, "sent.jpg"))
      error = assert_raises(ArgumentError) { Ocr::TargetedReview.new(judge: reject).call(dir) }
      assert_equal "Missing sent_sha256", error.message
    end
  end

  def test_rejects_pdf_before_calling_judge
    with_artifact do |dir, source|
      pdf = "%PDF-1.4\n"
      FileUtils.rm(File.join(dir, "source.png"))
      File.binwrite(File.join(dir, "source.pdf"), pdf)
      %w[source_sha256 sent_sha256].each { |key| source["hashes"][key] = Digest::SHA256.hexdigest(pdf) }
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(*) { flunk "PDF must not call the judge" }

      error = assert_raises(ArgumentError) { Ocr::TargetedReview.new(mode: :separate, judge: judge).call(dir) }
      assert_match(/not an image/, error.message)
    end
  end

  def test_no_matching_questions_makes_no_calls
    with_artifact do |dir, source|
      source["events"] = [{"name" => "Concerto"}]
      source["review_items"] = [{"reason" => "missing_start_date", "candidate" => nil}]
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      judge = ->(*) { flunk "no questions to send" }

      report = Ocr::TargetedReview.new(judge: judge).call(dir)

      assert_equal "advisory", report.fetch(:status)
      assert_empty report.fetch(:questions)
      assert_empty report.fetch(:calls)
    end
  end

  def test_invalid_batch_does_not_keep_partial_answers
    with_artifact do |dir, _source|
      judge = ->(_input, questions, _image) {
        questions.keys.each_with_index.to_h { |id, index| [id, {choice: (index == 1) ? "invalid" : "supported"}] }
      }

      report = Ocr::TargetedReview.new(judge: judge).call(dir)

      assert_equal "technical_failure", report.fetch(:status)
      error = report.fetch(:calls).first.fetch(:error)
      report.fetch(:questions).each do |question|
        refute question.key?(:answer)
        assert_equal error, question.fetch(:error)
      end
    end
  end

  def test_cli_sends_image_and_typed_questions_to_decisions
    with_artifact do |dir, source|
      source["events"] = [{"name" => "Concerto", "organizer" => "Associação Cultural"}]
      source["review_items"] = []
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      preload = File.join(dir, "decisions_stub.rb")
      File.write(preload, <<~RUBY)
        require "base64"
        require "digest"
        require "json"
        require "webmock"
        WebMock.enable!
        WebMock.disable_net_connect!
        status = Integer(ENV.fetch("OCR_DECISIONS_TEST_HTTP_STATUS", "200"))
        body = if status == 200
          {model: "gpt-6-luna", answers: [{name: "q1", choice: "supported", confidence: 0.9,
            probabilities: [{value: "supported", probability: 0.9}, {value: "unsupported", probability: 0.05}, {value: "uncertain", probability: 0.05}]}]}
        else
          {error: {type: "server_error", message: "Temporarily unavailable"}}
        end
        WebMock.stub_request(:post, "https://api.openai.com/v1/decisions").with do |request|
          payload = JSON.parse(request.body)
          question = payload.fetch("questions").fetch(0)
          content = payload.fetch("input").first.fetch("content")
          image = content.find { |part| part["type"] == "input_image" }
          data = Base64.decode64(image.fetch("image_url").split(",", 2).last)
          payload["model"] == "gpt-6-luna" &&
            payload.fetch("questions").size == 1 &&
            question.values_at("name", "type") == ["q1", "choice"] &&
            question.fetch("choices").map { |choice| choice.fetch("value") } == %w[supported unsupported uncertain] &&
            Digest::SHA256.hexdigest(data) == "#{source.fetch("hashes").fetch("sent_sha256")}"
        end.to_return(status: status, headers: {"Content-Type" => "application/json"}, body: JSON.generate(body))
      RUBY
      env = {"OPENAI_API_KEY" => "offline-test-key"}
      command = ["bundle", "exec", "ruby", "-r", preload, CLI, "--mode", "separate", dir]
      stdout, stderr, status = Open3.capture3(env, *command)

      assert status.success?, "#{stderr}\n#{stdout}"
      report = JSON.parse(stdout)
      assert_equal ["advisory", "separate"], report.values_at("status", "mode")
      assert_equal source.fetch("events"), report.fetch("events")
      assert_equal "supported", report.dig("questions", 0, "answer", "choice")
      assert_equal "supported", report.dig("calls", 0, "evidence", "raw_body", "answers", 0, "choice")

      stdout, stderr, status = Open3.capture3(env.merge("OCR_DECISIONS_TEST_HTTP_STATUS" => "503"), *command)
      assert_equal 1, status.exitstatus, "#{stderr}\n#{stdout}"
      failure = JSON.parse(stdout)
      assert_equal "technical_failure", failure.fetch("status")
      assert_equal "RubyLLM::ServiceUnavailableError", failure.dig("calls", 0, "error", "type")
    end
  end

  private

  def with_artifact(name = "artifact")
    Dir.mktmpdir do |root|
      dir = File.join(root, name)
      Dir.mkdir(dir)
      image_hash = Digest::SHA256.file(IMAGE).hexdigest
      FileUtils.cp(IMAGE, File.join(dir, "source.png"))
      request = {"instructions" => "Instructions", "prompt" => "Document context", "schema" => {}}
      response = {"stage" => "reader", "raw_text" => "{}"}
      source = {"events" => [{"name" => "Show", "start_date" => "01/01/2026", "end_date" => "03/01/2026", "organizer" => "Porta 33", "description" => "Organizado pela Porta 33"}],
                "review_items" => [{"reason" => "missing_start_date", "candidate" => {"name" => "Other", "end_date" => "03/01/2026"}}, {"reason" => "missing_location", "candidate" => {"name" => "Venue"}}],
                "hashes" => {"source_sha256" => image_hash, "sent_sha256" => image_hash,
                             "reader_prompt_sha256" => Digest::SHA256.hexdigest(request.fetch("instructions")),
                             "reader_request_sha256" => Digest::SHA256.hexdigest(request.fetch("prompt")),
                             "reader_schema_sha256" => Digest::SHA256.hexdigest(JSON.generate(request.fetch("schema")))},
                "calls" => [response]}
      File.write(File.join(dir, "result.json"), JSON.generate(source))
      File.write(File.join(dir, "reader_request.json"), JSON.generate(request))
      File.write(File.join(dir, "reader_response.json"), JSON.generate(response))
      yield dir, source
    end
  end
end
