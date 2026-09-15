# Roteiro do vídeo da Fase 3 (até 10 minutos)

Vídeo único, sem corte de edição, mostrando a plataforma **FCG (Fiap Cloud Games)** em execução no cluster e os repositórios atualizados. O roteiro é **cronometrado**: cada bloco traz o tempo, os comandos **literais** na ordem em que devem ser digitados e o que precisa **aparecer na tela** para o requisito ficar comprovado.

A seção [Atendimento dos requisitos da Fase 3](../README.md#atendimento-dos-requisitos-da-fase-3) do README tem a mesma ordem deste roteiro — a banca consegue acompanhar os dois lados.

| Tempo | Bloco | Na tela |
|---|---|---|
| 0:00–0:45 | **Abertura e arquitetura** | README aberto na seção *Arquitetura* + diagrama de fluxo de eventos; 1 frase por componente (Kong, 3 APIs, função, Mongo, Redis, Prometheus/Grafana/Loki) |
| 0:45–3:00 | **Gateway: roteamento e segurança** | `kubectl get svc kong` (Service do gateway) → `curl.exe -i http://localhost:8000/api/jogos` (**401**) → `curl.exe -X POST http://localhost:8000/api/auth/login -d '{...}'` (**200** + token) → `curl.exe -H "Authorization: Bearer <token>" .../api/jogos` (**200**) → `kubectl port-forward deploy/kong 8001:8001` + `curl.exe localhost:8001/routes` (mostra as rotas) e a config DB-less com o plugin `jwt`; fechar mostrando que `svc/users-api` é `ClusterIP` (API não exposta) |
| 3:00–5:15 | **Função serverless + log centralizado** | `kubectl get deploy notifications-function` (**0/0**) → `kubectl get pods -l app=notifications-function -w` em um terminal → cadastro pelo gateway (`201`) → **pod sobe em ~15–30 s** → Grafana `FCG - Logs (Loki)` com `[EMAIL ENVIADO] Boas-vindas para ...` (o log aparece **na plataforma**, não no terminal) → pod volta a zero |
| 5:15–7:30 | **Observabilidade (Opção A)** | `scripts/demo-trafego.ps1 -Segundos 90` rodando em um terminal + dashboard `FCG - APIs` em tela cheia (latência p50/p95, RPS, status code, erros, `up`) → Prometheus `Status → Targets` com **3 alvos `up`** → painel *Pagamentos processados por status* mexendo após uma compra |
| 7:30–9:15 | **NoSQL na arquitetura** | `PUT /api/jogos/{id}/avaliacoes` (upsert devolve o documento persistido) → `GET /api/jogos/{id}/avaliacoes` (lista vinda do Mongo) → `kubectl exec deploy/redis -- redis-cli keys 'catalog:*'` + `type`/`ttl` → contadores `cache_hit`/`cache_miss`; explicar **por que** Mongo (documento flexível de avaliação) e **por que** Redis (cache de leitura com TTL 60 s), e que o SQL continua dono do dado transacional |
| 9:15–10:00 | **Repositórios e fechamento** | tabela de repositórios do README (5 repos, incluindo o link da função) + a seção *Atendimento dos requisitos da Fase 3*; fechar com "como subir tudo": `kubectl create secret ...` → `kubectl apply -f k8s/` → `scripts/deploy-kong.ps1` |

**Soma dos tempos: 0:45 + 2:15 + 2:15 + 2:15 + 1:45 + 0:45 = 10:00.** O roteiro cabe no limite de 10 minutos com **zero folga** — se um bloco estourar, aplique a regra de corte do fim do documento (a primeira coisa a cair é o `port-forward` da Admin API do Kong, no bloco 2). Os blocos 3 e 4 têm **espera real** (o pod da função e o scrape de 15 s do Prometheus): narre durante a espera em vez de cortá-la — a espera é a evidência.

## Antes de apertar REC

1. **Preflight verde** — ele é a única garantia do estado inicial:

   ```powershell
   $env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'      # NAO versionada: so na sessao do terminal
   powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1
   ```

   Esperado na última linha: **`TUDO PRONTO PARA GRAVAR`**. Se sair qualquer `[FALHOU]`, corrija antes de gravar — o preflight termina com `exit 1`.

2. **A senha da demonstração vive só na variável de ambiente** `FCG_DEMO_SENHA` (o preflight e o gerador de tráfego leem dela; nenhum dos dois tem senha padrão no arquivo). Ela precisa atender à política do cadastro: **8+ caracteres, com ao menos uma letra, um dígito e um caractere especial**.
3. **Estado inicial esperado:** os 11 pods de infraestrutura/APIs `Running` e `Ready`, o Promtail `Running`, a função de notificações em **0 réplicas** (nenhum pod) e o usuário `demo@fcg.local` já existente, com o catálogo contendo pelo menos **2 jogos** — é o que o preflight deixa pronto.
4. **Três terminais** abertos em `fcg-orchestration` (T1 = comandos, T2 = `kubectl ... -w` / gerador de tráfego, T3 = `port-forward`), todos com `$env:FCG_DEMO_SENHA` definida.
5. **Navegador preparado:** deixe as abas já posicionadas antes de gravar (o Grafana e o Prometheus só respondem depois que os `port-forward` dos blocos 3 e 4 subirem — deixe-os ativos até o fim, sem reabrir):
   - Grafana — `http://localhost:13000` (login `admin` e a senha do Secret `grafana-admin`);
   - Prometheus — `http://localhost:19090/targets`;
   - README do repositório na seção **Atendimento dos requisitos da Fase 3**.

## Regras de segurança de gravação

Estas regras valem para **todo** o vídeo — um descuido aqui vira credencial exposta na entrega:

- **Nunca abrir o `.env`** — nem `cat`, nem `code .env`, nem `Get-Content .env`. Ele existe no host e está no `.gitignore`; no vídeo ele simplesmente não aparece.
- **Nunca `kubectl get secret -o yaml` / `-o json` / `describe secret`.** Só o **nome** do Secret pode aparecer (`kubectl get secrets`), nunca o valor: em Kubernetes o valor é apenas base64, ou seja, ler o Secret é ler a credencial.
- **Nunca mostrar a senha da demonstração.** Nos comandos de cadastro/login ela entra por **`$env:FCG_DEMO_SENHA`**, nunca digitada no terminal. O mesmo vale para a senha do Grafana: ela é digitada no formulário de login (que mascara) e **nunca** vai para a barra de endereço como `admin:senha@localhost:3000`.
- **Nunca imprimir o token.** Login com `-o NUL`/`-w '%{http_code}'`, e para provar que o token veio, mostre o **tamanho** (`$token.Length`), não o valor.
- **Nunca `curl.exe http://localhost:8001/`.** Em modo DB-less a Admin API devolve a configuração declarativa inteira — **incluindo o `secret` HMAC do consumer `fcg-client`, com o qual qualquer um forja um token válido**. Use só `/routes` e `/plugins` (que não trazem segredo).
- **Nunca mostrar o conteúdo do ambiente** (`Get-ChildItem env:`, `kubectl exec ... -- env`, `docker inspect`): `$env:FCG_DEMO_SENHA` apareceria em claro.
- **Ao terminar**, feche os terminais da gravação (`Clear-History` + fechar a janela): o token e a senha viveram só na memória daquela sessão. O preflight e o gerador de tráfego também não deixam senha para trás: os dois montam o corpo do login num arquivo temporário (é o `-d @arquivo` do curl, que evita o JSON inline perder as aspas) e **apagam o temporário no fim** — nenhuma senha vai para o repositório.

## Bloco 1 — 0:00–0:45: Abertura e arquitetura

**Tela:** README (`README.md`) aberto na seção **Arquitetura**, com a tabela de serviços e o diagrama do **Fluxo de eventos** visíveis.

**Narração (uma frase por componente, ~5 s cada):**

- "A plataforma FCG é composta por três microsserviços .NET 8 — UsersAPI, CatalogAPI e PaymentsAPI —, uma função serverless de notificações e um API Gateway Kong na frente de tudo."
- "Todo o acesso externo entra pelo **Kong**; nenhuma API é publicada direto."
- "Os serviços conversam de forma **assíncrona** pelo RabbitMQ: `UserCreatedEvent` da UsersAPI e `OrderPlacedEvent` da CatalogAPI."
- "A notificação é uma **função com escala a zero** (KEDA): sem evento, zero pods."
- "O **MongoDB** guarda as avaliações dos jogos e o **Redis** é o cache de leitura do catálogo — o SQL Server continua dono do dado transacional."
- "A observabilidade é a **Opção A**: Prometheus coletando os três `/metrics`, Grafana com os dashboards e **Loki** centralizando os logs — inclusive os da função, que não tem pod permanente."

**Comandos:** nenhum. (Se quiser um comando de contexto: `kubectl get pods` — 11 pods.)

## Bloco 2 — 0:45–3:00: Gateway: roteamento e segurança

**T1 (raiz de `fcg-orchestration`):**

```powershell
# 1) O Service do gateway: LoadBalancer publicando SO a porta 8000
kubectl get svc kong

# 2) A rota protegida SEM token -> o proprio Kong responde 401 (a API nem e alcancada)
curl.exe -i http://localhost:8000/api/jogos
```

**Na tela:** o `svc/kong` como `LoadBalancer` com `EXTERNAL-IP` `localhost` (porta `8000`) e, no `curl -i`, o **`HTTP/1.1 401 Unauthorized`** com o corpo do Kong.

```powershell
# 3) Login (rota ANONIMA). A senha entra pela variavel de ambiente e NUNCA aparece.
#    O bloco vira uma funcao para ser reaproveitado nos blocos 4 e 5 sem redigitar nada.
function Login-FCG {
    Set-Content -Path "$env:TEMP\fcg-login.json" -Encoding ascii -NoNewline `
        -Value ('{"email":"demo@fcg.local","senha":"' + $env:FCG_DEMO_SENHA + '"}')
    (curl.exe -s -X POST http://localhost:8000/api/auth/login `
        -H "Content-Type: application/json" -d "@$env:TEMP\fcg-login.json" | ConvertFrom-Json).token
}
$token = Login-FCG
'token recebido: ' + $token.Length + ' caracteres'      # prova o login SEM mostrar o token

