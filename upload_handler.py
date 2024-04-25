import json
import boto3
import requests
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    # Extract S3 bucket and key from the event passed by the Step Functions
    bucket = event['bucket']
    key = event['fileKey']

    # Initialize S3 client
    s3 = boto3.client('s3')

    try:
        # Get the file object from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        file_content = response['Body'].read()

        # URL of the remote server endpoint expecting the file upload
        upload_url = "https://example-remote-server.com/upload"

        # Optionally include headers, such as Content-Type or authorization tokens
        headers = {
            "Content-Type": "application/octet-stream",
            "Authorization": "Bearer your_access_token"
        }

        # Make the POST request to upload the file
        upload_response = requests.post(upload_url, data=file_content, headers=headers)

        # Check if the upload was successful
        if upload_response.status_code == 200:
            return {
                'fileKey': key,
                'bucket': bucket,
                'status': 'UploadSuccessful',
                'fileReady': False,  # Assuming that file processing is asynchronous
                'retryCount': 0,     # Initial retry count for the next state
                'waitSeconds': 60    # Initial delay before the first check, can be adjusted dynamically
            }
        else:
            # Return a failed status to the state machine
            return {
                'fileKey': key,
                'bucket': bucket,
                'status': 'UploadFailed',
                'error': f"Failed to upload file, response code {upload_response.status_code}"
            }
    except ClientError as e:
        print(e)
        return {
            'fileKey': key,
            'bucket': bucket,
            'status': 'S3Error',
            'error': str(e)
        }
    except Exception as e:
        print(e)
        return {
            'fileKey': key,
            'bucket': bucket,
            'status': 'Error',
            'error': str(e)
        }