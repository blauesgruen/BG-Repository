# Text fuer den PVR-Addon-Chat

Das BG-Repository ist online:

```text
GitHub:
https://github.com/blauesgruen/BG-Repository

Kodi-/Pages-URL:
https://blauesgruen.github.io/BG-Repository/

Installierbares Repository-ZIP:
https://blauesgruen.github.io/BG-Repository/repository.bg/repository.bg-0.4.0.zip
```

Das PVR-Repo triggert nach einem vollstaendigen Release den Import in den zur
Kodi-Generation passenden Feed.

Verwendet wird:

```text
event_type: pvr-satip-release
client_payload.release_tag: <release_tag>
client_payload.feed: omega|piers
```

Secret im PVR-Repo:

```text
KODI_REPO_DISPATCH_TOKEN
```

Der Token muss `repository_dispatch` auf dieses Repository ausloesen duerfen:

```text
blauesgruen/BG-Repository
```

`Release All` verwendet fuer Omega und Piers dieselben Plattform-Workflows:

```text
Linux
Windows
CoreELEC
LibreELEC
Android
```

Die Generation waehlt dabei ein festes Build-Profil. Nach erfolgreichem
Abschluss aller Plattformen wird BG genau einmal mit Release-Tag und Feed
getriggert.

BG importiert in getrennte Feeds:

```text
omega -> Kodi 21.x
piers -> Kodi 22.x
```

Gemeinsame Ziele:

```text
pvr.satip.libreelec-rpi4-aarch64 -> id pvr.satip.libreelec-rpi4-aarch64
pvr.satip.linux-x86_64            -> id pvr.satip.linux-x86_64
windows-x64                       -> id pvr.satip
android-aarch64                   -> id pvr.satip
android-armv7                     -> id pvr.satip
```

CoreELEC unterscheidet sich je Generation:

```text
Omega: pvr.satip.coreelec-ne, pvr.satip.coreelec-ng
Piers: pvr.satip.coreelec-no
```

Die ZIPs muessen diese Plattformwerte im `addon.xml` haben:

```text
CoreELEC:                 linux
LibreELEC RPi4 aarch64:   linux
Linux x86_64:             linux
Windows:                  windows-x86_64
Android aarch64:          android-aarch64
Android armv7:            android-armv7
```

Vor einem Import entfernt BG vorhandene SAT>IP-Zielordner nur aus dem
gewaehlten Feed. Omega- und Piers-Pakete ueberschreiben sich dadurch nicht.

Die Version im ZIP muss zur Release-Version passen, zum Beispiel:

```xml
<addon id="pvr.satip" version="0.1.0" ...>
```

Danach macht BG automatisch:

```text
Release-Assets herunterladen
Assetnamen den Zielordnern zuordnen
vollstaendige Zielmenge fuer den Feed pruefen
gueltige ZIPs importieren
Repository validieren
Feed- und Repository-Metadaten neu bauen
Aenderungen committen
```