# 4) A MESMA rota, agora COM o token -> 200
curl.exe -s -o NUL -w 'com-token=%{http_code}\n' -H "Authorization: Bearer $token" http://localhost:8000/api/jogos
```

**Na tela:** o **`200` do login** (o `ConvertFrom-Json` não imprime o token: só a linha `token recebido: ...`) e **`com-token=200`**.

```powershell
# 5) Admin API do Kong: rota /routes e plugin jwt — a prova do roteamento e da autenticacao
kubectl port-forward deploy/kong 8001:8001
# T3 (outro terminal), com o forward ativo:
curl.exe -s http://localhost:8001/routes
curl.exe -s http://localhost:8001/plugins

# 6) As APIs NAO sao expostas: users-api e catalog-api sao ClusterIP, so o Kong e LoadBalancer
kubectl get svc users-api catalog-api kong
```

**Na tela:** as rotas declaradas (`users-signup`, `users-login`, `catalog-jogos`, `catalog-biblioteca`, `users-protegida`), o plugin **`jwt`** com `key_claim_name: iss`, `claims_to_verify: ["exp"]` e `uri_param_names: []`, e a tabela de Services com **`ClusterIP`** em `users-api`/`catalog-api` contra **`LoadBalancer`** em `kong`.

> **Não** rode `curl.exe http://localhost:8001/`: em DB-less ele devolve a config inteira, **com o segredo HMAC do consumer**. É a regra de segurança mais fácil de violar sem perceber.
>
> O `port-forward` da Admin API é sobre `deploy/kong` (e não `svc/kong`): a Admin API escuta **só no loopback do pod** e **não** é publicada no Service — `svc/kong` só tem a porta `8000`.

