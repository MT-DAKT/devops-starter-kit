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

## Étape 5 — Générer un token de runner GitHub

Sur ton repo GitHub : **Settings → Actions → Runners → New self-hosted runner**, copie le token affiché (expire après 1h).

## Étape 6 — Configurer le serveur (k3s + runner)

```bash
cd ../ansible
ansible-playbook -i inventory.ini playbook.yml --extra-vars "github_runner_token=TON_TOKEN"
```

## Étape 7 — Configurer les secrets GitHub

Sur ton repo → **Settings → Secrets and variables → Actions**, crée :
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN` (token Read & Write)

## Étape 8 — Déployer l'application

```bash
export KUBECONFIG=$(pwd)/kubeconfig
cd ..
kubectl apply -f k8s/base/
```

Crée le secret de connexion à la base de données (jamais commité) :

```bash
kubectl create secret generic api-secrets \
  --from-literal=postgres-password='CHOISIS_UN_MOT_DE_PASSE' \
  --from-literal=database-url='postgresql://postgres:CHOISIS_UN_MOT_DE_PASSE@postgres-svc:5432/appdb'
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

## Nettoyage

```bash
./scripts/teardown.sh
```
EOF