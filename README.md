# polymarket-strikes-upload

Daily backfill of Polymarket BTC/ETH 5-minute **Price to Beat** (Chainlink
TWAP60 strikes) from Polymarket's public Gamma API, run on GitHub Actions and
saved to S3. No VPN, no VM, no stored AWS keys.

## How a run works

1. Loads `btc_5m_strikes.csv` / `eth_5m_strikes.csv` from S3. If a file isn't
   in S3 yet, it falls back to `seed/*.csv.gz`, or rebuilds the file from
   `START_DATE` (about 2 hours, one time only).
2. Runs `crawl_5m_strike_chainlink_twap60_indicator.ipynb` unchanged, apart
   from three settings it now reads from the environment (`STRIKES_DIR`,
   `CREATE_BACKUP`, `ASSET_MODE`). Run locally, it behaves as before.
3. Uploads both CSVs back to S3. If the notebook fails, nothing is uploaded and
   GitHub emails you.

Schedule: daily at 01:00 UTC (09:00 SGT). The **Actions → Backfill 5m strikes
→ Run workflow** button runs it on demand.

Without S3 configured, the workflow still runs and attaches the CSVs to the run
as a downloadable artifact.

## One-time AWS setup

1. Quickest: open **AWS CloudShell** (terminal icon in the console's top bar),
   choose **Actions → Upload file**, upload `aws/setup_cloudshell.sh`, then run:

   ```
   bash setup_cloudshell.sh <your-bucket> [prefix]
   ```

   It detects the bucket's region and whether the GitHub identity provider
   already exists, deploys `aws/github-oidc-s3-role.yaml` as the stack
   `polymarket-strikes-github`, and prints the four variable values below.

   Console alternative: **CloudFormation → Create stack → Upload a template
   file** with `aws/github-oidc-s3-role.yaml` (set `CreateOIDCProvider` to
   `false` if IAM → Identity providers already lists
   `token.actions.githubusercontent.com`), then copy **Outputs → RoleArn**.
2. In this repo: **Settings → Secrets and variables → Actions → Secrets → New
   repository secret**, add two secrets (secrets are masked in the public logs):

   | Secret         | Value                                                    |
   |----------------|----------------------------------------------------------|
   | `AWS_ROLE_ARN` | the stack's `RoleArn`                                    |
   | `S3_BUCKET`    | your bucket name                                         |

   Region and folder default to `ap-northeast-2` and
   `db/polymarket/polymarket_reference`. Override them with the repository
   *variables* `AWS_REGION` / `S3_PREFIX` if needed (the stack's `Prefix` must
   match). The role only allows read/write under that one prefix, and only for
   workflow runs on this repo's `main` branch.
3. Optional: upload your current local CSVs to the prefix once, so the first
   run doesn't rebuild ETH from scratch:

   ```
   aws s3 cp "C:\Wealth Project\db\polymarket\polymarket_reference\eth_5m_strikes.csv" s3://my-bucket/db/polymarket/polymarket_reference/
   aws s3 cp "C:\Wealth Project\db\polymarket\polymarket_reference\btc_5m_strikes.csv" s3://my-bucket/db/polymarket/polymarket_reference/
   ```

4. Optional: turn on **bucket versioning** to keep every previous version
   (this replaces the notebook's local timestamped backups).

## Pulling the results locally

```
aws s3 sync s3://my-bucket/db/polymarket/polymarket_reference/ "C:\Wealth Project\db\polymarket\polymarket_reference" --exclude "*" --include "*_5m_strikes.csv"
```

## Cost

The repo is public, so GitHub Actions minutes are free and unmetered. Public
repos pause scheduled workflows after 60 idle days; the workflow commits
`.github/heartbeat` about once a month to prevent that. S3 storage for two
~25 MB files is negligible.
