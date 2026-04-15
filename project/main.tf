# =============================================================================
# MAIN.TF — Recursos Principais
# =============================================================================
# Este arquivo contém toda a infraestrutura da demonstração:
#
#   1. data "aws_ami"          → busca a AMI Ubuntu mais recente (data source)
#   2. aws_key_pair            → registra a chave pública SSH na AWS
#   3. aws_security_group      → firewall da instância (portas 22 e 80)
#   4. aws_instance            → servidor EC2 com Nginx instalado via user_data
#
# FLUXO DE DEPENDÊNCIAS (Terraform resolve automaticamente):
#
#   data.aws_ami ──────────────────────┐
#   aws_key_pair ──────────────────────┤
#   aws_security_group ────────────────┴──▶ aws_instance
#
# Recursos sem dependência entre si são criados em PARALELO pelo Terraform.
# =============================================================================


# =============================================================================
# 1. DATA SOURCE — AMI Ubuntu mais recente
# =============================================================================
# DATA SOURCE não cria nada — ele LÊ informações de recursos existentes.
# Aqui usamos para buscar o ID da AMI Ubuntu 22.04 mais recente.
#
# POR QUE USAR EM VEZ DE HARDCODAR?
#   - IDs de AMI são DIFERENTES por região (ami-0c55b1... é us-east-1,
#     outro ID é sa-east-1)
#   - AMIs antigas são descontinuadas pela Canonical periodicamente
#   - Com o data source, o Terraform sempre encontra a versão correta
#     para a região configurada, automaticamente
#
# REFERÊNCIA: data.aws_ami.ubuntu.id
# =============================================================================
data "aws_ami" "ubuntu" {
  most_recent = true

  # owners: ID da Canonical (publicadora oficial do Ubuntu na AWS)
  # Usar o ID do owner evita pegar AMIs não-oficiais com nome similar
  owners = ["099720109477"]

  # filter: filtra AMIs pelo padrão de nome do Ubuntu 22.04 LTS
  # O * no nome age como wildcard — pega qualquer versão de build
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }

  # filter: garante que é uma AMI do tipo HVM (Hardware Virtual Machine)
  # HVM é o tipo moderno e recomendado — PV (Paravirtual) é legado
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  # filter: apenas AMIs com EBS como dispositivo raiz (não instance-store)
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}


# =============================================================================
# 2. KEY PAIR — Par de chaves SSH gerado pelo Terraform
# =============================================================================
# O Terraform gera o par de chaves automaticamente usando o provider TLS,
# elimina o processo manual de criar o par no console AWS e baixar o arquivo.
#
# FLUXO:
#   1. tls_private_key  → gera o par de chaves RSA localmente (em memória)
#   2. aws_key_pair     → envia a chave PÚBLICA para a AWS
#   3. local_file       → salva a chave PRIVADA em disco para acesso SSH
#
# ⚠️  ATENÇÃO: a chave privada ficará salva no tfstate (remoto no S3).
#     Por isso o bucket S3 está configurado com criptografia AES256.
#     Nunca use state local sem criptografia quando gerar chaves SSH.
#
# ALTERNATIVA — se preferir usar uma chave existente no seu sistema:
#   Comente este bloco e descomente o bloco abaixo (key pair manual).
# =============================================================================
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "web" {
  key_name   = local.key_name
  public_key = tls_private_key.web.public_key_openssh

  tags = merge(local.common_tags, {
    Name = local.key_name
  })
}

# Salva a chave privada em disco no diretório do projeto
# Permissão 0600 — obrigatória para que o SSH aceite o arquivo
resource "local_file" "private_key" {
  content         = tls_private_key.web.private_key_pem
  filename        = "${path.module}/${local.key_name}.pem"
  file_permission = "0600"
}

# -----------------------------------------------------------------------------
# ALTERNATIVA — Key Pair a partir de chave existente no sistema
# -----------------------------------------------------------------------------
# Se preferir usar uma chave já existente (~/.ssh/id_rsa.pub):
#   1. Comente o bloco acima (tls_private_key + aws_key_pair + local_file)
#   2. Descomente o bloco abaixo
#   3. Confirme o caminho em var.public_key_path no terraform.tfvars
# -----------------------------------------------------------------------------
#
# resource "aws_key_pair" "web" {
#   key_name   = local.key_name
#   public_key = file(var.public_key_path)
#
#   tags = merge(local.common_tags, {
#     Name = local.key_name
#   })
# }



