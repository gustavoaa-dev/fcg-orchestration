# Roteiro do vídeo da Fase 3 (até 10 minutos)

Vídeo único, sem corte de edição, mostrando a plataforma **FCG (Fiap Cloud Games)** em execução no cluster e os repositórios atualizados. O roteiro é **cronometrado**: cada bloco traz o tempo, os comandos **literais** na ordem em que devem ser digitados e o que precisa **aparecer na tela** para o requisito ficar comprovado.

A seção [Atendimento dos requisitos da Fase 3](../README.md#atendimento-dos-requisitos-da-fase-3) do README tem a mesma ordem deste roteiro — a banca consegue acompanhar os dois lados.

| Tempo | Bloco | Na tela |
|---|---|---|
| 0:00–0:35 | **Abertura e arquitetura** | README aberto na seção *Arquitetura* + diagrama de fluxo de eventos; 1 frase curta por componente (Kong, 3 APIs, função, Mongo, Redis, Prometheus/Grafana/Loki) |
| 0:35–2:50 | **Gateway: roteamento e segurança** | `kubectl get -n default svc kong` (Service do gateway) → `curl.exe -i http://localhost:8000/api/jogos` (**401**) → `curl.exe -X POST http://localhost:8000/api/auth/login -d '{...}'` (**200** + token) → `curl.exe -H "Authorization: Bearer <token>" .../api/jogos` (**200**) → `kubectl port-forward -n default deploy/kong 8001:8001` + `curl.exe localhost:8001/routes` (mostra as rotas) e a config DB-less com o plugin `jwt`; fechar mostrando que `svc/users-api` é `ClusterIP` (API não exposta) |
| 2:50–5:05 | **Função serverless + log centralizado** | `kubectl get -n default deploy notifications-function` (**0/0**) → `kubectl get -n default pods -l app=notifications-function -w` em um terminal → cadastro pelo gateway (`201`) → **pod sobe em ~15–30 s** → Grafana `FCG - Logs (Loki)` com `[EMAIL ENVIADO] Boas-vindas para ...` (o log aparece **na plataforma**, não no terminal) → pod volta a zero |
| 5:05–7:20 | **Observabilidade (Opção A)** | `scripts/demo-trafego.ps1 -Segundos 90` rodando em um terminal + dashboard `FCG - APIs` em tela cheia (latência p50/p95, RPS, status code, erros, `up`) → Prometheus `Status → Targets` com **3 alvos `up`** → painel *Pagamentos processados por status* mexendo após uma compra |
| 7:20–8:55 | **NoSQL na arquitetura** | `PUT /api/jogos/{id}/avaliacoes` (upsert devolve o documento persistido) → `GET /api/jogos/{id}/avaliacoes` (lista vinda do Mongo) → `kubectl exec -n default deploy/redis -- redis-cli keys 'catalog:*'` + `type`/`ttl` → contadores `cache_hit`/`cache_miss`; **uma frase por banco** sobre o *porquê* (Mongo = documento de avaliação; Redis = cache de leitura com TTL 60 s; o SQL continua dono do transacional — o README detalha) |
| 8:55–9:30 | **Repositórios e fechamento** | tabela de repositórios do README (5 repos, incluindo o link da função) + a seção *Atendimento dos requisitos da Fase 3*; fechar com "como subir tudo": `kubectl create -n default secret ...` → `kubectl apply -n default -f k8s/` → `scripts/deploy-kong.ps1` |

**Soma dos tempos: 0:35 + 2:15 + 2:15 + 2:15 + 1:35 + 0:35 = 9:30.** O **alvo é 9:30 de conteúdo** e o **teto duro é 10:00** — o enunciado diz "até 10 minutos", então um vídeo de 10:01 descumpre o requisito: os **~30 s de folga** entre o alvo e o teto são o que absorve a narração e as esperas reais. Se ainda assim estiver passando do alvo, aplique a **regra de corte** do fim do documento (rede de segurança; a primeira coisa a cair é o `port-forward` da Admin API do Kong, no bloco 2) — e, em qualquer cenário, **feche antes de 10:00**. Os blocos 3 e 4 têm **espera real** (o pod da função e o scrape de 15 s do Prometheus): narre durante a espera em vez de cortá-la — a espera é a evidência.

> **Namespace, em todo o roteiro:** cada comando `kubectl` leva **`-n default`** (o namespace onde a plataforma roda), e o caminho de proxy do kubectl carrega o namespace **dentro do próprio caminho** (`kubectl get --raw '/api/v1/namespaces/default/services/...'`). As duas formas apontam para o mesmo lugar — nada aqui depende do namespace do contexto, que pode estar em outro namespace sem que você perceba.

## Antes de apertar REC

1. **Preflight verde** — ele é a única garantia do estado inicial:

   ```powershell
   $env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'      # NAO versionada: so na sessao do terminal
   powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1
   ```

   Esperado na última linha: **`TUDO PRONTO PARA GRAVAR`**. Se sair qualquer `[FALHOU]`, corrija antes de gravar — o preflight termina com `exit 1`.

   No resumo ele imprime **o jogo que o bloco 4 deve comprar** (o primeiro do catálogo que o usuário demo **não** possui — o catálogo volta ordenado por nome e a biblioteca cresce a cada rodada, então "o primeiro id" não serve):

   ```
   jogo do bloco 4 (compra) = <nome> (<id>)  -- e o mesmo id serve para o bloco 5 (avaliacoes)
   ```

   Guarde esse id na sessão **antes de apertar REC** (o bloco 4 lê `$env:FCG_DEMO_JOGO`; assim nenhum GUID é digitado na gravação):

   ```powershell
   $env:FCG_DEMO_JOGO = '<id-impresso-na-linha-jogo-do-bloco-4>'
   ```

2. **A senha da demonstração vive só na variável de ambiente** `FCG_DEMO_SENHA` (o preflight e o gerador de tráfego leem dela; nenhum dos dois tem senha padrão no arquivo). Ela precisa atender à política do cadastro: **8+ caracteres, com ao menos uma letra, um dígito e um caractere especial**.
3. **Estado inicial esperado:** os 11 pods de infraestrutura/APIs `Running` e `Ready`, o Promtail `Running`, a função de notificações em **0 réplicas** (nenhum pod) e o usuário `demo@fcg.local` já existente, com o catálogo contendo pelo menos **3 jogos** (o mínimo que garante um jogo livre para a compra do bloco 4 mesmo depois de rodadas anteriores) — é o que o preflight deixa pronto.
4. **Três terminais** abertos em `fcg-orchestration` (T1 = comandos, T2 = `kubectl get -n default ... -w` / gerador de tráfego, T3 = `port-forward`), todos com `$env:FCG_DEMO_SENHA` e `$env:FCG_DEMO_JOGO` definidas. O **diretório de sessão** que guarda os corpos de requisição nasce no passo 0 do bloco 2 e é apagado no fechamento (bloco 6) — mantenha o T1 do começo ao fim, ou repita o passo 0.
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
- **Ao terminar, apague os temporários da sessão** (bloco 6, "higiene da sessão"): `Remove-Item $dirDemo -Recurse -Force` remove o diretório do passo 0 do bloco 2, que é o **único** lugar em que o roteiro grava corpo de requisição — e o corpo do login carrega a senha. Depois feche os terminais da gravação (`Clear-History` + fechar a janela): o token e a senha viveram só na memória daquela sessão. **Os dois scripts de apoio fazem a mesma limpeza**: o `preflight-fase3.ps1` e o `demo-trafego.ps1` montam o corpo do login num diretório temporário próprio (é o `-d @arquivo` do curl, que evita o JSON inline perder as aspas) e **removem o diretório inteiro no fim**, em todos os caminhos de saída (inclusive quando falham). Ou seja: nenhum artefato com senha — nem o do roteiro, nem o dos scripts — sobrevive à gravação.

## Bloco 1 — 0:00–0:35: Abertura e arquitetura

**Tela:** README (`README.md`) aberto na seção **Arquitetura**, com a tabela de serviços e o diagrama do **Fluxo de eventos** visíveis.

**Narração (uma frase curta por componente, ~4 s cada — o bloco inteiro tem 35 s):**

- "A plataforma FCG é composta por três microsserviços .NET 8 — UsersAPI, CatalogAPI e PaymentsAPI —, uma função serverless de notificações e um API Gateway Kong na frente de tudo."
- "Todo o acesso externo entra pelo **Kong**; nenhuma API é publicada direto."
- "Os serviços conversam de forma **assíncrona** pelo RabbitMQ: `UserCreatedEvent` da UsersAPI e `OrderPlacedEvent` da CatalogAPI."
- "A notificação é uma **função com escala a zero** (KEDA): sem evento, zero pods."
- "O **MongoDB** guarda as avaliações dos jogos e o **Redis** é o cache de leitura do catálogo — o SQL Server continua dono do dado transacional."
- "A observabilidade é a **Opção A**: Prometheus coletando os três `/metrics`, Grafana com os dashboards e **Loki** centralizando os logs — inclusive os da função, que não tem pod permanente."

**Comandos:** nenhum. (Se quiser um comando de contexto: `kubectl get -n default pods` — 11 pods.)

## Bloco 2 — 0:35–2:50: Gateway: roteamento e segurança

**T1 (raiz de `fcg-orchestration`):**

```powershell
# 0) DIRETORIO DE SESSAO: todo corpo de requisicao (o do login carrega a senha) e gravado SO aqui
#    dentro, e o diretorio inteiro e removido no fechamento (bloco 6). Sem isso sobraria senha em
#    claro no %TEMP% da maquina de apresentacao.
$dirDemo = Join-Path $env:TEMP ('fcg-demo-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Path $dirDemo -Force | Out-Null

# 1) O Service do gateway: LoadBalancer publicando SO a porta 8000
kubectl get -n default svc kong

# 2) A rota protegida SEM token -> o proprio Kong responde 401 (a API nem e alcancada)
curl.exe -i http://localhost:8000/api/jogos
```

**Na tela:** o `svc/kong` como `LoadBalancer` com `EXTERNAL-IP` `localhost` (porta `8000`) e, no `curl -i`, o **`HTTP/1.1 401 Unauthorized`** com o corpo do Kong.

```powershell
# 3) Login (rota ANONIMA). A senha entra pela variavel de ambiente e NUNCA aparece.
#    O bloco vira uma funcao para ser reaproveitado nos blocos 4 e 5 sem redigitar nada.
function Login-FCG {
    Set-Content -Path (Join-Path $dirDemo 'login.json') -Encoding ascii -NoNewline `
        -Value ('{"email":"demo@fcg.local","senha":"' + $env:FCG_DEMO_SENHA + '"}')
    (curl.exe -s -X POST http://localhost:8000/api/auth/login `
        -H "Content-Type: application/json" -d ('@' + (Join-Path $dirDemo 'login.json')) | ConvertFrom-Json).token
}
$token = Login-FCG
'token recebido: ' + $token.Length + ' caracteres'      # prova o login SEM mostrar o token

