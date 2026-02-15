# HARC Jekyll site

Jekyll site for High Altitude Receiving Center. Theme converted from the WordPress “HARC Amalie Lite Child” theme. Includes github workflows that automatically transcribe mp3s.

## Structure

- **`_config.yml`** – Site title, pagination (20 posts per page), optional logo path.
- **`_layouts/`** – `default`, `post`, `archive`.
- **`_includes/`** – Header, footer, post subtitle, post excerpt.
- **`index.html`** – Home page (paginated post list).
- **`assets/css/style.css`** – Theme styles.

## Post and audio filename structure

Notice that underscores separate items, which must be in this order:

`2025-04-05_circle-a_event-x_001`

where `2025-04-05` is the date (April 5, 2025), `circle-a` would refer to circle it maps to in `category_descriptions.yml`, same with `event-x` and `001` is the session number. This base filename woudl have a `.md` extension in `_posts` and a `.mp3` extension under `assets/audio`

## Post front matter

| Field        | Description                          |
|-------------|--------------------------------------|
| `title`     | Post title                           |
| `date`      | Session/post date                    |
| `circle`    | Circle name                          |
| `event`     | Event name                           |
| `session`   | Session number                       |
| `categories`| e.g. `Transcripts`, `Training Session` |
| `tags`      | Optional tags                        |

Posts in the **Training Session** category get the training label and caveat on the single post view. They are excluded from the index feed, but available by going to any category page.

## Transcribe workflow

MP3s are stored in the repo at `assets/audio/` and served from the filesystem. The transcribe workflow runs on push: it finds orphan MP3s (no matching post), transcribes each, and creates a new post with `title: TBD` and the transcript in the body. **Make sure you `git pull` after you give it a chance to create the stub post`.

**Convention:** Audio path is derived from the post filename. For `_posts/2024-06-09_harc_gathering-24_005.md`, the audio is `assets/audio/2024-06-09_harc_gathering-24_005.mp3`.

To add new content: commit MP3s to `assets/audio/` and push. The workflow will detect orphans and create posts.

## Run locally

```bash
bundle install
bundle exec jekyll serve
```

Open http://localhost:4000.
