# Moof

![Moof notification cards in the Hollow Knight, Elden Ring, Mario and Default themes](assets/banner.avif)

A macOS menu bar app that shows floating notification cards, triggered from a URL scheme or the `moof` command line tool, and can mirror them to WeChat or Telegram.

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

Choose **Connect WeChat…** in the menu bar and scan the QR code with WeChat. Pairing does not require an inbound message. Moof stores the bot and account credentials locally, and no Node.js runtime or OpenClaw installation is needed. After pairing, enable **Also Send to WeChat** to send a copy of each incoming URL-scheme or CLI notification to the account that scanned the code.

The integration uses the same iLink bot login and message endpoints as Tencent's MIT-licensed OpenClaw Weixin channel. The stored tokens leave the local credential file only in authenticated requests to WeChat.

While **Also Send to WeChat** is enabled, Moof keeps a long-poll for messages from the connected account and stores each new conversation token. Outbound messages include that token when available. If WeChat rejects it, Moof retries the same notification without it. If WeChat rejects both attempts, Moof keeps the pending notification, waits for a new message from the connected account, stores its conversation token, and retries automatically. No QR scan is needed unless WeChat invalidates the bot credential itself.

## Telegram

Choose **Connect Telegram…** in the menu bar, create a bot with [@BotFather](https://t.me/BotFather), and paste its token. Moof validates the token and shows a short one-time code. Send that code in the bot’s private chat, and Moof discovers and binds the chat automatically. It needs no inbound server, webhook, SDK, or Node.js runtime.

After pairing, enable **Also Send to Telegram** to send a copy of each incoming URL-scheme or CLI notification as a plain-text bot message. HTTP actions become inline buttons. The bot token and paired chat are stored locally in Moof's preferences.

## License

Moof is released under the [MIT License](LICENSE).
