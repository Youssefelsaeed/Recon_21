# 🔍 Recon Toolkit

Automated reconnaissance toolkit for **bug bounty hunters** and **pentesters**.  
Collects **subdomains, directories, ports, URLs, JS files, CORS checks, and vulnerabilities** into one organized report.

---

## 🚀 Features
- Subdomain enumeration: `subfinder`, `assetfinder`, `amass`
- Live probe: `httpx`
- Directory brute force: `ffuf`
- Port scanning: `nmap` (fast-first strategy)
- URL collection: `gau`, `waybackurls`
- Template-based vulnerability checks: `nuclei`
- CORS checks: `Corsy`
- JavaScript discovery & analysis: `subjs` + `LinkFinder`
- Organized master report: `recon_results/<domain>/report.txt`

---

## ⚙️ Quick start

```bash
# 1) Clone repo (on the machine where you will run scripts - e.g., Linux/WSL)
git clone https://github.com/YOUR-USERNAME/recon-toolkit.git
cd recon-toolkit

# 2) Make scripts executable
chmod +x setup.sh recon.sh

# 3) Run setup (install tools) — run once (on Linux/WSL)
./setup.sh

# 4) Run recon on a target you are authorized to test
./recon.sh example.com

# 5) Open the report
less recon_results/example.com/report.txt
```

**Important**: Only run recon against assets you have permission to test.

---

## 🔧 Customize
Open `recon.sh` and change the toggles at the top:
- `ENABLE_AMASS`, `ENABLE_WAYBACK_GAU`, `ENABLE_NUCLEI`, `ENABLE_CORSY`, `ENABLE_JS_ANALYSIS`
- `MAX_FFUF_HOSTS`, `FFUF_THREADS`, `WORDLIST`

Set `FULL_NMAP_ON_LIVE=1` if you want a slow full port scan after fast scanning.

---

## 🧾 Output
All raw output + the report are stored under:
```
recon_results/<domain>/
```

---

## ⚖️ License
MIT — see `LICENSE` file.

---

If you find this helpful, give it a star ⭐
