require "bundler/setup"
require "minitest/autorun"
require_relative "../test_helper"

Bundler.require(:default)

require_relative "../../lib/server/ocr/places"
require_relative "../../lib/server/ocr/admission"

class OcrPlacesAndAdmissionTest < Minitest::Test
  def test_clean_visible_text_removes_invisible_format_chars_and_normalizes_spaces
    raw = " \u200B  Auditório\uFEFF\u00A0do   CCC \t "
    assert_equal "Auditório do CCC", Ocr::Places.clean_visible_text(raw)
    assert_nil Ocr::Places.clean_visible_text(" \u200B \uFEFF ")
  end

  def test_canonical_location_normalizes_aliases_and_allows_new_real_venues
    assert_equal "Auditório do Centro Cultural e de Congressos", Ocr::Places.canonical_location("Auditório do CCC")
    assert_equal "Centro Cultural de Congressos do Porto Santo", Ocr::Places.canonical_location("C. C. de Congressos")
    assert_equal "Court Social Club", Ocr::Places.canonical_location("@courtsocialclub")
    assert_equal "Praia da Calheta", Ocr::Places.canonical_location("Praia da Calheta")
    assert_equal "Rua Dr. João Abel de Freitas 12", Ocr::Places.canonical_location("Rua Dr. João Abel de Freitas 12")
  end

  def test_canonical_location_rejects_short_placeholders_and_generic_island_names
    assert_nil Ocr::Places.canonical_location("AB")
    assert_nil Ocr::Places.canonical_location("12345")
    assert_nil Ocr::Places.canonical_location("Não indicado")
    assert_nil Ocr::Places.canonical_location("Desconhecido")
    assert_nil Ocr::Places.canonical_location("Porto Santo")
    assert_nil Ocr::Places.canonical_location("Ilha do Porto Santo")
  end

  def test_canonical_location_does_not_merge_institution_and_school_names
    assert_includes Ocr::Places.prompt_catalogue.fetch("Escola da Vila"), "Escola da Vila - Porta 33"
    refute Ocr::Places.prompt_catalogue.key?("Porta 33")
    assert_equal "Porta 33", Ocr::Places.canonical_location("Porta 33")
    assert_equal "Porta33", Ocr::Places.canonical_location("Porta33")
    assert_equal "Escola da Vila", Ocr::Places.canonical_location("Escola da Vila – Porta 33")
    ["Escola da Vila", "Escola do Porto Santo"].each do |source_name|
      assert_equal source_name, Ocr::Places.canonical_location(source_name)
    end
  end

  def test_admission_keeps_event_without_using_organizer_credit_as_venue
    panels_data = [
      {
        "panel_id" => 1,
        "panel_review_reason" => "none",
        "panel_review_detail" => nil,
        "candidates" => [
          {
            "name" => "Workshop de Comunicação",
            "start_date" => "16/07/2025",
            "start_time" => "10:00",
            "end_date" => "16/07/2025",
            "end_time" => nil,
            "location" => "Casa do Povo de N. S. da Piedade",
            "description" => "Workshop prático de comunicação e atendimento ao público.",
            "category" => "Aprendizagem & Workshops",
            "organizer" => "Casa do Povo",
            "contact_email" => nil,
            "contact_tel" => nil,
            "price_type" => "Gratuito",
            "event_link1" => nil,
            "event_link2" => nil,
            "event_link3" => nil,
            "event_link4" => nil,
            "location_evidence" => "Casa do Povo de N. S. da Piedade",
            "location_source" => "main_text",
            "date_source" => "main_text",
            "price_source" => "main_text",
            "review_reason" => "none",
            "review_detail" => nil
          },
          {
            "name" => "Dia dos Avós",
            "start_date" => "26/07/2025",
            "start_time" => nil,
            "end_date" => nil,
            "end_time" => nil,
            "location" => "Biblioteca Municipal",
            "description" => "Comemoração do Dia dos Avós com programa a anunciar.",
            "category" => "Comunidade & Cultura",
            "organizer" => "Biblioteca Municipal",
            "contact_email" => nil,
            "contact_tel" => nil,
            "price_type" => nil,
            "event_link1" => nil,
            "event_link2" => nil,
            "event_link3" => nil,
            "event_link4" => nil,
            "location_evidence" => "BIBLIOTECA MUNICIPAL",
            "location_source" => "organizer_only",
            "date_source" => "main_text",
            "price_source" => "none",
            "review_reason" => "none",
            "review_detail" => nil
          }
        ]
      }
    ]

    result = Ocr::Admission.evaluate(panels_data, panel_ids: [1])

    workshop, celebration = result.fetch(:events)
    assert_equal ["Workshop de Comunicação", "Casa do Povo de Nossa Senhora da Piedade"], workshop.values_at(:name, :location)
    assert_equal ["Dia dos Avós", "26/07/2025", nil], celebration.values_at(:name, :start_date, :location)
    assert_empty result.fetch(:review_items)
  end

  def test_admission_downgrades_service_fee_to_desconhecido
    panels_data = [
      {
        "panel_id" => 1,
        "panel_review_reason" => "none",
        "panel_review_detail" => nil,
        "candidates" => [
          {
            "name" => "Concerto de Verão",
            "start_date" => "10/07/2025",
            "start_time" => "22:00",
            "end_date" => nil,
            "end_time" => nil,
            "location" => "Largo das Palmeiras",
            "description" => "Concerto noturno integrado nas festas de verão.",
            "category" => "Música",
            "organizer" => "Município",
            "contact_email" => nil,
            "contact_tel" => nil,
            "price_type" => "Pago",
            "event_link1" => nil,
            "event_link2" => nil,
            "event_link3" => nil,
            "event_link4" => nil,
            "location_evidence" => "Largo das Palmeiras",
            "location_source" => "banner",
            "date_source" => "main_text",
            "price_source" => "service_fee_only",
            "review_reason" => "none",
            "review_detail" => nil
          }
        ]
      }
    ]

    result = Ocr::Admission.evaluate(panels_data, panel_ids: [1])

    assert_equal 1, result[:events].length
    assert_equal "Desconhecido", result[:events].first[:price_type]
    assert_empty result[:review_items]
  end

  def test_admission_clears_unsupported_times_in_ready_and_held_candidates
    candidate = admission_candidate.merge("start_time" => "18:00", "end_time" => "20:00")

    ready = admit(candidate)
    assert_empty ready.fetch(:review_items)
    assert_equal [nil, nil], ready.fetch(:events).first.values_at(:start_time, :end_time)

    held = admit(candidate.merge("date_source" => "none"))
    assert_equal "missing_start_date", held.fetch(:review_items).first.fetch(:reason)
    assert_equal [nil, nil], held.fetch(:review_items).first.fetch(:candidate).values_at(:start_time, :end_time)
  end

  def test_admission_honors_panel_conflicting_main_text_and_illegible_flags_even_when_candidate_claims_ready
    panels_data = [
      {
        "panel_id" => 1,
        "panel_review_reason" => "conflicting_main_text",
        "panel_review_detail" => "Duas datas contraditórias no texto principal.",
        "candidates" => [
          {
            "name" => "Torneio de Golfe",
            "start_date" => "15/10/2026",
            "start_time" => "09:00",
            "end_date" => nil,
            "end_time" => nil,
            "location" => "Porto Santo Golfe",
            "description" => "Torneio com conflito no texto principal.",
            "category" => "Desporto",
            "organizer" => "Porto Santo Golfe",
            "contact_email" => nil,
            "contact_tel" => nil,
            "price_type" => "Desconhecido",
            "event_link1" => nil,
            "event_link2" => nil,
            "event_link3" => nil,
            "event_link4" => nil,
            "location_evidence" => "Porto Santo Golfe",
            "location_source" => "main_text",
            "date_source" => "main_text",
            "time_source" => "main_text",
            "price_source" => "none",
            "review_reason" => "none",
            "review_detail" => nil
          }
        ]
      }
    ]

    result = Ocr::Admission.evaluate(panels_data, panel_ids: [1])

    assert_empty result[:events]
    assert_equal 1, result[:review_items].length
    item = result[:review_items].first
    assert_equal "conflicting_main_text", item[:reason]
    assert_equal "Duas datas contraditórias no texto principal.", item[:message]
    assert_equal "Torneio de Golfe", item.dig(:candidate, :name)
    assert_equal "Porto Santo Golfe", item.dig(:candidate, :location)
    assert_equal "conflicting_main_text", item.dig(:trace, :panel_review_reason)
  end

  def test_admission_allows_banner_facts_from_the_whole_source
    base_candidate = {
      "name" => "Concerto do Porto Santo",
      "start_date" => "10/07/2025",
      "start_time" => "22:00",
      "end_date" => nil,
      "end_time" => nil,
      "location" => "Largo das Palmeiras",
      "description" => "Concerto integrado na programação de verão.",
      "category" => "Música",
      "organizer" => "Município",
      "contact_email" => nil,
      "contact_tel" => nil,
      "price_type" => "Desconhecido",
      "event_link1" => nil,
      "event_link2" => nil,
      "event_link3" => nil,
      "event_link4" => nil,
      "location_evidence" => "Largo das Palmeiras",
      "location_source" => "main_text",
      "date_source" => "main_text",
      "time_source" => "main_text",
      "price_source" => "none",
      "review_reason" => "none",
      "review_detail" => nil
    }

    direct_candidate = base_candidate.merge(
      "location_source" => "banner",
      "date_source" => "banner",
      "time_source" => "banner"
    )
    direct_result = Ocr::Admission.evaluate(
      [{"panel_id" => 1, "panel_review_reason" => "none", "panel_review_detail" => nil, "candidates" => [direct_candidate]}],
      panel_ids: [1]
    )
    assert_equal 1, direct_result[:events].length
    assert_empty direct_result[:review_items]
  end

  def test_admission_reviews_populated_date_without_source
    candidate = admission_candidate.merge("date_source" => "none", "end_date" => "11/07/2025")
    result = admit(candidate)
    assert_empty result[:events]
    assert_equal "missing_start_date", result[:review_items].first[:reason]
    assert_equal "10/07/2025", result[:review_items].first.dig(:candidate, :start_date)
    assert_nil result[:review_items].first.dig(:candidate, :end_date)
  end

  def test_admission_drops_unsupported_dates_from_candidates_held_for_another_reason
    candidate = admission_candidate.merge("date_source" => "none", "end_date" => "11/07/2025", "review_reason" => "missing_required_fields")

    result = admit(candidate)

    review = result.fetch(:review_items).first
    assert_equal "missing_required_fields", review.fetch(:reason)
    assert_equal [nil, nil], review.fetch(:candidate).values_at(:start_date, :end_date)
  end

  def test_admission_drops_organizer_only_venue_when_date_review_takes_precedence
    candidate = admission_candidate.merge("start_date" => nil, "date_source" => "none", "location_source" => "organizer_only")

    result = admit(candidate)

    assert_empty result.fetch(:events)
    review = result.fetch(:review_items).first
    assert_equal "missing_start_date", review.fetch(:reason)
    assert_nil review.fetch(:candidate).fetch(:location)
    assert_equal "Biblioteca Municipal", review.fetch(:trace).fetch(:location_evidence)
  end

  def test_admission_reviews_conflicting_known_location_evidence
    candidate = admission_candidate.merge("location" => "Biblioteca Municipal", "location_evidence" => "Auditório do CCC")
    result = admit(candidate)
    assert_empty result[:events]
    assert_equal "conflicting_location_evidence", result[:review_items].first[:reason]
    assert_equal "Biblioteca Municipal do Porto Santo", result[:review_items].first.dig(:candidate, :location)
  end

  def test_admission_drops_conflicting_venue_when_date_review_takes_precedence
    candidate = admission_candidate.merge("start_date" => nil, "date_source" => "none", "location_evidence" => "Auditório do CCC")

    result = admit(candidate)

    review = result.fetch(:review_items).first
    assert_equal "missing_start_date", review.fetch(:reason)
    assert_nil review.fetch(:candidate).fetch(:location)
    assert_equal "Auditório do CCC", review.fetch(:trace).fetch(:location_evidence)
  end

  def test_admission_keeps_aliases_and_unrecognised_free_text
    [
      {"location" => "Auditório do Centro Cultural e de Congressos", "location_evidence" => "Auditório do CCC"},
      {"location" => "Biblioteca Municipal", "location_evidence" => "Biblioteca Municipal, entrada norte"},
      {"location" => "Praia da Calheta", "location_evidence" => "PRAIA DA CALHETA"}
    ].each do |location|
      result = admit(admission_candidate.merge(location))
      assert_equal 1, result[:events].length
      assert_empty result[:review_items]
    end
  end

  def admission_candidate
    {
      "name" => "Concerto de Verão", "start_date" => "10/07/2025", "location" => "Biblioteca Municipal",
      "description" => "Concerto de verão na biblioteca.", "category" => "Música", "price_type" => "Desconhecido",
      "location_evidence" => "Biblioteca Municipal", "location_source" => "main_text", "date_source" => "main_text",
      "time_source" => "none", "price_source" => "none", "review_reason" => "none"
    }
  end

  def admit(candidate)
    Ocr::Admission.evaluate(
      [{"panel_id" => 1, "panel_review_reason" => "none", "candidates" => [candidate]}], panel_ids: [1]
    )
  end

  def test_unavailable_additional_text_routes_referenced_sources_to_review
    candidate = {
      "name" => "Workshop de Atendimento ao Público e Comunicação", "start_date" => "16/07/2025",
      "location" => "Casa do Povo de Nossa Senhora da Piedade", "description" => "Workshop de atendimento ao público e comunicação.",
      "category" => "Aprendizagem & Workshops", "organizer" => "Casa do Povo de Nossa Senhora da Piedade",
      "contact_tel" => "291 985 289", "price_type" => "Desconhecido",
      "location_evidence" => "CASA DO POVO DE NOSSA SENHORA DA PIEDADE", "location_source" => "additional_text",
      "date_source" => "main_text", "time_source" => "none", "price_source" => "none", "review_reason" => "none"
    }
    %w[location_source date_source time_source price_source].each do |source|
      modified = candidate.merge("location_source" => "main_text", "price_type" => "Gratuito", source => "additional_text")
      sibling = candidate.merge("location_source" => "main_text")
      panels = [{"panel_id" => 2, "panel_review_reason" => "none", "candidates" => [modified, sibling]}]
      [nil, "", "  \n"].each do |text|
        result = Ocr::Admission.evaluate(panels, panel_ids: [2], additional_text: text)
        assert_equal 1, result[:events].length
        assert_equal "unavailable_additional_text", result[:review_items].first[:reason]
        assert_equal "additional_text", result[:review_items].first.dig(:trace, source.to_sym)
      end
      result = Ocr::Admission.evaluate(panels, panel_ids: [2], additional_text: "Informação fornecida")
      assert_equal 2, result[:events].length
      assert_empty result[:review_items]
    end
  end
end
