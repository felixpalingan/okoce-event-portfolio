import os
from dotenv import load_dotenv
load_dotenv()
from flask import Flask, request, jsonify, render_template, redirect, url_for, send_from_directory, flash, Response
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import extract
from flask_bcrypt import Bcrypt
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.utils import secure_filename
import uuid
import pytz
from datetime import datetime, timedelta, time
import random
from functools import wraps
import csv
import io
from flask_mail import Mail, Message
from itsdangerous import URLSafeTimedSerializer, SignatureExpired, BadTimeSignature
import string
import firebase_admin
from firebase_admin import credentials, messaging
from flask_cors import CORS

UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}

app = Flask(__name__)
CORS(app)
base_dir = os.path.abspath(os.path.dirname(__file__))
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'sqlite:///' + os.path.join(base_dir, 'instance', 'eventit.db'))
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY')
app.config['SESSION_COOKIE_HTTPONLY'] = True
app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
app.config['REMEMBER_COOKIE_DURATION'] = timedelta(days=3650)
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024

app.config['MAIL_SERVER'] = 'smtp.googlemail.com'
app.config['MAIL_PORT'] = 587
app.config['MAIL_USE_TLS'] = True
app.config['MAIL_USERNAME'] = os.getenv("MAIL_USERNAME")
app.config['MAIL_PASSWORD'] = os.getenv("MAIL_PASSWORD")
app.config['MAIL_DEFAULT_SENDER'] = ('OK OCE Admin', os.environ.get('MAIL_SENDER'))

mail = Mail(app)
s = URLSafeTimedSerializer(app.config['SECRET_KEY'])

db = SQLAlchemy(app)
bcrypt = Bcrypt(app)
LOCAL_TZ = pytz.timezone('Asia/Jakarta')

try:
    cred = credentials.Certificate('firebase-service-account-key.json') 
    firebase_admin.initialize_app(cred)
    print("Firebase Admin SDK berhasil diinisialisasi.")
except Exception as e:
    print(f"GAGAL inisialisasi Firebase Admin SDK: {e}")

login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'web_login'
login_manager.login_message_category = "warning"

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

@login_manager.unauthorized_handler
def unauthorized():
    if request.path.startswith('/api/'):
        return jsonify(message="Authentication required"), 401
    return redirect(url_for('web_login'))

def role_required(roles_list):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not current_user.is_authenticated or current_user.role not in roles_list:
                flash("Anda tidak memiliki izin untuk mengakses halaman ini.", "danger")
                if current_user.is_authenticated and current_user.role == 'panitia':
                    return redirect(url_for('panitia_dashboard'))
                return redirect(url_for('web_login'))
            return f(*args, **kwargs)
        return decorated_function
    return decorator

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def send_broadcast_notification(title, body, event_id):
    """
    Mengirim notifikasi ke semua user yang subscribe ke topic 'new_events'.
    """
    try:
        topic = 'new_events'
        
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            topic=topic,
            data={
                'event_id': str(event_id),
                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            }
        )
        
        response = messaging.send(message)
        print(f'Successfully sent message to topic {topic}: {response}')
        return True
    except Exception as e:
        print(f'Error sending broadcast message: {e}')
        return False
    
def send_single_notification(token, title, body, event_id):
    """
    Mengirim notifikasi ke SATU token FCM spesifik.
    """
    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            token=token, 
            data={
                'event_id': str(event_id),
                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            }
        )
        response = messaging.send(message)
        print(f"Successfully sent reminder to token {token[:10]}...: {response}")
        return True
    except Exception as e:
        print(f"Error sending single notification: {e}")
        return False

def save_event_questions(event_id, form_data):
    """Menyimpan atau update 5 soal dari form ke database."""
    EventQuestion.query.filter_by(event_id=event_id).delete()
    
    for i in range(1, 6):
        q_text = form_data.get(f'q_{i}_text')
        if q_text:
            question = EventQuestion(
                event_id=event_id,
                question_number=i,
                question_text=q_text,
                option_a=form_data.get(f'q_{i}_a'),
                option_b=form_data.get(f'q_{i}_b'),
                option_c=form_data.get(f'q_{i}_c'),
                option_d=form_data.get(f'q_{i}_d'),
                correct_answer=form_data.get(f'q_{i}_answer')
            )
            db.session.add(question)
    db.session.commit()

@app.cli.command("send-reminders")
def send_reminders_command():
    """
    Mencari event yang akan mulai BESOK (kapanpun di hari berikutnya)
    dan mengirim notifikasi H-1 ke peserta.
    Dirancang untuk dijalankan SEKALI SEHARI (misal: jam 7 pagi).
    """
    print("--- [Scheduled Task] Memulai pengecekan notifikasi H-1... ---")
    
    now_utc = datetime.utcnow()
    
    tomorrow_date = (now_utc + timedelta(days=1)).date()
    
    start_of_tomorrow = datetime.combine(tomorrow_date, time.min)
    
    start_of_day_after_tomorrow = datetime.combine(tomorrow_date + timedelta(days=1), time.min)
    
    print(f"--- [Scheduled Task] Mencari event antara {start_of_tomorrow} dan {start_of_day_after_tomorrow} (UTC) ---")

    events_tomorrow = Event.query.filter(
        Event.tgl_mulai_event >= start_of_tomorrow,
        Event.tgl_mulai_event < start_of_day_after_tomorrow,
        Event.is_archived == False
    ).all()
    
    if not events_tomorrow:
        print("--- [Scheduled Task] Tidak ada event yang dijadwalkan untuk besok. Selesai. ---")
        return

    print(f"--- [Scheduled Task] Ditemukan {len(events_tomorrow)} event untuk dikirim pengingat. ---")
    
    total_reminders_sent = 0
    
    for event in events_tomorrow:
        tickets = Ticket.query.filter_by(event_id=event.id).all()
        
        if not tickets:
            continue 

        print(f"--- Mengirim {len(tickets)} pengingat untuk event: '{event.title}' ---")
        
        for ticket in tickets:
            user = ticket.user
            
            if user and user.fcm_token:
                
                dt_aware_utc = pytz.utc.localize(event.tgl_mulai_event)
                dt_aware_wib = dt_aware_utc.astimezone(LOCAL_TZ)
                
                tanggal_wib = dt_aware_wib.strftime('%d %B') 
                waktu_wib = dt_aware_wib.strftime('%H:%M WIB') 

                send_single_notification(
                    token=user.fcm_token,
                    title=f"Pengingat Event: '{event.title}' Besok!",
                    body=f"Jangan lupa, event Anda akan dimulai besok, {tanggal_wib} pukul {waktu_wib}.",
                    event_id=event.id
                )
                total_reminders_sent += 1
            
    print(f"--- [Scheduled Task] Selesai. Total {total_reminders_sent} pengingat terkirim. ---")

