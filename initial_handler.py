import json
import boto3

def lambda_handler(event, context):
    sfn_client = boto3.client('stepfunctions')

    # Extract file and bucket details from the S3 event
    for record in event['Records']:
        bucket_name = record['s3']['bucket']['name']
        file_key = record['s3']['object']['key']

        # Define the input for the state machine
        input = {
            "bucket": bucket_name,
            "fileKey": file_key,
            "status": "FileUploaded",
            "initialCheckDelay": 60,
            "maxRetries": 5,
            "retryCount": 0,
            "waitSeconds": 60
        }

        # Start execution of the state machine for each file
        response = sfn_client.start_execution(
            stateMachineArn='arn:aws:states:us-east-1:587747483980:stateMachine:FileProcessingStateMachine',
            input=json.dumps(input)
        )

        print(response)

    return {
        'statusCode': 200,
        'body': json.dumps('State machine executions started successfully')
    }