# 4) A MESMA rota, agora COM o token -> 200
curl.exe -s -o NUL -w 'com-token=%{http_code}\n' -H "Authorization: Bearer $token" http://localhost:8000/api/jogos
```

**Na tela:** o **`200` do login** (o `ConvertFrom-Json` não imprime o token: só a linha `token recebido: ...`) e **`com-token=200`**.

> O `$dirDemo` do passo 0 é o **único** lugar onde o roteiro grava arquivo, e ele é apagado no fechamento (bloco 6, "higiene da sessão") — se este terminal for novo, repita o passo 0 antes de chamar `Login-FCG` (a função lê `$dirDemo` da sessão).

```powershell
# 5) Admin API do Kong: rota /routes e plugin jwt — a prova do roteamento e da autenticacao
kubectl port-forward -n default deploy/kong 8001:8001
# T3 (outro terminal), com o forward ativo:
curl.exe -s http://localhost:8001/routes
curl.exe -s http://localhost:8001/plugins

# 6) As APIs NAO sao expostas: users-api e catalog-api sao ClusterIP, so o Kong e LoadBalancer
kubectl get -n default svc users-api catalog-api kong
```

**Na tela:** as rotas declaradas (`users-signup`, `users-login`, `catalog-jogos`, `catalog-biblioteca`, `users-protegida`), o plugin **`jwt`** com `key_claim_name: iss`, `claims_to_verify: ["exp"]` e `uri_param_names: []`, e a tabela de Services com **`ClusterIP`** em `users-api`/`catalog-api` contra **`LoadBalancer`** em `kong`.

> **Não** rode `curl.exe http://localhost:8001/`: em DB-less ele devolve a config inteira, **com o segredo HMAC do consumer**. É a regra de segurança mais fácil de violar sem perceber.
>
> O `port-forward` da Admin API é sobre `deploy/kong` (e não `svc/kong`): a Admin API escuta **só no loopback do pod** e **não** é publicada no Service — `svc/kong` só tem a porta `8000`.

