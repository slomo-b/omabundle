# Security-Audit: omabundle

Stand: 2026-11-10 · Version 0.1.0 · Umfang: CLI, Adapter, Desktop-Handler,
MIME-Integration, Ledger. Eine GUI gibt es nicht (bewusst entfernt).

## Bedrohungsmodell

**Angreifer:** liefert eine Datei (AppImage, Tarball, Flatpak, Arch-Paket) über
Download, Chat oder USB. Der Angreifer kontrolliert den **Inhalt** der Datei
und alle darin enthaltenen Namen, Metadaten, Pfade, Symlinks und Größen. Er
kontrolliert **nicht** den Code von omabundle, nicht die Shell-Konfiguration
und hat keinen lokalen Account.

**Ziele:** Codeausführung als Benutzer oder root, Ausbrechen aus dem
Installationsverzeichnis, Überschreiben/Löschen fremder Dateien, Hijack von
Dateizuordnungen, Ausblenden bösartiger Aktionen, Ressourcen-Erschöpfung
(Disk/Inodes), Terminal-/UI-Injection.

**Vertrauensgrenzen:**

| Zone | Vertrauen |
|---|---|
| omabundle-Code, Systembinaries (`unsquashfs`, `bsdtar`, `jq`, …) | vertrauenswürdig |
| heruntergeladene Datei und ihre Metadaten | **nicht** vertrauenswürdig |
| Ledger `~/.local/state/omabundle/db.json` | benutzerschreibbar, wird trotzdem validiert |
| Upstream-Paketquellen (Flatpak-Repo, pacman-Paket) | außerhalb des Modells |

**Nicht im Modell:** ein bereits kompromittierter Benutzeraccount, ein
kompromittierter Kernel/FUSE/Squashfs-Treiber, bösartige Systembinaries,
Schwachstellen in Flatpak/pacman selbst sowie das spätere **Ausführen** einer
installierten Anwendung. Wer eine Datei doppelklickt, entscheidet sich bewusst
dafür, sie zu installieren; gestartet wird sie erst durch den Benutzer.

## Gefundene Punkte und Behebung

Schweregrade: **K** kritisch, **H** hoch, **M** mittel, **N** niedrig,
**I** informativ.

