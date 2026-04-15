# 📚 Conceitos Terraform Aplicados no Projeto

> Este documento explica cada conceito do Terraform utilizado no projeto, com exemplos retirados do próprio código. Serve como guia de estudo e referência durante a apresentação.

> 📎 **Documentação oficial do Terraform:** [developer.hashicorp.com/terraform/docs](https://developer.hashicorp.com/terraform/docs)

---

## Índice

- [Infrastructure as Code (IaC)](#infrastructure-as-code-iac)
- [HCL — HashiCorp Configuration Language](#hcl--hashicorp-configuration-language)
- [Providers](#providers)
- [Version Constraints](#version-constraints)
- [Resources](#resources)
- [Data Sources](#data-sources)
- [Variables](#variables)
- [Locals](#locals)
- [Outputs](#outputs)
- [State](#state)
- [Remote Backend](#remote-backend)
- [State Locking](#state-locking)
- [Resource Dependencies](#resource-dependencies)
- [Lifecycle Rules](#lifecycle-rules)
- [Functions](#functions)
- [Provisioners](#provisioners)
- [Meta-Arguments](#meta-arguments)
- [Comandos essenciais](#comandos-essenciais)
- [Boas práticas aplicadas](#boas-práticas-aplicadas)

---

## Infrastructure as Code (IaC)

**O que é:** a prática de definir e gerenciar infraestrutura usando código, em vez de configurar servidores manualmente pelo console ou com scripts imperativos.

**Por que importa:**

| Abordagem manual | Abordagem com IaC |
|---|---|
| Configuração feita clicando no console | Configuração declarada em arquivos `.tf` |
| Difícil de reproduzir exatamente | Idêntico em qualquer ambiente |
| Sem histórico de mudanças | Versionável no Git |
| Propenso a erro humano | Previsível e auditável |
| Demorado para múltiplos ambientes | Um `apply` recria tudo |

**Tipos de ferramentas IaC:**

```
Configuration Management   → Ansible, Chef, Puppet (instala software)
Server Templating          → Packer, Docker (cria imagens imutáveis)
Provisioning Tools         → Terraform, CloudFormation (cria infra)
```

O Terraform é uma ferramenta de **provisioning** — ele cria e gerencia a infraestrutura em si (servidores, redes, bancos de dados), não o que roda dentro deles.

---

## HCL — HashiCorp Configuration Language

**O que é:** linguagem declarativa desenvolvida pela HashiCorp para escrever configurações do Terraform. É legível por humanos e estruturada em blocos.

**Estrutura básica:**

```hcl
<tipo_do_bloco> "<tipo_do_recurso>" "<nome_local>" {
  argumento1 = "valor1"
  argumento2 = "valor2"
}
```

**Exemplo real do projeto:**

```hcl
resource "aws_instance" "web" {   # tipo=resource, recurso=aws_instance, nome=web
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
}
```

**Diferença entre declarativo e imperativo:**

```bash
# Imperativo (script shell) — você descreve O QUE FAZER
if ! aws ec2 describe-instances --instance-ids i-123 | grep running; then
  aws ec2 run-instances --image-id ami-xyz --instance-type t2.micro
fi

# Declarativo (Terraform) — você descreve COMO DEVE SER
resource "aws_instance" "web" {
  ami           = "ami-xyz"
  instance_type = "t2.micro"
}
```

No modo declarativo, o Terraform descobre sozinho o que precisa fazer para chegar no estado desejado.

---

## Providers

**O que é:** plugin que permite ao Terraform se comunicar com uma plataforma específica (AWS, Azure, GCP, etc.). Cada provider traduz os recursos HCL em chamadas de API da plataforma.

**Por que usar version constraints:**

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"  # aceita 5.x, nunca 6.0
    }
  }
}
```

Sem essa restrição, o `terraform init` sempre instala a versão mais recente. Uma atualização de `5.x` para `6.0` pode conter breaking changes que quebram o projeto silenciosamente.

**No projeto:** o provider AWS é configurado com a região vinda de uma variável, tornando o projeto portável entre regiões.

```hcl
provider "aws" {
  region = var.aws_region  # não hardcoded
}
```

---

## Version Constraints

**O que é:** sintaxe para controlar quais versões de providers são aceitas.

**Tabela de operadores:**

| Operador | Exemplo | Significado |
|---|---|---|
| `=` | `= 5.0.0` | Exatamente esta versão |
| `!=` | `!= 5.1.0` | Qualquer versão exceto esta |
| `>` | `> 5.0` | Maior que |
| `>=` | `>= 5.0` | Maior ou igual |
| `<` | `< 6.0` | Menor que |
| `~>` | `~> 5.0` | Pessimistic constraint — aceita `5.x` mas não `6.0` |

**Recomendação:** usar `~>` com o major e minor fixos (`~> 5.2`) garante patches automáticos mas bloqueia mudanças incompatíveis.

---

## Resources

**O que é:** bloco principal do Terraform — representa um componente de infraestrutura que será criado, atualizado ou destruído.

**Sintaxe:**

```hcl
resource "<provider>_<tipo>" "<nome_local>" {
  # argumentos
}
```

**Recursos usados no projeto:**

```hcl
resource "aws_instance" "web"          # EC2
resource "aws_security_group" "web"    # Security Group
resource "aws_key_pair" "web"          # Key Pair SSH
resource "aws_s3_bucket" "state"       # Bucket do state
resource "aws_dynamodb_table" "lock"   # State locking
```

**Como referenciar atributos de um recurso:**

```hcl
# Formato: <tipo_do_recurso>.<nome_local>.<atributo>
vpc_security_group_ids = [aws_security_group.web.id]
key_name               = aws_key_pair.web.key_name
```

Essa referência cria uma **dependência implícita** — o Terraform entende que a EC2 deve ser criada depois do Security Group.

---

## Data Sources

**O que é:** permite ao Terraform **ler** informações de recursos que já existem (criados fora do Terraform ou em outro projeto) sem gerenciá-los.

**Diferença fundamental:**

```
resource → cria, atualiza, destrói (Terraform gerencia)
data     → apenas lê (Terraform não gerencia)
```

**Uso no projeto — buscar AMI Ubuntu mais recente:**

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # ID oficial da Canonical na AWS

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

**Por que usar:** o ID de uma AMI (`ami-0c55b159cbfafe1f0`) muda por região e pode ser descontinuado. O data source garante que sempre usamos a versão mais recente, sem alterar o código.

**Como referenciar:**

```hcl
resource "aws_instance" "web" {
  ami = data.aws_ami.ubuntu.id  # ID resolvido em tempo de plan
}
```

---

## Variables

**O que é:** parâmetros de entrada que tornam o código reutilizável. Em vez de valores fixos no código, usamos variáveis que podem ter valores diferentes em cada ambiente.

**Anatomia completa de uma variável:**

```hcl
variable "instance_type" {
  type        = string                        # tipo obrigatório
  description = "Tipo da instância EC2"       # documentação
  default     = "t2.micro"                    # valor padrão (opcional)

  validation {                                # validação customizada
    condition     = contains(["t2.micro", "t2.small", "t2.medium"], var.instance_type)
    error_message = "Use t2.micro, t2.small ou t2.medium."
  }
}
```

**Tipos suportados:**

```hcl
variable "nome"    { type = string }
variable "qtd"     { type = number }
variable "ativo"   { type = bool }
variable "lista"   { type = list(string) }
variable "mapa"    { type = map(string) }
variable "objeto"  { type = object({ nome = string, porta = number }) }
variable "tupla"   { type = tuple([string, number, bool]) }
```

**Formas de passar valores (ordem de precedência — último ganha):**

```bash
# 1. Valor default na declaração da variável
# 2. Arquivo terraform.tfvars
# 3. Arquivo *.auto.tfvars
# 4. Variável de ambiente
export TF_VAR_instance_type="t2.small"
# 5. Flag na linha de comando (maior precedência)
terraform apply -var="instance_type=t2.small"
```

**Variáveis usadas no projeto:**

| Variável | Tipo | Descrição |
|---|---|---|
| `aws_region` | `string` | Região AWS de deploy |
| `instance_type` | `string` | Tipo da instância EC2 |
| `environment` | `string` | Nome do ambiente (dev/staging/prod) |
| `project_name` | `string` | Nome do projeto para tags |
| `owner` | `string` | Responsável pelo recurso |
| `public_key_path` | `string` | Caminho da chave pública SSH local |

---

## Locals

**O que é:** valores locais calculados uma vez e reutilizados em múltiplos lugares do projeto. Diferente de variáveis, locals não recebem valores externos — são calculados internamente.

**Por que usar:**

```hcl
# Sem locals — repetição em cada recurso
resource "aws_instance" "web" {
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Owner       = "time-plataforma"
    Project     = "demo"
  }
}

resource "aws_s3_bucket" "state" {
  tags = {
    Environment = "dev"       # duplicado
    ManagedBy   = "Terraform" # duplicado
    Owner       = "time-plataforma" # duplicado
    Project     = "demo"      # duplicado
  }
}
```

```hcl
# Com locals — define uma vez, usa em todos
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    Project     = var.project_name
  }
}

resource "aws_instance" "web" {
  tags = local.common_tags  # referencia o local
}

resource "aws_s3_bucket" "state" {
  tags = local.common_tags  # referencia o mesmo local
}
```

Se o valor de `Owner` mudar, altera em **um único lugar**.

---

## default_tags — Tagging centralizado via Provider

**O que é:** bloco do provider AWS que aplica automaticamente um conjunto de tags em **todos** os recursos criados por aquele provider, sem precisar declarar as tags em cada recurso individualmente.

**Por que é recomendado pela comunidade:**

```hcl
# ❌ Abordagem com locals apenas — é preciso lembrar de usar local.common_tags em cada recurso
resource "aws_instance" "web" {
  tags = local.common_tags  # pode esquecer em algum recurso
}

resource "aws_security_group" "web" {
  tags = local.common_tags  # pode esquecer aqui também
}
```

```hcl
# ✅ Abordagem com default_tags — aplicado automaticamente em tudo
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = var.project_name
      Environment = var.environment
    }
  }
}
```

**Como funciona na prática:**
- As `default_tags` são aplicadas em **todos** os recursos do provider como base
- Tags declaradas em cada recurso individualmente são **mescladas** com as `default_tags` (não sobrescritas)
- Se houver conflito de chave, a tag do recurso tem prioridade sobre a `default_tag`

**Boas práticas de tagging:**
- Sempre taguear todos os recursos — facilita rastreabilidade de custos, auditoria e controle de acesso
- Tags mínimas recomendadas: `ManagedBy`, `Project`, `Environment`, `Owner`
- Use `default_tags` no provider para as tags universais e `locals` para tags específicas de contexto que variam por recurso

---

## Outputs

**O que é:** valores exportados após o `terraform apply`. Funcionam como a "saída" do módulo — expõem atributos dos recursos criados.

**Por que usar:**
- Exibir o IP da instância para o usuário conectar via SSH
- Compartilhar valores entre módulos
- Integrar com pipelines CI/CD que precisam de IDs de recursos

```hcl
output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "IP público da instância EC2 — use para acessar via SSH"
  sensitive   = false  # true ocultaria o valor no terminal (ex: senhas)
}
```

**Como consumir:**

```bash
terraform output                     # todos os outputs
terraform output instance_public_ip  # output específico
terraform output -json               # formato JSON para scripts
```

---

## State

**O que é:** arquivo JSON (`terraform.tfstate`) que mapeia os recursos declarados no código para os recursos reais na cloud. É a memória do Terraform.

**O que o state contém:**

```json
{
  "resources": [
    {
      "type": "aws_instance",
      "name": "web",
      "instances": [{
        "attributes": {
          "id": "i-0abc123def456",
          "public_ip": "54.71.34.19",
          "ami": "ami-0c55b159cbfafe1f0"
        }
      }]
    }
  ]
}
```

**Para que serve:**

| Uso | Explicação |
|---|---|
| **Mapeamento** | Liga `aws_instance.web` ao ID real `i-0abc123` na AWS |
| **Diff** | Compara o estado atual com o código para calcular mudanças |
| **Performance** | Evita consultas desnecessárias à API da AWS a cada `plan` |
| **Metadados** | Rastreia dependências entre recursos |

**Regras de ouro:**
- ❌ Nunca editar o `.tfstate` manualmente — nem via texto, nem via comando direto no arquivo
- ❌ Nunca commitar o `.tfstate` no Git
- ✅ Usar remote backend para times
- ✅ Usar `terraform state` commands para manipulações necessárias (ex: `state mv`, `state rm`, `import`)

> ⚠️ **Recomendação da comunidade:** manipular o `tfstate` diretamente (edição manual ou comandos de força bruta) deve ser **sempre o último recurso** para resolver erros no state — nunca a abordagem padrão. Prefira sempre os comandos oficiais do Terraform que garantem integridade e rastreabilidade.

---

## Remote Backend

**O que é:** configuração que diz ao Terraform para salvar o state em um serviço externo em vez de localmente.

**Por que usar S3:**
- Acessível por qualquer membro do time
- Suporta versionamento — é possível voltar para um state anterior
- Suporta criptografia em repouso (SSE)
- Alta disponibilidade e durabilidade (99.999999999%)

```hcl
terraform {
  backend "s3" {
    bucket         = "meu-projeto-terraform-state"
    key            = "demo/terraform.tfstate"  # caminho dentro do bucket
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"    # habilita o locking
    encrypt        = true                      # criptografia em repouso
  }
}
```

**Importante:** após adicionar ou alterar o backend, é obrigatório rodar `terraform init` novamente para reconectar.

---

## State Locking

**O que é:** mecanismo que impede que dois `terraform apply` rodem simultaneamente no mesmo estado.

**Por que é crítico:**

```
Engenheiro A                    Engenheiro B
     │                               │
     ├── lê o state ───────────────▶ │
     │                               ├── lê o state
     │                               ├── calcula mudanças
     ├── calcula mudanças            ├── apply
     ├── apply                       ├── grava novo state ◀── B grava
     ├── grava novo state ◀── A grava sobre o state de B
                                         💥 estado corrompido
```

**Com DynamoDB Locking:**

```
Engenheiro A                    Engenheiro B
     │                               │
     ├── adquire lock no DynamoDB    │
     ├── apply em andamento...       ├── tenta adquirir lock
     │                               ├── ERRO: já está travado por A
     ├── finaliza                    │
     ├── libera o lock               │
                                     ├── adquire lock
                                     ├── apply com state atualizado ✅
```

**Configuração no DynamoDB:**

```hcl
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"  # atributo obrigatório para o Terraform

  attribute {
    name = "LockID"
    type = "S"  # S = String
  }
}
```

---

## Resource Dependencies

**O que é:** controle da ordem de criação e destruição dos recursos.

**Dependência implícita** (recomendada):

```hcl
resource "aws_instance" "web" {
  # ao referenciar o ID do security group, o Terraform automaticamente
  # entende que a EC2 depende do Security Group
  vpc_security_group_ids = [aws_security_group.web.id]
}
```

**Dependência explícita** (para casos sem referência de atributo):

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  # EC2 só será criada depois que o S3 e o DynamoDB existirem
  depends_on = [
    aws_s3_bucket.state,
    aws_dynamodb_table.lock
  ]
}
```

O Terraform usa um grafo de dependências (DAG) para determinar a ordem de criação. Recursos sem dependências entre si são criados em **paralelo**.

---

## Lifecycle Rules

**O que é:** bloco que altera o comportamento padrão de criação, atualização e destruição de recursos.

**`prevent_destroy`** — impede que o recurso seja destruído:

```hcl
resource "aws_s3_bucket" "state" {
  bucket = "meu-terraform-state"

  lifecycle {
    prevent_destroy = true
    # um `terraform destroy` vai falhar com erro explícito
    # em vez de apagar o bucket que guarda todo o estado
  }
}
```

**`create_before_destroy`** — cria o novo antes de destruir o antigo:

```hcl
resource "aws_instance" "web" {
  lifecycle {
    create_before_destroy = true
    # evita downtime em atualizações que forçam recriação do recurso
  }
}
```

**`ignore_changes`** — ignora mudanças em atributos específicos:

```hcl
resource "aws_instance" "web" {
  tags = local.common_tags

  lifecycle {
    ignore_changes = [tags]
    # a AWS adiciona tags automáticas (ex: para billing)
    # sem este bloco, o Terraform tentaria removê-las a cada apply
  }
}
```

---

## Functions

**O que é:** funções built-in do Terraform para transformar e combinar valores.

**Funções usadas no projeto:**

```hcl
# file() — lê o conteúdo de um arquivo como string
public_key = file(var.public_key_path)
# resultado: "ssh-rsa AAAAB3NzaC1yc2EA..."

# lookup() — busca um valor em um mapa com fallback
instance_type = lookup(var.instance_types_by_env, var.environment, "t2.micro")
# se var.environment = "prod", retorna o valor correspondente no mapa

# toset() — converte lista em set (remove duplicatas, sem ordem)
for_each = toset(var.availability_zones)

# length() — retorna o tamanho de uma lista, mapa ou string
count = length(var.subnets)
```

**Testando funções no console interativo:**

```bash
terraform console
> file("~/.ssh/id_rsa.pub")
> lookup({"dev" = "t2.micro", "prod" = "t2.large"}, "dev", "t2.micro")
> length(["a", "b", "c"])
```

---

## Provisioners

**O que é:** executam scripts ou comandos durante a criação ou destruição de um recurso.

> ⚠️ **Uso com parcimônia:** a HashiCorp recomenda usar `user_data` (AWS) em vez de provisioners sempre que possível. Provisioners não aparecem no `terraform plan`, dificultando a previsibilidade.

**`local-exec`** — executa um comando na máquina que roda o Terraform:

```hcl
resource "aws_instance" "web" {
  # ... configurações

  provisioner "local-exec" {
    command = "echo 'IP criado: ${self.public_ip}' >> /tmp/ips.txt"
  }
}
```

**`remote-exec`** — executa comandos dentro da instância via SSH:

```hcl
resource "aws_instance" "web" {
  # ... configurações

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install -y nginx",
    ]
  }
}
```

**No projeto:** usamos `user_data` na EC2 (preferível) e um `local-exec` demonstrativo para exibir o IP no terminal.

---

## Meta-Arguments

**O que são:** argumentos especiais que modificam o comportamento de qualquer resource, independente do tipo.

**`depends_on`** — dependência explícita:
```hcl
depends_on = [aws_s3_bucket.state]
```

**`lifecycle`** — comportamento de ciclo de vida:
```hcl
lifecycle {
  prevent_destroy       = true
  create_before_destroy = true
  ignore_changes        = [tags]
}
```

**`count`** — cria múltiplas instâncias do recurso:
```hcl
resource "aws_instance" "web" {
  count = 3  # cria web[0], web[1], web[2]
  ami   = data.aws_ami.ubuntu.id
}
```

**`for_each`** — cria uma instância por item de um mapa ou set:
```hcl
resource "aws_iam_user" "devs" {
  for_each = toset(["alice", "bob", "carlos"])
  name     = each.value  # cria um usuário para cada nome
}
```

**`provider`** — especifica qual provider usar (multi-region/multi-account):
```hcl
resource "aws_instance" "web" {
  provider = aws.us-west-2
}
```

---

## Comandos essenciais

```bash
# Inicializa o projeto — baixa providers, configura backend
terraform init

# Valida a sintaxe dos arquivos .tf sem contatar a API
terraform validate

# Formata os arquivos seguindo o estilo oficial
terraform fmt

# Mostra o que será criado/alterado/destruído
terraform plan

# Aplica as mudanças
terraform apply

# Aplica sem confirmação interativa (para CI/CD)
terraform apply -auto-approve

# Destrói toda a infraestrutura gerenciada
terraform destroy

# Exibe o state atual de forma legível
terraform show

# Lista os recursos no state
terraform state list

# Mostra detalhes de um recurso específico no state
terraform state show aws_instance.web

# Move um recurso no state (renomear sem recriar)
terraform state mv aws_instance.web aws_instance.app

# Remove um recurso do state sem destruí-lo na cloud
terraform state rm aws_instance.web

# Importa um recurso existente para o state
terraform import aws_instance.web i-0abc123def456

# Abre console interativo para testar funções e expressões
terraform console

# Ativa logs detalhados
export TF_LOG=DEBUG  # ou INFO, WARN, ERROR, TRACE
```

---

## Boas práticas aplicadas

| Prática | Onde aplicada | Por quê |
|---|---|---|
| Version constraints | `provider.tf` | Evitar breaking changes em atualizações |
| Variáveis tipadas | `variables.tf` | Validação em tempo de plan, não em apply |
| `description` em tudo | Variáveis e outputs | Documentação viva junto ao código |
| Tags via locals | `locals.tf` | Consistência e manutenção centralizada |
| `default_tags` no provider | `provider.tf` | Garante que nenhum recurso fique sem tags base, independente de quem escreve o código |
| Sempre taguear tudo | Todos os recursos | Rastreabilidade de custos, auditoria e controle de acesso |
| `prevent_destroy` | S3 do state | Proteção contra destruição acidental |
| `ignore_changes` nas tags | `aws_instance` | Evitar drift com tags automáticas da AWS |
| Data source para AMI | `main.tf` | Sempre usar a imagem mais atualizada |
| Par de chaves gerado pelo Terraform | `main.tf` | Elimina processo manual, totalmente reproduzível via código |
| `user_data` vs provisioners | `aws_instance` | Mais simples, sem requisito de rede |
| Remote state | `backend.tf` | Colaboração segura em times |
| State locking | DynamoDB | Evitar corrupção em operações simultâneas |
| `.gitignore` completo | raiz do projeto | Não vazar dados sensíveis no repositório |
| Arquivos separados por responsabilidade | Estrutura do projeto | Legibilidade e manutenção |
