require "bundler/setup"
require "minitest/autorun"
require "base64"
require "digest"
require "json"
require "tmpdir"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/ocr/workflow"
require_relative "../../lib/server/ocr/benchmark_scorer"

class OcrWorkflowTest < Minitest::Test
  OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
  OPENAI_DECISIONS_URL = "https://api.openai.com/v1/decisions"
  GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"

  def setup
    TestHelper.setup_network_blocking
    @original_openai_key = RubyLLM.config.openai_api_key
    @original_gemini_key = RubyLLM.config.gemini_api_key
    @original_router_key = RubyLLM.config.openrouter_api_key
    RubyLLM.configure do |config|
      config.openai_api_key = "offline-openai-key"
      config.gemini_api_key = "offline-gemini-key"
    end

    @dir = Dir.mktmpdir("ocr_workflow_test_")
    @image_path = File.join(@dir, "poster.png")
    MiniMagick.convert do |convert|
      convert.size "400x400"
      convert << "xc:white"
      convert << @image_path
    end

    @decision_requests = []
    @response_requests = []
    @gemini_requests = []
  end

  def teardown
    RubyLLM.configure do |config|
      config.openai_api_key = @original_openai_key
      config.gemini_api_key = @original_gemini_key
      config.openrouter_api_key = @original_router_key
    end
    TestHelper.reset_network_mocks
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def test_input_rejection_has_fresh_evidence_even_when_reusing_a_workflow
    stub_decisions([decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})])
    stub_responses([openai_response(model: "gpt-6.1-terra", payload: {
      panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate]}]
    })])
    workflow = Ocr::Workflow.new
    workflow.analyze(@image_path)
    refute_empty workflow.run_evidence[:calls]

    pdf_path = File.join(@dir, "sample.pdf")
    File.write(pdf_path, "%PDF-1.4")
    [pdf_path, File.join(@dir, "missing.png")].each do |path|
      assert_raises(ArgumentError) { workflow.analyze(path) }
      evidence = workflow.run_evidence
      assert_equal "init", evidence[:stage]
      assert_empty evidence[:calls]
      assert_empty evidence.dig(:timing, :stages)
      assert_equal 0, evidence.dig(:usage_totals, :input_tokens)
      refute_equal Digest::SHA256.file(@image_path).hexdigest, evidence.dig(:hashes, :source_sha256)
    end
  end

  def test_direct_route_propagates_additional_text_and_clock_year_without_leaking_temp_dirs
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_responses([
      openai_response(
        model: "gpt-6.1-terra",
        payload: {
          panels: [
            {
              panel_id: 1,
              panel_review_reason: "none",
              panel_review_detail: nil,
              candidates: [
                ready_candidate(
                  name: "Formação de Palmito",
                  organizer: nil,
                  start_date: "19/10/2027",
                  end_date: "23/10/2027",
                  start_time: "14:00",
                  end_time: "18:00",
                  location: "Casa do Povo de N. S. da Piedade",
                  location_evidence: "Casa do Povo de N. S. da Piedade",
                  contact_tel: "924366168"
                )
              ]
            }
          ]
        }
      )
    ])

    before_tmps = Dir.glob("/tmp/ocr_workflow_*")
    result = Ocr::Workflow.call(
      @image_path,
      additional_text: "Inscrições abertas até sexta.",
      fallback_year: 2027
    )

    assert_equal before_tmps, Dir.glob("/tmp/ocr_workflow_*")
    assert_equal "direct_ocr", result[:route]
    assert_equal 2027, result[:fallback_year]
    assert_equal 1, result[:events].length
    assert_empty result[:review_items]
    refute result[:events].first.key?(:organizer)
    assert_equal "19/10/2027", result[:events].first[:start_date]
    assert_equal "Casa do Povo de Nossa Senhora da Piedade", result[:events].first[:location]

    reader_req = @response_requests.first
    assert_equal "gpt-6.1-terra", reader_req["model"]
    assert_equal "low", reader_req.dig("reasoning", "effort")
    candidate_properties = reader_req.fetch("text").fetch("format").fetch("schema")
      .dig("properties", "panels", "items", "properties", "candidates", "items", "properties")
    refute candidate_properties.key?("status")
    refute candidate_properties.key?("supporting_quote")
    assert_equal "original", result[:image_detail]
    assert_equal false, result[:upscale]
    reader_req.dig("input", 0, "content").select { |part| part["type"] == "input_image" }.each do |part|
      assert_equal "original", part["detail"]
    end
    user_text = reader_req.dig("input", 0, "content").find { |p| p["type"] == "input_text" }.fetch("text")
    assert_includes user_text, "Inscrições abertas até sexta."
    assert_includes user_text, "\"fallback_year\":2027"
    assert_includes reader_req["instructions"], "Fallback year for sources without an explicit year: 2027."
    assert_includes reader_req["instructions"], "Always preserve a year explicitly printed"

    # Default reader input retains native pixels and requests original detail
    image_url = reader_req.dig("input", 0, "content").find { |p| p["type"] == "input_image" }.fetch("image_url")
    pixels = Base64.decode64(image_url.split(",", 2).last)
    assert_equal [400, 400], MiniMagick::Image.read(pixels).dimensions

    # Check hashes & telemetry
    assert_equal Digest::SHA256.file(@image_path).hexdigest, result.dig(:hashes, :source_sha256)
    assert_equal 1, result.dig(:hashes, :reader_inputs).length
    assert_equal 2, result[:calls].length
    assert_operator result.dig(:cost_totals, :total), :>, 0
    assert_in_delta result[:calls].sum { |call| call.dig(:cost, :total) }, result.dig(:cost_totals, :total)
    assert_operator result.dig(:timing, :total_seconds), :>=, 0.0
    assert_operator result.dig(:usage_totals, :input_tokens), :>, 0
  end

  def test_direct_route_preserves_printed_year_even_when_fallback_year_differs_and_handles_missing_venue_review
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_responses([
      openai_response(
        model: "gpt-6.1-terra",
        payload: {
          panels: [
            {
              panel_id: 1,
              panel_review_reason: "none",
              panel_review_detail: nil,
              candidates: [
                ready_candidate(
                  name: "Campanha de Vacinação Antirrábica",
                  start_date: "14/07/2026",
                  start_time: "09:30",
                  end_time: "12:00",
                  location: nil,
                  location_evidence: "Canil & Gatil",
                  location_source: "booking_only",
                  price_type: "Pago",
                  price_source: "service_fee_only",
                  contact_tel: "291982198",
                  review_reason: "missing_location",
                  review_detail: "Canil & Gatil surge apenas abaixo do contacto de marcação."
                )
              ]
            }
          ]
        }
      )
    ])

    result = Ocr::Workflow.call(@image_path, fallback_year: 2027)

    assert_equal "direct_ocr", result[:route]
    assert_empty result[:events]
    assert_equal 1, result[:review_items].length
    review = result[:review_items].first
    assert_equal "missing_location", review[:reason]
    assert_equal "14/07/2026", review.dig(:candidate, :start_date)
    assert_equal "Desconhecido", review.dig(:candidate, :price_type)
    assert_equal "291982198", review.dig(:candidate, :contact_tel)
    assert_nil review.dig(:candidate, :location)
    assert_equal false, review.dig(:trace, :verified)
  end

  def test_monthly_route_runs_geometry_crops_banner_judges_old_inset_rule_and_persists_artifacts
    artifact_dir = File.join(@dir, "artifacts")
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      # Panel 1 miniature: preserve with allowed_fields location+time
      decision_response(model: "gpt-6-luna", answers: {action: "preserve", relationship: "shared_banner", main_text_overlap: "clear_of_main_text", location: "allow", time: "allow", date: "deny"}),
      # Panel 2 miniature: preserve with empty allowed_fields (must NOT be masked!)
      decision_response(model: "gpt-6-luna", answers: {action: "preserve", relationship: "shared_banner", main_text_overlap: "clear_of_main_text", location: "deny", time: "deny", date: "deny"}),
      # Panel 3 miniature: review on bounded old secondary inset (Padel valid main text vs Exhibition missing start day)
      decision_response(model: "gpt-6-luna", answers: {action: "review", relationship: "old_secondary_inset", main_text_overlap: "clear_of_main_text", location: "deny", time: "deny", date: "deny"})
    ])

    geometry_payload = {
      heading_text: "Agenda Cultural Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Mostra e Dia dos Avós",
          box: {left: 0, top: 0, right: 500, bottom: 500},
          miniatures: [{left: 50, top: 50, right: 150, bottom: 150}],
          cleanup: "keep_colour"
        },
        {
          id: 2,
          title_hint: "Workshops",
          box: {left: 500, top: 0, right: 1000, bottom: 500},
          miniatures: [{left: 550, top: 50, right: 650, bottom: 150}],
          cleanup: "whiten_light_background"
        },
        {
          id: 3,
          title_hint: "Padel e Exposição",
          box: {left: 0, top: 500, right: 1000, bottom: 1000},
          miniatures: [{left: 100, top: 600, right: 300, bottom: 800}],
          cleanup: "keep_colour"
        }
      ]
    }

    reader_payload = {
      panels: [
        {
          panel_id: 1,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [
            ready_candidate(
              name: "VII Mostra do Pão",
              start_date: "16/10/2026",
              end_date: "18/10/2026",
              location: "Praça do Município",
              location_evidence: "Praça do Município",
              location_source: "banner"
            ),
            ready_candidate(
              name: "Dia dos Avós",
              start_date: "26/10/2026",
              location: "Biblioteca Municipal",
              location_evidence: "Biblioteca Municipal",
              location_source: "organizer_only",
              review_reason: "missing_location"
            )
          ]
        },
        {
          panel_id: 2,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [
            ready_candidate(
              name: "Oficina de Croché",
              start_date: "19/10/2026",
              location: "Casa do Povo de N. S. da Piedade",
              location_evidence: "Casa do Povo"
            )
          ]
        },
        {
          panel_id: 3,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [
            ready_candidate(
              name: "Circuito Padel Dourado",
              start_date: "27/10/2026",
              end_date: "01/11/2026",
              location: "Hotel Vila Baleira",
              location_evidence: "Hotel Vila Baleira",
              date_source: "main_text",
              location_source: "main_text"
            ),
            ready_candidate(
              name: "Exposição Imagens e Memória",
              start_date: nil,
              end_date: "31/12/2026",
              location: "Átrio da Câmara Municipal",
              location_evidence: "Átrio da Câmara Municipal",
              review_reason: "missing_start_date",
              review_detail: "Apenas indica até 31 dez no texto principal."
            )
          ]
        }
      ]
    }

    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload)
    ])

    result = Ocr::Workflow.call(
      @image_path,
      additional_text: "Informação complementar do operador.",
      artifact_dir: artifact_dir
    )

    assert_equal "monthly_agenda", result[:route]
    assert_equal 3, result[:events].length
    assert_equal ["VII Mostra do Pão", "Oficina de Croché", "Circuito Padel Dourado"], result[:events].map { |e| e[:name] }
    assert_equal "01/11/2026", result[:events].last[:end_date]

    assert_equal 2, result[:review_items].length
    assert_equal ["Dia dos Avós", "Exposição Imagens e Memória"], result[:review_items].map { |r| r.dig(:candidate, :name) }
    assert_equal "31/12/2026", result[:review_items].last.dig(:candidate, :end_date)
    assert_equal "missing_start_date", result[:review_items].last[:reason]

    # Verify Judge policies: panel 2 preserve+empty was NOT masked; panel 3 review became safe main-only crop retaining original review
    policies = result.dig(:diagnostics, :banner_policies)
    assert_equal "preserve", policies.find { |p| p[:panel_id] == 2 }[:action]
    assert_equal [], policies.find { |p| p[:panel_id] == 2 }[:masked_boxes]
    panel3_policy = policies.find { |p| p[:panel_id] == 3 }
    assert_equal "mask_unverified_inset", panel3_policy[:action]
    assert_equal "review", panel3_policy[:original_judge_action]
    assert_equal 1, panel3_policy[:masked_boxes].length

    # Verify geometry used gpt-6-luna medium and reader received 3 attachments + additional_text
    geometry_req = @response_requests[0]
    assert_equal "gpt-6-luna", geometry_req["model"]
    assert_equal "medium", geometry_req.dig("reasoning", "effort")
    reader_req = @response_requests[1]
    assert_equal "gpt-6.1-terra", reader_req["model"]
    assert_equal "low", reader_req.dig("reasoning", "effort")
    reader_parts = reader_req.dig("input", 0, "content")
    assert_equal 3, reader_parts.count { |p| p["type"] == "input_image" }
    assert_includes reader_parts.find { |p| p["type"] == "input_text" }.fetch("text"), "Informação complementar do operador."

    # Verify persisted exact final input images match recorded hashes
    result.dig(:hashes, :reader_inputs).each do |input_record|
      assert File.exist?(input_record[:path]), "Expected persisted input image #{input_record[:path]}"
      assert_equal input_record[:sha256], Digest::SHA256.file(input_record[:path]).hexdigest
    end
  end

  def test_monthly_unsafe_mask_covering_panel_withholds_panel_to_review_without_masking_main_text
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      decision_response(
        model: "gpt-6-luna",
        answers: {
          action: "review",
          relationship: "old_secondary_inset",
          main_text_overlap: "overlaps_or_uncertain",
          location: "deny",
          time: "deny",
          date: "deny"
        }
      )
    ])
    geometry_payload = {
      heading_text: "Agenda Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Painel Único",
          box: {left: 0, top: 0, right: 500, bottom: 500},
          # Small 10% box still overlaps main text per Judge assessment (not decided by %)
          miniatures: [{left: 20, top: 20, right: 120, bottom: 120}],
          cleanup: "keep_colour"
        }
      ]
    }
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload)
    ])

    result = Ocr::Workflow.call(@image_path)

    assert_equal "monthly_agenda", result[:route]
    assert_empty result[:events]
    assert_equal 1, result[:review_items].length
    assert_equal "judge", result[:review_items].first[:stage]
    assert_equal "uncertain_mask_geometry", result[:review_items].first[:reason]
    # Reader was not called because the only panel was withheld by unsafe mask geometry
    assert_equal 1, @response_requests.length
  end

  def test_monthly_normal_mask_with_overlap_and_uncertain_relationship_withhold_to_review
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      # Panel 1: normal mask action, but Judge says it overlaps main text -> must NOT erase main text
      decision_response(
        model: "gpt-6-luna",
        answers: {
          action: "mask",
          relationship: "separate_graphic",
          main_text_overlap: "overlaps_or_uncertain",
          location: "deny",
          time: "deny",
          date: "deny"
        }
      ),
      # Panel 2: review action, clear geometry, but uncertain_or_main_conflict -> must NOT pass mask_unverified_inset
      decision_response(
        model: "gpt-6-luna",
        answers: {
          action: "review",
          relationship: "uncertain_or_main_conflict",
          main_text_overlap: "clear_of_main_text",
          location: "deny",
          time: "deny",
          date: "deny"
        }
      )
    ])
    geometry_payload = {
      heading_text: "Agenda Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Máscara Normal Insegura",
          box: {left: 0, top: 0, right: 500, bottom: 500},
          miniatures: [{left: 20, top: 20, right: 100, bottom: 100}],
          cleanup: "keep_colour"
        },
        {
          id: 2,
          title_hint: "Conflito/Relação Incerta",
          box: {left: 500, top: 0, right: 1000, bottom: 500},
          miniatures: [{left: 520, top: 20, right: 600, bottom: 100}],
          cleanup: "keep_colour"
        }
      ]
    }
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload)
    ])

    result = Ocr::Workflow.call(@image_path)

    assert_empty result[:events]
    assert_equal 2, result[:review_items].length
    assert_equal "uncertain_mask_geometry", result[:review_items][0][:reason]
    assert_equal "uncertain_inset_relationship", result[:review_items][1][:reason]
    assert_equal 1, @response_requests.length
  end

  def test_monthly_mixed_preserve_and_review_enforces_banner_time_date_permissions_and_panel_flags
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      # Panel 1 miniature 1: preserve with only location allowed
      decision_response(
        model: "gpt-6-luna",
        answers: {
          action: "preserve",
          relationship: "shared_banner",
          main_text_overlap: "clear_of_main_text",
          location: "allow",
          time: "deny",
          date: "deny"
        }
      ),
      # Panel 1 miniature 2: old secondary inset clear of main text -> mask_unverified_inset
      decision_response(
        model: "gpt-6-luna",
        answers: {
          action: "review",
          relationship: "old_secondary_inset",
          main_text_overlap: "clear_of_main_text",
          location: "deny",
          time: "deny",
          date: "deny"
        }
      )
    ])
    geometry_payload = {
      heading_text: "Agenda Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Grupo Misto + Painel Ilegível",
          box: {left: 0, top: 0, right: 1000, bottom: 500},
          miniatures: [
            {left: 20, top: 20, right: 200, bottom: 100},
            {left: 700, top: 20, right: 900, bottom: 150}
          ],
          cleanup: "keep_colour"
        },
        {
          id: 2,
          title_hint: "Painel com Texto Contraditório",
          box: {left: 0, top: 500, right: 1000, bottom: 1000},
          miniatures: [],
          cleanup: "keep_colour"
        }
      ]
    }
    reader_payload = {
      panels: [
        {
          panel_id: 1,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [
            ready_candidate(
              name: "Evento com Hora do Banner Negada",
              start_date: "18/10/2026",
              start_time: "22:00",
              location: "Largo das Palmeiras",
              location_evidence: "Largo das Palmeiras",
              location_source: "banner",
              time_source: "banner"
            )
          ]
        },
        {
          panel_id: 2,
          panel_review_reason: "illegible_panel",
          panel_review_detail: "Hora e local parcialmente cortados.",
          candidates: [
            ready_candidate(
              name: "Evento em Painel Ilegível",
              start_date: "20/10/2026",
              location: "Praça do Município",
              location_evidence: "Praça do Município"
            )
          ]
        }
      ]
    }
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload)
    ])

    result = Ocr::Workflow.call(@image_path)

    assert_empty result[:events]
    assert_equal 2, result[:review_items].length
    assert_equal "unauthorized_banner_time", result[:review_items][0][:reason]
    assert_equal "illegible_panel", result[:review_items][1][:reason]
    assert_equal "Evento em Painel Ilegível", result[:review_items][1].dig(:candidate, :name)

    panel1_policy = result.dig(:diagnostics, :banner_policies).find { |p| p[:panel_id] == 1 }
    assert_equal "mask_unverified_inset", panel1_policy[:action]
    assert_equal true, panel1_policy[:has_preserved_banner]
    assert_equal 1, panel1_policy[:masked_boxes].length
  end

  def test_uncertain_router_returns_review_route_without_calling_geometry_or_reader
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "uncertain", month: "uncertain"})
    ])

    result = Ocr::Workflow.call(@image_path)

    assert_equal "review", result[:route]
    assert_empty result[:events]
    assert_equal 1, result[:review_items].length
    assert_equal "router", result[:review_items].first[:stage]
    assert_empty @response_requests
  end

  def test_failed_crop_mask_outside_panel_raises_crop_error
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "july"})
    ])
    geometry_payload = {
      heading_text: "Agenda Julho 2025",
      month: 7,
      year: 2025,
      panels: [
        {
          id: 1,
          title_hint: "Painel 1",
          box: {left: 0, top: 0, right: 400, bottom: 400},
          miniatures: [{left: 450, top: 10, right: 550, bottom: 100}],
          cleanup: "keep_colour"
        }
      ]
    }
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload)
    ])

    error = assert_raises(Ocr::CropError) { Ocr::Workflow.call(@image_path) }
    assert_equal :crop, error.stage
    assert_equal 1, error.panel_id
  end

  def test_truncated_reader_response_raises_hard_workflow_error
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_responses([
      openai_response(model: "gpt-6.1-terra", payload: {panels: []}, status: "incomplete")
    ])

    workflow = Ocr::Workflow.new
    error = assert_raises(Ocr::WorkflowError) { workflow.analyze(@image_path) }
    assert_equal :reader, error.stage
    evidence = workflow.run_evidence
    elapsed = evidence.dig(:timing, :total_seconds)
    assert_kind_of Numeric, elapsed
    assert_operator elapsed, :>, 0
    assert_operator elapsed, :>=, evidence.dig(:timing, :stages).values.sum - 0.001
    assert_equal elapsed, workflow.run_evidence.dig(:timing, :total_seconds)

    report = Ocr::BenchmarkScorer.score_runs(
      [evidence.merge(case_id: "reading_club_control", error: {stage: error.stage, message: error.message})],
      cases_path: File.expand_path("../fixtures/ocr/cases.json", __dir__)
    )
    assert_equal elapsed, report.dig(:aggregates, :total_seconds)
  end

  def test_malformed_reader_json_raises_hard_workflow_error
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_responses([
      openai_response(model: "gpt-6.1-terra", payload: "{bad json")
    ])

    error = assert_raises(Ocr::WorkflowError) { Ocr::Workflow.call(@image_path) }
    assert_equal :reader, error.stage
  end

  def test_invalid_emitted_ready_event_raises_event_validation_error
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_responses([
      openai_response(
        model: "gpt-6.1-terra",
        payload: {
          panels: [
            {
              panel_id: 1,
              panel_review_reason: "none",
              panel_review_detail: nil,
              candidates: [ready_candidate(name: "Concerto", start_date: "31/02/2026")]
            }
          ]
        }
      )
    ])

    assert_raises(EventValidationError) { Ocr::Workflow.call(@image_path) }
  end

  def test_repeats_execute_fresh_router_geometry_judge_and_reader_calls_with_no_reuse
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"}),
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_responses([
      openai_response(model: "gpt-6.1-terra", payload: {panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate]}]}),
      openai_response(model: "gpt-6.1-terra", payload: {panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate]}]})
    ])

    2.times { Ocr::Workflow.call(@image_path) }

    assert_equal 2, @decision_requests.length
    assert_equal 2, @response_requests.length
  end

  def test_pdf_input_raises_explicit_boundary_error_preserving_legacy_pdf_path
    pdf_path = File.join(@dir, "programme.pdf")
    File.write(pdf_path, "%PDF-1.4")

    error = assert_raises(ArgumentError) { Ocr::Workflow.call(pdf_path) }
    assert_includes error.message, "PDF"
    assert_includes error.message, "EventOcrService"
  end

  def test_missing_openai_key_does_not_redirect_to_openrouter
    RubyLLM.config.openai_api_key = nil
    RubyLLM.config.openrouter_api_key = "openrouter-key"

    assert_raises(RubyLLM::ConfigurationError) { Ocr::Workflow.call(@image_path) }
    assert_empty @decision_requests
    assert_empty @response_requests
  end

  def test_gemini_reader_override_works_on_direct_workflow_branch
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_request(:post, GEMINI_URL).with do |req|
      @gemini_requests << JSON.parse(req.body)
      true
    end.to_return(
      status: 200,
      headers: {"Content-Type" => "application/json"},
      body: JSON.generate(
        candidates: [
          {
            content: {
              role: "model",
              parts: [{text: JSON.generate(panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate]}])}]
            },
            finishReason: "STOP"
          }
        ],
        usageMetadata: {promptTokenCount: 120, candidatesTokenCount: 60},
        modelVersion: "gemini-flash-latest"
      )
    )

    result = Ocr::Workflow.call(@image_path, model: "gemini-flash-latest", reasoning_effort: "medium")

    assert_equal "direct_ocr", result[:route]
    assert_equal 1, result[:events].length
    assert_equal 1, @gemini_requests.length
  end

  def test_clock_year_2026_and_2027_and_truncated_geometry_and_crop_failure
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"}),
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"}),
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "july"})
    ])
    stub_responses([
      openai_response(model: "gpt-6.1-terra", payload: {panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate(start_date: "19/10/2026")]}]}),
      openai_response(model: "gpt-6.1-terra", payload: {panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate(start_date: "19/10/2027")]}]}),
      openai_response(model: "gpt-6-luna", payload: {heading_text: "Julho", month: 7, year: 2025, panels: []}, status: "incomplete")
    ])

    r2026 = Ocr::Workflow.call(@image_path, fallback_year: 2026)
    r2027 = Ocr::Workflow.call(@image_path, fallback_year: 2027)
    assert_equal "19/10/2026", r2026[:events].first[:start_date]
    assert_equal "19/10/2027", r2027[:events].first[:start_date]

    geom_err = assert_raises(Ocr::GeometryError) { Ocr::Workflow.call(@image_path) }
    assert_equal :geometry, geom_err.stage

    # MiniMagick crop failure raises Ocr::CropError
    Ocr::ImagePrep.stub(:crop_region, ->(*_args, **_kwargs) { raise Ocr::CropError.new("Falha simulada no recorte", panel_id: 1) }) do
      stub_decisions([decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "july"})])
      stub_responses([
        openai_response(
          model: "gpt-6-luna",
          payload: {
            heading_text: "Agenda Julho 2025",
            month: 7,
            year: 2025,
            panels: [{id: 1, title_hint: "P1", box: {left: 0, top: 0, right: 500, bottom: 500}, miniatures: [], cleanup: "keep_colour"}]
          }
        )
      ])
      crop_err = assert_raises(Ocr::CropError) { Ocr::Workflow.call(@image_path) }
      assert_equal :crop, crop_err.stage
    end
  end

  def test_workflow_explicit_auto_omits_image_detail_across_all_stages
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      decision_response(
        model: "gpt-6-luna",
        answers: {
          action: "preserve",
          relationship: "shared_banner",
          main_text_overlap: "clear_of_main_text",
          location: "allow",
          time: "deny",
          date: "deny"
        }
      )
    ])
    geometry_payload = {
      heading_text: "Agenda Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Painel 1",
          box: {left: 0, top: 0, right: 500, bottom: 500},
          miniatures: [{left: 20, top: 20, right: 120, bottom: 120}],
          cleanup: "keep_colour"
        }
      ]
    }
    reader_payload = {
      panels: [
        {
          panel_id: 1,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [ready_candidate(location: "Largo das Palmeiras", location_evidence: "Largo das Palmeiras", location_source: "banner")]
        }
      ]
    }
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload)
    ])

    result = Ocr::Workflow.call(@image_path, image_detail: "auto")

    assert_equal "auto", result[:image_detail]
    @decision_requests.each do |req|
      parts = req.dig("input", 0, "content").select { |p| p["type"] == "input_image" }
      refute_empty parts
      parts.each { |part| refute part.key?("detail"), "Expected default auto to omit detail in Decisions: #{part.inspect}" }
    end
    @response_requests.each do |req|
      parts = req.dig("input", 0, "content").select { |p| p["type"] == "input_image" }
      refute_empty parts
      parts.each { |part| refute part.key?("detail"), "Expected default auto to omit detail in Responses: #{part.inspect}" }
    end
  end

  def test_workflow_original_image_detail_passes_original_to_router_geometry_judge_pair_and_reader_and_traces_errors
    assert_raises(ArgumentError) { Ocr::Workflow.call(@image_path, image_detail: "ultra_invalid") }
    assert_empty @decision_requests
    assert_empty @response_requests

    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      decision_response(
        model: "gpt-6-luna",
        answers: {
          action: "preserve",
          relationship: "shared_banner",
          main_text_overlap: "clear_of_main_text",
          location: "allow",
          time: "deny",
          date: "deny"
        }
      )
    ])
    geometry_payload = {
      heading_text: "Agenda Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Painel 1",
          box: {left: 0, top: 0, right: 500, bottom: 500},
          miniatures: [{left: 20, top: 20, right: 120, bottom: 120}],
          cleanup: "keep_colour"
        }
      ]
    }
    reader_payload = {
      panels: [
        {
          panel_id: 1,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [ready_candidate(location: "Largo das Palmeiras", location_evidence: "Largo das Palmeiras", location_source: "banner")]
        }
      ]
    }
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload)
    ])

    result = Ocr::Workflow.call(@image_path, image_detail: "original")

    assert_equal "original", result[:image_detail]
    assert_equal 2, @decision_requests.length
    assert_equal 2, @response_requests.length

    router_images = @decision_requests[0].dig("input", 0, "content").select { |p| p["type"] == "input_image" }
    assert_equal ["original"], router_images.map { |p| p["detail"] }

    judge_images = @decision_requests[1].dig("input", 0, "content").select { |p| p["type"] == "input_image" }
    assert_equal %w[original original], judge_images.map { |p| p["detail"] }

    geometry_images = @response_requests[0].dig("input", 0, "content").select { |p| p["type"] == "input_image" }
    assert_equal ["original"], geometry_images.map { |p| p["detail"] }

    reader_images = @response_requests[1].dig("input", 0, "content").select { |p| p["type"] == "input_image" }
    assert_equal ["original"], reader_images.map { |p| p["detail"] }

    # Trace requested image_detail even when a stage errors
    stub_decisions([decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})])
    stub_responses([openai_response(model: "gpt-6.1-terra", payload: "{broken", status: "completed")])
    workflow = Ocr::Workflow.new(image_detail: "original")
    assert_raises(Ocr::WorkflowError) { workflow.analyze(@image_path) }
    assert_equal "original", workflow.run_evidence[:image_detail]
  end

  def test_workflow_monthly_panel_without_miniatures_blocks_banner_sourced_candidate
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"})
    ])
    geometry_payload = {
      heading_text: "Agenda Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Sem miniatura",
          box: {left: 0, top: 0, right: 500, bottom: 500},
          miniatures: [],
          cleanup: "keep_colour"
        }
      ]
    }
    reader_payload = {
      panels: [
        {
          panel_id: 1,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [ready_candidate(date_source: "banner")]
        }
      ]
    }
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload)
    ])

    result = Ocr::Workflow.call(@image_path)
    assert_empty result[:events]
    assert_equal "unauthorized_banner_date", result[:review_items].first[:reason]
  end

  def test_gemini_reader_override_works_with_image_detail_original
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_request(:post, GEMINI_URL).with do |req|
      @gemini_requests << JSON.parse(req.body)
      true
    end.to_return(
      status: 200,
      headers: {"Content-Type" => "application/json"},
      body: JSON.generate(
        candidates: [
          {
            content: {
              role: "model",
              parts: [{text: JSON.generate(panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate]}])}]
            },
            finishReason: "STOP"
          }
        ],
        usageMetadata: {promptTokenCount: 120, candidatesTokenCount: 60},
        modelVersion: "gemini-flash-latest"
      )
    )

    result = Ocr::Workflow.call(@image_path, model: "gemini-flash-latest", image_detail: "original")

    assert_equal "direct_ocr", result[:route]
    assert_equal "original", result[:image_detail]
    assert_equal 1, result[:events].length
    assert_equal 1, @gemini_requests.length
  end

  def test_workflow_direct_no_upscale_retains_1x_dimensions_with_4096_cap_and_keeps_image_detail_original
    assert_raises(ArgumentError) { Ocr::Workflow.call(@image_path, upscale: "no") }
    assert_empty @decision_requests
    assert_empty @response_requests

    artifact_up = File.join(@dir, "direct_up")
    artifact_no = File.join(@dir, "direct_no")
    reader_payload = {
      panels: [
        {panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [ready_candidate]}
      ]
    }
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"}),
      decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})
    ])
    stub_responses([
      openai_response(model: "gpt-6.1-terra", payload: reader_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload)
    ])

    result_up = Ocr::Workflow.call(@image_path, image_detail: "original", upscale: true, artifact_dir: artifact_up)
    result_no = Ocr::Workflow.call(@image_path, image_detail: "original", upscale: false, artifact_dir: artifact_no)

    assert_equal true, result_up[:upscale]
    assert_equal [800, 800], result_up.dig(:hashes, :reader_inputs, 0, :dimensions)
    assert_equal false, result_no[:upscale]
    assert_equal "original", result_no[:image_detail]
    assert_equal [400, 400], MiniMagick::Image.new(File.join(artifact_no, "01-original.png")).dimensions
    assert_equal [400, 400], MiniMagick::Image.new(File.join(artifact_no, "03-direct-ocr.png")).dimensions
    assert_equal [400, 400], result_no.dig(:hashes, :reader_inputs, 0, :dimensions)

    @decision_requests.concat(@response_requests).each do |req|
      parts = req.dig("input", 0, "content").select { |p| p["type"] == "input_image" }
      refute_empty parts
      parts.each { |part| assert_equal "original", part["detail"] }
    end

    oversized_path = File.join(@dir, "oversized.png")
    MiniMagick.convert do |cmd|
      cmd.size "5000x1000"
      cmd << "xc:white"
      cmd << oversized_path
    end
    artifact_cap = File.join(@dir, "direct_cap")
    stub_decisions([decision_response(model: "gpt-6-luna", answers: {kind: "other", month: "uncertain"})])
    stub_responses([openai_response(model: "gpt-6.1-terra", payload: reader_payload)])

    capped = Ocr::Workflow.call(oversized_path, upscale: false, artifact_dir: artifact_cap)
    assert_equal false, capped[:upscale]
    assert_equal [5000, 1000], MiniMagick::Image.new(File.join(artifact_cap, "01-original.png")).dimensions
    capped_dims = MiniMagick::Image.new(File.join(artifact_cap, "03-direct-ocr.png")).dimensions
    assert_equal 4096, capped_dims.max
    assert_equal capped_dims, capped.dig(:hashes, :reader_inputs, 0, :dimensions)
  end

  def test_workflow_monthly_no_upscale_retains_100_percent_reader_dimensions_while_preserving_crop_mask_cleanup_and_judge_inputs
    geometry_payload = {
      heading_text: "Agenda Outubro 2026",
      month: 10,
      year: 2026,
      panels: [
        {
          id: 1,
          title_hint: "Painel 1",
          box: {left: 0, top: 0, right: 500, bottom: 500},
          miniatures: [{left: 20, top: 20, right: 120, bottom: 120}],
          cleanup: "whiten_light_background"
        }
      ]
    }
    reader_payload = {
      panels: [
        {
          panel_id: 1,
          panel_review_reason: "none",
          panel_review_detail: nil,
          candidates: [ready_candidate(location: "Largo das Palmeiras", location_evidence: "Largo das Palmeiras", location_source: "banner")]
        }
      ]
    }
    stub_decisions([
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      decision_response(model: "gpt-6-luna", answers: {action: "preserve", relationship: "shared_banner", main_text_overlap: "clear_of_main_text", location: "allow", time: "deny", date: "deny"}),
      decision_response(model: "gpt-6-luna", answers: {kind: "monthly_agenda", month: "october"}),
      decision_response(model: "gpt-6-luna", answers: {action: "preserve", relationship: "shared_banner", main_text_overlap: "clear_of_main_text", location: "allow", time: "deny", date: "deny"})
    ])
    stub_responses([
      openai_response(model: "gpt-6-luna", payload: geometry_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload),
      openai_response(model: "gpt-6-luna", payload: geometry_payload),
      openai_response(model: "gpt-6.1-terra", payload: reader_payload)
    ])

    artifact_up = File.join(@dir, "monthly_up")
    artifact_no = File.join(@dir, "monthly_no")
    result_up = Ocr::Workflow.call(@image_path, image_detail: "original", upscale: true, artifact_dir: artifact_up)
    result_no = Ocr::Workflow.call(@image_path, image_detail: "original", upscale: false, artifact_dir: artifact_no)

    assert_equal true, result_up[:upscale]
    assert_equal false, result_no[:upscale]
    assert_equal "original", result_no[:image_detail]

    native_dims = MiniMagick::Image.new(File.join(artifact_no, "panel-1-native.png")).dimensions
    assert_equal native_dims, MiniMagick::Image.new(File.join(artifact_up, "panel-1-native.png")).dimensions
    assert_equal File.binread(File.join(artifact_up, "panel-1-candidate-1.png")), File.binread(File.join(artifact_no, "panel-1-candidate-1.png"))
    assert_equal File.binread(File.join(artifact_up, "panel-1-masked.png")), File.binread(File.join(artifact_no, "panel-1-masked.png"))
    assert_equal File.binread(File.join(artifact_up, "panel-1-cleaned.png")), File.binread(File.join(artifact_no, "panel-1-cleaned.png"))
    assert_equal File.binread(File.join(artifact_up, "panel-1-mask-overlay.png")), File.binread(File.join(artifact_no, "panel-1-mask-overlay.png"))

    up_final_dims = MiniMagick::Image.new(File.join(artifact_up, "panel-1-final-ocr.png")).dimensions
    no_final_dims = MiniMagick::Image.new(File.join(artifact_no, "panel-1-final-ocr.png")).dimensions
    assert_operator up_final_dims[0], :>, native_dims[0]
    assert_equal native_dims, no_final_dims
    assert_equal native_dims, result_no.dig(:hashes, :reader_inputs, 0, :dimensions)

    @decision_requests.concat(@response_requests).each do |req|
      parts = req.dig("input", 0, "content").select { |p| p["type"] == "input_image" }
      refute_empty parts
      parts.each { |part| assert_equal "original", part["detail"] }
    end
  end

  def test_additional_text_source_availability_in_direct_and_monthly_routes
    candidate = ready_candidate(
      name: "Workshop de Atendimento ao Público e Comunicação", start_date: "16/07/2025", start_time: nil,
      location: "Casa do Povo de Nossa Senhora da Piedade", description: "Workshop de atendimento ao público e comunicação.",
      category: "Aprendizagem & Workshops", organizer: "Casa do Povo de Nossa Senhora da Piedade",
      contact_tel: "291 985 289", location_evidence: "CASA DO POVO DE NOSSA SENHORA DA PIEDADE",
      location_source: "additional_text", time_source: "none"
    )
    reader = {panels: [{panel_id: 1, panel_review_reason: "none", panel_review_detail: nil, candidates: [candidate]}]}
    geometry = {heading_text: "julho 2025", month: 7, year: 2025,
                panels: [{id: 1, title_hint: "Workshop e Oficina", box: {left: 0, top: 0, right: 500, bottom: 500}, miniatures: [], cleanup: "keep_colour"}]}
    [false, true].each do |monthly|
      [nil, "Local: Casa do Povo de Nossa Senhora da Piedade"].each do |additional_text|
        stub_decisions([decision_response(model: "gpt-6-luna", answers: {kind: monthly ? "monthly_agenda" : "other", month: monthly ? "july" : "uncertain"})])
        responses = []
        responses << openai_response(model: "gpt-6-luna", payload: geometry) if monthly
        responses << openai_response(model: "gpt-6.1-terra", payload: reader)
        stub_responses(responses)
        result = Ocr::Workflow.call(@image_path, additional_text: additional_text)
        reader_request = @response_requests.last
        properties = reader_request.dig("text", "format", "schema", "properties", "panels", "items", "properties", "candidates", "items", "properties")
        %w[location_source date_source time_source price_source].each do |source|
          choices = properties.fetch(source).fetch("enum")
          if additional_text
            assert_includes choices, "additional_text"
          else
            refute_includes choices, "additional_text"
          end
        end
        assert_includes reader_request["instructions"], "Captions visible inside source images"
        if additional_text
          assert_equal 1, result[:events].length
          assert_empty result[:review_items]
        else
          assert_empty result[:events]
          assert_equal "unavailable_additional_text", result[:review_items].first[:reason]
          assert_equal "additional_text", result[:review_items].first.dig(:trace, :location_source)
        end
      end
    end
  end

  private

  def ready_candidate(**overrides)
    {
      name: "Clube de Leitura — Livros que Inspiram",
      start_date: "14/11/2026",
      start_time: "18:00",
      end_date: nil,
      end_time: nil,
      location: "Biblioteca Municipal",
      description: "Sessão mensal do clube de leitura na Biblioteca Municipal.",
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
      review_detail: nil
    }.merge(overrides)
  end

  def stub_decisions(bodies)
    stub_request(:post, OPENAI_DECISIONS_URL).with do |request|
      @decision_requests << JSON.parse(request.body)
      true
    end.to_return(*bodies.map do |body|
      {status: 200, headers: {"Content-Type" => "application/json"}, body: JSON.generate(body)}
    end)
  end

  def decision_response(model:, answers:)
    {
      model: model,
      answers: answers.map do |name, choice|
        {
          name: name.to_s,
          choice: choice.to_s,
          probabilities: [{value: choice.to_s, probability: 1.0}],
          confidence: 1.0
        }
      end,
      usage: {input_tokens: 150, output_tokens: 10}
    }
  end

  def stub_responses(bodies)
    stub_request(:post, OPENAI_RESPONSES_URL).with do |request|
      @response_requests << JSON.parse(request.body)
      true
    end.to_return(*bodies)
  end

  def openai_response(model:, payload:, status: "completed")
    text = payload.is_a?(String) ? payload : JSON.generate(payload)
    body = {
      id: "resp_test",
      object: "response",
      status: status,
      model: model,
      output: [{id: "msg_test", type: "message", role: "assistant", content: [{type: "output_text", text: text}]}],
      usage: {input_tokens: 300, output_tokens: 120, output_tokens_details: {reasoning_tokens: 30}}
    }
    body[:incomplete_details] = {reason: "max_output_tokens"} if status == "incomplete"
    {status: 200, headers: {"Content-Type" => "application/json"}, body: JSON.generate(body)}
  end
end
