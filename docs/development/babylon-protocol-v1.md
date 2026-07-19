# Babylon Capture Protocol v1

Rockxy owns the receiver contract. Babylon implements the client without importing Rockxy source.

## Discovery and transport

- Bonjour service: `_Rockxy._tcp`
- TCP port: `10909` for Bonjour and simulator `localhost`
- Frame: 8-byte unsigned big-endian payload length followed by the JSON frame
- Maximum JSON frame: 72 MiB (75,497,472 bytes), providing encoding headroom for a 50 MiB captured body
- All captured payloads require the secure frame below. There is no cleartext legacy fallback.

## Pairing and encryption

Rockxy generates 32 cryptographically random bytes, displays them as a 64-character lowercase hex pairing token, and stores the UTF-8 token in Keychain. The token is never sent over the connection or logged.

Each frame key is HKDF-SHA256:

- Input key material: UTF-8 pairing token
- Salt: UTF-8 `rockxy-babylon-v1`
- Info: UTF-8 `<clientID>:<sessionID>`
- Output: 32 bytes

The encrypted payload uses AES-GCM. Additional authenticated data is UTF-8:

`1:<clientID>:<sessionID>:<messageID>:<sequence>`

## Secure frame

`Data` values use the standard JSON `Codable` base64 representation.

`messageID`, `sessionID`, and `clientID` are non-empty UTF-8 strings capped at 128, 128, and 512 bytes respectively. They cannot contain `:`, ASCII control bytes, or DEL, so the HKDF info and AAD delimiters remain unambiguous.

```json
{
  "protocolVersion": 1,
  "messageID": "UUID",
  "sessionID": "UUID",
  "clientID": "stable client ID",
  "sequence": 1,
  "compression": "gzip",
  "nonce": "base64 12 bytes",
  "ciphertext": "base64",
  "tag": "base64 16 bytes"
}
```

`sequence` must increase monotonically per `clientID` and `sessionID`. Rockxy treats an authenticated retry with the same message ID and sequence as idempotent and sends its ACK again without reprocessing the payload. A reused sequence with a different ID, or reused ID with a different sequence, is rejected. Rockxy remembers the most recent 2,048 message IDs, and this replay state survives TCP reconnects while Rockxy is running.

After AES-GCM authentication, Rockxy GZIP-decompresses the plaintext once with a 96 MiB output cap, then decodes:

```json
{
  "messageType": "connection|traffic|websocket|runtime|heartbeat|ack|error",
  "sentAt": 0,
  "content": "base64 JSON payload"
}
```

Rockxy sends an encrypted `ack` for every accepted non-ACK message. ACK content is `{"messageID":"<accepted ID>"}`. Regenerating the pairing token disconnects clients and clears replay/session state.

## Payload compatibility

`connection`, `traffic`, `websocket`, and `runtime` content use Babylon's current package JSON field names. Rockxy defines local decoding DTOs and does not link Babylon. A connection message must precede traffic, WebSocket, or runtime messages so Rockxy can establish project and device identity.

WebSocket messages correlate to the parent traffic package by `TrafficPackage.id`. Runtime identifiers use the existing snake-case keys (`session_id`, `trace_id`, `step_id`, and `parent_step_id`).

Decoded request and response bodies are each limited to 50 MiB. WebSocket frames use Rockxy's 10 MiB per-frame and 100 MiB per-connection limits. The larger authenticated-envelope cap accounts for two nested JSON/base64 layers; GZIP reduces that representation before AES-GCM and the outer 72 MiB wire-frame cap.
