#!/usr/bin/env bash
# ==============================================================================
# Script de Configuração e Sincronização do Git + GitHub na EC2 (Debian 13)
# ==============================================================================

set -e

# Cores para destaque no terminal
VERDE='\033[0;32m'
AZUL='\033[0;34m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
NEGRITO='\033[1m'
NC='\033[0m'

clear
echo -e "${AZUL}${NEGRITO}======================================================================${NC}"
echo -e "${AZUL}${NEGRITO}       CONFIGURAÇÃO DE GIT & GITHUB NA EC2 (DEBIAN 13)               ${NC}"
echo -e "${AZUL}${NEGRITO}======================================================================${NC}"
echo -e "${AMARELO}Preencha as informações solicitadas abaixo:${NC}\n"

# ------------------------------------------------------------------------------
# 1. ENTRADA DE DADOS
# ------------------------------------------------------------------------------
echo -e "${AZUL}${NEGRITO}>>> [ETAPA 1/6] Configuração de Parâmetros${NC}"

read -p "Caminho do projeto na EC2 [/var/www/html/meu-projeto]: " PROJ_DIR
PROJ_DIR=${PROJ_DIR:-/var/www/html/meu-projeto}

read -p "Seu Nome Completo (para commits do Git): " GIT_USER
while [ -z "$GIT_USER" ]; do
    echo -e "${VERMELHO}O nome não pode ser vazio.${NC}"
    read -p "Seu Nome Completo: " GIT_USER
done

read -p "Seu E-mail cadastrado no GitHub: " GIT_EMAIL
while [ -z "$GIT_EMAIL" ]; do
    echo -e "${VERMELHO}O e-mail não pode ser vazio.${NC}"
    read -p "Seu E-mail do GitHub: " GIT_EMAIL
done

read -p "Nome de Usuário no GitHub (username): " GH_USER
while [ -z "$GH_USER" ]; do
    echo -e "${VERMELHO}O usuário não pode ser vazio.${NC}"
    read -p "Usuário GitHub: " GH_USER
done

read -p "Nome do Repositório no GitHub: " GH_REPO
while [ -z "$GH_REPO" ]; do
    echo -e "${VERMELHO}O repositório não pode ser vazio.${NC}"
    read -p "Repositório GitHub: " GH_REPO
done

echo ""
echo -e "${VERDE}Parâmetros definidos:${NC}"
echo -e " • Pasta do Projeto: ${NEGRITO}$PROJ_DIR${NC}"
echo -e " • Usuário Git:      ${NEGRITO}$GIT_USER${NC}"
echo -e " • E-mail Git:       ${NEGRITO}$GIT_EMAIL${NC}"
echo -e " • Repositório:      ${NEGRITO}git@github.com:$GH_USER/$GH_REPO.git${NC}"
echo ""
read -p "Pressione [ENTER] para iniciar a execução..."

# ------------------------------------------------------------------------------
# 2. PRÉ-TESTE NO AMBIENTE
# ------------------------------------------------------------------------------
echo -e "\n${AZUL}${NEGRITO}>>> [ETAPA 2/6] Pré-teste no Ambiente EC2${NC}"
echo -e "Usuário logado: $(whoami)"

if [ ! -d "$PROJ_DIR" ]; then
    echo -e "${AMARELO}Diretório não existe. Criando $PROJ_DIR...${NC}"
    sudo mkdir -p "$PROJ_DIR"
    sudo chown -R "$(whoami)":"$(whoami)" "$PROJ_DIR"
fi

cd "$PROJ_DIR"
pwd

if [ -w "$PROJ_DIR" ]; then
    echo -e "${VERDE}✔ Pasta com permissão de escrita.${NC}"
else
    echo -e "${VERMELHO}✖ Sem permissão de escrita. Ajustando dono da pasta para $(whoami)...${NC}"
    sudo chown -R "$(whoami)":"$(whoami)" "$PROJ_DIR"
fi

# ------------------------------------------------------------------------------
# 3. INSTALAÇÃO E CONFIGURAÇÃO GLOBAL DO GIT
# ------------------------------------------------------------------------------
echo -e "\n${AZUL}${NEGRITO}>>> [ETAPA 3/6] Verificando Git e Configurações Globais${NC}"
if ! command -v git &> /dev/null; then
    echo -e "${AMARELO}Instalando git e openssh-client via apt...${NC}"
    sudo apt update && sudo apt install -y git openssh-client
else
    echo -e "${VERDE}✔ Git já instalado: $(git --version)${NC}"
fi

git config --global user.name "$GIT_USER"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main

echo -e "${VERDE}✔ Configuração global aplicada:${NC}"
git config --global --list

# ------------------------------------------------------------------------------
# 4. CHAVE SSH PARA O GITHUB
# ------------------------------------------------------------------------------
echo -e "\n${AZUL}${NEGRITO}>>> [ETAPA 4/6] Configuração de Chave SSH${NC}"
SSH_KEY="$HOME/.ssh/id_ed25519"