class User(db.Model, UserMixin):
    id = db.Column(db.Integer, primary_key=True)
    okoce_id = db.Column(db.String(8), unique=True, nullable=False)
    name = db.Column(db.String(100), nullable=False)
    phone_number = db.Column(db.String(20), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    province = db.Column(db.String(100), nullable=False)
    city = db.Column(db.String(100), nullable=False)
    institution = db.Column(db.String(150), nullable=True)
    has_business = db.Column(db.Boolean, default=False)
    password_hash = db.Column(db.String(128), nullable=False)
    role = db.Column(db.String(20), nullable=False, default='user')
    businesses = db.relationship('BusinessProfile', backref='owner', lazy='dynamic', cascade="all, delete-orphan")
    is_verified = db.Column(db.Boolean, nullable=False, default=False)
    verification_otp = db.Column(db.String(6), nullable=True)
    otp_expiry = db.Column(db.DateTime, nullable=True)
    last_otp_sent = db.Column(db.DateTime, nullable=True)
    fcm_token = db.Column(db.String(255), nullable=True, unique=True)
    privacy_accepted_at = db.Column(db.DateTime, nullable=True)

    def set_password(self, password): self.password_hash = bcrypt.generate_password_hash(password).decode('utf8')
    def check_password(self, password): return bcrypt.check_password_hash(self.password_hash, password)

class Event(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    sifat_pelatihan = db.Column(db.String(50), nullable=False)
    title = db.Column(db.String(150), nullable=False)
    jenis_event = db.Column(db.String(50), nullable=False)
    tempat_event = db.Column(db.String(50), nullable=False)
    pic_event = db.Column(db.String(100), nullable=False)
    narasumber = db.Column(db.String(255), nullable=False)
    slot_peserta = db.Column(db.Integer, nullable=False)
    description = db.Column(db.Text, nullable=False)
    price = db.Column(db.Integer, nullable=False, default=0)
    image_filename = db.Column(db.String(255), nullable=True)
    tgl_buka_pendaftaran = db.Column(db.DateTime, nullable=False)
    tgl_tutup_pendaftaran = db.Column(db.DateTime, nullable=False)
    tgl_mulai_event = db.Column(db.DateTime, nullable=False)
    tgl_selesai_event = db.Column(db.DateTime, nullable=False)
    is_umkm_data_required = db.Column(db.Boolean, default=False)
    is_archived = db.Column(db.Boolean, default=False, nullable=False)
    online_event_url = db.Column(db.String(500), nullable=True)
    has_pre_post_test = db.Column(db.Boolean, default=False)
    is_post_test_open_manually = db.Column(db.Boolean, default=False)
    questions = db.relationship('EventQuestion', backref='event', lazy='dynamic', cascade="all, delete-orphan")
    
class EventQuestion(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    event_id = db.Column(db.Integer, db.ForeignKey('event.id'), nullable=False)
    question_number = db.Column(db.Integer, nullable=False)
    question_text = db.Column(db.Text, nullable=False)
    option_a = db.Column(db.String(200), nullable=False)
    option_b = db.Column(db.String(200), nullable=False)
    option_c = db.Column(db.String(200), nullable=False)
    option_d = db.Column(db.String(200), nullable=False)
    correct_answer = db.Column(db.String(1), nullable=False)

class UserTestScore(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    event_id = db.Column(db.Integer, db.ForeignKey('event.id'), nullable=False)
    pre_test_score = db.Column(db.Integer, nullable=True)
    post_test_score = db.Column(db.Integer, nullable=True)
    pre_test_submitted_at = db.Column(db.DateTime, nullable=True)
    post_test_submitted_at = db.Column(db.DateTime, nullable=True)
    user = db.relationship('User', backref=db.backref('test_scores', lazy=True))
    event = db.relationship('Event', backref=db.backref('test_scores', lazy=True))

class Ticket(db.Model):
    id = db.Column(db.Integer, primary_key=True); ticket_code = db.Column(db.String(36), unique=True, nullable=False, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    event_id = db.Column(db.Integer, db.ForeignKey('event.id'), nullable=False)
    is_checked_in = db.Column(db.Boolean, default=False)
    user = db.relationship('User', backref=db.backref('tickets', lazy=True))
    event = db.relationship('Event', backref=db.backref('tickets', lazy=True))

class CheckIn(db.Model):
    id = db.Column(db.Integer, primary_key=True); ticket_id = db.Column(db.Integer, db.ForeignKey('ticket.id'), nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False)
    ticket = db.relationship('Ticket', backref=db.backref('check_ins', lazy=True, cascade="all, delete-orphan"))

class BusinessProfile(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    
    business_name = db.Column(db.String(150), nullable=False)
    business_type = db.Column(db.String(100), nullable=False) 
    
    address_same_as_home = db.Column(db.Boolean, default=False)
    address_province = db.Column(db.String(100), nullable=True)
    address_city = db.Column(db.String(100), nullable=True)
    address_district = db.Column(db.String(100), nullable=True) 
    address_village = db.Column(db.String(100), nullable=True) 
    address_rt = db.Column(db.String(5), nullable=True)
    address_rw = db.Column(db.String(5), nullable=True)
    address_postal_code = db.Column(db.String(10), nullable=True)
    address_detail = db.Column(db.Text, nullable=True) 
    premise_status = db.Column(db.String(50), nullable=True) 

    has_license = db.Column(db.Boolean, default=False)
    legal_entity = db.Column(db.String(50), nullable=True) 
    has_npwp = db.Column(db.Boolean, default=False)
    financial_report_type = db.Column(db.String(50), default='Manual') 
    financial_report_app = db.Column(db.String(100), nullable=True) 
    report_laba_rugi = db.Column(db.Boolean, default=False)
    report_neraca = db.Column(db.Boolean, default=False)
    report_arus_kas = db.Column(db.Boolean, default=False)
    has_funding = db.Column(db.Boolean, default=False)

    business_phone = db.Column(db.String(20), nullable=True)
    business_email = db.Column(db.String(120), nullable=True)
    operating_since = db.Column(db.String(50), nullable=True) 

    marketplaces = db.relationship('BusinessMarketplace', backref='business', lazy='dynamic', cascade="all, delete-orphan")
    licenses = db.relationship('BusinessLicense', backref='business', lazy='dynamic', cascade="all, delete-orphan")
    finances = db.relationship('BusinessFinance', backref='business', lazy='dynamic', cascade="all, delete-orphan")
    npwps = db.relationship('BusinessNPWP', backref='business', lazy='dynamic', cascade="all, delete-orphan")
    fundings = db.relationship('BusinessFunding', backref='business', lazy='dynamic', cascade="all, delete-orphan")

class BusinessMarketplace(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    business_id = db.Column(db.Integer, db.ForeignKey('business_profile.id'), nullable=False)
    marketplace_type = db.Column(db.String(100), nullable=False)
    url = db.Column(db.String(255), nullable=False)

class BusinessLicense(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    business_id = db.Column(db.Integer, db.ForeignKey('business_profile.id'), nullable=False)
    license_type = db.Column(db.String(100), nullable=False)
    license_number = db.Column(db.String(100), nullable=True)

class BusinessFinance(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    business_id = db.Column(db.Integer, db.ForeignKey('business_profile.id'), nullable=False)
    year = db.Column(db.String(4), nullable=False)
    omzet_range = db.Column(db.String(100), nullable=False)
    profit = db.Column(db.BigInteger, nullable=True)
    asset_value = db.Column(db.BigInteger, nullable=True)
    employee_count = db.Column(db.String(50), nullable=False)

class BusinessNPWP(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    business_id = db.Column(db.Integer, db.ForeignKey('business_profile.id'), nullable=False)
    npwp_number = db.Column(db.String(100), nullable=True)
    report_receipt_number = db.Column(db.String(100), nullable=True)
    year = db.Column(db.String(4), nullable=True)
    submission_date = db.Column(db.String(50), nullable=True)

class BusinessFunding(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    business_id = db.Column(db.Integer, db.ForeignKey('business_profile.id'), nullable=False)
    funder_type = db.Column(db.String(100), nullable=True)
    funder_name = db.Column(db.String(100), nullable=True)
    amount = db.Column(db.BigInteger, nullable=True)
    received_date = db.Column(db.String(50), nullable=True)
    installment_start_date = db.Column(db.String(50), nullable=True)
    duration_months = db.Column(db.Integer, nullable=True)

def generate_otp(length=6):
    """Generate a random numeric OTP."""
    return ''.join(random.choices(string.digits, k=length))

def send_verification_email(user_email, otp_code):
    """Sends an email with the OTP code using Flask-Mail."""
    
    html_content = f"""
    <div style="font-family: Arial, sans-serif; line-height: 1.6;">
        <h2>Selamat datang di OK OCE!</h2>
        <p>Gunakan kode di bawah ini untuk memverifikasi akun email Anda:</p>
        <p style="font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 20px 0; padding: 10px; background-color:
            {otp_code}
        </p>
        <p>Kode ini akan kedaluwarsa dalam 10 menit.</p>
        <hr>
        <p style="font-size: 12px; color:
            © 2025 OK OCE.
        </p>
    </div>
    """
    
    try:
        msg = Message(
            subject="Kode Verifikasi Akun OK OCE Anda",
            recipients=[user_email],
            html=html_content, 
            body=f"Kode verifikasi Anda adalah: {otp_code}"
        )
        mail.send(msg)
        print(f"Email verifikasi berhasil dikirim ke {user_email} via Gmail.")
        return True
    except Exception as e:
        print(f"Error sending email: {e}")
        return False

def send_password_reset_email(user_email, otp_code):
    """Sends a password reset OTP code using Flask-Mail."""
    
    html_content = f"""
    <div style="font-family: Arial, sans-serif; line-height: 1.6;">
        <h2>Permintaan Reset Password</h2>
        <p>Kami menerima permintaan untuk mereset password akun OK OCE Anda.</p>
        <p>Gunakan kode di bawah ini untuk melanjutkan:</p>
        <p style="font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 20px 0; padding: 10px; background-color:
            {otp_code}
        </p>
        <p>Kode ini akan kedaluwarsa dalam 10 menit.</p>
        <hr>
        <p style="font-size: 12px; color:
            © 2025 OK OCE.
        </p>
    </div>
    """

    try:
        msg = Message(
            subject="Kode Reset Password OK OCE Anda",
            recipients=[user_email],
            html=html_content, 
            body=f"Kode reset password Anda adalah: {otp_code}" 
        )
        mail.send(msg)
        print(f"Email reset password berhasil dikirim ke {user_email} via Gmail.")
        return True
    except Exception as e:
        print(f"Error sending email: {e}")
        return False

@app.route('/api/public/events', methods=['GET'])
def public_get_events():
    """
    Endpoint PUBLIK untuk mengambil daftar event aktif.
    Support Pagination: ?page=1&limit=10
    """
    try:
        page = request.args.get('page', 1, type=int)
        limit = request.args.get('limit', 10, type=int)
        
        now_utc = datetime.utcnow()
        
        query = Event.query.filter(
            Event.jenis_event == 'Public', 
            Event.is_archived == False,
            Event.tgl_selesai_event > now_utc
        ).order_by(Event.tgl_mulai_event.asc())
        
        pagination = query.paginate(page=page, per_page=limit, error_out=False)
        events = pagination.items
        
        results = []
        for e in events:
            dt_aware_utc = pytz.utc.localize(e.tgl_mulai_event)
            dt_aware_wib = dt_aware_utc.astimezone(LOCAL_TZ)
            
            results.append({
                'id': e.id,
                'title': e.title,
                'description': e.description[:200] + "..." if len(e.description) > 200 else e.description,
                'start_time': dt_aware_wib.isoformat(),
                'location': e.tempat_event,
                'price': e.price,
                'image_url': f"{request.host_url}uploads/{e.image_filename}" if e.image_filename else None,
                'registration_open': e.tgl_buka_pendaftaran <= now_utc <= e.tgl_tutup_pendaftaran
            })
            
        return jsonify({
            'status': 'success',
            'data': results,
            'meta': {
                'current_page': page,
                'per_page': limit,
                'total_events': pagination.total,
                'total_pages': pagination.pages
            }
        }), 200

    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500
    
@app.route('/api/register', methods=['POST'])
def api_register():
    data = request.json
    
    if not data.get('email') or not data.get('phone_number'):
        return jsonify({'message': 'Email dan Nomor HP wajib diisi'}), 400
    
    if User.query.filter_by(email=data['email'], is_verified=True).first():
        return jsonify({'message': 'Email sudah terdaftar'}), 409
    if User.query.filter_by(phone_number=data['phone_number'], is_verified=True).first():
        return jsonify({'message': 'Nomor HP sudah terdaftar'}), 409

    User.query.filter_by(email=data['email'], is_verified=False).delete()
    User.query.filter_by(phone_number=data['phone_number'], is_verified=False).delete()
    db.session.commit()

    while True:
        new_id = str(random.randint(10000000, 99999999))
        if not User.query.filter_by(okoce_id=new_id).first(): break
    
    otp = generate_otp()
    expiry_time = datetime.utcnow() + timedelta(minutes=10)
    
    new_user = User(
        okoce_id=new_id, name=data['name'], phone_number=data['phone_number'],
        email=data['email'], province=data['province'], city=data['city'],
        institution=data.get('institution'), has_business=data.get('has_business', False), 
        role='user',
        is_verified=False, 
        verification_otp=otp, 
        otp_expiry=expiry_time, 
        last_otp_sent=datetime.utcnow(),
        privacy_accepted_at=datetime.utcnow()
    )
    new_user.set_password(data['password'])
    
    if send_verification_email(new_user.email, otp):
        db.session.add(new_user)
        db.session.commit()
        return jsonify({
            'message': 'Registrasi berhasil! Cek email Anda untuk kode verifikasi.',
            'user_email': new_user.email 
        }), 201
    else:
        return jsonify({'message': 'Registrasi gagal. Tidak dapat mengirim email verifikasi.'}), 500

@app.route('/api/login', methods=['POST'])
def api_login():
    data = request.json; login_identifier = data.get('login_identifier'); password = data.get('password')
    
    if '@' in login_identifier: 
        user = User.query.filter_by(email=login_identifier).first()
    else: 
        user = User.query.filter_by(phone_number=login_identifier).first()
        
    if user and user.check_password(password):
        if not user.is_verified:
            otp = generate_otp()
            user.verification_otp = otp
            user.otp_expiry = datetime.utcnow() + timedelta(minutes=10)
            user.last_otp_sent = datetime.utcnow()
            db.session.commit()
            send_verification_email(user.email, otp)
            
            return jsonify({
                'message': 'Akun Anda belum terverifikasi. Kami telah mengirim ulang kode OTP ke email Anda.',
                'action': 'verify', 
                'user_email': user.email
            }), 403 

        login_user(user, remember=True)
        return jsonify({'message': 'Login berhasil', 'user_id': user.id, 'name': user.name, 'okoce_id': user.okoce_id, 'has_business': user.has_business}), 200
        
    return jsonify({'message': 'Nomor HP/Email atau password salah'}), 401

@app.route('/api/logout', methods=['POST'])
@login_required
def api_logout(): logout_user(); return jsonify(message="Logout berhasil"), 200

@app.route('/api/status', methods=['GET'])
@login_required
def get_status():
    return jsonify({'logged_in': True, 'user_id': current_user.id, 'name': current_user.name, 'okoce_id': current_user.okoce_id, 'has_business': current_user.has_business}), 200

@app.route('/api/verify-email', methods=['POST'])
def verify_email():
    data = request.json
    email = data.get('email')
    otp = data.get('otp')
    
    if not email or not otp:
        return jsonify({'message': 'Email dan OTP wajib diisi'}), 400
        
    user = User.query.filter_by(email=email).first()
    
    if not user:
        return jsonify({'message': 'User tidak ditemukan'}), 404
        
    if user.is_verified:
        return jsonify({'message': 'Akun sudah terverifikasi'}), 400

    if user.otp_expiry and user.otp_expiry < datetime.utcnow():
        return jsonify({'message': 'Kode OTP telah kedaluwarsa'}), 410 

    if user.verification_otp == otp:
        user.is_verified = True
        user.verification_otp = None
        user.otp_expiry = None
        db.session.commit()
        return jsonify({'message': 'Verifikasi berhasil! Silakan login.'}), 200
    else:
        return jsonify({'message': 'Kode OTP salah'}), 400

@app.route('/api/send-password-reset-otp', methods=['POST'])
def send_password_reset_otp():
    data = request.json
    email = data.get('email')
    user = User.query.filter_by(email=email, is_verified=True).first()
    
    if user:
        otp = generate_otp()
        user.verification_otp = otp
        user.otp_expiry = datetime.utcnow() + timedelta(minutes=10)
        db.session.commit()
        
        if send_password_reset_email(user.email, otp):
            return jsonify({'message': 'OTP reset password telah dikirim ke email Anda'}), 200
        else:
            return jsonify({'message': 'Gagal mengirim email'}), 500
    else:
        return jsonify({'message': 'Email tidak terdaftar'}), 404

@app.route('/api/verify-otp-and-reset-password', methods=['POST'])
def verify_otp_and_reset_password():
    data = request.json
    email = data.get('email')
    otp = data.get('otp')
    new_password = data.get('new_password')

    if not email or not otp or not new_password:
        return jsonify({'message': 'Semua field wajib diisi'}), 400
        
    user = User.query.filter_by(email=email).first()
    
    if not user:
        return jsonify({'message': 'User tidak ditemukan'}), 404
    
    if user.otp_expiry and user.otp_expiry < datetime.utcnow():
        return jsonify({'message': 'Kode OTP telah kedaluwarsa'}), 410
        
    if user.verification_otp == otp:
        user.set_password(new_password)
        user.verification_otp = None 
        user.otp_expiry = None
        user.is_verified = True
        db.session.commit()
        return jsonify({'message': 'Password berhasil direset. Silakan login.'}), 200
    else:
        return jsonify({'message': 'Kode OTP salah'}), 400

@app.route('/api/resend-otp', methods=['POST'])
def resend_otp():
    data = request.json
    email = data.get('email')
    if not email:
        return jsonify({'message': 'Email diperlukan'}), 400

    user = User.query.filter_by(email=email).first()
    if not user:
        return jsonify({'message': 'User tidak ditemukan'}), 404
    if user.is_verified:
        return jsonify({'message': 'Akun sudah terverifikasi'}), 400

    if user.last_otp_sent:
        time_diff = datetime.utcnow() - user.last_otp_sent
        if time_diff < timedelta(seconds=60):
            remaining = 60 - int(time_diff.total_seconds())
            return jsonify({'message': f'Harap tunggu {remaining} detik lagi'}), 429
    
    otp = generate_otp()
    user.verification_otp = otp
    user.otp_expiry = datetime.utcnow() + timedelta(minutes=10)
    user.last_otp_sent = datetime.utcnow()
    
    if send_verification_email(user.email, otp):
        db.session.commit()
        return jsonify({'message': 'OTP baru telah dikirim'}), 200
    else:
        return jsonify({'message': 'Gagal mengirim email'}), 500

@app.route('/api/change-verification-email', methods=['POST'])
def change_verification_email():
    data = request.json
    old_email = data.get('old_email')
    new_email = data.get('new_email')

    if not old_email or not new_email:
        return jsonify({'message': 'Email lama dan baru diperlukan'}), 400
    
    if User.query.filter_by(email=new_email, is_verified=True).first():
        return jsonify({'message': 'Email baru sudah terdaftar oleh akun lain'}), 409

    user = User.query.filter_by(email=old_email, is_verified=False).first()
    if not user:
        return jsonify({'message': 'Akun unverified tidak ditemukan'}), 404

    User.query.filter_by(email=new_email, is_verified=False).delete()
    db.session.commit()

    otp = generate_otp()
    user.email = new_email
    user.verification_otp = otp
    user.otp_expiry = datetime.utcnow() + timedelta(minutes=10)
    user.last_otp_sent = datetime.utcnow()
    
    if send_verification_email(user.email, otp):
        db.session.commit()
        return jsonify({'message': f'OTP telah dikirim ke email baru: {new_email}', 'new_email': new_email}), 200
    else:
        db.session.rollback()
        return jsonify({'message': 'Gagal mengirim email ke alamat baru'}), 500

@app.route('/api/user/update-fcm-token', methods=['POST'])
@login_required
def update_fcm_token():
    """
    Menerima FCM token dari aplikasi Flutter dan menyimpannya
    untuk user yang sedang login.
    """
    data = request.json
    token = data.get('token')
    
    if not token:
        return jsonify(message="Token required"), 400

    try:
        current_user.fcm_token = token
        db.session.commit()
        return jsonify(message="Token updated"), 200
    except Exception as e:
        db.session.rollback()
        print(f"Error updating FCM token: {e}")
        return jsonify(message="Server error"), 500

@app.route('/api/events', methods=['GET'])
@login_required
def get_events():
    """
    Mengambil event untuk aplikasi user.
    HANYA event yang:
    1. Pendaftaran sedang dibuka (di antara tgl_buka dan tgl_tutup)
    2. Event-nya sendiri belum selesai (tgl_selesai > sekarang)
    3. Event tidak di-arsip
    Diurutkan berdasarkan event yang paling cepat mulai (ASC).
    """
    now_utc = datetime.utcnow()
    
    visible_events = Event.query.filter(
        Event.tgl_buka_pendaftaran <= now_utc,
        Event.tgl_tutup_pendaftaran >= now_utc,
        Event.tgl_selesai_event > now_utc,
        Event.is_archived == False
    ).order_by(Event.tgl_mulai_event.asc()).all()
    
    event_list = []
    for e in visible_events:
        event_data = { 
            'id': e.id, 'title': e.title, 'description': e.description, 
            'date': e.tgl_mulai_event.strftime('%d %B %Y'), 'location': e.tempat_event, 
            'price': e.price, 'image_filename': e.image_filename, 
            'tgl_buka_pendaftaran': e.tgl_buka_pendaftaran.isoformat() if e.tgl_buka_pendaftaran else None, 
            'tgl_tutup_pendaftaran': e.tgl_tutup_pendaftaran.isoformat() if e.tgl_tutup_pendaftaran else None,
            'is_umkm_data_required': e.is_umkm_data_required
        }
        event_list.append(event_data)
    return jsonify(event_list)

@app.route('/api/tickets/buy', methods=['POST'])
@login_required
def buy_ticket():
    user_id = current_user.id
    data = request.json
    event_id = data.get('event_id')

    existing_ticket = Ticket.query.filter_by(user_id=user_id, event_id=event_id).first()
    if existing_ticket: return jsonify({'message': 'Anda sudah terdaftar di event ini.'}), 409

    event = Event.query.get(event_id)
    if not event: return jsonify({'message': 'Event tidak ditemukan.'}), 404
    
    if event.price > 0: return jsonify({'message': 'Event ini berbayar (fitur belum siap).'}), 400

    now_aware = datetime.now(LOCAL_TZ)
    buka_pendaftaran_aware = LOCAL_TZ.localize(event.tgl_buka_pendaftaran)
    tutup_pendaftaran_aware = LOCAL_TZ.localize(event.tgl_tutup_pendaftaran)
    if now_aware < buka_pendaftaran_aware: return jsonify({'message': 'Pendaftaran belum dibuka.'}), 409
    if now_aware > tutup_pendaftaran_aware: return jsonify({'message': 'Pendaftaran sudah ditutup.'}), 409

    ticket_count = Ticket.query.filter_by(event_id=event_id).count()
    if ticket_count >= event.slot_peserta: return jsonify({'message': 'Kuota penuh.'}), 409

    if event.is_umkm_data_required:
        business_count = BusinessProfile.query.filter_by(user_id=user_id).count()
        if business_count == 0:
            return jsonify({'message': 'Event ini mewajibkan Anda melengkapi data UMKM. Silakan isi di menu Profil.'}), 409

    new_ticket = Ticket(user_id=user_id, event_id=event_id)
    db.session.add(new_ticket); db.session.commit()
    return jsonify({'message': 'Tiket berhasil dibeli', 'ticket_code': new_ticket.ticket_code}), 201

@app.route('/api/users/<int:user_id>/tickets', methods=['GET'])
@login_required
def get_user_tickets(user_id):
    if user_id != current_user.id: return jsonify({"message": "Akses ditolak"}), 403
    
    tickets = Ticket.query.join(Event).filter(Ticket.user_id == user_id).order_by(Event.tgl_mulai_event.desc()).all()
    
    results = []
    for t in tickets:
        status = 'READY'
        label = 'Tersedia'
        
        if t.is_checked_in:
            if not t.event.has_pre_post_test:
                status = 'DONE'
                label = 'Selesai'
            else:
                score = UserTestScore.query.filter_by(user_id=user_id, event_id=t.event.id).first()
                
                if not score:
                    status = 'PRE_TEST'
                    label = 'Isi Pre-Test'
                elif score.post_test_score is None:
                    status = 'POST_TEST'
                    label = 'Isi Post-Test'
                else:
                    status = 'DONE'
                    label = 'Selesai'
        
        if not t.is_checked_in and t.event.tempat_event == 'Online':
             label = 'Gabung Online'

        results.append({
            'ticket_code': t.ticket_code, 
            'is_checked_in': t.is_checked_in, 
            'event_title': t.event.title, 
            'event_date': t.event.tgl_mulai_event.strftime('%d %B %Y'), 
            'event_id': t.event.id,
            'event_location': t.event.tempat_event,
            'status': status,
            'status_label': label
        })
        
    return jsonify(results)

@app.route('/api/events/<int:event_id>/test/status', methods=['GET'])
@login_required
def get_test_status_api(event_id):
    event = Event.query.get_or_404(event_id)
    user_id = current_user.id

    if not event.has_pre_post_test:
        return jsonify({'status': 'NO_TEST'}), 200

    score_record = UserTestScore.query.filter_by(user_id=user_id, event_id=event_id).first()

    if not score_record:
        return jsonify({
            'status': 'PRE_TEST_NEEDED',
            'message': 'Silakan isi Pre-Test sebelum melanjutkan.'
        }), 200

    if score_record.post_test_score is None:
        now_utc = datetime.utcnow()
        
        time_threshold = event.tgl_selesai_event - timedelta(minutes=30)
        is_time_open = now_utc >= time_threshold
        
        if event.is_post_test_open_manually or is_time_open:
            return jsonify({
                'status': 'POST_TEST_AVAILABLE',
                'message': 'Post-Test telah dibuka.'
            }), 200
        else:
            return jsonify({
                'status': 'POST_TEST_LOCKED',
                'message': 'Post-Test belum dibuka.',
                'open_at': time_threshold.isoformat() 
            }), 200

    return jsonify({
        'status': 'COMPLETED',
        'pre_score': score_record.pre_test_score,
        'post_score': score_record.post_test_score,
        'message': 'Anda telah menyelesaikan semua tes.'
    }), 200

@app.route('/api/events/<int:event_id>/test/questions', methods=['GET'])
@login_required
def get_test_questions_api(event_id):
    questions = EventQuestion.query.filter_by(event_id=event_id).order_by(EventQuestion.question_number).all()
    
    if not questions:
        return jsonify({'message': 'Soal belum dibuat oleh admin'}), 404

    return jsonify([{
        'id': q.id,
        'number': q.question_number,
        'text': q.question_text,
        'options': {
            'A': q.option_a,
            'B': q.option_b,
            'C': q.option_c,
            'D': q.option_d
        }
    } for q in questions]), 200

@app.route('/api/events/<int:event_id>/test/submit', methods=['POST'])
@login_required
def submit_test_api(event_id):
    data = request.json
    user_answers = data.get('answers', {})
    
    questions = EventQuestion.query.filter_by(event_id=event_id).all()
    if not questions: return jsonify({'message': 'Error data soal'}), 500

    correct_count = 0
    total_questions = len(questions)

    for q in questions:
        ans = user_answers.get(str(q.question_number))
        if ans and ans == q.correct_answer:
            correct_count += 1
    
    final_score = int((correct_count / total_questions) * 100)

    score_record = UserTestScore.query.filter_by(user_id=current_user.id, event_id=event_id).first()
    
    test_type = 'Pre-Test'
    
    if not score_record:
        score_record = UserTestScore(
            user_id=current_user.id,
            event_id=event_id,
            pre_test_score=final_score,
            pre_test_submitted_at=datetime.utcnow()
        )
        db.session.add(score_record)
    else:
        test_type = 'Post-Test'
        score_record.post_test_score = final_score
        score_record.post_test_submitted_at = datetime.utcnow()
    
    db.session.commit()

    return jsonify({
        'status': 'success',
        'score': final_score,
        'type': test_type,
        'message': f'{test_type} Selesai! Nilai Anda: {final_score}'
    }), 200

@app.route('/api/mobile/panitia/login', methods=['POST'])
def mobile_panitia_login():
    """
    Login khusus Panitia. 
    User biasa (role='user') akan DITOLAK (403 Forbidden).
    """
    data = request.json
    login_identifier = data.get('login_identifier')
    password = data.get('password')

    if '@' in login_identifier:
        user = User.query.filter_by(email=login_identifier).first()
    else:
        user = User.query.filter_by(phone_number=login_identifier).first()

    if user and user.check_password(password):
        if user.role not in ['admin', 'panitia']:
            return jsonify({
                'status': 'error',
                'message': 'Akses Ditolak. Akun Anda bukan Panitia.'
            }), 403
        
        login_user(user, remember=True)
        
        return jsonify({
            'status': 'success',
            'message': 'Login Panitia Berhasil',
            'user': {
                'id': user.id,
                'name': user.name,
                'role': user.role
            }
        }), 200
    
    return jsonify({'status': 'error', 'message': 'Email/Password Salah'}), 401

@app.route('/api/mobile/panitia/scan', methods=['POST'])
@login_required
@role_required(['admin', 'panitia'])
def mobile_panitia_scan():
    """
    Endpoint scan tiket khusus Mobile App.
    Mengembalikan data lengkap untuk UI (mirip Web Scanner).
    """
    data = request.json
    ticket_code = data.get('ticket_code')
    
    if not ticket_code:
        return jsonify({'status': 'error', 'message': 'Kode tiket tidak terbaca'}), 400
        
    ticket = Ticket.query.filter_by(ticket_code=ticket_code).first()
    
    if not ticket:
        return jsonify({'status': 'error', 'message': 'Tiket Tidak Valid / Tidak Ditemukan'}), 404
        
    if ticket.is_checked_in:
        checker_name = "Panitia Sebelumnya"
        check_in_data = CheckIn.query.filter_by(ticket_id=ticket.id).first()
        time_str = check_in_data.timestamp.strftime('%H:%M') if check_in_data else "-"
        
        return jsonify({
            'status': 'error',
            'message': f'Tiket SUDAH DIGUNAKAN pukul {time_str}',
            'detail': {
                'user_name': ticket.user.name,
                'event_title': ticket.event.title
            }
        }), 409
    
    try:
        ticket.is_checked_in = True
        new_check_in = CheckIn(ticket_id=ticket.id, timestamp=datetime.utcnow())
        db.session.add(new_check_in)
        db.session.commit()
        
        return jsonify({
            'status': 'success',
            'message': 'Check-in BERHASIL',
            'detail': {
                'user_name': ticket.user.name, 
                'user_email': ticket.user.email,
                'event_title': ticket.event.title,
                'ticket_type': 'Reguler',
                'check_in_time': datetime.now(LOCAL_TZ).strftime('%H:%M WIB')
            }
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'status': 'error', 'message': f'Server Error: {str(e)}'}), 500
    
@app.route('/api/checkin', methods=['POST'])
@login_required
def check_in():
    data = request.json
    ticket_code = data.get('ticket_code')
    target_event_id = data.get('event_id')
    
    if not ticket_code:
        return jsonify({'status': 'error', 'message': 'Kode tiket tidak ada'}), 400
        
    ticket = Ticket.query.filter_by(ticket_code=ticket_code).first()
    
    if not ticket:
        return jsonify({'status': 'error', 'message': 'Tiket Tidak Valid'}), 404
    if ticket.is_checked_in:
        return jsonify({'status': 'error', 'message': 'Tiket Sudah Digunakan'}), 409
    
    if target_event_id:
        if ticket.event_id != int(target_event_id):
             return jsonify({'status': 'error', 'message': 'Tiket ini untuk Event LAIN!'}), 400
        
    user = User.query.get(ticket.user_id)
    event = Event.query.get(ticket.event_id)
    
    if not user or not event:
        return jsonify({'status': 'error', 'message': 'Data user/event tidak ditemukan'}), 500
    
    if current_user.role in ['admin', 'panitia']:
        pass 
    
    elif current_user.role == 'user':
        
        if ticket.user_id != current_user.id:
            return jsonify({'status': 'error', 'message': 'Akses Ditolak: Anda bukan pemilik tiket ini'}), 403
        
        if event.tempat_event != 'Online':
            return jsonify({'status': 'error', 'message': 'Akses Ditolak: Tiket ini harus di-scan oleh panitia'}), 403
        
        now = datetime.utcnow()
        if now < event.tgl_mulai_event:
            return jsonify({'status': 'error', 'message': 'Event belum dimulai'}), 400
    
        pass

    else:
        return jsonify({'status': 'error', 'message': 'Akses Ditolak'}), 403

    ticket.is_checked_in = True
    timestamp_wib = datetime.utcnow() 
    new_check_in = CheckIn(ticket_id=ticket.id, timestamp=timestamp_wib)
    
    db.session.add(new_check_in)
    db.session.commit()
    
    return jsonify({
        'status': 'success', 
        'message': 'Check-in Berhasil', 
        'user_name': user.name, 
        'event_title': event.title
    }), 200

@app.route('/api/event/<int:event_id>/open-post-test', methods=['POST'])
@login_required
@role_required(['admin', 'panitia'])
def open_post_test_manual(event_id):
    event = Event.query.get_or_404(event_id)
    event.is_post_test_open_manually = True
    db.session.commit()
    return jsonify({'message': 'Post-Test berhasil dibuka untuk semua peserta.'}), 200

@app.route('/api/tickets/status/<string:ticket_code>', methods=['GET'])
@login_required
def get_ticket_status(ticket_code):
    """
    Endpoint untuk polling. User (pemilik tiket) bertanya 
    apakah tiketnya sudah di-check-in oleh panitia.
    """
    ticket = Ticket.query.filter_by(ticket_code=ticket_code).first_or_404()
    
    if ticket.user_id != current_user.id:
        return jsonify(message="Akses ditolak"), 403
        
    return jsonify({
        'is_checked_in': ticket.is_checked_in,
        'ticket_code': ticket.ticket_code
    })

@app.route('/api/users/<int:user_id>', methods=['GET'])
@login_required
def get_user_profile(user_id):
    if user_id != current_user.id: return jsonify({"message": "Akses ditolak"}), 403
    user = User.query.get_or_404(user_id)
    return jsonify({'name': user.name, 'phone_number': user.phone_number, 'email': user.email, 'province': user.province, 'city': user.city, 'institution': user.institution, 'has_business': user.has_business})

@app.route('/api/users/<int:user_id>/update', methods=['POST'])
@login_required
def update_user_profile(user_id):
    if user_id != current_user.id: return jsonify({"message": "Akses ditolak"}), 403
    user = User.query.get_or_404(user_id); data = request.json
    user.name = data.get('name', user.name)
    user.phone_number = data.get('phone_number', user.phone_number)
    user.email = data.get('email', user.email)
    user.province = data.get('province', user.province)
    user.city = data.get('city', user.city)
    user.institution = data.get('institution', user.institution)
    if 'has_business' in data:
        user.has_business = data.get('has_business')
    db.session.commit()
    return jsonify({'message': 'Profil berhasil diperbarui'}), 200

@app.route('/api/check-phone', methods=['POST'])
def check_phone():
    data = request.json; phone = data.get('phone_number')
    user = User.query.filter_by(phone_number=phone).first()
    if user: return jsonify({'status': 'ok', 'message': 'Nomor HP ditemukan'}), 200
    else: return jsonify({'status': 'error', 'message': 'Nomor HP tidak terdaftar'}), 404

@app.route('/api/reset-password-unverified', methods=['POST'])
def reset_password_unverified():
    data = request.json; phone = data.get('phone_number'); new_password = data.get('password')
    user = User.query.filter_by(phone_number=phone).first()
    if not user: return jsonify({'message': 'User tidak ditemukan'}), 404
    if not new_password or len(new_password) < 5: return jsonify({'message': 'Password baru harus minimal 5 karakter'}), 400
    user.set_password(new_password); db.session.commit()
    return jsonify({'message': 'Password berhasil direset. Silakan login.'}), 200

@app.route('/uploads/<path:filename>')
def serve_upload(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

@app.route('/api/user/businesses', methods=['GET'])
@login_required
def get_user_businesses():
    businesses = BusinessProfile.query.filter_by(user_id=current_user.id).order_by(BusinessProfile.business_name).all()
    return jsonify([{
        'id': b.id,
        'business_name': b.business_name,
        'business_type': b.business_type,
    } for b in businesses])

@app.route('/api/user/businesses/<int:id>', methods=['GET'])
@login_required
def get_business_detail(id):
    business = BusinessProfile.query.filter_by(id=id, user_id=current_user.id).first_or_404()
    
    marketplace = business.marketplaces.first()
    license = business.licenses.first()
    finance = business.finances.first()
    npwp = business.npwps.first()
    funding = business.fundings.first()

    return jsonify({
        'business_name': business.business_name,
        'business_type': business.business_type,
        'address_same_as_home': business.address_same_as_home,
        'address_province': business.address_province,
        'address_city': business.address_city,
        'address_district': business.address_district,
        'address_village': business.address_village,
        'address_rt': business.address_rt, 'address_rw': business.address_rw,
        'address_postal_code': business.address_postal_code,
        'address_detail': business.address_detail,
        'premise_status': business.premise_status,
        'business_phone': business.business_phone,
        'business_email': business.business_email,
        'operating_since': business.operating_since,
        'has_license': business.has_license,
        'legal_entity': business.legal_entity,
        'has_npwp': business.has_npwp,
        'financial_report_type': business.financial_report_type,
        'financial_report_app': business.financial_report_app,
        'report_laba_rugi': business.report_laba_rugi,
        'report_neraca': business.report_neraca,
        'report_arus_kas': business.report_arus_kas,
        'has_funding': business.has_funding,
        'marketplace_type': marketplace.marketplace_type if marketplace else None,
        'url': marketplace.url if marketplace else None,
        'license_type': license.license_type if license else None,
        'license_number': license.license_number if license else None,
        'finance_year': finance.year if finance else None,
        'omzet_range': finance.omzet_range if finance else None,
        'profit': finance.profit if finance else None,
        'asset_value': finance.asset_value if finance else None,
        'employee_count': finance.employee_count if finance else None,
        'npwp_number': npwp.npwp_number if npwp else None,
        'report_receipt_number': npwp.report_receipt_number if npwp else None,
        'npwp_year': npwp.year if npwp else None,
        'submission_date': npwp.submission_date if npwp else None,
        'funder_type': funding.funder_type if funding else None,
        'funder_name': funding.funder_name if funding else None,
        'amount': funding.amount if funding else None,
        'received_date': funding.received_date if funding else None,
        'installment_start_date': funding.installment_start_date if funding else None,
        'duration_months': funding.duration_months if funding else None,
    })

def upsert_sub_record(model_class, business_id, data):
    record = model_class.query.filter_by(business_id=business_id).first()
    if record:
        for key, value in data.items():
            setattr(record, key, value)
    else:
        record = model_class(business_id=business_id, **data)
        db.session.add(record)

@app.route('/api/user/businesses/submit', methods=['POST'])
@login_required
def submit_user_business():
    data = request.json
    business_id = data.get('business_id')
    
    if not current_user.has_business:
        return jsonify({'message': 'Harap aktifkan status "Punya Usaha" di profil Anda dahulu.'}), 403
    if not data.get('business_name'):
        return jsonify({'message': 'Nama Usaha wajib diisi.'}), 400
    
    if business_id:
        business = BusinessProfile.query.filter_by(id=business_id, user_id=current_user.id).first_or_404()
        message = 'Data UMKM berhasil diperbarui'
    else:
        business = BusinessProfile(user_id=current_user.id)
        db.session.add(business)
        message = 'Data UMKM berhasil disimpan'

    try:
        business.business_name = data.get('business_name')
        business.business_type = data.get('business_type')
        business.address_same_as_home = data.get('address_same_as_home', False)
        if not business.address_same_as_home:
            business.address_province = data.get('address_province')
            business.address_city = data.get('address_city')
            business.address_district = data.get('address_district')
            business.address_village = data.get('address_village')
            business.address_rt = data.get('address_rt')
            business.address_rw = data.get('address_rw')
            business.address_postal_code = data.get('address_postal_code')
            business.address_detail = data.get('address_detail')
        business.premise_status = data.get('premise_status')
        business.business_phone = data.get('business_phone')
        business.business_email = data.get('business_email')
        business.operating_since = data.get('operating_since')
        business.has_license = data.get('has_license', False)
        business.legal_entity = data.get('legal_entity')
        business.has_npwp = data.get('has_npwp', False)
        business.financial_report_type = data.get('financial_report_type', 'Manual')
        business.financial_report_app = data.get('financial_report_app')
        business.report_laba_rugi = data.get('report_laba_rugi', False)
        business.report_neraca = data.get('report_neraca', False)
        business.report_arus_kas = data.get('report_arus_kas', False)
        business.has_funding = data.get('has_funding', False)
        
        if not business_id:
            db.session.commit() 
        
        if data.get('marketplace_type') or data.get('url'):
            upsert_sub_record(BusinessMarketplace, business.id, { 'marketplace_type': data.get('marketplace_type'), 'url': data.get('url') })
        
        if business.has_license and (data.get('license_type') or data.get('license_number')):
            upsert_sub_record(BusinessLicense, business.id, { 'license_type': data.get('license_type'), 'license_number': data.get('license_number') })

        if data.get('finance_year') or data.get('omzet_range') or data.get('employee_count'):
            upsert_sub_record(BusinessFinance, business.id, {
                'year': data.get('finance_year'), 'omzet_range': data.get('omzet_range'),
                'profit': data.get('profit'), 'asset_value': data.get('asset_value'),
                'employee_count': data.get('employee_count')
            })
            
        if business.has_npwp and (data.get('npwp_number') or data.get('report_receipt_number')):
            upsert_sub_record(BusinessNPWP, business.id, {
                'npwp_number': data.get('npwp_number'), 'report_receipt_number': data.get('report_receipt_number'),
                'year': data.get('npwp_year'), 'submission_date': data.get('submission_date')
            })
            
        if business.has_funding and (data.get('funder_type') or data.get('funder_name')):
            upsert_sub_record(BusinessFunding, business.id, {
                'funder_type': data.get('funder_type'), 'funder_name': data.get('funder_name'),
                'amount': data.get('amount'), 'received_date': data.get('received_date'),
                'installment_start_date': data.get('installment_start_date'), 'duration_months': data.get('duration_months')
            })

        db.session.commit()
        return jsonify({'message': message, 'business_id': business.id}), 200 if business_id else 201

    except Exception as e:
        db.session.rollback()
        print(f"--- ERROR Submitting Business: {e} ---")
        return jsonify({'message': f'Terjadi kesalahan server: {e}'}), 500

@app.route('/api/user/businesses/<int:id>/delete', methods=['POST'])
@login_required
def delete_user_business(id):
    business = BusinessProfile.query.filter_by(id=id, user_id=current_user.id).first_or_404()
    db.session.delete(business)
    db.session.commit()
    return jsonify({'message': 'Data UMKM berhasil dihapus'}), 200

@app.route('/api/events/<int:event_id>/join_url', methods=['GET'])
@login_required
def get_event_join_url(event_id):
    """
    Endpoint aman untuk mengambil URL event online.
    Hanya bisa diakses oleh user yang SUDAH PUNYA TIKET.
    """
    event = Event.query.get_or_404(event_id)
    ticket = Ticket.query.filter_by(user_id=current_user.id, event_id=event_id).first()

    if event.tempat_event != 'Online':
        return jsonify(message="Ini adalah event offline"), 400
    if not ticket:
        return jsonify(message="Anda tidak terdaftar di event ini"), 403
    if not event.online_event_url:
         return jsonify(message="Link event belum diatur oleh admin"), 404
        
    return jsonify({
        'join_url': event.online_event_url
    })

@app.route('/login', methods=['GET', 'POST'])
def web_login():
    if current_user.is_authenticated:
        if current_user.role == 'admin': return redirect(url_for('dashboard'))
        elif current_user.role == 'panitia': return redirect(url_for('panitia_dashboard'))
        else: return redirect(url_for('web_logout'))
    if request.method == 'POST':
        login_identifier = request.form.get('login_identifier'); password = request.form.get('password')
        if '@' in login_identifier: user = User.query.filter_by(email=login_identifier).first()
        else: user = User.query.filter_by(phone_number=login_identifier).first()
        if user and user.check_password(password) and user.role in ['admin', 'panitia']:
            login_user(user, remember=True); flash('Login berhasil!', 'success')
            if user.role == 'admin': return redirect(url_for('dashboard'))
            else: return redirect(url_for('panitia_dashboard'))
        else:
            flash('Login gagal. Cek Nomor HP/Email dan Password, atau Anda tidak punya hak akses.', 'danger')
    return render_template('login_web.html')

@app.route('/logout')
@login_required
def web_logout():
    logout_user(); flash('Anda telah logout.', 'success'); return redirect(url_for('web_login'))

@app.route('/')
@login_required
@role_required(['admin'])
def dashboard():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)
    search = request.args.get('search', '')

    query = Event.query.filter_by(is_archived=False)

    if search:
        query = query.filter(Event.title.ilike(f'%{search}%'))

    pagination = query.order_by(Event.tgl_mulai_event.asc()).paginate(page=page, per_page=per_page, error_out=False)
    
    events = pagination.items
    
    for event in events: 
        event.registered_count = Ticket.query.filter_by(event_id=event.id).count()

    return render_template(
        'dashboard.html', 
        events=events, 
        pagination=pagination,
        current_search=search,
        current_per_page=per_page
    )

@app.route('/archive')
@login_required
@role_required(['admin'])
def archived_events_list():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)
    search = request.args.get('search', '')

    query = Event.query.filter_by(is_archived=True)

    if search:
        query = query.filter(Event.title.ilike(f'%{search}%'))

    pagination = query.order_by(Event.tgl_mulai_event.desc()).paginate(page=page, per_page=per_page, error_out=False)
    
    events = pagination.items

    return render_template(
        'archive_list.html', 
        events=events, 
        pagination=pagination,
        current_search=search,
        current_per_page=per_page
    )

@app.route('/event/<int:event_id>/archive', methods=['POST'])
@login_required
@role_required(['admin'])
def archive_event(event_id):
    event = Event.query.get_or_404(event_id)
    event.is_archived = True
    db.session.commit()
    flash(f"Event '{event.title}' telah diarsipkan.", "success")
    return redirect(url_for('dashboard'))

@app.route('/event/<int:event_id>/unarchive', methods=['POST'])
@login_required
@role_required(['admin'])
def unarchive_event(event_id):
    event = Event.query.get_or_404(event_id)
    event.is_archived = False
    db.session.commit()
    flash(f"Event '{event.title}' telah dikembalikan.", "success")
    return redirect(url_for('archived_events_list'))

@app.route('/events/bulk-archive', methods=['POST'])
@login_required
@role_required(['admin'])
def bulk_archive():
    event_ids = request.form.getlist('event_ids')
    
    if not event_ids:
        flash('Tidak ada event yang dipilih.', 'warning')
        return redirect(url_for('dashboard'))

    try:
        Event.query.filter(Event.id.in_(event_ids)).update({Event.is_archived: True}, synchronize_session=False)
        db.session.commit()
        flash(f'{len(event_ids)} event berhasil diarsipkan.', 'success')
    except Exception as e:
        db.session.rollback()
        flash('Terjadi kesalahan saat mengarsipkan event.', 'danger')

    return redirect(url_for('dashboard'))

@app.route('/events/bulk-unarchive', methods=['POST'])
@login_required
@role_required(['admin'])
def bulk_unarchive():
    event_ids = request.form.getlist('event_ids')
    
    if not event_ids:
        flash('Tidak ada event yang dipilih.', 'warning')
        return redirect(url_for('archived_events_list'))

    try:
        Event.query.filter(Event.id.in_(event_ids)).update({Event.is_archived: False}, synchronize_session=False)
        db.session.commit()
        flash(f'{len(event_ids)} event berhasil dikembalikan.', 'success')
    except Exception as e:
        db.session.rollback()
        flash('Terjadi kesalahan saat mengembalikan event.', 'danger')

    return redirect(url_for('archived_events_list'))

@app.route('/event/new', methods=['GET', 'POST'])
@login_required
@role_required(['admin'])
def new_event():
    if request.method == 'POST':
        file = request.files['gambar_event']
        filename = None
        if file and file.filename != '' and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
        
        is_umkm_required = request.form.get('is_umkm_data_required') == 'on'
        
        notif_title = request.form.get('notif_title')
        notif_body = request.form.get('notif_body')
        event_name = request.form.get('nama_event')
        def convert_to_utc_naive(form_time_string):
            if not form_time_string: return None
            dt_naive_wib = datetime.strptime(form_time_string, '%Y-%m-%dT%H:%M')
            dt_aware_wib = LOCAL_TZ.localize(dt_naive_wib)
            return dt_aware_wib.astimezone(pytz.utc).replace(tzinfo=None)

        tgl_buka_utc = convert_to_utc_naive(request.form.get('tgl_buka'))
        tgl_tutup_utc = convert_to_utc_naive(request.form.get('tgl_tutup'))
        tgl_mulai_utc = convert_to_utc_naive(request.form.get('tgl_mulai'))
        tgl_selesai_utc = convert_to_utc_naive(request.form.get('tgl_selesai'))

        has_test = request.form.get('has_pre_post_test') == 'on'

        event_baru = Event(
            sifat_pelatihan=request.form.get('sifat_pelatihan'), title=request.form.get('nama_event'),
            jenis_event=request.form.get('jenis_event'), tempat_event=request.form.get('tempat_event'),
            pic_event=request.form.get('pic_event'), narasumber=request.form.get('narasumber'),
            slot_peserta=int(request.form.get('slot_peserta')), description=request.form.get('deskripsi_event'),
            price=int(request.form.get('pembayaran', 0)), image_filename=filename,
            tgl_buka_pendaftaran = tgl_buka_utc,
            tgl_tutup_pendaftaran = tgl_tutup_utc,
            tgl_mulai_event = tgl_mulai_utc,
            tgl_selesai_event = tgl_selesai_utc,
            is_umkm_data_required=is_umkm_required,
            online_event_url=request.form.get('online_event_url'),
            has_pre_post_test=has_test
        )
        db.session.add(event_baru); db.session.commit()

        if has_test:
            save_event_questions(event_baru.id, request.form)

        if notif_title: 
            
            body_to_send = notif_body
            if not body_to_send:
                body_to_send = f"Jangan ketinggalan: {event_name}"

            print(f"Event baru dibuat (ID: {event_baru.id}), mengirim notifikasi kustom...")
            send_broadcast_notification(
                title=notif_title,
                body=body_to_send,
                event_id=event_baru.id
            )

        return redirect(url_for('dashboard'))
    return render_template('create_event.html')

@app.route('/event/<int:event_id>/edit', methods=['GET', 'POST'])
@login_required
@role_required(['admin'])
def edit_event(event_id):
    event = Event.query.get_or_404(event_id)
    if request.method == 'POST':
        def convert_to_utc_naive(form_time_string):
            if not form_time_string: return None
            dt_naive_wib = datetime.strptime(form_time_string, '%Y-%m-%dT%H:%M')
            dt_aware_wib = LOCAL_TZ.localize(dt_naive_wib)
            return dt_aware_wib.astimezone(pytz.utc).replace(tzinfo=None)
        
        event.sifat_pelatihan = request.form.get('sifat_pelatihan'); event.title = request.form.get('nama_event')
        event.jenis_event = request.form.get('jenis_event'); event.tempat_event = request.form.get('tempat_event')
        event.pic_event = request.form.get('pic_event'); event.narasumber = request.form.get('narasumber')
        event.description = request.form.get('deskripsi_event'); event.slot_peserta = int(request.form.get('slot_peserta'))
        event.price = int(request.form.get('pembayaran', 0))
        event.tgl_buka_pendaftaran = convert_to_utc_naive(request.form.get('tgl_buka'))
        event.tgl_tutup_pendaftaran = convert_to_utc_naive(request.form.get('tgl_tutup'))
        event.tgl_mulai_event = convert_to_utc_naive(request.form.get('tgl_mulai'))
        event.tgl_selesai_event = convert_to_utc_naive(request.form.get('tgl_selesai'))
        event.online_event_url = request.form.get('online_event_url')
        event.is_umkm_data_required = request.form.get('is_umkm_data_required') == 'on'
        has_test = request.form.get('has_pre_post_test') == 'on'
        event.has_pre_post_test = has_test

        if has_test:
            save_event_questions(event.id, request.form)
        else:
            EventQuestion.query.filter_by(event_id=event.id).delete()
        
        file = request.files['gambar_event']
        if file and file.filename != '' and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            file.save(os.path.join(app.config['UPLOAD_FOLDER'], filename))
            event.image_filename = filename
            
        db.session.commit()
        return redirect(url_for('dashboard'))
    
    def convert_to_wib_string(utc_naive_dt):
        if not utc_naive_dt: return ""
        dt_aware_utc = pytz.utc.localize(utc_naive_dt)
        dt_aware_wib = dt_aware_utc.astimezone(LOCAL_TZ)
        return dt_aware_wib.strftime('%Y-%m-%dT%H:%M')
    event_wib = {
        'tgl_buka': convert_to_wib_string(event.tgl_buka_pendaftaran),
        'tgl_tutup': convert_to_wib_string(event.tgl_tutup_pendaftaran),
        'tgl_mulai': convert_to_wib_string(event.tgl_mulai_event),
        'tgl_selesai': convert_to_wib_string(event.tgl_selesai_event),
    }
    return render_template('edit_event.html', event=event, event_wib=event_wib)

@app.route('/event/<int:event_id>')
@login_required
@role_required(['admin'])
def event_detail(event_id):
    event = Event.query.get_or_404(event_id); tickets = Ticket.query.filter_by(event_id=event_id).all()
    event.registered_count = len(tickets); event.checked_in_count = Ticket.query.filter_by(event_id=event_id, is_checked_in=True).count()
    return render_template('event_detail.html', event=event, tickets=tickets)

@app.route('/panitia/dashboard')
@login_required
@role_required(['panitia', 'admin'])
def panitia_dashboard():
    now_utc = datetime.utcnow()
    today_start = datetime.combine(now_utc.date(), time.min)
    today_end = datetime.combine(now_utc.date(), time.max)
    
    events = Event.query.filter(
        Event.tgl_mulai_event >= today_start,
        Event.tgl_mulai_event <= today_end,
        Event.is_archived == False
    ).order_by(Event.tgl_mulai_event.asc()).all()
    
    return render_template('panitia_dashboard.html', events=events, now=now_utc, timedelta=timedelta)

@app.route('/event/<int:event_id>/scanner')
@login_required
@role_required(['admin', 'panitia'])
def event_scanner(event_id):
    event = Event.query.get_or_404(event_id)
    
    now_utc = datetime.utcnow()
    start_window = event.tgl_mulai_event - timedelta(hours=3)
    
    if now_utc < start_window and current_user.role != 'admin':
        flash("Check-in baru bisa dilakukan 3 jam sebelum acara.", "warning")
        return redirect(url_for('panitia_dashboard'))
        
    return render_template('scanner.html', event=event)

@app.route('/reports')
@login_required
@role_required(['admin'])
def reports():
    """Halaman Laporan Bulanan yang Dapat Disortir."""
    
    now = datetime.utcnow()
    try:
        selected_month = int(request.args.get('month', now.month))
        selected_year = int(request.args.get('year', now.year))
    except ValueError:
        selected_month = now.month
        selected_year = now.year
        
    sort_by = request.args.get('sort_by', 'date') 
    order = request.args.get('order', 'asc')
    
    events_in_month = Event.query.filter(
        extract('year', Event.tgl_mulai_event) == selected_year,
        extract('month', Event.tgl_mulai_event) == selected_month
    ).all()
    
    event_data = []
    for event in events_in_month:
        reg_count = Ticket.query.filter_by(event_id=event.id).count()
        check_count = Ticket.query.filter_by(event_id=event.id, is_checked_in=True).count()
        rate = (check_count / reg_count) * 100 if reg_count > 0 else 0
            
        event_data.append({
            'event': event,
            'registered': reg_count,
            'checked_in': check_count,
            'rate': rate
        })

    reverse = (order == 'desc')
    if sort_by == 'registered':
        key_func = lambda x: x['registered']
    elif sort_by == 'checked_in':
        key_func = lambda x: x['checked_in']
    elif sort_by == 'rate':
        key_func = lambda x: x['rate']
    else:
        key_func = lambda x: x['event'].tgl_mulai_event
        
    sorted_data = sorted(event_data, key=key_func, reverse=reverse)
    
    chart_labels = [data['event'].title for data in sorted_data]
    
    if sort_by == 'checked_in':
        chart_values = [data['checked_in'] for data in sorted_data]
        chart_title = 'Peserta Hadir'
    elif sort_by == 'rate':
        chart_values = [round(data['rate'], 1) for data in sorted_data]
        chart_title = 'Tingkat Kehadiran (%)'
    else:
        chart_values = [data['registered'] for data in sorted_data]
        chart_title = 'Peserta Terdaftar'
    
    months = [
        (1, 'Januari'), (2, 'Februari'), (3, 'Maret'), (4, 'April'),
        (5, 'Mei'), (6, 'Juni'), (7, 'Juli'), (8, 'Agustus'),
        (9, 'September'), (10, 'Oktober'), (11, 'November'), (12, 'Desember')
    ]
    years = range(now.year - 3, now.year + 2) 

    return render_template(
        'reports.html',
        event_data=sorted_data,
        months=months,
        years=years,
        selected_month=selected_month,
        selected_year=selected_year,
        current_sort_by=sort_by,
        current_order=order,
        
        chart_labels=chart_labels,
        chart_values=chart_values,
        chart_title=chart_title
    )

def serialize_business(business):
    if not business:
        return None
    
    marketplace = business.marketplaces.first()
    license = business.licenses.first()
    finance = business.finances.first()
    npwp = business.npwps.first()
    funding = business.fundings.first()

    return {
        'business_name': business.business_name,
        'business_type': business.business_type,
        
        'address_same_as_home': business.address_same_as_home,
        'address_province': business.address_province,
        'address_city': business.address_city,
        'address_district': business.address_district,
        'address_village': business.address_village,
        'address_rt': business.address_rt,
        'address_rw': business.address_rw,
        'address_postal_code': business.address_postal_code,
        'address_detail': business.address_detail,
        'premise_status': business.premise_status,

        'has_license': business.has_license,
        'legal_entity': business.legal_entity,
        'has_npwp': business.has_npwp,
        'financial_report_type': business.financial_report_type,
        'financial_report_app': business.financial_report_app,
        'report_laba_rugi': business.report_laba_rugi,
        'report_neraca': business.report_neraca,
        'report_arus_kas': business.report_arus_kas,
        'has_funding': business.has_funding,

        'business_phone': business.business_phone,
        'business_email': business.business_email,
        'operating_since': business.operating_since,

        'marketplace_type': marketplace.marketplace_type if marketplace else None,
        'url': marketplace.url if marketplace else None,
        
        'license_type': license.license_type if license else None,
        'license_number': license.license_number if license else None,
        
        'finance_year': finance.year if finance else None,
        'omzet_range': finance.omzet_range if finance else None,
        'profit': finance.profit if finance else None,
        'asset_value': finance.asset_value if finance else None,
        'employee_count': finance.employee_count if finance else None,
        
        'npwp_number': npwp.npwp_number if npwp else None,
        'report_receipt_number': npwp.report_receipt_number if npwp else None,
        'npwp_year': npwp.year if npwp else None,
        'submission_date': npwp.submission_date if npwp else None,
        
        'funder_type': funding.funder_type if funding else None,
        'funder_name': funding.funder_name if funding else None,
        'amount': funding.amount if funding else None,
        'received_date': funding.received_date if funding else None,
        'installment_start_date': funding.installment_start_date if funding else None,
        'duration_months': funding.duration_months if funding else None,
    }

@app.route('/api/public/download/apk', methods=['GET'])
def public_download_apk():
    """
    Endpoint PUBLIK untuk mendownload APK terbaru.
    """
    try:
        apk_directory = os.path.join(app.root_path, 'static', 'apk')
        filename = 'OK OCE.apk'

        return send_from_directory(
            directory=apk_directory,
            path=filename,
            as_attachment=True, 
            download_name='OKOCE.apk'
        )
    except Exception as e:
        return jsonify({'status': 'error', 'message': 'File APK belum tersedia di server.'}), 404
    
@app.route('/reports/download')
@login_required
@role_required(['admin'])
def download_monthly_report():
    now = datetime.utcnow()
    try:
        selected_month = int(request.args.get('month', now.month))
        selected_year = int(request.args.get('year', now.year))
    except ValueError:
        selected_month = now.month
        selected_year = now.year

    events_in_month = Event.query.filter(
        extract('year', Event.tgl_mulai_event) == selected_year,
        extract('month', Event.tgl_mulai_event) == selected_month
    ).order_by(Event.tgl_mulai_event.asc()).all()

    si = io.StringIO()
    writer = csv.writer(si)
    
    writer.writerow(['No', 'Nama Event', 'Tanggal Mulai', 'Lokasi', 'Kuota', 'Terdaftar', 'Hadir (Check-in)', 'Persentase Kehadiran (%)'])

    for i, event in enumerate(events_in_month, 1):
        reg_count = Ticket.query.filter_by(event_id=event.id).count()
        check_count = Ticket.query.filter_by(event_id=event.id, is_checked_in=True).count()
        rate = (check_count / reg_count) * 100 if reg_count > 0 else 0
        
        dt_aware_utc = pytz.utc.localize(event.tgl_mulai_event)
        dt_aware_wib = dt_aware_utc.astimezone(LOCAL_TZ)
        date_str = dt_aware_wib.strftime('%d-%m-%Y %H:%M')

        writer.writerow([
            i,
            event.title,
            date_str,
            event.tempat_event,
            event.slot_peserta,
            reg_count,
            check_count,
            f"{rate:.1f}"
        ])

    output = si.getvalue()
    si.close()
    
    filename = f"Laporan_Bulanan_{selected_month}_{selected_year}.csv"
    
    return Response(
        output,
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment;filename={filename}"}
    )

@app.route('/api/admin/user/<int:user_id>/details')
@login_required
@role_required(['admin'])
def get_user_details_admin(user_id):
    user = User.query.get_or_404(user_id)
    business_data = serialize_business(user.businesses.first()) 

    event_id = request.args.get('event_id')
    test_data = None
    
    if event_id:
        score = UserTestScore.query.filter_by(user_id=user_id, event_id=event_id).first()
        if score:
            test_data = {
                'pre_test': score.pre_test_score,
                'post_test': score.post_test_score
            }
    
    user_data = {
        'name': user.name,
        'phone_number': user.phone_number,
        'email': user.email,
        'province': user.province,
        'city': user.city,
        'institution': user.institution,
        'okoce_id': user.okoce_id,
        'has_business_flag': user.has_business,
        'business_profile': business_data,
        'test_scores': test_data
    }
    return jsonify(user_data)

@app.route('/event/<int:event_id>/download-csv', methods=['POST'])
@login_required
@role_required(['admin'])
def download_csv(event_id):
    event = Event.query.get_or_404(event_id)
    
    selected_columns = request.form.getlist('columns')
    if not selected_columns:
        flash("Anda harus memilih setidaknya satu kolom.", "warning")
        return redirect(url_for('event_detail', event_id=event_id))

    tickets = Ticket.query.filter_by(event_id=event_id).all()
    
    si = io.StringIO()
    writer = csv.writer(si)
    writer.writerow(selected_columns)
    
    for ticket in tickets:
        user = ticket.user
        check_in = ticket.check_ins[0] if ticket.check_ins else None
        business = user.businesses.first()
        marketplace = business.marketplaces.first() if business else None
        license = business.licenses.first() if business else None
        finance = business.finances.first() if business else None
        npwp = business.npwps.first() if business else None
        funding = business.fundings.first() if business else None
        score = UserTestScore.query.filter_by(user_id=user.id, event_id=event_id).first()
        
        row = []
        for col_name in selected_columns:
            if col_name == 'Nama Peserta': row.append(user.name)
            elif col_name == 'OK OCE ID': row.append(user.okoce_id)
            elif col_name == 'No. HP': row.append(user.phone_number)
            elif col_name == 'Email': row.append(user.email)
            elif col_name == 'Provinsi': row.append(user.province)
            elif col_name == 'Kota': row.append(user.city)
            elif col_name == 'Instansi': row.append(user.institution)
            elif col_name == 'Status Hadir': row.append("Hadir" if ticket.is_checked_in else "Belum Hadir")
            elif col_name == 'Waktu Check-in': row.append(check_in.timestamp.strftime('%Y-%m-%d %H:%M:%S') if check_in else '-')
            elif col_name == 'Nilai Pre-Test': row.append(score.pre_test_score if score and score.pre_test_score is not None else '-')
            elif col_name == 'Nilai Post-Test': row.append(score.post_test_score if score and score.post_test_score is not None else '-')
            elif col_name == 'Nama Bisnis': row.append(business.business_name if business else '-')
            elif col_name == 'Jenis Bisnis': row.append(business.business_type if business else '-')
            elif col_name == 'Provinsi Bisnis': row.append(business.address_province if business else '-')
            elif col_name == 'Kota Bisnis': row.append(business.address_city if business else '-')
            elif col_name == 'Kecamatan Bisnis': row.append(business.address_district if business else '-')
            elif col_name == 'Kelurahan Bisnis': row.append(business.address_village if business else '-')
            elif col_name == 'Status Tempat': row.append(business.premise_status if business else '-')
            elif col_name == 'Badan Usaha': row.append(business.legal_entity if business else '-')
            elif col_name == 'No. HP Bisnis': row.append(business.business_phone if business else '-')
            elif col_name == 'Email Bisnis': row.append(business.business_email if business else '-')
            elif col_name == 'Mulai Beroperasi': row.append(business.operating_since if business else '-')
            elif col_name == 'Marketplace': row.append(marketplace.marketplace_type if marketplace else '-')
            elif col_name == 'URL Marketplace': row.append(marketplace.url if marketplace else '-')
            elif col_name == 'Jenis Izin': row.append(license.license_type if license else '-')
            elif col_name == 'Nomor Izin': row.append(license.license_number if license else '-')
            elif col_name == 'Tahun Data Keuangan': row.append(finance.year if finance else '-')
            elif col_name == 'Omzet Tahunan': row.append(finance.omzet_range if finance else '-')
            elif col_name == 'Profit': row.append(finance.profit if finance else '-')
            elif col_name == 'Aset': row.append(finance.asset_value if finance else '-')
            elif col_name == 'Jumlah Karyawan': row.append(finance.employee_count if finance else '-')
            elif col_name == 'Nomor NPWP': row.append(npwp.npwp_number if npwp else '-')
            elif col_name == 'Jenis Pemodal': row.append(funding.funder_type if funding else '-')
            elif col_name == 'Nama Pemodal': row.append(funding.funder_name if funding else '-')
            elif col_name == 'Jumlah Modal': row.append(funding.amount if funding else '-')
            else:
                row.append('-')
        
        writer.writerow(row)
    
    output = si.getvalue()
    si.close()
    
    return Response(
        output,
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment;filename=peserta_event_{event.id}.csv"}
    )

@app.cli.command("init-db")
def init_db_command():
    """Membersihkan dan membuat ulang skema database."""
    db.drop_all()
    db.create_all()
    print("----------------------------------------")
    print("Database schema berhasil dibuat ulang.")
    print("Jalankan 'flask seed-db' untuk mengisi data demo.")
    print("----------------------------------------")

if __name__ == '__main__':
    if not os.path.exists(os.path.join(base_dir, 'instance')): os.makedirs(os.path.join(base_dir, 'instance'))
    if not os.path.exists(UPLOAD_FOLDER): os.makedirs(UPLOAD_FOLDER)
    app.run(debug=True, host='0.0.0.0')

import seed