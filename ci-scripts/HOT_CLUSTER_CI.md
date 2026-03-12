# Hot Cluster CI

This directory contains scripts and documentation for the hot cluster CI infrastructure. The hot cluster is a persistent OpenShift cluster on IBM Cloud with bare metal worker nodes, configured with KubeVirt (HCO) and GitHub Actions Runner Controller (ARC) for self-hosted CI runners.

## Architecture

```
GitHub Actions (workflow_dispatch)
  │
  ├── hot-cluster-setup.yml      → Provisions cluster, installs ARC + HCO
  ├── hot-cluster-teardown.yml   → Tears down cluster, cleans up ghost runners
  ├── hot-cluster-auto-teardown.yml → Scheduled idle check (every 30min, 2h threshold)
  └── hot-cluster-ci-test.yml    → Health gate + gating tests on self-hosted runner
        │
        ├── Job 1: cluster-health-check (ubuntu-latest)
        │     └── Runs ci-scripts/check-cluster-health.sh
        │
        └── Job 2: run-gating-tests (runs-on: hot-cluster)
              └── Cypress E2E tests in off-cluster UI mode
```

## Required GitHub Secrets

These secrets must be configured in the repository settings before running the workflows.

### IBM Cloud

| Secret              | Description           | How to Obtain                                                 |
| ------------------- | --------------------- | ------------------------------------------------------------- |
| `IBM_CLOUD_API_KEY` | IBM Cloud IAM API key | IBM Cloud Console → Manage → Access (IAM) → API keys → Create |

The API key must belong to a user or service ID with the following IAM permissions:

- **Kubernetes Service**: Administrator role (to create/delete ROKS clusters)
- **VPC Infrastructure Services**: Editor role (if using VPC-based clusters)
- **Classic Infrastructure**: Super User or equivalent (for bare metal provisioning)

### Ghost Runner Cleanup (optional)

| Secret    | Description               | How to Obtain                               |
| --------- | ------------------------- | ------------------------------------------- |
| `BOT_PAT` | PAT with repo admin scope | GitHub Settings → Developer Settings → PATs |

The `BOT_PAT` is only needed if you want the teardown workflow to automatically delete offline "ghost" runners from GitHub. Deleting self-hosted runners requires repository admin access which `GITHUB_TOKEN` cannot provide. The PAT needs the `repo` scope (classic) or **Administration: Read and Write** (fine-grained). If not set, ghost runners can be cleaned up manually via Settings → Actions → Runners.

### ARC Authentication (choose one)

#### Option A: GitHub App (recommended for production)

| Secret                       | Description           | How to Obtain                     |
| ---------------------------- | --------------------- | --------------------------------- |
| `ARC_GITHUB_APP_ID`          | GitHub App ID         | See "Creating a GitHub App" below |
| `ARC_GITHUB_APP_INSTALL_ID`  | App installation ID   | See "Creating a GitHub App" below |
| `ARC_GITHUB_APP_PRIVATE_KEY` | App private key (PEM) | See "Creating a GitHub App" below |

#### Option B: Personal Access Token (simpler, less secure)

| Secret           | Description      | How to Obtain                                              |
| ---------------- | ---------------- | ---------------------------------------------------------- |
| `ARC_GITHUB_PAT` | Fine-grained PAT | GitHub Settings → Developer Settings → Fine-grained tokens |

The PAT requires these permissions on the target repository:

- **Administration**: Read and Write
- **Metadata**: Read-only

## Cluster Authentication

All workflows that need cluster access use the IBM Cloud CLI to pull a kubeconfig on-demand:

```yaml
- name: Setup IBM Cloud CLI
  uses: IBM/actions-ibmcloud-cli@v1
  with:
    api_key: ${{ secrets.IBM_CLOUD_API_KEY }}
    plugins: kubernetes-service

- name: Configure kubeconfig
  run: |
    ibmcloud oc cluster config --cluster "${CLUSTER_NAME}" --admin
    oc cluster-info
```

This avoids storing kubeconfig or credentials as GitHub secrets. Any workflow or job that needs `oc`/`kubectl` access simply repeats these two steps with the shared `IBM_CLOUD_API_KEY`.

## Creating a GitHub App for ARC

1. Go to your organization settings (or personal settings) → Developer settings → GitHub Apps → New GitHub App
2. Configure the app:
   - **Name**: `kubevirt-plugin-arc` (or any name)
   - **Homepage URL**: Your repository URL
   - **Webhook**: Uncheck "Active" (not needed)
   - **Permissions**:
     - Repository permissions → Administration: Read and Write
     - Organization permissions → Self-hosted runners: Read and Write
3. Create the app and note the **App ID**
4. Generate a **Private Key** (downloads a `.pem` file)
5. Install the app on your organization/repository and note the **Installation ID**
   - Find it in the URL: `https://github.com/settings/installations/<INSTALL_ID>`
6. Store the three values as GitHub secrets:
   - `ARC_GITHUB_APP_ID` = App ID
   - `ARC_GITHUB_APP_INSTALL_ID` = Installation ID
   - `ARC_GITHUB_APP_PRIVATE_KEY` = Contents of the `.pem` file

## Usage

### Custom runner image

The setup workflow builds a **custom runner image** on the cluster after HCO is installed. The image extends the official GitHub Actions runner with Node.js 22, kubectl, oc, and virtctl so workflow jobs do not need to install them. The image is built in-cluster (OpenShift BuildConfig, binary Docker build), pushed to the internal registry, and the ARC scale set is reconfigured to use it.

