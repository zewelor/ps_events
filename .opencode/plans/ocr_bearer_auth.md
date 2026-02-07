# Plan: Dodanie autentykacji Bearer token dla endpointu OCR

## Cel
Umożliwienie zewnętrznym usługom programistycznym dostępu do endpointu `/events_ocr` za pomocą Bearer token authentication, z wykorzystaniem Registry Pattern dla elastycznej obsługi metod autentykacji.

## Architektura

### AuthRegistry - centralny rejestr metod autentykacji
- Rejestruje dostępne metody przy starcie serwera
- Próbuje każdej metody w kolejności rejestracji
- Zwraca `{authenticated: true, email: "..."}` lub `{authenticated: false, error: "..."}`
- Loguje dostępne metody przy starcie

### ApiAuthService - walidacja Bearer tokenów
- Parsuje `API_KEYS` (format CSV: `token:email,token2:email2`)
- Waliduje format przy ładowaniu (konkretne logi błędów)
- Metoda `validate_token(token)` - zwraca submitter lub nil
- Aktywny tylko gdy `API_KEYS` jest skonfigurowane

## Zadania

### 1. Utworzyć lib/server/auth_registry.rb
**Szczegóły implementacji:**
```ruby
module AuthRegistry
  extend self
  
  def register(name, handler)
    @handlers ||= {}
    @handlers[name] = handler
  end
  
  def available_methods
    @handlers&.keys || []
  end
  
  def authenticate(request)
    return {authenticated: false, error: "No authentication methods configured"} if @handlers.nil? || @handlers.empty?
    
    @handlers.each do |name, handler|
      result = handler.call(request)
      return result.merge(method: name) if result[:authenticated]
    end
    
    {authenticated: false, error: "Authentication failed"}
  end
end
```

### 2. Utworzyć lib/server/api_auth_service.rb
**Szczegóły implementacji:**
```ruby
module ApiAuthService
  extend self
  
  class InvalidFormatError < StandardError; end
  
  def load_keys!(csv_string)
    @keys = {}
    return if csv_string.nil? || csv_string.strip.empty?
    
    pairs = csv_string.split(',').map(&:strip)
    
    pairs.each_with_index do |pair, index|
      validate_pair!(pair, index)
      token, email = pair.split(':', 2).map(&:strip)
      @keys[token] = email
    end
    
    puts "✅ ApiAuthService: Loaded #{@keys.size} API key(s)"
  rescue InvalidFormatError => e
    puts "❌ ApiAuthService: Failed to load keys - #{e.message}"
    raise
  end
  
  def enabled?
    @keys && !@keys.empty?
  end
  
  def validate_token(token)
    return {authenticated: false} unless enabled?
    return {authenticated: false} if token.nil? || token.strip.empty?
    
    submitter = @keys[token]
    if submitter
      {authenticated: true, email: submitter}
    else
      {authenticated: false}
    end
  end
  
  private
  
  def validate_pair!(pair, index)
    if !pair.include?(':')
      raise InvalidFormatError, "Pair #{index + 1} missing colon separator: '#{pair}'"
    end
    
    token, email = pair.split(':', 2).map(&:strip)
    
    if token.nil? || token.empty?
      raise InvalidFormatError, "Pair #{index + 1} has empty token: '#{pair}'"
    end
    
    if email.nil? || email.empty?
      raise InvalidFormatError, "Pair #{index + 1} has empty email: '#{pair}'"
    end
    
    unless email.include?('@')
      raise InvalidFormatError, "Pair #{index + 1} has invalid email format: '#{email}'"
    end
  end
end
```

**Logi błędów (konkretne):**
- `"Pair 1 missing colon separator: 'invalid_pair'"`
- `"Pair 2 has empty token: ':email@example.com'"`
- `"Pair 1 has empty email: 'token:'"`
- `"Pair 1 has invalid email format: 'not_an_email'"`

### 3. Zmodyfikować bin/server.rb
**Zmiany:**

**a) Dodaj require na górze:**
```ruby
require_relative "../lib/server/auth_registry"
require_relative "../lib/server/api_auth_service"
```

