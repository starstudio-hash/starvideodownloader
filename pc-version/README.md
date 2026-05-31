# Star Video Downloader for PC

This is the Windows PC version of Star Video Downloader. It keeps the Mac app's purchase model:

- Free tier: 5 downloads per day, up to 1080p, 1 practical active download.
- Pro tier: same $5 one-time Gumroad product and license key.
- License verification: `https://api.gumroad.com/v2/licenses/verify`.
- Product ID: `vdHfyiPVIE20rc3y7Rfc8g==`.

## What It Includes

- Windows desktop app shell built with Electron.
- `yt-dlp.exe` installer for PC downloads.
- `ffmpeg.exe` installer for merging, conversion, and repair.
- Download queue with progress parsing.
- Pro activation, validation, and local persistence.
- Pro-gated playlist downloads, SponsorBlock removal, conversion, and repair flows.

## Develop

```bash
npm install
npm test
npm start
```

## Package Windows Builds

```bash
npm run package:win:x64
npm run package:win:arm64
```

The packaged Windows app is written to `dist/`. The x64 build can be zipped and published as:

```text
Star.Video.Downloader.Windows.zip
```

## PC QA Checklist

Run this on a real Windows 10/11 PC before publishing a public release:

1. Launch `Star Video Downloader.exe`.
2. Install or update `yt-dlp.exe`.
3. Install or update `ffmpeg.exe`.
4. Start a 1080p free download and confirm the queue reaches completed.
5. Try a 4K or playlist download on the free tier and confirm it asks for Pro.
6. Buy Pro through the Gumroad button, paste the license key, and confirm activation succeeds.
7. Validate the license and confirm it does not increment Gumroad uses.
8. Run a playlist download, a SponsorBlock download, a conversion, and a fast repair with Pro active.

The Node tests cover the Gumroad request body, daily free-tier reset, Pro-safe validation behavior, Windows `yt-dlp` argument construction, and ffmpeg conversion/repair arguments.
