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

# Busca uma lista com todos os repositórios do workspace no Bitbucket
REPO_LIST=$(curl -s -u "$BITBUCKET_USERNAME:$BITBUCKET_PASSWORD" "$BITBUCKET_BASE_URL/repositories/$BITBUCKET_WORKSPACE?q=updated_on%20%3E%20$LAST_UPDATED_ENCODED&sort=-updated_on&pagelen=100")

# Loop pelos repositórios na lista
for ROW in $(echo "${REPO_LIST}" | jq -r '.values[] | @base64'); do
  _jq() {
    echo ${ROW} | base64 --decode | jq -r ${1}
  }

  # Extrai o nome do repositório
  REPO_NAME=$(_jq '.name')

  echo "Repo name: "
  echo $REPO_NAME

  # Clona o repositório do Bitbucket localmente
  git clone --mirror "https://$BITBUCKET_USERNAME:$BITBUCKET_PASSWORD@bitbucket.org/$BITBUCKET_WORKSPACE/$REPO_NAME.git"
  cd "$REPO_NAME.git"

  # Faz o push com mirror do repositório
  git push --mirror --force "https://$GITLAB_NAMESPACE:$GITLAB_TOKEN@gitlab.com/$GITLAB_NAMESPACE/$REPO_NAME.git"

  # Retorna para o diretório anterior
  cd ..
done

# Mensagem de conclusão
echo "Transferência concluída!"

exit 0