**Narração:** "o Kong valida o JWT **no próprio gateway**: sem token a requisição recebe 401 e nunca chega à API; o `400` do login é de e-mail inexistente, e o `401` é senha errada — quem responde isso é a UsersAPI".

## Bloco 3 — 3:00–5:15: Função serverless + log centralizado

**T1:**

```powershell
# 1) Estado de repouso: 0 de 0 replicas e NENHUM pod — a escala a zero
kubectl get deploy notifications-function
kubectl get pods -l app=notifications-function
```

**T2 (deixe rodando durante o cadastro):**

```powershell
kubectl get pods -l app=notifications-function -w
```

**T1 — o cadastro que acorda a função (e-mail NOVO a cada gravação):**

```powershell
$email = 'video' + (Get-Date -Format 'HHmmss') + '@fcg.com'
Set-Content -Path "$env:TEMP\fcg-cadastro.json" -Encoding ascii -NoNewline `
    -Value ('{"nome":"Espectador Video","email":"' + $email + '","senha":"' + $env:FCG_DEMO_SENHA + '"}')
curl.exe -s -o NUL -w 'cadastro=%{http_code}\n' -X POST http://localhost:8000/api/usuarios `
    -H "Content-Type: application/json" -d "@$env:TEMP\fcg-cadastro.json"
