# Clipdown

Clipdown is a tiny Mac app that turns copied content into clean Markdown.

Copy from Word, Google Docs, Slack, Notion, GitHub, Excel, a webpage, or another app. Press the Clipdown hotkey. Paste Markdown anywhere.

Clipdown runs locally on your Mac. Clipboard contents are converted on-device.

## Install

1. Download the latest `Clipdown.zip` from the [Releases](https://github.com/dvelton/clipdown/releases) page.
2. Unzip it.
3. Move `Clipdown.app` to your Applications folder.
4. Open `Clipdown.app`.

Because Clipdown is not notarized yet, macOS may block the first launch. First try right-clicking `Clipdown.app`, choosing **Open**, and confirming that you want to open it.

If macOS says "`Clipdown` is damaged and can't be opened," the downloaded app is being blocked by quarantine. To allow this copy of Clipdown, run:

```bash
xattr -dr com.apple.quarantine /Applications/Clipdown.app
open /Applications/Clipdown.app
```

That command removes the quarantine flag from `Clipdown.app` only.

## What it does

- Converts rich clipboard content to Markdown.
- Handles copied HTML, rich text, plain text, links, local files, images, and simple tables.
- Turns copied spreadsheet-style rows into Markdown tables.
- Turns copied links into Markdown links.
- Runs from the macOS menu bar.
- Uses a global hotkey: `Control` + `Option` + `Command` + `V`.

## How to use it

1. Copy content from any app.
2. Press `Control` + `Option` + `Command` + `V`.
3. Paste the result wherever you want Markdown.

By default, the hotkey converts the clipboard and leaves the Markdown on your clipboard. In the menu bar, turn on **Hotkey Converts and Pastes** if you want Clipdown to paste automatically after converting.

macOS may ask for Accessibility permission if you enable automatic paste. Clipdown needs that permission only to send the final paste keystroke.

## Build from source

Install the Xcode command line tools, then run:

```bash
git clone https://github.com/dvelton/clipdown.git
cd clipdown
./scripts/test.sh
./scripts/package-app.sh
open dist/Clipdown.app
```
