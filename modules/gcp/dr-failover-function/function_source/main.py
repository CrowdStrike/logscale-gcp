"""
DR Failover Cloud Function Handler

This Cloud Function handles automatic DR failover for LogScale clusters on GCP.
When the primary cluster's health check fails, this function:
1. Validates the alert state and health check status
2. Cleans up stale TLS secrets to prevent CA mismatch
3. Scales the humio-operator deployment to start LogScale pods
4. Waits for pods to become ready

Features:
- Exponential backoff retry logic for transient Kubernetes/GCP API failures
- Jitter to prevent thundering herd problem
- Configurable retry parameters via environment variables
- Detailed logging and retry statistics for observability
"""

import base64
import json
import os
import logging
import random
import tempfile
import time
from dataclasses import dataclass, field
from functools import wraps
from typing import Callable

import functions_framework
from cloudevents.http import CloudEvent
from google.cloud import container_v1
from google.cloud import monitoring_v3
from google.cloud import storage as gcs_storage
from google.auth import default
from google.auth.transport.requests import Request
from kubernetes import client as k8s_client
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# Configuration from Environment Variables
# =============================================================================

PROJECT_ID = os.environ.get('PROJECT_ID')
CLUSTER_NAME = os.environ.get('CLUSTER_NAME')
CLUSTER_LOCATION = os.environ.get('CLUSTER_LOCATION')
NAMESPACE = os.environ.get('NAMESPACE', 'log')
TARGET_OPERATOR_REPLICAS = 1
TARGET_NODE_COUNT = int(os.environ.get('TARGET_NODE_COUNT', '1'))
PRIMARY_UPTIME_CHECK_ID = os.environ.get('PRIMARY_UPTIME_CHECK_ID', '')
SKIP_PRIMARY_HEALTH_VALIDATION = os.environ.get('SKIP_PRIMARY_HEALTH_VALIDATION', 'false').lower() == 'true'
HUMIOCLUSTER_NAME = os.environ.get('HUMIOCLUSTER_NAME', '')

# Pre-failover validation configuration
PRE_FAILOVER_FAILURE_SECONDS = int(os.environ.get('PRE_FAILOVER_FAILURE_SECONDS', '180'))
FAILOVER_COOLDOWN_SECONDS = int(os.environ.get('FAILOVER_COOLDOWN_SECONDS', '300'))

# Pre-failover cleanup configuration
GCS_BUCKET_NAME = os.environ.get('GCS_BUCKET_NAME', '')
KAFKA_BOOTSTRAP_SERVER = os.environ.get('KAFKA_BOOTSTRAP_SERVER', '')

# Retry configuration (with sensible defaults)
MAX_RETRIES = int(os.environ.get('MAX_RETRIES', '3'))
BASE_DELAY_SECONDS = float(os.environ.get('BASE_DELAY_SECONDS', '1.0'))
MAX_DELAY_SECONDS = float(os.environ.get('MAX_DELAY_SECONDS', '30.0'))

# Per-instance cooldown — resets on cold start. PRE_FAILOVER_FAILURE_SECONDS is the durable gate.
_last_failover_time = 0

# HTTP status codes that indicate transient failures and should trigger retry
RETRYABLE_STATUS_CODES = frozenset([429, 500, 502, 503, 504])


# =============================================================================
# Retry Statistics Tracking
# =============================================================================

@dataclass
class RetryStats:
    """Track retry statistics for observability and debugging."""
    total_attempts: int = 0
    successful_retries: int = 0
    failed_operations: int = 0
    total_delay_seconds: float = 0.0
    errors_by_status: dict = field(default_factory=dict)
    errors_by_type: dict = field(default_factory=dict)


# Global retry stats for the current function invocation
retry_stats = RetryStats()


def _reset_retry_stats():
    """Reset retry statistics for a new invocation."""
    global retry_stats
    retry_stats = RetryStats()


def _get_retry_stats_dict() -> dict:
    """Convert retry stats to a dictionary for logging/response."""
    return {
        "total_attempts": retry_stats.total_attempts,
        "successful_retries": retry_stats.successful_retries,
        "failed_operations": retry_stats.failed_operations,
        "total_delay_seconds": round(retry_stats.total_delay_seconds, 2),
        "errors_by_status": retry_stats.errors_by_status,
        "errors_by_type": retry_stats.errors_by_type,
    }


# =============================================================================
# Retry Logic Implementation
# =============================================================================

def _calculate_delay(attempt: int, base_delay: float, max_delay: float, exponential_base: float = 2.0) -> float:
    """
    Calculate delay with exponential backoff and jitter.

    Args:
        attempt: Current attempt number (0-indexed)
        base_delay: Base delay in seconds
        max_delay: Maximum delay cap in seconds
        exponential_base: Base for exponential calculation (default 2.0)

    Returns:
        Delay in seconds with jitter applied

    Example delays (base=1.0, max=30.0):
        attempt 0: ~1.0s (+-0.25s jitter)
        attempt 1: ~2.0s (+-0.5s jitter)
        attempt 2: ~4.0s (+-1.0s jitter)
        attempt 3: ~8.0s (+-2.0s jitter)
    """
    # Calculate exponential backoff
    delay = min(base_delay * (exponential_base ** attempt), max_delay)

    # Add jitter (+-25%) to prevent thundering herd problem
    jitter = delay * 0.25 * (2 * random.random() - 1)

    return max(0.1, delay + jitter)