'email do cadastro: ' + $email
```

**Na tela:** `cadastro=201` e, no T2, o pod `notifications-function-...` **aparecendo** e indo para `Running` — o KEDA consulta a fila a cada `pollingInterval` de **15 s**, e o tempo medido ponta a ponta nesta fase foi de **20 a 31 s** (é o número que o README registra): o pod aparece **em ~15–30 s**, não instantaneamente.

**T3 — o log tem de aparecer na PLATAFORMA, não no terminal:**

```powershell
kubectl port-forward svc/grafana 13000:3000
```

No navegador: `http://localhost:13000` → login `admin` → **Dashboards → FCG - Logs (Loki)** → painel `{app="notifications-function"}` → período **Last 5 minutes** → a linha:

```
[EMAIL ENVIADO] Boas-vindas para Espectador Video - video<HHmmss>@fcg.com
```

**T1 — a volta a zero (fecha o ciclo da escala a zero):**

```powershell
# o cooldown do KEDA e de 30s: espere o pod terminar e a contagem voltar a zero
kubectl get pods -l app=notifications-function
kubectl get deploy notifications-function
```

**Na tela:** o `-w` do T2 mostrando o pod **`Terminating`** → nenhum recurso; e de volta o `0/0`. No Grafana, o log **continua lá** — o pod que o escreveu já não existe, e é exatamente para isso que o Loki existe (`kubectl logs` não sobrevive ao pod).

> **A espera de ~15 s pela função não é travamento: ela É a prova da escala a zero.** `kubectl logs` no caminho contrário (mostrar o log pelo terminal) provaria menos: o pod que registrou o `[EMAIL ENVIADO]` já não existe quando alguém vai ler, e o log tem de estar na plataforma centralizada. Narre a espera: "o KEDA consulta a fila a cada 15 s, e é por isso que o pod leva esse tempo para aparecer".

## Bloco 4 — 5:15–7:30: Observabilidade (Opção A)

