<p align="center">
  <img src="Icon/previews/face.png" width="128" alt="Domark icon">
</p>

<h1 align="center">Domark</h1>

<p align="center">
  A fast, native Markdown reader and editor for macOS.<br>
  Built with SwiftUI and Apple's <a href="https://github.com/apple/swift-markdown">swift-markdown</a>, with no web view.
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/UI-SwiftUI-0A84FF">
</p>

<p align="center">
  <img src="docs/screenshots/preview-light.png" alt="Domark showing a Markdown document in Preview mode" width="860">
</p>

---

## ✨ Features

- **Native rendering.** Markdown is parsed to an AST and drawn with SwiftUI views, so there's no HTML or WebKit layer.
- **Three view modes.** Switch between **Preview**, **Split** and **Edit** with the toolbar or `⌃⌘1` / `⌃⌘2` / `⌃⌘3`.
- **Edit and save.** The preview updates as you type. Domark also warns you before closing or quitting with unsaved work.
- **Quick notes.** `⌘N` opens a blank Untitled note in Edit mode. The first `⌘S` asks where to save it (inside the open folder by default), and `⇧⌘S` is Save As.
- **Live reload.** When a file changes on disk, Domark reloads it. If you have unsaved edits, it asks whether to use the disk version or keep yours.
- **Folder browsing.** Open a folder to get a sidebar of every Markdown file in it. Move between files with `⌘[` and `⌘]`.
- **Outline.** A panel on the right lists the H1–H3 headings and highlights the one you're reading. Click a heading to jump to it (`⌥⌘0`).
- **Syntax highlighting.** 15 languages, using Xcode's light and dark colours: Swift, Dart, JS/TS, Python, Shell, JSON, YAML, SQL, HTML/XML, CSS, Diff, Go, Rust, Kotlin/Java and C/C++.
- **HTML that READMEs use.** `align="center"`, `<img width>` and rows of badges, `<details>` that fold away, `<kbd>`, `<sub>`/`<sup>` and `<br>`. Any other HTML is shown as code, so nothing goes missing.
- **Math.** `$…$` inline, and `$$…$$` or ` ```math ` blocks, typeset natively with [SwiftMath](https://github.com/mgriebling/SwiftMath). Prices like $5 are left alone.
- **Find in the preview.** `⌘F`, `⌘G` and `⇧⌘G` highlight matches in the rendered page, with an option for case-sensitive search.
- **Heading links.** `[jump](#some-heading)` scrolls to that heading inside the app.
- **Full CommonMark and GFM.** Headings, lists, task lists, blockquotes, code blocks, tables with column alignment, images and horizontal rules all render.
- **Thai-friendly typography.** You can pick the reading and code typefaces separately. Fonts that draw Thai are listed first, with optical size correction (TH Sarabun New is used by default if it's installed).
- **Light, dark or match the system.** The floating Liquid Glass control resizes the text.
- **Drag and drop.** Drop a `.md` file or a folder onto the window to open it.
- **Recent files.** File ▸ Open Recent lists the last 10 files and folders, and the start screen shows the latest 5.

## 📸 Screenshots

| Preview (Dark)                                             | Split view                                                    |
| ---------------------------------------------------------- | ------------------------------------------------------------- |
| ![Preview in dark mode](docs/screenshots/preview-dark.png) | ![Split editor and preview](docs/screenshots/split-light.png) |

> The screenshots come from [`Fixtures/kitchen-sink.md`](Fixtures/kitchen-sink.md). To take them again, run `./Scripts/screenshots.sh` (whatever runs it needs Screen Recording permission).

## 🚀 Getting started

### Requirements

- macOS 26 (Tahoe) or later
- Xcode 26 / Swift 6.2 or later

### Build and run

```bash
./Scripts/bundle.sh
```

```bash
open build/Domark.app
```

`bundle.sh` runs `swift build -c release`, wraps the binary in `build/Domark.app` and ad-hoc signs it. Pass `debug` to get a debug build: `./Scripts/bundle.sh debug`.

### Install into /Applications

```bash
./Scripts/install.sh
```

The script quits any running Domark, copies the app into `/Applications` and registers it with Finder. To install for your user only, use `./Scripts/install.sh ~/Applications`.

To open a file in Domark:

- In Finder, right-click → **Open With → Domark**
- To make Domark the default: **Get Info → Open with → Domark → Change All…**
- From the Terminal: `open -a Domark file.md`

## ⌨️ Keyboard shortcuts

| Action                         | Shortcut              |
| ------------------------------ | --------------------- |
| Open file / Open folder        | `⌘O` / `⇧⌘O`          |
| Save / Reload                  | `⌘S` / `⌘R`           |
| Close                          | `⇧⌘W`                 |
| Preview / Split / Edit         | `⌃⌘1` / `⌃⌘2` / `⌃⌘3` |
| Find / Next / Previous         | `⌘F` / `⌘G` / `⇧⌘G`   |
| Bigger / Smaller / Actual size | `⌘+` / `⌘-` / `⌘0`    |
| Next / Previous file           | `⌘]` / `⌘[`           |
| Show / Hide outline            | `⌥⌘0`                 |
| Settings                       | `⌘,`                  |

## 🗂 Project layout

```
Sources/Domark/
├── DomarkApp.swift, AppDelegate.swift   App, menus, opening files from Finder
├── Model/    DocumentStore, FileWatcher, FolderTree, FindSession, settings
├── Render/   Markdown AST → render blocks (BlockBuilder, InlineBuilder, Theme, Fonts)
└── Views/    ContentView, BlockView, code/table/image blocks, editor, sidebar, find bar
Bundle/Info.plist      Bundle metadata and the .md document type
Icon/                  App icon (generated by make-icon.swift)
Fixtures/              kitchen-sink.md, a page that exercises every element
Scripts/               bundle.sh · install.sh · screenshots.sh
```

## 🧭 Roadmap

- [x] Outline panel
- [x] Syntax highlighting in code blocks
- [x] A subset of HTML: `<img>`, `<details>`, `align="center"`, `<kbd>`
- [x] Math (`$…$`, `$$…$$`)
- [ ] Mermaid diagrams
- [ ] Export to PDF and printing

See [docs/roadmap.md](docs/roadmap.md) for the details.
