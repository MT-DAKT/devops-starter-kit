output "instance_public_ip" {
  description = "Adresse IP publique du serveur"
  value       = aws_instance.server.public_ip
}

output "ssh_command" {
  description = "Commande prête à copier-coller pour se connecter en SSH"
  value       = "ssh ubuntu@${aws_instance.server.public_ip}"
}

output "instance_id" {
  description = "ID de l'instance EC2 (utile pour la console AWS ou aws cli)"
  value       = aws_instance.server.id
}