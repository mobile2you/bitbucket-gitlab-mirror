#!/bin/bash
set -ex

# Limpa os repositórios antes de buscar novos repositórios
rm -rf TestRepo.git/ TestRepo1.git/ TestRepo2.git/

# Configuração das variáveis
GITLAB_BASE_URL="https://gitlab.com/api/v4"
BITBUCKET_BASE_URL="https://api.bitbucket.org/2.0"

# Subtrai o número de dias da data atual e converte em um formato aceito pela URL
if [[ "$OSTYPE" == "darwin"* ]]; then # Processamento de datas para sistemas MacOS
    LAST_UPDATED=$(date '+%Y-%m-%d')
    LAST_UPDATED_UNIX=$(date -j -f "%Y-%m-%d" "$LAST_UPDATED" "+%s")
    LAST_UPDATED_UNIX=$(expr $LAST_UPDATED_UNIX - $DAYS_TO_LOOK_BACK \* 24 \* 3600)
    LAST_UPDATED=$(date -r "$LAST_UPDATED_UNIX" -u "+%Y-%m-%dT%H:%M:%S-00:00")
else # Processamento de datas para sistemas Linux
    LAST_UPDATED=$(date +%s)
    LAST_UPDATED=$(expr $LAST_UPDATED - $DAYS_TO_LOOK_BACK \* 24 \* 3600)
    LAST_UPDATED=$(date -u -d @"$LAST_UPDATED" "+%Y-%m-%dT%H:%M:%S-00:00")
fi

LAST_UPDATED_ENCODED=$(echo "$LAST_UPDATED" | sed 's/:/%3A/g')

# Busca a primeira página com os repositórios
FIRST_PAGE=$(curl -s -u "$BITBUCKET_USERNAME:$BITBUCKET_PASSWORD" "$BITBUCKET_BASE_URL/repositories/$BITBUCKET_WORKSPACE?q=updated_on%20%3E%20$LAST_UPDATED_ENCODED&sort=-updated_on&pagelen=50")

# Imprime a contagem de repositórios
echo "Foram encontrados $(echo "$FIRST_PAGE" | jq -r '.size') repositórios."

# Inicializa a variável de próxima página
NEXT_PAGE=$(echo "$FIRST_PAGE" | jq -r '.next')

# Inicializa a lista de repositórios com a primeira página de resultados
REPO_LIST=$(echo "$FIRST_PAGE" | jq -r '.values[].slug')

# Enquanto houver uma próxima página de resultados
while [[ ! -z "$NEXT_PAGE" && "$NEXT_PAGE" != "null" ]]; do
    # Busca a próxima página de resultados
    NEW_PAGE=$(curl -s -u "$BITBUCKET_USERNAME:$BITBUCKET_PASSWORD" "$NEXT_PAGE")
    # Adiciona os nomes dos repositórios da próxima página à lista de repositórios
    REPO_LIST=$(echo "$REPO_LIST"; echo "$NEW_PAGE" | jq -r '.values[].slug')
    # Obtém o link para a próxima página, se houver
    NEXT_PAGE=$(echo "$NEW_PAGE" | jq -r '.next')
done

# Imprime a lista com todos os repositórios
echo "$REPO_LIST" | nl -w 2 -s '. '

# Lista com os erros para cada repositório
ERROR_MESSAGES=()

# Itera na lista de repositórios encontrados
for REPO_NAME in $REPO_LIST; do
  # Clona o repositório do Bitbucket localmente
  git clone --bare "https://$BITBUCKET_USERNAME:$BITBUCKET_PASSWORD@bitbucket.org/$BITBUCKET_WORKSPACE/$REPO_NAME.git"
  cd "$REPO_NAME.git"

  # Faz o push com mirror do repositório
  if ! git push --mirror --force "https://$GITLAB_NAMESPACE:$GITLAB_TOKEN@$GITLAB_WORKSPACE/$REPO_NAME.git"; then
    # Adiciona a mensagem de erro na lista
    ERROR_MESSAGES+=("$REPO_NAME - Falha ao fazer o mirror do repositório no Gitlab")
  fi

  # Retorna para o diretório anterior
  cd ..
done

# Imprime a lista de erros, caso haja
if [[ ${#ERROR_MESSAGES[@]} -gt 0 ]]; then
  ERROR_STRING=$(printf '%s\n' "${ERROR_MESSAGES[@]}" | awk '{print NR". "$0}')
  envman add --key ERROR_MESSAGE_OUTPUT --value "$ERROR_STRING"
  exit 1
else
  echo "Transferência concluída!"
  exit 0
fi

