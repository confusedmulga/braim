"""Builds the offline dictionary the app ships: assets/dictionary/oewn.db.gz.

Source: Open English WordNet, 2025 edition (common words; no proper nouns),
the GWA XML file from https://github.com/globalwordnet/english-wordnet/releases

    python -I tool/build_dictionary.py path/to/english-wordnet-2025.xml.gz

Only the standard library is used. The result is a small read-only SQLite
database the app unpacks on first use:

  words     every headword as written, plus a lower-case lookup key
  synsets   one meaning: part of speech, definition, up to two examples
  senses    which meanings a word has, in WordNet's (frequency) order
  forms     irregular inflections ("went" -> go, "mice" -> mouse)
  similar   adjective clusters ("happy" ~ "blissful"), for synonyms
  defs      a full-text index of the definitions (FTS4, Porter stemming), for
            finding a word from its meaning. FTS4 rather than FTS5: every
            Android build of SQLite has FTS4.

Licence: CC BY 4.0 (Open English WordNet) over the Princeton WordNet licence;
both notices travel with the app in assets/dictionary/LICENSE.txt.
"""

import gzip
import os
import sqlite3
import sys
import xml.etree.ElementTree as ET

# The edition baked into the asset. Bump with the source file; the app
# re-unpacks the database when this changes.
EDITION = "2025"

POS = {"n": "n", "v": "v", "a": "a", "s": "a", "r": "r"}
MAX_EXAMPLES = 2


def main(src, out_dir):
    words = {}  # lemma as written -> id
    senses = []  # (word, synset key, rank)
    forms = set()  # (form key, word)
    synsets = {}  # synset key -> (pos, definition, examples)
    similar = []  # (synset key, synset key)

    with gzip.open(src, "rb") as f:
        for _, el in ET.iterparse(f, events=("end",)):
            if el.tag == "LexicalEntry":
                lemma = el.find("Lemma").get("writtenForm").strip()
                wid = words.setdefault(lemma, len(words) + 1)
                for rank, sense in enumerate(el.iter("Sense")):
                    senses.append((wid, sense.get("synset"), rank))
                for form in el.iter("Form"):
                    key = form.get("writtenForm").strip().lower()
                    if key and key != lemma.lower():
                        forms.add((key, wid))
                el.clear()
            elif el.tag == "Synset":
                definition = (el.findtext("Definition") or "").strip()
                examples = [
                    (e.text or "").strip().strip('"').strip()
                    for e in el.iter("Example")
                ]
                examples = [e for e in examples if e][:MAX_EXAMPLES]
                synsets[el.get("id")] = (
                    POS.get(el.get("partOfSpeech"), "n"),
                    definition,
                    "\n".join(examples) or None,
                )
                for rel in el.iter("SynsetRelation"):
                    if rel.get("relType") == "similar":
                        similar.append((el.get("id"), rel.get("target")))
                el.clear()

    ids = {key: i for i, key in enumerate(sorted(synsets), start=1)}

    os.makedirs(out_dir, exist_ok=True)
    db_path = os.path.join(out_dir, "oewn.db")
    if os.path.exists(db_path):
        os.remove(db_path)
    db = sqlite3.connect(db_path)
    db.executescript(
        """
        PRAGMA page_size = 4096;
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT) WITHOUT ROWID;
        CREATE TABLE words(id INTEGER PRIMARY KEY, lemma TEXT NOT NULL,
                           key TEXT NOT NULL);
        CREATE TABLE synsets(id INTEGER PRIMARY KEY, pos TEXT NOT NULL,
                             def TEXT NOT NULL, ex TEXT);
        CREATE TABLE senses(word INTEGER NOT NULL, synset INTEGER NOT NULL,
                            rank INTEGER NOT NULL,
                            PRIMARY KEY(word, synset)) WITHOUT ROWID;
        CREATE TABLE forms(form TEXT NOT NULL, word INTEGER NOT NULL,
                           PRIMARY KEY(form, word)) WITHOUT ROWID;
        CREATE TABLE similar(synset INTEGER NOT NULL, other INTEGER NOT NULL,
                             PRIMARY KEY(synset, other)) WITHOUT ROWID;
        """
    )
    db.executemany(
        "INSERT INTO meta VALUES(?, ?)",
        [("edition", EDITION), ("source", "Open English WordNet")],
    )
    db.executemany(
        "INSERT INTO words VALUES(?, ?, ?)",
        [(i, lemma, lemma.lower()) for lemma, i in words.items()],
    )
    db.executemany(
        "INSERT INTO synsets VALUES(?, ?, ?, ?)",
        [(ids[k], *v) for k, v in synsets.items()],
    )
    db.executemany(
        "INSERT OR IGNORE INTO senses VALUES(?, ?, ?)",
        [(w, ids[s], r) for w, s, r in senses if s in ids],
    )
    db.executemany("INSERT INTO forms VALUES(?, ?)", sorted(forms))
    db.executemany(
        "INSERT OR IGNORE INTO similar VALUES(?, ?)",
        [(ids[a], ids[b]) for a, b in similar if a in ids and b in ids],
    )
    db.executescript(
        """
        CREATE INDEX words_key ON words(key);
        CREATE INDEX senses_synset ON senses(synset);
        CREATE VIRTUAL TABLE defs USING fts4(content="synsets", def,
                                             tokenize=porter);
        INSERT INTO defs(docid, def) SELECT id, def FROM synsets;
        INSERT INTO defs(defs) VALUES('optimize');
        """
    )
    db.commit()
    db.execute("VACUUM")
    db.close()

    with open(db_path, "rb") as raw, gzip.open(
        db_path + ".gz", "wb", compresslevel=9
    ) as packed:
        packed.write(raw.read())
    unpacked = os.path.getsize(db_path)
    os.remove(db_path)
    print(
        f"{len(words)} words, {len(synsets)} meanings, {len(senses)} senses, "
        f"{len(forms)} forms, {len(similar)} similar -> "
        f"{os.path.getsize(db_path + '.gz') / 1e6:.1f} MB packed, "
        f"{unpacked / 1e6:.1f} MB unpacked"
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1], os.path.join(os.path.dirname(__file__), "..",
                                   "assets", "dictionary"))
