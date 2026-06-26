# DR Post-Install Verification Checklist

After deploying a DR primary + standby pair, run these checks to confirm
correct configuration.

Replace `<NAMESPACE>` with your LogScale namespace (default: `log`).

---

## 1. Encryption Key Sync

The standby must hold the same encryption key as the primary to decrypt
GCS snapshots during recovery.

### On PRIMARY

```bash
kubectl get secret <INFRA_PREFIX>-gcp-storage-encryption-key -n <NAMESPACE> \
  -o jsonpath='{.data.gcp-storage-encryption-key}' | base64 -d | shasum -a 256
```

### On STANDBY

The recovery secret default name is `dr-secondary-gcs-storage-encryption`
(configurable via `gcp_recover_from_encryption_key_secret_name`).

```bash
kubectl get secret dr-secondary-gcs-storage-encryption -n <NAMESPACE> \
  -o jsonpath='{.data.gcp-storage-encryption-key}' | base64 -d | shasum -a 256
```

**Pass:** Both SHA256 hashes are identical.

---

## 2. Recovery Environment Variables (STANDBY only)

These `GCP_RECOVER_FROM_*` env vars are injected into standby LogScale pods.
They do **not** exist on the primary.

```bash
POD=$(kubectl get pods -n <NAMESPACE> -l app.kubernetes.io/name=humio -o name | head -1)
```

### GCP_RECOVER_FROM_BUCKET

```bash
kubectl exec $POD -n <NAMESPACE> -- env | grep GCP_RECOVER_FROM_BUCKET
```

**Expected:** `GCP_RECOVER_FROM_BUCKET=<primary-bucket-name>`

### GCP_RECOVER_FROM_WORKLOAD_IDENTITY

```bash
kubectl exec $POD -n <NAMESPACE> -- env | grep GCP_RECOVER_FROM_WORKLOAD_IDENTITY
```

**Expected:** `GCP_RECOVER_FROM_WORKLOAD_IDENTITY=true`

Tells the standby to authenticate with its own Workload Identity SA when
reading from the primary's bucket.

### GCP_RECOVER_FROM_REPLACE_REGION

```bash
kubectl exec $POD -n <NAMESPACE> -- env | grep GCP_RECOVER_FROM_REPLACE_REGION
```

**Expected:** `GCP_RECOVER_FROM_REPLACE_REGION=<primary-region>/<standby-region>`

String replacement (find/replace format) applied to region references in
stored segment metadata during recovery.

### GCP_RECOVER_FROM_REPLACE_BUCKET

```bash
kubectl exec $POD -n <NAMESPACE> -- env | grep GCP_RECOVER_FROM_REPLACE_BUCKET
```

**Expected:** `GCP_RECOVER_FROM_REPLACE_BUCKET=<primary-bucket>/<standby-bucket>`

String replacement for bucket name references in segment metadata. After
promotion, the standby writes new segments to its own bucket while still
reading historical segments from the primary's bucket.

### GCP_RECOVER_FROM_ENCRYPTION_KEY (secretKeyRef)

```bash
kubectl get humiocluster -n <NAMESPACE> -o yaml | grep -A5 'GCP_RECOVER_FROM_ENCRYPTION_KEY'
```

**Expected:** `secretKeyRef` pointing to the recovery encryption secret with
`key: gcp-storage-encryption-key`.

### GCP_RECOVER_FROM_REGION (should NOT be set)

```bash
kubectl exec $POD -n <NAMESPACE> -- env | grep GCP_RECOVER_FROM_REGION || echo 'NOT SET (correct)'
```

**Expected:** Not set. GCS buckets are globally addressable — no region
qualifier needed (unlike S3).

### ENABLE_ALERTS

```bash
kubectl exec $POD -n <NAMESPACE> -- env | grep ENABLE_ALERTS
```

**Expected:** `ENABLE_ALERTS=false`

Alerts are disabled on standby to prevent duplicate firing. On promotion,
setting `dr = "active"` re-enables them.

---

## 3. GCS Cross-Region Access

The standby's Workload Identity SA needs read access to the primary's bucket.

```bash
kubectl exec $POD -n <NAMESPACE> -- \
  gcloud storage ls gs://<primary-bucket-name>/ --limit=5
```

**Pass:** Lists objects (or empty output for new bucket). Must NOT show
`AccessDeniedException`.

If access fails, verify the IAM binding:

```bash
gcloud storage buckets get-iam-policy gs://<primary-bucket-name> \
  --format="table(bindings.role,bindings.members)" | grep <standby-sa-email>
```

The standby SA should have `roles/storage.objectViewer` on the primary bucket.

---

## 4. Terraform Outputs Cross-Check

Verify the standby's Terraform outputs reference the correct primary values:

```bash
terraform output -json | jq '{
  recover_from_bucket: .gcp_recover_from_bucket.value,
  recover_from_encryption_key_secret: .gcp_recover_from_encryption_key_secret_name.value,
  primary_bucket: .dr_primary_gcs_bucket.value
}'
```

**Pass:** `recover_from_bucket` matches the primary's actual GCS bucket name.

---

## 5. Summary

| Check | Where | Pass Criteria |
|-------|-------|---------------|
| Encryption key hash | Primary + Standby | SHA256 identical |
| `GCP_RECOVER_FROM_BUCKET` | Standby | Primary's bucket name |
| `GCP_RECOVER_FROM_WORKLOAD_IDENTITY` | Standby | `true` |
| `GCP_RECOVER_FROM_REPLACE_REGION` | Standby | `<primary-region>/<standby-region>` |
| `GCP_RECOVER_FROM_REPLACE_BUCKET` | Standby | `<primary-bucket>/<standby-bucket>` |
| `GCP_RECOVER_FROM_ENCRYPTION_KEY` | Standby | secretKeyRef resolves |
| `GCP_RECOVER_FROM_REGION` | Standby | Not set |
| `ENABLE_ALERTS` | Standby | `false` |
| GCS cross-region read | Standby | No AccessDeniedException |
| Terraform outputs | Standby | Bucket names match |
