[English version](README.md)

# install-neovim

Distributionsunabhängiger Installer für Neovim. Der Schwerpunkt liegt auf Fedora-Atomic-Distributionen wie Silverblue, Kinoite und Bazzite.

## Überblick

Das Skript `install-neovim.sh` installiert Neovim ohne Root-Rechte in das Benutzerverzeichnis. Es bietet mehrere Installationsmethoden (Tarball, Flatpak, Paketmanager, Brew), automatische Versionsumschaltung und Rollback-Funktionen. Auf Atomic-Hosts ist die Standard-Tarball-Methode vorzuziehen, da sie keinen Neustart erfordert.

## Schnellstart

Skript herunterladen und ausführen:

```bash
./install-neovim.sh
```

Verfügbare Optionen anzeigen:

```bash
./install-neovim.sh --help
```

Vor einem echten Install die geplanten Änderungen prüfen:

```bash
./install-neovim.sh --dry-run
```

## Funktionsweise der Tarball-Methode (Standard)

Die Standard-Installationsmethode nutzt das offizielle Release-Tarball von GitHub:

- **Speicherort**: Alle Dateien bleiben im Benutzerverzeichnis (`$XDG_DATA_HOME/nvim-install`, standardmäßig `~/.local/share/nvim-install`)
- **Keine Root-Rechte**: Das Skript weigert sich, als Root ausgeführt zu werden
- **Keine Layering**: Auf Atomic-Hosts ist kein Neustart erforderlich
- **Integritätsprüfung**: Der sha256-Digest wird anhand der GitHub-Release-Metadaten überprüft
- **Versionsverwaltung**: Versionen werden unter `versions/<tag>/` speichert (nightly verwendet `nightly-<digest12>`)
- **Symlinks**: `current` und `previous` Symlinks ermöglichen Upgrades und Rollback
- **Ausführbare Binärdatei**: Das Skript prüft, dass die Binärdatei tatsächlich ausgeführt werden kann, bevor die Installation als erfolgreich gilt

Der Symlink `~/.local/bin/nvim` zeigt auf die aktuelle ausführbare Datei.

## Weitere Installationsmethoden

### Flatpak

```bash
./install-neovim.sh --method flatpak
```

Der Editor läuft in einer Sandbox und hat möglicherweise eingeschränkten Zugriff auf Dateisystem, Terminal und Zwischenablage.

Ausführung:

```bash
flatpak run io.neovim.nvim
```

### Paketmanager (dnf, apt-get, pacman, zypper, apk, xbps-install)

```bash
./install-neovim.sh --method package
```

**Auf Atomic-Hosts**: Das Skript fragt standardmäßig interaktiv, bevor es mit `rpm-ostree install` ein Layering durchführt (Standard: Nein, Fallback zur Tarball-Methode). Für nicht-interaktive Umgebungen:

```bash
./install-neovim.sh --method package --allow-layering
```

Nach dem Layering ist ein Neustart erforderlich.

### Brew

```bash
./install-neovim.sh --method brew
```

Voraussetzung: Homebrew muss installiert sein.

## Optionen

| Option | Beschreibung |
|--------|-------------|
| `--version <tag\|stable\|nightly>` | Release-Version installieren (Standard: `stable`). `<tag>` muss wie `v0.10.2` aussehen. |
| `--method <tarball\|flatpak\|package\|brew>` | Installationsmethode (Standard: `tarball`). |
| `--allow-layering` | Auf Atomic-Hosts: rpm-ostree-Layering ohne interaktive Abfrage aktivieren. Erfordert Neustart. |
| `--uninstall` | Tarball-Installation entfernen (Versionsverzeichnisse und Symlinks). |
| `--rollback` | Zur zuvor installierten Tarball-Version zurückwechseln. |
| `--check-deps` | Optionale Laufzeit-Abhängigkeiten überprüfen und Installationshinweise anzeigen. Keine Installation. |
| `--with-plugins` | Bestehende NvChad/lazy.nvim-Konfiguration mit Treesitter, Mason, Linting und Rechtschreibung erweitern. |
| `--no-sync` | Mit `--with-plugins`: Managed Files schreiben, Rechtschreibwörterbücher laden, aber Lazy/Mason-Installationen überspringen. |
| `--yes, -y` | Auf Bestätigungsabfragen mit „ja" antworten (uninstall, `--with-plugins` Write; **nicht** rpm-ostree-Layering). |
| `--dry-run` | Geplante Änderungen anzeigen, nichts ausführen. |
| `-h, --help` | Hilfe anzeigen. |

## Abhängigkeits-Überprüfung mit `--check-deps`

```bash
./install-neovim.sh --check-deps
```

Das Skript prüft auf folgende optionale Abhängigkeiten und meldet fehlende:

