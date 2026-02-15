# frozen_string_literal: true

# Liquid filters for category display and slug formatting.
# Parent/Child categories: slug = parent-slug/child-slug, display = "Parent: Child"

EVENT_CI_SLUGS = {
  "first-channeling-intensive" => "ci1",
  "second-channeling-intensive" => "ci2",
  "third-channeling-intensive" => "ci3",
  "fourth-channeling-intensive" => "ci4",
  "fifth-channeling-intensive" => "ci5",
  "sixth-channeling-intensive" => "ci6",
}.freeze

module Jekyll
  module CategoryFilters
    def category_slug(category_name)
      return "" if category_name.to_s.strip.empty?
      return "" if category_name.to_s == "Channeling Session"
      if category_name.to_s.include?("/")
        parent, child = category_name.to_s.split("/", 2).map(&:strip)
        return "" if parent.to_s.empty? || child.to_s.empty?
        p_slug = Jekyll::Utils.slugify(parent)
        c_slug = Jekyll::Utils.slugify(child)
        c_slug = EVENT_CI_SLUGS[c_slug] || c_slug if p_slug == "events"
        return "" if p_slug.to_s.empty? || c_slug.to_s.empty?
        "#{p_slug}/#{c_slug}"
      else
        s = Jekyll::Utils.slugify(category_name.to_s)
        s.to_s
      end
    end

    def category_display(category_name)
      return category_name.to_s if category_name.to_s.strip.empty?
      if category_name.to_s.include?("/")
        parent, child = category_name.to_s.split("/", 2).map(&:strip)
        return category_name.to_s if parent.to_s.empty? || child.to_s.empty?
        "#{parent}: #{child}"
      else
        category_name.to_s
      end
    end

    # Returns just the child part for Parent/Child categories (e.g. "Acceptance" from "Topics/Acceptance")
    def category_short(category_name)
      return category_name.to_s if category_name.to_s.strip.empty?
      if category_name.to_s.include?("/")
        _parent, child = category_name.to_s.split("/", 2).map(&:strip)
        child.to_s
      else
        category_name.to_s
      end
    end
  end
end

Liquid::Template.register_filter(Jekyll::CategoryFilters)
