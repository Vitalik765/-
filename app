from dis import name

from flask import Flask, request, jsonify, session, Response, render_template, url_for, redirect
import secrets
import math
from io import StringIO
import random

def create_app():
    app = Flask(__name__)
    # Секретный ключ для сессий (генерируется при старте; для production замените на постоянный)
    app.config["SECRET_KEY"] = secrets.token_urlsafe(32)
    app.config["SESSION_COOKIE_HTTPONLY"] = True
    app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

    # --- вспомогательные функции ---

    CHARSETS = {
        "lowercase": "abcdefghijklmnopqrstuvwxyz",
        "uppercase": "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        "numbers": "0123456789",
        "symbols": "!@#$%^&*()-_=+[]{};:,.<>/?|~"
    }

    def build_charset(uppercase: bool, lowercase: bool, numbers: bool, symbols: bool) -> str:
        parts = []
        if lowercase:
            parts.append(CHARSETS["lowercase"])
        if uppercase:
            parts.append(CHARSETS["uppercase"])
        if numbers:
            parts.append(CHARSETS["numbers"])
        if symbols:
            parts.append(CHARSETS["symbols"])
        return "".join(parts)

    def calculate_bits(charset_size: int, length: int) -> float:
        if charset_size <= 0 or length <= 0:
            return 0.0
        return length * math.log2(charset_size)

    def score_percent_from_bits(bits: float) -> int:
        """
        Переводим энтропию (bits) в понятный процент:
        - <28 bits  -> слабый
        - 28-35     -> средний
        - 35-59     -> сильный
        - >=60      -> отличный
        Делаем плавную интерполяцию между границами.
        """
        if bits <= 0:
            return 0
        # Плавная шкала: 0..64 бит -> 0..100%
        # Больше 64 бит считаем 100%
        pct = int(min(100, round((bits / 64.0) * 100)))
        return pct

    def generate_password(length: int, uppercase: bool, lowercase: bool, numbers: bool, symbols: bool) -> str:
        charset = build_charset(uppercase, lowercase, numbers, symbols)
        if not charset:
            raise ValueError("no_charsets")

        # Гарантируем, что хотя бы один символ из каждого выбранного класса присутствует
        required_chars = []
        if lowercase:
            required_chars.append(secrets.choice(CHARSETS["lowercase"]))
        if uppercase:
            required_chars.append(secrets.choice(CHARSETS["uppercase"]))
        if numbers:
            required_chars.append(secrets.choice(CHARSETS["numbers"]))
        if symbols:
            required_chars.append(secrets.choice(CHARSETS["symbols"]))

        if length < len(required_chars):
            # Невозможно включить все требуемые классы из-за слишком маленькой длины
            # Решаем: уменьшаем список required_chars до length (оставляем первые)
            required_chars = required_chars[:length]

        # Остальные символы заполняем случайно из полного charset
        remaining_count = length - len(required_chars)
        pwd_chars = required_chars + [secrets.choice(charset) for _ in range(remaining_count)]

        # Перемешиваем надёжно
        sysrand = random.SystemRandom()
        sysrand.shuffle(pwd_chars)

        return "".join(pwd_chars)

    # --- маршруты ---

    def load_students(STUDENTS_FILE=None):
        try:
            with open(STUDENTS_FILE, "r", encoding="utf-8") as f:
                return [line.strip() for line in f if line.strip()]
        except FileNotFoundError:
            return []

    def save_students(students, STUDENTS_FILE=None):
        with open(STUDENTS_FILE, "w", encoding="utf-8") as f:
            for s in students:
                f.write(s + "\n")

    @app.route("/")
    def index():
        students = load_students()
        return render_template("index.html", students=students)

    @app.route("/add", methods=["GET", "POST"])
    def add_student():
        if request.method == "POST":
            name = request.form.get("name")
            students = load_students()
            if name and name not in students:
                students.append(name)
                save_students(students)
            return redirect(url_for("index"))
        return render_template("add_student.html")

    @app.route("/delete", methods=["GET", "POST"])
    def delete_student():
        students = load_students()
        if request.method == "POST":
            name = request.form.get("name")
            if name in students:
                students.remove(name)
                save_students(students)
            return redirect(url_for("index"))
        return render_template("delete_student.html", students=students)

    @app.route("/edit", methods=["GET", "POST"])
    def edit_student():
        students = load_students()
        if request.method == "POST":
            old_name = request.form.get("old_name")
            new_name = request.form.get("new_name")
            if old_name in students and new_name:
                index = students.index(old_name)
                students[index] = new_name
                save_students(students)
            return redirect(url_for("index"))
        return render_template("edit_student.html", students=students)
app = create_app()

if name == "__main__":
    # debug=True только для разработки
    app.run(debug=True, host= '0.0.0.0', port=5000)
