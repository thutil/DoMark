# Domark — Kitchen Sink

A normal paragraph, long enough to wrap across several lines, so the line spacing and the measure of the text column can be judged at a glance rather than guessed at.

## Heading level 2

### Heading level 3

#### Heading level 4

##### Heading level 5

###### Heading level 6

---

## Inline styles

plain · **bold** · *italic* · ***bold and italic*** · ~~struck through~~ · `inline code` · **`code inside bold`**

External link: [Apple's swift-markdown](https://github.com/apple/swift-markdown)

Link inside bold: **[click here](https://swift.org)**

This line ends with a backslash\
← the new line belongs here

## Lists

- First item
- Second item with **bold** in it
- Third item, nested
  - Inner item A
  - Inner item B
    - Innermost
- Fourth item

1. One
2. Two
3. Three
   1. Three point one
   2. Three point two

Starting from another number:

5. Five
6. Six
7. Seven

## Task list

- [x] Set up the Swift package
- [x] Write the AST-based renderer
- [ ] Add syntax highlighting
- [ ] Draw an app icon

## Blockquote

> A single-level quote, with **bold** and `code` in it.
>
> A second paragraph inside the same quote.
>
> > A quote inside a quote
> >
> > - with a list inside it
> > - and another item

## Code

No language:

```
$ swift build
Build complete!
```

Swift:

```swift
@MainActor
@Observable
final class DocumentStore {
    private(set) var blocks: [IdentifiedBlock] = []

    func open(_ url: URL) {
        self.url = url
        reload()
    }
}
```

A line wider than the column, to check horizontal scrolling:

```bash
swift build -c release && codesign --force --sign - build/Domark.app && open -a Domark Fixtures/kitchen-sink.md
```

## Tables

| Feature | Status | Notes |
|---|:---:|---:|
| Headings | ✅ | H1–H6 |
| **Bold / italic** | ✅ | including `***nested***` |
| Tables | ✅ | left, centre, right |
| Task lists | ✅ | real checkboxes |
| Syntax highlighting | ❌ | not yet |

Wider than the window:

| Column A | Column B | Column C | Column D | Column E | Column F | Column G |
|---|---|---|---|---|---|---|
| a fairly long value | a fairly long value | a fairly long value | a fairly long value | a fairly long value | a fairly long value | a fairly long value |

## Non-Latin text

Kept as a rendering check — these scripts break lines differently from Latin:

ข้อความภาษาไทยที่ยาวพอจะต้องขึ้นบรรทัดใหม่ เพื่อดูว่าตัดคำและตัดบรรทัดถูกต้องไหม ไม่ตกขอบคอลัมน์

日本語のテキストも同じように折り返しを確認します。中文文本也一样。

## Images

An image that cannot load, to check the placeholder:

![A caption for a missing image](./not-here.png)

## Raw HTML

<div class="note">HTML is shown as code, not rendered</div>

## Other rules

***

___

End of fixture.
