# Teste-SRE-Pleno

## 🚀 Introdução
Este projeto utiliza automação total. Para implantar a solução:

1. **Configuração:** Adicione os `Secrets` necessários no seu repositório GitHub (veja a seção de Guia de Instalação).
2. **Deploy:** Realize um `git push` para a branch `main`.
3. **Monitoramento:** O pipeline fará o build, push e deploy via Helm automaticamente no cluster configurado.

## 🏗 Arquitetura
A solução consiste em uma aplicação Node.js containerizada, rodando em um cluster Kubernetes ((**k3s**) gerenciado via **k3d**. A arquitetura inclui suporte para auto-scaling (HPA), monitoramento via Prometheus/Grafana e agregação de logs via ELK Stack.

## ⚖️ Por que k3d/k3s? (Decisão de Infraestrutura)
Diferente de ferramentas como **Kind** (Kubernetes in Docker) ou **Minikube**, a escolha pelo **k3d/k3s** para este projeto baseia-se em:

* **Leveza e Performance:** O k3s é um binário único de < 100MB que consome significativamente menos memória RAM que o Minikube, sendo ideal para ambientes de efêmeros e execuções via Self-hosted Runners.
* **Pronto para Produção:** Enquanto o Kind é focado estritamente em testes locais de CI, o k3s é uma distribuição certificada pela CNCF pronta para uso em produção, o que aproxima este laboratório de um cenário real.
* **Simplicidade Operacional via k3d:** O uso do **k3d** permite subir o cluster k3s rapidamente como containers Docker, eliminando o overhead de gerenciar máquinas virtuais pesadas (Minikube) ou drivers de virtualização complexos, mantendo compatibilidade total com Helm e manifestos padrão.
* **Integração com CI/CD Local:** A arquitetura baseada em Docker facilitou a integração com o **GitHub Self-hosted Runner**, permitindo que o pipeline de CD acesse o API Server do cluster sem a necessidade de expor portas para a internet pública.

## 🛠 Componentes
* **App:** Microserviço em Node.js com suporte a health checks e exportação de métricas.
* **K8S:** Cluster multi-node com Deployment, Service, HPA, PDB e ConfigMaps.
* **CI/CD:** Pipeline automatizado via GitHub Actions para Build e Deploy (Docker Hub + Helm).
* **Observabilidade:** Stack Prometheus e ELK integrados.

## 🛠️ Guia de Instalação

Este projeto foi desenhado para ser totalmente portátil via **Infrastructure as a Template**.

### 1. Configuração de Secrets no GitHub
Para o funcionamento do pipeline, configure os seguintes Segredos em seu repositório (**Settings > Secrets and variables > Actions > New repository secret**):

| Nome do Secret | Descrição |
| :--- | :--- |
| `DOCKERHUB_USERNAME` | Seu nome de usuário no Docker Hub. |
| `DOCKERHUB_TOKEN` | Seu Personal Access Token do Docker Hub. |
| `KUBE_CONFIG_DATA` | O conteúdo do seu arquivo `~/.kube/config` em Base64. |

### 2. Como gerar o Token do Docker Hub
Para maior segurança, utilize um Personal Access Token (PAT) em vez da sua senha:
1. No Docker Hub, vá em **Account Settings > Security > Generate new token**.
2. Gere um token com permissões de `Read & Write`.
3. Use este token no secret `DOCKERHUB_TOKEN`.

### 3. Como exportar o KUBECONFIG
O pipeline utiliza o arquivo de configuração para autenticação externa.

1. No terminal onde o `kubectl` está configurado, execute:
   ```bash
   cat ~/.kube/config | base64 -w 0
2. Copie toda a string resultante.
3. No GitHub, cole este valor no secret `KUBE_CONFIG_DATA`.

### 4. Execução
Qualquer alteração enviada para a branch `main` disparará o workflow `.github/workflows/main.yml`. Este pipeline gerencia:
* **Build e Push:** Envio da imagem para o Docker Hub.
* **Deploy:** Criação do namespace e instalação via Helm no Kubernetes.

## 🐳Tarefa 1: Containerização & Execução - Decisões Técnicas: Dockerfile

### 1. Imagem Base: Node 20-alpine (Active LTS)
* **Escolha:** Foi utilizada a versão `node:20-alpine`.
* **Justificativa de Tamanho:** O Alpine Linux é uma distribuição minimalista reduzindo assim o tempo de download (pull) e o consumo de storage no cluster.
* **Justificativa de Segurança:** Por conter apenas o essencial para a execução do SO, o Alpine possui menos binários e bibliotecas instaladas. Isso reduz drasticamente a "superfície de ataque", diminuindo o número de vulnerabilidades (CVEs) potenciais que ferramentas de scan podem encontrar.

### 2. Otimização de Build: Multi-Stage, Camadas e Cache
* **Aproveitamento de Cache:** A cópia dos arquivos `package.json` e `yarn.lock` foi realizada antes da cópia do restante do código fonte. Como o Docker funciona em camadas (layers), isso garante que, se o código mudar mas as dependências não, o Docker reutilize a camada de instalação (cache), acelerando o tempo de build no pipeline CI/CD.
* **Redução de Camadas:**  O arquivo foi organizado para agrupar comandos RUN, reduzindo o número de camadas intermediárias e o tamanho final da imagem.
* **Multi-Stage Build:** Foi implementada a separação entre o estágio de construção (build) e o de execução (runtime). O ambiente final contém apenas os artefatos compilados, eliminando compiladores e arquivos fonte, o que garante uma imagem mais leve e segura para o ambiente de stagin.

### 3. Gerenciamento de Dependências com Yarn
* **Determinismo com yarn.lock:** A inclusão do arquivo yarn.lock no repositório e no build garante que as versões das bibliotecas sejam exatamente as mesmas em qualquer ambiente (Local, CI/CD e Produção).
* **Flag --frozen-lockfile:** Garante que o Yarn não tente atualizar o arquivo lock durante o build. Se houver discrepância, o build falha, evitando comportamentos inesperados.
* **Flag --production:** Instalamos apenas as dependencies essenciais para rodar o app. Dependências de desenvolvimento (devDependencies), como linters ou frameworks de teste, são ignoradas para reduzir a superfície de ataque e o tamanho da imagem.

### 4. Segurança: Usuário Non-Root com ID Fixo
* **Justificativa do ID 1001:** O uso de um UID/GID fixo acima de 1000 é uma convenção de segurança para garantir que o usuário da aplicação não coincida com usuários do sistema host (como o root, que é ID 0). Além disso, IDs fixos facilitam a gestão de permissões de volumes (RBAC) e políticas de segurança do pod (PodSecurityPolicies) no Kubernetes.
* **Privilégios Mínimos:** Rodar o processo como non-root impede que, em caso de invasão da aplicação, o atacante obtenha privilégios administrativos sobre o kernel do nó hospedeiro.
* **ID 1001 vs appuser:** Em vez de apenas usar um nome como appuser, definir explicitamente o UID 1001 é uma boa prática porque muitos sistemas de arquivos e ferramentas de segurança monitoram o ID numérico.
* **Minimização de Ferramentas:** Ao usar --production, removemos ferramentas de build que poderiam ser exploradas por atacantes dentro do container.

### 5. Execução: Binário Direto vs Gerenciadores
* **Comando:** Foi definido o uso de `CMD ["node", "src/app.js"]`.
* **Sinais do Sistema:** O Node.js foi configurado como o processo principal (PID 1) para que possa receber sinais de terminação do Kubernetes, como o `SIGTERM`. Gerenciadores como `npm` ou `yarn` costumam "encapsular" o processo, impedindo que os sinais cheguem ao Node, o que inviabilizaria um Graceful Shutdown (desligamento limpo).
* **Determinismo:** O uso do parâmetro `--frozen-lockfile` no build garante que as versões das dependências instaladas sejam exatamente as testadas, evitando desvios entre ambientes.

## ☸️ Tarefa 2: Deployment Kubernetes - Decisões Técnicas: Helm & Kubernetes

A arquitetura de deployment foi projetada para garantir alta disponibilidade, escalabilidade automática e isolamento de recursos, seguindo as melhores práticas de infraestrutura como código.

#### 1. Orquestração Declarativa e Reutilização (Helm & Helmfile)
* **Orquestração via Helmfile:** A utilização do Helmfile permite gerenciar o ciclo de vida da aplicação e da stack de observabilidade de forma unificada. Através da definição de dependências (`needs`), garante-se que o monitoramento esteja operacional antes do deploy da aplicação principal.
* **Abstração via Values:** Todos os parâmetros sensíveis e de configuração (portas, caminhos de health check, limites de recursos) foram movidos para o arquivo `values.yaml`. Isso permite que o mesmo chart seja utilizado em diferentes ambientes apenas alterando o arquivo de valores, sem a necessidade de modificar os templates base.
* **Uso de Helpers:** Foi implementado o arquivo `_helpers.tpl` para gerenciar a nomenclatura dos recursos e labels de forma dinâmica. O uso da função `fullname` garante a unicidade dos nomes dentro do cluster, evitando colisões de recursos entre diferentes releases.

### 2. Alta Disponibilidade e Distribuição (Topology Spread Constraints)
* **Estratégia de Espalhamento:** Foi utilizada a funcionalidade de `topologySpreadConstraints` com `maxSkew: 1` e `topologyKey: kubernetes.io/hostname`. 
* **Justificativa:** Diferente de uma afinidade simples, o Spread Constraint garante matematicamente que as réplicas da aplicação sejam distribuídas de forma equilibrada entre os nós disponíveis (`node-01` e `node-02`). O uso de `whenUnsatisfiable: DoNotSchedule` assegura que o cluster não concentre pods em um único nó, mitigando o risco de downtime total em caso de falha de um host físico.

### 3. Resiliência e Ciclo de Vida (PDB e Probes)
* **Pod Disruption Budget (PDB):** Foi implementado um PDB com `minAvailable: 1`. Esta configuração é vital para operações de SRE, pois impede que manutenções automatizadas (como o dreno de um nó) desliguem todas as instâncias da aplicação simultaneamente, garantindo que pelo menos 50% da capacidade esteja sempre ativa.
* **Startup Probe:** Implementada para proteger o processo de inicialização da aplicação, permitindo um tempo de carência maior para o carregamento de dependências antes que as probes de integridade iniciem suas verificações.
* **Health Checks Dinâmicos:** As Probes de `liveness` e `readiness` foram parametrizadas para validar a saúde da aplicação em tempo real. A separação entre liveness (reinício do container) e readiness (entrada no balanceador) garante que o tráfego só seja direcionado para pods que completaram seu processo de inicialização.

### 4. Escalabilidade Automática (HPA v2)
* **Métricas Combinadas:** O Horizontal Pod Autoscaler foi configurado para monitorar tanto CPU quanto Memória simultaneamente.
* **Thresholds de Performance:** Foram definidos gatilhos de **70% para CPU** e **75% para Memória**, conforme requisitos técnicos do projeto. Esta abordagem híbrida protege a aplicação contra gargalos de processamento e vazamentos de memória (memory leaks), garantindo que o cluster escale horizontalmente de forma proativa antes da degradação da latência.

### 5. Estratégia de Deploy (Rolling Update)
* **Zero Downtime:** Foi configurada a estratégia `RollingUpdate` com `maxUnavailable: 0`. Isso garante que o Kubernetes nunca remova uma versão antiga da aplicação sem antes ter uma nova versão saudável e pronta para receber tráfego, eliminando quedas de serviço durante atualizações de versão.
* **Justificativa:** Esta escolha garante que a capacidade total da aplicação (2 réplicas) seja preservada durante todo o processo de atualização. O Kubernetes é forçado a instanciar um novo Pod saudável antes de iniciar o encerramento de qualquer instância da versão anterior, evitando gargalos de processamento durante janelas de deploy.

## 🚀 Tarefa 4: Pipeline CI/CD - Decisões Técnicas: CI/CD (GitHub Actions)

A automação do ciclo de vida da aplicação foi implementada via GitHub Actions, focando em garantir a integridade do código e a consistência dos deploys.

### 1. Estratégia de Runner: GitHub Self-hosted
* **Conectividade Local:** Como o cluster Kubernetes (k3d) está rodando localmente, foi utilizado um runner self-hosted para permitir que o pipeline alcance o Control Plane do cluster sem a necessidade de expor APIs para a internet pública (via Ngrok ou túneis), mantendo a comunicação restrita ao ambiente interno.
* **Segurança de Rede:** O uso do runner local elimina vetores de ataque externos, mantendo toda a comunicação de deploy restrita ao ambiente controlado.
* **Eficiência de Cache:** O runner compartilha o daemon do Docker da máquina host, permitindo o reaproveitamento imediato de cache de camadas (layers), o que reduz drasticamente o tempo de build das imagens em comparação a runners efêmeros na nuvem.
* **Persistência:** Diferente de ambientes de laboratório temporários, o runner local garante a persistência das configurações de context do kubectl e do Helm, tornando o ciclo de desenvolvimento e deploy mais ágil e previsível.

### 2. Pipeline de Integração Contínua (CI)
* **Uso de `uses` para Tarefas Utilitárias:** Foi adotado o padrão `uses` para etapas como `actions/checkout` e `docker/setup-buildx-action`. Esta escolha justifica-se pela confiabilidade de Actions oficiais que simplificam tarefas complexas de autenticação e setup.
* **Build Multi-arquitetura:** O pipeline realiza o build da imagem Docker utilizando o contexto do Dockerfile multi-stage, garantindo que apenas imagens que passaram nos testes de build avancem para a etapa de push.
* **Versionamento de Imagem:** Foi adotada a estratégia de versionamento via tags numéricas incrementais baseadas no `${{ github.run_number }}`. Esta abordagem garante que cada build gere uma versão única, legível e sequencial (ex: `1.10`, `1.11`), facilitando o rastreio de deploys, a gestão de imagens no Docker Hub e o rollbacks.

### 3. Pipeline de Entrega Contínua (CD)
* **Helm Lint:** Antes de qualquer alteração no cluster, o pipeline executa o `helm lint` para validar a sintaxe e as boas práticas dos templates do Chart, evitando falhas de deploy por erros de indentação ou lógica de template.
* **Uso de `run` para Deploys Críticos:** Para as etapas de deploy (Helmfile), foi priorizado o uso de comandos `run`. Esta decisão técnica visa o controle total sobre a infraestrutura de CI/CD, permitindo maior visibilidade de debug e evitando a dependência de "caixas-pretas" de terceiros no caminho crítico de produção.
* **Instalação via Script de Bootstrap:** A instalação do Helmfile no Runner foi realizada através de um script de shell customizado. Esta prática permite o versionamento da lógica de instalação, garante que a mesma versão do binário seja utilizada em qualquer ambiente e facilita a testabilidade local do processo de setup.
* **Orquestração Declarativa:** Foi utilizado o **Helmfile** para gerenciar a aplicação e suas dependências de forma declarativa, permitindo aplicar toda a stack com um único comando `helmfile apply`.
* **Idempotência e Sincronização:** O Helmfile garante que o cluster reflita exatamente o estado definido nos arquivos de configuração, tratando atualizações e instalações de forma nativa e segura.
* **Abstração de Ambientes:** O uso do Helmfile facilita a separação de contextos, permitindo que o mesmo pipeline gerencie diferentes estados do cluster de forma organizada.
* **Imutabilidade de Deploy:** O pipeline injeta a tag específica do build diretamente no manifesto do Kubernetes via Helm durante o deploy. Isso assegura que o cluster execute exatamente a versão de artefato gerada no ciclo de CI, eliminando a ambiguidade de versões.

### 4. Segurança e Portabilidade (Secrets Management)
* **Kubeconfig as a Secret:** A autenticação com o cluster Kubernetes é realizada através da variável de ambiente `KUBECONFIG` armazenada nos GitHub Secrets. 
* **Justificativa:** Esta abordagem desacopla o pipeline da infraestrutura subjacente, permitindo que a estratégia de deploy seja reutilizada em qualquer provedor de nuvem ou ambiente on-premises sem alterações no código. Além disso, garante que credenciais sensíveis nunca fiquem expostas no repositório.

### 5. Gestão de Imagens e Registro Externo (Docker Hub)
* **External Registry:** Foi adotado o Docker Hub como registro oficial de imagens da solução, em detrimento do registro efêmero local. 
* **Justificativa:** O uso de um registro externo garante a persistência dos artefatos de build independentemente da vida útil do cluster de teste. Isso facilita auditorias de segurança externas e permite que a imagem seja testada em múltiplos ambientes (Hybrid Cloud) sem necessidade de re-build.
* **Autenticação Segura:** O acesso ao Docker Hub é realizado via Personal Access Tokens (PAT) injetados como segredos no GitHub Actions, evitando a exposição de senhas globais da conta.

### 6. Portabilidade e Abstração do Pipeline
* **Generic Workflow:** O pipeline foi projetado para ser agnóstico. Todas as referências a nomes de registro, tags, variáveis, secrets e contextos de infraestrutura foram movidas para GitHub Secrets.
* **Justificativa:** Isso permite que o projeto seja replicado por qualquer outro profissional apenas configurando seus próprios Segredos (Secrets), sem a necessidade de alterar uma única linha de código nos arquivos YAML ou Helm. Esta abordagem segue o princípio de "Infrastructure as a Template".