# =============================================================================
# 3. SECURITY GROUP — Firewall virtual da instância
# =============================================================================
# Define regras de entrada (ingress) e saída (egress) para a instância EC2.
# Por padrão, instâncias EC2 bloqueiam TODO o tráfego.
# O Security Group define EXPLICITAMENTE o que é permitido.
#
# REGRAS CONFIGURADAS:
#   Entrada: porta 22  (SSH)  — acesso ao terminal da instância
#   Entrada: porta 80  (HTTP) — acesso ao Nginx pelo navegador
#   Saída:   tudo      — instância pode fazer downloads, updates etc.
#
# DEPENDÊNCIA IMPLÍCITA:
# Ao referenciar aws_security_group.web.id na EC2, o Terraform
# automaticamente cria o SG ANTES da instância — sem precisar de depends_on.
# =============================================================================
resource "aws_security_group" "web" {
  name        = local.security_group_name
  description = "Permite SSH (22) e HTTP (80) para a instancia de demo"

  # VPC onde o Security Group será criado.
  # Se var.vpc_id for null, usa a VPC padrão da região automaticamente.
  # Em produção, sempre passe o ID explicitamente via terraform.tfvars.
  vpc_id = var.vpc_id

  # ------------------------------------------------------------------
  # INGRESS — tráfego de ENTRADA permitido
  # ------------------------------------------------------------------

  # Porta 22 — SSH: acesso ao terminal da instância
  ingress {
    description = "SSH - acesso remoto ao terminal"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr
    # DICA: em produção, substitua por ["SEU_IP/32"] ou use um bastion host
  }

  # Porta 80 — HTTP: acesso ao servidor Nginx
  ingress {
    description = "HTTP - acesso ao Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr
  }

  # ------------------------------------------------------------------
  # EGRESS — tráfego de SAÍDA permitido
  # ------------------------------------------------------------------

  # Libera todo o tráfego de saída — necessário para apt update/install
  # e para que a instância possa se comunicar com serviços externos
  egress {
    description = "Saida irrestrita - necessario para updates e instalacoes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"    # -1 = todos os protocolos
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = local.security_group_name
  })
}


# =============================================================================
# 4. EC2 INSTANCE — Servidor Ubuntu com Nginx
# =============================================================================
# Cria uma instância EC2 com Ubuntu 22.04 e instala o Nginx automaticamente
# via user_data na primeira inicialização.
#
# DEPENDÊNCIAS IMPLÍCITAS (Terraform resolve automaticamente):
#   - data.aws_ami.ubuntu       → provê o ami ID
#   - aws_key_pair.web          → provê o key_name
#   - aws_security_group.web    → provê o vpc_security_group_ids
#
# USER_DATA:
#   Script executado UMA ÚNICA VEZ quando a instância inicia pela primeira vez.
#   É a forma nativa da AWS de instalar software sem SSH — mais simples e
#   mais confiável do que provisioners remote-exec.
#   Não aparece no `terraform plan` — é opaco para o Terraform.
#
# LIFECYCLE — ignore_changes em tags:
#   A AWS adiciona tags automáticas em instâncias (ex: aws:autoscaling:*).
#   Sem ignore_changes, o Terraform tentaria remover essas tags a cada apply,
#   gerando um diff constante (configuration drift).
# =============================================================================
resource "aws_instance" "web" {
  # AMI: resultado do data source — sempre a versão mais recente do Ubuntu 22.04
  ami = data.aws_ami.ubuntu.id

  # Tipo da instância: configurável por variável
  instance_type = var.instance_type

  # Key Pair: referencia o recurso criado acima — dependência implícita
  key_name = aws_key_pair.web.key_name

  # Security Group: referencia o recurso criado acima — dependência implícita
  vpc_security_group_ids = [aws_security_group.web.id]

  # ---------------------------------------------------------------------------
  # USER_DATA — Script de inicialização
  # ---------------------------------------------------------------------------
  # O heredoc (<<-EOF ... EOF) permite escrever o script inline no HCL.
  # O hífen após << permite que as linhas sejam indentadas sem afetar o script.
  # ---------------------------------------------------------------------------
  user_data = <<-EOF
    #!/bin/bash
    # Atualiza os pacotes do sistema
    sudo apt update -y

    # Instala o Nginx
    sudo apt install -y nginx

    # Habilita o Nginx para iniciar automaticamente com o sistema
    sudo systemctl enable nginx

    # Inicia o Nginx imediatamente
    sudo systemctl start nginx

    # Cria uma página HTML customizada para confirmar o deploy
    cat <<HTML | sudo tee /var/www/html/index.html
    <!DOCTYPE html>
    <html>
    <head><title>Terraform Demo</title></head>
    <body>
      <h1>✅ Terraform Demo — Infraestrutura provisionada com sucesso!</h1>
      <p>Instancia: $(hostname)</p>
      <p>Ambiente: ${var.environment}</p>
      <p>Projeto: ${var.project_name}</p>
    </body>
    </html>
    HTML
  EOF

  # ---------------------------------------------------------------------------
  # USER_DATA HASH:
  # O Terraform detecta mudanças no user_data pelo hash do conteúdo.
  # Se o script mudar, a instância será RECRIADA (não apenas reiniciada),
  # pois o user_data só é executado na primeira inicialização.
  # ---------------------------------------------------------------------------

  tags = merge(local.common_tags, {
    Name = local.instance_name
  })

  # ---------------------------------------------------------------------------
  # LIFECYCLE — ignore_changes
  # ---------------------------------------------------------------------------
  # Ignora mudanças externas nas tags (ex: tags adicionadas via console AWS
  # ou por serviços AWS como Cost Explorer, autoscaling etc.).
  # Sem isso, o Terraform geraria um diff a cada plan tentando remover
  # essas tags automáticas — um falso "configuration drift".
  # ---------------------------------------------------------------------------
  lifecycle {
    ignore_changes = [tags]
  }
}
