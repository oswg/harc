# frozen_string_literal: true

# Jekyll plugin: Build post permalinks and populate date/circle/event/session from filename
# Permalink format: /{date}/{circle}/{event}/{session}/{slugified-title} (session padded to 3 digits)
#
# Filename format: YYYY-MM-DD_circle_event_session-number (e.g. 2024-01-01_richmond_ccp_017.md)
# The filename is the source of truth. Date, circle, event, and session are parsed from it and
# stored in post.data. No need to duplicate these in front matter.
# Use {{ post.circle_display }} and {{ post.event_display }} for human-readable names
# (configure designation_mappings in _config.yml).

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

CIRCLE_SLUG_OVERRIDES = { "harc_circle" => "harc" }.freeze

def circle_from_categories(categories)
  return nil unless categories.is_a?(Array)
  categories.each do |cat|
    next unless cat.to_s.include?("/")
    parent, child = cat.to_s.split("/", 2)
    return { slug: Jekyll::Utils.slugify(child), display: child.to_s.strip } if parent.to_s.casecmp("circles").zero?
  end
  nil
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

# Parse date, circle, event, session from filename (YYYY-MM-DD_circle_event_session-number)
# Returns { date:, circle:, event:, session: } or nil if format doesn't match
# Filename is the source of truth for these fields; front matter is ignored for them.
def parse_filename_metadata(relative_path)
  basename = File.basename(relative_path.to_s, ".*")
  return nil unless basename =~ /\A(\d{4}-\d{2}-\d{2})[-_](.+)\z/
  date_str = Regexp.last_match(1)
  slug = Regexp.last_match(2)
  parts = slug.split("_")
  return nil unless parts.length >= 2 && parts.last.match?(/^\d+$/)
  session = parts.last
  event = Jekyll::Utils.slugify(parts[-2])
  circle = parts.length >= 3 ? parts[0] : nil
  date = begin
    Time.parse(date_str)
  rescue ArgumentError
    nil
  end
  { :date => date, :circle => circle, :event => event, :session => session }
end

Jekyll::Hooks.register :site, :post_read do |site|
  mappings = site.config["designation_mappings"] || {}

  site.posts.docs.each do |post|
    data = post.data
    parsed = parse_filename_metadata(post.relative_path)

    # Filename is source of truth for date, circle, event, session when parseable
    if parsed
      data["date"] = parsed[:date] if parsed[:date]
      data["circle"] = parsed[:circle] if parsed[:circle]
      data["event"] = parsed[:event] if parsed[:event]
      data["session"] = parsed[:session] if parsed[:session]
    end

    data["circle_display"] = designation_display(data["circle"], "circle", mappings)

    circle_from_cat = circle_from_categories(data["categories"])
    circle_raw = data["circle"]&.then { |c| Jekyll::Utils.slugify(c.to_s) } || circle_from_cat&.dig(:slug) || parsed&.dig(:circle)
    circle_for_url = CIRCLE_SLUG_OVERRIDES[circle_raw.to_s] || designation_slug_for_url(circle_raw, "circle", mappings)

    event_from_cat = event_from_categories(data["categories"])
    event_raw = data["event"]&.then { |e| Jekyll::Utils.slugify(e.to_s) } || event_from_cat&.dig(:slug) || parsed&.dig(:event)
    event_display = designation_display(event_raw, "event", mappings)
    data["event_display"] = (event_display != event_raw && !event_display.empty?) ? event_display : (event_from_cat&.dig(:display) || data["event"]&.to_s || event_raw.to_s)
    event_for_url = designation_slug_for_url(event_raw, "event", mappings)
    session = data["session"]&.to_s || parsed&.dig(:session)&.to_s
    next unless data["date"] && circle_for_url && event_for_url && session && data["title"]

    date_str = data["date"].respond_to?(:strftime) ? data["date"].strftime("%Y-%m-%d") : data["date"].to_s
    session_padded = session.to_s.rjust(3, "0")
    title_slug = Jekyll::Utils.slugify(data["title"].to_s.gsub(/[''`]/, ""))
    permalink = "/#{date_str}/#{circle_for_url}/#{event_for_url}/#{session_padded}/#{title_slug}/"
    post.data["permalink"] = permalink
    post.instance_variable_set(:@url, nil) if post.instance_variable_defined?(:@url)

    # Redirect from old permalink format: /date/circle/event/session/filename-slug (e.g. richmond-ccp-019)
    if parsed && parsed[:circle] && parsed[:event]
      filename_slug = Jekyll::Utils.slugify("#{parsed[:circle]}-#{parsed[:event]}-#{session}")
      old_url = "/#{date_str}/#{circle_for_url}/#{event_for_url}/#{session_padded}/#{filename_slug}/"
      if old_url != permalink
        existing = post.data["redirect_from"] || []
        existing = [existing] unless existing.is_a?(Array)
        post.data["redirect_from"] = (existing + [old_url]).uniq
      end
    end
  end
end