- `git`
- `ripgrep` (rg)
- `fd` (oder `fdfind`)
- C-Compiler (gcc oder clang)
- Zwischenablage-Werkzeug (xclip, xsel oder wl-clipboard)
- `npm` (Node.js, erforderlich für Mason npm-basierte Server wie html und cssls)
- `tree-sitter` CLI (erforderlich für nvim-treesitter main branch)

Das Skript zeigt paketmanager-spezifische Installationshinweise an, installiert diese Abhängigkeiten aber nie selbst.

**Hinweis**: Mason (Lazy-Plugin-Verwalter für LSP/DAP/Formatter) benötigt zusätzlich git, curl oder wget, tar/unzip/gzip und einen C-Compiler. Diese sind nur informativ; das Skript installiert sie nicht.

## Konfiguration mit `--with-plugins` erweitern

```bash
./install-neovim.sh --with-plugins
```

Diese Option erweitert eine bestehende NvChad oder lazy.nvim-Konfiguration:

### Was wird hinzugefügt

Das Skript schreibt zwei verwaltete Dateien (nur falls nicht vorhanden):

**`lua/plugins/extras.lua`** – Folgende Plugins und Konfigurationen:
- **nvim-treesitter**: Parser für lua, vim, vimdoc, bash, python, markdown, markdown_inline, powershell, yaml, json, html, css, regex
- **mason.nvim**: Paketmanager für Language Server und Linting-Tools: bash-language-server, lua-language-server, powershell-editor-services, shellcheck, shfmt, stylua, html-lsp, css-lsp
- **nvim-lint**: Linting für Shell-Skripte (shellcheck)
- **flash.nvim**: Schnelle Navigation
- **render-markdown.nvim**: Markdown-Rendering

**`lua/plugins/extras-spell.lua`** – Rechtschreibung:
- Lädt Wörterbücher für Englisch (en_us) und Deutsch (de_de)
- Aktiviert Rechtschreibprüfung automatisch für markdown, text, gitcommit

### Verhalten

- **Keine Überschreibung**: Existierende Dateien werden nicht verändert; nur fehlende Files werden geschrieben
- **Anforderungen**: 
  - Neovim muss bereits auf PATH sein oder durch dieses Skript installiert werden
  - Ein existierendes `lua/plugins/`-Verzeichnis ist erforderlich
  - Das Skript bootstrappt keine neue Konfiguration
- **Lazy und Mason**: Standardmäßig werden ein headless Lazy-Sync und eine headless Mason-Installation durchgeführt (kann mit `--no-sync` übersprungen werden)
- **Spell-Dateien**: Wörterbücher werden von ftp.nluug.nl heruntergeladen

### Zusätzliche Voraussetzungen

Für `--with-plugins` sind diese Tools erforderlich oder empfohlen:

- `tree-sitter` CLI (für nvim-treesitter, Hauptbranch)
- `pwsh` (PowerShell 7+, für powershell-editor-services)
- `fd` (oder `fdfind`, für NvChad/Telescope Datei-Picker)

Lautet: `./install-neovim.sh --check-deps` für alle erforderlichen Abhängigkeiten.

### Beispiele

Erweitern und Lazy/Mason installieren:

```bash
./install-neovim.sh --with-plugins
```

Nur Managed Files schreiben und Wörterbücher laden, Lazy/Mason überspringen:

```bash
./install-neovim.sh --with-plugins --no-sync --yes
```

## PATH-Konfiguration

Das Skript ändert Shell-Konfigurationsdateien (`.bashrc`, `.zshrc`, etc.) **nicht**. Sollte `~/.local/bin` nicht bereits in `PATH` sein, zeigt das Skript eine Warnung mit dem erforderlichen Export-Befehl an:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Diese Zeile muss manuell in die Shell-Konfigurationsdatei hinzugefügt werden.

## Deinstallation und Rollback

### Rollback zur vorherigen Version

```bash
./install-neovim.sh --rollback
```

### Neovim entfernen

```bash
./install-neovim.sh --uninstall
```

Das Skript entfernt nur die Tarball-Installation (das `nvim-install`-Verzeichnis und den Symlink `~/.local/bin/nvim`), nicht die Konfiguration unter `~/.config/nvim`.

## Voraussetzungen

Minimal erforderlich:

- `curl` oder `wget`
- `tar`

Optional:

- `jq` (zur effizienteren JSON-Verarbeitung; das Skript fällt auf `awk` zurück)

## Einschränkungen

- **Architektur**: Nur Linux x86_64 und aarch64 werden unterstützt
- **Root-Befugnisse**: Die Tarball-Methode weigert sich, als Root ausgeführt zu werden

## Lizenz

Dieses Projekt wird unter der MIT-Lizenz veröffentlicht. Details in der Datei [LICENSE](LICENSE).

---

**Autor**: [Pat9496](https://github.com/Pat9496)
