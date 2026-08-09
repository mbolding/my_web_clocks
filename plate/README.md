# Plate — installable QR code generator

A QR code generator that runs entirely in the browser and keeps working offline.
Encoding is done in the page itself, so nothing you type ever leaves the device.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole app, encoder included |
| `manifest.webmanifest` | Name, icons, standalone display, Android share target |
| `sw.js` | Service worker, precaches the shell for offline use |
| `icon-*.png`, `icon.svg` | App icons, including a maskable one for Android |
| `apple-touch-icon-180.png` | Home screen icon for iOS |

## Why it needs hosting

Service workers only register over HTTPS or on `localhost`, so opening
`index.html` from the filesystem gives you the app but not the installable,
offline part. It needs a real origin.

## Dropping it into an existing site

Every path in the manifest, the service worker and the page is relative, so the
folder works from a subdirectory. On a GitHub Pages project site, copy this
folder in as, say, `plate/` and it serves at
`https://USER.github.io/REPO/plate/`. The service worker scope is that
subdirectory only, so it will not touch anything else on the site, and its cache
names are prefixed `plate-` so cleanup never evicts another app's cache.

One thing to know about shared origins: a service worker registered at the root
of the domain, if you ever add one, would control this path too. Nothing to do
about it now, just worth remembering if a page here starts serving stale files.

## Deploying to Cloudflare Pages

```
cd plate-pwa
git init && git add . && git commit -m "Plate"
```

Push to a GitHub repo, then in Cloudflare Pages create a project from that repo
with no build command and the output directory set to `/`. Direct upload works
too: drag this folder into the Pages dashboard.

Any static host is fine, and a subdirectory is fine as well, since every path in
the manifest and the service worker is relative.

## Testing locally first

```
cd plate-pwa
python3 -m http.server 8000
```

Then open `http://localhost:8000`. Service workers are allowed on localhost, so
install and offline behaviour both work here.

## Installing

- **Android and desktop Chrome:** an Install button appears in the header.
- **iPhone and iPad:** Safari only, tap Share then Add to Home Screen. The app
  reminds you of this when it detects iOS.

Once installed it opens without browser chrome, keeps its own icon, and works
in airplane mode.

## Sharing a link into the app

On Android, Plate registers as a share target. Share a URL from any app, pick
Plate, and the link is already in the content field when it opens.

## Updating

Change a file, bump `CACHE` in `sw.js` from `PREFIX + 'v1'` to `PREFIX + 'v2'`,
and redeploy.
The old cache is deleted on activation and installed copies pick up the new
version on next launch. Without the bump, installed copies keep serving the old
files from cache.
