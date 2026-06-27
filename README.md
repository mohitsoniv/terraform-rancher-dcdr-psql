# Rancher + DC cluster (AWS) — Terraform

Ye Terraform **DC side poora AWS pe** bana deta hai, purane instances ko bina chhede:

- Rancher server (Ubuntu 24.04, t3.large, 30G disk) — **Rancher auto-install** via user_data
- 3 DC nodes (24.04, 30G) — RKE2 prereqs ready (swap, sysctl, **nm-cloud-setup disabled** = wahi 203/EXEC fix)
- Security group with all RKE2/Rancher ports (no more "SG bhool gaye")
- 2 S3 buckets (DC region + DR region) + versioning + **disjoint-prefix two-way replication** (`dc/`→DR, `dr/`→DC)
- IAM user + keys for pgBackRest

> DR site (local multipass VMs) = **Phase 2**, baad me Ansible se. Ye sirf Phase-1 (AWS/DC).

---

## 1. Prerequisites
- Terraform >= 1.5, AWS CLI configured (`aws configure`) with admin-ish creds
- Existing EC2 key pair (default `rancher`) — `.pem` apne paas ho

## 2. Configure
```bash
cd terraform-rancher-dcdr
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars edit karo: my_ip_cidr, dc_bucket_name, dr_bucket_name (globally unique)
```

## 3. Apply
```bash
terraform init
terraform plan
terraform apply     # yes
```
Output me milega: `rancher_url`, `dc_node_public_ips`, S3 bucket names, pgBackRest key id.
Secret nikaalne ke liye:
```bash
terraform output -raw pgbackrest_secret_access_key
```

## 4. Rancher UI kholo (2-4 min wait, auto-install ho raha)
```bash
# bootstrap password (Rancher server pe)
ssh -i rancher.pem ubuntu@<rancher_ip> "sudo cat /root/rancher-bootstrap-password.txt"
```
Browser → `https://<rancher_ip>` → password daalo → naya admin password → Server URL confirm.

## 5. Cluster banao
- Cluster Management → **Create → Custom**
- Name: `dc-cluster` (lowercase!)
- Create → **Registration** tab → roles **etcd + Control Plane + Worker** tick
- **"Insecure" checkbox tick** (self-signed cert) → command copy

## 6. 3 DC nodes pe register karo
`terraform output dc_node_public_ips` se IPs lo. Har node pe:
```bash
ssh -i rancher.pem ubuntu@<dc_node_ip>
sudo <PASTE the insecure registration command, single line>
```
Prereqs pehle se ho chuke (user_data ne kiya), to RKE2 ab clean install hoga — 203/EXEC nahi aayega.

5-10 min me Rancher me cluster **Active** → 3 nodes **Running**.

---

## Notes
- Token Rancher chalu hone ke **baad** banta hai, isliye step 5-6 manual (ek command). Full automation chahiye to `rancher2` provider se ho sakta hai — bolना to add kar dunga.
- Cleanup: `terraform destroy` (sirf ye naye resources hatega, purane instances safe).
- pgBackRest S3 config (Phase 2 Ansible) ke liye access key/secret + bucket names outputs me hain.
