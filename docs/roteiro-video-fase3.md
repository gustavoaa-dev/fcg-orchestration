# Roteiro do vídeo da Fase 3 (até 10 minutos) — gravação em módulos

Vídeo de demonstração da **FCG (Fiap Cloud Games)** para a entrega da Fase 3: **até 10 minutos**, mostrando a plataforma rodando no cluster e os repositórios atualizados. O vídeo é gravado **em módulos** — seis tomadas independentes, uma por capítulo deste documento — e **montado na edição**. Cada capítulo é **autossuficiente**: quem abrir só ele consegue gravar aquele módulo sem ler os outros.

A seção [Atendimento dos requisitos da Fase 3](../README.md#atendimento-dos-requisitos-da-fase-3) do README tem a mesma ordem dos módulos — a banca consegue acompanhar os dois lados.

## Módulos

| # | Módulo | O que comprova (enunciado) | Duração-alvo | Arquivo sugerido da tomada |
|---|---|---|---|---|
| 1 | Abertura e arquitetura | contexto: a plataforma e a stack (README: *Arquitetura* + fluxo de eventos) | 0:35 | `modulo-1-arquitetura.mp4` |
| 2 | Gateway: roteamento e segurança | **item 1** — requisições via Gateway | 2:15 | `modulo-2-gateway.mp4` |
| 3 | Função serverless + log centralizado | **item 2** — função acionada, com o log **na plataforma** | 2:15 | `modulo-3-serverless.mp4` |
| 4 | Observabilidade (Opção A) | **item 3** — dashboard do Grafana com métricas em tempo real | 2:15 | `modulo-4-observabilidade.mp4` |
| 5 | NoSQL e cache | **item 4** — como o NoSQL foi integrado (+ Redis) | 1:35 | `modulo-5-nosql.mp4` |
| 6 | Repositórios e fechamento | os 5 itens de repositório do enunciado | 0:35 | `modulo-6-repositorios.mp4` |
| | **Total** | | **9:30** | |

**Soma: 0:35 + 2:15 + 2:15 + 2:15 + 1:35 + 0:35 = 9:30.** O alvo é **9:30 de conteúdo montado** e o **teto duro é 10:00** (o enunciado diz "até 10 minutos", então 10:01 descumpre): os ~30 s de folga entre o alvo e o teto são o que absorve a narração e as esperas reais. A seção [Montagem](#montagem) fecha a conta e traz a ordem de corte.

> **O teto vale para o vídeo MONTADO, não para o tempo de gravação.** Gravar seis módulos leva bem mais que 10 minutos — inclusive porque cada módulo pode ser regravado quantas vezes for preciso. O que tem de caber em 10:00 é a soma das durações-alvo dos módulos que entrarem no corte final.

> **Namespace, em todo o roteiro:** cada comando `kubectl` leva **`-n default`** (o namespace onde a plataforma roda), e o caminho de proxy do kubectl carrega o namespace **dentro do próprio caminho** (`kubectl get --raw '/api/v1/namespaces/default/services/...'`). As duas formas apontam para o mesmo lugar — nada aqui depende do namespace do contexto, que pode estar em outro namespace sem que você perceba.

## Como gravar em módulos

1. **Antes da primeira tomada, rode o preflight completo uma vez** — **sem** o parâmetro, ele valida o cluster inteiro (pods, PVCs, gateway, Loki, Grafana, KEDA, dados de demonstração e a função em 0 réplicas) e é a execução única que precede a série de gravações:

   ```powershell
   $env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'      # NAO versionada: so na sessao do terminal
   powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1
   ```

   → no fim, `checagens=48..54  falhas=0` e a última linha **`TUDO PRONTO PARA GRAVAR`**. O total varia porque algumas checagens só existem quando há o que verificar (a promoção do usuário a Admin, o log da função no Loki, a compra de verificação); o que importa é **`falhas=0`**. Sem o `-Modulo`, como diz o fim da [seção de apoio](#apoio-o-que-o-preflight-garante), o script é o preflight completo de sempre — e ele **não** é obrigatório antes de cada tomada: quem garante o estado de cada módulo é o preparo `-Modulo N`.

2. **Abra o capítulo do módulo** que vai gravar (por exemplo, `Módulo 2 — Gateway`) e siga **só ele**: cada capítulo tem o preparo, os comandos, a narração e o que fazer se der errado.
3. **Rode o preparo daquele módulo** no terminal em que você vai gravar (o T1):

   ```powershell
   $env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'      # NAO versionada: so na sessao do terminal
   powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo N
   ```

   Cada `-Modulo N` **valida e prepara só o que aquela tomada precisa** e termina em **`TUDO PRONTO PARA GRAVAR O MODULO N`**. Se sair `PREFLIGHT REPROVADO ... NAO GRAVE ainda`, leia as linhas `[FALHOU]` acima, corrija e rode de novo (o script termina com `exit 1`). Os módulos que fazem login (**2, 4 e 5**) exigem a senha; os módulos 1, 3 e 6 não fazem login e por isso não exigem (no **3** o preparo lê o cluster, mas quem usa a senha é a **tomada**, no cadastro).
4. **Confira que a tela está limpa** antes de apertar REC: nada de token, senha, `.env`, `kubectl get secret -o yaml` ou conteúdo do ambiente. As [regras de segurança](#regras-de-segurança-de-gravação) valem para **toda** tomada — um descuido em uma delas vira credencial exposta na entrega.
5. **Grave o módulo** seguindo o *Passo a passo na tela* do capítulo, usando a *Narração sugerida* como fala. Limpe a tela (`Clear-Host`) no começo para o corte ficar limpo.
6. **Pare a gravação e salve com o nome do módulo** (`modulo-2-gateway.mp4`), para a edição não depender de memória.
7. **Feche o que a tomada abriu** — os `port-forward` (Ctrl+C) e a higiene do diretório de sessão que o próprio capítulo termina mostrando — e passe para o módulo seguinte. Os módulos seguintes assumem que as portas voltaram a ficar livres (o preparo de cada um checa isso).
8. **Regrave quantas vezes quiser.** Cada módulo pode ser regravado do zero: rode **o preparo de novo** antes de cada retake, porque é ele que devolve o estado inicial daquela tomada. O caso mais claro é o da **compra**: o preparo garante (criando um jogo novo, se o usuário demo já possuir todos) um **jogo livre** e imprime o id a ser usado — repetir a compra do mesmo jogo devolveria `400` ("já possui este jogo") e o painel de pagamentos não se mexeria na tela.

**Onde ficam os segredos da sessão.** Cada módulo cria o **próprio diretório de sessão** (`$dirDemo`, no começo do *Passo a passo na tela* do capítulo — é o `# 0)` nos módulos 2, 3 e 5 e o `# 4)` no módulo 4, onde a tomada começa pelos painéis) e o **remove no fim dele**. É por tomada, de propósito: nenhum arquivo com senha em claro sobrevive à tomada que o criou, um retake não depende de nada do que veio antes, e o módulo 6 fecha o vídeo mostrando que **não sobrou nenhum diretório `fcg-demo-*`** no `%TEMP%` da máquina.

## Regras de segurança de gravação

Valem para **toda** tomada — antes de apertar REC, confira uma a uma:

- **Nunca abrir o `.env`** — nem `cat`, nem `code .env`, nem `Get-Content .env`. Ele existe no host e está no `.gitignore`; no vídeo ele simplesmente não aparece.
- **Nunca `kubectl get secret -o yaml` / `-o json` / `describe secret`.** Só o **nome** do Secret pode aparecer (`kubectl get secrets`), nunca o valor: em Kubernetes o valor é apenas base64, ou seja, ler o Secret é ler a credencial.
- **Nunca mostrar a senha da demonstração.** Nos comandos de cadastro/login ela entra por **`$env:FCG_DEMO_SENHA`**, nunca digitada no terminal. O mesmo vale para a senha do Grafana: ela é digitada no formulário de login (que mascara) e **nunca** vai para a barra de endereço como `admin:senha@localhost:13000`.
- **Nunca imprimir o token.** Login com `-o NUL`/`-w '%{http_code}'`, e para provar que o token veio, mostre o **tamanho** (`$token.Length`), não o valor.
- **Nunca `curl.exe http://localhost:8001/`.** Em modo DB-less a Admin API devolve a configuração declarativa inteira — **incluindo o `secret` HMAC do consumer `fcg-client`, com o qual qualquer um forja um token válido**. Use só `/routes` e `/plugins` (que não trazem segredo).
- **Nunca mostrar o conteúdo do ambiente** (`Get-ChildItem env:`, `kubectl exec ... -- env`, `docker inspect`): `$env:FCG_DEMO_SENHA` apareceria em claro.
- **Ao terminar cada tomada, apague o diretório de sessão dela** (`Remove-Item $dirDemo -Recurse -Force`, o passo de higiene que fecha cada capítulo): ele é o **único** lugar em que o roteiro grava corpo de requisição — e o corpo do login e do cadastro carrega a senha. Depois feche os terminais da gravação (`Clear-History` + fechar a janela): o token e a senha viveram só na memória daquela sessão. **Os dois scripts de apoio fazem a mesma limpeza**: o `preflight-fase3.ps1` e o `demo-trafego.ps1` montam o corpo do login num diretório temporário próprio (é o `-d @arquivo` do curl, que evita o JSON inline perder as aspas) e **removem o diretório inteiro no fim**, em todos os caminhos de saída (inclusive quando falham). Ou seja: nenhum artefato com senha — nem o do roteiro, nem o dos scripts — sobrevive à gravação.

## Módulo 1 — Abertura e arquitetura (`~0:35`)

### O que este módulo comprova

O contexto da entrega: a plataforma FCG e a stack que o resto do vídeo vai usar, lidas do próprio README (seção *Arquitetura* + diagrama do **Fluxo de eventos**). É o mapa do vídeo — os quatro itens que o enunciado cobra aparecem aqui primeiro, em uma frase cada.

### Duração-alvo

`~0:35`. O diagrama do README fala por si: nada de repetir o que está escrito na tela.

### Antes de gravar

```powershell
$env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'      # NAO versionada: so na sessao do terminal
powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo 1
```

Este preparo **não consome nada** do cluster (só lê os pods e o disco) e **não exige a senha**. Esperado no fim:

```
=== MODULO 1 - abertura e arquitetura: a plataforma no ar e o README na mao ===
pods do namespace:                                  <- 12 linhas: os 11 da plataforma + promtail
pod-sqlserver-1/1-Running=True  [OK]                (idem para rabbitmq, mongo, redis,
...                                                  users-api, catalog-api, payments-api, kong,
pod-promtail-1/1-Running=True  [OK]                  prometheus, grafana e loki)
README com a secao Arquitetura = True  com o fluxo de eventos = True
readme-com-arquitetura-e-fluxo-de-eventos=True  [OK]
=== RESULTADO ===
modulo=1  checagens=13  falhas=0
TUDO PRONTO PARA GRAVAR O MODULO 1
```

**Na tela, deixe pronto:** o `README.md` aberto na seção **Arquitetura**, com a tabela de serviços e o diagrama do **Fluxo de eventos** visíveis (aba do navegador no GitHub ou o arquivo no editor). Nenhum terminal além do T1 é necessário — e ele deve estar com a tela limpa (`Clear-Host`) quando o REC começar.

### Passo a passo na tela

1. **T1** — mostre a plataforma no ar (comando de contexto, ~5 s):

   ```powershell
   kubectl get -n default pods
   ```

   → **12 pods** (`Running`): os 11 de infraestrutura/APIs — `sqlserver`, `rabbitmq`, `mongo`, `redis`, `users-api`, `catalog-api`, `payments-api`, `kong`, `prometheus`, `grafana`, `loki` — mais o `promtail` do DaemonSet, que é o coletor de logs.

2. **Navegador/editor** — README na seção *Arquitetura*: aponte a tabela de serviços e o **fluxo de eventos** (`UserCreatedEvent` da UsersAPI e `OrderPlacedEvent` da CatalogAPI), narrando como abaixo. Sem mais comandos: a abertura é a tela do README.

### Narração sugerida

Uma frase por componente, ~4 s cada (o módulo inteiro tem 35 s):

- **(0:00–0:05)** "Esta é a plataforma FCG: três microsserviços .NET 8 — UsersAPI, CatalogAPI e PaymentsAPI —, uma função serverless de notificações e um API Gateway Kong na frente de tudo."
- **(0:05–0:11)** "Todo o acesso externo entra pelo **Kong**: nenhuma API é publicada direto."
- **(0:11–0:18)** "Os serviços conversam de forma **assíncrona** pelo RabbitMQ: o `UserCreatedEvent` da UsersAPI e o `OrderPlacedEvent` da CatalogAPI."
- **(0:18–0:24)** "A notificação é uma **função com escala a zero** (KEDA): sem evento, zero pods."
- **(0:24–0:30)** "O **MongoDB** guarda as avaliações dos jogos e o **Redis** é o cache de leitura do catálogo — o SQL Server continua dono do dado transacional."
- **(0:30–0:35)** "A observabilidade é a **Opção A**: Prometheus coletando as métricas, Grafana com os dashboards e **Loki** centralizando os logs — inclusive os da função, que não tem pod permanente."

### Como saber que deu certo

- a seção *Arquitetura* na tela, com a tabela de serviços **e** o diagrama de fluxo de eventos;
- as seis frases ditas, sem ler o README em voz alta;
- (se mostrar os pods) **12** pods, todos `Running`, incluindo o `promtail`;
- nenhuma janela do vídeo com `.env`, token, senha ou `secret` aberto.

### Se der errado

- **o README não abre / a seção não existe** → `Test-Path README.md` e abra em `## Arquitetura`. O preparo reprova em `readme-com-arquitetura-e-fluxo-de-eventos` se a seção mudar de nome.
- **menos de 12 pods** → o preparo reprova em `pod-<nome>-1/1-Running`; espere o rollout (`kubectl get -n default pods -w`) e rode `-Modulo 1` de novo.
- **apareceu `.env`, token ou senha na tela** → pare, feche a aba/arquivo e **regrave a tomada**: é a regra de ouro das [regras de segurança](#regras-de-segurança-de-gravação).

### Nota de edição

É a abertura fria: no corte, pode começar direto no diagrama e manter só as frases dos itens cobrados (gateway, serverless, observabilidade, NoSQL/cache). O `kubectl get pods` é contexto e pode cair inteiro se o tempo apertar. **Emenda com o módulo 2** na frase "todo o acesso externo entra pelo Kong". **Não pode sumir:** a menção de que existe uma **função com escala a zero** e um **banco NoSQL** — são dois dos quatro itens do enunciado, e é aqui que a banca entende o desenho antes de ver rodando.

## Módulo 2 — Gateway: roteamento e segurança (`~2:15`)

### O que este módulo comprova

**Item 1** — as requisições entram pelo **Gateway**: roteamento (as rotas declaradas) e segurança (401 sem token → login 200 → 200 com token), com o plugin `jwt` aplicado no próprio Kong e as APIs não expostas.

### Duração-alvo

`~2:15`.

### Antes de gravar

```powershell
$env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'
powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo 2
```

Esperado no fim (valores medidos no cluster; o preparo garante que o usuário demo existe, cria se faltar, e lê a config do Kong **de dentro do Secret, em memória** — imprimindo só o resumo, **nenhum segredo**):

```
=== MODULO 2 - gateway: roteamento e seguranca ===
pod-...-1/1-Running=True  [OK]                            (os 11 + pod-promtail: 12 checagens)
GET /api/jogos sem token = 401  (esperado 401)
gateway-401-sem-token=True  [OK]
POST /api/auth/login = 200  (esperado 200)
usuario-de-demonstracao-login-200=True  [OK]
token obtido: 79 caracteres (valor nunca e impresso)
GET /api/jogos com token = 200  (esperado 200)
gateway-200-com-token=True  [OK]
porta 8001 no host = livre  (o port-forward da Admin API e desta tomada)
porta-8001-livre-no-host=True  [OK]
config do Kong lida do Secret kong-declarative-config (so o resumo: nenhum segredo e impresso)
servicos no Kong = users-api, catalog-api
rotas no Kong = users-login, users-signup, users-protegida, catalog-jogos, catalog-biblioteca
kong-sem-rota-para-payments-api=True  [OK]
kong-com-plugin-jwt=True  [OK]
=== RESULTADO ===
modulo=2  checagens=18  falhas=0
TUDO PRONTO PARA GRAVAR O MODULO 2
  usuario de demonstracao: demo@fcg.local (senha em FCG_DEMO_SENHA; a tomada faz login com ele)
  a Admin API (porta 8001) e DESTA tomada: suba o port-forward no T3 e feche-o ao terminar
```

(o número de caracteres do token varia com e-mail/senha — o que importa é existir. Se o preparo tiver criado o usuário demo, ele avisa em três linhas `*** AVISO ***`: isso só acontece em cluster novo.)

**Na tela, deixe pronto:** **dois terminais** abertos em `fcg-orchestration` — **T1** (o dos comandos, onde o preparo rodou e onde você vai digitar) e **T3** (o do `port-forward`, ocupado até o fim do módulo). O T1 precisa ter `$env:FCG_DEMO_SENHA` na sessão. `Clear-Host` nos dois antes de apertar REC.

> **Não existe T2 neste módulo** — e isso é de propósito. A numeração dos terminais é fixa no roteiro inteiro, para você nunca ter de adivinhar qual janela é qual: o **T2** é o `kubectl get ... -w` do **módulo 3** e o **T3** é o `port-forward` (aqui o da Admin API do Kong, nos módulos 3 e 4 o do Grafana). Este módulo tem só dois papéis — comandos (T1) e a Admin API (T3) —, então o T2 fica vazio.

### Passo a passo na tela

**T1 (raiz de `fcg-orchestration`):**

```powershell
# 0) DIRETORIO DE SESSAO desta tomada: todo corpo de requisicao (o do login carrega a senha) e
#    gravado SO aqui dentro, e o diretorio inteiro e removido no fim DESTE modulo (passo 8).
$dirDemo = Join-Path $env:TEMP ('fcg-demo-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Path $dirDemo -Force | Out-Null

# 1) O Service do gateway: LoadBalancer publicando SO a porta 8000
kubectl get -n default svc kong

# 2) A rota protegida SEM token -> o proprio Kong responde 401 (a API nem e alcancada)
curl.exe -i http://localhost:8000/api/jogos
```

→ **1)** o `svc/kong` como `LoadBalancer` com `EXTERNAL-IP` `localhost` e a porta **`8000`**. **2)** o **`HTTP/1.1 401 Unauthorized`** com o corpo do Kong.

```powershell
# 3) Login (rota ANONIMA). A senha entra pela variavel de ambiente e NUNCA aparece.
#    O bloco vira uma funcao para ser reaproveitado nos passos 4 e nos modulos 4 e 5.
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

→ **3)** a linha `token recebido: <n> caracteres` (o `ConvertFrom-Json` não imprime o token). **4)** **`com-token=200`**.

> A função `Login-FCG` vive na sessão **deste** terminal: cada módulo é uma sessão nova, então os módulos 4 e 5 definem a mesma função de novo (o texto está nos capítulos deles).

**T3 — a Admin API do Kong (este terminal fica bloqueado pelo `port-forward` até o passo 9):**

```powershell
# 5) Admin API do Kong: as rotas e o plugin jwt -- a prova do roteamento e da autenticacao.
#    Rode no T3 e deixe o forward ativo: o comando so termina com Ctrl+C, entao o T1 fica livre.
kubectl port-forward -n default deploy/kong 8001:8001
```

**T1 — com o forward ativo no T3, do terminal de comandos:**

```powershell
# 6) As rotas e o plugin, lidos de OUTRO terminal (o T3 esta bloqueado pelo port-forward)
curl.exe -s http://localhost:8001/routes
curl.exe -s http://localhost:8001/plugins

# 7) As APIs NAO sao expostas: users-api e catalog-api sao ClusterIP, so o Kong e LoadBalancer
kubectl get -n default svc users-api catalog-api kong
```

→ **6)** as rotas declaradas (`users-signup`, `users-login`, `catalog-jogos`, `catalog-biblioteca`, `users-protegida`) e o plugin **`jwt`** com `key_claim_name: iss`, `claims_to_verify: ["exp"]` e `uri_param_names: []`. **7)** a tabela de Services com **`ClusterIP`** em `users-api`/`catalog-api` contra **`LoadBalancer`** em `kong`.

> **Não** rode `curl.exe http://localhost:8001/`: em DB-less ele devolve a config inteira, **com o segredo HMAC do consumer**. É a regra de segurança mais fácil de violar sem perceber.
>
> O `port-forward` da Admin API é sobre `deploy/kong` (e não `svc/kong`): a Admin API escuta **só no loopback do pod** e **não** é publicada no Service — `svc/kong` só tem a porta `8000`. É por isso que o preparo checa que a **8001 está livre**: quem vai ocupá-la é esta tomada.

```powershell
# 8) HIGIENE DA TOMADA: os corpos de requisicao desta tomada (o do login tem a senha) saem da maquina
Remove-Item $dirDemo -Recurse -Force
Test-Path $dirDemo      # False
```

→ **8)** **`False`**.

```powershell
# 9) FIM DA TOMADA: libere a porta 8001 para o proximo modulo
#    (no T3: Ctrl+C no port-forward)
```

### Narração sugerida

- **(0:00–0:15, com o `svc/kong` na tela)** "Todo o acesso externo entra por aqui: o Kong é um `LoadBalancer` e publica só a porta 8000 — nenhuma API é exposta direto."
- **(0:15–0:40, no `401`)** "Esta é a rota do catálogo sem token: o 401 vem do próprio Kong, e a requisição nem chega à CatalogAPI."
- **(0:40–1:05, no login)** "O login é a rota anônima; a senha entra pela variável de ambiente e não aparece em lugar nenhum — o que eu mostro é só o **tamanho** do token."
- **(1:05–1:25, no `com-token=200`)** "Com o token que o gateway acabou de validar, a mesma rota responde 200."
- **(1:25–1:55, no `/routes` e `/plugins`)** "Esta é a configuração declarativa em DB-less: as cinco rotas e o plugin `jwt`, que valida o token **no próprio Kong** — a mesma chave que a UsersAPI usa para assinar, com `iss` como `key_claim_name` e verificação de expiração."
- **(1:55–2:10, na tabela de Services)** "E as APIs em si são `ClusterIP`: só o Kong é `LoadBalancer` — não existe caminho até elas que não passe pelo gateway."
- **(2:10–2:15)** "O `400` do login é e-mail inexistente e o `401` é senha errada — quem responde isso é a UsersAPI, atrás do gateway."

### Como saber que deu certo

- o `svc/kong` na tela como `LoadBalancer` na porta `8000`;
- **`HTTP/1.1 401 Unauthorized`** sem token e **`com-token=200`** com o token, na mesma rota;
- a linha `token recebido: N caracteres` — e **nenhuma** ocorrência do token em si na tela;
- `/routes` com as cinco rotas e `/plugins` com o `jwt`;
- `users-api` e `catalog-api` como `ClusterIP` contra `kong` como `LoadBalancer`;
- `Test-Path $dirDemo` → **`False`** no fim;
- nada de `curl.exe .../8001/` (a raiz da Admin API) em momento nenhum.

### Se der errado

- **veio `200` sem token** → a rota está aberta: falta o plugin `jwt` na config. Rode `-Modulo 2` de novo (ele lê a config do Kong do Secret e reprova em `kong-com-plugin-jwt`).
- **login `401`** → a senha de `$env:FCG_DEMO_SENHA` não é a do `demo@fcg.local`. **login `400`** → e-mail inexistente, ou a senha não atende à política (8+ caracteres, com letra, dígito e caractere especial). Se o cadastro pelo gateway responder `400`, o e-mail já existe com **outra** senha.
- **`port-forward` com `address already in use`** → há um forward velho na 8001: Ctrl+C nele (ou feche a janela) e rode o preparo de novo — ele checa a porta antes de liberar.
- **`/routes` vazio ou sem o catálogo** → o forward não subiu ou o Kong está com outra config: `powershell -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1` e recomece a tomada.
- **compra/avaliação dando `400` aqui?** Este módulo **não consome jogo nenhum** — se algo de compra apareceu, você está com comandos de outro capítulo na tela.

### Nota de edição

O bloco do `port-forward` + `/routes` + `/plugins` (passos 5–6) é o **primeiro a cair** se o tempo estourar: o `401` sem token e o `200` com token já provam o gateway e a autenticação. A **higiene** (passo 8) pode ficar fora do corte, mas tem de **acontecer** — execute o `Remove-Item` mesmo sem câmera. **Emenda com o módulo 3** na ideia de que o que acabou de passar pelo gateway vai acionar a função. **Não pode sumir:** o `401` sem token e o `200` com token na mesma rota.

## Módulo 3 — Função serverless + log centralizado (`~2:15`)

### O que este módulo comprova

**Item 2** — a função serverless é **acionada** pelo evento (cadastro → `UserCreatedEvent` → KEDA sobe o pod) e o log dela aparece **na plataforma** (Grafana/Loki), não no terminal. É também a prova da **escala a zero**: `0/0` → pod → `0/0`.

### Duração-alvo

`~2:15` (o módulo que mais depende de tempo real: tem uma espera de ~15–30 s que é evidência).

### Antes de gravar

```powershell
$env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'
powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo 3
```

Este preparo **não faz login** e por isso **não exige a senha** (quem faz login são os módulos 2, 4 e 5). A variável continua na lista acima porque **a tomada** a usa: o cadastro do passo 2 entra com a senha por `$env:FCG_DEMO_SENHA`.

Esperado no fim (é o estado com que a tomada começa):

```
=== MODULO 3 - funcao serverless: escala a zero, filas e log na plataforma ===
pod-...-1/1-Running=True  [OK]                        (os 11 + pod-promtail)
filas do broker (rabbitmqctl list_queues name):       <- as tres filas notifications-*
fila-notifications-user-created=True  [OK]
fila-notifications-payment-processed=True  [OK]
fila-notifications-dead-letter=True  [OK]
ScaledObject notifications-function Ready=True  min=0 max=2
scaledobject-Ready-True=True  [OK]
loki /ready = ready  (esperado ready)
loki-ready=True  [OK]
rotulos app no Loki = notifications-function, users-api, catalog-api
loki-rotulo-app-com-log=True  [OK]
linhas de notifications-function na janela de 24h = 1  (esperado >= 1)
loki-log-da-funcao-de-notificacoes=True  [OK]
grafana /api/health = database=ok version=11.4.0
grafana-health-ok=True  [OK]
datasources = loki, prometheus
dashboards encontrados = fcg-apis, fcg-logs
grafana-datasource-loki=True  [OK]
grafana-dashboard-fcg-logs=True  [OK]
porta 13000 no host = livre  (o port-forward do Grafana e desta tomada)
porta-13000-livre-no-host=True  [OK]
deployment notifications-function: replicas=0  pods=0  (esperado 0 e 0)
kubectl get -n default pods -l app=notifications-function = No resources found
funcao-em-zero-replicas-estado-inicial=True  [OK]
=== RESULTADO ===
modulo=3  checagens=24  falhas=0
TUDO PRONTO PARA GRAVAR O MODULO 3
  funcao de notificacoes: 0 replicas e 0 pod(s) -- a tomada comeca com o 0/0 na tela
  o cadastro da tomada sobe o pod em ~15-30s (pollingInterval de 15s; medido 20-31s)
  painel da tomada: Grafana > Dashboards > FCG - Logs (Loki), com o periodo Last 5 minutes
```

> **A espera pela escala a zero faz parte do preparo, de propósito.** Se a tomada anterior acordou a função (cadastro, ou a compra de verificação do módulo 4), o pod pode estar de pé pelo `cooldownPeriod` de 30 s: o preparo **espera** até 120 s imprimindo `aguardando o cooldown do KEDA (30s) + o termino do pod...` e só então libera. Essa espera é a **última** coisa que ele faz, porque é o estado com que a tomada começa. Se estourar os 120 s, espere um pouco mais, confira `kubectl get -n default pods -l app=notifications-function` e rode `-Modulo 3` de novo.
>
> O preparo **não faz cadastro nenhum** — o cadastro é desta tomada. Se o rótulo `notifications-function` ainda não existir no Loki (a função não subiu nas últimas 24 h), ele sai **ATENÇÃO sem contar checagem** e a tomada continua válida: o cadastro dela gera a linha ao vivo.

**Na tela, deixe pronto:** **três terminais** — **T1** (comandos e cadastro), **T2** (`kubectl get ... -w`) e **T3** (o `port-forward` do Grafana, ocupado até o fim do módulo) — mais o **navegador** com a aba do Grafana em `http://localhost:13000` pronta (o login `admin` é feito na própria tomada, no formulário que mascara a senha). T1 e T2 com `$env:FCG_DEMO_SENHA` (só o T1 usa) e as telas limpas.

### Passo a passo na tela

**T1 — o estado de repouso e o diretório de sessão desta tomada:**

```powershell
# 0) DIRETORIO DE SESSAO desta tomada (o corpo do cadastro carrega a senha): removido no fim do modulo
$dirDemo = Join-Path $env:TEMP ('fcg-demo-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Path $dirDemo -Force | Out-Null

# 1) Estado de repouso: 0 de 0 replicas e NENHUM pod -- a escala a zero
kubectl get -n default deploy notifications-function
kubectl get -n default pods -l app=notifications-function
```

→ **1)** **`0/0`** no Deployment e **`No resources found`** para os pods.

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

→ **`cadastro=201`** e, no **T2**, o pod `notifications-function-...` **aparecendo** e indo para `Running` em **~15–30 s (pollingInterval de 15 s; medido 20–31 s)** — não é instantâneo.

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

→ no **T2**, o pod **`Terminating`** → nenhum recurso; e de volta o **`0/0`**. No Grafana, o log **continua lá** — o pod que o escreveu já não existe, e é exatamente para isso que o Loki existe (`kubectl logs -n default` não sobrevive ao pod).

**T1 — higiene da tomada:**

```powershell
Remove-Item $dirDemo -Recurse -Force
Test-Path $dirDemo      # False
```

→ **`False`**. **Fim da tomada:** Ctrl+C no `port-forward` do T3 (libera a porta 13000 para o próximo módulo).

### Narração sugerida

- **(0:00–0:10, no `0/0` e no `No resources found`)** "A função de notificações está em **zero réplicas**: nenhum pod, custo zero enquanto não há evento."
- **(0:10–0:25, com o `-w` rodando no T2)** "Deixei este terminal observando os pods da função: qualquer pod que nascer aparece aqui na hora."
- **(0:25–0:45, no cadastro)** "Vou cadastrar um usuário novo pelo gateway: o cadastro publica um `UserCreatedEvent` no RabbitMQ."
- **(0:45–1:20, durante a espera — narre, não corte)** "O KEDA consulta a fila a cada 15 segundos, então o pod leva de 15 a 30 segundos para aparecer. Essa espera **é** a prova da escala a zero, não é travamento. E aqui está ele: a função subiu para consumir a mensagem."
- **(1:20–1:55, no painel do Grafana)** "E este é o log dela: `[EMAIL ENVIADO] Boas-vindas para Espectador Video`. Repare que ele está **na plataforma** — Loki, com o Promtail coletando no nó. `kubectl logs` não serviria: o pod que escreveu esta linha já não existe."
- **(1:55–2:15, na volta a zero)** "Depois do cooldown de 30 segundos o KEDA devolve a função para zero: o ciclo fecha — zero, um, zero."

### Como saber que deu certo

- **`0/0`** e **`No resources found`** no começo da tomada;
- o pod da função **aparecendo** no T2 e chegando a `Running`;
- **`cadastro=201`** no T1;
- a linha **`[EMAIL ENVIADO] Boas-vindas para ...`** no painel do Grafana (na plataforma);
- o pod **`Terminating`** → `No resources found` → **`0/0`** de novo;
- o log **continuando visível** depois que o pod morreu;
- nenhum `kubectl logs` usado como prova.

### Se der errado

- **o pod não aparece** → o KEDA pode estar em `TriggerError` por fila ausente: rode `-Modulo 3` de novo (ele checa as **três filas** e o `ScaledObject Ready=True`) e, se faltar fila, faça o `terraform apply` do repositório da função. Confira também a ordem: o `-w` do T2 tem de estar rodando **antes** do cadastro, senão o pod nasce e morre sem aparecer.
- **a função não voltou a `0/0`** → espere o `cooldownPeriod` (30 s) mais o término do pod e rode o preparo do módulo de novo: a tomada tem de **começar** com o `0/0` na tela.
- **o painel do Loki está vazio** → o período do Grafana está fora da janela (use **Last 5 minutes**) ou o Promtail está fora (`kubectl get -n default pods -l app=promtail`). O preparo avisa quando o rótulo da função ainda não existe no Loki.
- **login do Grafana falha** → a senha é a do Secret `grafana-admin`; digite no formulário (que mascara) e **nunca** na URL.
- **`port-forward` com `address already in use`** → forward velho na 13000: Ctrl+C e rode o preparo de novo.
- **cadastro `400`** → o e-mail gerado (`video<HHmmss>@fcg.com`) já existia: rode o passo 2 de novo, o `HHmmss` muda a cada segundo.

### Nota de edição

A espera de ~15–30 s pode virar um **jump cut** — mas o **momento em que o pod aparece** (e o `Running`) tem de ficar: é o requisito. **Emenda com o módulo 4** na ideia de que a função não tem pod permanente, mas o que ela faz tem painel próprio. **Não pode sumir:** o `0/0`, o cadastro, o pod subindo, a linha do log **no Grafana** e a volta a zero — esse conjunto é o requisito de serverless com escala a zero.

## Módulo 4 — Observabilidade (Opção A) (`~2:15`)

### O que este módulo comprova

**Item 3** — o dashboard do Grafana com **métricas em tempo real** (latência p50/p95, RPS, status code, erros, `up`) sob tráfego autenticado de verdade, os **três alvos `up`** no Prometheus e o painel de **pagamentos por status** mexendo por **evento** depois de uma compra.

### Duração-alvo

`~2:15` (inclui os 90 s do gerador de tráfego, que podem ser acelerados no corte).

### Antes de gravar

```powershell
$env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'
powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo 4
```

Esperado no fim (é o preparo que **garante um jogo livre novo** para a compra desta tomada — é ele que protege o **retake**):

```
=== MODULO 4 - observabilidade: trafego, paineis e o pagamento por evento ===
porta 13000 no host = livre  (o port-forward da tomada precisa dela)
porta-13000-livre-no-host=True  [OK]
porta 19090 no host = livre  (o port-forward da tomada precisa dela)
porta-19090-livre-no-host=True  [OK]
  alvo job=fcg-apis http://users-api:80/metrics health=up        <- os tres alvos
  alvo job=fcg-apis http://catalog-api:80/metrics health=up
  alvo job=fcg-apis http://payments-api:80/metrics health=up
prometheus-tres-alvos-fcg-apis=True  [OK]
prometheus-alvo-users-api-up=True  [OK]
prometheus-alvo-catalog-api-up=True  [OK]
prometheus-alvo-payments-api-up=True  [OK]
prometheus-nenhum-alvo-down=True  [OK]
grafana /api/health = database=ok version=11.4.0
grafana-health-ok=True  [OK]
datasources = loki, prometheus
dashboards encontrados = fcg-apis, fcg-logs
grafana-datasource-prometheus=True  [OK]
grafana-dashboard-fcg-apis=True  [OK]
POST /api/auth/login = 200  (esperado 200)
usuario-de-demonstracao-login-200=True  [OK]
token obtido: 79 caracteres (valor nunca e impresso)
userId (claim Id do token) = <guid do demo>
GET /api/jogos = 200  jogos no catalogo = 3
catalogo-listagem-200=True  [OK]
GET /api/biblioteca/{userId} = 200  (a biblioteca do usuario demo)
biblioteca do usuario demo = 0 item(ns), 0 id(s) reconhecido(s)
biblioteca-do-usuario-200=True  [OK]
jogo da tomada livre = True  (existe no catalogo=True  esta na biblioteca=False)
jogo-do-bloco-4-escolhido=True  [OK]
contador fcg_payments_processados_total no /metrics do payments-api = True
metrics-payments-api-contador-de-negocio=True  [OK]
jogo do modulo 4 (compra) = <nome do jogo> (<id>)
  (nenhum outro jogo foi comprado aqui: a primeira compra DESTE par e a que move o painel na tomada)
=== RESULTADO ===
modulo=4  checagens=15  falhas=0
TUDO PRONTO PARA GRAVAR O MODULO 4
  jogo do modulo 4 (compra) = <nome do jogo> (<id>)
  copie para a sessao da tomada: $env:FCG_DEMO_JOGO = '<id>'
  painel da tomada: dashboard FCG - APIs em tela cheia + Status > Targets no Prometheus
```

**Copie o id impresso para a sessão do T1 antes de apertar REC** — a compra desta tomada lê `$env:FCG_DEMO_JOGO`, e assim nenhum GUID é digitado na gravação:

```powershell
$env:FCG_DEMO_JOGO = '<id-impresso-na-linha-jogo-do-modulo-4>'
```

Três variações possíveis, todas impressas pelo preparo (as duas últimas são as do **cluster frio**):

- **o usuário demo já possui todos os jogos do catálogo** → ele imprime `todos os jogos do catalogo ja estao na biblioteca do usuario demo: criando mais um` + `POST /api/jogos = 201` e escolhe **esse** jogo novo (é o que permite regravar a tomada quantas vezes quiser);
- **cluster frio, sem o contador de pagamentos** → ele faz uma **compra de verificação em OUTRO jogo livre** (`compra de verificacao (jogo <id>, OUTRO que o da tomada) = 202`) só para o contador `fcg_payments_processados_total` nascer no `/metrics` e espera até 30 s por ele; o jogo **da tomada não é tocado** (a primeira compra daquele par é a que move o painel no vídeo). Nessa rodada a última linha sobre o jogo da tomada passa a ser `(o jogo da tomada NAO foi comprado aqui: a primeira compra DESTE par e a que move o painel no video)`, e não a do caso normal;
- **cluster frio e sem nenhum outro jogo livre** (o demo possui todos e o preparo acabou de criar o da tomada) → ele **cria um jogo só para essa compra** (`nao ha outro jogo LIVRE no catalogo para a compra de verificacao: criando um jogo NOVO` + `POST /api/jogos = 201` + `jogo da compra de verificacao = …`) e compra esse. É por isso que o contador é **sempre** provado antes de liberar a gravação: o módulo anuncia o contador no *Esperado no fim* acima e não pode liberar uma tomada com ele por verificar.

> O único caso em que a prova do contador **não** acontece é a compra de verificação devolvendo **`400`/`409`** (re-execução: o usuário já possui aquele jogo): aí o preparo avisa em `ATENCAO`, não conta checagem (a rodada fecha em **14**, sem a linha do contador) e segue — mas o esperado, quando isso aparece, é rodar `-Modulo 4` de novo até o contador aparecer no `/metrics`.

**Na tela, deixe pronto:** **quatro terminais** em `fcg-orchestration` — **T1** (comandos: login e compra), **T2** (o gerador de tráfego), **T3** (`port-forward` do Grafana) e **T4** (`port-forward` do Prometheus) — mais **duas abas**: o Grafana em `http://localhost:13000` (logado) e o Prometheus em `http://localhost:19090/targets`. T1 com `$env:FCG_DEMO_SENHA` e `$env:FCG_DEMO_JOGO` e as telas limpas.

> Os dois `port-forward` **não podem dividir o mesmo terminal**: cada um bloqueia a janela até o Ctrl+C. T3 e T4 ficam ocupados até o fim do módulo.

### Passo a passo na tela

**T3 e T4 — os painéis (cada forward no seu terminal):**

```powershell
# T3
kubectl port-forward -n default svc/grafana 13000:3000
```

```powershell
# T4
kubectl port-forward -n default svc/prometheus 19090:9090
```

**T2 — tráfego autenticado contínuo (90 s):**

```powershell
powershell -ExecutionPolicy Bypass -File scripts/demo-trafego.ps1 -Segundos 90
```

**No navegador, nesta ordem:**

1. **Grafana** → `http://localhost:13000/d/fcg-apis/fcg-apis?kiosk&refresh=5s&from=now-5m` (**tela cheia**, sem menus) — com o gerador rodando, as séries **se movem em até 15 s** (o scrape é de 15 s): latência **p50/p95**, **requisições por segundo**, **requisições por status code**, **taxa de erros 5xx** e o painel de coleta (**`up`**).
2. **Prometheus** → `http://localhost:19090/targets` (**Status → Targets**): os **três alvos do job `fcg-apis`** — `users-api:80`, `catalog-api:80` e `payments-api:80` — com **`health: up`** (além do próprio Prometheus, no job `prometheus`).
3. **Volte ao Grafana** e mova o painel **Pagamentos processados por status** com uma **compra** (T1):

```powershell
# 4) DIRETORIO DE SESSAO desta tomada (o corpo do login e o da compra carregam a senha/id)
$dirDemo = Join-Path $env:TEMP ('fcg-demo-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Path $dirDemo -Force | Out-Null

# 5) Login: a mesma funcao do modulo 2 -- esta sessao e nova, entao ela vem junto
function Login-FCG {
    Set-Content -Path (Join-Path $dirDemo 'login.json') -Encoding ascii -NoNewline `
        -Value ('{"email":"demo@fcg.local","senha":"' + $env:FCG_DEMO_SENHA + '"}')
    (curl.exe -s -X POST http://localhost:8000/api/auth/login `
        -H "Content-Type: application/json" -d ('@' + (Join-Path $dirDemo 'login.json')) | ConvertFrom-Json).token
}
$token  = Login-FCG
'token recebido: ' + $token.Length + ' caracteres'

