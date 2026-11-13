# Moof

![Moof notification cards in the Hollow Knight, Elden Ring, Mario and Default themes](assets/banner.avif)

A macOS menu bar app that shows floating notification cards, triggered from a URL scheme or the `moof` command line tool.

```sh
moof notify --title "Build done" --body "All green" --style success
open -g "moof://notify?title=Deploy&body=Waiting%20for%20approval&style=warning&duration=0"
```

Install the CLI from the menu bar (**Command Line Tool…**), or use **Copy Prompt** to give an AI agent the full reference.

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

Choose **Connect WeChat…** in the menu bar and scan the QR code with WeChat. Then send any message to the newly connected bot once; that inbound message supplies the conversation token WeChat requires for proactive delivery. Moof reads only the token and discards the message content. It stores both tokens locally, and no Node.js runtime or OpenClaw installation is needed. After pairing, enable **Also Send to WeChat** to send a copy of each incoming URL-scheme or CLI notification to the account that scanned the code.

The integration uses the same iLink bot login and message endpoints as Tencent's MIT-licensed OpenClaw Weixin channel. The stored tokens leave the local credential file only in authenticated requests to WeChat.

Moof does not keep a permanent long-poll connection. It polls only while waiting for a new conversation token, either during initial setup or after WeChat rejects an expired delivery context. In the latter case, sending any message to the bot restores notifications without another QR scan. If WeChat invalidates the bot session itself, the QR connection must be verified again.

## License

Moof is released under the [MIT License](LICENSE).
