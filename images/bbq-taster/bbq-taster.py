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

print('test')


print (username)
#app = Flask(__name__)


# Create a connection to the MongoDB instance running on localhost
client = pymongo.MongoClient("mongodb://%s:%s@%s:27017/" % (username, password, server)) 

# Access the specific database
db = client["porxbbq"]

# Access the specific collection
collection = db["orders"]

# Use the count_documents() method to get the number of documents
document_count = collection.count_documents({})

print(document_count)


client = Minio(s3url, accesskey, secretkey)

def get_document_count(database_name, collection_name):
  
    document_count = "0"

    return document_count

# Use the function

@app.route('/')
def armory_random():
    docCount = get_document_count("porxbbq", "orders")
    code = random.choice([200,404])
    return ("%s orders served from PorxBBQ" % docCount), code

app.run(host='0.0.0.0')

