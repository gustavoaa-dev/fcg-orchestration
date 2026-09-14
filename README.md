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
| MongoDB | `ClusterIP:27017` | Avaliações dos jogos (Kubernetes): **não** é publicado pelo gateway; o acesso é por `kubectl port-forward svc/mongo 27017:27017` — ver [Persistência poliglota e cache](#persistência-poliglota-e-cache) |
| Redis | `ClusterIP:6379` | Cache de leitura do catálogo (Kubernetes): **não** é publicado pelo gateway; o acesso é por `kubectl port-forward svc/redis 6379:6379` — ver [Persistência poliglota e cache](#persistência-poliglota-e-cache) |
| Prometheus | `ClusterIP:9090` → `http://localhost:19090` | Observabilidade (Kubernetes): **não** é publicado pelo gateway; o acesso é por `port-forward` — ver [Observabilidade](#observabilidade) |
| Grafana | `ClusterIP:3000` → `http://localhost:13000` | Observabilidade (Kubernetes): **não** é publicado pelo gateway; login `admin` e senha vêm do `Secret grafana-admin` |

> As portas `5001`–`5004` das APIs não existem mais: os containers das APIs não publicam porta alguma no host.

> Prometheus e Grafana também ficam **fechados dentro do cluster**: o gateway Kong roteia apenas quatro prefixos (`/api/auth`, `/api/usuarios`, `/api/jogos` e `/api/biblioteca`), e os dois Services são `ClusterIP` sem `EXTERNAL-IP` — chega-se a eles só por `port-forward`, nas portas locais `19090` e `13000` (ver [Observabilidade](#observabilidade)).

> O mesmo vale para o **MongoDB e o Redis**: os dois são `ClusterIP` sem `EXTERNAL-IP` e **não** têm rota no Kong — quem fala com eles é o `catalog-api`, por `mongo:27017` e `redis:6379`, de dentro do cluster. Para inspecionar de fora, o caminho é `port-forward` (ver [Persistência poliglota e cache](#persistência-poliglota-e-cache)).

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

As imagens são buildadas **localmente** (não há registry) e o cluster as consome com `imagePullPolicy: IfNotPresent`. A tag usada no build tem de ser **a mesma** declarada no manifesto:

```bash
# Em cada diretório de microsserviço:
docker build -t fcg-users-api:sp2 .
docker build -t fcg-catalog-api:sp2 .
docker build -t fcg-payments-api:latest .
docker build -t fcg-notifications-api:latest .
```

> **Convenção de tag: cada rebuild exige uma tag nova.** As APIs instrumentadas nesta fase usam tag **versionada por fase** — as duas APIs revisadas no SP2 (`users-api` e `catalog-api`) são buildadas como `fcg-users-api:sp2` e `fcg-catalog-api:sp2`, e é exatamente essa tag que está declarada em `k8s/users-api-deployment.yaml` e `k8s/catalog-api-deployment.yaml` (`payments-api` e `notifications-api` ainda usam `:latest`). Com `imagePullPolicy: IfNotPresent` **rebuildar a mesma tag não atualiza o pod**: o kubelet encontra a imagem daquela tag já presente no nó e reutiliza a antiga, sem novo pull — o `kubectl rollout restart` sobe de novo, mas com o binário velho. Publicar alteração de código é, portanto, sempre um passo de três partes: **buildar com tag nova** (`:sp3`), **trocar a tag no manifesto** e **reaplicar** — `docker build -t fcg-users-api:sp3 .`, editar `image:` em `k8s/users-api-deployment.yaml` e `kubectl apply -f k8s/users-api-deployment.yaml`. Se você alterar `payments-api` ou `notifications-api`, a mesma regra vale — tag nova por rebuild (hoje elas ainda estão em `:latest`, e é justamente por isso que um rebuild delas não chega ao pod). (É por isso que os comandos acima não usam `-t fcg-users-api .`, que gera a tag móvel `:latest`: ela não distingue duas revisões e o pod passa a rodar código diferente do que o git descreve.)

### Aplicar os manifestos

A **ordem importa**: primeiro a infraestrutura, as APIs e a observabilidade (com o `Secret` do Grafana antes do apply), depois o gateway Kong.

```bash
# 1) Infraestrutura (RabbitMQ, SQL Server), APIs e observabilidade (Prometheus, Grafana)
kubectl apply -f k8s/

# 2) Gateway Kong — depende do Secret users-api-secret, criado no passo 1
kubectl apply -f k8s/kong/kong-deployment.yaml
```

> `kubectl apply -f k8s/` não é recursivo: aplica apenas os manifestos que estão na raiz de `k8s/`. O subdiretório `k8s/kong/` é aplicado em separado de propósito, porque o pod do Kong só fica pronto depois de o script abaixo criar o `Secret kong-declarative-config`.

> Antes desse apply crie o `Secret grafana-admin`: o Deployment do Grafana o referencia em `secretKeyRef` e, sem ele, o pod fica em `CreateContainerConfigError` (comando em [Subir a stack](#subir-a-stack)).

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
kubectl get svc users-api catalog-api kong prometheus grafana
kubectl get pvc prometheus-data
```

Todos os pods devem estar com status `Running` — o do Kong só fica `Ready` depois de o script acima criar o `Secret kong-declarative-config`, e o **do Grafana** só sobe depois do `Secret grafana-admin` (ele é o único que referencia o Secret; se o pod do **Prometheus** não subir, a causa é outra — PVC/StorageClass ou imagem — ver [Observabilidade](#observabilidade)).

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
# o Secret do Grafana também é criado à mão, não pelos manifestos:
kubectl delete secret grafana-admin
```

> `kubectl delete -f k8s/` também remove o PVC `prometheus-data`: o histórico coletado pelo Prometheus vai junto (a retenção de 7 dias é descartada).

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

## Observabilidade

A stack escolhida para esta fase é a **Opção A — Prometheus + Grafana**: as duas ferramentas são de **código aberto, sem custo e sem dependência de conta em nuvem**, então a plataforma continua executável apenas com o Docker Desktop, sem serviço externo, sem chave de API e sem enviar métrica alguma para fora da máquina. Toda a pilha é declarativa: a instrumentação é código nas APIs e o resto são manifestos Kubernetes versionados **neste repositório** (`k8s/prometheus-*.yaml` e `k8s/grafana-*.yaml`), aplicados pelo mesmo `kubectl apply -f k8s/` do restante do ambiente.

- **Instrumentação:** `users-api` e `catalog-api` expõem `/metrics` (biblioteca `prometheus-net` 8.2.1) e `/health`. O `UseHttpMetrics()` está posicionado de forma que os `401`/`403` de `[Authorize]` e as exceções tratadas pelo `ErrorHandlingMiddleware` também entram nas métricas — confirmado nas séries, com `controller`, `action` e `endpoint` preenchidos (ex.: `http_requests_received_total{code="401",method="GET",controller="Users",action="ObterTodos",endpoint="api/usuarios"}`). As probes `startup`/`readiness`/`liveness` dos dois Deployments apontam para `/health:8080`.
- **Coleta:** o Prometheus raspa `users-api:80` e `catalog-api:80` (job `fcg-apis`, `metrics_path: /metrics`) a cada **15s** (`k8s/prometheus-configmap.yaml`), além de a si mesmo em `localhost:9090`, e guarda **7 dias** de dados em volume persistente (`--storage.tsdb.retention.time=7d`, PVC `prometheus-data`, 2Gi).
- **Visualização:** o Grafana sobe com datasource e dashboard **provisionados por ConfigMap** (`k8s/grafana-configmap.yaml` e `k8s/grafana-dashboards-configmap.yaml`) — nada é cadastrado à mão na interface. O datasource `Prometheus` (`uid: prometheus`) aponta para `http://prometheus:9090`, e o dashboard **FCG - APIs** (`uid: fcg-apis`) traz latência (p50/p95) por rota, requisições por segundo por rota, requisições por status code, taxa de erro 5xx e um painel de coleta (`up`) por alvo — os quatro painéis de tráfego derivam de `http_request_duration_seconds_bucket` e `http_requests_received_total`, coletados na porta `/metrics` das APIs, e o de coleta vem da série `up` do próprio Prometheus. Os quatro painéis de tráfego **excluem as probes `/health`** (filtro `endpoint!="/health"`): sozinhas elas respondem por quase todo o volume coletado (um `code="200"` a cada 5s/10s por pod) e afogariam o tráfego de negócio — o número que aparece nesses painéis é tráfego de negócio, não probe. As rotas aparecem pelo **RoutePattern** do ASP.NET, **sem a barra inicial** do path: `/api/jogos` é exibido como `api/jogos`, `/api/usuarios` como `api/usuarios`; a única série que mantém a barra é a própria probe, `endpoint="/health"` — é por isso que qualquer filtro por `endpoint` precisa casar com esses valores exatos.
- **Exposição:** nenhum dos dois é publicado pelo gateway — ambos são `ClusterIP` e o acesso é por `port-forward` (veja abaixo). O Kong roteia apenas quatro prefixos (`/api/auth`, `/api/usuarios`, `/api/jogos` e `/api/biblioteca`), então `/metrics` e `/health` não saem do cluster (o mesmo vale para a interface do Prometheus e a do Grafana).
- **Senha do Grafana:** o login é `admin` e a senha vem do `Secret` `grafana-admin` (chave `admin-password`) — que **nunca** vai para o git. As demais configurações do Grafana são fixas no manifesto, entre elas `GF_USERS_ALLOW_SIGN_UP=false`.
- **Persistência do Grafana:** o container monta `emptyDir` em `/var/lib/grafana`, então nada daí sobrevive a um restart do pod. Isso não afeta datasource nem dashboard — os dois são **recriados pela provisão a cada start** (é o que a montagem por ConfigMap garante) —, mas dados criados pela UI (usuários extras, snapshots, preferências) **são perdidos**: trate os manifestos de provisionamento como a fonte de verdade e não conte com a interface para o que precisa durar.

### Subir a stack

A ordem importa: **o `Secret` do Grafana precisa existir antes do apply**, porque o Deployment o referencia em `secretKeyRef` — sem ele o pod fica em `CreateContainerConfigError`.

```powershell
# 1) Secret do Grafana — crie ANTES do apply (a senha é sua; não vai para o git):
kubectl create secret generic grafana-admin --from-literal=admin-password='<sua-senha>' --dry-run=client -o yaml | kubectl apply -f -

# 2) Prometheus e Grafana estão na raiz de k8s/, então entram no mesmo apply
#    da infraestrutura e das APIs (ver "Aplicar os manifestos"):
kubectl apply -f k8s/
```

O PVC `prometheus-data` declara `storageClassName: standard`, então a StorageClass `standard` (a default do Docker Desktop) é **pré-requisito**: num cluster sem ela o PVC fica `Pending` indefinidamente, porque não há provisionamento dinâmico. Confira o que subiu:

```bash
kubectl get pods -l 'app in (prometheus,grafana)'
kubectl get pvc prometheus-data
kubectl get svc prometheus grafana
```

Esperado: os dois pods `Running` e `Ready` (`1/1`), o PVC em `Bound` e os dois Services como `ClusterIP`.

> Logo depois do apply é normal o `prometheus-data` aparecer como **`Pending`**: com `WaitForFirstConsumer` a StorageClass só provisiona o volume quando o pod que o consome é criado. Assim que o pod do Prometheus entra em execução o PVC passa a `Bound` — só investigue se ele continuar `Pending` com o pod agendado. (Confirmado neste cluster: a `standard` usa `WaitForFirstConsumer`, e o evento do PVC é literalmente `WaitForFirstConsumer: waiting for first consumer to be created before binding`.)

> O Deployment do Prometheus usa `strategy: Recreate` de propósito: o PVC é `ReadWriteOnce`, então o pod novo não conseguiria montar o volume enquanto o antigo o estivesse usando (ou, num provisioner local onde o `ReadWriteOnce` não é imposto, montaria o mesmo caminho por cima do primeiro, com risco para o TSDB). O rollout ficaria **preso** esperando o novo pod ficar `Ready` — e, como no rolling update o pod antigo não é removido antes disso, a troca nunca terminaria.

### Acessar os painéis (port-forward)

Nenhum dos dois tem `EXTERNAL-IP`: o acesso é por `port-forward`, em **dois terminais**. As portas locais (`19090` e `13000`) são diferentes das do Kong (`8000`/`8001`/`8100`), então todos os forwards podem ficar ativos ao mesmo tempo:

```bash
kubectl port-forward svc/prometheus 19090:9090   # http://localhost:19090
kubectl port-forward svc/grafana 13000:3000      # http://localhost:13000  (admin / senha do Secret)
```

No Grafana o dashboard **FCG - APIs** já aparece no menu (provisionado por ConfigMap) e o login é `admin` com a senha que você pôs no `Secret grafana-admin`. No Prometheus, `Status → Targets` mostra os alvos. Com o forward ativo, dá para conferir a coleta sem abrir o Grafana:

```bash
# os alvos do job fcg-apis (users-api e catalog-api) devem aparecer com "health":"up"
curl -s "http://localhost:19090/api/v1/targets?state=active"

# série de fato coletada — é o nome de métrica usado pelos painéis
curl -s "http://localhost:19090/api/v1/query?query=http_requests_received_total"
```

> No **PowerShell**, `curl` resolve para o alias de `Invoke-WebRequest` e esses comandos falham — use `curl.exe -s` (o `curl.exe` do Windows 10/11 é o `curl` de verdade). O mesmo cuidado vale para os exemplos de `curl` deste README.

### Gerar tráfego para os painéis

Os painéis ficam vazios enquanto não houver requisição: use o fluxo de [Acessar as APIs](#acessar-as-apis) — cadastro, login e chamadas autenticadas pelo gateway em `http://localhost:8000`. Cada execução movimenta `users-api` e `catalog-api`: as chamadas que chegam às APIs aparecem no painel de status code — inclusive as anônimas que falham por credencial, como `POST /api/auth/login` de um usuário **existente** com a senha incorreta, que aparece como `401` (já o e-mail inexistente responde `400`, pelo contrato do endpoint). Os `401` rejeitados **no gateway** (chamadas sem token) **não** aparecem, porque o Kong responde antes de encaminhar: o gateway não é instrumentado nesta fase — a Opção A instrumenta `users-api` e `catalog-api`.

### Alterar o scrape exige restart do Prometheus

O Prometheus **não recarrega** o `prometheus.yml` sozinho: o arquivo é lido uma única vez, na inicialização do processo, e não há sidecar de reload (nem `--web.enable-lifecycle`). Depois de mudar `k8s/prometheus-configmap.yaml`:

```bash
kubectl apply -f k8s/prometheus-configmap.yaml
kubectl rollout restart deployment/prometheus   # sem isso a config antiga continua valendo
```

> A lógica é a mesma do Kong DB-less ([Configurar o gateway](#configurar-o-gateway-segredo-jwt)): a configuração montada só passa a valer no próximo start do processo.

### Alterar a provisão do Grafana (semântica de reload)

Os dois ConfigMaps do Grafana **não** têm a mesma semântica de reload:

- **Dashboard** (`k8s/grafana-dashboards-configmap.yaml`) — **propaga sozinho**: o provider `fcg` é do tipo `file` com `updateIntervalSeconds: 30` (ver `dashboards.yml` em `k8s/grafana-configmap.yaml`), então o Grafana relê os arquivos de `/var/lib/grafana/dashboards` a cada **30s**. Depois do apply, basta esperar o kubelet atualizar o volume montado do ConfigMap (até ~1 min) e o dashboard novo aparece — **não** é preciso reiniciar pod algum.
- **Datasource e provider** (`k8s/grafana-configmap.yaml`) — **exige restart do pod**: essa metade da provisão é lida uma única vez, no boot do Grafana. Sem restart, o arquivo novo fica montado e **ignorado**.

```bash
kubectl apply -f k8s/grafana-dashboards-configmap.yaml   # propaga sozinho (provider relê a cada 30s)
kubectl apply -f k8s/grafana-configmap.yaml              # só passa a valer no próximo boot:
kubectl rollout restart deployment/grafana
```

## Persistência poliglota e cache

Esta fase acrescenta dois serviços de dados ao cluster — **MongoDB** para as avaliações dos jogos e **Redis** para o cache de leitura do catálogo — cada um escolhido pelo **formato do dado**, não por substituição: o SQL Server continua sendo a fonte de verdade do catálogo e dos usuários, e nada foi migrado para fora dele. Os dois manifestos (`k8s/mongo-deployment.yaml` e `k8s/redis-deployment.yaml`) ficam na raiz de `k8s/` e entram no mesmo `kubectl apply -f k8s/` do restante do ambiente; os dois Services são `ClusterIP` (`mongo:27017` e `redis:6379`) e não têm rota no gateway.

| Componente | Imagem | Persistência | Observação |
|---|---|---|---|
| MongoDB | `mongo:8.0.30` | PVC `mongo-data` (1Gi, `standard`) | `strategy: Recreate` de propósito: o PVC é `ReadWriteOnce` e, em rolling update, o pod novo ficaria preso esperando o volume — a mesma razão do Prometheus |
| Redis | `redis:7.4.11-alpine3.21` | **nenhuma** (é cache) | Sem PVC por decisão: perder o conteúdo é aceitável porque a fonte de verdade é o SQL. `--maxmemory 128mb --maxmemory-policy allkeys-lru` |

### Por que MongoDB (avaliações)

- **É dado gerado pelo usuário, com formato que varia.** A `nota` (1 a 5) é obrigatória, mas o `comentario` é opcional e `tags[]` é uma lista livre — em modelo relacional isso vira coluna anulável mais uma tabela de tags, com junção a cada leitura, sem nenhum ganho de integridade em troca.
- **A volumetria cresce com o uso, não com o cadastro.** Cada usuário pode avaliar cada jogo, e o conjunto cresce para sempre; é o oposto do **catálogo**, que é pequeno, tem preço e participa de junções com a biblioteca — e por isso continua no SQL Server.
- **A leitura que importa é agregada.** O resumo (total e média) é uma agregação do próprio Mongo, não um `SELECT` que traz os documentos para a API calcular.
- **Driver oficial `MongoDB.Driver` 3.11.2.** Database `fcg_catalog`, coleção `avaliacoes`, com **índice único `(gameId, userId)` criado no boot da API** — é ele que sustenta a regra "uma avaliação por usuário por jogo".
- **A avaliação nunca é órfã:** o jogo precisa existir no SQL Server antes do `PUT`, senão a resposta é `404`.
- **O catálogo não depende dele.** O Mongo serve **apenas** os endpoints de avaliação: com o Mongo fora, a listagem e a biblioteca continuam vindo do SQL Server (e do cache) e só as rotas `/avaliacoes` deixam de responder. Conferido em runtime com o Deployment em `0` réplicas: o `catalog-api` **sobe** assim mesmo e responde `/health` e `/metrics` com `200` — o `MongoDB.Driver` loga o timeout ao tentar criar o índice e o processo segue; o boot paga cerca de **30s** a mais por causa desse timeout.

### Por que Redis (cache do catálogo)

- **A listagem inteira vai ao SQL a cada chamada.** `GET /api/jogos` não tem paginação: devolve o catálogo completo todas as vezes, e é a consulta mais repetida da plataforma — o lugar onde o cache rende mais e arrisca menos.
- **É cache, não banco.** O Redis não guarda nada que não possa ser reconstruído do SQL, e por isso não tem PVC: um restart do pod é irrelevante para a plataforma.
- **A conexão não é segredo:** `Redis__ConnectionString: redis:6379` está no ConfigMap `catalog-api-config`.
- **Degradação graciosa por desenho:** o cache é sempre opcional na leitura — se ele falhar, a resposta vem do SQL (detalhes em [Cache em operação](#cache-em-operação)).

### Endpoints de avaliação

As rotas passam pelo Kong como as demais (`/api/jogos`, JWT obrigatório) — **não** há rota nova no gateway, só endpoints novos no `catalog-api`:

| Método e rota | Resposta |
|---|---|
| `PUT /api/jogos/{gameId}/avaliacoes` (o mesmo caminho também aceita `POST`) | `201` na primeira avaliação do usuário para aquele jogo e `200` ao atualizar (upsert por `(gameId, userId)`) |
| `GET /api/jogos/{gameId}/avaliacoes` | Lista das avaliações do jogo, mais recentes primeiro (por `dataAtualizacao`) |
| `GET /api/jogos/{gameId}/avaliacoes/resumo` | `{ "jogoId": "...", "total": 2, "notaMedia": 3.5 }` — com nenhuma avaliação, `total: 0` e `notaMedia` nulo |

- Corpo de ambos (`PUT` e `POST`): `{"nota": 5, "comentario": "opcional", "tags": ["acao"]}`; `nota` entre **1 e 5** (`400` fora da faixa ou com corpo inválido).
- **O caminho aceita `POST` além de `PUT`:** a spec da disciplina escreve `POST /api/jogos/{gameId}/avaliacoes`, então os dois verbos chegam ao mesmo action — o `PUT` é a forma preferida por ser um upsert idempotente, e as duas respondem os **mesmos status** (`201` na criação, `200` na atualização) e recebem o **mesmo JSON**.
- **O autor vem do claim `Id` do token, nunca do corpo:** um `usuarioId` enviado no JSON é ignorado (comportamento conferido em runtime), e um token válido que **não** traga o claim `Id` recebe `401`.
- Demais contratos: `404` se o jogo não existir no SQL Server, `401` sem token.

### Cache em operação

- **Onde ele mora:** um decorator `CachedGameRepository` sobre `IGameRepository` (`Microsoft.Extensions.Caching.StackExchangeRedis` 8.0.31) — o `GameService` não mudou, porque cache-aside é detalhe de acesso a dado, não regra de negócio.
- **Chaves e TTL:** `catalog:games:all` (listagem) e `catalog:game:{id}` (por id), com **TTL de 60s** (`AbsoluteExpirationRelativeToNow`). Numa leitura real logo após o `GET`, o `TTL` da chave mediu **59**.
- **Invalidação explícita no POST e no DELETE de jogo:** os dois passam por `Salvar()`, que remove `catalog:games:all` **e** `catalog:game:{id}` do jogo alterado. Sem isso, a listagem ficaria até 60s mentindo para quem lê logo depois de criar ou remover um jogo.
- **Contadores `cache_hit` e `cache_miss`** no `/metrics`, coletados pelo Prometheus do SP2 (mesmo job `fcg-apis`). Atenção ao nome: o `prometheus-net` 8.2.1 expõe a série **exatamente como registrada, sem o sufixo `_total`** — no `/metrics` a linha é `cache_hit` seguida do valor, e **não** `cache_hit_total` (conferido em runtime; qualquer painel ou consulta tem de usar o nome cru).
- **Frio x quente:** a primeira leitura vai ao SQL e a segunda vem do Redis, com o **corpo da resposta idêntico** nos dois casos (comparado em runtime, primeiro com o cache frio e depois quente). Numa medição real desta máquina: **32ms** no miss e **19ms** no hit.
- **Degradação graciosa:** toda falha de cache é capturada e a leitura segue para o SQL — o Redis **não** derruba a API. Com o Redis fora do ar (`kubectl scale deployment/redis --replicas=0`), `GET /api/jogos`, `GET /api/jogos/{id}` e o `PUT` de avaliação continuam respondendo `200`, e o log traz `Falha ao ler a chave catalog:... do Redis; seguindo para o SQL Server.` na leitura e `Falha ao gravar a chave catalog:... no Redis; a resposta segue sem cache.` na gravação. O preço são os timeouts do cliente (2s por operação): a listagem medida nesse cenário levou **5,6s** antes de responder. Com o Redis de volta, as chaves são recriadas e o `cache_hit` volta a subir — não é preciso reiniciar o `catalog-api`.
- **Inspecionar as chaves (armadilha):** o `IDistributedCache` grava o valor como **hash** (`HSET <chave> data/absexp/sldexp`), então `redis-cli GET <chave>` devolve **`WRONGTYPE`** (a chave existe e é um hash; numa chave inexistente a saída é vazia). O erro não é do cache — confira com `EXISTS`/`TYPE`/`HLEN`:

```bash
kubectl exec deploy/redis -- redis-cli exists catalog:games:all   # 1
kubectl exec deploy/redis -- redis-cli type catalog:games:all     # hash
kubectl exec deploy/redis -- redis-cli hlen catalog:games:all     # 3 (data, absexp, sldexp)
kubectl exec deploy/redis -- redis-cli ttl catalog:games:all      # ate 60
kubectl exec deploy/redis -- redis-cli keys 'catalog:*'
```

### Subir o Mongo e o Redis

O `Secret mongo-secret` é **pré-requisito do apply**, como o `grafana-admin`: o Deployment do Mongo o referencia em `secretKeyRef` e, sem ele, o pod fica em `CreateContainerConfigError`. Ele é criado à mão e **nunca vai para o git**:

```powershell
# 1) Secret do Mongo — crie ANTES do apply (usuario e senha sao seus; nao vao para o git):
kubectl create secret generic mongo-secret `
  --from-literal=root-username='<usuario>' `
  --from-literal=root-password='<senha>' `
  --from-literal=connection-string='mongodb://<usuario>:<senha>@mongo:27017/?authSource=admin' `
  --dry-run=client -o yaml | kubectl apply -f -

# 2) O Mongo e o Redis estao na raiz de k8s/, entao entram no mesmo apply
#    da infraestrutura, das APIs e da observabilidade (ver "Aplicar os manifestos"):
kubectl apply -f k8s/
```

> A senha do Mongo deve ser **alfanumérica**: em URI, caractere especial precisa vir percent-encoded (`@` → `%40`) e é uma fonte clássica de erro silencioso de conexão. A chave `connection-string` do segredo é o que o `catalog-api` consome em `Mongo__ConnectionString`; o database vem do ConfigMap, em `Mongo__DatabaseName` (`fcg_catalog`).

Confira o que subiu (o Mongo é o único dos dois que tem PVC):

```bash
kubectl get pods -l 'app in (mongo,redis)'
kubectl get pvc mongo-data
kubectl get svc mongo redis
```

Esperado: os dois pods `Running` e `Ready` (`1/1`), o PVC `mongo-data` em `Bound` e os dois Services como `ClusterIP`. O Redis **não** tem PVC nenhum de propósito — não estranhe a ausência dele.

### Limitações conhecidas e follow-ups

- **O `docker-compose.yml` não sobe Mongo nem Redis.** O caminho do Compose continua sendo apenas a infraestrutura de desenvolvimento (RabbitMQ e SQL Server) e as APIs; esta fase é contemplada **somente** pelo fluxo do cluster, documentado acima.
- **Não há circuit breaker no cache.** Com o Redis fora, cada leitura cacheada paga os timeouts de conexão (2s por operação; 5,6s na listagem medida) antes de cair no SQL — a API responde certo, mas mais devagar enquanto o Redis estiver indisponível.
- **O cache é do `catalog-api`.** A `users-api` não lê nem invalida chave alguma: `GET /api/usuarios` continua indo ao SQL a cada chamada.
- **O `ErrorHandlingMiddleware` do `catalog-api` vaza stack trace e responde em PascalCase.** Ele devolve `Detalhe` com o **stack trace** da exceção e serializa o corpo como `StatusCode`/`Mensagem`/`Detalhe`, enquanto os controllers existentes respondem `{"mensagem": ...}` em camelCase. O defeito **já foi observado em runtime** no `401` de um token válido sem o claim `Id`, cuja resposta trouxe o stack trace com `AvaliacoesController.ObterUsuarioId()`.
- **O scrape do Prometheus é estático por Service** (`users-api:80`, `catalog-api:80`), o que **pressupõe 1 réplica por API**: com 2+ réplicas ele raspa um pod aleatório por scrape e as réplicas colapsam numa única série — revisar ao escalar.

## Estrutura de arquivos

```
fcg-orchestration/
├── docker-compose.yml
├── k8s/
│   ├── rabbitmq-deployment.yaml
│   ├── sqlserver-deployment.yaml
│   ├── mongo-deployment.yaml
│   ├── redis-deployment.yaml
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
│   ├── prometheus-configmap.yaml
│   ├── prometheus-deployment.yaml
│   ├── grafana-configmap.yaml
│   ├── grafana-dashboards-configmap.yaml
│   ├── grafana-deployment.yaml
│   └── kong/
│       ├── kong-deployment.yaml      # Deployment + Service (proxy 8000; Admin 8001 e Status 8100 só no pod)
│       └── kong.yml.template         # config declarativa com o marcador ${JWT_SECRET}
├── scripts/
│   └── deploy-kong.ps1               # renderiza o segredo, reinicia o Kong e espera o rollout
└── README.md
```
