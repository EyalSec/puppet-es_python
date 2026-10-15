#!/bin/sh
# es-python fleet install helper
#
# Installs es-python for the user that runs this script, the same way the
# install command on the EyalSec Machines page does, so that configuration
# management can do it on many hosts. When es-python is already installed for
# this user it changes nothing and exits 0, so it is safe to run on every
# configuration pass.
#
# Run it with sh, as the user es-python is for. Do not source it.
#
#   sh es-python-fleet-install.sh [--api-key-stdin | --install-secret-stdin] [--check]
#
# Credentials, one of the two. Each can come from the environment, from a file
# (the _FILE form, read and never copied) or from standard input. They are never
# printed and never put on a command line.
#
#   EYALSEC_API_KEY         A full-access API key (Settings > API access). One key
#                           serves the whole fleet: for each host the script finds
#                           the machine named after it, adds it on the first run,
#                           and asks for a fresh one-time install secret.
#   EYALSEC_INSTALL_SECRET  A one-time install secret for one machine, from the
#                           Machines page or the API. It works once and expires
#                           10 minutes after it was issued.
#
# Settings:
#   EYALSEC_AUTHORIZED      "true" is required with an API key. It is your
#                           confirmation that you own this host or are authorized
#                           to monitor it: the same statement as the tick box on
#                           the Machines page.
#   EYALSEC_URL             Your EyalSec address. Default https://eyalsec.com
#   EYALSEC_MACHINE         The machine name for this host. Default: the host name.
#   EYALSEC_PYTHON_VERSION  3.9 to 3.14. Default: match the host's own python3.
#   EYALSEC_FORCE           "1" installs again even when already installed (an update).
#   EYALSEC_HOME            Install into this directory instead of the user's home.
#   EYALSEC_PLAIN_OUTPUT    "1" prints plain ASCII even on a terminal (it already
#                           does when the output is a log or a pipe).
#
# --check exits 0 when es-python is installed for this user and 1 when it is not,
# and does nothing else.
#
# Exit status: 0 installed or already installed; 1 the install did not finish;
# 2 a setting is missing or wrong.
#
# MIT License. https://eyalsec.com/docs/install