**Narração:** "o Kong valida o JWT **no próprio gateway**: sem token a requisição recebe 401 e nunca chega à API; o `400` do login é de e-mail inexistente, e o `401` é senha errada — quem responde isso é a UsersAPI".

## Bloco 3 — 2:50–5:05: Função serverless + log centralizado

**T1:**

```powershell
# 1) Estado de repouso: 0 de 0 replicas e NENHUM pod — a escala a zero
kubectl get -n default deploy notifications-function
kubectl get -n default pods -l app=notifications-function
```

**T2 (deixe rodando durante o cadastro):**

```powershell
kubectl get -n default pods -l app=notifications-function -w
```

**T1 — o cadastro que acorda a função (e-mail NOVO a cada gravação):**

```powershell
$email = 'video' + (Get-Date -Format 'HHmmss') + '@fcg.com'
Set-Content -Path (Join-Path $dirDemo 'cadastro.json') -Encoding ascii -NoNewline `
    -Value ('{"nome":"Espectador Video","email":"' + $email + '","senha":"' + $env:FCG_DEMO_SENHA + '"}')
curl.exe -s -o NUL -w 'cadastro=%{http_code}\n' -X POST http://localhost:8000/api/usuarios `
    -H "Content-Type: application/json" -d ('@' + (Join-Path $dirDemo 'cadastro.json'))
