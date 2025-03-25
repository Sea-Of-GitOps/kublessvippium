#!/bin/bash


# Installa i pacchetti necessari
sudo dnf install -y dnf-plugins-core ca-certificates curl gnupg2 git

# Scarica lo script di installazione di OpenTofu
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
# Alternativamente: wget --secure-protocol=TLSv1_2 --https-only https://get.opentofu.org/install-opentofu.sh -O install-opentofu.sh

# Rendi eseguibile lo script
chmod +x install-opentofu.sh

# Ispeziona il file prima di eseguirlo (opzionale)

# Esegui lo script di installazione
./install-opentofu.sh --install-method rpm

# Rimuovi lo script di installazione
rm -f install-opentofu.sh

# Aggiungi il repository Docker ufficiale
sudo dnf install docker-cli containerd

# Installa Docker

# Abilita e avvia il servizio Docker
sudo systemctl enable --now docker

# Aggiungi l'utente al gruppo docker
sudo groupadd -f docker
sudo usermod -aG docker $USER
newgrp docker

# Scarica e installa Kind se l'architettura è x86_64
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64

chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