# 6) A COMPRA que move o painel -- o passo seguinte aos paineis no ar:
# O JOGO DESTA TOMADA nao e "o primeiro do catalogo": e o que o preparo IMPRIMIU na linha
# "jogo do modulo 4 (compra) = <nome> (<id>)" e voce guardou em FCG_DEMO_JOGO antes de apertar REC
# (o catalogo volta ordenado por NOME e a biblioteca do usuario demo cresce a cada rodada --
# comprar um jogo que ele ja possui devolve 400 e o painel de pagamentos nao se mexe).
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

→ **`compra=202`** (aceita e assíncrona) e, em até ~30 s (scrape de 15 s + processamento), as séries **`Approved`/`Rejected`** do painel *Pagamentos processados por status* subindo. Se vier **`400`**, o jogo já estava na biblioteca do usuário: **pare e rode o preparo do módulo de novo** — ele escolhe (ou cria) um jogo livre novo e imprime a linha `jogo do modulo 4 (compra)` — em vez de gravar uma tomada sem evidência.

**T1 — higiene e fim da tomada:**

```powershell
# 7) HIGIENE DA TOMADA: os corpos de requisicao desta tomada (o do login tem a senha) saem da maquina
Remove-Item $dirDemo -Recurse -Force
Test-Path $dirDemo      # False
# FIM: Ctrl+C nos port-forward do T3 e do T4 (liberam as portas 13000 e 19090)
```

