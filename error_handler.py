import boto3

def notify_failure(event, context):
    sns = boto3.client('sns')
    message = f"File {event['fileKey']} in bucket {event['bucket']} is not ready after several checks."
    print(f'Error: {message}')
    # response = sns.publish(
    #     TopicArn='arn:aws:sns:your-region:123456789012:YourTopic',
    #     Message=message,
    #     Subject='File Processing Alert'
    # )
    # return response