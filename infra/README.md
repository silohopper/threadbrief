# AWS Deploy (ECS Fargate)

This folder contains Terraform for staging/prod in `ap-southeast-2`.

If you're new to AWS, follow the steps below in order. Each step explains what
it does and why.

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
Terraform workspaces (`stage`, `prod`) so resources don’t overwrite each other.

From now on, use `sh bin/tools.sh stage ...` and `sh bin/tools.sh prod ...` only.

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
        "ec2:*",
        "ecr:*",
        "ecs:*",
        "elasticloadbalancing:*",
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
        "logs:*",
        "route53:*",
        "secretsmanager:*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```
If you want “delete and re-add” to be the default recovery path, make sure this
policy includes `iam:DeletePolicyVersion` so Terraform can fully remove and
recreate IAM policies during rebuilds.

## Step 5) Decide your domains
For staging we will use:
- Web: `staging.threadbrief.com`
- API: `api.staging.threadbrief.com`

These are already set in `infra/terraform/envs/stage.tfvars`.

## Step 6) Provision staging infrastructure
This creates ECS, ECR, ALB (load balancer), Route53 (DNS), and ACM (SSL certs).
```bash
sh bin/tools.sh stage up
```

If Terraform fails with “already exists” errors (state drift), run:
```bash
sh bin/tools.sh stage resync
```
Then re-run `sh bin/tools.sh stage up`.

## Step 7) Point GoDaddy DNS to AWS (one time)
Terraform creates a Route53 hosted zone and gives you 4 name servers. You need
to point your domain to those name servers.

## GoDaddy DNS update
1) Run this from the repo root to get the Route53 nameservers:
   ```bash
   sh bin/tools.sh stage dns
   ```
2) Open your domain in GoDaddy → DNS settings.
3) Replace the existing nameservers with the Route53 values from the command above.
3) Wait for DNS propagation (usually minutes, sometimes longer).

You only do this once. Stage and prod share the same hosted zone for
`threadbrief.com`, so there is only one set of name servers.

Terraform will keep waiting at the ACM validation step until DNS is updated and
propagated.

If your terminal looks like it’s “stuck” waiting for ACM validation, open a
second terminal and run:
```bash
sh bin/tools.sh stage dns
```
Use the output to update GoDaddy nameservers, then wait for propagation so the
original `stage up` can finish.

You’ll typically see logs like:
```
aws_acm_certificate_validation.this: Still creating... [8m10s elapsed]
aws_acm_certificate_validation.this: Still creating... [8m20s elapsed]
aws_acm_certificate_validation.this: Still creating... [8m30s elapsed]
aws_acm_certificate_validation.this: Still creating... [8m40s elapsed]
```

If you cannot change nameservers (staying on GoDaddy DNS), you must add the ACM
validation CNAMEs manually. This command will create the ACM certificate (if
needed) and print the CNAMEs to add in GoDaddy:
```bash
sh bin/tools.sh stage cert
```
Add each record to GoDaddy DNS exactly as shown (Name/Type/Value).

After adding the CNAMEs in GoDaddy, re-run:
```bash
sh bin/tools.sh stage up
```

## Step 8) Wait for SSL to validate (ACM)
ACM is AWS Certificate Manager. It issues your SSL certs for HTTPS.
Once GoDaddy is pointing at Route53, ACM will validate automatically.

How to check ACM:
1) AWS Console → **ACM** → Certificates.
2) Open the cert and look for **Status: Issued**.
3) Under **Domains**, you should see **two entries**:
   - one for `staging.threadbrief.com`
   - one for `api.staging.threadbrief.com`
4) Each domain should show **Success** (validation complete).
If one is missing, DNS is not fully propagated or the record is missing.

## Step 9) Deploy containers
This builds Docker images, pushes them to ECR, then restarts ECS services.
```bash
sh bin/tools.sh stage deploy
```

### Optional: yt-dlp proxy (recommended for AWS)
YouTube often blocks AWS datacenter IPs even with cookies. A residential proxy
fixes this. If you have a proxy URL:
1) Save it to `env/<env>/proxy.txt` (one line, e.g. `http://user:pass@host:port` or
   `host:port:username:password`). We are currently using Decodo (Smartproxy).
2) Run `sh bin/tools.sh stage deploy`.

The deploy script will read `env/<env>/proxy.txt` (or `env/dev/proxy.txt`) and
store it as a `YTDLP_PROXY` secret for the API task. Do **not** commit this file.

## Step 10) Test
- Web: https://staging.threadbrief.com
- API health: https://api.staging.threadbrief.com/health

## Step 11) Provision prod (after staging works)
```bash
sh bin/tools.sh prod up
sh bin/tools.sh prod deploy
```

## Step 12) Test prod
- Web: https://threadbrief.com
- API health: https://api.threadbrief.com/health

## Step 13) Destroy (when done)
```bash
sh bin/tools.sh stage down
```

## Debug checklist (when something goes wrong)
1) **Terraform state**
   - Re-run: `sh bin/tools.sh stage up` (auto-resync on failure).
   - If it still fails or resources are inconsistent, delete and re-add:
     `sh bin/tools.sh stage down` then `sh bin/tools.sh stage up`.
2) **ECS service events**
   - AWS Console → ECS → Cluster → Service → Events.
3) **Container logs**
   - CloudWatch Logs → `/ecs/threadbrief/stage/api` and `/ecs/threadbrief/stage/web`.
4) **Load balancer health**
   - EC2 → Target Groups → Health.
5) **DNS**
   - Route53 → Hosted zone → records exist for `staging.threadbrief.com` + `api.staging.threadbrief.com`.
6) **SSL**
   - ACM → certificate status should be **Issued**.

## If Terraform partially creates resources
Terraform tracks what it created. Re-run `sh bin/tools.sh stage up` to finish. If
that fails, use the “delete and re-add” path: `sh bin/tools.sh stage down` then
`sh bin/tools.sh stage up`. This is more bullet-proof but requires delete
permissions (notably `iam:DeletePolicyVersion`) so Terraform can remove and
recreate IAM policies and related resources.

## Notes
- Images are pushed to ECR with tag `latest` by default (override with `TAG=...`).
- `GEMINI_API_KEY` is stored in Secrets Manager if provided via tfvars.

## Optional: YouTube cookies (for bot checks)
If YouTube blocks downloads in staging, add cookies:
1) Log into YouTube in your browser.
2) Export cookies to a `cookies.txt` file (browser extension).
3) Paste the contents into `infra/terraform/envs/stage.local.tfvars`:
   ```
   ytdlp_cookies = """PASTE_COOKIES_TXT_HERE"""
   ```
4) Re-apply and deploy:
   ```bash
   sh bin/tools.sh stage deploy
   ```

## Cost control ideas
- **Scale ECS to zero** for staging when idle (manual or scheduled).
- Use smaller task sizes for stage if performance allows.
- Serve the web UI from S3 + CloudFront (static) instead of Fargate.
- Keep ACM (free) and Route53 (low cost) as-is.
