# Azure Event Grid → GitHub repository_dispatch Setup

This guide configures Azure Event Grid to trigger a GitHub Actions workflow when Microsoft Defender for Containers completes an image vulnerability scan on ACR.

## Architecture

```
ACR Image Push
  → Defender for Containers scans image (async, 5-30 min)
    → Event Grid detects assessment completion
      → Webhook POSTs to GitHub repository_dispatch
        → defender-release-report.yml runs
          → Queries Defender API for findings
            → Updates GitHub Release with scan results
```

## Prerequisites

- Microsoft Defender for Containers enabled on the Azure subscription
- Azure Container Registry (ACR) with Defender scanning active
- A GitHub Personal Access Token (PAT) with `repo` scope (for `repository_dispatch`)

---

## Step 1: Create a GitHub PAT

1. Go to **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
2. Create a token with:
   - **Repository access**: Select `python-msdo-org`
   - **Permissions**: `Contents: Read and write` (required by the `POST /repos/{owner}/{repo}/dispatches` API to trigger `repository_dispatch` events on the repo)
3. Copy the token value

## Step 2: Store the PAT in Azure Key Vault

```bash
# Create or use an existing Key Vault
az keyvault secret set \
  --vault-name <YOUR_KEYVAULT_NAME> \
  --name github-pat \
  --value <YOUR_GITHUB_PAT>
```

## Step 3: Create an Event Grid System Topic

```bash
# Create a system topic for your subscription's security events
az eventgrid system-topic create \
  --name defender-scan-events \
  --resource-group <YOUR_RG> \
  --source "/subscriptions/<SUBSCRIPTION_ID>" \
  --topic-type "Microsoft.Security.SecurityCenter" \
  --location global
```

## Step 4: Create the Event Subscription with Webhook

The webhook endpoint is the GitHub repository_dispatch API. Event Grid will POST to it when Defender completes an assessment.

```bash
# Retrieve the PAT from Key Vault
GITHUB_PAT=$(az keyvault secret show \
  --vault-name <YOUR_KEYVAULT_NAME> \
  --name github-pat \
  --query value -o tsv)

# Create the event subscription
az eventgrid system-topic event-subscription create \
  --name defender-to-github \
  --system-topic-name defender-scan-events \
  --resource-group <YOUR_RG> \
  --endpoint-type webhook \
  --endpoint "https://api.github.com/repos/<OWNER>/python-msdo-org/dispatches" \
  --included-event-types "Microsoft.Security.AssessmentCreated" \
  --advanced-filter subject StringContains "<YOUR_ACR_NAME>" \
  --delivery-attribute-mapping \
    Authorization Static "token ${GITHUB_PAT}" true \
    Accept Static "application/vnd.github+json" false \
    Content-Type Static "application/json" false
```

> **Note**: Replace `<OWNER>` with your GitHub org/user (e.g., `DevOpsVyaspeeth`).

## Step 5: Configure the Webhook Payload Transform

Event Grid sends its own event schema by default. You need an Azure Function or Logic App as a thin proxy to transform the Event Grid payload into the `repository_dispatch` format:

### Required payload format for GitHub:

```json
{
  "event_type": "defender-scan-completed",
  "client_payload": {
    "image_digest": "<from Defender event>",
    "registry": "<acr-name>.azurecr.io",
    "repository": "sample-app",
    "tag": "<semver tag>"
  }
}
```

### Option A: Azure Function (recommended)

Create a lightweight HTTP-triggered Azure Function that:
1. Receives the Event Grid event
2. Extracts the image digest, registry, and repository from the event data
3. Looks up the image tag from ACR (by digest)
4. POSTs the transformed payload to GitHub `repository_dispatch`

### Option B: Logic App

1. **Trigger**: Event Grid → When a resource event occurs
2. **Parse JSON**: Extract `data.properties.additionalData`
3. **HTTP action**: POST to `https://api.github.com/repos/<OWNER>/python-msdo-org/dispatches`
   - Headers: `Authorization: token <PAT>`, `Accept: application/vnd.github+json`
   - Body: The transformed JSON payload above

---

## Verification

1. Push a new image to ACR (merge a PR to trigger `ci-new.yml`)
2. Wait for Defender to scan (5-30 minutes)
3. Check Event Grid metrics: **Azure Portal → Event Grid System Topic → Metrics**
4. Check GitHub Actions: The `Defender Scan → GitHub Release` workflow should trigger
5. Check the GitHub Release: A "Microsoft Defender Scan Results" section should appear

## Troubleshooting

| Issue | Check |
|-------|-------|
| Event Grid subscription not firing | Verify Defender is enabled and has completed at least one scan. Check Event Grid metrics for delivery failures. |
| GitHub workflow not triggered | Verify PAT has `repo` scope. Check Event Grid delivery logs for HTTP 401/403 errors. |
| No findings in release | Verify the Resource Graph query returns results: run `az graph query` manually with the image details. |
| Duplicate findings on release | The workflow strips previous Defender sections before appending — ensure the sed pattern in the workflow matches. |
