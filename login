{% extends 'base.html' %}
{% block title %}Вход{% endblock %}
{% block content %}
<h1>Вход</h1>
<form method="post" class="card narrow">
  <label>Email
    <input type="email" name="email" required>
  </label>
  <label>Пароль
    <input type="password" name="password" required>
  </label>
  <button class="btn primary" type="submit">Войти</button>
</form>
<p class="muted">Нет аккаунта? <a href="{{ url_for('register') }}">Зарегистрируйтесь</a></p>
{% endblock %}
