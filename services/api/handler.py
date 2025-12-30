from mangum import Mangum
from app.main import app

# AWS Lambda entrypoint (API Gateway / Lambda proxy)
handler = Mangum(app)
