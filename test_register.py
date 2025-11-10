import requests

url = "http://127.0.0.1:5000/api/auth/register"

payload = {
    "username": "testuser",
    "email": "test@example.com",
    "password": "123456"
}

headers = {
    "Content-Type": "application/json"
}

response = requests.post(url, json=payload, headers=headers)

print("Status Code:", response.status_code)
try:
    print("Response JSON:", response.json())
except Exception:
    print("Response Text:", response.text)
