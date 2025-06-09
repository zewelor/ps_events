require "minitest/autorun"
require "capybara/minitest"
require "capybara"
require "selenium-webdriver"
require_relative "../../bin/server"

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = :headless_chrome
Capybara.server = :puma, {Silent: true}

class AddEventBrowserTest < Minitest::Test
  include Capybara::DSL

  class DummySheets
    attr_reader :rows

    def initialize
      @rows = []
    end

    def append_row(_spreadsheet_id, _range, data)
      @rows << data
    end
  end

  def setup
    root = File.expand_path("../..", __dir__)
    system(
      "jekyll build -s events_listing -d tmp/test_site",
      chdir: root,
      env: {"JEKYLL_ENV" => "development", "BACKEND_HOST" => Capybara.server_url}
    )

    Sinatra::Application.settings.google_sheets = DummySheets.new

    Capybara.app = Rack::Builder.new do
      use Rack::Static, urls: [""], root: File.expand_path("../tmp/test_site", __dir__), index: "index.html"
      run Sinatra::Application
    end
  end

  def teardown
    FileUtils.rm_rf(File.expand_path("../tmp/test_site", __dir__))
    Capybara.reset_sessions!
  end

  def test_add_event
    GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
      visit "/add_event/"
      fill_in "name", with: "Browser Event"
      fill_in "description", with: "Descrição de teste"
      select "Música", from: "category"
      fill_in "organizer", with: "Tester"
      fill_in "location", with: "Lisboa"
      fill_in "start_date", with: "2025-12-01"
      fill_in "end_date", with: "2025-12-02"
      find("#responsibility_agreement").set(true)
      fill_in "google_token", with: "token"
      click_button "Adicionar Evento"
      assert_selector "#toast-container", text: "Evento \"Browser Event\" adicionado com sucesso!"
      assert_equal 1, Sinatra::Application.settings.google_sheets.rows.size
    end
  end
end
