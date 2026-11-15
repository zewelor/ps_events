require "bundler/setup"
require "minitest/autorun"
require "json"
require "tempfile"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/ocr/benchmark_scorer"

class OcrBenchmarkScorerTest < Minitest::Test
  CASES_PATH = File.expand_path("../fixtures/ocr/cases.json", __dir__)

  def test_reference_without_route_expectation_does_not_measure_routing
    Tempfile.create(["ocr_source_reference", ".json"]) do |file|
      reference = JSON.parse(File.read(CASES_PATH))
      reference.fetch("cases").each { |entry| entry.delete("expected_route") }
      file.write(JSON.generate(reference))
      file.flush
      run = {case_id: "reading_club_control", route: "source", events: [], review_items: []}

      report = Ocr::BenchmarkScorer.score_runs([run], cases_path: file.path)

      assert_nil report.fetch(:runs).first.fetch(:route_matched)
      assert_equal 0, report.dig(:aggregates, :route_evaluated_runs)
      assert_equal 0, report.dig(:aggregates, :route_matches)
      assert_equal 1, report.dig(:aggregates, :missing_occurrences)
    end
  end

  def test_cases_json_corpus_totals_are_53_strict_events_and_3_july_review_candidates
    cases = Ocr::BenchmarkScorer.load_cases(CASES_PATH)
    assert_equal 10, cases.length
    assert_equal 53, cases.sum { |c| c.fetch("expected_event_count") }
    monthly = cases.select { |c| c["expected_route"] == "monthly_agenda" }
    direct = cases.select { |c| c["expected_route"] == "direct_ocr" }
    assert_equal 48, monthly.sum { |c| c.fetch("expected_event_count") }
    assert_equal 5, direct.sum { |c| c.fetch("expected_event_count") }
    july = cases.find { |c| c["id"] == "monthly_july_2025_shared_banner" }
    assert_equal 3, july.dig("review_candidates", "events").length
  end

  def test_scorer_aggregates_saved_legacy_top_level_time_and_tokens_with_selected_metrics
    legacy_run = JSON.parse(JSON.generate(
      case_id: "reading_club_control",
      run: 1,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      seconds: 12.5,
      tokens: {input_tokens: 1_000, output_tokens: 200, cache_read_tokens: 300, cache_write_tokens: 50, thinking_tokens: 25},
      response_models: ["gpt-6-luna"],
      ocr_schema_sha256: "saved-schema-hash",
      responses: []
    ))
    selected_run = {
      case_id: "reading_club_control",
      run: 2,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      seconds: 99,
      tokens: {input_tokens: 900, output_tokens: 90},
      timing: {total_seconds: 8.0, stages: {reader: 8.0}},
      usage_totals: {input_tokens: 400, output_tokens: 80}
    }

    report = Ocr::BenchmarkScorer.score_runs([legacy_run, selected_run], cases_path: CASES_PATH)
    legacy_scored, selected_scored = report[:runs]

    assert_equal({total_seconds: 12.5, stages: {}}, legacy_scored[:timing])
    assert_equal(
      {input_tokens: 1_000, output_tokens: 200, cache_read_tokens: 300, cache_write_tokens: 50, thinking_tokens: 25},
      legacy_scored[:usage_totals]
    )
    assert_equal({total_seconds: 8.0, stages: {reader: 8.0}}, selected_scored[:timing])
    assert_equal({input_tokens: 400, output_tokens: 80}, selected_scored[:usage_totals])

    assert_equal 20.5, report.dig(:aggregates, :total_seconds)
    assert_equal({"reader" => 8.0}, report.dig(:aggregates, :stage_seconds))
    assert_equal(
      {input_tokens: 1_400, output_tokens: 280, cache_read_tokens: 300, cache_write_tokens: 50, thinking_tokens: 25},
      report.dig(:aggregates, :usage_totals)
    )
  end

  def test_scorer_matches_aliases_fallback_year_bad_fields_omissions_extras_and_reviews
    palmito_run = {
      case_id: "palmito_multiple_phone_numbers",
      run: 1,
      fallback_year: 2027,
      route: "direct_ocr",
      events: [
        {
          name: "Formação de Palmito",
          start_date: "19/10/2027",
          end_date: "23/10/2027",
          start_time: "14:00",
          end_time: "18:00",
          location: "Casa do Povo de N. S. da Piedade",
          price_type: "Desconhecido",
          contact_tel: "924 366 168",
          description: "Formação tradicional de palmito. Informações pelo 291 985 289."
        },
        {
          name: "Evento Inventado",
          start_date: "20/10/2027",
          location: "Praça do Município",
          price_type: "Desconhecido"
        }
      ],
      review_items: []
    }

    rally_run = {
      case_id: "rally_missing_venue",
      run: 1,
      fallback_year: 2027,
      route: "direct_ocr",
      events: [],
      review_items: [
        {
          stage: "admission",
          group_id: 1,
          reason: "missing_location",
          candidate: {name: "Rali Porto Santo", start_date: "06/11/2026", end_date: "07/11/2026", location: nil}
        }
      ]
    }

    november_run = {
      case_id: "monthly_november_2026_weekend_hours",
      run: 1,
      fallback_year: 2026,
      route: "monthly_agenda",
      events: [
        {
          name: "2.ª Feira de Artesanato",
          start_date: "07/11/2026",
          end_date: "15/11/2026",
          start_time: "17:00", # wrong weekday hour!
          end_time: "23:00",
          location: "Centro Cultural e de Congressos",
          price_type: "Desconhecido"
        },
        {
          name: "História Florestal do Porto Santo",
          start_date: "21/11/2026",
          start_time: "18:00",
          location: "Centro Cultural de Congressos do Porto Santo",
          organizer: "Reserva da Biosfera da Ilha do Porto Santo"
        }
      ],
      review_items: [
        {
          stage: "admission",
          group_id: 4,
          reason: "missing_location",
          candidate: {name: "Concurso de Natal — Presépios da nossa Reserva da Biosfera", start_date: "16/11/2026", end_date: "04/12/2026"}
        }
      ]
    }

    report = Ocr::BenchmarkScorer.score_runs([palmito_run, rally_run, november_run], cases_path: CASES_PATH)

    palmito_scored = report[:runs][0]
    assert palmito_scored[:route_matched]
    assert_equal 1, palmito_scored[:matched_occurrences]
    assert_equal 1, palmito_scored[:complete_checked_events]
    assert_equal({total: 1, passed: 1, failed: 0, details: []}, palmito_scored[:contact_number_checks])
    assert_equal 1, palmito_scored[:unmatched_extra_events].length
    assert_equal "Evento Inventado", palmito_scored[:unmatched_extra_events].first[:name]

    rally_scored = report[:runs][1]
    assert rally_scored[:route_matched]
    assert_equal 1, rally_scored[:expected_reviews]
    assert_equal 1, rally_scored[:matched_expected_reviews]
    assert_empty rally_scored[:unsafe_omission_emissions]

    november_scored = report[:runs][2]
    assert_equal 2, november_scored[:matched_occurrences]
    assert_equal 5, november_scored[:missing_occurrences]
    assert_equal 1, november_scored[:bad_fields].length
    assert_equal "start_time", november_scored[:bad_fields].first[:field]
    assert_equal "16:00", november_scored[:bad_fields].first[:expected]
    assert_equal "17:00", november_scored[:bad_fields].first[:actual]
    assert_equal 5, november_scored[:expected_reviews]
    assert_equal 1, november_scored[:matched_expected_reviews]
    assert_equal 4, november_scored[:missed_expected_reviews]
  end

  def test_scorer_distinguishes_july_ambiguous_review_candidates_from_unmatched_extras
    july_run = {
      case_id: "monthly_july_2025_shared_banner",
      run: 1,
      fallback_year: 2026,
      route: "monthly_agenda",
      events: [
        {
          name: "Viagem +65",
          start_date: "02/07/2025",
          end_date: "04/07/2025",
          location: "Madeira",
          organizer: "Município do Porto Santo"
        },
        {
          name: "Evento Desconhecido",
          start_date: "05/07/2025",
          location: "Largo das Palmeiras"
        }
      ],
      review_items: [
        {
          stage: "admission",
          group_id: 8,
          reason: "missing_location",
          candidate: {name: "Dia dos Avós", start_date: "26/07/2025", location: nil}
        },
        {
          stage: "admission",
          group_id: 9,
          reason: "ambiguous_venue_policy",
          candidate: {name: "Visitas LIFEDUNAS", start_date: "09/07/2025", location: "Zona de intervenção do Projeto LIFEDUNAS"}
        },
        {
          stage: "admission",
          group_id: 9,
          reason: "ambiguous_venue_policy",
          candidate: {name: "Visitas LIFEDUNAS", start_date: "23/07/2025", location: "Zona de intervenção do Projeto LIFEDUNAS"}
        }
      ]
    }

    report = Ocr::BenchmarkScorer.score_runs([july_run], cases_path: CASES_PATH)
    scored = report[:runs].first

    assert_equal 1, scored[:review_candidate_emissions].length
    assert_equal "Viagem +65", scored[:review_candidate_emissions].first[:name]
    assert_equal 1, scored[:unmatched_extra_events].length
    assert_equal "Evento Desconhecido", scored[:unmatched_extra_events].first[:name]
    assert_equal({total: 3, emitted: 1, in_review: 2, absent: 0}, scored[:review_candidates_summary])
    assert_equal 1, scored[:matched_expected_reviews]
  end

  def test_omission_identity_is_independent_of_child_field_errors
    base = {case_id: "monthly_september_2026_neighbouring_venues", fallback_year: 2026,
            route: "monthly_agenda", review_items: []}
    valid = {name: "Visita Orientada Imagens e Memória do Concelho do Porto Santo",
             start_date: "17/09/2026", start_time: "15:00", location: "Átrio da Câmara Municipal",
             organizer: "Direção Regional dos Arquivos, das Bibliotecas e do Livro",
             description: "Integrado no Festival Colombo"}
    bad_fields = valid.merge(start_time: "16:00", location: "Outro local")
    scored = Ocr::BenchmarkScorer.score_runs([base.merge(events: [bad_fields])], cases_path: CASES_PATH)[:runs].first

    assert_empty scored[:unsafe_omission_emissions]
    assert_equal %w[location_contains start_time], scored[:bad_fields].map { |item| item[:field] }.sort

    parent = valid.merge(name: "Festival Colombo", description: valid[:name])
    generic = valid.merge(name: "Evento cultural")
    wrong_date = valid.merge(name: "Pequenos Aventureiros, grandes descoberta")
    scored = Ocr::BenchmarkScorer.score_runs([base.merge(events: [parent, generic, wrong_date])], cases_path: CASES_PATH)[:runs].first
    assert_equal [parent[:name], generic[:name], wrong_date[:name]],
      scored[:unsafe_omission_emissions].map { |item| item[:emitted_event] }
  end

  def test_reviews_require_candidate_identity_and_dates_and_cannot_cover_two_occurrences
    base = {case_id: "monthly_july_2025_shared_banner", fallback_year: 2026,
            route: "monthly_agenda", events: []}
    broad = {title_hint: "Visitas LIFEDUNAS", candidate: {name: "Visitas LIFEDUNAS"}}
    wrong_date = {title_hint: "Visitas LIFEDUNAS", candidate: {name: "Visitas LIFEDUNAS", start_date: "10/07/2025"}}
    hint_only = {title_hint: "Visitas LIFEDUNAS", candidate: {name: "Outra atividade", start_date: "09/07/2025"}}
    reviews = [broad, wrong_date, hint_only]
    scored = Ocr::BenchmarkScorer.score_runs([base.merge(review_items: reviews)], cases_path: CASES_PATH)[:runs].first
    assert_equal({total: 3, emitted: 0, in_review: 0, absent: 3}, scored[:review_candidates_summary])

    reviews << {candidate: {name: "Visitas LIFEDUNAS", start_date: "09/07/2025"}}
    scored = Ocr::BenchmarkScorer.score_runs([base.merge(review_items: reviews)], cases_path: CASES_PATH)[:runs].first
    assert_equal({total: 3, emitted: 0, in_review: 1, absent: 2}, scored[:review_candidates_summary])
  end

  def test_undated_group_hint_cannot_override_a_conflicting_candidate
    cases = JSON.parse(File.read(CASES_PATH))
    target = cases.fetch("cases").find { |entry| entry["id"] == "monthly_july_2025_shared_banner" }
    target["required_omissions"] = [{"name_contains" => ["Dia dos Avós"]}]
    run = {case_id: target.fetch("id"), fallback_year: 2026, route: "monthly_agenda", events: []}

    Tempfile.create(["scorer-cases", ".json"]) do |file|
      file.write(JSON.generate(cases))
      file.flush
      conflicting = {title_hint: "Dia dos Avós", candidate: {name: "Outra atividade"}}
      scored = Ocr::BenchmarkScorer.score_runs([run.merge(review_items: [conflicting])], cases_path: file.path)[:runs].first
      assert_equal 0, scored[:matched_expected_reviews]

      scored = Ocr::BenchmarkScorer.score_runs([run.merge(review_items: [{title_hint: "Dia dos Avós"}])], cases_path: file.path)[:runs].first
      assert_equal 1, scored[:matched_expected_reviews]
    end
  end

  def test_one_combined_review_does_not_credit_both_november_activities
    run = {case_id: "monthly_november_2026_weekend_hours", fallback_year: 2026,
           route: "monthly_agenda", events: [], review_items: [
             {candidate: {name: "Dia Nacional do Pijama", start_date: "20/11/2026",
                          description: "A Menina que Queria Desenhar o Mundo e Exibição de um filme para crianças"}}
           ]}
    scored = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH)[:runs].first

    assert_equal 1, scored[:matched_expected_reviews]
    assert_equal 4, scored[:missed_expected_reviews]
  end

  def test_required_review_requires_both_dates_and_candidate_identity
    base = {case_id: "monthly_september_2026_neighbouring_venues", fallback_year: 2026,
            route: "monthly_agenda", events: []}
    invalid = [
      {candidate: {name: "Festival Colombo", start_date: "17/09/2026"}},
      {candidate: {name: "Festival Colombo", start_date: "17/09/2026", end_date: "21/09/2026"}},
      {title_hint: "Festival Colombo", candidate: {name: "Outro", start_date: "17/09/2026", end_date: "20/09/2026"}}
    ]
    scored = Ocr::BenchmarkScorer.score_runs([base.merge(review_items: invalid)], cases_path: CASES_PATH)[:runs].first
    assert_equal 0, scored[:matched_expected_reviews]
    scored = Ocr::BenchmarkScorer.score_runs([base.merge(review_items: invalid + [
      {candidate: {name: "Festival Colombo", start_date: "17/09/2026", end_date: "20/09/2026"}}
    ])], cases_path: CASES_PATH)[:runs].first
    assert_equal 1, scored[:matched_expected_reviews]
  end

  def test_scorer_checks_visible_contact_numbers_for_pair_missing_description_only_joined_and_fabricated
    cases = [
      {
        label: :valid_with_spaces,
        contact_tel: "291 985 289",
        description: "Formação tradicional de palmito. Contacto alternativo: 924 366 168.",
        expected_complete: 1,
        expected_failed: 0
      },
      {
        label: :lost_second_number,
        contact_tel: "924366168",
        description: "Formação tradicional de palmito.",
        expected_complete: 0,
        expected_failed: 1
      },
      {
        label: :both_only_in_description,
        contact_tel: nil,
        description: "Formação tradicional. Contactos: 924366168 / 291985289.",
        expected_complete: 0,
        expected_failed: 1
      },
      {
        label: :joined_in_contact_tel,
        contact_tel: "924 366 168 / 291 985 289",
        description: "Formação tradicional de palmito.",
        expected_complete: 0,
        expected_failed: 1
      },
      {
        label: :fabricated_phone_number,
        contact_tel: "924366168",
        description: "Formação tradicional. Outros números: 291985289 e 911111111.",
        expected_complete: 0,
        expected_failed: 1
      }
    ]

    cases.each do |scenario|
      run = {
        case_id: "palmito_multiple_phone_numbers",
        run: 1,
        fallback_year: 2026,
        route: "direct_ocr",
        events: [
          {
            name: "Formação de Palmito",
            start_date: "19/10/2026",
            end_date: "23/10/2026",
            start_time: "14:00",
            end_time: "18:00",
            location: "Casa do Povo de Nossa Senhora da Piedade",
            price_type: "Desconhecido",
            contact_tel: scenario[:contact_tel],
            description: scenario[:description]
          }
        ],
        review_items: []
      }

      scored = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH)[:runs].first
      assert_equal scenario[:expected_complete], scored[:complete_checked_events], "Failed scenario: #{scenario[:label]}"
      assert_equal scenario[:expected_failed], scored.dig(:contact_number_checks, :failed), "Failed scenario: #{scenario[:label]}"
    end
  end

  def test_scorer_excludes_errored_runs_from_quality_totals_and_surfaces_cost_completeness
    failed_pilot_like = {
      case_id: "monthly_october_2026_reused_inset",
      run: 1,
      fallback_year: 2026,
      stage: "router",
      error: {
        stage: "router",
        type: "RubyLLM::RateLimitError",
        message: "Your project has reached its configured enforced spend limit."
      },
      calls: [],
      usage_totals: {input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0, thinking_tokens: 0},
      cost_totals: {known_cost_usd: 0, cold_cost_usd: 0}
    }

    only_failed = Ocr::BenchmarkScorer.score_runs([failed_pilot_like], cases_path: CASES_PATH)
    failed_run = only_failed[:runs].first
    assert_equal true, failed_run[:unscored_due_to_error]
    assert_equal "router", failed_run[:failed_stage]
    assert_equal 9, failed_run[:expected_events]
    assert_equal 9, failed_run[:unscored_events]
    assert_equal 0, failed_run[:missing_occurrences]
    assert_equal 2, failed_run[:expected_reviews]
    assert_equal 2, failed_run[:unscored_reviews]
    assert_equal 0, failed_run[:missed_expected_reviews]

    failed_agg = only_failed[:aggregates]
    assert_equal 1, failed_agg[:runs]
    assert_equal 0, failed_agg[:scored_runs]
    assert_equal 1, failed_agg[:failed_runs]
    assert_equal({"router" => 1}, failed_agg[:errors_by_stage])
    assert_equal 9, failed_agg[:total_expected_events]
    assert_equal 9, failed_agg[:unscored_due_to_error_events]
    assert_equal 0, failed_agg[:expected_events]
    assert_equal 0, failed_agg[:missing_occurrences]
    assert_equal 2, failed_agg[:total_expected_reviews]
    assert_equal 2, failed_agg[:unscored_due_to_error_reviews]
    assert_equal 0, failed_agg[:expected_reviews]
    assert_equal 0, failed_agg[:missed_expected_reviews]
    assert_equal "unknown", failed_agg.dig(:cost_totals, :status)
    assert_equal false, failed_agg.dig(:cost_totals, :verified)
    assert_nil failed_agg.dig(:cost_totals, :known_cost_usd)

    good_run_missing_call_usage = {
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
      calls: [
        {stage: "router", cost: {known_cost_usd: 0.0001, cold_cost_usd: 0.0001, usage_available: true}},
        {stage: "reader", cost: {known_cost_usd: 0.0, cold_cost_usd: 0.0, usage_available: false}}
      ]
    }

    mixed = Ocr::BenchmarkScorer.score_runs([failed_pilot_like, good_run_missing_call_usage], cases_path: CASES_PATH)
    mixed_agg = mixed[:aggregates]
    assert_equal 1, mixed_agg[:scored_runs]
    assert_equal 1, mixed_agg[:failed_runs]
    assert_equal 1, mixed_agg[:matched_occurrences]
    assert_equal 1, mixed_agg[:expected_events]
    assert_equal 0, mixed_agg[:missing_occurrences]
    assert_equal "partial", mixed_agg.dig(:cost_totals, :status)
    assert_equal false, mixed_agg.dig(:cost_totals, :verified)
    assert_equal 1, mixed_agg.dig(:cost_totals, :unknown_cost_calls)
    assert_equal 2, mixed_agg.dig(:cost_totals, :runs_with_unknown_cost)
    assert_in_delta 0.0001, mixed_agg.dig(:cost_totals, :known_cost_usd), 1e-8
  end

  def test_scorer_uses_native_cost_total_and_prices_cached_tokens_as_hypothetical_writes
    call = {
      stage: "reader",
      model: "gpt-6-luna",
      provider: "openai",
      tokens: {
        input_tokens: 1_000,
        output_tokens: 200,
        cache_read_tokens: 1_000,
        cache_write_tokens: 500,
        thinking_tokens: 100
      },
      cost: {
        input: 0.00001,
        output: 0.0001,
        cache_read: 0.00001,
        cache_write: 0.0000625,
        total: 0.0001825
      }
    }
    run = {
      case_id: "reading_club_control",
      run: 1,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      calls: [call],
      cost_totals: {input: 0.00001, output: 0.0001, cache_read: 0.00001, cache_write: 0.0000625, total: 0.0001825}
    }

    cost = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH).dig(:runs, 0, :cost_totals)

    assert_equal "complete", cost[:status]
    assert_equal 1, cost[:calls_count]
    assert_equal 0, cost[:unknown_cost_calls]
    assert_in_delta 0.0001825, cost[:known_cost_usd], 1e-8
    assert_in_delta 0.0003875, cost[:cold_cost_usd], 1e-8
  end

  def test_scorer_keeps_known_native_costs_when_later_calls_are_unknown_and_run_errors
    paid_call = {
      model: "gpt-6-luna",
      provider: "openai",
      tokens: {input_tokens: 1_000, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0, thinking_tokens: 0},
      cost: {input: 0.0001, total: 0.0001}
    }
    unknown_call = {
      model: "gpt-6-luna",
      provider: "openai",
      tokens: {input_tokens: 1_000, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0, thinking_tokens: 0},
      cost: {input: 0.0001}
    }
    run = {
      case_id: "reading_club_control",
      run: 1,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      error: {stage: "reader", type: "StandardError", message: "later call failed"},
      calls: [paid_call, unknown_call],
      cost_totals: {input: 0.0002}
    }

    cost = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH).dig(:runs, 0, :cost_totals)

    assert_equal "partial", cost[:status]
    assert_equal 2, cost[:calls_count]
    assert_equal 1, cost[:unknown_cost_calls]
    assert_in_delta 0.0001, cost[:known_cost_usd], 1e-8
    assert_in_delta 0.0002, cost[:cold_cost_usd], 1e-8
  end

  def test_scorer_keeps_recorded_native_cost_when_model_pricing_is_unavailable
    run = {
      case_id: "reading_club_control",
      run: 1,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      calls: [
        {
          model: "missing-pricing-model",
          provider: "openai",
          tokens: {input_tokens: 1_000, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0, thinking_tokens: 0},
          cost: {input: 0.0001, total: 0.0001}
        }
      ],
      cost_totals: {input: 0.0001, total: 0.0001}
    }

    cost = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH).dig(:runs, 0, :cost_totals)

    assert_equal "partial", cost[:status]
    assert_equal 0, cost[:unknown_cost_calls]
    assert_in_delta 0.0001, cost[:known_cost_usd], 1e-8
    assert_nil cost[:cold_cost_usd]
  end

  def test_scorer_treats_native_zero_cost_as_known_and_free
    run = {
      case_id: "reading_club_control",
      run: 1,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      calls: [
        {
          model: "gpt-6-luna",
          provider: "openai",
          tokens: {input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0, thinking_tokens: 0},
          cost: {total: 0.0}
        }
      ],
      cost_totals: {total: 0.0}
    }

    cost = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH).dig(:runs, 0, :cost_totals)

    assert_equal "complete", cost[:status]
    assert_equal 0, cost[:unknown_cost_calls]
    assert_equal 0.0, cost[:known_cost_usd]
    assert_equal 0.0, cost[:cold_cost_usd]
  end

  def test_scorer_marks_native_cold_cost_unknown_when_token_buckets_are_incomplete
    run = {
      case_id: "reading_club_control",
      run: 1,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      calls: [
        {
          model: "gpt-6-luna",
          provider: "openai",
          tokens: {input_tokens: 1_000, output_tokens: 0, cache_read_tokens: 0, cache_write_tokens: 0},
          cost: {input: 0.0001, total: 0.0001}
        }
      ],
      cost_totals: {input: 0.0001, total: 0.0001}
    }

    cost = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH).dig(:runs, 0, :cost_totals)

    assert_equal "partial", cost[:status]
    assert_equal 0, cost[:unknown_cost_calls]
    assert_in_delta 0.0001, cost[:known_cost_usd], 1e-8
    assert_nil cost[:cold_cost_usd]
  end

  def test_scorer_preserves_successful_legacy_aggregate_only_cost_totals
    run = {
      case_id: "reading_club_control",
      run: 1,
      fallback_year: 2026,
      route: "direct_ocr",
      events: [],
      usage_totals: {input_tokens: 100, output_tokens: 10},
      cost_totals: {
        status: "complete",
        usage_available: true,
        calls_count: 1,
        unknown_cost_calls: 0,
        known_cost_usd: 0.0002,
        cold_cost_usd: 0.0003
      }
    }

    cost = Ocr::BenchmarkScorer.score_runs([run], cases_path: CASES_PATH).dig(:runs, 0, :cost_totals)

    assert_equal "complete", cost[:status]
    assert_equal 1, cost[:calls_count]
    assert_equal 0, cost[:unknown_cost_calls]
    assert_equal 0.0002, cost[:known_cost_usd]
    assert_equal 0.0003, cost[:cold_cost_usd]
  end
end