**T2 — tráfego autenticado contínuo (90 s), no mesmo terminal do gerador:**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/demo-trafego.ps1 -Segundos 90
```

**T3 — os painéis:**

```powershell
kubectl port-forward svc/grafana 13000:3000
kubectl port-forward svc/prometheus 19090:9090
```

**No navegador, nesta ordem:**

1. Grafana → `http://localhost:13000/d/fcg-apis/fcg-apis?kiosk&refresh=5s&from=now-5m` (**tela cheia**, sem menus) — com o gerador rodando, as séries **se movem em até 15 s** (o scrape é de 15 s): latência **p50/p95**, **requisições por segundo**, **requisições por status code**, **taxa de erros 5xx** e o painel de coleta (**`up`**).
2. Prometheus → `http://localhost:19090/targets` (**Status → Targets**): os **três alvos do job `fcg-apis`** — `users-api:80`, `catalog-api:80` e `payments-api:80` — com **`health: up`** (além do próprio Prometheus, no job `prometheus`).
3. Volte ao Grafana e mova o painel **Pagamentos processados por status** com uma **compra** (T1):

```powershell
$token  = Login-FCG
$gameId = ((curl.exe -s -H "Authorization: Bearer $token" http://localhost:8000/api/jogos | ConvertFrom-Json) | Select-Object -First 1).id

# O userId vem do claim Id do TOKEN (o corpo com usuarioId e ignorado, por contrato do endpoint):
$p = ($token -split '\.')[1].Replace('-','+').Replace('_','/')
switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
$userId = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json).Id

Set-Content -Path "$env:TEMP\fcg-compra.json" -Encoding ascii -NoNewline `
    -Value ('{"userId":"' + $userId + '","gameId":"' + $gameId + '"}')
curl.exe -s -w 'compra=%{http_code}\n' -X POST ("http://localhost:8000/api/jogos/" + $gameId + "/comprar") `
    -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d "@$env:TEMP\fcg-compra.json"
```

**Na tela:** `compra=202` (aceita e assíncrona) e, em até ~30 s (scrape de 15 s + processamento), as séries **`Approved`/`Rejected`** do painel *Pagamentos processados por status* subindo.

**Narração — o ponto que costuma ser mal entendido:** "o `payments-api` **não recebe requisição nenhuma do gateway**: ele é consumidor de fila. Quem move o painel dele é o **fluxo de eventos** — cada compra publica `OrderPlacedEvent` e incrementa o contador de negócio `fcg_payments_processados_total`. E os painéis de tráfego **excluem as probes `/health`**: o número que aparece é tráfego de negócio, não probe."

## Bloco 5 — 7:30–9:15: NoSQL na arquitetura

**T1 — avaliação no Mongo (o `PUT` é upsert):**

```powershell
$token = Login-FCG      # se este terminal for novo; senao reaproveite o $token da sessao
                        # o $gameId vem do bloco 4: mantenha o mesmo terminal T1 de ponta a ponta
Set-Content -Path "$env:TEMP\fcg-avaliacao.json" -Encoding ascii -NoNewline `
    -Value '{"nota":5,"comentario":"Jogo muito bom","tags":["acao","video"]}'
curl.exe -s -w 'avaliacao=%{http_code}\n' -X PUT ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes") `
    -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d "@$env:TEMP\fcg-avaliacao.json"

# A lista e o resumo vem do Mongo (nao ha tabela de avaliacao no SQL Server):
curl.exe -s -H "Authorization: Bearer $token" ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes")
curl.exe -s -H "Authorization: Bearer $token" ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes/resumo")
```

**Na tela:** o documento persistido devolvido pelo `PUT` (com `gameId`, `usuarioId`, `nota`, `comentario`, `tags`, `dataAtualizacao`), a lista do `GET` e o resumo `{"total":1,"notaMedia":5}`. O `usuarioId` **não** veio do corpo: veio do claim `Id` do token. O `PUT` é **upsert**, então o status é `201` na primeira avaliação daquele usuário naquele jogo e `200` ao atualizar — **o preflight já deixa uma avaliação do usuário de demonstração**, então na gravação o esperado é `200` (e isso é a prova do upsert, não um erro).

**T1 — o Redis como cache de leitura** (leia a listagem **imediatamente antes**: o TTL é de **60 s**):

```powershell
curl.exe -s -o NUL -w 'catalogo=%{http_code}\n' -H "Authorization: Bearer $token" http://localhost:8000/api/jogos

