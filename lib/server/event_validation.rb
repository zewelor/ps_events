require "dry/validation"

# Event validation contract using dry-validation
class EventValidation < Dry::Validation::Contract
  params do
    required(:name).filled(:string)
    required(:start_date).filled(:string)
    optional(:end_date).maybe(:string)
    required(:location).filled(:string)
    required(:description).filled(:string)
    required(:category).filled(:string)
    required(:organizer).filled(:string)
    required(:contact_email).filled(:string)
    optional(:contact_tel).maybe(:string)
    optional(:price_type).maybe(:string)
    optional(:event_link1).maybe(:string)
    optional(:event_link2).maybe(:string)
    optional(:event_link3).maybe(:string)
    optional(:event_link4).maybe(:string)
  end

  rule(:contact_email) do
    unless /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.match?(value)
      key.failure("must be a valid email address")
    end
  end

  rule(:start_date) do
    DateTime.parse(value)
  rescue ArgumentError
    key.failure("must be a valid date and time format")
  end

  rule(:end_date) do
    if key? && value && !value.empty?
      begin
        end_dt = DateTime.parse(value)
        start_dt = DateTime.parse(values[:start_date]) if values[:start_date]

        if start_dt && end_dt < start_dt
          key.failure("must be after start date")
        end
      rescue ArgumentError
        key.failure("must be a valid date and time format")
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
      "Arts & Culture", "Business & Professional", "Community & Social",
      "Education & Learning", "Entertainment", "Family & Kids",
      "Food & Drink", "Health & Wellness", "Music", "Outdoors & Adventure",
      "Religion & Spirituality", "Science & Technology", "Sports & Fitness",
      "Travel & Tourism", "Other"
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
      # Basic phone number validation - allows digits, spaces, hyphens, parentheses, and plus sign
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
      valid_price_types = ["Free", "Paid", "Donation", "Members Only"]
      unless valid_price_types.include?(value)
        key.failure("must be one of: #{valid_price_types.join(", ")}")
      end
    end
  end
end
