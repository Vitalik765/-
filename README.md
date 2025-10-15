Функции:
- Регистрация и вход пользователей
- Генерация паролей с настройками
- Личная история последних 100 паролей

## Запуск (Windows PowerShell)

```powershell
# 1) Создайте и активируйте виртуальное окружение (по желанию)
python -m venv .venv
. .venv/Scripts/Activate.ps1

# 2) Установите зависимости
pip install -r requirements.txt

# 3) Запустите приложение
$env:FLASK_APP="app.py"
$env:FLASK_ENV="development"
python app.py
```

Откройте `http://127.0.0.1:5000` в браузере.

Логика БД: SQLite файл `app.db` создаётся автоматически при первом запросе.

Переменные окружения (опционально):
- `SECRET_KEY` — секретный ключ Flask
- `DATABASE_URL` — строка подключения к БД (по умолчанию SQLite `app.db`)