| ID | Schwere | Befund | Behebung | Status |
|---|---|---|---|---|
| F1 | K | AppImage-Metadaten wurden durch Ausführen des mitgelieferten Runtimes gelesen (`--appimage-extract`). Eine präparierte Datei konnte beim bloßen Installieren beliebigen Code als Benutzer ausführen. | Metadaten werden mit `unsquashfs -o <offset> -cat` gelesen. Der Runtime-Fallback wurde **entfernt**; fehlt `squashfs-tools`, wird die Installation verweigert. | behoben |
| F2 | H | `.DirIcon` konnte ein Symlink auf `/etc/passwd` sein und wurde als Icon ins Benutzerverzeichnis kopiert (Informationsleck). | `unsquashfs -cat` folgt keinen Symlinks; `install_icon` löst den Pfad auf, verlangt Aufenthalt im Extraktionsbaum, reguläre Datei, ≤ 4 MiB und MIME-Typ `image/png`/`image/svg+xml`. | behoben |
| F3 | H | `.desktop`-Felder (Name, Comment, MimeType, Categories, StartupWMClass) flossen ungefiltert in generierte `.desktop`-Dateien. MIME-Typen mit `;`, Leerzeichen, `\n`, `<script>` oder `../` erzeugten ungültige/irreführende Einträge. | `clean_text`, `desktop_text` (Backslash-Escaping), `sanitize_mime_list` (Syntax, Dedupe, max. 20), `sanitize_categories` (Whitelist, sonst `X-`-Namespace), `is_safe_slug`, `desktop_quote` (verdoppelt `%`). `desktop-file-validate` bleibt als zweite Schranke. | behoben |
| F4 | H | `install` registrierte die vom Paket behaupteten MIME-Typen per `xdg-mime default` als **Standard**. Ein bösartiges AppImage konnte damit z. B. `text/plain`, `application/pdf` oder `application/x-appimage` übernehmen (Persistenz/Handler-Hijack). | Standard-Registrierung entfernt. Der `.desktop`-Eintrag nennt `MimeType=` weiterhin, sodass „Öffnen mit“ funktioniert; die Standardwahl trifft der Benutzer. `remove` räumt veraltete Zuordnungen auf. | behoben |
| F5 | H | `remove` vertraute dem `prefix` aus dem benutzerschreibbaren Ledger und führte `rm -rf` aus. `$PREFIX/../../…` bestand die reine String-Prüfung. | `prefix_is_safe` löst mit `realpath -m` auf und verlangt exakt `<prefix>/<slug>/<version>`. `doctor` prüft dasselbe. Mit Canary-Datei getestet. | behoben |
| F6 | H | Ein portables Archiv mit genau einem Top-Level-Symlink (z. B. `bundle -> $HOME`) konnte die Wurzel-Erkennung täuschen; `cp -a "$root/."` hätte außerhalb des Extraktionsordners kopiert. | Top-Level-Symlink wird verworfen; `root` wird aufgelöst und muss im Extraktionsordner liegen. | behoben |
| F7 | H | Das Startprogramm eines portablen Archivs durfte ein Symlink auf ein Systembinary (z. B. `/bin/sh`) sein und wurde als Menüeintrag registriert. | `launcher` wird aufgelöst und muss im Archivbaum liegen, sonst Abbruch. | behoben |
| F8 | M | Der Handler baute für Arch-Pakete einen Shell-Befehl. Dateinamen mit `$(…)`, Backticks, `;`, Leerzeichen oder Quotes waren ohne korrekte Quotierung gefährlich. | `printf %q` für CLI und Datei, Übergabe als ein Argument; getestet mit allen genannten Metazeichen — keine Ausführung. | behoben |
| F9 | M | Dateinamen mit Steuerzeichen/Newlines konnten Benachrichtigungen oder das Handler-Log verfälschen (Terminal-/UI-Injection, Log-Spoofing). | `clean()` entfernt C0-Steuerzeichen und wandelt Newlines in Leerzeichen; Logeinträge nutzen `%q`; Meldungen als reiner Text gerendert. | behoben |
| F10 | M | Ressourcen-Erschöpfung: portables Entpacken ohne Grenzen (Inodes/Disk), AppImage-Metadaten konnten beliebig große Einträge dekomprimieren. | Portable: max. 20.000 Einträge, Größensumme aus `bsdtar -tv`, Vergleich mit freiem Platz. AppImage: `-cat` mit `head -c` (64 KiB Desktop, 4 MiB Icon), max. 50/30 Kandidaten, Listing-Cap 400. | behoben |
| F11 | M | Terminal-Escape-Injection über Ledger-/Metadatenwerte in `list`, `detect`, `step`-Ausgaben. | `jq @tsv` für Tabellen, `tr -d` für Steuerzeichen, `clean_text` für `detect` und Flatpak-Version, Regex-Whitelist für `pkgver`. | behoben |
| F12 | M | Parallele Installationen konnten das Ledger überschreiben (lost update/kaputtes JSON). | `flock` auf `install.lock` (60 s) plus DB-Lock; Slug-Validierung bei `remove`. | behoben |
| F13 | M | `mktempdir` wurde per Command-Substitution aufgerufen; die Cleanup-Liste entstand in einer Subshell, der EXIT-Trap sah sie nie. Jede Installation hinterließ ein `/tmp/omabundle.*`-Verzeichnis (unbegrenztes Wachstum). | `mktempdir <varname>` mit Nameref, Aufruf ohne Subshell; EXIT-Trap räumt auf. Nach der Regression keine Rückstände. | behoben |
| F14 | M | Dateirechte hingen vom umask ab; State-Verzeichnis, Ledger und Handler-Log konnten für andere Benutzer lesbar sein. | `umask 077` in CLI und Handler, State `700`, Ledger/Log `600`, Lockdown bei jedem `ledger_init`. | behoben |
| F15 | N | FIFO/Gerätedatei als „Installationsdatei“ konnte Prozesse blockieren. | `install`/`detect` verlangen eine reguläre Datei (`-f`). | behoben |
| F16 | N | `desktop_text` maskierte Backslashes nicht; `.desktop`-Strings kennen `\n`, `\t`, `\\`. | Backslashes werden vor dem Schreiben verdoppelt. | behoben |
| F17 | N | Extrem lange oder leere Namen erzeugten überlange/ungültige Slugs. | `slugify` kappt auf 64 Zeichen; `is_safe_slug` prüft Länge und Zeichensatz; sonst Fallback aus Dateiname, sonst Abbruch. | behoben |
| F18 | N | `.snap` (nacktes SquashFS bei Offset 0) wurde nicht erkannt und erhielt keine hilfreiche Ablehnung. | `hsqs` bei Offset 0 → `snap`; `application/vnd.snap` ist jetzt im Handler, damit der Doppelklick die Begründung zeigt. | behoben |
| F19 | N | `register_mimetypes` erhielt die ungefilterte Liste, obwohl die `.desktop`-Datei sanitisiert war. | Funktion entfernt (siehe F4); Zuordnungen entstehen nur noch über den sanitisierten `.desktop`-Eintrag. | behoben |
| F20 | N | `integration enable` konnte durch `pipefail` abbrechen, wenn `desktop-file-validate` nur einen Hinweis ausgab. | Validator-Aufrufe mit `|| true` entkoppelt. | behoben |
| F21 | N | Flatpak-App-ID wurde vor der Validierung ausgegeben (Terminal-Escape möglich). | Validierung vor `step`; Version durch `clean_text`. | behoben |
| F22 | N | `remove` konnte über einen Symlink im Prefix-Verzeichnis nach außen zeigen. | Durch `prefix_is_safe` (F5) abgedeckt; mit Symlink-Canary getestet. | behoben |
| F23 | I | Arch-Pakete laufen mit root (pacman-Skripte/Hooks). | Kein stiller Weg: Bestätigung im CLI, sichtbares Terminal mit Passwortabfrage, `sudo` nur dort. `--noconfirm` betrifft nur pacman-Rückfragen. | bewusst |
| F24 | I | Eine GUI könnte dynamische Texte als Rich Text interpretieren oder Befehle aus Strings bauen. | Die QML-Oberfläche wurde entfernt; es gibt nur CLI und den unsichtbaren Handler. Beide übergeben Argumente als Arrays, der eine Terminal-Aufruf wird mit `%q`/`shellQuote` gebaut. | entfällt |
| F25 | I | Tar-Traversal (`..`, absolute Pfade, Schreiben durch Symlinks). | `bsdtar` blockiert alle drei Fälle (mit präparierten Archiven getestet); zusätzlich Wurzel-/Launcher-Containment (F6/F7). | geprüft |
| F26 | I | Führt das Installieren eines AppImage es aus? | Nein: Quellmodus blieb bei präpariertem Fixture `644` und unverändert; nur `unsquashfs` liest. | geprüft |
| F27 | I | Options-Injection in `omarchy-notification-send` (`--exec=…` als Text). | Headline/Description sind positional und mit festen Präfixen; Test mit `--exec=` führte nichts aus. | geprüft |
| F28 | I | Deinstallation hinterlässt MIME-Standardzuordnungen. | `remove_app_from_mimeapps` entfernt den Eintrag aus allen Listen in `mimeapps.list`. | behoben |
| F29 | I | AppImages sind nicht signiert; Flatpak-/Arch-Pakete stammen von Upstream. | Keine kryptografische Prüfung von AppImages möglich (Format sieht sie nicht vor); SHA-256 wird im Ledger gespeichert. Flatpak nutzt GPG des Repos, pacman die `SigLevel`-Konfiguration. Das bleibt eine Vertrauensentscheidung des Benutzers. | dokumentiert |

