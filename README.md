# Pulseboard

[![CI](https://github.com/lucakader/Pulseboard/actions/workflows/ci.yml/badge.svg)](https://github.com/lucakader/Pulseboard/actions/workflows/ci.yml)

Pulseboard is a native macOS Activity Monitor reimagining built with Swift, SwiftUI, AppKit, and public Darwin APIs. It now has a Notion-style customization studio for shaping dashboards, cards, themes, widgets, and process-table properties.

## Run

```sh
swift run Pulseboard
```

## Test

```sh
swift test
```

## What is included

- Native split-pane monitor UI with dashboard presets, live widgets, process table, inspector, and dashboard cover area.
- Customizable dashboards with saved JSON presets in Application Support.
- Studio controls for dashboard title, subtitle, SF Symbol, theme swatches, canvas style, card style, density, chart style, signal rail, refresh interval, widget titles, widget sizes, widget order, and column visibility.
- Focus profiles for Balanced, Coding, Creative, Battery, and Performance workflows.
- Smart System Brief cards that surface high CPU, memory pressure, disk pressure, network spikes, and heavy processes.
- Focus Lock keeps the process table order steady while inspecting a process.
- Cleanup Review suggests high-resource user processes with Kill or Keep choices.
- Richer metric cards for memory composition, disk capacity, network lanes, trend lines, and ranked CPU offenders.
- Public macOS process/system sampling through `libproc`, Mach host statistics, disk capacity APIs, and network interface counters.
- Process actions for quit, force quit, and reveal in Finder.
- XCTest coverage for preset persistence, Codable round trips, customization options, CPU delta math, live sampling, and process-table sorting.
