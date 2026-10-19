# Moof

A macOS menu bar app that shows floating notification cards, triggered from a URL scheme or the `moof` command line tool.

```sh
moof notify --title "Build done" --body "All green" --style success
open -g "moof://notify?title=Deploy&style=warning&duration=0"
```

Install the CLI from the menu bar (**Command Line Tool…**), or use **Copy Prompt** to give an AI agent the full reference.

## Themes

Every theme is drawn entirely in code — no bundled images or fonts.

- **Default** — Liquid Glass tinted by the notification style.
- **Elden Ring** — a translucent band fading at both ends, centered serif text, and a gold divider that doubles as the countdown.
- **Mario** — a slanted, striped dark box with a white speaker tab, bold rounded text, and a bouncing ▼; a white bar along the bottom is the countdown.

Pick one under **Theme** in the menu, or per notification with `--theme <name>`.

## Inspiration

Moof's themes are love letters to the message boxes of games we enjoy:

- **Elden Ring** (FromSoftware) — the quiet, weathered in-game message band.
- **Mario** (Nintendo) — bold, playful dialog boxes with a speaker name tab.

These themes only reinterpret general visual styles. Moof contains no assets, fonts, characters, or other material from these games. All names and trademarks belong to their respective owners, and Moof is not affiliated with or endorsed by them.
