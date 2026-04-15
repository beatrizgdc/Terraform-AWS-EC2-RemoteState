# =============================================================================
# OUTPUTS — Bootstrap
# =============================================================================
# Após o apply, esses valores serão exibidos no terminal.
# São essenciais para a configuração do backend no projeto principal:
# o nome do bucket e da tabela precisam ser copiados para o backend.tf.
#
# DICA: para buscar os outputs a qualquer momento após o apply, execute:
#   terraform output
#   terraform output -json   (formato JSON para scripts)
# =============================================================================

output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "Nome do bucket S3 criado para armazenar o terraform.tfstate. Copie este valor para o backend.tf do projeto principal."
}

output "state_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "ARN do bucket S3 — útil para configurar políticas IAM de acesso ao state."
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_lock.name
  description = "Nome da tabela DynamoDB para state locking. Copie este valor para o backend.tf do projeto principal."
}

output "aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "Account ID da conta AWS utilizada — confirma que o apply rodou na conta correta."
}
