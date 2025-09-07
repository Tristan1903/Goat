import os

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'your_very_secure_secret_key_change_me'
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or 'sqlite:///site.db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Google Drive Configuration
    GOOGLE_DRIVE_CREDENTIALS_FILE = 'credentials.json'
    GOOGLE_DRIVE_TOKEN_FILE = 'token.json'
    GOOGLE_DRIVE_SCOPES = [
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/spreadsheets'
    ]
    GOOGLE_DRIVE_FOLDER_ID = '1klxw1pnKmAywmh3ayn9O77RpcDPZe-fb'  # Your main folder ID

    # Replace these with actual folder IDs from your Google Drive:
    GOOGLE_DRIVE_LEAVE_DOCS_FOLDER_ID = '1V3XV2fWQjHE710DqMKXh1bc8qGGrlgyB'
    GOOGLE_DRIVE_EOD_IMAGES_FOLDER_ID = '1iRyvDglSJ6hgTIRE9XAp_0hy4rUX-lpH'
    GOOGLE_DRIVE_EOD_SHEET_FOLDER_ID = '1udZ-tksPhs04gsxZs3bRhfP_xDInCtxO'

    GOOGLE_OAUTH_REDIRECT_URI = os.environ.get('GOOGLE_OAUTH_REDIRECT_URI') or 'https://abbadon1903.pythonanywhere.com/google/callback'

    # Flask-Mail Configuration
    MAIL_SERVER = 'smtp.gmail.com'
    MAIL_PORT = 587
    MAIL_USE_TLS = True
    MAIL_USERNAME = os.environ.get('EMAIL_USER') or 'valkyriethread@gmail.com'
    MAIL_PASSWORD = os.environ.get('EMAIL_PASS') or 'xcyw xnkv gadd srpp'
    MAIL_DEFAULT_SENDER = ('Inventory App', MAIL_USERNAME)

    EOD_REPORT_SHEET_ID = '1u4JCET3_Cu8c1NKaDJy05VvFxoFRzXBOtDcDOFBczfo'

    # EOD Report Recipients (Dummy Emails)
    EOD_REPORT_RECIPIENTS = [
        'tristandutoit311@gmail.com'
       ## 'dummy_email2@example.com',
       ## 'dummy_email3@example.com',
       ## 'dummy_email4@example.com'
    ]