# Política de Nomenclatura – Terraform & Terragrunt

**Autor: Raul Rodrigues Soares**

Este documento define a política oficial de nomenclatura para recursos, módulos, diretórios e arquivos utilizados em projetos de Terraform e Terragrunt.

Seu objetivo é garantir padronização, clareza, previsibilidade e facilidade de manutenção, especialmente em cenários multi-ambiente e multi-cloud.

---

## 1. Princípios Gerais

- Nomes devem ser claros, previsíveis e legíveis
- Evitar abreviações não padronizadas
- Priorizar consistência ao invés de preferências pessoais
- Todo nome deve permitir identificar provedor, tipo de recurso e contexto

---

## 2. Nomenclatura de Diretórios de Módulos Terraform

### Regra obrigatória

Todo diretório de módulo Terraform **DEVE** iniciar com o nome do provedor.

**Formato padrão:**

```
<provider>_<recurso>
```

**Exemplos válidos ✅**

```
aws_vpc
aws_ec2
aws_rds
azurerm_vnet
azurerm_key_vault
google_compute_instance
```

**Exemplos inválidos ⚠️**

```
vpc
ec2_module
network
database
```

**Por quê?**

- Facilita identificação rápida do provedor
- Evita conflitos em ambientes multi-cloud
- Melhora navegação e entendimento do repositório
- Padroniza automações e validações futuras

---

## 3. Nomenclatura de Diretórios por Ambiente

Ambientes devem utilizar nomes curtos, padronizados e previsíveis:

```
dev
qa
hml
staging
prod
```

**Evitar ⚠️**

```
development
production
homologacao
```

---

## 4. Nomenclatura de Regiões

Os diretórios de região devem seguir exatamente o identificador oficial do provedor.

**Exemplo AWS:**

```
us-east-1
us-west-2
sa-east-1
```

---

## 5. Nomenclatura de Recursos Terraform

**Padrão geral:**

- Utilizar `snake_case`
- Evitar nomes genéricos como `this`, `default`, `main`
- O nome deve refletir a função do recurso

**Exemplo:**

```hcl
resource "aws_vpc" "core_network" {}
resource "aws_subnet" "private_app" {}
resource "aws_security_group" "ec2_app" {}
```

---

## 6. Nomenclatura de Variáveis

**Formato:** `snake_case`

**Exemplos:**

```hcl
variable "vpc_cidr" {}
variable "instance_type" {}
variable "enable_public_access" {}
```

---

## 7. Nomenclatura de Outputs

Outputs devem ser claros e reutilizáveis por outros módulos ou stacks.

**Exemplos:**

```hcl
output "vpc_id" {}
output "private_subnet_ids" {}
output "rds_endpoint" {}
```

---

## 8. Nomes de Recursos na Cloud (Tags e IDs)

Prefira usar `locals` para centralizar os nomes de recursos, em vez de espalhar strings pelo código. Isso facilita encontrar e manter a nomenclatura em um único lugar.

```hcl
locals {
  name_prefix         = "${var.project_name}-${var.environment}"
  security_group_name = "${local.name_prefix}-sg"
  instance_name       = "${local.name_prefix}-webserver"
  key_name            = "${local.name_prefix}-key"
}
```

Em vez de:

```hcl
# ❌ Strings espalhadas pelo código
resource "aws_security_group" "web" {
  name = "${var.project_name}-${var.environment}-sg"
}
resource "aws_instance" "web" {
  tags = { Name = "${var.project_name}-${var.environment}-webserver" }
}
```

---

## 9. Validação em Pull Requests

Toda alteração deve respeitar esta política.

**Checklist mínimo:**

- [ ] Diretórios de módulos iniciam com o nome do provedor
- [ ] Nomes seguem `snake_case`
- [ ] Não existem nomes genéricos ou ambíguos (`this`, `main`, `default`)
- [ ] Estrutura segue o padrão do repositório
- [ ] Recursos na cloud possuem tags de identificação (`Project`, `Environment`, `Owner`, `ManagedBy`)

---

**Observação Final**

Esta política é obrigatória para novos módulos e refatorações. Exceções devem ser justificadas e aprovadas pela equipe DevOps.
