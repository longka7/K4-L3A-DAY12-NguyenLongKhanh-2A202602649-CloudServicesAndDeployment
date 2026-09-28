# ═══════════════════════════════════════════════════════════════════
# CP2 — Production Dockerfile (multi-stage, non-root, healthcheck, $PORT)
# Bản 1 stage ban đầu giữ ở Dockerfile.single để so sánh dung lượng.
# ═══════════════════════════════════════════════════════════════════

# ---------- Stage 1: builder — cài dependency vào một venv riêng ----------
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Chỉ copy requirements trước: sửa code không làm mất cache của layer pip install.
COPY requirements.txt .

# requirements.txt gồm cả thư viện test (pytest, httpx, ...). Runtime chỉ cần
# phần "# Runtime" nên cắt từ dòng "# Test" trở xuống trước khi cài.
RUN sed '/^# Test/,$d' requirements.txt > requirements-runtime.txt \
    && python -m venv /opt/venv \
    && /opt/venv/bin/pip install -r requirements-runtime.txt

# ---------- Stage 2: runtime — chỉ mang venv + source, không có công cụ build ----------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=8000

# User thường, không có shell đăng nhập, không có home — thoát được khỏi app
# cũng chỉ là user không đặc quyền.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app app/ ./app/
COPY --chown=app:app utils/ ./utils/

USER app

EXPOSE 8000

# Image slim không có curl → dùng Python sẵn có để gọi /health.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT', '8000') + '/health', timeout=3)" || exit 1

# sh -c để nội suy $PORT do platform cấp; exec để uvicorn là PID 1 và nhận SIGTERM trực tiếp.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
