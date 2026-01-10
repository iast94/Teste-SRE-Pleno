#!/usr/bin/env bash

set -euo pipefail

############################################
# Variáveis Globais
############################################
SEALED_SECRETS_NS="kube-system"
SEALED_SECRETS_RELEASE="sealed-secrets-controller"
SEALED_SECRETS_VERSION="2.15.0"

OBS_NAMESPACE="observability"

# Diretório raiz do repositório
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BIN_DIR="$ROOT_DIR/.bin"
YQ_BIN="$BIN_DIR/yq"
TMP_DIR="$ROOT_DIR/.tmp-secrets"

SEALED_SECRET_FILE="$ROOT_DIR/helm/grafana/secrets/grafana-admin-sealed.yaml"
ELASTIC_SEALED_SECRET_FILE="$ROOT_DIR/helm/elk/secrets/elasticsearch-admin-sealed.yaml"
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

command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl não encontrado"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ helm não encontrado"; exit 1; }

############################################
# Garantir diretórios
############################################
mkdir -p "$BIN_DIR"
mkdir -p "$TMP_DIR"
mkdir -p "$(dirname "$SEALED_SECRET_FILE")"
mkdir -p "$(dirname "$ELASTIC_SEALED_SECRET_FILE")"

############################################
# Garantir yq
############################################
if [ ! -x "$YQ_BIN" ]; then
  log "Instalando yq localmente"
  curl -fsSL \
    https://github.com/mikefarah/yq/releases/download/v4.43.1/yq_linux_amd64 \
    -o "$YQ_BIN"
  chmod +x "$YQ_BIN"
else
  log "yq já disponível"
fi

############################################
# Instalar kubeseal
############################################
if ! command -v kubeseal >/dev/null 2>&1; then
  log "Instalando kubeseal"

  OS="$(uname | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"

  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "❌ Arquitetura não suportada: $ARCH"; exit 1 ;;
  esac

  curl -fsSL -o kubeseal.tar.gz \
    "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${SEALED_SECRETS_VERSION}/kubeseal-${SEALED_SECRETS_VERSION}-${OS}-${ARCH}.tar.gz"

  tar -xzf kubeseal.tar.gz kubeseal
  sudo mv kubeseal /usr/local/bin/
  rm -f kubeseal.tar.gz

  log "kubeseal instalado com sucesso"
else
  log "kubeseal já instalado"
fi

############################################
# Instalar Sealed Secrets Controller
############################################
log "Garantindo Sealed Secrets Controller"

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null 2>&1 || true
helm repo update >/dev/null

if helm list -n "$SEALED_SECRETS_NS" -q | grep -q sealed-secrets; then
  log "Sealed Secrets já instalado"
else
  helm install "$SEALED_SECRETS_RELEASE" sealed-secrets/sealed-secrets \
    --namespace "$SEALED_SECRETS_NS" \
    --version "$SEALED_SECRETS_VERSION"
fi

log "Aguardando controller ficar pronto..."
kubectl rollout status deployment/sealed-secrets-controller -n "$SEALED_SECRETS_NS"

############################################
# Garantir namespace observability
############################################
log "Garantindo namespace ${OBS_NAMESPACE}"
kubectl get namespace "$OBS_NAMESPACE" >/dev/null 2>&1 || \
  kubectl create namespace "$OBS_NAMESPACE"

# ------------------------
# Grafana
# ------------------------
############################################
# Configurações
############################################
# ⚠️ Convenção fixa (NÃO alterar)
SECRET_NAME="grafana-admin-credentials"     # Secret real
SEALED_SECRET_NAME="grafana-admin-sealed"   # SealedSecret (controle)

PLAIN_SECRET_FILE="$TMP_DIR/grafana-secret.yaml"

############################################
# Criar Secret temporário (plain)
############################################
log "Gerando Secret temporário para criptografia"

