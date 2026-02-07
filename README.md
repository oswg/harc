# HARC Jekyll site

Jekyll site for High Altitude Receiving Center. Theme converted from the WordPress “HARC Amalie Lite Child” theme.

## Structure

- **`_config.yml`** – Site title, pagination (15 posts per page), optional logo path.
- **`_layouts/`** – `default`, `post`, `archive`.
- **`_includes/`** – Header, footer, post subtitle, post excerpt.
- **`index.html`** – Home page (paginated post list).
- **`assets/css/style.css`** – Theme styles.

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

Posts in the **Training Session** category get the training label and caveat on the single post view.

## Logo

In `_config.yml`: `logo: "/assets/logo.png"` (or leave empty to hide).

## Run locally

```bash
bundle install
bundle exec jekyll serve
```

Open http://localhost:4000.
