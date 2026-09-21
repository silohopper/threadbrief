# AWS Deploy (S3 + CloudFront + Lambda + DynamoDB)

This folder contains Terraform for `ap-southeast-2`. The stack is fully
serverless:

- **Web** (`services/web`) is a static Next.js export (`next build` with
  `output: "export"`) served from a private S3 bucket behind CloudFront.
- **API** (`services/api`) is a container-image Lambda function, reached
  directly via its Function URL (no API Gateway — see "Why no API Gateway"
  below). Briefs and per-IP rate limits are stored in DynamoDB.

There's no ECS, no ALB, and no always-on compute: everything bills
pay-per-request, so an idle environment costs close to $0/month.

## Prereqs
- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Docker

## Step 1) Install tools
Make sure these are installed locally:
```bash
aws --version
terraform -version
docker --version
```
If anything is missing:
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Terraform: https://developer.hashicorp.com/terraform/downloads
- Docker Desktop: https://www.docker.com/products/docker-desktop/

## Important: separate Terraform state per env
Staging and prod must not share the same Terraform state. The tooling uses
Terraform workspaces (`stage`, `prod`) so resources don't overwrite each
other.

From now on, use `sh bin/tools.sh stage ...` and `sh bin/tools.sh prod ...`
only. As of this writing, only `prod` (`threadbrief.com`) is actually
provisioned — `stage` was torn down after `prod` was verified, since this is
a demo project that doesn't need a permanent second environment. The
`stage` workspace still works if you want to stand it back up (`sh bin/tools.sh
stage up`); it creates the exact same kind of resources as `prod`, just under
`staging.threadbrief.com`.

## Known issues (temporary)
- Route53 hosted zone duplication: if multiple public zones exist for
  `threadbrief.com`, Terraform may pick the wrong one. For now, set
  `route53_zone_id` in `infra/terraform/envs/prod.tfvars` to the correct public
  hosted zone ID (strip the `/hostedzone/` prefix). Use:
  ```bash
  sh bin/tools.sh prod zoneid
  ```

## Step 2) Create the IAM policy and group (console)
This creates a least-privilege policy and a group that uses it.

1) Go to **IAM** → **Policies** → **Create policy**.
2) Select the **JSON** tab.
3) Paste the JSON from **Suggested IAM policy** below and click **Next**.
4) Name it `threadbrief-deploy` and click **Create policy**.
5) Go to **IAM** → **User groups** → **Create group**.
6) Name the group `threadbrief`.
7) Attach the `threadbrief-deploy` policy to the group and create it.

## Step 3) Create an IAM user (console)
This creates a programmatic user for the AWS CLI.

1) Go to **IAM** → **Users** → **Create user**.
2) Name it `threadbrief`.
3) On **Set permissions**, add it to the `threadbrief` group.
4) Finish creating the user.
5) Open the user → **Security credentials** → **Create access key**.
6) Choose **Command Line Interface (CLI)**.
7) Save the **Access Key ID** and **Secret Access Key**.

## Step 4) Configure AWS CLI credentials
This tells Terraform and the deploy script which AWS account to use.
```bash
aws configure
```
You will be asked for:
- Access Key ID
- Secret Access Key
- Default region (`ap-southeast-2`)
- Output format (you can leave blank)

### Suggested IAM policy (least-privilege starter)
Create a policy with the JSON below and attach it to your `threadbrief` IAM
group/user. This covers the services used by the Terraform stack and deploy
script without granting full admin access.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "acm:*",
        "cloudfront:*",
        "dynamodb:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:PassRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:CreateServiceLinkedRole",
        "iam:CreatePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeleteServiceLinkedRole",
        "iam:GetServiceLinkedRoleDeletionStatus",
        "iam:DeletePolicyVersion",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:ListPolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy",
        "ecr:*",
        "lambda:*",
        "logs:*",
        "route53:*",
        "s3:*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```
If you want "delete and re-add" to be the default recovery path, make sure this
policy includes `iam:DeletePolicyVersion` so Terraform can fully remove and
recreate IAM policies during rebuilds.

## Step 5) Decide your domain
For staging (optional, see above):
- Web: `staging.threadbrief.com`

For prod, the web domain is `threadbrief.com`. There is no API domain —
Lambda Function URLs don't support custom domains, so the API is always
reached at its raw `*.lambda-url.<region>.on.aws` address (the web app's
build picks this up automatically from the Terraform output). These are
already set in `infra/terraform/envs/{stage,prod}.tfvars`.

## Step 6) Provision infrastructure
This creates the S3 bucket, CloudFront distribution, DynamoDB table, Lambda
function + Function URL, and the ACM cert CloudFront needs (in us-east-1,
regardless of `aws_region` — CloudFront requires that).
```bash
sh bin/tools.sh prod up
```

If Terraform fails with "already exists" errors (state drift), run:
```bash
sh bin/tools.sh prod resync
```
Then re-run `sh bin/tools.sh prod up`.

## Step 7) Point GoDaddy DNS to AWS (one time)
Terraform creates a Route53 hosted zone and gives you 4 name servers. You need
to point your domain to those name servers.

## GoDaddy DNS update
1) Run this from the repo root to get the Route53 nameservers:
   ```bash
   sh bin/tools.sh prod dns
   ```
2) Open your domain in GoDaddy → DNS settings.
3) Replace the existing nameservers with the Route53 values from the command above.
4) Wait for DNS propagation (usually minutes, sometimes longer).

