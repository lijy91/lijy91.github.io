#!/bin/sh
#
# im in ur computer 👀
# Find apps on your machine that ship my code (macOS / Linux).
#
#   curl -fsSL https://lijy91.github.io/im-in-ur-computer.sh | sh
#
# Run with -h for options.

KEYWORD="LiJianying"
ICASE=0
LIST=0
ONLY_DIRS=""

# Help is inlined (not read from $0) so it works with `curl | sh`,
# and is a plain string (some shells back heredocs with temp files)
usage() {
  printf '%s\n' \
    "im in ur computer 👀" \
    "Find apps on your machine that ship my code (macOS / Linux)." \
    "" \
    "Usage:" \
    "  im-in-ur-computer.sh [-i] [-l] [-k keyword] [-d dir]... [extra dirs...]" \
    "  curl -fsSL https://lijy91.github.io/im-in-ur-computer.sh | sh -s -- [options]" \
    "" \
    "  -k  keyword to look for in NOTICES (default: LiJianying)" \
    "  -d  search only this dir instead of the defaults (repeatable)" \
    "  -i  case-insensitive" \
    "  -l  list the apps that depend on my code" \
    "  -h  show this help"
}

while getopts "k:d:ilh" opt; do
  case "$opt" in
    k) KEYWORD="$OPTARG" ;;
    i) ICASE=1 ;;
    l) LIST=1 ;;
    d) ONLY_DIRS="$ONLY_DIRS|$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

OS=$(uname -s)
case "$OS" in
  Darwin)
    DIRS="/Applications $HOME/Applications"
    # Input methods (paths contain spaces, so they're |-separated)
    DIRS_IM="/Library/Input Methods|$HOME/Library/Input Methods"
    ;;
  Linux)
    DIRS="/opt /usr/lib /usr/local /usr/share /snap /var/lib/flatpak/app \
$HOME/.local/share/flatpak/app $HOME/.local/share $HOME/.local/lib $HOME/Applications $HOME/apps"
    ;;
  *)
    echo "unsupported OS: $OS" >&2
    exit 1
    ;;
esac

# -d replaces the default search dirs
if [ -n "$ONLY_DIRS" ]; then
  DIRS=""
  DIRS_IM="${ONLY_DIRS#|}"
fi

# Spinner on stderr while working (only when stderr is a terminal).
# Nothing is written to disk: status() restarts the spinner with a new message.
SPIN=0
[ -t 2 ] && SPIN=1
SPIN_PID=""
spin() {
  while :; do
    for f in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do
      printf '\r\033[K%s %s' "$f" "$1" >&2
      sleep 0.1 2>/dev/null || sleep 1
    done
  done
}
kill_spin() {
  if [ -n "$SPIN_PID" ]; then
    kill "$SPIN_PID" 2>/dev/null
    wait "$SPIN_PID" 2>/dev/null
    SPIN_PID=""
  fi
}
status() {
  [ $SPIN -eq 1 ] || return 0
  kill_spin
  spin "$1" &
  SPIN_PID=$!
}
stop_spin() {
  [ $SPIN -eq 1 ] || return 0
  kill_spin
  SPIN=0
  printf '\r\033[K\033[?25h' >&2
}
trap stop_spin EXIT
trap 'stop_spin; exit 130' INT TERM

[ $SPIN -eq 1 ] && printf '\033[?25l' >&2
status "sneaking into ur apps..."

# NOTICES.Z is gzip (zlib as fallback); plain NOTICES is printed as-is
decompress() {
  case "$1" in
    *.Z)
      gzip -dc "$1" 2>/dev/null && return 0
      if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys,zlib;sys.stdout.buffer.write(zlib.decompress(open(sys.argv[1],"rb").read(),47))' "$1" 2>/dev/null && return 0
      fi
      perl -MCompress::Zlib -e 'local $/; open F,"<",$ARGV[0] or exit 1; binmode F; my $d=uncompress(<F>); defined $d or exit 1; print $d' "$1" 2>/dev/null
      ;;
    *)
      cat "$1"
      ;;
  esac
}

# App name from the NOTICES path
app_name() {
  case "$OS" in
    Darwin)
      # Outermost .app (covers nested apps and iOS Wrapper/xxx.app)
      p=$(echo "$1" | sed 's#\.app/.*#.app#')
      basename "$p" .app
      ;;
    *)
      # Linux bundle: <app>/data/flutter_assets/NOTICES.Z
      p=$(dirname "$(dirname "$1")")
      [ "$(basename "$p")" = "data" ] && p=$(dirname "$p")
      basename "$p"
      ;;
  esac
}