kubectl exec deploy/redis -- redis-cli keys 'catalog:*'
kubectl exec deploy/redis -- redis-cli type catalog:games:all   # hash (o IDistributedCache grava HSET, nao SET)
kubectl exec deploy/redis -- redis-cli ttl catalog:games:all    # ate 60
kubectl exec deploy/redis -- redis-cli hlen catalog:games:all   # 3 (data, absexp, sldexp)

# Cache hit/miss vistos pelo proprio Prometheus (a serie tem o nome cru, sem sufixo _total):
kubectl get --raw '/api/v1/namespaces/default/services/catalog-api:80/proxy/metrics' | Select-String '^cache_(hit|miss)'
```

**Na tela:** `catalogo=200`, as chaves `catalog:games:all` (e `catalog:game:{id}` quando o `GET` por id é exercitado pelo gerador), `type` = **`hash`** — `GET` na chave devolveria `WRONGTYPE`, porque o `IDistributedCache` grava hash, não string —, `ttl` ≤ 60 e as linhas `cache_hit`/`cache_miss` com valores crescentes.

**Narração — o "por quê" de cada escolha (é o requisito, não detalhe):**

- **Por que MongoDB:** a avaliação é **dado gerado pelo usuário, com formato variável** — `nota` obrigatória, `comentario` opcional e `tags[]` livre. Em modelo relacional isso vira coluna anulável mais tabela de tags, com junção a cada leitura, sem ganho de integridade; a leitura que importa é **agregada** (total e média) e a coleção é **um documento por avaliação**, com índice único `(gameId, userId)` criado no boot da API.
- **Por que Redis:** `GET /api/jogos` devolve o **catálogo inteiro** sem paginação e é a consulta mais repetida — o lugar onde o cache rende mais. É **cache, não banco**: não tem PVC porque tudo nele é reconstruível do SQL, a degradação é **graciosa** (se o Redis cair, a leitura segue para o SQL) e as chaves têm **TTL de 60 s**, com invalidação explícita no `POST`/`DELETE` de jogo.
- **O SQL continua dono do dado transacional:** usuários, catálogo e biblioteca seguem no SQL Server. O Mongo serve **apenas** as rotas `/avaliacoes` e o Redis **apenas** a leitura do catálogo — nenhum dado foi migrado para fora do SQL.

## Bloco 6 — 9:15–10:00: Repositórios e fechamento

**Tela 1 — os repositórios da entrega** (tabela da seção *Arquitetura* do README, mais este repositório de orquestração):

| # | Repositório | Papel |
|---|---|---|
| 1 | [fcg-orchestration](https://github.com/gustavoaa-dev/fcg-orchestration) | Infraestrutura: manifestos Kubernetes, Kong, observabilidade e este roteiro |
| 2 | [fcg-users-api](https://github.com/gustavoaa-dev/fcg-users-api) | Cadastro e autenticação (emissor do JWT) |
| 3 | [fcg-catalog-api](https://github.com/gustavoaa-dev/fcg-catalog-api) | Catálogo, biblioteca, avaliações no Mongo e cache no Redis |
| 4 | [fcg-payments-api](https://github.com/gustavoaa-dev/fcg-payments-api) | Consumidor de pagamento + contador de negócio do painel |
| 5 | [fcg-notifications-function](https://github.com/gustavoaa-dev/fcg-notifications-function) | Função serverless com escala a zero (Terraform + KEDA) |

**Tela 2 — README na seção [Atendimento dos requisitos da Fase 3](../README.md#atendimento-dos-requisitos-da-fase-3):** a tabela requisito → onde está → como comprovar, na mesma ordem do vídeo.

**T1 — "como subir tudo do zero" (mostre os comandos, não os valores):**

```powershell
# 1) Secrets (os valores sao SEUS; nada de credencial no repositorio):
kubectl create secret generic sqlserver-secret --from-literal=sa-password='<senha-do-sa>' --dry-run=client -o yaml | kubectl apply -f -
#    ... (os Secrets das APIs, do Grafana, do Mongo e do RabbitMQ — secao "Segredos" do README)

