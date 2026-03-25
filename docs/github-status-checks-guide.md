# GitHub Status Checks - Comprehensive Guide

## What is a Status Check?

A **status check** is an external validation that runs against a commit or pull request. GitHub uses status checks to determine whether a PR meets the required quality and security criteria before merging.

Status checks appear on the PR page as **pass** (green check), **fail** (red X), or **pending** (yellow dot).

---

## How Status Check Names Are Formed

The status check name is derived from the **workflow name** and **job key**:

```yaml
name: CI                    # workflow name
jobs:
  build_scan_push:          # job key
```

**Status check name:** `CI / build_scan_push`

> The job `key` (not the job `name` display label) determines the status check identifier.

---

## Scenario 1: Single Repo with Inline Workflow

**Setup:** Workflow defined directly in the repo.

```yaml
# .github/workflows/build-scan-and-push.yml
name: build-scan-and-push
on:
  pull_request:
    branches: [main]

jobs:
  build_scan_push:
    runs-on: ubuntu-latest
    steps:
      - name: Build
        run: docker build ...
      - name: Security scan
        run: trivy image ...
      - name: Security gate
        run: |
          if [ "$HIGH" -gt 1 ]; then exit 1; fi
```

**Status check name:** `build-scan-and-push / build_scan_push`

**Branch protection:**
1. Repo → Settings → Branches → Add rule for `main`
2. Enable "Require status checks to pass"
3. Add `build_scan_push` as required

---

## Scenario 2: Reusable Workflows in the Same Org

**Setup:** Centralized reusable workflows stored in a shared repo within the same GitHub organization.

### Shared repo structure

```
OrgName/.github/
  └── .github/workflows/
        ├── reusable-build.yml
        ├── reusable-test.yml
        └── reusable-security-scan.yml
```

### Reusable workflow definition

```yaml
# OrgName/.github/.github/workflows/reusable-security-scan.yml
name: security-scan
on:
  workflow_call:
    inputs:
      image-ref:
        required: true
        type: string
    secrets:
      AZURE_CLIENT_ID:
        required: true

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - name: Run Trivy
        run: trivy image ${{ inputs.image-ref }}
      - name: Security gate
        run: |
          if [ "$HIGH" -gt 1 ]; then exit 1; fi
```

### Consuming repo

```yaml
# app-repo/.github/workflows/ci.yml
name: CI
on:
  pull_request:
    branches: [main]

jobs:
  build:
    uses: OrgName/.github/.github/workflows/reusable-build.yml@main

  test:
    needs: build
    uses: OrgName/.github/.github/workflows/reusable-test.yml@main

  security-scan:
    needs: build
    uses: OrgName/.github/.github/workflows/reusable-security-scan.yml@main
    with:
      image-ref: myapp:${{ github.sha }}
    secrets:
      AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
```

**Status check names:**
| Job Key | Status Check Name |
|---------|-------------------|
| `build` | `CI / build` |
| `test` | `CI / test` |
| `security-scan` | `CI / security-scan` |

> **Key:** The status check name comes from the **calling workflow's job key**, not the reusable workflow's internal job key.

**Visibility requirement:** Reusable workflow repo must be set to **internal** or **public** within the org.

---

## Scenario 3: Multi-Org with Cross-Org Reusable Workflows

**Setup:** Reusable workflows stored in **Org A**, consumed by repos in **Org B**.

### Org A (shared workflows)

```
OrgA/shared-workflows/
  └── .github/workflows/
        ├── reusable-build.yml
        ├── reusable-test.yml
        └── reusable-security-scan.yml
```

> **Requirement:** The shared repo in Org A must be **public** for cross-org access.

### Org B (consuming repos)

```yaml
# OrgB/app-repo/.github/workflows/ci.yml
name: CI
on:
  pull_request:
    branches: [main]

jobs:
  build:
    uses: OrgA/shared-workflows/.github/workflows/reusable-build.yml@main

  test:
    needs: build
    uses: OrgA/shared-workflows/.github/workflows/reusable-test.yml@main

  security-scan:
    needs: build
    uses: OrgA/shared-workflows/.github/workflows/reusable-security-scan.yml@main
    with:
      image-ref: myapp:${{ github.sha }}
```

**Status check names (same pattern):**
- `CI / build`
- `CI / test`
- `CI / security-scan`

**Branch protection** is configured in **Org B** (where the repos live).

---

## Scenario 4: Org-Level Rulesets with Custom Properties

