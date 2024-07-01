${jsonencode(
{
    // This template specifies the available paramaters for the different sizes of LogScale clusters
    "xsmall": {
        "logscale_digest_node_count": 3,
        "logscale_digest_machine_type": "n2-standard-8",
        "logscale_digest_local_ssd_count": 8,
        "logscale_digest_root_disk_size": 128,
        "logscale_digest_root_disk_type": "pd-ssd",
        "logscale_digest_data_disk_size": "3000Gi",
        "logscale_digest_min_node_count": 1,
        "logscale_digest_max_node_count": 3,
        "logscale_digest_resources": {"limits": {"cpu": 7, "memory": "30Gi"}, "requests": {"cpu": 7, "memory": "30Gi"}},
        "logscale_ingress_node_count": 3,
        "logscale_ingress_machine_type": "n2-standard-8",
        "logscale_ingress_root_disk_size": 128,
        "logscale_ingress_root_disk_type": "pd-ssd",
        "logscale_ingress_data_disk_size": "128Gi",
        "logscale_ingress_min_node_count": 1,
        "logscale_ingress_max_node_count": 3,
        "logscale_ingress_resources": {"limits": {"cpu": 7, "memory": "12Gi"}, "requests": {"cpu": 7, "memory": "12Gi"}},
        "logscale_ingest_node_count": 3,
        "logscale_ingest_machine_type": "e2-standard-4",
        "logscale_ingest_root_disk_size": 128,
        "logscale_ingest_root_disk_type": "pd-ssd",
        "logscale_ingest_data_disk_size": "128Gi",
        "logscale_ingest_min_node_count": 1,
        "logscale_ingest_max_node_count": 3,
        "logscale_ingest_resources": {"limits": {"cpu": 3, "memory": "12Gi"}, "requests": {"cpu": 3, "memory": "12Gi"}},
        "logscale_ui_node_count": 3,
        "logscale_ui_machine_type": "e2-standard-4",
        "logscale_ui_root_disk_size": 128,
        "logscale_ui_root_disk_type": "pd-ssd",
        "logscale_ui_data_disk_size": "128Gi",
        "logscale_ui_min_node_count": 1,
        "logscale_ui_max_node_count": 3,
        "logscale_ui_resources": {"limits": {"cpu": 3, "memory": "12Gi"}, "requests": {"cpu": 3, "memory": "12Gi"}},
        "kafka_broker_node_count": 3,
        "kafka_broker_machine_type": "e2-standard-4",
        "kafka_broker_min_node_count": 1,
        "kafka_broker_max_node_count": 3,
        "kafka_broker_root_disk_size": 128,
        "kafka_broker_root_disk_type": "pd-ssd",
        "kafka_broker_data_disk_size": "152Gi",
        "kafka_broker_resources": {"limits": {"cpu": 3, "memory": "12Gi"}, "requests": {"cpu": 3, "memory": "12Gi"}},
        "zookeeper_machine_type": "e2-standard-4",
        "zookeeper_node_count": 3,
        "zookeeper_min_node_count": 1,
        "zookeeper_max_node_count": 3,
        "zookeeper_root_disk_size": 64,
        "zookeeper_root_disk_type": "pd-ssd",
        "zookeeper_data_disk_size": "64Gi",
        "zookeeper_resources": {"limits": {"cpu": 3, "memory": "8Gi"}, "requests": {"cpu": 1, "memory": "8Gi"}},
    },
    "small": {
        "logscale_digest_node_count": 9,
        "logscale_digest_machine_type": "n2-standard-8",
        "logscale_digest_local_ssd_count": 16,
        "logscale_digest_root_disk_size": 128,
        "logscale_digest_root_disk_type": "pd-ssd",
        "logscale_digest_data_disk_size": "5800Gi",
        "logscale_digest_min_node_count": 3,
        "logscale_digest_max_node_count": 6,
        "logscale_digest_resources": {"limits": {"cpu": 7, "memory": "28Gi"}, "requests": {"cpu": 7, "memory": "28Gi"}},
        "logscale_ingress_node_count": 6,
        "logscale_ingress_machine_type": "e2-standard-4",
        "logscale_ingress_root_disk_size": 128,
        "logscale_ingress_root_disk_type": "pd-ssd",
        "logscale_ingress_data_disk_size": "128Gi",
        "logscale_ingress_min_node_count": 2,
        "logscale_ingress_max_node_count": 4,
        "logscale_ingress_resources": {"limits": {"cpu": 3, "memory": "12Gi"}, "requests": {"cpu": 3, "memory": "12Gi"}},
        "logscale_ingest_node_count": 3,
        "logscale_ingest_machine_type": "e2-standard-4",
        "logscale_ingest_root_disk_size": 128,
        "logscale_ingest_root_disk_type": "pd-ssd",
        "logscale_ingest_data_disk_size": "128Gi",
        "logscale_ingest_min_node_count": 1,
        "logscale_ingest_max_node_count": 3,
        "logscale_ingest_resources": {"limits": {"cpu": 3, "memory": "12Gi"}, "requests": {"cpu": 3, "memory": "12Gi"}},
        "logscale_ui_node_count": 3,
        "logscale_ui_machine_type": "e2-standard-4",
        "logscale_ui_root_disk_size": 128,
        "logscale_ui_root_disk_type": "pd-ssd",
        "logscale_ui_data_disk_size": "128Gi",
        "logscale_ui_min_node_count": 1,
        "logscale_ui_max_node_count": 3,
        "logscale_ui_resources": {"limits": {"cpu": 3, "memory": "12Gi"}, "requests": {"cpu": 3, "memory": "12Gi"}},
        "kafka_broker_node_count": 6,
        "kafka_broker_machine_type": "e2-standard-4",
        "kafka_broker_min_node_count": 2,
        "kafka_broker_max_node_count": 4,
        "kafka_broker_root_disk_size": 128,
        "kafka_broker_root_disk_type": "pd-ssd",
        "kafka_broker_data_disk_size": "376Gi",
        "kafka_broker_resources": {"limits": {"cpu": 3, "memory": "10Gi"}, "requests": {"cpu": 3, "memory": "10Gi"}},
        "zookeeper_machine_type": "e2-standard-4",
        "zookeeper_node_count": 3,
        "zookeeper_min_node_count": 1,
        "zookeeper_max_node_count": 3,
        "zookeeper_root_disk_size": 64,
        "zookeeper_root_disk_type": "pd-ssd",
        "zookeeper_data_disk_size": "64Gi",
        "zookeeper_resources": {"limits": {"cpu": 3, "memory": "8Gi"}, "requests": {"cpu": 1, "memory": "8Gi"}},
    },
    "medium": {
        "logscale_digest_node_count": 21,
        "logscale_digest_machine_type": "n2-standard-32",
        "logscale_digest_local_ssd_count": 32,
        "logscale_digest_root_disk_size": 128,
        "logscale_digest_root_disk_type": "pd-ssd",
        "logscale_digest_data_disk_size": "11500Gi",
        "logscale_digest_min_node_count": 7,
        "logscale_digest_max_node_count": 9,
        "logscale_digest_resources": {"limits": {"cpu": 30, "memory": "120Gi"}, "requests": {"cpu": 30, "memory": "120Gi"}},
        "logscale_ingress_node_count": 12,
        "logscale_ingress_machine_type": "n2-standard-8",
        "logscale_ingress_root_disk_size": 200,
        "logscale_ingress_root_disk_type": "pd-ssd",
        "logscale_ingress_data_disk_size": "128Gi",
        "logscale_ingress_min_node_count": 4,
        "logscale_ingress_max_node_count": 6,
        "logscale_ingress_resources": {"limits": {"cpu": 7, "memory": "30Gi"}, "requests": {"cpu": 7, "memory": "30Gi"}},
        "logscale_ingest_node_count": 6,
        "logscale_ingest_machine_type": "n2-standard-8",
        "logscale_ingest_root_disk_size": 200,
        "logscale_ingest_root_disk_type": "pd-ssd",
        "logscale_ingest_data_disk_size": "128Gi",
        "logscale_ingest_min_node_count": 2,
        "logscale_ingest_max_node_count": 4,
        "logscale_ingest_resources": {"limits": {"cpu": 7, "memory": "30Gi"}, "requests": {"cpu": 7, "memory": "30Gi"}},
        "logscale_ui_node_count": 6,
        "logscale_ui_machine_type": "n2-standard-8",
        "logscale_ui_root_disk_size": 200,
        "logscale_ui_root_disk_type": "pd-ssd",
        "logscale_ui_data_disk_size": "128Gi",
        "logscale_ui_min_node_count": 2,
        "logscale_ui_max_node_count": 4,
        "logscale_ui_resources": {"limits": {"cpu": 7, "memory": "30Gi"}, "requests": {"cpu": 7, "memory": "30Gi"}},
        "kafka_broker_node_count": 9,
        "kafka_broker_machine_type": "n2-standard-8",
        "kafka_broker_min_node_count": 3,
        "kafka_broker_max_node_count": 9,
        "kafka_broker_root_disk_size": 200,
        "kafka_broker_root_disk_type": "pd-ssd",
        "kafka_broker_data_disk_size": "1252Gi",
        "kafka_broker_resources": {"limits": {"cpu": 7, "memory": "30Gi"}, "requests": {"cpu": 7, "memory": "30Gi"}},
        "zookeeper_machine_type": "e2-standard-4",
        "zookeeper_node_count": 3,
        "zookeeper_min_node_count": 1,
        "zookeeper_max_node_count": 3,
        "zookeeper_root_disk_size": 64,
        "zookeeper_root_disk_type": "pd-ssd",
        "zookeeper_data_disk_size": "64Gi",
        "zookeeper_resources": {"limits": {"cpu": 3, "memory": "8Gi"}, "requests": {"cpu": 1, "memory": "8Gi"}},
    },
    "large": {
        "logscale_digest_node_count": 42,
        "logscale_digest_machine_type": "n2-standard-32",
        "logscale_digest_local_ssd_count": 32,
        "logscale_digest_root_disk_size": 128,
        "logscale_digest_root_disk_type": "pd-ssd",
        "logscale_digest_data_disk_size": "11500Gi",
        "logscale_digest_min_node_count": 14,
        "logscale_digest_max_node_count": 16,
        "logscale_digest_resources": {"limits": {"cpu": 30, "memory": "120Gi"}, "requests": {"cpu": 30, "memory": "120Gi"}},
        "logscale_ingress_node_count": 18,
        "logscale_ingress_machine_type": "n2-standard-16",
        "logscale_ingress_root_disk_size": 128,
        "logscale_ingress_root_disk_type": "pd-ssd",
        "logscale_ingress_data_disk_size": "128Gi",
        "logscale_ingress_min_node_count": 6,
        "logscale_ingress_max_node_count": 9,
        "logscale_ingress_resources": {"limits": {"cpu": 15, "memory": "60Gi"}, "requests": {"cpu": 15, "memory": "60Gi"}},
        "logscale_ingest_node_count": 9,
        "logscale_ingest_machine_type": "n2-standard-16",
        "logscale_ingest_root_disk_size": 200,
        "logscale_ingest_root_disk_type": "pd-ssd",
        "logscale_ingest_data_disk_size": "128Gi",
        "logscale_ingest_min_node_count": 3,
        "logscale_ingest_max_node_count": 6,
        "logscale_ingest_resources": {"limits": {"cpu": 15, "memory": "30Gi"}, "requests": {"cpu": 15, "memory": "60Gi"}},
        "logscale_ui_node_count": 9,
        "logscale_ui_machine_type": "n2-standard-16",
        "logscale_ui_root_disk_size": 128,
        "logscale_ui_root_disk_type": "pd-ssd",
        "logscale_ui_data_disk_size": "128Gi",
        "logscale_ui_min_node_count": 3,
        "logscale_ui_max_node_count": 6,
        "logscale_ui_resources": {"limits": {"cpu": 15, "memory": "60Gi"}, "requests": {"cpu": 7, "memory": "60Gi"}},
        "kafka_broker_node_count": 9,
        "kafka_broker_machine_type": "n2-standard-16",
        "kafka_broker_min_node_count": 3,
        "kafka_broker_max_node_count": 9,
        "kafka_broker_root_disk_size": 200,
        "kafka_broker_root_disk_type": "pd-ssd",
        "kafka_broker_data_disk_size": "2504Gi",
        "kafka_broker_resources": {"limits": {"cpu": 15, "memory": "60Gi"}, "requests": {"cpu": 15, "memory": "60Gi"}},
        "zookeeper_machine_type": "e2-standard-4",
        "zookeeper_node_count": 3,
        "zookeeper_min_node_count": 1,
        "zookeeper_max_node_count": 3,
        "zookeeper_root_disk_size": 64,
        "zookeeper_root_disk_type": "pd-ssd",
        "zookeeper_data_disk_size": "64Gi",
        "zookeeper_resources": {"limits": {"cpu": 3, "memory": "8Gi"}, "requests": {"cpu": 1, "memory": "8Gi"}},
    },
    "xlarge": {
        "logscale_digest_node_count": 78,
        "logscale_digest_machine_type": "n2-standard-48",
        "logscale_digest_local_ssd_count": 32,
        "logscale_digest_root_disk_size": 128,
        "logscale_digest_root_disk_type": "pd-ssd",
        "logscale_digest_data_disk_size": "11500Gi",
        "logscale_digest_min_node_count": 26,
        "logscale_digest_max_node_count": 28,
        "logscale_digest_resources": {"limits": {"cpu": 46, "memory": "184Gi"}, "requests": {"cpu": 46, "memory": "184Gi"}},
        "logscale_ingress_node_count": 18,
        "logscale_ingress_machine_type": "n2-standard-16",
        "logscale_ingress_root_disk_size": 128,
        "logscale_ingress_root_disk_type": "pd-ssd",
        "logscale_ingress_data_disk_size": "128Gi",
        "logscale_ingress_min_node_count": 6,
        "logscale_ingress_max_node_count": 9,
        "logscale_ingress_resources": {"limits": {"cpu": 30, "memory": "122Gi"}, "requests": {"cpu": 15, "memory": "122Gi"}},
        "logscale_ingest_node_count": 9,
        "logscale_ingest_machine_type": "n2-standard-16",
        "logscale_ingest_root_disk_size": 200,
        "logscale_ingest_root_disk_type": "pd-ssd",
        "logscale_ingest_data_disk_size": "128Gi",
        "logscale_ingest_min_node_count": 3,
        "logscale_ingest_max_node_count": 6,
        "logscale_ingest_resources": {"limits": {"cpu": 30, "memory": "122Gi"}, "requests": {"cpu": 30, "memory": "122Gi"}},
        "logscale_ui_node_count": 9,
        "logscale_ui_machine_type": "n2-standard-16",
        "logscale_ui_root_disk_size": 128,
        "logscale_ui_root_disk_type": "pd-ssd",
        "logscale_ui_data_disk_size": "128Gi",
        "logscale_ui_min_node_count": 3,
        "logscale_ui_max_node_count": 6,
        "logscale_ui_resources": {"limits": {"cpu": 30, "memory": "122Gi"}, "requests": {"cpu": 30, "memory": "122Gi"}},
        "kafka_broker_node_count": 18,
        "kafka_broker_machine_type": "n2-standard-16",
        "kafka_broker_min_node_count": 3,
        "kafka_broker_max_node_count": 9,
        "kafka_broker_root_disk_size": 200,
        "kafka_broker_root_disk_type": "pd-ssd",
        "kafka_broker_data_disk_size": "2504Gi",
        "kafka_broker_resources": {"limits": {"cpu": 15, "memory": "60Gi"}, "requests": {"cpu": 15, "memory": "60Gi"}},
        "zookeeper_machine_type": "e2-standard-4",
        "zookeeper_node_count": 2,
        "zookeeper_min_node_count": 1,
        "zookeeper_max_node_count": 3,
        "zookeeper_root_disk_size": 64,
        "zookeeper_root_disk_type": "pd-ssd",
        "zookeeper_data_disk_size": "64Gi",
        "zookeeper_resources": {"limits": {"cpu": 3, "memory": "8Gi"}, "requests": {"cpu": 1, "memory": "8Gi"}},
    },
}
)}