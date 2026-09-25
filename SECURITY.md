# Security

Security fixes are maintained on the default branch as time allows. This is an
experimental source release; there is no guaranteed response time or support
for older revisions.

If this repository has GitHub private vulnerability reporting enabled, use
**Security → Report a vulnerability**. Otherwise, open an issue asking for a
private reporting channel without including exploit details or sensitive data.
Do not post credentials or private images in public issues.

Background removal runs locally after the build downloads the pinned model.
Opening an image URL contacts the supplied website. Optional AI editing sends
the visible canvas, instruction, and optional mask directly to OpenAI only when
Generate is selected. It uses the API key supplied by the user. Keys are held in
memory or saved explicitly to the Mac's Keychain, never in project files or
preferences. See the README for billing and cancellation behavior.
