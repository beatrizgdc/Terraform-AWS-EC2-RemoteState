# =============================================================================
# OUTPUTS — Projeto Principal
# =============================================================================
# Outputs expõem atributos dos recursos criados após o `terraform apply`.
# São exibidos no terminal ao final do apply e ficam armazenados no state.
#
# USOS PRÁTICOS:
#   - Exibir o IP da instância para o usuário se conectar via SSH
#   - Compartilhar valores entre módulos (ex: passar o SG ID para outro módulo)
#   - Integrar com pipelines CI/CD que precisam do IP ou ID de recursos
#
# COMO ACESSAR APÓS O APPLY:
#   terraform output                    → todos os outputs
#   terraform output instance_public_ip → output específico
#   terraform output -json              → formato JSON (ideal para scripts)
#   terraform output -raw instance_public_ip → valor puro sem aspas (para shell)
# =============================================================================

output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "IP publico da instancia EC2."
}

output "instance_public_dns" {
  value       = aws_instance.web.public_dns
  description = "DNS publico da instancia EC2. Acesse o Nginx pelo navegador: http://<DNS>"
}

output "instance_id" {
  value       = aws_instance.web.id
  description = "ID da instancia EC2 (formato: i-0abc123...). Util para comandos AWS CLI."
}

output "ami_id_used" {
  value       = data.aws_ami.ubuntu.id
  description = "ID da AMI Ubuntu 22.04 utilizada. Confirma qual versao foi selecionada pelo data source."
}

output "ami_name_used" {
  value       = data.aws_ami.ubuntu.name
  description = "Nome completo da AMI — inclui a versao de build exata. Util para auditoria."
}

output "security_group_id" {
  value       = aws_security_group.web.id
  description = "ID do Security Group criado. Util para adicionar regras adicionais ou associar a outros recursos."
}

output "private_key_path" {
  value       = local_file.private_key.filename
  description = "Caminho da chave privada gerada pelo Terraform. Use este arquivo para conectar via SSH."
}

output "ssh_command" {
  value       = "ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.web.public_ip}"
  description = "Comando SSH pronto para uso. Cole no terminal para conectar na instancia."
}

output "nginx_url" {
  value       = "http://${aws_instance.web.public_ip}"
  description = "URL do Nginx. Aguarde ~60 segundos apos o apply para o user_data terminar de instalar o Nginx."
}