def retry_with_backoff(
    max_retries: int = MAX_RETRIES,
    base_delay: float = BASE_DELAY_SECONDS,
    max_delay: float = MAX_DELAY_SECONDS,
    operation_name: str = "operation",
):
    """
    Decorator that retries a function with exponential backoff and jitter.

    Retries are triggered for:
    - HTTP 429 (Too Many Requests) - Kubernetes API rate limiting
    - HTTP 500 (Internal Server Error) - Transient server errors
    - HTTP 502 (Bad Gateway) - Load balancer/proxy issues
    - HTTP 503 (Service Unavailable) - API server overloaded
    - HTTP 504 (Gateway Timeout) - Request timeout
    - Connection errors (ConnectionError, ConnectionResetError, TimeoutError, OSError)

    Non-retryable errors (fail immediately):
    - HTTP 400 (Bad Request) - Invalid request
    - HTTP 401 (Unauthorized) - Authentication failed
    - HTTP 403 (Forbidden) - Permission denied
    - HTTP 404 (Not Found) - Resource doesn't exist
    - HTTP 409 (Conflict) - Resource version conflict
    - HTTP 422 (Unprocessable Entity) - Validation error

    Args:
        max_retries: Maximum number of retry attempts
        base_delay: Initial delay in seconds before first retry
        max_delay: Maximum delay cap between retries
        operation_name: Human-readable name for logging
    """
    def decorator(func: Callable):
        @wraps(func)
        def wrapper(*args, **kwargs):
            global retry_stats
            last_exception = None

            for attempt in range(max_retries + 1):
                retry_stats.total_attempts += 1

                try:
                    result = func(*args, **kwargs)

                    # Log successful retry
                    if attempt > 0:
                        retry_stats.successful_retries += 1
                        logger.info(
                            f"[{operation_name}] Succeeded after {attempt} retry attempt(s)"
                        )

                    return result

                except ApiException as e:
                    last_exception = e
                    status_key = f"http_{e.status}"
                    retry_stats.errors_by_status[status_key] = retry_stats.errors_by_status.get(status_key, 0) + 1

                    # Check if this is a retryable status code
                    if e.status not in RETRYABLE_STATUS_CODES:
                        logger.error(
                            f"[{operation_name}] Non-retryable API error (HTTP {e.status}): {e.reason}"
                        )
                        retry_stats.failed_operations += 1
                        raise

                    # Check if we have retries remaining
                    if attempt >= max_retries:
                        logger.error(
                            f"[{operation_name}] Max retries ({max_retries}) exhausted. "
                            f"Last error (HTTP {e.status}): {e.reason}"
                        )
                        retry_stats.failed_operations += 1
                        raise

                    # Calculate and apply delay
                    delay = _calculate_delay(attempt, base_delay, max_delay)
                    retry_stats.total_delay_seconds += delay

                    logger.warning(
                        f"[{operation_name}] Retryable API error (HTTP {e.status}): {e.reason}. "
                        f"Attempt {attempt + 1}/{max_retries + 1}, retrying in {delay:.2f}s..."
                    )
                    time.sleep(delay)

                except (ConnectionError, ConnectionResetError, TimeoutError, OSError) as e:
                    last_exception = e
                    error_type = type(e).__name__
                    retry_stats.errors_by_type[error_type] = retry_stats.errors_by_type.get(error_type, 0) + 1

                    # Check if we have retries remaining
                    if attempt >= max_retries:
                        logger.error(
                            f"[{operation_name}] Max retries ({max_retries}) exhausted. "
                            f"Last connection error: {e}"
                        )
                        retry_stats.failed_operations += 1
                        raise

                    # Calculate and apply delay
                    delay = _calculate_delay(attempt, base_delay, max_delay)
                    retry_stats.total_delay_seconds += delay

                    logger.warning(
                        f"[{operation_name}] Connection error: {e}. "
                        f"Attempt {attempt + 1}/{max_retries + 1}, retrying in {delay:.2f}s..."
                    )
                    time.sleep(delay)

            # Should not reach here, but handle edge case
            if last_exception:
                raise last_exception

        return wrapper
    return decorator


# =============================================================================
# GKE Credentials and Kubernetes Client
# =============================================================================

@retry_with_backoff(operation_name="get_gke_credentials")
def _get_gke_credentials():
    """
    Get GKE cluster credentials and return a configured Kubernetes API client.
    Uses the Cloud Function's service account for authentication.

    This function is decorated with retry logic because:
    - GKE API can experience transient failures
    - Network issues between Cloud Function and GKE endpoint can occur
    """
    credentials, project = default(scopes=['https://www.googleapis.com/auth/cloud-platform'])

    container_client = container_v1.ClusterManagerClient(credentials=credentials)
    cluster_path = f"projects/{PROJECT_ID}/locations/{CLUSTER_LOCATION}/clusters/{CLUSTER_NAME}"

    logger.info(f"Fetching cluster info for {cluster_path}")
    cluster = container_client.get_cluster(name=cluster_path)

    credentials.refresh(Request())

    configuration = k8s_client.Configuration()
    configuration.host = f"https://{cluster.endpoint}"
    configuration.api_key = {"authorization": f"Bearer {credentials.token}"}

    with tempfile.NamedTemporaryFile(delete=False, mode='wb', suffix='.crt') as ca_file:
        ca_data = base64.b64decode(cluster.master_auth.cluster_ca_certificate)
        ca_file.write(ca_data)
        configuration.ssl_ca_cert = ca_file.name

    configuration.verify_ssl = True

    api_client = k8s_client.ApiClient(configuration)
    logger.info(f"Successfully configured Kubernetes client for cluster {CLUSTER_NAME}")

    return api_client, credentials


