# omabundle

omabundle installiert portable Linux-Programme **nativ** auf Omarchy
(Arch Linux) und entfernt sie wieder sauber. Kein Container, keine
Konvertierung, kein Fremd-Paketmanager, **keine GUI** und keine laufende
Shell-Abhängigkeit: nach dem Einrichten bleibt das System garantiert.

```
omabundle install ~/Downloads/Obsidian-1.5.3.AppImage
omabundle install ./app.flatpak          # oder .flatpakref oder org.gimp.GIMP
omabundle list
omabundle remove obsidian
omabundle doctor
```

## Was installiert werden kann

| Datei | Inhalt | Ablage |
|---|---|---|
| `.AppImage` (Type 1/2) | ELF + `AI\x01`/`AI\x02` bzw. SquashFS | `~/.local/opt/<slug>/<version>/` |
| `.pkg.tar.{zst,xz,gz}` | `.PKGINFO` im Tar | `pacman` im sichtbaren Terminal |
| `.flatpak` | `metadata` mit `[Application]` | Flatpak |
| `.flatpakref` | `[Flatpak Ref]`-Datei | Flatpak |
| Flatpak App-ID | z. B. `org.gimp.GIMP` | Flatpak |
| `.tar.{zst,xz,gz}`, `.zip` und andere Archive, die `bsdtar` lesen kann | Inhalt mit `AppRun` oder `bin/` | `~/.local/opt/<slug>/<version>/app/` |

Bewusst nicht installiert (mit Begründung, keine stillen Fehler):

| Format | Grund |
|---|---|
| `.deb`, `.rpm` | läuft nur mit `distrobox` oder `debtap` |
| `.snap` | auf Arch/Omarchy nicht unterstützt |
| `.run` (self-extracting) | schreibt unkontrolliert ins System |
| nackte ELF/ausführbare Datei | keine Metadaten, bitte als Tarball beziehen |

`omabundle detect <datei>` nennt genau das Format samt Grund, ohne etwas zu
verändern.

## Installation des Tools

### GitHub mit `install.sh` (empfohlen)

```bash
git clone -b v0.1.2 --depth 1 https://github.com/slomo-b/omabundle
cd omabundle/packaging
./install.sh              # installiert nach ~/.local, ohne sudo
omabundle integration enable   # Doppelklick-Installation aktivieren
```

Alternativ direkt aus dem Release (ohne `git`) — die `.sha256`-Datei liegt im
Release und wird von `install.sh` nicht benötigt:

```bash
curl -LO https://github.com/slomo-b/omabundle/releases/download/v0.1.2/install.sh
sha256sum install.sh      # 7d66bda3fb68f8edbcb386a5a39ae2e7cf6fdf3ed8a0b63d408a31b0528da2ab
bash install.sh           # nie curl | bash, immer lokal ausführen
omabundle integration enable
```

`install.sh` kopiert die Skripte nach `~/.local/share/omabundle` und legt die
Links `omabundle`, `omab` und `omabundle-handle` in `~/.local/bin` an. Mit
`./install.sh --enable` wird die Doppelklick-Integration gleich mit
eingerichtet; `./install.sh uninstall` entfernt alles wieder. Kein einziger
privilegierter Befehl wird ausgeführt. Die Doppelklick-Integration findet den
Handler über `PATH`, siehe `bin/omabundle` → `integration_handler_path`.

### pacman über `makepkg`

```bash
git clone -b v0.1.2 --depth 1 https://github.com/slomo-b/omabundle
cd omabundle/packaging
makepkg -si               # installiert systemweit über pacman, sudo im Terminal
omabundle integration enable   # danach als normaler Benutzer
```

Entfernen: `sudo pacman -Rns omabundle` und danach
`omabundle integration disable`.

### AUR

Ein AUR-Paket folgt, sobald die AUR-Registrierung wieder offen ist. Das
`packaging/PKGBUILD` ist dafür vorbereitet (`packaging/README.md` enthält den
Ablauf).

## Doppelklick-Installation

```bash
omabundle integration enable
omabundle integration status
omabundle integration disable
```

| Datei | Verhalten |
|---|---|
| `.AppImage`, portable Archive | still installiert, kurze Benachrichtigung, Klick auf die Meldung startet das Programm |
| `.flatpak`, `.flatpakref` | dito |
| `.pkg.tar.*` | öffnet ein sichtbares Terminal mit Passwortabfrage, weil `pacman` sudo braucht |
| `.deb`, `.rpm`, `.snap`, `.run` | Benachrichtigung mit Begründung, sonst nichts |

Bewusst **nicht** als Handler registriert sind `.tar.gz`, `.zip`, `.zst` und
 nackte ELF-Dateien, sonst würde omabundle jeden Download übernehmen. Für
diese Formate bleibt `omabundle install` (oder `omabundle detect`).

## Was bei einer Installation passiert

