#!/usr/bin/env bash

set -euo pipefail

############################################
# Configurações
############################################
SEALED_SECRETS_NS="kube-system"
SEALED_SECRETS_RELEASE="sealed-secrets-controller"
SEALED_SECRETS_VERSION="2.15.0"

OBS_NAMESPACE="observability"

SECRET_NAME="grafana-admin-credentials"
SEALED_SECRET_NAME="grafana-admin-sealed"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" # Diretório raiz do repositório (independente de onde o script é executado)
BIN_DIR="$ROOT_DIR/.bin"
YQ_BIN="$BIN_DIR/yq"

mkdir -p "$BIN_DIR"

TMP_DIR=".tmp-secrets"
PLAIN_SECRET_FILE="${TMP_DIR}/grafana-secret.yaml"
SEALED_SECRET_FILE="$ROOT_DIR/helm/grafana/secrets/grafana-admin-sealed.yaml"

############################################
# Helpers
############################################
log() {
  echo -e "\n▶ $1"
}

############################################
# Pré-checks
############################################
log "Verificando dependências"

command -v kubectl >/dev/null 2>&1 || {
  echo "❌ kubectl não encontrado"
  exit 1
}

command -v helm >/dev/null 2>&1 || {
  echo "❌ helm não encontrado"
  exit 1
}

############################################
# Pré-requisitos
############################################
  if [ ! -x "$YQ_BIN" ]; then
    echo "▶ Instalando yq localmente"
    curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.43.1/yq_linux_amd64 \
      -o "$YQ_BIN"
    chmod +x "$YQ_BIN"
  else
    echo "▶ yq já disponível"
  fi

############################################
# 1. Instalar kubeseal (binário local)
############################################
if ! command -v kubeseal >/dev/null 2>&1; then
  log "Instalando kubeseal"

  OS=$(uname | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
      echo "❌ Arquitetura não suportada: $ARCH"
      exit 1
      ;;
  esac

  curl -fsSL -o kubeseal.tar.gz \
    "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${SEALED_SECRETS_VERSION}/kubeseal-${SEALED_SECRETS_VERSION}-${OS}-${ARCH}.tar.gz"

  tar -xzf kubeseal.tar.gz kubeseal
  sudo mv kubeseal /usr/local/bin/
  rm kubeseal.tar.gz

  log "kubeseal instalado com sucesso"
else
  log "kubeseal já instalado"
fi

############################################
# 2. Instalar Sealed Secrets Controller
############################################
log "Instalando Sealed Secrets Controller via Helm"

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

EXISTING_RELEASE=$(helm list -n "$SEALED_SECRETS_NS" -q | grep sealed-secrets || true)

if [[ -n "$EXISTING_RELEASE" ]]; then
  log "Sealed Secrets já instalado como release: $EXISTING_RELEASE"
  SEALED_SECRETS_RELEASE="$EXISTING_RELEASE"
else
  helm install "$SEALED_SECRETS_RELEASE" sealed-secrets/sealed-secrets \
    --namespace "$SEALED_SECRETS_NS" \
    --version "$SEALED_SECRETS_VERSION"
fi


log "Aguardando controller ficar pronto..."
kubectl rollout status deployment/sealed-secrets-controller -n "$SEALED_SECRETS_NS"

############################################
# 3. Criar namespace observability (se não existir)
############################################
log "Garantindo namespace ${OBS_NAMESPACE}"

kubectl get namespace "$OBS_NAMESPACE" >/dev/null 2>&1 || \
  kubectl create namespace "$OBS_NAMESPACE"

############################################
# 4. Gerar Secret temporário (NÃO versionado)
############################################
log "Gerando Secret temporário para criptografia"

mkdir -p "$TMP_DIR"

read -rp "Grafana admin user: " GRAFANA_USER
read -srp "Grafana admin password: " GRAFANA_PASSWORD
echo ""

kubectl create secret generic "$SECRET_NAME" \
  --from-literal=admin-user="$GRAFANA_USER" \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --namespace "$OBS_NAMESPACE" \
  --dry-run=client \
  -o yaml > "$PLAIN_SECRET_FILE"

############################################
# 5. Gerar SealedSecret
############################################
log "Gerando SealedSecret"

kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace "$SEALED_SECRETS_NS" \
  --format yaml \
  < "$PLAIN_SECRET_FILE" > "$SEALED_SECRET_FILE"

log "Adicionando annotation de ownership ao SealedSecret"

"$YQ_BIN" eval '
  .spec.template.metadata.annotations.sealedsecrets.bitnami.com/managed = "true"
' -i "$SEALED_SECRET_FILE"

############################################
# 6. Limpeza
############################################
log "Limpando arquivos temporários"

rm -rf "$TMP_DIR"

############################################
# Final
############################################
log "SealedSecret gerado com sucesso!"
log "Arquivo criado: $SEALED_SECRET_FILE"

echo -e "\n✔ Agora você pode versionar APENAS o SealedSecret."
echo "✔ Nenhuma credencial em texto claro foi commitada."
echo "✔ O Secret real será criado automaticamente no cluster."