**b) W configure do - rejestracja metod:**
```ruby
configure do
  # Rejestruj Google OAuth jako domyślną metodę
  AuthRegistry.register(:google_oauth, ->(request) {
    # Logika z obecnego endpointu:
    # 1. Sprawdź params[:google_token]
    # 2. Waliduj przez GoogleAuthService
    # 3. Sprawdź SecurityService
    # 4. Zwróć {authenticated: true, email: auth[:email]} lub {authenticated: false}
  })
  
  # Warunkowo rejestruj API Bearer
  if ENV['API_KEYS'] && !ENV['API_KEYS'].empty?
    begin
      ApiAuthService.load_keys!(ENV['API_KEYS'])
      
      AuthRegistry.register(:api_bearer, ->(request) {
        auth_header = request.env['HTTP_AUTHORIZATION']
        return {authenticated: false} unless auth_header&.start_with?('Bearer ')
        
        token = auth_header.sub('Bearer ', '').strip
        ApiAuthService.validate_token(token)
      })
      
      puts "✅ API Bearer authentication registered"
    rescue ApiAuthService::InvalidFormatError => e
      puts "❌ Failed to register API Bearer authentication: #{e.message}"
    end
  else
    puts "ℹ️ API Bearer authentication not registered (no API_KEYS configured)"
  end
  
  puts "Available auth methods: #{AuthRegistry.available_methods.join(', ')}"
end
```

**c) Zmodyfikuj endpoint `/events_ocr`:**
```ruby
post "/events_ocr" do
  auth_result = AuthRegistry.authenticate(request)
  
  unless auth_result[:authenticated]
    return json_error(auth_result[:error] || "Authentication required", 401)
  end
  
  user_email = auth_result[:email]
  method_used = auth_result[:method]
  puts "✅ Authenticated via #{method_used}: #{user_email}"
  
  # ... reszta logiki (bez zmian, używa user_email)
end
```

**d) Analogiczna zmiana w `/event_image` i `/add_event` (jeśli potrzebne):**
```ruby
post "/event_image" do
  unless settings.environment == :development
    auth_result = AuthRegistry.authenticate(request)
    unless auth_result[:authenticated]
      return json_error(auth_result[:error] || "Authentication required", 401)
    end
    # ... reszta
  end
  # ...
end
```

### 4. Zaktualizować .env.example
```bash
# API Authentication for external services
# Format: token1:email1@example.com,token2:email2@partner.pl
# Each token is paired with a submitter email for audit trail
API_KEYS=supersecrettoken123:api-service@example.com
```

### 5. Utworzyć testy test/server/api_auth_service_test.rb
```ruby
require "minitest/autorun"
require_relative "../../lib/server/api_auth_service"

class ApiAuthServiceTest < Minitest::Test
  def setup
    # Reset state before each test
    ApiAuthService.instance_variable_set(:@keys, nil)
  end
  
  def test_load_single_key
    ApiAuthService.load_keys!("token123:api@example.com")
    assert ApiAuthService.enabled?
    result = ApiAuthService.validate_token("token123")
    assert result[:authenticated]
    assert_equal "api@example.com", result[:email]
  end
  
  def test_load_multiple_keys
    ApiAuthService.load_keys!("token1:email1@x.com,token2:email2@y.pl")
    assert ApiAuthService.enabled?
    assert_equal "email1@x.com", ApiAuthService.validate_token("token1")[:email]
    assert_equal "email2@y.pl", ApiAuthService.validate_token("token2")[:email]
  end
  
  def test_invalid_token
    ApiAuthService.load_keys!("valid:email@x.com")
    result = ApiAuthService.validate_token("invalid")
    refute result[:authenticated]
  end
  
  def test_empty_token
    ApiAuthService.load_keys!("valid:email@x.com")
    result = ApiAuthService.validate_token("")
    refute result[:authenticated]
  end
  
  def test_nil_token
    ApiAuthService.load_keys!("valid:email@x.com")
    result = ApiAuthService.validate_token(nil)
    refute result[:authenticated]
  end
  
  def test_not_enabled_without_keys
    refute ApiAuthService.enabled?
    result = ApiAuthService.validate_token("anything")
    refute result[:authenticated]
  end
  
  def test_invalid_format_missing_colon
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      ApiAuthService.load_keys!("invalid_pair")
    end
    assert_includes error.message, "missing colon separator"
  end
  
  def test_invalid_format_empty_token
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      ApiAuthService.load_keys!(":email@x.com")
    end
    assert_includes error.message, "empty token"
  end
  
  def test_invalid_format_empty_email
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      ApiAuthService.load_keys!("token:")
    end
    assert_includes error.message, "empty email"
  end
  
  def test_invalid_format_bad_email
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      ApiAuthService.load_keys!("token:not_an_email")
    end
    assert_includes error.message, "invalid email format"
  end
end
```