'email do cadastro: ' + $email
```

**Na tela:** `cadastro=201` e, no T2, o pod `notifications-function-...` **aparecendo** e indo para `Running` — o KEDA consulta a fila a cada `pollingInterval` de **15 s**, e o tempo medido ponta a ponta nesta fase foi de **20 a 31 s** (é o número que o README registra): o pod aparece **em ~15–30 s**, não instantaneamente.

**T3 — o log tem de aparecer na PLATAFORMA, não no terminal:**

```powershell
kubectl port-forward -n default svc/grafana 13000:3000
```

No navegador: `http://localhost:13000` → login `admin` → **Dashboards → FCG - Logs (Loki)** → painel `{app="notifications-function"}` → período **Last 5 minutes** → a linha:

```
[EMAIL ENVIADO] Boas-vindas para Espectador Video - video<HHmmss>@fcg.com
```

**T1 — a volta a zero (fecha o ciclo da escala a zero):**

```powershell
# o cooldown do KEDA e de 30s: espere o pod terminar e a contagem voltar a zero
kubectl get -n default pods -l app=notifications-function
kubectl get -n default deploy notifications-function
```

**Na tela:** o `-w` do T2 mostrando o pod **`Terminating`** → nenhum recurso; e de volta o `0/0`. No Grafana, o log **continua lá** — o pod que o escreveu já não existe, e é exatamente para isso que o Loki existe (`kubectl logs -n default` não sobrevive ao pod).

> **A espera de ~15–30 s pela função não é travamento: ela É a prova da escala a zero.** `kubectl logs -n default` no caminho contrário (mostrar o log pelo terminal) provaria menos: o pod que registrou o `[EMAIL ENVIADO]` já não existe quando alguém vai ler, e o log tem de estar na plataforma centralizada. Narre a espera: "o KEDA consulta a fila a cada 15 s, e é por isso que o pod leva esse tempo para aparecer".

## Bloco 4 — 5:05–7:20: Observabilidade (Opção A)

**T2 — tráfego autenticado contínuo (90 s), no mesmo terminal do gerador:**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/demo-trafego.ps1 -Segundos 90
```

**T3 — os painéis:**

```powershell
kubectl port-forward -n default svc/grafana 13000:3000
kubectl port-forward -n default svc/prometheus 19090:9090
```

**No navegador, nesta ordem:**

1. Grafana → `http://localhost:13000/d/fcg-apis/fcg-apis?kiosk&refresh=5s&from=now-5m` (**tela cheia**, sem menus) — com o gerador rodando, as séries **se movem em até 15 s** (o scrape é de 15 s): latência **p50/p95**, **requisições por segundo**, **requisições por status code**, **taxa de erros 5xx** e o painel de coleta (**`up`**).
2. Prometheus → `http://localhost:19090/targets` (**Status → Targets**): os **três alvos do job `fcg-apis`** — `users-api:80`, `catalog-api:80` e `payments-api:80` — com **`health: up`** (além do próprio Prometheus, no job `prometheus`).
3. Volte ao Grafana e mova o painel **Pagamentos processados por status** com uma **compra** (T1):

