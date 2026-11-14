# Roadmap

Domark is a reader first. Every feature below serves reading; editing features wait.

**Rendering rule:** the page stays native SwiftUI. Mermaid is the only thing that may use a
hidden `WKWebView`, and only to produce an image that the page then shows like any other image.

Order is deliberate. Each step ships on its own before the next starts.

## 1. Outline (table of contents)

- Right-hand `.inspector`, hidden by default, remembered across launches. Toolbar button and `⌥⌘0`.
- Lists H1–H3 as a flat, indented list. H4–H6 are left out.
- A document with exactly one H1 uses it as the panel title and lists from H2.
- Highlights the heading being read (scroll-spy).
- Moves the preview only. Hidden in Edit mode.
- Later: record source line numbers per block → Split-mode scroll sync, and the outline can then move the editor too.

## 2. Syntax highlighting

- Hand-written tokenizer, no dependency.
- Swift, Dart, JavaScript/TypeScript, Python, Bash/Shell, JSON, YAML, SQL, HTML/XML, CSS, Diff, Go, Rust, Kotlin/Java, C/C++ — plus the usual short names (`js`, `ts`, `py`, `sh`, `zsh`, `yml`).
- No language or an unknown one → unchanged, never guessed.
- Xcode Default colours, light and dark: keyword, string, comment, number, type, function/attribute.
- Applied at parse time in `BlockBuilder` with dynamic colours, so an appearance change needs no re-render.
- No line numbers.

## 3. HTML subset

- `<img src width height alt>`, `<p|div align="center">`, `<details><summary>` (collapsed by default, Markdown inside), `<br>`, `<kbd>`, `<sub>`, `<sup>`; `<!-- -->` hidden.
- Anything else stays shown as code — nothing is dropped silently.
- Not supported: HTML `<table>`, `style=""`, `<script>`, `<iframe>`.

## 4. Math

- SwiftMath, native LaTeX drawing.
- `$$…$$` and ` ```math ` blocks; `$…$` inline.

## 5. Mermaid

- ` ```mermaid ` blocks rendered by mermaid.js (bundled, never fetched) in a hidden `WKWebView`.
- Output cached as an image keyed by source + appearance; shown with a placeholder while it renders.
- A render error falls back to showing the source as code, with the error underneath.

## 6. Export PDF

- File → Export as PDF… (`⌥⌘P`) and Print… (`⌘P`).
- Paginated, light appearance always, waits for Mermaid images to finish.
- Done last on purpose: it has to carry everything above.