**Setup:** Enforce status checks across multiple repos using org-level rulesets, targeted by custom properties.

### Step 1: Create a custom property

Go to **Org Settings → Custom Properties → New Property**

| Field | Value |
|-------|-------|
| Name | `security-scan-required` |
| Type | `True/False` |

### Step 2: Assign property to repos

Via UI:
- Org → Repositories → Select repos → Set Properties → `security-scan-required` = `true`

Via CLI:
```bash
gh api --method PATCH \
  /orgs/OrgName/properties/values \
  -f "repository_names[]=app-repo-1" \
  -f "repository_names[]=app-repo-2" \
  -f "properties[0][property_name]=security-scan-required" \
  -f "properties[0][value]=true"
```

### Step 3: Create an org ruleset

Go to **Org Settings → Rules → New Ruleset**

| Setting | Value |
|---------|-------|
| Name | `Require security scan` |
| Enforcement | `Active` |
| Target branches | `main` |
| Target repos | Property: `security-scan-required` is `true` |
| Required status checks | `CI / build`, `CI / test`, `CI / security-scan` |

### Result

| Repo | Property Value | Rule Applied? | Merge Blocked on Failure? |
|------|---------------|---------------|--------------------------|
| `app-repo-1` | `true` | Yes | Yes |
| `app-repo-2` | `true` | Yes | Yes |
| `internal-tool` | `false` | No | No |
| `new-repo` (unset) | — | No | No |

> New repos automatically get the rule when `security-scan-required` is set to `true`.

---

## Scenario 5: Starter Workflows for Consistency

**Setup:** Provide a template workflow in the org's `.github` repo so new repos automatically get the correct workflow with standardized job names.

### Create a starter workflow

```
OrgName/.github/
  └── workflow-templates/
        ├── security-ci.yml
        └── security-ci.properties.json
```

```yaml
# workflow-templates/security-ci.yml
name: CI
on:
  pull_request:
    branches: [$default-branch]

jobs:
  build:
    uses: OrgName/.github/.github/workflows/reusable-build.yml@main

  test:
    needs: build
    uses: OrgName/.github/.github/workflows/reusable-test.yml@main

  security-scan:
    needs: build
    uses: OrgName/.github/.github/workflows/reusable-security-scan.yml@main
    with:
      image-ref: ${{ github.repository }}:${{ github.sha }}
```

```json
// workflow-templates/security-ci.properties.json
{
  "name": "Security CI Pipeline",
  "description": "Standard build, test, and security scan pipeline",
  "iconName": "shield-lock",
  "categories": ["Security", "CI"]
}
```

When a developer creates a new repo in the org, they can select this starter workflow from **Actions → New Workflow → By OrgName**, and it comes pre-configured with the correct job names that match the org ruleset.

---

## Summary: Status Check Name Patterns

| Scenario | Status Check Format | Who Controls the Name? |
|----------|-------------------|----------------------|
| Inline workflow | `{workflow name} / {job key}` | Repo owner |
| Reusable workflow (same org) | `{calling workflow name} / {calling job key}` | Repo owner (caller) |
| Reusable workflow (cross-org) | `{calling workflow name} / {calling job key}` | Repo owner (caller) |
| Org ruleset | References `{job key}` | Org admin |

## Summary: Branch Protection Layers

| Layer | Scope | Mechanism |
|-------|-------|-----------|
| **Repo branch protection** | Single repo | Settings → Branches → Rules |
| **Org ruleset** | Multiple repos | Settings → Rules → Target by property |
| **Custom property** | Repo tagging | Determines which repos get which rules |
| **Starter workflow** | New repo onboarding | Ensures consistent job names across org |
| **Reusable workflow** | Centralized logic | Single source of truth for build/test/scan steps |

---

## Quick Reference: Enforcing Security Gates on PRs

```
┌─────────────────────────────────────────────────┐
│                  Developer opens PR              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│  CI workflow triggers (pull_request event)       │
│  Jobs: build → test → security-scan              │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│  Security gate checks vulnerability counts       │
│  HIGH > threshold? → exit 1 (FAIL)              │
└─────────────────┬───────────────────────────────┘
                  │
          ┌───────┴───────┐
          │               │
        PASS            FAIL
          │               │
          ▼               ▼
   ┌──────────┐   ┌────────────────┐
   │ PR merge │   │ PR merge       │
   │ allowed  │   │ BLOCKED        │
   └──────────┘   │ (org ruleset   │
                  │  requires      │
                  │  status check) │
                  └────────────────┘
```
