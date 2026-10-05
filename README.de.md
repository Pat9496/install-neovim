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

## Aliase für `vim` und `vi`

Standardmäßig erstellt das Skript bei der Tarball-Installation und beim Rollback zusätzliche Symlinks in `~/.local/bin`:

- `neovim` → zeigt auf die gleiche Binärdatei wie `nvim`
- `vim` → zeigt auf die gleiche Binärdatei wie `nvim`
- `vi` → zeigt auf die gleiche Binärdatei wie `nvim`

Dies erlaubt es, Neovim mit `vim` oder `vi` zu starten. Diese Aliase überlagern nur die System-Befehle (`/usr/bin/vim`, `/usr/bin/vi`), wenn `~/.local/bin` im PATH vor `/usr/bin` angeordnet ist. Sudo-Sitzungen und absolute Pfade (z. B. `/usr/bin/vi`) bleiben unberührt.

Existierende Dateien oder Symlinks, die auf andere Ziele verweisen (z. B. eine selbst verwaltete `vi`-Konfiguration), werden übersprungen.

Die Alias-Erstellung kann mit `--no-aliases` deaktiviert werden:

```bash
./install-neovim.sh --no-aliases
./install-neovim.sh --rollback --no-aliases
```

Diese Option gilt nur für die Tarball-Methode und `--rollback`. Andere Installationsmethoden (`flatpak`, `package`, `brew`) und die Aktionen `--uninstall`, `--check-deps`, `--install-deps` berühren Aliase nicht.

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
| `--install-deps` | Fehlende optional dependencies via Homebrew installieren (tree-sitter-cli). Nur wenn brew gefunden wird. Keine Installation von Homebrew selbst. Fragt um Bestätigung (Standard: Nein), außer mit `--yes/-y`. Ehrt `--dry-run`. Mit `--with-plugins` kombinierbar. Ausschließlich mit `--uninstall`, `--rollback`, `--check-deps`. |
| `--no-aliases` | Erstellen der `neovim`-, `vim`- und `vi`-Symlinks in ~/.local/bin überspringen (nur bei Tarball-Installation und `--rollback`; andere Methoden berühren Aliases nicht). Existierende Dateien und fremde Symlinks werden immer stehen gelassen. |
| `--with-plugins` | Bestehende NvChad/lazy.nvim-Konfiguration mit Treesitter, Mason, Linting und Rechtschreibung erweitern. |
| `--no-sync` | Mit `--with-plugins`: Managed Files schreiben, Rechtschreibwörterbücher laden, aber Lazy/Mason-Installationen überspringen. |
| `--yes, -y` | Auf Bestätigungsabfragen mit „ja" antworten (`--uninstall`, `--install-deps`, `--with-plugins`-Schreibvorgänge; **nicht** rpm-ostree-Layering). |
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

Das Skript zeigt paketmanager-spezifische Installationshinweise an. Für die `tree-sitter` CLI kann alternativ `./install-neovim.sh --install-deps` genutzt werden, um dieses Tool via Homebrew zu installieren (sofern Homebrew bereits eingerichtet ist).

**Hinweis**: Mason (Lazy-Plugin-Verwalter für LSP/DAP/Formatter) benötigt zusätzlich git, curl oder wget, tar/unzip/gzip und einen C-Compiler. Diese sind nur informativ; das Skript installiert sie nicht (ausgenommen `--install-deps` für die tree-sitter CLI).

## Konfiguration mit `--with-plugins` erweitern

```bash
./install-neovim.sh --with-plugins
```

Diese Option erweitert eine bestehende NvChad oder lazy.nvim-Konfiguration:

### Was wird hinzugefügt

Das Skript schreibt zwei verwaltete Dateien (nur falls nicht vorhanden):

**`lua/plugins/extras.lua`** – Folgende Plugins und Konfigurationen:
- **nvim-treesitter**: Parser für lua, vim, vimdoc, bash, python, markdown, markdown_inline, powershell, yaml, json, html, css, regex
- **mason.nvim**: Paketmanager für Language Server und Linting-Tools: bash-language-server, lua-language-server, shellcheck, shfmt, stylua, html-lsp, css-lsp
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
- `fd` (oder `fdfind`, für NvChad/Telescope Datei-Picker)

