# FCG - Orquestração

Repositório central de infraestrutura da plataforma **Fiap Cloud Games**. Contém a configuração de containers Docker e os manifestos para deploy no Kubernetes.

## Arquitetura

A plataforma é composta por 4 microsserviços independentes que se comunicam de forma assíncrona via RabbitMQ:

| Serviço | Repositório | Responsabilidade |
|---|---|---|
| UsersAPI | [fcg-users-api](https://github.com/gustavoaa-dev/fcg-users-api) | Cadastro e autenticação de usuários |
| CatalogAPI | [fcg-catalog-api](https://github.com/gustavoaa-dev/fcg-catalog-api) | Catálogo de jogos e biblioteca |
| PaymentsAPI | [fcg-payments-api](https://github.com/gustavoaa-dev/fcg-payments-api) | Processamento de pagamentos |
| NotificationsAPI | [fcg-notifications-api](https://github.com/gustavoaa-dev/fcg-notifications-api) | Envio de notificações |

Todo o acesso externo passa pelo **API Gateway (Kong)** em `http://localhost:8000`: as APIs **não** são publicadas diretamente. Detalhes em [API Gateway (Kong)](#api-gateway-kong).

### Fluxo de eventos

```
UsersAPI ──UserCreatedEvent──→ NotificationsAPI (boas-vindas)

CatalogAPI ──OrderPlacedEvent──→ PaymentsAPI (processa pagamento)
                                      │
                              PaymentProcessedEvent
                                      │
                    ┌─────────────────┴─────────────────┐
                    ↓                                   ↓
            CatalogAPI (adiciona à biblioteca)   NotificationsAPI (confirmação)
```

## Como executar com Docker

### Pré-requisitos

- Docker
- Docker Compose

### Subir a aplicação

```bash
# Clonar este repositório e os 4 microsserviços no mesmo diretório pai:
# .
# ├── fcg-orchestration/
# ├── fcg-users-api/
# ├── fcg-catalog-api/
# ├── fcg-payments-api/
# └── fcg-notifications-api/

cd fcg-orchestration
docker-compose up -d
```

### Serviços e portas

As APIs **não são publicadas diretamente**: o acesso é feito pelo gateway Kong em `http://localhost:8000` (ver [API Gateway (Kong)](#api-gateway-kong)). No Compose sobem apenas a infraestrutura de desenvolvimento e os containers das APIs dentro da rede interna `fcg-network`; o gateway Kong faz parte do [deploy no Kubernetes](#como-fazer-deploy-no-kubernetes).

| Serviço | Porta | Observação |
|---|---|---|
| Kong (gateway) | `http://localhost:8000` | Único ponto de entrada das APIs (Kubernetes) |
| RabbitMQ Management | `http://localhost:15672` (guest/guest) | Infraestrutura de desenvolvimento |
| SQL Server | `localhost:1433` (sa/FCG@Password123) | Infraestrutura de desenvolvimento |

> As portas `5001`–`5004` das APIs não existem mais: os containers das APIs não publicam porta alguma no host.

### Parar a aplicação

```bash
docker-compose down
```

## Como fazer deploy no Kubernetes

### Pré-requisitos

- Cluster Kubernetes (Docker Desktop, Kind ou Minikube)
- kubectl configurado

### Build das imagens

```bash
# Em cada diretório de microsserviço:
docker build -t fcg-users-api .
docker build -t fcg-catalog-api .
docker build -t fcg-payments-api .
docker build -t fcg-notifications-api .
```

### Aplicar os manifestos

A **ordem importa**: primeiro a infraestrutura e as APIs, depois o gateway Kong.

```bash
# 1) Infraestrutura (RabbitMQ, SQL Server) e APIs
kubectl apply -f k8s/

# 2) Gateway Kong — depende do Secret users-api-secret, criado no passo 1
kubectl apply -f k8s/kong/kong-deployment.yaml
```

> `kubectl apply -f k8s/` não é recursivo: aplica apenas os manifestos que estão na raiz de `k8s/`. O subdiretório `k8s/kong/` é aplicado em separado de propósito, porque o pod do Kong só fica pronto depois de o script abaixo criar o `Secret kong-declarative-config`.

### Configurar o gateway (segredo JWT)

O Kong é **DB-less**: a configuração declarativa é montada a partir de um `Secret` do cluster e **nenhum segredo é versionado**. O passo obrigatório depois de aplicar os manifestos é:

```powershell
# Lê o segredo users-api-secret/jwt-secret-key, renderiza o template,
# cria/atualiza o Secret kong-declarative-config e reinicia o Kong.
powershell -File scripts/deploy-kong.ps1
```

> A invocação suportada é `powershell -File scripts/deploy-kong.ps1`. Em quem tiver PowerShell 7, a alternativa é `pwsh -File scripts/deploy-kong.ps1` — o script é agnóstico de versão.

**Sem esse restart a mudança de configuração não vale**: em modo DB-less o Kong carrega a config declarativa na inicialização do pod.

### Verificar o deploy

```bash
kubectl get pods
kubectl get services
kubectl get svc users-api catalog-api kong
```

Todos os pods devem estar com status `Running` — o do Kong só fica `Ready` depois de o script acima criar o `Secret kong-declarative-config`.

Confirme também que as APIs ficaram fechadas: `users-api` e `catalog-api` aparecem como `ClusterIP` e **não existe mais `NodePort`** (as antigas `30001`/`30002` não respondem).

### Acessar as APIs

Tudo passa pelo gateway: **`http://localhost:8000`**.

```bash
# Sem token: bloqueado pelo próprio gateway
curl -s -o /dev/null -w "sem-token=%{http_code}\n" http://localhost:8000/api/jogos

# Login + chamada autenticada no MESMO bloco (o token não é reaproveitado entre blocos;
# reautentique sempre que for testar). Ajuste e-mail/senha para um usuário cadastrado.
TOKEN=$(curl -s -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"usuario@fcg.com","senha":"Senha@12345"}' | jq -r '.token')

curl -s -o /dev/null -w "com-token=%{http_code}\n" http://localhost:8000/api/jogos \
  -H "Authorization: Bearer $TOKEN"
```

Esperado: `sem-token=401` e `com-token=200`. O login (`POST /api/auth/login`, rota anônima) responde `{ "token": "..." }`.

### Depurar (port-forward)

O gateway é a única entrada suportada; os comandos abaixo servem **apenas para depuração local**:

```bash
# Bypass do gateway para inspecionar uma API direto no pod (só na sua máquina)
kubectl port-forward svc/users-api 8080:80

# Admin API do Kong — a porta 8001 NÃO é publicada, só existe via port-forward
kubectl port-forward deploy/kong 8001:8001
# com o forward ativo, abra http://localhost:8001/status (ou /routes, /services, /plugins)
```

### Remover o deploy

```bash
kubectl delete -f k8s/kong/kong-deployment.yaml
kubectl delete -f k8s/
# o Secret do Kong é criado pelo script, não pelos manifestos:
kubectl delete secret kong-declarative-config
```

## API Gateway (Kong)

O [Kong 3.10](https://konghq.com/) em modo **DB-less** é o ponto de entrada único das APIs: `http://localhost:8000`. Nenhuma API é acessível diretamente de fora do cluster.

### Como está montado

| Componente | Onde vive | Papel |
|---|---|---|
| Config declarativa | `k8s/kong/kong.yml.template` | Serviços, rotas, plugin `jwt` e consumer — versionado, com o marcador `${JWT_SECRET}` no lugar do segredo |
| Deployment + Service | `k8s/kong/kong-deployment.yaml` | Kong `3.10` com `KONG_DATABASE=off`, proxy em `0.0.0.0:8000`; Service `LoadBalancer` publicando **apenas** a porta `8000` |
| Config renderizada | `Secret kong-declarative-config` (cluster) | `kong.yml` final, montado somente leitura em `/kong/declarative/kong.yml` |
| Script de deploy | `scripts/deploy-kong.ps1` | Renderiza o template, aplica o `Secret` e reinicia o Kong |

A Admin API (`8001`) **não é publicada**: só é acessível por `kubectl port-forward deploy/kong 8001:8001` (ver [Depurar (port-forward)](#depurar-port-forward)).

### Como o segredo JWT é injetado

O `kong.yml` final **nunca** vai para o git — o repositório guarda apenas o template com `${JWT_SECRET}`. O fluxo é:

1. `scripts/deploy-kong.ps1` lê o segredo que já existe no cluster (`Secret users-api-secret`, chave `jwt-secret-key` — o mesmo usado pelas APIs);
2. substitui `${JWT_SECRET}` no template e grava o resultado num arquivo temporário em **UTF-8 sem BOM** (com BOM, o Kong pode falhar no parse da config declarativa);
3. cria/atualiza o `Secret kong-declarative-config` (`kubectl create secret generic ... --dry-run=client -o yaml | kubectl apply -f -`);
4. reinicia o Deployment do Kong e apaga o arquivo temporário (que contém o segredo em claro).

Invocação suportada: **`powershell -File scripts/deploy-kong.ps1`** (alternativa em quem tem PowerShell 7: `pwsh -File scripts/deploy-kong.ps1`). Como o Kong é DB-less, **a configuração só passa a valer depois do restart feito pelo script**.

### Rotas expostas

| Rota | Métodos | Autenticação | Upstream |
|---|---|---|---|
| `/api/auth` (ex.: `POST /api/auth/login`) | `POST` | **Anônima** | `http://users-api:80` |
| `/api/usuarios` (cadastro) | `POST` | **Anônima** | `http://users-api:80` |
| `/api/usuarios` | `GET`, `PUT`, `PATCH`, `DELETE` | **JWT obrigatório** | `http://users-api:80` |
| `/api/jogos` (e subrotas) | qualquer | **JWT obrigatório** | `http://catalog-api:80` |
| `/api/biblioteca` (e subrotas) | qualquer | **JWT obrigatório** | `http://catalog-api:80` |

Plugin `jwt` aplicado por rota, validado **no próprio gateway**:

- algoritmo **HS256**, com o consumer `fcg-client`;
- o token é identificado por `key_claim_name: iss`, e o valor precisa ser `FCG.UsersAPI` (o issuer emitido pela UsersAPI);
- `claims_to_verify: exp` — token expirado é rejeitado;
- o token é lido **somente** do header `Authorization: Bearer <token>` (`uri_param_names` e `cookie_names` vazios);
- requisição sem token ou com token inválido/expirado recebe **`401` do próprio Kong**, sem chegar à API. Regras de negócio e de perfil (ex.: papéis exigidos por um endpoint) continuam valendo dentro de cada API.

Os upstreams são internos: `users-api` e `catalog-api` são `ClusterIP` na porta `80` (`targetPort 8080`), alcançáveis apenas de dentro do cluster. Não existe mais `NodePort`: `http://localhost:30001` não responde.

### Aviso: não definir porta HTTPS nos serviços

As APIs chamam `UseHttpsRedirection()`, e o Kong fala **HTTP puro** com os upstreams (`http://users-api:80`, `http://catalog-api:80`).

- **Sem** porta HTTPS definida, o `UseHttpsRedirection()` apenas registra um aviso no log e continua servindo HTTP — este é o cenário esperado.
- **Com** porta HTTPS definida (`ASPNETCORE_HTTPS_PORTS`, ou `ASPNETCORE_URLS` contendo `https://`), o middleware passa a responder **`307 Temporary Redirect`** para `https`. O Kong não segue esse redirect e o **roteamento quebra** (o cliente recebe `307` e o upstream nunca é alcançado).

Portanto: **não defina porta HTTPS nos Deployments/ConfigMaps das APIs, nem publique uma porta HTTPS nos Services.**

### Depurar o gateway

```bash
# Admin API do Kong (a 8001 não é publicada)
kubectl port-forward deploy/kong 8001:8001
# depois abra http://localhost:8001/status | /routes | /services | /plugins | /consumers

# Logs do Kong (mostram o 401/200 de cada requisição)
kubectl logs deploy/kong -f
```

## Estrutura de arquivos

```
fcg-orchestration/
├── docker-compose.yml
├── k8s/
│   ├── rabbitmq-deployment.yaml
│   ├── sqlserver-deployment.yaml
│   ├── users-api-configmap.yaml
│   ├── users-api-secret.yaml
│   ├── users-api-deployment.yaml
│   ├── catalog-api-configmap.yaml
│   ├── catalog-api-secret.yaml
│   ├── catalog-api-deployment.yaml
│   ├── payments-api-configmap.yaml
│   ├── payments-api-secret.yaml
│   ├── payments-api-deployment.yaml
│   ├── notifications-api-configmap.yaml
│   ├── notifications-api-deployment.yaml
│   └── kong/
│       ├── kong-deployment.yaml      # Deployment + Service (proxy 8000, Admin 8001 interna)
│       └── kong.yml.template         # config declarativa com o marcador ${JWT_SECRET}
├── scripts/
│   └── deploy-kong.ps1               # renderiza o segredo e reinicia o Kong
└── README.md
```
