#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO="neovim/neovim"
API_BASE="https://api.github.com/repos/${REPO}"

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
INSTALL_ROOT="$XDG_DATA_HOME/nvim-install"
VERSIONS_DIR="$INSTALL_ROOT/versions"
CURRENT_LINK="$INSTALL_ROOT/current"
PREVIOUS_LINK="$INSTALL_ROOT/previous"
CURRENT_BIN="$CURRENT_LINK/bin/nvim"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/nvim"
ALIAS_NAMES=(neovim vim vi)
NVIM_CONFIG_DIR="$XDG_CONFIG_HOME/nvim"
PLUGINS_DIR="$NVIM_CONFIG_DIR/lua/plugins"
EXTRAS_FILE="$PLUGINS_DIR/extras.lua"
EXTRAS_SPELL_FILE="$PLUGINS_DIR/extras-spell.lua"
NVIM_DATA_DIR="$XDG_DATA_HOME/nvim"
SPELL_DIR="$NVIM_DATA_DIR/site/spell"
SPELL_BASE_URL="https://ftp.nluug.nl/pub/vim/runtime/spell"
SPELL_LANGS=(en de)

TREESITTER_PARSERS=(lua vim vimdoc bash python markdown markdown_inline powershell yaml json html css regex)
MASON_PACKAGES=(bash-language-server lua-language-server shellcheck shfmt stylua html-lsp css-lsp)

VERSION_ARG="stable"
METHOD="tarball"
ALLOW_LAYERING=0
ASSUME_YES=0
DRY_RUN=0
WITH_PLUGINS=0
NO_SYNC=0
CREATE_ALIASES=1
ACTION="install"

TMPDIR_CREATED=""

log_info() { printf '[info] %s\n' "$*" >&2; }
log_warn() { printf '[warn] %s\n' "$*" >&2; }
log_err()  { printf '[error] %s\n' "$*" >&2; }
die() { log_err "$*"; exit 1; }

cleanup() {
  if [[ -n "$TMPDIR_CREATED" && -d "$TMPDIR_CREATED" ]]; then
    rm -rf "$TMPDIR_CREATED"
  fi
}
trap cleanup EXIT

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Install or manage a user-local Neovim build.

Options:
  --version <tag|stable|nightly>  Release to install (default: stable).
                                   <tag> must look like v0.10.2.
  --method <tarball|flatpak|package|brew>
                                   Install method (default: tarball).
  --allow-layering                Non-interactive opt-in to rpm-ostree
                                   layering on an atomic host when
                                   --method package is used. Skips the
                                   interactive prompt below. Requires a
                                   reboot afterward.
  --uninstall                     Remove the tarball-method install
                                   (versions dir, symlinks).
  --rollback                      Switch back to the previously
                                   installed tarball version.
  --check-deps                    Report missing optional runtime
                                   dependencies and exit. No install.
  --install-deps                  Install missing optional dependencies
                                   (currently: the tree-sitter CLI) via
                                   Homebrew. Only runs when brew is found
                                   on PATH or at
                                   /home/linuxbrew/.linuxbrew/bin/brew or
                                   ~/.linuxbrew/bin/brew; otherwise dies
                                   with a pointer to https://brew.sh.
                                   Never installs Homebrew itself and
                                   never uses sudo. Prompts for
                                   confirmation (default No) unless
                                   --yes/-y. Honors --dry-run (prints the
                                   exact brew command, installs nothing).
                                   An action on its own (does not install
                                   Neovim); combine with --with-plugins
                                   to install deps first, then set up
                                   plugins. Mutually exclusive with
                                   --uninstall, --rollback, and
                                   --check-deps.
  --no-aliases                    Skip creating the neovim/vim/vi command
                                   aliases in ~/.local/bin that this
                                   script creates by default next to
                                   nvim (tarball-method install and
                                   --rollback only; other --method
                                   values and --install-deps/--check-deps/
                                   --uninstall do not touch aliases).
                                   Existing files, or symlinks pointing
                                   somewhere other than this script's own
                                   nvim target, are always left alone
                                   regardless of this flag.
  --with-plugins                  Extend an existing NvChad/lazy.nvim
                                   config (at \$XDG_CONFIG_HOME/nvim) with
                                   treesitter parsers, Mason LSP/lint/
                                   format tools, nvim-lint, flash.nvim,
                                   render-markdown.nvim, and en_us/de_de
                                   spell support. Requires nvim already on
                                   PATH or freshly installed by this run,
                                   and an existing lua/plugins/ directory;
                                   refuses to bootstrap a config from
                                   scratch. Never overwrites an existing
                                   managed file; writes only
                                   lua/plugins/extras.lua and
                                   lua/plugins/extras-spell.lua if they do
                                   not already exist.
  --no-sync                       With --with-plugins, write the managed
                                   files and fetch spell dictionaries but
                                   skip the headless Lazy/Mason install
                                   step.
  --yes, -y                       Assume yes on confirmation prompts
                                   (currently: --uninstall, --install-deps,
                                   and writing the --with-plugins managed
                                   files). Never applies to rpm-ostree
                                   layering.
  --dry-run                       Show what would happen, change nothing.
  -h, --help                      Show this help and exit.

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --version v0.10.2
  ${SCRIPT_NAME} --version nightly
  ${SCRIPT_NAME} --method package --allow-layering
  ${SCRIPT_NAME} --no-aliases
  ${SCRIPT_NAME} --install-deps
  ${SCRIPT_NAME} --install-deps --with-plugins --yes
  ${SCRIPT_NAME} --with-plugins
  ${SCRIPT_NAME} --with-plugins --no-sync --yes
  ${SCRIPT_NAME} --uninstall
  ${SCRIPT_NAME} --rollback

On an rpm-ostree atomic host, --method package without --allow-layering
prompts interactively (default: no) and falls back to the tarball
method unless you confirm layering. Non-interactive sessions without
--allow-layering are refused outright.
EOF
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
}