### Narração sugerida

- **(0:00–0:20, com o gerador rodando no T2)** "Aqui está tráfego autenticado de verdade: 90 segundos batendo nas rotas do catálogo pelo gateway."
- **(0:20–1:00, no dashboard em tela cheia)** "O painel mostra latência p50/p95, requisições por segundo, requisições por status code e a taxa de erro — as séries se movem em até 15 segundos, que é o intervalo de coleta do Prometheus. E estes painéis **excluem as probes `/health`**: o número na tela é tráfego de negócio."
- **(1:00–1:25, no Prometheus `Status → Targets`)** "Os três serviços do job `fcg-apis` estão `up`: users-api, catalog-api e payments-api."
- **(1:25–1:55, de volta ao Grafana, no momento da compra)** "Agora uma compra. O detalhe que costuma passar batido: o `payments-api` **não recebe requisição nenhuma do gateway** — ele é consumidor de fila. Quem move este painel é o **fluxo de eventos**: a compra publica `OrderPlacedEvent` e incrementa o contador de negócio."
- **(1:55–2:15, com o painel mexendo)** "E aqui está o efeito: as séries de pagamentos `Approved` subindo depois da compra — o evento virou métrica."

### Como saber que deu certo

- o gerador imprimindo `requisicoes` crescendo e **`status codes = 200:~N`** (sem erro);
- as séries do painel **`FCG - APIs`** se mexendo em até 15 s (p50/p95, RPS, status code, `up`);
- os **três alvos `up`** em `Status → Targets`;
- **`compra=202`** e o painel *Pagamentos processados por status* mexendo em até ~30 s;
- `Test-Path $dirDemo` → **`False`** no fim.