1. **Erkennen** über Magic Bytes, nie über den Dateinamen.
2. **Metadaten lesen** (Name, Comment, Kategorien, MIME-Typen, Icon) mit
   `unsquashfs -cat` oder aus `.desktop`-Dateien — niemals durch Ausführen
   der heruntergeladenen Datei.
3. **Ablage** unter `~/.local/opt/<slug>/<version>/`, Symlink nach
   `~/.local/bin/<slug>`.
4. **Integrieren**: `.desktop`-Eintrag (validiert mit
   `desktop-file-validate`), Icon unter `~/.local/share/icons/hicolor`,
   Cache-Refresh. Die Einträge deklarieren die MIME-Typen des Programms,
   überschreiben also **keine** Standard-Zuordnungen. Ein installiertes
   Bundle kann nie "alle PDFs übernehmen".
5. **Ledger** in `~/.local/state/omabundle/db.json` — nur was dort steht,
   kann `remove` wieder löschen.

Damit ist das Entfernen exakt: `omabundle remove <slug>` löscht nur, was
`install` angelegt hat. `omabundle doctor` findet tote Symlinks, fehlende
Icons und verwaiste Ledger-Einträge.

## Kommandozeile

```bash
omabundle install <datei|app-id>   # AppImage, .pkg.tar.*, Flatpak, Tarball
omabundle list                      # Ledger anzeigen
omabundle remove <slug>             # sauber entfernen
omabundle doctor                    # alles prüfen
omabundle detect <datei>            # Format erkennen, ohne etwas zu tun
omabundle integration enable|status|disable
```

Optionen: `-n --dry-run` (verändert nichts, auch keine `chmod` auf der
Quelldatei), `--json` (maschinenlesbar), `-y --yes` (Rückfragen überspringen,
wichtig für pacman-Aufrufe).

## Dateisystem

| Pfad | Zweck |
|---|---|
| `~/.local/opt/<slug>/<version>/` | installierte Programme |
| `~/.local/bin/<slug>` | Befehl startet das Programm |
| `~/.local/share/applications/<slug>.desktop` | Menüeintrag |
| `~/.local/share/icons/hicolor/.../<slug>.png` / `svg` | Icon |
| `~/.local/share/applications/omabundle-handle.desktop` | der unsichtbare Handler |
| `~/.local/share/mime/packages/omabundle.xml` | `application/x-appimage` und Freunde |
| `~/.config/mimeapps.list` | die 9 aktivierten MIME-Typen |
| `~/.local/state/omabundle/db.json` | Ledger |
| `~/.local/state/omabundle/handle.log` | Handler-Protokoll |

## Sicherheit

Der volle Audit-Bericht steht in [SECURITY.md](SECURITY.md): Bedrohungsmodell,
gefundene Punkte (F1–F29), Behebung und verbleibende Risiken. Kernpunkte:

- **Kein Code aus dem Paket wird beim Installieren ausgeführt.** AppImage-
  Metadaten werden mit `unsquashfs -cat` gelesen.
- **Textfelder** (Name, Comment, Kategorie, MIME) gefiltert und bereinigt,
  bevor sie in `.desktop`-Dateien oder Benachrichtigungen landen.
- **Ledger-Pfade** gegen `~/.local/opt` mit `realpath` geprüft; ein kompro-
  mittierter Eintrag kann nicht nach außen zeigen.
- **Archive** werden auf Dateianzahl und Gesamtgröße limitiert; AppImage-
  Metadaten werden pro Datei größenbegrenzt gelesen.
- **Privilegien**: `sudo`/`pacman` nur nach Bestätigung in einem sichtbaren
  Terminal. Der Hintergrund-Handler startet nie `sudo`.
- **Startklick auf Benachrichtigung** startet das Programm als Argv-Array,
  nicht als Shell-String.

## Hintergrundbetrieb

omabundle hat bewusst **keine grafische Oberfläche**. Es gibt genau zwei Wege:

1. **Doppelklick** im Dateimanager auf eine heruntergeladene Datei — nach
   einmaligem `omabundle integration enable` läuft die Installation still im
   Hintergrund. Die Erfolgsmeldung lässt sich anklicken und startet das
   installierte Programm direkt.
2. **Kommandozeile** für alles Weitere (siehe oben).

Kein Fenster, kein Panel, kein Hintergrunddienst, kein Plugin im
`omarchy-shell`-Prozess.

## Lizenz

MIT License.

## Roadmap

- [x] P0: Detection, AppImage, Arch-Paket, Flatpak, Portable, Ledger, Remove, Doctor
- [x] P1: Doppelklick-Installation (MIME-Handler, still + Benachrichtigung)
- [x] Security-Audit: F1–F29
- [x] `install.sh` für Install-Ansätze ohne pacman
- [ ] P2: `omabundle update` (nur wenn Quelle/URL bekannt)
- [ ] P3: `.deb`/`.rpm`-Hinweisadapter mit distrobox-Anbindung
- [ ] AUR-Paket, sobald die Registrierung wieder offen ist
