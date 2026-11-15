require "bundler/setup"
require "minitest/autorun"
require "json"
require "digest"
require "open3"
require "tmpdir"

class OcrCliTest < Minitest::Test
  BIN_OCR = File.expand_path("../../bin/ocr", __dir__)
  BIN_BENCHMARK = File.expand_path("../../bin/ocr_benchmark", __dir__)
  CASES_PATH = File.expand_path("../fixtures/ocr/cases.json", __dir__)
  FIXTURE_IMAGE = File.expand_path("../fixtures/ocr_events.png", __dir__)

  def setup
    @dir = Dir.mktmpdir("ocr_cli_test_")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def test_source_benchmark_dry_run_plans_only_reader
    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", BIN_BENCHMARK,
      "--workflow", "source", "--dry-run", FIXTURE_IMAGE)

    assert status.success?, stderr
    plan = JSON.parse(stdout)
    assert_equal "source", plan.fetch("workflow")
    assert_equal %w[reader reader_effort], plan.fetch("models").keys.sort
  end

  def test_source_rejects_selected_only_options
    _stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", BIN_OCR,
      "--workflow", "source", "--router-model", "gpt-6-luna", FIXTURE_IMAGE)
    refute status.success?
    assert_includes stderr, "only supported with --workflow selected"
  end

  def test_source_cli_reads_one_original_image
    preload = write_offline_stub_preload(mode: :selected_direct)
    artifacts = File.join(@dir, "artifacts")
    stdout, stderr, status = Open3.capture3({"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_OCR, "--workflow", "source", "--json",
      "--artifacts-dir", artifacts, FIXTURE_IMAGE)
    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal "whole_source", result.fetch("route")
    assert_equal 1, result.fetch("events").length
    assert_equal ["reader"], result.fetch("calls").map { |call| call.fetch("stage") }
    assert_equal File.binread(FIXTURE_IMAGE), File.binread(File.join(artifacts, "source.png"))
  end

  def test_source_benchmark_continues_after_pdf_error
    preload = write_offline_stub_preload(mode: :selected_direct)
    pdf = File.join(@dir, "sample.pdf")
    File.write(pdf, "%PDF-1.4")
    output = File.join(@dir, "source-results.json")
    stdout, stderr, status = Open3.capture3({"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK, "--workflow", "source",
      "--output", output, FIXTURE_IMAGE, pdf, FIXTURE_IMAGE)
    assert_equal 1, status.exitstatus, "#{stderr}\n#{stdout}"
    runs = JSON.parse(File.read(output)).fetch("runs")
    assert_equal 3, runs.length
    assert_equal "init", runs[1].dig("error", "stage")
    assert_empty runs[1].fetch("calls")
    assert_equal ["reader"], runs[2].fetch("calls").map { |call| call.fetch("stage") }
  end

  def test_bin_ocr_selected_workflow_rejects_pdf_pointing_to_legacy_path
    pdf_path = File.join(@dir, "sample.pdf")
    File.write(pdf_path, "%PDF-1.4")

    stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", BIN_OCR, "--workflow", "selected", pdf_path)

    refute status.success?
    combined = stdout + stderr
    assert_includes combined, "PDF"
    assert_includes combined, "EventOcrService"
  end

  def test_bin_ocr_selected_workflow_outputs_detailed_json_with_stubbed_network
    preload = write_offline_stub_preload(mode: :selected_direct)
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_OCR,
      "--workflow", "selected", "--text", "Entrada gratuita.", "--fallback-year", "2027", "--json", FIXTURE_IMAGE
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    parsed = JSON.parse(stdout)
    assert_equal "direct_ocr", parsed["route"]
    assert_equal 2027, parsed["fallback_year"]
    assert_equal 1, parsed["events"].length
    assert_equal [], parsed["review_items"]
    assert parsed.dig("hashes", "source_sha256")
    assert parsed.dig("timing", "total_seconds")
  end

  def test_bin_ocr_legacy_gemini_override_does_not_require_openai_key
    preload = write_offline_stub_preload(mode: :legacy_gemini)
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => "offline-gemini-key", "OCR_MODEL" => "gemini-flash-latest"},
      "bundle", "exec", "ruby", "-r", preload, BIN_OCR, FIXTURE_IMAGE
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    assert_includes stdout, "Concerto Gemini"
  end

  def test_legacy_json_remains_parseable_after_validation_recovery
    preload = write_offline_stub_preload(mode: :legacy_gemini_recovery)
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => "offline-gemini-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_OCR,
      "--model", "gemini-flash-latest", "--json", FIXTURE_IMAGE
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    assert_equal "Concerto Gemini", JSON.parse(stdout).first.fetch("name")
    assert_includes stderr, "Retrying due to validation error"
    assert_includes stderr, "Retry attempt"
  end

  def test_selected_benchmark_preserves_results_and_continues_after_unsupported_pdf
    pdf_path = File.join(@dir, "sample.pdf")
    File.write(pdf_path, "%PDF-1.4")
    preload = write_offline_stub_preload(mode: :selected_direct)
    output_path = File.join(@dir, "results.json")
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--workflow", "selected", "--output", output_path, FIXTURE_IMAGE, pdf_path, FIXTURE_IMAGE
    )

    assert_equal 1, status.exitstatus
    assert File.file?(output_path), "stderr: #{stderr}\nstdout: #{stdout}"
    runs = JSON.parse(File.read(output_path)).fetch("runs")
    assert_equal 3, runs.length
    [runs.first, runs.last].each do |run|
      assert_equal 1, run.fetch("events").length
      refute run.key?("error")
    end
    failed = runs[1]
    assert_equal "ArgumentError", failed.dig("error", "type")
    assert_includes failed.dig("error", "message"), "does not support PDF"
    assert_equal "init", failed.dig("error", "stage")
    assert_empty failed.fetch("calls")
    assert_empty failed.dig("timing", "stages")
  end

  def test_benchmark_keeps_distinct_artifacts_for_inputs_with_the_same_basename
    images = %w[first second].map do |folder|
      directory = File.join(@dir, folder)
      FileUtils.mkdir_p(directory)
      image = File.join(directory, "poster.png")
      FileUtils.cp(FIXTURE_IMAGE, image)
      image
    end
    _stdout, stderr, status = Open3.capture3("convert", images.last, "-negate", images.last)
    assert status.success?, stderr
    preload = write_offline_stub_preload(mode: :selected_direct)
    output_path = File.join(@dir, "artifacts_results.json")
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--workflow", "selected", "--artifacts-dir", File.join(@dir, "artifacts"),
      "--output", output_path, *images, images.first
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    runs = JSON.parse(File.read(output_path)).fetch("runs")
    reader_inputs = runs.map { |run| run.dig("hashes", "reader_inputs", 0) }
    assert_equal 3, reader_inputs.map { |input| input.fetch("path") }.uniq.length
    assert_equal 2, reader_inputs.map { |input| input.fetch("sha256") }.uniq.length
    reader_inputs.each do |input|
      assert_equal input.fetch("sha256"), Digest::SHA256.file(input.fetch("path")).hexdigest
    end
  end

  def test_benchmark_dry_run_verifies_fixtures_offline_without_api_calls_and_creates_nested_output_dir
    nested_plan = File.join(@dir, "nested", "sub", "plan.json")
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_BENCHMARK,
      "--workflow", "selected", "--cases", CASES_PATH, "--repeat", "3",
      "--image-detail", "original", "--output", nested_plan, "--dry-run"
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    assert File.file?(nested_plan)
    parsed = JSON.parse(File.read(nested_plan))
    assert_equal true, parsed["dry_run"]
    assert_equal "selected", parsed["workflow"]
    assert_equal "original", parsed["image_detail"]
    assert_equal false, parsed["upscale"]
    assert_equal 3, parsed["repeat"]
    assert_equal 10, parsed["cases"].length
    assert_equal 30, parsed["planned_runs"]
  end

  def test_no_upscale_option_dry_run_selected_run_and_legacy_rejection
    _stdout, stderr_ocr, status_ocr = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_OCR, "--no-upscale", FIXTURE_IMAGE
    )
    refute status_ocr.success?
    assert_includes stderr_ocr, "selected"

    _stdout, stderr_bench, status_bench = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_BENCHMARK, "--no-upscale", FIXTURE_IMAGE
    )
    refute status_bench.success?
    assert_includes stderr_bench, "selected"

    plan_path = File.join(@dir, "plan_no_upscale.json")
    stdout_plan, stderr_plan, status_plan = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_BENCHMARK,
      "--workflow", "selected", "--cases", CASES_PATH, "--no-upscale", "--image-detail", "original", "--output", plan_path, "--dry-run"
    )
    assert status_plan.success?, "stderr: #{stderr_plan}\nstdout: #{stdout_plan}"
    plan = JSON.parse(File.read(plan_path))
    assert_equal false, plan["upscale"]
    assert_equal "original", plan["image_detail"]

    preload = write_offline_stub_preload(mode: :selected_direct)
    output_path = File.join(@dir, "no_upscale_results.json")
    artifacts_dir = File.join(@dir, "no_upscale_artifacts")
    stdout_run, stderr_run, status_run = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--workflow", "selected", "--cases", CASES_PATH, "--case", "reading_club_control",
      "--no-upscale", "--image-detail", "original", "--artifacts-dir", artifacts_dir, "--output", output_path
    )
    assert status_run.success?, "stderr: #{stderr_run}\nstdout: #{stdout_run}"
    report = JSON.parse(File.read(output_path))
    assert_equal false, report["upscale"]
    assert_equal "original", report["image_detail"]
    run = report["runs"].first
    assert_equal false, run["upscale"]
    assert_equal "original", run["image_detail"]

    stdout_cli, stderr_cli, status_cli = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_OCR,
      "--workflow", "selected", "--no-upscale", "--image-detail", "original", "--json", FIXTURE_IMAGE
    )
    assert status_cli.success?, "stderr: #{stderr_cli}\nstdout: #{stdout_cli}"
    cli_json = JSON.parse(stdout_cli)
    assert_equal false, cli_json["upscale"]
    assert_equal "original", cli_json["image_detail"]
  end

  def test_benchmark_score_only_scores_saved_runs_offline_and_creates_nested_output_dir
    saved_path = File.join(@dir, "saved.json")
    File.write(saved_path, JSON.generate([
      {
        case_id: "reading_club_control",
        run: 1,
        fallback_year: 2026,
        route: "direct_ocr",
        events: [
          {
            name: "Clube de Leitura — Livros que inspiram",
            start_date: "14/11/2026",
            start_time: "18:00",
            location: "Biblioteca Municipal",
            price_type: "Desconhecido"
          }
        ],
        review_items: [],
        timing: {total_seconds: 1.5, stages: {router: 0.4, reader: 1.1}},
        usage_totals: {input_tokens: 400, output_tokens: 80},
        cost_totals: {known_cost_usd: 0.0008, cold_cost_usd: 0.0008}
      }
    ]))

    score_out = File.join(@dir, "nested_score", "deeper", "score.json")
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_BENCHMARK,
      "--score-only", saved_path, "--cases", CASES_PATH, "--output", score_out
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    assert File.file?(score_out)
    report = JSON.parse(File.read(score_out))
    assert_equal 1, report.dig("aggregates", "matched_occurrences")
    assert_equal 1, report.dig("aggregates", "complete_checked_events")
    assert_equal 0, report.dig("aggregates", "unmatched_extra_count")
  end

  def test_image_detail_rejects_legacy_mode_and_invalid_values_without_http
    _stdout, stderr_ocr, status_ocr = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_OCR, "--image-detail", "original", FIXTURE_IMAGE
    )
    refute status_ocr.success?
    assert_includes stderr_ocr, "selected"

    _stdout, stderr_bench, status_bench = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_BENCHMARK, "--image-detail", "original", FIXTURE_IMAGE
    )
    refute status_bench.success?
    assert_includes stderr_bench, "selected"

    _stdout, _stderr_invalid, status_invalid = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_BENCHMARK, "--workflow", "selected", "--image-detail", "bogus", "--cases", CASES_PATH, "--dry-run"
    )
    refute status_invalid.success?
  end

  def test_benchmark_selected_workflow_runs_repeats_persists_artifacts_and_scores_cases
    preload = write_offline_stub_preload(mode: :selected_direct)
    output_path = File.join(@dir, "results.json")
    artifacts_dir = File.join(@dir, "artifacts")

    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--workflow", "selected", "--cases", CASES_PATH, "--case", "reading_club_control",
      "--repeat", "2", "--image-detail", "original", "--artifacts-dir", artifacts_dir, "--output", output_path
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    report = JSON.parse(File.read(output_path))
    assert_equal "selected", report["workflow"]
    assert_equal "original", report["image_detail"]
    assert_equal 2, report["runs"].length
    assert_equal 2, report.dig("score", "aggregates", "matched_occurrences")
    report["runs"].each do |run|
      assert_equal "original", run["image_detail"]
      reader_inputs = run.dig("hashes", "reader_inputs")
      assert_equal 1, reader_inputs.length
      assert File.exist?(reader_inputs.first["path"])
    end
  end

  def test_legacy_benchmark_propagates_explicit_year_to_event_ocr_service_instructions
    preload = write_offline_stub_preload(mode: :legacy_gemini_capture)
    output_path = File.join(@dir, "legacy_2027.json")
    captured_req = File.join(@dir, "captured_gemini_request.json")

    stdout, stderr, status = Open3.capture3(
      {
        "OPENAI_API_KEY" => nil,
        "GEMINI_API_KEY" => "offline-gemini-key",
        "OCR_CAPTURED_REQ_PATH" => captured_req
      },
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--model", "gemini-flash-latest", "--fallback-year", "2027", "--output", output_path, FIXTURE_IMAGE
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    report = JSON.parse(File.read(output_path))
    assert_equal 2027, report.first["fallback_year"]
    req_body = JSON.parse(File.read(captured_req))
    system_text = req_body.dig("systemInstruction", "parts", 0, "text")
    assert_includes system_text, "Fallback year for sources without an explicit year: 2027."
  end

  def test_legacy_benchmark_case_report_retains_recorded_time_and_tokens
    preload = write_offline_stub_preload(mode: :legacy_gemini)
    output_path = File.join(@dir, "legacy_cases.json")
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => "offline-gemini-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--workflow", "legacy", "--model", "gemini-flash-latest",
      "--cases", CASES_PATH, "--case", "reading_club_control", "--output", output_path
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    report = JSON.parse(File.read(output_path))
    run = report.fetch("runs").first
    totals = report.dig("score", "aggregates")
    assert_operator run.fetch("seconds"), :>, 0
    assert_equal run.fetch("seconds"), totals.fetch("total_seconds")
    assert_equal 100, totals.dig("usage_totals", "input_tokens")
    assert_equal 40, totals.dig("usage_totals", "output_tokens")
  end

  private

  def write_offline_stub_preload(mode:)
    path = File.join(@dir, "preload_#{mode}.rb")
    content = <<~RUBY
      require "webmock"
      require "json"
      WebMock.enable!
      WebMock.disable_net_connect!(allow_localhost: true)

      if "#{mode}" == "selected_direct"
        WebMock.stub_request(:post, "https://api.openai.com/v1/decisions").to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: JSON.generate(
            model: "gpt-6-luna",
            answers: [
              {name: "kind", choice: "other", probabilities: [{value: "other", probability: 1.0}], confidence: 1.0},
              {name: "month", choice: "uncertain", probabilities: [{value: "uncertain", probability: 1.0}], confidence: 1.0}
            ],
            usage: {input_tokens: 100, output_tokens: 10}
          )
        )
        candidate = {
          name: "Clube de Leitura — Livros que inspiram",
          start_date: "14/11/2026",
          start_time: "18:00",
          end_date: nil,
          end_time: nil,
          location: "Biblioteca Municipal",
          description: "Clube de leitura mensal na Biblioteca Municipal.",
          category: "Comunidade & Cultura",
          organizer: "Câmara Municipal do Porto Santo",
          contact_email: nil,
          contact_tel: nil,
          price_type: "Desconhecido",
          event_link1: nil,
          event_link2: nil,
          event_link3: nil,
          event_link4: nil,
          location_evidence: "Biblioteca Municipal",
          location_source: "main_text",
          date_source: "main_text",
          time_source: "main_text",
          price_source: "none",
          review_reason: "none",
          review_detail: nil,
        }
        WebMock.stub_request(:post, "https://api.openai.com/v1/responses").to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: JSON.generate(
            id: "resp_cli",
            object: "response",
            status: "completed",
            model: "gpt-6.1-terra",
            output: [{id: "msg_cli", type: "message", role: "assistant", content: [{type: "output_text", text: JSON.generate(panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [candidate]}])}]}],
            usage: {input_tokens: 200, output_tokens: 80}
          )
        )
      elsif %w[legacy_gemini legacy_gemini_capture legacy_gemini_recovery].include?("#{mode}")
        event = {
          name: "Concerto Gemini",
          start_date: "15/10/2026",
          location: "Centro Cultural",
          description: "Concerto de música no centro cultural.",
          category: "Música",
          organizer: "Associação Cultural"
        }
        attempts = 0
        WebMock.stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent").with do |req|
          File.write(ENV["OCR_CAPTURED_REQ_PATH"], req.body) if ENV["OCR_CAPTURED_REQ_PATH"]
          true
        end.to_return do
          attempts += 1
          response_event = if "#{mode}" == "legacy_gemini_recovery" && attempts == 1
            event.merge(start_date: "invalid")
          else
            event
          end
          {
            status: 200,
            headers: {"Content-Type" => "application/json"},
            body: JSON.generate(
              candidates: [{content: {role: "model", parts: [{text: JSON.generate(events: [response_event])}]}, finishReason: "STOP"}],
              usageMetadata: {promptTokenCount: 100, candidatesTokenCount: 40},
              modelVersion: "gemini-flash-latest"
            )
          }
        end
      end
    RUBY
    File.write(path, content)
    path
  end
end
