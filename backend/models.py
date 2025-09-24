from datetime import date, datetime, timedelta, time
from flask_sqlalchemy import SQLAlchemy
from flask_login import UserMixin
from sqlalchemy import distinct, func, or_

db = SQLAlchemy()

# ==============================================================================
# Database Models
# ==============================================================================

class Warning(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False) # Staff member receiving the warning
    issued_by_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False) # Manager who issued the warning
    date_issued = db.Column(db.Date, nullable=False, default=datetime.utcnow().date)
    reason = db.Column(db.Text, nullable=False)
    severity = db.Column(db.String(50), nullable=False, default='Minor') # e.g., 'Minor', 'Major', 'Critical'
    status = db.Column(db.String(50), nullable=False, default='Active') # e.g., 'Active', 'Resolved', 'Expired'
    notes = db.Column(db.Text, nullable=True) # Internal manager notes
    resolution_date = db.Column(db.Date, nullable=True)
    resolved_by_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True) # Manager who resolved it
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow) # When the warning was created

    # Relationships
    user = db.relationship('User', foreign_keys=[user_id], backref=db.backref('warnings_received', lazy=True))
    issued_by = db.relationship('User', foreign_keys=[issued_by_id], backref=db.backref('warnings_issued', lazy=True))
    resolved_by = db.relationship('User', foreign_keys=[resolved_by_id], backref=db.backref('warnings_resolved', lazy=True))

    __table_args__ = {'extend_existing': True}

class EndOfDayReport(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    report_date = db.Column(db.Date, nullable=False, default=datetime.utcnow().date, unique=True) # One report per day
    manager_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False) # Manager who submitted the report

    # Operational Checks
    gas_ordered = db.Column(db.Boolean, nullable=True) # Yes/No
    garnish_ordered = db.Column(db.Boolean, nullable=True) # Yes/No
    maintenance_issues = db.Column(db.Text, nullable=True)
    staff_pitched_absences = db.Column(db.Text, nullable=True)
    staff_deductions = db.Column(db.Text, nullable=True)
    stock_borrowed_lent = db.Column(db.Text, nullable=True) # Will store notes or links to announcements
    customer_complaints = db.Column(db.Text, nullable=True)
    customer_complaint_contact_no = db.Column(db.Text, nullable=True) # Sub-line: Where possible, collect the customers' details and invite them back

    # Closing Checks
    shop_phone_on_charge = db.Column(db.Boolean, nullable=True) # Yes/No
    tv_boxes_locked = db.Column(db.Boolean, nullable=True) # Yes/No
    all_equipment_switched_off = db.Column(db.Boolean, nullable=True) # Yes/No

    # Financials
    credit_card_machines_banked = db.Column(db.Boolean, nullable=True) # Yes/No
    card_machines_on_charge = db.Column(db.Boolean, nullable=True) # Yes/No
    declare_card_sales_pos360 = db.Column(db.String(100), nullable=True) # Text field for the declared amount
    actual_card_figure_banked = db.Column(db.String(100), nullable=True) # Text field for actual amount
    declare_cash_sales_pos360 = db.Column(db.String(100), nullable=True) # Text field for declared amount
    actual_cash_on_hand = db.Column(db.String(100), nullable=True) # Text field for actual amount
    accounts_amount = db.Column(db.Text, nullable=True) # Multi-line text for (per account)
    stock_wastage_value = db.Column(db.Text, nullable=True) # Notes down any stock wastage and the value thereof

    # Daily Performance & Security
    pos360_day_end_complete = db.Column(db.Boolean, nullable=True) # Yes/No
    todays_target = db.Column(db.String(255), nullable=True) # Text input field
    turnover_ex_tips = db.Column(db.String(255), nullable=True) # Text input field
    security_walk_through_clean_shop = db.Column(db.Boolean, nullable=True) # Yes/No
    other_issues_experienced = db.Column(db.Text, nullable=True)

    # Email Copy Option
    email_copy_address = db.Column(db.String(255), nullable=True) # Open field for email address

    # Relationships
    manager = db.relationship('User', backref=db.backref('eod_reports', lazy=True))
    images = db.relationship('EndOfDayReportImage', backref='eod_report', lazy=True, cascade="all, delete-orphan")

    __table_args__ = {'extend_existing': True}