def _refresh_token_if_needed(api_client, credentials):
    """Refresh the access token if it's expired or about to expire."""
    if credentials.expired or not credentials.token:
        logger.info("Refreshing expired credentials")
        credentials.refresh(Request())
        api_client.configuration.api_key = {"authorization": f"Bearer {credentials.token}"}
    return api_client


# =============================================================================
# Kubernetes Operations with Retry
# =============================================================================

@retry_with_backoff(operation_name="get_operator_replicas")
def _get_current_operator_replicas(apps_v1, namespace):
    """
    Get the current replica count of the humio-operator deployment.

    Retryable errors: 429, 500, 502, 503, 504, connection errors
    Non-retryable: 404 (deployment not found) - raises RuntimeError
    """
    try:
        deployment = apps_v1.read_namespaced_deployment(
            name="humio-operator",
            namespace=namespace
        )
        replicas = deployment.spec.replicas or 0
        logger.info(f"Current humio-operator replicas: {replicas}")
        return replicas
    except ApiException as e:
        if e.status == 404:
            logger.error(f"humio-operator deployment not found in namespace {namespace}")
            raise RuntimeError(f"Deployment humio-operator not found in namespace {namespace}")
        raise


@retry_with_backoff(operation_name="patch_operator_replicas")
def _patch_operator_replicas(apps_v1, namespace, target_replicas):
    """
    Patch the humio-operator deployment to scale replicas.

    This is the most critical operation - it triggers the DR failover.
    Retryable errors: 429, 500, 502, 503, 504, connection errors
    """
    patch_body = {"spec": {"replicas": target_replicas}}

    logger.info(f"Patching humio-operator deployment to {target_replicas} replica(s)")

    apps_v1.patch_namespaced_deployment(
        name="humio-operator",
        namespace=namespace,
        body=patch_body
    )
    logger.info(f"Successfully patched humio-operator replicas to {target_replicas}")
    return True


@retry_with_backoff(operation_name="patch_humiocluster_node_count")
def _patch_humiocluster_node_count(api_client, namespace, humiocluster_name, target_node_count):
    """Patch HumioCluster CR nodeCount for all pools (basic + advanced cluster types)."""
    if not humiocluster_name:
        raise RuntimeError("HUMIOCLUSTER_NAME required for CR patching")

    custom_api = k8s_client.CustomObjectsApi(api_client)

    cr = custom_api.get_namespaced_custom_object(
        group="core.humio.com",
        version="v1alpha1",
        namespace=namespace,
        plural="humioclusters",
        name=humiocluster_name,
    )

    patch_ops = [
        {"op": "replace", "path": "/spec/nodeCount", "value": target_node_count}
    ]

    node_pools = cr.get("spec", {}).get("nodePools", [])
    for idx, pool in enumerate(node_pools):
        pool_name = pool.get("name", f"pool-{idx}")
        patch_ops.append({
            "op": "replace",
            "path": f"/spec/nodePools/{idx}/spec/nodeCount",
            "value": target_node_count
        })
        logger.info(f"  Will patch nodePool '{pool_name}' nodeCount to {target_node_count}")

    logger.info(
        f"Patching HumioCluster '{humiocluster_name}': "
        f"spec.nodeCount + {len(node_pools)} pool(s) to {target_node_count}"
    )

    custom_api.api_client.default_headers['Content-Type'] = 'application/json-patch+json'
    custom_api.patch_namespaced_custom_object(
        group="core.humio.com",
        version="v1alpha1",
        namespace=namespace,
        plural="humioclusters",
        name=humiocluster_name,
        body=patch_ops,
    )
    custom_api.api_client.default_headers['Content-Type'] = 'application/json'
    logger.info(f"Successfully patched all HumioCluster nodeCount values to {target_node_count}")
    return True


@retry_with_backoff(operation_name="cleanup_tls_secret")
def _cleanup_stale_tls_secret(core_v1, namespace, humiocluster_name):
    """
    Delete stale TLS secret before scaling operator to prevent CA certificate mismatch.

    In DR standby deployments, when the operator is scaled to 0 and later scaled back up,
    the CA keypair may be regenerated but the cluster TLS secret ({humiocluster_name})
    retains the old CA. This causes TLS verification failures when the operator tries
    to communicate with LogScale pods.

    Deleting the TLS secret allows cert-manager to recreate it with the correct CA
    from the current CA keypair.

    See: humio-operator/internal/helpers/clusterinterface.go line 213

    Retryable errors: 429, 500, 502, 503, 504, connection errors
    Non-retryable: 404 is handled gracefully (secret doesn't exist)
    """
    if not humiocluster_name:
        logger.info("HUMIOCLUSTER_NAME not set; skipping TLS secret cleanup")
        return True

    secret_name = humiocluster_name

    try:
        core_v1.read_namespaced_secret(name=secret_name, namespace=namespace)
        logger.info(f"Found TLS secret '{secret_name}' in namespace '{namespace}'")

        core_v1.delete_namespaced_secret(name=secret_name, namespace=namespace)
        logger.info(f"Deleted stale TLS secret '{secret_name}' to prevent CA mismatch")
        logger.info("  cert-manager will recreate the secret with the current CA")
        return True

    except ApiException as e:
        if e.status == 404:
            logger.info(f"TLS secret '{secret_name}' not found; nothing to cleanup")
            return True
        # Re-raise for retry logic to handle
        raise


# =============================================================================
# Pre-Failover Cleanup (Kafka + GCS)
# =============================================================================