```powershell
$token  = Login-FCG
# O JOGO DO BLOCO 4 nao e "o primeiro do catalogo": e o que o preflight IMPRIMIU na linha
# "jogo do bloco 4 (compra) = <nome> (<id>)" (o catalogo volta ordenado por NOME e a biblioteca do
# usuario demo cresce a cada rodada -- comprar um jogo que ele ja possui devolve 400 e o painel de
# pagamentos nao se move). O id foi guardado na variavel de ambiente antes de apertar REC:
$gameId = $env:FCG_DEMO_JOGO

# O userId vem do claim Id do TOKEN (o corpo com usuarioId e ignorado, por contrato do endpoint):
$p = ($token -split '\.')[1].Replace('-','+').Replace('_','/')
switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
$userId = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json).Id

Set-Content -Path (Join-Path $dirDemo 'compra.json') -Encoding ascii -NoNewline `
    -Value ('{"userId":"' + $userId + '","gameId":"' + $gameId + '"}')
curl.exe -s -w 'compra=%{http_code}\n' -X POST ("http://localhost:8000/api/jogos/" + $gameId + "/comprar") `
    -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d ('@' + (Join-Path $dirDemo 'compra.json'))
```

**Na tela:** `compra=202` (aceita e assíncrona) e, em até ~30 s (scrape de 15 s + processamento), as séries **`Approved`/`Rejected`** do painel *Pagamentos processados por status* subindo. Se vier **`400`**, o jogo já estava na biblioteca do usuário: **pare e rode o preflight de novo** — ele reescolhe um jogo livre e imprime a linha `jogo do bloco 4` — em vez de gravar um bloco sem evidência.

**Narração — o ponto que costuma ser mal entendido:** "o `payments-api` **não recebe requisição nenhuma do gateway**: ele é consumidor de fila. Quem move o painel dele é o **fluxo de eventos** — cada compra publica `OrderPlacedEvent` e incrementa o contador de negócio `fcg_payments_processados_total`. E os painéis de tráfego **excluem as probes `/health`**: o número que aparece é tráfego de negócio, não probe."

## Bloco 5 — 7:20–8:55: NoSQL na arquitetura

**T1 — avaliação no Mongo (o `PUT` é upsert):**

```powershell
$token = Login-FCG      # se este terminal for novo; senao reaproveite o $token da sessao
                        # o $gameId vem do bloco 4: mantenha o mesmo terminal T1 de ponta a ponta
Set-Content -Path (Join-Path $dirDemo 'avaliacao.json') -Encoding ascii -NoNewline `
    -Value '{"nota":5,"comentario":"Jogo muito bom","tags":["acao","video"]}'
curl.exe -s -w 'avaliacao=%{http_code}\n' -X PUT ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes") `
    -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d ('@' + (Join-Path $dirDemo 'avaliacao.json'))

# A lista e o resumo vem do Mongo (nao ha tabela de avaliacao no SQL Server):
curl.exe -s -H "Authorization: Bearer $token" ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes")
curl.exe -s -H "Authorization: Bearer $token" ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes/resumo")
```

**Na tela:** o documento persistido devolvido pelo `PUT` (com `gameId`, `usuarioId`, `nota`, `comentario`, `tags`, `dataAtualizacao`), a lista do `GET` e o resumo `{"total":1,"notaMedia":5}`. O `usuarioId` **não** veio do corpo: veio do claim `Id` do token. O `PUT` é **upsert**, então o status é `201` na primeira avaliação daquele usuário naquele jogo e `200` ao atualizar — **o preflight já deixa uma avaliação do usuário de demonstração**, então na gravação o esperado é `200` (e isso é a prova do upsert, não um erro).

**T1 — o Redis como cache de leitura** (leia a listagem **imediatamente antes**: o TTL é de **60 s**):

```powershell
curl.exe -s -o NUL -w 'catalogo=%{http_code}\n' -H "Authorization: Bearer $token" http://localhost:8000/api/jogos

