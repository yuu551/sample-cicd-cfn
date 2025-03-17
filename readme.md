# CloudFormation ASG Blue/Greenデプロイ実装

## 概要

このリポジトリは、AWS CloudFormationを使用してAuto Scaling Group (ASG)のBlue/Greenデプロイメントを実装するためのコードを提供します。Blue/Greenデプロイメントパターンを使用することで、新しいバージョンのアプリケーション（Green環境）をデプロイし、既存の環境（Blue環境）と並行して稼働させることができます。テスト完了後、トラフィックを切り替えることで、ダウンタイムを最小限に抑えたデプロイが可能になります。

## ディレクトリ構成

```
cicd-cfn/
├── app/
│   ├── network.yaml      # ネットワークリソース定義
│   ├── asg.yaml          # Auto Scaling Group定義
│   ├── iam.yaml          # IAMロールとポリシー定義
│   ├── cicd.yaml         # CI/CDパイプライン定義
│   ├── index.html        # サンプルHTMLファイル
│   ├── appspec.yml       # CodeDeployアプリケーション仕様ファイル
│   └── scripts/          # デプロイスクリプト
│       ├── before_install.sh    # インストール前の準備スクリプト
│       ├── after_install.sh     # インストール後の設定スクリプト
│       ├── application_start.sh # アプリケーション起動スクリプト
│       └── validate_service.sh  # サービス検証スクリプト
```

## CloudFormationテンプレートの役割と実行順序

### 1. network.yaml

**役割**: VPC、サブネット、セキュリティグループ、ロードバランサーなどのネットワークインフラストラクチャを作成します。

**主要リソース**:
- VPC
- パブリックサブネット（2つのアベイラビリティゾーン）
- インターネットゲートウェイ
- ルートテーブル
- セキュリティグループ（WebサーバーとALB用）
- Application Load Balancer (ALB)
- Blue/Green環境用のターゲットグループ

**パラメータ**:
- `EnvironmentName`: 環境名（デフォルト: dev）
- `VpcCIDR`: VPCのCIDRブロック（デフォルト: 10.0.0.0/16）
- `PublicSubnet1CIDR`: パブリックサブネット1のCIDR（デフォルト: 10.0.1.0/24）
- `PublicSubnet2CIDR`: パブリックサブネット2のCIDR（デフォルト: 10.0.2.0/24）

### 2. iam.yaml

**役割**: EC2インスタンスとCodeDeployが必要とするIAMロールとポリシーを作成します。

**主要リソース**:
- EC2インスタンスプロファイル
- CodeDeployサービスロール
- 必要なIAMポリシー

### 3. asg.yaml

**役割**: Blue/Green環境用のAuto Scaling Groupを作成します。

**主要リソース**:
- Blue環境用の起動テンプレート
- Green環境用の起動テンプレート
- Blue環境用のAuto Scaling Group
- Green環境用のAuto Scaling Group（初期状態では作成されない）

**パラメータ**:
- `EnvironmentName`: 環境名
- `InstanceType`: EC2インスタンスタイプ（デフォルト: t3.micro）
- `KeyName`: EC2キーペア名
- `LatestAmiId`: 使用するAMI ID（デフォルト: Amazon Linux 2023）

### 4. cicd.yaml

**役割**: CI/CDパイプラインを構築し、Blue/Greenデプロイメントを自動化します。

**主要リソース**:
- CodeCommitリポジトリ
- CodeBuildプロジェクト
- CodeDeployアプリケーション
- Lambda関数を使用したカスタムリソースによるCodeDeployデプロイメントグループ
- CodePipelineの設定

**パラメータ**:
- `EnvironmentName`: 環境名（デフォルト: dev）
- `GitHubOwner`: GitHubリポジトリのオーナー
- `GitHubRepo`: GitHubリポジトリ名
- `GitHubBranch`: デプロイ対象のブランチ名（デフォルト: main）
- `ApplicationName`: CodeDeployアプリケーション名（デフォルト: MyApplication）

**特記事項**:
- **カスタムリソースによるCodeDeployデプロイメントグループの作成**: 
  - 通常のCloudFormationリソースではなく、Lambda関数を使用したカスタムリソースを実装して、CodeDeployのデプロイメントグループを作成しています。
  - このアプローチにより、Blue/Greenデプロイメントの高度な設定（Auto Scaling Groupのコピー、トラフィック制御、ロールバック設定など）をより柔軟に制御できます。
  - Lambda関数は、デプロイメントグループの作成、更新、削除を処理し、CloudFormationスタックのライフサイクルと連携します。
  - 特に、Green環境のプロビジョニングオプションとして「COPY_AUTO_SCALING_GROUP」を指定し、既存のBlue環境からGreen環境を自動的に作成する機能を実装しています。

## デプロイメントプロセス

1. **ネットワークスタックのデプロイ**:
   ```
   aws cloudformation deploy --template-file app/network.yaml --stack-name network-stack --parameter-overrides EnvironmentName=dev
   ```

2. **IAMスタックのデプロイ**:
   ```
   aws cloudformation deploy --template-file app/iam.yaml --stack-name iam-stack --parameter-overrides EnvironmentName=dev
   ```

3. **ASGスタックのデプロイ**:
   ```
   aws cloudformation deploy --template-file app/asg.yaml --stack-name asg-stack --parameter-overrides EnvironmentName=dev KeyName=your-key-pair
   ```

4. **CI/CDスタックのデプロイ**:
   ```
   aws cloudformation deploy --template-file app/cicd.yaml --stack-name cicd-stack --parameter-overrides EnvironmentName=dev
   ```

## Blue/Greenデプロイメントの仕組み

1. 初期状態では、Blueの環境がトラフィックを処理しています。
2. 新しいバージョンのアプリケーションをデプロイする際、カスタムリソースで作成されたCodeDeployデプロイメントグループが既存のBlue ASGをコピーしてGreen環境を作成します。
3. Green環境が正常に起動したことを確認後、ALBリスナールールを更新してトラフィックをGreen環境に転送します。
4. デプロイが成功した場合、古いBlue環境は終了されます。次回のデプロイでは、現在のGreen環境が新しいBlue環境となります。
5. デプロイに問題がある場合は、トラフィックを元のBlue環境に戻すロールバックが自動的に行われます。

## appspec.yml

CodeDeployがデプロイプロセスを制御するための設定ファイルです。アプリケーションのライフサイクルイベント（インストール前、インストール後など）に対応するスクリプトを指定します。

## デプロイスクリプト（scripts/）

`scripts`ディレクトリには、CodeDeployのライフサイクルイベントで実行される以下のスクリプトが含まれています：

1. **before_install.sh**:
   - デプロイ前の準備を行います
   - インストールディレクトリ（/var/www/html/）をクリーンアップします

2. **after_install.sh**:
   - アプリケーションファイルのインストール後に実行されます
   - 必要な設定やパーミッションの調整を行います

3. **application_start.sh**:
   - アプリケーションサービスを起動/再起動します
   - Webサーバー（httpd）の再起動などを行います

4. **validate_service.sh**:
   - デプロイ後にサービスが正常に動作しているかを検証します
   - ヘルスチェックを実行し、アプリケーションの状態を確認します

これらのスクリプトは`appspec.yml`で指定されたライフサイクルイベントに従って順番に実行され、デプロイプロセスの各段階で必要な処理を行います。

## 注意事項

- 実際の本番環境では、セキュリティグループの設定をより厳格にすることをお勧めします。
- キーペアは事前に作成しておく必要があります。
- 各スタックのパラメータは、環境に合わせて適切に設定してください。
