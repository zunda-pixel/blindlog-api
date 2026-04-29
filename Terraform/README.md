# blindlog-api Terraform (prod)

Cloud Run / Artifact Registry / Secret Manager / IAM を Terraform で管理する。
Image のビルドと push、Cloud Run への反映は GitHub Actions が行う (`.github/workflows/deploy.yml`)。

## 構成概要

- **PR**: 既存の `ci.yml` が Docker build 検証のみ (push しない)
- **`main` push**: `deploy.yml` が build → Artifact Registry に push → `gcloud run services update --image=...` で Cloud Run 更新
- **認証**: Workload Identity Federation。長期鍵 (JSON) なし
- **Terraform 実行**: 当面オペレータ手元から (GHA で terraform apply は回さない)
- **環境**: prod のみ
- **公開範囲**: `allow_unauthenticated = true` のため Cloud Run は **public endpoint** として公開される。アプリ層 (Hummingbird) の認証ミドルウェア + Valkey ベースのレートリミットで保護する前提。

## Bootstrap 手順 (初回のみ)

### 0. 作業用環境変数を設定

以降のコマンドで使い回すのでシェルに export しておく。新しいターミナルで作業を再開する場合は毎回ここから実行する。

```sh
export PROJECT_ID="<your-gcp-project-id>"
export REGION="asia-northeast1"              # prod Cloud Run を動かすリージョン
export STATE_BUCKET="${PROJECT_ID}-tfstate"  # Terraform state 用 GCS バケット名
```

### 1. Google Cloud プロジェクトに Owner/Editor で認証

```sh
gcloud auth application-default login
gcloud config set project "$PROJECT_ID"
```

### 2. 必要 API の先行有効化

Terraform 自身が `google_project_service` で残りを有効化するが、その前段で `serviceusage` (他 API を有効化するための API)、`cloudresourcemanager` (project lookup)、`iam` の 3 つは手で有効化しておく必要がある。これらが無効だと `terraform init` / 最初の `apply` が通らない。

```sh
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com
```

### 3. State bucket 作成

Terraform の state を保存する GCS バケット (名前は `$STATE_BUCKET`) を作る。バケット名は Google Cloud 全体でグローバル一意なので、`<PROJECT_ID>-tfstate` 形式にしておけば衝突しにくい。

```sh
gcloud storage buckets create "gs://$STATE_BUCKET" \
  --location="$REGION" \
  --uniform-bucket-level-access
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
```

### 4. 変数ファイルを作る

```sh
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
```

### 5. `terraform init`

```sh
terraform init \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="prefix=blindlog-api"
```

### 6. 既存リソースを import

現在 Google Cloud コンソールで動いている Cloud Run サービスを destroy/recreate すると本番が落ちる。以下を先に import する。

> **ブラウンフィールド注意**: 過去に手動で作った同名リソース (例: `blindlog-api-runtime` SA、`github-pool` WIF pool、Artifact Registry repo) が残っている場合、初回 apply で `Already Exists` エラーになる。下記の Cloud Run / AR / Secret に加え、既存の SA や WIF pool/provider があれば同様に import する (resource address は `terraform plan` の create 計画から逆引き)。新規プロジェクトでの bootstrap なら不要。

```sh
# 直前に手順 0 の env が export されていることを確認
echo "Importing into project=$PROJECT_ID, region=$REGION"
test -n "$PROJECT_ID" -a -n "$REGION" || { echo "PROJECT_ID/REGION not set"; exit 1; }

# 既存 Cloud Run service
terraform import google_cloud_run_v2_service.api \
  "projects/$PROJECT_ID/locations/$REGION/services/blindlog-api"

# Artifact Registry repo (すでに作っている場合のみ)
terraform import google_artifact_registry_repository.app \
  "projects/$PROJECT_ID/locations/$REGION/repositories/blindlog-api"

# 既存の Secret Manager secret (1個ずつ)
terraform import 'google_secret_manager_secret.app["POSTGRES_PASSWORD"]' \
  "projects/$PROJECT_ID/secrets/POSTGRES_PASSWORD"
terraform import 'google_secret_manager_secret.app["VALKEY_PASSWORD"]' \
  "projects/$PROJECT_ID/secrets/VALKEY_PASSWORD"
terraform import 'google_secret_manager_secret.app["EDDSA_PRIVATE_KEY"]' \
  "projects/$PROJECT_ID/secrets/EDDSA_PRIVATE_KEY"
terraform import 'google_secret_manager_secret.app["CLOUDFLARE_API_TOKEN"]' \
  "projects/$PROJECT_ID/secrets/CLOUDFLARE_API_TOKEN"
terraform import 'google_secret_manager_secret.app["OTP_SECRET_KEY"]' \
  "projects/$PROJECT_ID/secrets/OTP_SECRET_KEY"
```

