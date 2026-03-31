# :rocket: Azure Infra + n8n - Complete Guide

> :white_check_mark: This README is the full handover guide for the project.
> It explains architecture, setup, each YAML file, deployment flow, and troubleshooting.

---

## :sparkles: What You Get

This folder contains a full Azure platform to deploy n8n with:
- private network infrastructure
- managed PostgreSQL database
- Blob storage mounted on the VM
- Caddy reverse proxy
- GitHub Actions pipelines for end-to-end deployment

---

## :dart: 1) Project Overview

The project is split into 3 blocks:

1. **Azure infrastructure (Bicep)**
- network (VNet + subnets)
- private DNS
- private Key Vault
- application VM
- Blob storage + private endpoint
- private PostgreSQL Flexible Server

2. **Application deployment (n8n + Caddy)**
- `Azure/conf/compose.yml` defines containers
- `Azure/conf/n8n.sh` prepares the VM, mounts Blob, syncs `Caddyfile`, starts Docker Compose

3. **CI/CD orchestration**
- 4 GitHub Actions workflows in `.github/workflows`
- logical order: infra -> private runner -> project resources -> n8n app

---

## :file_folder: 2) Repository Structure

```text
.github/workflows/
  azure-infra.yml
  azure-gh-runner.yml
  azure-project.yml
  azure-n8n.yml

Azure/
  conf/
    compose.yml
    n8n.sh
    copy-compose-to-vm.sh
  resources/
    rg.bicep
    nw.bicep
    vnet.bicep
    privatedns.bicep
    nsg.bicep
    pip.bicep
    nic.bicep
    vm.bicep
    stvm.bicep
    psql-db.bicep
    kv.bicep
```

---

## :blue_book: 3) Explanation of Each YAML File

### :building_construction: `.github/workflows/azure-infra.yml`
**Purpose:** deploy base infrastructure.

**Triggers:**
- `push` to `main` (when `Azure/**` or workflow files change)
- `pull_request` (same path filter)
- `workflow_dispatch` (manual)

**Jobs:**
- `build`: Bicep lint + ARM JSON compilation + artifacts
- `checkov_scan`: Checkov security scan on compiled templates
- `rg`: creates shared resource groups (`rg-common`, `rg-network`, `rg-privatedns`, `rg-database`)
- `deploy`: deploys `nw`, `vnet`, `privatedns`, `kv`

### :jigsaw: `.github/workflows/azure-gh-runner.yml`
**Purpose:** deploy a self-hosted runner inside the private VNet so it can reach private Key Vault.

**Triggers:**
- manual
- after `Azure Base Infrastructure Deployment` completes

**Main actions:**
- creates runner RG + NSG/PIP/NIC + runner VM
- assigns Key Vault roles to the runner VM managed identity
- installs/registers GitHub runner service (labels: `self-hosted,linux,azure,kv-private`)
- validates Key Vault private-link access from the runner VM

### :lock: `.github/workflows/azure-project.yml`
**Purpose:** deploy project resources (app VM, storage, DB, etc.) using the private runner.

**Triggers:**
- manual
- after `Azure Self-Hosted Runner for Key Vault Private Link` completes

**Key points:**
- `runs-on: [self-hosted, linux, azure, kv-private]`
- generates/reuses SSH key pair stored in Key Vault
- deploys:
  - `psql-db.bicep`
  - `nsg.bicep`
  - `pip.bicep`
  - `nic.bicep`
  - `vm.bicep`
  - `stvm.bicep`

### :robot: `.github/workflows/azure-n8n.yml`
**Purpose:** deploy the n8n application on the VM.

**Triggers:**
- manual
- after `Azure Project Deployment` completes

**Main actions:**
- gets Storage Account key
- generates runtime `.env` (DB, n8n, blob, domain, etc.)
- copies `compose.yml` and `.env` to `/home/azureuser/n8n` via `az vm run-command invoke`
- runs `Azure/conf/n8n.sh` on the VM
- uploads deployment logs/artifacts (with redacted `.env`)

### :whale: `Azure/conf/compose.yml`
**Purpose:** define Docker services.

**Services:**
- `caddy`
  - HTTP/HTTPS reverse proxy
  - mounts `./conf` to `/etc/caddy`
  - exposes ports `80`, `443`, `443/udp`
- `n8n`
  - image `n8nio/n8n:latest`
  - loads `.env`
  - configures public HTTPS URL
  - uses external PostgreSQL
  - persists data in `n8n_data` volume

---

## :bricks: 4) Quick Explanation of Bicep Files

- `rg.bicep`: creates a resource group (subscription scope)
- `nw.bicep`: creates Network Watcher
- `vnet.bicep`: creates VNet + subnets (app, psql, runner, etc.)
- `privatedns.bicep`: creates private DNS zones + VNet links
- `nsg.bicep`: SSH/HTTP/HTTPS rules and outbound 445 rule
- `pip.bicep`: static public IP + DNS label
- `nic.bicep`: app VM NIC + NSG/subnet/PIP attachment
- `vm.bicep`: Debian 13 VM (system-assigned managed identity)
- `stvm.bicep`: Storage Account + blob container + blob private endpoint
- `psql-db.bicep`: private PostgreSQL Flexible Server + `psql_<project>` database
- `kv.bicep`: private Key Vault + private endpoint + DNS zone group

