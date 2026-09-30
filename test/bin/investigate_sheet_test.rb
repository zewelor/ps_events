require "minitest/autorun"
require "open3"

class InvestigateSheetCliTest < Minitest::Test
  def test_custom_range_row_numbers_are_preserved_across_all_report_sections
    stdout, stderr, status = run_cli("--range", "EventTable", "--date", "3/10/2026", "--duplicates", "--invalid")

    assert status.success?, stderr
    assert_equal [11, 13, 14, 16], stdout.scan(/^\s*(\d+) \|/).flatten.map(&:to_i)
    assert_includes stdout, "row 11 | 3/10/2026 | Festa"
    assert_includes stdout, "row 13 | 03/10/2026 | Festa"
    assert_includes stdout, "row 14: Preço inválido"
    assert_includes stdout, "Showing 4 of 4 matching events (5 rows in the sheet)."
    refute_includes stdout, "Outro dia"
  end

  def test_configured_range_preserves_the_offset_with_a_zero_padded_date_filter
    stdout, stderr, status = run_cli("--date", "03/10/2026")

    assert status.success?, stderr
    assert_equal [11, 13, 14, 16], stdout.scan(/^\s*(\d+) \|/).flatten.map(&:to_i)
  end

  def test_malformed_date_filters_fail_before_reading_the_sheet
    ["03/10/26", "03/10/2026junk", "03/10/2026\njunk", "31/02/2026"].each do |date|
      stdout, stderr, status = run_cli("--date", date, "--duplicates", "--invalid", expect_no_read: true)

      refute status.success?, "Expected #{date.inspect} to fail"
      assert_includes stderr, "Invalid --date"
      assert_empty stdout
    end
  end

  private

  def run_cli(*arguments, expect_no_read: false)
    command = [
      "bundle", "exec", "ruby",
      "-r", File.expand_path("../fixtures/inspection_sheet.rb", __dir__),
      File.expand_path("../../bin/investigate_sheet", __dir__),
      *arguments
    ]
    Open3.capture3({"EXPECT_NO_SHEET_READ" => expect_no_read ? "1" : nil}, *command)
  end
end
