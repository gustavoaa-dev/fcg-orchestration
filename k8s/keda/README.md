# KEDA (escala a zero da função de notificações)

O operador é instalado pelo manifesto oficial de release (não há Helm neste ambiente):

```powershell
kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.20.2/keda-2.20.2.yaml
kubectl get pods -n keda
kubectl get crd scaledobjects.keda.sh
```

A função de notificações é implantada a partir do repositório próprio
(`fcg-notifications-function`), cujo Terraform declara o `Deployment`, o `TriggerAuthentication` e o
`ScaledObject`. Este diretório guarda apenas o procedimento do operador: **não** há manifesto da função
aqui, e um `kubectl apply -f k8s/` deste repositório não implanta a função.

> O `kubectl apply -f k8s/` **não** entra neste subdiretório (ele não é recursivo), então o operador do
> KEDA nunca é instalado pelo fluxo normal do README — os três comandos acima são um passo à parte,
> executado **antes** do `terraform apply` do repositório da função (os recursos `keda.sh/v1alpha1` só
> existem com a CRD instalada).

Verificação rápida:

```powershell
kubectl get scaledobject notifications-function -o wide   # READY=True
kubectl get pods -l app=notifications-function            # vazio em repouso (minReplicaCount: 0)
```

Esperado em repouso: os três pods do KEDA `Running` no namespace `keda` — o operador, o
metrics-apiserver e o admission webhook (`keda-operator-*`, `keda-metrics-apiserver-*` e
`keda-admission-*`, nomes conferidos em runtime), o `ScaledObject` com `READY=True`, e **nenhum** pod
da função — as duas filas vazias mantêm a função em **0 réplicas**, e ela só sobe quando chega
mensagem em `notifications-user-created` ou `notifications-payment-processed`.
