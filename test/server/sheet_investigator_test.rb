require "minitest/autorun"
require_relative "../../lib/server/sheet_investigator"
require_relative "../../lib/server/sheet_report"

class TestSheetInvestigator < Minitest::Test
  # Pinned as a literal on purpose: deriving it from REQUIRED_COLUMNS would let
  # a missing or misspelled column in that constant pass unnoticed. Namespaced
  # in the class so it does not leak onto Object in the single-process suite.
  SHEET_HEADERS = %w[
    added_at submitted_by name start_date start_time end_date end_time location
    description category organizer email phone price image link_1 link_2 link_3 link_4
  ].freeze

  HEADERS = SHEET_HEADERS

  def setup
    @investigator = build_investigator
  end

  def test_required_columns_cover_everything_but_the_optional_links
    # approved!A:O stops before the link columns, and added_at is not reported.
    optional = %w[added_at link_1 link_2 link_3 link_4]

    assert_equal (HEADERS - optional).sort, SheetInvestigator::REQUIRED_COLUMNS.sort
  end

  def test_resolves_columns_from_the_sheet_header
    # Columns are addressed by name, so their position in the sheet is irrelevant.
    reordered = HEADERS.reverse
    rows = [row_for("Festa da Escola", "9/10/2026", "Escola da Vila", headers: reordered)]

    investigator = SheetInvestigator.new(rows, headers: reordered)
    event = investigator.all.first

    assert_equal "Festa da Escola", event.name
    assert_equal "9/10/2026", event.start_date
    assert_equal "Escola da Vila", event.location
  end

  def test_rejects_unexpected_header
    error = assert_raises(RuntimeError) do
      SheetInvestigator.new([], headers: ["name", "start_date"])
    end

    assert_match(/Missing columns/, error.message)
  end

  def test_ignores_blank_rows
    investigator = SheetInvestigator.new([[], nil, [""]], headers: HEADERS)

    assert_empty investigator.all
  end

  def test_with_image_filters_on_flyer_uuid
    matching = investigator_with_image("uuid-a").with_image("uuid-a")

    assert_equal 1, matching.size
    assert_equal "uuid-a", matching.first.image
  end

  def test_matching_searches_name_and_description
    assert_equal ["Festa da Escola"], @investigator.matching("escola").map(&:name)
    # Only the first row mentions "projeto artístico" in its description.
    assert_equal ["Festa da Escola"], @investigator.matching("projeto artístico").map(&:name)
  end

  def test_matching_does_not_straddle_two_columns
    # "Festa" ends the name and "da Praça" starts the location, but neither
    # field contains "festa da" on its own.
    investigator = build_investigator([row_for("Festa", "9/10/2026", "da Praça do Município")])

    assert_empty investigator.matching("festa da")
    assert_equal 1, investigator.matching("festa").size
  end

  def test_select_combines_filters_instead_of_overriding_them
    rows = [
      row_for("Festa da Escola", "9/10/2026", "Escola da Vila", image: "uuid-a"),
      row_for("Festa do Pão", "9/10/2026", "Praça do Município", image: "uuid-b")
    ]
    investigator = build_investigator(rows)

    # Both filters apply: only the first row matches the image and the text.
    assert_equal ["Festa da Escola"], investigator.select(image: "uuid-a", text: "escola").map(&:name)
    # The text filter is honoured too, so nothing survives the mismatch.
    assert_empty investigator.select(image: "uuid-a", text: "pão")
  end

  def test_select_without_filters_returns_everything
    assert_equal 3, @investigator.select.size
  end

  def test_on_date_includes_events_spanning_that_day
    investigator = build_investigator([row_for("Mostra do Pão", "16/10/2026", "Praça", end_date: "18/10/2026")])

    assert_empty investigator.on_date(Date.new(2026, 10, 15))
    assert_equal 1, investigator.on_date(Date.new(2026, 10, 17)).size
    assert_empty investigator.on_date(Date.new(2026, 10, 19))
  end

  def test_exact_duplicates_group_same_name_and_start_date
    rows = [row_for("Festa", "9/10/2026"), row_for("Festa", "9/10/2026", "Outro sítio")]
    groups = SheetInvestigator.new(rows, headers: HEADERS).exact_duplicates

    assert_equal 1, groups.size
    assert_equal 2, groups.first.size
  end

  def test_exact_duplicates_group_rows_that_differ_only_in_date_padding
    # The sheet mixes "5/6/2026" and "05/06/2026" for the same event.
    rows = [row_for("Festa", "5/6/2026"), row_for("Festa", "05/06/2026")]
    groups = SheetInvestigator.new(rows, headers: HEADERS).exact_duplicates

    assert_equal 1, groups.size
    assert_equal 2, groups.first.size
  end

  def test_suspicious_duplicates_group_rows_that_differ_only_in_date_padding
    rows = [
      row_for("Concurso de Vinhos", "2/5/2026"),
      row_for("IX Concurso de Vinhos", "02/05/2026")
    ]

    assert_equal 1, SheetInvestigator.new(rows, headers: HEADERS).suspicious_duplicates.size
  end

  def test_suspicious_duplicates_catch_rewording_of_the_same_booking
    rows = [
      row_for("Concurso de Vinhos", "2/5/2026"),
      row_for("IX Concurso de Vinhos", "2/5/2026")
    ]
    groups = SheetInvestigator.new(rows, headers: HEADERS).suspicious_duplicates

    assert_equal 1, groups.size
    assert_equal 2, groups.first.size
  end

  def test_matching_with_blank_text_returns_everything
    assert_equal 3, @investigator.matching("").size
  end

  def test_suspicious_duplicates_ignore_surrounding_whitespace_in_the_key
    rows = [
      row_for("Concurso de Vinhos", "2/5/2026", "Praça do Município", category: "Comida"),
      row_for("IX Concurso de Vinhos", "2/5/2026", " praça do município ", category: " comida ")
    ]

    assert_equal 1, SheetInvestigator.new(rows, headers: HEADERS).suspicious_duplicates.size
  end

  def test_suspicious_duplicates_ignore_different_categories
    rows = [
      row_for("Festa", "9/10/2026", category: "Comida"),
      row_for("Baile", "9/10/2026", category: "Música")
    ]

    assert_empty SheetInvestigator.new(rows, headers: HEADERS).suspicious_duplicates
  end

  def test_date_range_collapses_single_day_events
    same_day = row_for("Jantar", "23/10/2026")
    spanning = row_for("Mostra", "16/10/2026", end_date: "18/10/2026")

    assert_equal "23/10/2026", investigator_for(same_day).all.first.date_range
    assert_equal "16/10/2026 -> 18/10/2026", investigator_for(spanning).all.first.date_range
  end

  def test_schema_params_preserve_date_values
    ["9/10/2026", "09/10/26", "09/10/2026junk"].each do |date|
      event = investigator_for(row_for("Festa", date, end_date: date)).all.first

      assert_equal [date, date], event.schema_params.values_at(:start_date, :end_date)
    end
  end

  def test_validation_reports_malformed_dates_without_changing_them
    %i[start_date end_date].each do |field|
      ["09/10/26", "09/10/2026junk", "09/10/2026\njunk", "31/02/2026"].each do |date|
        row = if field == :start_date
          row_for("Festa", date)
        else
          row_for("Festa", "9/10/2026", end_date: date)
        end
        failures = investigator_for(row).validation_failures

        assert_equal 1, failures.size
        event, errors = failures.first
        assert_equal date, event.public_send(field)
        assert errors.key?(field), "Expected #{field} error for #{date.inspect}"
      end
    end
  end

  def test_malformed_dates_do_not_match_valid_dates_or_duplicates
    investigator = build_investigator([
      row_for("Festa", "09/10/2026"),
      row_for("Festa", "09/10/2026junk")
    ])

    assert_equal [2], investigator.on_date(Date.new(2026, 10, 9)).map(&:row_number)
    assert_empty investigator.exact_duplicates
  end

  def test_validation_failures_reports_real_problems_only
    rows = [
      row_for("Evento válido", "9/10/2026"),
      row_for("Preço inválido", "9/10/2026", price: "Grátis")
    ]
    failures = SheetInvestigator.new(rows, headers: HEADERS).validation_failures

    assert_equal 1, failures.size
    event, errors = failures.first
    assert_equal "Preço inválido", event.name
    assert errors.key?(:price_type)
  end

  def test_single_digit_day_is_not_a_validation_failure
    # Published rows almost always use a single-digit day and the site parses
    # them fine, so this must not be reported.
    assert_empty @investigator.validation_failures
  end

  private

  def build_investigator(rows = default_rows, headers: HEADERS)
    SheetInvestigator.new(rows, headers: headers)
  end

  def default_rows
    [
      row_for("Festa da Escola", "9/10/2026", "Escola da Vila", description: "comunidade e projeto artístico"),
      row_for("VII Mostra do Pão", "16/10/2026", "Praça do Município"),
      row_for("Jantar Rosa", "23/10/2026", "Hotel The Navigator Colombus")
    ]
  end

  def investigator_with_image(uuid)
    build_investigator(
      [
        row_for("Com imagem", "9/10/2026", "Escola da Vila", image: uuid),
        row_for("Sem imagem", "10/10/2026", "Praça do Município", image: "outra")
      ]
    )
  end

  def investigator_for(*rows)
    build_investigator(rows)
  end

  def row_for(name, start_date, location = "Local", end_date: "", category: "Comunidade & Cultura",
    description: "Descrição do evento com texto suficiente.", organizer: "Organização",
    price: "Desconhecido", image: "", submitted_by: "alguem@example.com", headers: HEADERS)
    values = {
      "name" => name,
      "start_date" => start_date,
      "start_time" => "",
      "end_date" => end_date,
      "end_time" => "",
      "location" => location,
      "description" => description,
      "category" => category,
      "organizer" => organizer,
      "email" => "",
      "phone" => "",
      "price" => price,
      "image" => image,
      "submitted_by" => submitted_by
    }

    headers.map { |header| values[header] }
  end
