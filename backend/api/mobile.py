from flask import jsonify, request, current_app
from backend.api import mobile_api_bp

from backend.models import (db, User, Location, Product, Role, BeginningOfDay, Count,
                            Announcement, ActivityLog, RecountRequest, Sale, Delivery, Recipe, RecipeIngredient, CocktailsSold,
                            LeaveRequest, VarianceExplanation, UserFCMToken, ShiftSubmission, Schedule, RequiredStaff, ShiftSwapRequest, VolunteeredShift,
                            Warning, Booking)

from firebase_admin import messaging

from flask_jwt_extended import jwt_required, get_jwt_identity, create_access_token

from datetime import datetime, timedelta, time, timezone
from functools import wraps
from werkzeug.utils import secure_filename
import io
import mimetypes
import os


from sqlalchemy import distinct, func, or_

from ..utils import (get_drive_service, upload_file_to_drive, append_eod_data_to_google_sheet,
                     get_role_specific_shift_types, get_shift_time_display,
                     SCHEDULER_SHIFT_TYPES_GENERIC, ROLE_SHIFT_DEFINITIONS,
                     MANUAL_CONTENT)

def _build_week_dates_api(week_offset=0):
    """
    Calculates the 7 dates for the current/offset scheduling week, always starting on Monday.
    Also fetches approved leave requests for that week.
    Returns: start_of_week, week_dates, end_of_week, leave_dict
    """
    today = datetime.now(timezone.utc).date()
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
    leave_dict = {req.id: [] for req in User.query.all()} # Initialize for all users
    for req in leave_requests_this_week:
        for d in week_dates:
            if req.start_date <= d <= req.end_date:
                leave_dict.setdefault(req.user_id, []).append(d.isoformat()) # Store ISO format for dates

    return start_of_offset_week, week_dates, end_of_week, leave_dict

def send_push_notification(user_id, title, body, data=None):
    """
    Sends a push notification to all FCM tokens associated with a user.
    `data` is an optional dictionary for custom key-value pairs (e.g., {"type": "shift_published"}).
    """
    user = User.query.get(user_id)
    if not user:
        current_app.logger.warning(f"Attempted to send notification to non-existent user_id: {user_id}")
        return False

    if not user.fcm_tokens:
        current_app.logger.info(f"User {user.username} has no FCM tokens registered.")
        return False

    # Get a list of all FCM tokens for the user
    registration_tokens = [token_obj.fcm_token for token_obj in user.fcm_tokens]

    # Create a MulticastMessage for efficiency
    message = messaging.MulticastMessage(
        notification=messaging.Notification(
            title=title,
            body=body,
        ),
        data=data, # Optional data payload
        tokens=registration_tokens,
    )

    try:
        response = messaging.send_multicast(message)
        current_app.logger.info(f"Successfully sent {response.success_count} messages to user {user.username}.")
        if response.failure_count > 0:
            for resp in response.responses:
                if not resp.success:
                    current_app.logger.warning(f"Failed to send message: {resp.exception}")
                    # You might want to remove invalid/expired tokens here
                    # For example, if resp.exception is messaging.UnregisteredError:
                    # if isinstance(resp.exception, messaging.UnregisteredError):
                    #    # Find and delete the corresponding token from db
                    #    pass
        return True
    except Exception as e:
        current_app.logger.error(f"Error sending FCM notification to user {user.username}: {e}", exc_info=True)
        return False

@mobile_api_bp.route('/fcm_token/register', methods=['POST'])
@jwt_required()
def register_fcm_token():
    """
    Registers or updates a user's FCM token.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    data = request.json
    fcm_token = data.get('fcm_token')
    device_info = data.get('device_info') # Optional

    if not fcm_token:
        return jsonify({"msg": "FCM token is required."}), 400

    # Check if the token already exists for this user (or any user to update it)
    existing_token_entry = UserFCMToken.query.filter_by(fcm_token=fcm_token).first()

    if existing_token_entry:
        # If the token exists but is linked to a different user (e.g., device given to new user), reassign
        if existing_token_entry.user_id != user.id:
            existing_token_entry.user_id = user.id
            existing_token_entry.device_info = device_info
            existing_token_entry.timestamp = datetime.utcnow()
            current_app.logger.info(f"FCM token {fcm_token} reassigned to user {user.username}.")
        else:
            # Token exists for this user, just update timestamp/device info if needed
            existing_token_entry.device_info = device_info
            existing_token_entry.timestamp = datetime.utcnow()
            current_app.logger.info(f"FCM token {fcm_token} updated for user {user.username}.")
    else:
        # Create a new token entry
        new_token = UserFCMToken(
            user_id=user.id,
            fcm_token=fcm_token,
            device_info=device_info
        )
        db.session.add(new_token)
        current_app.logger.info(f"FCM token {fcm_token} registered for user {user.username}.")

    try:
        db.session.commit()
        return jsonify({"msg": "FCM token registered successfully."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error registering FCM token: {e}", exc_info=True)
        return jsonify({"msg": "Failed to register FCM token due to server error."}), 500

@mobile_api_bp.route('/fcm_token/unregister', methods=['POST'])
@jwt_required()
def unregister_fcm_token():
    """
    Unregisters a user's FCM token (e.g., when they log out or uninstall).
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    data = request.json
    fcm_token = data.get('fcm_token')

    if not fcm_token:
        return jsonify({"msg": "FCM token is required."}), 400

    token_entry = UserFCMToken.query.filter_by(user_id=user.id, fcm_token=fcm_token).first()

    if token_entry:
        db.session.delete(token_entry)
        try:
            db.session.commit()
            current_app.logger.info(f"FCM token {fcm_token} unregistered for user {user.username}.")
            return jsonify({"msg": "FCM token unregistered successfully."}), 200
        except Exception as e:
            db.session.rollback()
            current_app.logger.error(f"Error unregistering FCM token: {e}", exc_info=True)
            return jsonify({"msg": "Failed to unregister FCM token due to server error."}), 500
    else:
        return jsonify({"msg": "FCM token not found for this user."}), 404


# NEW: Role-based authorization for API endpoints
# Let's encapsulate the decorator creation slightly differently to avoid Flask's auto-detection.
# This approach explicitly returns a decorator function that Flask won't try to register as a view.
def create_role_required_api_decorator():
    def role_required_api(role_names):
        """Decorator to restrict API access based on user roles from JWT."""
        def wrapper(fn):
            @wraps(fn)
            def decorated_view(*args, **kwargs):
                current_user_id = get_jwt_identity()
                user = User.query.get(current_user_id)

                if not user:
                    return jsonify({"msg": "User not found"}), 404
                
                user_role_names = [r.name for r in user.roles]
                if not any(role_name in user_role_names for role_name in role_names):
                    return jsonify({"msg": "Access Denied: Insufficient permissions"}), 403
                
                return fn(*args, **kwargs)
            return decorated_view
        return wrapper
    return role_required_api

# Assign the created decorator function to a variable
role_required_api = create_role_required_api_decorator()

@mobile_api_bp.route('/login', methods=['POST'])
def login():
    app_bcrypt = current_app.extensions['flask_bcrypt']

    username = request.json.get('username', None)
    password = request.json.get('password', None)

    user = User.query.filter_by(username=username).first()

    if not user or not app_bcrypt.check_password_hash(user.password, password):
        return jsonify({"msg": "Bad username or password"}), 401

    access_token = create_access_token(identity=str(user.id), expires_delta=timedelta(days=1))
    return jsonify(access_token=access_token), 200