---

## :white_check_mark: 5) Prerequisites

### Azure / GitHub
- Azure subscription
- GitHub repository with Actions enabled
- Azure Service Principal for GitHub Actions
- permissions to deploy infra + create RBAC assignments

### Local tools (for manual testing)
- `git`
- `az` (Azure CLI)
- Bicep CLI (`az bicep install`)

### Required GitHub Secrets
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_TENANT_ID`
- `AZURE_DB_PASSWORD`
- `AZURE_GITHUB_OBJECT_ID`
- `N8N_ENCRYPTION_KEY`
- `GH_RUNNER_PAT`

### Required GitHub Variables
- `AZURE_ENV` (example: `dev`)
- `PROJECT_NAME` (example: `azureinfra`)
- `PROJECT_VERSION` (example: `01`)
- `LOCATION` (example: `canadacentral`)

---

## :package: 6) How to Copy the Project

### Option A - clone this repository
```bash
git clone <REPO_URL>
cd <REPO>
```

### Option B - reuse in a new repository
Copy at minimum:
- `Azure/`
- `.github/workflows/`

Then:
1. create a new GitHub repository
2. push these folders
3. configure all required GitHub secrets and variables
4. verify naming values (`PROJECT_NAME`, `AZURE_ENV`, `PROJECT_VERSION`) match your Azure naming convention

---

## :rocket: 7) Full Setup (Step-by-Step)

1. Configure GitHub secrets and variables (section 5).
2. Run workflow `Azure Base Infrastructure Deployment`.
3. Run/verify `Azure Self-Hosted Runner for Key Vault Private Link`.
4. Confirm runner is visible in the repo with labels:
   - `self-hosted`
   - `linux`
   - `azure`
   - `kv-private`
5. Run `Azure Project Deployment`.
6. Run `Azure n8n Deployment`.

Automatic chaining via `workflow_run` is already configured, but the first run is easier to validate step by step when done manually.

---

## :gear: 8) What `Azure/conf/n8n.sh` Does on the VM

The script:
1. updates system packages
2. installs Docker if missing
3. adds `azureuser` to docker group
4. preloads `.env` variables
5. installs `blobfuse2` with fallback strategy (apt -> Microsoft repo -> GitHub package)
6. applies `libfuse3` runtime compatibility fix if needed
7. mounts Blob container at `/media/<container>`
8. syncs or creates `Caddyfile` in Blob storage
9. validates `docker compose config`
10. runs `docker compose up -d`

---

## :test_tube: 9) Runtime `.env` Variables for n8n

`azure-n8n.yml` dynamically generates:
- storage: `AZURE_STORAGE_ACCOUNT`, `AZURE_STORAGE_ACCESS_KEY`, `AZURE_BLOB_CONTAINER`
- legacy compatibility: `R_STORAGE_ACCOUNT_NAME`, `R_STORAGE_PASSWORD`, `R_STORAGE_CONTAINER`
- n8n/caddy: `N8N_SUBDOMAIN`, `DOMAIN`, `ENCRYPTION_KEY`, `TZ`
- DB: `DB_NAME`, `DB_PORT`, `DB_HOST`, `DB_USER`, `DB_SSL`, `DB_SSL_REJECT_UNAUTHORIZED`, `DB_PASSWORD`

---

## :mag: 10) Post-Deployment Validation

Connect to the app VM and run:
```bash
sudo tail -n 200 /var/log/n8n-bootstrap.log
sudo docker ps
sudo mountpoint -q /media/share-<project>-<env>-<version> && echo mounted || echo not-mounted
sudo ls -la /media/share-<project>-<env>-<version>/caddy
sudo ls -la /home/azureuser/n8n/conf
```

Expected result:
- `n8n` and `caddy` containers are running
- blob mount is active
- `Caddyfile` exists in blob storage and in local `conf/`

---

## :hammer_and_wrench: 11) Quick Troubleshooting

- `blobfuse2: No such file or directory`
  - check bootstrap log, script already tries 3 installation methods

- blob mount fails
  - verify storage key, container name, private DNS resolution

- pipeline successful but app is not running
  - check `copy-compose.log` and `n8n-bootstrap.log` artifacts in GitHub Actions

- Key Vault access denied from runner
  - verify runner workflow assigned Key Vault roles to the VM managed identity

---

## :memo: 12) Important Notes

- `azure-project.yml` depends on a private self-hosted runner (strict labels).
- resource names are derived from `PROJECT_NAME + AZURE_ENV + PROJECT_VERSION`.
- this project uses private endpoints, so private DNS and routing must be correct.