def _cleanup_gcs_snapshots(bucket_name):
    """
    Delete stale global snapshots and dataspaces from the standby's GCS bucket.

    LogScale DR recovery loads a snapshot from the primary's bucket that contains
    Kafka epoch/offset state from the primary's Kafka cluster. If stale local
    snapshots exist in the standby bucket, LogScale may load those instead and
    crash with OffsetOutOfRangeException or Kafka epoch mismatch.

    Removing all local state forces LogScale to do a clean DR recovery from the
    primary bucket and start at Kafka offset 0.
    """
    if not bucket_name:
        logger.info("GCS_BUCKET_NAME not configured; skipping GCS cleanup")
        return True

    try:
        client = gcs_storage.Client()
        bucket = client.bucket(bucket_name)

        prefixes_to_clean = ["globalsnapshots/", "dataspace_"]
        total_deleted = 0

        for prefix in prefixes_to_clean:
            blobs = list(bucket.list_blobs(prefix=prefix))
            if blobs:
                logger.info(f"Deleting {len(blobs)} objects with prefix '{prefix}' from gs://{bucket_name}")
                bucket.delete_blobs(blobs)
                total_deleted += len(blobs)

        logger.info(f"GCS cleanup complete: deleted {total_deleted} objects from gs://{bucket_name}")
        return True

    except Exception as e:
        logger.error(f"GCS cleanup failed: {e}")
        return False


@retry_with_backoff(operation_name="cleanup_kafka_topics")
def _cleanup_kafka_topics(api_client, namespace):
    """
    Delete all Kafka topics on the standby cluster via exec into a Kafka broker pod.

    LogScale's DR recovery loads a snapshot from the primary that references the
    primary's Kafka offsets. If standby Kafka has stale topics with different
    epoch/offsets, LogScale crashes with:
    - OffsetOutOfRangeException (offset mismatch)
    - Kafka epoch key changed (cluster ID mismatch)

    Deleting all topics ensures LogScale boots against empty Kafka, which is the
    expected state for allowKafkaReset=true to succeed.
    """
    if not KAFKA_BOOTSTRAP_SERVER:
        logger.info("KAFKA_BOOTSTRAP_SERVER not configured; skipping Kafka cleanup")
        return True

    core_v1 = k8s_client.CoreV1Api(api_client)

    # Find a running Kafka broker pod
    pods = core_v1.list_namespaced_pod(
        namespace=namespace,
        label_selector="strimzi.io/kind=Kafka,strimzi.io/name"
    )

    kafka_pod = None
    for pod in pods.items:
        if pod.status.phase == "Running":
            kafka_pod = pod.metadata.name
            break

    if not kafka_pod:
        logger.warning("No running Kafka broker pod found; skipping Kafka cleanup")
        return True

    logger.info(f"Using Kafka broker pod '{kafka_pod}' for topic cleanup")

    # List all topics
    from kubernetes.stream import stream
    list_cmd = [
        '/opt/kafka/bin/kafka-topics.sh',
        '--bootstrap-server', 'localhost:9093',
        '--command-config', '/tmp/strimzi.properties',
        '--list'
    ]

    try:
        resp = stream(
            core_v1.connect_get_namespaced_pod_exec,
            kafka_pod,
            namespace,
            command=list_cmd,
            stderr=True, stdin=False, stdout=True, tty=False
        )
        topics = [t.strip() for t in resp.strip().split('\n') if t.strip() and not t.startswith('__')]
    except Exception as e:
        logger.warning(f"Failed to list Kafka topics: {e}")
        return True

    if not topics:
        logger.info("No user topics found in Kafka; nothing to delete")
        return True

    logger.info(f"Deleting {len(topics)} Kafka topics: {topics}")

    for topic in topics:
        delete_cmd = [
            '/opt/kafka/bin/kafka-topics.sh',
            '--bootstrap-server', 'localhost:9093',
            '--command-config', '/tmp/strimzi.properties',
            '--delete', '--topic', topic
        ]
        try:
            stream(
                core_v1.connect_get_namespaced_pod_exec,
                kafka_pod,
                namespace,
                command=delete_cmd,
                stderr=True, stdin=False, stdout=True, tty=False
            )
            logger.info(f"Deleted Kafka topic: {topic}")
        except Exception as e:
            logger.warning(f"Failed to delete topic '{topic}': {e}")

    logger.info("Kafka topic cleanup complete")
    return True


@retry_with_backoff(operation_name="rotate_kafka_topic_prefix")
def _rotate_kafka_topic_prefix(api_client, namespace, humiocluster_name):
    """
    Rotate HUMIO_KAFKA_TOPIC_PREFIX on the HumioCluster CR to bypass epoch mismatch.

    Per-cluster Strimzi Kafka means each cluster has a different Kafka cluster ID.
    When LogScale loads the primary's GCS snapshot during DR recovery, the snapshot
    contains the primary's Kafka epoch (cluster ID). The standby's Kafka has a
    different cluster ID, triggering an epoch mismatch check.

    allowKafkaReset=true should handle this, but LogScale's TransientChatter thread
    writes ~848 messages to global-events during bootstrap BEFORE the epoch check
    runs. The check requires 0 messages -> always fails.

    Workaround: assign a new unique HUMIO_KAFKA_TOPIC_PREFIX. LogScale creates
    brand-new topics for the new prefix. No epoch history exists for these topics,
    so no mismatch is detected. Recovery proceeds normally.
    """
    if not humiocluster_name:
        logger.info("HUMIOCLUSTER_NAME not set; skipping topic prefix rotation")
        return True

    custom_api = k8s_client.CustomObjectsApi(api_client)

    cr = custom_api.get_namespaced_custom_object(
        group="core.humio.com",
        version="v1alpha1",
        namespace=namespace,
        plural="humioclusters",
        name=humiocluster_name,
    )

    new_prefix = f"humio-dr-{int(time.time())}"
    logger.info(f"Rotating HUMIO_KAFKA_TOPIC_PREFIX to '{new_prefix}'")

    env_vars = cr.get("spec", {}).get("commonEnvironmentVariables", [])
    prefix_found = False
    for i, env in enumerate(env_vars):
        if env.get("name") == "HUMIO_KAFKA_TOPIC_PREFIX":
            env_vars[i]["value"] = new_prefix
            prefix_found = True
            break

    if not prefix_found:
        env_vars.append({"name": "HUMIO_KAFKA_TOPIC_PREFIX", "value": new_prefix})

    patch_body = {"spec": {"commonEnvironmentVariables": env_vars}}

    custom_api.patch_namespaced_custom_object(
        group="core.humio.com",
        version="v1alpha1",
        namespace=namespace,
        plural="humioclusters",
        name=humiocluster_name,
        body=patch_body,
    )

    logger.info(f"Successfully rotated HUMIO_KAFKA_TOPIC_PREFIX to '{new_prefix}'")
    return True


