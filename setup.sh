#!/bin/bash

echo "[*] Installing required tools..."

# Update system
sudo apt update -y
sudo apt install -y golang-go python3 python3-pip git nmap ffuf

# Create tools dir
mkdir -p $HOME/tools
cd $HOME/tools

# Subfinder
if ! command -v subfinder &>/dev/null; then
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
fi

# Assetfinder
if ! command -v assetfinder &>/dev/null; then
    go install -v github.com/tomnomnom/assetfinder@latest
fi

# Amass
if ! command -v amass &>/dev/null; then
    sudo snap install amass
fi

# Httpx
if ! command -v httpx &>/dev/null; then
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
fi

# Gau
if ! command -v gau &>/dev/null; then
    go install -v github.com/lc/gau/v2/cmd/gau@latest
fi

# Waybackurls
if ! command -v waybackurls &>/dev/null; then
    go install -v github.com/tomnomnom/waybackurls@latest
fi

# Nuclei
if ! command -v nuclei &>/dev/null; then
    go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest
fi

# Corsy
if [ ! -d "$HOME/tools/Corsy" ]; then
    git clone https://github.com/s0md3v/Corsy.git
    pip3 install -r Corsy/requirements.txt
fi

# LinkFinder (for JS)
if [ ! -d "$HOME/tools/LinkFinder" ]; then
    git clone https://github.com/GerbenJavado/LinkFinder.git
    pip3 install -r LinkFinder/requirements.txt
fi

echo "[+] Setup complete! Make sure \$HOME/go/bin is in your PATH."