parse_args() {
  local action_set=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die "--version requires an argument"
        VERSION_ARG="$2"
        shift 2
        ;;
      --method)
        [[ $# -ge 2 ]] || die "--method requires an argument"
        METHOD="$2"
        shift 2
        ;;
      --allow-layering)
        ALLOW_LAYERING=1
        shift
        ;;
      --uninstall)
        ACTION="uninstall"
        action_set=$((action_set + 1))
        shift
        ;;
      --rollback)
        ACTION="rollback"
        action_set=$((action_set + 1))
        shift
        ;;
      --check-deps)
        ACTION="check-deps"
        action_set=$((action_set + 1))
        shift
        ;;
      --install-deps)
        ACTION="install-deps"
        action_set=$((action_set + 1))
        shift
        ;;
      --no-aliases)
        CREATE_ALIASES=0
        shift
        ;;
      --with-plugins)
        WITH_PLUGINS=1
        shift
        ;;
      --no-sync)
        NO_SYNC=1
        shift
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
  done

  if [[ "$action_set" -gt 1 ]]; then
    die "--uninstall, --rollback, --check-deps and --install-deps are mutually exclusive"
  fi

  case "$VERSION_ARG" in
    stable|nightly) ;;
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) die "invalid --version value: $VERSION_ARG (expected stable, nightly, or vX.Y.Z)" ;;
  esac

  case "$METHOD" in
    tarball|flatpak|package|brew) ;;
    *) die "invalid --method value: $METHOD (expected tarball, flatpak, package, or brew)" ;;
  esac

  if [[ "$WITH_PLUGINS" -eq 1 && "$ACTION" != "install" && "$ACTION" != "install-deps" ]]; then
    die "--with-plugins only applies to the install or --install-deps actions, not --uninstall, --rollback, or --check-deps"
  fi

  if [[ "$NO_SYNC" -eq 1 && "$WITH_PLUGINS" -ne 1 ]]; then
    die "--no-sync requires --with-plugins"
  fi

  if [[ "$CREATE_ALIASES" -eq 0 && "$ACTION" != "install" && "$ACTION" != "rollback" ]]; then
    die "--no-aliases only applies to the default install action or --rollback, not --uninstall, --check-deps, or --install-deps"
  fi
}

detect_context() {
  OS_ID=""
  OS_PRETTY=""
  ATOMIC_HOST=0
  CONTAINER_CTX="none"
  ARCH="$(uname -m)"

  if [[ -r /etc/os-release ]]; then
    OS_ID="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n1)"
    OS_PRETTY="$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"' | head -n1)"
  fi

  if [[ -f /run/.toolboxenv || -n "${TOOLBOX_PATH:-}" ]]; then
    CONTAINER_CTX="toolbox"
  elif [[ -f /run/.containerenv && -n "${CONTAINER_ID:-}" ]]; then
    CONTAINER_CTX="distrobox"
  elif [[ -f /run/.containerenv ]]; then
    CONTAINER_CTX="container"
  fi

  if [[ -f /run/ostree-booted ]] && command -v rpm-ostree >/dev/null 2>&1; then
    ATOMIC_HOST=1
  fi
}

print_context_summary() {
  log_info "OS: ${OS_PRETTY:-unknown} (id=${OS_ID:-unknown}, arch=${ARCH})"
  if [[ "$CONTAINER_CTX" != "none" ]]; then
    log_info "Running inside a ${CONTAINER_CTX} container; host atomicity cannot be inferred from here."
  fi
  if [[ "$ATOMIC_HOST" -eq 1 ]]; then
    log_info "Host is an rpm-ostree atomic system (/run/ostree-booted present)."
  else
    log_info "No rpm-ostree atomic host indicators from this context."
  fi
}

asset_arch() {
  case "$ARCH" in
    x86_64) printf 'x86_64\n' ;;
    aarch64) printf 'arm64\n' ;;
    *) die "unsupported architecture: $ARCH" ;;
  esac
}

http_fetch() {
  local url="$1" outfile="$2"
  if command -v curl >/dev/null 2>&1; then
    local code
    code="$(curl -sS -L -w '%{http_code}' -o "$outfile" "$url" || true)"
    if [[ "$code" != "200" ]]; then
      log_err "HTTP $code fetching $url"
      [[ -s "$outfile" ]] && log_err "$(head -c 300 "$outfile")"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$outfile" "$url" || { log_err "failed fetching $url"; return 1; }
  else
    die "neither curl nor wget is available"
  fi
}

json_get_tag() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.tag_name' "$file"
  else
    sed -n 's/^[[:space:]]*"tag_name": *"\([^"]*\)".*/\1/p' "$file" | head -n1
  fi
}