# =============================================================================
# Pre-Failover Validation Functions
# =============================================================================

def _check_cooldown_period() -> bool:
    """
    Check if we're still within the cooldown period from a previous failover.

    Returns:
        True if cooldown has passed (OK to proceed), False if still in cooldown
    """
    global _last_failover_time

    if FAILOVER_COOLDOWN_SECONDS <= 0:
        return True

    current_time = time.time()
    time_since_last = current_time - _last_failover_time

    if _last_failover_time > 0 and time_since_last < FAILOVER_COOLDOWN_SECONDS:
        logger.warning(
            f"Failover cooldown active: {int(time_since_last)}s since last failover, "
            f"cooldown is {FAILOVER_COOLDOWN_SECONDS}s. Skipping."
        )
        return False

    return True


def _query_uptime_check_results(uptime_check_id: str, lookback_seconds: int) -> dict:
    """
    Query Cloud Monitoring for recent uptime check results.

    Args:
        uptime_check_id: The uptime check configuration ID
        lookback_seconds: How far back to look for results

    Returns:
        dict with 'passed', 'failed', 'total' counts and 'consecutive_failure_seconds'
    """
    from google.cloud import monitoring_v3
    from google.protobuf import timestamp_pb2

    credentials, _ = default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
    metrics_client = monitoring_v3.MetricServiceClient(credentials=credentials)

    now = time.time()
    end_time = timestamp_pb2.Timestamp()
    end_time.FromSeconds(int(now))
    start_time = timestamp_pb2.Timestamp()
    start_time.FromSeconds(int(now - lookback_seconds))

    interval = monitoring_v3.TimeInterval({
        "end_time": end_time,
        "start_time": start_time,
    })

    # Query the uptime check passed metric
    filter_str = (
        f'metric.type="monitoring.googleapis.com/uptime_check/check_passed" '
        f'AND metric.labels.check_id="{uptime_check_id}"'
    )

    results = {"passed": 0, "failed": 0, "total": 0, "consecutive_failure_seconds": 0}

    try:
        request = monitoring_v3.ListTimeSeriesRequest(
            name=f"projects/{PROJECT_ID}",
            filter=filter_str,
            interval=interval,
            view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL,
        )

        # Collect all datapoints with timestamps
        datapoints = []
        for series in metrics_client.list_time_series(request=request):
            for point in series.points:
                results["total"] += 1
                timestamp = int(point.interval.end_time.timestamp())
                passed = point.value.bool_value
                datapoints.append((timestamp, passed))
                if passed:
                    results["passed"] += 1
                else:
                    results["failed"] += 1

        # Calculate consecutive failure seconds from most recent datapoint
        if datapoints:
            # Sort by timestamp descending (most recent first)
            datapoints.sort(key=lambda x: x[0], reverse=True)

            # Find how long the health check has been failing
            most_recent_time = datapoints[0][0]
            failure_start_time = most_recent_time

            for timestamp, passed in datapoints:
                if passed:
                    # Found a passing check, stop counting
                    break
                failure_start_time = timestamp

            # Calculate consecutive failure duration
            if not datapoints[0][1]:  # Most recent check failed
                results["consecutive_failure_seconds"] = int(most_recent_time - failure_start_time)

    except Exception as e:
        logger.warning(f"Error querying uptime check metrics: {e}")
        # Return empty results on error - caller decides how to handle

    return results


