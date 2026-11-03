# A live Sheets replacement shared by ingestion tests; no network or credentials.
class MemorySheets
  HEADERS = %w[added_at submitted_by name start_date start_time end_date end_time location description category organizer email phone price image link_1 link_2 link_3 link_4].freeze
  Response = Struct.new(:range, :values)
  Updates = Struct.new(:updated_range)
  AppendResponse = Struct.new(:updates)

  attr_reader :rows, :approved_rows, :reads
  attr_accessor :headers, :read_error, :append_failure_after

  def initialize
    @rows = []
    @approved_rows = []
    @reads = []
    @headers = HEADERS.dup
  end

  def get_values(_id, range)
    @reads << range
    raise read_error if read_error

    tab = range.include?("!") ? range.rpartition("!").first : "Events"
    data = (tab.delete("'") == "Approved") ? approved_rows : rows
    Response.new("#{tab}!A1:S#{data.length + 1}", [headers, *data.map(&:dup)])
  end

  def append_row(_id, range, row)
    raise "Write failed" if append_failure_after && rows.length >= append_failure_after

    tab = range.include?("!") ? range.rpartition("!").first : "Events"
    data = (tab.delete("'") == "Approved") ? approved_rows : rows
    data << row
    AppendResponse.new(Updates.new("#{tab}!A#{data.length + 1}:S#{data.length + 1}"))
  end
end
