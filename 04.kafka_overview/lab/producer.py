import socket
from pathlib import Path

from confluent_kafka import Producer

BOOK_PATH = Path(__file__).with_name("around_the_world_in_80_days.txt")
TOPIC = "gutenberg-book"

conf = {
    "bootstrap.servers": "localhost:9092",
    "client.id": socket.gethostname(),
}

producer = Producer(conf)


def on_delivery(err, msg):
    if err is not None:
        print(f"Delivery failed: {err}")


sent = 0
with BOOK_PATH.open(encoding="utf-8") as book:
    for line in book:
        producer.produce(
            topic=TOPIC,
            value=line.rstrip("\n").encode("utf-8"),
            callback=on_delivery,
        )
        producer.poll(0)
        sent += 1
        if sent % 500 == 0:
            print(f"Queued {sent} lines")

remaining = producer.flush(30)
print(f"Sent {sent} lines to topic '{TOPIC}'. Unflushed: {remaining}")
