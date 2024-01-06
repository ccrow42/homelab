import pymongo
import urllib.parse
import os
import random
import io
import datetime
from minio import Minio

#username = urllib.parse.quote_plus('porxie')
#password = urllib.parse.quote_plus('porxie')
#server = urllib.parse.quote_plus('10.0.1.53')

username = os.getenv('MONGO_USER')
password = os.getenv('MONGO_PASS')
server = os.getenv('MONGO_NODE')
s3url = os.getenv('S3_URL')
accesskey = os.getenv('S3_ACCESSKEY')
secretkey = os.getenv('S3_SECRETKEY')
bucket = os.getenv('S3_BUCKET')






# Create a connection to the MongoDB instance running on localhost
client = pymongo.MongoClient("mongodb://%s:%s@%s:27017/" % (username, password, server)) 

# Access the specific database
db = client["pxbbq"]

# Access the specific collection
orders_collection = db["orders"]

# Use the count_documents() method to get the number of documents
orders_document_count = orders_collection.count_documents({})




# Access the specific collection
registrations_collection = db["registrations"]

# Use the count_documents() method to get the number of documents
registrations_document_count = registrations_collection.count_documents({})


output=(f"Orders {orders_document_count} \nRegistrations {registrations_document_count}")

client = Minio(s3url, accesskey, secretkey)

myobject = "result-" + str(datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S"))

# Upload data with content-type.
result = client.put_object(
    "bbq-taster", myobject, io.BytesIO(output.encode('utf-8')), -1, part_size=10*1024*1024
)
print(
    "created {0} object; etag: {1}, version-id: {2}".format(
        result.object_name, result.etag, result.version_id,
    ),
)