def _check_primary_still_unhealthy() -> bool:
    """
    Check if the primary cluster is still unhealthy before proceeding with failover.

    This function ALWAYS performs pre-failover validation to prevent the Cloud Function
    from scaling the secondary operator when the primary is healthy (e.g., during failback).

    Validation steps:
    1. Checks if validation is explicitly skipped (SKIP_PRIMARY_HEALTH_VALIDATION=true)
    2. Checks if uptime check ID is configured
    3. Queries Cloud Monitoring for recent uptime check results
    4. Verifies failures have persisted for the required duration

    Returns:
        True if primary is unhealthy (proceed with failover)
        False if primary appears healthy (skip failover)
    """
    # Check if validation is disabled via skip flag - this is the only way to bypass
    if SKIP_PRIMARY_HEALTH_VALIDATION:
        logger.info("Skipping primary health validation (SKIP_PRIMARY_HEALTH_VALIDATION=true)")
        return True

    # Check if uptime check ID is configured
    if not PRIMARY_UPTIME_CHECK_ID:
        logger.info("No PRIMARY_UPTIME_CHECK_ID configured; proceeding without primary health gate")
        return True

    try:
        # Use a lookback window that's longer than the required failure duration
        lookback_seconds = max(PRE_FAILOVER_FAILURE_SECONDS * 2, 300)

        logger.info(
            f"Querying primary uptime check {PRIMARY_UPTIME_CHECK_ID} "
            f"(lookback={lookback_seconds}s, required_failure_seconds={PRE_FAILOVER_FAILURE_SECONDS})"
        )

        # Query recent uptime check results
        results = _query_uptime_check_results(PRIMARY_UPTIME_CHECK_ID, lookback_seconds)

        logger.info(
            f"Uptime check results: passed={results['passed']}, failed={results['failed']}, "
            f"total={results['total']}, consecutive_failure_seconds={results['consecutive_failure_seconds']}"
        )

        # If we got no results, proceed with failover (fail-open)
        if results["total"] == 0:
            logger.warning("No uptime check results found; proceeding with failover (fail-open)")
            return True

        # Check if primary has recent passed checks - prevents failover during failback
        if results["passed"] > 0 and results["consecutive_failure_seconds"] == 0:
            logger.info("Primary has recent passed checks; may be recovering. Skipping failover.")
            return False

        # Check if failures have persisted for the required duration
        if results["consecutive_failure_seconds"] < PRE_FAILOVER_FAILURE_SECONDS:
            logger.info(
                f"Primary has been failing for {results['consecutive_failure_seconds']}s "
                f"(need {PRE_FAILOVER_FAILURE_SECONDS}s); waiting for more confirmation"
            )
            return False

        # Primary is confirmed unhealthy for the required duration
        logger.info(
            f"Primary confirmed unhealthy: failing for {results['consecutive_failure_seconds']}s "
            f"(>= {PRE_FAILOVER_FAILURE_SECONDS}s required). Proceeding with failover."
        )
        return True

    except Exception as e:
        logger.warning(f"Failed to check primary health status: {str(e)}; proceeding with failover (fail-open)")
        return True


@retry_with_backoff(operation_name="check_secondary_cluster_health")
def check_secondary_cluster_health(project_id, cluster_name, cluster_location):
    """
    Check if the secondary GKE cluster is healthy before attempting failover.

    Retryable errors: Connection errors, transient GKE API failures
    """
    credentials, _ = default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
    client = container_v1.ClusterManagerClient(credentials=credentials)
    name = f"projects/{project_id}/locations/{cluster_location}/clusters/{cluster_name}"

    cluster = client.get_cluster(name=name)

    if cluster.status == container_v1.Cluster.Status.RUNNING:
        logger.info(f"Secondary cluster {cluster_name} is healthy (RUNNING)")
        return True
    else:
        logger.error(f"Secondary cluster {cluster_name} status: {cluster.status.name}")
        return False


# =============================================================================
# GLB Backend Capacity Management
# =============================================================================

GLB_BACKEND_SERVICE_NAME = os.environ.get('GLB_BACKEND_SERVICE_NAME', '')
GLB_PROJECT_ID = os.environ.get('GLB_PROJECT_ID', '')
SECONDARY_INSTANCE_GROUPS = json.loads(os.environ.get('SECONDARY_INSTANCE_GROUPS', '[]'))


@retry_with_backoff(operation_name="flip_glb_capacity")
def _flip_glb_capacity():
    """
    Flip GLB capacity: secondary → 1.0, primary → 0.0.

    Backends are pre-registered by Terraform. This function only changes
    capacity_scaler values to redirect traffic during failover.
    """
    if not GLB_BACKEND_SERVICE_NAME:
        logger.info("No GLB_BACKEND_SERVICE_NAME configured; skipping capacity flip")
        return True

    if not SECONDARY_INSTANCE_GROUPS:
        logger.info("No SECONDARY_INSTANCE_GROUPS configured; skipping capacity flip")
        return True

    from google.cloud import compute_v1

    project = GLB_PROJECT_ID or PROJECT_ID
    client = compute_v1.BackendServicesClient()

    backend_service = client.get(project=project, backend_service=GLB_BACKEND_SERVICE_NAME)

    secondary_set = set(SECONDARY_INSTANCE_GROUPS)
    changed = False

    for backend in backend_service.backends:
        if backend.group in secondary_set:
            if backend.capacity_scaler != 1.0:
                backend.capacity_scaler = 1.0
                changed = True
                logger.info(f"Setting secondary backend capacity → 1.0: {backend.group}")
        else:
            if backend.capacity_scaler != 0.0:
                backend.capacity_scaler = 0.0
                changed = True
                logger.info(f"Setting primary backend capacity → 0.0: {backend.group}")

    if not changed:
        logger.info("GLB capacity already correct (secondary=1.0, primary=0.0)")
        return True

    operation = client.update(
        project=project,
        backend_service=GLB_BACKEND_SERVICE_NAME,
        backend_service_resource=backend_service,
    )

    ops_client = compute_v1.GlobalOperationsClient()
    ops_client.wait(project=project, operation=operation.name)

    logger.info("GLB capacity flip complete: traffic now routes to secondary")
    return True


# =============================================================================
# Core Failover Logic
# =============================================================================