### 6. Utworzyć testy test/server/auth_registry_test.rb
```ruby
require "minitest/autorun"
require_relative "../../lib/server/auth_registry"

class AuthRegistryTest < Minitest::Test
  def setup
    # Clear registry before each test
    AuthRegistry.instance_variable_set(:@handlers, nil)
  end
  
  def test_register_and_list_methods
    AuthRegistry.register(:test_method, ->(req) { {authenticated: true} })
    assert_equal [:test_method], AuthRegistry.available_methods
  end
  
  def test_authenticate_success
    AuthRegistry.register(:success, ->(req) { {authenticated: true, email: "test@x.com"} })
    result = AuthRegistry.authenticate(nil)
    assert result[:authenticated]
    assert_equal "test@x.com", result[:email]
    assert_equal :success, result[:method]
  end
  
  def test_authenticate_fallback_to_second_method
    AuthRegistry.register(:fails, ->(req) { {authenticated: false} })
    AuthRegistry.register(:succeeds, ->(req) { {authenticated: true, email: "test@x.com"} })
    result = AuthRegistry.authenticate(nil)
    assert result[:authenticated]
    assert_equal :succeeds, result[:method]
  end
  
  def test_authenticate_failure_when_all_fail
    AuthRegistry.register(:fails1, ->(req) { {authenticated: false} })
    AuthRegistry.register(:fails2, ->(req) { {authenticated: false} })
    result = AuthRegistry.authenticate(nil)
    refute result[:authenticated]
    assert_equal "Authentication failed", result[:error]
  end
  
  def test_authenticate_no_methods_configured
    result = AuthRegistry.authenticate(nil)
    refute result[:authenticated]
    assert_equal "No authentication methods configured", result[:error]
  end
end
```

### 7. Uruchomić testy
```bash
source dockerized.sh; rake test
```

### 8. Uruchomić rubocop
```bash
rubocop -a
```

## Przykład użycia

### Konfiguracja (.env):
```bash
API_KEYS=mysecret:api@my-service.com
```

### Request z Bearer token:
```bash
curl -X POST http://localhost:4567/events_ocr \
  -H "Authorization: Bearer mysecret" \
  -F "event_image=@plakat.jpg" \
  -F "use_event_image=on"
```

### Request z Google OAuth (bez zmian):
```bash
curl -X POST http://localhost:4567/events_ocr \
  -F "google_token=xxx" \
  -F "event_image=@plakat.jpg"
```

## Logi przy starcie serwera

**Gdy API_KEYS skonfigurowane:**
```
✅ ApiAuthService: Loaded 1 API key(s)
✅ API Bearer authentication registered
Available auth methods: google_oauth, api_bearer
```

**Gdy brak API_KEYS:**
```
ℹ️ API Bearer authentication not registered (no API_KEYS configured)
Available auth methods: google_oauth
```

**Gdy błędny format API_KEYS:**
```
❌ Failed to register API Bearer authentication: Pair 1 missing colon separator: 'invalid'
Available auth methods: google_oauth
```

## Decyzje projektowe

1. **Kolejność próbowania metod:** W kolejności rejestracji (google_oauth pierwszy, api_bearer drugi)
2. **Fallback:** Jeśli pierwsza metoda zwróci `authenticated: false`, próbujemy następną
3. **Email w API_KEYS:** Zawsze wymagany, używany jako submitter w Google Sheets
4. **Scope:** Na razie tylko `/events_ocr`, ale łatwo rozszerzyć na inne endpointy

## Dodatkowe uwagi

- **Bezpieczeństwo:** Tokeny powinny być długie (min. 32 znaki) i losowe
- **Rotacja kluczy:** Wystarczy zaktualizować ENV i restart serwera
- **Monitoring:** Logi pokazują która metoda autentykacji została użyta
- **Testy:** Endpoint tests wymagają aktualizacji aby testować nowe metody
