import os
import cv2
import face_recognition
import numpy as np
import mysql.connector
import uuid
import io
import jwt
import datetime  # Fixed imports
from functools import wraps
from flask import Flask, request, jsonify, send_from_directory, send_file
from flask_cors import CORS
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib import colors
from reportlab.lib.units import inch

# ================= CONFIGURATION ==================
KNOWN_FACES_ROOT = "known_faces"
DETECTED_FACES_DIR = "detected_faces"
UPLOADS_DIR = "uploads"

os.makedirs(KNOWN_FACES_ROOT, exist_ok=True)
os.makedirs(DETECTED_FACES_DIR, exist_ok=True)
os.makedirs(UPLOADS_DIR, exist_ok=True)

app = Flask(__name__)
app.config['SECRET_KEY'] = 'my_secret_startup_key'
CORS(app)


# ================= AUTH MIDDLEWARE =================
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({'message': 'Token is missing!'}), 401
        try:
            token = token.split(" ")[1]  # Bearer <token>
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
            current_user = data
        except Exception as e:
            return jsonify({'message': 'Token is invalid!'}), 401
        return f(current_user, *args, **kwargs)

    return decorated


# ================= DATABASE CONNECTION ==================
def get_connection():
    # Ensure database name is correct
    return mysql.connector.connect(
        host="localhost", user="root", password="Sahil12@", database="attendance_new"
    )


