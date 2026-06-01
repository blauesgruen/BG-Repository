# Automation

BG-Repository is online here:

```text
https://github.com/blauesgruen/BG-Repository
https://blauesgruen.github.io/BG-Repository/
```

The install ZIP is:

```text
repository.bg/repository.bg-0.3.0.zip
```

## Import Workflow

The workflow `.github/workflows/import-pvr-satip.yml` imports release assets from
`blauesgruen/pvr.satip`.

It does this:

```text
1. download ZIP assets from the pvr.satip release
2. read each ZIP's root addon.xml
3. map each asset to its target directory by asset filename
4. validate the Kodi repository
5. rebuild addons.xml
6. commit and push changes only when files changed
```

The repository install ZIP is rebuilt by `scripts/build-repository.ps1` so
changes to repository add-on assets such as `icon.png` are included immediately.

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

## Omega Feed

`omega/addons.xml` is the single Kodi feed. Linux/ELEC variants use distinct
add-on IDs so Kodi can show them as separate choices.

## Expected Assets And Platforms

The current platform values expected in `addon.xml` are:

```text
Asset pvr.satip.coreelec-ng:      id pvr.satip.coreelec-ng,      platform linux
Asset pvr.satip.coreelec-ne:      id pvr.satip.coreelec-ne,      platform linux
Asset pvr.satip.linux-x86_64:     id pvr.satip.linux-x86_64,     platform linux
Asset contains windows-x64:       id pvr.satip,                  platform windows-x86_64
Asset contains android-aarch64:   id pvr.satip,                  platform android-aarch64
Asset contains android-armv7:     id pvr.satip,                  platform android-armv7
```

The platform value must not be empty.

Linux and CoreELEC ZIPs intentionally use `<platform>linux</platform>`. The
architecture is made visible by the add-on ID and name, not by a Linux
architecture platform token in `addon.xml`.

Before importing a release, BG-Repository removes existing SAT>IP target
directories from the Omega feed. This prevents stale packages from remaining
when the current release no longer contains them.

## Manual Import

Manual import is still possible:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\import-github-release.ps1 -Repository blauesgruen/pvr.satip -ReleaseTag v0.1.0-omega
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repository.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-repository.ps1
```

During import, a temporary report is written under:

```text
incoming/blauesgruen_pvr.satip/<release-tag>/asset-report.json
```

`incoming/` is ignored and is not committed to the public repository.
