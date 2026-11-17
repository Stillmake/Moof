# Moof ↔ WeChat Gateway Transport Draft

## Recommended Transport

Do not use HTTP between Moof and the server. Use one long-lived TCP connection
with a pre-shared-key Noise handshake:

```text
Moof ── TCP :7443 ──> Go gateway
        Noise PSK
```

This needs no domain, certificate, port 80/443, SSH, VPN, reverse proxy, or
additional installed service.

Moof configuration remains exactly:

```text
Endpoint: 43.142.242.195:7443
API key:  <32 random bytes, Base64URL>
```

## Protocol

Use `Noise_NNpsk0_25519_ChaChaPoly_SHA256`. The API key is the 32-byte PSK and
never crosses the network.

1. Moof connects over TCP.
2. It sends:

```text
magic "MOOF" | version | keyID | Noise handshake message
```

`keyID` is the first 8 bytes of `SHA-256(API key)` and lets the server select
the key. It is not secret.

3. The Noise handshake authenticates both ends, provides forward secrecy, and
   derives bidirectional encryption keys.
4. All subsequent traffic is length-prefixed and encrypted/authenticated.

```text
u32 frameLength | encrypted(type + JSON payload)
```

Limit frames to 64 KiB. Use one ordered stream. A reconnect always starts a new
Noise session.

## Application Messages

The decrypted payload is small and versioned:

- `notify`: `requestID`, `idempotencyKey`, title, body, source, optional action.
- `sync`: `lastEventID`.
- `ack`: `eventID`.
- `event`: inbound WeChat message or delivery result.
- `ping` / `pong`.

The server assigns a durable monotonically increasing `eventID` to every inbound
event and outbound status change.

- `notify` is acknowledged only after the server has persisted it.
- Moof retries an unacknowledged `notify` with the same `idempotencyKey`.
- After reconnect, Moof sends `sync(lastEventID)`; the server first drains missed
  events, then resumes live pushes.
- Moof advances `lastEventID` only after processing an event. Delivery is
  at-least-once, with client-side deduplication by `eventID`.

## Moof Client

Moof needs a small connection actor around `NWConnection`:

- `NWConnection` with plain TCP; `URLSession` and ATS are not involved.
- API key in Keychain; endpoint in preferences.
- On launch, wake, or network change: connect and immediately send `sync`.
- On sleep or path loss: cancel the connection; never assume it survives sleep.
- Reconnect with exponential backoff and jitter, capped around 30 seconds.
- Send a heartbeat every 25–30 seconds; reconnect after ten seconds without a
  response.
- Persist the pending outbound queue and `lastEventID`.

The Go gateway remains the sole owner of the iLink bot token, long-poll cursor,
`context_token`, outbound queue, and inbound event store.

The only real cost is implementing a small framed protocol and using a vetted
Noise implementation. Do not create your own cipher construction. If
certificates were acceptable, pinned TLS plus a simple HTTP API would require
less code; under the stated constraints, Noise over TCP is the cleaner design.
