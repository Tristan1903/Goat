import os
import io
import mimetypes

from datetime import datetime, timedelta

from flask_login import current_user

from flask import current_app
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaIoBaseUpload

import firebase_admin
from firebase_admin import credentials, messaging
from .models import User, UserFCMToken, Role, LeaveRequest, User, db, ActivityLog

def _build_week_dates(week_offset=0):
    """
    Calculates the 7 dates for the current/offset scheduling week, always starting on Monday.
    Also fetches approved leave requests for that week.
    Returns: start_of_week, week_dates, end_of_week, leave_dict
    """
    today = datetime.utcnow().date()
    days_since_monday = today.weekday()
    start_of_current_week = today - timedelta(days=days_since_monday)
    
    # Adjust start_of_week by week_offset
    start_of_offset_week = start_of_current_week + timedelta(weeks=week_offset)
    
    week_dates = [start_of_offset_week + timedelta(days=i) for i in range(7)]
    end_of_week = week_dates[-1]

    leave_requests_this_week = LeaveRequest.query.filter(
        LeaveRequest.status == 'Approved',
        LeaveRequest.start_date <= end_of_week,
        LeaveRequest.end_date >= start_of_offset_week
    ).all()
    
    # Initialize leave_dict using user.id from User objects
    leave_dict = {user_obj.id: [] for user_obj in User.query.all()} # Use user_obj.id

    for req in leave_requests_this_week: # req is a LeaveRequest object here
        for d in week_dates:
            if req.start_date <= d <= req.end_date:
                leave_dict.setdefault(req.user_id, []).append(d.isoformat()) # req.user_id is correct here

    return start_of_offset_week, week_dates, end_of_week, leave_dict

SCHEDULER_SHIFT_TYPES_GENERIC = ['Open', 'Day', 'Night', 'Double A', 'Double B', 'Split Double']

