# ==============================================================================
# Imports
# ==============================================================================

import os
import json
import re
from datetime import date, datetime, timedelta, time
from functools import wraps
from werkzeug.utils import secure_filename
from werkzeug.routing import BaseConverter
from flask import (Flask, render_template, request, redirect, url_for,
                   flash, Response, jsonify, get_flashed_messages, send_from_directory, session, current_app)
                    
from flask_bcrypt import Bcrypt
from flask_login import (LoginManager, UserMixin, login_user, logout_user,
                       current_user, login_required)
from sqlalchemy import distinct, func, or_

from flask_mail import Mail, Message

from flask_cors import CORS

from .config import Config

from .models import (db, Warning, EndOfDayReport, EndOfDayReportImage, RecountRequest, Booking, VarianceExplanation, Delivery, CocktailsSold,
RequiredStaff, Role, User, Location, Product, Announcement, Count, BeginningOfDay, Sale, ActivityLog, Recipe, RecipeIngredient, ShiftSubmission,
Schedule, ShiftSwapRequest, LeaveRequest, VolunteeredShift)

from .api.mobile import mobile_api_bp

from flask_jwt_extended import JWTManager

from .utils import (get_drive_service, upload_file_to_drive, append_eod_data_to_google_sheet,
                 send_push_notification,
                 SCHEDULER_SHIFT_TYPES_GENERIC, ROLE_SHIFT_DEFINITIONS,
                 get_role_specific_shift_types, get_shift_time_display,
                 _build_week_dates,
                 MANUAL_CONTENT)

import firebase_admin # <--- NEW IMPORT
from firebase_admin import credentials, messaging

# ==============================================================================
# App Configuration
# ==============================================================================

basedir = os.path.abspath(os.path.dirname(__file__))

project_root = os.path.join(basedir, os.pardir)

app = Flask(
    __name__,
    template_folder=os.path.join(project_root, 'templates'),
    static_folder=os.path.join(project_root, 'static'),
    instance_path=os.path.join(project_root, 'instance')
)
app.config.from_object(Config)

CORS(app)

if not firebase_admin._apps: # Check if app is already initialized to prevent re-initialization
    try:
        cred = credentials.Certificate(app.config['FIREBASE_SERVICE_ACCOUNT_KEY'])
        firebase_admin.initialize_app(cred)
        app.logger.info("Firebase Admin SDK initialized.")
    except Exception as e:
        app.logger.error(f"Failed to initialize Firebase Admin SDK: {e}", exc_info=True)

# Initialize extensions
db.init_app(app)

bcrypt_obj = Bcrypt(app)

app.extensions['flask_bcrypt'] = bcrypt_obj
bcrypt = bcrypt_obj

login_manager = LoginManager(app)
login_manager.login_view = 'login'
login_manager.login_message_category = 'info'

mail = Mail(app)

jwt = JWTManager(app)

with app.app_context():
    from .api import mobile

app.register_blueprint(mobile_api_bp)

# ==============================================================================
# Global Definitions (UPDATED/NEW)
# ==============================================================================

class OptionalIntConverter(BaseConverter):
    """
    Custom URL converter to make an integer path segment optional.
    Matches either /<int_value> or nothing.
    Default value in to_python is 0 when no value is provided in the URL.
    """
    regex = r'(?:/(?P<int_val>\d+))?' # Matches /123 or nothing (empty string after first /)

    def to_python(self, value):
        # Check for None or empty string first, indicating the segment was not present.
        if value is None or value == '':
            return 0  # Default value for week_offset when not in URL

        # If 'value' is not empty, it means the regex matched something like '/123'.
        # We need to re-match the regex against the received 'value' to extract
        # the content of the named group 'int_val'.
        match = re.match(self.regex, value)
        if match and match.group('int_val'):
            return int(match.group('int_val'))
        else:
            # This case should ideally not be reached if 'value' is always a result
            # of a successful match of 'self.regex'. However, it's good for robustness.
            raise ValueError(f"OptionalIntConverter could not parse '{value}' into an integer.")

    def to_url(self, value):
        if value == 0:
            return '' # Don't add to URL if value is default
        return f'/{value}'

app.url_map.converters['optional_int'] = OptionalIntConverter


def send_complaint_feedback_email(feedback_data, recipient_emails, personal_email_copy=None):
    """
    Sends an HTML formatted email of the complaint feedback.
    """
    try:
        msg = Message("New Complaint/Feedback Submission",
                      sender=app.config['MAIL_DEFAULT_SENDER'])

        to_recipients = list(recipient_emails)
        if personal_email_copy and personal_email_copy not in to_recipients:
            to_recipients.append(personal_email_copy)
        msg.recipients = to_recipients

        # Determine sender name for display
        sender_name_display = "Anonymous User" if feedback_data['is_anonymous'] else feedback_data['submitter_name']

        html_body = f"""
        <html>
        <head></head>
        <body>
            <h3>New Complaint/Feedback Submitted</h3>
            <p><strong>Submitted By:</strong> {sender_name_display}</p>
            <p><strong>Date Submitted:</strong> {feedback_data['submission_date'].strftime('%Y-%m-%d %H:%M:%S')}</p>
            <hr>

            <h4>Feedback Details</h4>
            <ul>
                <li><strong>Anonymous Submission:</strong> {'Yes' if feedback_data['is_anonymous'] else 'No'}</li>
                <li><strong>Staff Member Position:</strong> {feedback_data['staff_position'] or 'N/A'}</li>
                <li><strong>Date of Feedback:</strong> {feedback_data['feedback_date']}</li>
                <li><strong>Feedback:</strong></li>
                <p style="white-space: pre-wrap;">{feedback_data['feedback_text']}</p>
            </ul>

            <p>This feedback was submitted via the Goat and Co. Portal.</p>
        </body>
        </html>
        """
        msg.html = html_body
        mail.send(msg)
        app.logger.info(f"Complaint/Feedback email sent to {', '.join(msg.recipients)}")
        return True
    except Exception as e:
        app.logger.error(f"Error sending complaint/feedback email: {e}", exc_info=True)
        return False

def slugify(s):
    if not isinstance(s, str):
        return ""
    s = s.lower().strip()
    s = re.sub(r'[^\w\s-]', '', s) # Remove all non-word chars (except spaces and hyphens)
    s = re.sub(r'[\s_-]+', '-', s)  # Replace spaces and underscores with a single hyphen
    s = s.strip('-') # Remove leading/trailing hyphens
    return s

def get_products_data(group_by=None, sort_by=None, sort_order='asc', type_filter='all', search_query=None):
    products_query = Product.query

    # NEW: Apply search filter first
    if search_query:
        products_query = products_query.filter(Product.name.ilike(f'%{search_query}%'))

    # Apply type filter next
    if type_filter and type_filter != 'all':
        products_query = products_query.filter_by(type=type_filter)

    # Apply sorting next
    if sort_by == 'name':
        products_query = products_query.order_by(Product.name.asc() if sort_order == 'asc' else Product.name.desc())
    elif sort_by == 'type':
        products_query = products_query.order_by(Product.type.asc() if sort_order == 'asc' else Product.type.desc())
    elif sort_by == 'unit_of_measure':
        products_query = products_query.order_by(Product.unit_of_measure.asc() if sort_order == 'asc' else Product.unit_of_measure.desc())
    elif sort_by == 'unit_price':
        products_query = products_query.order_by(Product.unit_price.asc() if sort_order == 'asc' else Product.unit_price.desc())
    elif sort_by == 'product_number':
        if sort_order == 'asc':
            products_query = products_query.order_by(
                db.func.CAST(Product.product_number, db.Integer).nullsfirst()
            )
        else: # desc
            products_query = products_query.order_by(
                db.func.CAST(Product.product_number, db.Integer).nullslast()
            )
    else: # Default sort if none of the above are matched
        products_query = products_query.order_by(Product.type, Product.name)

    all_products = products_query.all()

    grouped_products = {}

    # Now apply grouping
    if group_by == 'type':
        for product in all_products:
            grouped_products.setdefault(product.type, []).append(product)
        # Sort groups by type name
        grouped_products = dict(sorted(grouped_products.items()))
    elif group_by == 'location':
        all_locations = Location.query.order_by(Location.name).all()
        for location in all_locations:
            grouped_products[location.name] = []
        for product in all_products:
            if not product.locations.all(): # Products with no assigned location
                grouped_products.setdefault('Unassigned Location', []).append(product)
            for location in product.locations:
                grouped_products.setdefault(location.name, []).append(product)
        # Sort groups by location name
        grouped_products = dict(sorted(grouped_products.items()))
    else: # No grouping
        grouped_products['All Products'] = all_products # A single group

    return grouped_products


@login_manager.user_loader
def load_user(user_id):
    with app.app_context():
        return db.session.get(User, int(user_id))



# ==============================================================================
# Helper Functions & Decorators
# ==============================================================================

app.jinja_env.filters['slugify'] = slugify

# MODIFIED: Function to send the EOD report email
def send_eod_report_email(report_data, manager_name, image_links, recipient_emails, eod_sheet_link=None, drive_folder_link=None, personal_email_copy=None):
    """
    Sends an HTML formatted email of the EOD report, including links to uploaded images,
    the Google Sheet, and the Google Drive folder.
    """
    try:
        msg = Message("End of Day Report - " + report_data.report_date.strftime('%Y-%m-%d'),
                      sender=current_app.config['MAIL_DEFAULT_SENDER'])

        to_recipients = list(recipient_emails)
        if personal_email_copy and personal_email_copy not in to_recipients:
            to_recipients.append(personal_email_copy)
        msg.recipients = to_recipients

        # Build HTML content for the email
        html_body = f"""
        <html>
        <head></head>
        <body>
            <h3>End of Day Report for {report_data.report_date.strftime('%Y-%m-%d')}</h3>
            <p><strong>Manager:</strong> {manager_name}</p>
            <hr>

            <h4>Operational Checks</h4>
            <ul>
                <li><strong>Gas Ordered:</strong> {'Yes' if report_data.gas_ordered else 'No'}</li>
                <li><strong>Garnish Ordered:</strong> {'Yes' if report_data.garnish_ordered else 'No'}</li>
                <li><strong>Maintenance Issues:</strong> {report_data.maintenance_issues or 'None'}</li>
                <li><strong>Staff Pitched / Absences:</strong> {report_data.staff_pitched_absences or 'None'}</li>
                <li><strong>Staff Deductions:</strong> {report_data.staff_deductions or 'None'}</li>
                <li><strong>Stock Borrowed/Lent:</strong> {report_data.stock_borrowed_lent or 'None'}</li>
                <li><strong>Customer Complaints:</strong> {report_data.customer_complaints or 'None'}</li>
                <li><strong>Customer Complaint Contact:</strong> {report_data.customer_complaint_contact_no or 'N/A'}</li>
            </ul>

            <h4>Closing Checks</h4>
            <ul>
                <li><strong>Shop Phone On Charge:</strong> {'Yes' if report_data.shop_phone_on_charge else 'No'}</li>
                <li><strong>TV Boxes Locked:</strong> {'Yes' if report_data.tv_boxes_locked else 'No'}</li>
                <li><strong>All Equipment Switched Off:</strong> {'Yes' if report_data.all_equipment_switched_off else 'No'}</li>
            </ul>

            <h4>Financials</h4>
            <ul>
                <li><strong>Credit Card Machines Banked:</strong> {'Yes' if report_data.credit_card_machines_banked else 'No'}</li>
                <li><strong>Card Machines On Charge:</strong> {'Yes' if report_data.card_machines_on_charge else 'No'}</li>
                <li><strong>Declared Card Sales (POS360):</strong> {report_data.declare_card_sales_pos360 or 'N/A'}</li>
                <li><strong>Actual Card Figure Banked:</strong> {report_data.actual_card_figure_banked or 'N/A'}</li>
                <li><strong>Declared Cash Sales (POS360):</strong> {report_data.declare_cash_sales_pos360 or 'N/A'}</li>
                <li><strong>Actual Cash On Hand:</strong> {report_data.actual_cash_on_hand or 'N/A'}</li>
                <li><strong>Accounts Amount:</strong> {report_data.accounts_amount or 'None'}</li>
                <li><strong>Stock Wastage Value:</strong> {report_data.stock_wastage_value or 'None'}</li>
            </ul>

            <h4>Daily Performance & Security</h4>
            <ul>
                <li><strong>POS360 Day End Complete:</strong> {'Yes' if report_data.pos360_day_end_complete else 'No'}</li>
                <li><strong>Today's Target:</strong> {report_data.todays_target or 'N/A'}</li>
                <li><strong>Turnover (ex TIPS):</strong> {report_data.turnover_ex_tips or 'N/A'}</li>
                <li><strong>Security Walk Through:</strong> {'Yes' if report_data.security_walk_through_clean_shop else 'No'}</li>
                <li><strong>Other Issues Experienced:</strong> {report_data.other_issues_experienced or 'None'}</li>
            </ul>

            {"<h4>Card Batch Pictures (" + str(len(image_links)) + ")</h4>" if image_links else ""}
            {"" if not image_links else "<ul>" + "".join([f"<li><a href='{link.image_url}' target='_blank'>{link.filename or f'Image {i+1}'}</a></li>" for i, link in enumerate(image_links)]) + "</ul>"}

            <hr>
            <h4>Report Links</h4>
            <ul>
                {f"<li><a href='https://docs.google.com/spreadsheets/d/1KRlXPOVpad_gRpUcc3KIc-2-Kv14OSEyBS-OSNKsdZ4/edit?usp=drivesdk' target='_blank'>View Full Report in Google Sheet</a></li>"}
                {f"<li><a href='https://drive.google.com/drive/folders/1iRyvDglSJ6hgTIRE9XAp_0hy4rUX-lpH' target='_blank'>View Google Drive Folder for EOD Reports</a></li>"}
            </ul>



            <p>Report generated by the Goat and Co. Portal.</p>
        </body>
        </html>
        """
        msg.html = html_body
        mail.send(msg)
        app.logger.info(f"EOD report for {report_data.report_date} sent to {', '.join(msg.recipients)}")
        return True
    except Exception as e:
        app.logger.error(f"Error sending EOD report email: {e}", exc_info=True)
        flash(f"Failed to send email copy of the report: {e}", 'danger')
        return False

SCHEDULER_SHIFT_TYPES = ['Day', 'Night', 'Double', 'Open', 'Split Double'] # ADDED 'Open', 'Split Double'
STAFF_SUBMISSION_SHIFT_TYPES = ['Day', 'Night', 'Double'] # Staff only submit for standard types


def _render_scheduler_for_role(role_name, role_label, week_offset=0):
    today = datetime.utcnow().date()

    # Use the modified _build_week_dates
    start_of_week, week_dates, end_of_week, leave_dict = _build_week_dates(week_offset=week_offset)

    # Filter users to include only those with the specified role
    users_in_role_query = User.query.join(User.roles).filter(Role.name == role_name, User.is_suspended == False)

    if role_name == 'manager':
        users_in_role_query = User.query.join(User.roles).filter(
            or_(Role.name == 'manager', Role.name == 'general_manager', Role.name == 'system_admin'),
            User.is_suspended == False
        )

    users = users_in_role_query.order_by(User.full_name).all()

    # Fetch all shift submissions for these users for the week
    submissions = ShiftSubmission.query.filter(
        ShiftSubmission.user_id.in_([u.id for u in users]),
        ShiftSubmission.shift_date.in_(week_dates)
    ).all()

    user_availability = {}
    users_with_submissions_for_week = set() # NEW: To track who submitted shifts
    for sub in submissions:
        user_availability.setdefault(sub.user_id, {}).setdefault(sub.shift_date, set()).add(sub.shift_type)
        users_with_submissions_for_week.add(sub.user_id) # Add user to the set

    # Convert sets to lists for Jinja
    for user_id, days in user_availability.items():
        for day, shifts_set in days.items():
            user_availability[user_id][day] = list(shifts_set)

    # Prepare a list of users who submitted shifts for the week to pass to the template
    submitted_users_details = []
    for user_id in users_with_submissions_for_week:
        user_obj = next((u for u in users if u.id == user_id), None)
        if user_obj:
            submitted_users_details.append({
                'id': user_obj.id,
                'full_name': user_obj.full_name,
                'roles': [r.name for r in user_obj.roles] # Optional: list roles for display
            })
    # Sort submitted_users_details by full_name
    submitted_users_details.sort(key=lambda x: x['full_name'])


    # Fetch existing published assignments for the week

    # Important: retrieve assignments of the specific roles currently being scheduled
    assigned_shifts_query = Schedule.query.filter(
        Schedule.shift_date.in_(week_dates),
        Schedule.user_id.in_([u.id for u in users]),
        Schedule.published == True # Only show published assignments
    ).all()

    # Initialize assignments dict to store Schedule objects (needed for custom times)
    assignments = {} # {date: {user_id: Schedule_object}}
    for shift in assigned_shifts_query:
        # Assuming only one shift of a given type per user per day for now,
        # but the dropdown model ensures only one assignment per slot
        assignments.setdefault(shift.shift_date, {})[shift.user_id] = shift


    # Calculate staffing status for the week
    staffing_status = {}
    for day in week_dates:
        if day.weekday() == 0: continue # Skip Monday for display_dates (as per scheduler_role.html's columns)

        assigned_count = sum(1 for user_id, shift_obj in assignments.get(day, {}).items() if shift_obj.user_id is not None)

        required_staff_entry = RequiredStaff.query.filter_by(role_name=role_name, shift_date=day).first()
        min_staff = required_staff_entry.min_staff if required_staff_entry else 0
        max_staff = required_staff_entry.max_staff if required_staff_entry else None

        status_class = "text-danger"
        status_text = "Understaffed"
        if assigned_count >= min_staff:
            status_class = "text-success"
            status_text = "Good"
        if max_staff is not None and assigned_count > max_staff:
            status_class = "text-warning"
            status_text = "Overstaffed"
        if assigned_count == 0 and min_staff == 0:
            status_class = "text-muted"
            status_text = "No Req."


        staffing_status[day.isoformat()] = {
            'min_staff': min_staff,
            'max_staff': max_staff,
            'assigned_count': assigned_count,
            'status_class': status_class,
            'status_text': status_text
        }


    display_dates = [d for d in week_dates if d.weekday() != 0] # Tuesday to Sunday

    return render_template(
        'scheduler_role.html',
        title=f"{role_label} Scheduler",
        role_name=role_name,
        role_label=role_label,
        users=users,
        display_dates=display_dates,
        week_dates=week_dates, # The full 7 days, Monday to Sunday
        assignments=assignments,
        user_availability=user_availability,
        leave_requests=leave_dict,
        scheduler_shift_types_generic=SCHEDULER_SHIFT_TYPES_GENERIC,
        role_shift_definitions=ROLE_SHIFT_DEFINITIONS, # Pass the detailed definitions
        get_role_specific_shift_types=get_role_specific_shift_types, # Pass helper for filtering dropdowns
        get_shift_time_display=get_shift_time_display, # Pass helper for displaying times
        today=today,
        staffing_status=staffing_status,
        current_week_offset=week_offset, # NEW: Pass current week offset
        submitted_users_for_week=submitted_users_details # NEW: Pass users who submitted shifts for this week
    )

def _process_schedule_post_request(role_name, request_form, week_offset=0):
    start_of_week, week_dates, end_of_week, _ = _build_week_dates(week_offset=week_offset)

    # Determine which users belong to this role (including managers, GMs, system_admins for 'manager' role)
    users_in_role_query = User.query.join(User.roles).filter(User.is_suspended == False)
    if role_name == 'manager':
        users_in_role_query = users_in_role_query.filter(
            or_(Role.name == 'manager', Role.name == 'general_manager', Role.name == 'system_admin')
        )
    else:
        users_in_role_query = users_in_role_query.filter(Role.name == role_name)

    users_in_role = users_in_role_query.all()
    user_ids_in_role = [u.id for u in users_in_role]

    try:
        # Delete existing published shifts for this role and week before saving new ones
        Schedule.query.filter(
            Schedule.shift_date >= start_of_week,
            Schedule.shift_date <= end_of_week,
            Schedule.user_id.in_(user_ids_in_role) if user_ids_in_role else False,
            Schedule.published == True # Only delete published shifts
        ).delete(synchronize_session=False)
        db.session.flush()

        # Delete any existing draft shifts for this role and week before saving new ones
        Schedule.query.filter(
            Schedule.shift_date >= start_of_week,
            Schedule.shift_date <= end_of_week,
            Schedule.user_id.in_(user_ids_in_role) if user_ids_in_role else False,
            Schedule.published == False # Only delete draft shifts
        ).delete(synchronize_session=False)
        db.session.flush()

        for user in users_in_role:
            for day in week_dates:
                # We skip Monday in the display, so only process days Tuesday-Sunday for consistency with the form
                if day.weekday() == 0: continue

                assigned_shift_type = request_form.get(f'assignment_{day.isoformat()}_{user.id}')

                if assigned_shift_type and assigned_shift_type != "":
                    start_time_str = None
                    end_time_str = None

                    if assigned_shift_type in SCHEDULER_SHIFT_TYPES_GENERIC:
                        day_name = day.strftime('%A')
                        role_specific_shift_types = get_role_specific_shift_types(role_name, day_name)

                        if assigned_shift_type in role_specific_shift_types:
                            role_def_for_day = ROLE_SHIFT_DEFINITIONS.get(role_name, {}).get(day_name) or ROLE_SHIFT_DEFINITIONS.get(role_name, {}).get('default', {})
                            shift_times_def = role_def_for_day.get(assigned_shift_type, {})

                            if shift_times_def.get('start') == 'Specified by Scheduler' or shift_times_def.get('end') == 'Specified by Scheduler':
                                start_time_str = request_form.get(f'assignment_{day.isoformat()}_{user.id}_start_time')
                                end_time_str = request.form.get(f'assignment_{day.isoformat()}_{user.id}_end_time')

                                if not start_time_str or not end_time_str:
                                    flash(f"Start and End times are required for {assigned_shift_type} on {day.strftime('%a, %b %d')} for {user.full_name}.", 'danger')
                                    raise ValueError("Custom shift times missing")

                    s = Schedule(
                        shift_date=day,
                        assigned_shift=assigned_shift_type,
                        user_id=user.id,
                        published=(request_form.get('action') == 'publish'),
                        start_time_str=start_time_str,
                        end_time_str=end_time_str
                    )
                    db.session.add(s)

        db.session.commit()
        if request_form.get('action') == 'publish':
            flash(f'{role_name.title()} schedule saved and published.', 'success')
            log_activity(f"Published {role_name.title()} schedule for week starting {start_of_week.strftime('%Y-%m-%d')}.")

            users_to_notify_query = User.query.join(User.roles).filter(
                Role.name == role_name,
                User.is_suspended == False
            )
            # If manager schedule is published, also notify general managers and system admins
            if role_name == 'manager':
                users_to_notify_query = User.query.join(User.roles).filter(
                    or_(Role.name == 'manager', Role.name == 'general_manager', Role.name == 'system_admin'),
                    User.is_suspended == False
                )

            users_to_notify = users_to_notify_query.all()
            for user_to_notify in users_to_notify:
                send_push_notification(
                    user_to_notify.id,
                    f"{role_name.title()} Schedule Published!",
                    f"The new {role_name.title()} schedule for the week of {start_of_week.strftime('%b %d')} has been published. Check your schedule now!",
                    data={"type": "schedule_published", "role": role_name, "week_start": start_of_week.isoformat()}
                )                
        else:
            flash(f'{role_name.title()} schedule draft saved.', 'info')
            log_activity(f"Saved draft for {role_name.title()} schedule for week starting {start_of_week.strftime('%Y-%m-%d')}.")
        return True
    except ValueError as ve:
        db.session.rollback()
        flash(f'Failed to save {role_name} schedule: {ve}', 'danger')
        app.logger.error(f"Failed to save {role_name} schedule (ValueError): {ve}")
        return False
    except Exception as e:
        db.session.rollback()
        flash(f'Failed to save {role_name} schedule due to an unexpected error: {e}', 'danger')
        app.logger.exception(f"Error saving {role_name} schedule.")
        return False

def _calculate_ingredient_usage_from_cocktails_sold(target_date):
    """
    Calculates the total quantity of each product used as ingredients for cocktails
    sold on a given target_date.
    Returns a dictionary: {product_id: total_quantity_used}
    """
    total_ingredient_usage = {}

    # 1. Get all cocktails sold on the target_date
    cocktails_sold_on_date = CocktailsSold.query.filter_by(date=target_date).all()

    if not cocktails_sold_on_date:
        return total_ingredient_usage # No cocktails sold, so no ingredients used

    # 2. For each cocktail sold, find its ingredients and their quantities
    for cocktail_sold in cocktails_sold_on_date:
        recipe = cocktail_sold.recipe # Access the Recipe object
        if not recipe:
            app.logger.warning(f"CocktailsSold entry {cocktail_sold.id} refers to non-existent Recipe ID {cocktail_sold.recipe_id}. Skipping.")
            continue

        # Get all ingredients for this recipe
        # Access recipe.recipe_ingredients which is the backref from RecipeIngredient
        for recipe_ingredient in recipe.recipe_ingredients:
            product_id = recipe_ingredient.product_id
            # Calculate total quantity of this ingredient used
            # = (quantity of this ingredient per cocktail) * (number of cocktails sold)
            quantity_used_per_product = recipe_ingredient.quantity * cocktail_sold.quantity_sold

            total_ingredient_usage.setdefault(product_id, 0.0)
            total_ingredient_usage[product_id] += quantity_used_per_product

    return total_ingredient_usage

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

