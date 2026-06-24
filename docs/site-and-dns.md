# Otterpace site — deploy + DNS (otterpace.com)

The marketing landing page and privacy policy live in `site/` (`index.html`,
`privacy.html`, `style.css`, `otterpace-icon.png`) and deploy to **GitHub Pages**
via `.github/workflows/pages.yml`. The privacy policy URL the app + App Store
need is **https://otterpace.com/privacy.html**.

## One-time setup (you)

### 1. Turn on GitHub Pages
Repo → **Settings → Pages** → **Build and deployment → Source: GitHub Actions**.
(The workflow already deploys `site/` on every push to `main` that touches it.)

### 2. Point otterpace.com at GitHub Pages (Namecheap)
Namecheap → Domain List → **Manage** otterpace.com → **Advanced DNS** → add:

| Type  | Host | Value                  |
|-------|------|------------------------|
| A     | @    | 185.199.108.153        |
| A     | @    | 185.199.109.153        |
| A     | @    | 185.199.110.153        |
| A     | @    | 185.199.111.153        |
| CNAME | www  | nseldeib.github.io.    |

Remove any default Namecheap "parking"/redirect records on `@` and `www` first.
DNS can take 30 min–24 h to propagate.

### 3. Set the custom domain in GitHub
Repo → **Settings → Pages → Custom domain** → `otterpace.com` → Save. The repo's
`site/CNAME` already declares it. Once DNS resolves, check **Enforce HTTPS**.

## Verify
- Action: repo → **Actions → "Deploy site to GitHub Pages"** is green.
- Before DNS: the site is live at the Action's `page_url` (…github.io/…).
- After DNS: `https://otterpace.com` and `https://otterpace.com/privacy.html` load.

## Email (optional, for the privacy contact)
`hello@otterpace.com` is referenced in the privacy policy + Code of Conduct. Set up
an email alias/forwarding for it on Namecheap (or your mail provider) when ready.

## Alternative host
If you'd rather use Vercel/Netlify: point it at this repo with `site/` as the
output/root directory and add otterpace.com as a custom domain (their dashboard
gives the DNS records). Then this Pages workflow can be removed.
