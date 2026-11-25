require "bundler/setup"
require "minitest/autorun"
require "json"
require "digest"
require "open3"
require "mini_magick"
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

  def test_benchmark_uses_code_defaults_and_accepts_explicit_overrides
    env = {"OCR_MODEL" => "gpt-6-luna", "OCR_REASONING_EFFORT" => "high"}
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", BIN_BENCHMARK, "--dry-run", FIXTURE_IMAGE)
    assert status.success?, stderr
    plan = JSON.parse(stdout)
    assert_equal({"reader" => "gpt-6.1-terra", "reader_effort" => "medium"}, plan.fetch("models"))

    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", BIN_BENCHMARK,
      "--dry-run", "--model", "gpt-6-luna", "--effort", "low", FIXTURE_IMAGE)
    assert status.success?, stderr
    assert_equal({"reader" => "gpt-6-luna", "reader_effort" => "low"}, JSON.parse(stdout).fetch("models"))
  end

  def test_workflow_option_has_been_removed_from_both_cli_entry_points
    [BIN_OCR, BIN_BENCHMARK].each do |command|
      _stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", command, "--workflow", "source", "--help")

      refute status.success?, command
      assert_includes stderr, "invalid option: --workflow"
    end
  end

  def test_cli_reads_pdf_through_source_with_explicit_model_and_effort
    pdf = File.join(@dir, "programme.pdf")
    MiniMagick.convert do |convert|
      convert << FIXTURE_IMAGE
      convert << pdf
    end
    preload = write_offline_stub_preload
    captured = File.join(@dir, "request.json")
    env = {"OPENAI_API_KEY" => "offline-test-key", "OCR_CAPTURED_REQ_PATH" => captured}
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-r", preload,
      BIN_OCR, "--model", "gpt-6-luna", "--effort", "low", "--json", pdf)

    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "whole_source", result.fetch("route")
    assert_equal ["Clube de Leitura — Livros que inspiram"], result.fetch("events").map { |event| event.fetch("name") }
    request = JSON.parse(File.read(captured))
    assert_equal "gpt-6-luna", request.fetch("model")
    assert_equal "low", request.dig("reasoning", "effort")
  end

  def test_cli_uses_gemini_without_an_openai_key
    preload = write_offline_stub_preload
    captured = File.join(@dir, "request.json")
    env = {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => "offline-gemini-key", "OCR_CAPTURED_REQ_PATH" => captured}
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "ruby", "-r", preload,
      BIN_OCR, "--model", "gemini-flash-latest", "--fallback-year", "2028", FIXTURE_IMAGE)

    assert status.success?, stderr
    assert_includes stdout, "Clube de Leitura — Livros que inspiram"
    request = JSON.parse(File.read(captured))
    assert_includes request.dig("systemInstruction", "parts", 0, "text"),
      "The fallback year is 2028 only if the source omitted a year."
  end

  def test_benchmark_scores_pdf_case
    pdf = File.join(@dir, "programme.pdf")
    MiniMagick.convert do |convert|
      convert << FIXTURE_IMAGE
      convert << pdf
    end
    target = {id: "programme", image: "programme.pdf", sha256: Digest::SHA256.file(pdf).hexdigest,
              expected_events: [{name_contains: ["Clube de Leitura"], start_date: "14/11/2026"}]}
    cases_path = File.join(@dir, "cases.json")
    File.write(cases_path, JSON.generate(cases: [target]))
    output = File.join(@dir, "benchmark.json")
    artifacts = File.join(@dir, "artifacts")
    preload = write_offline_stub_preload
    stdout, stderr, status = Open3.capture3({"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--cases", cases_path, "--output", output, "--artifacts-dir", artifacts, "--fallback-year", "2028")

    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(File.read(output))
    refute result.key?("image_detail")
    run, = result.fetch("runs")
    refute run.key?("image_detail")
    assert_equal ["programme"], result.dig("score", "runs").map { |run| run.fetch("case_id") }
    assert_equal 1, result.dig("score", "aggregates", "matched_occurrences")
    request = JSON.parse(File.read(File.join(run.dig("diagnostics", "artifact_dir"), "reader_request.json")))
    assert_includes request.fetch("instructions"), "The fallback year is 2028 only if the source omitted a year."
    assert_includes request.fetch("prompt"), "Read every page of the PDF as part of the same panel."
  end

  def test_source_cli_reads_one_original_image
    preload = write_offline_stub_preload
    artifacts = File.join(@dir, "artifacts")
    captured = File.join(@dir, "request.json")
    env = {"OPENAI_API_KEY" => "offline-test-key", "OCR_MODEL" => "gpt-6-luna",
           "OCR_REASONING_EFFORT" => "high", "OCR_CAPTURED_REQ_PATH" => captured}
    stdout, stderr, status = Open3.capture3(env,
      "bundle", "exec", "ruby", "-r", preload, BIN_OCR, "--json",
      "--artifacts-dir", artifacts, FIXTURE_IMAGE)
    assert status.success?, "#{stderr}\n#{stdout}"
    result = JSON.parse(stdout)
    assert_equal "whole_source", result.fetch("route")
    assert_equal 1, result.fetch("events").length
    assert_equal ["reader"], result.fetch("calls").map { |call| call.fetch("stage") }
    assert_equal File.binread(FIXTURE_IMAGE), File.binread(File.join(artifacts, "source.png"))
    assert_equal result, JSON.parse(File.read(File.join(artifacts, "result.json")))
    request = JSON.parse(File.read(captured))
    assert_equal "gpt-6.1-terra", request.fetch("model")
    assert_equal "medium", request.dig("reasoning", "effort")
  end

  def test_source_benchmark_continues_after_pdf_error
    preload = write_offline_stub_preload
    pdf = File.join(@dir, "sample.pdf")
    File.write(pdf, "Not a PDF")
    output = File.join(@dir, "source-results.json")
    stdout, stderr, status = Open3.capture3({"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--output", output, FIXTURE_IMAGE, pdf, FIXTURE_IMAGE)
    assert_equal 1, status.exitstatus, "#{stderr}\n#{stdout}"
    runs = JSON.parse(File.read(output)).fetch("runs")
    assert_equal 3, runs.length
    assert_equal "init", runs[1].dig("error", "stage")
    assert_empty runs[1].fetch("calls")
    assert_equal ["reader"], runs[2].fetch("calls").map { |call| call.fetch("stage") }
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
    preload = write_offline_stub_preload
    output_path = File.join(@dir, "artifacts_results.json")
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--artifacts-dir", File.join(@dir, "artifacts"),
      "--output", output_path, *images, images.first
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    runs = JSON.parse(File.read(output_path)).fetch("runs")
    artifacts = runs.map { |run| File.join(run.dig("diagnostics", "artifact_dir"), "source.png") }
    assert_equal 3, artifacts.uniq.length
    assert_equal 2, runs.map { |run| run.dig("hashes", "source_sha256") }.uniq.length
    runs.zip(artifacts).each do |run, artifact|
      assert_equal run.dig("hashes", "source_sha256"), Digest::SHA256.file(artifact).hexdigest
    end
  end

  def test_benchmark_dry_run_verifies_fixtures_offline_without_api_calls_and_creates_nested_output_dir
    nested_plan = File.join(@dir, "nested", "sub", "plan.json")
    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => nil, "GEMINI_API_KEY" => nil},
      "bundle", "exec", "ruby", BIN_BENCHMARK,
      "--cases", CASES_PATH, "--repeat", "3", "--output", nested_plan, "--dry-run"
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    assert File.file?(nested_plan)
    parsed = JSON.parse(File.read(nested_plan))
    assert_equal true, parsed["dry_run"]
    refute parsed.key?("workflow")
    assert_equal 3, parsed["repeat"]
    assert_equal 10, parsed["cases"].length
    assert_equal 30, parsed["planned_runs"]
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

  def test_benchmark_runs_repeats_persists_artifacts_and_scores_cases
    preload = write_offline_stub_preload
    output_path = File.join(@dir, "results.json")
    artifacts_dir = File.join(@dir, "artifacts")

    stdout, stderr, status = Open3.capture3(
      {"OPENAI_API_KEY" => "offline-test-key"},
      "bundle", "exec", "ruby", "-r", preload, BIN_BENCHMARK,
      "--cases", CASES_PATH, "--case", "reading_club_control",
      "--repeat", "2", "--artifacts-dir", artifacts_dir, "--output", output_path
    )

    assert status.success?, "stderr: #{stderr}\nstdout: #{stdout}"
    report = JSON.parse(File.read(output_path))
    refute report.key?("workflow")
    assert_equal 2, report["runs"].length
    assert_equal 2, report.dig("score", "aggregates", "matched_occurrences")
    report["runs"].each do |run|
      assert_equal "original", run["image_detail"]
      assert_equal ["reader"], run.fetch("calls").map { |call| call.fetch("stage") }
      assert File.file?(File.join(run.dig("diagnostics", "artifact_dir"), "source.jpg"))
    end
  end

  private

  def write_offline_stub_preload
    path = File.join(@dir, "preload.rb")
    content = <<~RUBY
      require "webmock"
      require "json"
      WebMock.enable!
      WebMock.disable_net_connect!(allow_localhost: true)

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
      capture_request = ->(req) do
        File.write(ENV["OCR_CAPTURED_REQ_PATH"], req.body) if ENV["OCR_CAPTURED_REQ_PATH"]
        true
      end
      result = JSON.generate(panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [candidate]}])
      headers = {"Content-Type" => "application/json"}
      WebMock.stub_request(:post, "https://api.openai.com/v1/responses").with(&capture_request).to_return(
        status: 200,
        headers: headers,
        body: JSON.generate(
          id: "resp_cli",
          object: "response",
          status: "completed",
          model: "gpt-6.1-terra",
          output: [{id: "msg_cli", type: "message", role: "assistant", content: [{type: "output_text", text: result}]}],
          usage: {input_tokens: 200, output_tokens: 80}
        )
      )
      WebMock.stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent")
        .with(&capture_request).to_return(
          status: 200,
          headers: headers,
          body: JSON.generate(candidates: [{content: {role: "model", parts: [{text: result}]}, finishReason: "STOP"}])
        )
    RUBY
    File.write(path, content)
    path
  end
end
