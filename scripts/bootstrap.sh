#!/bin/bash
set -euo pipefail

echo "==> Starter Kit DevOps — Bootstrap complet"
echo "Ce script provisionne l'infrastructure AWS, configure k3s, installe ArgoCD,"
echo "connecte le chart Helm, et installe le monitoring."
echo ""

# --- Vérifications préalables ---
command -v terraform >/dev/null 2>&1 || { echo "Terraform n'est pas installé."; exit 1; }
command -v ansible-playbook >/dev/null 2>&1 || { echo "Ansible n'est pas installé."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl n'est pas installé."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "Helm n'est pas installé."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI n'est pas installé."; exit 1; }

if [ ! -f infra/terraform/terraform.tfvars ]; then
  echo "Fichier infra/terraform/terraform.tfvars manquant."
  echo "Copie infra/terraform/terraform.tfvars.example et renseigne ta propre IP (curl https://ifconfig.me)."
  exit 1
fi

# --- Étape 1 : Infrastructure ---
echo "==> [1/5] Provisionnement de l'infrastructure (Terraform)"
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
echo "==> [2/5] Configuration du cluster k3s (Ansible)"
cd infra/ansible
ansible-playbook -i inventory.ini playbook.yml
cd ../..

export KUBECONFIG="$(pwd)/infra/ansible/kubeconfig"

# --- Étape 3 : ArgoCD ---
echo "==> [3/5] Installation d'ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
echo "==> Attente qu'ArgoCD soit prêt"
kubectl wait --for=condition=available --timeout=180s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=180s deployment/argocd-repo-server -n argocd

# --- Étape 4 : Secret DB + connexion ArgoCD au chart Helm ---
echo "==> [4/5] Création du secret de base de données et de l'Application ArgoCD"
if ! kubectl get secret api-secrets >/dev/null 2>&1; then
  if [ -z "${DB_PASSWORD:-}" ]; then
    echo "Variable DB_PASSWORD non définie."
    echo "Relance avec : DB_PASSWORD=xxx ./scripts/bootstrap.sh"
    exit 1
  fi
  kubectl create secret generic api-secrets \
    --from-literal=postgres-password="${DB_PASSWORD}" \
    --from-literal=database-url="postgresql://postgres:${DB_PASSWORD}@postgres-svc:5432/appdb"
else
  echo "Secret api-secrets déjà présent, on ne le recrée pas."
fi

kubectl apply -f argocd/application.yaml
echo "==> Attente que l'Application soit synchronisée"
sleep 20
kubectl get application devops-starter-kit -n argocd

# --- Étape 5 : Monitoring ---
echo "==> [5/5] Installation du monitoring (Prometheus + Grafana)"
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
echo "ArgoCD :     kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "Grafana :    kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
