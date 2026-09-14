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

Todo o acesso externo passa pelo **API Gateway (Kong)** — em `http://localhost:8000` quando o `EXTERNAL-IP` do `svc/kong` for `localhost` ou com o `port-forward` ativo, e em `http://<EXTERNAL-IP>:8000` quando o cluster entregar um IP de rede (ver [exposição por cluster](#expor-o-gateway-porta-de-entrada)): as APIs **não** são publicadas diretamente. Detalhes em [API Gateway (Kong)](#api-gateway-kong).

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

As APIs **não são publicadas diretamente**: o acesso é feito pelo gateway Kong — `http://localhost:8000` com o `EXTERNAL-IP` do `svc/kong` em `localhost` ou com o `port-forward` ativo (ver [exposição por cluster](#expor-o-gateway-porta-de-entrada) e [API Gateway (Kong)](#api-gateway-kong)). No Compose sobem apenas a infraestrutura de desenvolvimento e os containers das APIs dentro da rede interna `fcg-network`; o gateway Kong faz parte do [deploy no Kubernetes](#como-fazer-deploy-no-kubernetes).

| Serviço | Porta | Observação |
|---|---|---|
| Kong (gateway) | `http://localhost:8000` | Único ponto de entrada das APIs (Kubernetes; ver [exposição por cluster](#expor-o-gateway-porta-de-entrada)) |
| RabbitMQ Management | `http://localhost:15672` (guest/guest) | Infraestrutura de desenvolvimento |
| SQL Server | `localhost:1433` (sa/FCG@Password123) | Infraestrutura de desenvolvimento |

> As portas `5001`–`5004` das APIs não existem mais: os containers das APIs não publicam porta alguma no host.

### Parar a aplicação

```bash
docker-compose down
```

## Como fazer deploy no Kubernetes

### Pré-requisitos

- Cluster Kubernetes — a decisão do projeto é **Docker Desktop**; Kind e Minikube também funcionam, com as ressalvas de [exposição do gateway](#expor-o-gateway-porta-de-entrada)
- kubectl configurado
- Para executar os exemplos de chamada HTTP deste README, escolha **uma** das duas variantes equivalentes — as duas fazem o mesmo fluxo `cadastro → login → rota protegida`:
  - **PowerShell nativo** — usa `Invoke-RestMethod`, sem dependências extras; roda em qualquer Windows, inclusive **Windows PowerShell 5.1** (é a variante usada neste projeto);
  - **bash** — exige **Git Bash** ou **WSL**, com **`curl`** e **`jq`** instalados (o `jq` é o que extrai o token do JSON).

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
# cria/atualiza o Secret kong-declarative-config, reinicia o Kong e espera o rollout.
powershell -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1
```

> A invocação suportada é `powershell -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1`. O `-ExecutionPolicy Bypass` é necessário porque o Windows client vem com a política de execução `Restricted`, que bloqueia arquivos `.ps1` (o `-File` puro falha com "a execução de scripts foi desabilitada neste sistema"). Em quem tiver PowerShell 7, a alternativa equivalente é `pwsh -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1` — o script é agnóstico de versão.

**Sem esse restart a mudança de configuração não vale**: em modo DB-less o Kong carrega a config declarativa na inicialização do pod. Por isso o script não termina no `rollout restart`: ele espera o `kubectl rollout status deployment/kong` e **falha** se o pod não ficar pronto em 120s (config inválida em DB-less mata o container no boot e vira `CrashLoopBackOff`, sem que o restart acuse erro).

### Expor o gateway (porta de entrada)

O Service do Kong é `LoadBalancer`, e **nem todo cluster entrega um `EXTERNAL-IP` local**: o Docker Desktop, inclusive, ora publica `localhost`, ora entrega um **IP de rede** (na verificação real desta máquina ele devolveu `172.18.0.5`). Confira sempre o que o seu cluster imprimiu:

```bash
kubectl get svc kong
```

| Cluster | `EXTERNAL-IP` típico do `svc/kong` | Como chegar ao gateway |
|---|---|---|
| **Docker Desktop** (decisão do projeto) | `localhost` **ou um IP de rede** (ex.: `172.18.0.5`) | `localhost` → direto em `http://localhost:8000`; **IP de rede** → `http://<EXTERNAL-IP>:8000` (se o host não alcançar esse IP, use o `port-forward` abaixo e `http://localhost:8000`) |
| **Minikube** | `<pending>` | rodar `minikube tunnel` em um terminal separado e mantê-lo aberto |
| **Kind** | `<pending>` (não há load balancer) | usar o `port-forward` abaixo |
| Qualquer cluster | `<pending>` | **fallback universal:** `kubectl port-forward svc/kong 8000:8000` |

O procedimento correto, em qualquer cluster, é nesta ordem:

1. leia o `EXTERNAL-IP` impresso por `kubectl get svc kong`;
2. se ele for um endereço alcançável do host, use **`http://<EXTERNAL-IP>:8000`** (com `localhost` isso é simplesmente `http://localhost:8000`);
3. se **não** for alcançável do host (ou estiver `<pending>`), use o **fallback universal** abaixo — e só então a URL é `http://localhost:8000`.

```bash
# Fallback universal: funciona em qualquer cluster, com ou sem EXTERNAL-IP.
# Deixe rodando em um terminal separado — com o forward ativo a URL é http://localhost:8000.
kubectl port-forward svc/kong 8000:8000
```

Nos exemplos deste README, **`http://localhost:8000` vale quando o `port-forward` está ativo ou quando o `EXTERNAL-IP` do `svc/kong` é `localhost`**; nos demais casos, troque a base da URL pelo `EXTERNAL-IP` — os dois blocos de exemplo abaixo já trazem uma variável (`$gateway` / `$GATEWAY`) só para isso.

Como o Kong publica apenas a porta `8000`, o `port-forward` do proxy não conflita com nenhum outro: a Admin API (`8001`) e a Status API (`8100`) **não são publicadas no Service** e só são alcançáveis por `port-forward` — cada um sobe numa porta local distinta (`8000`, `8001`, `8100`), então os três podem ficar ativos ao mesmo tempo (ver [Depurar (port-forward)](#depurar-port-forward)).

### Verificar o deploy

```bash
kubectl get pods
kubectl get services
kubectl get svc users-api catalog-api kong
```

Todos os pods devem estar com status `Running` — o do Kong só fica `Ready` depois de o script acima criar o `Secret kong-declarative-config`.

Se o pod do Kong **não** sair de `ContainerCreating`/`Pending`, o caso mais comum é a imagem não resolver: com uma tag inexistente (a tag documentada aqui é `kong:3.9`) o pod fica em **`ImagePullBackOff`** e o Service fica **sem endpoints** — daí todos os `curl` ao gateway falharem. Diagnóstico rápido:

```bash
kubectl describe pod -l app=kong             # procure "Failed to pull image" na seção Events
kubectl get events --field-selector reason=Failed
```

Confirme também que as APIs ficaram fechadas: `users-api` e `catalog-api` aparecem como `ClusterIP` e **não existe mais `NodePort`** (as antigas `30001`/`30002` não respondem).

E confirme a exposição do gateway em `kubectl get svc kong`:

- `EXTERNAL-IP` = `localhost` → o gateway já responde em `http://localhost:8000`;
- `EXTERNAL-IP` = um **IP de rede** (ex.: `172.18.0.5`, caso já observado no Docker Desktop) → use `http://<EXTERNAL-IP>:8000`; se esse IP não for alcançável do host, aplique o **fallback universal** `kubectl port-forward svc/kong 8000:8000` e volte para `http://localhost:8000`;
- `EXTERNAL-IP` = `<pending>` → aplique o passo de exposição do cluster (`minikube tunnel`) ou o **fallback universal** `kubectl port-forward svc/kong 8000:8000` antes de seguir para os exemplos.

### Acessar as APIs

Tudo passa pelo gateway, e a base da URL é **o que o `EXTERNAL-IP` do `svc/kong` mandar** ([exposição por cluster](#expor-o-gateway-porta-de-entrada)): `http://localhost:8000` quando o `EXTERNAL-IP` for `localhost` ou quando o `port-forward svc/kong 8000:8000` estiver ativo; `http://<EXTERNAL-IP>:8000` quando o cluster entregar um IP de rede alcançável do host. Os exemplos usam a variável `$gateway` / `$GATEWAY` exatamente para essa troca — os valores esperados não mudam.

O fluxo é **autocontido** e sempre na mesma sessão do terminal: **cadastrar → logar (capturando o token) → chamar a rota protegida**. O token não é reaproveitado entre passos nem entre blocos.

#### Variante A — PowerShell nativo (Windows, sem dependências)

```powershell
# Base do gateway: troque por http://<EXTERNAL-IP>:8000 se o EXTERNAL-IP do svc/kong
# nao for "localhost" (ver "Expor o gateway"). Com port-forward ativo, mantenha localhost.
$gateway = "http://localhost:8000"

# 1) Cadastro (POST /api/usuarios é rota ANÔNIMA). Senha: mínimo de 8 caracteres,
#    com ao menos uma letra, um dígito e um caractere especial. Esperado: 201.
$corpoCadastro = @{ nome = "Jogador FCG"; email = "jogador@fcg.com"; senha = "Senha@123" } | ConvertTo-Json
try {
    Invoke-RestMethod -Method Post -Uri "$gateway/api/usuarios" `
        -ContentType "application/json" -Body $corpoCadastro | Out-Null
    Write-Host "cadastro=201"
} catch {
    # 400 = e-mail já cadastrado (rodada repetida) ou payload inválido
    Write-Host "cadastro=$($_.Exception.Response.StatusCode.value__)"
}

# 2) Login (POST /api/auth/login é rota ANÔNIMA) e captura do token NA MESMA SESSÃO.
$corpoLogin = @{ email = "jogador@fcg.com"; senha = "Senha@123" } | ConvertTo-Json
$token = (Invoke-RestMethod -Method Post -Uri "$gateway/api/auth/login" `
    -ContentType "application/json" -Body $corpoLogin).token

# 3) Rota protegida SEM token -> o gateway responde 401
try {
    Invoke-WebRequest -Uri "$gateway/api/jogos" -UseBasicParsing | Out-Null
    Write-Host "sem-token=200 (inesperado)"
} catch {
    Write-Host "sem-token=$($_.Exception.Response.StatusCode.value__)"
}

# 4) Rota protegida COM token -> 200
$respostaComToken = Invoke-WebRequest -Uri "$gateway/api/jogos" `
    -Headers @{ Authorization = "Bearer $token" } -UseBasicParsing
Write-Host "com-token=$($respostaComToken.StatusCode)"
```

Esperado: `cadastro=201`, `sem-token=401`, `com-token=200` (numa segunda execução, `cadastro=400` — o usuário já existe — e o restante igual).

> No Windows PowerShell 5.1, o `Invoke-WebRequest` sem `-UseBasicParsing` depende do Internet Explorer; os exemplos acima já passam `-UseBasicParsing`.

#### Variante B — bash (`curl` + `jq`, em Git Bash ou WSL)

```bash
# Base do gateway: troque por http://<EXTERNAL-IP>:8000 se o EXTERNAL-IP do svc/kong
# nao for "localhost" (ver "Expor o gateway"). Com port-forward ativo, mantenha localhost.
GATEWAY="${GATEWAY:-http://localhost:8000}"

# 1) Cadastro (rota ANÔNIMA). Esperado: 201
curl -s -o /dev/null -w "cadastro=%{http_code}\n" -X POST "$GATEWAY/api/usuarios" \
  -H "Content-Type: application/json" \
  -d '{"nome":"Jogador FCG","email":"jogador@fcg.com","senha":"Senha@123"}'

# 2) Login (rota ANÔNIMA) e captura do token NO MESMO BLOCO.
#    O jq extrai o campo "token" da resposta { "token": "..." }.
TOKEN=$(curl -s -X POST "$GATEWAY/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"jogador@fcg.com","senha":"Senha@123"}' | jq -r '.token')

# 3) Rota protegida SEM token -> 401
curl -s -o /dev/null -w "sem-token=%{http_code}\n" "$GATEWAY/api/jogos"

# 4) Rota protegida COM token -> 200
curl -s -o /dev/null -w "com-token=%{http_code}\n" "$GATEWAY/api/jogos" \
  -H "Authorization: Bearer $TOKEN"
```

Esperado: `cadastro=201`, `sem-token=401`, `com-token=200`. Sem `jq` instalado, remova o pipe e copie o campo `token` da resposta do login para a chamada do passo 4.

Em ambas as variantes, se o `login` falhar, o passo 4 recebe `401` — reautentique (passo 2) em vez de reaproveitar um token de outra sessão.

### Depurar (port-forward)

O gateway é a única entrada suportada; os comandos abaixo servem **apenas para depuração local**:

```bash
# Bypass do gateway para inspecionar uma API direto no pod (só na sua máquina)
kubectl port-forward svc/users-api 8080:80

# Admin API do Kong — NÃO é publicada no Service e escuta apenas em 127.0.0.1 dentro
# do pod. O port-forward alcança esse loopback (ele abre o túnel dentro do netns do pod),
# então continue usando o mesmo comando de sempre:
kubectl port-forward deploy/kong 8001:8001
# com o forward ativo, em OUTRO terminal:
curl -s http://localhost:8001/status     # 200
curl -s http://localhost:8001/routes     # users-login, catalog-jogos, catalog-biblioteca, users-protegida, users-signup

# Alternativa sem curl (nem no host nem no pod) — o próprio binário do Kong:
kubectl exec -it deploy/kong -- kong health
# e para validar o parse da config declarativa montada no pod:
kubectl exec -it deploy/kong -- kong config parse /kong/declarative/kong.yml
```

> A Admin API continua restrita ao loopback do pod de propósito: em DB-less o `GET /` devolve a configuração declarativa inteira, incluindo o `secret` HMAC do consumer — mantê-la fora da rede do cluster (e fora do Service) evita que qualquer pod leia a chave e forje tokens. O `port-forward` é um túnel da **sua** máquina para o loopback do pod, não uma exposição da porta: por isso ele funciona e a Admin API segue inalcançável de qualquer outro pod.
>
> A imagem `kong:3.9` **não traz `curl`** (só o binário `kong`), então `kubectl exec -it deploy/kong -- curl ...` não funciona — use o par `port-forward` + `curl` no host, ou os comandos `kong health` / `kong config parse` dentro do pod.

### Remover o deploy

```bash
kubectl delete -f k8s/kong/kong-deployment.yaml
kubectl delete -f k8s/
# o Secret do Kong é criado pelo script, não pelos manifestos:
kubectl delete secret kong-declarative-config
```

## API Gateway (Kong)

O [Kong 3.9](https://konghq.com/) em modo **DB-less** é o ponto de entrada único das APIs: `http://localhost:8000` quando o `EXTERNAL-IP` do `svc/kong` for `localhost` ou com o `port-forward` ativo, e `http://<EXTERNAL-IP>:8000` quando o cluster entregar um IP de rede (ver [exposição por cluster](#expor-o-gateway-porta-de-entrada)). Nenhuma API é acessível diretamente de fora do cluster.

### Como está montado

| Componente | Onde vive | Papel |
|---|---|---|
| Config declarativa | `k8s/kong/kong.yml.template` | Serviços, rotas, plugin `jwt` e consumer — versionado, com o marcador `${JWT_SECRET}` no lugar do segredo |
| Deployment + Service | `k8s/kong/kong-deployment.yaml` | Kong `3.9` com `KONG_DATABASE=off`, proxy em `0.0.0.0:8000`; Service `LoadBalancer` publicando **apenas** a porta `8000`; Admin API em loopback (`127.0.0.1:8001`) e Status API em `0.0.0.0:8100`, ambas fora do Service |
| Config renderizada | `Secret kong-declarative-config` (cluster) | `kong.yml` final, montado somente leitura em `/kong/declarative/kong.yml` |
| Script de deploy | `scripts/deploy-kong.ps1` | Renderiza o template, aplica o `Secret`, reinicia o Kong e espera o rollout |

A Admin API (`8001`) **não é publicada no Service** e escuta apenas em `127.0.0.1` **dentro do pod**; o acesso é por `kubectl port-forward deploy/kong 8001:8001` + `curl http://localhost:8001/status` (o `port-forward` alcança o loopback do pod — ver [Depurar (port-forward)](#depurar-port-forward)). Dentro do pod, sem `curl` (a imagem `kong:3.9` não o traz), use `kubectl exec -it deploy/kong -- kong health`. As probes usam a Status API (`8100`), que também não é publicada.

### Como o segredo JWT é injetado

O `kong.yml` final **nunca** vai para o git — o repositório guarda apenas o template com `${JWT_SECRET}`. O fluxo é:

1. `scripts/deploy-kong.ps1` lê o segredo que já existe no cluster (`Secret users-api-secret`, chave `jwt-secret-key` — o mesmo usado pelas APIs);
2. substitui `${JWT_SECRET}` no template e grava o resultado num arquivo temporário em **UTF-8 sem BOM** (com BOM, o Kong pode falhar no parse da config declarativa);
3. cria/atualiza o `Secret kong-declarative-config` (`kubectl create secret generic ... --dry-run=client -o yaml | kubectl apply -f -`);
4. reinicia o Deployment do Kong, **espera o `kubectl rollout status`** (se o Kong não ficar pronto, o script lança erro em vez de anunciar sucesso) e apaga o arquivo temporário (que contém o segredo em claro).

Invocação suportada: **`powershell -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1`** (alternativa em quem tem PowerShell 7: `pwsh -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1`). Como o Kong é DB-less, **a configuração só passa a valer depois do restart feito pelo script**.

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

Contratos das rotas anônimas (as únicas que dispensam token):

- `POST /api/usuarios` (cadastro) — corpo `{"nome": "...", "email": "...", "senha": "..."}` (`CriarUsuarioDTO`); a senha precisa ter no mínimo 8 caracteres, com ao menos uma letra, um dígito e um caractere especial; responde `201` no sucesso e `400` se o e-mail já existir ou o payload for inválido. Exemplo executável em [Acessar as APIs](#acessar-as-apis).
- `POST /api/auth/login` — corpo `{"email": "...", "senha": "..."}` (`LoginDTO`); responde `200` com o token, `401` se a senha estiver incorreta e `400` se o e-mail não existir ou o payload for inválido.

### Aviso: não definir porta HTTPS nos serviços

As APIs chamam `UseHttpsRedirection()`, e o Kong fala **HTTP puro** com os upstreams (`http://users-api:80`, `http://catalog-api:80`).

- **Sem** porta HTTPS definida, o `UseHttpsRedirection()` apenas registra um aviso no log e continua servindo HTTP — este é o cenário esperado.
- **Com** porta HTTPS definida (`ASPNETCORE_HTTPS_PORTS`, ou `ASPNETCORE_URLS` contendo `https://`), o middleware passa a responder **`307 Temporary Redirect`** para `https`. O Kong não segue esse redirect e o **roteamento quebra** (o cliente recebe `307` e o upstream nunca é alcançado).

Portanto: **não defina porta HTTPS nos Deployments/ConfigMaps das APIs, nem publique uma porta HTTPS nos Services.**

### Depurar o gateway

```bash
# Admin API do Kong — escuta só no loopback do pod e não é publicada no Service;
# o port-forward alcança o loopback (túnel aberto dentro do netns do pod):
kubectl port-forward deploy/kong 8001:8001
# com o forward ativo, em outro terminal:
curl -s http://localhost:8001/status
curl -s http://localhost:8001/routes     # /services | /plugins | /consumers

# Sem curl (a imagem kong:3.9 não traz curl): health do Kong e parse da config montada
kubectl exec -it deploy/kong -- kong health
kubectl exec -it deploy/kong -- kong config parse /kong/declarative/kong.yml

# Status API (8100) — a mesma que as probes usam; também não é publicada no Service
kubectl port-forward deploy/kong 8100:8100
curl -s http://localhost:8100/status/ready

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
│       ├── kong-deployment.yaml      # Deployment + Service (proxy 8000; Admin 8001 e Status 8100 só no pod)
│       └── kong.yml.template         # config declarativa com o marcador ${JWT_SECRET}
├── scripts/
│   └── deploy-kong.ps1               # renderiza o segredo, reinicia o Kong e espera o rollout
└── README.md
```
