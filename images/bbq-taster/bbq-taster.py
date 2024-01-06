from flask import Flask
import pymongo
import urllib.parse
import os
import random

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


print('test')


print (username)
#app = Flask(__name__)


# Create a connection to the MongoDB instance running on localhost
client = pymongo.MongoClient("mongodb://%s:%s@%s:27017/" % (username, password, server)) 

# Access the specific database
db = client["pxbbq"]

# Access the specific collection
orders_collection = db["orders"]

# Use the count_documents() method to get the number of documents
orders_document_count = orders_collection.count_documents({})

print(orders_document_count)


# Access the specific collection
registrations_collection = db["registrations"]

# Use the count_documents() method to get the number of documents
registrations_document_count = registrations_collection.count_documents({})

print(orders_document_count)


