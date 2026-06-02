# GitLab Pages and custom domains

This guide covers per-project custom domains on a GitLab instance installed with [`scripts/setup_gitlab_server.sh`](../scripts/setup_gitlab_server.sh).

## Short answer

**Yes.** GitLab Pages supports a **custom domain per project**. Each published Pages site can use its own domain, not only the instance-wide Pages URL.

## How it works

### 1. Instance-level Pages URL

The bootstrap script sets `pages_external_url` in `/etc/gitlab/gitlab.rb` (via `GITLAB_PAGES_URL`, e.g. `https://pages.example.io`). That is the **default** host for Pages sites (often paths like `namespace.gitlab.io` or project URLs under that domain).

`GITLAB_PAGES_URL` must be a **separate domain** from `GITLAB_EXTERNAL_URL` — the setup script documents this requirement.

### 2. Per-project custom domain

For each project that publishes Pages:

1. Open the project in the GitLab UI.
2. Go to **Deploy → Pages** (or **Settings → Pages**, depending on GitLab version).
3. Add a **custom domain** (e.g. `docs.myproject.com`).

That domain serves **that project’s** published Pages output.

### 3. DNS

For each custom domain, point DNS at your GitLab/Pages server:

- **CNAME** to your Pages host (e.g. `pages.example.io`), or
- **A/AAAA** to the server IP (if your GitLab/Pages docs recommend that for your topology)

For the **default** Pages domain, you typically also need **wildcard DNS**, e.g. `*.pages.example.io` → server IP (see the bootstrap script’s post-install summary).

### 4. TLS

If Let’s Encrypt is enabled in `gitlab.rb` (`GITLAB_ENABLE_LETSENCRYPT=1` and `GITLAB_LETSENCRYPT_EMAIL` at install time), GitLab can usually obtain certificates for verified custom domains once DNS is correct.

## With this bootstrap setup

| Item | Notes |
|------|--------|
| `GITLAB_PAGES_URL` | Separate from GitLab app URL; default Pages host |
| Wildcard DNS | Needed for default Pages subdomain pattern |
| Per-project domains | Configured in each project’s Pages settings + that domain’s DNS |
| Firewalls | UFW allows 80/443 on the server; Pages is served over HTTPS like the main app |

## Limits

- Custom domains are **per Pages site (project)**, not one domain per HTML page inside a single static site — one domain maps to one project’s published artifact.
- DNS and certificate issuance must succeed for **each** domain you add.
- Feature availability follows your GitLab edition (EE in this repo’s bootstrap script).

## Related

- [Controlling GitLab after bootstrap](gitlab-server.md)
- Bootstrap script: [`scripts/setup_gitlab_server.sh`](../scripts/setup_gitlab_server.sh)
