# Text fuer den PVR-Addon-Chat

Das BG-Repository ist online:

```text
GitHub:
https://github.com/blauesgruen/BG-Repository

Kodi-/Pages-URL:
https://blauesgruen.github.io/BG-Repository/

Installierbares Repository-ZIP:
https://blauesgruen.github.io/BG-Repository/repository.bg/repository.bg-0.3.0.zip
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
  startet Linux, Windows, CoreELEC und Android
  verhindert die fruehen BG-Trigger der Einzelworkflows
  wartet auf alle Plattform-Workflows
  triggert BG danach genau einmal
```

So importiert BG nicht zu frueh, wenn noch Plattform-ZIPs fehlen.

BG importiert anhand des Assetnamens in ein gemeinsames `omega/addons.xml`:

```text
pvr.satip.coreelec-ng      -> id pvr.satip.coreelec-ng
pvr.satip.coreelec-ne      -> id pvr.satip.coreelec-ne
pvr.satip.libreelec-rpi4-aarch64 -> id pvr.satip.libreelec-rpi4-aarch64
pvr.satip.linux-x86_64     -> id pvr.satip.linux-x86_64
windows-x64                -> id pvr.satip
android-aarch64            -> id pvr.satip
android-armv7              -> id pvr.satip
```

Die ZIPs muessen diese Plattformwerte im `addon.xml` haben:

```text
pvr.satip.coreelec-ng:      linux
pvr.satip.coreelec-ne:      linux
pvr.satip.libreelec-rpi4-aarch64: linux
pvr.satip.linux-x86_64:     linux
pvr.satip Windows:          windows-x86_64
pvr.satip Android aarch64:  android-aarch64
pvr.satip Android armv7:    android-armv7
```

Der Plattformwert darf nicht leer sein. Linux/CoreELEC verwenden bewusst
`<platform>linux</platform>`. Die Architektur wird ueber Addon-ID und Namen
sichtbar gemacht.

BG-Repository entfernt vor einem Import vorhandene SAT>IP-Zielordner aus dem
Omega-Feed. Dadurch bleiben keine alten Plattform-ZIPs im Feed liegen, wenn sie
im aktuellen Release nicht mehr vorhanden sind.

Die Version im ZIP muss zur Release-Version passen, zum Beispiel:

```xml
<addon id="pvr.satip" version="0.1.0" ...>
```

Danach macht BG automatisch:

```text
Release-Assets herunterladen
Assetnamen den Zielordnern zuordnen
gueltige ZIPs importieren
Repository validieren
addons.xml neu bauen
Aenderungen committen
Kodi-Nutzern Updates anbieten
```
