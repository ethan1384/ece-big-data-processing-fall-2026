import string
from collections import Counter
from pathlib import Path

from confluent_kafka import Consumer

TOPIC = "gutenberg-book"
OUTPUT_PATH = Path(__file__).with_name("cleaned_book.txt")
COUNTS_PATH = Path(__file__).with_name("word_counts.txt")

# Common English stop words, same idea as the word-count lab.
STOPWORDS = {
    "a", "about", "above", "after", "again", "against", "all", "am", "an",
    "and", "any", "are", "as", "at", "be", "because", "been", "before",
    "being", "below", "between", "both", "but", "by", "can", "did", "do",
    "does", "doing", "down", "during", "each", "few", "for", "from",
    "further", "had", "has", "have", "having", "he", "her", "here", "hers",
    "herself", "him", "himself", "his", "how", "i", "if", "in", "into", "is",
    "it", "its", "itself", "just", "me", "more", "most", "my", "myself",
    "no", "nor", "not", "now", "of", "off", "on", "once", "only", "or",
    "other", "our", "ours", "ourselves", "out", "over", "own", "s", "same",
    "she", "should", "so", "some", "such", "t", "than", "that", "the",
    "their", "theirs", "them", "themselves", "then", "there", "these",
    "they", "this", "those", "through", "to", "too", "under", "until", "up",
    "very", "was", "we", "were", "what", "when", "where", "which", "while",
    "who", "whom", "why", "will", "with", "would", "could", "you", "your",
    "yours", "yourself",
    "yourselves",
}

PUNCTUATION = str.maketrans(
    "",
    "",
    string.punctuation + "“”‘’—–…«»",
)

conf = {
    "bootstrap.servers": "localhost:9092",
    "group.id": "gutenberg-readers",
    "auto.offset.reset": "earliest",
}

consumer = Consumer(conf)
consumer.subscribe([TOPIC])

MAX_EMPTY_POLLS = 10
empty_polls = 0
word_counts = Counter()
lines_written = 0
in_book = False

with OUTPUT_PATH.open("w", encoding="utf-8") as cleaned:
    while True:
        msg = consumer.poll(1.0)

        if msg is None:
            empty_polls += 1
            if empty_polls >= MAX_EMPTY_POLLS:
                print("Closing: no new messages received.")
                break
            continue

        if msg.error():
            print(f"Consumer error: {msg.error()}")
            continue

        empty_polls = 0
        line = msg.value().decode("utf-8", errors="replace")

        if "START OF THE PROJECT GUTENBERG EBOOK" in line:
            in_book = True
            continue
        if "END OF THE PROJECT GUTENBERG EBOOK" in line:
            in_book = False
            continue
        if not in_book:
            continue

        # Lowercase, drop punctuation, then drop stop words and blanks.
        tokens = [
            word
            for word in line.lower().translate(PUNCTUATION).split()
            if word not in STOPWORDS
        ]
        if not tokens:
            continue

        cleaned.write(" ".join(tokens) + "\n")
        word_counts.update(tokens)
        lines_written += 1

consumer.close()

with COUNTS_PATH.open("w", encoding="utf-8") as counts:
    for word, count in word_counts.most_common():
        counts.write(f"{word}\t{count}\n")

print(f"Wrote {lines_written} cleaned lines to {OUTPUT_PATH.name}")
print(f"Wrote {len(word_counts)} word counts to {COUNTS_PATH.name}")
