# =============================================================================
# BACKEND — Remote State com S3 + DynamoDB
# =============================================================================
# Define ONDE o arquivo terraform.tfstate será armazenado.
#
# POR QUE REMOTE STATE?
# ┌─────────────────────────────────────────────────────┐
# │  Estado LOCAL                │  Estado REMOTO (S3)  │
# ├─────────────────────────────────────────────────────┤
# │  Preso na máquina de uma     │  Acessível por       │
# │  única pessoa                │  qualquer membro     │
# │                              │  do time             │
# ├─────────────────────────────────────────────────────┤
# │  Sem histórico de versões    │  Versionamento S3    │
# │                              │  guarda versões      │
# │                              │  anteriores          │
# ├─────────────────────────────────────────────────────┤
# │  Sem proteção contra         │  State locking via   │
# │  operações simultâneas       │  DynamoDB            │
# └─────────────────────────────────────────────────────┘
#
# PRÉ-REQUISITO: execute o bootstrap/ antes deste projeto.
# Os valores de bucket, key e dynamodb_table vêm dos outputs do bootstrap.
#
# ATENÇÃO: após alterar este bloco, sempre execute `terraform init`
# para que o Terraform reconecte ao backend correto.
# =============================================================================

terraform {
  backend "s3" {
    # Nome do bucket criado pelo bootstrap
    # Substitua pelo valor do output: terraform output state_bucket_name
    bucket = "terraform-state-demo-<SEU-ACCOUNT-ID>"

    # Caminho do arquivo dentro do bucket — funciona como uma "pasta"
    # Convenção: <projeto>/<ambiente>/terraform.tfstate
    key = "demo/terraform.tfstate"

    # Região onde o bucket S3 foi criado (deve ser a mesma do bootstrap)
    region = "us-east-1"

    # Tabela DynamoDB para state locking
    # Substitua pelo valor do output: terraform output dynamodb_table_name
    # dynamodb_table = "terraform-state-lock"  # Deprecated — substituído por use_lockfile
    use_lockfile   = true

    # Criptografia em trânsito — o estado é criptografado ao ser
    # enviado e recebido do S3
    encrypt = true
  }
}
