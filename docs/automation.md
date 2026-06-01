# Automation

BG-Repository is online here:

```text
https://github.com/blauesgruen/BG-Repository
https://blauesgruen.github.io/BG-Repository/
```

Install ZIPs are generated per repository channel:

```text
repository.bg.coreelec-ng/repository.bg.coreelec-ng-0.2.0.zip
repository.bg.coreelec-ne/repository.bg.coreelec-ne-0.2.0.zip
repository.bg.linux-x86_64/repository.bg.linux-x86_64-0.2.0.zip
repository.bg.windows-x86_64/repository.bg.windows-x86_64-0.2.0.zip
repository.bg.android-aarch64/repository.bg.android-aarch64-0.2.0.zip
repository.bg.android-armv7/repository.bg.android-armv7-0.2.0.zip
```

## Import Workflow

The workflow `.github/workflows/import-pvr-satip.yml` imports release assets from
`blauesgruen/pvr.satip`.

It does this:

```text
1. download ZIP assets from the pvr.satip release
2. read each ZIP's pvr.satip/addon.xml
3. map each asset to its platform channel by asset filename
4. validate the Kodi repository
5. rebuild addons.xml
6. commit and push changes only when files changed
```

Repository install ZIPs are rebuilt by `scripts/build-repository.ps1` so changes
to repository add-on assets such as `icon.png` are included immediately.

The workflow supports:

```text
workflow_dispatch
repository_dispatch
```

The dispatch event is:

```text
event_type: pvr-satip-release
client_payload.release_tag: <release_tag>
```

## Secrets

This repository already has:

```text
PVR_RELEASE_TOKEN
```

That token is used by the BG-Repository workflow to read the private
`blauesgruen/pvr.satip` release assets.

The PVR repository needs:

```text
KODI_REPO_DISPATCH_TOKEN
```

That token must be able to trigger `repository_dispatch` on:

```text
blauesgruen/BG-Repository
```

## PVR Workflow Contract

The PVR repository is expected to behave like this:

```text
Direct single-platform workflows:
  build one platform
  upload its ZIP
  trigger BG-Repository after upload

Release All workflow:
  start Linux, Windows, CoreELEC and Android workflows
  suppress early BG triggers in those child workflows
  wait until all platform workflows finished successfully
  trigger BG-Repository once after all ZIPs are uploaded
```

This avoids importing a release before all expected platform ZIPs are present.

## Channels

`pvr.satip` binary packages are not published together in one shared
`omega/addons.xml`. Each target system has its own feed:

```text
omega/coreelec-ng/addons.xml
omega/coreelec-ne/addons.xml
omega/linux-x86_64/addons.xml
omega/windows-x86_64/addons.xml
omega/android-aarch64/addons.xml
omega/android-armv7/addons.xml
```

Each feed contains at most one `pvr.satip` entry for a given version.

## Expected Assets And Platforms

The current platform values expected in `addon.xml` are:

```text
Asset contains Amlogic-ng:     channel coreelec-ng,      platform linux
Asset contains Amlogic-ne:     channel coreelec-ne,      platform linux
Asset contains linux-x86_64:   channel linux-x86_64,    platform linux
Asset contains windows-x64:    channel windows-x86_64,  platform windows-x86_64
Asset contains android-aarch64: channel android-aarch64, platform android-aarch64
Asset contains android-armv7:   channel android-armv7,   platform android-armv7
```

The platform value must not be empty.

Linux and CoreELEC ZIPs intentionally use `<platform>linux</platform>`. The
architecture is selected by the repository channel, not by a Linux architecture
platform token in `addon.xml`.

Before importing a release, BG-Repository removes existing `pvr.satip` folders
from the channel feeds. This prevents stale packages from remaining in a channel
when the current release no longer contains them.

## Manual Import

Manual import is still possible:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\import-github-release.ps1 -Repository blauesgruen/pvr.satip -ReleaseTag v0.1.1-omega
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repository.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-repository.ps1
```

During import, a temporary report is written under:

```text
incoming/blauesgruen_pvr.satip/<release-tag>/asset-report.json
```

`incoming/` is ignored and is not committed to the public repository.
