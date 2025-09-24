# your_project_root/backend/wsgi.py
import sys
import os

# Add your project directory to the sys.path
# Assuming your Flask app is in a 'backend' folder directly under yourusername/projectname
path = '/home/Abbadon1903/GoatApp/backend' # <--- REPLACE yourusername and projectname
if path not in sys.path:
    sys.path.insert(0, path)

# Set the FLASK_APP environment variable.
# PythonAnywhere often sets this, but explicit is better.
os.environ['FLASK_APP'] = 'app' # Your Flask app is defined in app.py

# Import the Flask app from your app.py file
from app import app as application # 'application' is the standard WSGI variable name