class EndOfDayReportImage(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    eod_report_id = db.Column(db.Integer, db.ForeignKey('end_of_day_report.id'), nullable=False)
    image_url = db.Column(db.String(500), nullable=False) # Google Drive webViewLink
    filename = db.Column(db.String(255), nullable=True) # Original filename for reference

class RecountRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.id'), nullable=True)
    location_id = db.Column(db.Integer, db.ForeignKey('location.id'), nullable=True)

    
    __table_args__ = (db.CheckConstraint('product_id IS NOT NULL OR location_id IS NOT NULL', name='product_or_location_required'),)

    requested_by_user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    request_date = db.Column(db.Date, nullable=False, default=datetime.utcnow().date)
    status = db.Column(db.String(20), nullable=False, default='Pending') 
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    # Relationships for convenience
    product = db.relationship('Product', backref=db.backref('recount_requests', lazy=True))
    location = db.relationship('Location', backref=db.backref('recount_requests', lazy=True))
    requested_by = db.relationship('User', backref=db.backref('initiated_recount_requests', lazy=True))

class Booking(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    customer_name = db.Column(db.String(100), nullable=False)
    contact_info = db.Column(db.String(100), nullable=True)
    party_size = db.Column(db.Integer, nullable=False)
    booking_date = db.Column(db.Date, nullable=False)
    booking_time = db.Column(db.String(50), nullable=False) 
    notes = db.Column(db.Text, nullable=True)
    status = db.Column(db.String(20), nullable=False, default='Pending') 
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False) 

    user = db.relationship('User', backref=db.backref('logged_bookings', lazy=True))

def _build_week_dates():
    today = datetime.utcnow().date()
    days_since_monday = today.weekday()
    start_of_week = today - timedelta(days=days_since_monday)
    week_dates = [start_of_week + timedelta(days=i) for i in range(7)]
    end_of_week = week_dates[-1]

    leave_requests_this_week = LeaveRequest.query.filter(
        LeaveRequest.status == 'Approved',
        LeaveRequest.start_date <= end_of_week,
        LeaveRequest.end_date >= start_of_week
    ).all()
    leave_dict = {}
    for req in leave_requests_this_week:
        for d in week_dates:
            if req.start_date <= d <= req.end_date:
                leave_dict.setdefault(req.user_id, set()).add(d)

    return start_of_week, week_dates, end_of_week, leave_dict

class VarianceExplanation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    count_id = db.Column(db.Integer, db.ForeignKey('count.id'), nullable=False, unique=True)
    reason = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)

    count = db.relationship('Count', backref=db.backref('variance_explanation', uselist=False, cascade="all, delete-orphan", lazy=True))
    user = db.relationship('User', backref=db.backref('variance_explanations', lazy=True))
    __table_args__ = {'extend_existing': True}

