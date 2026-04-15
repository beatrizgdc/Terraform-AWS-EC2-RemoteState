# =============================================================================
# LOCALS — Bootstrap
# =============================================================================
# Locals são valores calculados internamente — diferente de variáveis,
# não recebem valores externos. São ideais para valores derivados ou
# para evitar repetição de código.
#
# PADRÃO DE TAGS:
# Definir as tags em um local e referenciar com local.common_tags em
# cada recurso garante consistência. Se o valor de Owner mudar,
# alteramos em UM único lugar e todos os recursos são atualizados.
# =============================================================================

locals {
  common_tags = {
    Environment = var.environment
    Owner       = var.owner
    Project     = var.project_name
  }
}