if [ ! -f "$SSH_KEY" ]; then
    echo -e "${AMARELO}Gerando nova chave SSH ed25519...${NC}"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
else
    echo -e "${VERDE}✔ Chave SSH existente encontrada em $SSH_KEY${NC}"
fi

echo -e "\n${AMARELO}${NEGRITO}======================================================================${NC}"
echo -e "${AMARELO}${NEGRITO}ATENÇÃO: COPIE A CHAVE PÚBLICA ABAIXO E ADICIONE NO GITHUB:${NC}"
echo -e "${AMARELO}Acesse: https://github.com/settings/keys -> Clique em 'New SSH key'${NC}"
echo -e "${AMARELO}${NEGRITO}======================================================================${NC}\n"
cat "${SSH_KEY}.pub"
echo -e "\n${AMARELO}${NEGRITO}======================================================================${NC}\n"

read -p "Já cadastrou a chave pública no GitHub? Pressione [ENTER] para testar a conexão..."

echo -e "\nTestando autenticação SSH com o GitHub..."
set +e
ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | tee /tmp/ssh_test.log
set -e

if grep -q -E "(successfully authenticated|Hi )" /tmp/ssh_test.log; then
    echo -e "${VERDE}✔ Autenticação SSH confirmada com sucesso!${NC}"
else
    echo -e "${VERMELHO}Aviso: Falha ao autenticar via SSH.${NC}"
    read -p "Deseja prosseguir mesmo assim? (s/n): " CONTINUAR
    if [[ "$CONTINUAR" != "s" && "$CONTINUAR" != "S" ]]; then
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# 5. .GITIGNORE E REPOSITÓRIO LOCAL
# ------------------------------------------------------------------------------
echo -e "\n${AZUL}${NEGRITO}>>> [ETAPA 5/6] Preparando .gitignore e Repositório Local${NC}"
cd "$PROJ_DIR"

if [ ! -f .gitignore ]; then
    echo -e "${AMARELO}Criando .gitignore padrão...${NC}"
    cat > .gitignore <<'EOF'
.env
.env.*
config.local.php
*.log
/vendor/
/node_modules/
/uploads/
EOF
    echo -e "${VERDE}✔ .gitignore criado.${NC}"
else
    echo -e "${VERDE}✔ .gitignore existente mantido.${NC}"
fi

if [ ! -d .git ]; then
    echo -e "Inicializando repositório Git com branch main..."
    git init -b main
else
    echo -e "${VERDE}✔ Repositório local já existente.${NC}"
fi

# Cria um arquivo se o diretório estiver limpo
if [ -z "$(ls -A "$PROJ_DIR" | grep -v '^\.git$')" ]; then
    echo "<h1>Meu Projeto na EC2</h1>" > index.php
    echo -e "${AMARELO}Pasta estava vazia: index.php criado para teste.${NC}"
fi

git add .

if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    git commit -m "Versão inicial do projeto"
    echo -e "${VERDE}✔ Commit inicial criado.${NC}"
else
    echo -e "${VERDE}✔ Nenhum arquivo pendente para commit.${NC}"
fi

git log --oneline -n 3 2>/dev/null || true

# ------------------------------------------------------------------------------
# 6. REMOTE E PUSH INICIAL
# ------------------------------------------------------------------------------
echo -e "\n${AZUL}${NEGRITO}>>> [ETAPA 6/6] Configurando Remote e Realizando Push${NC}"
REMOTE_URL="git@github.com:$GH_USER/$GH_REPO.git"

if git remote | grep -q "^origin$"; then
    echo -e "${AMARELO}Remote origin já existia. Atualizando URL para: $REMOTE_URL${NC}"
    git remote set-url origin "$REMOTE_URL"
else
    git remote add origin "$REMOTE_URL"
fi

git remote -v

echo -e "\n${AZUL}Enviando arquivos (git push -u origin main)...${NC}"
if git push -u origin main; then
    echo -e "\n${VERDE}${NEGRITO}✔ Sucesso! Projeto publicado no GitHub.${NC}"
else
    echo -e "\n${VERMELHO}✖ Erro no git push.${NC}"
    echo -e "${AMARELO}Se o repositório remoto foi criado com README/licença, execute:${NC}"
    echo -e "git pull --rebase origin main && git push origin main"
    exit 1
fi

# ------------------------------------------------------------------------------
# CHECKLIST FINAL
# ------------------------------------------------------------------------------
echo -e "\n${AZUL}${NEGRITO}======================================================================${NC}"
echo -e "${VERDE}${NEGRITO}           CHECKLIST FINAL CONCLUÍDO COM SUCESSO!                    ${NC}"
echo -e "${AZUL}${NEGRITO}======================================================================${NC}"
echo -e "[✔] Git: $(git --version)"
echo -e "[✔] Pasta: $(pwd)"
echo -e "[✔] .gitignore criado e validado"
echo -e "[✔] Commit registrado:"
git log --oneline -n 1
echo -e "[✔] Remote origin configurado:"
git remote -v | head -n 1
echo -e "${AZUL}======================================================================${NC}\n"
