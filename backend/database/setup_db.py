from pymilvus import (
    MilvusClient, 
    FieldSchema, 
    DataType, 
    CollectionSchema,
    Collection)
import sqlite3


client = MilvusClient("./milvus_storage.db")

fields = [
    FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
    FieldSchema(name="embedding",dtype=DataType.FLOAT_VECTOR, dim=512),
    FieldSchema(name="video_id",dtype=DataType.INT64)
]

schema = CollectionSchema(fields,"Milvus Schema")

client.create_collection(
    collection_name="clip_embeddings",
    schema=schema,
    dimension=512
)


db_conn = sqlite3.connect("sqlite.db")
db_cursor = db_conn.cursor()
db_cursor.execute("""
                  CREATE TABLE IF NOT EXISTS videos(
                      id INTEGER PRIMARY KEY,
                      title TEXT,
                      transcript TEXT,
                      timestamp TEXT
                  )
                  """)
db_cursor.execute("""
                  CREATE TABLE IF NOT EXISTS tags(
                      id INTEGER PRIMARY KEY AUTOINCREMENT,
                      tag TEXT,
                      video_id INTEGER
                  )
                  """)
db_conn.commit()
db_conn.close()
