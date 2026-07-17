variable "aws_region" {
  description = "Région AWS où déployer l'infrastructure"
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Nom du projet, utilisé pour préfixer les ressources"
  type        = string
  default     = "devops-starter-kit"
}

variable "instance_type" {
  description = "Type d'instance EC2 pour le serveur k3s"
  type        = string
  default     = "t3.small"
}

variable "ssh_public_key_path" {
  description = "Chemin vers ta clé publique SSH (pour te connecter à l'instance)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "allowed_ssh_cidr" {
  description = "Plage d'IP autorisée à se connecter en SSH (mets TON IP publique en /32)"
  type        = string
}