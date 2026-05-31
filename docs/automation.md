# Automation

BG-Repository is online here:

```text
https://github.com/blauesgruen/BG-Repository
https://blauesgruen.github.io/BG-Repository/
```

The install ZIP is:

```text
https://blauesgruen.github.io/BG-Repository/repository.bg/repository.bg-0.1.0.zip
```

## Import Workflow

The workflow `.github/workflows/import-pvr-satip.yml` imports release assets from
`blauesgruen/pvr.satip`.

It does this:

```text
1. download ZIP assets from the pvr.satip release
2. read each ZIP's pvr.satip/addon.xml
3. import assets with a valid platform into omega/
4. validate the Kodi repository
5. rebuild addons.xml
6. commit and push changes only when files changed
```

The install ZIP under `repository.bg/` is rebuilt on every repository build so
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
  start Linux, Windows and CoreELEC workflows
  suppress early BG triggers in those child workflows
  wait until all platform workflows finished successfully
  trigger BG-Repository once after all ZIPs are uploaded
```

This avoids importing a release before all expected platform ZIPs are present.

## Expected Platforms

The current platform values expected in `addon.xml` are:

```text
Windows:              windows-x86_64
CoreELEC Amlogic-ne:  linux-aarch64
CoreELEC Amlogic-ng:  linux-armv7
```

The platform value must not be empty.

For CoreELEC Amlogic-ng, BG-Repository also publishes a compatibility package
with `<platform>linux</platform>` generated from the `linux-armv7` release ZIP.
This is needed because the CoreELEC/Kodi repository browser matches the broad
`linux` platform, not `linux-armv7`, when listing repository contents.

Do not import a generic Linux x86_64 ZIP as `<platform>linux</platform>` into
the same feed. It can be offered to CoreELEC ARM devices and install the wrong
binary.

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
