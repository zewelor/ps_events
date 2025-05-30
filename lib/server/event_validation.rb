require "dry/validation"

# Event validation contract using dry-validation
class EventValidation < Dry::Validation::Contract
  params do
    required(:name).filled(:string)
    required(:start_date).filled(:string)
    optional(:start_time).maybe(:string)
    required(:end_date).filled(:string)
    optional(:end_time).maybe(:string)
    required(:location).filled(:string)
    required(:description).filled(:string)
    required(:category).filled(:string)
    required(:organizer).filled(:string)
    optional(:contact_email).maybe(:string)
    optional(:contact_tel).maybe(:string)
    optional(:price_type).maybe(:string)
    optional(:event_link1).maybe(:string)
    optional(:event_link2).maybe(:string)
    optional(:event_link3).maybe(:string)
    optional(:event_link4).maybe(:string)
    optional(:event_image).maybe(:hash)
  end

  rule(:contact_email) do
    if key? && value && !value.empty?
      unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match?(value)
        key.failure("must be a valid email address")
      end
    end
  end

  rule(:start_date) do
    if /\A\d{4}-\d{2}-\d{2}\z/.match?(value)
      begin
        Date.strptime(value, "%Y-%m-%d")
      rescue ArgumentError
        key.failure("must be a valid date (e.g., month between 01-12, day between 01-31)")
      end
    else
      key.failure("must be a valid date format (YYYY-MM-DD)")
    end
  end

  rule(:start_time) do
    if key? && value && !value.empty?
      begin
        Time.parse(value)
      rescue ArgumentError
        key.failure("must be a valid time format (HH:MM)")
      end
    end
  end

  rule(:end_date) do
    if /\A\d{4}-\d{2}-\d{2}\z/.match?(value)
      begin
        end_date = Date.strptime(value, "%Y-%m-%d")
        start_val = values[:start_date]
        start_date = nil
        if start_val && /\A\d{4}-\d{2}-\d{2}\z/.match?(start_val) # Ensure start_val is also in correct format before parsing
          begin
            start_date = Date.strptime(start_val, "%Y-%m-%d")
          rescue ArgumentError
            # This should ideally not happen if start_date rule passed
          end
        end

        if start_date && end_date < start_date
          key.failure("must be on or after start date")
        end
      rescue ArgumentError
        key.failure("must be a valid date (e.g., month between 01-12, day between 01-31)")
      end
    else
      key.failure("must be a valid date format (YYYY-MM-DD)")
    end
  end

  rule(:end_time) do
    if key? && value && !value.empty?
      begin
        Time.parse(value)
      rescue ArgumentError
        key.failure("must be a valid time format (HH:MM)")
      end
    end
  end

  rule(:start_date, :start_time, :end_date, :end_time) do
    if values[:start_date] && values[:end_date]
      begin
        start_date_obj = Date.strptime(values[:start_date], "%Y-%m-%d")
        end_date_obj = Date.strptime(values[:end_date], "%Y-%m-%d")

        if start_date_obj == end_date_obj && values[:start_time] && values[:end_time] &&
            !values[:start_time].empty? && !values[:end_time].empty?
          start_time = Time.parse(values[:start_time])
          end_time = Time.parse(values[:end_time])

          if end_time <= start_time
            key(:end_time).failure("must be after start time when on the same date")
          end
        end
      rescue ArgumentError
      end
    end
  end

  rule(:name) do
    if value.length < 3
      key.failure("must be at least 3 characters long")
    elsif value.length > 200
      key.failure("must be no more than 200 characters long")
    end
  end

  rule(:description) do
    if value.length < 10
      key.failure("must be at least 10 characters long")
    elsif value.length > 1000
      key.failure("must be no more than 1000 characters long")
    end
  end

  rule(:location) do
    if value.length < 3
      key.failure("must be at least 3 characters long")
    elsif value.length > 100
      key.failure("must be no more than 100 characters long")
    end
  end

  rule(:organizer) do
    if value.length < 2
      key.failure("must be at least 2 characters long")
    elsif value.length > 100
      key.failure("must be no more than 100 characters long")
    end
  end

  rule(:category) do
    valid_categories = [
      "Música", "Comida", "Arte", "Natureza", "Saúde & Bem-Estar",
      "Desporto", "Aprendizagem & Workshops", "Comunidade & Cultura"
    ]

    unless valid_categories.include?(value)
      key.failure("must be one of: #{valid_categories.join(", ")}")
    end
  end

  rule(:event_link1, :event_link2, :event_link3, :event_link4) do
    [values[:event_link1], values[:event_link2], values[:event_link3], values[:event_link4]].each_with_index do |link, index|
      if link && !link.empty?
        unless /\Ahttps?:\/\/.+\z/i.match?(link)
          key(:"event_link#{index + 1}").failure("must be a valid URL starting with http:// or https://")
        end
      end
    end
  end

  rule(:contact_tel) do
    if key? && value && !value.empty?
      unless /\A[\d\s\-\(\)\+]+\z/.match?(value)
        key.failure("must contain only numbers, spaces, hyphens, parentheses, and plus sign")
      end

      if value.gsub(/[\s\-\(\)\+]/, "").length < 7
        key.failure("must contain at least 7 digits")
      end
    end
  end

  rule(:price_type) do
    if key? && value && !value.empty?
      valid_price_types = ["Free", "Paid", "Unknown"]
      unless valid_price_types.include?(value)
        key.failure("must be one of: #{valid_price_types.join(", ")}")
      end
    end
  end
end
