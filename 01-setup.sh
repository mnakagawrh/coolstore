#!/bin/bash
set -e  # エラー時に停止

cd $(dirname $0)

# Get current OpenShift user and create project name
USERNAME=$(oc whoami)
PROJECT_NAME="${USERNAME}-wk"
APP_NAME=coolstore-quarkus

echo "======================================"
echo "🚀 01-SETUP: ユーザー用のセットアップを開始: ${USERNAME}"
echo "📂 プロジェクト名: ${PROJECT_NAME}"
echo "🏷️  アプリケーション名: ${APP_NAME}"
echo "====================================="

# Create or switch to project
echo "プロジェクトの作成/切り替え: ${PROJECT_NAME}"
if oc get project ${PROJECT_NAME} >/dev/null 2>&1; then
    echo "プロジェクト ${PROJECT_NAME} は既に存在します。切り替えています..."
    oc project ${PROJECT_NAME}
else
    echo "新しいプロジェクトを作成中: ${PROJECT_NAME}"
    oc new-project ${PROJECT_NAME} --description="Coolstore application for ${USERNAME}" --display-name="Coolstore-${USERNAME}"
fi

# Keycloak configuration
export AUTH_SERVER_URL=https://keycloak-ingress-keycloak.apps.rosa.rhsc2025.c4cn.p3.openshiftapps.com
export AUTH_REALM=eap
export AUTH_RESOURCE=eap-app

# Create keycloak.json from template
echo "Keycloak設定を作成中..."
if command -v envsubst >/dev/null 2>&1; then
    envsubst < keycloak.template.json > src/main/resources/META-INF/resources/keycloak.json
else
    python3 - <<'PY'
import os
from pathlib import Path

template = Path("keycloak.template.json").read_text()
template = template.replace("${AUTH_REALM}", os.environ["AUTH_REALM"])
template = template.replace("${AUTH_SERVER_URL}", os.environ["AUTH_SERVER_URL"])
template = template.replace("${AUTH_RESOURCE}", os.environ["AUTH_RESOURCE"])

output = Path("src/main/resources/META-INF/resources/keycloak.json")
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(template)
PY
fi

# Create BuildConfig
echo "BuildConfigを作成中..."
oc new-build registry.access.redhat.com/ubi8/openjdk-21 --strategy source --binary --name ${APP_NAME} --dry-run -o yaml | oc apply -f -

# Deploy PostgreSQL database using existing postgresql.yaml
echo "coolstoreアプリで使用するPostgreSQLデータベースをセットアップ中..."
if ! oc get cluster postgres >/dev/null 2>&1; then
    echo "deploy/postgresql.yamlを使用してPostgreSQLクラスターを作成中"
    oc apply -f deploy/postgresql.yaml
    
    # Wait for PostgreSQL cluster to be ready
    echo "PostgreSQLクラスターの準備完了を待機中..."
    oc wait --for=condition=Ready cluster/postgres --timeout=300s
    echo "PostgreSQLクラスターの準備が完了しました"
else
    echo "PostgreSQLクラスター 'postgres' は既に存在します"
fi

# Apply postgres credentials
echo "PostgreSQL認証情報を適用中..."
oc apply -f deploy/postgres-cred.yaml

echo "✅ セットアップが正常に完了しました！"