# Detailed shift definitions by role and day of the week
ROLE_SHIFT_DEFINITIONS = {
    'bartender': {
        'Tuesday': {
            'Open': {'start': '08:00', 'end': '16:00'},
            'Day': {'start': '10:00', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double A': {'start': '08:00', 'end': 'Specified by Scheduler'},
            'Double B': {'start': '10:00', 'end': 'Specified by Scheduler'},
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        },
        'Wednesday': { # Same as Tuesday
            'Open': {'start': '08:00', 'end': '16:00'},
            'Day': {'start': '10:00', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double A': {'start': '08:00', 'end': 'Specified by Scheduler'},
            'Double B': {'start': '10:00', 'end': 'Specified by Scheduler'},
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        },
        'Thursday': { # Same as Tuesday
            'Open': {'start': '08:00', 'end': '16:00'},
            'Day': {'start': '10:00', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double A': {'start': '08:00', 'end': 'Specified by Scheduler'},
            'Double B': {'start': '10:00', 'end': 'Specified by Scheduler'},
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        },
        'Friday': {
            'Open': {'start': '08:00', 'end': '17:00'},
            'Day': {'start': '10:00', 'end': '17:00'},
            'Night': {'start': '15:00', 'end': 'Close'},
            'Double A': {'start': '08:00', 'end': 'Specified by Scheduler'},
            'Double B': {'start': '10:00', 'end': 'Specified by Scheduler'},
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        },
        'Saturday': { # Same as Friday
            'Open': {'start': '08:00', 'end': '17:00'},
            'Day': {'start': '10:00', 'end': '17:00'},
            'Night': {'start': '15:00', 'end': 'Close'},
            'Double A': {'start': '08:00', 'end': 'Specified by Scheduler'},
            'Double B': {'start': '10:00', 'end': 'Specified by Scheduler'},
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        },
        'Sunday': {
            'Open': {'start': '08:00', 'end': '15:00'},
            'Day': {'start': '10:00', 'end': '17:00'},
            'Night': {'start': '15:00', 'end': 'Close'},
            'Double A': {'start': '08:00', 'end': 'Specified by Scheduler'},
            'Double B': {'start': '10:00', 'end': 'Specified by Scheduler'},
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        }
    },
    'waiter': {
        'Tuesday': {
            'Day': {'start': '09:45', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double': {'start': '09:45', 'end': 'Close'},
        },
        'Wednesday': { # Same as Tuesday
            'Day': {'start': '09:45', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double': {'start': '09:45', 'end': 'Close'},
        },
        'Thursday': { # Same as Tuesday
            'Day': {'start': '09:45', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double': {'start': '09:45', 'end': 'Close'},
        },
        'Friday': { # Same as Tuesday
            'Day': {'start': '09:45', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double': {'start': '09:45', 'end': 'Close'},
        },
        'Saturday': { # Same as Tuesday
            'Day': {'start': '09:45', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double': {'start': '09:45', 'end': 'Close'},
        },
        'Sunday': {
            'Day': {'start': '10:00', 'end': '16:00'},
            'Night': {'start': '16:00', 'end': 'Close'},
            'Double': {'start': '10:00', 'end': 'Close'},
        }
    },
    # Default definitions for other roles if not explicitly specified.
    'skullers': {
        'default': { # Apply these for all days not explicitly defined
            'Open': {'start': 'Flexible', 'end': 'Flexible'},
            'Day': {'start': '09:00', 'end': '17:00'},
            'Night': {'start': '17:00', 'end': 'Close'},
            'Double': {'start': '09:00', 'end': 'Close'},
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        }
    },
    'manager': { # Managers and General Managers share rules
        'default': {
            'Split Double': {'start': 'Specified by Scheduler', 'end': 'Specified by Scheduler'},
        }
    }
}

def get_role_specific_shift_types(role_name, day_name):
    """
    Returns a list of shift types relevant for a given role and day,
    based on ROLE_SHIFT_DEFINITIONS.
    """
    role_def = ROLE_SHIFT_DEFINITIONS.get(role_name)
    if not role_def:
        # Fallback for roles without explicit definitions, e.g., 'system_admin' to 'manager'
        role_def = ROLE_SHIFT_DEFINITIONS.get('manager')
        if not role_def: # Fallback if 'manager' default is also missing (shouldn't happen)
            return SCHEDULER_SHIFT_TYPES_GENERIC

    day_def = role_def.get(day_name)
    if not day_def and 'default' in role_def:
        day_def = role_def.get('default')
        if not day_def: # Fallback if 'default' is also missing
            return []

    if day_def:
        return list(day_def.keys())
    return [] # No specific definition found, return empty list


def get_shift_time_display(role_name, day_name, shift_type, custom_start=None, custom_end=None):
    """
    Helper to retrieve formatted shift start/end times for display, with custom overrides.
    Used by scheduler_role.html and my_schedule.html
    """
    # Override for custom-defined shifts (Split Double, Double A/B for bartender)
    if custom_start and custom_end:
        # If 'Close' was specified, display it correctly
        end_display = "Close" if custom_end.lower() == "close" else custom_end
        return f"({custom_start} - {end_display})"

    # Fallback to predefined role/day specific times
    role_def = ROLE_SHIFT_DEFINITIONS.get(role_name)
    if not role_def:
        role_def = ROLE_SHIFT_DEFINITIONS.get('manager') # Fallback for roles without explicit definitions

    day_def = role_def.get(day_name)
    if not day_def and 'default' in role_def:
        day_def = role_def.get('default')

    if day_def:
        times = day_def.get(shift_type)
        if times:
            return f"({times['start']} - {times['end']})"
    return "" # No specific definition found

def get_drive_service():
    """
    Authenticates with Google Drive/Sheets using stored tokens and returns service objects.
    Assumes initial authorization via /google/authorize and /google/callback has occurred.
    Returns a dictionary of services: {'drive': drive_service, 'sheets': sheets_service}.
    """
    creds = None
    token_file = current_app.config['GOOGLE_DRIVE_TOKEN_FILE']
    scopes = current_app.config['GOOGLE_DRIVE_SCOPES']
    credentials_file = current_app.config['GOOGLE_DRIVE_CREDENTIALS_FILE']


    if os.path.exists(token_file):
        creds = Credentials.from_authorized_user_file(token_file, scopes)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
            # Save the refreshed credentials
            with open(token_file, 'w') as token:
                token.write(creds.to_json())
        else:
            # If no valid token, check if credentials.json is present for a fresh flow
            if os.path.exists(credentials_file):
                # This path should ideally be triggered by a user via /google/authorize
                current_app.logger.warning("Google Drive token missing or invalid. Please re-authorize if expecting background operations.")
                # We won't trigger a full web flow from an API call, just raise.
                raise Exception("Google Drive/Sheets not authorized. Please initiate authorization via /google/authorize.")
            else:
                current_app.logger.error(f"Google Drive credentials file not found at {credentials_file}.")
                raise Exception(f"Google Drive credentials file not found at {credentials_file}.")

    drive_service = build('drive', 'v3', credentials=creds)
    sheets_service = build('sheets', 'v4', credentials=creds) # Build Sheets service
    return {'drive': drive_service, 'sheets': sheets_service} # Return both services

def log_activity(action):
     """Helper function to log a user's action to the database."""
     if current_user.is_authenticated:
         log_entry = ActivityLog(user_id=current_user.id, action=action)
         db.session.add(log_entry)


def upload_file_to_drive(file_obj, filename, mimetype, parent_folder_id=None):
    """
    Uploads a file-like object to Google Drive.
    Returns the webViewLink of the uploaded file on success, None otherwise.
    If parent_folder_id is provided, the file will be uploaded to that folder.
    Otherwise, it defaults to app.config['GOOGLE_DRIVE_FOLDER_ID'].
    Requires an active Flask application context to access current_app.config.
    """
    try:
        services = get_drive_service()
        service = services['drive']

        file_metadata = {'name': filename}

        target_folder_id = parent_folder_id if parent_folder_id else current_app.config['GOOGLE_DRIVE_FOLDER_ID']
        if target_folder_id:
            file_metadata['parents'] = [target_folder_id]
        else:
            current_app.logger.error("No target_folder_id provided for Google Drive upload.")
            # For API, avoid flashing. Log and return None.
            return None

        media = MediaIoBaseUpload(file_obj, mimetype=mimetype, resumable=True)

        file = service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id, webViewLink',
            supportsAllDrives=True
        ).execute()

        # Permissions to make it publicly readable
        service.permissions().create(
            fileId=file.get('id'),
            body={'type': 'anyone', 'role': 'reader'},
            fields='id'
        ).execute()

        current_app.logger.info(f"File '{filename}' uploaded to Google Drive. Link: {file.get('webViewLink')}")
        return file.get('webViewLink')

    except HttpError as error:
        current_app.logger.error(f"An error occurred during Google Drive upload: {error.resp.status} {error.resp.reason} - {error.content}", exc_info=True)
        return None
    except Exception as e:
        current_app.logger.error(f"An unexpected error occurred during document upload: {e}", exc_info=True)
        return None

# NEW HELPER: Function to append EOD data to a Google Sheet
def append_eod_data_to_google_sheet(spreadsheet_id, data_row_dict):
    """
    Appends a row of data to the specified Google Sheet.
    Automatically adds a header row if the sheet is empty.
    Assumes 'Image Links' field in data_row_dict is already formatted as a Sheets HYPERLINK formula.
    Returns the URL of the Google Sheet.
    """
    try:
        services = get_drive_service()
        sheets_service = services['sheets']

        # Determine if header needs to be added
        result = sheets_service.spreadsheets().values().get(
            spreadsheetId=spreadsheet_id, range='A1'
        ).execute()
        values = result.get('values', [])
        sheet_is_empty = not values

        # Construct the row to append based on the ordered keys in data_row_dict
        row_values = []
        for key in data_row_dict.keys(): # Iterate over keys to maintain order
            row_values.append(data_row_dict[key]) # Just append the value directly

        # If sheet is empty, first add the header
        if sheet_is_empty:
            header = list(data_row_dict.keys()) # Get the ordered headers
            body = {'values': [header]}
            sheets_service.spreadsheets().values().update(
                spreadsheetId=spreadsheet_id, range='A1',
                valueInputOption='RAW', body=body # RAW for header strings
            ).execute()
            current_app.logger.info(f"Added header to Google Sheet {spreadsheet_id}.")

        # Append the new data row
        body = {'values': [row_values]}
        sheets_service.spreadsheets().values().append(
            spreadsheetId=spreadsheet_id, range='A:A',
            valueInputOption='USER_ENTERED', # IMPORTANT: Use USER_ENTERED to parse formulas
            insertDataOption='INSERT_ROWS', body=body
        ).execute()

        current_app.logger.info(f"Appended data to Google Sheet {spreadsheet_id}.")
        drive_service = services['drive']
        sheet_metadata = drive_service.files().get(fileId=spreadsheet_id, fields='webViewLink', supportsAllDrives=True).execute()
        return sheet_metadata.get('webViewLink')

    except Exception as e:
        current_app.logger.error(f"An unexpected error occurred during Google Sheets API operation: {e}", exc_info=True)
        return None

def send_push_notification(user_id, title, body, data=None):
    """
    Sends a push notification to all FCM tokens associated with a user.
    `data` is an optional dictionary for custom key-value pairs (e.g., {"type": "shift_published"}).
    """
    # Ensure Firebase Admin SDK is initialized
    if not firebase_admin._apps:
        current_app.logger.error("Firebase Admin SDK not initialized when attempting to send push notification.")
        return False

    user_obj = User.query.get(user_id)
    if not user_obj:
        current_app.logger.warning(f"Attempted to send notification to non-existent user_id: {user_id}")
        return False

    if not user_obj.fcm_tokens:
        current_app.logger.info(f"User {user_obj.username} has no FCM tokens registered.")
        return False

    registration_tokens = [token_obj.fcm_token for token_obj in user_obj.fcm_tokens]

    message = messaging.MulticastMessage(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data=data,
        tokens=registration_tokens,
    )

    try:
        response = messaging.send_multicast(message)
        current_app.logger.info(f"Successfully sent {response.success_count} messages to user {user_obj.username}.")
        if response.failure_count > 0:
            for resp in response.responses:
                if not resp.success:
                    current_app.logger.warning(f"Failed to send message: {resp.exception}")
        return True
    except Exception as e:
        current_app.logger.error(f"Error sending FCM notification to user {user_obj.username}: {e}", exc_info=True)
        return False

# ==============================================================================
# User Manual Content
# ==============================================================================
MANUAL_CONTENT = {
    "Getting Started": {
        "content": """
            <p>Welcome to the Inventory Management & Scheduling System. This manual will help you understand the features available based on your assigned roles.</p>
            <strong>Logging In:</strong> Use the username and password provided by your administrator.
            <br>
            <strong>Changing Your Password:</strong> You can change your own password at any time by clicking your name in the top-right corner and selecting "Change Password".
        """,
        "roles": ["system_admin", "manager", "bartender", "waiter", "scheduler", "general_manager", "skullers", "owners"]
    },
    "Daily Workflow (Inventory)": {
        "content": """
            <p>The daily inventory process follows a strict order:</p>
            <ol>
                <li><strong>Beginning of Day:</strong> A Manager or Admin must first enter the starting counts for all products and the previous day's sales. This can be done manually or by uploading a sales CSV from the POS system. This step unlocks the daily counting pages for staff.</li>
                <li><strong>Daily Counts:</strong> Perform counts for your assigned locations. You can do a "First Count" and then make "Corrections" later. Note: A user cannot correct their own first count; a different user must make the correction.</li>
                <li><strong>Recount Requests:</strong> Managers can request a recount of a specific product or location from the Variance Report page. Relevant staff will be notified and asked to perform a new count.</li>
                <li><strong>View Reports:</strong> The reporting suite allows managers to see a daily summary, compare first vs. correction counts, and view a product-by-product breakdown.</li>
            </ol>
        """,
        "roles": ["system_admin", "manager", "bartender", "owner"]
    },
    "Scheduling for Staff": {
        "content": """
            <p>The scheduling system allows you to manage your work availability and view your assigned shifts.</p>
            <ul>
                <li><strong>Submit Shifts:</strong> Use the "Submit Shifts" page to mark your availability for the upcoming week. You can update your availability at any time until the schedule is published.</li>
                <li><strong>My Schedule:</strong> Once a schedule is published by a Scheduler, you can view your assigned shifts for the week on the "My Schedule" page. Your shifts will be highlighted with their assigned times. New shift types like 'Open' (flexible slot) and 'Split Double' (specific split times) might appear based on manager assignments.</li>
                <li><strong>Request Swap:</strong> If you need to swap an assigned shift, you can click the "Request Swap" button next to that shift on the "My Schedule" page. This will notify managers of your request.</li>
                <li><strong>Relinquish Shift:</strong> If you need to give up a shift and let others volunteer, use the "Relinquish Shift" button on "My Schedule". This makes the shift available for other eligible staff to volunteer for.</li>
            </ul>
        """,
        "roles": ["bartender", "waiter", "skullers"]
    },
    "Scheduling for Management": {
        "content": """
            <p>As a Scheduler, you are responsible for creating and publishing the weekly work schedule.</p>
            <ol>
                <li><strong>Review Availability:</strong> Go to the "Scheduler" page to see a grid of all staff availability for the upcoming week. A green badge indicates a user is available.</li>
                <li><strong>Assign Shifts with Times:</strong> Assign staff to specific shift types like 'Open', 'Day', 'Night', 'Double', or 'Split Double' using the dropdowns. Hover over shift types or click 'View Rules' for their defined times. 'Open' shifts are flexible slots, 'Split Double' requires custom timing.</li>
                <li><strong>Manage Staff Minimums:</strong> Set minimum and optional maximum staff requirements per role per day to guide scheduling and assess staffing levels.</li>
                <li><strong>Save Draft:</strong> You can save your progress at any time by clicking "Save Draft". The schedule will not be visible to staff.</li>
                <li><strong>Publish Schedule:</strong> When you are finished, click "Save and Publish Schedule". This will make the schedule visible to all staff and send out a notification. This action will replace any previously published schedule for that week.</li>
                <li><strong>Export:</strong> You can download a CSV of the full schedule for a specific role at any time using the "Export to CSV" button on the scheduler page.</li>
                <li><strong>Manage Swaps & Volunteered Shifts:</strong> Review and approve/deny requests for shift swaps and shifts put up for volunteering on their respective management pages.</li>
            </ol>
        """,
        "roles": ["scheduler", "manager", "general_manager", "system_admin"]
    },
    "HR & Communication": {
        "content": """
            <p>The system includes tools for managing leave and communicating with the team.</p>
            <ul>
                <li><strong>Announcements:</strong> Managers can post announcements, categorizing them as General, Late Arrival, or Urgent. They can also target specific roles or include actionable links to schedules. All announcements can now be cleared by authorized users.</li>
                <li><strong>Leave Requests:</strong> Use the "Leave" page to submit requests for time off. You can include dates, a reason, and an optional supporting document (like a doctor's note).</li>
                <li><strong>Bookings:</strong> Log and manage customer bookings, including customer name, party size, date, time, and notes.</li>
                <li><strong>Manage Swaps (Managers):</strong> Managers can review all pending shift swap requests on the "Manage Swaps" page. To approve a request, select a covering employee from the list and click "Approve". The schedule will be updated automatically.</li>
                <li><strong>Manage Volunteered Shifts (Managers):</strong> Managers can review shifts that staff have relinquished for volunteering. They can then assign an eligible volunteer or cancel the volunteering cycle.</li>
            </ul>
        """,
        "roles": ["system_admin", "manager", "general_manager", "bartender", "waiter", "skullers","owner","hostess"]
    },
    "Recipe Book": {
        "content": """
            <p>The "Recipe Book" is a central location for all cocktail recipes. Bartenders can view recipes, while Managers and Admins can add, edit, or delete them. Use the search bar to quickly find recipes by name.</p>
        """,
        "roles": ["system_admin", "manager", "bartender","owner"]
    },
    "Managing Users (Admins)": {
        "content": """
            <p>As a System Admin or General Manager, you have advanced user management capabilities.</p>
            <ul>
                <li><strong>Add & Edit Users:</strong> Use the "Manage Users" page to create new accounts or edit existing ones. You can now assign multiple roles to a single user using the checkboxes.</li>
                <li><strong>Suspend Users:</strong> On the user edit page, you can temporarily suspend an account. A suspended user has limited access (they can only view their schedule and announcements). You can set an optional end date to have the suspension lifted automatically and upload/delete suspension documents.</li>
                <li><strong>Reinstate Users:</strong> Suspended users can be reinstated from the "Manage Users" list.</li>
                <li><strong>Active Users:</strong> The "Active Users" page shows who has been using the application in the last 5 minutes. From here, you can force a user to be logged out.</li>
                <li><strong>Clear Activity Log:</strong> System Administrators can clear all past activity log entries from the Dashboard.</li>
            </ul>
        """,
        "roles": ["system_admin", "general_manager"]
    }
}

