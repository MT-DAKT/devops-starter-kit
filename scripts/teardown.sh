#!/bin/bash
set -euo pipefail

echo "==> Destruction de l'infrastructure DevOps Starter Kit"
read -p "Es-tu sûr ? Cette action est irréversible (y/N) " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Annulé."
  exit 0
fi

echo "==> Suppression du monitoring"
export KUBECONFIG="$(pwd)/infra/ansible/kubeconfig"
helm uninstall monitoring -n monitoring 2>/dev/null || echo "Monitoring déjà absent, on continue."

echo "==> Destruction de l'infrastructure Terraform"
cd infra/terraform
terraform destroy -auto-approve
cd ../..

echo "==> Terminé. L'infrastructure AWS a été détruite."