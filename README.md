# Teste-Pr-tico-SRE-Pleno
## 🐳 Decisões Técnicas: Dockerfile

[cite_start]A estratégia de containerização foi focada em segurança, otimização de camadas e confiabilidade para atender aos requisitos de SRE Pleno[cite: 5, 26, 27].

### 1. Imagem Base: Node 20-alpine (Active LTS)
* [cite_start]**Escolha:** Foi utilizada a versão `node:20-alpine`[cite: 39, 42].
* **Justificativa de Tamanho:** O Alpine Linux é uma distribuição minimalista baseada em musl libc e busybox. [cite_start]Enquanto uma imagem base Debian pode superar 600MB, o Alpine mantém a imagem próxima de 100MB, reduzindo o tempo de download (pull) e o consumo de storage no cluster[cite: 10, 35].
* **Justificativa de Segurança:** Por conter apenas o essencial para a execução do SO, o Alpine possui menos binários e bibliotecas instaladas. [cite_start]Isso reduz drasticamente a "superfície de ataque", diminuindo o número de vulnerabilidades (CVEs) potenciais que ferramentas de scan podem encontrar[cite: 35, 42].

### 2. Otimização de Build: Multi-Stage e Cache
* **Aproveitamento de Cache:** A cópia dos arquivos `package.json` e `yarn.lock` foi realizada antes da cópia do restante do código fonte. [cite_start]Como o Docker funciona em camadas (layers), isso garante que, se o código mudar mas as dependências não, o Docker reutilize a camada de instalação (cache), acelerando o tempo de build no pipeline CI/CD[cite: 13, 35].
* [cite_start]**Multi-Stage Build:** Foi implementada a separação entre o estágio de construção (build) e o de execução (runtime)[cite: 10, 27]. [cite_start]O ambiente final contém apenas os artefatos compilados, eliminando compiladores e arquivos fonte, o que garante uma imagem mais leve e segura para o ambiente de staging[cite: 30, 35].

### 3. Segurança: Usuário Non-Root com ID Fixo
* [cite_start]**Implementação:** Foi criado um grupo e usuário específico (`appuser`) com ID fixo `1001`[cite: 42].
* **Justificativa do ID 1001:** O uso de um UID/GID fixo acima de 1000 é uma convenção de segurança para garantir que o usuário da aplicação não coincida com usuários do sistema host (como o root, que é ID 0). [cite_start]Além disso, IDs fixos facilitam a gestão de permissões de volumes (RBAC) e políticas de segurança do pod (PodSecurityPolicies) no Kubernetes[cite: 35, 42].
* [cite_start]**Privilégios Mínimos:** Rodar o processo como non-root impede que, em caso de invasão da aplicação, o atacante obtenha privilégios administrativos sobre o kernel do nó hospedeiro[cite: 35, 42].

### 4. Execução: Binário Direto vs Gerenciadores
* **Comando:** Foi definido o uso de `CMD ["node", "dist/main.js"]`.
* **Sinais do Sistema:** O Node.js foi configurado como o processo principal (PID 1) para que possa receber sinais de terminação do Kubernetes, como o `SIGTERM`. [cite_start]Gerenciadores como `npm` ou `yarn` costumam "encapsular" o processo, impedindo que os sinais cheguem ao Node, o que inviabilizaria um Graceful Shutdown (desligamento limpo)[cite: 42, 53].
* [cite_start]**Determinismo:** O uso do parâmetro `--frozen-lockfile` no build garante que as versões das dependências instaladas sejam exatamente as testadas, evitando desvios entre ambientes[cite: 34, 35].