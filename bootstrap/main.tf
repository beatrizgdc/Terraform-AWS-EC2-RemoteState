# =============================================================================
# BOOTSTRAP — Remote State Infrastructure
# =============================================================================
# Este diretório cria os recursos necessários para o remote state ANTES
# de qualquer outra coisa. Ele é executado UMA ÚNICA VEZ, manualmente,
# com estado local (sem backend remoto configurado ainda).
#
# POR QUE SEPARADO?
# Não é possível usar um bucket S3 como backend se ele ainda não existe.
# Criamos primeiro com estado local, depois o projeto principal usa esse
# bucket como backend.
#
# ORDEM DE EXECUÇÃO:
#   1. cd bootstrap/ && terraform init && terraform apply
#   2. Anote o nome do bucket e da tabela nos outputs
#   3. cd ../project/ && terraform init && terraform apply
# =============================================================================


# -----------------------------------------------------------------------------
# S3 BUCKET — Armazenamento do terraform.tfstate
# -----------------------------------------------------------------------------
# O bucket precisa ter um nome globalmente único na AWS.
# Usamos uma combinação de prefixo + Account ID para garantir unicidade
# sem precisar inventar um nome aleatório.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"

  # LIFECYCLE — prevent_destroy é a regra mais importante deste projeto.
  # Se o bucket for deletado, o Terraform perde o estado de TODA a infra
  # e não consegue mais gerenciar os recursos criados.
  # Um `terraform destroy` vai falhar com erro explícito em vez de apagar.
  lifecycle {
    prevent_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.state_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
  })
}

# -----------------------------------------------------------------------------
# S3 BUCKET VERSIONING — Histórico de versões do tfstate
# -----------------------------------------------------------------------------
# Com versionamento ativo, cada `terraform apply` gera uma nova versão
# do arquivo de estado no S3. Isso permite:
#   - Recuperar um estado anterior em caso de corrupção
#   - Auditar o que mudou e quando
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# S3 BUCKET ENCRYPTION — Criptografia em repouso
# -----------------------------------------------------------------------------
# O tfstate pode conter dados sensíveis: IPs, IDs de recursos, ARNs.
# SSE-S3 criptografa o arquivo automaticamente sem custo adicional.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# S3 BLOCK PUBLIC ACCESS — Bloqueia qualquer acesso público ao bucket
# -----------------------------------------------------------------------------
# Por padrão, buckets S3 podem ter políticas que permitem acesso público.
# Este recurso garante que NUNCA será possível tornar o bucket público,
# independente de qualquer política que seja criada no futuro.
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# DYNAMODB TABLE — State Locking
# -----------------------------------------------------------------------------
# Impede que dois `terraform apply` rodem ao mesmo tempo no mesmo estado.
#
# COMO FUNCIONA:
#   1. Antes de qualquer operação, o Terraform cria um item com chave "LockID"
#   2. Se o item já existe, outro processo está rodando — Terraform aguarda/falha
#   3. Ao terminar, o item é deletado, liberando o lock para o próximo
#
# O atributo "LockID" com tipo "S" (String) é OBRIGATÓRIO — é o contrato
# entre o Terraform e o DynamoDB para o mecanismo de locking funcionar.
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # cobra por operação, sem capacidade provisionada
  hash_key     = "LockID"          # chave primária obrigatória para o Terraform

  attribute {
    name = "LockID"
    type = "S" # S = String
  }

  tags = merge(local.common_tags, {
    Name = var.dynamodb_table_name
  })
}

# -----------------------------------------------------------------------------
# DATA SOURCE — AWS Caller Identity
# -----------------------------------------------------------------------------
# Lê o Account ID da conta AWS autenticada no momento do plan/apply.
# Usamos o Account ID para compor um nome de bucket globalmente único,
# sem precisar hardcodar valores ou usar sufixos aleatórios.
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}
