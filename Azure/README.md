# 🚀 Azure Infra + n8n Deployment Guide

> ✅ This README is the full handover guide for this project.  
> It explains architecture, setup, variables, workflow behavior, and troubleshooting so a new teammate can run and maintain it confidently.

---

## 📚 Table of Contents
1. [Project Overview](#-project-overview)
2. [Architecture](#-architecture)
3. [Repository Structure](#-repository-structure)
4. [Prerequisites](#-prerequisites)
5. [GitHub Secrets and Variables](#-github-secrets-and-variables)
6. [Environment Variables (.env)](#-environment-variables-env)
7. [Deployment Flow](#-deployment-flow)
8. [VM Bootstrap Internals](#-vm-bootstrap-internals)
9. [Blob Mount + Caddyfile Sync Logic](#-blob-mount--caddyfile-sync-logic)
10. [How to Deploy](#-how-to-deploy)
11. [Validation Checklist](#-validation-checklist)
12. [Troubleshooting](#-troubleshooting)
13. [Security Notes](#-security-notes)
14. [Operational Runbook](#-operational-runbook)
15. [Known Behaviors and Notes](#-known-behaviors-and-notes)

---

## 🎯 Project Overview
This project deploys and runs:

- 🧠 `n8n` in Docker
- 🌐 `Caddy` as reverse proxy
- 🗄️ Azure PostgreSQL Flexible Server (private networking)
- ☁️ Azure Blob container mounted on VM using `blobfuse2`
- 📄 `Caddyfile` synchronized from Blob storage into local compose `conf`

Main runtime script:
- `Azure/conf/n8n.sh`

Main CI/CD workflow:
- `.github/workflows/azure-project.yml`

---

## 🧱 Architecture

```text
GitHub Actions
  -> Azure login
  -> Generate compose + .env
  -> Copy files to VM (/home/azureuser/n8n)
  -> Run bootstrap script (n8n.sh)

VM (Debian 13)
  -> Install/check Docker
  -> Install/check blobfuse2
  -> Apply Debian libfuse compatibility if required
  -> Mount blob container at /media/<container>
  -> Sync Caddyfile from storage
  -> docker compose up -d

Azure resources
  -> VNet + subnets + private DNS
  -> VM + NIC + PIP + NSG
  -> Storage account + blob container + private endpoint
  -> PostgreSQL Flexible Server
  -> Key Vault
```

---

## 🗂️ Repository Structure

### `Azure/conf`
- `compose.yml` -> Docker Compose stack (`n8n` + `caddy`)
- `n8n.sh` -> Bootstrap script executed remotely on VM
- `copy-compose-to-vm.sh` -> helper copy script

### `Azure/resources`
- `rg.bicep` -> resource group creation (subscription scope)
- `nw.bicep` -> network watcher
- `vnet.bicep` -> VNet and subnets
- `privatedns.bicep` -> private DNS zones + links
- `nsg.bicep` -> network security rules
- `pip.bicep` -> public IP + DNS label
- `nic.bicep` -> VM NIC
- `vm.bicep` -> Debian 13 VM with system-assigned identity
- `stvm.bicep` -> storage account + blob container + private endpoint
- `psql-db.bicep` -> PostgreSQL flexible server
- `kv.bicep` -> Key Vault + private endpoint

---

## ✅ Prerequisites

### Local tools
- Azure CLI
- Bicep CLI
- Git + GitHub access

### Install Azure CLI and Bicep (Windows)
```powershell
winget install --exact --id Microsoft.AzureCLI
az bicep install
```

### Recommended
- VS Code Bicep extension

---

## 🔐 GitHub Secrets and Variables

## GitHub Secrets
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_TENANT_ID`
- `AZURE_DB_PASSWORD`

## GitHub Variables
- `AZURE_ENV` (example: `dev`)
- `PROJECT_NAME` (example: `azureinfra`)
- `PROJECT_VERSION` (example: `01`)
- `LOCATION` (example: `canadacentral`)

---

## 🧪 Environment Variables (.env)
Workflow generates `.env` and copies it to:
- `/home/azureuser/n8n/.env`

### Storage / Blob variables
- `AZURE_STORAGE_ACCOUNT`
- `AZURE_STORAGE_ACCESS_KEY`
- `AZURE_BLOB_CONTAINER`

Legacy-compatible fallback variables also supported in script:
- `R_STORAGE_ACCOUNT_NAME`
- `R_STORAGE_PASSWORD`
- `R_STORAGE_CONTAINER`

### n8n / caddy / DB variables
- `N8N_SUBDOMAIN`
- `DOMAIN`
- `ENCRYPTION_KEY`
- `TZ`
- `DB_NAME`
- `DB_PORT`
- `DB_HOST`
- `DB_USER`
- `DB_SSL`
- `DB_SSL_REJECT_UNAUTHORIZED`
- `DB_PASSWORD`

### Optional override variables supported by script
- `LOG_FILE` (default: `/var/log/n8n-bootstrap.log`)
- `BLOBFUSE2_VERSION` (default fallback: `2.5.3`)
- `AZURE_MOUNT_POINT` (default: `/media/<container>`)
- `AZURE_BLOBFUSE_TMP_PATH` (default: `/mnt/blobfuse2tmp/<container>`)
- `AZURE_CADDY_DIR_PATH` (default: `<mount>/caddy`)
- `AZURE_CADDYFILE_PATH` (default: `<caddy_dir>/Caddyfile`)
- `COMPOSE_DIR` (override compose path)

---

## ⚙️ Deployment Flow

The `azure-project.yml` workflow does this:

1. 🔑 Login to Azure.
2. 🧾 Build runtime `.env` (including storage key and container name).
3. 📦 Copy `compose.yml` and `.env` to VM path `/home/azureuser/n8n`.
4. 🖥️ Execute `Azure/conf/n8n.sh` remotely via `az vm run-command invoke`.

---

## 🧠 VM Bootstrap Internals

`n8n.sh` performs:

1. apt update/upgrade
2. Docker installation check and startup
3. Ensure `azureuser` is in docker group
4. Preload compose `.env`
5. Install `blobfuse2` with fallback strategy:
   - apt direct
   - Microsoft apt repo package
   - GitHub release `.deb`
6. Debian compatibility fix for `libfuse3.so.3` if needed
7. Mount blob container
8. Sync/create Caddyfile in blob storage
9. Validate docker compose config
10. Start stack (`docker compose up -d`)

---

## ☁️ Blob Mount + Caddyfile Sync Logic

### Blob mount behavior
- Mount target default: `/media/<AZURE_BLOB_CONTAINER>`
- If mount directory is not empty, local files are moved to backup under `/tmp/blobfuse2-local-backup-...` before mounting.

### Caddyfile behavior (simple and intentional)
Path in mounted storage by default:
- `/media/<container>/caddy/Caddyfile`

Logic:
1. If file exists in storage -> copy to local `compose_dir/conf/Caddyfile`
2. If file does not exist -> `mkdir /caddy`, create `Caddyfile` in storage, then copy to local conf

Default generated file content:

```caddyfile
${DOMAIN} {
    reverse_proxy n8n:5678
}
```

---

## 🚢 How to Deploy

1. Push changes to branch monitored by workflow (`main` in current config).
2. Wait for GitHub Actions job `Azure Project Deployment`.
3. SSH to VM and verify post-deployment status.

---

## 🧾 Validation Checklist

Run on VM:

```bash
sudo tail -n 200 /var/log/n8n-bootstrap.log
sudo mountpoint -q /media/share-azureinfra-dev-01 && echo mounted || echo not-mounted
sudo findmnt -T /media/share-azureinfra-dev-01
sudo ls -la /media/share-azureinfra-dev-01/caddy
sudo ls -la /home/azureuser/n8n/conf
sudo docker ps
```

Expected:
- Blob mount is active
- `Caddyfile` exists in storage path and local conf path
- `n8n` and `caddy` containers are running

---

## 🛠️ Troubleshooting

### `blobfuse2: No such file or directory`
- `blobfuse2` package missing
- bootstrap now includes fallback install from GitHub `.deb`

### `libfuse3.so.3` missing on Debian 13
- runtime compatibility function creates symlink to available `libfuse3.so.3.*`
- then runs `ldconfig`

### `Error: mount directory is not empty`
- mountpoint had local files
- script now backs up local files before mounting

### Storage appears empty after writing
- verify mount is active with `sudo mountpoint -q ...`
- verify with `sudo` (non-root reads can be misleading on root-owned mounted paths)

### Pipeline says success but expected files not synced
- inspect `/var/log/n8n-bootstrap.log`
- ensure workflow used latest commit

---

## 🔒 Security Notes

- Do not hardcode secrets in workflow.
- Store `ENCRYPTION_KEY` in GitHub secrets.
- Keep storage keys in secrets only.
- Restrict NSG source IPs for SSH where possible.
- Keep private endpoints and private DNS enabled.

---

## 🧭 Operational Runbook

### Update Caddy config
1. Edit `Caddyfile` in blob-mounted path `/media/<container>/caddy/Caddyfile`
2. Re-run bootstrap or restart stack

### Redeploy app stack only
1. Update `compose.yml` or `.env` generation logic
2. Re-run workflow

### Rotate storage key
1. Rotate key in Azure
2. Re-run workflow (it regenerates `.env` with fresh key)

---

## 📝 Known Behaviors and Notes

- Function name `mount_azure_files_share` is historical, but implementation mounts **Blob container via blobfuse2**.
- Infrastructure deployment block in workflow is currently commented, so app deployment expects infra to exist.
- VM uses Debian 13 image; blobfuse compatibility handling is included for this OS generation.

---

## 🙌 Final Notes
If you are onboarding a new teammate, ask them to run first:

```bash
sudo tail -n 200 /var/log/n8n-bootstrap.log
sudo mountpoint -q /media/share-azureinfra-dev-01 && echo mounted || echo not-mounted
sudo docker ps
```

If all three checks are good, environment is healthy ✅
