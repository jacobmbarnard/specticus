# specticus

A fast, beautiful documentation generator.

## Features

- Specifications as code
- Turns plain text (like Markdown) into styled, readable, printable HTML
- Respects light and dark system themes

## Usage

```swift
let html = MarkdownParser().html(from: markdown)
try html.write(to: outputURL, atomically: true, encoding: .utf8)
```

## Philosophy

> Simple tools that get out of your way.

Just getting started!