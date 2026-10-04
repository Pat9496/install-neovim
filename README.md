[Deutsche Version](README.de.md)

# install-neovim

A distro-agnostic Neovim installer script for user-local installation. It is primarily designed for Fedora atomic distros (Silverblue, Kinoite, Bazzite) but works on any Linux distribution.

## Quick Start

Clone or download the script and run it:

```bash
git clone https://github.com/Pat9496/install-neovim
cd install-neovim
./install-neovim.sh
```

Before you install, check the `--help` output to see all available options:

```bash
./install-neovim.sh --help
```

To preview what the script would do without making changes, use `--dry-run`:

```bash
./install-neovim.sh --dry-run
```

## Installation Methods

The script supports four installation methods via the `--method` flag:

### Tarball (Default)

The default method downloads an official Neovim release tarball from GitHub, verifies it against the published SHA256 digest, and extracts it into `$XDG_DATA_HOME/nvim-install` (typically `~/.local/share/nvim-install`). No root access required.

- Installs into a user-local directory under `$XDG_DATA_HOME/nvim-install/versions/`
- Creates symlinks: `~/.local/bin/nvim` points to the active version, and `current`/`previous` symlinks inside the install root enable quick rollback
- Verifies the binary actually runs before marking the install complete
- Supports upgrading to `stable`, `nightly`, or a specific version tag like `v0.10.2`
- No root access, no layering, no reboot required

Example:

```bash
./install-neovim.sh --version stable
./install-neovim.sh --version nightly
./install-neovim.sh --version v0.10.2
```

### Flatpak

Installs Neovim from Flathub (sandboxed, with restricted filesystem and clipboard access):

```bash
./install-neovim.sh --method flatpak
```

Run with: `flatpak run io.neovim.nvim` or `nvim` (if `~/.local/share/flatpak/exports/bin` is on your `PATH`).

### Package Manager

Uses the system package manager to install Neovim:

```bash
./install-neovim.sh --method package
```

On non-atomic systems, this runs `sudo dnf install neovim` (or the equivalent for apt, pacman, zypper, apk, or xbps). On rpm-ostree atomic hosts (Silverblue, Kinoite, Bazzite), it prompts interactively before layering with `rpm-ostree`, which requires a reboot. Use `--allow-layering` to skip the prompt on atomic hosts and proceed with layering non-interactively.

```bash
./install-neovim.sh --method package --allow-layering
```

### Homebrew

Installs Neovim via Homebrew (if installed):

```bash
./install-neovim.sh --method brew
```

## Tarball Method Details

The tarball method is the default and recommended approach for most users, especially on atomic hosts.

### How It Works

1. **Fetching**: Queries the GitHub Neovim API to resolve the release tag and download URL for the requested version (`stable`, `nightly`, or a specific tag like `v0.10.2`). For x86_64 and aarch64 architectures only.

2. **Verification**: Downloads the tarball and verifies its SHA256 digest against the published digest from the GitHub release metadata. Refuses to proceed if the digest is missing or mismatched.

3. **Extraction**: Extracts the tarball into a versioned directory under `$XDG_DATA_HOME/nvim-install/versions/` (e.g., `v0.10.2` or `nightly-<digest12>` for nightly builds).

4. **Binary Check**: Runs `nvim --version` to confirm the binary works on your system and catches architecture/glibc mismatches.

5. **Symlinks**: Updates `current` (points to the active version) and keeps `previous` (points to the prior version, for rollback). Updates `~/.local/bin/nvim` to point to the active version's binary.

6. **Cleanup**: Removes all other old version directories, keeping only `current` and `previous`.

### Versioned Directories and Rollback

Each release is extracted into its own directory under `$XDG_DATA_HOME/nvim-install/versions/`. The `current` symlink always points to the active version directory. When you upgrade, the previous version is retained in the `previous` symlink, allowing quick rollback without re-downloading:

```bash
./install-neovim.sh --rollback
```

### PATH Configuration

The script creates a symlink at `~/.local/bin/nvim` pointing to the active Neovim binary. To use it, ensure `~/.local/bin` is on your `PATH`. The script prints a warning if it detects that `~/.local/bin` is not in your `PATH` and shows the line to add to your shell rc file:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

The script does not edit shell rc files automatically; you must add this line manually.

## Flags and Options

| Flag | Argument | Description |
|------|----------|-------------|
| `--version` | `stable` \| `nightly` \| `vX.Y.Z` | Release to install. Default: `stable`. |
| `--method` | `tarball` \| `flatpak` \| `package` \| `brew` | Installation method. Default: `tarball`. |
| `--allow-layering` | None | On rpm-ostree atomic hosts with `--method package`, skip the interactive prompt and proceed with layering (non-interactive sessions otherwise refuse). Requires a reboot afterward. |
| `--uninstall` | None | Remove the tarball-method installation (versions directory, symlinks). |
| `--rollback` | None | Switch back to the previously installed tarball version. |
| `--check-deps` | None | Report missing optional runtime dependencies and exit (no install). |
| `--with-plugins` | None | Extend an existing NvChad/lazy.nvim config with treesitter parsers, Mason tools, spell support, and extras. |
| `--no-sync` | None | With `--with-plugins`, write managed files and fetch spell dictionaries but skip the headless Lazy sync and Mason install. |
| `--yes`, `-y` | None | Assume yes on confirmation prompts (`--uninstall`, `--with-plugins` file writes). Does not apply to rpm-ostree layering. |
| `--dry-run` | None | Show what would happen without making changes. |
| `-h`, `--help` | None | Show help and exit. |

