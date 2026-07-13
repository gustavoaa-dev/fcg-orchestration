# FCG - Orquestração

Repositório central de infraestrutura da plataforma **Facul Cloud Games**. Contém a configuração de containers Docker e os manifestos para deploy no Kubernetes.

## Arquitetura

A plataforma é composta por 4 microsserviços independentes que se comunicam de forma assíncrona via RabbitMQ:

| Serviço | Repositório | Responsabilidade |
|---|---|---|
| UsersAPI | [fcg-users-api](https://github.com/gustavoaa-dev/fcg-users-api) | Cadastro e autenticação de usuários |
| CatalogAPI | [fcg-catalog-api](https://github.com/gustavoaa-dev/fcg-catalog-api) | Catálogo de jogos e biblioteca |
| PaymentsAPI | [fcg-payments-api](https://github.com/gustavoaa-dev/fcg-payments-api) | Processamento de pagamentos |
| NotificationsAPI | [fcg-notifications-api](https://github.com/gustavoaa-dev/fcg-notifications-api) | Envio de notificações |

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

| Serviço | Porta |
|---|---|
| UsersAPI | `http://localhost:5001` |
| CatalogAPI | `http://localhost:5002` |
| PaymentsAPI | `http://localhost:5003` |
| NotificationsAPI | `http://localhost:5004` |
| RabbitMQ Management | `http://localhost:15672` (guest/guest) |
| SQL Server | `localhost:1433` (sa/FCG@Password123) |

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

```bash
cd fcg-orchestration/k8s
kubectl apply -f .
```

### Verificar o deploy

```bash
kubectl get pods
kubectl get services
```

Todos os 6 pods devem estar com status `Running`.

### Acessar as APIs

```bash
# UsersAPI (NodePort 30001)
kubectl port-forward svc/users-api 8080:80

# CatalogAPI (NodePort 30002)
kubectl port-forward svc/catalog-api 8080:80
```

### Remover o deploy

```bash
kubectl delete -f .
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
│   └── notifications-api-deployment.yaml
└── README.md
```
