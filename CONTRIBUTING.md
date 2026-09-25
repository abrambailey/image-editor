# Contributing

Image Editor is a small, experimental Mac app maintained as time allows. Bug
reports and focused pull requests are welcome; response times and feature
requests are not guaranteed. Open an issue before starting a large feature.

## Development

Use macOS 14 or newer with Apple's Command Line Tools. Start with
`./scripts/run.sh`; see the README for the local model download and optional AI
connection. No API key is needed to build the app or run the tests.

Before submitting a change, run:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/window-test.sh
```

The window test requires a logged-in Mac desktop. For machines without desktop
services, `./scripts/test.sh --headless` skips clipboard checks explicitly. The
optional real-image model test requires a local fixture; AI tests use a mock
service and never make paid requests. CI compiles the app and runs the headless
regression suite without downloading the model or publishing an app bundle.

Keep changes focused and explain the behavior they fix. Add regression coverage
for changes that affect image output, Undo, file handling, or protection of
unexported work. For interface changes, check the default light window and the
minimum-size dark window, including keyboard behavior.

## Reporting a bug

Include the macOS version, Apple Silicon or Intel architecture, steps to
reproduce, and expected versus actual behavior. Use a small synthetic or owned
image when a fixture helps. Remove personal paths and private content from logs
and screenshots. Never post API keys, `.env` files, or signing certificates.

Only contribute code and images you have the right to share. Contributions to
the application are under the MIT license in `LICENSE`; retain all third-party
license notices. Keep builds, downloaded models, and private test imagery out of
commits.
