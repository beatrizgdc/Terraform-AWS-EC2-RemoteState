# Arquitetura do Projeto

> Este documento explica cada decisão de design da infraestrutura, o papel de cada arquivo e por que cada recurso foi escolhido.

---

## Índice

- [Visão geral da arquitetura](#visão-geral-da-arquitetura)
- [Camadas do projeto](#camadas-do-projeto)
- [Explicação de cada arquivo](#explicação-de-cada-arquivo)
- [Explicação de cada recurso AWS](#explicação-de-cada-recurso-aws)
- [Decisões de design](#decisões-de-design)

---

## Visão geral da arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│  Terraform (local)                                                  │
│                                                                     │
│  bootstrap/                         project/                        │
│  provider.tf  main.tf               provider.tf  main.tf           │
│  variables.tf outputs.tf            variables.tf outputs.tf        │
│  locals.tf    terraform.tfvars      locals.tf    backend.tf        │
└──────────┬──────────────────────────────────┬───────────────────────┘
           │ terraform apply (1º)             │ terraform apply (2º)
           ▼                                  ▼
┌──────────────────────┐        ┌─────────────────────────────────────┐
│  AWS — Remote State  │        │  AWS Region (var.aws_region)        │
│                      │        │                                     │
│  S3 Bucket           │◀───────│  backend "s3" { ... }              │
│  terraform.tfstate   │  state │                                     │
│  versionamento       │        │  ┌──────────────────────────────┐  │
│  criptografia AES256 │        │  │  VPC padrão                  │  │
│  prevent_destroy     │        │  │                              │  │
│                      │        │  │  ┌────────────┐  ┌────────┐  │  │
│  DynamoDB Table      │◀───────│  │  │  Security  │─▶│  EC2   │  │  │
│  State Locking       │  lock  │  │  │  Group     │  │ Ubuntu │  │  │
│  LockID (hash key)   │        │  │  │  SSH :22   │  │ Nginx  │  │  │
└──────────────────────┘        │  │  │  HTTP :80  │  │t2.micro│  │  │
                                │  │  └────────────┘  └───┬────┘  │  │
                                │  │                       │       │  │
                                │  │  ┌────────────┐       │       │  │
                                │  │  │  Key Pair  │───────┘       │  │
                                │  │  │ id_rsa.pub │               │  │
                                │  │  └────────────┘               │  │
                                │  │                               │  │
                                │  │  ┌────────────┐               │  │
                                │  │  │ data source│── AMI ID ─────│  │
                                │  │  │ aws_ami    │               │  │
                                │  │  └────────────┘               │  │
                                │  └──────────────────────────────┘  │
                                │                                     │
                                │  Outputs: public_ip, ssh_command,   │
                                │           nginx_url, ami_id_used    │
                                └─────────────────────────────────────┘
```

---

## Camadas do projeto

O projeto é dividido em **dois diretórios** com responsabilidades completamente distintas, executados em sequência:

### Camada 1 — `bootstrap/` (Remote State)

Deve ser executada **primeiro**, manualmente, apenas uma vez.
Cria o S3 e o DynamoDB que vão guardar e travar o estado do projeto principal.
Usa estado **local** intencionalmente — o backend remoto ainda não existe neste ponto.

**Arquivos:**
```
bootstrap/
├── provider.tf      # Provider AWS + version constraints (sem backend block)
├── variables.tf     # Região, nome do bucket, nome da tabela DynamoDB
├── locals.tf        # Tags comuns
├── main.tf          # aws_s3_bucket + aws_dynamodb_table + data.aws_caller_identity
├── outputs.tf       # Expõe o nome do bucket e da tabela para uso no backend.tf
└── terraform.tfvars # Valores padrão — ajuste antes de executar
```

**Por que criar separadamente?**
Não é possível usar um bucket S3 como backend se ele ainda não existe. Criamos esses recursos primeiro com estado local e depois o projeto principal usa esse bucket como backend.

---

### Camada 2 — `project/` (Infraestrutura Principal)

Executada depois do bootstrap. Usa o S3 criado como backend remoto para armazenar o state.
Contém todos os recursos da aplicação: EC2, Security Group, Key Pair.

**Arquivos:**
```
project/
├── provider.tf      # Provider AWS + version constraints + default_tags
├── backend.tf       # Remote state: aponta para o S3 e DynamoDB do bootstrap
├── variables.tf     # Região, instance_type, key path, CIDRs, tags
├── locals.tf        # common_tags (Environment, Owner, Project) + name_prefix
├── main.tf          # data source AMI + aws_key_pair + aws_security_group + aws_instance
├── outputs.tf       # public_ip, ssh_command, nginx_url, ami_id_used, sg_id
└── terraform.tfvars # Valores das variáveis — ajuste antes de executar
```

---

## Explicação de cada arquivo

### `bootstrap/provider.tf` e `project/provider.tf`

**O que é:** define qual provedor de cloud o Terraform vai usar e suas configurações de autenticação.

**Por que existe:** sem o provider, o Terraform não sabe com qual API conversar. O provider AWS é um plugin que traduz os recursos declarados no HCL em chamadas reais à API da Amazon.

**Diferença entre os dois:**
- `bootstrap/provider.tf` — não tem bloco `backend`, estado é salvo localmente
- `project/provider.tf` — inclui `default_tags` que aplica tags automaticamente em todos os recursos

```hcl
# Version constraint ~> 5.0 significa:
# aceita 5.x mas nunca 6.0 — protege contra breaking changes
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# default_tags aplica tags em TODOS os recursos sem precisar declarar em cada um
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = var.project_name
    }
  }
}
```

---

### `project/backend.tf`

**O que é:** define onde o arquivo `terraform.tfstate` será armazenado.

**Por que existe:** por padrão o Terraform salva o estado localmente. Isso é um problema em times porque o estado fica preso na máquina de uma pessoa. Com o backend S3, qualquer membro do time pode executar o Terraform apontando para o mesmo estado.

**O que contém:**
- Referência ao bucket S3 criado pelo bootstrap
- Referência à tabela DynamoDB para locking
- Chave (caminho) do arquivo de estado dentro do bucket
- `encrypt = true` para criptografia em trânsito

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-demo-<ACCOUNT-ID>"  # output do bootstrap
    key            = "demo/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

> ⚠️ O bucket precisa ser preenchido manualmente com o valor do output do bootstrap antes de rodar `terraform init` no `project/`.

---

### `locals.tf` (em ambos os diretórios)

**O que é:** define valores locais reutilizáveis dentro do projeto.

**Por que existe:** evita repetição de código. As tags de todos os recursos seguem o mesmo padrão — em vez de copiar e colar em cada recurso, define-se uma vez no `locals` e referencia com `local.common_tags`.

**No `project/locals.tf`** há também o `name_prefix`, que compõe um prefixo padronizado para o nome dos recursos:

```hcl
locals {
  common_tags = {
    Environment = var.environment
    Owner       = var.owner
    Project     = var.project_name
    # ManagedBy = "Terraform" já vem do default_tags no provider.tf
  }

  # Exemplo: "terraform-demo-dev"
  name_prefix = "${var.project_name}-${var.environment}"
}
```

> **Nota:** `ManagedBy` é configurado via `default_tags` no `provider.tf`, não nos locals. Isso evita duplicação — o provider já aplica essa tag automaticamente em todos os recursos.

---

### `variables.tf` (em ambos os diretórios)

**O que é:** declara todas as variáveis de entrada do módulo.

**Por que existe:** elimina valores hardcoded. Em vez de escrever `"us-east-1"` diretamente no código, usamos `var.aws_region`. Isso torna o projeto reutilizável em diferentes ambientes sem alterar o código principal.

**O que contém no `project/variables.tf`:**
- Variáveis com `type`, `description` e `default`
- Bloco `validation` em variáveis críticas (ex: `environment`, `instance_type`)
- Variáveis de rede com CIDRs configuráveis para SSH e HTTP

---

### `main.tf` (em ambos os diretórios)

**O que é:** arquivo principal com todos os recursos de infraestrutura do módulo.

**`bootstrap/main.tf` contém:**
- `data "aws_caller_identity"` para obter o Account ID e compor o nome único do bucket
- `aws_s3_bucket` com `lifecycle { prevent_destroy = true }`
- `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_public_access_block`
- `aws_dynamodb_table` com `hash_key = "LockID"`

**`project/main.tf` contém:**
- `data "aws_ami"` para buscar a AMI Ubuntu 22.04 mais recente
- `aws_key_pair` referenciando a chave pública via `file()`
- `aws_security_group` com regras de ingress (22, 80) e egress livre
- `aws_instance` com `user_data`, `lifecycle { ignore_changes = [tags] }`

---

### `outputs.tf` (em ambos os diretórios)

**O que é:** define quais informações serão exibidas após o `terraform apply`.

**`bootstrap/outputs.tf`** expõe o nome do bucket e da tabela — valores que precisam ser copiados para o `backend.tf` do projeto principal.

**`project/outputs.tf`** expõe tudo que o usuário precisa para acessar a instância:

| Output | Valor exemplo | Uso |
|---|---|---|
| `instance_public_ip` | `54.71.34.19` | IP para SSH e HTTP |
| `instance_public_dns` | `ec2-54-71...amazonaws.com` | DNS público da instância |
| `instance_id` | `i-0abc123def456` | Uso com AWS CLI |
| `ami_id_used` | `ami-0c55b159cbfafe1f0` | Auditoria — qual AMI foi usada |
| `ami_name_used` | `ubuntu/images/hvm-ssd/...` | Versão exata de build |
| `security_group_id` | `sg-0f02f3ea92b14bed8` | Para associar outros recursos |
| `ssh_command` | `ssh -i ~/.ssh/id_rsa ubuntu@54...` | Comando pronto para colar no terminal |
| `nginx_url` | `http://54.71.34.19` | URL do Nginx no navegador |

---

### `terraform.tfvars`

**O que é:** arquivo com os valores das variáveis declaradas no `variables.tf`.

**Por que existe:** separa a declaração de variáveis (o "o que existe") dos valores reais (o "qual é o valor"). Permite ter um `terraform.tfvars` por ambiente (`dev.tfvars`, `prod.tfvars`) sem alterar o código base.

> ⚠️ **Nunca versionar** `terraform.tfvars` se ele contiver dados sensíveis como access keys. Use o `.gitignore` para excluí-lo quando necessário.

---

### `.gitignore`

**O que é:** lista de arquivos que o Git deve ignorar. Fica na raiz do projeto e se aplica a ambos os diretórios (`bootstrap/` e `project/`).

| Arquivo/Pasta | Motivo |
|---|---|
| `.terraform/` | Plugins baixados — grandes e regeneráveis com `terraform init` |
| `*.tfstate` | Estado local — pode conter dados sensíveis |
| `*.tfstate.*` | Backups automáticos do estado |
| `*.tfvars` | Pode conter senhas e access keys |
| `.terraform.lock.hcl` | Opcional — alguns times versionam para reproducibilidade |
| `crash.log` | Logs de crash gerados pelo Terraform |
| `*.tfplan` | Planos salvos — são binários que podem conter dados do state |

---

## Explicação de cada recurso AWS

### `data "aws_caller_identity"` — Account ID (bootstrap)

**O que é:** data source que retorna informações da conta AWS autenticada no momento do plan/apply.

**Por que usar:** o nome do bucket S3 deve ser globalmente único. Usar o Account ID como sufixo (`terraform-state-demo-123456789012`) garante unicidade sem precisar de sufixos aleatórios ou nomes inventados.

---

### `data "aws_ami"` — Data Source de AMI (project)

**O que é:** um data source não cria nada — ele **lê** informações de recursos já existentes na AWS.

**Por que usar:** IDs de AMI mudam por região e são atualizados frequentemente. Hardcodar `"ami-0c55b159cbfafe1f0"` no código cria dois problemas: o ID é diferente em cada região, e a imagem pode ser descontinuada. O data source busca sempre a versão mais recente do Ubuntu automaticamente.

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical — publisher oficial do Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
```

---

### `tls_private_key` + `aws_key_pair` + `local_file` — Par de Chaves SSH

**O que é:** conjunto de três recursos que geram e registram automaticamente um par de chaves SSH, eliminando a necessidade de criação manual.

**Por que usar geração automática:** o processo manual (criar o par no console AWS, baixar o arquivo, apontar o caminho) é propenso a erros e cria dependências externas ao Terraform. Gerar o par via código torna o processo totalmente reproduzível.

**Como funciona:**

```hcl
# 1. Gera o par de chaves RSA em memória
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Envia a chave pública para a AWS
resource "aws_key_pair" "web" {
  key_name   = local.key_name
  public_key = tls_private_key.web.public_key_openssh
}

# 3. Salva a chave privada em disco com permissão 0600
resource "local_file" "private_key" {
  content         = tls_private_key.web.private_key_pem
  filename        = "${path.module}/${local.key_name}.pem"
  file_permission = "0600"
}
```

> ⚠️ **Atenção:** a chave privada é armazenada no `tfstate`. Por isso o bucket S3 está configurado com criptografia AES256 — nunca use estado local sem criptografia ao gerar chaves SSH via Terraform.

---

### `aws_security_group` — Grupo de Segurança

**O que é:** firewall virtual que controla o tráfego de entrada e saída da instância EC2.

**Por que existe:** por padrão, instâncias EC2 bloqueiam todo o tráfego. O Security Group define explicitamente o que é permitido.

**Regras configuradas:**

| Direção | Porta | Protocolo | Origem | Motivo |
|---|---|---|---|---|
| Ingress | 22 | TCP | `var.allowed_ssh_cidr` | Acesso SSH |
| Ingress | 80 | TCP | `var.allowed_http_cidr` | Acesso HTTP ao Nginx |
| Egress | Todas | Todos | `0.0.0.0/0` | Saída livre (downloads, updates) |

> 🔒 **Nota de segurança:** os CIDRs de SSH e HTTP são configuráveis por variável. O padrão `0.0.0.0/0` é adequado para demonstração, mas em produção restrinja o SSH ao IP do seu time ou use um bastion host.

---

### `aws_instance` — Instância EC2

**O que é:** servidor virtual na nuvem AWS. EC2 significa Elastic Compute Cloud.

**Por que este tipo (`t2.micro`):** está no nível gratuito da AWS (free tier), suficiente para demonstração.

**O `user_data` explicado:**

```bash
#!/bin/bash
sudo apt update -y
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
# Também cria uma página HTML customizada com o hostname e ambiente
```

O `user_data` é executado **uma única vez**, quando a instância inicia pela primeira vez. É a forma nativa da AWS de bootstrapar software — preferível a provisioners `remote-exec` por não depender de conectividade SSH durante o apply.

**Lifecycle configurado:**
```hcl
lifecycle {
  ignore_changes = [tags]
  # Evita configuration drift com tags automáticas adicionadas pela AWS
}
```

**Dependências implícitas:** ao referenciar `aws_security_group.web.id` e `aws_key_pair.web.key_name`, o Terraform detecta automaticamente que a EC2 depende desses recursos e os cria **antes** da instância.

---

### `aws_s3_bucket` + recursos relacionados — Bucket de Estado (bootstrap)

**O que é:** serviço de armazenamento de objetos da AWS. Neste caso, usado para guardar o `terraform.tfstate`.

**Por que S3 e não local:**
- **Compartilhamento:** qualquer pessoa do time acessa o mesmo estado
- **Histórico:** versionamento S3 guarda versões anteriores do state
- **Segurança:** criptografia AES256 em repouso + block public access

**Recursos criados junto ao bucket:**

| Recurso | Função |
|---|---|
| `aws_s3_bucket_versioning` | Guarda versões anteriores do tfstate para recuperação |
| `aws_s3_bucket_server_side_encryption_configuration` | Criptografa o state com AES256 |
| `aws_s3_bucket_public_access_block` | Bloqueia qualquer acesso público, agora e no futuro |

**O `lifecycle prevent_destroy`:**

```hcl
lifecycle {
  prevent_destroy = true
}
```

Impede que um `terraform destroy` acidental delete o bucket. Sem o state, o Terraform perde o controle sobre todos os recursos criados.

---

### `aws_dynamodb_table` — State Locking (bootstrap)

**O que é:** banco de dados NoSQL da AWS. Aqui usado exclusivamente para controlar quem pode modificar o estado.

**Por que necessário:** sem locking, dois `terraform apply` simultâneos podem sobrescrever as mudanças um do outro, corrompendo o state.

**Como funciona o locking:**
1. Antes de qualquer operação, o Terraform cria um item no DynamoDB com a chave `LockID`
2. Se o item já existe (outra operação em andamento), o Terraform falha com erro explícito
3. Ao terminar, o item é deletado, liberando o lock para o próximo

---

## Decisões de design

| Decisão | Alternativa considerada | Motivo da escolha |
|---|---|---|
| Usar `data "aws_ami"` | Hardcodar AMI ID | AMI IDs mudam por região e são descontinuadas |
| `data "aws_caller_identity"` para nome do bucket | Nome fixo ou aleatório | Unicidade garantida sem aleatoriedade, rastreável pelo Account ID |
| Tags via `locals` | Tags em cada recurso individualmente | Evita repetição, facilita manutenção centralizada |
| `ManagedBy` via `default_tags` no provider | Nos locals junto com as outras tags | O provider aplica automaticamente em todos os recursos sem exceção |
| `user_data` para instalar Nginx | Provisioner `remote-exec` | Mais simples, sem dependência de conectividade SSH durante o apply |
| `prevent_destroy` no S3 | Sem proteção | Evita perda do state por `terraform destroy` acidental |
| `ignore_changes` nas tags da EC2 | Forçar tags via Terraform sempre | Permite que a AWS adicione tags automáticas sem gerar configuration drift |
| CIDRs configuráveis por variável | Hardcodar `0.0.0.0/0` | Mesmo código funciona para demo (aberto) e produção (restrito) |
| Separar bootstrap da infra principal em pastas distintas | Tudo em um único diretório | Backend precisa existir antes de ser referenciado; separação deixa a responsabilidade explícita |
| Versionamento e criptografia no S3 | Bucket simples | O state contém dados sensíveis e deve ser protegido e recuperável |
