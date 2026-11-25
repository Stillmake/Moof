# Moof

![Moof notification cards in the Hollow Knight, Elden Ring, Mario and Default themes](assets/banner.avif)

A macOS menu bar app that shows floating notification cards, triggered from a URL scheme or the `moof` command line tool, and can mirror them to WeChat or Telegram.

## Install

- [Download from the Mac App Store](https://apps.apple.com/us/app/moof-notification-cards/id6825177572?mt=12)
- [Download Moof 1.1.4 (DMG)](https://github.com/Stillmake/releases/releases/download/moof-1.1.4-50/Moof.dmg)

Requires macOS 26 or later.

```sh
moof notify --title "Build done" --body "All green" --style success
open -g "moof://notify?title=Deploy&body=Waiting%20for%20approval&style=warning&duration=0"
```

After installing, use **Command Line Tool…** in the menu bar to install the `moof` CLI, or **Copy Prompt** to give an AI agent the full reference.

## Themes

Themes are drawn in code with no bundled fonts; the only images are Hollow Knight's two vector ornaments.

- **Default** — Liquid Glass tinted by the notification style.
- **Elden Ring** — a translucent band fading at both ends, centered serif text, and a gold divider that doubles as the countdown.
- **Mario** — a slanted, striped dark box with a white speaker tab, bold rounded text, and a bouncing ▼; a white bar along the bottom is the countdown.
- **Hollow Knight** — a soft-edged dark panel with serif text between two fleur ornaments; the bottom fleur fades in from its ends as the countdown.

Pick one under **Theme** in the menu, or per notification with `--theme <name>`.

## Inspiration

Moof's themes are love letters to the message boxes of games we enjoy:

- **Elden Ring** (FromSoftware) — the quiet, weathered in-game message band.
- **Mario** (Nintendo) — bold, playful dialog boxes with a speaker name tab.
- **Hollow Knight** (Team Cherry) — the dark dialog panel framed by its fleur ornaments.

These themes reinterpret general visual styles. Moof contains no fonts, characters, or game files; the Hollow Knight fleur ornaments are vector traces modeled on the game's design. All names and trademarks belong to their respective owners, and Moof is not affiliated with or endorsed by them.

## WeChat

- Choose **Connect WeChat…** and scan the QR code.
- Enable **Also Send to WeChat** to mirror notifications.
- Moof talks directly to WeChat's bot service; no Node.js, OpenClaw, or server is required.
- Failed sends retry automatically.

## Telegram

- Create your own bot with [@BotFather](https://t.me/BotFather) and paste its token into **Connect Telegram…**.
- Open the bot, press Start if needed, and send the one-time code Moof shows.
- Enable **Also Send to Telegram** to mirror notifications.
- HTTP actions become inline buttons; no server or SDK is required.

## License

Moof is released under the [MIT License](LICENSE).
