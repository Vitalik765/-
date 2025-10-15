import os
import sqlite3
import secrets
import string
from datetime import datetime
from functools import wraps

from flask import Flask, render_template, request, redirect, url_for, flash, session, g
from werkzeug.security import generate_password_hash, check_password_hash

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DB_PATH = os.path.join(BASE_DIR, 'app.db')


def create_app():
	app = Flask(__name__)
	app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret-change-me')
	return app


app = create_app()


# --- Database helpers (sqlite3 stdlib) ---

def get_db() -> sqlite3.Connection:
	if 'db' not in g:
		conn = sqlite3.connect(DB_PATH)
		conn.row_factory = sqlite3.Row
		g.db = conn
	return g.db


@app.teardown_appcontext
def close_db(exception=None):
	conn = g.pop('db', None)
	if conn is not None:
		conn.close()


def init_db() -> None:
	conn = get_db()
	conn.execute(
		"""
		CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			email TEXT UNIQUE NOT NULL,
			password_hash TEXT NOT NULL,
			created_at TEXT NOT NULL
		);
		"""
	)
	conn.execute(
		"""
		CREATE TABLE IF NOT EXISTS password_entries (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			user_id INTEGER NOT NULL,
			password_value TEXT NOT NULL,
			length INTEGER NOT NULL,
			use_lower INTEGER NOT NULL,
			use_upper INTEGER NOT NULL,
			use_digits INTEGER NOT NULL,
			use_symbols INTEGER NOT NULL,
			created_at TEXT NOT NULL,
			FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
		);
		"""
	)
	conn.commit()


@app.before_request
def ensure_db():
	init_db()


# --- Auth helpers (session-based) ---

def login_required(view_func):
	@wraps(view_func)
	def wrapper(*args, **kwargs):
		if not session.get('user_id'):
			return redirect(url_for('login'))
		return view_func(*args, **kwargs)
	return wrapper


# --- Password generator ---

def generate_password(length: int, use_lower: bool, use_upper: bool, use_digits: bool, use_symbols: bool) -> str:
	alphabet = ''
	if use_lower:
		alphabet += string.ascii_lowercase
	if use_upper:
		alphabet += string.ascii_uppercase
	if use_digits:
		alphabet += string.digits
	if use_symbols:
		alphabet += '!@#$%^&*()-_=+[]{};:,.<>/?'
	if not alphabet:
		raise ValueError('Нужно выбрать хотя бы один тип символов')
	return ''.join(secrets.choice(alphabet) for _ in range(length))


# --- Routes ---

@app.route('/', methods=['GET', 'POST'])
@login_required
def index():
	generated = None
	if request.method == 'POST':
		try:
			length = int(request.form.get('length', 12))
			use_lower = bool(request.form.get('use_lower'))
			use_upper = bool(request.form.get('use_upper'))
			use_digits = bool(request.form.get('use_digits'))
			use_symbols = bool(request.form.get('use_symbols'))
			if length < 6 or length > 128:
				raise ValueError('Длина должна быть от 6 до 128')
			generated = generate_password(length, use_lower, use_upper, use_digits, use_symbols)
			conn = get_db()
			conn.execute(
				"""
				INSERT INTO password_entries (user_id, password_value, length, use_lower, use_upper, use_digits, use_symbols, created_at)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?)
				""",
				(
					session['user_id'],
					generated,
					length,
					1 if use_lower else 0,
					1 if use_upper else 0,
					1 if use_digits else 0,
					1 if use_symbols else 0,
					datetime.utcnow().isoformat(timespec='seconds'),
				),
			)
			conn.commit()
			flash('Пароль сгенерирован и сохранен в историю', 'success')
		except Exception as e:
			flash(str(e), 'danger')
	return render_template('index.html', generated=generated)


@app.route('/history')
@login_required
def history():
	conn = get_db()
	rows = conn.execute(
		"""
		SELECT password_value, length, use_lower, use_upper, use_digits, use_symbols, created_at
		FROM password_entries
		WHERE user_id = ?
		ORDER BY datetime(created_at) DESC
		LIMIT 100
		""",
		(session['user_id'],),
	).fetchall()
	return render_template('history.html', entries=rows)


@app.route('/register', methods=['GET', 'POST'])
def register():
	if session.get('user_id'):
		return redirect(url_for('index'))
	if request.method == 'POST':
		email = request.form.get('email', '').strip().lower()
		password = request.form.get('password', '')
		password2 = request.form.get('password2', '')
		if not email or not password:
			flash('Введите email и пароль', 'warning')
			return render_template('register.html')
		if password != password2:
			flash('Пароли не совпадают', 'warning')
			return render_template('register.html')
		if len(password) < 6:
			flash('Пароль должен быть не менее 6 символов', 'warning')
			return render_template('register.html')
		conn = get_db()
		row = conn.execute("SELECT id FROM users WHERE email = ?", (email,)).fetchone()
		if row:
			flash('Пользователь с таким email уже существует', 'danger')
			return render_template('register.html')
		password_hash = generate_password_hash(password)
		conn.execute(
			"INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)",
			(email, password_hash, datetime.utcnow().isoformat(timespec='seconds')),
		)
		conn.commit()
		flash('Регистрация успешна. Теперь войдите.', 'success')
		return redirect(url_for('login'))
	return render_template('register.html')


@app.route('/login', methods=['GET', 'POST'])
def login():
	if session.get('user_id'):
		return redirect(url_for('index'))
	if request.method == 'POST':
		email = request.form.get('email', '').strip().lower()
		password = request.form.get('password', '')
		conn = get_db()
		row = conn.execute("SELECT id, email, password_hash FROM users WHERE email = ?", (email,)).fetchone()
		if not row or not check_password_hash(row['password_hash'], password):
			flash('Неверные учетные данные', 'danger')
			return render_template('login.html')
		session['user_id'] = row['id']
		session['user_email'] = row['email']
		return redirect(url_for('index'))
	return render_template('login.html')


@app.route('/logout')
@login_required
def logout():
	session.clear()
	return redirect(url_for('login'))


if __name__ == '__main__':
	port = int(os.environ.get('PORT', 5656))
	app.run(host='0.0.0.0', port=port, debug=True)
