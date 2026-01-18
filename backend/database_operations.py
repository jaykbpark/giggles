from pymilvus import MilvusClient
import sqlite3
import numpy as np

MILVUS_COLLECTION_NAME = "clip_embeddings"
class DatabaseOperations():
    def __init__(self):
        self.milvus_conn = MilvusClient('database/milvus_storage.db')
        self.sqlite_conn = sqlite3.connect('database/sqlite.db')
        self.cursor = self.sqlite_conn.cursor()
        
    def search_vector_table(self,vector_data):
        response = self.milvus_conn.search(
            collection_name=MILVUS_COLLECTION_NAME,
            anns_field= "embedding",
            data = [vector_data],
            param = {"metric_type": "L2", "params": {"nprobe": 10}},
            limit=10,
            output_fields=["video_id"]
        )
        return response
    
    def insert_vector_table(self, vector_data, video_id):
        if hasattr(vector_data, "tolist"):
            vector_list = vector_data.tolist()
        else:
            vector_list = vector_data

        data = [
            {
                "embedding": vector_list,  
                "video_id": str(video_id)
            }
        ]
        
        response = self.milvus_conn.insert(
            collection_name="clip_embeddings",
            data=data
        )
        return response
     
    def query_video_table(self,video_id):
        self.cursor.execute(
            "SELECT * FROM videos WHERE id = ?", 
            (video_id,)                         
        )
        return self.cursor.fetchall()
    
    def insert_video_table(self,video_id,title,transcript,timestamp):
        self.cursor.execute(
            "INSERT into videos (id,title,transcript,timestamp) VALUES (?,?,?,?)",
            (video_id,title,transcript,timestamp)
        ) 
        self.sqlite_conn.commit()
    
    def query_tags_table_by_tag(self,tag):
        
        self.cursor.execute(
            "SELECT * FROM tags where tag = ?",
            (tag,)
        )
        return self.cursor.fetchall()
    
    def query_tags_table_get_tags(self):
        self.cursor.execute(
            "SELECT DISTINCT tag from tags"
        )
        res = self.cursor.fetchall()
        res = [data[0] for data in res]
        return res
    def insert_tags_table(self,tag,video_id):
        self.cursor.execute(
            "INSERT into tags (tag,video_id) VALUES (?,?)",
            (tag,video_id)
        ) 
        self.sqlite_conn.commit()
    
    def get_videos_from_tags(self,tag):
        self.cursor.execute(
            "SELECT * FROM videos LEFT JOIN tags ON videos.id = tags.video_id WHERE tags.tag = ?",
            (tag,)
        )
        return self.cursor.fetchall()
    def close(self):
        self.sqlite_conn.close()

