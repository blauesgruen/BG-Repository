# Text fuer den PVR-Addon-Chat

Wir bauen ein eigenes Kodi-Repository fuer `pvr.satip`. Damit Kodi spaeter nur
die Add-ons anbietet, die zum System des Nutzers passen, muessen die Release-
Assets bestimmte Regeln einhalten.

Bitte beim Bauen der PVR-Zips beachten:

1. Jedes Zielsystem braucht ein eigenes ZIP.

Beispiele:

```text
pvr.satip-0.1.1-windows-x64.zip
pvr.satip-0.1.1-linux-x86_64.zip
pvr.satip-0.1.1-21.3-Omega-Amlogic-ne.zip
pvr.satip-0.1.1-21.3-Omega-Amlogic-ng.zip
```

2. Im ZIP muss `pvr.satip/addon.xml` liegen.

3. Die Version im `addon.xml` muss zur Release-Version passen.

Beispiel:

```xml
<addon id="pvr.satip" version="0.1.1" ...>
```

4. Im Metadata-Block muss ein korrekter Plattformwert stehen.

Beispiel Windows:

```xml
<extension point="xbmc.addon.metadata">
  <platform>windows-x86_64</platform>
</extension>
```

Beispiel Linux:

```xml
<extension point="xbmc.addon.metadata">
  <platform>linux</platform>
</extension>
```

5. Der Plattformwert darf nicht leer sein.

Aktuell sind die beiden Amlogic-Zips nicht automatisch importierbar, weil dort
`<platform>` leer ist. Dadurch kann Kodi sie nicht sauber einem System zuordnen.

6. Wenn Amlogic-ne und Amlogic-ng automatisch getrennt angeboten werden sollen,
muss geklaert werden, welche Kodi-/CoreELEC-Plattformwerte dafuer korrekt sind.
Solange beide denselben Add-on-ID-Wert `pvr.satip` haben und keinen eindeutigen
Plattformwert besitzen, kann das Kodi-Repository sie nicht offiziell sauber
filtern.

7. Nach dem Erstellen und Hochladen aller Release-Assets soll das PVR-Repo das
Kodi-Repository triggern.

Beispiel-Schritt fuer GitHub Actions:

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

Das Ergebnis soll sein:

```text
PVR-Release wird gebaut
Release-Assets werden hochgeladen
Kodi-Repository wird automatisch getriggert
Kodi-Repository importiert die neuen Zips
addons.xml wird neu gebaut
Kodi-Nutzer bekommen automatisch Updates
```
