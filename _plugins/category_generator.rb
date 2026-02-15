# frozen_string_literal: true

# Jekyll generator: create category archive pages at /category/parent/child/
# Slugs conform to parent/child for hierarchical categories.
# Run after posts are read so site.categories is populated.

EVENT_CI_SLUGS = {
  "first-channeling-intensive" => "ci1",
  "second-channeling-intensive" => "ci2",
  "third-channeling-intensive" => "ci3",
  "fourth-channeling-intensive" => "ci4",
  "fifth-channeling-intensive" => "ci5",
  "sixth-channeling-intensive" => "ci6",
}.freeze

module Jekyll
  class CategoryArchiveGenerator < Generator
    safe true
    priority :low

    def category_slug(name)
      return nil if name.to_s.strip.empty?
      if name.include?("/")
        parent, child = name.split("/", 2).map(&:strip)
        return nil if parent.empty? || child.empty?
        p_slug = Jekyll::Utils.slugify(parent)
        c_slug = Jekyll::Utils.slugify(child)
        c_slug = EVENT_CI_SLUGS[c_slug] || c_slug if p_slug == "events"
        return nil if p_slug.nil? || p_slug.empty? || c_slug.nil? || c_slug.empty?
        "#{p_slug}/#{c_slug}"
      else
        s = Jekyll::Utils.slugify(name)
        s.to_s.empty? ? nil : s
      end
    end

    SIDEBAR_PARENTS = %w[Circles Topics Events Contacts Instruments].freeze

    def generate(site)
      return unless site.categories && !site.categories.empty?

      grouped = Hash.new { |h, k| h[k] = [] }

      site.categories.each do |category_name, posts|
        next if category_name == "Channeling Session"

        slug = category_slug(category_name)
        next if slug.nil? || slug.empty?

        dir = File.join("category", slug.split("/"))
        page = CategoryArchivePage.new(site, site.source, dir, slug, category_name, posts)
        site.pages << page

        # Build grouped categories for sidebar
        if category_name.include?("/")
          parent, child = category_name.split("/", 2).map(&:strip)
          grouped[parent] << { "name" => category_name, "slug" => slug, "child" => child } if SIDEBAR_PARENTS.include?(parent)
        else
          grouped["Other"] << { "name" => category_name, "slug" => slug, "child" => category_name }
        end
      end

      # Sort children within each group; attach to site.data for layouts
      grouped_list = SIDEBAR_PARENTS.map do |parent|
        next unless grouped[parent]&.any?
        cats = grouped[parent].sort_by { |c| c["child"].downcase }
        { "parent" => parent, "categories" => cats }
      end.compact + (grouped["Other"]&.any? ? [{ "parent" => "Other", "categories" => grouped["Other"].sort_by { |c| c["child"].downcase } }] : [])
      site.data["grouped_categories"] = grouped_list
    end
  end

  class CategoryArchivePage < Page
    def initialize(site, base, dir, slug, category_name, posts)
      @site = site
      @base = base
      @dir = dir
      @name = "index.html"
      @category_name = category_name
      @posts = posts.sort { |a, b| a.date <=> b.date } # oldest first
      self.process(@name)
      self.data = {
        "layout" => "category",
        "title" => category_name,
        "category" => category_name,
        "posts" => @posts,
      }
      self.content = ""  # Layout renders the listing
    end
  end
end
