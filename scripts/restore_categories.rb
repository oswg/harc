#!/usr/bin/env ruby
# frozen_string_literal: true

# Restore WordPress categories (parent/child) from WXR export into Jekyll post front matter.
#
# Reads the WXR, builds the category taxonomy, and adds categories to each post
# in Parent/Child format (e.g. "Circles/Colorado Springs Circle", "Contacts/Q'uo").
#
# Usage: ruby scripts/restore_categories.rb ~/Downloads/harc_wp.xml [_posts]

require "fileutils"
require "yaml"
require "time"

begin
  require "nokogiri"
rescue LoadError
  abort "Run: bundle install (requires nokogiri)"
end

POSTS_DIR = "_posts"

def build_category_taxonomy(doc)
  # wp:category elements: term_id, category_nicename, category_parent, cat_name
  cats = {}
  doc.xpath("//*[local-name()='category']").each do |cat_el|
    next unless cat_el.xpath("*[local-name()='term_id']").first
    nicename = cat_el.xpath("*[local-name()='category_nicename']").first&.text.to_s.strip
    parent_slug = cat_el.xpath("*[local-name()='category_parent']").first&.text.to_s.strip
    cat_name = cat_el.xpath("*[local-name()='cat_name']").first&.text.to_s.strip
    next if nicename.empty?
    cats[nicename] = { parent: parent_slug, name: cat_name }
  end
  # Build full path for each: Parent/Child
  path_cache = {}
  cats.each do |slug, data|
    path = build_path(slug, cats, path_cache)
    path_cache[slug] = path
  end
  path_cache
end

def build_path(slug, cats, cache)
  return cache[slug] if cache[slug]
  data = cats[slug]
  return slug unless data
  parent_slug = data[:parent]
  if parent_slug.nil? || parent_slug.empty?
    cache[slug] = data[:name]
    return data[:name]
  end
  parent_path = build_path(parent_slug, cats, cache)
  cache[slug] = "#{parent_path}/#{data[:name]}"
  cache[slug]
end

def get_post_categories(item)
  # domain="category" only (exclude post_tag)
  item.xpath("*[local-name()='category']").select do |c|
    c["domain"].to_s.downcase == "category"
  end.map do |c|
    c["nicename"].to_s.strip
  end.compact.reject(&:empty?)
end

def load_jekyll_posts(dir)
  posts = {}
  Dir[File.join(dir, "*.md")].each do |path|
    basename = File.basename(path, ".*")
    date_from_file = basename[0..9] if basename =~ /^\d{4}-\d{2}-\d{2}/
    raw = File.read(path)
    next unless raw =~ /\A---\s*\n(.*?)---\s*\n/m
    fm = YAML.safe_load(Regexp.last_match(1))
    next unless fm.is_a?(Hash)
    title = fm["title"].to_s.strip
    date = fm["Date"] || fm["date"]
    date_str = date_from_file || (date.respond_to?(:strftime) ? date.strftime("%Y-%m-%d") : date.to_s.gsub(/['"]/, ""))
    posts["#{date_str}|#{title}"] = path
  end
  posts
end

def normalize_title(s)
  s.to_s.gsub(/['']/, "'").strip
end

def main
  wxr_path = ARGV[0]
  posts_dir = ARGV[1] || POSTS_DIR
  unless wxr_path && File.exist?(wxr_path)
    puts "Usage: ruby scripts/restore_categories.rb ~/Downloads/harc_wp.xml [_posts]"
    exit 1
  end
  unless File.directory?(posts_dir)
    puts "Posts dir not found: #{posts_dir}"
    exit 1
  end

  doc = Nokogiri::XML(File.read(wxr_path))
  doc.remove_namespaces!
  taxonomy = build_category_taxonomy(doc)
  jekyll_posts = load_jekyll_posts(posts_dir)

  items = doc.xpath("//item").select do |item|
    pt = item.xpath("*[local-name()='post_type']").first&.text.to_s.strip
    pt == "post"
  end

  updated = 0
  items.each do |item|
    title = item.xpath("*[local-name()='title']").first&.text.to_s.strip
    pub_date = item.xpath("*[local-name()='post_date']").first&.text
    next unless pub_date
    date = Time.parse(pub_date) rescue next
    date_str = date.strftime("%Y-%m-%d")
    key = "#{date_str}|#{title}"
    path = jekyll_posts[key]
    path ||= jekyll_posts["#{date_str}|#{normalize_title(title)}"]
    unless path
      # Try fuzzy match
      path = jekyll_posts.find { |k, _| k.start_with?(date_str) && k.include?(title[0..30]) }&.last
    end
    next unless path

    nickenames = get_post_categories(item)
    next if nickenames.empty?

    category_paths = nickenames.map { |n| taxonomy[n] }.compact.uniq.sort
    next if category_paths.empty?

    raw = File.read(path)
    unless raw =~ /\A---\s*\n(.*?)---\s*\n\n*(.*)/m
      puts "Skipping (no front matter): #{path}"
      next
    end
    fm_raw = Regexp.last_match(1)
    body = Regexp.last_match(2)
    fm = YAML.safe_load(fm_raw)
    next unless fm.is_a?(Hash)

    fm["categories"] = category_paths
    new_fm = fm.to_yaml(line_width: -1).sub(/\A---\s*\n/, "")
    new_content = "---\n#{new_fm.strip}\n---\n\n#{body}"
    File.write(path, new_content)
    puts "Updated: #{File.basename(path)} -> #{category_paths.size} categories"
    updated += 1
  end

  puts "\nUpdated #{updated} posts with categories."
end

main