__es_fleet_main() (
    say()  { printf 'es-python: %s\n' "$*"; }
    warn() { printf 'es-python: %s\n' "$*" >&2; }
    fail() { warn "$*"; exit 1; }
    usage_fail() { warn "$*"; exit 2; }

    from_stdin=""
    check_only=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --api-key-stdin)        from_stdin=api_key; shift ;;
            --install-secret-stdin) from_stdin=install_secret; shift ;;
            --check)                check_only=1; shift ;;
            -h|--help)
                sed -n '2,40p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
                exit 0 ;;
            *) usage_fail "unknown option: $1" ;;
        esac
    done

    # Under sudo the installer installs into SUDO_USER's home, which is right for
    # a person at a terminal and wrong here: configuration tools reach the target
    # user through sudo, and es-python belongs to the user running this script.
    # EYALSEC_HOME picks another directory, such as a volume shared by a
    # Kubernetes init container and the application container.
    unset SUDO_USER SUDO_UID SUDO_GID SUDO_COMMAND
    if [ -n "${EYALSEC_HOME:-}" ]; then
        HOME="$EYALSEC_HOME"
    else
        __h="$( { getent passwd "$(id -u)" 2>/dev/null || true; } | cut -d: -f6)"
        if [ -n "$__h" ] && [ -d "$__h" ]; then
            HOME="$__h"
        fi
    fi
    if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
        usage_fail "the user $(id -un 2>/dev/null) has no home directory; es-python installs into it"
    fi
    export HOME

    pyver="${EYALSEC_PYTHON_VERSION:-}"
    case "$pyver" in
        ''|3.9|3.10|3.11|3.12|3.13|3.14) ;;
        auto) pyver="" ;;
        *) usage_fail "EYALSEC_PYTHON_VERSION must be one of 3.9, 3.10, 3.11, 3.12, 3.13, 3.14 (or empty to match the host)" ;;
    esac

    launcher="$HOME/.local/bin/es-python"
    [ -n "$pyver" ] && launcher="$HOME/.local/bin/es-python$pyver"
    is_installed() {
        [ -x "$launcher" ] || return 1
        for __m in "$HOME"/.eyalsec/builds/*.json; do
            [ -f "$__m" ] && return 0
        done
        return 1
    }

    if [ "$check_only" = 1 ]; then
        is_installed && exit 0
        exit 1
    fi
    if [ "${EYALSEC_FORCE:-0}" != 1 ] && is_installed; then
        say "already installed for $(id -un 2>/dev/null) ($launcher); nothing to do"
        exit 0
    fi

    # ── Credentials ────────────────────────────────────────────────────────
    api_key="${EYALSEC_API_KEY:-}"
    install_secret="${EYALSEC_INSTALL_SECRET:-}"
    if [ -z "$api_key" ] && [ -n "${EYALSEC_API_KEY_FILE:-}" ]; then
        [ -r "$EYALSEC_API_KEY_FILE" ] || usage_fail "cannot read EYALSEC_API_KEY_FILE"
        api_key="$(head -n 1 "$EYALSEC_API_KEY_FILE")"
    fi
    if [ -z "$install_secret" ] && [ -n "${EYALSEC_INSTALL_SECRET_FILE:-}" ]; then
        [ -r "$EYALSEC_INSTALL_SECRET_FILE" ] || usage_fail "cannot read EYALSEC_INSTALL_SECRET_FILE"
        install_secret="$(head -n 1 "$EYALSEC_INSTALL_SECRET_FILE")"
    fi
    case "$from_stdin" in
        api_key)        IFS= read -r api_key || [ -n "$api_key" ] ;;
        install_secret) IFS= read -r install_secret || [ -n "$install_secret" ] ;;
    esac
    # Keep the values in this shell only: nothing started from here inherits them.
    unset EYALSEC_API_KEY EYALSEC_INSTALL_SECRET
    api_key="$(printf '%s' "$api_key" | tr -d ' \r\n\t')"
    install_secret="$(printf '%s' "$install_secret" | tr -d ' \r\n\t')"
    if [ -z "$api_key" ] && [ -z "$install_secret" ]; then
        usage_fail "no credential: set EYALSEC_API_KEY (or EYALSEC_API_KEY_FILE) or EYALSEC_INSTALL_SECRET (or EYALSEC_INSTALL_SECRET_FILE)"
    fi

    base="${EYALSEC_URL:-https://eyalsec.com}"
    base="${base%/}"
    case "$base" in
        https://*|http://127.0.0.1*|http://localhost*) ;;
        *) usage_fail "EYALSEC_URL must start with https://" ;;
    esac

    command -v curl >/dev/null 2>&1 || usage_fail "curl is required; install it with your package manager"
    command -v bash >/dev/null 2>&1 || usage_fail "bash is required to run the installer"

    work="$(mktemp -d 2>/dev/null)" || fail "mktemp failed"
    chmod 700 "$work" || fail "cannot protect the temporary directory"
    trap 'rm -rf "$work"' EXIT
    trap 'exit 130' INT TERM

    # ── API key: find or add this host's machine, get a one-time secret ───
    script_url="$base/install.sh"
    if [ -n "$api_key" ]; then
        case "${EYALSEC_AUTHORIZED:-}" in
            true|TRUE|True|1|yes) ;;
            *) usage_fail "set EYALSEC_AUTHORIZED=true to confirm you own this host or are authorized to monitor it" ;;
        esac
        machine="${EYALSEC_MACHINE:-}"
        [ -n "$machine" ] || machine="$(uname -n 2>/dev/null)"
        [ -n "$machine" ] || usage_fail "set EYALSEC_MACHINE: this host reports no name"

        # The key reaches curl through a 0600 file, never its command line.
        (umask 077 && printf 'X-API-Key: %s\n' "$api_key" > "$work/hdr") || fail "cannot write a temporary file"
        api() {
            __p="$1"; shift
            curl -sS -X POST -H "@$work/hdr" -o "$work/body" -w '%{http_code}' \
                --retry 2 --retry-delay 3 "$@" "$base$__p" 2>"$work/curlerr" || true
        }
        kv() { sed -n "s/^$1=//p" "$work/body" 2>/dev/null | head -n 1; }
        api_error() {
            __e="$(kv error)"
            [ -n "$__e" ] || __e="$(sed -n 's/.*"error" *: *"\([^"]*\)".*/\1/p' "$work/body" 2>/dev/null | head -n 1)"
            [ -n "$__e" ] || __e="$(head -c 300 "$work/body" 2>/dev/null)"
            [ -n "$__e" ] || __e="$(cat "$work/curlerr" 2>/dev/null)"
            printf '%s' "$__e"
        }
        ask_secret() {
            set -- -d attested=true -d format=text --data-urlencode "machine_name=$machine"
            [ -n "$pyver" ] && set -- "$@" --data-urlencode "python_version=$pyver"
            api /api/ci/install/ "$@"
        }

        say "getting an install secret for machine $machine from $base"
        code="$(ask_secret)"
        if [ "$code" = 422 ] && api_error | grep -q "is named .* yet"; then
            # First run on this host: add the machine with its build left to
            # detection, exactly as the Machines page does by default.
            set -- --data-urlencode "machine_name=$machine" -d product=python
            [ -n "$pyver" ] && set -- "$@" --data-urlencode "python_version=$pyver"
            acode="$(api /api/add_new_machine/ "$@")"
            [ "$acode" = 200 ] || fail "adding machine $machine failed (HTTP $acode): $(api_error)"
            say "added machine $machine (build detected at install)"
            code="$(ask_secret)"
        fi
        case "$code" in
            200) ;;
            000) fail "could not reach $base: $(cat "$work/curlerr" 2>/dev/null)" ;;
            401|403) fail "the API key was refused (HTTP $code): $(api_error)" ;;
            *) fail "getting an install secret failed (HTTP $code): $(api_error)" ;;
        esac
        install_secret="$(kv secret)"
        __s="$(kv script_path)"
        [ -n "$__s" ] && script_url="$__s"
        [ -n "$install_secret" ] || fail "the server's answer had no install secret"
        rm -f "$work/hdr" "$work/body"
    fi

    # ── Install, as the Machines page command does ─────────────────────────
    # The same host facts the one-line command sends: processor, C library,
    # the ID lines of /etc/os-release and the host's python3 version. The
    # secret travels in a 0600 file.
    (umask 077 && printf 'secret=%s' "$install_secret" > "$work/sec") || fail "cannot write a temporary file"
    glibc="$(ldd --version 2>/dev/null | head -n 1)"
    host_arch="$(uname -m 2>/dev/null)"
    osr="$(grep -E '^(ID|ID_LIKE|VERSION_ID)=' /etc/os-release 2>/dev/null)"
    py="$(python3 -V 2>/dev/null)"
    # The installer runs in a child, never sourced. Unless the output is a
    # terminal, its colours and symbols are turned into plain ASCII, which every
    # configuration tool's log can hold whatever its locale.
    plain() {
        __esc="$(printf '\033')"; __ok="$(printf '\342\234\223')"
        __no="$(printf '\342\234\227')"; __to="$(printf '\342\206\222')"
        __dot="$(printf '\302\267')"; __bar="$(printf '\342\224\200')"
        LC_ALL=C sed -e "s/${__esc}\[[0-9;]*m//g" -e "s/${__ok}/ok/g" \
            -e "s/${__no}/x/g" -e "s/${__to}/->/g" -e "s/${__dot}/-/g" \
            -e "s/${__bar}/-/g" | LC_ALL=C tr -d '\200-\377'
    }
    run_installer() {
        if [ -t 1 ] && [ "${EYALSEC_PLAIN_OUTPUT:-0}" != 1 ]; then
            bash "$work/installer" </dev/null
            return
        fi
        { bash "$work/installer" </dev/null; echo "$?" > "$work/rc"; } 2>&1 | plain
        return "$(cat "$work/rc" 2>/dev/null || echo 1)"
    }

    say "preparing your build on the server (this can take up to a minute)"
    tries=0
    while :; do
        tries=$((tries + 1))
        icode="$( (umask 077 && curl -sS -o "$work/installer" -w '%{http_code}' \
            -d "@$work/sec" -d stage=install \
            --data-urlencode "glibc=$glibc" --data-urlencode "arch=$host_arch" \
            --data-urlencode "osr=$osr" --data-urlencode "py=$py" \
            "$script_url" 2>"$work/curlerr") || true)"
        # 503 is "busy, retry": the one-time secret is still valid then.
        if [ "$icode" = 503 ] && [ "$tries" -lt 4 ]; then
            say "the install service is busy; retrying in 30 seconds"
            sleep 30
            continue
        fi
        break
    done
    rm -f "$work/sec"
    case "$icode" in
        200) ;;
        000) fail "could not reach $script_url: $(cat "$work/curlerr" 2>/dev/null)" ;;
        *)
            # A refusal is a short script that prints the reason.
            if head -n 1 "$work/installer" 2>/dev/null | grep -q '^#'; then
                run_installer || true
            fi
            fail "the install was refused (HTTP $icode)"
            ;;
    esac
    run_installer || fail "the install did not finish (see the lines above)"
    is_installed || fail "the installer finished but $launcher is missing"
    say "installed for $(id -un 2>/dev/null): $launcher"
)

__es_fleet_rc=0
__es_fleet_main "$@" || __es_fleet_rc=$?
exit "$__es_fleet_rc"
