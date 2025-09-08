#!/usr/bin/env bash
# recon.sh — Optimized recon script (safe checks, modular)
# Usage: ./recon.sh example.com
# Output: recon_results/<domain>/report.txt

set -u

# === Tunables ===
FAST_NMAP_FIRST=1          # 1 = quick nmap (-F) first; 0 = skip quick
FULL_NMAP_ON_LIVE=0        # 1 = do -p- on live hosts (slow)
MAX_FFUF_HOSTS=10          # max live hosts to run ffuf on
FFUF_THREADS=150
WORDLIST="/usr/share/wordlists/dirb/common.txt"  # change if you prefer a different wordlist

# Extensions toggles
ENABLE_AMASS=1
ENABLE_WAYBACK_GAU=1
ENABLE_NUCLEI=1
ENABLE_CORSY=1
ENABLE_JS_ANALYSIS=1

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

need() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

if [ "$#" -ne 1 ]; then
  echo -e "${RED}Usage: $0 <domain>${NC}"
  exit 1
fi

DOMAIN="$1"
OUTDIR="recon_results/$DOMAIN"
REPORT="$OUTDIR/report.txt"

mkdir -p "$OUTDIR" "$OUTDIR/dirs" "$OUTDIR/ext"

echo -e "${GREEN}[+] Recon started for: $DOMAIN${NC}"
{
  echo "Recon Report for $DOMAIN"
  echo "Generated: $(date)"
  echo "===================================="
  echo
} > "$REPORT"

# -------------------------
# Subdomain enumeration
# -------------------------
echo -e "${GREEN}[+] Subdomain enumeration${NC}"
echo "#SubDomains:" >> "$REPORT"

# run subfinder & assetfinder in parallel (if present)
if need subfinder; then
  subfinder -silent -d "$DOMAIN" > "$OUTDIR/subfinder.txt" &
  PID_SF=$!
else
  echo "    (subfinder not installed)" >> "$REPORT"
fi

if need assetfinder; then
  assetfinder --subs-only "$DOMAIN" > "$OUTDIR/assetfinder.txt" &
  PID_AF=$!
else
  echo "    (assetfinder not installed)" >> "$REPORT"
fi

# wait for those that started
wait 2>/dev/null || true

# write outputs in the same skeleton order
if [ -f "$OUTDIR/subfinder.txt" ]; then
  echo "  ## Subfinder output" >> "$REPORT"
  sed 's/^/    /' "$OUTDIR/subfinder.txt" >> "$REPORT"
  echo >> "$REPORT"
fi

if [ -f "$OUTDIR/assetfinder.txt" ]; then
  echo "  ## Assetfinder output" >> "$REPORT"
  sed 's/^/    /' "$OUTDIR/assetfinder.txt" >> "$REPORT"
  echo >> "$REPORT"
fi

# merge
cat "$OUTDIR"/subfinder.txt "$OUTDIR"/assetfinder.txt 2>/dev/null | sed '/^\s*$/d' | sort -u > "$OUTDIR/all_subs.txt" || true
echo "  ## Combined unique subdomains: $( [ -f "$OUTDIR/all_subs.txt" ] && wc -l < "$OUTDIR/all_subs.txt" || echo 0 )" >> "$REPORT"
echo >> "$REPORT"

# -------------------------
# Live host probing (httpx)
# -------------------------
echo -e "${GREEN}[+] Probing live hosts (httpx)${NC}"
echo "#LiveHosts:" >> "$REPORT"
if need httpx && [ -s "$OUTDIR/all_subs.txt" ]; then
  httpx -silent -l "$OUTDIR/all_subs.txt" -mc 200,201,301,302,401,403 -timeout 8 -retries 1 -threads 150 > "$OUTDIR/live_urls.txt" || true
  awk -F/ 'NF>=3 {print $3}' "$OUTDIR/live_urls.txt" | sort -u > "$OUTDIR/live_hosts.txt" || true
  [ -s "$OUTDIR/live_urls.txt" ] && sed 's/^/    /' "$OUTDIR/live_urls.txt" >> "$REPORT" || echo "    (no live hosts found)" >> "$REPORT"
else
  echo "    (httpx missing or no subdomains)" >> "$REPORT"
fi
echo >> "$REPORT"

