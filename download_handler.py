import boto3
import requests

def download_file(event, context):
    # Extract file key and bucket name from the event passed by Step Functions
    file_key = event['fileKey']
    bucket_name = event['bucket']

    # URL of the remote server where the file is located
    # This URL should be adapted to where your files are actually stored
    download_url = f"https://example.com/downloads/{file_key}"

    # Perform the download
    response = requests.get(download_url)
    if response.status_code == 200:
        s3 = boto3.client('s3')

        # Upload the downloaded file to S3
        s3.put_object(
            Bucket=bucket_name,
            Key=f"processed/{file_key}",
            Body=response.content
        )

        return {
            "status": "success",
            "message": f"File {file_key} downloaded and saved to {bucket_name}/processed/"
        }
    else:
        return {
            "status": "error",
            "message": f"Failed to download the file {file_key}. Status code: {response.status_code}"
        }