# Print the packages whose license block mentions the keyword, e.g.
# "tray_manager, window_manager". Platform variants like
# screen_retriever_macos are folded into screen_retriever.
search_notices() {
  awk -v kw="$KEYWORD" -v icase="$ICASE" '
    BEGIN {
      sep = sprintf("%80s", ""); gsub(/ /, "-", sep)
      inhdr = 1; nh = 0; hit = 0; n = 0
      if (icase) kw = tolower(kw)
    }
    function flush(   i) {
      if (hit) for (i = 1; i <= nh; i++) if (!(hdr[i] in seen)) { seen[hdr[i]] = 1; pkgs[++n] = hdr[i] }
      nh = 0; hit = 0
    }
    $0 == sep { flush(); inhdr = 1; next }
    inhdr { if ($0 == "") inhdr = 0; else hdr[++nh] = $0 }
    { line = icase ? tolower($0) : $0; if (index(line, kw)) hit = 1 }
    END {
      flush()
      out = ""
      for (i = 1; i <= n; i++) {
        skip = 0
        for (j = 1; j <= n; j++)
          if (i != j && index(pkgs[i], pkgs[j] "_") == 1) { skip = 1; break }
        if (!skip) out = out (out == "" ? "" : ", ") pkgs[i]
      }
      if (out == "") exit 1
      print out
    }
  '
}

scan_dir() {
  [ -d "$1" ] || return 0
  find "$1" -type f \( -name 'NOTICES.Z' -o -name 'NOTICES' \) \
    -path '*flutter_assets/*' 2>/dev/null
}

FOUND=$(
  for d in $DIRS; do scan_dir "$d"; done
  if [ -n "$DIRS_IM" ]; then
    IFS='|'
    for d in $DIRS_IM; do scan_dir "$d"; done
  fi
  for d in "$@"; do scan_dir "$d"; done
)
FOUND=$(printf '%s\n' "$FOUND" | sort -u)

count=$(printf '%s\n' "$FOUND" | grep -c .)
total=0
matched=0
all_pkgs=""
apps=""
# Split on newlines only (paths may contain spaces), no globbing
set -f
OLD_IFS=$IFS
IFS='
'
for notices in $FOUND; do
  IFS=$OLD_IFS
  [ -n "$notices" ] || continue
  total=$((total + 1))
  name=$(app_name "$notices")
  status "reading the fine print of $name ($total/$count)..."

  pkgs=$(decompress "$notices" | search_notices)
  if [ -n "$pkgs" ]; then
    matched=$((matched + 1))
    all_pkgs="$all_pkgs,$pkgs"
    n=$(echo "$pkgs" | tr ',' '\n' | grep -c .)
    apps="$apps$name|$n
"
  fi
done
IFS=$OLD_IFS
set +f

stop_spin

npkgs=$(echo "$all_pkgs" | tr ',' '\n' | sed 's/^ *//' | grep -v '^$' | sort -u | wc -l | tr -d ' ')

# Colors only when writing to a terminal
if [ -t 1 ]; then
  B=$(printf '\033[1m'); D=$(printf '\033[2m'); C=$(printf '\033[36m'); R=$(printf '\033[0m')
else
  B=""; D=""; C=""; R=""
fi

plural() { [ "$1" -eq 1 ] && echo "$1 $2" || echo "$1 ${2}s"; }

if [ $matched -gt 0 ]; then
  echo "😼 ${B}oh hai. im in ur computer.${R}"
  echo ""
  if [ $matched -eq 1 ]; then were="was"; they="it depends"; else were="were"; they="they depend"; fi
  echo "$(plural $matched app) here $were built by other ppl. $they on $(plural $npkgs package) i wrote."
  echo "${B}u never installed me. but here i am.${R}"
  if [ $LIST -eq 1 ]; then
    echo ""
    printf '%s' "$apps" | sort -f | while IFS='|' read -r name n; do
      echo "  · $name ${D}($(plural $n package))${R}"
    done
  fi
  echo ""
  echo "${D}not my apps. just my code, quietly doing its job inside ♥${R}"
else
  echo "👀 ${B}im not in ur computer... yet.${R}"
  echo ""
  if [ $total -gt 0 ]; then
    echo "looked through $(plural $total app). none of them depend on my code."
    echo "${B}ur next favorite one might.${R}"
  else
    echo "looked around. couldn't find a single app to peek into."
    echo "${B}wrong dir, maybe?${R}"
  fi
fi
echo ""
echo "${D}who dis? →${R} ${C}https://github.com/lijy91${R}"
echo ""