read -rp "Grafana admin user: " GRAFANA_USER
while true; do
  read -srp "Grafana admin password (mín. 8 caracteres): " GRAFANA_PASSWORD
  echo ""

  if [[ ${#GRAFANA_PASSWORD} -lt 8 ]]; then
    echo "❌ Senha muito curta. Informe pelo menos 8 caracteres."
    continue
  fi

  break
done

kubectl create secret generic "$SECRET_NAME" \
  --from-literal=admin-user="$GRAFANA_USER" \
  --from-literal=admin-password="$GRAFANA_PASSWORD" \
  --namespace "$OBS_NAMESPACE" \
  --dry-run=client \
  -o yaml > "$PLAIN_SECRET_FILE"

############################################
# Gerar SealedSecret
############################################
log "Gerando SealedSecret"

kubeseal \
  --format yaml \
  --controller-name sealed-secrets-controller \
  --controller-namespace "$SEALED_SECRETS_NS" \
  --name "$SEALED_SECRET_NAME" \
  --namespace "$OBS_NAMESPACE" \
  < "$PLAIN_SECRET_FILE" > "$SEALED_SECRET_FILE"

############################################
# Corrigir template (NOME + TYPE + ANNOTATION)
############################################
log "Ajustando template do SealedSecret"

"$YQ_BIN" eval "
  .spec.template.metadata.name = \"$SECRET_NAME\" |
  .spec.template.metadata.namespace = \"$OBS_NAMESPACE\" |
  .spec.template.metadata.annotations.\"sealedsecrets.bitnami.com/managed\" = \"true\" |
  .spec.template.type = \"Opaque\"
" -i "$SEALED_SECRET_FILE"

############################################
# Final
############################################
log "SealedSecret gerado com sucesso!"
log "Arquivo criado: $SEALED_SECRET_FILE"

echo -e "\n✔ Resultado final garantido:"
echo "  - SealedSecret : $SEALED_SECRET_NAME"
echo "  - Secret real  : $SECRET_NAME"
echo "  - type         : Opaque"
echo "  - managed      : true"
echo "✔ Pronto para aplicar no cluster com kubectl ou Helmfile"

# ------------------------
# Elasticsearch
# ------------------------
############################################
# Configurações
############################################
ELASTIC_SECRET_NAME="elasticsearch-master-credentials"
ELASTIC_SEALED_SECRET_NAME="elasticsearch-master-credentials"
ELASTIC_PLAIN_SECRET_FILE="$TMP_DIR/elasticsearch-secret.yaml"

############################################
# Criar Secret temporário (plain)
############################################
log "Gerando Secret temporário do Elasticsearch"

read -rp "Elasticsearch username [elastic]: " ELASTIC_USERNAME
ELASTIC_USERNAME=${ELASTIC_USERNAME:-elastic}

while true; do
  read -srp "Elastic password (mín. 8 caracteres): " ELASTIC_PASSWORD
  echo ""

  if [[ ${#ELASTIC_PASSWORD} -lt 8 ]]; then
    echo "❌ Senha muito curta. Informe pelo menos 8 caracteres."
    continue
  fi

  break
done

kubectl create secret generic "$ELASTIC_SECRET_NAME" \
  --from-literal=username="$ELASTIC_USERNAME" \
  --from-literal=password="$ELASTIC_PASSWORD" \
  --namespace "$OBS_NAMESPACE" \
  --dry-run=client \
  -o yaml > "$ELASTIC_PLAIN_SECRET_FILE"

############################################
# Gerar SealedSecret
############################################
log "Gerando SealedSecret do Elasticsearch"

kubeseal \
  --format yaml \
  --controller-name sealed-secrets-controller \
  --controller-namespace "$SEALED_SECRETS_NS" \
  --name "$ELASTIC_SEALED_SECRET_NAME" \
  --namespace "$OBS_NAMESPACE" \
  < "$ELASTIC_PLAIN_SECRET_FILE" > "$ELASTIC_SEALED_SECRET_FILE"

############################################
# Ajustar template
############################################
log "Ajustando template do SealedSecret"

"$YQ_BIN" eval "
  .spec.template.metadata.name = \"$ELASTIC_SECRET_NAME\" |
  .spec.template.metadata.namespace = \"$OBS_NAMESPACE\" |
  .spec.template.metadata.annotations.\"sealedsecrets.bitnami.com/managed\" = \"true\" |
  .spec.template.type = \"Opaque\"
" -i "$ELASTIC_SEALED_SECRET_FILE"

############################################
# Final
############################################
log "SealedSecret do Elasticsearch gerado com sucesso!"
log "Arquivo criado: $ELASTIC_SEALED_SECRET_FILE"

echo -e "\n✔ Resultado final garantido:"
echo "  - SealedSecret : $ELASTIC_SEALED_SECRET_NAME"
echo "  - Secret real  : $ELASTIC_SECRET_NAME"
echo "  - username     : $ELASTIC_USERNAME"
echo "  - type         : Opaque"
echo "  - managed      : true"
echo "✔ Pronto para aplicar no cluster com kubectl ou Helmfile"

############################################
# Limpeza
############################################
log "Limpando arquivos temporários"
rm -rf "$TMP_DIR"