### Se der errado

- **o dashboard não abre / dá 401 no Grafana** → o `port-forward` do T3 não subiu (confira a porta 13000) ou a senha/usuário estão errados (o usuário é `admin`).
- **as séries não se mexem** → o gerador não está rodando (T2) ou o login dele falhou: rode `scripts/demo-trafego.ps1 -Segundos 90` de novo e veja o resumo no fim. Lembre que o scrape é de **15 s**: dê tempo.
- **`compra=400`** → o jogo já está na biblioteca do usuário demo (retake com id velho): rode `-Modulo 4` de novo, copie o **novo** id para `$env:FCG_DEMO_JOGO` e regrave a tomada.
- **`compra=401/403/5xx`** → token recusado / sem permissão / serviço fora: o preparo já reprova nesses códigos (`FALHOU`) — resolva antes de gravar.
- **o painel de pagamentos continua vazio depois de ~30 s** → o consumidor pode estar parado: `kubectl get -n default pods -l app=payments-api` e `kubectl logs -n default deploy/payments-api`. Rode `-Modulo 4` de novo para conferir o contador no `/metrics`.
- **`port-forward` com `address already in use`** → forward velho nas portas 13000/19090 (ou um forward do módulo 3 que ficou aberto): Ctrl+C nele e rode o preparo de novo.

