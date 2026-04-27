# =============================================================================
# VARIABLES — Projeto Principal
# =============================================================================
# Todas as variáveis com type + description + default.
#
# BOAS PRÁTICAS APLICADAS:
#   - type   → validação em tempo de plan, não de apply (falha mais cedo)
#   - description → documentação viva junto ao código
#   - default    → evita prompts interativos para valores padrão razoáveis
#   - validation → validação customizada com mensagem de erro clara
# =============================================================================

# -----------------------------------------------------------------------------
# Configurações AWS
# -----------------------------------------------------------------------------

variable "aws_region" {
  type        = string
  description = "Região AWS onde todos os recursos serão provisionados. Altere para sa-east-1 para São Paulo, us-west-2 para Oregon, etc."
  default     = "us-east-2"
}

# -----------------------------------------------------------------------------
# Identificação e Tags
# -----------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Nome do projeto — usado em tags e como prefixo de nomes de recursos para facilitar identificação no console AWS."
  default     = "terraform-demo"
}

variable "environment" {
  type        = string
  description = "Nome do ambiente. Usado em tags e no nome dos recursos para separar dev, staging e prod na mesma conta."
  default     = "dev"

  # VALIDATION: garante que apenas valores esperados sejam aceitos.
  # O erro aparece no `terraform plan`, antes de qualquer recurso ser criado.
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "O ambiente deve ser um dos valores: dev, staging, prod, demo."
  }
}

variable "owner" {
  type        = string
  description = "Responsável pelos recursos — nome ou e-mail do time/pessoa. Aparece nas tags para rastreabilidade e billing."
  default     = "time-infra"
}

# -----------------------------------------------------------------------------
# Instância EC2
# -----------------------------------------------------------------------------

variable "instance_type" {
  type        = string
  description = "Tipo da instância EC2. t2.micro está no free tier da AWS. Use t3.small ou superior para cargas reais."
  default     = "t2.micro"

  validation {
    condition     = contains(["t2.micro", "t2.small", "t2.medium", "t3.micro", "t3.small"], var.instance_type)
    error_message = "Use um dos tipos permitidos: t2.micro, t2.small, t2.medium, t3.micro, t3.small."
  }
}

variable "public_key_path" {
  type        = string
  description = "Caminho absoluto ou relativo para a chave pública SSH local. O conteúdo deste arquivo será enviado para a AWS como Key Pair. Ex: ~/.ssh/id_rsa.pub"
  default     = "~/.ssh/id_rsa.pub"
}

variable "key_pair_name" {
  type        = string
  description = "Nome do Key Pair que será criado na AWS. Deve ser único por região."
  default     = "terraform-demo-key"
}

# -----------------------------------------------------------------------------
# Rede / Acesso
# -----------------------------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = "ID da VPC onde o Security Group e a instância EC2 serão criados. Use `aws ec2 describe-vpcs` para listar as VPCs disponíveis na sua conta. Se não informado, os recursos serão criados na VPC padrão da região."
  default     = null

  # NOTA: Em produção, sempre especifique explicitamente o VPC ID.
  # A VPC padrão pode não ter as configurações de segurança adequadas.
  # Execute: aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId"
}

variable "allowed_ssh_cidr" {
  type        = list(string)
  description = "Lista de CIDRs com permissão para acesso SSH (porta 22). Use seu IP público em produção: ['SEU_IP/32']. O valor padrão 0.0.0.0/0 é adequado apenas para demonstração."
  default     = ["0.0.0.0/0"]

  # NOTA PARA APRESENTAÇÃO: em produção, nunca use 0.0.0.0/0 na porta 22.
  # Substitua pelo IP do escritório/VPN: ["200.100.50.25/32"]
}

variable "allowed_http_cidr" {
  type        = list(string)
  description = "Lista de CIDRs com permissão para acesso HTTP (porta 80). 0.0.0.0/0 libera acesso público ao Nginx."
  default     = ["0.0.0.0/0"]
}