Die `tree-sitter` CLI kann über `./install-neovim.sh --install-deps` via Homebrew installiert werden (sofern brew bereits eingerichtet ist).

Alle fehlenden Abhängigkeiten überprüfen: `./install-neovim.sh --check-deps`

### Beispiele

Erweitern und Lazy/Mason installieren:

```bash
./install-neovim.sh --with-plugins
```

Nur Managed Files schreiben und Wörterbücher laden, Lazy/Mason überspringen:

```bash
./install-neovim.sh --with-plugins --no-sync --yes
```

Mit `--install-deps` kombinieren (Dependencies zuerst installieren):

```bash
./install-neovim.sh --install-deps --with-plugins
```

## Optionale Dependencies mit `--install-deps` installieren

```bash
./install-neovim.sh --install-deps
```

Diese Aktion installiert fehlende optionale Dependencies (tree-sitter-cli) ausschließlich über Homebrew:

- Findet Homebrew im PATH oder an den üblichen Linux-Homebrew-Orten (`/home/linuxbrew/.linuxbrew/bin/brew`, `~/.linuxbrew/bin/brew`)
- Installiert Homebrew selbst nicht und nutzt niemals sudo
- Prüft, welche Tools bereits vorhanden sind, und installiert nur das Fehlende
- Fragt um Bestätigung (Standard: Nein), es sei denn `--yes` oder `-y` wird übergeben
- Mit `--dry-run` wird der exakte Brew-Befehl angezeigt, ohne etwas zu installieren
- `--install-deps` ist eine eigenständige Aktion (installiert nicht Neovim)
- Kann mit `--with-plugins` kombiniert werden (Dependencies werden zuerst installiert, dann Plugins eingerichtet)
- Gegenseitig ausschließend mit `--uninstall`, `--rollback`, `--check-deps`

Beispiele:

```bash
./install-neovim.sh --install-deps
./install-neovim.sh --install-deps --yes
./install-neovim.sh --install-deps --with-plugins
./install-neovim.sh --install-deps --with-plugins --yes
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
- Homebrew (nur für `--install-deps` erforderlich; das Skript sucht nach brew im PATH oder an den üblichen Linux-Homebrew-Orten und installiert Homebrew selbst nicht)

## Einschränkungen

- **Architektur**: Nur Linux x86_64 und aarch64 werden unterstützt
- **Root-Befugnisse**: Die Tarball-Methode weigert sich, als Root ausgeführt zu werden

## Kurzreferenz

### Häufige Installer-Befehle

| Befehl | Zweck |
|--------|-------|
| `./install-neovim.sh` | Standard-Installation (stabile Version); Symlinks `neovim`, `vim`, `vi` werden angelegt |
| `./install-neovim.sh --dry-run` | Geplante Änderungen anzeigen, ohne zu installieren |
| `./install-neovim.sh --version nightly` | Nightly-Build installieren |
| `./install-neovim.sh --version v0.10.2` | Spezifische Version installieren |
| `./install-neovim.sh --no-aliases` | Standard-Installation ohne Symlinks für `neovim`, `vim`, `vi` |
| `./install-neovim.sh --check-deps` | Optionale Abhängigkeiten überprüfen |
| `./install-neovim.sh --install-deps` | Fehlende tree-sitter-CLI via Homebrew installieren (interaktive Bestätigung) |
| `./install-neovim.sh --install-deps --yes` | Fehlende tree-sitter-CLI via Homebrew installieren (ohne Bestätigung) |
| `./install-neovim.sh --install-deps --with-plugins` | Dependencies installieren, dann Plugins einrichten |
| `./install-neovim.sh --rollback` | Zur vorherigen Version zurückwechseln (Symlinks werden angelegt) |
| `./install-neovim.sh --rollback --no-aliases` | Rollback ohne Symlink-Erstellung |
| `./install-neovim.sh --uninstall` | Installation entfernen |
| `./install-neovim.sh --with-plugins` | Mit Plugins (Treesitter, Mason, LSP, Rechtschreibung) erweitern |
| `./install-neovim.sh --with-plugins --no-sync --yes` | Plugins konfigurieren, aber Lazy/Mason nicht synkronisieren |
| `./install-neovim.sh --method flatpak` | Flatpak-Installation |
| `./install-neovim.sh --method package --allow-layering` | RPM-OSTree-Layering ohne Bestätigung |

### Häufige Neovim-Befehle und Tastenkürzel

**Dateinavi­gation und Suche (Telescope & Tree)**

| Tastenkürzel | Modus | Funktion |
|---|---|---|
| `<Space>ff` | n | Dateien suchen |
| `<Space>fa` | n | Alle Dateien anzeigen (auch versteckte) |
| `<Space>fw` | n | Text in Dateien durchsuchen (live grep) |
| `<Space>fh` | n | Hilfeseiten durchsuchen |
| `<Space>fz` | n | In aktuellem Buffer suchen |
| `<Space>fo` | n | Zuletzt geöffnete Dateien |
| `<C-n>` | n | Dateibaum (nvim-tree) umschalten |
| `<Space>e` | n | Auf Dateibaum fokussieren |

**Buffer und Tabs**

| Tastenkürzel | Modus | Funktion |
|---|---|---|
| `<Space>b` | n | Neuer Buffer |
| `<Tab>` | n | Nächster Buffer |
| `<S-Tab>` | n | Vorheriger Buffer |
| `<Space>x` | n | Buffer schließen |

**LSP, Formatierung und Diagnose**

| Tastenkürzel | Modus | Funktion |
|---|---|---|
| `<Space>fm` | n, x | Datei formatieren |
| `<Space>ds` | n | Diagnose in Quickfix laden |
| `:Lazy` | n | Plugin-Manager öffnen |
| `:Mason` | n | LSP/Tools-Manager |
| `:MasonInstall <name>` | n | Spezifisches Tool installieren |
| `:checkhealth` | n | System-Health prüfen |
| `:TSInstall <parser>` | n | Treesitter-Parser installieren |
| `:TSUpdate` | n | Treesitter-Parser aktualisieren |

**Flash-Navigation (flash.nvim)**

| Tastenkürzel | Modus | Funktion |
|---|---|---|
| `s` | n, x, o | Zu Zeichen springen |
| `S` | n, x, o | Treesitter-Objekt anvisieren |
| `r` | o | Remote-Flash (in Operator-pending) |
| `R` | o, x | Treesitter-Suche |
| `<C-s>` | c | Flash in Suche umschalten |

**Rechtschreibprüfung (English + Deutsch)**

| Tastenkürzel | Modus | Funktion |
|---|---|---|
| `]s` | n | Nächster Fehler |
| `[s` | n | Vorheriger Fehler |
| `z=` | n | Vorschläge anzeigen |
| `zg` | n | Wort akzeptieren |
| `zw` | n | Wort als falsch markieren |
| `:set spell` | n | Rechtschreibung aktivieren |
| `:set nospell` | n | Rechtschreibung deaktivieren |

(Rechtschreibung wird automatisch für markdown, text und gitcommit aktiviert.)

**Fenster, Terminal und Extras**

| Tastenkürzel | Modus | Funktion |
|---|---|---|
| `<C-h/j/k/l>` | n | Zu Fenster wechseln (links/unten/oben/rechts) |
| `<Space>h` | n | Horizontales Terminal öffnen |
| `<Space>v` | n | Vertikales Terminal öffnen |
| `<A-i>` | n, t | Schwebendes Terminal umschalten |
| `<C-x>` | t | Terminal-Modus beenden |
| `<Space>th` | n | Design-Theme wählen |
| `<Space>wK` | n | Alle Tastenkürzel anzeigen |
| `<Space>ch` | n | NvCheatsheet umschalten |
| `<Space>/` | n, v | Zeilen kommentieren/dekommentieren |

**Eigene Mappings**

| Tastenkürzel | Modus | Funktion |
|---|---|---|
| `;` | n | Kommando-Modus (Ersatz für `:`) |
| `jk` | i | Escape |

## Lizenz

Dieses Projekt wird unter der MIT-Lizenz veröffentlicht. Details in der Datei [LICENSE](LICENSE).

---

**Autor**: [Pat9496](https://github.com/Pat9496)