(既存の secret_id が上と違う場合は Google Cloud コンソールで確認して合わせる。)

### 7. Plan が空になるまで調整

```sh
terraform plan
```

差分が出るものを `terraform.tfvars` の `app_env` と各 `variables.tf` の値で一致させる。annotations やラベルなど無害な drift が残る場合は `cloud_run.tf` の `lifecycle.ignore_changes` に追加する。

**重要**: `image_tag` は現在 prod で動いている image の tag を渡す (例: `image_tag = "<current-sha>"`)。ただし `ignore_changes = [template[0].containers[0].image]` を入れているため、ここで渡した値は実際には適用されず、現行の image タグはそのまま維持される。

### 8. Secret の入れ物だけ先に作る

```sh
terraform apply \
  -target=google_project_service.required \
  -target=google_secret_manager_secret.app
```

初回 bootstrap では、Secret Manager に `latest` version が存在しない状態で Cloud Run を作ると失敗する。ここでは API 有効化と secret の入れ物作成だけを先に済ませる。

### 9. Secret 値のアップロード

Terraform は secret の「入れ物」だけ作る。値は手で入れる。

```sh
printf '%s' "<POSTGRES_PASSWORD_VALUE>"    | gcloud secrets versions add POSTGRES_PASSWORD    --data-file=-
printf '%s' "<VALKEY_PASSWORD_VALUE>"      | gcloud secrets versions add VALKEY_PASSWORD      --data-file=-
printf '%s' "<EDDSA_PRIVATE_KEY_VALUE>"    | gcloud secrets versions add EDDSA_PRIVATE_KEY    --data-file=-
printf '%s' "<CLOUDFLARE_API_TOKEN_VALUE>" | gcloud secrets versions add CLOUDFLARE_API_TOKEN --data-file=-
printf '%s' "<OTP_SECRET_KEY_VALUE>"       | gcloud secrets versions add OTP_SECRET_KEY       --data-file=-
```

### 10. 全体を `terraform apply`

```sh
terraform apply
```

Cloud Run service, WIF pool/provider, deployer SA, IAM bindings などの新規リソースが作成される。

### 11. GitHub 側の設定

`terraform output` で値を確認し、GitHub リポジトリの Settings → Secrets and variables → Actions → **Variables** に登録する (Secrets ではなく Variables で良い。WIF 構成値は機密ではない)。

| Variable 名 | 値のソース |
|---|---|
| `GOOGLE_CLOUD_PROJECT` | `terraform.tfvars` の `project_id` |
| `GOOGLE_CLOUD_REGION` | `terraform.tfvars` の `region` |
| `GOOGLE_CLOUD_SERVICE_NAME` | `terraform.tfvars` の `service_name` (未指定なら `blindlog-api`) |
| `GOOGLE_CLOUD_ARTIFACT_REPO` | `terraform.tfvars` の `artifact_repo_id` (未指定なら `blindlog-api`) |
| `GOOGLE_CLOUD_WIF_PROVIDER` | `terraform output -raw wif_provider` |
| `GOOGLE_CLOUD_DEPLOYER_SA` | `terraform output -raw deployer_sa_email` |

### 12. 既存の Cloud Build トリガーを無効化

```sh
gcloud builds triggers list
gcloud builds triggers update <TRIGGER_ID> --disabled=true
```

GHA deploy がグリーンになってから 1〜2 週間問題なく回ったことを確認し、問題なければ `gcloud builds triggers delete <TRIGGER_ID>`。

## 日常運用

### 設定変更

Cloud Run の env / scaling / resources などは `terraform.tfvars` や `*.tf` を編集して `terraform apply`。GHA の image 更新とは独立している (image は `ignore_changes`)。

### Secret 値のローテーション

```sh
printf '%s' "<new>" | gcloud secrets versions add <secret-id> --data-file=-
```

Cloud Run は `version = "latest"` 参照なので、次回リビジョン作成時に新しい値が読まれる。すぐ反映させたい場合は GHA deploy を回すか、`gcloud run services update blindlog-api --region=$REGION --update-env-vars=_DUMMY=$(date +%s)` のような空更新で新リビジョンを作る。

### Image ロールバック

過去の SHA を指定して手で回す (Bootstrap 手順 0 と同じ `PROJECT_ID`/`REGION` を export しておく):

```sh
gcloud run services update blindlog-api \
  --region="$REGION" \
  --image="$REGION-docker.pkg.dev/$PROJECT_ID/blindlog-api/blindlog-api:<OLD_SHA>"
```
