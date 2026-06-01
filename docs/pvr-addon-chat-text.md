# Text fuer den PVR-Addon-Chat

Das BG-Repository ist online:

```text
GitHub:
https://github.com/blauesgruen/BG-Repository

Kodi-/Pages-URL:
https://blauesgruen.github.io/BG-Repository/

Installierbare Repository-ZIPs:
CoreELEC Amlogic-ng:
https://blauesgruen.github.io/BG-Repository/repository.bg.coreelec-ng/repository.bg.coreelec-ng-0.2.1.zip

CoreELEC Amlogic-ne:
https://blauesgruen.github.io/BG-Repository/repository.bg.coreelec-ne/repository.bg.coreelec-ne-0.2.1.zip

Linux x86_64:
https://blauesgruen.github.io/BG-Repository/repository.bg.linux-x86_64/repository.bg.linux-x86_64-0.2.1.zip

Windows x86_64:
https://blauesgruen.github.io/BG-Repository/repository.bg.windows-x86_64/repository.bg.windows-x86_64-0.2.1.zip

Android aarch64:
https://blauesgruen.github.io/BG-Repository/repository.bg.android-aarch64/repository.bg.android-aarch64-0.2.1.zip

Android armv7:
https://blauesgruen.github.io/BG-Repository/repository.bg.android-armv7/repository.bg.android-armv7-0.2.1.zip
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

BG importiert anhand des Assetnamens in getrennte Kanaele:

```text
Amlogic-ng      -> omega/coreelec-ng/
Amlogic-ne      -> omega/coreelec-ne/
linux-x86_64    -> omega/linux-x86_64/
windows-x64     -> omega/windows-x86_64/
android-aarch64 -> omega/android-aarch64/
android-armv7   -> omega/android-armv7/
```

Die ZIPs muessen diese Plattformwerte im `addon.xml` haben:

```text
CoreELEC Amlogic-ng:  linux
CoreELEC Amlogic-ne:  linux
Linux x86_64:         linux
Windows x86_64:       windows-x86_64
Android aarch64:      android-aarch64
Android armv7:        android-armv7
```

Der Plattformwert darf nicht leer sein. Linux/CoreELEC verwenden bewusst
`<platform>linux</platform>`. Die Architektur wird ueber den getrennten
Repository-Kanal ausgewaehlt.

BG-Repository entfernt vor einem Import vorhandene `pvr.satip`-Ordner aus den
Kanaelen. Dadurch bleiben keine alten Plattform-ZIPs im Feed liegen, wenn sie im
aktuellen Release nicht mehr vorhanden sind.

Die Version im ZIP muss zur Release-Version passen, zum Beispiel:

```xml
<addon id="pvr.satip" version="0.1.1" ...>
```

Danach macht BG automatisch:

```text
Release-Assets herunterladen
Assetnamen den Kanaelen zuordnen
gueltige Kanal-ZIPs importieren
Repository validieren
addons.xml neu bauen
Aenderungen committen
Kodi-Nutzern Updates anbieten
```