- **Dockerfile**: `ci-scripts/runner-image/Dockerfile`
- **Build**: `ci-scripts/build-arc-runner-image.sh` (run after ARC and HCO; creates BuildConfig, streams context, waits for build)
- **Use the image**: `ci-scripts/generate-arc-runner-values.sh <image_ref> <output.yaml>` then re-run `install-arc.sh` with `ARC_RUNNER_VALUES_FILE=<output.yaml>`

The generated values include a pod `securityContext` (runAsUser/runAsGroup/fsGroup 1001) so the runner process matches the image’s `runner` user and can write to `/home/runner/.npm` and `/home/runner/.tmp` (npm cache/tmp). Without this, OpenShift’s default random UID would make those directories unwritable.

Optional env for the build script: `OC_VERSION` (e.g. 4.20), `VIRTCTL_VERSION` (e.g. v1.4.0), `ARC_RUNNERS_NS` (default arc-runners).

### Setting Up the Hot Cluster

1. Go to Actions → "Hot Cluster Setup" → Run workflow
2. Configure inputs (cluster name, region, OpenShift version, worker flavor, count)
3. Click "Run workflow"
4. Wait for completion (30-90 minutes for bare metal provisioning; includes building the custom runner image and reconfiguring ARC)

### Running CI Tests

1. Go to Actions → "Hot Cluster CI Test" → Run workflow
2. Optionally customize the test spec (defaults to `tests/gating.cy.ts`)
3. The workflow will:
   - Run a health check on `ubuntu-latest` to verify the cluster is ready
   - If healthy, run gating tests on the `hot-cluster` self-hosted runner
   - Upload test artifacts (screenshots, videos) on completion

### Tearing Down the Cluster

**Manual**: Go to Actions → "Hot Cluster Teardown" → Run workflow

**Automatic**: The auto-teardown workflow runs every 30 minutes and will tear down the cluster if no CI jobs have run in the last 2 hours.

## Scripts

| Script                          | Purpose                                                            |
| ------------------------------- | ------------------------------------------------------------------ |
| `install-hco.sh`                | Installs HCO operator, HPP storage, and virtctl                    |
| `install-arc.sh`                | Installs ARC controller and runner scale set                       |
| `build-arc-runner-image.sh`     | Builds custom runner image (Node, kubectl, oc, virtctl) in-cluster |
| `generate-arc-runner-values.sh` | Writes values fragment so ARC uses the custom runner image         |
| `check-cluster-health.sh`       | Verifies cluster, HCO, ARC, and storage health                     |

### Script Configuration

All scripts accept configuration via environment variables. See the header comments in each script for details.

Key defaults:

- `KVM_EMULATION=false` (bare metal has real KVM)
- `RUNNER_SCALE_SET_NAME=hot-cluster` (the `runs-on:` label)
- `MIN_RUNNERS=0`, `MAX_RUNNERS=5`

## Cost Control

Bare metal nodes on IBM Cloud are expensive. The auto-teardown workflow provides automatic cost control:

- Runs every 30 minutes via cron
- Checks if any CI jobs are in-progress or queued
- If idle for more than 2 hours, triggers the teardown workflow
- Worst case: an idle cluster runs ~2.5 hours before teardown

**Important**: Always verify the cluster has been torn down if you're done testing. The auto-teardown is a safety net, not a substitute for manual cleanup.

## Troubleshooting

### Cluster setup fails during provisioning

- Check IBM Cloud status page for outages
- Verify the API key has sufficient permissions
- Bare metal availability varies by region; try a different zone

### ARC runners not registering

- Check ARC controller logs: `oc logs -n arc-systems -l app.kubernetes.io/name=gha-rs-controller`
- Verify GitHub App credentials are correct
- Ensure the GitHub App is installed on the repository

### Health check fails

- Run `ci-scripts/check-cluster-health.sh` manually with `oc` configured
- Check individual component status: `oc get pods -n kubevirt-hyperconverged`
- Verify storage: `oc get storageclass`

### `npm ci` fails in hot-cluster job

- **"package-lock.json is out of sync"**: Run `npm install` locally and commit the updated `package-lock.json`.
- **Node/npm version**: The workflow uses Node 22; the runner image must provide a compatible Node (or use `actions/setup-node`). Check the "Install dependencies" step log for `node -v` and `npm -v`.
- **Network**: The runner must reach the npm registry. If the cluster restricts egress, allow `registry.npmjs.org` (and any private registries).

### Ghost runners after failed teardown

- Go to repository Settings → Actions → Runners
- Manually delete any offline runners
- Or run the teardown workflow again (it includes ghost runner cleanup)

### ARC runner `oc` / `kubectl` permissions

Jobs that run on `hot-cluster` use the **default service account** in the `arc-runners` namespace. That account has minimal permissions by default, so steps like `oc cluster-info`, `oc get consoles.config.openshift.io`, creating test namespaces, or running Cypress setup/cleanup may fail with "Forbidden" or "Unauthorized".

**Fix:** Grant the runner’s service account the needed privileges by applying the RBAC manifest after ARC is installed:

```bash
oc apply -f ci-scripts/arc-runner-rbac.yaml
```

This creates a `ClusterRole` (`arc-runner-ci`) with permissions to read cluster/console config, create and delete namespaces, and manage pods, VMs, DataVolumes, etc., and binds it to `system:serviceaccount:arc-runners:default`.

For a disposable or single-tenant cluster you can instead grant full cluster-admin by using the alternative ClusterRoleBinding described in the comments at the top of `ci-scripts/arc-runner-rbac.yaml`.