# -------------------------
# Nmap (fast-first strategy)
# -------------------------
echo -e "${GREEN}[+] Nmap scanning${NC}"
echo "#Ports:" >> "$REPORT"
NMAP_TARGETS="$OUTDIR/live_hosts.txt"
[ ! -s "$NMAP_TARGETS" ] && NMAP_TARGETS="$OUTDIR/all_subs.txt"

if need nmap && [ -s "$NMAP_TARGETS" ]; then
  if [ "$FAST_NMAP_FIRST" -eq 1 ]; then
    nmap -T4 -F --open -oN "$OUTDIR/nmap_fast.txt" -iL "$NMAP_TARGETS" >/dev/null 2>&1 || true
    echo "  ## nmap fast (-F)" >> "$REPORT"
    [ -s "$OUTDIR/nmap_fast.txt" ] && sed 's/^/    /' "$OUTDIR/nmap_fast.txt" >> "$REPORT" || echo "    (no common open ports found)" >> "$REPORT"
    echo >> "$REPORT"
  fi

  if [ "$FULL_NMAP_ON_LIVE" -eq 1 ]; then
    nmap -T4 -p- --open -oN "$OUTDIR/nmap_full.txt" -iL "$NMAP_TARGETS" >/dev/null 2>&1 || true
    echo "  ## nmap full (-p-) on targets" >> "$REPORT"
    [ -s "$OUTDIR/nmap_full.txt" ] && sed 's/^/    /' "$OUTDIR/nmap_full.txt" >> "$REPORT"
    echo >> "$REPORT"
  fi
else
  echo "    (nmap missing or no targets)" >> "$REPORT"
  echo >> "$REPORT"
fi

# -------------------------
# Directory fuzzing (ffuf) — on live URLs only, limited
# -------------------------
echo -e "${GREEN}[+] Directory enumeration (ffuf)${NC}"
echo "#Directories:" >> "$REPORT"
if need ffuf && [ -s "$OUTDIR/live_urls.txt" ]; then
  if [ ! -f "$WORDLIST" ]; then
    echo "    (wordlist $WORDLIST not found)" >> "$REPORT"
  else
    mapfile -t FFUF_URLS < <(head -n "$MAX_FFUF_HOSTS" "$OUTDIR/live_urls.txt")
    for URL in "${FFUF_URLS[@]}"; do
      HOST=$(echo "$URL" | awk -F/ '{print $3}')
      OUTJSON="$OUTDIR/dirs/${HOST}.json"
      echo "  ## $HOST" >> "$REPORT"
      ffuf -w "$WORDLIST" -u "${URL%/}/FUZZ" -mc 200,301,302 -of json -o "$OUTJSON" -t "$FFUF_THREADS" -timeout 5 -retries 0 >/dev/null 2>&1 || true
      if [ -s "$OUTJSON" ]; then
        jq -r '.results[]? | .url // .input.FUZZ' "$OUTJSON" 2>/dev/null | sed 's/^/    /' >> "$REPORT" || echo "    (parsed no results)" >> "$REPORT"
      else
        echo "    (no hits)" >> "$REPORT"
      fi
      echo >> "$REPORT"
    done
  fi
else
  echo "    (ffuf missing or no live URLs)" >> "$REPORT"
  echo >> "$REPORT"
fi

# -------------------------
# Extensions (kept modular)
# -------------------------
echo -e "${GREEN}[+] Extensions${NC}"
echo "#Extensions:" >> "$REPORT"

# Amass passive
if [ "$ENABLE_AMASS" -eq 1 ] && need amass; then
  echo "  ## Amass (passive)" >> "$REPORT"
  amass enum -passive -d "$DOMAIN" -norecursive -noalts -timeout 15 > "$OUTDIR/ext/amass.txt" 2>/dev/null || true
  sed 's/^/    /' "$OUTDIR/ext/amass.txt" >> "$REPORT" || true
  cat "$OUTDIR/all_subs.txt" "$OUTDIR/ext/amass.txt" 2>/dev/null | sort -u > "$OUTDIR/.tmp_subs" || true
  mv "$OUTDIR/.tmp_subs" "$OUTDIR/all_subs.txt" 2>/dev/null || true
  echo >> "$REPORT"
else
  echo "  ## Amass: (disabled or missing)" >> "$REPORT"
  echo >> "$REPORT"
fi