json_get_asset() {
  local file="$1" name="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg n "$name" '
      .assets[] | select(.name == $n) |
      ((.digest // "") | sub("^sha256:"; "")) + "\t" + .browser_download_url
    ' "$file"
  else
    awk -v target="$name" '
      /"name":/ {
        line = $0
        gsub(/^[[:space:]]*"name":[[:space:]]*"/, "", line)
        gsub(/",?$/, "", line)
        found = (line == target) ? 1 : 0
        next
      }
      found && /"digest":/ {
        line = $0
        gsub(/^[[:space:]]*"digest":[[:space:]]*"sha256:/, "", line)
        gsub(/",?$/, "", line)
        digest = line
        next
      }
      found && /"browser_download_url":/ {
        line = $0
        gsub(/^[[:space:]]*"browser_download_url":[[:space:]]*"/, "", line)
        gsub(/",?$/, "", line)
        print digest "\t" line
        exit
      }
    ' "$file"
  fi
}

resolve_release() {
  local version_arg="$1" arch="$2"
  local api_url json_file asset_name line tag digest url

  case "$version_arg" in
    stable) api_url="${API_BASE}/releases/latest" ;;
    nightly) api_url="${API_BASE}/releases/tags/nightly" ;;
    *) api_url="${API_BASE}/releases/tags/${version_arg}" ;;
  esac

  json_file="$TMPDIR_CREATED/release.json"
  http_fetch "$api_url" "$json_file" || die "could not fetch release metadata from $api_url"

  tag="$(json_get_tag "$json_file")"
  [[ -n "$tag" && "$tag" != "null" ]] || die "could not determine tag_name from release metadata"

  asset_name="nvim-linux-${arch}.tar.gz"
  line="$(json_get_asset "$json_file" "$asset_name")"
  digest="${line%%$'\t'*}"
  url="${line#*$'\t'}"

  [[ -n "$url" && "$url" != "$line" ]] || die "asset $asset_name not found in release $tag"

  RESOLVED_TAG="$tag"
  RESOLVED_DIGEST="$digest"
  RESOLVED_URL="$url"
  RESOLVED_ASSET="$asset_name"
}

version_dir_name() {
  if [[ "$VERSION_ARG" == "nightly" ]]; then
    if [[ -z "$RESOLVED_DIGEST" ]]; then
      die "nightly release has no digest to key a version directory on; refusing to install unverified build"
    fi
    printf 'nightly-%s\n' "${RESOLVED_DIGEST:0:12}"
  else
    printf '%s\n' "$RESOLVED_TAG"
  fi
}

check_path_warning() {
  case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *)
      log_warn "${BIN_DIR} is not on your PATH."
      log_warn "Add this to your shell rc file to fix it:"
      log_warn "  export PATH=\"${BIN_DIR}:\$PATH\""
      ;;
  esac
}

verify_nvim_runs() {
  local bin_path="$1" err_file="$2"
  require_cmd timeout
  if [[ -d "$bin_path" ]]; then
    printf '%s: is a directory, not the nvim binary\n' "$bin_path" >"$err_file"
    return 126
  fi
  timeout 10 "$bin_path" --version >/dev/null 2>"$err_file"
}

diagnose_binary_failure() {
  local bin_path="$1" rc="$2" err_file="$3"

  if [[ -s "$err_file" ]]; then
    log_err "$(cat "$err_file")"
  fi

  log_err "diagnostic: ${bin_path} failed to execute (exit ${rc})."

  if [[ -L "$bin_path" && ! -e "$bin_path" ]]; then
    log_err "  - it is a broken symlink (target missing)"
  fi

  if [[ -e "$bin_path" && ! -x "$bin_path" ]]; then
    log_err "  - the executable bit is not set; check with: ls -l ${bin_path}"
  fi

  log_err "  - possible SELinux denial; check context and recent denials with:"
  log_err "      ls -Z ${bin_path}"
  log_err "      sudo ausearch -m avc,user_avc -ts recent"

  log_err "  - possible noexec mount; check with:"
  log_err "      findmnt -T $(dirname "$bin_path")"

  case "$rc" in
    126) log_err "  - exit 126 means the file exists but could not be executed (permission, SELinux denial, or a noexec mount)." ;;
    127) log_err "  - exit 127 means the binary (or an interpreter/library it needs) was not found." ;;
  esac
}

check_alias_path_shadowing() {
  local -a path_entries
  IFS=':' read -r -a path_entries <<< "$PATH"

  local bin_dir_pos=-1 usr_bin_pos=-1 i=0 entry
  for entry in "${path_entries[@]}"; do
    if [[ "$bin_dir_pos" -eq -1 && "$entry" == "$BIN_DIR" ]]; then
      bin_dir_pos=$i
    fi
    if [[ "$usr_bin_pos" -eq -1 && "$entry" == "/usr/bin" ]]; then
      usr_bin_pos=$i
    fi
    i=$((i + 1))
  done

  if [[ "$bin_dir_pos" -eq -1 || "$usr_bin_pos" -eq -1 ]]; then
    return 0
  fi

  if [[ "$bin_dir_pos" -gt "$usr_bin_pos" ]]; then
    log_info "Note: ${BIN_DIR} comes after /usr/bin on your PATH, so the vim/vi aliases"
    log_info "here will not shadow the system vim/vi until ${BIN_DIR} is moved earlier"
    log_info "on PATH. This never affects sudo/root sessions or anything invoking"
    log_info "/usr/bin/vim or /usr/bin/vi by absolute path."
  fi
}

create_aliases() {
  if [[ "$CREATE_ALIASES" -ne 1 ]]; then
    return 0
  fi

  local name path existing_target
  for name in "${ALIAS_NAMES[@]}"; do
    path="$BIN_DIR/$name"

    if [[ "$DRY_RUN" -eq 1 ]]; then
      if [[ -L "$path" ]]; then
        existing_target="$(readlink "$path")"
        if [[ "$existing_target" == "$CURRENT_BIN" ]]; then
          log_info "[dry-run] ${path} already links to ${CURRENT_BIN}; no change"
        elif [[ "$existing_target" == "$CURRENT_LINK" ]]; then
          log_info "[dry-run] would repair ${path}: '${existing_target}' -> '${CURRENT_BIN}'"
        else
          log_warn "[dry-run] ${path} is a symlink to '${existing_target}', not managed by this script; would leave it alone"
        fi
      elif [[ -e "$path" ]]; then
        log_warn "[dry-run] ${path} exists and is not a symlink; would leave it alone"
      else
        log_info "[dry-run] would link ${path} -> ${CURRENT_BIN}"
      fi
      continue
    fi

    if [[ -L "$path" ]]; then
      existing_target="$(readlink "$path")"
      if [[ "$existing_target" == "$CURRENT_BIN" ]]; then
        continue
      elif [[ "$existing_target" == "$CURRENT_LINK" ]]; then
        log_warn "repairing ${path}: '${existing_target}' -> '${CURRENT_BIN}'"
        ln -sfn "$CURRENT_BIN" "$path"
      else
        log_warn "${path} is a symlink to '${existing_target}', not managed by this script; leaving it alone"
        continue
      fi
    elif [[ -e "$path" ]]; then
      log_warn "${path} already exists and is not a symlink; leaving it alone"
      continue
    else
      ln -sfn "$CURRENT_BIN" "$path"
    fi

    local alias_verify_err="$TMPDIR_CREATED/alias-${name}-verify.err"
    local alias_verify_rc=0
    verify_nvim_runs "$path" "$alias_verify_err" || alias_verify_rc=$?
    if [[ "$alias_verify_rc" -ne 0 ]]; then
      diagnose_binary_failure "$path" "$alias_verify_rc" "$alias_verify_err"
      log_warn "alias ${path} was created but does not run (exit ${alias_verify_rc}); leaving it in place for inspection"
    fi
  done

  check_alias_path_shadowing
}

locate_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  local candidate
  for candidate in /home/linuxbrew/.linuxbrew/bin/brew "$HOME/.linuxbrew/bin/brew"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

check_deps() {
  local missing=()

  command -v git >/dev/null 2>&1 || missing+=("git")
  command -v rg >/dev/null 2>&1 || missing+=("ripgrep (rg)")
  { command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; } || missing+=("fd (or fdfind)")
  { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1; } || missing+=("a C compiler (gcc or clang)")
  {
    command -v xclip >/dev/null 2>&1 || command -v xsel >/dev/null 2>&1 ||
    { command -v wl-copy >/dev/null 2>&1 && command -v wl-paste >/dev/null 2>&1; }
  } || missing+=("a clipboard tool (xclip, xsel, or wl-clipboard)")
  command -v npm >/dev/null 2>&1 || missing+=("npm (Node.js, used by Mason for npm-based servers like html and cssls)")
  command -v tree-sitter >/dev/null 2>&1 || missing+=("tree-sitter CLI (needed by nvim-treesitter's main branch to compile parsers)")

  if [[ "${#missing[@]}" -eq 0 ]]; then
    log_info "All optional Neovim runtime dependencies were found."
  else
    log_info "Missing optional dependencies (Neovim will still run without them):"
    local dep
    for dep in "${missing[@]}"; do
      log_info "  - ${dep}"
    done

    if [[ "$ATOMIC_HOST" -eq 1 ]]; then
      log_info "On the atomic host itself, install these inside a toolbox/distrobox, or via brew/pipx/cargo:"
      log_info "  toolbox run sudo dnf install -y git ripgrep fd-find gcc wl-clipboard nodejs"
    elif command -v dnf >/dev/null 2>&1; then
      log_info "  sudo dnf install -y git ripgrep fd-find gcc wl-clipboard nodejs"
    elif command -v apt-get >/dev/null 2>&1; then
      log_info "  sudo apt-get install -y git ripgrep fd-find gcc wl-clipboard nodejs npm"
    elif command -v pacman >/dev/null 2>&1; then
      log_info "  sudo pacman -S git ripgrep fd gcc wl-clipboard nodejs npm"
    elif command -v zypper >/dev/null 2>&1; then
      log_info "  sudo zypper install git ripgrep fd gcc wl-clipboard nodejs npm"
    elif command -v apk >/dev/null 2>&1; then
      log_info "  sudo apk add git ripgrep fd gcc wl-clipboard nodejs npm"
    elif command -v xbps-install >/dev/null 2>&1; then
      log_info "  sudo xbps-install -y git ripgrep fd gcc wl-clipboard nodejs npm"
    else
      log_info "  install git, ripgrep, fd, a C compiler, a clipboard tool, and npm (Node.js) via your package manager."
    fi

    if printf '%s\n' "${missing[@]}" | grep -q 'tree-sitter CLI'; then
      log_info "For the tree-sitter CLI specifically (crates.io: tree-sitter-cli):"
      if [[ "$ATOMIC_HOST" -ne 1 ]] && command -v dnf >/dev/null 2>&1; then
        log_info "  dnf install tree-sitter-cli   (confirmed available on Fedora)"
      fi
      if command -v cargo >/dev/null 2>&1; then
        log_info "  or: cargo install tree-sitter-cli"
      fi
      if command -v npm >/dev/null 2>&1; then
        log_info "  or: npm install -g tree-sitter-cli"
      fi
      if locate_brew >/dev/null 2>&1; then
        log_info "  or: brew install tree-sitter-cli   (confirmed on Homebrew for Linux)"
      fi
      log_info "  or: ${SCRIPT_NAME} --install-deps   (uses brew if it is already set up)"
      log_info "  package names on other distros are not verified here; check your package manager."
    fi
  fi

  log_info "Note: if you use Mason (plugin-managed LSP/DAP/formatter installer), it also"
  log_info "expects git, curl or wget, and tar/unzip/gzip to fetch and unpack packages;"
  log_info "treesitter parsers need a C compiler (checked above). These are informational"
  log_info "notes only; this script only installs the tree-sitter CLI, and only via the"
  log_info "explicit ${SCRIPT_NAME} --install-deps opt-in."
}

confirm_or_die() {
  local prompt="$1"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  local reply
  read -r -p "${prompt} [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) die "aborted by user" ;;
  esac
}

install_deps() {
  local -a missing_formulae=()
  command -v tree-sitter >/dev/null 2>&1 || missing_formulae+=(tree-sitter-cli)

  if [[ "${#missing_formulae[@]}" -eq 0 ]]; then
    log_info "tree-sitter is already on PATH; nothing to install."
    return 0
  fi

  local brew_bin
  if ! brew_bin="$(locate_brew)"; then
    die "brew not found on PATH, /home/linuxbrew/.linuxbrew/bin/brew, or ~/.linuxbrew/bin/brew; install Homebrew first: https://brew.sh (this script never installs brew itself)"
  fi

  local -a brew_cmd=("$brew_bin" install "${missing_formulae[@]}")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] would run: ${brew_cmd[*]}"
    return 0
  fi

  confirm_or_die "Install ${missing_formulae[*]} via Homebrew (${brew_bin})?"

  "${brew_cmd[@]}"

  local pkg
  for pkg in "${missing_formulae[@]}"; do
    case "$pkg" in
      tree-sitter-cli)
        command -v tree-sitter >/dev/null 2>&1 || log_warn "brew install tree-sitter-cli finished, but 'tree-sitter' is still not on PATH; check 'brew --prefix' is on PATH."
        ;;
    esac
  done
}