@mobile_api_bp.route('/protected', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners', 'hostess'])
def protected():
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404
    
    user_roles = [r.name for r in user.roles]

    return jsonify(
        id=user.id,
        username=user.username,
        full_name=user.full_name,
        roles=user_roles
    ), 200

@mobile_api_bp.route('/profile', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners', 'hostess'])
def get_user_profile():
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    user_roles = [r.name for r in user.roles]

    return jsonify({
        "id": user.id,
        "username": user.username,
        "full_name": user.full_name,
        "email": user.email,
        "is_suspended": user.is_suspended,
        "roles": user_roles
    }), 200

@mobile_api_bp.route('/locations', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin'])
def get_locations():
    locations = Location.query.order_by(Location.name).all()
    
    locations_data = []
    for loc in locations:
        locations_data.append({
            "id": loc.id,
            "name": loc.name,
            "slug": loc.name.replace(' ', '_').lower()
        })
    return jsonify(locations_data), 200

@mobile_api_bp.route('/products_by_location/<int:location_id>', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin'])
def get_products_by_location(location_id):
    location = Location.query.get(location_id)
    if not location:
        return jsonify({"msg": "Location not found"}), 404

    products_in_location = location.products.order_by(Product.type, Product.name).all()

    products_data = []
    for product in products_in_location:
        products_data.append({
            "id": product.id,
            "name": product.name,
            "type": product.type,
            "unit_of_measure": product.unit_of_measure,
            "unit_price": product.unit_price,
            "product_number": product.product_number
        })
    return jsonify(products_data), 200

@mobile_api_bp.route('/bod_for_today', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'skullers', 'manager', 'general_manager', 'system_admin'])
def get_bod_for_today():
    """
    Returns the Beginning of Day (BOD) stock for all products for the current day.
    """
    today_date = datetime.utcnow().date()
    
    # We'll get all products first to ensure we return a comprehensive list,
    # even for those without a BOD entry (will show 0).
    all_products = Product.query.order_by(Product.name).all()

    bod_entries = BeginningOfDay.query.filter_by(date=today_date).all()
    bod_map = {entry.product_id: entry.amount for entry in bod_entries}

    response_data = []
    for product in all_products:
        response_data.append({
            "product_id": product.id,
            "product_name": product.name,
            "unit_of_measure": product.unit_of_measure,
            "bod_amount": bod_map.get(product.id, 0.0) # Default to 0.0 if no BOD entry
        })
    
    return jsonify(response_data), 200

@mobile_api_bp.route('/submit_count', methods=['POST'])
@jwt_required()
@role_required_api(['bartender', 'skullers', 'manager', 'general_manager', 'system_admin'])
def submit_count():
    """
    Receives count data for a location and saves it to the database.
    Can be a 'First Count' or 'Corrections Count'.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    data = request.json
    location_id = data.get('location_id')
    count_type_str = data.get('count_type') # 'First Count' or 'Corrections Count'
    products_to_count = data.get('products_to_count', []) # List of {product_id, amount, comment}

    if not location_id or not count_type_str or not products_to_count:
        return jsonify({"msg": "Missing required data: location_id, count_type, or products_to_count"}), 400

    location = Location.query.get(location_id)
    if not location:
        return jsonify({"msg": "Location not found"}), 404

    # Fetch expected_amounts and deliveries for variance calculation
    today_date = datetime.utcnow().date()
    yesterday = today_date - datetime.timedelta(days=1)
    
    
    bod_for_today_map = {
        b.product_id: b.amount
        for b in BeginningOfDay.query.filter_by(date=today_date).all()
    }
    todays_deliveries_map = {
        d.product_id: d.quantity
        for d in Delivery.query.filter_by(delivery_date=today_date).all()
    }
    
    new_count_entries = []
    
    for product_data in products_to_count:
        product_id = product_data.get('product_id')
        amount = product_data.get('amount')
        comment = product_data.get('comment')
        
        if product_id is None or amount is None:
            return jsonify({"msg": f"Missing product_id or amount for a product entry: {product_data}"}), 400
        
        product_obj = Product.query.get(product_id)
        if not product_obj:
            return jsonify({"msg": f"Product with ID {product_id} not found"}), 404

        # Calculate expected amount based on BOD for today + deliveries today
        # This is a simplified version of the web app's full logic.
        expected_amount_at_count = bod_for_today_map.get(product_id, 0.0) + \
                                   todays_deliveries_map.get(product_id, 0.0)

        variance_amount = float(amount) - expected_amount_at_count

        # Check for self-correction rule (only if it's a Corrections Count)
        if count_type_str == 'Corrections Count':
            # Find the first count for this product, location, and day
            first_count = Count.query.filter_by(
                product_id=product_id,
                location=location.name,
                count_type='First Count',
                user_id=user.id # By the current user
            ).filter(db.func.date(Count.timestamp) == today_date).first()

            if first_count:
                # If the current user submitted the first count, they cannot correct it
                return jsonify({"msg": f"User {user.full_name} cannot submit corrections for product {product_obj.name} because they submitted the first count."}), 403

        # Create new count entry
        new_count = Count(
            product_id=product_id,
            user_id=user.id,
            location=location.name,
            count_type=count_type_str,
            amount=float(amount),
            comment=comment,
            expected_amount=expected_amount_at_count,
            variance_amount=variance_amount
        )
        new_count_entries.append(new_count)
    
    try:
        db.session.add_all(new_count_entries)
        db.session.commit()
        return jsonify({"msg": f"{count_type_str} submitted successfully for {location.name}."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting count: {e}")
        return jsonify({"msg": "Failed to submit count due to server error."}), 500

@mobile_api_bp.route('/announcements', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners', 'hostess'])
def get_announcements():
    """
    Returns announcements relevant to the current user's roles.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    user_roles_ids = [role.id for role in user.roles]

    # Replicate the announcement filtering logic from inject_global_data in app.py
    # Filter for announcements that are either:
    # 1. Not targeted to any specific role
    # 2. Targeted to one of the current_user's roles
    # 3. Posted by the current user (optional, but good for management context)
    filtered_announcements_query = Announcement.query.outerjoin(Announcement.target_roles) \
                                                  .filter(or_(
                                                      db.not_(Announcement.target_roles.any()), # No specific roles targeted
                                                      Role.id.in_(user_roles_ids) # Targeted to user's roles
                                                      # Announcement.user_id == current_user_id # If you want to include all announcements posted by user
                                                  )) \
                                                  .distinct() \
                                                  .order_by(Announcement.id.desc()) \
                                                  .limit(10) # Limit for mobile dashboard display

    announcements = filtered_announcements_query.all()

    announcements_data = []
    for ann in announcements:
        announcements_data.append({
            "id": ann.id,
            "title": ann.title,
            "message": ann.message,
            "category": ann.category,
            "timestamp": ann.timestamp.isoformat(), # ISO format for easy parsing in Flutter
            "posted_by": ann.user.full_name,
            "action_link": ann.action_link # If present, for navigation
            # You might add a field here to indicate if the current user has seen it,
            # but that would require a more complex query joining with `announcement_view`.
            # For simplicity, mobile just fetches all relevant and displays.
        })
    return jsonify(announcements_data), 200

@mobile_api_bp.route('/location_count_statuses', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'skullers', 'manager', 'general_manager', 'system_admin'])
def get_location_count_statuses():
    """
    Returns the current day's count status for each location.
    Also indicates if BOD for today has been submitted.
    """
    today_date = datetime.utcnow().date()
    
    # Check if BOD for today has been submitted (important for enabling counts)
    bod_submitted_for_today = BeginningOfDay.query.filter_by(date=today_date).first() is not None

    locations = Location.query.order_by(Location.name).all()
    location_statuses_data = []

    for loc in locations:
        latest_count_for_location = Count.query.filter(
            Count.location == loc.name,
            db.func.date(Count.timestamp) == today_date # Ensure func.date is used for date comparison
        ).order_by(Count.timestamp.desc()).first() # Get the very latest count

        status = 'not_started'
        if latest_count_for_location:
            status = 'corrected' if latest_count_for_location.count_type == 'Corrections Count' else 'counted'
        
        location_statuses_data.append({
            "id": loc.id,
            "name": loc.name,
            "slug": loc.name.replace(' ', '_').lower(),
            "status": status, # 'not_started', 'counted', 'corrected'
        })
    
    return jsonify({
        "bod_submitted_for_today": bod_submitted_for_today,
        "location_statuses": location_statuses_data
    }), 200

@mobile_api_bp.route('/dashboard_summary', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'owners'])
def get_dashboard_summary():
    """
    Provides aggregated dashboard alerts and summary data for managers/admins.
    Includes password reset requests and variance alerts.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    summary_data = {
        "password_reset_requests": [],
        "variance_alerts": [],
        "activity_logs": [], # Only for system admins
        "open_shifts_for_volunteering": [], # Only for staff
        "is_bod_submitted": False # For variance alerts context
    }

    # --- Password Reset Requests (for system_admin) ---
    if user.has_role('system_admin'):
        reset_requests = User.query.filter_by(password_reset_requested=True).all()
        summary_data["password_reset_requests"] = [{
            "id": req_user.id,
            "full_name": req_user.full_name,
            "username": req_user.username
        } for req_user in reset_requests]

        # --- Recent Activity Log (for system_admin) ---
        activity_logs = ActivityLog.query.order_by(ActivityLog.timestamp.desc()).limit(10).all()
        summary_data["activity_logs"] = [{
            'user_full_name': log.user.full_name,
            'user_username': log.user.username,
            'action': log.action,
            'timestamp': log.timestamp.isoformat()
        } for log in activity_logs]


    # --- Variance Alerts (for managers, GMs, system_admin, owners) ---
    today_date = datetime.utcnow().date()
    yesterday = today_date - timedelta(days=1)

    bod_submitted_today = BeginningOfDay.query.filter_by(date=today_date).first() is not None
    summary_data["is_bod_submitted"] = bod_submitted_today

    if bod_submitted_today:
        # Fetch BOD for today
        bod_counts = {b.product_id: b.amount for b in BeginningOfDay.query.filter_by(date=today_date).all()}
        # Fetch yesterday's sales to calculate today's *expected* EOD (which is BOD - sales from previous day)
        # Assuming previous day's sales are settled before today's BOD is calculated/used.
        # This mirrors the `daily_summary` logic
        sales_counts_yesterday = {s.product_id: s.quantity_sold for s in Sale.query.filter_by(date=yesterday).all()}
        
        # Fetch today's deliveries
        todays_deliveries = {d.product_id: d.quantity for d in Delivery.query.filter_by(delivery_date=today_date).all()}

        # Fetch today's cocktail ingredient usage (requires a helper or re-implementation)
        # For simplicity for this mobile API, let's assume cocktail usage is part of previous day's sales settling.
        # If detailed real-time usage is needed for *today*, you'd need `_calculate_ingredient_usage_from_cocktails_sold`
        # helper to be available and callable from here.
        
        # For now, let's simplify to only compare with BOD and deliveries for current variance
        
        products = Product.query.all()
        eod_latest_count_objects = {} # {product_id: Count_object}
        all_counts_on_today = Count.query.filter(db.func.date(Count.timestamp) == today_date).all()
        for count in all_counts_on_today:
            product_id = count.product_id
            if product_id not in eod_latest_count_objects or count.timestamp > eod_latest_count_objects[product_id].timestamp:
                eod_latest_count_objects[product_id] = count
        
        variance_alerts = []
        for product in products:
            bod = bod_counts.get(product.id, 0.0)
            deliveries = todays_deliveries.get(product.id, 0.0)
            
            # Simplified expected EOD for mobile context (BOD + Deliveries)
            # Full web app dashboard factors in sales of the day, but mobile might not need that real-time for an "alert"
            expected_amount_available = bod + deliveries

            latest_count_obj = eod_latest_count_objects.get(product.id)
            
            variance_val = None
            if latest_count_obj and latest_count_obj.variance_amount is not None:
                variance_val = latest_count_obj.variance_amount
            elif latest_count_obj: # If actual count exists but variance wasn't stored, calculate based on current expected
                 variance_val = latest_count_obj.amount - expected_amount_available

            if variance_val is not None and variance_val != 0:
                variance_alerts.append({
                    'product_id': product.id,
                    'product_name': product.name,
                    'variance': round(variance_val, 2)
                })
        summary_data["variance_alerts"] = variance_alerts


    # --- Open Shifts for Volunteering (for staff roles) ---
    # This logic replicates the dashboard's `open_shifts_for_volunteering` section.
    # It requires models like `VolunteeredShift`, `Schedule`, `User`, `Role`.
    if user.has_role('bartender') or user.has_role('waiter') or user.has_role('skullers'):
        all_open_volunteered_shifts = VolunteeredShift.query.filter_by(status='Open').all()

        # Get current_user's schedule for the week to check for conflicts
        today_date_for_week = datetime.utcnow().date()
        days_since_monday = (today_date_for_week.weekday()) % 7 # 0 for Mon, 1 for Tue etc.
        week_start = today_date_for_week - datetime.timedelta(days=days_since_monday)
        week_end = week_start + datetime.timedelta(days=6)

        current_user_scheduled_shifts_raw = Schedule.query.filter(
            Schedule.user_id == user.id,
            Schedule.shift_date.between(week_start, week_end)
        ).all()
        current_user_schedule_this_week = {} # {date_iso: {shift_type1, shift_type2}}
        for s in current_user_scheduled_shifts_raw:
            current_user_schedule_this_week.setdefault(s.shift_date.isoformat(), set()).add(s.assigned_shift)

        current_user_roles = [r.name for r in user.roles]

        for v_shift in all_open_volunteered_shifts:
            # Skip shifts relinquished by self
            if v_shift.requester_id == user.id:
                continue

            requester_roles = [r.name for r in v_shift.requester.roles]
            has_matching_role = any(role in requester_roles for role in current_user_roles)
            if not has_matching_role:
                continue

            shift_date_iso = v_shift.schedule.shift_date.isoformat()
            assigned_shifts_on_day = current_user_schedule_this_week.get(shift_date_iso, set())

            conflict = False
            requested_shift_type = v_shift.schedule.assigned_shift

            # Simplified conflict check: If a double is requested, any existing shift conflicts.
            # If a day/night is requested, a double or the same shift type conflicts.
            if 'Double' in requested_shift_type: # Catches 'Double', 'Double A', 'Double B'
                if assigned_shifts_on_day:
                    conflict = True
            else: # Day, Night, Open, Split Double
                if 'Double' in assigned_shifts_on_day or requested_shift_type in assigned_shifts_on_day:
                    conflict = True

            already_volunteered = any(v_user.id == user.id for v_user in v_shift.volunteers)

            if not conflict and not already_volunteered:
                summary_data["open_shifts_for_volunteering"].append({
                    'id': v_shift.id,
                    'assigned_shift': v_shift.schedule.assigned_shift,
                    'shift_date': v_shift.schedule.shift_date.isoformat(),
                    'requester_full_name': v_shift.requester.full_name,
                    'relinquish_reason': v_shift.relinquish_reason
                })
    
    return jsonify(summary_data), 200 

@mobile_api_bp.route('/submit_bod_stock', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def submit_bod_stock():
    """
    Receives Beginning of Day (BOD) stock for multiple products for the current day.
    This is equivalent to setting initial stock for the day.
    """
    current_user_id = get_jwt_identity()
    # User object not directly used here but good for decorator context

    today_date = datetime.utcnow().date()
    data = request.json
    products_stock_data = data.get('products_stock_data', []) # List of {product_id, amount}

    if not products_stock_data:
        return jsonify({"msg": "No product stock data provided."}), 400

    errors = []
    updated_count = 0
    new_count = 0

    for item in products_stock_data:
        product_id = item.get('product_id')
        amount = item.get('amount')

        if product_id is None or amount is None:
            errors.append(f"Missing product_id or amount in item: {item}")
            continue

        try:
            amount = float(amount)
            if amount < 0:
                errors.append(f"Stock amount for product_id {product_id} must be non-negative. Received: {amount}")
                continue
        except ValueError:
            errors.append(f"Invalid amount for product_id {product_id}. Received: {amount}")
            continue

        # Check if BOD entry for this product already exists for today
        existing_bod = BeginningOfDay.query.filter_by(product_id=product_id, date=today_date).first()

        if existing_bod:
            if existing_bod.amount != amount:
                existing_bod.amount = amount
                updated_count += 1
        else:
            new_bod = BeginningOfDay(
                product_id=product_id,
                amount=amount,
                date=today_date
            )
            db.session.add(new_bod)
            new_count += 1
    
    if errors:
        db.session.rollback() # Rollback all changes if any error occurred
        return jsonify({"msg": "Errors occurred during submission.", "details": errors}), 400

    try:
        db.session.commit()
        return jsonify({"msg": f"BOD stock updated successfully. New entries: {new_count}, Updated entries: {updated_count}."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting BOD stock: {e}")
        return jsonify({"msg": "Failed to submit BOD stock due to server error."}), 500

@mobile_api_bp.route('/request_recount', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def request_recount():
    """
    Allows managers to request a recount for a specific product or location.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    data = request.json
    product_id = data.get('product_id')
    location_id = data.get('location_id')
    
    if not product_id and not location_id:
        return jsonify({"msg": "Must specify either product_id OR location_id for a recount."}), 400
    if product_id and location_id:
        return jsonify({"msg": "Please request a recount for either a product OR a location, not both at once."}), 400

    target_obj_name = ""
    target_type = ""
    
    if product_id:
        product = Product.query.get(product_id)
        if not product:
            return jsonify({"msg": "Product not found."}), 404
        target_obj_name = product.name
        target_type = "product"
    elif location_id:
        location = Location.query.get(location_id)
        if not location:
            return jsonify({"msg": "Location not found."}), 404
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
        return jsonify({"msg": f"A recount for {target_obj_name} is already pending for today."}), 409 # 409 Conflict

    new_recount_request = RecountRequest(
        product_id=product_id,
        location_id=location_id,
        requested_by_user_id=user.id,
        request_date=datetime.utcnow().date(),
        status='Pending'
    )
    db.session.add(new_recount_request)

    # Create an announcement for relevant staff (mirrors web app)
    notification_title = "Recount Requested"
    notification_message = (
        f"A recount has been requested for {target_type} **{target_obj_name}** by {user.full_name}. "
        f"Please check inventory count pages for details and perform the recount."
    )
    target_roles_for_recount = Role.query.filter(Role.name.in_(['bartender', 'skullers'])).all()

    new_announcement = Announcement(
        user_id=user.id,
        title=notification_title,
        message=notification_message,
        category='Urgent',
        target_roles=target_roles_for_recount
    )
    db.session.add(new_announcement)

    try:
        db.session.commit()
        return jsonify({"msg": f"Recount for {target_obj_name} requested successfully. Relevant staff have been notified."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error requesting recount: {e}")
        return jsonify({"msg": "Failed to request recount due to server error."}), 500

@mobile_api_bp.route('/submit_sales', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def submit_sales():
    """
    Receives sales data for manual products and cocktails sold for a given date.
    This replaces the sales input part of the web's 'Beginning of Day' process.
    """
    current_user_id = get_jwt_identity()
    # User object not directly used here but implicitly by roles

    data = request.json
    sales_date_str = data.get('sales_date') # Date for which sales are being submitted
    manual_product_sales = data.get('manual_product_sales', []) # List of {product_id, quantity_sold}
    cocktail_sales = data.get('cocktail_sales', []) # List of {recipe_id, quantity_sold}

    if not sales_date_str:
        return jsonify({"msg": "Sales date is required."}), 400

    try:
        sales_date = datetime.strptime(sales_date_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid sales date format. Use YYYY-MM-DD."}), 400

    if not manual_product_sales and not cocktail_sales:
        return jsonify({"msg": "No sales data provided for manual products or cocktails."}), 400

    # --- Process Manual Product Sales ---
    # Delete existing manual sales for this date before adding new ones
    Sale.query.filter_by(date=sales_date).delete(synchronize_session=False)
    db.session.flush()

    for item in manual_product_sales:
        product_id = item.get('product_id')
        quantity_sold = item.get('quantity_sold')

        if product_id is None or quantity_sold is None:
            return jsonify({"msg": f"Missing product_id or quantity_sold in manual product sales item: {item}"}), 400
        
        try:
            quantity_sold = float(quantity_sold)
            if quantity_sold < 0:
                return jsonify({"msg": f"Quantity sold for product_id {product_id} must be non-negative."}), 400
        except ValueError:
            return jsonify({"msg": f"Invalid quantity sold for product_id {product_id}."}), 400

        product_obj = Product.query.get(product_id)
        if not product_obj:
            return jsonify({"msg": f"Product with ID {product_id} not found."}), 404
        
        new_sale = Sale(product_id=product_id, quantity_sold=quantity_sold, date=sales_date)
        db.session.add(new_sale)

    # --- Process Cocktail Sales ---
    # Delete existing cocktail sales for this date before adding new ones
    CocktailsSold.query.filter_by(date=sales_date).delete(synchronize_session=False)
    db.session.flush()

    for item in cocktail_sales:
        recipe_id = item.get('recipe_id')
        quantity_sold = item.get('quantity_sold')

        if recipe_id is None or quantity_sold is None:
            return jsonify({"msg": f"Missing recipe_id or quantity_sold in cocktail sales item: {item}"}), 400
        
        try:
            quantity_sold = int(quantity_sold)
            if quantity_sold < 0:
                return jsonify({"msg": f"Quantity sold for recipe_id {recipe_id} must be non-negative."}), 400
        except ValueError:
            return jsonify({"msg": f"Invalid quantity sold for recipe_id {recipe_id}."}), 400

        recipe_obj = Recipe.query.get(recipe_id)
        if not recipe_obj:
            return jsonify({"msg": f"Recipe with ID {recipe_id} not found."}), 404

        new_cocktail_sale = CocktailsSold(recipe_id=recipe_id, quantity_sold=quantity_sold, date=sales_date)
        db.session.add(new_cocktail_sale)

    try:
        db.session.commit()
        return jsonify({"msg": f"Sales for {sales_date_str} submitted successfully."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting sales: {e}")
        return jsonify({"msg": "Failed to submit sales due to server error."}), 500

@mobile_api_bp.route('/submit_delivery', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin']) # Deliveries are typically logged by managers/admins
def submit_delivery():
    """
    Receives and logs a new product delivery.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    data = request.json
    product_id = data.get('product_id')
    quantity = data.get('quantity')
    delivery_date_str = data.get('delivery_date')
    comment = data.get('comment') # Optional

    if product_id is None or quantity is None or not delivery_date_str:
        return jsonify({"msg": "Missing required data: product_id, quantity, or delivery_date."}), 400

    try:
        quantity = float(quantity)
        if quantity <= 0:
            return jsonify({"msg": "Quantity for delivery must be positive."}), 400
    except ValueError:
        return jsonify({"msg": "Invalid quantity for delivery."}), 400
    
    try:
        delivery_date = datetime.strptime(delivery_date_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid delivery date format. Use YYYY-MM-DD."}), 400

    product_obj = Product.query.get(product_id)
    if not product_obj:
        return jsonify({"msg": f"Product with ID {product_id} not found."}), 404

    new_delivery = Delivery(
        product_id=product_id,
        quantity=quantity,
        delivery_date=delivery_date,
        user_id=user.id,
        comment=comment
    )
    db.session.add(new_delivery)

    try:
        db.session.commit()
        return jsonify({"msg": f"Delivery of {quantity} {product_obj.unit_of_measure} {product_obj.name} logged successfully."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting delivery: {e}")
        return jsonify({"msg": "Failed to submit delivery due to server error."}), 500

@mobile_api_bp.route('/products', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin']) # Adjust roles as needed
def get_all_products_api():
    """
    Returns a list of all products.
    """
    products = Product.query.order_by(Product.name).all()
    products_data = []
    for product in products:
        products_data.append({
            "id": product.id,
            "name": product.name,
            "type": product.type,
            "unit_of_measure": product.unit_of_measure,
            "unit_price": product.unit_price,
            "product_number": product.product_number
        })
    return jsonify(products_data), 200

@mobile_api_bp.route('/recipes', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'manager', 'general_manager', 'system_admin', 'owners'])
def get_all_recipes_api():
    """
    Returns a list of all recipes with their basic details AND ingredients.
    """
    recipes = Recipe.query.order_by(Recipe.name).all()
    recipes_data = []
    for recipe in recipes:
        ingredients_data = []
        # Access the recipe_ingredients relationship
        for ri in recipe.recipe_ingredients:
            ingredients_data.append({
                "product_id": ri.product_id,
                "product_name": ri.product.name, # Access the product name
                "unit_of_measure": ri.product.unit_of_measure, # Access its unit
                "quantity": ri.quantity
            })

        recipes_data.append({
            "id": recipe.id,
            "name": recipe.name,
            "instructions": recipe.instructions,
            "ingredients": ingredients_data # <--- NEW: Add ingredients list
        })
    return jsonify(recipes_data), 200

@mobile_api_bp.route('/latest_counts_for_location/<int:location_id>', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'skullers', 'manager', 'general_manager', 'system_admin'])
def get_latest_counts_for_location(location_id):
    """
    Returns the latest submitted count (First or Corrections) for each product
    in a given location for the current day.
    """
    today_date = datetime.utcnow().date()

    location = Location.query.get(location_id)
    if not location:
        return jsonify({"msg": "Location not found"}), 404

    # Fetch all latest counts for each product in this location for today
    # This involves a subquery or a CTE to get the latest timestamp per product_id/location_name
    
    # Simpler approach: Fetch all counts for the day/location, then group in Python
    all_counts_today_for_location = Count.query.filter(
        Count.location == location.name,
        db.func.date(Count.timestamp) == today_date
    ).order_by(Count.timestamp.desc()).all() # Order by desc to easily pick latest

    latest_counts_map = {} # {product_id: latest_count_object}
    for count in all_counts_today_for_location:
        if count.product_id not in latest_counts_map:
            latest_counts_map[count.product_id] = count # The first one found (due to desc order) is the latest

    counts_data = []
    for product_id, count_obj in latest_counts_map.items():
        counts_data.append({
            "product_id": product_id,
            "amount": count_obj.amount,
            "comment": count_obj.comment,
            "count_type": count_obj.count_type, # 'First Count' or 'Corrections Count'
            "expected_amount": count_obj.expected_amount,
            "variance_amount": count_obj.variance_amount,
            "user_id": count_obj.user_id,
            "timestamp": count_obj.timestamp.isoformat()
        })
    
    return jsonify(counts_data), 200

@mobile_api_bp.route('/leave_requests', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners'])
def get_leave_requests():
    """
    Returns a list of leave requests for the current user, or all for managers/admins.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    is_manager_or_admin = user.has_role('manager') or user.has_role('general_manager') or user.has_role('system_admin')

    query = LeaveRequest.query.order_by(LeaveRequest.timestamp.desc())

    if not is_manager_or_admin:
        query = query.filter_by(user_id=user.id)

    leave_requests = query.all()

    requests_data = []
    for req in leave_requests:
        requests_data.append({
            "id": req.id,
            "user_id": req.user_id,
            "user_full_name": req.user.full_name, # Include requester's name
            "start_date": req.start_date.isoformat(),
            "end_date": req.end_date.isoformat(),
            "reason": req.reason,
            "document_path": req.document_path, # URL for the document
            "status": req.status,
            "timestamp": req.timestamp.isoformat(),
        })
    return jsonify(requests_data), 200

@mobile_api_bp.route('/leave_requests/submit', methods=['POST'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners'])
def submit_leave_request():
    """
    Submits a new leave request, optionally with a supporting document.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    start_date_str = request.form.get('start_date')
    end_date_str = request.form.get('end_date')
    reason = request.form.get('reason')
    document_file = request.files.get('document')

    if not start_date_str or not end_date_str or not reason:
        return jsonify({"msg": "Missing required fields: start_date, end_date, or reason."}), 400

    try:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid date format. Use YYYY-MM-DD."}), 400
    
    if start_date > end_date:
        return jsonify({"msg": "Start date cannot be after end date."}), 400

    doc_path = None
    if document_file and document_file.filename != '':
        try:
            filename = secure_filename(f"leave_request_{user.id}_{datetime.utcnow().timestamp()}_{document_file.filename}")
            file_stream = io.BytesIO(document_file.read())
            mimetype = mimetypes.guess_type(document_file.filename)[0] or 'application/octet-stream'

            # <--- NOW CALLS THE HELPER FROM UTILS ---
            drive_link = upload_file_to_drive(
                file_stream,
                filename,
                mimetype,
                parent_folder_id=current_app.config['GOOGLE_DRIVE_LEAVE_DOCS_FOLDER_ID']
            )
            # --- END CALL ---
            if drive_link:
                doc_path = drive_link
            else:
                return jsonify({"msg": "Failed to upload supporting document to Google Drive."}), 500
        except Exception as e:
            current_app.logger.error(f"Error handling document upload for leave request: {e}", exc_info=True)
            return jsonify({"msg": "Server error during document upload."}), 500


    new_request = LeaveRequest(
        user_id=user.id,
        start_date=start_date,
        end_date=end_date,
        reason=reason,
        document_path=doc_path,
        status='Pending'
    )
    db.session.add(new_request)

    try:
        db.session.commit()
        return jsonify({"msg": "Your leave request has been submitted for review."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting leave request: {e}", exc_info=True)
        return jsonify({"msg": "Failed to submit leave request due to server error."}), 500

@mobile_api_bp.route('/leave_requests/<int:req_id>/update_status', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def update_leave_request_status(req_id):
    """
    Allows managers/admins to approve or deny a leave request.
    """
    current_user_id = get_jwt_identity()
    manager_user = User.query.get(current_user_id)
    if not manager_user:
        return jsonify({"msg": "Manager user not found"}), 404

    leave_req = LeaveRequest.query.get(req_id)
    if not leave_req:
        return jsonify({"msg": "Leave request not found."}), 404
    
    if leave_req.user_id == manager_user.id:
        return jsonify({"msg": "You cannot approve or deny your own leave request."}), 403

    data = request.json
    status = data.get('status') # Expected: 'Approved' or 'Denied'

    if status not in ['Approved', 'Denied']:
        return jsonify({"msg": "Invalid status provided. Must be 'Approved' or 'Denied'."}), 400

    leave_req.status = status
    
    try:
        db.session.commit()
        return jsonify({"msg": f"Leave request for {leave_req.user.full_name} has been {status.lower()}."}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error updating leave request status: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update leave request status due to server error."}), 500

@mobile_api_bp.route('/leave_requests/<int:req_id>/document', methods=['GET'])
@jwt_required()
def view_leave_document(req_id):
    """
    Redirects to the Google Drive link for a leave request's supporting document.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    leave_req = LeaveRequest.query.get(req_id)
    if not leave_req:
        return jsonify({"msg": "Leave request not found."}), 404
    
    # Check permissions (requester or manager/admin)
    if not (leave_req.user_id == user.id or user.has_role('manager') or user.has_role('general_manager') or user.has_role('system_admin')):
        return jsonify({"msg": "Access Denied: You are not authorized to view this document."}), 403

    if leave_req.document_path:
        # For an API, we can either return the URL directly, or redirect.
        # Returning the URL is often cleaner for mobile apps, as they can decide to open in browser.
        return jsonify({"document_url": leave_req.document_path}), 200
    else:
        return jsonify({"msg": "No supporting document available for this request."}), 404

def _calculate_ingredient_usage_from_cocktails_sold_api(target_date):
    """
    Calculates the total quantity of each product used as ingredients for cocktails
    sold on a given target_date.
    Returns a dictionary: {product_id: total_quantity_used}
    """
    total_ingredient_usage = {}
    cocktails_sold_on_date = CocktailsSold.query.filter_by(date=target_date).all()

    if not cocktails_sold_on_date:
        return total_ingredient_usage

    for cocktail_sold in cocktails_sold_on_date:
        recipe = cocktail_sold.recipe
        if not recipe:
            current_app.logger.warning(f"CocktailsSold entry {cocktail_sold.id} refers to non-existent Recipe ID {cocktail_sold.recipe_id}. Skipping.")
            continue

        for recipe_ingredient in recipe.recipe_ingredients:
            product_id = recipe_ingredient.product_id
            quantity_used_per_product = recipe_ingredient.quantity * cocktail_sold.quantity_sold
            total_ingredient_usage.setdefault(product_id, 0.0)
            total_ingredient_usage[product_id] += quantity_used_per_product
    return total_ingredient_usage


@mobile_api_bp.route('/daily_summary_report', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'owners'])
def get_daily_summary_report():
    """
    Returns a daily summary of inventory movements and variances for a specific date.
    """
    report_date_str = request.args.get('date') # YYYY-MM-DD
    if not report_date_str:
        report_date = datetime.utcnow().date()
    else:
        try:
            report_date = datetime.strptime(report_date_str, '%Y-%m-%d').date()
        except ValueError:
            return jsonify({"msg": "Invalid date format for report date. Use YYYY-MM-DD."}), 400

    day_before_report_date = report_date - timedelta(days=1)

    products = Product.query.order_by(Product.type, Product.name).all()

    # --- Data Collection for the Report Date ---
    bod_counts = {
        b.product_id: b.amount
        for b in BeginningOfDay.query.filter_by(date=report_date).all()
    }
    deliveries_for_day = {
        d.product_id: d.quantity
        for d in Delivery.query.filter_by(delivery_date=report_date).all()
    }
    manual_sales_for_day = {
        s.product_id: s.quantity_sold
        for s in Sale.query.filter_by(date=report_date).all()
    }
    cocktail_usage_for_day = _calculate_ingredient_usage_from_cocktails_sold_api(report_date)

    eod_latest_count_objects = {} # {product_id: Count_object}
    all_counts_on_report_date = Count.query.filter(func.date(Count.timestamp) == report_date).all()
    for count in all_counts_on_report_date:
        product_id = count.product_id
        if product_id not in eod_latest_count_objects or count.timestamp > eod_latest_count_objects[product_id].timestamp:
            eod_latest_count_objects[product_id] = count

    summary_data = []
    for product in products:
        bod = bod_counts.get(product.id, 0.0)
        deliveries = deliveries_for_day.get(product.id, 0.0)
        manual_sales = manual_sales_for_day.get(product.id, 0.0)
        cocktail_usage = cocktail_usage_for_day.get(product.id, 0.0)

        expected_stock_available = bod + deliveries
        total_usage_for_day = manual_sales + cocktail_usage
        expected_eod = expected_stock_available - total_usage_for_day

        actual_eod = eod_latest_count_objects.get(product.id, {}).amount if eod_latest_count_objects.get(product.id) else None

        variance_val = None
        loss_value = None

        latest_count_obj = eod_latest_count_objects.get(product.id)
        if latest_count_obj and latest_count_obj.variance_amount is not None:
            variance_val = latest_count_obj.variance_amount
        elif actual_eod is not None:
            variance_val = actual_eod - expected_eod

        if variance_val is not None and product.unit_price is not None:
            loss_value = variance_val * product.unit_price

        summary_data.append({
            'product_id': product.id,
            'name': product.name,
            'unit': product.unit_of_measure,
            'bod': round(bod, 2),
            'deliveries': round(deliveries, 2),
            'manual_sales': round(manual_sales, 2),
            'cocktail_usage': round(cocktail_usage, 2),
            'total_usage_for_day': round(total_usage_for_day, 2),
            'expected_eod': round(max(0.0, expected_eod), 2),
            'actual_eod': round(actual_eod, 2) if actual_eod is not None else None,
            'variance': round(variance_val, 2) if variance_val is not None else None,
            'loss_value': round(loss_value, 2) if loss_value is not None else None
        })

    return jsonify(summary_data), 200

@mobile_api_bp.route('/inventory_log', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'owners'])
def get_inventory_log():
    """
    Returns a chronological log of all inventory movements within a date range.
    """
    start_date_str = request.args.get('start_date')
    end_date_str = request.args.get('end_date')

    if not start_date_str or not end_date_str:
        return jsonify({"msg": "Start date and end date are required (YYYY-MM-DD)."}), 400

    try:
        start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid date format. Use YYYY-MM-DD."}), 400

    all_activities = []

    # 1. BeginningOfDay records
    bod_entries = BeginningOfDay.query.filter(BeginningOfDay.date.between(start_date, end_date)).all()
    for bod in bod_entries:
        product = Product.query.get(bod.product_id) # Fetch product for details
        all_activities.append({
            'type': 'BOD',
            'timestamp': datetime.combine(bod.date, datetime.min.time()).isoformat(),
            'product_name': product.name,
            'product_unit': product.unit_of_measure,
            'quantity_change': bod.amount,
            'details': f"Calculated/Set Beginning of Day stock",
            'user': 'System',
            'location': 'N/A'
        })

    # 2. Counts (First and Corrections)
    count_entries = Count.query.filter(func.date(Count.timestamp).between(start_date, end_date)).all()
    for count in count_entries:
        product = Product.query.get(count.product_id)
        user = User.query.get(count.user_id)
        variance_display = ""
        if count.variance_amount is not None:
            variance_display = f" (Variance: {count.variance_amount:.2f})"
            explanation = VarianceExplanation.query.filter_by(count_id=count.id).first()
            if explanation:
                variance_display += f" - Reason: {explanation.reason}"
            # No "No Explanation" for mobile API, just omit if none

        expected_amount_display = f"{count.expected_amount:.2f}" if count.expected_amount is not None else "N/A"

        all_activities.append({
            'type': count.count_type,
            'timestamp': count.timestamp.isoformat(),
            'product_name': product.name,
            'product_unit': product.unit_of_measure,
            'quantity_change': count.amount, # Show counted amount for count entries
            'details': f"Counted {count.amount:.2f} {product.unit_of_measure}. Expected: {expected_amount_display}{variance_display}",
            'user': user.full_name,
            'location': count.location
        })

    # 3. Deliveries
    delivery_entries = Delivery.query.filter(Delivery.delivery_date.between(start_date, end_date)).all()
    for delivery in delivery_entries:
        product = Product.query.get(delivery.product_id)
        user = User.query.get(delivery.user_id)
        all_activities.append({
            'type': 'Delivery',
            'timestamp': delivery.timestamp.isoformat(),
            'product_name': product.name,
            'product_unit': product.unit_of_measure,
            'quantity_change': delivery.quantity, # Positive for incoming
            'details': f"Received {delivery.quantity:.2f} {product.unit_of_measure}. Comment: {delivery.comment or 'N/A'}",
            'user': user.full_name,
            'location': 'N/A'
        })

    # 4. Manual Sales
    sale_entries = Sale.query.filter(Sale.date.between(start_date, end_date)).all()
    for sale in sale_entries:
        product = Product.query.get(sale.product_id)
        all_activities.append({
            'type': 'Manual Sale',
            'timestamp': datetime.combine(sale.date, datetime.min.time()).isoformat(),
            'product_name': product.name,
            'product_unit': product.unit_of_measure,
            'quantity_change': -sale.quantity_sold, # Negative for outgoing
            'details': f"Sold {sale.quantity_sold:.2f} {product.unit_of_measure}",
            'user': 'System',
            'location': 'N/A'
        })

    # 5. Cocktails Sold (for ingredient usage)
    cocktails_sold_entries = CocktailsSold.query.filter(CocktailsSold.date.between(start_date, end_date)).all()
    for cs in cocktails_sold_entries:
        recipe = Recipe.query.get(cs.recipe_id)
        all_activities.append({
            'type': 'Cocktail Sale',
            'timestamp': datetime.combine(cs.date, datetime.min.time()).isoformat(),
            'product_name': recipe.name,
            'product_unit': 'cocktails',
            'quantity_change': -cs.quantity_sold,
            'details': f"Sold {cs.quantity_sold} of '{recipe.name}'. Ingredients deducted automatically.",
            'user': 'System',
            'location': 'N/A'
        })
        # For ingredient deductions, we could also log them separately
        for ri in recipe.recipe_ingredients:
            ingredient_deduction = ri.quantity * cs.quantity_sold
            all_activities.append({
                'type': 'Ingredient Deduction',
                'timestamp': datetime.combine(cs.date, datetime.min.time()).isoformat(),
                'product_name': ri.product.name,
                'product_unit': ri.product.unit_of_measure,
                'quantity_change': -ingredient_deduction,
                'details': f"Deducted for {cs.quantity_sold} of '{recipe.name}' sold",
                'user': 'System',
                'location': 'N/A'
            })


    # Sort by timestamp
    all_activities.sort(key=lambda x: x['timestamp'])

    return jsonify(all_activities), 200

@mobile_api_bp.route('/variance_report', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'owners'])
def get_variance_report():
    """
    Returns a detailed variance report for a specific date, including explanations.
    """
    report_date_str = request.args.get('date')
    if not report_date_str:
        report_date = datetime.utcnow().date()
    else:
        try:
            report_date = datetime.strptime(report_date_str, '%Y-%m-%d').date()
        except ValueError:
            return jsonify({"msg": "Invalid date format for report date. Use YYYY-MM-DD."}), 400

    all_counts_on_report_date = Count.query.filter(
        func.date(Count.timestamp) == report_date
    ).order_by(Count.product_id, Count.location, Count.timestamp).all()

    variance_report_data = {} # { (product_id, location_name): { ... data ... } }

    grouped_counts = {}
    for count in all_counts_on_report_date:
        key = (count.product_id, count.location)
        if key not in grouped_counts:
            grouped_counts[key] = []
        grouped_counts[key].append(count)

    for (product_id, location_name), counts_for_product_location in grouped_counts.items():
        first_count_entry = None
        correction_count_entry = None

        counts_for_product_location.sort(key=lambda c: c.timestamp)

        for c in counts_for_product_location:
            if c.count_type == 'First Count':
                first_count_entry = c
            elif c.count_type == 'Corrections Count':
                correction_count_entry = c

        final_count_entry = correction_count_entry if correction_count_entry else first_count_entry

        if not final_count_entry:
            continue

        current_location_obj = Location.query.filter_by(name=location_name).first()
    # --- END NEW ---

        has_significant_variance = (
            final_count_entry.variance_amount is not None and
            final_count_entry.variance_amount != 0
        )
        has_correction_difference = (
            correction_count_entry is not None and
            first_count_entry is not None and
            correction_count_entry.amount != first_count_entry.amount
        )

        if has_significant_variance or has_correction_difference:
            explanation = VarianceExplanation.query.filter_by(count_id=final_count_entry.id).first()
            variance_report_data[(product_id, location_name)] = {
                'location_id': current_location_obj.id if current_location_obj else None, # <--- USE current_location_obj here
                'location_name': location_name,
                'product_id': product_id,
                'product_name': final_count_entry.product.name,
                'product_unit': final_count_entry.product.unit_of_measure,
                'first_count_amount': round(first_count_entry.amount, 2) if first_count_entry else None,
                'first_count_by': first_count_entry.user.full_name if first_count_entry and first_count_entry.user else None,
                'correction_amount': round(correction_count_entry.amount, 2) if correction_count_entry else None,
                'correction_by': correction_count_entry.user.full_name if correction_count_entry and correction_count_entry.user else None,
                'expected_amount': round(final_count_entry.expected_amount, 2) if final_count_entry.expected_amount is not None else None,
                'variance_amount': round(final_count_entry.variance_amount, 2) if final_count_entry.variance_amount is not None else None,
                'count_id_for_explanation': final_count_entry.id,
                'explanation': explanation.reason if explanation else None,
                'explanation_by': explanation.user.full_name if explanation and explanation.user else None,
            }
    
    # Convert dictionary to list for jsonify, then sort
    sorted_variance_list = sorted(
        list(variance_report_data.values()),
        key=lambda x: (x['location_name'], x['product_name'])
    )

    return jsonify(sorted_variance_list), 200

@mobile_api_bp.route('/variance_history/<int:product_id>', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'owners'])
def get_variance_history_api(product_id):
    """
    Returns historical variance data for a specific product over the last 30 days.
    """
    product = Product.query.get(product_id)
    if not product:
        return jsonify({'msg': 'Product not found.'}), 404

    end_date = datetime.utcnow().date()
    start_date = end_date - timedelta(days=29) # Last 30 days

    labels = []
    data_points = []

    current_iter_date = start_date
    while current_iter_date <= end_date:
        labels.append(current_iter_date.strftime('%Y-%m-%d')) # YYYY-MM-DD for consistency

        bod_entry = BeginningOfDay.query.filter_by(product_id=product_id, date=current_iter_date).first()
        bod_amount = bod_entry.amount if bod_entry else 0.0

        deliveries_for_day = Delivery.query.filter_by(product_id=product_id, delivery_date=current_iter_date).all()
        total_deliveries = sum(d.quantity for d in deliveries_for_day)

        manual_sale = Sale.query.filter_by(product_id=product_id, date=current_iter_date).first()
        manual_sale_qty = manual_sale.quantity_sold if manual_sale else 0.0

        cocktail_usage_on_day_all_products = _calculate_ingredient_usage_from_cocktails_sold_api(current_iter_date)
        cocktail_usage_qty = cocktail_usage_on_day_all_products.get(product_id, 0.0)

        expected_eod = bod_amount + total_deliveries - manual_sale_qty - cocktail_usage_qty
        expected_eod = max(0.0, expected_eod)

        latest_count = Count.query.filter(
            Count.product_id == product_id,
            func.date(Count.timestamp) == current_iter_date
        ).order_by(Count.timestamp.desc()).first()

        daily_variance = None
        if latest_count and latest_count.variance_amount is not None:
            daily_variance = latest_count.variance_amount
        elif latest_count:
            daily_variance = latest_count.amount - expected_eod

        data_points.append(round(daily_variance, 2) if daily_variance is not None else None)

        current_iter_date += timedelta(days=1)

    return jsonify({'labels': labels, 'data': data_points}), 200

@mobile_api_bp.route('/variance_explanation/submit', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def submit_variance_explanation():
    """
    Submits or updates a variance explanation for a given Count ID.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    data = request.json
    count_id = data.get('count_id')
    reason = data.get('reason')

    if not count_id or not reason:
        return jsonify({"msg": "Missing required fields: count_id or reason."}), 400
    
    count_entry = Count.query.get(count_id)
    if not count_entry:
        return jsonify({"msg": "Count entry not found."}), 404

    # Check if an explanation already exists for this count
    existing_explanation = VarianceExplanation.query.filter_by(count_id=count_id).first()

    if existing_explanation:
        existing_explanation.reason = reason
        existing_explanation.timestamp = datetime.utcnow()
        existing_explanation.user_id = user.id
    else:
        new_explanation = VarianceExplanation(
            count_id=count_id,
            reason=reason,
            user_id=user.id
        )
        db.session.add(new_explanation)
    
    try:
        db.session.commit()
        return jsonify({"msg": "Variance explanation saved successfully."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting variance explanation: {e}", exc_info=True)
        return jsonify({"msg": "Failed to submit variance explanation due to server error."}), 500

@mobile_api_bp.route('/set_all_prices', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def set_all_prices_api():
    """
    Receives bulk updates for product unit prices.
    """
    current_user_id = get_jwt_identity()
    # User object not directly used here but implicitly by roles

    data = request.json
    product_prices_data = data.get('product_prices_data', []) # List of {product_id, unit_price}

    if not product_prices_data:
        return jsonify({"msg": "No product price data provided."}), 400

    errors = []
    updated_count = 0

    for item in product_prices_data:
        product_id = item.get('product_id')
        unit_price = item.get('unit_price') # Can be None for clearing

        if product_id is None:
            errors.append(f"Missing product_id in item: {item}")
            continue

        product_obj = Product.query.get(product_id)
        if not product_obj:
            errors.append(f"Product with ID {product_id} not found.")
            continue

        # Handle clearing price (setting to None)
        if unit_price is None or unit_price == '':
            parsed_price = None
        else:
            try:
                parsed_price = float(unit_price)
                if parsed_price < 0:
                    errors.append(f"Unit price for product_id {product_id} must be non-negative. Received: {unit_price}")
                    continue
            except ValueError:
                errors.append(f"Invalid unit price for product_id {product_id}. Received: {unit_price}")
                continue

        if product_obj.unit_price != parsed_price:
            product_obj.unit_price = parsed_price
            updated_count += 1
    
    if errors:
        db.session.rollback()
        return jsonify({"msg": "Errors occurred during submission.", "details": errors}), 400

    try:
        db.session.commit()
        return jsonify({"msg": f"Product prices updated successfully. Updated entries: {updated_count}."}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting product prices: {e}", exc_info=True)
        return jsonify({"msg": "Failed to submit product prices due to server error."}), 500

@mobile_api_bp.route('/products/add', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def add_product_api():
    """
    Adds a new product.
    """
    data = request.json
    name = data.get('name')
    product_type = data.get('type')
    unit_of_measure = data.get('unit_of_measure')
    unit_price = data.get('unit_price') # Can be null
    product_number = data.get('product_number') # Can be null

    if not name or not product_type or not unit_of_measure:
        return jsonify({"msg": "Missing required fields: name, type, or unit_of_measure."}), 400
    
    if Product.query.filter_by(name=name).first():
        return jsonify({"msg": f"A product named '{name}' already exists."}), 409 # Conflict

    try:
        parsed_price = float(unit_price) if unit_price is not None and unit_price != '' else None
        if parsed_price is not None and parsed_price < 0:
            return jsonify({"msg": "Unit price must be non-negative."}), 400
    except ValueError:
        return jsonify({"msg": "Invalid unit price format."}), 400

    new_product = Product(
        name=name,
        type=product_type,
        unit_of_measure=unit_of_measure,
        unit_price=parsed_price,
        product_number=product_number
    )
    db.session.add(new_product)

    try:
        db.session.commit()
        return jsonify({"msg": f"Product '{name}' added successfully.", "product_id": new_product.id}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error adding product: {e}", exc_info=True)
        return jsonify({"msg": "Failed to add product due to server error."}), 500

@mobile_api_bp.route('/products/<int:product_id>', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_product_details_api(product_id):
    """
    Returns details for a single product.
    """
    product = Product.query.get(product_id)
    if not product:
        return jsonify({"msg": "Product not found."}), 404
    
    return jsonify({
        "id": product.id,
        "name": product.name,
        "type": product.type,
        "unit_of_measure": product.unit_of_measure,
        "unit_price": product.unit_price,
        "product_number": product.product_number
    }), 200

@mobile_api_bp.route('/products/<int:product_id>', methods=['PUT'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def update_product_api(product_id):
    """
    Updates an existing product's details.
    """
    product = Product.query.get(product_id)
    if not product:
        return jsonify({"msg": "Product not found."}), 404
    
    data = request.json
    name = data.get('name')
    product_type = data.get('type')
    unit_of_measure = data.get('unit_of_measure')
    unit_price = data.get('unit_price') # Can be null
    product_number = data.get('product_number') # Can be null

    if not name or not product_type or not unit_of_measure:
        return jsonify({"msg": "Missing required fields: name, type, or unit_of_measure."}), 400
    
    # Check for duplicate name if name is changed
    if name != product.name and Product.query.filter_by(name=name).first():
        return jsonify({"msg": f"A product named '{name}' already exists."}), 409 # Conflict

    try:
        parsed_price = float(unit_price) if unit_price is not None and unit_price != '' else None
        if parsed_price is not None and parsed_price < 0:
            return jsonify({"msg": "Unit price must be non-negative."}), 400
    except ValueError:
        return jsonify({"msg": "Invalid unit price format."}), 400

    product.name = name
    product.type = product_type
    product.unit_of_measure = unit_of_measure
    product.unit_price = parsed_price
    product.product_number = product_number

    try:
        db.session.commit()
        return jsonify({"msg": f"Product '{product.name}' updated successfully."}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error updating product {product_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update product due to server error."}), 500

@mobile_api_bp.route('/products/<int:product_id>', methods=['DELETE'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def delete_product_api(product_id):
    """
    Deletes a product.
    """
    product = Product.query.get(product_id)
    if not product:
        return jsonify({"msg": "Product not found."}), 404
    
    db.session.delete(product)

    try:
        db.session.commit()
        return jsonify({"msg": f"Product '{product.name}' deleted successfully."}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error deleting product {product_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to delete product due to server error."}), 500

@mobile_api_bp.route('/locations/add', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def add_location_api():
    """
    Adds a new location.
    """
    data = request.json
    name = data.get('name')

    if not name:
        return jsonify({"msg": "Location name is required."}), 400
    
    if Location.query.filter_by(name=name).first():
        return jsonify({"msg": f"A location named '{name}' already exists."}), 409 # Conflict

    new_location = Location(name=name)
    db.session.add(new_location)

    try:
        db.session.commit()
        return jsonify({"msg": f"Location '{name}' added successfully.", "location_id": new_location.id}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error adding location: {e}", exc_info=True)
        return jsonify({"msg": "Failed to add location due to server error."}), 500

@mobile_api_bp.route('/locations/<int:location_id>', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_location_details_api(location_id):
    """
    Returns details for a single location, including its assigned products.
    """
    location = Location.query.get(location_id)
    if not location:
        return jsonify({"msg": "Location not found."}), 404
    
    assigned_products_data = []
    for product in location.products:
        assigned_products_data.append({
            "id": product.id,
            "name": product.name,
            "type": product.type,
            "unit_of_measure": product.unit_of_measure,
            "product_number": product.product_number
        })

    return jsonify({
        "id": location.id,
        "name": location.name,
        "assigned_products": assigned_products_data
    }), 200

@mobile_api_bp.route('/locations/<int:location_id>', methods=['PUT'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def update_location_api(location_id):
    """
    Updates an existing location's details.
    (Currently only name can be updated, product assignment is a separate endpoint).
    """
    location = Location.query.get(location_id)
    if not location:
        return jsonify({"msg": "Location not found."}), 404
    
    data = request.json
    name = data.get('name')

    if not name:
        return jsonify({"msg": "Location name is required."}), 400
    
    if name != location.name and Location.query.filter_by(name=name).first():
        return jsonify({"msg": f"A location named '{name}' already exists."}), 409 # Conflict

    location.name = name

    try:
        db.session.commit()
        return jsonify({"msg": f"Location '{location.name}' updated successfully."}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error updating location {location_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update location due to server error."}), 500

@mobile_api_bp.route('/locations/<int:location_id>', methods=['DELETE'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def delete_location_api(location_id):
    """
    Deletes a location.
    """
    location = Location.query.get(location_id)
    if not location:
        return jsonify({"msg": "Location not found."}), 404
    
    db.session.delete(location)

    try:
        db.session.commit()
        return jsonify({"msg": f"Location '{location.name}' deleted successfully."}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error deleting location {location_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to delete location due to server error."}), 500

@mobile_api_bp.route('/locations/<int:location_id>/assign_products', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def assign_products_to_location_api(location_id):
    """
    Assigns a list of products to a specific location.
    """
    location = Location.query.get(location_id)
    if not location:
        return jsonify({"msg": "Location not found."}), 404
    
    data = request.json
    assigned_product_ids = data.get('assigned_product_ids', []) # List of product IDs

    # Clear existing assignments
    location.products = []
    db.session.flush() # Commit changes to relationship table immediately

    # Add new assignments
    products_to_assign = Product.query.filter(Product.id.in_(assigned_product_ids)).all()
    location.products.extend(products_to_assign)

    try:
        db.session.commit()
        return jsonify({"msg": f"Products assigned to '{location.name}' successfully."}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error assigning products to location {location_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to assign products due to server error."}), 500

@mobile_api_bp.route('/schedules/availability_window', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin'])
def get_availability_window_status():
    """
    Returns the current status of the availability submission window for the next week.
    """
    current_today = datetime.now(timezone.utc).date() # <--- Use timezone.utc
    days_until_next_monday = (0 - current_today.weekday() + 7) % 7
    next_monday_date = current_today + timedelta(days=days_until_next_monday)

    submission_window_start_date = next_monday_date - timedelta(weeks=1) + timedelta(days=1)
    submission_window_start = datetime.combine(submission_window_start_date, time(10, 0, 0), tzinfo=timezone.utc) # <--- ADD tzinfo
    submission_window_end = datetime.combine(next_monday_date, time(12, 0, 0), tzinfo=timezone.utc) # <--- ADD tzinfo

    current_utc_time = datetime.now(timezone.utc) # <--- Use timezone.utc
    is_open = (current_utc_time >= submission_window_start and current_utc_time <= submission_window_end)

    return jsonify({
        "is_open": is_open,
        "start_time_utc": submission_window_start.isoformat(),
        "end_time_utc": submission_window_end.isoformat(),
        "next_week_start_date": next_monday_date.isoformat(),
    }), 200

@mobile_api_bp.route('/schedules/my_availability', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin'])
def get_my_availability():
    # ...
    week_offset = 1 # <--- Fixed to 1 for availability submission
    _, next_week_dates, _, _ = _build_week_dates_api(week_offset=week_offset) # Use the correct week_offset
    
    existing_submissions = ShiftSubmission.query.filter(
        ShiftSubmission.user_id == User.id,
        ShiftSubmission.shift_date.in_(next_week_dates)
    ).all()

    availability_data = {}
    for sub in existing_submissions:
        availability_data.setdefault(sub.shift_date.isoformat(), []).append(sub.shift_type)
    
    return jsonify({ # <--- MODIFIED: Return week_dates here
        "availability_data": availability_data,
        "week_dates": [d.isoformat() for d in next_week_dates]
    }), 200

@mobile_api_bp.route('/schedules/submit_availability', methods=['POST'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin'])
def submit_my_availability():
    """
    Submits or updates the current user's availability for the next scheduling week.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    # First, check availability window (server-side validation)
    current_today = datetime.utcnow().date()
    days_until_next_monday = (0 - current_today.weekday() + 7) % 7
    next_monday_date = current_today + timedelta(days=days_until_next_monday)
    submission_window_start_date = next_monday_date - timedelta(weeks=1) + timedelta(days=1)
    submission_window_start = datetime.combine(submission_window_start_date, time(10, 0, 0))
    submission_window_end = datetime.combine(next_monday_date, time(12, 0, 0))
    current_utc_time = datetime.utcnow()
    is_submission_window_open = (current_utc_time >= submission_window_start and current_utc_time <= submission_window_end)

    if not is_submission_window_open:
        return jsonify({"msg": "Availability submission window is currently closed."}), 403


    data = request.json
    submitted_shifts_raw = data.get('shifts', []) # List of strings like "2025-10-20_Day"

    _, next_week_dates, _, _ = _build_week_dates_api(week_offset=1) # Next week for submission

    processed_shifts = {} # {date_str: set_of_shift_types}
    for shift_str in submitted_shifts_raw:
        try:
            date_str, shift_type = shift_str.split('_')
            submitted_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            
            # Basic validation: ensure date is in the correct next week
            if submitted_date not in next_week_dates:
                 return jsonify({"msg": f"Submitted date {date_str} is outside the allowed submission week."}), 400

            # Ensure only standard types are submitted by staff for now
            if shift_type not in ['Day', 'Night', 'Double']: # Staff can select Double directly now
                return jsonify({"msg": f"Invalid shift type '{shift_type}' submitted."}), 400

            processed_shifts.setdefault(date_str, set()).add(shift_type)
        except ValueError:
            return jsonify({"msg": f"Invalid shift submission format: {shift_str}"}), 400

    final_shifts_to_store = []
    for date_str, types_for_day in processed_shifts.items():
        if 'Day' in types_for_day and 'Night' in types_for_day:
            final_shifts_to_store.append((date_str, 'Double')) # Consolidate if both Day and Night selected
        else:
            for shift_type in types_for_day:
                final_shifts_to_store.append((date_str, shift_type))
    
    try:
        # Delete existing submissions for this user for the next week
        ShiftSubmission.query.filter(
            ShiftSubmission.user_id == user.id,
            ShiftSubmission.shift_date.in_(next_week_dates)
        ).delete(synchronize_session=False)
        db.session.flush()

        # Add new submissions
        for date_str, shift_type in final_shifts_to_store:
            shift_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            submission = ShiftSubmission(user_id=user.id, shift_date=shift_date, shift_type=shift_type)
            db.session.add(submission)

        db.session.commit()
        return jsonify({"msg": "Your shift availability has been submitted successfully!"}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error submitting availability: {e}", exc_info=True)
        return jsonify({"msg": "Failed to submit availability due to server error."}), 500

@mobile_api_bp.route('/schedules/my_assigned_shifts', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners'])
def get_my_assigned_shifts():
    """
    Returns the current user's assigned shifts for the current week, with swap/volunteer status.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404
    
    # Week offset for navigating current/past/future weeks
    week_offset = request.args.get('week_offset', 0, type=int)

    start_of_week, week_dates, _, leave_dict = _build_week_dates_api(week_offset=week_offset)
    
    shifts_query = Schedule.query.filter(
        Schedule.shift_date.in_(week_dates),
        Schedule.user_id == user.id,
        Schedule.published == True # Only show published shifts
    ).order_by(Schedule.shift_date).all()

    # Consolidate shifts by day, similar to `schedule_by_day` in web app
    schedule_by_day_data = {}
    for day in week_dates:
        schedule_by_day_data[day.isoformat()] = []

    for shift in shifts_query:
        shift_data = {
            'id': shift.id,
            'assigned_shift': shift.assigned_shift,
            'shift_date': shift.shift_date.isoformat(),
            'start_time_str': shift.start_time_str,
            'end_time_str': shift.end_time_str,
            'is_on_leave': shift.shift_date.isoformat() in leave_dict.get(user.id, []), # Check if user is on leave for this day
            'swap_request_status': None, # 'Pending', 'Approved', 'Denied'
            'volunteered_cycle_status': None, # 'Open', 'PendingApproval', 'Approved', 'Cancelled'
            'requester_id': None, # For relinquished shifts, who relinquished it
            'relinquish_reason': None # For relinquished shifts
        }

        # Check for pending swap requests
        pending_swap = ShiftSwapRequest.query.filter_by(schedule_id=shift.id, status='Pending').first()
        if pending_swap:
            shift_data['swap_request_status'] = 'Pending'

        # Check for volunteered cycle
        volunteered_cycle = VolunteeredShift.query.filter_by(schedule_id=shift.id).first()
        if volunteered_cycle and (volunteered_cycle.status == 'Open' or volunteered_cycle.status == 'PendingApproval'):
            shift_data['volunteered_cycle_status'] = volunteered_cycle.status
            shift_data['requester_id'] = volunteered_cycle.requester_id
            shift_data['relinquish_reason'] = volunteered_cycle.relinquish_reason
        
        schedule_by_day_data[shift.shift_date.isoformat()].append(shift_data)
    
    user_primary_role_for_rules = 'manager' # Default for roles not explicitly defined in ROLE_SHIFT_DEFINITIONS
    if user.has_role('bartender'): user_primary_role_for_rules = 'bartender'
    elif user.has_role('waiter'): user_primary_role_for_rules = 'waiter'
    elif user.has_role('skullers'): user_primary_role_for_rules = 'skullers'
    elif user.has_role('general_manager'): user_primary_role_for_rules = 'general_manager'
    elif user.has_role('system_admin'): user_primary_role_for_rules = 'system_admin'
    elif user.has_role('scheduler'): user_primary_role_for_rules = 'scheduler'

    return jsonify({
        "week_start": start_of_week.isoformat(),
        "week_dates": [d.isoformat() for d in week_dates], # Just Tuesday-Sunday usually
        "schedule_by_day": schedule_by_day_data,
        "display_role_name_for_rules": user_primary_role_for_rules,
        "week_offset": week_offset
    }), 200

@mobile_api_bp.route('/schedules/shift_definitions', methods=['GET'])
@jwt_required()
def get_shift_definitions():
    """
    Returns the ROLE_SHIFT_DEFINITIONS and SCHEDULER_SHIFT_TYPES_GENERIC.
    """
    return jsonify({
        "role_shift_definitions": ROLE_SHIFT_DEFINITIONS,
        "scheduler_shift_types_generic": SCHEDULER_SHIFT_TYPES_GENERIC
    }), 200

@mobile_api_bp.route('/schedules/manage_swaps_data', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_manage_swaps_data():
    """
    Returns data for managing shift swap requests, including pending and history.
    """
    # Define week_dates, week_start, week_end for schedule lookups (same as web app)
    week_offset = request.args.get('week_offset', 0, type=int) # Allow week navigation
    week_start, week_dates, week_end, _ = _build_week_dates_api(week_offset=week_offset)

    # Fetch all pending swaps
    pending_swaps_raw = [
        s for s in ShiftSwapRequest.query.filter_by(status='Pending').order_by(ShiftSwapRequest.timestamp.desc()).all()
        if s.schedule is not None # Filter out swaps with missing schedules early
    ]

    # Fetch all potential cover staff (same as web app for filtering dropdowns)
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
    staff_schedules_lookup = {u.id: {d.isoformat(): [] for d in week_dates} for u in all_potential_cover_staff}
    for shift in all_staff_shifts_this_week:
        if shift.user_id in staff_schedules_lookup and shift.shift_date.isoformat() in staff_schedules_lookup[shift.user_id]:
            staff_schedules_lookup[shift.user_id][shift.shift_date.isoformat()].append(
                {'id': shift.id, 'assigned_shift': shift.assigned_shift, 'shift_date': shift.shift_date.isoformat()}
            )


    # Process each pending swap to attach its filtered staff options
    processed_pending_swaps = []
    for swap in pending_swaps_raw:
        requester_roles = swap.requester.role_names
        requested_shift_date_iso = swap.schedule.shift_date.isoformat()
        requested_shift_type = swap.schedule.assigned_shift

        filtered_staff_for_this_swap = []
        for potential_cover in all_potential_cover_staff:
            if potential_cover.id == swap.requester_id:
                continue

            potential_cover_roles = potential_cover.role_names
            has_matching_role = any(role in requester_roles for role in potential_cover_roles)
            if not has_matching_role:
                continue

            coverer_schedule_for_requested_day = staff_schedules_lookup.get(potential_cover.id, {}).get(requested_shift_date_iso, [])
            conflict = False

            if requested_shift_type == 'Double':
                if coverer_schedule_for_requested_day and len(coverer_schedule_for_requested_day) > 0:
                    conflict = True
            else:
                conflict = any(
                    s['assigned_shift'] == 'Double' or s['assigned_shift'] == requested_shift_type
                    for s in coverer_schedule_for_requested_day
                )

            if not conflict:
                filtered_staff_for_this_swap.append({
                    'id': potential_cover.id,
                    'full_name': potential_cover.full_name
                })

        processed_pending_swaps.append({
            'id': swap.id,
            'schedule_id': swap.schedule_id,
            'requester_id': swap.requester_id,
            'requester_full_name': swap.requester.full_name,
            'coverer_id': swap.coverer_id,
            'coverer_full_name': swap.coverer.full_name if swap.coverer else None,
            'assigned_shift': swap.schedule.assigned_shift,
            'shift_date': swap.schedule.shift_date.isoformat(),
            'status': swap.status,
            'timestamp': swap.timestamp.isoformat(),
            'eligible_covers': filtered_staff_for_this_swap
        })

    # Fetch all swaps (including approved/denied) for history display
    all_swaps_raw = ShiftSwapRequest.query.order_by(ShiftSwapRequest.timestamp.desc()).all()
    all_swaps_history = []
    for s in all_swaps_raw:
        if s.schedule is None: continue # Filter out swaps with missing schedules
        all_swaps_history.append({
            'id': s.id,
            'schedule_id': s.schedule_id,
            'shift_date': s.schedule.shift_date.isoformat(),
            'assigned_shift': s.schedule.assigned_shift,
            'requester_full_name': s.requester.full_name,
            'coverer_full_name': s.coverer.full_name if s.coverer else None,
            'status': s.status,
            'timestamp': s.timestamp.isoformat()
        })
    
    return jsonify({
        "week_offset": week_offset,
        "pending_swaps": processed_pending_swaps,
        "all_swaps_history": all_swaps_history
    }), 200

@mobile_api_bp.route('/schedules/update_swap_status/<int:swap_id>', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def update_swap_status_api(swap_id):
    """
    Updates the status of a shift swap request (approve/deny).
    """
    current_user_id = get_jwt_identity()
    manager_user = User.query.get(current_user_id)
    if not manager_user:
        return jsonify({"msg": "Manager user not found"}), 404

    swap_request = ShiftSwapRequest.query.get(swap_id)
    if not swap_request:
        return jsonify({"msg": "Shift swap request not found."}), 404
    
    if swap_request.schedule is None: # Safety check
        return jsonify({"msg": "Associated schedule for swap request is missing."}), 400

    if swap_request.requester_id == manager_user.id:
        return jsonify({"msg": "You cannot approve or deny your own shift swap request."}), 403

    data = request.json
    action = data.get('action') # 'Approve' or 'Deny'
    coverer_id = data.get('coverer_id', type=int) # Only relevant for Approve

    if action not in ['Approve', 'Deny']:
        return jsonify({"msg": "Invalid action provided. Must be 'Approve' or 'Deny'."}), 400

    schedule_item = swap_request.schedule
    requester = swap_request.requester

    notification_title = ""
    notification_message = ""
    flash_category = "info" # default

    if action == 'Deny':
        swap_request.status = 'Denied'
        notification_title = "Shift Swap Request Denied"
        notification_message = f"Your request to swap the {schedule_item.assigned_shift} shift on {schedule_item.shift_date.strftime('%a, %b %d')} has been denied."
        flash_category = "warning"
        log_activity(f"Denied shift swap request #{swap_request.id} for {requester.full_name}'s shift on {schedule_item.shift_date}.")

    elif action == 'Approve':
        if not coverer_id:
            return jsonify({"msg": "You must select a staff member to cover the shift to approve."}), 400

        coverer = User.query.get(coverer_id)
        if not coverer:
            return jsonify({"msg": "Selected cover staff not found."}), 400

        swap_request.status = 'Approved'
        swap_request.coverer_id = coverer.id
        schedule_item.user_id = coverer.id # Assign the shift to the coverer

        # --- Apply "Day + Night = Double" logic for the approved volunteer ---
        # Get approved_volunteer's *other* shifts for that day
        volunteers_other_shifts_that_day = Schedule.query.filter(
            Schedule.user_id == coverer.id,
            Schedule.shift_date == schedule_item.shift_date,
            Schedule.id != schedule_item.id # Exclude the current schedule_item being modified
        ).all()

        current_coverer_shifts_on_day = {s.assigned_shift for s in volunteers_other_shifts_that_day}
        current_coverer_shifts_on_day.add(schedule_item.assigned_shift) # Add the shift being assigned

        if 'Day' in current_coverer_shifts_on_day and 'Night' in current_coverer_shifts_on_day:
            schedule_item.assigned_shift = 'Double' # Consolidate
            # Delete conflicting individual shifts for the coverer if a Double is now formed
            Schedule.query.filter(
                Schedule.user_id == coverer.id,
                Schedule.shift_date == schedule_item.shift_date,
                Schedule.assigned_shift.in_(['Day', 'Night'])
            ).delete(synchronize_session=False)
            db.session.flush() # Ensure deletions are processed

        notification_title = "Shift Swap Request Approved"
        notification_message = (
            f"The {schedule_item.assigned_shift} shift on {schedule_item.shift_date.strftime('%a, %b %d')}, "
            f"originally by {requester.full_name}, is now assigned to {coverer.full_name}."
        )
        flash_category = "success"
        log_activity(f"Approved shift swap request #{swap_request.id}: {coverer.full_name} now covers {requester.full_name}'s shift on {schedule_item.shift_date}.")
    
    db.session.commit() # Commit all changes

    # Send general announcement for approval
    if action == 'Approve':
        general_announcement = Announcement(
            user_id=current_user_id, # Manager who approved
            title=notification_title,
            message=notification_message,
            category='Urgent'
        )
        db.session.add(general_announcement)
        db.session.commit() # Commit announcement

    # Send specific push notification to requester and coverer
    # Use the send_push_notification helper from utils.py
    if action == 'Approve' and coverer:
        send_push_notification(
            requester.id,
            "Shift Swap Approved!",
            f"Your request to swap the {schedule_item.assigned_shift} shift on {schedule_item.shift_date.strftime('%a, %b %d')} has been approved! It is now assigned to {coverer.full_name}.",
            data={"type": "shift_swap_approved", "shift_date": schedule_item.shift_date.isoformat(), "role": coverer.role_names[0] if coverer.roles else "staff"}
        )
        send_push_notification(
            coverer.id,
            "Shift Assigned!",
            f"You have been assigned the {schedule_item.assigned_shift} shift on {schedule_item.shift_date.strftime('%a, %b %d')} (originally by {requester.full_name}).",
            data={"type": "shift_assigned", "shift_date": schedule_item.shift_date.isoformat(), "role": coverer.role_names[0] if coverer.roles else "staff"}
        )
    elif action == 'Deny':
         send_push_notification(
            requester.id,
            "Shift Swap Denied",
            f"Your request to swap the {schedule_item.assigned_shift} shift on {schedule_item.shift_date.strftime('%a, %b %d')} has been denied by a manager.",
            data={"type": "shift_swap_denied", "shift_date": schedule_item.shift_date.isoformat(), "role": requester.role_names[0] if requester.roles else "staff"}
        )
    
    return jsonify({"msg": notification_message, "status": flash_category}), 200

@mobile_api_bp.route('/schedules/manage_volunteered_shifts_data', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_manage_volunteered_shifts_data():
    """
    Returns data for managing volunteered shifts, including open shifts and history.
    """
    week_offset = request.args.get('week_offset', 0, type=int) # Allow week navigation
    week_start, week_dates, week_end, _ = _build_week_dates_api(week_offset=week_offset)

    # Fetch all actionable volunteered shifts
    actionable_volunteered_shifts_raw = VolunteeredShift.query.filter(
        VolunteeredShift.status.in_(['Open', 'PendingApproval'])
    ).order_by(VolunteeredShift.timestamp.desc()).all()

    processed_actionable_shifts = []
    for v_shift in actionable_volunteered_shifts_raw:
        if v_shift.schedule is None: continue # Safety check

        requester_roles = v_shift.requester.role_names

        eligible_volunteers_for_dropdown = []
        for volunteer_user in v_shift.volunteers:
            volunteer_roles = volunteer_user.role_names

            has_matching_role = any(role in requester_roles for role in volunteer_roles)
            if has_matching_role:
                # Also check for schedule conflicts for the assigned shift date for this potential volunteer
                # This logic is duplicated from app.py and should ideally be a shared helper or part of the API.
                # Replicate the conflict check here for accuracy:
                conflict = False
                volunteer_schedule_on_shift_day = Schedule.query.filter(
                    Schedule.user_id == volunteer_user.id,
                    Schedule.shift_date == v_shift.schedule.shift_date,
                    Schedule.published == True # Check against published schedule
                ).all()

                requested_shift_type = v_shift.schedule.assigned_shift
                if requested_shift_type == 'Double': # If requested is Double, any existing shift conflicts
                    if volunteer_schedule_on_shift_day: conflict = True
                else: # For Day, Night, Open, Split Double, check for direct conflicts
                    if any(s.assigned_shift == 'Double' or s.assigned_shift == requested_shift_type for s in volunteer_schedule_on_shift_day):
                        conflict = True

                if not conflict:
                    eligible_volunteers_for_dropdown.append({
                        'id': volunteer_user.id,
                        'full_name': volunteer_user.full_name
                    })

        processed_actionable_shifts.append({
            'id': v_shift.id,
            'schedule_id': v_shift.schedule_id,
            'requester_id': v_shift.requester_id,
            'requester_full_name': v_shift.requester.full_name,
            'assigned_shift': v_shift.schedule.assigned_shift,
            'shift_date': v_shift.schedule.shift_date.isoformat(),
            'relinquish_reason': v_shift.relinquish_reason,
            'status': v_shift.status,
            'volunteers': [{
                'id': v.id,
                'full_name': v.full_name,
                'is_eligible': any(el['id'] == v.id for el in eligible_volunteers_for_dropdown) # Indicate eligibility
            } for v in v_shift.volunteers],
            'eligible_volunteers_for_dropdown': eligible_volunteers_for_dropdown # For manager's selection
        })

    # Fetch all volunteered shifts for history
    all_volunteered_shifts_history_raw = VolunteeredShift.query.order_by(VolunteeredShift.timestamp.desc()).all()
    all_volunteered_shifts_history = []
    for v_shift in all_volunteered_shifts_history_raw:
        if v_shift.schedule is None: continue # Safety check
        all_volunteered_shifts_history.append({
            'id': v_shift.id,
            'schedule_id': v_shift.schedule_id,
            'shift_date': v_shift.schedule.shift_date.isoformat(),
            'assigned_shift': v_shift.schedule.assigned_shift,
            'requester_full_name': v_shift.requester.full_name,
            'approved_volunteer_full_name': v_shift.approved_volunteer.full_name if v_shift.approved_volunteer else None,
            'status': v_shift.status,
            'timestamp': v_shift.timestamp.isoformat(),
            'volunteers_offered': [v.full_name for v in v_shift.volunteers] # List of names
        })

    return jsonify({
        "week_offset": week_offset,
        "actionable_volunteered_shifts": processed_actionable_shifts,
        "all_volunteered_shifts_history": all_volunteered_shifts_history
    }), 200

@mobile_api_bp.route('/schedules/update_volunteered_shift_status/<int:v_shift_id>', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def update_volunteered_shift_status_api(v_shift_id):
    """
    Updates the status of a volunteered shift (assign/cancel).
    """
    current_user_id = get_jwt_identity()
    manager_user = User.query.get(current_user_id)
    if not manager_user:
        return jsonify({"msg": "Manager user not found"}), 404

    v_shift = VolunteeredShift.query.get(v_shift_id)
    if not v_shift:
        return jsonify({"msg": "Volunteered shift not found."}), 404
    
    if v_shift.schedule is None: # Safety check
        return jsonify({"msg": "Associated schedule for volunteered shift is missing."}), 400

    data = request.json
    action = data.get('action') # 'Assign' or 'Cancel'
    approved_volunteer_id = data.get('approved_volunteer_id', type=int) # Only relevant for Assign

    if action not in ['Assign', 'Cancel']:
        return jsonify({"msg": "Invalid action provided. Must be 'Assign' or 'Cancel'."}), 400

    original_schedule_item = v_shift.schedule
    requester = v_shift.requester # The person who relinquished the shift

    notification_title = ""
    notification_message = ""
    flash_category = "info" # default
    
    shift_date_str = original_schedule_item.shift_date.strftime('%a, %b %d')

    if action == 'Cancel':
        v_shift.status = 'Cancelled'
        v_shift.approved_volunteer_id = None # Clear approved volunteer if cancelled
        notification_title = "Shift Volunteering Cancelled"
        notification_message = (
            f"The volunteering cycle for the {original_schedule_item.assigned_shift} shift on {shift_date_str}, "
            f"originally relinquished by {requester.full_name}, has been cancelled."
        )
        flash_category = "warning"
        log_activity(f"Cancelled volunteering cycle for shift ID {v_shift.schedule_id} (orig. by {requester.full_name}).")

        # Notify requester and any volunteers
        if requester.id != manager_user.id: # Don't notify manager if they are the requester
             send_push_notification(
                requester.id,
                "Volunteered Shift Cancelled",
                f"Your relinquished shift ({original_schedule_item.assigned_shift} on {shift_date_str}) has had its volunteering cycle cancelled.",
                data={"type": "volunteered_shift_cancelled", "shift_date": shift_date_str, "role": requester.role_names[0] if requester.roles else "staff"}
            )
        for volunteer in v_shift.volunteers:
            if volunteer.id != manager_user.id:
                send_push_notification(
                    volunteer.id,
                    "Volunteered Shift Cancelled",
                    f"The volunteering cycle for the shift you volunteered for ({original_schedule_item.assigned_shift} on {shift_date_str}) has been cancelled.",
                    data={"type": "volunteered_shift_cancelled", "shift_date": shift_date_str, "role": volunteer.role_names[0] if volunteer.roles else "staff"}
                )

    elif action == 'Assign':
        if not approved_volunteer_id:
            return jsonify({"msg": "You must select a volunteer to assign the shift."}), 400
        
        approved_volunteer = User.query.get(approved_volunteer_id)
        if not approved_volunteer:
            return jsonify({"msg": "Selected volunteer not found."}), 400

        v_shift.status = 'Approved'
        v_shift.approved_volunteer_id = approved_volunteer_id
        original_schedule_item.user_id = approved_volunteer.id # Assign the shift to the approved volunteer

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

        notification_title = "Shift Volunteering Approved"
        notification_message = (
            f"The {original_schedule_item.assigned_shift} shift on {shift_date_str}, "
            f"originally relinquished by {requester.full_name}, "
            f"has been assigned to {approved_volunteer.full_name}."
        )
        flash_category = "success"
        log_activity(f"Approved volunteer '{approved_volunteer.full_name}' for shift ID {v_shift.schedule_id} (orig. by {requester.full_name}).")
        
        # Notify requester and approved volunteer
        if requester.id != manager_user.id:
            send_push_notification(
                requester.id,
                "Relinquished Shift Assigned!",
                f"Your relinquished shift ({original_schedule_item.assigned_shift} on {shift_date_str}) has been assigned to {approved_volunteer.full_name}.",
                data={"type": "relinquished_shift_assigned", "shift_date": shift_date_str, "role": requester.role_names[0] if requester.roles else "staff"}
            )
        if approved_volunteer.id != manager_user.id:
            send_push_notification(
                approved_volunteer.id,
                "Shift Assigned!",
                f"You have been assigned the {original_schedule_item.assigned_shift} shift on {shift_date_str} (originally relinquished by {requester.full_name}).",
                data={"type": "shift_assigned", "shift_date": shift_date_str, "role": approved_volunteer.role_names[0] if approved_volunteer.roles else "staff"}
            )

    db.session.commit() # Commit all changes
    return jsonify({"msg": notification_message, "status": flash_category}), 200

@mobile_api_bp.route('/schedules/manage_required_staff_data/<string:role_name>', methods=['GET'])
@jwt_required()
@role_required_api(['scheduler', 'manager', 'general_manager', 'system_admin'])
def get_manage_required_staff_data(role_name):
    """
    Returns required staff data for a specific role and week.
    """
    week_offset = request.args.get('week_offset', 0, type=int)
    start_of_week, week_dates, end_of_week, _ = _build_week_dates_api(week_offset=week_offset)

    existing_minimums = {
        rs.shift_date.isoformat(): {'min_staff': rs.min_staff, 'max_staff': rs.max_staff}
        for rs in RequiredStaff.query.filter_by(role_name=role_name)
                                     .filter(RequiredStaff.shift_date.in_(week_dates))
                                     .all()
    }

    display_dates = [d.isoformat() for d in week_dates if d.weekday() != 0] # Tue-Sun

    return jsonify({
        "week_offset": week_offset,
        "role_name": role_name,
        "display_dates": display_dates,
        "existing_minimums": existing_minimums
    }), 200

@mobile_api_bp.route('/schedules/update_required_staff', methods=['POST'])
@jwt_required()
@role_required_api(['scheduler', 'manager', 'general_manager', 'system_admin'])
def update_required_staff_api():
    """
    Updates min/max staff requirements for a specific role and week.
    """
    data = request.json
    role_name = data.get('role_name')
    week_offset = data.get('week_offset', 0, type=int)
    requirements = data.get('requirements', []) # List of {date: string, min_staff: int, max_staff: int_or_null}

    if not role_name or not requirements:
        return jsonify({"msg": "Missing required data: role_name or requirements."}), 400
    
    start_of_week, week_dates, end_of_week, _ = _build_week_dates_api(week_offset=week_offset)

    try:
        for req_data in requirements:
            date_str = req_data.get('date')
            min_staff_value = req_data.get('min_staff', type=int)
            max_staff_value = req_data.get('max_staff') # Can be null or empty string

            if not date_str or min_staff_value is None: # max_staff can be null
                return jsonify({"msg": f"Invalid requirement data: {req_data}"}), 400

            shift_date = datetime.strptime(date_str, '%Y-%m-%d').date()

            if min_staff_value < 0:
                return jsonify({"msg": f"Min staff for {date_str} must be non-negative."}), 400
            
            parsed_max_staff = None
            if max_staff_value is not None and max_staff_value != '':
                try:
                    parsed_max_staff = int(max_staff_value)
                    if parsed_max_staff < 0:
                        return jsonify({"msg": f"Max staff for {date_str} must be non-negative."}), 400
                except ValueError:
                    return jsonify({"msg": f"Invalid max staff value for {date_str}."}), 400

            if parsed_max_staff is not None and parsed_max_staff < min_staff_value:
                return jsonify({"msg": f"Max staff for {date_str} cannot be less than min staff."}), 400


            required_staff_entry = RequiredStaff.query.filter_by(
                role_name=role_name,
                shift_date=shift_date
            ).first()

            if required_staff_entry:
                required_staff_entry.min_staff = min_staff_value
                required_staff_entry.max_staff = parsed_max_staff
            else:
                new_entry = RequiredStaff(
                    role_name=role_name,
                    shift_date=shift_date,
                    min_staff=min_staff_value,
                    max_staff=parsed_max_staff
                )
                db.session.add(new_entry)

        db.session.commit()
        log_activity(f"Updated staff requirements for {role_name.title()} for week offset {week_offset}.")
        return jsonify({"msg": f"Staff requirements for {role_name.title()} updated successfully.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error updating staff requirements: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update staff requirements due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/schedules/shifts_today_data', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners'])
def get_shifts_today_data():

    """
    Returns shifts scheduled for the current day, categorized by role.
    """
    today_date = datetime.utcnow().date()

    # Fetch all published shifts for today for all relevant users
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
    
    users_lookup = {user.id: user for user in User.query.all()} # For quick user object lookup

    for shift in all_shifts_today_raw:
        user = users_lookup.get(shift.user_id)
        if not user:
            continue

        user_roles_names = [r.name for r in user.roles]
        
        # Determine role for time display (take first relevant one from ROLE_SHIFT_DEFINITIONS)
        display_role_for_time = 'manager' # Fallback
        if 'bartender' in user_roles_names: display_role_for_time = 'bartender'
        elif 'waiter' in user_roles_names: display_role_for_time = 'waiter'
        elif 'skullers' in user_roles_names: display_role_for_time = 'skullers'
        elif any(r in ['manager', 'general_manager', 'system_admin'] for r in user_roles_names): display_role_for_time = 'manager'


        shift_info = {
            'user_id': user.id,
            'user_name': user.full_name,
            'roles': [r.replace('_', ' ').title() for r in user_roles_names], # Formatted roles
            'assigned_shift': shift.assigned_shift,
            'time_display': get_shift_time_display(
                display_role_for_time, # The determined role for definition lookup
                today_date.strftime('%A'), # Day name (e.g., 'Sunday')
                shift.assigned_shift,
                custom_start=shift.start_time_str,
                custom_end=shift.end_time_str
            )
        }

        # Categorize for response
        if any(role in ['manager', 'general_manager', 'system_admin'] for role in user_roles_names):
            shifts_by_role_categorized['Managers'].append(shift_info)
        if 'bartender' in user_roles_names:
            shifts_by_role_categorized['Bartenders'].append(shift_info)
        if 'waiter' in user_roles_names:
            shifts_by_role_categorized['Waiters'].append(shift_info)
        if 'skullers' in user_roles_names:
            shifts_by_role_categorized['Skullers'].append(shift_info)
        
    sorted_role_categories = ['Managers', 'Bartenders', 'Waiters', 'Skullers']

    return jsonify({
        "today_date": today_date.isoformat(),
        "shifts_by_role_categorized": shifts_by_role_categorized,
        "sorted_role_categories": sorted_role_categories
    }), 200

@mobile_api_bp.route('/schedules/consolidated_schedule/<string:view_type>', methods=['GET'])
@jwt_required()
@role_required_api(['bartender', 'waiter', 'skullers', 'manager', 'general_manager', 'system_admin', 'owners'])
def get_consolidated_schedule(view_type):
    """
    Returns the consolidated assigned schedules for a specific category of roles (BOH, FOH, Managers).
    """
    week_offset = request.args.get('week_offset', 0, type=int)
    current_user_id = get_jwt_identity() # Needed for leave requests

    start_of_week, week_dates, end_of_week, leave_dict = _build_week_dates_api(week_offset=week_offset)

    target_roles = []
    consolidated_label = ""
    display_role_name_for_rules = "" # To fetch the correct shift definitions

    # Replicate web app's view_type logic for role filtering
    if view_type == 'boh':
        target_roles = ['bartender', 'skullers']
        consolidated_label = "Back of House (BOH) Schedule"
        display_role_name_for_rules = 'bartender' # Use bartender rules for BOH section
    elif view_type == 'foh':
        target_roles = ['waiter']
        consolidated_label = "Front of House (FOH) Schedule"
        display_role_name_for_rules = 'waiter'
    elif view_type == 'managers':
        target_roles = ['manager', 'general_manager', 'system_admin'] # Include system_admin for managers view
        consolidated_label = "Managers Schedule"
        display_role_name_for_rules = 'manager'
    elif view_type == 'bartenders_only': # Added specific roles for clarity
        target_roles = ['bartender']
        consolidated_label = "Bartenders Only Schedule"
        display_role_name_for_rules = 'bartender'
    elif view_type == 'waiters_only':
        target_roles = ['waiter']
        consolidated_label = "Waiters Only Schedule"
        display_role_name_for_rules = 'waiter'
    elif view_type == 'skullers_only':
        target_roles = ['skullers']
        consolidated_label = "Skullers Only Schedule"
        display_role_name_for_rules = 'skullers'
    else:
        return jsonify({"msg": f"Invalid consolidated schedule view type: {view_type}"}), 400
    
    # Fetch users for the targeted roles
    users_in_category = User.query.join(User.roles).filter(
        Role.name.in_(target_roles),
        User.is_suspended == False # Exclude suspended users from schedule display
    ).order_by(User.full_name).all()
    user_ids_in_category = [u.id for u in users_in_category]


    # Fetch all published shifts for these users for the week
    all_shifts_for_category = Schedule.query.filter(
        Schedule.shift_date.in_(week_dates),
        Schedule.user_id.in_(user_ids_in_category),
        Schedule.published == True
    ).order_by(Schedule.user_id, Schedule.shift_date).all()

    # Organize shifts by user and then by day
    schedule_by_user_data = {} # {user_id: {date_iso: [ScheduleItem_serialized]}}
    for user_obj in users_in_category:
        schedule_by_user_data[user_obj.id] = {day.isoformat(): [] for day in week_dates}

    for shift in all_shifts_for_category:
        shift_data = {
            'id': shift.id,
            'assigned_shift': shift.assigned_shift,
            'shift_date': shift.shift_date.isoformat(),
            'start_time_str': shift.start_time_str,
            'end_time_str': shift.end_time_str,
            'is_on_leave': shift.shift_date.isoformat() in leave_dict.get(shift.user_id, []),
            'swap_request_status': None, # For future display of pending swaps
            'volunteered_cycle_status': None, # For future display of volunteered shifts
        }
        # You can add logic here to fetch swap/volunteered status for each shift if needed
        # For a manager's consolidated view, simply displaying the assigned shift is often enough.

        schedule_by_user_data[shift.user_id][shift.shift_date.isoformat()].append(shift_data)

    return jsonify({
        "week_offset": week_offset,
        "week_start": start_of_week.isoformat(),
        "week_dates": [d.isoformat() for d in week_dates], # All 7 days
        "display_dates": [d.isoformat() for d in week_dates if d.weekday() != 0], # Tue-Sun
        "consolidated_label": consolidated_label,
        "display_role_name_for_rules": display_role_name_for_rules,
        "users_in_category": [{
            'id': u.id,
            'full_name': u.full_name,
            'roles': u.role_names
        } for u in users_in_category],
        "schedule_by_user": schedule_by_user_data
    }), 200

@mobile_api_bp.route('/hr/warnings', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_all_warnings_api():
    """
    Returns a list of all warnings with filtering options.
    """
    # Filters from query parameters (similar to web app)
    filter_staff_id = request.args.get('staff_id', type=int)
    filter_manager_id = request.args.get('manager_id', type=int)
    filter_severity = request.args.get('severity')
    filter_status = request.args.get('status')

    warnings_query = Warning.query.order_by(Warning.date_issued.desc(), Warning.timestamp.desc())

    if filter_staff_id:
        warnings_query = warnings_query.filter_by(user_id=filter_staff_id)
    if filter_manager_id:
        warnings_query = warnings_query.filter_by(issued_by_id=filter_manager_id)
    if filter_severity and filter_severity != 'all':
        warnings_query = warnings_query.filter_by(severity=filter_severity)
    if filter_status and filter_status != 'all':
        warnings_query = warnings_query.filter_by(status=filter_status)

    all_warnings = warnings_query.all()

    warnings_data = []
    for warning in all_warnings:
        warnings_data.append({
            'id': warning.id,
            'user_id': warning.user_id,
            'user_full_name': warning.user.full_name,
            'issued_by_id': warning.issued_by_id,
            'issued_by_full_name': warning.issued_by.full_name,
            'date_issued': warning.date_issued.isoformat(),
            'reason': warning.reason,
            'severity': warning.severity,
            'status': warning.status,
            'notes': warning.notes,
            'resolution_date': warning.resolution_date.isoformat() if warning.resolution_date else None,
            'resolved_by_id': warning.resolved_by_id,
            'resolved_by_full_name': warning.resolved_by.full_name if warning.resolved_by else None,
            'timestamp': warning.timestamp.isoformat(),
        })
    
    return jsonify(warnings_data), 200

@mobile_api_bp.route('/hr/warnings/<int:warning_id>', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_warning_details_api(warning_id):
    """
    Returns details for a single warning.
    """
    warning = Warning.query.get(warning_id)
    if not warning:
        return jsonify({"msg": "Warning not found."}), 404
    
    return jsonify({
        'id': warning.id,
        'user_id': warning.user_id,
        'user_full_name': warning.user.full_name,
        'issued_by_id': warning.issued_by_id,
        'issued_by_full_name': warning.issued_by.full_name,
        'date_issued': warning.date_issued.isoformat(),
        'reason': warning.reason,
        'severity': warning.severity,
        'status': warning.status,
        'notes': warning.notes,
        'resolution_date': warning.resolution_date.isoformat() if warning.resolution_date else None,
        'resolved_by_id': warning.resolved_by_id,
        'resolved_by_full_name': warning.resolved_by.full_name if warning.resolved_by else None,
        'timestamp': warning.timestamp.isoformat(),
    }), 200

@mobile_api_bp.route('/hr/warnings/add', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def add_warning_api():
    """
    Adds a new warning.
    """
    data = request.json
    user_id = data.get('user_id', type=int)
    date_issued_str = data.get('date_issued')
    reason = data.get('reason')
    severity = data.get('severity', 'Minor')
    notes = data.get('notes')

    if not user_id or not date_issued_str or not reason or not severity:
        return jsonify({"msg": "Missing required fields: staff member, date issued, reason, or severity."}), 400

    try:
        date_issued = datetime.strptime(date_issued_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid date format for date issued. Use YYYY-MM-DD."}), 400

    warned_user = User.query.get(user_id)
    if not warned_user:
        return jsonify({"msg": "Staff member not found."}), 404
    
    if warned_user.id == get_jwt_identity(): # Cannot warn self
        return jsonify({"msg": "You cannot issue a warning to yourself."}), 403

    new_warning = Warning(
        user_id=user_id,
        issued_by_id=get_jwt_identity(), # Current manager/admin
        date_issued=date_issued,
        reason=reason,
        severity=severity,
        notes=notes,
        status='Active'
    )
    db.session.add(new_warning)

    try:
        db.session.commit()
        log_activity(f"Issued a '{severity}' warning to {warned_user.full_name} for '{reason[:50]}...'.")
        return jsonify({"msg": f"Warning issued to {warned_user.full_name} successfully!", "warning_id": new_warning.id}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error adding warning: {e}", exc_info=True)
        return jsonify({"msg": "Failed to add warning due to server error."}), 500

@mobile_api_bp.route('/hr/warnings/<int:warning_id>/edit', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def edit_warning_api(warning_id):
    """
    Updates an existing warning.
    """
    current_user_id = get_jwt_identity()
    current_user = User.query.get(current_user_id)
    if not current_user:
        return jsonify({"msg": "User not found"}), 404

    warning = Warning.query.get(warning_id)
    if not warning:
        return jsonify({"msg": "Warning not found."}), 404
    
    # Permission check: Only issuer, GM, or System Admin can edit
    if not (warning.issued_by_id == current_user_id or current_user.has_role('general_manager') or current_user.has_role('system_admin')):
        return jsonify({"msg": "Access Denied: You are not authorized to edit this warning."}), 403

    data = request.json
    user_id = data.get('user_id', type=int) # Allow changing recipient
    date_issued_str = data.get('date_issued')
    reason = data.get('reason')
    severity = data.get('severity', 'Minor')
    status = data.get('status', 'Active')
    notes = data.get('notes')

    if not user_id or not date_issued_str or not reason or not severity or not status:
        return jsonify({"msg": "Missing required fields for warning update."}), 400
    
    try:
        date_issued = datetime.strptime(date_issued_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid date format for date issued. Use YYYY-MM-DD."}), 400

    warned_user = User.query.get(user_id)
    if not warned_user:
        return jsonify({"msg": "Staff member not found."}), 404
    
    if warned_user.id == current_user_id: # Cannot warn self
        return jsonify({"msg": "You cannot update a warning for yourself."}), 403


    warning.user_id = user_id
    warning.date_issued = date_issued
    warning.reason = reason
    warning.severity = severity
    warning.notes = notes

    # Handle status change logic
    if status != warning.status:
        warning.status = status
        if status == 'Resolved':
            warning.resolution_date = datetime.utcnow().date()
            warning.resolved_by_id = current_user_id
        else:
            warning.resolution_date = None
            warning.resolved_by_id = None
    
    try:
        db.session.commit()
        log_activity(f"Edited warning ID {warning_id} for {warned_user.full_name}.")
        return jsonify({"msg": f"Warning for {warned_user.full_name} updated successfully!"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error updating warning {warning_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update warning due to server error."}), 500

@mobile_api_bp.route('/hr/warnings/<int:warning_id>/resolve', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def resolve_warning_api(warning_id):
    """
    Marks a warning as resolved.
    """
    current_user_id = get_jwt_identity()
    manager_user = User.query.get(current_user_id)
    if not manager_user:
        return jsonify({"msg": "Manager user not found"}), 404

    warning = Warning.query.get(warning_id)
    if not warning:
        return jsonify({"msg": "Warning not found."}), 404
    
    if warning.issued_by_id != current_user_id and not (manager_user.has_role('general_manager') or manager_user.has_role('system_admin')):
        return jsonify({"msg": "Access Denied: You are not authorized to resolve this this warning."}), 403

    warning.status = 'Resolved'
    warning.resolution_date = datetime.utcnow().date()
    warning.resolved_by_id = current_user_id

    try:
        db.session.commit()
        log_activity(f"Resolved warning ID {warning_id} for {warning.user.full_name}.")
        return jsonify({"msg": f"Warning for {warning.user.full_name} marked as resolved.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error resolving warning {warning_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to resolve warning due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/hr/warnings/<int:warning_id>/delete', methods=['POST'])
@jwt_required()
@role_required_api(['general_manager', 'system_admin']) # Only GMs/Admins can delete
def delete_warning_api(warning_id):
    """
    Deletes a warning.
    """
    current_user_id = get_jwt_identity()
    current_user = User.query.get(current_user_id)
    if not current_user:
        return jsonify({"msg": "User not found"}), 404
    
    # Permission check: Only GM or System Admin can delete
    if not (current_user.has_role('general_manager') or current_user.has_role('system_admin')):
        return jsonify({"msg": "Access Denied: You are not authorized to delete this warning."}), 403

    warning = Warning.query.get(warning_id)
    if not warning:
        return jsonify({"msg": "Warning not found."}), 404
    
    warned_user_full_name = warning.user.full_name # Get name before deleting

    db.session.delete(warning)

    try:
        db.session.commit()
        log_activity(f"Deleted warning ID {warning_id} for {warned_user_full_name}.")
        return jsonify({"msg": f"Warning for {warned_user_full_name} has been deleted.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error deleting warning {warning_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to delete warning due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/hr/staff_for_warnings', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_staff_for_warnings_api():
    """
    Returns a list of staff members (bartenders, waiters, skullers) for the warning dropdown.
    """
    staff_roles_allowed_to_warn = ['bartender', 'waiter', 'skullers']
    all_staff_users = User.query.join(User.roles).filter(
        Role.name.in_(staff_roles_allowed_to_warn),
        User.is_suspended == False
    ).order_by(User.full_name).all()

    staff_data = [{
        'id': user.id,
        'full_name': user.full_name,
        'username': user.username,
        'roles': user.role_names
    } for user in all_staff_users]

    return jsonify(staff_data), 200

@mobile_api_bp.route('/hr/managers_for_warnings', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_managers_for_warnings_api():
    """
    Returns a list of managers (who can issue/resolve warnings) for filter dropdowns.
    """
    manager_roles = ['manager', 'general_manager', 'system_admin']
    manager_users = User.query.join(User.roles).filter(
        Role.name.in_(manager_roles),
        User.is_suspended == False
    ).order_by(User.full_name).all()

    managers_data = [{
        'id': user.id,
        'full_name': user.full_name,
        'username': user.username
    } for user in manager_users]

    return jsonify(managers_data), 200

@mobile_api_bp.route('/bookings/all', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'hostess', 'owners'])
def get_all_bookings_api():
    """
    Returns all future and recent past bookings, optionally filtered by date.
    Auto-deletes very old past bookings (as per web app's `bookings` route).
    """
    today = datetime.utcnow().date()

    # Auto-delete past bookings (same as web app on page load)
    try:
        past_bookings_to_delete = Booking.query.filter(Booking.booking_date < today).delete()
        db.session.commit()
        if past_bookings_to_delete > 0:
            current_app.logger.info(f"API: Automatically deleted {past_bookings_to_delete} past bookings.")
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"API: Error automatically deleting past bookings: {e}")
        # Not flashing, just logging for API

    # Fetch future bookings
    future_bookings_query = Booking.query.filter(Booking.booking_date >= today).order_by(Booking.booking_date, Booking.booking_time)
    future_bookings_data = []
    for booking in future_bookings_query.all():
        future_bookings_data.append({
            'id': booking.id,
            'customer_name': booking.customer_name,
            'contact_info': booking.contact_info,
            'party_size': booking.party_size,
            'booking_date': booking.booking_date.isoformat(),
            'booking_time': booking.booking_time,
            'notes': booking.notes,
            'status': booking.status,
            'timestamp': booking.timestamp.isoformat(),
            'user_id': booking.user_id,
            'user_full_name': booking.user.full_name,
        })

    # Fetch recent past bookings (e.g., last 10)
    past_bookings_query = Booking.query.filter(Booking.booking_date < today).order_by(Booking.booking_date.desc()).limit(10)
    past_bookings_data = []
    for booking in past_bookings_query.all():
        past_bookings_data.append({
            'id': booking.id,
            'customer_name': booking.customer_name,
            'contact_info': booking.contact_info,
            'party_size': booking.party_size,
            'booking_date': booking.booking_date.isoformat(),
            'booking_time': booking.booking_time,
            'notes': booking.notes,
            'status': booking.status,
            'timestamp': booking.timestamp.isoformat(),
            'user_id': booking.user_id,
            'user_full_name': booking.user.full_name,
        })
    
    return jsonify({
        "future_bookings": future_bookings_data,
        "past_bookings": past_bookings_data,
    }), 200

@mobile_api_bp.route('/bookings/add', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'hostess', 'owners'])
def add_booking_api():
    """
    Adds a new booking.
    """
    data = request.json
    customer_name = data.get('customer_name')
    contact_info = data.get('contact_info')
    party_size_raw = data.get('party_size')
    booking_date_str = data.get('booking_date')
    booking_time = data.get('booking_time')
    notes = data.get('notes')

    if party_size_raw is None:
        return jsonify({"msg": "Party size is required."}), 400
    try:
        party_size = int(party_size_raw)
    except ValueError:
        return jsonify({"msg": "Invalid format for party size. Must be an integer."}), 400

    if not customer_name or not party_size or not booking_date_str or not booking_time:
        return jsonify({"msg": "Missing required booking fields: customer name, party size, booking date, or booking time."}), 400

    try:
        booking_date = datetime.strptime(booking_date_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid date format for booking date. Use YYYY-MM-DD."}), 400

    if party_size <= 0:
        return jsonify({"msg": "Party size must be a positive number."}), 400

    new_booking = Booking(
        customer_name=customer_name,
        contact_info=contact_info,
        party_size=party_size,
        booking_date=booking_date,
        booking_time=booking_time,
        notes=notes,
        user_id=get_jwt_identity(), # Manager/hostess who logged it
    )
    db.session.add(new_booking)

    try:
        db.session.commit()
        log_activity(f"Logged new booking for {customer_name} on {booking_date_str} at {booking_time}.")
        return jsonify({"msg": "Booking added successfully!", "booking_id": new_booking.id}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error adding booking: {e}", exc_info=True)
        return jsonify({"msg": "Failed to add booking due to server error."}), 500

@mobile_api_bp.route('/bookings/<int:booking_id>', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'hostess', 'owners'])
def get_booking_details_api(booking_id):
    """
    Returns details for a single booking.
    """
    booking = Booking.query.get(booking_id)
    if not booking:
        return jsonify({"msg": "Booking not found."}), 404
    
    return jsonify({
        'id': booking.id,
        'customer_name': booking.customer_name,
        'contact_info': booking.contact_info,
        'party_size': booking.party_size,
        'booking_date': booking.booking_date.isoformat(),
        'booking_time': booking.booking_time,
        'notes': booking.notes,
        'status': booking.status,
        'timestamp': booking.timestamp.isoformat(),
        'user_id': booking.user_id,
        'user_full_name': booking.user.full_name,
    }), 200

@mobile_api_bp.route('/bookings/<int:booking_id>/edit', methods=['POST']) # Using POST for edits (as per web app)
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'hostess', 'owners'])
def edit_booking_api(booking_id):
    """
    Updates an existing booking.
    """
    booking = Booking.query.get(booking_id)
    if not booking:
        return jsonify({"msg": "Booking not found."}), 404
    
    data = request.json
    customer_name = data.get('customer_name')
    contact_info = data.get('contact_info')
    party_size_raw = data.get('party_size')
    booking_date_str = data.get('booking_date')
    booking_time = data.get('booking_time')
    notes = data.get('notes')
    status = data.get('status')

    if party_size_raw is None:
        return jsonify({"msg": "Party size is required."}), 400
    try:
        party_size = int(party_size_raw)
    except ValueError:
        return jsonify({"msg": "Invalid format for party size. Must be an integer."}), 400

    if not customer_name or not party_size or not booking_date_str or not booking_time or not status:
        return jsonify({"msg": "Missing required booking fields for update."}), 400

    try:
        booking_date = datetime.strptime(booking_date_str, '%Y-%m-%d').date()
    except ValueError:
        return jsonify({"msg": "Invalid date format for booking date. Use YYYY-MM-DD."}), 400

    if party_size <= 0:
        return jsonify({"msg": "Party size must be a positive number."}), 400
    
    booking.customer_name = customer_name
    booking.contact_info = contact_info
    booking.party_size = party_size
    booking.booking_date = booking_date
    booking.booking_time = booking_time
    booking.notes = notes
    booking.status = status

    try:
        db.session.commit()
        log_activity(f"Edited booking ID {booking_id} for {booking.customer_name}.")
        return jsonify({"msg": f"Booking for {booking.customer_name} updated successfully!", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error updating booking {booking_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update booking due to server error."}), 500

@mobile_api_bp.route('/bookings/<int:booking_id>/delete', methods=['POST']) # Using POST for delete (as per web app)
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'hostess', 'owners'])
def delete_booking_api(booking_id):
    """
    Deletes a booking.
    """
    booking = Booking.query.get(booking_id)
    if not booking:
        return jsonify({"msg": "Booking not found."}), 404
    
    customer_name = booking.customer_name # Get name before deleting

    db.session.delete(booking)

    try:
        db.session.commit()
        log_activity(f"Deleted booking ID {booking_id} for {customer_name}.")
        return jsonify({"msg": f"Booking for {customer_name} deleted successfully!", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error deleting booking {booking_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to delete booking due to server error.", "status": "danger"}), 500
    """
    Deletes a booking.
    """
    booking = Booking.query.get(booking_id)
    if not booking:
        return jsonify({"msg": "Booking not found."}), 404
    
    db.session.delete(booking)

    try:
        db.session.commit()
        log_activity(f"Deleted booking ID {booking_id} for {booking.customer_name} via mobile API.")
        return jsonify({"msg": "Booking deleted successfully!"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error deleting booking {booking_id} via mobile API: {e}", exc_info=True)
        return jsonify({"msg": "Failed to delete booking due to server error."}), 500

@mobile_api_bp.route('/users/all', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_all_users_api():
    """
    Returns a list of all users with their roles and suspension status.
    Can be filtered by role.
    """
    filter_role_name = request.args.get('role')
    search_query = request.args.get('search')

    users_query = User.query.order_by(User.full_name.asc())

    if filter_role_name and filter_role_name != 'all':
        users_query = users_query.join(User.roles).filter(Role.name == filter_role_name)
    
    if search_query:
        search_term = f"%{search_query.lower()}%"
        users_query = users_query.filter(or_(
            db.func.lower(User.full_name).like(search_term),
            db.func.lower(User.username).like(search_term)
        ))

    all_users = users_query.all()

    users_data = []
    for user in all_users:
        users_data.append({
            'id': user.id,
            'username': user.username,
            'full_name': user.full_name,
            'email': user.email,
            'roles': user.role_names,
            'is_suspended': user.is_suspended,
            'suspension_end_date': user.suspension_end_date.isoformat() if user.suspension_end_date else None,
            'suspension_document_path': user.suspension_document_path,
            'password_reset_requested': user.password_reset_requested,
            'last_seen': user.last_seen.isoformat() if user.last_seen else None,
            'force_logout_requested': user.force_logout_requested,
        })
    
    return jsonify(users_data), 200

@mobile_api_bp.route('/users/roles/all', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_all_roles_api():
    """
    Returns a list of all available roles.
    """
    all_roles = Role.query.order_by(Role.name).all()
    roles_data = [{
        'id': role.id,
        'name': role.name,
    } for role in all_roles]
    return jsonify(roles_data), 200

@mobile_api_bp.route('/users/add', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def add_user_api():
    """
    Adds a new user.
    """
    bcrypt = current_app.extensions['flask_bcrypt'] # Get bcrypt instance
    current_user_id = get_jwt_identity()
    current_manager = User.query.get(current_user_id)
    if not current_manager:
        return jsonify({"msg": "Current user not found."}), 404

    data = request.json
    username = data.get('username')
    full_name = data.get('full_name')
    password = data.get('password')
    role_names = data.get('roles', []) # List of role names

    if not username or not full_name or not password or not role_names:
        return jsonify({"msg": "Missing required fields: username, full name, password, or roles."}), 400
    
    if User.query.filter_by(username=username).first():
        return jsonify({"msg": f"A user with username '{username}' already exists."}), 409 # Conflict

    # Permission check for role assignment (same as web app)
    if current_manager.has_role('manager') and not (current_manager.has_role('system_admin') or current_manager.has_role('general_manager')):
        allowed_roles_for_manager = {'bartender', 'waiter', 'skullers'}
        if not set(role_names).issubset(allowed_roles_for_manager):
            return jsonify({"msg": "Managers can only create Bartender, Waiter, and Skullers accounts."}), 403

    new_user = User(
        username=username,
        full_name=full_name,
        password=bcrypt.generate_password_hash(password).decode('utf-8')
    )
    db.session.add(new_user)
    db.session.flush() # Flush to get new_user.id before assigning roles

    roles = Role.query.filter(Role.name.in_(role_names)).all()
    new_user.roles = roles

    try:
        db.session.commit()
        log_activity(f"Created new user: '{full_name}' ({username}, {', '.join(role_names)}).")
        return jsonify({"msg": f"User '{full_name}' created successfully!", "user_id": new_user.id}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error adding user: {e}", exc_info=True)
        return jsonify({"msg": "Failed to add user due to server error."}), 500

@mobile_api_bp.route('/users/<int:user_id>', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def get_user_details_api(user_id):
    """
    Returns details for a single user for editing.
    """
    user_to_edit = User.query.get(user_id)
    if not user_to_edit:
        return jsonify({"msg": "User not found."}), 404
    
    # Check if current_user is an owner with limited view (only allowed to see basic info)
    # This logic from web app's edit_user:
    is_limited_view = current_user.has_role('owners') and not (current_user.has_role('system_admin') or current_user.has_role('general_manager'))
    
    return jsonify({
        'id': user_to_edit.id,
        'username': user_to_edit.username,
        'full_name': user_to_edit.full_name,
        'email': user_to_edit.email,
        'roles': user_to_edit.role_names,
        'is_suspended': user_to_edit.is_suspended,
        'suspension_end_date': user_to_edit.suspension_end_date.isoformat() if user_to_edit.suspension_end_date else None,
        'suspension_document_path': user_to_edit.suspension_document_path,
        'password_reset_requested': user_to_edit.password_reset_requested,
        'last_seen': user_to_edit.last_seen.isoformat() if user_to_edit.last_seen else None,
        'force_logout_requested': user_to_edit.force_logout_requested,
        'is_limited_view_for_current_user': is_limited_view # Tell frontend if current user has limited view
    }), 200

@mobile_api_bp.route('/users/<int:user_id>/edit_details', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def edit_user_details_api(user_id):
    """
    Updates a user's details (full name, username, password, roles).
    """
    bcrypt = current_app.extensions['flask_bcrypt']
    current_user_id = get_jwt_identity()
    current_manager = User.query.get(current_user_id)
    if not current_manager:
        return jsonify({"msg": "Current user not found."}), 404

    user_to_edit = User.query.get(user_id)
    if not user_to_edit:
        return jsonify({"msg": "User not found."}), 404
    
    # Safety checks (copied from web app)
    if user_id == 1: # Root admin
        return jsonify({'msg': 'The root administrator account cannot be edited.'}), 403
    if user_id == current_user_id and current_manager.has_role('owners') and not (current_manager.has_role('system_admin') or current_manager.has_role('general_manager')):
        return jsonify({'msg': 'You cannot update your own account with limited owner role.'}), 403
    if current_manager.has_role('owners') and not (current_manager.has_role('system_admin') or current_manager.has_role('general_manager')):
        return jsonify({'msg': 'This role has view-only access to user details.'}), 403


    data = request.json
    full_name = data.get('full_name')
    username = data.get('username')
    new_password = data.get('password') # Optional, if provided, update
    role_names = data.get('roles', []) # List of role names

    if not full_name or not username or not role_names:
        return jsonify({"msg": "Missing required fields: full name, username, or roles."}), 400

    # Check for duplicate username if changed
    if username != user_to_edit.username and User.query.filter_by(username=username).first():
        return jsonify({"msg": f"A user with username '{username}' already exists."}), 409

    user_to_edit.full_name = full_name
    user_to_edit.username = username

    # Only managers/GMs/Admins can change roles, not limited owners
    if not (current_manager.has_role('owners') and not (current_manager.has_role('system_admin') or current_manager.has_role('general_manager'))):
        roles = Role.query.filter(Role.name.in_(role_names)).all()
        user_to_edit.roles = roles # Update roles

    if new_password:
        user_to_edit.password = bcrypt.generate_password_hash(new_password).decode('utf-8')
        user_to_edit.password_reset_requested = False # Reset flag if password is set

    try:
        db.session.commit()
        log_activity(f"Edited user details for '{user_to_edit.full_name}'.")
        return jsonify({"msg": f"User '{user_to_edit.full_name}' updated successfully!", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error updating user {user_id} details: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update user details due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/users/<int:user_id>/suspend', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def suspend_user_api(user_id):
    """
    Suspends a user, sets suspension end date, and handles document.
    """
    current_user_id = get_jwt_identity()
    current_manager = User.query.get(current_user_id)
    if not current_manager:
        return jsonify({"msg": "Current user not found."}), 404

    user_to_suspend = User.query.get(user_id)
    if not user_to_suspend:
        return jsonify({"msg": "User not found."}), 404

    # Safety checks (copied from web app)
    if user_id == 1: # Root admin
        return jsonify({'msg': 'The root administrator account cannot be suspended.'}), 403
    if user_id == current_user_id: # Cannot suspend self
        return jsonify({'msg': 'You cannot suspend your own account.'}), 403


    data = request.json
    suspension_end_date_str = data.get('suspension_end_date') # Optional
    # suspension_document_file is handled separately (see edit_user route for logic)
    delete_suspension_document = data.get('delete_suspension_document', False, type=bool)

    if data.get('action') == 'suspend_user': # Explicit action to suspend, if not already
        user_to_suspend.is_suspended = True

    if suspension_end_date_str:
        try:
            user_to_suspend.suspension_end_date = datetime.strptime(suspension_end_date_str, '%Y-%m-%d').date()
        except ValueError:
            return jsonify({"msg": "Invalid date format for suspension end date. Use YYYY-MM-DD."}), 400
    else:
        user_to_suspend.suspension_end_date = None # Indefinite suspension

    if delete_suspension_document and user_to_suspend.suspension_document_path:
        user_to_suspend.suspension_document_path = None # Clear document link

    # --- Document Upload (If file is sent as multipart, not JSON for this endpoint) ---
    # For now, we assume document upload is a separate action or handled by the general 'edit_details'
    # For simplicity of this JSON endpoint, we only handle path if already there or cleared.
    # If a new document needs to be uploaded, a multipart form API or separate upload is needed.
    # The existing web app handles file upload via a form in edit_user.

    try:
        db.session.commit()
        log_activity(f"User '{user_to_suspend.full_name}' suspension details updated or user suspended.")
        return jsonify({"msg": f"User '{user_to_suspend.full_name}' suspension status and details updated.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error suspending user {user_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to update suspension due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/users/<int:user_id>/reinstate', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def reinstate_user_api(user_id):
    """
    Reinstates a suspended user.
    """
    current_user_id = get_jwt_identity()
    current_manager = User.query.get(current_user_id)
    if not current_manager:
        return jsonify({"msg": "Current user not found."}), 404

    user_to_reinstate = User.query.get(user_id)
    if not user_to_reinstate:
        return jsonify({"msg": "User not found."}), 404
    
    # Safety checks
    if user_id == 1:
        return jsonify({'msg': 'The root administrator account cannot be reinstated.'}), 403
    if user_id == current_user_id:
        return jsonify({'msg': 'You cannot reinstate your own account.'}), 403
    if not user_to_reinstate.is_suspended:
        return jsonify({'msg': 'User is not currently suspended.'}), 200 # Info, not error

    user_to_reinstate.is_suspended = False
    user_to_reinstate.suspension_end_date = None
    user_to_reinstate.suspension_document_path = None

    try:
        db.session.commit()
        log_activity(f"Reinstated user: '{user_to_reinstate.full_name}'.")
        return jsonify({"msg": f"User '{user_to_reinstate.full_name}' has been reinstated.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error reinstating user {user_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to reinstate user due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/users/<int:user_id>/delete', methods=['POST'])
@jwt_required()
@role_required_api(['system_admin']) # Only System Admins can delete users
def delete_user_api(user_id):
    """
    Deletes a user.
    """
    current_user_id = get_jwt_identity()
    current_manager = User.query.get(current_user_id)
    if not current_manager:
        return jsonify({"msg": "Current user not found."}), 404

    user_to_delete = User.query.get(user_id)
    if not user_to_delete:
        return jsonify({"msg": "User not found."}), 404
    
    # Safety checks
    if user_id == 1:
        return jsonify({'msg': 'The root administrator account cannot be deleted.'}), 403
    if user_id == current_user_id:
        return jsonify({'msg': 'You cannot delete your own account.'}), 403
    
    warned_user_full_name = user_to_delete.full_name # Get name before deleting (if not already loaded by relationship)

    db.session.delete(user_to_delete)

    try:
        db.session.commit()
        log_activity(f"Deleted user: '{warned_user_full_name}'.")
        return jsonify({"msg": f"User '{warned_user_full_name}' has been deleted.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error deleting user {user_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to delete user due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/users/active_users_data', methods=['GET'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin', 'owners'])
def get_active_users_data_api():
    """
    Returns a list of users active in the last 5 minutes.
    """
    five_minutes_ago = datetime.utcnow() - timedelta(minutes=5)
    active_users = User.query.filter(User.last_seen > five_minutes_ago).order_by(User.last_seen.desc()).all()

    active_users_data = []
    for user in active_users:
        active_users_data.append({
            'id': user.id,
            'full_name': user.full_name,
            'username': user.username,
            'roles': user.role_names,
            'last_seen': user.last_seen.isoformat() if user.last_seen else None,
            'force_logout_requested': user.force_logout_requested
        })
    return jsonify(active_users_data), 200

@mobile_api_bp.route('/users/<int:user_id>/force_logout', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def force_logout_api(user_id):
    """
    Sets a flag to force a user to log out on their next request.
    """
    current_user_id = get_jwt_identity()
    current_manager = User.query.get(current_user_id)
    if not current_manager:
        return jsonify({"msg": "Current user not found."}), 404

    user_to_logout = User.query.get(user_id)
    if not user_to_logout:
        return jsonify({"msg": "User not found."}), 404
    
    # Safety checks
    if user_id == 1:
        return jsonify({'msg': 'The root administrator account cannot be force logged out.'}), 403
    if user_id == current_user_id:
        return jsonify({'msg': 'You cannot force log out your own account.'}), 403
    
    # Role-based restriction for managers
    if current_manager.has_role('manager') and not (current_manager.has_role('system_admin') or current_manager.has_role('general_manager')):
        target_is_staff = user_to_logout.has_role('bartender') or user_to_logout.has_role('waiter') or user_to_logout.has_role('skullers')
        if not target_is_staff:
            return jsonify({'msg': 'Managers can only force logout Bartenders, Waiters, and Skullers.'}), 403

    user_to_logout.force_logout_requested = True

    try:
        db.session.commit()
        log_activity(f"Requested force logout for user: '{user_to_logout.full_name}'.")
        return jsonify({"msg": f"User '{user_to_logout.full_name}' will be logged out on their next action.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error forcing logout for user {user_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to force logout due to server error.", "status": "danger"}), 500

@mobile_api_bp.route('/announcements/all', methods=['GET'])
@jwt_required()
def get_announcements_api():
    """
    Returns a list of announcements visible to the current user, with role filtering.
    (This is the existing /announcements route for viewing).
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    user_roles_ids = [role.id for role in user.roles]

    announcements_for_display_query = Announcement.query.outerjoin(Announcement.target_roles) \
                                                          .filter(or_(
                                                              db.not_(Announcement.target_roles.any()),
                                                              Role.id.in_(user_roles_ids),
                                                              Announcement.user_id == user.id # User can always see their own announcements
                                                          )) \
                                                          .distinct() \
                                                          .order_by(Announcement.id.desc())

    all_announcements = announcements_for_display_query.all()

    announcements_data = []
    for announcement in all_announcements:
        announcements_data.append({
            'id': announcement.id,
            'user_id': announcement.user_id,
            'user_full_name': announcement.user.full_name,
            'title': announcement.title,
            'message': announcement.message,
            'category': announcement.category,
            'timestamp': announcement.timestamp.isoformat(),
            'action_link': announcement.action_link,
            'target_roles': [role.name for role in announcement.target_roles],
        })
    return jsonify(announcements_data), 200


@mobile_api_bp.route('/announcements/add', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin']) # Only these roles can add
def add_announcement_api():
    """
    Adds a new announcement.
    """
    current_user_id = get_jwt_identity()
    current_user = User.query.get(current_user_id)
    if not current_user:
        return jsonify({"msg": "User not found"}), 404

    data = request.json
    title = data.get('title')
    message = data.get('message')
    category = data.get('category', 'General')
    target_role_names = data.get('target_roles', []) # List of role names
    action_link_view = data.get('action_link_view') # e.g., 'personal', 'boh'

    if not title or not message:
        return jsonify({"msg": "Missing required fields: title or message."}), 400
    
    action_link_url = None
    if action_link_view and action_link_view != 'none':
        # Construct the full URL using the configured base URL
        base_web_url = current_app.config.get('FLASK_WEB_BASE_URL', 'http://localhost:5000') # Fallback if not set
        if action_link_view == 'personal':
            action_link_url = f"{base_web_url}/my_schedule?view=personal"
        elif action_link_view == 'boh':
            action_link_url = f"{base_web_url}/my_schedule?view=boh"
        elif action_link_view == 'foh':
            action_link_url = f"{base_web_url}/my_schedule?view=foh"
        elif action_link_view == 'managers':
            action_link_url = f"{base_web_url}/my_schedule?view=managers"
        elif action_link_view == 'bartenders_only':
            action_link_url = f"{base_web_url}/my_schedule?view=bartenders"
        elif action_link_view == 'waiters_only':
            action_link_url = f"{base_web_url}/my_schedule?view=waiters"
        elif action_link_view == 'skullers_only':
            action_link_url = f"{base_web_url}/my_schedule?view=skullers"
        # Add other cases as needed for specific scheduler views from your web app
        # If the view is scheduler, the endpoint in web app is different e.g. /scheduler/bartenders
        # For simplicity, let's keep it to my_schedule views for now for consistency
        if action_link_url:
            current_app.logger.info(f"Generated action link for announcement: {action_link_url}")

    new_announcement = Announcement(
        user_id=current_user_id,
        title=title,
        message=message,
        category=category,
        action_link=action_link_url # Store the generated URL
    )
    db.session.add(new_announcement)
    db.session.flush()

    if target_role_names:
        target_roles = Role.query.filter(Role.name.in_(target_role_names)).all()
        new_announcement.target_roles = target_roles

    try:
        db.session.commit()
        log_activity(f"Posted new announcement titled: '{title}' via mobile API.")
        return jsonify({"msg": "Announcement posted successfully!", "announcement_id": new_announcement.id}), 201
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error adding announcement: {e}", exc_info=True)
        return jsonify({"msg": "Failed to add announcement due to server error."}), 500


@mobile_api_bp.route('/announcements/<int:announcement_id>/delete', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def delete_announcement_api(announcement_id):
    """
    Deletes an announcement.
    """
    current_user_id = get_jwt_identity()
    current_user = User.query.get(current_user_id)
    if not current_user:
        return jsonify({"msg": "User not found"}), 404

    announcement = Announcement.query.get(announcement_id)
    if not announcement:
        return jsonify({"msg": "Announcement not found."}), 404
    
    # Permission check: Issuer, GM, or System Admin can delete
    if not (announcement.user_id == current_user_id or current_user.has_role('general_manager') or current_user.has_role('system_admin')):
        return jsonify({"msg": "Access Denied: You are not authorized to delete this announcement."}), 403

    title_deleted = announcement.title # Get title before deleting

    db.session.delete(announcement)

    try:
        db.session.commit()
        log_activity(f"Deleted announcement titled: '{title_deleted}' via mobile API.")
        return jsonify({"msg": f"Announcement '{title_deleted}' deleted successfully!", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error deleting announcement {announcement_id}: {e}", exc_info=True)
        return jsonify({"msg": "Failed to delete announcement due to server error.", "status": "danger"}), 500


@mobile_api_bp.route('/announcements/clear_all', methods=['POST'])
@jwt_required()
@role_required_api(['manager', 'general_manager', 'system_admin'])
def clear_all_announcements_api():
    """
    Clears all announcements.
    """
    current_user_id = get_jwt_identity()
    current_user = User.query.get(current_user_id)
    if not current_user:
        return jsonify({"msg": "User not found"}), 404
    
    # Permission check: Manager, GM, or System Admin can clear
    if not (current_user.has_role('manager') or current_user.has_role('general_manager') or current_user.has_role('system_admin')):
        return jsonify({"msg": "Access Denied: You are not authorized to clear all announcements."}), 403

    try:
        num_deleted = Announcement.query.delete()
        db.session.commit()
        log_activity(f"Cleared all ({num_deleted}) announcements via mobile API.")
        return jsonify({"msg": f"All {num_deleted} announcements have been cleared.", "status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"Error clearing all announcements: {e}", exc_info=True)
        return jsonify({"msg": "Failed to clear all announcements due to server error.", "status": "danger"}), 500


@mobile_api_bp.route('/hr/user_manual_content', methods=['GET'])
@jwt_required()
def get_user_manual_content_api():
    """
    Returns user manual content filtered by current user's roles.
    """
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

    user_roles = user.role_names
    
    # Replicate filtering logic from app.py
    filtered_content = {}
    from ..app import MANUAL_CONTENT # Import the global MANUAL_CONTENT dict
    for title, data in MANUAL_CONTENT.items():
        if any(role_name in data['roles'] for role_name in user_roles):
            filtered_content[title] = {
                'content': data['content'],
                'roles': data['roles'] # Not strictly needed for UI, but included for consistency
            }
    
    return jsonify(filtered_content), 200
    current_user_id = get_jwt_identity()
    user = User.query.get(current_user_id)
    if not user:
        return jsonify({"msg": "User not found"}), 404

