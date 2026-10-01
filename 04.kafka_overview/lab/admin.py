from confluent_kafka.admin import AdminClient, NewTopic

config = {
    "bootstrap.servers": "localhost:9092",
}

admin_client = AdminClient(config)

topic = "gutenberg-book"
futures = admin_client.create_topics(
    [NewTopic(topic, num_partitions=1, replication_factor=1)]
)

for name, future in futures.items():
    try:
        future.result()
        print(f"Created topic: {name}")
    except Exception as exc:
        print(f"Topic {name}: {exc}")

metadata = admin_client.list_topics(timeout=10)
for name in sorted(metadata.topics):
    print(name)
