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

Schedule: daily at 00:13 UTC (08:13 SGT). The **Actions → Backfill 5m strikes
→ Run workflow** button runs it on demand.

Without S3 configured, the workflow still runs and attaches the CSVs to the run
as a downloadable artifact.

## One-time AWS setup

1. In the AWS console, open **CloudFormation → Create stack → Upload a template
   file** and pick `aws/github-oidc-s3-role.yaml`.
   - `BucketName`: your existing bucket.
   - `Prefix`: folder for the CSVs (default `polymarket_reference`).
   - `CreateOIDCProvider`: `false` only if IAM → Identity providers already
     lists `token.actions.githubusercontent.com`.
   - Tick the IAM acknowledgement and create.
2. Copy the stack's **Outputs → RoleArn**.
3. In this repo: **Settings → Secrets and variables → Actions → Variables**,
   add:

   | Variable       | Example                                                |
   |----------------|--------------------------------------------------------|
   | `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-polymarket-strikes` |
   | `AWS_REGION`   | `ap-southeast-1`                                       |
   | `S3_BUCKET`    | `my-bucket`                                            |
   | `S3_PREFIX`    | `polymarket_reference` (same as the stack's `Prefix`)  |

   None of these are secrets. The role only allows read/write under that one
   prefix, and only for workflow runs on this repo's `main` branch.
4. Optional: upload your current local CSVs to the prefix once, so the first
   run doesn't rebuild ETH from scratch:

   ```
   aws s3 cp "C:\Wealth Project\db\polymarket\polymarket_reference\eth_5m_strikes.csv" s3://my-bucket/polymarket_reference/
   aws s3 cp "C:\Wealth Project\db\polymarket\polymarket_reference\btc_5m_strikes.csv" s3://my-bucket/polymarket_reference/
   ```

5. Optional: turn on **bucket versioning** to keep every previous version
   (this replaces the notebook's local timestamped backups).

## Pulling the results locally

```
aws s3 sync s3://my-bucket/polymarket_reference/ "C:\Wealth Project\db\polymarket\polymarket_reference" --exclude "*" --include "*_5m_strikes.csv"
```

## Cost

GitHub's free plan includes 2,000 Actions minutes a month for private repos. A
daily run takes a few minutes. S3 storage for two ~25 MB files is negligible.