kubectl exec -n default deploy/redis -- redis-cli keys 'catalog:*'
kubectl exec -n default deploy/redis -- redis-cli type catalog:games:all   # hash (o IDistributedCache grava HSET, nao SET)
kubectl exec -n default deploy/redis -- redis-cli ttl catalog:games:all    # ate 60
kubectl exec -n default deploy/redis -- redis-cli hlen catalog:games:all   # 3 (data, absexp, sldexp)

# Cache hit/miss vistos pelo proprio Prometheus (a serie tem o nome cru, sem sufixo _total):
kubectl get -n default --raw '/api/v1/namespaces/default/services/catalog-api:80/proxy/metrics' | Select-String '^cache_(hit|miss)'
```

**Na tela:** `catalogo=200`, as chaves `catalog:games:all` (e `catalog:game:{id}` quando o `GET` por id é exercitado pelo gerador), `type` = **`hash`** — `GET` na chave devolveria `WRONGTYPE`, porque o `IDistributedCache` grava hash, não string —, `ttl` ≤ 60 e as linhas `cache_hit`/`cache_miss` com valores crescentes.

**Narração — o "por quê" de cada escolha (é o requisito, não detalhe). Com 1:35 de bloco, o alvo é UMA frase por banco; o resto é enfeite e o README já detalha:**

- **Por que MongoDB (1 frase):** a avaliação é dado do usuário com formato variável — `nota` obrigatória, `comentario` opcional e `tags[]` livre —, e no relacional isso viraria coluna anulável mais tabela de tags, com junção a cada leitura; a leitura que importa é **agregada** (total e média).
- **Por que Redis (1 frase):** `GET /api/jogos` devolve o **catálogo inteiro** sem paginação e é a consulta mais repetida; é **cache, não banco** — não tem PVC porque tudo nele é reconstruível do SQL e a degradação é **graciosa**.
- **O SQL continua dono do dado transacional (1 frase):** usuários, catálogo e biblioteca seguem no SQL Server; o Mongo serve **apenas** as rotas `/avaliacoes` e o Redis **apenas** a leitura do catálogo — nada foi migrado para fora do SQL.

> Se sobrar tempo aqui, os detalhes que valem a pena (e que ninguém vê na tela): o **TTL de 60 s** com invalidação explícita no `POST`/`DELETE` de jogo, o índice único `(gameId, userId)` criado no boot da API e o `WRONGTYPE` do `redis-cli GET`. Se faltar tempo, essas três frases são as primeiras a cair.

## Bloco 6 — 8:55–9:30: Repositórios e fechamento

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
kubectl create -n default secret generic sqlserver-secret --from-literal=sa-password='<senha-do-sa>' --dry-run=client -o yaml | kubectl apply -n default -f -
#    ... (os Secrets das APIs, do Grafana, do Mongo e do RabbitMQ — secao "Segredos" do README)

# 2) Manifestos: infraestrutura, APIs, Mongo, Redis, Prometheus, Grafana, Loki e Promtail
kubectl apply -n default -f k8s/

# 3) Gateway: renderiza a chave JWT do Secret, recria o kong-declarative-config e espera o rollout
powershell -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1
```

**Narração final:** "nenhuma credencial é versionada: os manifestos guardam só o **nome** dos Secrets; a configuração do Kong é um **template** com o marcador `${JWT_SECRET}`, renderizado pelo script a partir do que já está no cluster. A função é implantada pelo **Terraform do repositório dela** — e o `terraform plan` com a função em zero devolve `No changes`: o Terraform não briga com o KEDA pelo número de réplicas."

**Higiene da sessão — o último comando do vídeo (mostre na tela):**

```powershell
# Os corpos de requisicao da sessao (o do login tem a senha em claro) vivem so no diretorio do
# passo 0 do bloco 2. Apagar o diretorio inteiro e o fecho do ciclo de segredo da gravacao:
Remove-Item $dirDemo -Recurse -Force
Test-Path $dirDemo      # False
```

**Na tela:** `False` — e a narração: "a senha da demonstração viveu só na variável de ambiente da sessão; os arquivos temporários com ela foram apagados agora, e os dois scripts de apoio (`preflight-fase3.ps1` e `demo-trafego.ps1`) fazem exatamente a mesma limpeza no fim".

