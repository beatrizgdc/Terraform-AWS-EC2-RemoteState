# =============================================================================
# PROVIDER — Bootstrap
# =============================================================================
# Define o provedor AWS e a versão mínima do Terraform aceita para este
# módulo de bootstrap.
#
# VERSION CONSTRAINTS — por que ~> 5.0?
#   ~> é o "pessimistic constraint operator":
#   - Aceita qualquer versão 5.x (ex: 5.1, 5.20, 5.99)
#   - NUNCA aceita 6.0 (que pode ter breaking changes)
#   Isso garante que atualizações de patch acontecem automaticamente,
#   mas mudanças incompatíveis são bloqueadas até uma decisão consciente.
# =============================================================================

terraform {
  # Versão mínima do binário Terraform aceita
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # NOTA: este módulo bootstrap INTENCIONALMENTE não tem backend remoto.
  # Ele salva o tfstate LOCALMENTE porque o bucket S3 ainda não existe.
  # Após o apply, o estado local (terraform.tfstate) deve ser guardado
  # em um local seguro — ele é pequeno e contém apenas 2 recursos.
}

provider "aws" {
  region = var.aws_region

  # PERFIL AWS CLI — escolha qual perfil será usado para criar os recursos.
  # Execute `aws configure list-profiles` para ver os perfis disponíveis.
  # Se omitido, o Terraform usa o perfil "default".
  # Descomente e ajuste conforme necessário:
  #
  # profile                 = "msp2"                    # nome do perfil AWS CLI
  # shared_config_files     = ["~/.aws/config"]         # caminho para o config da AWS CLI
  # shared_credentials_files = ["~/.aws/credentials"]  # caminho para as credenciais da AWS CLI

  # Boas práticas: tags padrão aplicadas em TODOS os recursos criados
  # por este provider, automaticamente, sem precisar declarar em cada recurso.
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Module    = "bootstrap"
    }
  }
}
