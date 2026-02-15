# frozen_string_literal: true

# Exclude posts with public: false from all Jekyll output.
# Such posts are removed from site.posts and will not appear in any listing,
# sitemap, search index, or generate a page.

Jekyll::Hooks.register :site, :post_read do |site|
  posts = site.collections["posts"]
  posts.docs.delete_if { |doc| doc.data["public"] == false }
end
