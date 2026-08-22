FROM python:3.11-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
RUN addgroup --system app && adduser --system --ingroup app app
COPY backend/requirements.txt requirements.txt
RUN python -m pip install --no-cache-dir --upgrade wheel==0.46.2 setuptools \
    && python -m pip install --no-cache-dir -r requirements.txt
COPY backend ./backend
USER app
EXPOSE 8000
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
