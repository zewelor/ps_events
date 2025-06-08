class SecurityService
  WHITELISTED_EMAILS = [
    "admin@example.com",
    "moderator@example.com"
  ].freeze

  def self.is_valid?(email)
    return false unless email && !email.strip.empty?

    WHITELISTED_EMAILS.include?(email.strip.downcase)
  end
end
