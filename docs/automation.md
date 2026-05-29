# Automatischer Release-Import

Dieses Repository kann neue `pvr.satip`-Releases automatisch uebernehmen.

## Voraussetzung

Das Kodi-Repository muss auf GitHub liegen.

In diesem Kodi-Repository muss ein Secret angelegt werden:

```text
PVR_RELEASE_TOKEN
```

Der Token braucht Leserechte auf:

```text
blauesgruen/pvr.satip
```

Wenn das PVR-Repo privat ist, reicht der normale `GITHUB_TOKEN` des Kodi-Repos
nicht aus.

## Manueller Start

In GitHub:

```text
Actions -> Import pvr.satip release -> Run workflow
```

Dann den Release-Tag eingeben:

```text
v0.1.1-omega
```

Der Workflow macht dann:

```text
1. Release-Zips herunterladen
2. gueltige Plattform-Zips nach omega/ importieren
3. Repository validieren
4. addons.xml neu bauen
5. Aenderungen committen und pushen
```

## Automatischer Start aus dem PVR-Repo

Das PVR-Repo kann nach dem Upload aller Release-Assets ein Signal an dieses
Repository senden.

Das Signal ist:

```text
repository_dispatch
event_type: pvr-satip-release
payload: release_tag
```

Beispiel:

```yaml
- name: Trigger Kodi repository import
  env:
    GH_TOKEN: ${{ secrets.KODI_REPO_DISPATCH_TOKEN }}
    RELEASE_TAG: ${{ github.event.release.tag_name }}
  run: |
    gh api repos/blauesgruen/BG-Repository/dispatches \
      --method POST \
      --field event_type=pvr-satip-release \
      --field client_payload[release_tag]="$RELEASE_TAG"
```

Wenn das Repository spaeter unter einem anderen Owner liegt, muss
`blauesgruen/BG-Repository` entsprechend ersetzt werden.

`KODI_REPO_DISPATCH_TOKEN` liegt im PVR-Repo und braucht Schreibrechte auf dieses
Kodi-Repository, damit es den Dispatch ausloesen darf.

## Wichtig fuer Amlogic

Die aktuellen Amlogic-Zips werden vom Import noch abgelehnt, weil im `addon.xml`
kein Plattformwert steht.

Der Report wird waehrend des Imports hier erzeugt:

```text
incoming/blauesgruen_pvr.satip/<release-tag>/asset-report.json
```

Der `incoming/`-Ordner wird nicht ins oeffentliche Kodi-Repository committed.