# 2) Manifestos: infraestrutura, APIs, Mongo, Redis, Prometheus, Grafana, Loki e Promtail
kubectl apply -f k8s/

# 3) Gateway: renderiza a chave JWT do Secret, recria o kong-declarative-config e espera o rollout
powershell -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1
```

**Narração final:** "nenhuma credencial é versionada: os manifestos guardam só o **nome** dos Secrets; a configuração do Kong é um **template** com o marcador `${JWT_SECRET}`, renderizado pelo script a partir do que já está no cluster. A função é implantada pelo **Terraform do repositório dela** — e o `terraform plan` com a função em zero devolve `No changes`: o Terraform não briga com o KEDA pelo número de réplicas."

**Encerramento:** pare os `port-forward` (Ctrl+C) e feche as janelas.

## Se estourar o tempo (regra de corte)

Corte **nesta ordem**, e só até caber em 10:00:

1. **primeiro** o `port-forward` da Admin API do Kong com `/routes` e `/plugins` (bloco 2) — o 401 sem token e o 200 com token já provam o gateway e a autenticação;
2. depois o `GET /api/jogos/{id}/avaliacoes/resumo` e o `hlen` (bloco 5) — o documento do `PUT`, a lista do `GET` e o `keys`/`ttl` do Redis já provam a persistência poliglota e o cache;
3. depois a segunda passada em `Status → Targets` (bloco 4), mantendo o dashboard `FCG - APIs` em tela e o painel de pagamentos mexendo.

**Não corte:** o cadastro que acorda a função, a espera de ~15–30 s, o log da função **no Grafana** e a volta a zero — esse conjunto é o requisito de **serverless com escala a zero**, e é o bloco que mais depende de tempo real. Também não corte a seção *Atendimento dos requisitos da Fase 3* no fim: é o mapa que a banca usa para conferir o enunciado.

## Apoio: o que o preflight garante para esta gravação

`scripts/preflight-fase3.ps1` roda **antes** de gravar e falha (`exit 1`) se qualquer peça do vídeo não estiver no ar: os 11 pods e o promtail, os **4 PVCs `Bound`**, o gateway (`401` sem token e `200` com token), os três alvos do job `fcg-apis` no Prometheus, o Loki `ready` e com log recente da stack (se ainda não houver log da **função** nas últimas 24 h, ele **avisa** em vez de reprovar — o cadastro do bloco 3 gera esse log ao vivo), o datasource e os dois dashboards do Grafana, as **três filas `notifications-*`** com o `ScaledObject Ready=True` (sem fila o KEDA cai em `TriggerError` e a **função simplesmente não sobe** — falha silenciosa que só apareceria na gravação), o Redis com as chaves `catalog:*`, o Mongo respondendo e — o mais importante — o **usuário e os jogos de demonstração**, além da **função em 0 réplicas** no estado inicial. Ele também **exercita os comandos que só aparecem no vídeo**: as séries dos painéis em `/metrics` dos três serviços (pelo proxy do `kubectl`), a **compra** (`202`) e o `PUT`/`GET` de **avaliação** (upsert) — assim nenhum bloco do roteiro leva um comando que nunca rodou. `scripts/demo-trafego.ps1 -Segundos 90` é o gerador do bloco 4; os dois leem a senha de `$env:FCG_DEMO_SENHA` e **não** têm senha padrão no arquivo.