### Nota de edição

Os 90 s do gerador podem ser **acelerados no corte** (jump cut ou velocidade), mas as séries **têm de aparecer se mexendo** — é o "tempo real" do enunciado. A segunda passada em `Status → Targets` é a primeira coisa que pode cair depois do `port-forward` do módulo 2. **Emenda com o módulo 5** no "o painel do catálogo também tem cache por trás". **Não pode sumir:** o dashboard com as métricas mexendo, a compra `202` e o painel de pagamentos reagindo por evento.

## Módulo 5 — NoSQL e cache (`~1:35`)

### O que este módulo comprova

**Item 4** — como o **NoSQL foi integrado**: a avaliação do jogo é persistida no **MongoDB** (`PUT` upsert devolve o documento; `GET` devolve a lista vinda do Mongo) e o **Redis** é o **cache de leitura** do catálogo (chave `catalog:*`, `type` `hash`, `ttl` ≤ 60 s, contadores `cache_hit`/`cache_miss`). Uma frase por banco explica o *porquê* de cada escolha.

### Duração-alvo

`~1:35`.

### Antes de gravar

```powershell
$env:FCG_DEMO_SENHA = '<senha-da-demonstracao>'
powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo 5
```

Esperado no fim (a contagem de checagens varia com o caminho do preparo — **8 a 10**; o que importa é `falhas=0`):

