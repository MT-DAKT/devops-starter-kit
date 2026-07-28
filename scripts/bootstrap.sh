#!/bin/bash
set -euo pipefail

echo "==> Starter Kit DevOps — Bootstrap complet"
echo "Ce script provisionne l'infrastructure AWS, configure k3s, et déploie l'app."
echo ""

# --- Vérifications préalables ---
command -v terraform >/dev/null 2>&1 || { echo "Terraform n'est pas installé."; exit 1; }
command -v ansible-playbook >/dev/null 2>&1 || { echo "Ansible n'est pas installé."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl n'est pas installé."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI n'est pas installé."; exit 1; }

if [ ! -f infra/terraform/terraform.tfvars ]; then
  echo "Fichier infra/terraform/terraform.tfvars manquant."
  echo "Copie infra/terraform/terraform.tfvars.example et renseigne ta propre IP (curl https://ifconfig.me)."
  exit 1
fi

# --- Étape 1 : Infrastructure ---
echo "==> [1/4] Provisionnement de l'infrastructure (Terraform)"
cd infra/terraform
terraform init -input=false
terraform apply -auto-approve
SERVER_IP=$(terraform output -raw instance_public_ip)
cd ../..

echo "==> Instance créée : $SERVER_IP"
echo "==> Mise à jour de l'inventory Ansible"
cat > infra/ansible/inventory.ini << INV
[k3s_server]
${SERVER_IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_ed25519
INV

echo "==> Attente que l'instance soit prête pour SSH (30s)"
sleep 30

# --- Étape 2 : Configuration k3s ---
echo "==> [2/4] Configuration du cluster k3s (Ansible)"

if [ -z "${GITHUB_RUNNER_TOKEN:-}" ]; then
  echo "Erreur : la variable GITHUB_RUNNER_TOKEN est requise."
  echo ""
  echo "Génère un token sur GitHub :"
  echo "  Settings > Actions > Runners > New self-hosted runner"
  echo ""
  echo "Puis relance :"
  echo "  GITHUB_RUNNER_TOKEN=xxx ./scripts/bootstrap.sh"
  exit 1
fi

cd infra/ansible
ansible-playbook -i inventory.ini playbook.yml --extra-vars "github_runner_token=${GITHUB_RUNNER_TOKEN}"
cd ../..

export KUBECONFIG="$(pwd)/infra/ansible/kubeconfig"

# --- Étape 3 : Déploiement de l'app ---
echo "==> [3/4] Déploiement des manifests Kubernetes"
kubectl apply -f k8s/base/

echo "==> Attente que les pods soient prêts"
kubectl rollout status deployment/api --timeout=120s
kubectl rollout status deployment/postgres --timeout=120s

# --- Étape 4 : Monitoring ---
echo "==> [4/4] Installation du monitoring (Prometheus + Grafana)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -f monitoring/helm-values/kube-prometheus-stack-values.yaml \
  --namespace monitoring \
  --create-namespace \
  --wait --timeout 5m

echo ""
echo "==> Bootstrap terminé !"
echo ""
echo "API :        http://${SERVER_IP}/health"
echo "Kubeconfig : export KUBECONFIG=$(pwd)/infra/ansible/kubeconfig"
echo "Grafana :    kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"