from flask import Flask, jsonify
from minio import Minio
import urllib.parse
import os
import random
import io
import datetime
import difflib
import json


username = os.getenv('MONGO_USER')
password = os.getenv('MONGO_PASS')
server = os.getenv('MONGO_NODE')
s3url = os.getenv('S3_URL')
accesskey = os.getenv('S3_ACCESSKEY')
secretkey = os.getenv('S3_SECRETKEY')
bucket = os.getenv('S3_BUCKET')
results_bucket = os.getenv('S3_RESULTS_BUCKET')

app = Flask(__name__)
client = Minio(s3url, accesskey, secretkey)

@app.route('/')
def compare_files():
    # Example: List all objects in the bucket
    objects = client.list_objects(bucket, recursive=True)

    # Get the last two objects
    last_two_objects = sorted(objects, key=lambda obj: obj.last_modified, reverse=True)[:2]

    # Download the last two objects into variables as strings
    content1 = client.get_object(bucket, last_two_objects[0].object_name).read().decode('utf-8')
    content2 = client.get_object(bucket, last_two_objects[1].object_name).read().decode('utf-8')

    # Compare the two contents using difflib
    differ = difflib.Differ()
    diff_results = list(differ.compare(content1.splitlines(), content2.splitlines()))

    # Check if the contents are the same
    status = 'success' if content1 == content2 else 'error'
    message = 'The contents of the two files are the same.' if status == 'success' else 'The contents of the two files are different.'

    # Create a dictionary with the response data
    response_data = {'status': status, 'message': message, 'diff': diff_results}

    # Convert the response data to JSON
    json_response = json.dumps(response_data)

    # Upload the JSON response to the "results" bucket
    result_object_name = 'result' + str(datetime.datetime.now().strftime("%Y-%m-%d-%H-%M-%S")) + '.json'  # Change to your desired object name
    client.put_object(results_bucket, result_object_name, io.BytesIO(json_response.encode('utf-8')), len(json_response))

    return jsonify(response_data), 200 if status == 'success' else 404



app.run(host='0.0.0.0')