def init_db():
    # 1. DB Create Check
    try:
        conn_server = mysql.connector.connect(host="localhost", user="root", password="Sahil12@")
        cur_server = conn_server.cursor()
        cur_server.execute("CREATE DATABASE IF NOT EXISTS attendance_new")
        conn_server.close()
    except Exception as e:
        print(f"Error checking DB: {e}")

    conn = get_connection()
    cur = conn.cursor()

    # 2. Tables Create
    # Organizations Table
    cur.execute("""
        CREATE TABLE IF NOT EXISTS organizations (
            org_id INT AUTO_INCREMENT PRIMARY KEY,
            org_name VARCHAR(100) NOT NULL
        )
    """)

    # Users Table (YE MISSING THA)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            user_id INT AUTO_INCREMENT PRIMARY KEY,
            org_id INT,
            name VARCHAR(100),
            email VARCHAR(100) UNIQUE NOT NULL,
            password VARCHAR(255) NOT NULL,
            role VARCHAR(20) DEFAULT 'Teacher',
            FOREIGN KEY (org_id) REFERENCES organizations(org_id)
        )
    """)

    # Students Table
    cur.execute("""
        CREATE TABLE IF NOT EXISTS students (
            id INT AUTO_INCREMENT PRIMARY KEY,
            org_id INT,
            name VARCHAR(255) NOT NULL,
            roll_number VARCHAR(50),
            class_name VARCHAR(50),
            phone_number VARCHAR(20),
            photo_path VARCHAR(255)
        )
    """)

    # Attendance Table
    cur.execute("""
        CREATE TABLE IF NOT EXISTS attendance_new (
            id INT AUTO_INCREMENT PRIMARY KEY,
            org_id INT,
            session_id VARCHAR(100),
            name VARCHAR(255),
            status VARCHAR(50),
            confidence FLOAT,
            face_img_path VARCHAR(255),
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 3. Default Admin User Insert (Auto-create if not exists)
    cur.execute("SELECT * FROM users WHERE email = 'sahil@bncet.in'")
    if not cur.fetchone():
        # Pehle Org ensure karein
        cur.execute("INSERT IGNORE INTO organizations (org_id, org_name) VALUES (1, 'BNCET College')")
        # Phir User banayein
        cur.execute(
            "INSERT INTO users (org_id, name, email, password, role) VALUES (1, 'Sahil Sir', 'sahil@bncet.in', '12345', 'Admin')")
        print("✅ Default User Created: sahil@bncet.in / 12345")

    conn.commit()
    conn.close()

# ================= API ENDPOINTS ==================

# --- 1. LOGIN API ---
@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    conn = get_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT * FROM users WHERE email=%s AND password=%s", (data.get('email'), data.get('password')))
    user = cur.fetchone()
    conn.close()

    if user:
        token = jwt.encode({
            'user_id': user['user_id'],
            'org_id': user['org_id'],
            'exp': datetime.datetime.utcnow() + datetime.timedelta(days=7)
        }, app.config['SECRET_KEY'], algorithm="HS256")
        return jsonify({'token': token, 'org_id': user['org_id']})

    return jsonify({'message': 'Invalid Credentials'}), 401


# --- 2. REGISTER (SaaS Fixed) ---
@app.route('/api/register', methods=['POST'])
# @token_required  # <--- FIXED: Now requires Login
def register_student():
    org_id = "1" # Hardcoded for testing since we removed token_required

    name = request.form.get('name')
    roll = request.form.get('roll_number')
    class_name = request.form.get('class_name')
    phone = request.form.get('phone')
    file = request.files.get('photo')

    if not all([name, roll, class_name, file]):
        return jsonify({"error": "Missing data"}), 400

    # Folder Structure: known_faces / ORG_ID / CLASS_NAME
    org_class_dir = os.path.join(KNOWN_FACES_ROOT, org_id, class_name)
    os.makedirs(org_class_dir, exist_ok=True)

    clean_name = f"{name}_{roll}".replace(" ", "_")
    filename = f"{clean_name}.jpg"
    save_path = os.path.join(org_class_dir, filename)
    file.save(save_path)

    conn = get_connection()
    cur = conn.cursor()
    try:
        # Delete old record for THIS Org
        cur.execute("DELETE FROM students WHERE name=%s AND org_id=%s", (clean_name, org_id))

        # Insert with Org ID
        cur.execute("""
            INSERT INTO students (org_id, name, roll_number, class_name, phone_number, photo_path) 
            VALUES (%s, %s, %s, %s, %s, %s)
        """, (org_id, clean_name, roll, class_name, phone, save_path))
        conn.commit()
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        conn.close()

    return jsonify({"message": "Student Registered successfully!"})


# --- 3. DETECT FACES (Fixed) ---
@app.route('/api/detect', methods=['POST'])
# @token_required
def detect_faces():
    org_id = "1" # Hardcoded for testing since we removed token_required

    if 'image' not in request.files: return jsonify({"error": "No image"}), 400
    file = request.files['image']
    target_class = request.form.get('class_name')
    session_id = request.form.get('session_id')
    if not session_id or session_id == "null": session_id = str(uuid.uuid4())

    # Load Faces (Org Specific)
    known_encodings = []
    known_names = []

    target_dir = os.path.join(KNOWN_FACES_ROOT, org_id, target_class)

    if os.path.exists(target_dir):
        for filename in os.listdir(target_dir):
            if filename.endswith(('.jpg', '.png')):
                try:
                    img = face_recognition.load_image_file(os.path.join(target_dir, filename))
                    encs = face_recognition.face_encodings(img)
                    if encs:
                        known_encodings.append(encs[0])
                        known_names.append(os.path.splitext(filename)[0])
                except:
                    pass

    print(f"Loaded {len(known_names)} faces for Org {org_id}")

    # Process Image
    input_path = os.path.join(UPLOADS_DIR, f"{session_id}.jpg")
    file.save(input_path)
    img = cv2.imread(input_path)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    # Upsample = 2 for better small face detection
    locs = face_recognition.face_locations(rgb, number_of_times_to_upsample=2, model="hog")
    encs = face_recognition.face_encodings(rgb, locs)

    conn = get_connection()
    cur = conn.cursor()
    new_count = 0

    for (top, right, bottom, left), enc in zip(locs, encs):
        name = "Unknown"
        confidence = 0.0

        if len(known_encodings) > 0:
            matches = face_recognition.compare_faces(known_encodings, enc, tolerance=0.50)
            dists = face_recognition.face_distance(known_encodings, enc)
            if True in matches:
                best_idx = np.argmin(dists)
                if matches[best_idx]:
                    name = known_names[best_idx]
                    confidence = round((1 - dists[best_idx]) * 100, 2)

        # Crop
        face_filename = f"face_{name}_{uuid.uuid4().hex[:6]}.jpg"
        h, w, _ = img.shape
        # Add margin
        top = max(0, top - 20);
        bottom = min(h, bottom + 20)
        left = max(0, left - 20);
        right = min(w, right + 20)

        try:
            cv2.imwrite(os.path.join(DETECTED_FACES_DIR, face_filename), img[top:bottom, left:right])
        except:
            pass

        status = "Present" if name != "Unknown" else "Unknown"

        try:
            # Fixed SQL Insert (Includes Org ID)
            cur.execute("""
                INSERT INTO attendance_new (org_id, session_id, name, status, confidence, face_img_path)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (org_id, session_id, name, status, confidence, face_filename))

            if cur.rowcount > 0 and name != "Unknown":
                new_count += 1
        except Exception as e:
            print(e)

    conn.commit()

    cur.execute(
        "SELECT name, status, confidence, face_img_path, id FROM attendance_new WHERE session_id = %s AND org_id = %s",
        (session_id, org_id))
    rows = cur.fetchall()
    conn.close()

    results = []
    for r in rows:
        results.append({
            "name": r[0],
            "status": r[1],
            "confidence": r[2],
            "face_url": f"http://{request.host}/static/faces/{r[3]}",
            "id": r[4]
        })

    return jsonify({"summary": {"new_in_this_shot": new_count, "session_id": session_id}, "details": results})


# --- 4. UPDATE RECORD ---
@app.route('/api/update_record', methods=['POST'])
# @token_required
def update_record():
    org_id = "1" # Hardcoded for testing since we removed token_required
    data = request.json
    # Validation
    if not data or 'id' not in data:
        return jsonify({"message": "ID required"}), 400

    conn = get_connection()
    cur = conn.cursor()

    # Secure Update (Checks Org ID)
    cur.execute("""
        UPDATE attendance_new SET name=%s, status=%s 
        WHERE id=%s AND org_id=%s
    """, (data.get('name'), data.get('status'), data.get('id'), org_id))

    conn.commit()
    conn.close()
    return jsonify({"message": "Record Updated Successfully"})


@app.route('/api/classes', methods=['GET'])
def get_classes():
    return jsonify(["Computer Science - Year 3", "Mechanical - Year 2", "Civil - Year 4", "MBA - Year 1"])


# ================= EXPORT PDF API (Structured Report) =================
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet


@app.route('/api/export_pdf', methods=['GET'])
def generate_pdf():
    session_id = request.args.get('session_id')

    # Database connection
    conn = get_connection()
    cur = conn.cursor()

    # Data Fetching Logic
    if session_id and session_id != 'null':
        cur.execute("SELECT name, status, timestamp FROM attendance_new WHERE session_id = %s", (session_id,))
    else:
        # Agar session ID nahi hai to aaj ka data nikalo
        cur.execute("SELECT name, status, timestamp FROM attendance_new WHERE DATE(timestamp) = CURDATE()")

    rows = cur.fetchall()
    conn.close()

    # PDF Setup
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter)
    elements = []

    # Styles
    styles = getSampleStyleSheet()
    title_style = styles['Title']
    meta_style = styles['Normal']

    # 1. Title Section
    elements.append(Paragraph("Class Attendance Report", title_style))
    elements.append(Spacer(1, 10))

    # 2. Metadata Section (Session ID & Date)
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    elements.append(Paragraph(f"<b>Session ID:</b> {session_id}", meta_style))
    elements.append(Paragraph(f"<b>Generated On:</b> {current_time}", meta_style))
    elements.append(Spacer(1, 15))

    # 3. Table Header & Data
    # Header Row
    table_data = [['S.No', 'Student Name', 'Status', 'Timestamp']]

    # Data Rows Loop
    for i, row in enumerate(rows, start=1):
        name = row[0]
        status = row[1]
        timestamp = str(row[2])  # Datetime ko string bana rahe hain
        table_data.append([str(i), name, status, timestamp])

    # 4. Table Styling (Professional Look)
    # Column Widths adjust kiye hain taaki page par fit ho
    col_widths = [0.6 * inch, 3.0 * inch, 1.2 * inch, 2.0 * inch]

    t = Table(table_data, colWidths=col_widths)

    # Style Define
    style = TableStyle([
        # Header Style (Navy Blue Background, White Text)
        ('BACKGROUND', (0, 0), (-1, 0), colors.navy),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 12),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 10),
        ('TOPPADDING', (0, 0), (-1, 0), 10),

        # Grid Lines (Black Borders)
        ('GRID', (0, 0), (-1, -1), 1, colors.black),

        # Content Style
        ('FONTNAME', (0, 1), (-1, -1), 'Helvetica'),
        ('FONTSIZE', (0, 1), (-1, -1), 10),
        ('ALIGN', (0, 1), (-1, -1), 'CENTER'),  # Center align all data
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ])

    # 5. Conditional Coloring (Green for Present, Red for Unknown/Absent)
    # Row 1 se shuru karenge kyunki Row 0 Header hai
    for i, row in enumerate(table_data[1:], start=1):
        status_text = row[2].lower()
        if "present" in status_text:
            text_color = colors.green
        else:
            text_color = colors.red  # Unknown ya Absent ke liye Red

        # Sirf 'Status' column (Index 2) ka color badalna hai
        style.add('TEXTCOLOR', (2, i), (2, i), text_color)

    t.setStyle(style)
    elements.append(t)

    # Build PDF
    doc.build(elements)
    buffer.seek(0)

    return send_file(
        buffer,
        as_attachment=True,
        download_name=f"Report_{session_id}.pdf",
        mimetype="application/pdf"
    )
@app.route('/static/faces/<path:filename>')
def serve_faces(filename):
    return send_from_directory(DETECTED_FACES_DIR, filename)


if __name__ == "__main__":
    init_db()  # Initializes DB with org_id columns
    app.run(host="0.0.0.0", port=5000, debug=True)