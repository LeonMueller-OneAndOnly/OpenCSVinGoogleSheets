# CSVtoSheets

Eine lokale macOS-App, die CSV- und TSV-Dateien als neue Google-Sheets-Dateien hochlaedt und das Ergebnis im Standardbrowser oeffnet.

## Voraussetzungen

- [mise](https://mise.jdx.dev/)
- Ein Google-Cloud-Projekt mit aktivierter Google Drive API
- Ein OAuth-Client vom Typ **Desktop-App**

## Google OAuth einrichten

1. In der Google Cloud Console einen OAuth-Zustimmungsbildschirm konfigurieren und die Google Drive API aktivieren.
2. Einen OAuth-Client vom Typ **Desktop-App** erstellen.
3. Die heruntergeladene Client-Datei als `credentials.json` im Projektstamm ablegen. Sie wird nicht eingecheckt.

Die Anwendung fordert nur den Scope `https://www.googleapis.com/auth/drive.file` an. Sie kann damit nur Dateien verwalten, die sie selbst erstellt oder die ueber sie geoeffnet wurden. Beim ersten Upload erstellt sie im Google Drive einen Ordner `Sheets`; alle erzeugten Tabellen werden dort abgelegt.

## Entwicklung

```sh
mise install
mise run build
./bin/CSVtoSheets /Pfad/zur/umsatz.csv
```

Beim ersten Lauf oeffnet sich die Google-Anmeldung. Das Token wird mit Berechtigung `0600` unter `~/Library/Application Support/CSVtoSheets/token.json` gespeichert. Es enthaelt keine CSV-Daten.

Mehrere Dateien werden nacheinander verarbeitet:

```sh
./bin/CSVtoSheets datei1.csv datei2.tsv
```

## macOS-App bauen

```sh
mise run app
open dist
```

Das Ergebnis liegt unter `dist/CSVtoSheets.app`. `credentials.json` wird beim Bauen in das App-Bundle aufgenommen, falls sie im Projektstamm liegt. Die App deklariert `.csv` und `.tsv` als Dokumenttypen. Ein nativer macOS-Launcher nimmt Finder-Dateiuebergaben entgegen und ruft die Go-Anwendung mit den Dateipfaden auf. Nach dem Verschieben in `Programme` kann sie im Finder ueber **Informationen > Oeffnen mit > Alle aendern** als Standard-App zugeordnet werden.

Die nicht signierte private App muss beim ersten Oeffnen gegebenenfalls mit Rechtsklick > **Oeffnen** bestaetigt werden.

## Konfiguration

Mit `CSV_TO_SHEETS_CREDENTIALS=/sicherer/pfad/credentials.json` kann ein anderer Ort fuer die OAuth-Zugangsdaten verwendet werden. Die lokale CSV-Datei wird nie geloescht und jede Ausfuehrung erstellt ein neues Google Sheet im Google-Drive-Ordner `Sheets`.
