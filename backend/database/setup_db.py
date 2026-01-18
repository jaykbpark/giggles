from pymilvus import (
    MilvusClient, 
    FieldSchema, 
    DataType, 
    CollectionSchema,
    Collection)
import sqlite3


import os
db_dir = os.path.dirname(__file__)
client = MilvusClient(os.path.join(db_dir, "milvus_storage.db"))

if not client.has_collection("clip_embeddings"):
    fields = [
        FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
        FieldSchema(name="embedding", dtype=DataType.FLOAT_VECTOR, dim=512),
        FieldSchema(name="video_id", dtype=DataType.VARCHAR, max_length=64)
    ]
    schema = CollectionSchema(fields, "Milvus Schema")

    client.create_collection(
        collection_name="clip_embeddings",
        schema=schema
    )

    index_params = client.prepare_index_params()
    index_params.add_index(
        field_name="embedding",
        index_type="FLAT",  
        metric_type="L2"
    )
    client.create_index("clip_embeddings", index_params)

client.load_collection("clip_embeddings")

db_conn = sqlite3.connect(os.path.join(db_dir, "sqlite.db"))
db_cursor = db_conn.cursor()
db_cursor.execute("""
                  CREATE TABLE IF NOT EXISTS videos(
                      id TEXT PRIMARY KEY,
                      title TEXT,
                      transcript TEXT,
                      timestamp TEXT
                  )
                  """)
db_cursor.execute("""
                  CREATE TABLE IF NOT EXISTS tags(
                      id INTEGER PRIMARY KEY AUTOINCREMENT,
                      tag TEXT,
                      video_id TEXT
                  )
                  """)
db_conn.commit()
db_conn.close()
