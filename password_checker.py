# lambda/password_checker.py (FINAL STABLE VERSION)
import json
import hashlib
import os
import boto3
import urllib.request
from time import time 

# Initialize AWS clients
DYNAMODB = boto3.resource('dynamodb')
SNS = boto3.client('sns')

# Load table name
DB_TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME') 

def check_hibp(sha1_prefix):
    """Checks the HIBP API using the k-Anonymity model."""
    url = f"https://api.pwnedpasswords.com/range/{sha1_prefix}"
    
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return response.read().decode('utf-8')
    except Exception as e:
        print(f"ERROR: Failed HIBP API call: {e}")
        return ""

def lambda_handler(event, context):
    try:
        body = json.loads(event['body'])
        name = body.get('name')
        phone = body.get('phone') 
        password = body.get('password')
        
        if not (name and phone and password): 
            return {'statusCode': 400, 'body': json.dumps({'message': 'Missing required fields: name, phone, or password'})}

        # 1. Hashing and HIBP Check
        sha1_hash = hashlib.sha1(password.encode('utf-8')).hexdigest().upper()
        sha1_prefix = sha1_hash[:5]
        sha1_suffix = sha1_hash[5:]

        hibp_response = check_hibp(sha1_prefix)
        is_breached = False
        breach_count = 0
        
        for line in hibp_response.splitlines():
            suffix, count = line.split(':')
            if suffix == sha1_suffix:
                is_breached = True
                breach_count = int(count)
                break
        
        status = 'Breached' if is_breached else 'Safe'

        # 2. DynamoDB Audit Log
        table = DYNAMODB.Table(DB_TABLE_NAME)
        table.put_item(
            Item={
                'UserID': phone, 
                'CheckTime': int(time() * 1000), 
                'Name': name,
                'SHA1Prefix': sha1_prefix,
                'BreachStatus': status,
                'BreachCount': breach_count
            }
        )

        # 3. SNS Notification (SMS) - Crash-proof block
        try:
            sms_message = f"Hello {name}. Your password check status: "
            if is_breached:
                sms_message += f"Your pass is compromised (found in {breach_count} breaches)."
            else:
                sms_message += "Your pass is not compromised."

            # Publish SMS directly using the PhoneNumber parameter
            SNS.publish(
                PhoneNumber=phone, 
                Message=sms_message
            )
            print(f"SNS SMS publish attempt successful to {phone}.")
        except Exception as sns_e:
            # NON-FATAL: Allows the function to return a 200 OK to the browser even if SMS fails
            print(f"NON-FATAL SNS SMS PUBLISH ERROR: {sns_e}")

        # 4. Return result to the frontend
        return {
            'statusCode': 200,
            'headers': { "Content-Type": "application/json" },
            'body': json.dumps({
                'message': 'Check complete. Status returned.', 
                'breach_count': breach_count,
                'status': status
            })
        }
    except Exception as e:
        # Catch-all for any other unexpected failure
        print(f"FATAL PYTHON ERROR: {e}")
        return {'statusCode': 500, 'body': json.dumps({'message': f'Internal Server Error in Lambda: {str(e)}'})}