# Helper filters for category metadata (color and icon) in Jekyll
# Place this file in the _plugins directory of your Jekyll site
module Jekyll
  module CategoryHelpers
    # Central metadata mapping for categories
    CATEGORY_META = {
      "Music" => {"color" => "#F08080", "icon" => '<path d="M12 21C10.3431 21 9 19.6569 9 18V10C9 8.34315 10.3431 7 12 7C13.6569 7 15 8.34315 15 10V18C15 19.6569 13.6569 21 12 21ZM12 7V3" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M15 18C15 19.6569 16.3431 21 18 21C19.6569 21 21 19.6569 21 18V8C21 6.34315 19.6569 5 18 5C16.3431 5 15 6.34315 15 8V18Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'},
      "Food" => {"color" => "#FFA07A", "icon" => '<path d="M3 3L15 3C16.1046 3 17 3.89543 17 5V21C17 21.5523 16.5523 22 16 22H14C13.4477 22 13 21.5523 13 21V13H5C3.89543 13 3 12.1046 3 11V3Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M21 3L9 3C7.89543 3 7 3.89543 7 5V21C7 21.5523 7.44772 22 8 22H10C10.5523 22 11 21.5523 11 21V13H19C20.1046 13 21 12.1046 21 11V3Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'},
      "Art" => {"color" => "#40E0D0", "icon" => '<path d="M12 15C15.3137 15 18 12.3137 18 9C18 5.68629 15.3137 3 12 3C8.68629 3 6 5.68629 6 9C6 12.3137 8.68629 15 12 15Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M19 17L15 15" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M5 17L9 15" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M12 15V21" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M12 21H9M12 21H15" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'},
      "Nature" => {"color" => "#20B2AA", "icon" => '<path d="M17 21L12 16L7 21" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M12 16V3" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M12 3C14.2091 3 16 4.79086 16 7C16 9.20914 14.2091 11 12 11C9.79086 11 8 9.20914 8 7C8 4.79086 9.79086 3 12 3Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'},
      "Health & Wellness" => {"color" => "#98FB98", "icon" => '<path d="M12 22C17.5228 22 22 17.5228 22 12C22 6.47715 17.5228 2 12 2C6.47715 2 2 6.47715 2 12C2 17.5228 6.47715 22 12 22Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M12 8V16" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M8 12H16" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'},
      "Sports" => {"color" => "#FF7F50", "icon" => '<path d="M12 22C17.5228 22 22 17.5228 22 12C22 6.47715 17.5228 2 12 2C6.47715 2 2 6.47715 2 12C2 17.5228 6.47715 22 12 22Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M12 22C14.7614 22 17 17.5228 17 12C17 6.47715 14.7614 2 12 2" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M12 22C9.23858 22 7 17.5228 7 12C7 6.47715 9.23858 2 12 2" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M2 12H22" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'},
      "Learning & Workshops" => {"color" => "#ADD8E6", "icon" => '<path d="M4 19.5V15.5C4 14.3954 4.89543 13.5 6 13.5H18C19.1046 13.5 20 14.3954 20 15.5V19.5C20 20.6046 19.1046 21.5 18 21.5H6C4.89543 21.5 4 20.6046 4 19.5Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M6 13.5V4.5C6 3.39543 6.89543 2.5 8 2.5H16C17.1046 2.5 18 3.39543 18 4.5V13.5" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M10 8.5H14" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M10 12.5H14" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'},
      "Community & Culture" => {"color" => "#DAA520", "icon" => '<path d="M17 21V19C17 17.9391 16.5786 16.9217 15.8284 16.1716C15.0783 15.4214 14.0609 15 13 15H6C4.93913 15 3.92172 15.4214 3.17157 16.1716C2.42143 16.9217 2 17.9391 2 19V21" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M10 7C11.6569 7 13 5.65685 13 4C13 2.34315 11.6569 1 10 1C8.34315 1 7 2.34315 7 4C7 5.65685 8.34315 7 10 7Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M22 21V19C22 17.9391 21.5786 16.9217 20.8284 16.1716C20.0783 15.4214 19.0609 15 18 15H17" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M17 7C18.6569 7 20 5.65685 20 4C20 2.34315 18.6569 1 17 1C15.3431 1 14 2.34315 14 4C14 5.65685 15.3431 7 17 7Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>'}
    }

    # Combined metadata: returns a hash with color and icon keys
    def category_metadata(category)
      CATEGORY_META.fetch(category.to_s)
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryHelpers)
