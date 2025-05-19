# Helper filters for category metadata (color and icon) in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module CategoryHelpers
    # Central metadata mapping for categories
    CATEGORY_META = {
      "Music" => {"color" => "#F08080", "icon" => "icon-music"},
      "Food" => {"color" => "#FFA07A", "icon" => "icon-food"},
      "Art" => {"color" => "#40E0D0", "icon" => "icon-art"},
      "Nature" => {"color" => "#20B2AA", "icon" => "icon-nature"},
      "Health & Wellness" => {"color" => "#98FB98", "icon" => "icon-health"},
      "Sports" => {"color" => "#FF7F50", "icon" => "icon-sports"},
      "Learning & Workshops" => {"color" => "#ADD8E6", "icon" => "icon-learning"},
      "Community & Culture" => {"color" => "#DAA520", "icon" => "icon-community"}
    }

    # Return a hex color code based on the category name
    def category_color(category)
      category_metadata(category)["color"]
    end

    # Return an icon placeholder (CSS class or markup) based on category
    def category_icon(category)
      category_metadata(category)["icon"]
    end

    # Combined metadata: returns a hash with color and icon keys
    def category_metadata(category)
      CATEGORY_META.fetch(category.to_s, {"color" => "#ADD8E6", "icon" => ""})
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryHelpers)