class Delivery(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.id'), nullable=False)
    quantity = db.Column(db.Float, nullable=False)
    delivery_date = db.Column(db.Date, nullable=False, default=datetime.utcnow().date)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    comment = db.Column(db.Text, nullable=True)
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    product = db.relationship('Product', backref=db.backref('deliveries', lazy=True))
    user = db.relationship('User', backref=db.backref('delivery_logs', lazy=True))

class CocktailsSold(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    recipe_id = db.Column(db.Integer, db.ForeignKey('recipe.id'), nullable=False)
    quantity_sold = db.Column(db.Integer, nullable=False, default=0)
    date = db.Column(db.Date, nullable=False, default=datetime.utcnow().date)

    recipe = db.relationship('Recipe', backref=db.backref('cocktails_sold_entries', lazy=True))

    __table_args__ = (db.UniqueConstraint('recipe_id', 'date', name='_recipe_date_uc'),)

class RequiredStaff(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    role_name = db.Column(db.String(50), nullable=False)
    shift_date = db.Column(db.Date, nullable=False)
    min_staff = db.Column(db.Integer, nullable=False, default=1)
    max_staff = db.Column(db.Integer, nullable=True)

    __table_args__ = (db.UniqueConstraint('role_name', 'shift_date', name='_role_date_uc'),)
    __table_args__ = (db.UniqueConstraint('role_name', 'shift_date', name='_role_date_uc'), {'extend_existing': True})

product_location = db.Table('product_location',
    db.Column('product_id', db.Integer, db.ForeignKey('product.id'), primary_key=True),
    db.Column('location_id', db.Integer, db.ForeignKey('location.id'), primary_key=True)
)
announcement_view = db.Table('announcement_view',
    db.Column('user_id', db.Integer, db.ForeignKey('user.id'), primary_key=True),
    db.Column('announcement_id', db.Integer, db.ForeignKey('announcement.id'), primary_key=True)
)
user_roles = db.Table('user_roles',
    db.Column('user_id', db.Integer, db.ForeignKey('user.id'), primary_key=True),
    db.Column('role_id', db.Integer, db.ForeignKey('role.id'), primary_key=True)
)

announcement_roles = db.Table('announcement_roles',
    db.Column('announcement_id', db.Integer, db.ForeignKey('announcement.id'), primary_key=True),
    db.Column('role_id', db.Integer, db.ForeignKey('role.id'), primary_key=True)
)

class Role(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)

class User(db.Model, UserMixin):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(20), unique=True, nullable=False)
    full_name = db.Column(db.String(100), nullable=False)
    password = db.Column(db.String(60), nullable=False)
    password_reset_requested = db.Column(db.Boolean, nullable=False, default=False)
    last_seen = db.Column(db.DateTime, default=datetime.utcnow)
    force_logout_requested = db.Column(db.Boolean, default=False)
    is_suspended = db.Column(db.Boolean, default=False, nullable=False)
    suspension_end_date = db.Column(db.Date, nullable=True)
    suspension_document_path = db.Column(db.String(255), nullable=True)
    email = db.Column(db.String(255), nullable=True)
    roles = db.relationship('Role', secondary=user_roles, backref=db.backref('users', lazy='dynamic'))
    counts = db.relationship('Count', backref='user', lazy=True)
    announcements = db.relationship('Announcement', backref='user', lazy=True)
    seen_announcements = db.relationship('Announcement', secondary=announcement_view, back_populates='viewers', lazy='dynamic')

    @property
    def role_names(self):
        return [role.name for role in self.roles]

    def has_role(self, role_name):
        return role_name in self.role_names

class Location(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(50), unique=True, nullable=False)
    products = db.relationship('Product', secondary=product_location, back_populates='locations', lazy='dynamic')

class Product(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    type = db.Column(db.String(50), nullable=False)
    unit_of_measure = db.Column(db.String(10), nullable=False)
    unit_price = db.Column(db.Float, nullable=True)
    product_number = db.Column(db.String(50))
    counts = db.relationship('Count', backref='product', lazy=True, cascade="all, delete-orphan")
    locations = db.relationship('Location', secondary=product_location, back_populates='products', lazy='dynamic')

class Announcement(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    title = db.Column(db.String(100), nullable=False)
    message = db.Column(db.Text, nullable=False)
    category = db.Column(db.String(50), nullable=False, default='General')
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    viewers = db.relationship('User', secondary=announcement_view, back_populates='seen_announcements', lazy='dynamic')
    target_roles = db.relationship('Role', secondary=announcement_roles, backref=db.backref('targeted_announcements', lazy='dynamic'))

    action_link = db.Column(db.String(255), nullable=True) 

class Count(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.id'), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    location = db.Column(db.String(50), nullable=False)
    count_type = db.Column(db.String(20), nullable=False)
    amount = db.Column(db.Float, nullable=False)
    comment = db.Column(db.Text, nullable=True)
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    expected_amount = db.Column(db.Float, nullable=True) 
    variance_amount = db.Column(db.Float, nullable=True)

class BeginningOfDay(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.id'), nullable=False)
    amount = db.Column(db.Float, nullable=False)
    date = db.Column(db.Date, nullable=False, default=datetime.utcnow().date)
    __table_args__ = (db.UniqueConstraint('product_id', 'date', name='_product_date_uc'),)
    product = db.relationship('Product', backref=db.backref('beginning_of_day_entries', lazy=True))

class Sale(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, db.ForeignKey('product.id'), nullable=False)
    quantity_sold = db.Column(db.Float, nullable=False)
    date = db.Column(db.Date, nullable=False, default=datetime.utcnow().date)
    product = db.relationship('Product', backref=db.backref('sale_entries', lazy=True))

class ActivityLog(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    action = db.Column(db.String(255), nullable=False)
    user = db.relationship('User', backref='activity_logs')

class Recipe(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    instructions = db.Column(db.Text, nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    user = db.relationship('User', backref='recipes') 

class RecipeIngredient(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    recipe_id = db.Column(db.Integer, db.ForeignKey('recipe.id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('product.id'), nullable=False)
    quantity = db.Column(db.Float, nullable=False)

    # Define relationships
    recipe = db.relationship('Recipe', backref=db.backref('recipe_ingredients', cascade="all, delete-orphan", lazy=True))
    product = db.relationship('Product', backref=db.backref('recipe_usages', lazy=True))

    __table_args__ = (db.UniqueConstraint('recipe_id', 'product_id', name='_recipe_product_uc'),)

class ShiftSubmission(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    shift_date = db.Column(db.Date, nullable=False)
    shift_type = db.Column(db.String(50), nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    user = db.relationship('User', backref='shift_submissions')

class Schedule(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    shift_date = db.Column(db.Date, nullable=False)
    assigned_shift = db.Column(db.String(50), nullable=False)
    published = db.Column(db.Boolean, default=False)
    start_time_str = db.Column(db.String(50), nullable=True)
    end_time_str = db.Column(db.String(50), nullable=True)
    user = db.relationship('User', backref=db.backref('scheduled_shifts', cascade="all, delete-orphan"))

class ShiftSwapRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    schedule_id = db.Column(db.Integer, db.ForeignKey('schedule.id'), nullable=False)
    requester_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    coverer_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True)
    status = db.Column(db.String(20), nullable=False, default='Pending')
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    schedule = db.relationship('Schedule', backref='swap_requests')
    requester = db.relationship('User', foreign_keys=[requester_id])
    coverer = db.relationship('User', foreign_keys=[coverer_id])

class LeaveRequest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    start_date = db.Column(db.Date, nullable=False)
    end_date = db.Column(db.Date, nullable=False)
    reason = db.Column(db.Text, nullable=False)
    document_path = db.Column(db.String(255), nullable=True)
    status = db.Column(db.String(20), nullable=False, default='Pending')
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    user = db.relationship('User', backref='leave_requests')

volunteered_shift_candidates = db.Table('volunteered_shift_candidates',
    db.Column('volunteered_shift_id', db.Integer, db.ForeignKey('volunteered_shift.id'), primary_key=True),
    db.Column('user_id', db.Integer, db.ForeignKey('user.id'), primary_key=True)
)

class VolunteeredShift(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    schedule_id = db.Column(db.Integer, db.ForeignKey('schedule.id'), nullable=False, unique=True)
    requester_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    status = db.Column(db.String(20), nullable=False, default='Open')
    approved_volunteer_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True)

    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    # Relationships
    schedule = db.relationship('Schedule', backref=db.backref('volunteered_cycle', uselist=False, cascade="all, delete-orphan", lazy=True))
    requester = db.relationship('User', foreign_keys=[requester_id], backref=db.backref('shifts_relinquished', lazy=True))
    approved_volunteer = db.relationship('User', foreign_keys=[approved_volunteer_id], backref=db.backref('shifts_volunteered_approved', lazy=True))
    volunteers = db.relationship('User', secondary=volunteered_shift_candidates, backref=db.backref('shifts_volunteered_for', lazy='dynamic'))
    relinquish_reason = db.Column(db.Text, nullable=True)

class UserFCMToken(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    fcm_token = db.Column(db.String(255), unique=True, nullable=False) # The FCM token from the device/browser
    device_info = db.Column(db.String(255), nullable=True) # e.g., "Chrome on Windows", "Safari on iOS PWA"
    timestamp = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    user = db.relationship('User', backref=db.backref('fcm_tokens', lazy=True, cascade="all, delete-orphan"))

    __table_args__ = {'extend_existing': True}