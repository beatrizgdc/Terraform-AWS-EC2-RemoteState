# Projeto Terraform AWS + EC2 - Remote State

> Projeto de desenvolvimento prático em Terraform.
> Cobre os principais conceitos do Terraform aplicados em infraestrutura real na AWS.

---

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Pré-requisitos](#pré-requisitos)
- [Estrutura de Arquivos](#estrutura-de-arquivos)
- [O que este projeto cria](#o-que-este-projeto-cria)
- [Como executar](#como-executar)
- [Comandos úteis](#comandos-úteis)
- [Documentação detalhada](#documentação-detalhada)

---

## Visão Geral

Este projeto provisiona uma instância EC2 Ubuntu com Nginx instalado automaticamente via `user_data`, protegida por um Security Group e acessível via SSH com Key Pair gerado pelo próprio Terraform. O estado do Terraform é armazenado remotamente em um bucket S3 com state locking, seguindo as boas práticas de times que trabalham em colaboração.

O projeto está dividido em **dois diretórios independentes**: `bootstrap/` (cria a infraestrutura de remote state) e `project/` (cria a infraestrutura principal). Essa separação é necessária porque o bucket S3 precisa existir antes de ser usado como backend.

O objetivo principal é **didático**: cada arquivo, recurso e decisão de design está comentado e documentado para facilitar o aprendizado.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Verificar com |
|---|---|---|
| Terraform | `>= 1.3.0` | `terraform version` |
| AWS CLI | `>= 2.0` | `aws --version` |
| Credenciais AWS | Configuradas | `aws sts get-caller-identity` |

### Configurando credenciais AWS

```bash
aws configure
# AWS Access Key ID: sua_access_key
# AWS Secret Access Key: sua_secret_key
# Default region name: us-east-1
# Default output format: json
```

Ou via variáveis de ambiente:

```bash
export AWS_ACCESS_KEY_ID="sua_access_key"
export AWS_SECRET_ACCESS_KEY="sua_secret_key"
export AWS_DEFAULT_REGION="us-east-1"
```

> **Múltiplos perfis AWS CLI:** se você usa perfis nomeados (`aws configure --profile meu-perfil`), configure o perfil desejado nos arquivos `provider.tf` de cada diretório. Consulte os comentários dentro do bloco `provider "aws"` para mais detalhes.

---

## Estrutura de Arquivos

```
terraform-demo/
│
├── README.md                        # Este arquivo
├── .gitignore                       # Arquivos ignorados pelo Git
│
├── docs/
│   ├── ARCHITECTURE.md              # Explicação detalhada da arquitetura
│   ├── TERRAFORM_CONCEPTS.md        # Conceitos Terraform usados no projeto
│   └── NAMING_POLICY.md             # Política de nomenclatura Terraform & Terragrunt
│
├── bootstrap/                       # ⚠️ Execute PRIMEIRO — apenas uma vez
│   ├── provider.tf                  # Provider AWS + version constraints
│   ├── variables.tf                 # Variáveis do bootstrap
│   ├── locals.tf                    # Tags comuns
│   ├── main.tf                      # S3 bucket + DynamoDB table + data source
│   ├── outputs.tf                   # Nome do bucket e da tabela (use no backend.tf)
│   └── terraform.tfvars             # Valores das variáveis do bootstrap
│
└── project/                         # Infraestrutura principal
    ├── provider.tf                  # Provider AWS + TLS + Local + version constraints
    ├── backend.tf                   # Remote state: S3 + use_lockfile
    ├── variables.tf                 # Variáveis do projeto
    ├── locals.tf                    # Tags comuns, prefixo e nomes de recursos
    ├── main.tf                      # data source AMI + Key Pair + SG + EC2
    ├── outputs.tf                   # IPs, IDs, comandos SSH prontos
    └── terraform.tfvars             # Valores das variáveis do projeto
```

> 📖 Para entender **o que cada arquivo faz e por quê ele existe**, veja [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
> 📖 Para entender **cada conceito Terraform utilizado**, veja [docs/TERRAFORM_CONCEPTS.md](docs/TERRAFORM_CONCEPTS.md).
> 📖 Para seguir a **política de nomenclatura** do time, veja [docs/NAMING_POLICY.md](docs/NAMING_POLICY.md).

---

## O que este projeto cria

### Bootstrap — Remote State (pasta `bootstrap/`)

| Recurso | Tipo Terraform | Descrição |
|---|---|---|
| Bucket S3 | `aws_s3_bucket` | Armazena o `terraform.tfstate` do projeto principal |
| Versionamento S3 | `aws_s3_bucket_versioning` | Guarda versões anteriores do state para recuperação |
| Criptografia S3 | `aws_s3_bucket_server_side_encryption_configuration` | Criptografa o state em repouso (AES256) |
| Block Public Access | `aws_s3_bucket_public_access_block` | Garante que o bucket nunca fique público |
| Tabela DynamoDB | `aws_dynamodb_table` | State locking — evita operações simultâneas |

### Infraestrutura principal (pasta `project/`)

| Recurso | Tipo Terraform | Descrição |
|---|---|---|
| AMI Ubuntu | `data.aws_ami` | Busca automática da AMI Ubuntu 22.04 mais recente |
| Chave SSH (TLS) | `tls_private_key` | Gera o par de chaves RSA 4096 automaticamente |
| Key Pair | `aws_key_pair` | Registra a chave pública na AWS |
| Chave privada local | `local_file` | Salva o arquivo `.pem` no diretório do projeto |
| Security Group | `aws_security_group` | Libera portas 22 (SSH) e 80 (HTTP), egress livre |
| Instância EC2 | `aws_instance` | Ubuntu t2.micro com Nginx instalado via `user_data` |

---

## Como executar

### Passo 1 — Clone o repositório e entre na raiz do projeto

```bash
git clone <url-do-repositorio>
cd Terraform-AWS-EC2-RemoteState   # ← raiz do projeto
```

> **Convenção de navegação:** os passos abaixo sempre partem da **raiz do projeto**. Sempre que precisar trocar de diretório, o comando estará explícito. Após cada etapa, volte para a raiz antes de continuar.

---

### Passo 2 — Bootstrap: criar o Remote State (apenas na primeira vez)

O bucket S3 e a tabela DynamoDB precisam existir **antes** de configurar o backend.
O bootstrap usa estado **local** (sem backend remoto) por design.

```bash
# A partir da raiz do projeto:
cd bootstrap/

# Ajuste as variáveis em terraform.tfvars se necessário
terraform init
terraform plan
terraform apply

# Anote os valores dos outputs exibidos:
# state_bucket_name   = "terraform-state-demo-123456789012"
# dynamodb_table_name = "terraform-state-lock"

# Volte para a raiz do projeto
cd ..
```

---

### Passo 3 — Atualizar o backend.tf com o nome do bucket

A partir da raiz do projeto, abra `project/backend.tf` e substitua o placeholder pelo nome real do bucket (valor do output anterior):

```hcl
backend "s3" {
  bucket       = "terraform-state-demo-123456789012"  # ← valor do output
  key          = "demo/terraform.tfstate"
  region       = "us-east-1"
  use_lockfile = true
  encrypt      = true
}
```

---

### Passo 4 — Inicializar o projeto principal

```bash
# A partir da raiz do projeto:
cd project/

terraform init
# O Terraform vai baixar os providers (AWS, TLS, Local) e conectar ao backend S3
```

---

### Passo 5 — Revisar o plano de execução

```bash
# Ainda em project/
terraform plan
# Revise tudo que será criado antes de aplicar
```

---

### Passo 6 — Aplicar a infraestrutura

```bash
# Ainda em project/
terraform apply
# Digite "yes" quando solicitado
```

Ao final do apply, os outputs mostram tudo que você precisa:

```
instance_public_ip = "54.71.34.19"
private_key_path   = "./terraform-demo-dev-key.pem"
ssh_command        = "ssh -i ./terraform-demo-dev-key.pem ubuntu@54.71.34.19"
nginx_url          = "http://54.71.34.19"
ami_id_used        = "ami-0c55b159cbfafe1f0"
```

> O arquivo `.pem` com a chave privada é gerado automaticamente no diretório `project/`. Não é necessário criar nem baixar chaves manualmente.

```bash
# Volte para a raiz do projeto
cd ..
```

---

### Passo 7 — Acessar a instância

```bash
# A partir da raiz do projeto:
cd project/

# Ajuste a permissão da chave privada (obrigatório)
chmod 400 terraform-demo-dev-key.pem

# (Opcional) confira a permissão
ls -l terraform-demo-dev-key.pem
# Deve aparecer algo como: -r-------- 

# Use o comando SSH gerado pelo Terraform:
terraform output -raw ssh_command

# Ou conecte manualmente com o IP exibido:
ssh -i ./terraform-demo-dev-key.pem ubuntu@<ip_exibido_no_output>

# Após terminar, volte para a raiz do projeto
cd ..
```

> ⏱️ Aguarde ~60 segundos após o apply para o `user_data` terminar de instalar o Nginx antes de acessar a URL HTTP.

---

### Passo 8 — Destruir a infraestrutura

```bash
# A partir da raiz do projeto:
cd project/
terraform destroy
# Destrói EC2, SG, Key Pair e o arquivo .pem local

cd ..

# Para destruir o bootstrap/ (S3 + DynamoDB):
cd bootstrap/
terraform destroy
# ⚠️ O bucket S3 tem prevent_destroy = true — o destroy vai falhar por design.
# Para destruir de verdade: remova o lifecycle block do main.tf do bootstrap
# ou delete o bucket manualmente no console AWS.

cd ..
```

---

## Comandos úteis

```bash
# Validar sintaxe dos arquivos .tf
terraform validate

# Formatar automaticamente os arquivos
terraform fmt

# Listar recursos no state
terraform state list

# Ver detalhes de um recurso específico
terraform state show aws_instance.web

# Ver todos os outputs
terraform output

# Ver o valor de um output específico (sem aspas — ideal para scripts)
terraform output -raw ssh_command
terraform output -raw nginx_url

# Ativar logs detalhados para debug
export TF_LOG=DEBUG
terraform apply

# Sobrescrever uma variável pontualmente (sem alterar o tfvars)
terraform apply -var="instance_type=t2.small"

# Verificar qual conta AWS está sendo usada antes do apply
aws sts get-caller-identity
```

---

## Documentação detalhada

| Documento | Conteúdo |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Diagrama, estrutura de pastas, decisões de design, explicação de cada arquivo e recurso |
| [TERRAFORM_CONCEPTS.md](docs/TERRAFORM_CONCEPTS.md) | Conceitos do Terraform aplicados com exemplos do próprio código |
| [NAMING_POLICY.md](docs/NAMING_POLICY.md) | Política oficial de nomenclatura para recursos, módulos, diretórios e arquivos |
