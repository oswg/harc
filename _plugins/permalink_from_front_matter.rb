# frozen_string_literal: true

# Jekyll plugin: Build post permalinks and populate circle/event/session from filename
# Permalink format: /{date}/{event}/{session}/{slugified-title} (session padded to 3 digits)
#
# Filename format: YYYY-MM-DD_circle_event_session-number (e.g. 2024-01-01_richmond_ccp_017.md)
# Values parsed from filename are stored in post.data and available in templates as:
#   {{ post.circle }}  {{ post.event }}  {{ post.session }}
# Use {{ post.circle_display }} and {{ post.event_display }} for human-readable names
# (configure designation_mappings in _config.yml). Front matter overrides filename-derived values.
#
# Event can also come from categories (Event/CCP) for the permalink.

def designation_display(value, field, mappings)
  return value.to_s if value.to_s.strip.empty?
  return value.to_s unless mappings.is_a?(Hash) && mappings[field.to_s].is_a?(Hash)
  map = mappings[field.to_s]
  slug = Jekyll::Utils.slugify(value.to_s)
  map[value.to_s] || map[slug] || value.to_s
end

# Return the short key for use in URLs (permalink). Reverse lookup: value -> key.
def designation_slug_for_url(value, field, mappings)
  return value.to_s if value.to_s.strip.empty?
  return value.to_s unless mappings.is_a?(Hash) && mappings[field.to_s].is_a?(Hash)
  map = mappings[field.to_s]
  value_slug = Jekyll::Utils.slugify(value.to_s)
  return value.to_s if map[value.to_s] || map[value_slug]  # value is already a key
  map.each { |key, val| return key if Jekyll::Utils.slugify(val.to_s) == value_slug }
  value_slug
end

def event_from_categories(categories)
  return nil unless categories.is_a?(Array)
  categories.each do |cat|
    next unless cat.to_s.include?("/")
    parent, child = cat.to_s.split("/", 2)
    return { slug: Jekyll::Utils.slugify(child), display: child.to_s.strip } if parent.to_s.casecmp("event").zero?
  end
  nil
end

# Parse circle, event, session from filename (YYYY-MM-DD_circle_event_session-number)
# Returns { circle:, event:, session: } or nil if format doesn't match
def parse_filename_metadata(relative_path)
  basename = File.basename(relative_path.to_s, ".*")
  return nil unless basename =~ /\A\d{4}-\d{2}-\d{2}[-_](.+)\z/
  slug = Regexp.last_match(1)
  parts = slug.split("_")
  return nil unless parts.length >= 2 && parts.last.match?(/^\d+$/)
  session = parts.last
  event = Jekyll::Utils.slugify(parts[-2])
  circle = parts.length >= 3 ? parts[0] : nil
  { :circle => circle, :event => event, :session => session }
end

Jekyll::Hooks.register :site, :post_read do |site|
  mappings = site.config["designation_mappings"] || {}

  site.posts.docs.each do |post|
    data = post.data
    parsed = parse_filename_metadata(post.relative_path)

    if parsed
      data["circle"] ||= parsed[:circle]
      data["event"] ||= parsed[:event]
      data["session"] ||= parsed[:session]
    end

    data["circle_display"] = designation_display(data["circle"], "circle", mappings)

    event_from_cat = event_from_categories(data["categories"])
    event_raw = event_from_cat&.dig(:slug) || data["event"]&.then { |e| Jekyll::Utils.slugify(e.to_s) } || parsed&.dig(:event)
    event_display = designation_display(event_raw, "event", mappings)
    data["event_display"] = (event_display != event_raw && !event_display.empty?) ? event_display : (event_from_cat&.dig(:display) || data["event"]&.to_s || event_raw.to_s)
    event_for_url = designation_slug_for_url(event_raw, "event", mappings)
    session = data["session"]&.to_s || parsed&.dig(:session)
    next unless data["date"] && event_for_url && session && data["title"]

    date_str = data["date"].respond_to?(:strftime) ? data["date"].strftime("%Y-%m-%d") : data["date"].to_s
    session_padded = session.to_s.rjust(3, "0")
    title_slug = Jekyll::Utils.slugify(data["title"].to_s)

    post.data["permalink"] = "/#{date_str}/#{event_for_url}/#{session_padded}/#{title_slug}/"
    post.instance_variable_set(:@url, nil) if post.instance_variable_defined?(:@url)
  end
end
