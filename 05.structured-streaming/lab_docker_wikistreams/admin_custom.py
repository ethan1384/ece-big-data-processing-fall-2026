# %%
from confluent_kafka.admin import AdminClient, NewTopic

# %%
config =  {
  'bootstrap.servers': 'localhost:9092',
}

admin_client = AdminClient(config)

# %%
# wikistreams: demo producer (fr.wikipedia.org history)
# wikistreams_live: custom producer (live edits of several wikis)
topics = ['wikistreams', 'wikistreams_live']
existing = admin_client.list_topics(timeout=10).topics
futures = admin_client.create_topics(
  [NewTopic(t, num_partitions=1, replication_factor=1) for t in topics if t not in existing]
)
for t, f in futures.items():
  f.result()
  print(f'created {t}')

# %%
x = admin_client.list_topics()
for  t in x.topics.keys():
  print(t)

# %%
#admin_client.delete_topics(topics)

# %%
