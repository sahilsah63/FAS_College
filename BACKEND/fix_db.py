import mysql.connector


def fix_database_schema():
    print("🔧 Database fix start kar raha hu...")

    try:
        # Database se connect karein
        conn = mysql.connector.connect(
            host="localhost",
            user="root",
            password="Sahil12@",
            database="attendance_new"
        )
        cur = conn.cursor()

        # 1. Students table mein org_id add karein
        try:
            print("👉 Checking 'students' table...")
            cur.execute("ALTER TABLE students ADD COLUMN org_id INT DEFAULT 1")
            print("✅ 'org_id' column added to students table.")
        except mysql.connector.Error as e:
            if "Duplicate column" in str(e):
                print("ℹ️ 'org_id' students table mein pehle se hai.")
            else:
                print(f"❌ Error in students table: {e}")

        # 2. Attendance table mein org_id add karein
        try:
            print("👉 Checking 'attendance_new' table...")
            cur.execute("ALTER TABLE attendance_new ADD COLUMN org_id INT DEFAULT 1")
            print("✅ 'org_id' column added to attendance_new table.")
        except mysql.connector.Error as e:
            if "Duplicate column" in str(e):
                print("ℹ️ 'org_id' attendance_new table mein pehle se hai.")
            else:
                print(f"❌ Error in attendance_new table: {e}")

        conn.commit()
        conn.close()
        print("\n🎉 Database fix ho gaya! Ab aap 'new.py' chala sakte hain.")

    except Exception as e:
        print(f"\n❌ Connection Error: {e}")
        print("Check karein ki MySQL chalu hai aur password sahi hai.")


if __name__ == "__main__":
    fix_database_schema()