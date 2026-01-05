#!/bin/bash

# Aborta o script se qualquer comando falhar
set -e

HELMFILE_VERSION="v1.2.3"

if ! command -v helmfile &> /dev/null; then
    echo "Instalando Helmfile ${HELMFILE_VERSION}..."
    
    # Download do binário
    curl -L "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_$(echo ${HELMFILE_VERSION} | sed 's/v//')_linux_amd64.tar.gz" | tar xz
    
    # Move para o path do sistema
    sudo mv helmfile /usr/local/bin/
    
    echo "Helmfile instalado com sucesso!"
else
    echo "Helmfile já está instalado. Versão: $(helmfile --version)"
fi