# Waybackurls + gau
if [ "$ENABLE_WAYBACK_GAU" -eq 1 ] && need waybackurls && need gau; then
  echo "  ## WaybackURLs + GAU" >> "$REPORT"
  waybackurls "$DOMAIN" > "$OUTDIR/ext/wayback.txt" 2>/dev/null || true
  gau --subs "$DOMAIN" > "$OUTDIR/ext/gau.txt" 2>/dev/null || true
  cat "$OUTDIR/ext/wayback.txt" "$OUTDIR/ext/gau.txt" | sed '/^\s*$/d' | sort -u > "$OUTDIR/ext/historical_urls.txt" || true
  echo "    Total historical URLs: $( [ -f "$OUTDIR/ext/historical_urls.txt" ] && wc -l < "$OUTDIR/ext/historical_urls.txt" || echo 0 )" >> "$REPORT"
  head -n 20 "$OUTDIR/ext/historical_urls.txt" | sed 's/^/    /' >> "$REPORT" || true
  echo >> "$REPORT"
else
  echo "  ## Wayback + GAU: (disabled or missing)" >> "$REPORT"
  echo >> "$REPORT"
fi

# Nuclei
if [ "$ENABLE_NUCLEI" -eq 1 ] && need nuclei; then
  echo "  ## Nuclei" >> "$REPORT"
  TARGET_URLS="$OUTDIR/live_urls.txt"
  [ ! -s "$TARGET_URLS" ] && TARGET_URLS="$OUTDIR/ext/historical_urls.txt"
  if [ -s "$TARGET_URLS" ]; then
    nuclei -silent -l "$TARGET_URLS" -c 30 -o "$OUTDIR/ext/nuclei.txt" 2>/dev/null || true
    echo "    Findings: $( [ -f "$OUTDIR/ext/nuclei.txt" ] && wc -l < "$OUTDIR/ext/nuclei.txt" || echo 0 )" >> "$REPORT"
    head -n 25 "$OUTDIR/ext/nuclei.txt" | sed 's/^/    /' >> "$REPORT" || true
  else
    echo "    (no target URLs for nuclei)" >> "$REPORT"
  fi
  echo >> "$REPORT"
else
  echo "  ## Nuclei: (disabled or missing)" >> "$REPORT"
  echo >> "$REPORT"
fi

# Corsy
if [ "$ENABLE_CORSY" -eq 1 ]; then
  echo "  ## Corsy" >> "$REPORT"
  if [ -d "$HOME/tools/Corsy" ] && [ -s "$OUTDIR/live_urls.txt" ]; then
    python3 "$HOME/tools/Corsy/corsy.py" -i "$OUTDIR/live_urls.txt" -t 50 -o "$OUTDIR/ext/corsy.json" >/dev/null 2>&1 || true
    [ -s "$OUTDIR/ext/corsy.json" ] && echo "    corsy output: $OUTDIR/ext/corsy.json" >> "$REPORT" || echo "    (no results or error)" >> "$REPORT"
  else
    echo "    (corsy missing or no live URLs)" >> "$REPORT"
  fi
  echo >> "$REPORT"
else
  echo "  ## Corsy: disabled" >> "$REPORT"
  echo >> "$REPORT"
fi

# JS analysis (subjs + LinkFinder)
if [ "$ENABLE_JS_ANALYSIS" -eq 1 ]; then
  echo "  ## JS Analysis (subjs + LinkFinder)" >> "$REPORT"
  if need subjs && [ -s "$OUTDIR/live_urls.txt" ]; then
    subjs -i "$OUTDIR/live_urls.txt" > "$OUTDIR/ext/js_urls.txt" 2>/dev/null || true
    echo "    JS URLs: $( [ -f "$OUTDIR/ext/js_urls.txt" ] && wc -l < "$OUTDIR/ext/js_urls.txt" || echo 0 )" >> "$REPORT"
    if [ -d "$HOME/tools/LinkFinder" ] && [ -s "$OUTDIR/ext/js_urls.txt" ]; then
      head -n 50 "$OUTDIR/ext/js_urls.txt" | while read -r js; do
        python3 "$HOME/tools/LinkFinder/linkfinder.py" -i "$js" -o CLI 2>/dev/null | sed 's/^/    /' >> "$REPORT" || true
      done
    else
      echo "    (LinkFinder missing or no JS URLs)" >> "$REPORT"
    fi
  else
    echo "    (subjs missing or no live URLs)" >> "$REPORT"
  fi
  echo >> "$REPORT"
else
  echo "  ## JS Analysis: disabled" >> "$REPORT"
  echo >> "$REPORT"
fi

echo -e "${GREEN}[+] Recon finished. Report: $REPORT${NC}"
