# =============================================================================
# LOCALS — Projeto Principal
# =============================================================================
# Locals são valores calculados internamente pelo Terraform.
# Diferente de variáveis (input externo), locals são computados a partir
# de outros valores e não podem ser sobrescritos de fora do código.
#
# QUANDO USAR LOCALS vs VARIÁVEIS:
#   - Variável → valor que vem de fora (tfvars, CLI, env var)
#   - Local    → valor calculado internamente, derivado de outros valores
#
# BENEFÍCIO PRINCIPAL das tags via locals:
# Todos os recursos do projeto compartilham as mesmas tags base.
# Se o nome do Owner mudar, altera em UM lugar e todos os recursos
# recebem o valor atualizado no próximo apply.
# =============================================================================

locals {
  # -------------------------------------------------------------------------
  # Tags comuns — aplicadas em TODOS os recursos via tags = local.common_tags
  # O merge() em cada recurso permite adicionar tags específicas por recurso
  # sem perder as tags comuns.
  # -------------------------------------------------------------------------
  common_tags = {
    Environment = var.environment
    Owner       = var.owner
    Project     = var.project_name
    # ManagedBy já vem do default_tags no provider.tf
    # Região é visível no console AWS — não duplicamos aqui
  }

  # -------------------------------------------------------------------------
  # Prefixo de nomes — padrão consistente para todos os recursos
  # Exemplo: "terraform-demo-dev"
  # -------------------------------------------------------------------------
  name_prefix = "${var.project_name}-${var.environment}"

  # -------------------------------------------------------------------------
  # Nomes de recursos — centralizados aqui para fácil manutenção.
  # Em vez de espalhar strings pelo código, ajuste tudo neste único lugar.
  # -------------------------------------------------------------------------
  key_name            = "${local.name_prefix}-key"
  security_group_name = "${local.name_prefix}-sg"
  instance_name       = "${local.name_prefix}-webserver"
}
