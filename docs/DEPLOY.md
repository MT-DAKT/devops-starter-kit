cat > docs/DEPLOY.md << 'EOF'
# Guide de déploiement

## Prérequis

- Un compte AWS, avec le plan de facturation permettant les instances `t3.medium` (le plan "Free Plan" restreint de certains comptes récents bloque ce type — vérifier dans Billing si besoin)
- Un utilisateur IAM dédié avec accès programmatique (jamais le compte root)
- Terraform, Ansible, kubectl, Helm, AWS CLI installés (voir versions testées ci-dessous)
- Une paire de clés SSH (`ssh-keygen -t ed25519`)
- Un compte Docker Hub avec un token **Read & Write**
- Un compte GitHub avec le repo cloné

### Environnement testé

Ce projet a été construit et validé sous **WSL2 (Ubuntu)** sur Windows — les outils Terraform/Ansible/kubectl doivent être installés dans WSL, pas seulement côté Windows (les deux environnements ont des installations et configurations séparées).

## Étape 1 — Configuration AWS

```bash
aws configure
aws sts get-caller-identity   # vérifie l'authentification
```

## Étape 2 — Variables Terraform

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
```

Édite `terraform.tfvars` :

```hcl
allowed_ssh_cidr    = "TON_IP/32"   # trouve-la avec: curl https://ifconfig.me
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
instance_type        = "t3.medium"   # t3.small insuffisant, voir docs/ARCHITECTURE.md
```

## Étape 3 — Provisionner l'infrastructure

```bash
cd infra/terraform
terraform init
terraform plan     # vérifier avant d'appliquer
terraform apply
```

Récupère l'IP publique affichée en sortie.

## Étape 4 — Configurer l'inventory Ansible

```bash
cat > ../ansible/inventory.ini << INV
[k3s_server]
<IP_AFFICHÉE> ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519
INV
```

## Étape 5 — Configurer les secrets GitHub

Sur ton repo → **Settings → Secrets and variables → Actions**, crée :
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN` (token Read & Write)

Va aussi dans **Settings → Actions → General → Workflow permissions**, sélectionne **Read and write permissions** — nécessaire pour que le pipeline puisse committer la mise à jour du tag d'image dans `k8s/base/deployment.yaml`.

## Étape 6 — Installer ArgoCD

```bash
export KUBECONFIG=$(pwd)/infra/ansible/kubeconfig
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd   # attendre que tout soit Running
```

Récupère le mot de passe admin initial :

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Étape 7 — Créer le secret de base de données

```bash
kubectl create secret generic api-secrets \
  --from-literal=postgres-password='CHOISIS_UN_MOT_DE_PASSE' \
  --from-literal=database-url='postgresql://postgres:CHOISIS_UN_MOT_DE_PASSE@postgres-svc:5432/appdb'
```

## Étape 8 — Connecter ArgoCD au chart Helm

```bash
kubectl apply -f argocd/application.yaml
```

ArgoCD va détecter et déployer automatiquement tout ce que génère le chart `helm/devops-starter-kit/` — pas de `helm install` manuel nécessaire pour l'app elle-même (Helm reste utilisé directement uniquement pour le monitoring, voir étape 9).

Pour vérifier le rendu du chart avant de le laisser à ArgoCD :

```bash
helm template devops-starter-kit helm/devops-starter-kit/
```

## Étape 9 — Installer le monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -f monitoring/helm-values/kube-prometheus-stack-values.yaml \
  --namespace monitoring --create-namespace
```

## Étape 10 — Vérifier

```bash
curl http://<IP_PUBLIQUE>/health
kubectl get pods -A
```

Push un commit sur `main` pour valider que le pipeline CD déploie automatiquement.

## Problèmes fréquents

| Symptôme | Cause probable | Solution |
|---|---|---|
| SSH timeout | Ton IP a changé depuis `terraform.tfvars` | Mets à jour `allowed_ssh_cidr` et `terraform apply` |
| `kubectl` : TLS handshake timeout | Instance surchargée en mémoire | Vérifie `free -h` en SSH, upgrade l'instance si besoin |
| `ErrImagePull` sur les pods `api` | Image pas encore poussée sur Docker Hub | Vérifie le pipeline CD dans GitHub Actions |
| Certificat TLS invalide (`kubectl`) | IP publique absente du `tls-san` de k3s | Vérifie la tâche `tls-san` du playbook Ansible |
| `No data` dans Grafana pour l'app | Le `Service` n'a pas de `metadata.labels` | Le `ServiceMonitor` filtre sur les labels du Service, pas son `selector` — voir `k8s/base/service.yaml` |
| `app path does not exist` (ArgoCD) | Le chart Helm n'a pas été poussé sur GitHub avant la sync | `git add helm/ && git push`, puis Refresh dans ArgoCD |
| Pipeline CD échoue sur `sed: can't read` | Le chemin ciblé par `sed` dans `cd.yml` ne correspond plus à la structure actuelle | Vérifier que `cd.yml` cible bien `helm/devops-starter-kit/values.yaml`, pas `k8s/base/deployment.yaml` |
| Trivy bloque la CI sur des CVE sans correctif | Vulnérabilités OS sans patch amont disponible | Documenter et lister dans `app/.trivyignore` avec justification |

## Nettoyage

```bash
./scripts/teardown.sh
```