Terraform will keep waiting at the ACM validation step until DNS is updated and
propagated.

## Step 8) Wait for SSL to validate (ACM)
ACM is AWS Certificate Manager. It issues the cert CloudFront uses for HTTPS.
Once GoDaddy is pointing at Route53, ACM will validate automatically via the
DNS records Terraform creates for it — no manual step needed.

How to check ACM:
1) AWS Console → **ACM** (switch to the **us-east-1 / N. Virginia** region —
   the CloudFront cert lives there regardless of `aws_region`).
2) Open the cert and confirm **Status: Issued**.

## Step 9) Deploy
This applies Terraform, builds and pushes the API's Lambda container image,
force-updates the Lambda function, builds the static web export (pointed at
the Lambda Function URL), syncs it to S3, and invalidates the CloudFront
cache.
```bash
sh bin/tools.sh prod deploy
```

### Optional: yt-dlp proxy (recommended for AWS)
YouTube often blocks AWS datacenter IPs even with cookies. A residential proxy
fixes this. If you have a proxy URL:
1) Save it to `env/<env>/proxy.txt` (one line, e.g. `http://user:pass@host:port` or
   `host:port:username:password`). We are currently using Decodo (Smartproxy).
2) Run `sh bin/tools.sh prod deploy`.

The deploy script reads `env/<env>/proxy.txt` (or `env/dev/proxy.txt`) and
passes it straight to the Lambda function's environment as `YTDLP_PROXY`.

### Captions-only mode
The demo API does not run Whisper. Videos must have transcripts/captions available
via YouTube/yt-dlp or the request will return an error.

## Step 10) Test
- Web: https://threadbrief.com
- API health (no custom domain — read the real URL from Terraform):
  ```bash
  sh bin/tools.sh prod status   # or: terraform -chdir=infra/terraform output lambda_function_url
  ```

## Step 11) Destroy (when done)
```bash
sh bin/tools.sh prod down
```

## Why no API Gateway
API Gateway (REST or HTTP API) hard-caps integration timeouts at ~30 seconds,
with no way to raise it. Brief generation (transcript fetch + Gemini call) can
legitimately take several minutes for long videos — prod allows videos up to
180 minutes and the old ALB was explicitly configured with a 900s idle
timeout for exactly this reason. A Lambda Function URL inherits Lambda's own
timeout (up to 900s) instead, with no intermediate proxy imposing a shorter
cap. The trade-off is no custom domain for the API.

## Debug checklist (when something goes wrong)
1) **Terraform state**
   - Re-run: `sh bin/tools.sh prod up` (auto-resync on failure).
   - If it still fails or resources are inconsistent, delete and re-add:
     `sh bin/tools.sh prod down` then `sh bin/tools.sh prod up`.
2) **Lambda logs**
   ```bash
   sh bin/tools.sh prod logs
   ```
3) **CloudFront**
   - AWS Console → CloudFront → the distribution → check it's `Deployed`,
     and check the S3 origin / OAC settings if requests 403.
4) **DynamoDB**
   - AWS Console → DynamoDB → `threadbrief-<env>` table → items, to check
     briefs/rate-limit counters are actually being written.
5) **DNS**
   - Route53 → Hosted zone → an A record (alias) for `threadbrief.com` (or
     `staging.threadbrief.com`) pointing at the CloudFront distribution.
6) **SSL**
   - ACM (us-east-1) → certificate status should be **Issued**.

## If Terraform partially creates resources
Terraform tracks what it created. Re-run `sh bin/tools.sh prod up` to finish. If
that fails, use the "delete and re-add" path: `sh bin/tools.sh prod down` then
`sh bin/tools.sh prod up`. This is more bullet-proof but requires delete
permissions (notably `iam:DeletePolicyVersion`) so Terraform can fully remove and
recreate IAM policies and related resources.

## Teardown behavior
- `prod down` keeps the Route53 hosted zone intact (removed from
  Terraform state) to avoid breaking DNS.
- If you ever need to delete the hosted zone, do it manually after removing the
  `prevent_destroy` guard.

## Notes
- The Lambda image is pushed to ECR under the `lambda-latest` tag (the same
  ECR repo used to exist for ECS images — now solely for the Lambda image).
- `GEMINI_API_KEY`, `YTDLP_COOKIES`, and `YTDLP_PROXY` are passed to the
  Lambda function as plain environment variables (via Terraform), the same
  way ECS ultimately exposed them to its containers — just provisioned
  directly instead of via Secrets Manager, since Lambda has no equivalent
  ECS-agent-style secret injection.

## Optional: YouTube cookies (for bot checks)
If YouTube blocks downloads, add cookies:
1) Log into YouTube in your browser.
2) Export cookies to a `cookies.txt` file (browser extension).
3) Paste the contents into `infra/terraform/envs/prod.local.tfvars`:
   ```
   ytdlp_cookies = """PASTE_COOKIES_TXT_HERE"""
   ```
4) Re-apply and deploy:
   ```bash
   sh bin/tools.sh prod deploy
   ```

## Cost
At low/demo traffic, this stack runs close to $0/month: S3 storage of a few
MB, CloudFront on the cheapest price class, Lambda and DynamoDB both on
pay-per-request billing with generous free tiers, and no always-on compute
(no ECS Fargate task, no ALB) billing by the hour regardless of traffic.

## Product reminders
- Add an ETA/progress bar during brief generation (smooth % based on stages).