def scale_humio_operator(project_id, cluster_name, cluster_location, namespace):
    """
    Scale the Humio operator and patch HumioCluster CR to trigger DR failover.

    Steps:
    1. Get GKE credentials (with retry)
    2. Check current operator replica count (with retry)
    3. Cleanup stale TLS secret (with retry)
    4. Scale operator to target replicas (with retry)
    5. Patch HumioCluster CR nodeCount to enable pod creation (with retry)
    """
    try:
        logger.info(f"FAILOVER THRESHOLD REACHED - Scaling Humio operator from 0 -> {TARGET_OPERATOR_REPLICAS}")

        # Step 1: Get GKE credentials (with retry)
        api_client, credentials = _get_gke_credentials()

        apps_v1 = k8s_client.AppsV1Api(api_client)
        core_v1 = k8s_client.CoreV1Api(api_client)

        # Step 2: Get current replicas (with retry)
        current_replicas = _get_current_operator_replicas(apps_v1, namespace)

        if current_replicas >= TARGET_OPERATOR_REPLICAS:
            logger.info(
                f"humio-operator already has {current_replicas} replica(s) >= "
                f"target {TARGET_OPERATOR_REPLICAS}; skipping operator scale"
            )
        else:
            # Step 3: Cleanup stale TLS secret (with retry)
            _cleanup_stale_tls_secret(core_v1, namespace, HUMIOCLUSTER_NAME)

            # Refresh token if needed before patching
            api_client = _refresh_token_if_needed(api_client, credentials)
            apps_v1 = k8s_client.AppsV1Api(api_client)

            # Step 4: Scale operator to target replicas (with retry)
            _patch_operator_replicas(apps_v1, namespace, TARGET_OPERATOR_REPLICAS)

        # Step 5: Patch HumioCluster CR nodeCount (always — idempotent)
        api_client = _refresh_token_if_needed(api_client, credentials)
        _patch_humiocluster_node_count(api_client, namespace, HUMIOCLUSTER_NAME, TARGET_NODE_COUNT)

        return True

    except Exception as e:
        logger.error(f"Failed to scale Humio operator: {str(e)}")
        return False


def wait_for_logscale_ready(project_id, cluster_name, cluster_location, namespace, target_node_count, timeout=300):
    """
    Wait for LogScale pod to become ready and verify initialization.
    Checks Kubernetes pod status using the API.
    """
    try:
        logger.info(f"Waiting for LogScale pod to become ready (max {timeout}s)...")

        api_client, credentials = _get_gke_credentials()
        core_v1 = k8s_client.CoreV1Api(api_client)

        start_time = time.time()
        check_interval = 10
        label_selector = "app.kubernetes.io/name=humio,app.kubernetes.io/managed-by=humio-operator"

        while time.time() - start_time < timeout:
            elapsed = int(time.time() - start_time)

            try:
                api_client = _refresh_token_if_needed(api_client, credentials)
                core_v1 = k8s_client.CoreV1Api(api_client)

                pods = core_v1.list_namespaced_pod(
                    namespace=namespace,
                    label_selector=label_selector
                )

                if not pods.items:
                    logger.info(f"No LogScale pods found yet (elapsed: {elapsed}/{timeout}s)")
                    time.sleep(check_interval)
                    continue

                ready_pods = 0
                for pod in pods.items:
                    pod_name = pod.metadata.name
                    pod_phase = pod.status.phase

                    is_ready = False
                    if pod.status.conditions:
                        for condition in pod.status.conditions:
                            if condition.type == "Ready" and condition.status == "True":
                                is_ready = True
                                break

                    if is_ready:
                        ready_pods += 1
                        logger.info(f"Pod {pod_name} is Ready")
                    else:
                        logger.info(f"Pod {pod_name} phase={pod_phase}, ready={is_ready}")

                if ready_pods >= target_node_count:
                    logger.info(f"{ready_pods} LogScale pod(s) are Ready (target: {target_node_count})")
                    logger.info("LogScale DR failover complete - pods are ready to serve traffic")
                    return True

            except ApiException as e:
                logger.warning(f"Error checking pod status: {e.status} - {e.reason}")
                if e.status == 401:
                    api_client, credentials = _get_gke_credentials()
                    core_v1 = k8s_client.CoreV1Api(api_client)

            time.sleep(check_interval)

        logger.error(f"Timeout reached ({timeout}s) - Pod not ready")
        logger.error("Troubleshooting commands:")
        logger.error(f"  kubectl get pods -n {namespace} -l {label_selector}")
        logger.error(f"  kubectl describe pod -n {namespace} -l {label_selector}")
        logger.error(f"  kubectl logs -n {namespace} -l {label_selector}")

        return False

    except Exception as e:
        logger.error(f"Error waiting for LogScale readiness: {str(e)}")
        return False