def role_required(role_names):
    """Decorator to restrict access based on user roles."""
    def wrapper(fn):
        @wraps(fn)
        def decorated_view(*args, **kwargs):
            if not current_user.is_authenticated or not any(role.name in role_names for role in current_user.roles):
                flash('Access Denied: You are not authorized to view this page.', 'danger')
                return redirect(url_for('dashboard'))
            return fn(*args, **kwargs)
        return decorated_view
    return wrapper

@app.context_processor
def inject_global_data():
    """Makes globally needed data available to all templates."""
    global_data = {}
    try:
        global_data['all_locations'] = Location.query.order_by(Location.name).all()
        if current_user.is_authenticated:
            user_roles_ids = [role.id for role in current_user.roles]

            # Query for announcements that are either:
            # 1. Not targeted to any specific role
            # 2. Targeted to one of the current_user's roles
            filtered_announcements_query = Announcement.query.outerjoin(Announcement.target_roles) \
                                                          .filter(or_(
                                                              db.not_(Announcement.target_roles.any()),
                                                              Role.id.in_(user_roles_ids)
                                                          )) \
                                                          .distinct()

            recent_announcements_filtered = filtered_announcements_query.order_by(Announcement.id.desc()).limit(5).all()

            seen_ids = [a.id for a in current_user.seen_announcements.all()]
            unread_count = sum(1 for a in recent_announcements_filtered if a.id not in seen_ids)

            global_data['recent_announcements'] = recent_announcements_filtered
            global_data['unread_announcements_count'] = unread_count

    except Exception as e:
        app.logger.error(f"Error in inject_global_data: {e}", exc_info=True)
        global_data['all_locations'] = []
        if current_user.is_authenticated:
            global_data['recent_announcements'] = []
            global_data['unread_announcements_count'] = 0
    return global_data

def log_activity(action):
    """Helper function to log a user's action to the database."""
    if current_user.is_authenticated:
        log_entry = ActivityLog(user_id=current_user.id, action=action)
        db.session.add(log_entry)

@app.template_filter('to_local_time')
def to_local_time_filter(utc_dt_str, fmt="%Y-%m-%d @ %H:%M:%S"):
    """
    Converts a UTC datetime string (ISO format) to local time (+2h) and formats it.
    The input `utc_dt_str` is expected to be an ISO-formatted string.
    """
    if utc_dt_str is None:
        return "N/A"

    from datetime import datetime, timedelta

    try:
        # Convert the ISO formatted string back to a datetime object
        utc_dt = datetime.fromisoformat(utc_dt_str)
    except ValueError:
        # Handle cases where the string might not be in the expected ISO format
        # or if it's already a datetime object (though the route passes strings)
        # As a fallback, try to parse it as a simple date if it fails isoformat
        try:
            utc_dt = datetime.strptime(utc_dt_str, '%Y-%m-%d')
        except ValueError:
            return "Invalid Date/Time Format"


    local_dt = utc_dt + timedelta(hours=2)
    return local_dt.strftime(fmt)

def get_week_dates():
    """
    Calculates the 7 dates for the current scheduling week, always starting on Monday.
    If today is Monday, the week starts today. If today is Tuesday-Sunday, the week
    starts on the past Monday.
    """
    today = datetime.utcnow().date()
    # Find the most recent Monday (or today if today is Monday)
    # weekday() returns 0 for Monday, 1 for Tuesday, ..., 6 for Sunday
    days_since_monday = today.weekday()
    start_of_week = today - timedelta(days=days_since_monday)

    # Generate the 7 dates from this Monday
    return [start_of_week + timedelta(days=i) for i in range(7)]

@app.before_request
def before_request_handler():
    """Runs before every request."""
    if current_user.is_authenticated:
        db_changed = False

        # First, automatically lift suspension if the end date has passed
        if current_user.is_suspended and current_user.suspension_end_date and datetime.utcnow().date() > current_user.suspension_end_date:
            current_user.is_suspended = False
            current_user.suspension_end_date = None
            current_user.suspension_document_path = None # Clear document path on auto-reinstatement
            db_changed = True
            flash('Your suspension period has ended. Full access has been restored.', 'info')

        # Suspension Access Control (existing logic)
        if current_user.is_suspended:
            allowed_endpoints = ['dashboard', 'logout', 'static']

            if current_user.suspension_end_date:
                reinstatement_preview_date = current_user.suspension_end_date - timedelta(days=2)
                if datetime.utcnow().date() >= reinstatement_preview_date:
                    allowed_endpoints.append('submit_shifts')
                    if request.endpoint == 'dashboard' and 'shift_availability_reminder' not in session:
                        flash(f"Your suspension ends soon! You can now submit your availability starting from {reinstatement_preview_date.strftime('%Y-%m-%d')}.", 'info')
                        session['shift_availability_reminder'] = True

            if request.endpoint not in allowed_endpoints and request.blueprint != 'static':
                flash('Your account is currently suspended. You have limited access.', 'warning')
                return redirect(url_for('dashboard'))

        # Check for force logout (existing logic)
        if current_user.force_logout_requested:
            current_user.force_logout_requested = False
            db_changed = True
            db.session.commit()
            logout_user()
            flash('You have been logged out by an administrator.', 'warning')
            return redirect(url_for('login'))

        # --- NEW: Availability Submission Window Notifications ---
        # Only check for staff roles who submit availability
        if (current_user.has_role('bartender') or current_user.has_role('waiter') or current_user.has_role('skullers')) and request.endpoint not in ['static', 'logout', 'submit_shifts']:
            # The submit_shifts page handles its own notifications with the live timer
            current_time = datetime.now()

            current_date_for_window_calc = current_time.date()
            days_since_monday = current_date_for_window_calc.weekday()
            current_monday_date = current_date_for_window_calc - timedelta(days=days_since_monday)
            current_tuesday_date = current_monday_date + timedelta(days=1)
            next_week_monday_date = current_monday_date + timedelta(days=7)

            submission_window_start = datetime.combine(current_tuesday_date, time(10, 0, 0)) # Current Tuesday 10 AM UTC
            submission_window_end = datetime.combine(next_week_monday_date, time(12, 0, 0)) # Next Monday 2 PM UTC

            # 1-hour notification window BEFORE opening
            notification_before_open_start = submission_window_start - timedelta(hours=1)
            notification_before_open_end = submission_window_start

            # 1-hour notification window BEFORE closing
            notification_before_close_start = submission_window_end - timedelta(hours=1)
            notification_before_close_end = submission_window_end

            # Check if within "1 hour before open" window
            if current_time >= notification_before_open_start and current_time < notification_before_open_end:
                if 'availability_open_soon_notified' not in session:
                    flash(f"Heads up! The shift availability submission window opens in less than an hour, at {submission_window_start|to_local_time('%I:%M %p')} (UTC).", 'info')
                    session['availability_open_soon_notified'] = True
            else:
                # Clear notification flag once outside the window
                session.pop('availability_open_soon_notified', None)

            # Check if within "1 hour before close" window
            if current_time > notification_before_close_start and current_time <= notification_before_close_end:
                if 'availability_close_soon_notified' not in session:
                    flash(f"Warning! The shift availability submission window closes in less than an hour, at {submission_window_end|to_local_time('%I:%M %p')} (UTC).", 'warning')
                    session['availability_close_soon_notified'] = True
            else:
                # Clear notification flag once outside the window
                session.pop('availability_close_soon_notified', None)
        # --- END NEW: Availability Submission Window Notifications ---

        # Update last_seen timestamp (existing logic)
        current_user.last_seen = datetime.utcnow()
        db_changed = True

        if db_changed:
            db.session.commit()

# ==============================================================================
# shift volunteering management routes
# ==============================================================================

@app.route('/manage_volunteered_shifts')
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def manage_volunteered_shifts():
    # Fetch all actionable volunteered shifts
    actionable_volunteered_shifts_raw = VolunteeredShift.query.filter(
        VolunteeredShift.status.in_(['Open', 'PendingApproval'])
    ).order_by(VolunteeredShift.timestamp.desc()).all()

    processed_actionable_shifts = []
    for v_shift in actionable_volunteered_shifts_raw:
        # Pre-filter volunteers based on role matching here in Python
        requester_roles = v_shift.requester.role_names # Get requester's roles

        eligible_volunteers_for_dropdown = []
        for volunteer_user in v_shift.volunteers: # Iterate actual volunteers for this shift
            volunteer_roles = volunteer_user.role_names

            # Check if volunteer has at least one matching role with the requester
            has_matching_role = any(role in requester_roles for role in volunteer_roles)

            if has_matching_role:
                eligible_volunteers_for_dropdown.append(volunteer_user)

        # Append the processed shift data
        processed_actionable_shifts.append({
            'v_shift': v_shift,
            'eligible_volunteers': eligible_volunteers_for_dropdown
        })

    # Also fetch all volunteered shifts for history, regardless of status
    all_volunteered_shifts_history = VolunteeredShift.query.order_by(VolunteeredShift.timestamp.desc()).all()

    return render_template(
        'manage_volunteered_shifts.html',
        actionable_volunteered_shifts=processed_actionable_shifts, # Pass processed list
        all_volunteered_shifts_history=all_volunteered_shifts_history
    )

@app.route('/approve_volunteer', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin']) # Only managers/admins can approve/cancel
def approve_volunteer():
    volunteered_shift_id = request.form.get('volunteered_shift_id', type=int)
    action = request.form.get('action') # 'Approve' or 'Cancel'

    if not volunteered_shift_id:
        flash('No volunteered shift selected for action.', 'danger')
        return redirect(url_for('manage_volunteered_shifts'))

    v_shift = VolunteeredShift.query.get_or_404(volunteered_shift_id)

    # Pre-fetch relevant objects for notifications and updates
    original_schedule_item = v_shift.schedule
    requester = v_shift.requester

    # Safety check for original_schedule_item
    if original_schedule_item is None:
        app.logger.error(f"VolunteeredShift ID {v_shift.id} has no associated Schedule. Data inconsistency!")
        flash('Data inconsistency: The original shift for this request is missing.', 'danger')
        v_shift.status = 'Cancelled' # Mark as cancelled due to inconsistency
        db.session.commit()
        return redirect(url_for('manage_volunteered_shifts'))

    shift_date_str = original_schedule_item.shift_date.strftime('%a, %b %d')

    if action == 'Approve':
        approved_volunteer_id = request.form.get('approved_volunteer_id', type=int)
        if not approved_volunteer_id:
            flash('You must select a volunteer to approve.', 'danger')
            return redirect(url_for('manage_volunteered_shifts'))

        approved_volunteer = User.query.get(approved_volunteer_id)
        if not approved_volunteer:
            flash('Selected volunteer not found.', 'danger')
            return redirect(url_for('manage_volunteered_shifts'))

        # 1. Update the original Schedule entry
        original_schedule_item.user_id = approved_volunteer.id

        # --- Apply "Day + Night = Double" logic for the approved volunteer ---
        # Get approved_volunteer's *other* shifts for that day
        volunteers_other_shifts_that_day = Schedule.query.filter(
            Schedule.user_id == approved_volunteer.id,
            Schedule.shift_date == original_schedule_item.shift_date,
            Schedule.id != original_schedule_item.id # Exclude the current schedule_item being modified
        ).all()

        current_volunteer_shifts_on_day = {s.assigned_shift for s in volunteers_other_shifts_that_day}
        current_volunteer_shifts_on_day.add(original_schedule_item.assigned_shift) # Add the shift being assigned

        if 'Day' in current_volunteer_shifts_on_day and 'Night' in current_volunteer_shifts_on_day:
            original_schedule_item.assigned_shift = 'Double' # Consolidate
            # Delete conflicting individual shifts for the volunteer if a Double is now formed
            Schedule.query.filter(
                Schedule.user_id == approved_volunteer.id,
                Schedule.shift_date == original_schedule_item.shift_date,
                Schedule.assigned_shift.in_(['Day', 'Night'])
            ).delete(synchronize_session=False)
            db.session.flush() # Ensure deletions are processed

        # 2. Update the VolunteeredShift status
        v_shift.status = 'Approved'
        v_shift.approved_volunteer_id = approved_volunteer.id

        db.session.commit() # Commit changes to schedule and v_shift status

        # 3. Notify everyone
        notification_message_base = (
            f"The {original_schedule_item.assigned_shift} shift on {shift_date_str}, "
            f"originally relinquished by {requester.full_name}, "
            f"has been assigned to {approved_volunteer.full_name}."
        )
        # Notify original requester
        flash(f"Your relinquished shift on {shift_date_str} has been taken by {approved_volunteer.full_name}.", 'info')
        # Notify approved volunteer
        flash(f"You have been assigned the {original_schedule_item.assigned_shift} shift on {shift_date_str}, originally relinquished by {requester.full_name}.", 'success')

        # General announcement for all managers and volunteers
        general_announcement = Announcement(
            user_id=current_user.id, # Manager who approved
            title="Shift Volunteering Approved",
            message=notification_message_base,
            category='Urgent'
        )
        db.session.add(general_announcement)

        # Log activity
        log_activity(f"Approved volunteer '{approved_volunteer.full_name}' for shift ID {v_shift.schedule_id} (orig. by {requester.full_name}).")
        flash('Shift volunteering approved and schedule updated!', 'success')


    elif action == 'Cancel':
        v_shift.status = 'Cancelled'
        # No change to original_schedule_item needed, as it was never unassigned.

        db.session.commit() # Commit status change

        # Notify original requester and any volunteers
        notification_message_base = (
            f"The volunteering cycle for the {original_schedule_item.assigned_shift} shift on {shift_date_str}, "
            f"originally relinquished by {requester.full_name}, has been cancelled."
        )
        # Notify original requester
        flash(f"Your relinquished shift on {shift_date_str} has had its volunteering cycle cancelled.", 'warning')

        # General announcement for managers and potentially volunteers
        general_announcement = Announcement(
            user_id=current_user.id, # Manager who cancelled
            title="Shift Volunteering Cancelled",
            message=notification_message_base,
            category='General'
        )
        db.session.add(general_announcement)

        # Log activity
        log_activity(f"Cancelled volunteering cycle for shift ID {v_shift.schedule_id} (orig. by {requester.full_name}).")
        flash('Volunteering cycle cancelled.', 'warning')

    db.session.commit() # Final commit (for general announcements if any)
    return redirect(url_for('manage_volunteered_shifts'))

# ==============================================================================
# Main Routes
# ==============================================================================

@app.route('/complaint_feedback', methods=['GET', 'POST'])
def complaint_feedback():
    if request.method == 'POST':
        is_anonymous = request.form.get('submit_anonymously') == 'on'
        staff_position = request.form.get('staff_position')
        feedback_date_str = request.form.get('date')
        feedback_text = request.form.get('feedback')
        send_copy = request.form.get('send_copy') == 'on'
        personal_email_copy = request.form.get('email_copy_address')

        if not feedback_date_str or not feedback_text:
            flash('Date and Feedback are required fields.', 'danger')
            return render_template('Complaint_feedback.html')

        try:
            feedback_date = datetime.strptime(feedback_date_str, '%Y-%m-%d').date()
        except ValueError:
            flash('Invalid date format for Feedback Date.', 'danger')
            return render_template('Complaint_feedback.html')

        # Prepare data for email
        feedback_data = {
            'is_anonymous': is_anonymous,
            'submitter_name': current_user.full_name if current_user.is_authenticated and not is_anonymous else 'Anonymous',
            'submission_date': datetime.utcnow(),
            'staff_position': staff_position,
            'feedback_date': feedback_date.isoformat(),
            'feedback_text': feedback_text
        }

        # Determine recipients
        # This can be configured in config.py, e.g., COMPLAINT_FEEDBACK_RECIPIENTS = ['manager@example.com']
        recipient_emails = app.config.get('COMPLAINT_FEEDBACK_RECIPIENTS', [])

        # Send email
        email_sent_to_main = send_complaint_feedback_email(
            feedback_data,
            recipient_emails,
            personal_email_copy if send_copy else None
        )

        if email_sent_to_main:
            flash('Your feedback has been submitted successfully!', 'success')
            if send_copy and personal_email_copy:
                flash(f'A copy has been sent to {personal_email_copy}.', 'info')
        else:
            flash('Failed to submit feedback. Please try again later or contact support.', 'danger')

        # Log activity (only if user is authenticated)
        if current_user.is_authenticated:
            log_activity(f"Submitted { 'anonymous' if is_anonymous else 'personal' } complaint/feedback for date {feedback_date_str}.")

        return redirect(url_for('complaint_feedback'))

    return render_template('Complaint_feedback.html', today_date=datetime.utcnow().date())

@app.route('/announcements/clear-all', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def clear_all_announcements():
    try:
        # Delete all announcements
        # CASCADE delete should handle associated announcement_view entries
        num_deleted = Announcement.query.delete()
        db.session.commit()
        log_activity(f"Cleared all ({num_deleted}) announcements.")
        flash(f'All {num_deleted} announcements have been cleared.', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'Error clearing announcements: {e}', 'danger')
    return redirect(url_for('announcements'))

@app.route('/activity-log/clear-all', methods=['POST'])
@login_required
@role_required(['system_admin']) # Only System Admins can clear activity logs
def clear_all_activity_logs():
    try:
        num_deleted = ActivityLog.query.delete()
        db.session.commit()
        log_activity(f"Cleared all ({num_deleted}) activity log entries.")
        flash(f'All {num_deleted} activity log entries have been cleared.', 'success')
    except Exception as e:
        db.session.rollback()
        flash(f'Error clearing activity logs: {e}', 'danger')
    return redirect(url_for('dashboard'))

@app.route('/bookings', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'hostess'])
def bookings():
    today = datetime.utcnow().date()

    # NEW: Delete past bookings upon page load
    # This automatically cleans up old records. If history is needed, a separate archival system would be required.
    try:
        past_bookings_to_delete = Booking.query.filter(Booking.booking_date < today).delete()
        db.session.commit()
        if past_bookings_to_delete > 0:
            app.logger.info(f"Automatically deleted {past_bookings_to_delete} past bookings.")
    except Exception as e:
        db.session.rollback()
        app.logger.error(f"Error automatically deleting past bookings: {e}")
        flash("Error cleaning up past bookings.", 'warning')

    if request.method == 'POST':
        customer_name = request.form.get('customer_name')
        contact_info = request.form.get('contact_info')
        party_size = request.form.get('party_size', type=int)
        booking_date_str = request.form.get('booking_date')
        booking_time = request.form.get('booking_time')
        notes = request.form.get('notes')

        try:
            booking_date = datetime.strptime(booking_date_str, '%Y-%m-%d').date()
        except ValueError:
            flash('Invalid date format for booking date.', 'danger')
            return redirect(url_for('bookings'))

        if not customer_name or not party_size or not booking_date or not booking_time:
            flash('Missing required booking fields.', 'danger')
            return redirect(url_for('bookings'))

        new_booking = Booking(
            customer_name=customer_name,
            contact_info=contact_info,
            party_size=party_size,
            booking_date=booking_date,
            booking_time=booking_time,
            notes=notes,
            user_id=current_user.id
        )
        db.session.add(new_booking)
        db.session.commit()
        log_activity(f"Logged new booking for {customer_name} on {booking_date_str} at {booking_time}.")
        flash('Booking added successfully!', 'success')
        return redirect(url_for('bookings'))

    # GET request: Display only future bookings
    future_bookings = Booking.query.filter(Booking.booking_date >= today).order_by(Booking.booking_date, Booking.booking_time).all()

    return render_template('bookings.html', future_bookings=future_bookings)

    # GET request: Display bookings
    today = datetime.utcnow().date()
    future_bookings = Booking.query.filter(Booking.booking_date >= today).order_by(Booking.booking_date, Booking.booking_time).all()
    past_bookings = Booking.query.filter(Booking.booking_date < today).order_by(Booking.booking_date.desc()).limit(10).all() # Show some recent past bookings

    return render_template('bookings.html', future_bookings=future_bookings, past_bookings=past_bookings)

@app.route('/bookings/edit/<int:booking_id>', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'hostess'])
def edit_booking(booking_id):
    booking = Booking.query.get_or_404(booking_id)

    if request.method == 'POST':
        booking.customer_name = request.form.get('customer_name')
        booking.contact_info = request.form.get('contact_info')
        booking.party_size = request.form.get('party_size', type=int)
        booking_date_str = request.form.get('booking_date')
        booking.booking_time = request.form.get('booking_time')
        booking.notes = request.form.get('notes')
        booking.status = request.form.get('status')

        try:
            booking.booking_date = datetime.strptime(booking_date_str, '%Y-%m-%d').date()
        except ValueError:
            flash('Invalid date format for booking date.', 'danger')
            return render_template('edit_bookings.html', booking=booking)

        db.session.commit()
        log_activity(f"Edited booking ID {booking_id} for {booking.customer_name}.")
        flash('Booking updated successfully!', 'success')
        return redirect(url_for('bookings'))

    return render_template('edit_bookings.html', booking=booking)

