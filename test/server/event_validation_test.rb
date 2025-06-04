require "minitest/autorun"
require_relative "../../lib/server/event_validation"

class TestEventValidation < Minitest::Test
  def setup
    @validator = EventValidation.new
  end

  def test_valid_event
    data = {
      name: "Valid Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed for valid data: #{result.errors.to_h}"
  end

  def test_invalid_name_too_short
    data = {
      name: "V",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for short name"
    assert_includes result.errors.to_h[:name], "must be at least 3 characters long"
  end

  def test_invalid_start_date_format
    data = {
      name: "Event Name",
      start_date: "01-12-2025", # Invalid format
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid start_date format"
    assert_includes result.errors.to_h[:start_date], "must be a valid date format (YYYY-MM-DD)"
  end

  def test_end_date_before_start_date
    data = {
      name: "Event Name",
      start_date: "2025-12-02",
      end_date: "2025-12-01",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail when end_date is before start_date"
    assert_includes result.errors.to_h[:end_date], "must be on or after start date"
  end

  def test_invalid_category
    data = {
      name: "Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Invalid Category",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid category"
    valid_categories = [
      "Música", "Comida", "Arte", "Natureza", "Saúde & Bem-Estar",
      "Desporto", "Aprendizagem & Workshops", "Comunidade & Cultura"
    ]
    assert_includes result.errors.to_h[:category], "must be one of: #{valid_categories.join(", ")}"
  end

  def test_valid_optional_fields_empty
    data = {
      name: "Valid Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      start_time: "",
      end_time: "",
      contact_email: "",
      contact_tel: "",
      price_type: "",
      event_link1: ""
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed when optional fields are empty: #{result.errors.to_h}"
  end

  def test_invalid_email
    data = {
      name: "Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      contact_email: "invalid-email"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid email"
    assert_includes result.errors.to_h[:contact_email], "must be a valid email address"
  end

  def test_invalid_phone_number_too_short
    data = {
      name: "Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      contact_tel: "12345"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for short phone number"
    assert_includes result.errors.to_h[:contact_tel], "must contain at least 7 digits"
  end

  def test_invalid_phone_number_characters
    data = {
      name: "Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      contact_tel: "123-abc"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for phone number with invalid characters"
    assert_includes result.errors.to_h[:contact_tel], "must contain only numbers, spaces, hyphens, parentheses, and plus sign"
  end

  def test_invalid_price_type
    data = {
      name: "Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      price_type: "Expensive"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid price_type"
    assert_includes result.errors.to_h[:price_type], "must be one of: Gratuito, Pago, Desconhecido"
  end

  def test_invalid_event_link
    data = {
      name: "Event Name",
      start_date: "2025-12-01",
      end_date: "2025-12-02",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer",
      event_link1: "invalid-url"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail for invalid event_link1"
    assert_includes result.errors.to_h[:event_link1], "must be a valid URL starting with http:// or https://"
  end

  def test_end_time_before_start_time_on_same_day
    data = {
      name: "Event Name",
      start_date: "2025-12-01",
      start_time: "14:00",
      end_date: "2025-12-01",
      end_time: "12:00",
      location: "Valid Location",
      description: "This is a valid event description.",
      category: "Música",
      organizer: "Valid Organizer"
    }
    result = @validator.call(data)
    assert result.failure?, "Validation should fail if end_time is before start_time on the same day"
    assert_includes result.errors.to_h[:end_time], "must be after start time when on the same date"
  end

  def test_valid_event_with_all_optional_fields
    data = {
      name: "Complete Event",
      start_date: "2025-12-01",
      start_time: "10:00",
      end_date: "2025-12-01",
      end_time: "18:00",
      location: "Full Location Details",
      description: "A very detailed description of the event, ensuring it meets length requirements.",
      category: "Aprendizagem & Workshops",
      organizer: "The Main Organizer",
      contact_email: "test@example.com",
      contact_tel: "+1 (555) 123-4567",
      price_type: "Pago",
      event_link1: "http://example.com/event1",
      event_link2: "https://example.com/event2",
      event_link3: "http://example.com/event3",
      event_link4: "https://example.com/event4"
      # event_image is not tested here as it's a hash and needs specific file handling tests
    }
    result = @validator.call(data)
    assert result.success?, "Validation should succeed for a complete valid event: #{result.errors.to_h}"
  end
end