### Examples

```bash
./install-neovim.sh                              # Install latest stable
./install-neovim.sh --version v0.10.2            # Install specific version
./install-neovim.sh --version nightly            # Install nightly build
./install-neovim.sh --method package --allow-layering  # Use package manager with layering
./install-neovim.sh --dry-run                    # Preview what would happen
./install-neovim.sh --with-plugins               # Extend NvChad config
./install-neovim.sh --uninstall                  # Remove tarball installation
./install-neovim.sh --rollback                   # Revert to previous version
./install-neovim.sh --check-deps                 # List missing optional dependencies
```

## Optional Dependencies (--check-deps)

The `--check-deps` action reports missing optional Neovim runtime dependencies:

- `git` — version control
- `ripgrep` (rg) — fast search
- `fd` or `fdfind` — fast file finding
- A C compiler (gcc or clang) — for treesitter parser compilation
- A clipboard tool (xclip, xsel, or wl-clipboard) — for register/clipboard integration
- `npm` (Node.js) — used by Mason for Node.js-based language servers (html, css, etc.)
- `tree-sitter` CLI — needed by nvim-treesitter's main branch to compile parsers

Neovim runs without these, but they unlock additional functionality. The script never installs them; it only reports which are missing and suggests how to install them via your distro's package manager.

```bash
./install-neovim.sh --check-deps
```

## Optional Plugin Setup (--with-plugins)

The `--with-plugins` flag extends an existing NvChad v2.5 or lazy.nvim configuration at `$XDG_CONFIG_HOME/nvim` (typically `~/.config/nvim`) by writing managed plugin specs that cannot clobber user files. This feature is opt-in and only valid with the default install action.

### What It Does

- **Treesitter parsers**: Installs these language parsers: lua, vim, vimdoc, bash, python, markdown, markdown_inline, powershell, yaml, json, html, css, regex.
- **Mason language servers and tools**: Installs bash-language-server, lua-language-server, powershell-editor-services, shellcheck, shfmt, stylua, html-lsp, css-lsp.
- **Extra plugins**: nvim-lint (for linting with shellcheck), flash.nvim (for motion), render-markdown.nvim (for markdown rendering).
- **Spell support**: Sets spelllang to en_us and de_de (English and German), and enables spell checking for markdown, text, and gitcommit file types.
- **Spell files**: Fetches en.utf-8.spl and de.utf-8.spl from the official Vim spell server.

### Requirements

- `nvim` must already be on your `PATH` or freshly installed by this script run
- `$XDG_CONFIG_HOME/nvim/lua/plugins/` must already exist (the config directory structure must exist; the script never bootstraps a config from scratch)

### No-Clobber Design

The script only writes if the target files do not already exist:

- `lua/plugins/extras.lua` — written only if absent
- `lua/plugins/extras-spell.lua` — written only if absent

Existing files are reported and left untouched, allowing safe re-runs and preserving any local customizations.

### Usage

```bash
./install-neovim.sh --with-plugins
```

The script will ask for confirmation before writing files (unless `--yes`/`-y` is passed). By default, it then runs a headless Lazy sync and Mason install to fetch and set up all plugins.

To write the files and fetch spell dictionaries without the headless sync step, use `--no-sync`:

```bash
./install-neovim.sh --with-plugins --no-sync
```

To skip all prompts and proceed without the sync:

```bash
./install-neovim.sh --with-plugins --no-sync --yes
```

### Extra Runtime Requirements

`--with-plugins` assumes some additional tools for the plugins to work correctly. The script only reports these; it does not install them:

- **tree-sitter CLI** — Required by nvim-treesitter's main branch to compile parsers. Install via `cargo install tree-sitter-cli`, `npm install -g tree-sitter-cli`, or your distro's package manager (e.g., `dnf install tree-sitter-cli` on Fedora).
- **pwsh** (PowerShell 7+) — Required to run the `powershell-editor-services` Mason package. If not present, Mason will report it missing but the rest of the setup continues.
- **fd** — Used by NvChad's Telescope integration for fast file picking.

The script prints these notes at startup so you can install them in advance if needed.

## Uninstall

Remove the tarball-method installation:

```bash
./install-neovim.sh --uninstall
```

This removes the versioned installation directory and the `~/.local/bin/nvim` symlink (if it points into the installation directory). Other installation methods (flatpak, package, brew) should be uninstalled via their own tools.

## Rollback

If an upgrade causes problems, quickly switch back to the previously installed version:

```bash
./install-neovim.sh --rollback
```

The `rollback` action is only available for the tarball method and requires a previous version to exist. It updates the `current` and `previous` symlinks to swap versions, allowing easy toggling between two installs.

## Requirements

### Minimum

- curl or wget (for downloading)
- tar (for extracting tarballs)
- Linux x86_64 or aarch64 architecture

### Optional

- jq (for JSON parsing; the script has an awk fallback if jq is not installed)
- Flatpak (if using `--method flatpak`)
- Homebrew (if using `--method brew`)
- rpm-ostree (if using `--method package` on an atomic host)

## Limitations

The script is designed for **Linux only** and currently supports:

- **x86_64** (Intel/AMD 64-bit)
- **aarch64** (ARM 64-bit, e.g., Apple Silicon with Linux, Raspberry Pi 4/5)

Other architectures (i386, armv7, powerpc, etc.) are not supported by the script's asset-selection logic.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Credits

Created by [Pat9496](https://github.com/Pat9496).