@app.route('/bookings/delete/<int:booking_id>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'hostess'])
def delete_booking(booking_id):
    booking = Booking.query.get_or_404(booking_id)
    db.session.delete(booking)
    db.session.commit()
    log_activity(f"Deleted booking ID {booking_id} for {booking.customer_name}.")
    flash('Booking deleted successfully!', 'success')
    return redirect(url_for('bookings'))

@app.route('/')
def index():
    return redirect(url_for('login'))

@app.route('/dashboard')
@login_required
def dashboard():
    latest_announcement = Announcement.query.order_by(Announcement.id.desc()).first()
    today_date = datetime.utcnow().date()
    bod_submitted = BeginningOfDay.query.filter_by(date=today_date).first() is not None
    activity_logs, variance_alerts, password_reset_requests = None, None, None

    # --- NEW: Logic for Open Shifts for Volunteering ---
    open_shifts_for_volunteering = []
    if current_user.has_role('bartender') or current_user.has_role('waiter') or current_user.has_role('skullers'):
        # 1. Get all shifts currently open for volunteering
        all_open_volunteered_shifts = VolunteeredShift.query.filter_by(status='Open').all()

        # 2. Get current_user's schedule for the week to check for conflicts
        # --- MODIFIED: Query Schedule model directly ---
        _, week_dates, _, _ = _build_week_dates()
        current_user_scheduled_shifts_raw = Schedule.query.filter(
            Schedule.user_id == current_user.id,
            Schedule.shift_date.in_(week_dates)
        ).all()
        current_user_schedule_this_week = {
            s.shift_date.isoformat(): {shift.assigned_shift for shift in current_user_scheduled_shifts_raw if shift.shift_date.isoformat() == s.shift_date.isoformat()}
            for s in current_user_scheduled_shifts_raw
        }
        # --- END MODIFIED ---

        current_user_roles = current_user.role_names

        for v_shift in all_open_volunteered_shifts:
            if v_shift.requester_id == current_user.id:
                continue

            requester_roles = v_shift.requester.role_names
            has_matching_role = any(role in requester_roles for role in current_user_roles)
            if not has_matching_role:
                continue

            shift_date_iso = v_shift.schedule.shift_date.isoformat()
            assigned_shifts_on_day = current_user_schedule_this_week.get(shift_date_iso, set())

            conflict = False
            requested_shift_type = v_shift.schedule.assigned_shift

            if requested_shift_type == 'Double':
                if assigned_shifts_on_day:
                    conflict = True
            else:
                if 'Double' in assigned_shifts_on_day or requested_shift_type in assigned_shifts_on_day:
                    conflict = True

            already_volunteered = any(v.id == current_user.id for v in v_shift.volunteers)

            if not conflict and not already_volunteered:
                open_shifts_for_volunteering.append(v_shift)
    # --- END NEW LOGIC ---


    if current_user.has_role('system_admin'):
        activity_logs = ActivityLog.query.order_by(ActivityLog.timestamp.desc()).limit(20).all()
        password_reset_requests = User.query.filter_by(password_reset_requested=True).all()
    elif current_user.has_role('manager'):
        bod_counts = {b.product_id: b.amount for b in BeginningOfDay.query.filter_by(date=today_date).all()}
        sales_counts = {s.product_id: s.quantity_sold for s in Sale.query.filter_by(date=today_date - timedelta(days=1)).all()}
        products = Product.query.all()
        eod_counts = {p.id: (db.session.query(func.sum(Count.amount))
                                   .filter(Count.product_id == p.id, func.date(Count.timestamp) == today_date)
                                   .scalar() or 0) for p in products}
        alerts = []
        for product in products:
            bod = bod_counts.get(product.id, 0)
            sold = sales_counts.get(product.id, 0)
            eod = eod_counts.get(product.id, 0)
            variance_val = eod - (bod - sold)
            if variance_val != 0:
                alerts.append({'name': product.name, 'variance': variance_val})
        variance_alerts = alerts

    location_statuses = []
    if current_user.has_role('manager') or current_user.has_role('bartender'):
        locations = Location.query.order_by(Location.name).all()
        for loc in locations:
            latest_count = Count.query.filter(Count.location == loc.name, func.date(Count.timestamp) == today_date).order_by(Count.timestamp.desc()).first()
            status = 'not_started'
            if latest_count:
                status = 'corrected' if latest_count.count_type == 'Corrections Count' else 'counted'
            location_statuses.append({'location_obj': loc, 'status': status})

    return render_template('dashboard.html',
                           latest_announcement=latest_announcement,
                           location_statuses=location_statuses,
                           bod_submitted=bod_submitted,
                           activity_logs=activity_logs,
                           variance_alerts=variance_alerts,
                           password_reset_requests=password_reset_requests,
                           open_shifts_for_volunteering=open_shifts_for_volunteering)

@app.route('/user-manual')
@login_required
def user_manual():
    user_roles = current_user.role_names
    filtered_content = {
        title: data for title, data in MANUAL_CONTENT.items()
        if any(role in data['roles'] for role in user_roles)
    }
    return render_template('user_manual.html', manual_content=filtered_content)

@app.route('/announcements', methods=['GET', 'POST'])
@login_required
def announcements():
    all_roles = Role.query.order_by(Role.name).all()

    actionable_schedule_views = [
        {'value': 'personal', 'label': 'My Schedule'},
        {'value': 'boh', 'label': 'Back of House Schedule'},
        {'value': 'foh', 'label': 'Front of House Schedule'},
        {'value': 'managers', 'label': 'Managers Schedule'},
        {'value': 'bartenders', 'label': 'Bartenders Only Schedule'},
        {'value': 'waiters', 'label': 'Waiters Only Schedule'},
        {'value': 'skullers', 'label': 'Skullers Only Schedule'},
    ]


    if request.method == 'POST':
        title, message = request.form.get('title'), request.form.get('message')
        category = request.form.get('category', 'General')
        selected_role_ids = request.form.getlist('target_roles[]')
        selected_action_link_view = request.form.get('action_link_view')

        action_link_url = None
        if selected_action_link_view and selected_action_link_view != 'none':
            action_link_url = url_for('my_schedule', view=selected_action_link_view)


        new_announcement = Announcement(
            user_id=current_user.id,
            title=title,
            message=message,
            category=category,
            action_link=action_link_url
        )
        db.session.add(new_announcement)
        db.session.flush() # Flush to get new_announcement.id before adding roles and sending pushes

        if selected_role_ids:
            target_roles_for_announcement = Role.query.filter(Role.id.in_(selected_role_ids)).all()
            new_announcement.target_roles = target_roles_for_announcement

        db.session.commit() # Commit the new announcement first

        log_activity(f"Posted new announcement titled: '{title}' targeting roles: {', '.join([r.name for r in new_announcement.target_roles]) if new_announcement.target_roles else 'All Eligible'}. Action link: {action_link_url or 'None'}.")

        return redirect(url_for('announcements'))

    user_roles_ids = [role.id for role in current_user.roles]

    announcements_for_display = Announcement.query.outerjoin(Announcement.target_roles) \
                                                  .filter(or_(
                                                      db.not_(Announcement.target_roles.any()),
                                                      Role.id.in_(user_roles_ids),
                                                      Announcement.user_id == current_user.id
                                                  )) \
                                                  .distinct() \
                                                  .order_by(Announcement.id.desc()) \
                                                  .all()

    return render_template('announcements.html',
                           announcements=announcements_for_display,
                           all_roles=all_roles,
                           actionable_schedule_views=actionable_schedule_views)

@app.route('/announcements/delete/<int:announcement_id>', methods=['POST'])
@login_required
def delete_announcement(announcement_id):
    announcement = Announcement.query.get_or_404(announcement_id)
    if announcement.user_id != current_user.id and not current_user.has_role('system_admin'):
        flash("Access Denied: You are not authorized to delete this announcement.", 'danger')
        return redirect(url_for('announcements'))
    log_activity(f"Deleted announcement titled: '{announcement.title}'.")
    db.session.delete(announcement)
    db.session.commit()
    flash('Announcement has been successfully deleted.', 'success')
    return redirect(url_for('announcements'))

# ==============================================================================
# Manager-Specific Routes (New EOD Report)
# ==============================================================================

@app.route('/warnings/add', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def add_warning():
    # Only allow managers to warn staff roles (bartender, waiter, skullers)
    staff_roles_allowed_to_warn = ['bartender', 'waiter', 'skullers']
    all_staff_users = User.query.join(User.roles).filter(
        Role.name.in_(staff_roles_allowed_to_warn),
        User.is_suspended == False
    ).order_by(User.full_name).all()

    # Categorize staff for the dropdown filtering
    boh_staff = []
    foh_staff = []

    for user in all_staff_users:
        user_roles = [role.name for role in user.roles]
        if any(role in ['bartender', 'skullers'] for role in user_roles):
            boh_staff.append(user)
        if any(role in ['waiter'] for role in user_roles):
            foh_staff.append(user)

    # Remove duplicates if a user is both BOH and FOH (e.g., a waiter who also helps skull)
    # For now, append to both if they have roles in both categories
    # The JS will handle displaying them in both categories if selected.

    if request.method == 'POST':
        user_id = request.form.get('user_id', type=int)
        issued_by_id = current_user.id
        date_issued_str = request.form.get('date_issued')
        reason = request.form.get('reason')
        severity = request.form.get('severity', 'Minor')
        notes = request.form.get('notes')

        if not user_id or not date_issued_str or not reason:
            flash('Missing required fields for warning.', 'danger')
            return render_template('add_warning.html',
                                   staff_users=all_staff_users,
                                   boh_staff=boh_staff, # Pass back for re-render if error
                                   foh_staff=foh_staff, # Pass back for re-render if error
                                   today_date=datetime.utcnow().date(),
                                   current_selection_type='all') # Keep previous selection

        try:
            date_issued = datetime.strptime(date_issued_str, '%Y-%m-%d').date()
        except ValueError:
            flash('Invalid date format for date issued.', 'danger')
            return render_template('add_warning.html',
                                   staff_users=all_staff_users,
                                   boh_staff=boh_staff,
                                   foh_staff=foh_staff,
                                   today_date=datetime.utcnow().date(),
                                   current_selection_type='all')

        warned_user = User.query.get(user_id)
        if not warned_user or warned_user.id == current_user.id:
            flash('Invalid staff member selected.', 'danger')
            return render_template('add_warning.html',
                                   staff_users=all_staff_users,
                                   boh_staff=boh_staff,
                                   foh_staff=foh_staff,
                                   today_date=datetime.utcnow().date(),
                                   current_selection_type='all')
        if not any(role.name in staff_roles_allowed_to_warn for role in warned_user.roles):
            flash('Cannot issue warning to a non-staff role.', 'danger')
            return render_template('add_warning.html',
                                   staff_users=all_staff_users,
                                   boh_staff=boh_staff,
                                   foh_staff=foh_staff,
                                   today_date=datetime.utcnow().date(),
                                   current_selection_type='all')

        new_warning = Warning(
            user_id=user_id,
            issued_by_id=issued_by_id,
            date_issued=date_issued,
            reason=reason,
            severity=severity,
            notes=notes,
            status='Active'
        )
        db.session.add(new_warning)
        db.session.commit()
        log_activity(f"Issued a '{severity}' warning to {warned_user.full_name} for '{reason[:50]}...'.")
        flash(f"Warning issued to {warned_user.full_name} successfully!", 'success')
        return redirect(url_for('manage_warnings'))

    return render_template('add_warning.html',
                           staff_users=all_staff_users, # Still pass all_staff_users for general view
                           boh_staff=boh_staff,
                           foh_staff=foh_staff,
                           today_date=datetime.utcnow().date(),
                           current_selection_type='all')


@app.route('/warnings')
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def manage_warnings():
    all_warnings = Warning.query.order_by(Warning.date_issued.desc(), Warning.timestamp.desc()).all()

    # Get a list of all staff (recipients) and managers (issuers/resolvers) for filters
    staff_users = User.query.join(User.roles).filter(Role.name.in_(['bartender', 'waiter', 'skullers'])).order_by(User.full_name).all()
    manager_users = User.query.join(User.roles).filter(Role.name.in_(['manager', 'general_manager', 'system_admin'])).order_by(User.full_name).all()

    return render_template('manage_warnings.html',
                           warnings=all_warnings,
                           staff_users=staff_users,
                           manager_users=manager_users)


@app.route('/warnings/edit/<int:warning_id>', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def edit_warning(warning_id):
    warning = Warning.query.get_or_404(warning_id)

    staff_roles = ['bartender', 'waiter', 'skullers']
    staff_users = User.query.join(User.roles).filter(
        Role.name.in_(staff_roles),
        User.is_suspended == False
    ).order_by(User.full_name).all()

    if request.method == 'POST':
        # Updates
        warning.user_id = request.form.get('user_id', type=int) # Allow changing recipient if mistake was made
        warning.date_issued = datetime.strptime(request.form.get('date_issued'), '%Y-%m-%d').date()
        warning.reason = request.form.get('reason')
        warning.severity = request.form.get('severity')
        warning.notes = request.form.get('notes')

        # Status change (if any)
        new_status = request.form.get('status')
        if new_status and new_status != warning.status:
            warning.status = new_status
            if new_status == 'Resolved':
                warning.resolution_date = datetime.utcnow().date()
                warning.resolved_by_id = current_user.id
            else: # If status changes from Resolved to something else, clear resolution info
                warning.resolution_date = None
                warning.resolved_by_id = None

        db.session.commit()
        log_activity(f"Edited warning ID {warning_id} for {warning.user.full_name}.")
        flash('Warning updated successfully!', 'success')
        return redirect(url_for('manage_warnings'))

    return render_template('edit_warning.html',
                           warning=warning,
                           staff_users=staff_users,
                           today_date=datetime.utcnow().date())


@app.route('/warnings/resolve/<int:warning_id>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def resolve_warning(warning_id):
    warning = Warning.query.get_or_404(warning_id)

    # Only allow the issuing manager, GM, or System Admin to resolve
    if warning.issued_by_id != current_user.id and not current_user.has_role('general_manager') and not current_user.has_role('system_admin'):
        flash('You are not authorized to resolve this warning.', 'danger')
        return redirect(url_for('manage_warnings'))

    warning.status = 'Resolved'
    warning.resolution_date = datetime.utcnow().date()
    warning.resolved_by_id = current_user.id
    db.session.commit()
    log_activity(f"Resolved warning ID {warning_id} for {warning.user.full_name}.")
    flash(f"Warning for {warning.user.full_name} marked as resolved.", 'success')
    return redirect(url_for('manage_warnings'))


@app.route('/warnings/delete/<int:warning_id>', methods=['POST'])
@login_required
@role_required(['general_manager', 'system_admin','manager'])
def delete_warning(warning_id):
    warning = Warning.query.get_or_404(warning_id)
    # MODIFIED: Access the user's full name *before* deleting the warning
    warned_user_full_name = warning.user.full_name # This loads the 'user' relationship now

    db.session.delete(warning)
    db.session.commit()

    # Now use the pre-loaded name in the log and flash message
    log_activity(f"Deleted warning ID {warning_id} for {warned_user_full_name}.")
    flash(f"Warning for {warned_user_full_name} has been deleted.", 'success')
    return redirect(url_for('manage_warnings'))

@app.route('/eod_report', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def eod_report():
    today_date = datetime.utcnow().date()
    print(f"DEBUG: Entering eod_report. Request method: {request.method}")

    existing_report = EndOfDayReport.query.filter_by(report_date=today_date).first()
    if existing_report:
        flash(f'An End of Day Report for {today_date.strftime("%Y-%m-%d")} has already been submitted. You can view it from a reports page if implemented.', 'info')
        return redirect(url_for('dashboard'))

    eod_sheet_link = None
    # Initialize drive_folder_link with a default hardcoded value as requested
    # Make sure GOOGLE_DRIVE_EOD_IMAGES_FOLDER_ID is correctly set in your config.py
    drive_folder_link = f"https://drive.google.com/drive/folders/{app.config['GOOGLE_DRIVE_EOD_IMAGES_FOLDER_ID']}"

    uploaded_image_links = []


    if request.method == 'POST':
        print("DEBUG: Inside POST block.")
        # --- NEW DEBUG ---
        print(f"DEBUG: Full request.files object: {request.files}")
        # --- END NEW DEBUG ---

        form_data = {}
        try:
            form_data = {
                'manager_id': current_user.id,
                'report_date': today_date,
                'gas_ordered': request.form.get('gas_ordered') == 'True',
                'garnish_ordered': request.form.get('garnish_ordered') == 'True',
                'maintenance_issues': request.form.get('maintenance_issues'),
                'staff_pitched_absences': request.form.get('staff_pitched_absences'),
                'staff_deductions': request.form.get('staff_deductions'),
                'stock_borrowed_lent': request.form.get('stock_borrowed_lent'),
                'customer_complaints': request.form.get('customer_complaints'),
                'customer_complaint_contact_no': request.form.get('customer_complaint_contact_no'),
                'shop_phone_on_charge': request.form.get('shop_phone_on_charge') == 'True',
                'tv_boxes_locked': request.form.get('tv_boxes_locked') == 'True',
                'all_equipment_switched_off': request.form.get('all_equipment_switched_off') == 'True',
                'credit_card_machines_banked': request.form.get('credit_card_machines_banked') == 'True',
                'card_machines_on_charge': request.form.get('card_machines_on_charge') == 'True',
                'declare_card_sales_pos360': request.form.get('declare_card_sales_pos360'),
                'actual_card_figure_banked': request.form.get('actual_card_figure_banked'),
                'declare_cash_sales_pos360': request.form.get('declare_cash_sales_pos360'),
                'actual_cash_on_hand': request.form.get('actual_cash_on_hand'),
                'accounts_amount': request.form.get('accounts_amount'),
                'stock_wastage_value': request.form.get('stock_wastage_value'),
                'pos360_day_end_complete': request.form.get('pos360_day_end_complete') == 'True',
                'todays_target': request.form.get('todays_target'),
                'turnover_ex_tips': request.form.get('turnover_ex_tips'),
                'security_walk_through_clean_shop': request.form.get('security_walk_through_clean_shop') == 'True',
                'other_issues_experienced': request.form.get('other_issues_experienced'),
                'email_copy_address': request.form.get('email_copy_address') if request.form.get('email_copy_checkbox') else None
            }
            print("DEBUG: form_data dictionary successfully created.")
        except Exception as e:
            print(f"DEBUG ERROR: Failed to create form_data dictionary: {e}")
            flash(f"Error processing form data: {e}", 'danger')
            return redirect(url_for('eod_report'))

        try:
            new_eod_report = EndOfDayReport(**form_data)
            db.session.add(new_eod_report)
            db.session.flush() # Flush to get new_eod_report.id for image filenames
            print(f"DEBUG: new_eod_report created and flushed. ID: {new_eod_report.id}")
        except Exception as e:
            db.session.rollback()
            print(f"DEBUG ERROR: Failed to create or flush new_eod_report: {e}")
            flash(f"Error saving initial report details: {e}", 'danger')
            return redirect(url_for('eod_report'))

        # ====================================================================
        # REVISED IMAGE UPLOAD SECTION
        # ====================================================================
        print("DEBUG: Starting image upload process...")
        eod_files = request.files.getlist('eod_images')
        print(f"DEBUG: Found {len(eod_files)} files to potentially upload for 'eod_images'.")

        for i, file in enumerate(eod_files):
            if file and file.filename != '':
                print(f"DEBUG: Processing file {i+1} named: '{file.filename}' (MimeType: {file.mimetype}).")
                filename = secure_filename(f"eod_image_{today_date.isoformat()}_{new_eod_report.id}_{i}_{file.filename}")

                # Rewind file stream to the beginning before reading, just in case.
                file.seek(0)
                file_stream = io.BytesIO(file.read())

                # Use file.mimetype directly if available, fallback to mimetypes.guess_type
                mimetype = file.mimetype or 'application/octet-stream'

                print(f"DEBUG: Calling upload_file_to_drive for '{filename}' to folder ID: '{app.config['GOOGLE_DRIVE_EOD_IMAGES_FOLDER_ID']}'.")

                drive_link = upload_file_to_drive( # <--- NOW CALLS THE HELPER FROM UTILS
                    file_stream,
                    filename,
                    mimetype,
                    parent_folder_id=current_app.config['GOOGLE_DRIVE_EOD_IMAGES_FOLDER_ID'] # Use current_app.config
                )

                if drive_link:
                    print(f"DEBUG: Successfully uploaded '{filename}'. Google Drive Link: {drive_link}")
                    uploaded_image_links.append(EndOfDayReportImage(eod_report_id=new_eod_report.id, image_url=drive_link, filename=file.filename))
                else:
                    print(f"DEBUG ERROR: Failed to upload '{file.filename}'. 'upload_file_to_drive' returned None. Check error messages from 'upload_file_to_drive' in logs.")
                    flash(f"Failed to upload image '{file.filename}' to Google Drive. Please check server logs for specific Google Drive API errors.", 'danger')
            else:
                print(f"DEBUG: Skipping empty or invalid file at index {i}.")

        if uploaded_image_links:
            db.session.add_all(uploaded_image_links)
            print(f"DEBUG: {len(uploaded_image_links)} image links prepared for database commit.")
        else:
            print("DEBUG: No images were successfully uploaded for this report (uploaded_image_links is empty).")
        # ====================================================================
        # END REVISED IMAGE UPLOAD SECTION
        # ====================================================================

        try:
            db.session.commit()
            print("DEBUG: Database session committed (report and images).")
        except Exception as e:
            db.session.rollback()
            print(f"DEBUG ERROR: Failed to commit new_eod_report and images: {e}")
            flash(f"Error saving report data and images to database: {e}", 'danger')
            return redirect(url_for('eod_report'))

        # NEW LOGIC: Save email to user's profile if provided and not existing
        submitted_email_for_copy = form_data.get('email_copy_address')
        if submitted_email_for_copy and (not current_user.email or current_user.email != submitted_email_for_copy):
            # Basic validation for email format (client-side handles better, but good server-side too)
            if "@" in submitted_email_for_copy and "." in submitted_email_for_copy:
                current_user.email = submitted_email_for_copy
                try:
                    db.session.commit() # Commit update to user's email
                    flash(f"Your email address '{submitted_email_for_copy}' has been saved to your profile.", 'info')
                    log_activity(f"Manager email updated to '{submitted_email_for_copy}' via EOD report.")
                except Exception as e:
                    db.session.rollback()
                    app.logger.error(f"Failed to save manager email to profile: {e}", exc_info=True)
                    flash("Failed to save your email to your profile.", 'warning')
            else:
                flash("The provided email address is not valid and could not be saved to your profile.", 'warning')


        print(f"DEBUG: Before sheet_row_data assignment. uploaded_image_links count: {len(uploaded_image_links)}")
        sheet_row_data = {}
        try:
            # Use the hardcoded drive_folder_link here
            image_link_for_sheet = f'=HYPERLINK("{drive_folder_link}", "View Folder")'

            sheet_row_data = {
                'Report Date': today_date.isoformat(),
                'Manager Name': current_user.full_name,
                'Gas Ordered': 'Yes' if form_data['gas_ordered'] else 'No',
                'Garnish Ordered': 'Yes' if form_data['garnish_ordered'] else 'No',
                'Maintenance Issues': form_data['maintenance_issues'],
                'Staff Pitched / Absences': form_data['staff_pitched_absences'],
                'Staff Deductions': form_data['staff_deductions'],
                'Stock Borrowed/Lent': form_data['stock_borrowed_lent'],
                'Customer Complaints': form_data['customer_complaints'],
                'Customer Complaint Contact': form_data['customer_complaint_contact_no'],
                'Shop Phone On Charge': 'Yes' if form_data['shop_phone_on_charge'] else 'No',
                'TV Boxes Locked': 'Yes' if form_data['tv_boxes_locked'] == 'True' else 'No',
                'All Equipment Switched Off': 'Yes' if form_data['all_equipment_switched_off'] == 'True' else 'No',
                'Credit Card Machines Banked': 'Yes' if form_data['credit_card_machines_banked'] == 'True' else 'No',
                'Card Machines On Charge': 'Yes' if form_data['card_machines_on_charge'] == 'True' else 'No',
                'Declared Card Sales (POS360)': form_data['declare_card_sales_pos360'],
                'Actual Card Figure Banked': form_data['actual_card_figure_banked'],
                'Image Links': image_link_for_sheet,
                'Declared Cash Sales (POS360)': form_data['declare_cash_sales_pos360'],
                'Actual Cash On Hand': form_data['actual_cash_on_hand'],
                'Accounts Amount': form_data['accounts_amount'],
                'Stock Wastage Value': form_data['stock_wastage_value'],
                'POS360 Day End Complete': 'Yes' if form_data['pos360_day_end_complete'] == 'True' else 'No',
                'Today\'s Target': form_data['todays_target'],
                'Turnover (ex TIPS)': form_data['turnover_ex_tips'],
                'Security Walk Through': 'Yes' if form_data['security_walk_through_clean_shop'] == 'True' else 'No',
                'Other Issues Experienced': form_data['other_issues_experienced'],
            }
            print("DEBUG: sheet_row_data dictionary successfully created.")
        except Exception as e:
            print(f"DEBUG ERROR: Failed to create sheet_row_data: {e}")
            flash(f"Error preparing report data for Google Sheet: {e}", 'danger')
            return redirect(url_for('eod_report'))

        eod_sheet_link = append_eod_data_to_google_sheet( # <--- NOW CALLS THE HELPER FROM UTILS
            current_app.config['EOD_REPORT_SHEET_ID'], # Use current_app.config
            sheet_row_data
        )

        flash(f"Report data appended to Google Sheet. <a href='https://docs.google.com/spreadsheets/d/1KRlXPOVpad_gRpUcc3KIc-2-Kv14OSEyBS-OSNKsdZ4' target='_blank'>View Sheet</a>", 'info')

        if new_eod_report.email_copy_address:
            send_eod_report_email(
                new_eod_report,
                current_user.full_name,
                uploaded_image_links,
                app.config['EOD_REPORT_RECIPIENTS'],
                eod_sheet_link=eod_sheet_link,
                drive_folder_link=drive_folder_link,
                personal_email_copy=new_eod_report.email_copy_address
            )
            print(f"DEBUG: Email copy requested for {new_eod_report.email_copy_address}.")
        else:
             send_eod_report_email(
                new_eod_report,
                current_user.full_name,
                uploaded_image_links,
                app.config['EOD_REPORT_RECIPIENTS'],
                eod_sheet_link=eod_sheet_link,
                drive_folder_link=drive_folder_link
            )
             print("DEBUG: Sending email to default recipients.")

        log_activity(f"Submitted End of Day Report for {today_date}.")
        flash('End of Day Report submitted successfully!', 'success')
        return redirect(url_for('dashboard'))

    return render_template('eod_report.html', today_date=today_date)

# ==============================================================================
# Auth Routes
# ==============================================================================
@app.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        user = User.query.filter_by(username=request.form.get('username')).first()
        if user and bcrypt.check_password_hash(user.password, request.form.get('password')):
            login_user(user, remember='remember' in request.form)
            flash(f'Welcome back, {user.full_name}!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('Login Unsuccessful. Please check username and password.', 'danger')
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    flash('You have been logged out.', 'info')
    return redirect(url_for('login'))

@app.route('/change-password', methods=['GET', 'POST'])
@login_required
def change_password():
    if request.method == 'POST':
        current_password = request.form.get('current_password')
        new_password = request.form.get('new_password')
        confirm_password = request.form.get('confirm_password')

        if not bcrypt.check_password_hash(current_user.password, current_password):
            flash('Your current password is incorrect. Please try again.', 'danger')
            return redirect(url_for('change_password'))

        if new_password != confirm_password:
            flash('The new passwords do not match.', 'danger')
            return redirect(url_for('change_password'))

        current_user.password = bcrypt.generate_password_hash(new_password).decode('utf-8')
        db.session.commit()
        log_activity("User changed their own password.")
        flash('Your password has been updated successfully!', 'success')
        return redirect(url_for('dashboard'))

    return render_template('change_password.html')

@app.route('/reset-request', methods=['GET', 'POST'])
def reset_request():
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        username = request.form.get('username')
        user = User.query.filter_by(username=username).first()
        if user:
            # You can still keep this flag if it's used elsewhere, but for this request,
            # the primary action is sending the email.
            user.password_reset_requested = True
            db.session.commit()

            # --- Start of Changes ---
            msg = Message('Password Reset Request',
                          sender='valkyriethread@gmail.com', # Replace with your application's sender email
                          recipients=['tristandutoit311@gmail.com'])
            msg.body = f'''A password reset has been requested for the user: {username}.

Please proceed to manually reset their password via the admin panel.

No further action is required from the user at this time.
'''
            try:
                mail.send(msg)
                flash('If an account with that username exists, an administrator has been notified to reset the password.', 'info')
                log_activity(f"Password reset request email sent for user: '{user.username}'.")
            except Exception as e:
                flash('An error occurred while sending the reset request email. Please try again later.', 'danger')
                log_activity(f"Failed to send password reset request email for user: '{user.username}'. Error: {e}")
            # --- End of Changes ---

        else:
            # To prevent username enumeration, always show a generic message whether user exists or not
            flash('If an account with that username exists, an administrator has been notified to reset the password.', 'info')

        return redirect(url_for('login'))
    return render_template('reset_request.html')

# ==============================================================================
# Inventory Routes
# ==============================================================================

@app.route('/request_recount', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def request_recount():
    product_id = request.form.get('product_id', type=int)
    location_id = request.form.get('location_id', type=int)

    if not product_id and not location_id:
        flash('Must specify a product or a location for a recount.', 'danger')
        return redirect(request.referrer or url_for('variance'))

    if product_id and location_id:
        flash('Please request a recount for either a product OR a location, not both at once.', 'danger')
        return redirect(request.referrer or url_for('variance'))

    target_obj_name = ""
    target_type = ""
    if product_id:
        product = Product.query.get(product_id)
        if not product:
            flash('Product not found.', 'danger')
            return redirect(request.referrer or url_for('variance'))
        target_obj_name = product.name
        target_type = "product"
    elif location_id:
        location = Location.query.get(location_id)
        if not location:
            flash('Location not found.', 'danger')
            return redirect(request.referrer or url_for('variance'))
        target_obj_name = location.name
        target_type = "location"

    # Check for existing pending recount request for the same item/location on the same day
    existing_request_query = RecountRequest.query.filter_by(
        request_date=datetime.utcnow().date(),
        status='Pending'
    )
    if product_id:
        existing_request_query = existing_request_query.filter_by(product_id=product_id)
    elif location_id:
        existing_request_query = existing_request_query.filter_by(location_id=location_id)

    if existing_request_query.first():
        flash(f"A recount for {target_obj_name} is already pending for today.", 'info')
        return redirect(request.referrer or url_for('variance'))


    new_recount_request = RecountRequest(
        product_id=product_id,
        location_id=location_id,
        requested_by_user_id=current_user.id,
        request_date=datetime.utcnow().date(),
        status='Pending'
    )
    db.session.add(new_recount_request)
    db.session.commit()

    # Create an announcement for relevant staff (e.g., bartenders, skullers who might do counts)
    notification_title = "Recount Requested"
    notification_message = (
        f"A recount has been requested for {target_type} **{target_obj_name}** by {current_user.full_name}. "
        f"Please check inventory count pages for details and perform the recount."
    )
    # Target roles who are typically responsible for counts
    target_roles_for_recount = Role.query.filter(Role.name.in_(['bartender', 'skullers'])).all()

    new_announcement = Announcement(
        user_id=current_user.id,
        title=notification_title,
        message=notification_message,
        category='Urgent',
        target_roles=target_roles_for_recount # Target relevant staff
    )
    db.session.add(new_announcement)
    db.session.commit()

    log_activity(f"Requested recount for {target_type}: '{target_obj_name}'.")
    flash(f'Recount for {target_obj_name} requested successfully. Relevant staff have been notified.', 'success')
    return redirect(request.referrer or url_for('variance'))

@app.route('/deliveries', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def deliveries():
    products = Product.query.order_by(Product.name).all() # For dropdown in the form

    if request.method == 'POST':
        product_id = request.form.get('product_id', type=int)
        quantity = request.form.get('quantity', type=float)
        delivery_date_str = request.form.get('delivery_date')
        comment = request.form.get('comment')

        if not product_id or quantity is None or not delivery_date_str:
            flash('Missing required fields for delivery.', 'danger')
            return redirect(url_for('deliveries'))

        try:
            delivery_date = datetime.strptime(delivery_date_str, '%Y-%m-%d').date()
        except ValueError:
            flash('Invalid date format for delivery date.', 'danger')
            return redirect(url_for('deliveries'))

        if quantity <= 0:
            flash('Delivery quantity must be positive.', 'danger')
            return redirect(url_for('deliveries'))

        new_delivery = Delivery(
            product_id=product_id,
            quantity=quantity,
            delivery_date=delivery_date,
            user_id=current_user.id,
            comment=comment
        )
        db.session.add(new_delivery)
        db.session.commit()
        log_activity(f"Logged new delivery: {quantity} of {new_delivery.product.name} on {delivery_date_str}.")
        flash('Delivery recorded successfully!', 'success')
        return redirect(url_for('deliveries'))

    # GET request: Display existing deliveries
    recent_deliveries = Delivery.query.order_by(Delivery.delivery_date.desc(), Delivery.timestamp.desc()).limit(20).all()

    # --- NEW: Pass current_date to the template ---
    current_date = datetime.utcnow().date()

    return render_template('deliveries.html', products=products, recent_deliveries=recent_deliveries, current_date=current_date)



@app.route('/beginning_of_day', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def beginning_of_day():
    today_date = datetime.utcnow().date()
    yesterday = today_date - timedelta(days=1)

    products = Product.query.order_by(Product.type, Product.name).all()

    # --- MODIFIED: Move these definitions to the top level of the function ---
    # Pre-populate sales data from DB for yesterday's sales (manual products)
    existing_manual_sales_for_yesterday_db = {
        s.product_id: s.quantity_sold
        for s in Sale.query.filter_by(date=yesterday).all()
    }
    # Pre-populate cocktails sold data from DB for yesterday's cocktail sales
    existing_cocktails_sold_for_yesterday_db = {
        cs.recipe_id: cs.quantity_sold
        for cs in CocktailsSold.query.filter_by(date=yesterday).all()
    }
    # --- END MODIFIED ---

    # --- Check for yesterday's data availability to enable submission ---
    yesterdays_bod_exists = BeginningOfDay.query.filter_by(date=yesterday).first() is not None
    # We also need to consider if yesterday's sales are empty, but the initial check should be against BOD
    # yesterdays_manual_sales_exist = bool(existing_manual_sales_for_yesterday_db) # This isn't strictly needed for `can_submit_yesterdays_sales` primary check
    # yesterdays_cocktail_sales_exist = bool(existing_cocktails_sold_for_yesterday_db) # This isn't strictly needed for `can_submit_yesterdays_sales` primary check

    # bod_for_today_already_calculated_and_saved_to_db: checks if BOD for TODAY exists in the table.
    bod_for_today_already_calculated_and_saved_to_db = BeginningOfDay.query.filter_by(date=today_date).first() is not None

    # User can submit yesterday's sales IF yesterday's BOD exists AND today's BOD hasn't been saved yet.
    can_submit_yesterdays_sales = yesterdays_bod_exists and not bod_for_today_already_calculated_and_saved_to_db

    # --- Calculation for what TODAY's BOD *will be* (i.e., yesterday's EOD) ---
    calculated_bod_for_today_preview = {} # {product_id: amount}
    if yesterdays_bod_exists:
        yesterdays_bod_counts = {b.product_id: b.amount for b in BeginningOfDay.query.filter_by(date=yesterday).all()}
        # Use existing_manual_sales_for_yesterday_db and existing_cocktails_sold_for_yesterday_db
        yesterdays_manual_sales_preview = existing_manual_sales_for_yesterday_db
        yesterdays_cocktail_usage_preview = _calculate_ingredient_usage_from_cocktails_sold(yesterday)

        for product in products:
            y_bod = yesterdays_bod_counts.get(product.id, 0.0)
            y_manual_sold = yesterdays_manual_sales_preview.get(product.id, 0.0)
            y_cocktail_usage = yesterdays_cocktail_usage_preview.get(product.id, 0.0)

            todays_calculated_bod = y_bod - y_manual_sold - y_cocktail_usage
            calculated_bod_for_today_preview[product.id] = max(0.0, todays_calculated_bod)
    else:
        pass # calculated_bod_for_today_preview remains empty, prompting warning.

    # What the UI should show for "Today's Calculated On-Hand"
    bod_values_to_display = {
        p.id: BeginningOfDay.query.filter_by(product_id=p.id, date=today_date).first().amount
              if BeginningOfDay.query.filter_by(product_id=p.id, date=today_date).first() else
              calculated_bod_for_today_preview.get(p.id, 0.0)
        for p in products
    }

    # --- Setup for Recipe dropdowns (remains unchanged) ---
    all_recipes_objects = Recipe.query.order_by(Recipe.name).all()
    all_recipes_json_serializable = [{'id': r.id, 'name': r.name} for r in all_recipes_objects]

    sales_from_csv = {} # Used only if 'upload_csv' action occurs


    if request.method == 'POST':
        action = request.form.get('action')

        if action == 'upload_csv':
            if 'sales_csv_file' not in request.files:
                flash('No file selected for upload.', 'warning')
                # Return current context
                return render_template('beginning_of_day.html',
                               products=products,
                               all_recipes=all_recipes_objects,
                               all_recipes_json=json.dumps(all_recipes_json_serializable),
                               sales_from_csv=sales_from_csv,
                               existing_sales_for_yesterday=existing_manual_sales_for_yesterday_db,
                               existing_cocktails_sold_for_yesterday=existing_cocktails_sold_for_yesterday_db,
                               bod_values_to_display=bod_values_to_display,
                               can_submit_yesterdays_sales=can_submit_yesterdays_sales,
                               bod_for_today_already_calculated_and_saved_to_db=bod_for_today_already_calculated_and_saved_to_db,
                               yesterday=yesterday)

            file = request.files['sales_csv_file']
            if file and file.filename != '':
                try:
                    stream = io.StringIO(file.stream.read().decode("UTF8"), newline=None)
                    csv_reader = csv.reader(stream)
                    next(csv_reader)
                    product_map = {p.name.lower(): p for p in products}

                    for row in csv_reader:
                        if len(row) >= 2:
                            product_name = row[0].strip().lower()
                            quantity_sold = float(row[1])
                            if product_name in product_map:
                                product_id = product_map[product_name].id
                                sales_from_csv[product_id] = quantity_sold

                    flash('Sales data imported from CSV. Please review the values below, complete the starting counts, and then submit.', 'success')
                except Exception as e:
                    flash(f'Error processing CSV file: {e}', 'danger')
            else:
                flash('No file selected for upload.', 'warning')

            # When uploading CSV, also pass all other relevant context
            return render_template('beginning_of_day.html',
                                   products=products,
                                   all_recipes=all_recipes_objects,
                                   all_recipes_json=json.dumps(all_recipes_json_serializable),
                                   sales_from_csv=sales_from_csv,
                                   existing_sales_for_yesterday=existing_manual_sales_for_yesterday_db,
                                   existing_cocktails_sold_for_yesterday=existing_cocktails_sold_for_yesterday_db,
                                   bod_values_to_display=bod_values_to_display,
                                   can_submit_yesterdays_sales=can_submit_yesterdays_sales,
                                   bod_for_today_already_calculated_and_saved_to_db=bod_for_today_already_calculated_and_saved_to_db,
                                   yesterday=yesterday)


        elif action == 'submit_bod':
            if not can_submit_yesterdays_sales:
                flash("Cannot submit. Yesterday's Beginning of Day data is incomplete, or today's BOD is already calculated.", 'danger')
                return redirect(url_for('beginning_of_day'))

            # 1. Save yesterday's product sales (manual products)
            for product in products:
                sales_count = request.form.get(f'sales_{product.id}')
                existing_qty_db = Sale.query.filter_by(product_id=product.id, date=yesterday).first()
                if sales_count is not None and float(sales_count) >= 0:
                    if existing_qty_db:
                        existing_qty_db.quantity_sold = float(sales_count)
                    else:
                        db.session.add(Sale(product_id=product.id, quantity_sold=float(sales_count), date=yesterday))
                elif existing_qty_db:
                    existing_qty_db.quantity_sold = 0.0

            # 2. Save yesterday's cocktail sales
            recipe_ids = request.form.getlist('cocktail_recipe_id[]')
            quantities_sold = request.form.getlist('cocktail_quantity_sold[]')

            CocktailsSold.query.filter_by(date=yesterday).delete()
            db.session.flush()

            for i in range(len(recipe_ids)):
                recipe_id = int(recipe_ids[i])
                quantity = int(quantities_sold[i])
                if quantity > 0:
                    cocktail_sold_entry = CocktailsSold(
                        recipe_id=recipe_id,
                        quantity_sold=quantity,
                        date=yesterday
                    )
                    db.session.add(cocktail_sold_entry)

            db.session.commit() # Commit yesterday's sales and cocktail sales first

            # --- Autonomous BOD Calculation for TODAY (NEW) ---
            # This logic runs *after* yesterday's sales are confirmed.
            total_ingredient_usage_yesterday_recalculated = _calculate_ingredient_usage_from_cocktails_sold(yesterday)
            yesterdays_bod_counts_recalculated = {
                b.product_id: b.amount
                for b in BeginningOfDay.query.filter_by(date=yesterday).all()
            }

            # Loop through all products to calculate and save today's BOD
            for product in products:
                y_bod = yesterdays_bod_counts_recalculated.get(product.id, 0.0)
                y_manual_sold = Sale.query.filter_by(product_id=product.id, date=yesterday).first()
                y_manual_sold_qty = y_manual_sold.quantity_sold if y_manual_sold else 0.0
                y_cocktail_usage = total_ingredient_usage_yesterday_recalculated.get(product.id, 0.0)

                todays_final_bod = y_bod - y_manual_sold_qty - y_cocktail_usage
                todays_final_bod = max(0.0, todays_final_bod) # Ensure non-negative stock

                # Save or update today's BeginningOfDay entry
                bod_entry_for_today = BeginningOfDay.query.filter_by(product_id=product.id, date=today_date).first()
                if bod_entry_for_today:
                    bod_entry_for_today.amount = todays_final_bod
                else:
                    db.session.add(BeginningOfDay(product_id=product.id, amount=todays_final_bod, date=today_date))

            db.session.commit() # Commit today's BOD calculations

            flash("Yesterday's sales recorded, and today's Beginning of Day inventory has been automatically calculated.", 'success')
            return redirect(url_for('dashboard'))

    # --- GET Request Context for rendering the template ---
    return render_template('beginning_of_day.html',
                           products=products,
                           all_recipes=all_recipes_objects,
                           all_recipes_json=json.dumps(all_recipes_json_serializable),
                           sales_from_csv=sales_from_csv,
                           existing_sales_for_yesterday=existing_manual_sales_for_yesterday_db,
                           existing_cocktails_sold_for_yesterday=existing_cocktails_sold_for_yesterday_db,
                           bod_values_to_display=bod_values_to_display, # Pass calculated/existing BOD for display
                           can_submit_yesterdays_sales=can_submit_yesterdays_sales, # Control submit button/inputs
                           bod_for_today_already_calculated_and_saved_to_db=bod_for_today_already_calculated_and_saved_to_db, # Indicate if BOD is already present for today
                           yesterday=yesterday)

@app.route('/count/<string:location_slug>', methods=['GET', 'POST'])
@login_required
def submit_count(location_slug):
    today_date = datetime.utcnow().date()
    yesterday = today_date - timedelta(days=1)

    location_name = location_slug.replace('_', ' ').title()
    location = Location.query.filter_by(name=location_name).first_or_404()
    products_in_location = location.products.order_by(Product.type, Product.name).all()
    if not products_in_location:
        flash(f'No products assigned to "{location.name}". Please contact an admin.', 'warning')
        return redirect(url_for('dashboard'))

    expected_bod_for_today_all_products = {}

    yesterdays_bod_counts = {
        b.product_id: b.amount
        for b in BeginningOfDay.query.filter_by(date=yesterday).all()
    }
    yesterdays_manual_sales = {
        s.product_id: s.quantity_sold
        for s in Sale.query.filter_by(date=yesterday).all()
    }
    yesterdays_cocktail_usage = _calculate_ingredient_usage_from_cocktails_sold(yesterday)

    for product in Product.query.all():
        y_bod = yesterdays_bod_counts.get(product.id, 0.0)
        y_manual_sold = yesterdays_manual_sales.get(product.id, 0.0)
        y_cocktail_usage = yesterdays_cocktail_usage.get(product.id, 0.0)

        calculated_eod_yesterday = y_bod - y_manual_sold - y_cocktail_usage
        expected_bod_for_today_all_products[product.id] = max(0.0, calculated_eod_yesterday)

    todays_deliveries = {
        d.product_id: d.quantity
        for d in Delivery.query.filter_by(delivery_date=today_date).all()
    }

    current_counts = {}
    all_counts_today = Count.query.filter(
        Count.location == location.name,
        func.date(Count.timestamp) == today_date
    ).order_by(Count.timestamp.asc()).all()
    for c in all_counts_today:
        current_counts[c.product_id] = c

    first_counts = {
        c.product_id: c for c in all_counts_today if c.count_type == 'First Count'
    }

    if request.method == 'POST':
        submit_type = request.form.get('submit_type')
        count_data = []
        count_type_str = 'First Count' if submit_type == 'first_count' else 'Corrections Count'

        for product in products_in_location:
            count_value = request.form.get(f'product_{product.id}')
            if count_value:
                actual_amount = float(count_value)
                comment = request.form.get(f'comment_{product.id}')

                expected_amount_at_count = expected_bod_for_today_all_products.get(product.id, 0.0)
                expected_amount_at_count += todays_deliveries.get(product.id, 0.0)

                variance = actual_amount - expected_amount_at_count

                new_count_entry = Count(
                    product_id=product.id,
                    user_id=current_user.id,
                    location=location.name,
                    count_type=count_type_str,
                    amount=actual_amount,
                    comment=comment,
                    expected_amount=expected_amount_at_count,
                    variance_amount=variance
                )

                if submit_type == 'first_count':
                    count_data.append(new_count_entry)

                elif submit_type == 'corrections_count' and request.form.get(f'correct_{product.id}'):
                    first_count_submitter = first_counts.get(product.id)

                    is_self_correcting = (first_count_submitter and
                                          first_count_submitter.user_id == current_user.id)

                    if not is_self_correcting:
                        count_data.append(new_count_entry)
                    else:
                        log_activity(f"Skipped self-correction attempt by {current_user.username} for product {product.name}.")

        if count_data:
            db.session.add_all(count_data)
            db.session.commit()
            flash(f'{count_type_str} submitted successfully!', 'success')

            general_count_notification_title = f"Inventory Count Submitted: {location.name}"
            general_count_notification_message = (
                f"{current_user.full_name} submitted a {count_type_str.lower()} for {location.name}. "
                f"Review the latest counts and variances."
            )
            general_count_announcement = Announcement(
                user_id=current_user.id,
                title=general_count_notification_title,
                message=general_count_notification_message,
                category='Urgent',
                target_roles=Role.query.filter(Role.name.in_(['manager', 'general_manager', 'system_admin'])).all()
            )
            db.session.add(general_count_announcement)

            for entry in count_data:
                if entry.variance_amount is not None and entry.variance_amount != 0:
                    variance_notification_title = "Significant Inventory Variance Detected"
                    variance_notification_message = (
                        f"Variance of {entry.variance_amount:.2f} {entry.product.unit_of_measure} detected "
                        f"for {entry.product.name} in {entry.location} by {current_user.full_name} "
                        f"during a {entry.count_type}. Expected: {entry.expected_amount:.2f}, Actual: {entry.amount:.2f}. "
                        f"Action required."
                    )
                    variance_announcement = Announcement(
                        user_id=current_user.id,
                        title=variance_notification_title,
                        message=variance_notification_message,
                        category='Urgent',
                        target_roles=Role.query.filter(Role.name.in_(['manager', 'general_manager', 'system_admin'])).all()
                    )
                    db.session.add(variance_announcement)
            db.session.commit()

        else:
            flash('No new count data was submitted.', 'info')

        return redirect(url_for('dashboard'))

    # NEW: Fetch all distinct product types for the filter dropdown
    all_product_types = db.session.query(distinct(Product.type)).order_by(Product.type).all()
    all_product_types = [t[0] for t in all_product_types]

    return render_template('count.html',
                           products=products_in_location,
                           location=location,
                           current_counts=current_counts,
                           first_counts=first_counts,
                           all_product_types=all_product_types)

# ==============================================================================
# Reporting Routes
# ==============================================================================

@app.route('/daily_summary', methods=['GET'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin','owners'])
def daily_summary():
    # Allow selection of report date, default to today
    report_date_str = request.args.get('date', datetime.utcnow().date().isoformat())
    try:
        report_date = datetime.strptime(report_date_str, '%Y-%m-%d').date()
    except ValueError:
        flash("Invalid date format.", 'danger')
        report_date = datetime.utcnow().date()
        report_date_str = report_date.isoformat()

    day_before_report_date = report_date - timedelta(days=1) # This is 'yesterday' for BOD source

    products = Product.query.order_by(Product.type, Product.name).all()

    # --- Data Collection for the Report Date ---
    # 1. Beginning of Day (BOD) for the report_date
    #    This should be the autonomously calculated BOD for `report_date`
    bod_counts = {
        b.product_id: b.amount
        for b in BeginningOfDay.query.filter_by(date=report_date).all()
    }

    # 2. Deliveries for the report_date
    deliveries_for_day = {
        d.product_id: d.quantity
        for d in Delivery.query.filter_by(delivery_date=report_date).all()
    }

    # 3. Manual Sales for the report_date
    manual_sales_for_day = {
        s.product_id: s.quantity_sold
        for s in Sale.query.filter_by(date=report_date).all()
    }

    # 4. Cocktail Ingredient Usage for the report_date
    cocktail_usage_for_day = _calculate_ingredient_usage_from_cocktails_sold(report_date)

    # 5. End of Day (EOD) Actual from latest counts for the report_date
    eod_actual_counts = {} # {product_id: latest_count_amount}
    eod_latest_count_objects = {} # {product_id: Count_object} for accessing stored variance_amount

    all_counts_on_report_date = Count.query.filter(func.date(Count.timestamp) == report_date).all()

    for count in all_counts_on_report_date:
        product_id = count.product_id
        # Take the latest count for a given product on that day as the EOD actual
        if product_id not in eod_latest_count_objects or count.timestamp > eod_latest_count_objects[product_id].timestamp:
            eod_actual_counts[product_id] = count.amount
            eod_latest_count_objects[product_id] = count


    summary_data = []
    for product in products:
        bod = bod_counts.get(product.id, 0.0)
        deliveries = deliveries_for_day.get(product.id, 0.0)
        manual_sales = manual_sales_for_day.get(product.id, 0.0)
        cocktail_usage = cocktail_usage_for_day.get(product.id, 0.0)

        # Expected stock available during the day (before sales, after BOD+Deliveries)
        expected_stock_available = bod + deliveries

        # Total sales/usage for the day (manual sales + cocktail usage)
        total_usage_for_day = manual_sales + cocktail_usage

        # Expected EOD = BOD + Deliveries - Total Usage
        expected_eod = expected_stock_available - total_usage_for_day

        actual_eod = eod_actual_counts.get(product.id, None) # Can be None if no count was done

        variance_val = None
        loss_value = None

        latest_count_obj = eod_latest_count_objects.get(product.id)
        if latest_count_obj and latest_count_obj.variance_amount is not None:
            # Use the pre-calculated variance from the latest Count object for that day
            variance_val = latest_count_obj.variance_amount
        elif actual_eod is not None:
            # If actual_eod exists but no variance_amount was stored with it, calculate it
            variance_val = actual_eod - expected_eod

        if variance_val is not None and product.unit_price is not None:
            loss_value = variance_val * product.unit_price


        summary_data.append({
            'name': product.name,
            'unit': product.unit_of_measure,
            'bod': bod,
            'deliveries': deliveries,
            'manual_sales': manual_sales,
            'cocktail_usage': cocktail_usage,
            'total_usage_for_day': total_usage_for_day,
            'expected_eod': max(0.0, expected_eod), # Ensure non-negative display
            'actual_eod': actual_eod,
            'variance': variance_val,
            'loss_value': loss_value
        })

    return render_template('daily_summary.html',
                           summary_data=summary_data,
                           report_date_str=report_date_str,
                           report_date=report_date)

@app.route('/variance')
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'owners'])
def variance():
    today = datetime.utcnow().date() # Report date defaults to today

    # Allow selection of report date, default to today
    report_date_str = request.args.get('date', datetime.utcnow().date().isoformat())
    try:
        report_date = datetime.strptime(report_date_str, '%Y-%m-%d').date()
    except ValueError:
        flash("Invalid date format.", 'danger')
        report_date = datetime.utcnow().date()
        report_date_str = report_date.isoformat()

    # Fetch all counts for the report_date that have a non-zero variance_amount
    # OR where correction amount is different from first count amount (if applicable)

    # We need all counts to correctly determine first vs correction, and to get the latest.
    all_counts_on_report_date = Count.query.filter(
        func.date(Count.timestamp) == report_date
    ).order_by(Count.product_id, Count.location, Count.timestamp).all() # Order helps identify first/latest

    variance_report_data = {} # { (product_id, location_name): { ... data ... } }

    # Group counts by product and location
    grouped_counts = {}
    for count in all_counts_on_report_date:
        key = (count.product_id, count.location)
        if key not in grouped_counts:
            grouped_counts[key] = []
        grouped_counts[key].append(count)

    for (product_id, location_name), counts_for_product_location in grouped_counts.items():
        first_count_entry = None
        correction_count_entry = None

        # Sort to ensure we get true 'First Count' and latest 'Corrections Count'
        counts_for_product_location.sort(key=lambda c: c.timestamp)

        for c in counts_for_product_location:
            if c.count_type == 'First Count':
                first_count_entry = c
            elif c.count_type == 'Corrections Count':
                correction_count_entry = c # Keep the latest correction

        # The 'final' count for display and explanation is the correction if it exists, otherwise the first.
        final_count_entry = correction_count_entry if correction_count_entry else first_count_entry

        # Only proceed if there's an actual count and it has a variance or difference
        if not final_count_entry:
            continue

        # Check for conditions to include in the report
        has_significant_variance = (
            final_count_entry.variance_amount is not None and
            final_count_entry.variance_amount != 0
        )
        has_correction_difference = ( # Still include if correction changed from first, even if variance is zero
            correction_count_entry is not None and
            first_count_entry is not None and
            correction_count_entry.amount != first_count_entry.amount
        )

        if has_significant_variance or has_correction_difference:
            variance_report_data[(product_id, location_name)] = {
                'location': location_name,
                'product_name': final_count_entry.product.name,
                'product_unit': final_count_entry.product.unit_of_measure,
                'first_count_amount': first_count_entry.amount if first_count_entry else None,
                'first_count_by': first_count_entry.user.full_name if first_count_entry and first_count_entry.user else None,
                'correction_amount': correction_count_entry.amount if correction_count_entry else None,
                'correction_by': correction_count_entry.user.full_name if correction_count_entry and correction_count_entry.user else None,
                'expected_amount': final_count_entry.expected_amount, # From Count model
                'variance_amount': final_count_entry.variance_amount, # From Count model (Actual - Expected)
                'count_id_for_explanation': final_count_entry.id, # The ID of the count entry to explain
                'explanation': final_count_entry.variance_explanation.reason if final_count_entry.variance_explanation else None, # Link explanation
                'explanation_by': final_count_entry.variance_explanation.user.full_name if final_count_entry.variance_explanation and final_count_entry.variance_explanation.user else None,
            }

    sorted_variance_list = sorted(list(variance_report_data.values()), key=lambda x: (x['location'], x['product_name']))

    return render_template('variance.html',
                           variance_data=sorted_variance_list,
                           report_date_str=report_date_str,
                           report_date=report_date)

@app.route('/reports', methods=['GET'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'owners'])
def reports():
    start_date_str = request.args.get('start_date', (datetime.utcnow().date() - timedelta(days=7)).isoformat())
    end_date_str = request.args.get('end_date', datetime.utcnow().date().isoformat())

    try:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
    except ValueError:
        flash("Invalid date format for start or end date.", 'danger')
        start_date = datetime.utcnow().date() - timedelta(days=7)
        end_date = datetime.utcnow().date()

    all_activities = []

    # 1. BeginningOfDay records
    bod_entries = BeginningOfDay.query.filter(BeginningOfDay.date.between(start_date, end_date)).all()
    for bod in bod_entries:
        all_activities.append({
            'type': 'BOD',
            'timestamp': datetime.combine(bod.date, datetime.min.time()),
            'product_name': bod.product.name,
            'product_unit': bod.product.unit_of_measure,
            'quantity': bod.amount,
            'details': f"Calculated/Set Beginning of Day stock",
            'user': 'System'
        })

    # 2. Counts (First and Corrections)
    count_entries = Count.query.filter(func.date(Count.timestamp).between(start_date, end_date)).all()
    for count in count_entries:
        variance_display = ""
        if count.variance_amount is not None:
            variance_display = f" (Variance: {count.variance_amount:.2f})"
            if count.variance_amount != 0:
                explanation = VarianceExplanation.query.filter_by(count_id=count.id).first()
                if explanation:
                    variance_display += f" - Reason: {explanation.reason}"
                else:
                    variance_display += " - No Explanation"

        # --- MODIFIED: Handle None for count.expected_amount ---
        expected_amount_display = f"{count.expected_amount:.2f}" if count.expected_amount is not None else "N/A"
        # --- END MODIFIED ---

        all_activities.append({
            'type': count.count_type,
            'timestamp': count.timestamp,
            'product_name': count.product.name,
            'product_unit': count.product.unit_of_measure,
            'quantity': count.amount,
            # --- MODIFIED: Use expected_amount_display ---
            'details': f"Counted {count.amount:.2f} {count.product.unit_of_measure}. Expected: {expected_amount_display}{variance_display}",
            'user': count.user.full_name,
            'location': count.location
        })

    # 3. Deliveries
    delivery_entries = Delivery.query.filter(Delivery.delivery_date.between(start_date, end_date)).all()
    for delivery in delivery_entries:
        all_activities.append({
            'type': 'Delivery',
            'timestamp': delivery.timestamp,
            'product_name': delivery.product.name,
            'product_unit': delivery.product.unit_of_measure,
            'quantity': delivery.quantity,
            'details': f"Received {delivery.quantity:.2f} {delivery.product.unit_of_measure}. Comment: {delivery.comment or 'N/A'}",
            'user': delivery.user.full_name
        })

    # 4. Manual Sales
    sale_entries = Sale.query.filter(Sale.date.between(start_date, end_date)).all()
    for sale in sale_entries:
        all_activities.append({
            'type': 'Manual Sale',
            'timestamp': datetime.combine(sale.date, datetime.min.time()),
            'product_name': sale.product.name,
            'product_unit': sale.product.unit_of_measure,
            'quantity': -sale.quantity_sold,
            'details': f"Sold {sale.quantity_sold:.2f} {sale.product.unit_of_measure}",
            'user': 'System'
        })

    # 5. Cocktails Sold (for ingredient usage)
    cocktails_sold_entries = CocktailsSold.query.filter(CocktailsSold.date.between(start_date, end_date)).all()
    for cs in cocktails_sold_entries:
        all_activities.append({
            'type': 'Cocktail Sale',
            'timestamp': datetime.combine(cs.date, datetime.min.time()),
            'product_name': cs.recipe.name,
            'product_unit': 'cocktails',
            'quantity': -cs.quantity_sold,
            'details': f"Sold {cs.quantity_sold} of '{cs.recipe.name}'. Ingredients deducted automatically.",
            'user': 'System'
        })
        for ri in cs.recipe.recipe_ingredients:
            ingredient_deduction = ri.quantity * cs.quantity_sold
            all_activities.append({
                'type': 'Ingredient Deduction',
                'timestamp': datetime.combine(cs.date, datetime.min.time()),
                'product_name': ri.product.name,
                'product_unit': ri.product.unit_of_measure,
                'quantity': -ingredient_deduction,
                'details': f"Deducted for {cs.quantity_sold} of '{cs.recipe.name}' sold",
                'user': 'System'
            })

    all_activities.sort(key=lambda x: x['timestamp'])

    return render_template('reports.html',
                           report_data=all_activities,
                           start_date=start_date_str,
                           end_date=end_date_str)

@app.route('/historical_report', methods=['GET'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'owners'])
def historical_report():
    products = Product.query.order_by(Product.name).all()
    return render_template('historical_report.html', products=products)



@app.route('/variance_explanations')
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'owners']) # Roles that can view this report
def variance_explanations():
    # Fetch all variance explanations, ordering by timestamp
    # Eagerly load related `count`, `product`, `user` (for count), and `user` (for explanation)
    explanations = VarianceExplanation.query \
        .join(Count) \
        .join(Product, Count.product_id == Product.id) \
        .join(User, VarianceExplanation.user_id == User.id) \
        .order_by(VarianceExplanation.timestamp.desc()) \
        .all()

    # We will need to calculate the actual variance here to display it
    # Variance = Count.amount - (Calculated_Expected_Stock_at_time_of_count)
    # For now, let's just show the count.amount and product info,
    # The full Expected Stock calculation will come in Phase 2.
    # For this report, we'll aim to show: Date, Location, Product, Recorded Count, Reason, Explained By.


    return render_template('variance_explanations.html', explanations=explanations)

@app.route('/explain_variance/<int:count_id>', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin']) # Only managers/admins can explain variances
def explain_variance(count_id):
    count_entry = Count.query.get_or_404(count_id)

    # Check if an explanation already exists for this count
    existing_explanation = VarianceExplanation.query.filter_by(count_id=count_id).first()

    if request.method == 'POST':
        reason = request.form.get('reason')

        if not reason:
            flash('Reason for variance cannot be empty.', 'danger')
            # If coming from a modal, may need to handle this differently, or re-render a small form.
            # For simplicity, redirect back to variance report.
            return redirect(url_for('variance'))

        if existing_explanation:
            existing_explanation.reason = reason
            existing_explanation.timestamp = datetime.utcnow()
            existing_explanation.user_id = current_user.id
            flash('Variance explanation updated successfully!', 'success')
            log_activity(f"Updated variance explanation for Count ID {count_id} (Product: {count_entry.product.name}).")
        else:
            new_explanation = VarianceExplanation(
                count_id=count_id,
                reason=reason,
                user_id=current_user.id
            )
            db.session.add(new_explanation)
            flash('Variance explanation recorded successfully!', 'success')
            log_activity(f"Recorded variance explanation for Count ID {count_id} (Product: {count_entry.product.name}).")

        db.session.commit()
        return redirect(url_for('variance'))

    # For GET request (e.g., if we were to render a standalone page for this)
    # For now, this route primarily acts as a POST endpoint for a modal form.
    # We will pass this info to a modal.
    return render_template(
        'variance_explanation_modal_content.html', # Create a small partial template for the modal
        count_entry=count_entry,
        existing_explanation=existing_explanation
    )

# ==============================================================================
# Recipe Book Routes
# ==============================================================================

@app.route('/recipes')
@login_required
@role_required(['system_admin', 'manager', 'bartender'])
def recipes():
    all_recipes = Recipe.query.order_by(Recipe.name).all()
    return render_template('recipes.html', recipes=all_recipes)

@app.route('/recipes/add', methods=['GET', 'POST'])
@login_required
@role_required(['system_admin', 'manager'])
def add_recipe():
    products = Product.query.order_by(Product.name).all() # Fetch all products for dropdown

    if request.method == 'POST':
        name = request.form.get('name')
        instructions = request.form.get('instructions')

        # Check if a recipe with this name already exists
        if Recipe.query.filter_by(name=name).first():
            flash(f'A recipe named "{name}" already exists. Please choose a different name.', 'danger')
            return render_template('add_recipe.html', products=products) # Re-render with error

        new_recipe = Recipe(name=name, instructions=instructions, user_id=current_user.id)
        db.session.add(new_recipe)
        db.session.flush() # Flush to get new_recipe.id before adding ingredients

        # Process ingredients from the form
        ingredient_ids = request.form.getlist('ingredient_id[]')
        quantities = request.form.getlist('quantity[]')

        for i in range(len(ingredient_ids)):
            product_id = int(ingredient_ids[i])
            quantity_value = float(quantities[i])
            if quantity_value > 0: # Only add if quantity is positive
                recipe_ingredient = RecipeIngredient(
                    recipe_id=new_recipe.id,
                    product_id=product_id,
                    quantity=quantity_value
                )
                db.session.add(recipe_ingredient)

        db.session.commit()
        log_activity(f"Created new recipe: '{name}'.")
        flash('Recipe added successfully!', 'success')
        return redirect(url_for('recipes'))

    return render_template('add_recipe.html', products=products)

@app.route('/recipes/edit/<int:recipe_id>', methods=['GET', 'POST'])
@login_required
@role_required(['system_admin', 'manager'])
def edit_recipe(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    products = Product.query.order_by(Product.name).all() # Fetch all products for dropdown

    # Check authorization (existing logic)
    if recipe.user_id != current_user.id and not current_user.has_role('system_admin') and not current_user.has_role('general_manager'):
        flash('You are not authorized to edit this recipe.', 'danger')
        return redirect(url_for('recipes'))

    if request.method == 'POST':
        recipe.name = request.form.get('name')
        recipe.instructions = request.form.get('instructions')

        # Check for duplicate name if changed (excluding itself)
        existing_recipe_with_name = Recipe.query.filter(Recipe.name == recipe.name, Recipe.id != recipe_id).first()
        if existing_recipe_with_name:
            flash(f'A recipe named "{recipe.name}" already exists. Please choose a different name.', 'danger')
            return render_template('edit_recipe.html', recipe=recipe, products=products)


        # Process and update ingredients
        # First, delete all existing ingredients for this recipe
        RecipeIngredient.query.filter_by(recipe_id=recipe.id).delete()
        db.session.flush() # Ensure deletions are processed before new insertions

        ingredient_ids = request.form.getlist('ingredient_id[]')
        quantities = request.form.getlist('quantity[]')

        for i in range(len(ingredient_ids)):
            product_id = int(ingredient_ids[i])
            quantity_value = float(quantities[i])
            if quantity_value > 0: # Only add if quantity is positive
                recipe_ingredient = RecipeIngredient(
                    recipe_id=recipe.id,
                    product_id=product_id,
                    quantity=quantity_value
                )
                db.session.add(recipe_ingredient)

        db.session.commit()
        log_activity(f"Edited recipe: '{recipe.name}'.")
        flash('Recipe updated successfully!', 'success')
        return redirect(url_for('recipes'))

    # For GET request, fetch existing ingredients for pre-population
    existing_ingredients = RecipeIngredient.query.filter_by(recipe_id=recipe.id).all()

    return render_template('edit_recipe.html',
                           recipe=recipe,
                           products=products,
                           existing_ingredients=existing_ingredients)

@app.route('/recipes/delete/<int:recipe_id>', methods=['POST'])
@login_required
@role_required(['system_admin', 'manager'])
def delete_recipe(recipe_id):
    recipe = Recipe.query.get_or_404(recipe_id)
    if recipe.user_id != current_user.id and not current_user.has_role('system_admin'):
        flash('You are not authorized to delete this recipe.', 'danger')
        return redirect(url_for('recipes'))

    log_activity(f"Deleted recipe: '{recipe.name}'.")
    db.session.delete(recipe)
    db.session.commit()
    flash('Recipe deleted successfully.', 'success')
    return redirect(url_for('recipes'))

# ==============================================================================
# Scheduling Routes
# ==============================================================================

@app.route('/shifts_today', methods=['GET']) # <--- Define a clean URL path
@login_required
@role_required(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners'])
def shifts_today(): # <--- This is the endpoint name for url_for('shifts_today')
    today_date = datetime.utcnow().date()

    # Group users by role for display, similar to consolidated schedules
    manager_users = User.query.join(User.roles).filter(
        Role.name.in_(['manager', 'general_manager', 'system_admin'])
    ).order_by(User.full_name).all()

    bartender_users = User.query.join(User.roles).filter(Role.name == 'bartender').order_by(User.full_name).all()
    waiter_users = User.query.join(User.roles).filter(Role.name == 'waiter').order_by(User.full_name).all()
    skuller_users = User.query.join(User.roles).filter(Role.name == 'skullers').order_by(User.full_name).all()

    # Fetch published shifts for today for all relevant users
    all_shifts_today_raw = Schedule.query.filter(
        Schedule.shift_date == today_date,
        Schedule.published == True
    ).all()

    shifts_by_role_categorized = {
        'Managers': [],
        'Bartenders': [],
        'Waiters': [],
        'Skullers': []
    }
    
    # Use a dict to easily look up user details for shift
    users_lookup = {user.id: user for user in User.query.all()}

    for shift in all_shifts_today_raw:
        user = users_lookup.get(shift.user_id)
        if not user:
            continue # Skip if user not found

        user_roles_names = [r.name for r in user.roles]
        shift_info = {
            'user_name': user.full_name,
            'roles': ', '.join([r.replace('_', ' ').title() for r in user_roles_names]),
            'assigned_shift': shift.assigned_shift,
            'time_display': get_shift_time_display(
                # Determine role for time display (take first relevant one)
                'bartender' if 'bartender' in user_roles_names else
                'waiter' if 'waiter' in user_roles_names else
                'skullers' if 'skullers' in user_roles_names else
                'manager', # Fallback for managers
                today_date.strftime('%A'),
                shift.assigned_shift,
                custom_start=shift.start_time_str,
                custom_end=shift.end_time_str
            )
        }

        if any(role in ['manager', 'general_manager', 'system_admin'] for role in user_roles_names):
            shifts_by_role_categorized['Managers'].append(shift_info)
        if 'bartender' in user_roles_names:
            shifts_by_role_categorized['Bartenders'].append(shift_info)
        if 'waiter' in user_roles_names:
            shifts_by_role_categorized['Waiters'].append(shift_info)
        if 'skullers' in user_roles_names:
            shifts_by_role_categorized['Skullers'].append(shift_info)
     
    # Sort categories for consistent display
    sorted_role_categories = ['Managers', 'Bartenders', 'Waiters', 'Skullers']

    return render_template(
        'daily_shifts.html',
        today_date=today_date,
        shifts_by_role_categorized=shifts_by_role_categorized,
        sorted_role_categories=sorted_role_categories # To maintain order
    )

@app.route('/manage-required-staff/<string:role_name><optional_int:week_offset>', methods=['GET', 'POST'])
@login_required
@role_required(['scheduler', 'manager', 'general_manager', 'system_admin'])
def manage_required_staff(role_name, week_offset): # Removed week_offset=0 from signature
    start_of_week, week_dates, _, _ = _build_week_dates(week_offset=week_offset)

    if request.method == 'POST':
        for day in week_dates:
            min_staff_key = f'min_staff_{day.isoformat()}'
            max_staff_key = f'max_staff_{day.isoformat()}'

            min_staff_value = request.form.get(min_staff_key, type=int)
            max_staff_value = request.form.get(max_staff_key, type=int)

            if min_staff_value is not None or max_staff_value is not None:
                min_staff_value = max(0, min_staff_value) if min_staff_value is not None else None
                max_staff_value = max(0, max_staff_value) if max_staff_value is not None else None

                if min_staff_value is not None and max_staff_value is not None and max_staff_value < min_staff_value:
                    flash(f'Max staff for {day.strftime("%Y-%m-%d")} cannot be less than min staff. Please correct.', 'danger')
                    existing_minimums = {
                        rs.shift_date.isoformat(): {'min_staff': rs.min_staff, 'max_staff': rs.max_staff}
                        for rs in RequiredStaff.query.filter_by(role_name=role_name)
                                                     .filter(RequiredStaff.shift_date.in_(week_dates))
                                                     .all()
                    }
                    return render_template('manage_required_staff.html',
                                           week_dates=week_dates,
                                           role_name=role_name,
                                           existing_minimums=existing_minimums,
                                           display_dates=[d for d in week_dates if d.weekday() != 0],
                                           current_week_offset=week_offset)

                required_staff_entry = RequiredStaff.query.filter_by(
                    role_name=role_name,
                    shift_date=day
                ).first()

                if required_staff_entry:
                    required_staff_entry.min_staff = min_staff_value if min_staff_value is not None else required_staff_entry.min_staff
                    required_staff_entry.max_staff = max_staff_value
                else:
                    new_entry = RequiredStaff(
                        role_name=role_name,
                        shift_date=day,
                        min_staff=min_staff_value if min_staff_value is not None else 0,
                        max_staff=max_staff_value
                    )
                    db.session.add(new_entry)

        db.session.commit()
        flash(f'Staff requirements for {role_name.title()} updated successfully.', 'success')

        scheduler_endpoint_name = f'scheduler_{role_name}s'
        return redirect(url_for(scheduler_endpoint_name, week_offset=week_offset))

    # GET request: Load existing minimums and maximums
    existing_minimums = {
        rs.shift_date.isoformat(): {'min_staff': rs.min_staff, 'max_staff': rs.max_staff}
        for rs in RequiredStaff.query.filter_by(role_name=role_name)
                                     .filter(RequiredStaff.shift_date.in_(week_dates))
                                     .all()
    }

    return render_template('manage_required_staff.html',
                           week_dates=week_dates,
                           role_name=role_name,
                           existing_minimums=existing_minimums,
                           display_dates=[d for d in week_dates if d.weekday() != 0],
                           current_week_offset=week_offset)

@app.route('/submit-shifts', methods=['GET', 'POST'])
@login_required
@role_required(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin'])
def submit_shifts():
    current_today = datetime.utcnow().date()

    days_until_next_monday = (0 - current_today.weekday() + 7) % 7
    next_monday_date = current_today + timedelta(days=days_until_next_monday)

    next_week_dates = [next_monday_date + timedelta(days=i) for i in range(7)]

    submission_window_start_date = next_monday_date - timedelta(weeks=1) + timedelta(days=1)
    submission_window_end_date = next_monday_date

    submission_window_start = datetime.combine(submission_window_start_date, time(10, 0, 0)) # Current Tuesday 10 AM UTC
    submission_window_end = datetime.combine(submission_window_end_date, time(12, 0, 0)) # Next Monday 12 PM UTC (noon) UTC

    current_utc_time = datetime.utcnow()
    is_submission_window_open = (current_utc_time >= submission_window_start and
                                 current_utc_time <= submission_window_end)

    # These timedelta objects are no longer needed directly by the template for the timer.
    # The template will use the ISO string formats of submission_window_start/end.
    # time_until_window_opens = None
    # time_until_window_closes = None
    # if current_utc_time < submission_window_start:
    #     time_until_window_opens = submission_window_start - current_utc_time
    # elif current_utc_time < submission_window_end:
    #     time_until_window_closes = submission_window_end - current_utc_time

    staff_submission_shift_types = ['Day', 'Night']

    existing_submissions = ShiftSubmission.query.filter(
        ShiftSubmission.user_id == current_user.id,
        ShiftSubmission.shift_date.in_(next_week_dates)
    ).all()

    existing_set_for_display = set()
    for s in existing_submissions:
        if s.shift_type == 'Double':
            existing_set_for_display.add(f"{s.shift_date.isoformat()}_Day")
            existing_set_for_display.add(f"{s.shift_date.isoformat()}_Night")
        else:
            existing_set_for_display.add(f"{s.shift_date.isoformat()}_{s.shift_type}")


    if request.method == 'POST':
        if not is_submission_window_open:
            flash(f"Availability can only be submitted from {submission_window_start|to_local_time('%A, %b %d at %I:%M %p')} to {submission_window_end|to_local_time('%A, %b %d at %I:%M %p')} (your local time). Window is currently closed.", 'danger')
            return render_template('submit_shifts.html',
                                   week_dates=next_week_dates,
                                   shift_types=staff_submission_shift_types,
                                   existing_set=existing_set_for_display,
                                   today=current_today,
                                   is_submission_window_open=is_submission_window_open,
                                   submission_window_start=submission_window_start.isoformat(), # Pass ISO format
                                   submission_window_end=submission_window_end.isoformat()) # Pass ISO format


        submitted_shifts_raw = request.form.getlist('shifts')

        processed_shifts = {}
        for shift_str in submitted_shifts_raw:
            date_str, shift_type = shift_str.split('_')

            submitted_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            if submitted_date < current_today:
                flash(f"Cannot submit availability for past date: {submitted_date.strftime('%Y-%m-%d')}.", 'danger')
                return render_template('submit_shifts.html',
                                   week_dates=next_week_dates,
                                   shift_types=staff_submission_shift_types,
                                   existing_set=existing_set_for_display,
                                   today=current_today,
                                   is_submission_window_open=is_submission_window_open,
                                   submission_window_start=submission_window_start.isoformat(),
                                   submission_window_end=submission_window_end.isoformat())


            if date_str not in processed_shifts:
                processed_shifts[date_str] = set()
            processed_shifts[date_str].add(shift_type)

        final_shifts_to_store = []
        for date_str, types_for_day in processed_shifts.items():
            if 'Day' in types_for_day and 'Night' in types_for_day:
                final_shifts_to_store.append((date_str, 'Double'))
            else:
                for shift_type in types_for_day:
                    final_shifts_to_store.append((date_str, shift_type))

        ShiftSubmission.query.filter(
            ShiftSubmission.user_id == current_user.id,
            ShiftSubmission.shift_date.in_(next_week_dates)
        ).delete()
        db.session.flush()

        for date_str, shift_type in final_shifts_to_store:
            shift_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            if shift_date in next_week_dates:
                submission = ShiftSubmission(user_id=current_user.id, shift_date=shift_date, shift_type=shift_type)
                db.session.add(submission)
            else:
                flash(f"Submitted availability for {shift_date.strftime('%Y-%m-%d')} is outside the current submission period for the next week's schedule.", 'danger')
                db.session.rollback()
                return render_template('submit_shifts.html',
                                   week_dates=next_week_dates,
                                   shift_types=staff_submission_shift_types,
                                   existing_set=existing_set_for_display,
                                   today=current_today,
                                   is_submission_window_open=is_submission_window_open,
                                   submission_window_start=submission_window_start.isoformat(),
                                   submission_window_end=submission_window_end.isoformat())

        db.session.commit()
        log_activity(f"Updated their shift availability, consolidating Day+Night to Double where applicable.")
        flash('Your shift availability has been submitted successfully!', 'success')
        return redirect(url_for('dashboard'))

    return render_template('submit_shifts.html',
                           week_dates=next_week_dates,
                           shift_types=staff_submission_shift_types,
                           existing_set=existing_set_for_display,
                           today=current_today,
                           is_submission_window_open=is_submission_window_open,
                           submission_window_start=submission_window_start.isoformat(), # Pass ISO format
                           submission_window_end=submission_window_end.isoformat()) # Pass ISO format

@app.route('/scheduler/bartenders<optional_int:week_offset>', methods=['GET', 'POST'])
@login_required
@role_required(['scheduler', 'manager', 'general_manager', 'system_admin'])
def scheduler_bartenders(week_offset): # Removed week_offset=0 from signature
    if request.method == 'POST':
        success = _process_schedule_post_request('bartender', request.form, week_offset)
        if success:
            return redirect(url_for('scheduler_bartenders', week_offset=week_offset))
        else:
            return _render_scheduler_for_role('bartender', 'Bartender', week_offset)

    return _render_scheduler_for_role('bartender', 'Bartender', week_offset)


@app.route('/scheduler/waiters<optional_int:week_offset>', methods=['GET', 'POST'])
@login_required
@role_required(['scheduler', 'manager', 'general_manager', 'system_admin'])
def scheduler_waiters(week_offset): # Removed week_offset=0 from signature
    if request.method == 'POST':
        success = _process_schedule_post_request('waiter', request.form, week_offset)
        if success:
            return redirect(url_for('scheduler_waiters', week_offset=week_offset))
        else:
            return _render_scheduler_for_role('waiter', 'Waiter', week_offset)

    return _render_scheduler_for_role('waiter', 'Waiter', week_offset)


@app.route('/scheduler/skullers<optional_int:week_offset>', methods=['GET', 'POST'])
@login_required
@role_required(['scheduler', 'manager', 'general_manager', 'system_admin'])
def scheduler_skullers(week_offset): # Removed week_offset=0 from signature
    if request.method == 'POST':
        success = _process_schedule_post_request('skullers', request.form, week_offset)
        if success:
            return redirect(url_for('scheduler_skullers', week_offset=week_offset))
        else:
            return _render_scheduler_for_role('skullers', 'Skuller', week_offset)

    return _render_scheduler_for_role('skullers', 'Skuller', week_offset)


@app.route('/scheduler/managers<optional_int:week_offset>', methods=['GET', 'POST'])
@login_required
@role_required(['scheduler', 'manager', 'general_manager', 'system_admin'])
def scheduler_managers(week_offset): # Removed week_offset=0 from signature
    if request.method == 'POST':
        success = _process_schedule_post_request('manager', request.form, week_offset)
        if success:
            return redirect(url_for('scheduler_managers', week_offset=week_offset))
        else:
            return _render_scheduler_for_role('manager', 'Manager', week_offset)

    return _render_scheduler_for_role('manager', 'Manager', week_offset)


@app.route('/scheduler', methods=['GET'])
@login_required
def scheduler():
    # Dispatch to role-specific scheduler pages.
    # Prioritize roles with dedicated scheduler pages for direct access.
    # Default to week_offset=0
    if (current_user.has_role('bartender') or current_user.has_role('scheduler') or
        current_user.has_role('manager') or current_user.has_role('general_manager') or
        current_user.has_role('system_admin')):
        # Explicitly pass week_offset=0
        return redirect(url_for('scheduler_bartenders', week_offset=0))
    if current_user.has_role('waiter'):
        # Explicitly pass week_offset=0
        return redirect(url_for('scheduler_waiters', week_offset=0))
    if current_user.has_role('skullers'):
        # Explicitly pass week_offset=0
        return redirect(url_for('scheduler_skullers', week_offset=0))

    flash('Access denied. You do not have permission to view the scheduler.', 'danger')
    return redirect(url_for('dashboard'))

@app.route('/my_schedule')
@login_required
def my_schedule():
    view_type = request.args.get('view', 'personal')

    # Use _build_week_dates with default 0 offset for 'current' week
    _, week_dates, week_end, _ = _build_week_dates(week_offset=0)
    week_start = week_dates[0]

    shifts_query = Schedule.query.filter(
        Schedule.shift_date >= week_start,
        Schedule.shift_date <= week_end,
        Schedule.published == True
    )

    if view_type != 'personal':
        target_roles = []
        consolidated_label = ""
        display_role_name_for_rules = ""

        if view_type == 'boh':
            target_roles = ['bartender', 'skullers']
            consolidated_label = "Back of House (BOH) Schedule"
            display_role_name_for_rules = 'bartender' # Use bartender rules for BOH section
        elif view_type == 'foh':
            target_roles = ['waiter']
            consolidated_label = "Front of House (FOH) Schedule"
            display_role_name_for_rules = 'waiter'
        elif view_type == 'managers':
            target_roles = ['manager', 'general_manager']
            consolidated_label = "Managers Schedule"
            display_role_name_for_rules = 'manager'
        elif view_type == 'bartenders':
            target_roles = ['bartender']
            consolidated_label = "Bartenders Only Schedule"
            display_role_name_for_rules = 'bartender'
        elif view_type == 'waiters':
            target_roles = ['waiter']
            consolidated_label = "Waiters Only Schedule"
            display_role_name_for_rules = 'waiter'
        elif view_type == 'skullers':
            target_roles = ['skullers']
            consolidated_label = "Skullers Only Schedule"
            display_role_name_for_rules = 'skullers'
        else:
            flash(f"Unknown schedule view type: {view_type}", "warning")
            return redirect(url_for('my_schedule', view='personal'))

        bartender_users_for_display = []
        skuller_users_for_display = []
        staff_users_for_display_generic = []
        manager_users_for_display = []

        if view_type == 'boh':
            bartender_users_for_display = User.query.join(User.roles).filter(Role.name == 'bartender').order_by(User.full_name).all()
            skuller_users_for_display = User.query.join(User.roles).filter(Role.name == 'skullers').order_by(User.full_name).all()
            combined_staff_for_query = bartender_users_for_display + skuller_users_for_display
        elif target_roles:
            non_manager_target_roles = [r for r in target_roles if r not in ['manager', 'general_manager']]
            if non_manager_target_roles:
                staff_users_for_display_generic = User.query.join(User.roles).filter(Role.name.in_(non_manager_target_roles)).order_by(User.full_name).all()

            combined_staff_for_query = staff_users_for_display_generic
        else:
            combined_staff_for_query = []

        manager_users_for_display = User.query.join(User.roles).filter(
            Role.name.in_(['manager', 'general_manager'])
        ).order_by(User.full_name).all()


        all_users_involved_for_schedule = combined_staff_for_query + manager_users_for_display
        all_user_ids_for_query = [u.id for u in all_users_involved_for_schedule]

        all_shifts = shifts_query.filter(Schedule.user_id.in_(all_user_ids_for_query)).all() if all_user_ids_for_query else []

        schedule_by_user = {}
        for user in all_users_involved_for_schedule:
            schedule_by_user[user.id] = {day: [] for day in week_dates}

        for shift in all_shifts:
            if shift.user_id in schedule_by_user:
                schedule_by_user[shift.user_id].setdefault(shift.shift_date, []).append(shift)

        schedule_by_day_for_template = {day: [] for day in week_dates}
        for shift in all_shifts:
            schedule_by_day_for_template.setdefault(shift.shift_date, []).append(shift)


        return render_template(
            'my_schedule.html',
            bartender_users=bartender_users_for_display,
            skuller_users=skuller_users_for_display,
            staff_users=staff_users_for_display_generic,
            manager_users=manager_users_for_display,
            schedule_by_user=schedule_by_user,
            week_dates=week_dates,
            view_type=view_type,
            consolidated_label=consolidated_label,
            role_shift_definitions=ROLE_SHIFT_DEFINITIONS,
            display_role_name_for_rules=display_role_name_for_rules,
            get_shift_time_display=get_shift_time_display
        )

    # Personal view logic - MODIFIED TO CREATE SERIALIZABLE DATA FOR JS
    schedule_by_day_objects = {day: [] for day in week_dates}
    shifts = shifts_query.filter(Schedule.user_id == current_user.id).all()
    for shift in shifts:
        schedule_by_day_objects.setdefault(shift.shift_date, []).append(shift)

    user_primary_role_for_rules = 'manager'
    if current_user.has_role('bartender'): user_primary_role_for_rules = 'bartender'
    elif current_user.has_role('waiter'): user_primary_role_for_rules = 'waiter'
    elif current_user.has_role('skullers'): user_primary_role_for_rules = 'skullers'
    elif current_user.has_role('general_manager'): user_primary_role_for_rules = 'general_manager'
    elif current_user.has_role('system_admin'): user_primary_role_for_rules = 'system_admin'
    elif current_user.has_role('scheduler'): user_primary_role_for_rules = 'scheduler'


    personal_schedule_data_for_json = {}
    for date_obj, shifts_on_day in schedule_by_day_objects.items():
        date_iso = date_obj.isoformat()
        personal_schedule_data_for_json[date_iso] = []
        for shift in shifts_on_day:
            shift_entry = {
                'id': shift.id,
                'assigned_shift': shift.assigned_shift,
                'shift_date': shift.shift_date.isoformat() if shift.shift_date else None,
                'start_time_str': shift.start_time_str,
                'end_time_str': shift.end_time_str,
                'swap_requests': [
                    {
                        'id': req.id,
                        'status': req.status,
                        'coverer': {'id': req.coverer.id, 'full_name': req.coverer.full_name} if req.coverer else None
                    } for req in shift.swap_requests
                ],
                'volunteered_cycle': {
                    'status': shift.volunteered_cycle.status
                } if shift.volunteered_cycle else None
            }
            personal_schedule_data_for_json[date_iso].append(shift_entry)

    all_eligible_staff = User.query.join(User.roles).filter(
        Role.name.in_(['bartender', 'waiter', 'skullers']),
        User.is_suspended == False
    ).all()

    staff_schedules_for_week = {}
    for staff_user in all_eligible_staff:
        staff_schedules_for_week[staff_user.id] = {day.isoformat(): [] for day in week_dates}
        staff_shifts_for_user = Schedule.query.filter(
            Schedule.user_id == staff_user.id,
            Schedule.shift_date.between(week_start, week_end),
            Schedule.published == True
        ).all()
        for shift in staff_shifts_for_user:
            staff_schedules_for_week[staff_user.id][shift.shift_date.isoformat()].append(
                {'id': shift.id, 'assigned_shift': shift.assigned_shift, 'shift_date': shift.shift_date.isoformat()}
            )

    current_user_roles_list = [role.name for role in current_user.roles]

    return render_template(
        'my_schedule.html',
        schedule_by_day=schedule_by_day_objects,
        personal_schedule_data_json=json.dumps(personal_schedule_data_for_json),
        all_eligible_staff_json=json.dumps([{'id': u.id, 'full_name': u.full_name, 'roles': u.role_names} for u in all_eligible_staff]),
        staff_schedules_for_week_json=json.dumps(staff_schedules_for_week),
        current_user_roles_json=json.dumps(current_user_roles_list),
        week_dates=week_dates,
        view_type='personal',
        role_shift_definitions=ROLE_SHIFT_DEFINITIONS,
        display_role_name_for_rules=user_primary_role_for_rules,
        get_shift_time_display=get_shift_time_display
    )

@app.route('/volunteer_for_shift', methods=['POST'])
@login_required
@role_required(['bartender', 'waiter', 'skullers']) # Only staff roles can volunteer
def volunteer_for_shift():
    volunteered_shift_id = request.form.get('volunteered_shift_id', type=int)

    if not volunteered_shift_id:
        flash('No open shift selected to volunteer for.', 'danger')
        return redirect(url_for('dashboard'))

    v_shift = VolunteeredShift.query.get_or_404(volunteered_shift_id)

    # 1. Basic validation: Is the shift still open and not by current user?
    if v_shift.status != 'Open':
        flash('This shift is no longer open for volunteers.', 'danger')
        return redirect(url_for('dashboard'))

    if v_shift.requester_id == current_user.id:
        flash('You cannot volunteer for a shift you relinquished.', 'danger')
        return redirect(url_for('dashboard'))

    # 2. Check if current_user has already volunteered
    if current_user in v_shift.volunteers:
        flash('You have already volunteered for this shift.', 'info')
        return redirect(url_for('dashboard'))

    # 3. Perform eligibility checks (same as on dashboard, but server-side for safety)
    _, week_dates, _, _ = _build_week_dates()
    current_user_scheduled_shifts_raw = Schedule.query.filter(
        Schedule.user_id == current_user.id,
        Schedule.shift_date.in_(week_dates)
    ).all()
    current_user_schedule_this_week = {
        s.shift_date.isoformat(): {shift.assigned_shift for shift in current_user_scheduled_shifts_raw if shift.shift_date.isoformat() == s.shift_date.isoformat()}
        for s in current_user_scheduled_shifts_raw
    }
    current_user_roles = current_user.role_names

    requester_roles = v_shift.requester.role_names
    has_matching_role = any(role in requester_roles for role in current_user_roles)
    if not has_matching_role:
        flash('You do not have the matching role to volunteer for this shift.', 'danger')
        return redirect(url_for('dashboard'))

    shift_date_iso = v_shift.schedule.shift_date.isoformat()
    assigned_shifts_on_day = current_user_schedule_this_week.get(shift_date_iso, set())

    conflict = False
    requested_shift_type = v_shift.schedule.assigned_shift

    if requested_shift_type == 'Double':
        if assigned_shifts_on_day:
            conflict = True
    else:
        if 'Double' in assigned_shifts_on_day or requested_shift_type in assigned_shifts_on_day:
            conflict = True

    if conflict:
        flash(f"You have a conflicting shift on {v_shift.schedule.shift_date.strftime('%a, %b %d')} and cannot volunteer.", 'danger')
        return redirect(url_for('dashboard'))


    # 4. Record the volunteer
    v_shift.volunteers.append(current_user) # Add current_user to the volunteers relationship

    # Optional: Change status if first volunteer or if it should go to approval immediately
    # For now, keep it 'Open' until a manager acts. Managers will see who volunteered.
    # v_shift.status = 'PendingApproval' # Could be an option if desired

    # 5. Notify managers that a shift has a new volunteer
    announcement_title = "New Volunteer for Open Shift"
    announcement_message = (
        f"{current_user.full_name} has volunteered for the {v_shift.schedule.assigned_shift} "
        f"shift on {v_shift.schedule.shift_date.strftime('%a, %b %d')}, "
        f"originally relinquished by {v_shift.requester.full_name}. "
        f"There are now {len(v_shift.volunteers)} volunteers for this shift. "
        f"Review on the Manage Volunteered Shifts page."
    )
    urgent_announcement = Announcement(
        user_id=current_user.id, # Volunteer is the 'author' of this notification
        title=announcement_title,
        message=announcement_message,
        category='Urgent' # Important for managers
    )
    db.session.add(urgent_announcement)

    db.session.commit()
    log_activity(f"User {current_user.full_name} volunteered for shift ID {v_shift.id} ({v_shift.schedule.assigned_shift} on {v_shift.schedule.shift_date}).")
    flash('Thank you for volunteering! Managers have been notified.', 'success')
    return redirect(url_for('dashboard'))

# ==============================================================================
# Leave & Swap Request Routes
# ==============================================================================
@app.route('/leave-requests', methods=['GET', 'POST'])
@login_required
@role_required(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin'])
def leave_requests():
    if request.method == 'POST':
        start_date = datetime.strptime(request.form.get('start_date'), '%Y-%m-%d').date()
        end_date = datetime.strptime(request.form.get('end_date'), '%Y-%m-%d').date()
        reason = request.form.get('reason')
        document = request.files.get('document')

        doc_path = None
        if document and document.filename != '':
            filename = secure_filename(f"leave_request_{current_user.id}_{datetime.utcnow().timestamp()}_{document.filename}")

            file_stream = io.BytesIO(document.read())

            import mimetypes
            mimetype = mimetypes.guess_type(document.filename)[0] or 'application/octet-stream'

            # MODIFIED: Pass the specific leave documents subfolder ID
            drive_link = upload_file_to_drive( # <--- NOW CALLS THE HELPER FROM UTILS
                file_stream,
                filename,
                mimetype,
                parent_folder_id=current_app.config['GOOGLE_DRIVE_LEAVE_DOCS_FOLDER_ID'] # Use current_app.config
            )
            if drive_link:
                doc_path = drive_link
            else:
                flash('Failed to upload supporting document to Google Drive. Please try again.', 'danger')
                return redirect(url_for('leave_requests'))

        new_request = LeaveRequest(user_id=current_user.id, start_date=start_date, end_date=end_date, reason=reason, document_path=doc_path)
        db.session.add(new_request)
        db.session.commit()
        log_activity("Submitted a leave request.")
        flash('Your leave request has been submitted for review.', 'success')
        return redirect(url_for('leave_requests'))

    if current_user.has_role('manager') or current_user.has_role('general_manager') or current_user.has_role('system_admin'):
        all_requests = LeaveRequest.query.order_by(LeaveRequest.timestamp.desc()).all()
    else:
        all_requests = LeaveRequest.query.filter_by(user_id=current_user.id).order_by(LeaveRequest.timestamp.desc()).all()

    return render_template('leave_requests.html', requests=all_requests)

@app.route('/leave-requests/update/<int:req_id>/<string:status>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def update_leave_status(req_id, status):
    leave_req = LeaveRequest.query.get_or_404(req_id)

    if leave_req.user_id == current_user.id:
        flash('You cannot approve or deny your own leave request.', 'danger')
        return redirect(url_for('leave_requests'))

    if status in ['Approved', 'Denied']:
        leave_req.status = status
        db.session.commit()
        log_activity(f"{status} leave request for {leave_req.user.full_name}.")
        flash(f'Leave request has been {status.lower()}.', 'success' if status == 'Approved' else 'warning')
    return redirect(url_for('leave_requests'))

# NEW: Route for downloading/viewing the document from Google Drive
@app.route('/leave-requests/document/<int:req_id>')
@login_required
def view_leave_document(req_id):
    leave_req = LeaveRequest.query.get_or_404(req_id)

    # Only the requester, managers, general managers, and system admins can view the document
    if not (leave_req.user_id == current_user.id or
            current_user.has_role('manager') or
            current_user.has_role('general_manager') or
            current_user.has_role('system_admin')):
        flash('Access Denied: You are not authorized to view this document.', 'danger')
        return redirect(url_for('leave_requests'))

    if leave_req.document_path:
        # Redirect directly to the Google Drive link
        return redirect(leave_req.document_path)
    else:
        flash('No supporting document available for this request.', 'info')
        return redirect(url_for('leave_requests'))

@app.route('/submit-new-swap-request', methods=['POST'])
@login_required
@role_required(['bartender', 'waiter', 'skullers'])
def submit_new_swap_request():
    data = request.get_json() if request.is_json else request.form
    requester_schedule_id = data.get('requester_schedule_id', type=int)
    desired_cover_id = data.get('desired_cover_id', type=int)

    if not requester_schedule_id or not desired_cover_id:
        flash('Invalid swap request. Please select a shift and a potential cover.', 'danger')
        # For API, we'd return JSON error. For web, redirect.
        if request.is_json:
            return jsonify({"msg": "Invalid swap request. Missing shift or cover."}), 400
        return redirect(url_for('my_schedule', view='personal'))

    schedule_item = Schedule.query.get_or_404(requester_schedule_id)
    desired_cover_user = User.query.get(desired_cover_id)

    if schedule_item.user_id != current_user.id:
        flash('You can only request to swap your own shifts.', 'danger')
        return redirect(url_for('my_schedule', view='personal'))

    if not desired_cover_user:
        flash('Selected potential cover staff not found.', 'danger')
        return redirect(url_for('my_schedule', view='personal'))

    existing_request = ShiftSwapRequest.query.filter_by(schedule_id=requester_schedule_id, status='Pending').first()
    if existing_request:
        flash('A swap request for this shift is already pending.', 'info')
        return redirect(url_for('my_schedule', view='personal'))



    # Create the new swap request, including the desired coverer
    # This acts as a suggestion for the manager, not a binding assignment yet
    new_swap_request = ShiftSwapRequest(
        schedule_id=requester_schedule_id,
        requester_id=current_user.id,
        coverer_id=desired_cover_user.id # Store the suggested coverer
    )
    db.session.add(new_swap_request)

    shift_date_str = schedule_item.shift_date.strftime('%a, %b %d')
    announcement_title = "New Shift Swap Request"
    announcement_message = f"{current_user.full_name} has requested to swap their {schedule_item.assigned_shift} shift on {shift_date_str}. They suggest {desired_cover_user.full_name} as a cover."
    new_announcement = Announcement(user_id=current_user.id, title=announcement_title, message=announcement_message, category='Urgent')
    db.session.add(new_announcement)

    db.session.commit()
    log_activity(f"Requested a shift swap for {schedule_item.assigned_shift} on {shift_date_str}, suggesting {desired_cover_user.full_name}.")
    if request.is_json:
        return jsonify({"msg": "Your swap request has been submitted. A manager will be notified."}), 201
    flash('Your swap request has been submitted. A manager will be notified.', 'success')
    return redirect(url_for('my_schedule', view='personal'))

@app.route('/relinquish_shift', methods=['POST'])
@login_required
@role_required(['bartender', 'waiter', 'skullers']) # Only staff roles can relinquish their own shifts
def relinquish_shift():
    data = request.get_json() if request.is_json else request.form
    schedule_id = data.get('schedule_id', type=int)
    relinquish_reason = data.get('relinquish_reason')

    if not schedule_id:
        flash('No shift selected to relinquish.', 'danger')
        if request.is_json:
            return jsonify({"msg": "No shift selected to relinquish."}), 400
        return redirect(url_for('my_schedule', view='personal'))

    schedule_item = Schedule.query.get_or_404(schedule_id)

    # 1. Validate the shift belongs to the current user
    if schedule_item.user_id != current_user.id:
        flash('You can only relinquish your own assigned shifts.', 'danger')
        return redirect(url_for('my_schedule', view='personal'))

    # 2. Check if this shift is already pending a swap or a volunteer cycle
    # (The frontend should filter this, but backend check is crucial for safety)
    existing_swap_request = ShiftSwapRequest.query.filter_by(schedule_id=schedule_id, status='Pending').first()
    existing_volunteered_cycle = VolunteeredShift.query.filter_by(schedule_id=schedule_id).first() # Any status

    if existing_swap_request:
        flash(f'This shift is already part of a pending swap request (ID: {existing_swap_request.id}).', 'danger')
        return redirect(url_for('my_schedule', view='personal'))

    if existing_volunteered_cycle:
        flash(f'This shift is already in a volunteering cycle (Status: {existing_volunteered_cycle.status}).', 'danger')
        return redirect(url_for('my_schedule', view='personal'))


    # 3. Create a new VolunteeredShift entry
    new_volunteered_shift = VolunteeredShift(
        schedule_id=schedule_id,
        requester_id=current_user.id,
        relinquish_reason=relinquish_reason,
        status='Open' # Mark it as open for volunteering
    )
    db.session.add(new_volunteered_shift)
    db.session.flush() # Flush to get new_volunteered_shift.id for notification

    # 4. Add an announcement/notification for managers
    shift_date_str = schedule_item.shift_date.strftime('%a, %b %d')
    announcement_title = "Shift Available for Volunteering"
    announcement_message = (
        f"{current_user.full_name} has relinquished their {schedule_item.assigned_shift} "
        f"shift on {shift_date_str}. It is now open for volunteers. "
        f"Reason: {relinquish_reason if relinquish_reason else 'None provided'}."
    )
    urgent_announcement = Announcement(
        user_id=current_user.id, # Requester is the 'author' of this notification
        title=announcement_title,
        message=announcement_message,
        category='Urgent' # Important for managers and potential volunteers
    )
    db.session.add(urgent_announcement)

    db.session.commit()
    log_activity(f"User {current_user.full_name} relinquished {schedule_item.assigned_shift} on {shift_date_str} for volunteering.")
    if request.is_json:
        return jsonify({"msg": "Your shift relinquishment request has been submitted. It is now open for volunteers."}), 201
    flash('Your shift relinquishment request has been submitted. It is now open for volunteers.', 'success')
    return redirect(url_for('my_schedule', view='personal'))

@app.route('/manage-swaps')
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def manage_swaps():
    # Define week_dates, week_start, week_end for schedule lookups
    week_dates = get_week_dates()
    week_start = week_dates[0]
    week_end = week_dates[-1]

    # Fetch all pending swaps
    # MODIFIED: Filter out swaps with missing schedules early
    pending_swaps_raw = [
        s for s in ShiftSwapRequest.query.filter_by(status='Pending').order_by(ShiftSwapRequest.timestamp.desc()).all()
        if s.schedule is not None
    ]

    # Fetch all potential cover staff once
    all_potential_cover_staff = User.query.join(User.roles).filter(
        Role.name.in_(['bartender', 'waiter', 'skullers']),
        User.is_suspended == False
    ).order_by(User.full_name).all()

    # Pre-fetch all shifts for all potential cover staff for the current week
    all_staff_shifts_this_week = Schedule.query.filter(
        Schedule.user_id.in_([u.id for u in all_potential_cover_staff]),
        Schedule.shift_date.between(week_start, week_end)
    ).all()

    # Organize staff schedules by user_id and then date for quick lookup
    staff_schedules_lookup = {u.id: {day.isoformat(): [] for day in week_dates} for u in all_potential_cover_staff}
    for shift in all_staff_shifts_this_week:
        if shift.user_id in staff_schedules_lookup and shift.shift_date.isoformat() in staff_schedules_lookup[shift.user_id]:
            staff_schedules_lookup[shift.user_id][shift.shift_date.isoformat()].append(
                {'id': shift.id, 'assigned_shift': shift.assigned_shift, 'shift_date': shift.shift_date.isoformat()}
            )


    # Now, process each pending swap to attach its filtered staff options
    processed_pending_swaps = []
    for swap in pending_swaps_raw: # pending_swaps_raw is already filtered for None.
        requester_roles = swap.requester.role_names
        requested_shift_date_iso = swap.schedule.shift_date.isoformat()
        requested_shift_type = swap.schedule.assigned_shift

        filtered_staff_for_this_swap = []
        for potential_cover in all_potential_cover_staff:
            # 1. Exclude the requester themselves
            if potential_cover.id == swap.requester_id:
                continue

            # 2. Check if staff has at least one matching role with the requester
            potential_cover_roles = potential_cover.role_names
            has_matching_role = any(role in requester_roles for role in potential_cover_roles)
            if not has_matching_role:
                continue

            # 3. Check for shift conflicts for the requested shift date and type
            coverer_schedule_for_requested_day = staff_schedules_lookup.get(potential_cover.id, {}).get(requested_shift_date_iso, [])
            conflict = False

            if requested_shift_type == 'Double':
                # If requested shift is 'Double', coverer must be OFF for the entire day
                if coverer_schedule_for_requested_day and len(coverer_schedule_for_requested_day) > 0:
                    conflict = True
            else:
                # For 'Day' or 'Night' shifts, check if coverer has any conflicting shift
                conflict = any(
                    s['assigned_shift'] == 'Double' or s['assigned_shift'] == requested_shift_type
                    for s in coverer_schedule_for_requested_day
                )

            if not conflict:
                filtered_staff_for_this_swap.append(potential_cover)

        # Attach the filtered staff list to the swap object
        processed_pending_swaps.append({'swap': swap, 'filtered_staff': filtered_staff_for_this_swap})

    # Fetch all swaps (including approved/denied) for history display
    # MODIFIED: Filter out swaps with missing schedules for all_swaps too
    all_swaps_raw = ShiftSwapRequest.query.order_by(ShiftSwapRequest.timestamp.desc()).all()
    all_swaps = [s for s in all_swaps_raw if s.schedule is not None]


    return render_template(
        'manage_swaps.html',
        pending_swaps_data=processed_pending_swaps,
        all_swaps=all_swaps,
    )

@app.route('/update-swap/<int:swap_id>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def update_swap(swap_id):
    swap_request = ShiftSwapRequest.query.get_or_404(swap_id)
    action = request.form.get('action')

    schedule_item = swap_request.schedule
    requester = swap_request.requester

    notification_title = ""
    notification_message = ""

    if action == 'Deny':
        swap_request.status = 'Denied'
        notification_title = "Shift Swap Request Denied"
        notification_message = f"Your request to swap the {schedule_item.assigned_shift} shift on {schedule_item.shift_date.strftime('%a, %b %d')} has been denied."
        # No general announcement for deny, only individual notification (handled by flash to requester)

        flash('Shift swap request has been denied.', 'warning')
        log_activity(f"Denied shift swap request #{swap_request.id} for {requester.full_name}'s shift on {schedule_item.shift_date}.")

    elif action == 'Approve':
        coverer_id = request.form.get('coverer_id')
        if not coverer_id:
            flash('You must select a staff member to cover the shift to approve.', 'danger')
            return redirect(url_for('manage_swaps'))

        coverer = User.query.get(int(coverer_id))
        if not coverer:
            flash('Selected cover staff not found.', 'danger')
            return redirect(url_for('manage_swaps'))

        swap_request.status = 'Approved'
        swap_request.coverer_id = coverer.id

        schedule_item.user_id = coverer.id

        notification_title = "Shift Swap Request Approved"
        notification_message = f"The {schedule_item.assigned_shift} shift on {schedule_item.shift_date.strftime('%a, %b %d')} is now covered by {coverer.full_name}. Original assignee: {requester.full_name}."

        # Create an urgent announcement for all relevant roles for approval
        general_announcement = Announcement(
            user_id=current_user.id, # Manager who made the decision
            title=notification_title,
            message=notification_message,
            category='Urgent' # Important notification for all affected
        )
        db.session.add(general_announcement) # Add to session

        flash('Shift swap approved and schedule has been updated.', 'success')
        log_activity(f"Approved shift swap request #{swap_request.id}: {coverer.full_name} now covers {requester.full_name}'s shift on {schedule_item.shift_date}.")

    db.session.commit() # Commit all changes (swap status, schedule update, and announcements)

    # For Deny, explicitly flash to requester. For Approve, the general announcement covers it.
    if action == 'Deny':
        # If a manager denies, the flash message handled above is usually sufficient
        # but if we wanted a truly "private" notification for the requester, we would need
        # a dedicated UserNotification table or similar. For now, the "flash" mechanism
        # is the most direct way to get a message to the user on their next page load.
        pass # Flash already handled, no new Announcement for Deny to broad audience

    return redirect(url_for('manage_swaps'))

@app.route('/api/staff-for-swaps')
@login_required
def api_staff_for_swaps():
    # Only return non-managerial staff for swap requests
    staff = User.query.join(User.roles).filter(
        Role.name.in_(['bartender', 'waiter', 'skullers']),
        User.is_suspended == False # Exclude suspended users
    ).order_by(User.full_name).all()

    # You might want to filter out users on approved leave for the specific week
    # This would require passing the week's dates to this API or filtering client-side.
    # For simplicity, we'll just exclude suspended for now.

    return jsonify([{'id': u.id, 'full_name': u.full_name} for u in staff])

@app.route('/api/dashboard/open-shifts')
@login_required
@role_required(['bartender', 'waiter', 'skullers'])
def api_dashboard_open_shifts():
    if current_user.is_suspended:
        return jsonify([]) # No open shifts if suspended

    open_shifts_for_volunteering = []
    # 1. Get all shifts currently open for volunteering
    all_open_volunteered_shifts = VolunteeredShift.query.filter_by(status='Open').all()

    # 2. Get current_user's schedule for the week to check for conflicts
    _, week_dates, _, _ = _build_week_dates()
    current_user_scheduled_shifts_raw = Schedule.query.filter(
        Schedule.user_id == current_user.id,
        Schedule.shift_date.in_(week_dates)
    ).all()
    current_user_schedule_this_week = {
        s.shift_date.isoformat(): {shift.assigned_shift for shift in current_user_scheduled_shifts_raw if shift.shift_date.isoformat() == s.shift_date.isoformat()}
        for s in current_user_scheduled_shifts_raw
    }

    current_user_roles = current_user.role_names

    for v_shift in all_open_volunteered_shifts:
        if v_shift.requester_id == current_user.id:
            continue

        requester_roles = v_shift.requester.role_names
        has_matching_role = any(role in requester_roles for role in current_user_roles)
        if not has_matching_role:
            continue

        shift_date_iso = v_shift.schedule.shift_date.isoformat()
        assigned_shifts_on_day = current_user_schedule_this_week.get(shift_date_iso, set())

        conflict = False
        requested_shift_type = v_shift.schedule.assigned_shift

        if requested_shift_type == 'Double':
            if assigned_shifts_on_day:
                conflict = True
        else:
            if 'Double' in assigned_shifts_on_day or requested_shift_type in assigned_shifts_on_day:
                conflict = True

        already_volunteered = any(v.id == current_user.id for v in v_shift.volunteers)

        if not conflict and not already_volunteered:
            open_shifts_for_volunteering.append({
                'id': v_shift.id,
                'assigned_shift': v_shift.schedule.assigned_shift,
                'shift_date': v_shift.schedule.shift_date.strftime('%a, %b %d'),
                'requester_full_name': v_shift.requester.full_name,
                'relinquish_reason': v_shift.relinquish_reason
            })
    return jsonify(open_shifts_for_volunteering)


@app.route('/api/dashboard/admin-alerts')
@login_required
@role_required(['system_admin'])
def api_dashboard_admin_alerts():
    password_reset_requests = User.query.filter_by(password_reset_requested=True).all()
    reset_requests_data = [{
        'id': user.id,
        'full_name': user.full_name,
        'username': user.username
    } for user in password_reset_requests]
    return jsonify(reset_requests_data)


@app.route('/api/dashboard/activity-logs')
@login_required
@role_required(['system_admin'])
def api_dashboard_activity_logs():
    activity_logs = ActivityLog.query.order_by(ActivityLog.timestamp.desc()).limit(20).all()
    logs_data = [{
        'user_full_name': log.user.full_name,
        'user_username': log.user.username,
        'action': log.action,
        'timestamp': log.timestamp.isoformat() # Use ISO format for easy JS parsing
    } for log in activity_logs]
    return jsonify(logs_data)


@app.route('/api/dashboard/latest-announcement')
@login_required
def api_dashboard_latest_announcement():
    user_roles_ids = [role.id for role in current_user.roles]
    # Replicate the announcement filtering logic from inject_global_data
    filtered_announcements_query = Announcement.query.outerjoin(Announcement.target_roles) \
                                                  .filter(or_(
                                                      db.not_(Announcement.target_roles.any()),
                                                      Role.id.in_(user_roles_ids)
                                                  )) \
                                                  .distinct()

    latest_announcement = filtered_announcements_query.order_by(Announcement.id.desc()).first()

    if latest_announcement:
        return jsonify({
            'title': latest_announcement.title,
            'message': latest_announcement.message,
            'action_link': latest_announcement.action_link,
            'id': latest_announcement.id # Needed for dismiss button if implemented
        })
    return jsonify(None)


@app.route('/api/dashboard/variance-alerts')
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'owners'])
def api_dashboard_variance_alerts():
    today_date = datetime.utcnow().date()
    yesterday = today_date - timedelta(days=1)

    bod_submitted = BeginningOfDay.query.filter_by(date=today_date).first() is not None

    if not bod_submitted:
        return jsonify({'bod_submitted': False, 'alerts': []})

    bod_counts = {b.product_id: b.amount for b in BeginningOfDay.query.filter_by(date=today_date).all()}
    sales_counts = {s.product_id: s.quantity_sold for s in Sale.query.filter_by(date=yesterday).all()}
    # Fetch today's deliveries for accurate expected EOD
    todays_deliveries = {
        d.product_id: d.quantity
        for d in Delivery.query.filter_by(delivery_date=today_date).all()
    }
    # Fetch today's cocktail usage for accurate expected EOD
    cocktail_usage_today = _calculate_ingredient_usage_from_cocktails_sold(today_date)

    products = Product.query.all()
    # Get latest actual counts for today
    eod_latest_count_objects = {}
    all_counts_on_today = Count.query.filter(func.date(Count.timestamp) == today_date).all()
    for count in all_counts_on_today:
        product_id = count.product_id
        if product_id not in eod_latest_count_objects or count.timestamp > eod_latest_count_objects[product_id].timestamp:
            eod_latest_count_objects[product_id] = count

    alerts = []
    for product in products:
        bod = bod_counts.get(product.id, 0.0)
        deliveries = todays_deliveries.get(product.id, 0.0)
        manual_sales = sales_counts.get(product.id, 0.0)
        cocktail_usage = cocktail_usage_today.get(product.id, 0.0)

        expected_eod = bod + deliveries - manual_sales - cocktail_usage
        expected_eod = max(0.0, expected_eod) # Ensure non-negative

        latest_count_obj = eod_latest_count_objects.get(product.id)

        variance_val = None
        if latest_count_obj and latest_count_obj.variance_amount is not None:
            variance_val = latest_count_obj.variance_amount
        elif latest_count_obj: # If actual count exists but variance wasn't saved, calculate
             variance_val = latest_count_obj.amount - expected_eod

        if variance_val is not None and variance_val != 0:
            alerts.append({'name': product.name, 'variance': round(variance_val, 2)}) # Round for display

    return jsonify({'bod_submitted': bod_submitted, 'alerts': alerts})


@app.route('/api/dashboard/location-statuses')
@login_required
# This should be accessible to all roles that perform counts
@role_required(['manager', 'general_manager', 'system_admin', 'bartender', 'waiter', 'skullers'])
def api_dashboard_location_statuses():
    today_date = datetime.utcnow().date()
    bod_submitted = BeginningOfDay.query.filter_by(date=today_date).first() is not None

    locations = Location.query.order_by(Location.name).all()
    location_statuses_data = []

    for loc in locations:
        latest_count = Count.query.filter(Count.location == loc.name, func.date(Count.timestamp) == today_date).order_by(Count.timestamp.desc()).first()
        status = 'not_started'
        if latest_count:
            status = 'corrected' if latest_count.count_type == 'Corrections Count' else 'counted'

        location_statuses_data.append({
            'name': loc.name,
            'slug': loc.name.replace(' ', '_').lower(),
            'status': status
        })
    return jsonify({'bod_submitted': bod_submitted, 'location_statuses': location_statuses_data})

# ==============================================================================
# Export Routes
# ==============================================================================
@app.route('/export/daily-summary')
@login_required
@role_required(['manager', 'system_admin'])
def export_daily_summary():
    today = datetime.utcnow().date()
    yesterday = today - timedelta(days=1)
    products = Product.query.order_by(Product.type, Product.name).all()
    bod_counts = {b.product_id: b.amount for b in BeginningOfDay.query.filter_by(date=today).all()}
    sales_counts = {s.product_id: s.quantity_sold for s in Sale.query.filter_by(date=yesterday).all()}
    eod_counts = {}
    locations = Location.query.all()
    for product in products:
        total_on_hand = sum(c.amount for c in Count.query.filter(Count.product_id == product.id, func.date(Count.timestamp) == today).all())
        eod_counts[product.id] = total_on_hand

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Product', 'Unit', 'Beginning of Day', 'Sales', 'Expected On-Hand', 'Actual On-Hand', 'Variance'])

    for product in products:
        bod = bod_counts.get(product.id, 0)
        sold = sales_counts.get(product.id, 0)
        eod_total = eod_counts.get(product.id, 0)
        expected = bod - sold
        variance = eod_total - expected
        writer.writerow([product.name, product.unit_of_measure, bod, sold, expected, eod_total, variance])

    output.seek(0)
    return Response(output, mimetype="text/csv", headers={"Content-Disposition": f"attachment;filename=daily_summary_{today.strftime('%Y-%m-%d')}.csv"})

@app.route('/export/variance')
@login_required
@role_required(['manager', 'system_admin'])
def export_variance():
    today = datetime.utcnow().date()
    counts_today = Count.query.filter(func.date(Count.timestamp) == today).order_by(Count.location, Count.product_id, Count.timestamp).all()
    variance_data = {}
    for count in counts_today:
        key = (count.location, count.product_id)
        if key not in variance_data:
            variance_data[key] = {'location': count.location, 'product_name': count.product.name, 'first_count_amount': None, 'first_count_by': None, 'correction_amount': None, 'correction_by': None}
        if count.count_type == 'First Count':
            variance_data[key]['first_count_amount'] = count.amount
            variance_data[key]['first_count_by'] = count.user.full_name
        elif count.count_type == 'Corrections Count':
            variance_data[key]['correction_amount'] = count.amount
            variance_data[key]['correction_by'] = count.user.full_name
    variance_list = [v for v in variance_data.values() if v.get('correction_amount') is not None and v.get('first_count_amount') != v.get('correction_amount')]

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Location', 'Product', 'First Count', 'Submitted By', 'Correction', 'Corrected By', 'Difference'])

    for item in sorted(variance_list, key=lambda x: (x['location'], x['product_name'])):
        first = item.get('first_count_amount', 0)
        corr = item.get('correction_amount', 0)
        diff = corr - first
        writer.writerow([item['location'], item['product_name'], first, item.get('first_count_by', ''), corr, item.get('correction_by', ''), diff])

    output.seek(0)
    return Response(output, mimetype="text/csv", headers={"Content-Disposition": f"attachment;filename=variance_report_{today.strftime('%Y-%m-%d')}.csv"})

@app.route('/export/product-breakdown')
@login_required
@role_required(['manager', 'system_admin'])
def export_product_breakdown():
    start_date_str = request.args.get('start_date', '')
    end_date_str = request.args.get('end_date', '')

    query = Count.query.join(Product)
    if start_date_str and end_date_str:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
        query = query.filter(func.date(Count.timestamp).between(start_date, end_date))
        bod_query = db.session.query(BeginningOfDay.product_id, func.sum(BeginningOfDay.amount)).filter(BeginningOfDay.date.between(start_date, end_date)).group_by(BeginningOfDay.product_id).all()
        sales_query = db.session.query(Sale.product_id, func.sum(Sale.quantity_sold)).filter(Sale.date.between(start_date, end_date)).group_by(Sale.product_id).all()
        bod_totals, sales_totals = dict(bod_query), dict(sales_query)

    all_counts = query.all()
    data = {}
    for count in all_counts:
        p_name = count.product.name
        if p_name not in data:
            data[p_name] = {'id': count.product.id, 'total': 0, 'locations': {}}
        data[p_name]['locations'].setdefault(count.location, {'first': None, 'corr': None})
        if count.count_type == 'First Count': data[p_name]['locations'][count.location]['first'] = count.amount
        else: data[p_name]['locations'][count.location]['corr'] = count.amount

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Product', 'Total On-Hand', 'Expected On-Hand', 'Location', 'Final Count in Location'])

    for p_name, p_data in sorted(data.items()):
        total = sum(loc.get('corr', loc.get('first', 0)) for loc in p_data['locations'].values())
        expected = 0
        if start_date_str:
            expected = bod_totals.get(p_data['id'], 0) - sales_totals.get(p_data['id'], 0)

        for loc, loc_data in p_data['locations'].items():
            final = loc_data.get('corr') if loc_data.get('corr') is not None else loc_data.get('first', 0)
            writer.writerow([p_name, total, expected, loc, final])

    output.seek(0)
    return Response(output, mimetype="text/csv", headers={"Content-Disposition": f"attachment;filename=product_breakdown_{start_date_str}_to_{end_date_str}.csv"})

@app.route('/export/schedule/<string:role_name><optional_int:week_offset>')
@login_required
@role_required(['scheduler', 'manager', 'general_manager', 'system_admin'])
def export_schedule_for_role(role_name, week_offset):
    _, week_dates, _, _ = _build_week_dates(week_offset=week_offset)
    start_of_week = week_dates[0]
    end_of_week = week_dates[-1]

    # Get users for the specific role
    users_in_role = User.query.join(User.roles).filter(Role.name == role_name).order_by(User.full_name).all()
    user_ids_in_role = [u.id for u in users_in_role]

    if not user_ids_in_role:
        flash(f"No users found for role '{role_name}' to export.", 'info')
        return redirect(url_for(f'scheduler_{role_name}s', week_offset=week_offset))

    # Fetch published shifts for these users within the week
    current_schedule = Schedule.query.filter(
        Schedule.shift_date >= start_of_week,
        Schedule.shift_date <= end_of_week,
        Schedule.user_id.in_(user_ids_in_role),
        Schedule.published == True
    ).order_by(Schedule.shift_date, Schedule.assigned_shift).all()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Date', 'Day', 'Staff Member', 'Role', 'Assigned Shift'])

    for item in current_schedule:
        staff_roles = ', '.join([role.name.replace('_', ' ').title() for role in item.user.roles])
        writer.writerow([
            item.shift_date.strftime('%Y-%m-%d'),
            item.shift_date.strftime('%A'),
            item.user.full_name,
            staff_roles,
            item.assigned_shift
        ])

    output.seek(0)
    filename = f"{role_name}_schedule_{start_of_week.strftime('%Y-%m-%d')}_to_{end_of_week.strftime('%Y-%m-%d')}.csv"
    return Response(output, mimetype="text/csv", headers={"Content-Disposition": f"attachment;filename={filename}"})

# ==============================================================================
# Admin & User Management Routes
# ==============================================================================

@app.route('/suspend_user_modal_content/<int:user_id>', methods=['GET'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def suspend_user_modal_content(user_id):
    user_to_suspend = User.query.get_or_404(user_id)

    # Basic safety check (cannot suspend root admin or self)
    if user_id == 1 or user_id == current_user.id:
        # Returning a custom response for AJAX calls
        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return jsonify({'error': "Cannot suspend this user."}), 403
        flash('Cannot suspend this user.', 'danger')
        return redirect(url_for('manage_users')) # Fallback for non-AJAX

    return render_template(
        'suspend_user_modal_content.html',
        user=user_to_suspend,
        today_date=datetime.utcnow().date()
    )

@app.route('/users/reinstate/<int:user_id>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def reinstate_user(user_id):
    user_to_reinstate = User.query.get_or_404(user_id)

    # Safety checks
    if user_id == current_user.id:
        return jsonify({'status': 'danger', 'message': "You cannot reinstate your own account."}), 403
    if user_id == 1:
        return jsonify({'status': 'danger', 'message': "The root administrator account cannot be reinstated via this method."}), 403

    if not user_to_reinstate.is_suspended:
        return jsonify({'status': 'info', 'message': "User is not currently suspended."}), 200

    user_to_reinstate.is_suspended = False
    user_to_reinstate.suspension_end_date = None

    # --- Clear suspension document path on reinstate ---
    # MODIFIED: No longer deleting local file, just clearing the path/link
    user_to_reinstate.suspension_document_path = None
    # --- END CLEAR DOCUMENT ---

    db.session.commit()
    log_activity(f"Reinstated user: '{user_to_reinstate.full_name}' ({user_to_reinstate.username}).")
    return jsonify({'status': 'success', 'message': f"User '{user_to_reinstate.full_name}' has been reinstated."})

@app.route('/active-users')
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'owners'])
def active_users():
    five_minutes_ago = datetime.utcnow() - timedelta(minutes=5)
    users = User.query.filter(User.last_seen > five_minutes_ago).order_by(User.last_seen.desc()).all()
    return render_template('active_users.html', users=users)

@app.route('/users/force-logout/<int:user_id>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def force_logout(user_id):
    if user_id == current_user.id:
        flash("You cannot force your own account to log out.", "danger")
        return redirect(url_for('active_users'))

    user_to_logout = User.query.get_or_404(user_id)

    is_manager_only = current_user.has_role('manager') and not (current_user.has_role('system_admin') or current_user.has_role('general_manager'))
    if is_manager_only:
        target_is_staff = user_to_logout.has_role('bartender') or user_to_logout.has_role('waiter')
        if not target_is_staff:
            flash('Managers can only force logout Bartenders and Waiters.', 'danger')
            return redirect(url_for('active_users'))

    user_to_logout.force_logout_requested = True
    db.session.commit()
    log_activity(f"Requested force logout for user: '{user_to_logout.username}'.")
    flash(f"User '{user_to_logout.full_name}' will be logged out on their next action.", "success")
    return redirect(url_for('active_users'))

@app.route('/users')
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def manage_users():
    users = User.query.all()
    all_roles = Role.query.order_by(Role.name).all() # Fetch all roles for the filter dropdown
    # Pass today's date for modal's default suspension end date
    today_date = datetime.utcnow().date()
    return render_template('manage_users.html', users=users, today_date=today_date, all_roles=all_roles)

@app.route('/users/add', methods=['GET', 'POST'])
@login_required
@role_required(['system_admin', 'manager'])
def add_user():
    if request.method == 'POST':
        username, full_name, password = (request.form.get(k) for k in ['username', 'full_name', 'password'])
        role_names = request.form.getlist('roles')

        if current_user.has_role('manager') and not (current_user.has_role('system_admin') or current_user.has_role('general_manager')):
            # Check if the manager is trying to assign a role other than waiter, bartender, or skullers
            allowed_roles = {'bartender', 'waiter', 'skullers'} # ADDED 'skullers'
            if not set(role_names).issubset(allowed_roles):
                flash('Managers can only create Bartender, Waiter, and Skullers accounts.', 'danger')
                return redirect(url_for('add_user'))

        new_user = User(username=username, full_name=full_name, password=bcrypt.generate_password_hash(password).decode('utf-8'))

        roles = Role.query.filter(Role.name.in_(role_names)).all()
        new_user.roles = roles

        log_activity(f"Created new user: '{full_name}' ({username}, {', '.join(role_names)}).")
        db.session.add(new_user)
        db.session.commit()
        flash(f'User "{full_name}" created successfully!', 'success')
        return redirect(url_for('manage_users'))

    all_roles = Role.query.all()
    return render_template('add_user.html', all_roles=all_roles)

@app.route('/users/edit/<int:user_id>', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def edit_user(user_id):
    if user_id == 1:
        # Forbid editing root admin, especially suspension
        if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return jsonify({'status': 'danger', 'message': 'The root administrator account cannot be edited or suspended.'}), 403
        flash('The root administrator account cannot be edited or suspended.', 'danger')
        return redirect(url_for('manage_users'))
    if user_id == current_user.id:
        # Forbid self-suspension
        if request.form.get('action') in ['suspend_user', 'reinstate_user'] and request.headers.get('X-Requested-With') == 'XMLHttpRequest':
            return jsonify({'status': 'danger', 'message': 'You cannot suspend or reinstate your own account.'}), 403
        elif request.form.get('action') == 'suspend_user':
             flash('You cannot suspend your own account.', 'danger')
             return redirect(url_for('manage_users'))

    user_to_edit = User.query.get_or_404(user_id)

    # --- Handle POST Request (from either main form or suspend modal) ---
    if request.method == 'POST':
        action = request.form.get('action') # Check for specific action from modals/buttons

        # =============================================================
        # Action: Suspend User / Update Suspension Details
        # This comes from the suspendUserModal's form submission
        # =============================================================
        if action in ['suspend_user', 'update_suspension_details']:
            if not (current_user.has_role('system_admin') or current_user.has_role('general_manager') or current_user.has_role('manager')):
                # Even if they got here, ensure permissions
                return jsonify({'status': 'danger', 'message': 'Access Denied: Not authorized to manage suspensions.'}), 403

            # Ensure suspended status is toggled ON if it's 'suspend_user' action
            if action == 'suspend_user':
                user_to_edit.is_suspended = True

            # Update suspension end date
            suspension_end_date_str = request.form.get('suspension_end_date')
            if suspension_end_date_str:
                try:
                    user_to_edit.suspension_end_date = datetime.strptime(suspension_end_date_str, '%Y-%m-%d').date()
                except ValueError:
                    flash('Invalid date format for suspension end date.', 'danger')
                    return jsonify({'status': 'danger', 'message': 'Invalid date format.'}), 400
            else:
                user_to_edit.suspension_end_date = None # Indefinite suspension

            # Handle suspension document upload
            suspension_document_file = request.files.get('suspension_document')
            if suspension_document_file and suspension_document_file.filename != '':
                # NEW: Upload suspension document to Google Drive
                filename = secure_filename(f"susdoc_{user_id}_{datetime.utcnow().timestamp()}_{suspension_document_file.filename}")
                file_stream = io.BytesIO(suspension_document_file.read())
                import mimetypes
                mimetype = mimetypes.guess_type(suspension_document_file.filename)[0] or 'application/octet-stream'

                drive_link = upload_file_to_drive( # <--- NOW CALLS THE HELPER FROM UTILS
                    file_stream,
                    filename,
                    mimetype,
                    parent_folder_id=current_app.config['GOOGLE_DRIVE_SUSPESION_DOCS_FOLDER_ID'] # Use current_app.config
                )
                if drive_link:
                    user_to_edit.suspension_document_path = drive_link
                    # No need to delete old file if overwriting with a new Drive link
                else:
                    flash('Failed to upload suspension document to Google Drive.', 'danger')
                    return jsonify({'status': 'danger', 'message': 'Failed to upload document.'}), 500
                # END NEW

            # Handle suspension document deletion checkbox
            delete_doc_requested = request.form.get('delete_suspension_document') == '1'
            if delete_doc_requested and user_to_edit.suspension_document_path:
                # MODIFIED: Just clear the link, no local file to delete
                user_to_edit.suspension_document_path = None
                app.logger.info(f"Cleared suspension document link for user {user_id}.")

            db.session.commit()
            log_activity(f"User '{user_to_edit.full_name}' suspension details updated or user suspended.")

            # Flash message and return JSON for AJAX modal submission
            flash(f"User '{user_to_edit.full_name}' suspension status and details updated.", 'success')
            return jsonify({'status': 'success', 'message': get_flashed_messages(category_filter=['success'])[0]})

        # =============================================================
        # Action: Update User Details (from main edit form)
        # This is for the regular user profile update, not suspension
        # =============================================================
        else: # No specific action, assume it's the main form submission
            # Check permissions for regular edit
            if current_user.has_role('owners') and not (current_user.has_role('system_admin') or current_user.has_role('general_manager')):
                flash('This role has view-only access to user details.', 'danger')
                return redirect(url_for('manage_users'))

            user_to_edit.full_name = request.form.get('full_name')
            user_to_edit.username = request.form.get('username')

            role_names = request.form.getlist('roles')
            # Business owner cannot assign roles if limited view
            if not current_user.has_role('owners') or (current_user.has_role('system_admin') or current_user.has_role('general_manager')):
                user_to_edit.roles = Role.query.filter(Role.name.in_(role_names)).all()
            else:
                # If business owner and limited, ensure roles are not accidentally changed
                pass # Roles cannot be changed by limited business owner

            new_password = request.form.get('password')
            if new_password:
                user_to_edit.password = bcrypt.generate_password_hash(new_password).decode('utf-8')
                user_to_edit.password_reset_requested = False

            db.session.commit()
            log_activity(f"Edited user details for '{user_to_edit.full_name}'.")
            flash('User details updated successfully!', 'success')
            return redirect(url_for('manage_users')) # Redirect for regular form submission

    # --- Handle GET Request ---
    # This renders the main edit_user page
    all_roles = Role.query.all()
    user_role_names = [role.name for role in user_to_edit.roles]
    is_limited_view = current_user.has_role('owners') and not (current_user.has_role('system_admin') or current_user.has_role('general_manager'))

    return render_template('edit_user.html',
                           user=user_to_edit,
                           all_roles=all_roles,
                           user_role_names=user_role_names,
                           is_limited_view=is_limited_view)

@app.route('/users/delete/<int:user_id>', methods=['POST'])
@login_required
@role_required(['system_admin'])
def delete_user(user_id):
    # ... (rest of the function is unchanged) ...
    if user_id == current_user.id:
        flash('You cannot delete your own account.', 'danger')
        return redirect(url_for('manage_users'))
    if user_id == 1:
        flash('The root administrator account cannot be deleted.', 'danger')
        return redirect(url_for('manage_users'))
    user_to_delete = User.query.get_or_404(user_id)
    log_activity(f"Deleted user: '{user_to_delete.full_name}'.")
    db.session.delete(user_to_delete)
    db.session.commit()
    flash(f'User "{user_to_delete.full_name}" has been deleted.', 'success')
    return redirect(url_for('manage_users'))

# ==============================================================================
# Product & Location Management Routes
# ==============================================================================

@app.route('/products', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def products():
    # Get current sort/group preferences from URL parameters or session
    group_by = request.args.get('group_by', session.get('products_group_by', 'none'))
    sort_by = request.args.get('sort_by', session.get('products_sort_by', 'product_number'))
    sort_order = request.args.get('sort_order', session.get('products_sort_order', 'asc'))
    type_filter = request.args.get('type_filter', session.get('products_type_filter', 'all'))
    search_query = request.args.get('search_query', session.get('products_search_query', ''))

    # Store preferences in session for persistence
    session['products_group_by'] = group_by
    session['products_sort_by'] = sort_by
    session['products_sort_order'] = sort_order
    session['products_type_filter'] = type_filter
    session['products_search_query'] = search_query

    if request.method == 'POST':
        # This handles adding a new product
        name, p_type, unit = (request.form.get(k) for k in ['name', 'type', 'unit_of_measure'])
        unit_price = request.form.get('unit_price')
        product_number = request.form.get('product_number')

        new_product = Product(name=name, type=p_type, unit_of_measure=unit,
                              unit_price=float(unit_price) if unit_price else None,
                              product_number=product_number if product_number else None)
        db.session.add(new_product)
        db.session.commit()
        flash('Product added successfully!', 'success')

        # Redirect with parameters to retain the sorting and filters after adding a product
        return redirect(url_for('products',
                                group_by=group_by,
                                sort_by=sort_by,
                                sort_order=sort_order,
                                type_filter=type_filter,
                                search_query=search_query))

    # Handle GET request for viewing products with grouping/sorting/filtering
    grouped_products = get_products_data(group_by, sort_by, sort_order, type_filter, search_query)

    all_product_types = db.session.query(distinct(Product.type)).order_by(Product.type).all()
    all_product_types = [t[0] for t in all_product_types]

    return render_template('products.html',
                           grouped_products=grouped_products,
                           current_group_by=group_by,
                           current_sort_by=sort_by,
                           current_sort_order=sort_order,
                           current_type_filter=type_filter,
                           current_search_query=search_query,
                           all_product_types=all_product_types)

# NEW ROUTE: set_all_stock page
@app.route('/set_all_stock', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def set_all_stock():
    today_date = datetime.utcnow().date()
    products_query = Product.query.order_by(Product.name) # Start query for products

    # Add search filter if present (e.g., from clicking individual "Set Stock" button)
    search_query = request.args.get('search_query')
    if search_query:
        products_query = products_query.filter(Product.name.ilike(f'%{search_query}%'))

    products = products_query.all()

    # Pre-populate current BOD values
    existing_bod_map = {
        bod.product_id: bod
        for bod in BeginningOfDay.query.filter_by(date=today_date).all()
    }

    if request.method == 'POST':
        success_messages = []
        error_messages = []

        for product in products:
            stock_value_str = request.form.get(f'stock_value_{product.id}')

            # If the field is empty, it means no change was intended or it was skipped.
            # Only process if a value was actually entered.
            if stock_value_str:
                try:
                    stock_value = float(stock_value_str)
                    if stock_value < 0:
                        error_messages.append(f"Stock for '{product.name}' must be non-negative. Entered: {stock_value_str}.")
                        continue # Skip to next product

                    existing_bod = existing_bod_map.get(product.id)
                    if existing_bod:
                        if existing_bod.amount != stock_value: # Only update if value changed
                            existing_bod.amount = stock_value
                            success_messages.append(f"Updated '{product.name}' to {stock_value} {product.unit_of_measure}.")
                            log_activity(f"Updated initial stock for product '{product.name}' to {stock_value}.")
                    else:
                        new_bod = BeginningOfDay(
                            product_id=product.id,
                            amount=stock_value,
                            date=today_date
                        )
                        db.session.add(new_bod)
                        success_messages.append(f"Set '{product.name}' to {stock_value} {product.unit_of_measure}.")
                        log_activity(f"Set initial stock for product '{product.name}' to {stock_value}.")

                except ValueError:
                    error_messages.append(f"Invalid stock value for '{product.name}': '{stock_value_str}'. Must be a number.")
                except Exception as e:
                    error_messages.append(f"An error occurred updating '{product.name}': {e}")
                    app.logger.exception(f"Error updating stock for product {product.id} - {product.name}")

        if error_messages:
            for msg in error_messages:
                flash(msg, 'danger')
            db.session.rollback() # Rollback all changes if any error occurred
        else:
            db.session.commit()
            if success_messages:
                flash("Stock updates saved successfully!", 'success')
            else:
                flash("No stock values were changed.", 'info')

        return redirect(url_for('set_all_stock', search_query=search_query)) # Redirect back with search query

    return render_template('set_all_stock.html',
                           products=products,
                           existing_bod_map=existing_bod_map,
                           today_date=today_date,
                           current_search_query=search_query) # Pass search query to template
# END NEW ROUTE


# --- NEW ROUTE: set_all_prices page ---
@app.route('/set_all_prices', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def set_all_prices():
    # --- Filter/Group/Sort Logic (similar to products route) ---
    # Get current preferences from URL parameters or session
    # Defaults should ensure all products are loaded initially
    group_by = request.args.get('group_by_price', session.get('set_prices_group_by', 'none'))
    # No sort_by/sort_order needed for set_all_prices client-side sort, but keep if you want server-side initial sort
    type_filter = request.args.get('type_filter_price', session.get('set_prices_type_filter', 'all'))
    search_query = request.args.get('search_query_price', session.get('set_prices_search_query', ''))

    # Store preferences in session for persistence
    session['set_prices_group_by'] = group_by
    session['set_prices_type_filter'] = type_filter
    session['set_prices_search_query'] = search_query
    # --- END Filter/Group/Sort Logic ---

    if request.method == 'POST':
        # ... (existing POST logic for saving prices - UNCHANGED) ...

        # After POST, redirect with current filter settings to maintain view
        return redirect(url_for('set_all_prices',
                                group_by_price=group_by,
                                type_filter_price=type_filter,
                                search_query_price=search_query))

    # --- GET request: Populate products for the initial page render ---
    all_products = Product.query.order_by(Product.name).all() # Fetch all products to pass to JS

    # Get grouped products based on current filter/group settings for initial render
    # We explicitly pass all products here because the client-side JS handles dynamic filtering
    # The server-side render should reflect initial filters or show all.
    # We will pass the full product list and let JS handle the display.
    # For initial render, group_by_price might be 'none' and type_filter_price 'all' by default.
    grouped_products = get_products_data(
        group_by=group_by,
        sort_by='name', # Default sort for initial render
        sort_order='asc',
        type_filter=type_filter,
        search_query=search_query
    )

    all_product_types = db.session.query(distinct(Product.type)).order_by(Product.type).all()
    all_product_types = [t[0] for t in all_product_types]

    # Pre-populate current unit prices to make originalPrice available for JS
    # This is implicitly done by passing the product objects from grouped_products

    return render_template('set_all_prices.html',
                           grouped_products=grouped_products, # Passed to Jinja for initial rendering
                           all_product_types=all_product_types,
                           current_group_by=group_by,
                           current_type_filter=type_filter,
                           current_search_query=search_query)

@app.route('/edit_product/<int:product_id>', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def edit_product(product_id):
    product = Product.query.get_or_404(product_id)
    if request.method == 'POST':
        product.name = request.form['name']
        product.type = request.form['type']
        product.unit_of_measure = request.form['unit_of_measure']
        unit_price = request.form.get('unit_price')
        product.unit_price = float(unit_price) if unit_price else None
        # NEW: Update product_number
        product_number = request.form.get('product_number')
        product.product_number = product_number if product_number else None
        db.session.commit()
        flash('Product updated successfully!', 'success')
        return redirect(url_for('products'))
    return render_template('edit_product.html', product=product)

@app.route('/delete_product/<int:product_id>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def delete_product(product_id):
    product = Product.query.get_or_404(product_id)
    db.session.delete(product)
    db.session.commit()
    flash('Product deleted successfully!', 'success')
    return redirect(url_for('products'))


@app.route('/locations', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def manage_locations():
    if request.method == 'POST':
        location_name = request.form.get('name')
        if location_name and not Location.query.filter_by(name=location_name).first():
            db.session.add(Location(name=location_name))
            db.session.commit()
            flash(f'Location "{location_name}" added successfully.', 'success')
        else:
            flash('Location name is invalid or already exists.', 'danger')
        return redirect(url_for('manage_locations'))
    locations = Location.query.all()
    return render_template('locations.html', locations=locations)

@app.route('/locations/delete/<int:location_id>', methods=['POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def delete_location(location_id):
    location = Location.query.get_or_404(location_id)
    db.session.delete(location)
    db.session.commit()
    flash(f'Location "{location.name}" has been deleted.', 'success')
    return redirect(url_for('manage_locations'))

@app.route('/locations/assign/<int:location_id>', methods=['GET', 'POST'])
@login_required
@role_required(['manager', 'general_manager', 'system_admin'])
def assign_products(location_id):
    location = Location.query.get_or_404(location_id)
    if request.method == 'POST':
        assigned_product_ids = request.form.getlist('product_ids', type=int)
        location.products = Product.query.filter(Product.id.in_(assigned_product_ids)).all()
        db.session.commit()
        flash(f'Product list for "{location.name}" has been updated.', 'success')
        return redirect(url_for('manage_locations'))

    # Fetch all products available
    products = Product.query.order_by(Product.type, Product.name).all()
    # Get IDs of currently assigned products for checkbox pre-selection
    assigned_product_ids = [p.id for p in location.products]

    # NEW: Fetch all distinct product types for the filter dropdown
    all_product_types = db.session.query(distinct(Product.type)).order_by(Product.type).all()
    all_product_types = [t[0] for t in all_product_types]


    return render_template('assign_products.html',
                           location=location,
                           products=products,
                           assigned_product_ids=assigned_product_ids,
                           all_product_types=all_product_types)

# ==============================================================================
# API Routes
# ==============================================================================

@app.route('/api/active-users')
@login_required
@role_required(['manager', 'general_manager', 'system_admin', 'owners'])
def api_active_users():
    """
    Returns a JSON list of users who have been active in the last 5 minutes.
    This endpoint is used by client-side JavaScript for AJAX polling.
    """
    five_minutes_ago = datetime.utcnow() - timedelta(minutes=5)
    users = User.query.filter(User.last_seen > five_minutes_ago).order_by(User.last_seen.desc()).all()

    users_data = []
    for user in users:
        roles_names = [role.name.replace('_', ' ').title() for role in user.roles]
        users_data.append({
            'id': user.id,
            'full_name': user.full_name,
            'username': user.username,
            'roles': roles_names,
            'last_seen': user.last_seen.strftime('%Y-%m-%d %H:%M:%S') + ' UTC',
            'force_logout_requested': user.force_logout_requested
        })
    return jsonify(users_data)

@app.route('/api/latest-announcement')
@login_required
def latest_announcement_api():
    latest = Announcement.query.order_by(Announcement.id.desc()).first()
    if latest:
        return jsonify({'id': latest.id, 'title': latest.title, 'message': latest.message, 'user_id': latest.user_id, 'user_name': latest.user.full_name})
    return jsonify(None)

@app.route('/api/mark-announcements-read', methods=['POST'])
@login_required
def mark_announcements_read():
    """Marks all announcements as seen by the current user."""
    try:
        seen_announcement_ids = {a.id for a in current_user.seen_announcements}
        unread_announcements = Announcement.query.filter(Announcement.id.notin_(seen_announcement_ids)).all()
        for announcement in unread_announcements:
            current_user.seen_announcements.append(announcement)
        db.session.commit()
        return jsonify({'status': 'success', 'message': f'{len(unread_announcements)} announcements marked as read.'})
    except Exception as e:
        db.session.rollback()
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/api/variance-history/<int:product_id>')
@login_required
@role_required(['manager', 'system_admin'])
def variance_history_api(product_id):
    try:
        product = Product.query.get_or_404(product_id)

        end_date = datetime.utcnow().date()
        start_date = end_date - timedelta(days=29) # Last 30 days

        labels = []
        data_points = []

        current_iter_date = start_date
        while current_iter_date <= end_date:
            labels.append(current_iter_date.strftime('%b %d'))

            # --- Calculate Expected EOD for current_iter_date ---
            # 1. BOD for current_iter_date (which is previous day's EOD)
            #    This is the auto-calculated BOD that should exist for this day.
            bod_entry = BeginningOfDay.query.filter_by(product_id=product_id, date=current_iter_date).first()
            bod_amount = bod_entry.amount if bod_entry else 0.0

            # 2. Deliveries for current_iter_date
            deliveries_for_day = Delivery.query.filter_by(product_id=product_id, delivery_date=current_iter_date).all()
            total_deliveries = sum(d.quantity for d in deliveries_for_day) if deliveries_for_day else 0.0 # Ensure sum on empty list is 0

            # 3. Manual Sales for current_iter_date
            manual_sale = Sale.query.filter_by(product_id=product_id, date=current_iter_date).first()
            manual_sale_qty = manual_sale.quantity_sold if manual_sale else 0.0

            # 4. Cocktail Ingredient Usage for current_iter_date
            #    Need to call the helper function for each day
            cocktail_usage_on_day_all_products = _calculate_ingredient_usage_from_cocktails_sold(current_iter_date)
            cocktail_usage_qty = cocktail_usage_on_day_all_products.get(product_id, 0.0) # Default to 0 if product not found

            # Expected EOD = BOD + Deliveries - Manual Sales - Cocktail Usage
            expected_eod = bod_amount + total_deliveries - manual_sale_qty - cocktail_usage_qty
            expected_eod = max(0.0, expected_eod) # Ensure non-negative


            # --- Get Actual EOD from latest count for current_iter_date ---
            latest_count = Count.query.filter(
                Count.product_id == product_id,
                func.date(Count.timestamp) == current_iter_date
            ).order_by(Count.timestamp.desc()).first()

            daily_variance = None
            if latest_count and latest_count.variance_amount is not None:
                # Use the pre-calculated variance stored with the count
                daily_variance = latest_count.variance_amount
            elif latest_count:
                # If variance_amount not stored, but actual count exists, calculate based on actual vs. expected
                daily_variance = latest_count.amount - expected_eod
            else:
                # No actual count means no 'actual - expected' variance for this day
                daily_variance = None

            data_points.append(daily_variance)

            current_iter_date += timedelta(days=1)

        return jsonify({'labels': labels, 'data': data_points})

    except Exception as e:
        app.logger.exception(f"Error generating variance history for product ID {product_id}")
        return jsonify({'error': 'Failed to load historical data due to a server error.'}), 500

# ==============================================================================
# Google Drive OAuth Routes (NEW for Web Application Flow)
# ==============================================================================

@app.route('/test-google-drive-access')
@login_required
@role_required(['system_admin']) # Only admin should run this
def test_google_drive_access():
    try:
        services = get_drive_service()
        drive_service = services['drive']
        sheets_service = services['sheets']

        # Test Sheet Access
        sheet_id = app.config['EOD_REPORT_SHEET_ID']
        try:
            sheet_metadata = drive_service.files().get(fileId=sheet_id, fields='id, name',supportsAllDrives=True).execute()
            flash(f"SUCCESS: Google Sheet '{sheet_metadata.get('name')}' (ID: {sheet_id}) found and accessible.", 'success')
        except HttpError as e:
            flash(f"ERROR: Google Sheet ID {sheet_id} not found or inaccessible. HttpError: {e}", 'danger')
            app.logger.error(f"Test Sheet Access Error: {e}", exc_info=True)
        except Exception as e:
            flash(f"ERROR: Unexpected error accessing Google Sheet ID {sheet_id}: {e}", 'danger')
            app.logger.error(f"Test Sheet Access Unexpected Error: {e}", exc_info=True)

        # Test EOD Images Folder Access
        eod_images_folder_id = app.config['GOOGLE_DRIVE_EOD_IMAGES_FOLDER_ID']
        try:
            folder_metadata = drive_service.files().get(fileId=eod_images_folder_id, fields='id, name',supportsAllDrives=True).execute()
            flash(f"SUCCESS: EOD Images Folder '{folder_metadata.get('name')}' (ID: {eod_images_folder_id}) found and accessible.", 'success')
        except HttpError as e:
            flash(f"ERROR: EOD Images Folder ID {eod_images_folder_id} not found or inaccessible. HttpError: {e}", 'danger')
            app.logger.error(f"Test EOD Images Folder Access Error: {e}", exc_info=True)
        except Exception as e:
            flash(f"ERROR: Unexpected error accessing EOD Images Folder ID {eod_images_folder_id}: {e}", 'danger')
            app.logger.error(f"Test EOD Images Folder Unexpected Error: {e}", exc_info=True)

        # Test Leave Docs Folder Access
        leave_docs_folder_id = app.config['GOOGLE_DRIVE_LEAVE_DOCS_FOLDER_ID']
        try:
            folder_metadata = drive_service.files().get(fileId=leave_docs_folder_id, fields='id, name',supportsAllDrives=True).execute()
            flash(f"SUCCESS: Leave Docs Folder '{folder_metadata.get('name')}' (ID: {leave_docs_folder_id}) found and accessible.", 'success')
        except HttpError as e:
            flash(f"ERROR: Leave Docs Folder ID {leave_docs_folder_id} not found or inaccessible. HttpError: {e}", 'danger')
            app.logger.error(f"Test Leave Docs Folder Access Error: {e}", exc_info=True)
        except Exception as e:
            flash(f"ERROR: Unexpected error accessing Leave Docs Folder ID {leave_docs_folder_id}: {e}", 'danger')
            app.logger.error(f"Test Leave Docs Folder Unexpected Error: {e}", exc_info=True)


    except Exception as e:
        flash(f"CRITICAL ERROR: Failed to get Google Drive service: {e}", 'danger')
        app.logger.error(f"Test Drive Access Critical Error: {e}", exc_info=True)

    return redirect(url_for('dashboard')) # Or a dedicated test results page

@app.route('/google/authorize')
@login_required # Only an admin should trigger this initial authorization
@role_required(['system_admin'])
def google_authorize():
    """Initiates the Google Drive OAuth2.0 authentication flow."""
    flow = Flow.from_client_secrets_file(
        app.config['GOOGLE_DRIVE_CREDENTIALS_FILE'],
        scopes=app.config['GOOGLE_DRIVE_SCOPES'],
        redirect_uri=app.config['GOOGLE_OAUTH_REDIRECT_URI']
    )

    authorization_url, state = flow.authorization_url(
        access_type='offline',  # Request a refresh token
        include_granted_scopes='true'
    )

    session['oauth_state'] = state # Store state in session to prevent CSRF
    return redirect(authorization_url)

@app.route('/google/callback')
@login_required # Only an admin should complete this authorization
@role_required(['system_admin'])
def google_callback():
    """Handles the redirect from Google after user authorization."""
    state = session.pop('oauth_state', None)

    if not state or state != request.args.get('state'):
        flash('Invalid OAuth state. Potential CSRF attack.', 'danger')
        app.logger.error(f"Invalid OAuth state: Expected {state}, Got {request.args.get('state')}")
        return redirect(url_for('dashboard'))

    try:
        flow = Flow.from_client_secrets_file(
            app.config['GOOGLE_DRIVE_CREDENTIALS_FILE'],
            scopes=app.config['GOOGLE_DRIVE_SCOPES'],
            redirect_uri=app.config['GOOGLE_OAUTH_REDIRECT_URI']
        )
        flow.fetch_token(authorization_response=request.url)

        creds = flow.credentials

        # Save the credentials (including refresh token) for future use
        with open(app.config['GOOGLE_DRIVE_TOKEN_FILE'], 'w') as token:
            token.write(creds.to_json())

        flash('Google Drive successfully authorized!', 'success')
        log_activity(f"Google Drive API authorized by {current_user.full_name}.")
        return redirect(url_for('dashboard'))

    except Exception as e:
        app.logger.error(f"Error during Google Drive callback: {e}", exc_info=True)
        flash(f'Google Drive authorization failed: {e}', 'danger')
        return redirect(url_for('dashboard'))

# ==============================================================================
# Main Execution
# ==============================================================================


@app.cli.command('auth-google-drive', help='Initiates Google Drive OAuth2.0 authentication for the web app.')
def auth_google_drive_cli():
    """Instructs the user to perform the web-based Google Drive authentication."""
    print("For web application authentication, you need to initiate the OAuth flow via your browser.")
    print(f"Please log in to your Flask application as an admin and navigate to: {app.config['GOOGLE_OAUTH_REDIRECT_URI'].replace('/google/callback', '/google/authorize')}")
    print("Or if running locally, point your browser to:")
    print(f"http://localhost:5000/google/authorize (assuming default port 5000)")
    print("Follow the prompts in your browser to authorize access.")
    print("Once complete, your 'token.json' file will be created/updated.")

if __name__ == '__main__':
    with app.app_context():
        db.create_all()

    app.run(debug=False)