# omabundle

Installiert portable Linux-Programme **nativ** auf Omarchy (Arch Linux) und
entfernt sie wieder sauber. Kein Container, keine Konvertierung, kein
Fremd-Paketmanager, **keine GUI**: alles läuft im Hintergrund über
Doppelklick oder die Kommandozeile.

```
omabundle install ~/Downloads/Obsidian-1.5.3.AppImage
omabundle install ./tool.pkg.tar.zst
omabundle install ./app.flatpak
omabundle install org.gimp.GIMP
omabundle list
omabundle doctor
omabundle remove obsidian
```

## Unterstützt

| Format | Erkennung | Ablage |
|---|---|---|
| `.AppImage` (Type 1/2) | ELF + `AI\x01/\x02` oder SquashFS-Payload | `~/.local/opt/<slug>/<version>/` |
| `.pkg.tar.{zst,xz,gz}` | `.PKGINFO` im Tar | pacman (`sudo`) |
| `.flatpak`, `.flatpakref`, App-ID | `metadata` bzw. `[Flatpak Ref]` | Flatpak |
| `.tar.*`, `.zip` mit `AppRun`/`bin/` | Archiv + Heuristik | `~/.local/opt/<slug>/<version>/app/` |

## Bewusst nicht unterstützt

`.deb`, `.rpm`, `.snap` und selbstentpackende `.run`-Installer. Die ersten
beiden brauchen einen fremden Paketmanager (Lösung: `distrobox` oder
`debtap`), `snap` ist auf Arch nicht unterstützt, und `.run`-Skripte
schreiben unkontrolliert ins System — genau der Weg zu einem kaputten Arch.

`omabundle detect <datei>` nennt das Format und den Grund für die Ablehnung,
ohne etwas zu verändern.

## Was bei einer Installation passiert

1. **Erkennen** über Magic Bytes, nicht über den Dateinamen.
2. **Metadaten lesen** (Name, Comment, Kategorien, MIME-Typen, Icon) aus dem
   AppImage bzw. dem mitgelieferten `.desktop`-Eintrag.
3. **Ablegen** unter `~/.local/opt/<slug>/<version>/`, Symlink nach
   `~/.local/bin/<slug>`.
4. **Integrieren**: `.desktop`-Eintrag (validiert mit
   `desktop-file-validate`), Icon in `~/.local/share/icons/hicolor`,
   Cache-Updates. Der Eintrag nennt die vom Programm deklarierten MIME-Typen,
   überschreibt aber **keine** Standard-Zuordnungen — sonst könnte ein
   installiertes Bundle z. B. alle PDFs übernehmen.
5. **Ledger** in `~/.local/state/omabundle/db.json` — nur was dort steht,
   kann `remove` wieder löschen.

## Design-Entscheidungen

- **Ledger statt Raten.** `remove` löscht nur, was `install` angelegt hat.
  `doctor` findet tote Symlinks, fehlende Icons und verwaiste Einträge.
- **Kein `sudo` im Hintergrund.** Privilegierte Schritte (pacman) laufen nur
  nach Bestätigung in einem sichtbaren Terminal über
  `omarchy-launch-floating-terminal-with-presentation`. Der stille
  Doppelklick-Handler startet niemals `sudo`.
- **Kein Auto-Download.** Quellen werden gespeichert, aber nicht automatisch
  nachgeladen.
- **Ehrliche Fehler.** `GLIBC_2.xx not found` oder fehlende `.so` sind nicht
  reparierbar; `doctor` und der Startpfad melden das, statt still zu brechen.
- **`--dry-run` verändert nichts** — auch keine `chmod` auf der Quelldatei.

## Voraussetzungen

- `bash`, `jq`, `bsdtar` (libarchive), `file`, `desktop-file-validate`,
  `flock`, `realpath` (auf Omarchy vorhanden)
- `squashfs-tools` (`unsquashfs`) — **Pflicht** für AppImages. Metadaten werden
  gelesen, ohne die Datei auszuführen: `omarchy pkg add squashfs-tools`
- `fuse2` nur für das *Ausführen* von AppImages: `omarchy pkg add fuse2`
- `flatpak` für Flatpaks: `omarchy pkg add flatpak`

Ohne `squashfs-tools` verweigert `omabundle` die AppImage-Installation
bewusst, statt die heruntergeladene Datei zum Auslesen der Metadaten
auszuführen.

## Doppelklick-Installation (Integration)

```bash
omabundle integration enable     # einmalig einrichten
omabundle integration status
omabundle integration disable
```

Danach reicht in Nautilus ein Doppelklick auf eine heruntergeladene Datei:

| Datei | Verhalten |
|---|---|
| `.AppImage` | wird **still installiert**, danach kurze Benachrichtigung, Start über App-Menü |
| `.flatpak`, `.flatpakref` | dito |
| `.pkg.tar.*` | öffnet ein Terminal mit Passwortabfrage (pacman braucht sudo) |
| `.deb`, `.rpm`, `.snap` | Benachrichtigung mit Begründung, sonst nichts |

