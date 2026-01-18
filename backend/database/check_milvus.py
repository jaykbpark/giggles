from pymilvus import MilvusClient

client = MilvusClient("./milvus_storage.db")

# List all collection names
print("Collections:", client.list_collections())

# Get row count for your specific collection
stats = client.get_collection_stats(collection_name="clip_embeddings")

print(f"Total rows in clip_embeddings: {stats['row_count']}")