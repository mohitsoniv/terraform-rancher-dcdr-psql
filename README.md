# Hybrid DC/DR PostgreSQL on Rancher RKE2

A production-style **Disaster Recovery (DR)** setup for PostgreSQL running on two
Rancher-managed **RKE2** Kubernetes clusters. It uses the **Crunchy Data PostgreSQL
Operator (PGO v5)**, with **pgBackRest** WAL archiving to **Amazon S3** and
**cross-region bucket replication** between two AWS regions.

Data written on the **DC (primary)** cluster reaches the **DR** cluster entirely
through **S3 WAL archives** — the standby instances never stream directly from the
primary. This mirrors how a real cross-datacenter DR topology behaves: if the
primary site is lost, the DR site can be promoted and keep serving traffic.

---

## Table of Contents

- [Architecture](#architecture)
- [How Data Flows](#how-data-flows)
- [Repository Layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
  - [1. Provision Infrastructure](#1-provision-infrastructure)
  - [2. Register Clusters in Rancher](#2-register-clusters-in-rancher)
  - [3. Install the PostgreSQL Operator](#3-install-the-postgresql-operator)
  - [4. Configure S3 Credentials](#4-configure-s3-credentials)
  - [5. Deploy PostgreSQL](#5-deploy-postgresql)
- [Verifying the Setup](#verifying-the-setup)
- [Live Sync Test](#live-sync-test)
- [Failover (DR Drill)](#failover-dr-drill)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [License](#license)

---

## Architecture

```
                              Application write
                                     |
                                     v
        DC cluster (us-east-1)                  DR cluster (us-east-1, Spot)
        ----------------------                  ----------------------------
          Primary  (leader, TL=1)                  Standby Leader (TL=1)
             |  stream                                  |  stream
             v                                          v
          Replica                                    Replica  (promotes on DC failure)

          Standby                                    Standby
          (ns: pg-dc-standby)                        (ns: pg-dr-standby)
             ^  WAL replay                               ^  WAL replay
             |                                           |
        +----------------------+   cross-region   +----------------------+
        |  S3 DC bucket        |  -------------->  |  S3 DR bucket        |
        |  us-east-1           |   replication     |  us-west-2           |
        |  keen-...-dc-2026    |                   |  keen-...-dr-2026    |
        |  dc/pg-dc/           |                   |  dc/pg-dc/           |
        +----------------------+                   +----------------------+
```

A rendered topology diagram is included as
`dc_dr_four_cluster_clean_flow_topology.svg` and `dc_dr_complete_live_sync.png`.

**Key points**

- The primary and each standby are **separate PostgresCluster CRs in separate
  namespaces**.
- Standbys run in **archive recovery** and replay WAL from S3 — they do **not**
  stream from the primary (`pg_stat_wal_receiver` returns 0 rows).
- Streaming replication exists **only** between a leader and its replica inside
  the same cluster.
- All instances stay on the **same timeline (TL=1)**.

---

## How Data Flows

1. The application writes to the **DC primary**, which streams to its replica and
   archives WAL to the **DC S3 bucket** (`us-east-1`).
2. The **DC standby** (own namespace) replays that WAL straight from the DC bucket.
3. **Cross-region replication** copies the DC bucket into the **DR bucket**
   (`us-west-2`).
4. The **DR standby leader** replays WAL from the DR bucket and streams to its
   replica.
5. A **dedicated DR standby** (own namespace) also replays from the DR bucket.

The result: a single write on the DC primary lands on **all four PostgreSQL
instances** — DC standby, DR cluster, and the dedicated DR standby — with no
direct connection between sites.

---

## Repository Layout

```
.
├── compute.tf                  EC2 instances for Rancher server + RKE2 nodes
├── network.tf                  VPC, subnets, security groups
├── s3.tf                       S3 buckets + cross-region replication
├── iam.tf                      IAM user/policy for pgBackRest
├── providers.tf                Terraform/AWS provider config
├── variables.tf                Input variables
├── outputs.tf                  Useful outputs (IPs, bucket names)
├── terraform.tfvars.example    Copy to terraform.tfvars and fill in your values
├── user_data/
│   ├── rancher.sh              Rancher server bootstrap script
│   └── node.sh                 RKE2 node bootstrap script
└── manifests/
    ├── pg-dc-pgo-final.yaml     DC PostgresCluster (primary + replica)
    ├── pg-dc-standby-ns.yaml    DC standby (separate namespace, S3 WAL replay)
    ├── pg-dr-live.yaml          DR standby cluster (replays DC WAL from S3)
    └── pg-dr-standby-live.yaml  DR dedicated standby (separate namespace)
```

---

## Prerequisites

- An **AWS account** with permission to create VPC, EC2, S3, and IAM resources.
- **Terraform** >= 1.5
- **kubectl**
- **Crunchy Data PGO v5** installed on both clusters.
- Ubuntu **24.04** AMIs for the nodes (RKE2 is not compatible with 26.04).
- Two S3 buckets in **different regions** with **cross-region replication**
  configured (the Terraform in this repo creates them).

---

## Setup

### 1. Provision Infrastructure

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your own AWS values
terraform init
terraform apply
```

This creates the Rancher server, the DC and DR RKE2 nodes, both S3 buckets with
cross-region replication, and the IAM user/policy for pgBackRest.

> **Note on quotas:** the DR nodes use Spot instances in the example to stay
> within default vCPU limits. If you have an On-Demand vCPU quota increase, you
> can switch them to On-Demand in `compute.tf`.

### 2. Register Clusters in Rancher

1. Open the Rancher UI (the server's public IP is in `terraform output`).
2. Create two **Custom / RKE2** clusters: `dc-cluster` and `dr-cluster`.
3. Run the generated node-registration command on each node (with the
   `--etcd --controlplane --worker` roles).
4. Download the kubeconfig for each cluster.

### 3. Install the PostgreSQL Operator

Install Crunchy Data PGO v5 on both clusters (namespace `postgres-operator`):

```bash
git clone https://github.com/CrunchyData/postgres-operator.git
cd postgres-operator
kubectl apply --server-side -k config/namespace
kubectl apply --server-side -k config/default
```

Make sure a default `StorageClass` exists on both clusters (e.g.
`local-path-provisioner`).

### 4. Configure S3 Credentials

Every manifest references S3 credentials using placeholders:

- `<YOUR_S3_ACCESS_KEY>`
- `<YOUR_S3_SECRET_KEY>`

Replace these with your own pgBackRest IAM credentials before applying.

For the **standby namespaces**, the operator also expects a Kubernetes secret:

```bash
# DC standby
kubectl create namespace pg-dc-standby
kubectl -n pg-dc-standby create secret generic s3-creds \
  --from-literal=aws-s3-key=<YOUR_S3_ACCESS_KEY> \
  --from-literal=aws-s3-key-secret=<YOUR_S3_SECRET_KEY>

# DR standby cluster
kubectl create namespace pg-dr
kubectl -n pg-dr create secret generic s3-creds \
  --from-literal=aws-s3-key=<YOUR_S3_ACCESS_KEY> \
  --from-literal=aws-s3-key-secret=<YOUR_S3_SECRET_KEY>

# DR dedicated standby
kubectl create namespace pg-dr-standby
kubectl -n pg-dr-standby create secret generic s3-creds \
  --from-literal=aws-s3-key=<YOUR_S3_ACCESS_KEY> \
  --from-literal=aws-s3-key-secret=<YOUR_S3_SECRET_KEY>
```

### 5. Deploy PostgreSQL

On the **DC cluster**:

```bash
kubectl apply -f manifests/pg-dc-pgo-final.yaml    # primary + replica
kubectl apply -f manifests/pg-dc-standby-ns.yaml   # DC standby
```

On the **DR cluster**:

```bash
kubectl apply -f manifests/pg-dr-live.yaml          # DR standby cluster
kubectl apply -f manifests/pg-dr-standby-live.yaml  # DR dedicated standby
```

---

## Verifying the Setup

Check cluster roles and state with Patroni:

```bash
kubectl -n pg-dc exec -it <dc-primary-pod> -c database -- patronictl list
```

Expected: a `Leader (running, TL=1)`, a `Replica (streaming)`, and standbys
showing `Standby Leader / in archive recovery (TL=1)`.

Confirm a standby is **replaying from S3, not streaming**:

```bash
# Should return: t
kubectl -n pg-dr exec -it <dr-pod> -c database -- \
  psql -c "SELECT pg_is_in_recovery();"

# Should return: 0 rows (no WAL receiver = not streaming)
kubectl -n pg-dr exec -it <dr-pod> -c database -- \
  psql -c "SELECT * FROM pg_stat_wal_receiver;"
```

Check the pgBackRest repository:

```bash
kubectl -n pg-dr exec -it <dr-pod> -c pgbackrest -- pgbackrest --stanza=db info
```

---

## Live Sync Test

On the **DC primary**:

```sql
INSERT INTO test_dr (message) VALUES ('live sync test');
SELECT pg_switch_wal();
```

After cross-region replication completes (typically a few minutes), check the
**DR side**:

```sql
SELECT * FROM test_dr ORDER BY id DESC LIMIT 5;
```

The inserted row should appear on the DC standby, the DR cluster, and the
dedicated DR standby — proving the full path:

```
DC primary -> S3 DC bucket -> cross-region replication -> S3 DR bucket -> DR replay
```

---

## Failover (DR Drill)

When the DC site is lost, promote the DR standby to a full primary:

1. Confirm DC is truly down (avoid split-brain).
2. Disable standby mode on the DR cluster (`spec.standby.enabled: false`) and
   re-apply, so PGO promotes it to a writable primary.
3. Point the application at the DR endpoint.
4. After DC is restored, rebuild it as a standby of the new primary, then fail
   back when ready.

> Always test failover in a non-production environment first and verify writes
> succeed on the promoted cluster before redirecting traffic.

---

## Troubleshooting

**Standby pod crashes with `target timeline N forked from backup timeline ...`**
A stale `0000000N.history` file or higher-timeline WAL/backups exist in S3 from a
previous promotion. Remove the conflicting timeline artifacts from **both**
buckets so standbys restore cleanly on the correct timeline.

**Standby crashes with `unable to restore to path ... because it contains files`**
Don't include `spec.dataSource` once the data volume already has data. Remove it
and let PGO restore into a fresh volume; or delete the namespace (and its PVCs)
and re-apply for a clean restore.

**Cross-region copy not appearing in the DR bucket**
Verify the replication rule is enabled and the IAM role has permission. Compare
the latest objects in each bucket:

```bash
aws s3 ls s3://<dc-bucket>/dc/pg-dc/archive/ --recursive | tail
aws s3 ls s3://<dr-bucket>/dc/pg-dc/archive/ --recursive | tail
```

---

## Security Notes

- **Never commit** real credentials. All manifests in this repo use
  placeholders (`<YOUR_S3_ACCESS_KEY>`, `<YOUR_S3_SECRET_KEY>`).
- `.gitignore` excludes Terraform state, `terraform.tfvars`, `*.pem` keys, and
  kubeconfig files — keep it that way.
- Terraform state and kubeconfig files contain secrets and tokens; store them
  securely (e.g. an encrypted remote backend), not in version control.
- Rotate any credential that has ever been exposed.

---

## License

Released under the MIT License. See `LICENSE` for details.
