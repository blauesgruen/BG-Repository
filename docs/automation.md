# Automation

BG-Repository is online here:

```text
https://github.com/blauesgruen/BG-Repository
https://blauesgruen.github.io/BG-Repository/
```

The install ZIP is:

```text
repository.bg/repository.bg-0.4.0.zip
```

## Import Workflow

The workflow `.github/workflows/import-pvr-satip.yml` imports release assets from
`blauesgruen/pvr.satip` into the selected Kodi feed.

It does this:

```text
1. resolve release tag and feed
2. download ZIP assets from the pvr.satip release
3. read each ZIP's root addon.xml
4. map each asset to its target directory by asset filename
5. require the complete target set for the selected feed
6. validate the Kodi repository
7. rebuild feed and repository metadata
8. commit and push changes only when files changed
```

The repository install ZIP is rebuilt by `scripts/build-repository.ps1` so
changes to repository add-on metadata and feeds are included.

The workflow supports:

```text
workflow_dispatch
repository_dispatch
```

The dispatch event is:

```text
event_type: pvr-satip-release
client_payload.release_tag: <release_tag>
client_payload.feed: omega|piers
```

For backward compatibility, a dispatch without `feed` imports into `omega`.

## Secrets

This repository needs:

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

`Release All` selects one generation profile and starts the same platform
workflows for Omega and Piers:

```text
Linux
Windows
CoreELEC
LibreELEC
Android
```

After all platform workflows finish successfully, it triggers BG-Repository
once with the release tag and the selected feed. This avoids importing a
release before all expected platform ZIPs are present.

## Feeds

The configured feeds are:

```text
omega: Kodi 21.x
piers: Kodi 22.x
```

The common targets are:

```text
android-aarch64
android-armv7
libreelec-rpi4-aarch64
linux-x86_64
windows-x86_64
```

CoreELEC differs by Kodi generation:

```text
omega: coreelec-ne, coreelec-ng
piers: coreelec-no
```

The platform values expected in `addon.xml` are:

```text
CoreELEC variants:             linux
LibreELEC RPi4 aarch64:        linux
Linux x86_64:                  linux
Windows x86_64:                windows-x86_64
Android aarch64:               android-aarch64
Android armv7:                 android-armv7
```

Before importing a release, BG-Repository removes existing SAT>IP target
directories only from the selected feed. This prevents stale packages while
leaving the other Kodi generation untouched.

## Manual Import

Manual import is possible for either feed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\import-github-release.ps1 -Repository blauesgruen/pvr.satip -ReleaseTag v0.1.0-omega -FeedPath omega
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\import-github-release.ps1 -Repository blauesgruen/pvr.satip -ReleaseTag v0.1.0-piers -FeedPath piers
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repository.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-repository.ps1
```

During import, a temporary report is written under:

```text
incoming/blauesgruen_pvr.satip/<release-tag>/asset-report.json
```

`incoming/` is ignored and is not committed to the public repository.
