# Text fuer den PVR-Addon-Chat

Das BG-Repository ist online:

```text
GitHub:
https://github.com/blauesgruen/BG-Repository

Kodi-/Pages-URL:
https://blauesgruen.github.io/BG-Repository/

Installierbares Repository-ZIP:
https://blauesgruen.github.io/BG-Repository/repository.bg/repository.bg-0.1.1.zip
```

Das PVR-Repo soll nach neuen Release-Uploads das BG-Repository triggern.

Verwendet wird:

```text
event_type: pvr-satip-release
client_payload.release_tag: <release_tag>
```

Secret im PVR-Repo:

```text
KODI_REPO_DISPATCH_TOKEN
```

Der Token muss `repository_dispatch` auf dieses Repository ausloesen duerfen:

```text
blauesgruen/BG-Repository
```

Der Trigger-Schritt im PVR-Repo:

```yaml
- name: Trigger BG-Repository import
  env:
    GH_TOKEN: ${{ secrets.KODI_REPO_DISPATCH_TOKEN }}
    RELEASE_TAG: ${{ github.event.release.tag_name }}
  run: |
    gh api repos/blauesgruen/BG-Repository/dispatches \
      --method POST \
      --field event_type=pvr-satip-release \
      --field client_payload[release_tag]="$RELEASE_TAG"
```

Die Workflow-Logik im PVR-Repo soll so bleiben:

```text
Direkt gestartete Einzelworkflows:
  bauen ihre Plattform
  laden ihr ZIP ins Release hoch
  triggern BG danach selbst

Release All:
  startet Linux, Windows und CoreELEC
  verhindert die fruehen BG-Trigger der Einzelworkflows
  wartet auf alle Plattform-Workflows
  triggert BG danach genau einmal
```

So importiert BG nicht zu frueh, wenn noch Plattform-ZIPs fehlen.

Die ZIPs muessen diese Plattformwerte im `addon.xml` haben:

```text
Android 64-bit:       android-aarch64
Android 32-bit:       android-armv7
CoreELEC Amlogic-ne:  linux-aarch64
CoreELEC Amlogic-ng:  linux-armv7
Linux 64-bit:         linux-x86_64
Windows 64-bit:       windows-x86_64
```

Der Plattformwert darf nicht leer sein.

Ein echtes Linux-x86_64-ZIP darf nicht als generisches
`<platform>linux</platform>` gebaut werden. Es muss
`<platform>linux-x86_64</platform>` verwenden. BG-Repository blockiert das
breite `linux`, damit kein Paket dem falschen System angeboten wird.

BG-Repository entfernt vor einem Import vorhandene Plattformordner des Addons.
Dadurch bleiben keine alten Plattform-ZIPs im Feed liegen, wenn sie im aktuellen
Release nicht mehr vorhanden sind.

Die Version im ZIP muss zur Release-Version passen, zum Beispiel:

```xml
<addon id="pvr.satip" version="0.1.1" ...>
```

Danach macht BG automatisch:

```text
Release-Assets herunterladen
gueltige Plattform-ZIPs importieren
Repository validieren
addons.xml neu bauen
Aenderungen committen
Kodi-Nutzern Updates anbieten
```