## Verifizierte Angriffe

Reproduzierbare Fixtures, alle ohne Schaden ausgeführt:

| Test | Ergebnis |
|---|---|
| AppImage mit `.desktop`-Injection (`ESC[2J`, `<script>`, `../../etc/passwd` als MIME) | ESC entfernt, MIME auf `text/plain;application/pdf` reduziert, Kategorie `X-Injected`, Validator sauber |
| AppImage mit `.DirIcon -> /etc/passwd` | Icon ignoriert, kein Zugriff auf das Ziel |
| AppImage mit 48 MiB großem Fake-`.desktop`/`.png` (komprimiert 64 KiB) | in 177 ms abgelehnt/capped, 0 KiB zusätzlicher Platzverbrauch |
| AppImage ohne SquashFS-Tools | Installation verweigert (kein Ausführen der Datei) |
| Tarball mit `../escaped`, absolutem Pfad, Symlink-Traversal | von `bsdtar` blockiert, Extraktion scheitert |
| Tarball mit `bundle -> /tmp/outside` als einzigem Top-Level-Eintrag | „keine ausführbare Datei“ / Containment-Abbruch |
| Tarball mit `AppRun -> /bin/sh` | „Startprogramm verweist aus dem Archiv heraus“ |
| Tarball mit 20.001 Einträgen | vor dem Entpacken abgelehnt |
| Ledger-Prefix `…/opt/../../victim` und `…/opt/slug/../../victim` | `remove` verweigert, Canary-Datei unverändert |
| Ledger-Prefix als Symlink auf ein Opferverzeichnis | `remove` verweigert, Canary unverändert |
| Dateinamen `$(touch pwned).deb`, `` `touch pwned`.deb ``, `evil; touch pwned.deb`, ESC/Newline | nur Benachrichtigung, keine Ausführung, Log korrekt gequotet |
| `gio open` auf AppImage (echter Doppelklick-Pfad) | still installiert, Notification, Ledger, Menüeintrag |
| `gio open` auf `.deb`, `.snap` | nur Benachrichtigung mit Begründung |
| Wiederholtes Öffnen desselben AppImage | idempotent, keine Duplikate |
| `integration disable` / `enable` | GIO-MIME fällt zurück bzw. wird wieder gesetzt; `mimeapps.list` sauber |
| Menü/Plugin nach Entfernen der GUI | kein `omabundle`-Eintrag mehr, Panel-Plugin deaktiviert und gelöscht |