```
=== MODULO 5 - NoSQL e cache: avaliacoes no Mongo e o Redis como cache de leitura ===
POST /api/auth/login = 200  (esperado 200)
usuario-de-demonstracao-login-200=True  [OK]
token obtido: 79 caracteres (valor nunca e impresso)
GET /api/jogos = 200  jogos no catalogo = 3
catalogo-listagem-200=True  [OK]
jogo da tomada = <nome do jogo> (<id>)  -- veio de FCG_DEMO_JOGO        <- so no caminho COM a variavel
jogo-da-tomada-definido=True  [OK]
PUT /api/jogos/{id}/avaliacoes = 200  (esperado 201 na primeira, 200 na atualizacao)
avaliacao-upsert-200-ou-201=True  [OK]
GET /api/jogos/{id}/avaliacoes = 200  (esperado 200: a lista vem do Mongo)
avaliacao-listagem-200=True  [OK]
GET /api/jogos (aquece o cache) = 200
redis-cli keys catalog:* = catalog:games:all
redis-com-chaves-catalog=True  [OK]
redis-cli type/ttl catalog:games:all = hash / 57  (esperado hash / ate 60)
metrics-catalog-api-cache-hit=True  [OK]
metrics-catalog-api-cache-miss=True  [OK]
=== RESULTADO ===
modulo=5  checagens=10  falhas=0
                        <- 8 a 10, conforme o caminho do preparo: 10 quando ele REELEGE o jogo (o valor
                           medido no cluster) e 8 quando FCG_DEMO_JOGO ja traz um id do catalogo.
                           O que importa e falhas=0.
TUDO PRONTO PARA GRAVAR O MODULO 5
  jogo do modulo 5 (avaliacoes) = <nome do jogo> (<id>)
  copie para a sessao da tomada: $env:FCG_DEMO_JOGO = '<id>'
  o PUT da tomada devolve 200 (upsert): este preparo ja gravou a avaliacao do demo neste jogo
```

O preparo usa **o mesmo jogo do módulo 4** (`$env:FCG_DEMO_JOGO`, se o id ainda existir no catálogo). Se a variável não estiver definida nesta sessão — por exemplo, se você gravar o módulo 5 sem ter gravado o 4 — ele **reelege um jogo livre**, imprime `FCG_DEMO_JOGO nao esta definido nesta sessao: reelegendo um jogo livre e imprimindo o id` (no lugar da linha `jogo da tomada = ... -- veio de FCG_DEMO_JOGO`) e fecha com a linha `copie para a sessao da tomada: $env:FCG_DEMO_JOGO = '<id>'`. É o caminho da linha `checagens=10` acima; com a variável definida o preparo fecha em **8**. Copie o id para a sessão do T1 antes de apertar REC.

> Depois de gravar o módulo 4, aquele jogo **já pertence** ao usuário demo — e isso **não é problema aqui**: a avaliação é *upsert* por `(gameId, userId)` e não precisa de jogo livre. É por isso que o preparo do módulo 5 **não** exige um jogo livre, só que o id exista no catálogo.

**Na tela, deixe pronto:** **um terminal** (T1) em `fcg-orchestration`, com `$env:FCG_DEMO_SENHA` e `$env:FCG_DEMO_JOGO` na sessão e a tela limpa. Nenhum `port-forward` é necessário: o Redis é lido por `kubectl exec` e as métricas de cache pelo proxy do `kubectl`.

### Passo a passo na tela

**T1 — avaliação no Mongo (o `PUT` é upsert):**

```powershell
# 0) DIRETORIO DE SESSAO desta tomada (o corpo do login e o da avaliacao ficam aqui): removido no fim
$dirDemo = Join-Path $env:TEMP ('fcg-demo-' + (Get-Date -Format 'HHmmss'))
New-Item -ItemType Directory -Path $dirDemo -Force | Out-Null

# A mesma funcao do modulo 2: esta sessao e nova, entao ela vem junto
function Login-FCG {
    Set-Content -Path (Join-Path $dirDemo 'login.json') -Encoding ascii -NoNewline `
        -Value ('{"email":"demo@fcg.local","senha":"' + $env:FCG_DEMO_SENHA + '"}')
    (curl.exe -s -X POST http://localhost:8000/api/auth/login `
        -H "Content-Type: application/json" -d ('@' + (Join-Path $dirDemo 'login.json')) | ConvertFrom-Json).token
}
$token = Login-FCG
'token recebido: ' + $token.Length + ' caracteres'
# O $gameId e o id impresso pelo preparo desta tomada (a mesma variavel do modulo 4):
$gameId = $env:FCG_DEMO_JOGO

Set-Content -Path (Join-Path $dirDemo 'avaliacao.json') -Encoding ascii -NoNewline `
    -Value '{"nota":5,"comentario":"Jogo muito bom","tags":["acao","video"]}'
curl.exe -s -w 'avaliacao=%{http_code}\n' -X PUT ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes") `
    -H "Content-Type: application/json" -H "Authorization: Bearer $token" -d ('@' + (Join-Path $dirDemo 'avaliacao.json'))