Was `integration enable` anlegt (alles im Benutzerbereich, kein sudo):

- `~/.local/share/applications/omabundle-handle.desktop` — unsichtbarer Handler
  (`NoDisplay=true`) mit den passenden `MimeType`-Einträgen
- `~/.local/share/mime/packages/omabundle.xml` — MIME-Typ `application/x-appimage`
  (die Systemdatenbank stuft AppImages teils als `application/x-executable` ein)
- `xdg-mime default …` in `~/.config/mimeapps.list`

Technische Notiz: `xdg-mime query` nutzt `file` und ist hier unzuverlässig;
Nautilus nutzt **GIO**, und GIO liest die Benutzer-MIME-Datenbank. Getestet mit
`gio open` (derselbe Pfad wie ein Doppelklick) — Installation, Benachrichtigung
und Ledger-Eintrag funktionieren.

Bewusst **nicht** als Handler registriert: `.tar.gz`, `.zip`, `.zst` (würde
jedes Archiv übernehmen) sowie `.run` und nackte ELF-Dateien (würde alle
ausführbaren Dateien übernehmen). Für diese Formate bleibt `omabundle install`.
`.run` wird dort erkannt und mit Begründung abgelehnt.

## Installation des Tools

### AUR (empfohlen)

```bash
omarchy pkg aur add omabundle
omabundle integration enable
```

`omarchy pkg aur add` baut das Paket mit `makepkg` und installiert es mit
`pacman`; die sudo-Abfrage läuft im Terminal. `integration enable` danach als
normaler Benutzer ausführen — es richtet nur den MIME-Handler im
Benutzerbereich ein.

### Manuell aus dem Repo (Entwicklung)

```bash
git clone https://github.com/slomo-b/omabundle ~/Code/omabundle
mkdir -p ~/.local/bin
ln -sfn ~/Code/omabundle/bin/omabundle ~/.local/bin/omabundle
ln -sfn ~/Code/omabundle/bin/omabundle ~/.local/bin/omab
ln -sfn ~/Code/omabundle/bin/omabundle-handle ~/.local/bin/omabundle-handle
```

`omabundle-handle` muss im `PATH` liegen, weil der Desktop-Handler ihn über
den Dateinamen aufruft. Danach `omabundle integration enable` ausführen.

## Sicherheit

Der vollständige Audit-Bericht steht in [SECURITY.md](SECURITY.md): Bedrohungs-
modell, gefundene Punkte (F1–F29), Behebung und ausdrücklich verbleibende
Risiken. Kurzfassung:

- Installieren führt **keinen** Code aus dem Paket aus. AppImage-Metadaten
  werden mit `unsquashfs -cat` gelesen, nicht durch Starten des AppImage.
- Fremde Textfelder (Name, Comment, MIME-Typen, Kategorien) werden gefiltert,
  bevor sie in `.desktop`-Dateien oder Benachrichtigungen landen.
- Ledger-Pfade werden vor `rm -rf` mit `realpath` gegen `~/.local/opt`
  geprüft; kompromittierte JSON-Einträge können nicht nach außen zeigen.
- Archive werden vor dem Entpacken auf Dateianzahl und Größe geprüft;
  AppImage-Metadaten werden pro Datei größenbegrenzt gelesen.
- Privilegierte Schritte (`pacman`) laufen nie unsichtbar, sondern nur im
  sichtbaren Terminal nach Bestätigung.

## Hintergrundbetrieb

omabundle hat bewusst **keine grafische Oberfläche**. Es gibt genau zwei Wege:

1. **Doppelklick** im Dateimanager auf eine heruntergeladene Datei — nach
   einmaligem `omabundle integration enable` läuft die Installation still im
   Hintergrund. Die Erfolgsmeldung lässt sich anklicken und startet das
   installierte Programm direkt.
2. **Kommandozeile** für alles Weitere:

```bash
omabundle install <datei|app-id>
omabundle list
omabundle remove <slug>
omabundle doctor
omabundle integration enable|disable|status
```

Damit lässt sich omabundle wie ein normaler Systembaustein behandeln: einmal
einrichten, danach Programme per Doppelklick installieren und über die CLI
verwalten. Kein Fenster, kein Panel, kein Hintergrunddienst.

## Lizenz

MIT — siehe [LICENSE](LICENSE).

## Roadmap

- [x] P0: Detection, AppImage, Arch-Paket, Flatpak, Portable, Ledger, Remove, Doctor
- [x] P1: Doppelklick-Installation (MIME-Handler, still + Benachrichtigung)
- [x] Security-Audit: siehe [SECURITY.md](SECURITY.md)
- [ ] P2: `omabundle update` (nur wenn Quelle/URL bekannt)
- [ ] P3: `.deb`/`.rpm`-Hinweisadapter mit distrobox-Anbindung
