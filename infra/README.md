# AWS Deploy (ECS Fargate)

This folder contains Terraform for staging/prod in `ap-southeast-2`.

## Prereqs
- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Docker

## 1) Provision staging
```bash
sh bin/tools.sh stage up
```

Terraform outputs Route53 name servers. Update your GoDaddy domain to use them.

## GoDaddy DNS update
1) Open your domain in GoDaddy → DNS settings.
2) Change nameservers to the Route53 values from `terraform output route53_name_servers`.
3) Wait for DNS propagation (usually minutes, sometimes longer).

## 2) Wait for ACM validation
ACM uses DNS validation. Once Route53 is authoritative, cert validation completes.

## 3) Deploy containers
```bash
sh bin/tools.sh stage deploy
```

## 4) Destroy
```bash
sh bin/tools.sh stage down
```

## Notes
- Images are pushed to ECR with tag `latest` by default (override with `TAG=...`).
- `GEMINI_API_KEY` is stored in Secrets Manager if provided via tfvars.