## Härtung im Überblick

- **Keine Ausführung beim Installieren.** AppImage-Metadaten nur über
  `unsquashfs -cat`; keine Runtime, kein `--appimage-extract`.
- **Größen- und Mengenlimits** für alle vom Angreifer kontrollierten
  Lese-/Entpackvorgänge.
- **Containment**: Icons und portable Launcher müssen aufgelöst im
  Extraktionsbaum liegen. Ledger-Pfade müssen aufgelöst exakt
  `<prefix>/<slug>/<version>` sein.
- **Sanitisierung** aller Textfelder vor `.desktop`, Benachrichtigung, Log und
  Terminaltabelle; keine Shell-Interpolation von Dateinamen.
- **Keine Standard-MIME-Übernahme** durch installierte Bundles.
- **Rechte**: `umask 077`, State `700`, Ledger/Log `600`; `flock` gegen
  parallele Läufe.
- **Privilegien**: `sudo`/`pacman` nur nach Bestätigung in einem sichtbaren
  Terminal; der Hintergrund-Handler startet nie `sudo`.
- **Aufräumen**: EXIT-Trap entfernt temporäre Bäume; `remove` entfernt
  Ledger-Eintrag, Prefix, Menüeintrag, Icon, Symlink und MIME-Zuordnungen.

## Verbleibende Risiken

1. **Installieren ist eine Vertrauensentscheidung.** Ein AppImage wird beim
   Doppelklick ohne Rückfrage installiert (so gewünscht). Es wird dabei nicht
   ausgeführt, aber später beim Start. Nur Dateien aus vertrauenswürdigen
   Quellen öffnen; alternativ `omabundle integration disable`.
2. **Upstream-Code bleibt Upstream-Code.** Flatpak-Apps und Arch-Pakete
   installieren fremde Software; pacman-Hooks laufen als root. omabundle kann
   das nicht sandboxen und tut nicht so, als könnte es das.
3. **Parser-Abhängigkeiten.** `unsquashfs`, `bsdtar`, `file` und die
   Icon-/Desktop-Parser sind Systempakete aus Arch. Schwachstellen dort werden
   über Systemupdates geschlossen; omabundle begrenzt nur die Eingabegröße.
4. **Keine AppImage-Signaturprüfung.** Das Format erzwingt keine Signaturen.
   Die SHA-256-Summe im Ledger dient der Nachvollziehbarkeit, nicht der
   Authentizität.
5. **Gleicher Benutzer = gleiche Rechte.** Wer den Account kontrolliert, kann
   Ledger, `.desktop`-Dateien und `~/.local/bin` ändern. Das ist keine
   Grenze, die ein Benutzerwerkzeug schützen kann.
6. **Umgebungsvariablen/PATH.** omabundle ruft Systemwerkzeuge über `PATH` auf.
   Ein manipuliertes Login-Environment liegt außerhalb des Modells.

## Prüfbefehle

```bash
# keine Reste, konsistentes Ledger
omabundle doctor

# Format ohne Nebenwirkungen erkennen
omabundle detect ~/Downloads/datei

# Doppelklick-Pfad prüfen (ohne Dateimanager)
gio info ~/Downloads/datei | grep standard::content-type
gio mime application/x-appimage

# Integration ein-/ausschalten
omabundle integration status
omabundle integration disable
omabundle integration enable
```
