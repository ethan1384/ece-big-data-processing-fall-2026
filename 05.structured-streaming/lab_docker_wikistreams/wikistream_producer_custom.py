# %% Dependencies
import argparse
import json
import socket
import time
from datetime import datetime, timedelta
from confluent_kafka import Producer
from pywikibot.comms.eventstreams import EventStreams

# %% Command line arguments
# Customise which wiki events are followed, filtering happens at the producer level
parser = argparse.ArgumentParser(
  description='Send filtered Wikimedia recent changes to a Kafka topic'
)
parser.add_argument('--wikis', nargs='+',
  default=['fr.wikipedia.org', 'en.wikipedia.org', 'de.wikipedia.org'],
  help='server_name values to follow (fr.wikipedia.org, www.wikidata.org...)')
parser.add_argument('--types', nargs='+', default=['edit', 'new'],
  help='event types to follow: edit, new, log, categorize')
parser.add_argument('--titles', nargs='+',
  help='only follow these page titles (e.g. "Paris" "Emmanuel Macron")')
parser.add_argument('--namespaces', nargs='+', type=int,
  help='only follow these namespaces (0 = articles, 2 = user pages...)')
parser.add_argument('--humans-only', action='store_true',
  help='drop the edits made by bots')
parser.add_argument('--since',
  help='replay the history from this date (YYYYMMDD), live stream if omitted')
parser.add_argument('--minutes', type=float, default=10,
  help='how long the producer runs')
parser.add_argument('--topic', default='wikistreams_live')
args = parser.parse_args()

# %% Helper Functions
# Serializer function to change message from python dict to json
value_serializer = lambda val: json.dumps(val).encode('utf-8')

# %% Producer Instantiation
conf = {'bootstrap.servers': 'localhost:9092',
        'client.id': socket.gethostname(),
        'compression.type': 'lz4'
}
producer = Producer(conf)

# %% Create the filtered wikistreams query
# All the filters registered with ftype='all' (default) must match
stream = EventStreams(streams=['recentchange'], since=args.since)
stream.register_filter(server_name=args.wikis, type=args.types)
if args.titles:
  stream.register_filter(title=args.titles)
if args.namespaces:
  stream.register_filter(namespace=args.namespaces)
if args.humans_only:
  stream.register_filter(ftype='none', bot=True)

# %% Streaming Query
stop_time = datetime.now() + timedelta(minutes=args.minutes)
print(f'Following {args.wikis} ({args.types}) into topic "{args.topic}" '
      f'for {args.minutes} minutes')

sent = 0
try:
  while datetime.now() < stop_time:
    change = next(stream)
    # The wiki is used as message key, so one wiki always lands in the same partition
    producer.produce(
      topic=args.topic,
      key=change['server_name'].encode('utf-8'),
      value=value_serializer(change)
    )
    producer.poll(0)
    sent += 1
    if sent % 50 == 0:
      print(f'{sent} events sent, last: {change["server_name"]} '
            f'"{change["title"]}" by {change["user"]} at {change["meta"]["dt"]}')
except KeyboardInterrupt:
  print('\n interrupted')

# Wait for the last messages to be delivered before exiting
print(f'\n {sent} events sent, flushing producer')
producer.flush(30)
print(' closing producer')
