# =============================================================================
# VARIABLES — Bootstrap
# =============================================================================
# Todas as variáveis com type + description + default quando aplicável.
# Essa tríade é uma boa prática: type garante validação em tempo de plan,
# description serve como documentação viva, default evita prompts
# interativos para valores que raramente mudam.
# =============================================================================

variable "aws_region" {
  type        = string
  description = "Região AWS onde o bucket S3 e a tabela DynamoDB serão criados. Deve ser a mesma região que o projeto principal vai usar."
  default     = "us-east-2"
}

variable "state_bucket_prefix" {
  type        = string
  description = "Prefixo do nome do bucket S3. O Account ID da AWS será concatenado automaticamente para garantir unicidade global."
  default     = "terraform-state-demo"
}

variable "dynamodb_table_name" {
  type        = string
  description = "Nome da tabela DynamoDB usada para state locking. O Terraform exige o atributo 'LockID' (String) como hash key."
  default     = "terraform-state-lock"
}

variable "environment" {
  type        = string
  description = "Nome do ambiente para fins de tag. Ex: dev, staging, prod."
  default     = "demo"
}

variable "owner" {
  type        = string
  description = "Responsável pelos recursos — usado nas tags para rastreabilidade."
  default     = "time-infra"
}

variable "project_name" {
  type        = string
  description = "Nome do projeto — usado nas tags para agrupamento no Cost Explorer."
  default     = "terraform-demo"
}
