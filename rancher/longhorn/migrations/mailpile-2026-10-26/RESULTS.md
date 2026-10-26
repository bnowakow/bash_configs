# Mailpile migration — blocked before data copy

Preparation updated the target request to 12Gi data + 256Mi keys and created an
idle transfer helper. Repeated k3s/API failures prevented validation; the helper
cleanup request was not accepted. No app shutdown/copy/cutover occurred.
Mailpile remains on original local claims; both HTTPS hosts responded 302.
See [handoff](HANDOFF.md) and [major-action log](ACTIONS.log).

No completion marker or production migration count was added.
