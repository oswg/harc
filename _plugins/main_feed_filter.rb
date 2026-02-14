# frozen_string_literal: true

# Excludes "Training Session" category from the main index feed.
# Training sessions remain visible on category, search, circle, and other pages.
# Uses a pre_render hook to replace the paginator's posts on index/paginated pages.

TRAINING_SESSION_CATEGORY = "Training Session"

def main_feed_posts(site)
  posts = site.posts.respond_to?(:docs) ? site.posts.docs : site.posts.to_a
  @main_feed_posts ||= posts.reject do |p|
    p.data["categories"]&.include?(TRAINING_SESSION_CATEGORY)
  end
end

def build_filtered_pager(site, page_num, per_page)
  posts = main_feed_posts(site)
  total_posts = posts.size
  total_pages = (total_posts.to_f / per_page).ceil
  total_pages = 1 if total_pages < 1

  start_idx = (page_num - 1) * per_page
  end_idx = [start_idx + per_page - 1, total_posts - 1].min
  page_posts = start_idx <= end_idx ? posts[start_idx..end_idx] : []

  prev_page = page_num > 1 ? page_num - 1 : nil
  next_page = page_num < total_pages ? page_num + 1 : nil

  path_format = site.config["paginate_path"] || "/page:num/"
  # Page 1 is the index at /; pages 2+ use paginate_path (match jekyll-paginate)
  prev_path = prev_page ? (prev_page <= 1 ? "/" : path_format.sub(":num", prev_page.to_s)) : nil
  next_path = next_page ? path_format.sub(":num", next_page.to_s) : nil

  {
    "page" => page_num,
    "per_page" => per_page,
    "posts" => page_posts,
    "total_posts" => total_posts,
    "total_pages" => total_pages,
    "previous_page" => prev_page,
    "previous_page_path" => prev_path,
    "next_page" => next_page,
    "next_page_path" => next_path
  }
end

Jekyll::Hooks.register(:pages, :pre_render) do |page, payload|
  # Paginator only creates pagers for the index; any page with a pager is main feed
  next unless page.respond_to?(:pager) && page.pager
  next unless payload

  site = page.site
  paginate_per = site.config["paginate"].to_i
  paginate_per = 15 if paginate_per < 1

  page_num = page.pager.page
  filtered = build_filtered_pager(site, page_num, paginate_per)

  # Payload is already built with original paginator; replace with filtered posts
  payload["paginator"] = filtered
end