# A lista e o resumo vem do Mongo (nao ha tabela de avaliacao no SQL Server):
curl.exe -s -H "Authorization: Bearer $token" ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes")
curl.exe -s -H "Authorization: Bearer $token" ("http://localhost:8000/api/jogos/" + $gameId + "/avaliacoes/resumo")
```

→ o documento persistido devolvido pelo `PUT` (com `gameId`, `usuarioId`, `nota`, `comentario`, `tags`, `dataAtualizacao`), a lista do `GET` e o resumo `{"total":1,"notaMedia":5}`. O `usuarioId` **não** veio do corpo: veio do claim `Id` do token. O `PUT` é **upsert**, então o status é `201` na primeira avaliação daquele usuário naquele jogo e `200` ao atualizar — **o preparo desta tomada já deixou uma avaliação do usuário de demonstração**, então na gravação o esperado é **`200`** (e isso é a prova do upsert, não um erro).

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

→ **`catalogo=200`**, as chaves `catalog:games:all` (e `catalog:game:{id}` quando o `GET` por id é exercitado pelo gerador), `type` = **`hash`** — um `GET` na chave devolveria `WRONGTYPE`, porque o `IDistributedCache` grava hash, não string —, `ttl` ≤ 60 e as linhas `cache_hit`/`cache_miss` com valores crescentes.

**T1 — higiene da tomada:**

```powershell
Remove-Item $dirDemo -Recurse -Force
Test-Path $dirDemo      # False
```

### Narração sugerida

O "por quê" de cada escolha **é o requisito**, não detalhe. Com 1:35 de módulo, o alvo é **uma frase por banco**; o resto é enfeite e o README já detalha.

- **(0:00–0:25, no `PUT` e no `GET`)** "A avaliação de um jogo não é dado de tabela: é um documento do usuário, persistido no **MongoDB**. O `PUT` é *upsert* — atualizou, não duplicou —, e a lista que eu leio agora vem do Mongo."
- **(0:25–0:45)** "**Por que MongoDB:** a avaliação tem formato variável — nota obrigatória, comentário opcional e tags livres — e a leitura que importa é agregada, total e média. No relacional isso viraria coluna anulável mais tabela de tags, com junção a cada leitura."
- **(0:45–1:05, no Redis)** "O `GET /api/jogos` devolve o catálogo inteiro e é a consulta mais repetida: ela fica em **cache no Redis**, com TTL de 60 segundos. Repare no `type`: é um **hash**, porque quem grava é o `IDistributedCache` do .NET, não um `SET`."
- **(1:05–1:25, nos contadores)** "E o cache é observável: `cache_hit` e `cache_miss` aparecem no próprio `/metrics` do catalog-api."
- **(1:25–1:35)** "O **Redis é cache, não banco** — tudo nele é reconstruível do SQL e a degradação é graciosa — e o **SQL Server continua dono do dado transacional**: usuários, catálogo e biblioteca. Nada foi migrado para fora dele."

### Como saber que deu certo

- `PUT` devolvendo o documento persistido (**`200`** = upsert atualizando) e `GET` devolvendo a lista;
- o resumo `{"total":N,"notaMedia":...}` vindo da agregação;
- `redis-cli keys 'catalog:*'` mostrando a chave `catalog:games:all`;
- `type` = **`hash`** e `ttl` ≤ **60**;
- as séries `cache_hit`/`cache_miss` no `/metrics` do catalog-api;
- uma frase de *porquê* para Mongo, Redis e SQL;
- `Test-Path $dirDemo` → **`False`** no fim.

### Se der errado

- **`PUT` devolveu `201`** → é a **primeira** avaliação daquele par (usuário, jogo) nesta rodada; é upsert na mesma, só não é o caso que o preparo deixou pronto. Não é erro.
- **`PUT`/`GET` devolvendo `401`** → o `$token` expirou ou a sessão foi recriada: rode `Login-FCG` de novo.
- **`redis-cli keys` vazio** → a listagem do catálogo não foi feita (o TTL é de 60 s): rode o `curl.exe .../api/jogos` de novo **imediatamente antes** do `keys`.
- **`type` devolveu `string` em vez de `hash`** → confira se a chave é `catalog:games:all` (é o caminho do `IDistributedCache`); se você mexeu no Redis à mão, rode `-Modulo 5` de novo.
- **`$env:FCG_DEMO_JOGO` vazio** → rode o preparo do módulo de novo e copie a linha `copie para a sessao da tomada: $env:FCG_DEMO_JOGO = '<id>'`.
- **`kubectl exec` no redis falhando** → `kubectl get -n default pods -l app=redis` (o pod tem de estar `Running`; o preparo do módulo 3 já checa a infraestrutura).

### Nota de edição

Se faltar tempo, as primeiras frases a cair são o **resumo** (`/avaliacoes/resumo`) e o **`hlen`** — o documento do `PUT`, a lista do `GET` e o `keys`/`ttl` do Redis já provam a persistência poliglota e o cache. **Emenda com o módulo 6** no "e é isso que está nos repositórios". **Não pode sumir:** o `PUT` devolvendo o documento, a lista vinda do Mongo, a chave do Redis com TTL e **uma** frase de porquê por banco.

## Módulo 6 — Repositórios e fechamento (`~0:35`)

### O que este módulo comprova

Os **5 repositórios** da entrega e o mapa requisito → onde está → como comprovar, mais a higiene final da gravação (nenhum diretório de sessão sobrando, nenhum arquivo modificado aparecendo na tela).

### Duração-alvo

`~0:35`.

### Antes de gravar

```powershell
powershell -ExecutionPolicy Bypass -File scripts/preflight-fase3.ps1 -Modulo 6
```

Este preparo **não faz login** (não exige `FCG_DEMO_SENHA`) e **não toca no cluster**: ele confere os repositórios locais, a evidência de segredos e o README. Esperado no fim:

```
=== MODULO 6 - repositorios e fechamento ===
repositorios locais = C:\Users\<voce>\fcg\.fase2-repos
git status em fcg-orchestration = (limpo)
repo-fcg-orchestration-sem-alteracoes-pendentes=True  [OK]
git status em fcg-users-api = (limpo)
repo-fcg-users-api-sem-alteracoes-pendentes=True  [OK]
... (o mesmo para fcg-catalog-api, fcg-payments-api e fcg-notifications-function)
evidencia de segredos (a mesma do README, com varios -e) = (vazio: nenhuma credencial versionada)
evidencia-de-segredos-vazia=True  [OK]
README com o link da funcao = True  com a secao de requisitos = True
readme-com-link-do-repositorio-da-funcao=True  [OK]
readme-com-secao-de-requisitos-da-fase-3=True  [OK]
=== RESULTADO ===
modulo=6  checagens=8  falhas=0
TUDO PRONTO PARA GRAVAR O MODULO 6
  os 5 repositorios locais estao sem alteracao pendente e a evidencia de segredos devolve vazio
  README com a tabela dos repositorios e a secao Atendimento dos requisitos da Fase 3
