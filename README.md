# Teste-Pr-tico-SRE-Pleno
## 🐳 Decisões Técnicas: Dockerfile

A estratégia de containerização foi focada em segurança, otimização de camadas e confiabilidade para atender aos requisitos de SRE Pleno.

### 1. Imagem Base: Node 20-alpine (Active LTS)
* **Escolha:** Foi utilizada a versão `node:20-alpine`.
* **Justificativa de Tamanho:** O Alpine Linux é uma distribuição minimalista reduzindo assim o tempo de download (pull) e o consumo de storage no cluster.
* **Justificativa de Segurança:** Por conter apenas o essencial para a execução do SO, o Alpine possui menos binários e bibliotecas instaladas. Isso reduz drasticamente a "superfície de ataque", diminuindo o número de vulnerabilidades (CVEs) potenciais que ferramentas de scan podem encontrar.

### 2. Otimização de Build: Multi-Stage e Cache
* **Aproveitamento de Cache:** A cópia dos arquivos `package.json` e `yarn.lock` foi realizada antes da cópia do restante do código fonte. Como o Docker funciona em camadas (layers), isso garante que, se o código mudar mas as dependências não, o Docker reutilize a camada de instalação (cache), acelerando o tempo de build no pipeline CI/CD.
* **Multi-Stage Build:** Foi implementada a separação entre o estágio de construção (build) e o de execução (runtime). O ambiente final contém apenas os artefatos compilados, eliminando compiladores e arquivos fonte, o que garante uma imagem mais leve e segura para o ambiente de stagin.

### 3. Segurança: Usuário Non-Root com ID Fixo
* **Implementação:** Foi criado um grupo e usuário específico (`appuser`) com ID fixo `1001`.
* **Justificativa do ID 1001:** O uso de um UID/GID fixo acima de 1000 é uma convenção de segurança para garantir que o usuário da aplicação não coincida com usuários do sistema host (como o root, que é ID 0). Além disso, IDs fixos facilitam a gestão de permissões de volumes (RBAC) e políticas de segurança do pod (PodSecurityPolicies) no Kubernetes.
* **Privilégios Mínimos:** Rodar o processo como non-root impede que, em caso de invasão da aplicação, o atacante obtenha privilégios administrativos sobre o kernel do nó hospedeiro.

### 4. Execução: Binário Direto vs Gerenciadores
* **Comando:** Foi definido o uso de `CMD ["node", "dist/main.js"]`.
* **Sinais do Sistema:** O Node.js foi configurado como o processo principal (PID 1) para que possa receber sinais de terminação do Kubernetes, como o `SIGTERM`. Gerenciadores como `npm` ou `yarn` costumam "encapsular" o processo, impedindo que os sinais cheguem ao Node, o que inviabilizaria um Graceful Shutdown (desligamento limpo).
* **Determinismo:** O uso do parâmetro `--frozen-lockfile` no build garante que as versões das dependências instaladas sejam exatamente as testadas, evitando desvios entre ambientes.