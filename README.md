# Kodi PVR Repository

Dieses Projekt ist eine Schablone fuer ein eigenes Kodi-Repository mit
plattformabhaengigen PVR-Binary-Add-ons fuer Kodi Omega und spaeter Piers.

## Zielstruktur

Kodi erwartet ein installierbares Repository-Add-on und pro Kodi-Version einen
Feed mit `addons.xml`, `addons.xml.md5` und Add-on-Zips.

```text
repository.bg/
  addon.xml
  repository.bg-0.1.0.zip
omega/
  addons.xml
  addons.xml.md5
  pvr.meinaddon+windows-x86_64/
    pvr.meinaddon-1.0.0.zip
  pvr.meinaddon+android-aarch64/
    pvr.meinaddon-1.0.0.zip
piers/
  addons.xml
  addons.xml.md5
```

Fuer Binary/PVR-Add-ons ist die Plattformtrennung wichtig. Die offiziellen
Kodi-Binary-Repositories verwenden Verzeichnisse nach dem Muster:

```text
addon.id+platform/addon.id-version.zip
```

Das `addon.xml` im Zip muss dieselbe Plattform in
`<extension point="xbmc.addon.metadata"><platform>...</platform>` enthalten.
Dadurch zeigt Kodi nur die Add-ons an, die zur laufenden Plattform passen.

## Einrichten

1. `repo.config.json` anpassen:
   - `repository.id`
   - `repository.name`
   - `repository.providerName`
   - `repository.baseUrl`
2. PVR-Zips nach `omega/<addonid>+<platform>/` legen.
3. Optional Piers-Zips nach `piers/<addonid>+<platform>/` legen.
4. Alternativ aus einem GitHub-Release importieren:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\import-github-release.ps1 -Repository owner/repo -ReleaseTag v1.0.0-omega
```

5. Validieren:

```powershell
.\scripts\validate-repository.ps1
```

6. Repository-Dateien bauen:

```powershell
.\scripts\build-repository.ps1
```

Danach koennen `repository.*`, `omega` und spaeter `piers` auf einen HTTPS-Host
gelegt werden, zum Beispiel GitHub Pages oder einen eigenen Webserver.

## Automatisierung

Der Workflow `.github/workflows/import-pvr-satip.yml` kann neue Releases aus
`blauesgruen/pvr.satip` importieren, validieren, `addons.xml` neu bauen und die
Aenderungen committen.

Details stehen in:

```text
docs/automation.md
docs/pvr-addon-chat-text.md
```

## Plattformnamen

Kodi kennt unter anderem:

```text
windows-i686
windows-x86_64
android-armv7
android-aarch64
osx-x86_64
osx-arm64
linux
ios-armv7
ios-aarch64
tvos-aarch64
```

Fuer Linux liefert das offizielle Kodi-Repo Binary-PVR-Add-ons haeufig nicht als
ZIP fuer jede Distribution aus. Je nach Zielsystem kann dort ein Distributions-
Paket sinnvoller sein. Wenn du Linux-Zips anbietest, muss das Binary zur Kodi-
ABI und zur Zielplattform passen.

## Offizielle Anforderungen, die diese Schablone abbildet

- `addon.xml` hat eindeutige lowercase IDs und semantische Versionen.
- Das Repository-Add-on nutzt `xbmc.addon.repository` mit getrennten `dir`
  Eintraegen fuer Omega und Piers.
- Jeder Feed hat eine Master-Datei `addons.xml` und eine geaenderte
  `addons.xml.md5`.
- Online-Auslieferung ist ZIP-basiert.
- HTTPS ist vorgesehen.
- Die Plattformfilterung passiert ueber `<platform>` im Add-on-Metadatenblock.
- Die Binary-PVR-Zips bleiben plattformspezifisch getrennt.

## Quellen

- Kodi Wiki: Add-on repositories
- Kodi Wiki: Addon.xml
- Kodi Wiki: Submitting Add-ons
- Team Kodi: xbmc/repo-binary-addons, Branches Omega und Piers
- Kodi Mirror: `/addons/omega/` als Referenz fuer `addon.id+platform`