**Encerramento:** pare os `port-forward` (Ctrl+C), feche os terminais da gravação (`Clear-History` + fechar a janela) e só então feche o navegador.

## Se estourar o tempo (regra de corte)

A rede de segurança: o **alvo é 9:30** e o **teto duro é 10:00**, então há ~30 s de folga. Só se estiver passando de 9:30, corte **nesta ordem**:

1. **primeiro** o `port-forward` da Admin API do Kong com `/routes` e `/plugins` (bloco 2) — o 401 sem token e o 200 com token já provam o gateway e a autenticação;
2. depois o `GET /api/jogos/{id}/avaliacoes/resumo` e o `hlen` (bloco 5) — o documento do `PUT`, a lista do `GET` e o `keys`/`ttl` do Redis já provam a persistência poliglota e o cache;
3. depois a segunda passada em `Status → Targets` (bloco 4), mantendo o dashboard `FCG - APIs` em tela e o painel de pagamentos mexendo.

**Não corte:** o cadastro que acorda a função, a espera de ~15–30 s, o log da função **no Grafana** e a volta a zero — esse conjunto é o requisito de **serverless com escala a zero**, e é o bloco que mais depende de tempo real. Também não corte a seção *Atendimento dos requisitos da Fase 3* no fim: é o mapa que a banca usa para conferir o enunciado.

> **Se nada disso bastar, corte no tempo da própria narração — nunca no último bloco inteiro.** Os três campos onde sobra gordura são: a **abertura** (o diagrama do README fala por si: uma frase por componente, sem repetir o que está escrito), o **porquê do NoSQL** (uma frase por banco; o README detalha) e o **fechamento** (mostre a tabela de repositórios e a seção de requisitos; o "como subir tudo" pode ficar só com os três comandos na tela). Os quatro itens que o enunciado exige demonstrar — **gateway**, **serverless com escala a zero**, **observabilidade** e **persistência poliglota com cache** — ficam inteiros.

## Apoio: o que o preflight garante para esta gravação

`scripts/preflight-fase3.ps1` roda **antes** de gravar e falha (`exit 1`) se qualquer peça do vídeo não estiver no ar: os 11 pods e o promtail, os **4 PVCs `Bound`**, o gateway (`401` sem token e `200` com token), os três alvos do job `fcg-apis` no Prometheus, o Loki `ready` e com log recente da stack (se ainda não houver log da **função** nas últimas 24 h, ele **avisa** em vez de reprovar — o cadastro do bloco 3 gera esse log ao vivo), o datasource e os dois dashboards do Grafana, as **três filas `notifications-*`** com o `ScaledObject Ready=True` (sem fila o KEDA cai em `TriggerError` e a **função simplesmente não sobe** — falha silenciosa que só apareceria na gravação), o Redis com as chaves `catalog:*`, o Mongo respondendo e — o mais importante — o **usuário e os jogos de demonstração**, além da **função em 0 réplicas** no estado inicial.

Sobre os dados de demonstração, ele garante **3 jogos** no catálogo, promove o usuário demo a Admin se precisar criar jogos (SQL por dentro do pod, digitado por **stdin**), **lê a biblioteca do usuário** (`GET /api/biblioteca/{userId}`) e escolhe/impressiona o **jogo do bloco 4**: o primeiro do catálogo que o usuário **não** possui — é esse id que vai em `$env:FCG_DEMO_JOGO` e que o bloco 4 (compra) e o bloco 5 (avaliações) usam. A **compra de verificação** que ele faz em seguida usa **outro** jogo, de propósito: comprar o do bloco 4 aqui consumiria a primeira compra daquele par (usuário, jogo), que é justamente a que devolve `202` e move o painel de pagamentos no vídeo.

Ele também **exercita os comandos que só aparecem no vídeo**: as séries dos painéis em `/metrics` dos três serviços (pelo proxy do `kubectl`), a **compra** (`202`) e o `PUT`/`GET` de **avaliação** (upsert) — assim nenhum bloco do roteiro leva um comando que nunca rodou. `scripts/demo-trafego.ps1 -Segundos 90` é o gerador do bloco 4; os dois leem a senha de `$env:FCG_DEMO_SENHA` e **não** têm senha padrão no arquivo.
