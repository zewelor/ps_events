require "cgi"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "test_helper"
require "tmpdir"

class AddEventFormSchemaTest < Minitest::Test
  def test_rendered_form_uses_constraints_from_the_schema
    root = File.expand_path("../..", __dir__)

    Dir.mktmpdir do |fixture_root|
      source = File.join(fixture_root, "events_listing")
      destination = File.join(fixture_root, "_site")
      FileUtils.copy_entry(File.join(root, "events_listing"), source)
      FileUtils.cp(File.join(__dir__, "../fixtures/event_span_events.csv"), File.join(fixture_root, "events.csv"))
      FileUtils.mkdir(File.join(fixture_root, "lib"))
      schema = JSON.parse(File.read(File.join(root, "lib/event_schema.json")))
      properties = schema.fetch("properties")
      properties.fetch("name").merge!("minLength" => 5, "maxLength" => 175)
      properties.fetch("description").merge!("minLength" => 17, "maxLength" => 1200)
      properties.fetch("location").merge!("minLength" => 4, "maxLength" => 70)
      properties.fetch("organizer")["maxLength"] = 90
      properties.fetch("organizer")["pattern"] = '^Orquestra & "Coro"$'
      properties.fetch("category")["enum"] = ['Literatura & "Poesia"', "Saúde & Bem-Estar", "Arte"]
      properties.fetch("price_type")["enum"] = ["Pago", "Donativo", "Gratuito"]
      properties.fetch("responsibility_agreement")["const"] = 'aceite & "confirmado"'
      schema["required"] = %w[description location category organizer end_date contact_email event_link3]
      File.write(File.join(fixture_root, "lib/event_schema.json"), JSON.generate(schema))

      stdout, stderr, status = Open3.capture3("bundle", "exec", "jekyll", "build", "--source", source, "--destination", destination)
      assert status.success?, "Jekyll build failed:\n#{stdout}\n#{stderr}"

      html = File.read(File.join(destination, "add_event/index.html"))
      {"name" => [5, 175], "description" => [17, 1200], "location" => [4, 70], "organizer" => [nil, 90]}.each do |field, (min_length, max_length)|
        tag = control(html, field)
        if min_length
          assert_includes tag, %(minlength="#{min_length}")
        else
          refute_includes tag, "minlength="
        end
        assert_includes tag, %(maxlength="#{max_length}")
      end
      properties.keys.each do |field|
        next if field == "responsibility_agreement"

        required = schema.fetch("required").include?(field)
        assert_equal required, control(html, field).match?(/\srequired\s/), field
        label = html[%r{<label\b[^>]*\bfor="#{field}"[^>]*>(.*?)</label>}m, 1]
        assert_equal required, label.include?("*"), field
      end
      {"contact_email" => 100, "contact_tel" => 20, "event_link3" => 200}.each do |field, max_length|
        assert_includes control(html, field), %(maxlength="#{max_length}")
      end
      %w[organizer contact_email contact_tel event_link1 event_link2 event_link3 event_link4].each do |field|
        pattern = control(html, field)[/\spattern="([^"]*)"/, 1]
        assert_equal properties.fetch(field).fetch("pattern"), CGI.unescapeHTML(pattern.to_s), field
      end
      %w[start_date start_time end_date end_time].each do |field|
        refute_includes control(html, field), "pattern="
      end
      assert_equal [["", "Selecione uma categoria"], ['Literatura & "Poesia"', 'Literatura & "Poesia"'], ["Saúde & Bem-Estar", "Saúde e bem-estar"], ["Arte", "Arte"]], options(html, "category")
      assert_equal [%w[Pago Pago], %w[Donativo Donativo], %w[Gratuito Gratuito]], options(html, "price_type")
      agreement = control(html, "responsibility_agreement")
      assert_match(/\srequired\s/, agreement)
      assert_equal properties.fetch("responsibility_agreement").fetch("const"), CGI.unescapeHTML(agreement[/\svalue="([^"]*)"/, 1].to_s)
      assert_includes html, "Breve descrição (entre 17 e 1200 caracteres)"
      assert_includes html, "Nome ou título do evento (entre 5 e 175 caracteres)"
      assert_empty Dir.glob(File.join(destination, "**/event_schema.json"))
    end
  end

  private

  def control(html, field)
    html[/<(?:input|textarea|select)\b[^>]*\bid="#{field}"[^>]*>/]
  end

  def options(html, field)
    select = html[%r{<select\b[^>]*\bid="#{field}"[^>]*>(.*?)</select>}m, 1]
    select.scan(%r{<option\b[^>]*\bvalue="([^"]*)"[^>]*>(.*?)</option>}).map do |option|
      option.map { |part| CGI.unescapeHTML(part.strip) }
    end
  end
end