def _handle_failover():
    """
    Main failover logic with pre-checks and validation.
    Returns a dict with action taken and result.
    """
    global _last_failover_time
    _reset_retry_stats()

    # Step 0: Check cooldown period
    if not _check_cooldown_period():
        return {
            "action": "skipped",
            "reason": "cooldown_active",
            "retry_stats": _get_retry_stats_dict()
        }

    # Step 1: Check if primary is still unhealthy
    if not _check_primary_still_unhealthy():
        logger.info("Primary appears to have recovered; skipping operator scale-up")
        return {
            "action": "skipped",
            "reason": "primary_healthy",
            "retry_stats": _get_retry_stats_dict()
        }

    # Step 2: Check secondary cluster health (with retry)
    try:
        if not check_secondary_cluster_health(PROJECT_ID, CLUSTER_NAME, CLUSTER_LOCATION):
            logger.error("Secondary cluster is not healthy; aborting failover")
            return {
                "action": "skipped",
                "reason": "secondary_unhealthy",
                "retry_stats": _get_retry_stats_dict()
            }
    except Exception as e:
        logger.error(f"Failed to check secondary cluster health: {str(e)}")
        return {
            "action": "failed",
            "reason": f"secondary_health_check_failed: {str(e)}",
            "retry_stats": _get_retry_stats_dict()
        }

    # Step 3: Flip GLB capacity (secondary=1.0, primary=0.0)
    try:
        _flip_glb_capacity()
    except Exception as e:
        logger.warning(f"GLB capacity flip failed: {e}; continuing with operator scale")

    # Step 4: Pre-failover cleanup (Kafka topics + GCS snapshots)
    # Required to prevent Kafka epoch mismatch and OffsetOutOfRangeException.
    # The standby's local Kafka has different epoch/offsets than the primary's
    # snapshot expects. Wiping both ensures a clean DR boot.
    api_client = None
    try:
        logger.info("Starting pre-failover cleanup (Kafka topics + GCS snapshots)")
        api_client, credentials = _get_gke_credentials()
        _cleanup_kafka_topics(api_client, NAMESPACE)
        _cleanup_gcs_snapshots(GCS_BUCKET_NAME)
        logger.info("Pre-failover cleanup complete")
    except Exception as e:
        logger.warning(f"Pre-failover cleanup failed: {e}; continuing with operator scale")

    # Step 4b: Rotate HUMIO_KAFKA_TOPIC_PREFIX to prevent epoch mismatch
    # Per-cluster Kafka means different cluster IDs. LogScale loads the primary's
    # snapshot which contains primary's Kafka epoch. allowKafkaReset requires an
    # empty global-events topic, but LogScale writes 848 msgs during bootstrap
    # BEFORE the check runs. A new prefix forces fresh topics with no epoch history.
    try:
        if not api_client:
            api_client, credentials = _get_gke_credentials()
        _rotate_kafka_topic_prefix(api_client, NAMESPACE, HUMIOCLUSTER_NAME)
    except Exception as e:
        logger.warning(f"Kafka topic prefix rotation failed: {e}; continuing with operator scale")

    # Step 5: Scale the Humio operator
    success = scale_humio_operator(PROJECT_ID, CLUSTER_NAME, CLUSTER_LOCATION, NAMESPACE)

    if not success:
        return {
            "action": "failed",
            "reason": "scale_failed",
            "retry_stats": _get_retry_stats_dict()
        }

    # Update last failover time for cooldown tracking
    _last_failover_time = time.time()

    return {
        "action": "scaled",
        "target_replicas": TARGET_OPERATOR_REPLICAS,
        "retry_stats": _get_retry_stats_dict()
    }


# =============================================================================
# Cloud Function Entry Point
# =============================================================================

@functions_framework.cloud_event
def failover_handler(cloud_event: CloudEvent):
    """
    Cloud Function handler for LogScale DR failover automation.
    Triggered by Pub/Sub messages from monitoring alerts.
    """
    try:
        logger.info(f"DR Failover triggered for cluster {CLUSTER_NAME} in {CLUSTER_LOCATION}")
        logger.info(f"Project: {PROJECT_ID}, Namespace: {NAMESPACE}")
        logger.info(
            f"Retry config: max_retries={MAX_RETRIES}, "
            f"base_delay={BASE_DELAY_SECONDS}s, max_delay={MAX_DELAY_SECONDS}s"
        )

        pubsub_message = cloud_event.data
        message_data = None
        alert_state = None

        if 'message' in pubsub_message:
            try:
                raw_data = pubsub_message['message'].get('data', '')
                if raw_data:
                    message_data = base64.b64decode(raw_data).decode('utf-8')
                    alert_data = json.loads(message_data)
                    logger.info(f"Alert data: {json.dumps(alert_data, indent=2)}")

                    alert_state = alert_data.get('incident', {}).get('state', '')
                    if alert_state and alert_state.lower() != 'open':
                        logger.info(f"Alert state is '{alert_state}', not 'open'; skipping failover")
                        return {"status": "ignored", "reason": f"alert_state={alert_state}"}
            except (json.JSONDecodeError, KeyError) as e:
                logger.warning(f"Could not parse Pub/Sub message: {e}; proceeding with failover")

        result = _handle_failover()
        logger.info(f"Failover handler result: {json.dumps(result)}")

        if result.get("action") == "scaled":
            timeout = int(os.environ.get('POD_READY_TIMEOUT', '300'))

            if wait_for_logscale_ready(PROJECT_ID, CLUSTER_NAME, CLUSTER_LOCATION, NAMESPACE, TARGET_NODE_COUNT, timeout):
                logger.info("FAILOVER COMPLETE - LogScale pod is ready to serve traffic")
                return {
                    "status": "success",
                    "message": "DR failover completed successfully",
                    "result": result
                }
            else:
                logger.warning("FAILOVER PARTIAL - Operator scaled but pod readiness not confirmed")
                return {
                    "status": "warning",
                    "message": "Operator scaled but pod not ready within timeout",
                    "result": result
                }

        elif result.get("action") == "skipped":
            return {"status": "skipped", "reason": result.get("reason"), "result": result}

        else:
            logger.error("FAILOVER FAILED")
            return {"status": "error", "message": "Failed to scale Humio operator", "result": result}

    except Exception as e:
        logger.error(f"FAILOVER ERROR - Exception occurred: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        # Log retry stats even on failure
        logger.error(f"Retry stats at failure: {json.dumps(_get_retry_stats_dict())}")
        return {"status": "error", "message": f"Exception: {str(e)}", "retry_stats": _get_retry_stats_dict()}
