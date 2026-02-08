# AutoDevice Upload Action

A GitHub Action that uploads mobile app builds (`.apk` / `.ipa`) to [autodevice.io](https://autodevice.io).

## Usage

```yaml
- uses: autodevice/upload-action@v1
  with:
    api-key: ${{ secrets.AUTODEVICE_API_KEY }}
    package-name: com.example.app
    build-path: app/build/outputs/apk/release/app-release.apk
```

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `api-key` | Yes | — | AutoDevice API key |
| `package-name` | Yes | — | Application package name (e.g. `com.example.app`) |
| `build-path` | Yes | — | Path to the `.apk` or `.ipa` file |
| `api-url` | No | `https://autodevice.io` | AutoDevice API base URL |

## Full workflow example

```yaml
name: Upload to AutoDevice

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-upload:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # …your build steps here…

      - uses: autodevice/upload-action@v1
        with:
          api-key: ${{ secrets.AUTODEVICE_API_KEY }}
          package-name: com.example.app
          build-path: app/build/outputs/apk/release/app-release.apk
```

## How it works

The action follows a three-step API flow:

1. **Start upload** — requests a presigned upload URL from AutoDevice
2. **Upload binary** — uploads the build file directly to cloud storage
3. **Confirm upload** — notifies AutoDevice that the upload is complete

Git metadata (commit SHA, branch, repository) is automatically attached. For pull requests, the action uses the PR head SHA rather than the merge commit SHA.