```

**Comite o que estiver pendente antes de gravar** — é justamente o que o preparo exige (arquivo **não rastreado** sai como `ATENCAO`, sem reprovar, mas confira antes). Se algum repositório aparecer com alteração, o preparo reprova com as linhas `FALHOU`.

**Na tela, deixe pronto:** uma aba com o `README.md` (tabela de repositórios + seção *Atendimento dos requisitos da Fase 3*) e **um terminal** (T1) limpo, em `fcg-orchestration`.

### Passo a passo na tela

1. **Navegador** — README: a tabela dos **5 repositórios** (com o link do repositório da função) e, em seguida, a seção **Atendimento dos requisitos da Fase 3** (requisito → onde está → como comprovar), na mesma ordem dos módulos do vídeo.

2. **T1** — "como subir tudo do zero" (mostre os comandos, **não** os valores):

   ```powershell
   # 1) Secrets (os valores sao SEUS; nada de credencial no repositorio):
   kubectl create -n default secret generic sqlserver-secret --from-literal=sa-password='<senha-do-sa>' --dry-run=client -o yaml | kubectl apply -n default -f -
   #    ... (os Secrets das APIs, do Grafana, do Mongo e do RabbitMQ -- secao "Segredos" do README)

   # 2) Manifestos: infraestrutura, APIs, Mongo, Redis, Prometheus, Grafana, Loki e Promtail
   kubectl apply -n default -f k8s/

   # 3) Gateway: renderiza a chave JWT do Secret, recria o kong-declarative-config e espera o rollout
   powershell -ExecutionPolicy Bypass -File scripts/deploy-kong.ps1
   ```

3. **T1** — a **evidência de segredos** (a mesma linha da tabela *Segredos fora do repositório* do README, e a mesma checagem `evidencia-de-segredos-vazia` que o preparo do módulo 6 faz): a prova de que nenhuma credencial foi versionada é a **varredura vazia**:

   ```powershell
   # Os tres -e (nunca -E com alternancia e pipe escapado): um -e por padrao, e o resultado VAZIO e a prova.
   # Os padroes vao MONTADOS por concatenacao de proposito: escritos inteiros, este proprio roteiro
   # apareceria no resultado (o git grep varre o repositorio todo e so o README.md esta excluido, porque
   # e ele que traz a linha da evidencia) -- o preflight-fase3.ps1 toma o mesmo cuidado.
   git grep -n -E -e ('Password=' + 'FCG@') -e ('Fcg2024' + 'Test!') -e ('fcg-secret-key' + '-2024') -- . ':!README.md'
   ```

   → **nenhuma linha** (nem no roteiro nem em nenhum arquivo). Uma linha encontrada *é* a credencial: se aparecer alguma, **pare** e corrija antes de gravar.

4. **T1** — a higiene final da gravação (o fecho do ciclo de segredo, agora que **cada módulo** apagou o próprio diretório de sessão):

   ```powershell
   # 1) alguma tomada deixou diretorio de sessao para tras? (so os NOMES, nunca o conteudo)
   Get-ChildItem -Path $env:TEMP -Filter 'fcg-demo-*' -Directory | Select-Object -ExpandProperty Name

   # 2) remocao de qualquer sobra e a prova de que nao ficou nada:
   Remove-Item -Path (Join-Path $env:TEMP 'fcg-demo-*') -Recurse -Force -ErrorAction SilentlyContinue
   (Get-ChildItem -Path $env:TEMP -Filter 'fcg-demo-*' -Directory | Measure-Object).Count      # 0
   ```

   → **`0`** na tela.

### Narração sugerida

- **(0:00–0:15, na tabela de repositórios)** "A entrega são cinco repositórios: a orquestração com os manifestos, o Kong e a observabilidade; as três APIs — UsersAPI, CatalogAPI e PaymentsAPI —; e a função de notificações, que é implantada pelo Terraform do repositório dela."
- **(0:15–0:25, na seção de requisitos)** "E aqui está o mapa: cada requisito da fase, onde ele está implementado e o comando que comprova — na mesma ordem do vídeo."
- **(0:25–0:35, nos comandos, na evidência e na higiene final)** "Nenhuma credencial é versionada: os manifestos guardam só o **nome** dos Secrets e a configuração do Kong é um **template** com o marcador `${JWT_SECRET}`, renderizado pelo script a partir do que já está no cluster. Esta varredura do repositório pelos padrões de senha volta **vazia** — é isso que ela tem de mostrar. A senha da demonstração viveu só na variável de ambiente da sessão, os diretórios de sessão das tomadas foram apagados e a varredura final mostra **zero**: nada com senha sobreviveu à gravação."

### Como saber que deu certo

- a tabela dos **5 repositórios** (incluindo o link do repositório da função) na tela;
- a seção **Atendimento dos requisitos da Fase 3** mostrada na íntegra;
- os três comandos de "como subir tudo" **sem nenhum valor de credencial** na tela (só `<placeholders>`);
- a **evidência de segredos** (`git grep` com os três `-e`) devolvendo **vazio** — nenhuma linha na tela;
- a varredura final imprimindo **`0`**;
- nenhuma janela com `.env`, token ou `secret` aberto.

### Se der errado

- **o preparo reprova em `repo-...-sem-alteracoes-pendentes`** → há arquivo modificado naquele repositório: comite (ou descarte) antes de gravar — a ideia é não aparecer nada "pendente" na tela.
- **a evidência de segredos não está vazia** → **pare**: há credencial versionada em algum arquivo. O preparo **não imprime as linhas encontradas de propósito** (uma linha encontrada *é* a credencial): rode o mesmo `git grep` na sua máquina, corrija e regrave.
- **`Remove-Item` com `-Path` e curinga não remove** → confira se há diretório aberto por algum processo (feche os terminais antigos) e rode de novo; o `Count` tem de terminar em `0`.
- **a seção de requisitos não existe no README** → o preparo reprova em `readme-com-secao-de-requisitos-da-fase-3`: confira se o README está na versão da entrega.

### Nota de edição

É o fecho: mantenha a tabela de repositórios e a seção de requisitos; o "como subir tudo" pode ficar só com os três comandos na tela e a higiene final pode virar um corte rápido mostrando o `0`. **Não corte** a seção *Atendimento dos requisitos da Fase 3*: é o mapa que a banca usa para conferir o enunciado. **Fim do vídeo:** feche os terminais da gravação (`Clear-History` + fechar a janela) e só então o navegador.

## Montagem

**Ordem das tomadas no corte final** (é a ordem dos módulos, e a mesma do README):

| Ordem | Arquivo | Módulo | Duração-alvo | Acumulado |
|---|---|---|---|---|
| 1 | `modulo-1-arquitetura.mp4` | Abertura e arquitetura | 0:35 | 0:00–0:35 |
| 2 | `modulo-2-gateway.mp4` | Gateway: roteamento e segurança | 2:15 | 0:35–2:50 |
| 3 | `modulo-3-serverless.mp4` | Função serverless + log centralizado | 2:15 | 2:50–5:05 |
| 4 | `modulo-4-observabilidade.mp4` | Observabilidade (Opção A) | 2:15 | 5:05–7:20 |
| 5 | `modulo-5-nosql.mp4` | NoSQL e cache | 1:35 | 7:20–8:55 |
| 6 | `modulo-6-repositorios.mp4` | Repositórios e fechamento | 0:35 | 8:55–9:30 |
| | | **Soma** | **9:30** | folga até o teto: **0:30** |

**Soma: 0:35 + 2:15 + 2:15 + 2:15 + 1:35 + 0:35 = 9:30**, com ~30 s de folga até o teto duro de **10:00** (o enunciado diz "até 10 minutos", então 10:01 descumpre). Se a soma das tomadas montadas passar de 9:30, corte **nesta ordem — a mais barata primeiro**:

1. o bloco do `port-forward` da Admin API do Kong com `/routes` e `/plugins` (**módulo 2**, passos 5–6) — o `401` sem token e o `200` com token já provam o gateway e a autenticação;
2. o `GET /api/jogos/{id}/avaliacoes/resumo` e o `hlen` (**módulo 5**) — o documento do `PUT`, a lista do `GET` e o `keys`/`ttl` do Redis já provam a persistência poliglota e o cache;
3. a segunda passada em `Status → Targets` e os 90 s do gerador acelerados (**módulo 4**), mantendo em tela o dashboard `FCG - APIs` com as séries mexendo e o painel de pagamentos reagindo à compra;
4. a narração dos *porquês* reduzida a uma frase por banco (**módulo 5**) e a abertura enxugada (**módulo 1**: o diagrama do README fala por si).

**Não corte em nenhuma hipótese:** o cadastro que acorda a função, a espera de ~15–30 s, o log da função **no Grafana** e a volta a zero (**módulo 3**); o `401`+`200` do **módulo 2**; a compra `202` com o painel de pagamentos mexendo (**módulo 4**); o documento do `PUT`/`GET` e a chave do Redis com TTL (**módulo 5**); e a seção *Atendimento dos requisitos da Fase 3* (**módulo 6**).

**Conferência final do vídeo montado** — os quatro itens do enunciado têm de estar visíveis, e os repositórios citados:

| Item do enunciado | Onde aparece no montado |
|---|---|
| 1. Requisições via **Gateway**, com roteamento e segurança | **Módulo 2** (0:35–2:50): `svc/kong`, `401` sem token, login `200`, `200` com token, `/routes` + plugin `jwt`, APIs `ClusterIP` |
| 2. **Função serverless** acionada, com o log **na plataforma** | **Módulo 3** (2:50–5:05): `0/0` → cadastro `201` → pod em ~15–30 s → `[EMAIL ENVIADO]` no Grafana/Loki → volta a zero |
| 3. **Dashboard do Grafana** com métricas em tempo real | **Módulo 4** (5:05–7:20): `FCG - APIs` em tela cheia com as séries mexendo, 3 alvos `up` no Prometheus, painel de pagamentos movendo por evento |
| 4. Como o **NoSQL** foi integrado | **Módulo 5** (7:20–8:55): `PUT`/`GET` de avaliações no Mongo (upsert), cache `catalog:*` no Redis com TTL e `cache_hit`/`cache_miss` |
| **Repositórios** da entrega | **Módulo 6** (8:55–9:30): os 5 repositórios (com o link da função) e a seção *Atendimento dos requisitos da Fase 3* |

Antes de exportar, confira também: nenhuma cena com `.env`, token, senha ou `secret` na tela; os quatro itens acima cobertos; e o vídeo fechando **antes de 10:00**.

## Apoio: o que o preflight garante

`scripts/preflight-fase3.ps1` é o que garante o estado da gravação. Sem parâmetro ele é o **preflight completo** (uma execução antes de começar a série de tomadas); com **`-Modulo N`** ele prepara **uma** tomada. Nos dois modos ele **acumula** falhas e termina com `exit 1` se qualquer checagem reprovar.

No modo completo ele verifica, além dos pods, dos **4 PVCs `Bound`** e do gateway: os **três alvos do job `fcg-apis`** no Prometheus, o Loki `ready` e com log recente da stack (o log **da função** é `ATENÇÃO` quando o rótulo ainda não existe nas últimas 24 h — o cadastro do módulo 3 gera esse log ao vivo —; com o rótulo presente ele exige **linhas** de verdade), o datasource e os dois dashboards do Grafana, as **três filas `notifications-*`** com o `ScaledObject Ready=True` (sem fila o KEDA cai em `TriggerError` e a **função simplesmente não sobe** — falha silenciosa que só apareceria na gravação), o Redis com as chaves `catalog:*`, o Mongo respondendo, o **usuário e os jogos de demonstração** e a **função em 0 réplicas** no estado inicial.

Sobre os dados de demonstração, ele garante **3 jogos** no catálogo, promove o usuário demo a Admin se precisar criar jogos (SQL por dentro do pod, digitado por **stdin**), **lê a biblioteca do usuário** (`GET /api/biblioteca/{userId}`) e escolhe/impressiona o **jogo da compra**: o primeiro do catálogo que o usuário **não** possui — é esse id que vai em `$env:FCG_DEMO_JOGO` e que os módulos 4 (compra) e 5 (avaliações) usam. A **compra de verificação** que ele faz usa **outro** jogo, de propósito: comprar o do vídeo consumiria a primeira compra daquele par (usuário, jogo), que é justamente a que devolve `202` e move o painel de pagamentos — e, se **não houver** outro jogo livre (o demo possui todos), o preparo do módulo 4 **cria um** só para essa compra, porque o contador `fcg_payments_processados_total` é anunciado no *Esperado no fim* daquela tomada e tem de estar provado antes de liberar a gravação. Tudo isso o modo por módulo (`-Modulo 4` e `-Modulo 5`) faz **só com o que aquela tomada precisa** — inclusive recriando um jogo livre novo a cada execução, que é o que protege o **retake**.

Ele também **exercita os comandos que só aparecem no vídeo**: as séries dos painéis em `/metrics` (pelo proxy do `kubectl`), a **compra** (`202`) e o `PUT`/`GET` de **avaliação** (upsert) — assim nenhum módulo leva um comando que nunca rodou. `scripts/demo-trafego.ps1 -Segundos 90` é o gerador do módulo 4; os dois leem a senha de `$env:FCG_DEMO_SENHA` e **não** têm senha padrão no arquivo.
