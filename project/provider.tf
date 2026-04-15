# =============================================================================
# PROVIDER — Projeto Principal
# =============================================================================
# Este arquivo define:
#   1. A versão mínima do Terraform aceita
#   2. Os providers necessários e suas version constraints
#   3. A configuração de autenticação com a AWS
#
# AUTENTICAÇÃO AWS — o provider busca credenciais nesta ordem:
#   1. Argumentos no bloco provider (access_key / secret_key) — NÃO recomendado
#   2. Variáveis de ambiente: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
#   3. Arquivo ~/.aws/credentials (configurado via `aws configure`)
#   4. IAM Role da instância EC2 / ECS Task (em ambientes AWS)
#
# Para este projeto, usamos o método 3 (aws configure) ou 2 (env vars).
# =============================================================================

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # ~> 5.0 = aceita 5.x, bloqueia 6.0 (possível breaking change)
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
      # Usado para gerar o par de chaves SSH automaticamente
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
      # Usado para salvar a chave privada em disco
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Região configurável por variável — o mesmo código funciona em us-east-1,
  # sa-east-1 ou qualquer outra região sem alteração no código.

  # PERFIL AWS CLI — escolha qual perfil será usado para criar os recursos.
  # Execute `aws configure list-profiles` para ver os perfis disponíveis.
  # Se omitido, o Terraform usa o perfil "default".
  # Descomente e ajuste conforme necessário:
  #
  # profile                 = "msp2"                    # nome do perfil AWS CLI
  # shared_config_files     = ["~/.aws/config"]         # caminho para o config da AWS CLI
  # shared_credentials_files = ["~/.aws/credentials"]  # caminho para as credenciais da AWS CLI

  # default_tags aplica tags em TODOS os recursos deste provider
  # automaticamente — funciona em conjunto com as tags específicas
  # de cada recurso (as tags se mesclam, não se sobrescrevem).
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = var.project_name
    }
  }
}
