from app import app, db, User, Event, Ticket, CheckIn, LOCAL_TZ, pytz
from app import BusinessProfile, BusinessMarketplace, BusinessLicense, BusinessFinance, BusinessNPWP, BusinessFunding
from app import EventQuestion, UserTestScore 
from datetime import datetime, timedelta, time

@app.cli.command("seed-db")
def seed_db_command():
    """Mengisi database dengan data demo lengkap untuk showcase."""
    
    UserTestScore.query.delete()
    EventQuestion.query.delete()
    CheckIn.query.delete()
    Ticket.query.delete()
    BusinessMarketplace.query.delete()
    BusinessLicense.query.delete()
    BusinessFinance.query.delete()
    BusinessNPWP.query.delete()
    BusinessFunding.query.delete()
    Event.query.delete()
    BusinessProfile.query.delete()
    User.query.delete()
    
    db.session.commit()
    print("Data lama berhasil dibersihkan.")

    user_felix = User(id=1, okoce_id='10000001', name='Felix (Admin)', phone_number='08111111111', email='felix@admin.com', province='DKI JAKARTA', city='KOTA JAKARTA TIMUR', institution='OK OCE', has_business=True, role='admin', is_verified=True)
    user_felix.set_password('123')

    user_dewa = User(id=2, okoce_id='10000002', name='Dewa (Panitia)', phone_number='08222222222', email='dewa@panitia.com', province='JAWA BARAT', city='KOTA BANDUNG', institution='OK OCE', has_business=True, role='panitia', is_verified=True)
    user_dewa.set_password('123')

    user_bayu = User(id=3, okoce_id='10000003', name='Bayu (User Biasa)', phone_number='08333333333', email='bayu@user.com', province='BANTEN', city='KOTA TANGERANG', institution='BINUS', has_business=False, role='user', is_verified=True)
    user_bayu.set_password('123')
    
    user_rayyan = User(id=4, okoce_id='10000004', name='Rayyan (Unverified)', phone_number='08444444444', email='rayyan@unverified.com', province='JAWA TIMUR', city='KOTA SURABAYA', institution='ITS', has_business=False, role='user', is_verified=False, verification_otp='123456', otp_expiry=datetime.utcnow() + timedelta(minutes=10))
    user_rayyan.set_password('123')

    user_citra = User(id=5, okoce_id='10000005', name='Citra (User UMKM)', phone_number='08555555555', email='citra@umkm.com', province='JAWA TENGAH', city='KOTA SEMARANG', institution='UNDIP', has_business=True, role='user', is_verified=True)
    user_citra.set_password('123')

    db.session.add_all([user_felix, user_dewa, user_bayu, user_rayyan, user_citra])
    db.session.commit()
    
    b_felix = BusinessProfile(user_id=1, business_name="Felix Tech Solution", business_type="Teknologi", address_same_as_home=False, address_province="DKI JAKARTA", address_city="KOTA JAKARTA TIMUR", address_district="Cakung", address_village="Jatinegara", address_rt="005", address_rw="010", address_postal_code="13930", address_detail="Jl. Mawar Merah No. 1A", premise_status="Milik Sendiri", legal_entity="Perseorangan", has_license=True, has_npwp=True, financial_report_type='Aplikasi', financial_report_app='Zahir', report_laba_rugi=True, report_neraca=True, report_arus_kas=False, has_funding=True, business_phone='08111111111', business_email='felix@tech.com', operating_since='2023')
    db.session.add(b_felix)
    
    b_citra = BusinessProfile(user_id=5, business_name="Katering Citra Rasa", business_type="Makanan dan Minuman", address_same_as_home=True, premise_status="Sewa", legal_entity="Belum Memiliki", business_phone='08555555555', operating_since='2024')
    db.session.add(b_citra)
    db.session.commit()
    
    db.session.add_all([
        BusinessMarketplace(business_id=b_felix.id, marketplace_type='Website', url='https://felixtech.com'),
        BusinessLicense(business_id=b_felix.id, license_type='NIB', license_number='123456789'),
        BusinessFinance(business_id=b_felix.id, year='2024', omzet_range='< Rp 2.000.000.000', profit=50000000, asset_value=20000000, employee_count='2 - 10 Orang'),
        BusinessNPWP(business_id=b_felix.id, npwp_number='99.888.777.6-543.210', report_receipt_number='BPE123', year='2024', submission_date='2025-03-01'),
        BusinessFunding(business_id=b_felix.id, funder_type='BANK', funder_name='BCA', amount=100000000, received_date='2024-01-01')
    ])
    db.session.add(BusinessFinance(business_id=b_citra.id, year='2024', omzet_range='< Rp 2.000.000.000', employee_count='1 Orang'))
    db.session.commit()

    now_utc = datetime.utcnow()

    event_offline_wajib = Event(
        id=1, sifat_pelatihan='Umum', title='[OFFLINE] Workshop Advanced Funding (Test & Wajib UMKM)', 
        jenis_event='Public', tempat_event='Offline - OK OCE HQ',
        pic_event='Admin', narasumber='Felix', slot_peserta=10, 
        description='Event ini mewajibkan data UMKM dan memiliki Pre-Test & Post-Test.', price=0,
        tgl_buka_pendaftaran=now_utc - timedelta(days=10),
        tgl_tutup_pendaftaran=now_utc + timedelta(days=10),
        tgl_mulai_event=now_utc + timedelta(days=15),
        tgl_selesai_event=now_utc + timedelta(days=15, hours=3),
        is_umkm_data_required=True, 
        has_pre_post_test=True,
        online_event_url=None
    )
    
    event_online_umum = Event(
        id=2, sifat_pelatihan='Wajib', title='[ONLINE] Dasar Digital Marketing', 
        jenis_event='Private', tempat_event='Online',
        pic_event='Admin', narasumber='Bayu', slot_peserta=50, 
        description='Event online untuk semua anggota. Check-in otomatis.', price=0, 
        tgl_buka_pendaftaran=now_utc - timedelta(days=5), 
        tgl_tutup_pendaftaran=now_utc + timedelta(days=5), 
        tgl_mulai_event=now_utc + timedelta(days=7), 
        tgl_selesai_event=now_utc + timedelta(days=7, hours=2), 
        is_umkm_data_required=False, 
        online_event_url='https://zoom.us/j/1234567890'
    )
    
    event_reminder_test = Event(
        id=3, sifat_pelatihan='Umum', title='[DEMO] Event Besok (Test Notif)', 
        jenis_event='Public', tempat_event='Online',
        pic_event='Tester', narasumber='Citra', slot_peserta=5, 
        description='Event ini untuk demo notifikasi H-1.', price=0, 
        tgl_buka_pendaftaran=now_utc - timedelta(days=1), 
        tgl_tutup_pendaftaran=now_utc + timedelta(days=2), 
        tgl_mulai_event=now_utc + timedelta(hours=24, minutes=5), 
        tgl_selesai_event=now_utc + timedelta(hours=27), 
        is_umkm_data_required=False, 
        online_event_url='https://meet.google.com/abc-defg-hij'
    )
    
    event_selesai = Event(
        id=4, sifat_pelatihan='Umum', title='[SELESAI] Pameran Kuliner 2024', 
        jenis_event='Public', tempat_event='Offline - Monas', 
        pic_event='Admin', narasumber='Juri', slot_peserta=10, 
        description='Event ini sudah selesai.', price=0, 
        tgl_buka_pendaftaran=now_utc - timedelta(days=30), 
        tgl_tutup_pendaftaran=now_utc - timedelta(days=20), 
        tgl_mulai_event=now_utc - timedelta(days=10), 
        tgl_selesai_event=now_utc - timedelta(days=10, hours=3), 
        is_umkm_data_required=False
    )

    event_arsip = Event(
        id=5, sifat_pelatihan='Wajib', title='[ARSIP] Rapat Internal Q1', 
        jenis_event='Private', tempat_event='Offline', 
        pic_event='Admin', narasumber='Internal', slot_peserta=10, 
        description='Event ini diarsipkan.', price=0, 
        tgl_buka_pendaftaran=now_utc - timedelta(days=5), 
        tgl_tutup_pendaftaran=now_utc + timedelta(days=5), 
        tgl_mulai_event=now_utc + timedelta(days=10), 
        tgl_selesai_event=now_utc + timedelta(days=10, hours=1), 
        is_umkm_data_required=False, is_archived=True
    )

    db.session.add_all([event_offline_wajib, event_online_umum, event_reminder_test, event_selesai, event_arsip])
    db.session.commit()
    
    t1 = Ticket(user_id=1, event_id=1)
    t2 = Ticket(user_id=3, event_id=2)
    t3 = Ticket(user_id=5, event_id=3)
    t4 = Ticket(user_id=3, event_id=4)
    db.session.add_all([t1, t2, t3, t4])
    db.session.commit()

    c1 = CheckIn(ticket_id=t4.id, timestamp=datetime.utcnow())
    t4.is_checked_in = True
    db.session.add(c1)
    db.session.commit()

    q1 = EventQuestion(event_id=1, question_number=1, question_text="Apa syarat utama mengajukan KUR?", option_a="Punya KTP", option_b="Usaha berjalan min. 6 bulan", option_c="Punya sertifikat rumah", option_d="Punya NPWP", correct_answer="B")
    q2 = EventQuestion(event_id=1, question_number=2, question_text="Berapa bunga KUR Mikro saat ini?", option_a="3%", option_b="6%", option_c="12%", option_d="0%", correct_answer="B")
    q3 = EventQuestion(event_id=1, question_number=3, question_text="Laporan keuangan apa yang wajib ada?", option_a="Hanya Laba Rugi", option_b="Hanya Neraca", option_c="Laba Rugi & Neraca", option_d="Tidak Perlu", correct_answer="C")
    q4 = EventQuestion(event_id=1, question_number=4, question_text="Platform pencatatan keuangan OK OCE adalah?", option_a="Excel", option_b="OK OCE Keuangan", option_c="Zahir / SI APIK", option_d="Buku Tulis", correct_answer="C")
    q5 = EventQuestion(event_id=1, question_number=5, question_text="Siapa target utama pendanaan ini?", option_a="UMKM", option_b="Korporasi", option_c="BUMN", option_d="PNS", correct_answer="A")

    db.session.add_all([q1, q2, q3, q4, q5])
    db.session.commit()

    print("Event demo & Soal Test berhasil dibuat.")
    print("----------------------------------------")
    print("Database seeding selesai!")