do_install_tarball() {
  [[ "$EUID" -ne 0 ]] || die "refusing to run the tarball method as root; this installer is user-local only"

  require_cmd tar
  require_cmd sha256sum
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "curl or wget is required"
  fi

  ARCH="$(uname -m)"
  local arch
  arch="$(asset_arch)"

  resolve_release "$VERSION_ARG" "$arch"

  local verdir version_dir
  verdir="$(version_dir_name)"
  version_dir="$VERSIONS_DIR/$verdir"

  local current_target=""
  if [[ -L "$CURRENT_LINK" ]]; then
    current_target="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
  fi

  if [[ -d "$version_dir" && "$current_target" == "$(cd "$version_dir" && pwd -P)" ]]; then
    if [[ -L "$BIN_LINK" ]]; then
      local bin_link_target
      bin_link_target="$(readlink "$BIN_LINK")"
      if [[ "$bin_link_target" != "$CURRENT_BIN" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          log_info "[dry-run] would repair ${BIN_LINK}: '${bin_link_target}' -> '${CURRENT_BIN}'"
        else
          log_warn "${BIN_LINK} points to '${bin_link_target}' instead of '${CURRENT_BIN}'; repairing the symlink."
          mkdir -p "$BIN_DIR"
          ln -sfn "$CURRENT_BIN" "$BIN_LINK"
        fi
      fi
    fi

    local noop_verify_err="$TMPDIR_CREATED/noop-verify.err"
    local noop_verify_rc=0
    verify_nvim_runs "$BIN_LINK" "$noop_verify_err" || noop_verify_rc=$?
    if [[ "$noop_verify_rc" -eq 0 ]]; then
      log_info "Neovim $verdir is already installed and active; nothing to do."
      mkdir -p "$BIN_DIR"
      ln -sfn "$CURRENT_BIN" "$BIN_LINK"
      create_aliases
      check_path_warning
      return 0
    fi
    log_warn "Neovim $verdir is recorded as installed and active, but ${BIN_LINK} failed to run (exit ${noop_verify_rc})."
    diagnose_binary_failure "$BIN_LINK" "$noop_verify_rc" "$noop_verify_err"
    log_warn "Treating this as a broken install; reinstalling ${verdir} into ${version_dir}."
  fi

  log_info "Resolved release: tag=${RESOLVED_TAG} asset=${RESOLVED_ASSET}"
  if [[ -z "$RESOLVED_DIGEST" ]]; then
    die "release metadata has no sha256 digest for ${RESOLVED_ASSET}; refusing to install unverified binary"
  fi
  log_info "Expected sha256: ${RESOLVED_DIGEST}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] would download: $RESOLVED_URL"
    log_info "[dry-run] would verify sha256 and extract into: $version_dir"
    log_info "[dry-run] would point ${CURRENT_LINK} -> ${version_dir}"
    if [[ -n "$current_target" ]]; then
      log_info "[dry-run] would keep previous version at: ${PREVIOUS_LINK} -> ${current_target}"
    fi
    log_info "[dry-run] would symlink ${BIN_LINK} -> ${CURRENT_BIN}"
    create_aliases
    return 0
  fi

  mkdir -p "$VERSIONS_DIR" "$BIN_DIR"

  local tarball="$TMPDIR_CREATED/$RESOLVED_ASSET"
  log_info "Downloading $RESOLVED_ASSET ..."
  http_fetch "$RESOLVED_URL" "$tarball" || die "download failed"

  local actual_digest
  actual_digest="$(sha256sum "$tarball" | awk '{print $1}')"
  if [[ "${actual_digest,,}" != "${RESOLVED_DIGEST,,}" ]]; then
    die "sha256 mismatch for $RESOLVED_ASSET: expected $RESOLVED_DIGEST, got $actual_digest"
  fi
  log_info "Checksum verified."

  local staging_dir="$VERSIONS_DIR/.staging-$$"
  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"
  tar -xzf "$tarball" -C "$staging_dir" --strip-components=1

  local probe_err="$TMPDIR_CREATED/probe.err"
  if ! "$staging_dir/bin/nvim" --version >/dev/null 2>"$probe_err"; then
    log_err "the downloaded nvim binary failed to run on this system:"
    log_err "$(cat "$probe_err")"
    if grep -qi 'GLIBC' "$probe_err"; then
      log_err "This usually means your system's glibc is older than what this Neovim build requires."
    fi
    rm -rf "$staging_dir"
    die "aborting install; binary is not runnable here"
  fi

  rm -rf "$version_dir"
  mv "$staging_dir" "$version_dir"

  if [[ -n "$current_target" && "$current_target" != "$(cd "$version_dir" && pwd -P)" ]]; then
    ln -sfn "$current_target" "$PREVIOUS_LINK"
  fi
  ln -sfn "$version_dir" "$CURRENT_LINK"
  ln -sfn "$CURRENT_BIN" "$BIN_LINK"

  local final_verify_err="$TMPDIR_CREATED/final-verify.err"
  local final_verify_rc=0
  verify_nvim_runs "$BIN_LINK" "$final_verify_err" || final_verify_rc=$?
  if [[ "$final_verify_rc" -ne 0 ]]; then
    diagnose_binary_failure "$BIN_LINK" "$final_verify_rc" "$final_verify_err"
    die "installed Neovim binary at ${BIN_LINK} does not run (exit ${final_verify_rc})"
  fi

  prune_old_versions

  log_info "Installed Neovim ($verdir) -> $BIN_LINK"
  "$BIN_LINK" --version | head -n1
  create_aliases
  check_path_warning
}

prune_old_versions() {
  local keep_current="" keep_previous=""
  [[ -L "$CURRENT_LINK" ]] && keep_current="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
  [[ -L "$PREVIOUS_LINK" ]] && keep_previous="$(readlink -f "$PREVIOUS_LINK" 2>/dev/null || true)"

  local entry resolved
  shopt -s nullglob
  for entry in "$VERSIONS_DIR"/*/; do
    entry="${entry%/}"
    resolved="$(cd "$entry" && pwd -P)"
    if [[ "$resolved" != "$keep_current" && "$resolved" != "$keep_previous" ]]; then
      case "$entry" in
        "$VERSIONS_DIR"/*)
          rm -rf "$entry"
          ;;
      esac
    fi
  done
  shopt -u nullglob
}

do_rollback() {
  [[ -L "$PREVIOUS_LINK" ]] || die "no previous version recorded to roll back to"

  local prev_target cur_target
  prev_target="$(readlink -f "$PREVIOUS_LINK")"
  [[ -d "$prev_target" ]] || die "previous version directory no longer exists: $prev_target"
  cur_target="$([[ -L "$CURRENT_LINK" ]] && readlink -f "$CURRENT_LINK" || true)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] would point ${CURRENT_LINK} -> ${prev_target}"
    [[ -n "$cur_target" ]] && log_info "[dry-run] would point ${PREVIOUS_LINK} -> ${cur_target}"
    return 0
  fi

  ln -sfn "$prev_target" "$CURRENT_LINK"
  if [[ -n "$cur_target" ]]; then
    ln -sfn "$cur_target" "$PREVIOUS_LINK"
  fi
  mkdir -p "$BIN_DIR"
  ln -sfn "$CURRENT_BIN" "$BIN_LINK"

  local rollback_verify_err="$TMPDIR_CREATED/rollback-verify.err"
  local rollback_verify_rc=0
  verify_nvim_runs "$BIN_LINK" "$rollback_verify_err" || rollback_verify_rc=$?
  if [[ "$rollback_verify_rc" -ne 0 ]]; then
    diagnose_binary_failure "$BIN_LINK" "$rollback_verify_rc" "$rollback_verify_err"
    die "rolled-back Neovim binary at ${BIN_LINK} does not run (exit ${rollback_verify_rc})"
  fi

  create_aliases

  log_info "Rolled back to $(basename "$prev_target")"
  "$BIN_LINK" --version | head -n1
}

do_uninstall() {
  local expected_root="$XDG_DATA_HOME/nvim-install"
  [[ -n "$INSTALL_ROOT" && "$INSTALL_ROOT" != "/" && "$INSTALL_ROOT" != "$HOME" ]] || die "refusing to uninstall: unsafe path"
  [[ "$INSTALL_ROOT" == "$expected_root" ]] || die "refusing to uninstall: unexpected path $INSTALL_ROOT"
  [[ "$(basename "$INSTALL_ROOT")" == "nvim-install" ]] || die "refusing to uninstall: unexpected directory name"

  local -a all_links=("$BIN_LINK")
  local alias_name
  for alias_name in "${ALIAS_NAMES[@]}"; do
    all_links+=("$BIN_DIR/$alias_name")
  done

  if [[ "$DRY_RUN" -eq 1 ]]; then
    local link
    for link in "${all_links[@]}"; do
      log_info "[dry-run] would remove: $link (if it points into $INSTALL_ROOT)"
    done
    log_info "[dry-run] would remove: $INSTALL_ROOT"
    return 0
  fi

  if [[ ! -d "$INSTALL_ROOT" ]]; then
    log_info "Nothing to uninstall: $INSTALL_ROOT does not exist."
  else
    confirm_or_die "Remove ${INSTALL_ROOT} and its contents?"
    rm -rf "$INSTALL_ROOT"
    log_info "Removed $INSTALL_ROOT"
  fi

  local link target
  for link in "${all_links[@]}"; do
    if [[ -L "$link" ]]; then
      target="$(readlink "$link")"
      case "$target" in
        "$INSTALL_ROOT"*)
          rm -f "$link"
          log_info "Removed $link"
          ;;
        *)
          log_warn "$link does not point into $INSTALL_ROOT; leaving it alone"
          ;;
      esac
    fi
  done
}

do_flatpak() {
  command -v flatpak >/dev/null 2>&1 || die "flatpak not found; install it first or choose another --method"

  log_info "Flatpak sandboxing note: the editor runs sandboxed and may have restricted"
  log_info "filesystem, terminal, and clipboard access compared to a native binary."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] would run: flatpak install -y --user flathub io.neovim.nvim"
    return 0
  fi

  if ! flatpak install -y --user flathub io.neovim.nvim; then
    die "flatpak install failed; you may need: flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
  fi
  log_info "Installed. Run with: flatpak run io.neovim.nvim"
  log_info "If ~/.local/share/flatpak/exports/bin is on your PATH, 'nvim' may also work directly."
}

do_brew() {
  command -v brew >/dev/null 2>&1 || die "brew not found; install Homebrew first or choose another --method"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] would run: brew install neovim"
    return 0
  fi

  brew install neovim
  check_path_warning
}

prompt_layering_or_fallback() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    die "host is an rpm-ostree atomic system; refusing to layer packages without --allow-layering (use --method tarball, flatpak, or brew instead)"
  fi

  log_warn "This is an rpm-ostree atomic host."
  log_warn "Layering neovim with rpm-ostree install adds it to the next boot's image"
  log_warn "and requires a reboot before it is usable; it also makes future updates"
  log_warn "of the base image heavier to pull."
  log_warn "The tarball method installs to ~/.local instead: no reboot, no layering."

  local reply
  read -r -p "Use rpm-ostree layering anyway? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      log_info "Falling back to the tarball method (no reboot, no layering)."
      do_install_tarball
      return 1
      ;;
  esac
}

do_package() {
  if [[ "$ATOMIC_HOST" -eq 1 ]]; then
    if [[ "$ALLOW_LAYERING" -ne 1 ]]; then
      prompt_layering_or_fallback || return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      log_info "[dry-run] would run: sudo rpm-ostree install neovim"
      log_info "[dry-run] a reboot would be required afterward"
      return 0
    fi

    sudo rpm-ostree install neovim
    log_info "rpm-ostree layered neovim into the next deployment. A reboot is required."
    return 0
  fi

  local pkg_mgr=""
  if command -v dnf >/dev/null 2>&1; then
    pkg_mgr="dnf"
  elif command -v apt-get >/dev/null 2>&1; then
    pkg_mgr="apt-get"
  elif command -v pacman >/dev/null 2>&1; then
    pkg_mgr="pacman"
  elif command -v zypper >/dev/null 2>&1; then
    pkg_mgr="zypper"
  elif command -v apk >/dev/null 2>&1; then
    pkg_mgr="apk"
  elif command -v xbps-install >/dev/null 2>&1; then
    pkg_mgr="xbps-install"
  else
    die "no supported package manager found (dnf, apt-get, pacman, zypper, apk, xbps-install)"
  fi

  local -a cmd update_cmd
  update_cmd=()
  case "$pkg_mgr" in
    dnf) cmd=(sudo dnf install -y neovim) ;;
    apt-get) update_cmd=(sudo apt-get update); cmd=(sudo apt-get install -y neovim) ;;
    pacman) cmd=(sudo pacman -S --noconfirm neovim) ;;
    zypper) cmd=(sudo zypper --non-interactive install neovim) ;;
    apk) cmd=(sudo apk add neovim) ;;
    xbps-install) cmd=(sudo xbps-install -y neovim) ;;
  esac

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "${#update_cmd[@]}" -gt 0 ]]; then
      log_info "[dry-run] would run: ${update_cmd[*]}"
    fi
    log_info "[dry-run] would run: ${cmd[*]}"
    return 0
  fi

  if [[ "${#update_cmd[@]}" -gt 0 ]]; then
    "${update_cmd[@]}"
  fi
  "${cmd[@]}"
  check_path_warning
}

extras_lua_contents() {
  cat <<'LUA_EOF'
local mason_packages = {
  "bash-language-server",
  "lua-language-server",
  "shellcheck",
  "shfmt",
  "stylua",
  "html-lsp",
  "css-lsp",
}

local parsers = {
  "lua",
  "vim",
  "vimdoc",
  "bash",
  "python",
  "markdown",
  "markdown_inline",
  "powershell",
  "yaml",
  "json",
  "html",
  "css",
  "regex",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = vim.list_extend(opts.ensure_installed or {}, parsers)
      return opts
    end,
    config = function(_, opts)
      require("nvim-treesitter").setup(opts)
      require("nvim-treesitter").install(opts.ensure_installed)
    end,
  },

  {
    "mason-org/mason.nvim",
    event = "VeryLazy",
    opts = { PATH = "append" },
    config = function(_, opts)
      require("mason").setup(opts)
      local registry = require "mason-registry"
      registry.refresh(function()
        for _, name in ipairs(mason_packages) do
          if registry.has_package(name) then
            local pkg = registry.get_package(name)
            if not pkg:is_installed() then
              pkg:install()
            end
          end
        end
      end)
    end,
  },

  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local lint = require "lint"
      lint.linters_by_ft = {
        sh = { "shellcheck" },
        bash = { "shellcheck" },
      }
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("nvim_lint_run", { clear = true }),
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },

  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash",
      },
      {
        "S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash Treesitter",
      },
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote Flash",
      },
      {
        "R",
        mode = { "o", "x" },
        function()
          require("flash").treesitter_search()
        end,
        desc = "Treesitter Search",
      },
      {
        "<c-s>",
        mode = "c",
        function()
          require("flash").toggle()
        end,
        desc = "Toggle Flash Search",
      },
    },
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = "markdown",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {},
  },
}
LUA_EOF
}

extras_spell_lua_contents() {
  cat <<'LUA_EOF'
return {
  {
    dir = vim.fn.stdpath "config",
    name = "extras-spell",
    lazy = false,
    priority = 1,
    config = function()
      vim.opt.spelllang = { "en_us", "de_de" }
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("extras_spell_prose", { clear = true }),
        pattern = { "markdown", "text", "gitcommit" },
        callback = function()
          vim.opt_local.spell = true
        end,
      })
    end,
  },
}
LUA_EOF
}

write_managed_file() {
  local dest="$1" contents_fn="$2"
  local tmp_file
  tmp_file="$(mktemp "${PLUGINS_DIR}/.$(basename "$dest").XXXXXX")"
  if ! "$contents_fn" >"$tmp_file"; then
    rm -f "$tmp_file"
    die "failed to generate contents for ${dest}"
  fi
  mv "$tmp_file" "$dest"
}

resolve_plugins_nvim_bin() {
  if [[ -f "$BIN_LINK" && -x "$BIN_LINK" ]]; then
    PLUGINS_NVIM_BIN="$BIN_LINK"
  elif command -v nvim >/dev/null 2>&1; then
    PLUGINS_NVIM_BIN="$(command -v nvim)"
  else
    PLUGINS_NVIM_BIN=""
  fi
}

run_lazy_sync() {
  local nvim_bin="$1" rc=0
  log_info "Running headless Lazy sync: ${nvim_bin} --headless \"+Lazy! sync\" +qa"
  timeout -k 10 600 "$nvim_bin" --headless "+Lazy! sync" +qa || rc=$?
  if [[ "$rc" -eq 124 ]]; then
    log_warn "Lazy sync timed out after 10 minutes; re-run manually: ${nvim_bin} --headless \"+Lazy! sync\" +qa"
  elif [[ "$rc" -eq 126 || "$rc" -eq 127 ]]; then
    log_warn "Lazy sync could not execute ${nvim_bin} (exit ${rc}: cannot execute / not found); this is not a Lazy plugin failure. Check that the binary runs: ${nvim_bin} --version"
  elif [[ "$rc" -ne 0 ]]; then
    log_warn "Lazy sync exited with status ${rc}; check :Lazy inside nvim."
  fi
  return "$rc"
}

run_mason_install() {
  local nvim_bin="$1"
  shift
  local -a pkgs=("$@")
  local lua_script pkg rc=0
  lua_script="$TMPDIR_CREATED/mason-install.lua"

  {
    printf 'local registry = require("mason-registry")\n'
    printf 'local pkgs = {\n'
    for pkg in "${pkgs[@]}"; do
      printf '  %s,\n' "\"${pkg}\""
    done
    printf '}\n'
    cat <<'LUA_EOF'
registry.refresh(function()
  local handles = {}
  for _, name in ipairs(pkgs) do
    if registry.has_package(name) then
      local pkg = registry.get_package(name)
      if not pkg:is_installed() then
        table.insert(handles, pkg:install())
      end
    end
  end
  local tries = 0
  local function check()
    tries = tries + 1
    for _, h in ipairs(handles) do
      if not h:is_closed() then
        if tries >= 1200 then
          vim.cmd("qa")
          return
        end
        vim.defer_fn(check, 500)
        return
      end
    end
    vim.cmd("qa")
  end
  check()
end)
LUA_EOF
  } >"$lua_script"

  log_info "Running headless Mason install for: ${pkgs[*]}"
  timeout -k 10 900 "$nvim_bin" --headless -c "luafile ${lua_script}" || rc=$?
  if [[ "$rc" -eq 124 ]]; then
    log_warn "Mason install timed out after 15 minutes; some packages may be missing. Re-run :MasonInstall <name> inside nvim as needed."
  elif [[ "$rc" -eq 126 || "$rc" -eq 127 ]]; then
    log_warn "Mason install could not execute ${nvim_bin} (exit ${rc}: cannot execute / not found); this is not a Mason package failure. Check that the binary runs: ${nvim_bin} --version"
  elif [[ "$rc" -ne 0 ]]; then
    log_warn "Headless Mason install exited with status ${rc}; check :Mason inside nvim."
  fi
  return "$rc"
}

fetch_spell_file() {
  local lang="$1" filename url dest tmp_file
  filename="${lang}.utf-8.spl"
  url="${SPELL_BASE_URL}/${filename}"
  dest="${SPELL_DIR}/${filename}"

  if [[ -s "$dest" ]] && head -c 8 "$dest" | grep -aq '^VIMspell'; then
    log_info "Spell file already present: ${dest}"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "[dry-run] would download: ${url} -> ${dest}"
    return 0
  fi

  mkdir -p "$SPELL_DIR"
  tmp_file="$(mktemp "${SPELL_DIR}/.${filename}.XXXXXX")"

  if ! http_fetch "$url" "$tmp_file"; then
    rm -f "$tmp_file"
    log_warn "failed to download spell file: ${url}"
    return 1
  fi

  if [[ ! -s "$tmp_file" ]] || ! head -c 8 "$tmp_file" | grep -aq '^VIMspell'; then
    rm -f "$tmp_file"
    log_warn "downloaded file does not look like a Vim spell file; discarding: ${url}"
    return 1
  fi

  mv "$tmp_file" "$dest"
  log_info "Downloaded spell file: ${dest}"
}

fetch_spell_files() {
  local lang
  for lang in "${SPELL_LANGS[@]}"; do
    fetch_spell_file "$lang" || log_warn "spell file fetch for '${lang}' failed; spell checking for that language may not work until it succeeds"
  done
}

setup_plugins() {
  resolve_plugins_nvim_bin
  if [[ -z "$PLUGINS_NVIM_BIN" ]]; then
    die "no nvim found on PATH or at ${BIN_LINK}; install nvim first (this script's own install action, or any other method) before using --with-plugins"
  fi

  local plugins_verify_err="$TMPDIR_CREATED/plugins-verify.err"
  local plugins_verify_rc=0
  verify_nvim_runs "$PLUGINS_NVIM_BIN" "$plugins_verify_err" || plugins_verify_rc=$?
  if [[ "$plugins_verify_rc" -ne 0 ]]; then
    diagnose_binary_failure "$PLUGINS_NVIM_BIN" "$plugins_verify_rc" "$plugins_verify_err"
    die "nvim at ${PLUGINS_NVIM_BIN} does not run (exit ${plugins_verify_rc}); fix this before --with-plugins can proceed"
  fi

  if [[ ! -d "$PLUGINS_DIR" ]]; then
    die "no lazy.nvim-style config found: ${PLUGINS_DIR} does not exist; refusing to bootstrap a new Neovim config. --with-plugins only extends an existing NvChad/lazy.nvim setup"
  fi

  log_info "nvim-treesitter's main branch needs the 'tree-sitter' CLI to compile parsers; see --check-deps or ${SCRIPT_NAME} --install-deps."
  log_info "fd (or fdfind) is used by NvChad/Telescope file pickers; see --check-deps."
  log_info "NvChad's lua/configs/lazy.lua disables Vim's netrw plugins, which Vim's own interactive spell-file download depends on; this script fetches the en/de spell files itself instead."

  local extras_exists=0 extras_spell_exists=0
  [[ -e "$EXTRAS_FILE" ]] && extras_exists=1
  [[ -e "$EXTRAS_SPELL_FILE" ]] && extras_spell_exists=1

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$extras_exists" -eq 1 ]]; then
      log_info "[dry-run] ${EXTRAS_FILE} already exists; would leave it untouched"
    else
      log_info "[dry-run] would write: ${EXTRAS_FILE}"
    fi
    if [[ "$extras_spell_exists" -eq 1 ]]; then
      log_info "[dry-run] ${EXTRAS_SPELL_FILE} already exists; would leave it untouched"
    else
      log_info "[dry-run] would write: ${EXTRAS_SPELL_FILE}"
    fi
    fetch_spell_files
    log_info "[dry-run] treesitter parsers to ensure: ${TREESITTER_PARSERS[*]}"
    if [[ "$NO_SYNC" -eq 1 ]]; then
      log_info "[dry-run] --no-sync given; would skip headless Lazy sync and Mason install"
    else
      log_info "[dry-run] would run: ${PLUGINS_NVIM_BIN} --headless \"+Lazy! sync\" +qa"
      log_info "[dry-run] would run a headless Mason install for: ${MASON_PACKAGES[*]}"
    fi
    return 0
  fi

  mkdir -p "$PLUGINS_DIR"

  if [[ "$extras_exists" -eq 1 ]]; then
    log_info "${EXTRAS_FILE} already exists; leaving it untouched."
  else
    confirm_or_die "Write ${EXTRAS_FILE} (treesitter, mason, nvim-lint, flash.nvim, render-markdown.nvim specs)?"
    write_managed_file "$EXTRAS_FILE" extras_lua_contents
    log_info "Wrote ${EXTRAS_FILE}"
  fi

  if [[ "$extras_spell_exists" -eq 1 ]]; then
    log_info "${EXTRAS_SPELL_FILE} already exists; leaving it untouched."
  else
    confirm_or_die "Write ${EXTRAS_SPELL_FILE} (en_us/de_de spell for markdown, text, gitcommit)?"
    write_managed_file "$EXTRAS_SPELL_FILE" extras_spell_lua_contents
    log_info "Wrote ${EXTRAS_SPELL_FILE}"
  fi

  fetch_spell_files

  if [[ "$NO_SYNC" -eq 1 ]]; then
    log_info "--no-sync given; skipping headless Lazy sync and Mason install."
    return 0
  fi

  require_cmd timeout

  if run_lazy_sync "$PLUGINS_NVIM_BIN"; then
    run_mason_install "$PLUGINS_NVIM_BIN" "${MASON_PACKAGES[@]}"
  else
    log_warn "Skipping Mason install because Lazy sync did not complete cleanly."
  fi
}

main() {
  parse_args "$@"

  TMPDIR_CREATED="$(mktemp -d)"

  detect_context
  print_context_summary

  case "$ACTION" in
    check-deps)
      check_deps
      exit 0
      ;;
    uninstall)
      do_uninstall
      exit 0
      ;;
    rollback)
      do_rollback
      exit 0
      ;;
    install-deps)
      install_deps
      if [[ "$WITH_PLUGINS" -eq 1 ]]; then
        setup_plugins
      fi
      exit 0
      ;;
  esac

  case "$METHOD" in
    tarball) do_install_tarball ;;
    flatpak) do_flatpak ;;
    package) do_package ;;
    brew) do_brew ;;
  esac

  if [[ "$DRY_RUN" -eq 0 ]]; then
    check_deps
  fi

  if [[ "$WITH_PLUGINS" -eq 1 ]]; then
    setup_plugins
  fi
}

main "$@"