end

class TestSheetReport < Minitest::Test
  def test_events_table_reports_totals
    output = report.events_table(@investigator.all, limit: 10)

    assert_match(/row.*dates.*name.*location.*category.*image.*submitted_by/, output)
    assert_match(/Showing 2 of 2 matching events \(2 rows in the sheet\)\./, output)
  end

  def test_events_table_truncates_to_the_limit
    output = report.events_table(@investigator.all, limit: 1)

    assert_match(/Showing 1 of 2 matching events/, output)
  end

  def test_events_table_keeps_column_alignment_for_long_date_ranges
    spanning = investigator_for(
      row_for("Mostra do Pão", "16/10/2026", "Praça do Município", end_date: "18/10/2026", start_time: "21:00")
    )
    output = SheetReport.new(spanning).events_table(spanning.all, limit: 5)
    dates_cell = output.lines[1].split(" | ")[1]

    # "16/10/2026 -> 18/10/2026 21:00" is 30 chars and would push every later
    # column out of line, so it has to be clipped to the 25-wide column.
    assert_equal 25, dates_cell.length
    assert dates_cell.end_with?("…")
  end

  def test_duplicates_section_reports_both_kinds
    output = report.duplicates_section

    assert_match(/== Exact duplicates \(same name \+ start date\) ==/, output)
    assert_match(/== Suspicious duplicates/, output)
  end

  def test_duplicates_section_can_be_scoped_to_a_filtered_subset
    rows = [
      row_for("Festa", "9/10/2026", "Escola da Vila"),
      row_for("Festa", "9/10/2026", "Escola da Vila"),
      row_for("Baile", "10/10/2026", "Praça do Município"),
      row_for("Baile", "10/10/2026", "Praça do Município")
    ]
    investigator = investigator_for(*rows)
    output = SheetReport.new(investigator).duplicates_section(investigator.matching("baile"))

    # Only the "Baile" group should be reported, not the unrelated "Festa" pair.
    assert_match(/row 4 \| .*Baile/, output)
    refute_match(/Festa/, output)
  end

  def test_invalid_section_strips_the_json_schema_uuid
    failing = investigator_for(row_for("Preço inválido", "9/10/2026", price: "Grátis"))
    output = SheetReport.new(failing).invalid_section

    refute_match(/in schema [0-9a-f-]{36}/, output)
    assert_match(/price_type:/, output)
  end

  private

  def setup
    @investigator = investigator_for(
      row_for("Festa da Escola", "9/10/2026", "Escola da Vila"),
      row_for("Jantar Rosa", "23/10/2026", "Hotel The Navigator Colombus")
    )
    @report = SheetReport.new(@investigator)
  end

  attr_reader :report

  def investigator_for(*rows)
    SheetInvestigator.new(rows, headers: TestSheetInvestigator::SHEET_HEADERS)
  end

  def row_for(name, start_date, location = "Local", start_time: "", end_date: "",
    price: "Desconhecido")
    values = {
      "name" => name,
      "start_date" => start_date,
      "start_time" => start_time,
      "end_date" => end_date,
      "end_time" => "",
      "location" => location,
      "description" => "Descrição do evento com texto suficiente.",
      "category" => "Comunidade & Cultura",
      "organizer" => "Organização",
      "email" => "",
      "phone" => "",
      "price" => price,
      "image" => "",
      "submitted_by" => "alguem@example.com"
    }

    TestSheetInvestigator::SHEET_HEADERS.map { |header| values[header] }
  end
end
